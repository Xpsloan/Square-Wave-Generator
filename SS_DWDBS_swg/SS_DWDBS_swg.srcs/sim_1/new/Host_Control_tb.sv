`timescale 1ns / 1ps

//==================================================================
// Host_Control_tb
//
// End-to-end test of the Ethernet control plane at the pins:
//   - an 88E1111 model answers MDIO at address PHY_ADDR and records
//     what the bring-up writes (expects register 20 |= 0x0082, then
//     a soft reset);
//   - RGMII frames are driven center-aligned (as the PHY's RX delay
//     makes them) and TX is sampled 2 ns after each TXC edge (as the
//     PHY's TX delay does); FCS, IP and UDP checksums are verified;
//   - after an ARP exchange, the UDP command packets from
//     host/tb_vectors.py (built by the real host encoder) are sent
//     one by one and every reply is logged for tb_vectors.py check;
//   - a bus monitor fails the test if hold_reset ever falls except
//     right after an OKAY TRIGGER command with no write in flight.
//
// Run: python host/tb_vectors.py emit tb_vectors.txt
//      (simulate; plusargs +VEC=<file> +REP=<file>)
//      python host/tb_vectors.py check tb_vectors.txt tb_replies.txt
//==================================================================

module Host_Control_tb;

  localparam logic [47:0] FPGA_MAC  = 48'h02_00_00_00_00_00;
  localparam logic [31:0] FPGA_IP   = {8'd192, 8'd168, 8'd1, 8'd128};
  localparam logic [47:0] HOST_MAC  = 48'h02_11_22_33_44_55;
  localparam logic [31:0] HOST_IP   = {8'd192, 8'd168, 8'd1, 8'd100};
  localparam logic [15:0] HOST_PORT = 16'd50000;
  localparam logic [15:0] FPGA_PORT = 16'd1234;
  localparam logic [4:0]  PHY_ADDR  = 5'd3;
  localparam logic [31:0] RESET_SP  = 32'h8000_0000 - 32'h0666_6666 * 32'd100_014;

  typedef byte unsigned bytes_t[$];

  //----------------------------------------------------------------
  // Clocks, DUT
  //----------------------------------------------------------------

  logic clk_200 = 1'b0, clk_sync = 1'b0, phy_rx_clk = 1'b0;
  always #2.5 clk_200 = ~clk_200;
  initial begin #3.3; forever #10 clk_sync = ~clk_sync; end            // unrelated to clk_200
  initial begin #1.7; forever #4.001 phy_rx_clk = ~phy_rx_clk; end      // 125 MHz - 250 ppm

  logic        sys_reset = 1'b1, stop_btn = 1'b0;
  logic [3:0]  phy_rxd = 4'h0;
  logic        phy_rx_ctl = 1'b0;
  wire         phy_tx_clk, phy_tx_ctl, phy_reset_n, phy_mdc;
  wire  [3:0]  phy_txd;
  tri1         phy_mdio;   // board pull-up

  logic [31:0] phase_word [8];
  logic [31:0] start_phase [8];
  logic        hold_reset, status_led;
  logic [1:0]  run_state;

  Host_Control #(
    .RESET_START_PHASE     (RESET_SP),
    .PHY_RESET_HOLD_CYCLES (200),
    .PHY_RESET_WAIT_CYCLES (200),
    .MDC_DIV               (4)
  ) dut (
    .clk_200     (clk_200),
    .clk_sync    (clk_sync),
    .sys_reset   (sys_reset),
    .stop_btn    (stop_btn),
    .phy_rx_clk  (phy_rx_clk),
    .phy_rxd     (phy_rxd),
    .phy_rx_ctl  (phy_rx_ctl),
    .phy_tx_clk  (phy_tx_clk),
    .phy_txd     (phy_txd),
    .phy_tx_ctl  (phy_tx_ctl),
    .phy_reset_n (phy_reset_n),
    .phy_mdc     (phy_mdc),
    .phy_mdio    (phy_mdio),
    .phase_word  (phase_word),
    .start_phase (start_phase),
    .hold_reset  (hold_reset),
    .run_state   (run_state),
    .status_led  (status_led)
  );

  int tb_errors = 0;

  function automatic void fail(string msg);
    tb_errors++;
    $display("TB ERROR @%0t: %s", $time, msg);
  endfunction

  //----------------------------------------------------------------
  // 88E1111 MDIO model
  //----------------------------------------------------------------

  logic [15:0] phy_regs [32];
  logic        mdio_drv_en = 1'b0, mdio_drv = 1'b1;
  bit          soft_reset_seen = 0;
  int          mdio_reads = 0;

  assign phy_mdio = mdio_drv_en ? mdio_drv : 1'bz;

  initial begin
    foreach (phy_regs[i]) phy_regs[i] = 16'h0000;
    phy_regs[0]  = 16'h1140;
    phy_regs[2]  = 16'h0141;
    phy_regs[3]  = 16'h0CC2;
    phy_regs[20] = 16'h0C60;   // delay bits 7 and 1 clear
  end

  initial begin : mdio_slave
    int          ones;
    logic [11:0] h;
    logic [15:0] d;
    forever begin
      ones = 0;
      forever begin
        @(posedge phy_mdc);
        if (phy_mdio === 1'b1) ones++;
        else if (phy_mdio === 1'b0 && ones >= 32) break;
        else ones = 0;
      end
      @(posedge phy_mdc);
      if (phy_mdio !== 1'b1) continue;
      for (int i = 0; i < 12; i++) begin @(posedge phy_mdc); h = {h[10:0], phy_mdio}; end
      if (h[11:10] == 2'b10) begin            // read
        mdio_reads++;
        @(posedge phy_mdc);                   // TA0
        if (h[9:5] == PHY_ADDR) begin #1 mdio_drv_en = 1'b1; mdio_drv = 1'b0; end
        for (int i = 15; i >= 0; i--) begin
          @(posedge phy_mdc);
          if (h[9:5] == PHY_ADDR) #1 mdio_drv = phy_regs[h[4:0]][i];
        end
        @(posedge phy_mdc);
        #1 mdio_drv_en = 1'b0;
      end else if (h[11:10] == 2'b01) begin   // write
        @(posedge phy_mdc); @(posedge phy_mdc);
        for (int i = 0; i < 16; i++) begin @(posedge phy_mdc); d = {d[14:0], phy_mdio}; end
        if (h[9:5] == PHY_ADDR) begin
          $display("MDIO write @%0t: phy %0d reg %0d = %04h", $time, h[9:5], h[4:0], d);
          if (h[4:0] == 5'd0 && d[15]) begin
            soft_reset_seen = 1;
            phy_regs[0] = d & 16'h7FFF;
          end else begin
            phy_regs[h[4:0]] = d;
          end
        end
      end
    end
  end

  //----------------------------------------------------------------
  // Frame building
  //----------------------------------------------------------------

  function automatic logic [31:0] crc32(bytes_t d);
    logic [31:0] c = 32'hFFFF_FFFF;
    foreach (d[i]) begin
      c ^= {24'h0, d[i]};
      repeat (8) c = c[0] ? ((c >> 1) ^ 32'hEDB8_8320) : (c >> 1);
    end
    return ~c;
  endfunction

  function automatic logic [15:0] csum16(bytes_t d, logic [31:0] init = 0);
    logic [31:0] s = init;
    for (int i = 0; i < d.size(); i += 2) s += (32'(d[i]) << 8) + ((i + 1 < d.size()) ? 32'(d[i+1]) : 32'h0);
    while (s[31:16] != 0) s = s[15:0] + s[31:16];
    return s[15:0];
  endfunction

  function automatic void put(ref bytes_t q, input logic [63:0] v, input int n);
    for (int i = n - 1; i >= 0; i--) q.push_back(8'(v >> (8*i)));
  endfunction

  // n-byte big-endian value at q[off] (avoids {q[i], q[j]} concatenations, which crash xelab)
  function automatic logic [31:0] be(bytes_t q, int off, int n);
    logic [31:0] v;
    v = 0;
    for (int i = 0; i < n; i++) v = (v << 8) | q[off + i];
    return v;
  endfunction

  // q[off +: n] == the n-byte big-endian value v
  // (accumulated with shifts: xsim mis-evaluates v[8*k +: 8] on an argument here)
  function automatic bit qeq(bytes_t q, int off, logic [63:0] v, int n);
    logic [63:0] w;
    if (q.size() < off + n) return 0;
    w = 0;
    for (int i = 0; i < n; i++) w = (w << 8) | 64'(q[off + i]);
    return w == v;
  endfunction

  function automatic void eth_frame(ref bytes_t out, input logic [47:0] dst, input logic [15:0] etype,
                                    input bytes_t pl, input bit bad_fcs);
    bytes_t f;
    logic [31:0] crc;
    put(f, dst, 6); put(f, HOST_MAC, 6); put(f, etype, 2);
    foreach (pl[i]) f.push_back(pl[i]);
    while (f.size() < 60) f.push_back(8'h00);
    crc = crc32(f) ^ (bad_fcs ? 32'h0000_0001 : 32'h0);
    out.delete();
    repeat (7) out.push_back(8'h55);
    out.push_back(8'hD5);
    foreach (f[i]) out.push_back(f[i]);
    for (int i = 0; i < 4; i++) out.push_back(8'(crc >> (8*i)));
  endfunction

  function automatic void udp_ip(ref bytes_t ip, input logic [15:0] dport, input bytes_t pl);
    logic [15:0] c;
    ip.delete();
    put(ip, 16'h4500, 2); put(ip, 20 + 8 + pl.size(), 2); put(ip, 16'h1234, 2);
    put(ip, 16'h4000, 2); put(ip, 8'd64, 1); put(ip, 8'd17, 1); put(ip, 16'h0000, 2);
    put(ip, HOST_IP, 4); put(ip, FPGA_IP, 4);
    c = ~csum16(ip[0:19]);
    ip[10] = c[15:8]; ip[11] = c[7:0];
    put(ip, HOST_PORT, 2); put(ip, dport, 2); put(ip, 8 + pl.size(), 2); put(ip, 16'h0000, 2);
    foreach (pl[i]) ip.push_back(pl[i]);
  endfunction

  //----------------------------------------------------------------
  // RGMII RX (TB -> DUT): data changes 2 ns after each RXC edge
  //----------------------------------------------------------------

  task automatic rgmii_send(bytes_t fr);
    @(negedge phy_rx_clk);
    foreach (fr[i]) begin
      #2 phy_rxd = fr[i][3:0]; phy_rx_ctl = 1'b1;
      @(posedge phy_rx_clk);
      #2 phy_rxd = fr[i][7:4]; phy_rx_ctl = 1'b1;
      @(negedge phy_rx_clk);
    end
    #2 phy_rxd = 4'h0; phy_rx_ctl = 1'b0;
    repeat (12) @(posedge phy_rx_clk);
  endtask

  //----------------------------------------------------------------
  // RGMII TX (DUT -> TB): sampled 2 ns after each TXC edge
  //----------------------------------------------------------------

  byte unsigned tx_fifo [$];   // captured frames, back to back
  int           tx_lens [$];   // their lengths

  initial begin : tx_monitor
    bytes_t      cur, f, body;
    logic [31:0] fcs;
    logic [3:0]  lo;
    logic        en;
    forever begin
      @(posedge phy_tx_clk); #2 lo = phy_txd; en = phy_tx_ctl;
      @(negedge phy_tx_clk); #2;
      if (en === 1'b1) begin
        cur.push_back({phy_txd, lo});
      end else if (cur.size() > 0) begin
        if (cur.size() < 8 + 64 || !qeq(cur, 0, 64'h55_5555_5555_5555, 7) || cur[7] != 8'hD5) begin
          fail($sformatf("TX frame with bad preamble/length (%0d bytes): %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
                         cur.size(), cur[0], cur[1], cur[2], cur[3], cur[4], cur[5], cur[6], cur[7], cur[8], cur[9]));
        end else begin
          f    = cur[8:$];
          body = f[0:f.size()-5];
          fcs  = 32'(f[f.size()-1]) << 24 | 32'(f[f.size()-2]) << 16 | 32'(f[f.size()-3]) << 8 | 32'(f[f.size()-4]);
          if (crc32(body) != fcs) fail("TX frame FCS mismatch");
          else begin
            foreach (body[i]) tx_fifo.push_back(body[i]);
            tx_lens.push_back(body.size());
          end
        end
        cur.delete();
      end
    end
  end

  // Wait for the next frame of the given ethertype; answers the DUT's ARP requests on the way
  task automatic wait_frame(input logic [15:0] etype, input time timeout, output bit got, output bytes_t f);
    bytes_t fr, g, a;
    time    t0;
    int     n;
    t0  = $time;
    got = 0;
    while (!got && $time - t0 < timeout) begin
      if (tx_lens.size() > 0) begin
        n = tx_lens.pop_front();
        g.delete();
        for (int i = 0; i < n; i++) g.push_back(tx_fifo.pop_front());
        if (be(g, 12, 2) == etype) begin
          got = 1;
        end else if (be(g, 12, 2) == 16'h0806 && be(g, 20, 2) == 16'h0001) begin
          a.delete();
          put(a, 64'h0001_0800_0604_0002, 8); put(a, HOST_MAC, 6); put(a, HOST_IP, 4);
          put(a, FPGA_MAC, 6); put(a, FPGA_IP, 4);
          eth_frame(fr, FPGA_MAC, 16'h0806, a, 0);
          rgmii_send(fr);
        end else begin
          fail($sformatf("unexpected TX frame, ethertype %02h%02h", g[12], g[13]));
        end
      end
      if (!got) #100;
    end
    f = g;
  endtask

  task automatic wait_udp(input time timeout, output bit got, output bytes_t pl);
    bytes_t f;
    wait_frame(16'h0800, timeout, got, f);
    if (!got) return;
    if (!qeq(f, 0, HOST_MAC, 6) || !qeq(f, 6, FPGA_MAC, 6)) fail("reply MAC addresses wrong");
    if (f[23] != 8'd17) fail("reply is not UDP");
    if (csum16(f[14:33]) != 16'hFFFF) fail("reply IP header checksum bad");
    if (be(f, 26, 4) != FPGA_IP || be(f, 30, 4) != HOST_IP) fail("reply IP addresses wrong");
    if (be(f, 34, 2) != FPGA_PORT || be(f, 36, 2) != HOST_PORT) fail("reply UDP ports wrong");
    begin
      int ulen = be(f, 38, 2);
      bytes_t u = f[34:34 + ulen - 1];
      if (be(f, 40, 2) != 16'h0000 &&
          csum16(u, {16'h0, FPGA_IP[31:16]} + FPGA_IP[15:0] + HOST_IP[31:16] + HOST_IP[15:0] + 32'd17 + ulen) != 16'hFFFF)
        fail("reply UDP checksum bad");
      pl = f[42:34 + ulen - 1];
    end
  endtask

  //----------------------------------------------------------------
  // Bus monitor: hold_reset may only fall during the TRIGGER command
  // write itself (0x0008 <= 2) - i.e. never while a channel value is
  // being written - and that write must then complete OKAY
  //----------------------------------------------------------------

  logic [31:0] mon_aw, mon_w;
  bit          prev_hold = 1, expect_trigger_ok = 0;

  always @(posedge clk_sync) begin
    if (dut.m_awvalid && dut.m_awready) mon_aw <= dut.m_awaddr;
    if (dut.m_wvalid  && dut.m_wready)  mon_w  <= dut.m_wdata;
    if (dut.m_bvalid  && dut.m_bready && expect_trigger_ok) begin
      if (dut.m_bresp != 2'b00) fail("TRIGGER write that released hold_reset did not return OKAY");
      expect_trigger_ok <= 0;
    end
    if (prev_hold === 1'b1 && hold_reset === 1'b0) begin
      if (!(mon_aw == 32'h8 && mon_w == 32'd2))
        fail($sformatf("hold_reset released during write %h <= %h, not TRIGGER", mon_aw, mon_w));
      if (run_state != 2'd3) fail("hold_reset released outside OUTPUT");
      expect_trigger_ok <= 1;
    end
    prev_hold <= hold_reset;
  end

  //----------------------------------------------------------------
  // Test sequence
  //----------------------------------------------------------------

  initial begin
    string vec_path, rep_path, line, name, flag, hex;
    int    vf, rf, port, n_sent;
    bit    got;
    bytes_t f, pl, req, fr, ipk;

    if (!$value$plusargs("VEC=%s", vec_path)) vec_path = "tb_vectors.txt";
    if (!$value$plusargs("REP=%s", rep_path)) rep_path = "tb_replies.txt";
    vf = $fopen(vec_path, "r");
    rf = $fopen(rep_path, "w");
    if (vf == 0) begin $display("cannot open %s", vec_path); $finish; end

    #200 sys_reset = 1'b0;

    // PHY bring-up
    fork
      wait (soft_reset_seen);
      #2ms;
    join_any
    disable fork;
    if (!soft_reset_seen) fail("PHY bring-up never soft-reset the PHY");
    if (phy_regs[20] !== 16'h0CE2) fail($sformatf("PHY reg 20 = %04h, expected 0CE2", phy_regs[20]));
    if (dut.eth_link.phy_init.phy_addr !== PHY_ADDR) fail("PHY found at the wrong address");
    if (mdio_reads != PHY_ADDR + 1 + 2) fail($sformatf("%0d MDIO reads, expected %0d", mdio_reads, PHY_ADDR + 3));
    #2us;
    if (status_led !== 1'b1) fail("status LED not on after bring-up");

    // ARP: who has FPGA_IP?
    begin
      bytes_t a;
      put(a, 64'h0001_0800_0604_0001, 8); put(a, HOST_MAC, 6); put(a, HOST_IP, 4);
      put(a, 48'h0, 6); put(a, FPGA_IP, 4);
      eth_frame(fr, 48'hFFFF_FFFF_FFFF, 16'h0806, a, 0);
      rgmii_send(fr);
      wait_frame(16'h0806, 50us, got, f);
      if (!got) fail("no ARP reply");
      else if (!qeq(f, 20, 16'h0002, 2) || !qeq(f, 22, FPGA_MAC, 6) || !qeq(f, 28, FPGA_IP, 4) ||
               !qeq(f, 32, HOST_MAC, 6) || !qeq(f, 38, HOST_IP, 4) || !qeq(f, 0, HOST_MAC, 6))
        fail("bad ARP reply");
    end

    // Command packets
    n_sent = 0;
    while ($fgets(line, vf)) begin
      if (line.len() < 2) continue;
      if (line.substr(0, 6) == "!button") begin
        stop_btn = 1'b1; #1us; stop_btn = 1'b0; #1us;
        continue;
      end
      void'($sscanf(line, "%s %d %s %s", name, port, flag, hex));
      req.delete();
      for (int i = 0; i + 1 < hex.len(); i += 2) req.push_back(8'(hex.substr(i, i + 1).atohex()));
      udp_ip(ipk, 16'(port), req);
      eth_frame(fr, FPGA_MAC, 16'h0800, ipk, flag == "badfcs");
      rgmii_send(fr);
      n_sent++;
      wait_udp((flag == "ok") ? 500us : 100us, got, pl);
      if (got) begin
        $fwrite(rf, "%s ", name);
        foreach (pl[i]) $fwrite(rf, "%02x", pl[i]);
        $fwrite(rf, "\n");
      end else begin
        $fwrite(rf, "%s NONE\n", name);
      end
    end

    $fwrite(rf, "outputs");
    for (int i = 0; i < 8; i++) $fwrite(rf, " %08x %08x", phase_word[i], start_phase[i]);
    $fwrite(rf, "\n");
    $fwrite(rf, "tbcheck %s %0d\n", (tb_errors == 0) ? "PASS" : "FAIL", tb_errors);
    $fclose(rf);
    $display("Host_Control_tb done: %0d packets sent, %0d testbench errors", n_sent, tb_errors);
    $finish;
  end

endmodule

`timescale 1ns / 1ps

//==================================================================
// Channel_Regs_tb
//
// Self-checking AXI4-Lite test for Channel_Regs: reset values, AW/W
// in every order, byte strobes, RAZ/WI and address aliasing, writes
// pipelined under B backpressure, read during write, and a random
// mix checked against a reference model. A protocol monitor checks
// VALID/data stability, OKAY responses and VALIDs low in reset.
// Prints "Channel_Regs_tb PASSED" or the error count.
//==================================================================

module Channel_Regs_tb #(
  parameter int ADDR_W = 4
);

  localparam logic [31:0] RST_PW = 32'h0666_6666;
  localparam logic [31:0] RST_SP = 32'h8000_9C40;

  logic clk = 1'b0;
  always #10 clk = ~clk;  // 50 MHz clk_sync

  logic              aresetn;
  logic [ADDR_W-1:0] awaddr = '0, araddr = '0;
  logic              awvalid = 1'b0, wvalid = 1'b0, bready = 1'b0, arvalid = 1'b0, rready = 1'b0;
  logic [31:0]       wdata = '0;
  logic [3:0]        wstrb = '0;
  logic              awready, wready, bvalid, arready, rvalid;
  logic [1:0]        bresp, rresp;
  logic [31:0]       rdata, phase_word, start_phase;

  Channel_Regs #(
    .AXI_ADDR_WIDTH    (ADDR_W),
    .RESET_PHASE_WORD  (RST_PW),
    .RESET_START_PHASE (RST_SP)
  ) dut (
    .s_axi_aclk    (clk),       .s_axi_aresetn (aresetn),
    .s_axi_awaddr  (awaddr),    .s_axi_awprot  (3'b000),  .s_axi_awvalid (awvalid), .s_axi_awready (awready),
    .s_axi_wdata   (wdata),     .s_axi_wstrb   (wstrb),   .s_axi_wvalid  (wvalid),  .s_axi_wready  (wready),
    .s_axi_bresp   (bresp),     .s_axi_bvalid  (bvalid),  .s_axi_bready  (bready),
    .s_axi_araddr  (araddr),    .s_axi_arprot  (3'b000),  .s_axi_arvalid (arvalid), .s_axi_arready (arready),
    .s_axi_rdata   (rdata),     .s_axi_rresp   (rresp),   .s_axi_rvalid  (rvalid),  .s_axi_rready  (rready),
    .phase_word    (phase_word), .start_phase  (start_phase)
  );

  int errors = 0;
  int writes = 0, reads = 0;

  function automatic void fail(string msg);
    errors++;
    $display("ERROR @%0t: %s", $time, msg);
  endfunction

  //----------------------------------------------------------------
  // Reference model
  //----------------------------------------------------------------

  logic [31:0] m_pw, m_sp;

  function automatic void model_write(logic [ADDR_W-1:0] a, logic [31:0] d, logic [3:0] s);
    for (int i = 0; i < 4; i++) begin
      if (s[i] && a[ADDR_W-1:2] == 0) m_pw[8*i +: 8] = d[8*i +: 8];
      if (s[i] && a[ADDR_W-1:2] == 1) m_sp[8*i +: 8] = d[8*i +: 8];
    end
  endfunction

  function automatic logic [31:0] model_read(logic [ADDR_W-1:0] a);
    return (a[ADDR_W-1:2] == 0) ? m_pw : (a[ADDR_W-1:2] == 1) ? m_sp : 32'h0;
  endfunction

  function automatic void check_ports(string where);
    if (phase_word !== m_pw)  fail($sformatf("%s: phase_word=%h expected %h", where, phase_word, m_pw));
    if (start_phase !== m_sp) fail($sformatf("%s: start_phase=%h expected %h", where, start_phase, m_sp));
  endfunction

  //----------------------------------------------------------------
  // Protocol monitor (samples pre-edge values)
  //----------------------------------------------------------------

  logic        p_bvalid = 0, p_bready = 0, p_rvalid = 0, p_rready = 0, p_rst = 1;
  logic [31:0] p_rdata;

  always @(posedge clk) begin
    if (p_rst && (bvalid || rvalid)) fail("BVALID/RVALID high during reset");
    if (!p_rst) begin
      if (p_bvalid && !p_bready && !bvalid)  fail("BVALID dropped before BREADY");
      if (p_rvalid && !p_rready && !rvalid)  fail("RVALID dropped before RREADY");
      if (p_rvalid && !p_rready && rdata !== p_rdata) fail("RDATA changed while stalled");
      if (bvalid && bresp !== 2'b00) fail("BRESP not OKAY");
      if (rvalid && rresp !== 2'b00) fail("RRESP not OKAY");
    end
    p_bvalid <= bvalid; p_bready <= bready;
    p_rvalid <= rvalid; p_rready <= rready; p_rdata <= rdata;
    p_rst    <= !aresetn;
  end

  //----------------------------------------------------------------
  // Master BFM: drive on negedge, sample on posedge
  //----------------------------------------------------------------

  task automatic send_aw(logic [ADDR_W-1:0] a, int dly);
    repeat (dly) @(negedge clk);
    awaddr = a; awvalid = 1'b1;
    do @(posedge clk); while (!awready);
    @(negedge clk); awvalid = 1'b0; awaddr = 'x;
  endtask

  task automatic send_w(logic [31:0] d, logic [3:0] s, int dly);
    repeat (dly) @(negedge clk);
    wdata = d; wstrb = s; wvalid = 1'b1;
    do @(posedge clk); while (!wready);
    @(negedge clk); wvalid = 1'b0; wdata = 'x; wstrb = 'x;
  endtask

  task automatic get_b(int dly);
    repeat (dly) @(negedge clk);
    bready = 1'b1;
    do @(posedge clk); while (!bvalid);
    @(negedge clk); bready = 1'b0;
  endtask

  task automatic axi_write(logic [ADDR_W-1:0] a, logic [31:0] d, logic [3:0] s,
                           int aw_dly = 0, int w_dly = 0, int b_dly = 0);
    fork
      send_aw(a, aw_dly);
      send_w(d, s, w_dly);
      get_b(b_dly);
    join
    model_write(a, d, s);
    writes++;
    check_ports($sformatf("after write %h", a));
  endtask

  task automatic axi_read(logic [ADDR_W-1:0] a, output logic [31:0] d, input int ar_dly = 0, int r_dly = 0);
    fork
      begin
        repeat (ar_dly) @(negedge clk);
        araddr = a; arvalid = 1'b1;
        do @(posedge clk); while (!arready);
        @(negedge clk); arvalid = 1'b0; araddr = 'x;
      end
      begin
        repeat (r_dly) @(negedge clk);
        rready = 1'b1;
        do @(posedge clk); while (!rvalid);
        d = rdata;
        @(negedge clk); rready = 1'b0;
      end
    join
    reads++;
  endtask

  task automatic read_check(logic [ADDR_W-1:0] a, int ar_dly = 0, int r_dly = 0);
    logic [31:0] d;
    axi_read(a, d, ar_dly, r_dly);
    if (d !== model_read(a)) fail($sformatf("read %h = %h, expected %h", a, d, model_read(a)));
  endtask

  //----------------------------------------------------------------
  // Tests
  //----------------------------------------------------------------

  logic [ADDR_W-1:0] addr_pool [$];

  initial begin
    logic [31:0] d;

    addr_pool = '{'h0, 'h4, 'h8, 'hC};
    if (ADDR_W > 4) addr_pool.push_back('h10);
    if (ADDR_W > 8) addr_pool.push_back('h104);  // aliases 0x4 if upper bits were ignored

    aresetn = 1'b0;
    m_pw = RST_PW; m_sp = RST_SP;
    repeat (5) @(negedge clk);
    aresetn = 1'b1;
    @(negedge clk);

    // 1. Reset values
    check_ports("reset");
    read_check('h0);
    read_check('h4);

    // 2. AW/W in every order, with and without B backpressure
    axi_write('h0, 32'h1234_5678, 4'hF, 0, 0, 0);   // together
    axi_write('h4, 32'h9ABC_DEF0, 4'hF, 0, 3, 0);   // AW first
    axi_write('h0, 32'h0BAD_F00D, 4'hF, 3, 0, 0);   // W first
    axi_write('h4, 32'hCAFE_BABE, 4'hF, 1, 1, 4);   // B stalled
    read_check('h0);
    read_check('h4, 0, 5);                          // R stalled

    // 3. Byte strobes
    axi_write('h0, 32'hAAAA_AAAA, 4'b0101);
    axi_write('h4, 32'h5555_5555, 4'b1000);
    axi_write('h4, 32'hFFFF_FFFF, 4'b0000);
    read_check('h0);
    read_check('h4);

    // 4. RAZ/WI and aliasing
    foreach (addr_pool[i]) begin
      if (addr_pool[i][ADDR_W-1:2] > 1) begin
        axi_write(addr_pool[i], 32'hDEAD_BEEF, 4'hF);
        read_check(addr_pool[i]);
      end
    end
    read_check('h0);
    read_check('h4);

    // 5. Writes pipelined behind a stalled B channel
    fork
      begin
        send_aw('h0, 0); send_aw('h4, 0); send_aw('h0, 0); send_aw('h4, 0);
      end
      begin
        send_w(32'h1111_1111, 4'hF, 0); send_w(32'h2222_2222, 4'hF, 0);
        send_w(32'h3333_3333, 4'hF, 0); send_w(32'h4444_4444, 4'hF, 0);
      end
      begin
        repeat (8) @(negedge clk);
        repeat (4) get_b(0);
      end
    join
    model_write('h0, 32'h1111_1111, 4'hF); model_write('h4, 32'h2222_2222, 4'hF);
    model_write('h0, 32'h3333_3333, 4'hF); model_write('h4, 32'h4444_4444, 4'hF);
    writes += 4;
    check_ports("pipelined writes");
    read_check('h0);
    read_check('h4);

    // 6. Read while a write is in flight (read returns old or new value)
    fork
      axi_write('h0, 32'h7777_0000, 4'hF, 1, 2, 0);
      begin
        axi_read('h0, d, 0, 0);
        if (d !== 32'h3333_3333 && d !== 32'h7777_0000) fail($sformatf("read during write got %h", d));
      end
    join

    // 7. Random mix
    for (int n = 0; n < 2000; n++) begin
      automatic logic [ADDR_W-1:0] a = addr_pool[$urandom_range(0, addr_pool.size() - 1)];
      if ($urandom_range(0, 1)) begin
        axi_write(a, $urandom, 4'($urandom), $urandom_range(0, 3), $urandom_range(0, 3), $urandom_range(0, 3));
      end else begin
        read_check(a, $urandom_range(0, 3), $urandom_range(0, 3));
      end
    end

    // 8. Reset restores the defaults
    @(negedge clk); aresetn = 1'b0;
    repeat (2) @(negedge clk); aresetn = 1'b1;
    m_pw = RST_PW; m_sp = RST_SP;
    @(negedge clk);
    check_ports("second reset");
    read_check('h0);
    read_check('h4);

    if (errors == 0) $display("Channel_Regs_tb PASSED (ADDR_W=%0d): %0d writes, %0d reads", ADDR_W, writes, reads);
    else             $display("Channel_Regs_tb FAILED (ADDR_W=%0d): %0d errors", ADDR_W, errors);
    $finish;
  end

  initial begin
    #5ms;
    $display("Channel_Regs_tb FAILED: timeout (handshake hung)");
    $finish;
  end

endmodule

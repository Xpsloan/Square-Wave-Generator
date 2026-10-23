`timescale 1ns / 1ps

//==================================================================
// Host_Control
//
// Everything between the Ethernet jack and the square-wave
// channels: Eth_Host_Link turns UDP command packets into AXI4-Lite
// transactions on a bus clocked by clk_sync, which Axil_Decoder
// splits into 4 KB windows:
//
//   0x0000   Run_Control   run state machine, COMMIT/TRIGGER/STOP
//   0x1000   Channel_Regs  channel 0A (0x00 PHASE_WORD, 0x04 START_PHASE)
//   0x2000   Channel_Regs  channel 0B
//   ...
//   0x8000   Channel_Regs  channel 3B
//
// hold_reset (from Run_Control) holds every wave and marker in
// reset except while the run state is OUTPUT; it is the only way
// the waves get released.
//==================================================================

module Host_Control #(
  parameter int          N_CH              = 8,
  parameter logic [31:0] RESET_PHASE_WORD  = 32'h0666_6666,
  parameter logic [31:0] RESET_START_PHASE = 32'h8000_0000 - RESET_PHASE_WORD * 32'd100_000,
  parameter logic [47:0] LOCAL_MAC         = 48'h02_00_00_00_00_00,
  parameter logic [31:0] LOCAL_IP          = {8'd192, 8'd168, 8'd1, 8'd128},
  parameter logic [31:0] GATEWAY_IP        = {8'd192, 8'd168, 8'd1, 8'd1},
  parameter logic [31:0] SUBNET_MASK       = {8'd255, 8'd255, 8'd255, 8'd0},
  parameter logic [15:0] UDP_PORT          = 16'd1234,
  parameter int unsigned PHY_RESET_HOLD_CYCLES = 1_250_000,
  parameter int unsigned PHY_RESET_WAIT_CYCLES = 625_000,
  parameter int unsigned MDC_DIV               = 25
)(
  input  logic        clk_200,      // 200 MHz reference (BUFG)
  input  logic        clk_sync,     // 50 MHz; AXI4-Lite bus clock
  input  logic        sys_reset,    // async, active-high (system_reset | ~locked)
  input  logic        stop_btn,     // async, active-high: STOP while running

  // RGMII PHY (SP701 ethernet_1, Marvell 88E1111)
  input  logic        phy_rx_clk,
  input  logic [3:0]  phy_rxd,
  input  logic        phy_rx_ctl,
  output logic        phy_tx_clk,
  output logic [3:0]  phy_txd,
  output logic        phy_tx_ctl,
  output logic        phy_reset_n,
  output logic        phy_mdc,
  inout  wire         phy_mdio,

  // Channel configuration (clk_sync domain; only used by the DDS
  // while it is held in reset)
  output logic [31:0] phase_word  [N_CH],
  output logic [31:0] start_phase [N_CH],

  output logic        hold_reset,   // clk_sync domain, registered
  output logic [1:0]  run_state,
  output logic        status_led    // on = PHY configured, blinks off per packet
);

  localparam int N_SLAVES = N_CH + 1;

  //----------------------------------------------------------------
  // AXI reset: asserts with sys_reset, releases on clk_sync
  //----------------------------------------------------------------

  (* ASYNC_REG = "TRUE" *) logic [1:0] axi_rst_sync;
  logic axi_aresetn;

  always_ff @(posedge clk_sync or posedge sys_reset) begin
    if (sys_reset) axi_rst_sync <= 2'b00;
    else           axi_rst_sync <= {axi_rst_sync[0], 1'b1};
  end

  assign axi_aresetn = axi_rst_sync[1];

  //----------------------------------------------------------------
  // Ethernet link -> AXI4-Lite master
  //----------------------------------------------------------------

  logic [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
  logic [2:0]  m_awprot, m_arprot;
  logic [3:0]  m_wstrb;
  logic [1:0]  m_bresp, m_rresp;
  logic        m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
  logic        m_arvalid, m_arready, m_rvalid, m_rready;
  logic        mdio_o, mdio_oe;

  assign phy_mdio = mdio_oe ? mdio_o : 1'bz;

  Eth_Host_Link #(
    .LOCAL_MAC             (LOCAL_MAC),
    .LOCAL_IP              (LOCAL_IP),
    .GATEWAY_IP            (GATEWAY_IP),
    .SUBNET_MASK           (SUBNET_MASK),
    .UDP_PORT              (UDP_PORT),
    .STATUS_ADDR           (32'h0000_0004),
    .PHY_RESET_HOLD_CYCLES (PHY_RESET_HOLD_CYCLES),
    .PHY_RESET_WAIT_CYCLES (PHY_RESET_WAIT_CYCLES),
    .MDC_DIV               (MDC_DIV)
  ) eth_link (
    .clk_200       (clk_200),
    .sys_reset     (sys_reset),
    .phy_rx_clk    (phy_rx_clk),
    .phy_rxd       (phy_rxd),
    .phy_rx_ctl    (phy_rx_ctl),
    .phy_tx_clk    (phy_tx_clk),
    .phy_txd       (phy_txd),
    .phy_tx_ctl    (phy_tx_ctl),
    .phy_reset_n   (phy_reset_n),
    .phy_mdc       (phy_mdc),
    .phy_mdio_o    (mdio_o),
    .phy_mdio_oe   (mdio_oe),
    .phy_mdio_i    (phy_mdio),
    .m_axi_aclk    (clk_sync),
    .m_axi_aresetn (axi_aresetn),
    .m_axi_awaddr  (m_awaddr),
    .m_axi_awprot  (m_awprot),
    .m_axi_awvalid (m_awvalid),
    .m_axi_awready (m_awready),
    .m_axi_wdata   (m_wdata),
    .m_axi_wstrb   (m_wstrb),
    .m_axi_wvalid  (m_wvalid),
    .m_axi_wready  (m_wready),
    .m_axi_bresp   (m_bresp),
    .m_axi_bvalid  (m_bvalid),
    .m_axi_bready  (m_bready),
    .m_axi_araddr  (m_araddr),
    .m_axi_arprot  (m_arprot),
    .m_axi_arvalid (m_arvalid),
    .m_axi_arready (m_arready),
    .m_axi_rdata   (m_rdata),
    .m_axi_rresp   (m_rresp),
    .m_axi_rvalid  (m_rvalid),
    .m_axi_rready  (m_rready),
    .status_led    (status_led)
  );

  //----------------------------------------------------------------
  // Address decoder
  //----------------------------------------------------------------

  logic [11:0]         s_awaddr, s_araddr;
  logic [31:0]         s_wdata;
  logic [3:0]          s_wstrb;
  logic [N_SLAVES-1:0] s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
  logic [N_SLAVES-1:0] s_arvalid, s_arready, s_rvalid, s_rready, wr_ok;
  logic [1:0]          s_bresp [N_SLAVES];
  logic [1:0]          s_rresp [N_SLAVES];
  logic [31:0]         s_rdata [N_SLAVES];

  Axil_Decoder #(
    .N_SLAVES (N_SLAVES)
  ) decoder (
    .aclk      (clk_sync),
    .aresetn   (axi_aresetn),
    .s_awaddr  (m_awaddr),
    .s_awvalid (m_awvalid),
    .s_awready (m_awready),
    .s_wdata   (m_wdata),
    .s_wstrb   (m_wstrb),
    .s_wvalid  (m_wvalid),
    .s_wready  (m_wready),
    .s_bresp   (m_bresp),
    .s_bvalid  (m_bvalid),
    .s_bready  (m_bready),
    .s_araddr  (m_araddr),
    .s_arvalid (m_arvalid),
    .s_arready (m_arready),
    .s_rdata   (m_rdata),
    .s_rresp   (m_rresp),
    .s_rvalid  (m_rvalid),
    .s_rready  (m_rready),
    .m_awaddr  (s_awaddr),
    .m_awvalid (s_awvalid),
    .m_awready (s_awready),
    .m_wdata   (s_wdata),
    .m_wstrb   (s_wstrb),
    .m_wvalid  (s_wvalid),
    .m_wready  (s_wready),
    .m_bresp   (s_bresp),
    .m_bvalid  (s_bvalid),
    .m_bready  (s_bready),
    .m_araddr  (s_araddr),
    .m_arvalid (s_arvalid),
    .m_arready (s_arready),
    .m_rdata   (s_rdata),
    .m_rresp   (s_rresp),
    .m_rvalid  (s_rvalid),
    .m_rready  (s_rready),
    .wr_ok     (wr_ok)
  );

  //----------------------------------------------------------------
  // 0x0000: run control
  //----------------------------------------------------------------

  Run_Control run_ctrl (
    .s_axi_aclk    (clk_sync),
    .s_axi_aresetn (axi_aresetn),
    .s_axi_awaddr  (s_awaddr),
    .s_axi_awvalid (s_awvalid[0]),
    .s_axi_awready (s_awready[0]),
    .s_axi_wdata   (s_wdata),
    .s_axi_wstrb   (s_wstrb),
    .s_axi_wvalid  (s_wvalid[0]),
    .s_axi_wready  (s_wready[0]),
    .s_axi_bresp   (s_bresp[0]),
    .s_axi_bvalid  (s_bvalid[0]),
    .s_axi_bready  (s_bready[0]),
    .s_axi_araddr  (s_araddr),
    .s_axi_arvalid (s_arvalid[0]),
    .s_axi_arready (s_arready[0]),
    .s_axi_rdata   (s_rdata[0]),
    .s_axi_rresp   (s_rresp[0]),
    .s_axi_rvalid  (s_rvalid[0]),
    .s_axi_rready  (s_rready[0]),
    .cfg_wr        (|wr_ok[N_SLAVES-1:1]),
    .stop_btn      (stop_btn),
    .state         (run_state),
    .hold_reset    (hold_reset)
  );

  //----------------------------------------------------------------
  // 0x1000 + 0x1000*i: channel i (0A, 0B, 1A, 1B, 2A, 2B, 3A, 3B)
  //----------------------------------------------------------------

  for (genvar i = 0; i < N_CH; i++) begin : g_ch
    Channel_Regs #(
      .AXI_ADDR_WIDTH    (12),
      .RESET_PHASE_WORD  (RESET_PHASE_WORD),
      .RESET_START_PHASE (RESET_START_PHASE)
    ) regs (
      .s_axi_aclk    (clk_sync),
      .s_axi_aresetn (axi_aresetn),
      .s_axi_awaddr  (s_awaddr),
      .s_axi_awprot  (3'b000),
      .s_axi_awvalid (s_awvalid[i+1]),
      .s_axi_awready (s_awready[i+1]),
      .s_axi_wdata   (s_wdata),
      .s_axi_wstrb   (s_wstrb),
      .s_axi_wvalid  (s_wvalid[i+1]),
      .s_axi_wready  (s_wready[i+1]),
      .s_axi_bresp   (s_bresp[i+1]),
      .s_axi_bvalid  (s_bvalid[i+1]),
      .s_axi_bready  (s_bready[i+1]),
      .s_axi_araddr  (s_araddr),
      .s_axi_arprot  (3'b000),
      .s_axi_arvalid (s_arvalid[i+1]),
      .s_axi_arready (s_arready[i+1]),
      .s_axi_rdata   (s_rdata[i+1]),
      .s_axi_rresp   (s_rresp[i+1]),
      .s_axi_rvalid  (s_rvalid[i+1]),
      .s_axi_rready  (s_rready[i+1]),
      .phase_word    (phase_word[i]),
      .start_phase   (start_phase[i])
    );
  end

endmodule

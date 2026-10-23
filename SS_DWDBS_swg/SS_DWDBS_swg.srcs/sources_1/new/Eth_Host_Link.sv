`timescale 1ns / 1ps

//==================================================================
// Eth_Host_Link
//
// Host-to-FPGA link over 1000BASE-T: UDP command packets in, an
// AXI4-Lite master (in the m_axi_aclk / clk_sync domain) out.
//
//   clk_200 -> PLL -> clk_125 (one BUFG) runs the MAC TX, the
//   UDP/IP/ARP stack (verilog-ethernet, MIT license) and the
//   command engine. The RGMII RX clock stays on BUFIO/BUFR.
//   Mdio_Phy_Init resets the 88E1111 and turns on its RGMII clock
//   delays, which is why no 90-degree TX clock is needed; small RX
//   IDELAYs centre the data in the IDDR window. Udp_Cmd_Engine
//   executes each packet's ops through Axil_Master_Cdc and replies.
//==================================================================

module Eth_Host_Link #(
  parameter logic [47:0] LOCAL_MAC   = 48'h02_00_00_00_00_00,
  parameter logic [31:0] LOCAL_IP    = {8'd192, 8'd168, 8'd1, 8'd128},
  parameter logic [31:0] GATEWAY_IP  = {8'd192, 8'd168, 8'd1, 8'd1},
  parameter logic [31:0] SUBNET_MASK = {8'd255, 8'd255, 8'd255, 8'd0},
  parameter logic [15:0] UDP_PORT    = 16'd1234,
  parameter logic [31:0] STATUS_ADDR = 32'h0000_0004,
  parameter int unsigned PHY_RESET_HOLD_CYCLES = 1_250_000,  // 10 ms at 125 MHz
  parameter int unsigned PHY_RESET_WAIT_CYCLES = 625_000,    // 5 ms
  parameter int unsigned MDC_DIV               = 25,         // 2.5 MHz MDC
  parameter int unsigned RX_IDELAY_TAPS        = 10          // RGMII RX data delay (~78 ps/tap); 10 centres
                                                             // RXD in the IDDR window behind the BUFIO clock
                                                             // (about +/-0.4 ns setup/hold in timing)
)(
  input  logic        clk_200,     // 200 MHz reference (BUFG)
  input  logic        sys_reset,   // async, active-high

  // RGMII PHY
  input  logic        phy_rx_clk,
  input  logic [3:0]  phy_rxd,
  input  logic        phy_rx_ctl,
  output logic        phy_tx_clk,
  output logic [3:0]  phy_txd,
  output logic        phy_tx_ctl,
  output logic        phy_reset_n,
  output logic        phy_mdc,
  output logic        phy_mdio_o,
  output logic        phy_mdio_oe,
  input  logic        phy_mdio_i,

  // AXI4-Lite master
  input  logic        m_axi_aclk,
  input  logic        m_axi_aresetn,
  output logic [31:0] m_axi_awaddr,
  output logic [2:0]  m_axi_awprot,
  output logic        m_axi_awvalid,
  input  logic        m_axi_awready,
  output logic [31:0] m_axi_wdata,
  output logic [3:0]  m_axi_wstrb,
  output logic        m_axi_wvalid,
  input  logic        m_axi_wready,
  input  logic [1:0]  m_axi_bresp,
  input  logic        m_axi_bvalid,
  output logic        m_axi_bready,
  output logic [31:0] m_axi_araddr,
  output logic [2:0]  m_axi_arprot,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [31:0] m_axi_rdata,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready,

  // On once the PHY is configured, off for ~67 ms after each reply
  output logic        status_led
);

  //----------------------------------------------------------------
  // 125 MHz clock: PLL with internal feedback (no feedback BUFG)
  //----------------------------------------------------------------

  logic clk_125_pll, clk_125, pll_fb, pll_locked, rst_125;

  PLLE2_ADV #(
    .BANDWIDTH          ("OPTIMIZED"),
    .COMPENSATION       ("INTERNAL"),
    .CLKIN1_PERIOD      (5.000),
    .DIVCLK_DIVIDE      (1),
    .CLKFBOUT_MULT      (5),       // VCO 1000 MHz
    .CLKOUT0_DIVIDE     (8),       // 125 MHz
    .CLKOUT0_PHASE      (0.000),
    .CLKOUT0_DUTY_CYCLE (0.500)
  ) eth_pll (
    .CLKIN1   (clk_200),
    .CLKIN2   (1'b0),
    .CLKINSEL (1'b1),
    .CLKFBIN  (pll_fb),
    .CLKFBOUT (pll_fb),
    .CLKOUT0  (clk_125_pll),
    .CLKOUT1  (),
    .CLKOUT2  (),
    .CLKOUT3  (),
    .CLKOUT4  (),
    .CLKOUT5  (),
    .RST      (sys_reset),
    .PWRDWN   (1'b0),
    .LOCKED   (pll_locked),
    .DADDR    (7'h0),
    .DCLK     (1'b0),
    .DEN      (1'b0),
    .DI       (16'h0),
    .DO       (),
    .DRDY     (),
    .DWE      (1'b0)
  );

  BUFG eth_clk_bufg (
    .I (clk_125_pll),
    .O (clk_125)
  );

  sync_reset #(
    .N (4)
  ) rst_125_sync (
    .clk (clk_125),
    .rst (sys_reset | ~pll_locked),
    .out (rst_125)
  );

  //----------------------------------------------------------------
  // PHY bring-up
  //----------------------------------------------------------------

  logic phy_ready, packet_done;

  Mdio_Phy_Init #(
    .RESET_HOLD_CYCLES (PHY_RESET_HOLD_CYCLES),
    .RESET_WAIT_CYCLES (PHY_RESET_WAIT_CYCLES),
    .MDC_DIV           (MDC_DIV)
  ) phy_init (
    .clk         (clk_125),
    .rst         (rst_125),
    .phy_reset_n (phy_reset_n),
    .mdc         (phy_mdc),
    .mdio_o      (phy_mdio_o),
    .mdio_oe     (phy_mdio_oe),
    .mdio_i      (phy_mdio_i),
    .done        (phy_ready),
    .phy_addr    ()
  );

  //----------------------------------------------------------------
  // RX input delay: the BUFIO clock reaches the IDDRs ~1 ns after the
  // data, so delay RXD/RX_CTL to sit mid-window (uses Top's
  // IDELAYCTRL, which Vivado replicates into this bank)
  //----------------------------------------------------------------

  logic [4:0] rx_in, rx_dly;

  assign rx_in = {phy_rx_ctl, phy_rxd};

  for (genvar i = 0; i < 5; i++) begin : g_rx_idelay
    IDELAYE2 #(
      .IDELAY_TYPE           ("FIXED"),
      .DELAY_SRC             ("IDATAIN"),
      .IDELAY_VALUE          (RX_IDELAY_TAPS),
      .HIGH_PERFORMANCE_MODE ("TRUE"),
      .SIGNAL_PATTERN        ("DATA"),
      .REFCLK_FREQUENCY      (200.0),
      .CINVCTRL_SEL          ("FALSE"),
      .PIPE_SEL              ("FALSE")
    ) dly (
      .IDATAIN     (rx_in[i]),
      .DATAOUT     (rx_dly[i]),
      .DATAIN      (1'b0),
      .C           (1'b0),
      .CE          (1'b0),
      .INC         (1'b0),
      .LD          (1'b0),
      .LDPIPEEN    (1'b0),
      .REGRST      (1'b0),
      .CNTVALUEIN  (5'd0),
      .CNTVALUEOUT (),
      .CINVCTRL    (1'b0)
    );
  end

  //----------------------------------------------------------------
  // MAC
  //----------------------------------------------------------------

  logic [7:0] rx_axis_tdata, tx_axis_tdata;
  logic       rx_axis_tvalid, rx_axis_tready, rx_axis_tlast, rx_axis_tuser;
  logic       tx_axis_tvalid, tx_axis_tready, tx_axis_tlast, tx_axis_tuser;

  eth_mac_1g_rgmii_fifo #(
    .TARGET            ("XILINX"),
    .IODDR_STYLE       ("IODDR"),
    .CLOCK_INPUT_STYLE ("BUFR"),
    .USE_CLK90         ("FALSE"),
    .ENABLE_PADDING    (1),
    .MIN_FRAME_LENGTH  (64),
    .TX_FIFO_DEPTH     (4096),
    .TX_FRAME_FIFO     (1),
    .RX_FIFO_DEPTH     (4096),
    .RX_FRAME_FIFO     (1)
  ) eth_mac (
    .gtx_clk            (clk_125),
    .gtx_clk90          (clk_125),
    .gtx_rst            (rst_125),
    .logic_clk          (clk_125),
    .logic_rst          (rst_125),
    .tx_axis_tdata      (tx_axis_tdata),
    .tx_axis_tvalid     (tx_axis_tvalid),
    .tx_axis_tready     (tx_axis_tready),
    .tx_axis_tlast      (tx_axis_tlast),
    .tx_axis_tuser      (tx_axis_tuser),
    .rx_axis_tdata      (rx_axis_tdata),
    .rx_axis_tvalid     (rx_axis_tvalid),
    .rx_axis_tready     (rx_axis_tready),
    .rx_axis_tlast      (rx_axis_tlast),
    .rx_axis_tuser      (rx_axis_tuser),
    .rgmii_rx_clk       (phy_rx_clk),
    .rgmii_rxd          (rx_dly[3:0]),
    .rgmii_rx_ctl       (rx_dly[4]),
    .rgmii_tx_clk       (phy_tx_clk),
    .rgmii_txd          (phy_txd),
    .rgmii_tx_ctl       (phy_tx_ctl),
    .tx_fifo_overflow   (),
    .tx_fifo_bad_frame  (),
    .tx_fifo_good_frame (),
    .rx_error_bad_frame (),
    .rx_error_bad_fcs   (),
    .rx_fifo_overflow   (),
    .rx_fifo_bad_frame  (),
    .rx_fifo_good_frame (),
    .speed              (),
    .cfg_ifg            (8'd12),
    .cfg_tx_enable      (1'b1),
    .cfg_rx_enable      (1'b1)
  );

  //----------------------------------------------------------------
  // Ethernet framing + UDP/IP/ARP
  //----------------------------------------------------------------

  logic        rx_eth_hdr_valid, rx_eth_hdr_ready;
  logic [47:0] rx_eth_dest_mac, rx_eth_src_mac;
  logic [15:0] rx_eth_type;
  logic [7:0]  rx_eth_payload_axis_tdata;
  logic        rx_eth_payload_axis_tvalid, rx_eth_payload_axis_tready;
  logic        rx_eth_payload_axis_tlast, rx_eth_payload_axis_tuser;

  logic        tx_eth_hdr_valid, tx_eth_hdr_ready;
  logic [47:0] tx_eth_dest_mac, tx_eth_src_mac;
  logic [15:0] tx_eth_type;
  logic [7:0]  tx_eth_payload_axis_tdata;
  logic        tx_eth_payload_axis_tvalid, tx_eth_payload_axis_tready;
  logic        tx_eth_payload_axis_tlast, tx_eth_payload_axis_tuser;

  eth_axis_rx eth_rx (
    .clk                            (clk_125),
    .rst                            (rst_125),
    .s_axis_tdata                   (rx_axis_tdata),
    .s_axis_tvalid                  (rx_axis_tvalid),
    .s_axis_tready                  (rx_axis_tready),
    .s_axis_tlast                   (rx_axis_tlast),
    .s_axis_tuser                   (rx_axis_tuser),
    .m_eth_hdr_valid                (rx_eth_hdr_valid),
    .m_eth_hdr_ready                (rx_eth_hdr_ready),
    .m_eth_dest_mac                 (rx_eth_dest_mac),
    .m_eth_src_mac                  (rx_eth_src_mac),
    .m_eth_type                     (rx_eth_type),
    .m_eth_payload_axis_tdata       (rx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tvalid      (rx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready      (rx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast       (rx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser       (rx_eth_payload_axis_tuser),
    .busy                           (),
    .error_header_early_termination ()
  );

  eth_axis_tx eth_tx (
    .clk                       (clk_125),
    .rst                       (rst_125),
    .s_eth_hdr_valid           (tx_eth_hdr_valid),
    .s_eth_hdr_ready           (tx_eth_hdr_ready),
    .s_eth_dest_mac            (tx_eth_dest_mac),
    .s_eth_src_mac             (tx_eth_src_mac),
    .s_eth_type                (tx_eth_type),
    .s_eth_payload_axis_tdata  (tx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tvalid (tx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready (tx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast  (tx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser  (tx_eth_payload_axis_tuser),
    .m_axis_tdata              (tx_axis_tdata),
    .m_axis_tvalid             (tx_axis_tvalid),
    .m_axis_tready             (tx_axis_tready),
    .m_axis_tlast              (tx_axis_tlast),
    .m_axis_tuser              (tx_axis_tuser),
    .busy                      ()
  );

  logic        rx_udp_hdr_valid, rx_udp_hdr_ready;
  logic [31:0] rx_udp_ip_source_ip;
  logic [15:0] rx_udp_source_port, rx_udp_dest_port;
  logic [7:0]  rx_udp_payload_axis_tdata;
  logic        rx_udp_payload_axis_tvalid, rx_udp_payload_axis_tready;
  logic        rx_udp_payload_axis_tlast, rx_udp_payload_axis_tuser;

  logic        tx_udp_hdr_valid, tx_udp_hdr_ready;
  logic [5:0]  tx_udp_ip_dscp;
  logic [1:0]  tx_udp_ip_ecn;
  logic [7:0]  tx_udp_ip_ttl;
  logic [31:0] tx_udp_ip_source_ip, tx_udp_ip_dest_ip;
  logic [15:0] tx_udp_source_port, tx_udp_dest_port, tx_udp_length, tx_udp_checksum;
  logic [7:0]  tx_udp_payload_axis_tdata;
  logic        tx_udp_payload_axis_tvalid, tx_udp_payload_axis_tready;
  logic        tx_udp_payload_axis_tlast, tx_udp_payload_axis_tuser;

  udp_complete udp_stack (
    .clk                                    (clk_125),
    .rst                                    (rst_125),
    .s_eth_hdr_valid                        (rx_eth_hdr_valid),
    .s_eth_hdr_ready                        (rx_eth_hdr_ready),
    .s_eth_dest_mac                         (rx_eth_dest_mac),
    .s_eth_src_mac                          (rx_eth_src_mac),
    .s_eth_type                             (rx_eth_type),
    .s_eth_payload_axis_tdata               (rx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tvalid              (rx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready              (rx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast               (rx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser               (rx_eth_payload_axis_tuser),
    .m_eth_hdr_valid                        (tx_eth_hdr_valid),
    .m_eth_hdr_ready                        (tx_eth_hdr_ready),
    .m_eth_dest_mac                         (tx_eth_dest_mac),
    .m_eth_src_mac                          (tx_eth_src_mac),
    .m_eth_type                             (tx_eth_type),
    .m_eth_payload_axis_tdata               (tx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tvalid              (tx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready              (tx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast               (tx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser               (tx_eth_payload_axis_tuser),
    // Raw IP is not used
    .s_ip_hdr_valid                         (1'b0),
    .s_ip_hdr_ready                         (),
    .s_ip_dscp                              (6'd0),
    .s_ip_ecn                               (2'd0),
    .s_ip_length                            (16'd0),
    .s_ip_ttl                               (8'd0),
    .s_ip_protocol                          (8'd0),
    .s_ip_source_ip                         (32'd0),
    .s_ip_dest_ip                           (32'd0),
    .s_ip_payload_axis_tdata                (8'd0),
    .s_ip_payload_axis_tvalid               (1'b0),
    .s_ip_payload_axis_tready               (),
    .s_ip_payload_axis_tlast                (1'b0),
    .s_ip_payload_axis_tuser                (1'b0),
    .m_ip_hdr_valid                         (),
    .m_ip_hdr_ready                         (1'b1),
    .m_ip_eth_dest_mac                      (),
    .m_ip_eth_src_mac                       (),
    .m_ip_eth_type                          (),
    .m_ip_version                           (),
    .m_ip_ihl                               (),
    .m_ip_dscp                              (),
    .m_ip_ecn                               (),
    .m_ip_length                            (),
    .m_ip_identification                    (),
    .m_ip_flags                             (),
    .m_ip_fragment_offset                   (),
    .m_ip_ttl                               (),
    .m_ip_protocol                          (),
    .m_ip_header_checksum                   (),
    .m_ip_source_ip                         (),
    .m_ip_dest_ip                           (),
    .m_ip_payload_axis_tdata                (),
    .m_ip_payload_axis_tvalid               (),
    .m_ip_payload_axis_tready               (1'b1),
    .m_ip_payload_axis_tlast                (),
    .m_ip_payload_axis_tuser                (),
    // UDP
    .s_udp_hdr_valid                        (tx_udp_hdr_valid),
    .s_udp_hdr_ready                        (tx_udp_hdr_ready),
    .s_udp_ip_dscp                          (tx_udp_ip_dscp),
    .s_udp_ip_ecn                           (tx_udp_ip_ecn),
    .s_udp_ip_ttl                           (tx_udp_ip_ttl),
    .s_udp_ip_source_ip                     (tx_udp_ip_source_ip),
    .s_udp_ip_dest_ip                       (tx_udp_ip_dest_ip),
    .s_udp_source_port                      (tx_udp_source_port),
    .s_udp_dest_port                        (tx_udp_dest_port),
    .s_udp_length                           (tx_udp_length),
    .s_udp_checksum                         (tx_udp_checksum),
    .s_udp_payload_axis_tdata               (tx_udp_payload_axis_tdata),
    .s_udp_payload_axis_tvalid              (tx_udp_payload_axis_tvalid),
    .s_udp_payload_axis_tready              (tx_udp_payload_axis_tready),
    .s_udp_payload_axis_tlast               (tx_udp_payload_axis_tlast),
    .s_udp_payload_axis_tuser               (tx_udp_payload_axis_tuser),
    .m_udp_hdr_valid                        (rx_udp_hdr_valid),
    .m_udp_hdr_ready                        (rx_udp_hdr_ready),
    .m_udp_eth_dest_mac                     (),
    .m_udp_eth_src_mac                      (),
    .m_udp_eth_type                         (),
    .m_udp_ip_version                       (),
    .m_udp_ip_ihl                           (),
    .m_udp_ip_dscp                          (),
    .m_udp_ip_ecn                           (),
    .m_udp_ip_length                        (),
    .m_udp_ip_identification                (),
    .m_udp_ip_flags                         (),
    .m_udp_ip_fragment_offset               (),
    .m_udp_ip_ttl                           (),
    .m_udp_ip_protocol                      (),
    .m_udp_ip_header_checksum               (),
    .m_udp_ip_source_ip                     (rx_udp_ip_source_ip),
    .m_udp_ip_dest_ip                       (),
    .m_udp_source_port                      (rx_udp_source_port),
    .m_udp_dest_port                        (rx_udp_dest_port),
    .m_udp_length                           (),
    .m_udp_checksum                         (),
    .m_udp_payload_axis_tdata               (rx_udp_payload_axis_tdata),
    .m_udp_payload_axis_tvalid              (rx_udp_payload_axis_tvalid),
    .m_udp_payload_axis_tready              (rx_udp_payload_axis_tready),
    .m_udp_payload_axis_tlast               (rx_udp_payload_axis_tlast),
    .m_udp_payload_axis_tuser               (rx_udp_payload_axis_tuser),
    .ip_rx_busy                             (),
    .ip_tx_busy                             (),
    .udp_rx_busy                            (),
    .udp_tx_busy                            (),
    .ip_rx_error_header_early_termination   (),
    .ip_rx_error_payload_early_termination  (),
    .ip_rx_error_invalid_header             (),
    .ip_rx_error_invalid_checksum           (),
    .ip_tx_error_payload_early_termination  (),
    .ip_tx_error_arp_failed                 (),
    .udp_rx_error_header_early_termination  (),
    .udp_rx_error_payload_early_termination (),
    .udp_tx_error_payload_early_termination (),
    .local_mac                              (LOCAL_MAC),
    .local_ip                               (LOCAL_IP),
    .gateway_ip                             (GATEWAY_IP),
    .subnet_mask                            (SUBNET_MASK),
    .clear_arp_cache                        (1'b0)
  );

  //----------------------------------------------------------------
  // Command engine and the bus bridge into the clk_sync domain
  //----------------------------------------------------------------

  logic        req_start, req_busy, req_we, rsp_valid;
  logic [31:0] req_addr, req_wdata, rsp_rdata;
  logic [1:0]  rsp_resp;

  Udp_Cmd_Engine #(
    .UDP_PORT    (UDP_PORT),
    .STATUS_ADDR (STATUS_ADDR)
  ) cmd_engine (
    .clk                       (clk_125),
    .rst                       (rst_125),
    .local_ip                  (LOCAL_IP),
    .s_udp_hdr_valid           (rx_udp_hdr_valid),
    .s_udp_hdr_ready           (rx_udp_hdr_ready),
    .s_udp_ip_source_ip        (rx_udp_ip_source_ip),
    .s_udp_source_port         (rx_udp_source_port),
    .s_udp_dest_port           (rx_udp_dest_port),
    .s_udp_payload_axis_tdata  (rx_udp_payload_axis_tdata),
    .s_udp_payload_axis_tvalid (rx_udp_payload_axis_tvalid),
    .s_udp_payload_axis_tready (rx_udp_payload_axis_tready),
    .s_udp_payload_axis_tlast  (rx_udp_payload_axis_tlast),
    .s_udp_payload_axis_tuser  (rx_udp_payload_axis_tuser),
    .m_udp_hdr_valid           (tx_udp_hdr_valid),
    .m_udp_hdr_ready           (tx_udp_hdr_ready),
    .m_udp_ip_dscp             (tx_udp_ip_dscp),
    .m_udp_ip_ecn              (tx_udp_ip_ecn),
    .m_udp_ip_ttl              (tx_udp_ip_ttl),
    .m_udp_ip_source_ip        (tx_udp_ip_source_ip),
    .m_udp_ip_dest_ip          (tx_udp_ip_dest_ip),
    .m_udp_source_port         (tx_udp_source_port),
    .m_udp_dest_port           (tx_udp_dest_port),
    .m_udp_length              (tx_udp_length),
    .m_udp_checksum            (tx_udp_checksum),
    .m_udp_payload_axis_tdata  (tx_udp_payload_axis_tdata),
    .m_udp_payload_axis_tvalid (tx_udp_payload_axis_tvalid),
    .m_udp_payload_axis_tready (tx_udp_payload_axis_tready),
    .m_udp_payload_axis_tlast  (tx_udp_payload_axis_tlast),
    .m_udp_payload_axis_tuser  (tx_udp_payload_axis_tuser),
    .req_start                 (req_start),
    .req_busy                  (req_busy),
    .req_we                    (req_we),
    .req_addr                  (req_addr),
    .req_wdata                 (req_wdata),
    .rsp_valid                 (rsp_valid),
    .rsp_resp                  (rsp_resp),
    .rsp_rdata                 (rsp_rdata),
    .packet_done               (packet_done)
  );

  Axil_Master_Cdc bus_bridge (
    .req_clk       (clk_125),
    .req_rst       (rst_125),
    .req_start     (req_start),
    .req_we        (req_we),
    .req_addr      (req_addr),
    .req_wdata     (req_wdata),
    .req_busy      (req_busy),
    .rsp_valid     (rsp_valid),
    .rsp_resp      (rsp_resp),
    .rsp_rdata     (rsp_rdata),
    .m_axi_aclk    (m_axi_aclk),
    .m_axi_aresetn (m_axi_aresetn),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awprot  (m_axi_awprot),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arprot  (m_axi_arprot),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready)
  );

  //----------------------------------------------------------------
  // Status LED
  //----------------------------------------------------------------

  logic [22:0] blink_cnt;

  always_ff @(posedge clk_125) begin
    if (rst_125)             blink_cnt <= '0;
    else if (packet_done)    blink_cnt <= '1;
    else if (blink_cnt != 0) blink_cnt <= blink_cnt - 1'b1;
  end

  assign status_led = phy_ready && (blink_cnt == 0);

endmodule

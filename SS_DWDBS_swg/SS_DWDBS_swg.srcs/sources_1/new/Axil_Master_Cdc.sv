`timescale 1ns / 1ps

//==================================================================
// Axil_Master_Cdc
//
// Carries one 32-bit read or write at a time from the request clock
// domain (the 125 MHz Ethernet logic) to an AXI4-Lite master in the
// AXI clock domain (the 50 MHz clk_sync), and the response back.
//
// A 4-phase req/ack handshake crosses the domains: the request
// fields are held stable while req is high, and the response fields
// while ack is high, so only req/ack go through synchronizers. The
// field paths are covered by set_max_delay -datapath_only in eth.xdc.
//
// Request side: pulse req_start while req_busy is low; rsp_valid
// pulses once with the AXI response (BRESP/RRESP) and read data.
//==================================================================

module Axil_Master_Cdc (
  // Request domain
  input  logic        req_clk,
  input  logic        req_rst,
  input  logic        req_start,
  input  logic        req_we,
  input  logic [31:0] req_addr,
  input  logic [31:0] req_wdata,
  output logic        req_busy,
  output logic        rsp_valid,
  output logic [1:0]  rsp_resp,
  output logic [31:0] rsp_rdata,

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
  output logic        m_axi_rready
);

  //----------------------------------------------------------------
  // Request domain
  //----------------------------------------------------------------

  typedef enum logic [1:0] {Q_IDLE, Q_WAIT_ACK, Q_WAIT_NACK} q_state_t;

  q_state_t q_state;
  logic        req_flag;
  logic        req_we_q;
  logic [31:0] req_addr_q;
  logic [31:0] req_wdata_q;
  (* ASYNC_REG = "TRUE" *) logic [1:0] ack_sync;

  logic        ack_flag;        // AXI domain
  logic [1:0]  axi_resp_q;      // AXI domain, stable while ack_flag
  logic [31:0] axi_rdata_q;     // AXI domain, stable while ack_flag

  assign req_busy = (q_state != Q_IDLE);

  always_ff @(posedge req_clk) begin
    ack_sync <= {ack_sync[0], ack_flag};
  end

  always_ff @(posedge req_clk) begin
    rsp_valid <= 1'b0;
    if (req_rst) begin
      q_state  <= Q_IDLE;
      req_flag <= 1'b0;
    end else begin
      case (q_state)
        Q_IDLE: begin
          if (req_start) begin
            req_we_q    <= req_we;
            req_addr_q  <= req_addr;
            req_wdata_q <= req_wdata;
            req_flag    <= 1'b1;
            q_state     <= Q_WAIT_ACK;
          end
        end
        Q_WAIT_ACK: begin
          if (ack_sync[1]) begin
            rsp_valid <= 1'b1;
            rsp_resp  <= axi_resp_q;
            rsp_rdata <= axi_rdata_q;
            req_flag  <= 1'b0;
            q_state   <= Q_WAIT_NACK;
          end
        end
        default: begin  // Q_WAIT_NACK
          if (!ack_sync[1]) begin
            q_state <= Q_IDLE;
          end
        end
      endcase
    end
  end

  //----------------------------------------------------------------
  // AXI domain
  //----------------------------------------------------------------

  typedef enum logic [2:0] {A_IDLE, A_WRITE, A_READ_ADDR, A_READ_DATA, A_ACK} a_state_t;

  a_state_t a_state;
  (* ASYNC_REG = "TRUE" *) logic [1:0] req_sync;

  assign m_axi_awprot = 3'b000;
  assign m_axi_arprot = 3'b000;
  assign m_axi_wstrb  = 4'hF;

  always_ff @(posedge m_axi_aclk) begin
    req_sync <= {req_sync[0], req_flag};
  end

  always_ff @(posedge m_axi_aclk) begin
    if (!m_axi_aresetn) begin
      a_state       <= A_IDLE;
      ack_flag      <= 1'b0;
      m_axi_awvalid <= 1'b0;
      m_axi_wvalid  <= 1'b0;
      m_axi_bready  <= 1'b0;
      m_axi_arvalid <= 1'b0;
      m_axi_rready  <= 1'b0;
    end else begin
      case (a_state)
        A_IDLE: begin
          if (req_sync[1]) begin
            if (req_we_q) begin
              m_axi_awaddr  <= req_addr_q;
              m_axi_wdata   <= req_wdata_q;
              m_axi_awvalid <= 1'b1;
              m_axi_wvalid  <= 1'b1;
              m_axi_bready  <= 1'b1;
              a_state       <= A_WRITE;
            end else begin
              m_axi_araddr  <= req_addr_q;
              m_axi_arvalid <= 1'b1;
              a_state       <= A_READ_ADDR;
            end
          end
        end
        A_WRITE: begin
          if (m_axi_awready) m_axi_awvalid <= 1'b0;
          if (m_axi_wready)  m_axi_wvalid  <= 1'b0;
          if (m_axi_bvalid) begin
            m_axi_bready <= 1'b0;
            axi_resp_q   <= m_axi_bresp;
            axi_rdata_q  <= 32'h0;
            ack_flag     <= 1'b1;
            a_state      <= A_ACK;
          end
        end
        A_READ_ADDR: begin
          if (m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b1;
            a_state       <= A_READ_DATA;
          end
        end
        A_READ_DATA: begin
          if (m_axi_rvalid) begin
            m_axi_rready <= 1'b0;
            axi_resp_q   <= m_axi_rresp;
            axi_rdata_q  <= m_axi_rdata;
            ack_flag     <= 1'b1;
            a_state      <= A_ACK;
          end
        end
        default: begin  // A_ACK
          if (!req_sync[1]) begin
            ack_flag <= 1'b0;
            a_state  <= A_IDLE;
          end
        end
      endcase
    end
  end

endmodule

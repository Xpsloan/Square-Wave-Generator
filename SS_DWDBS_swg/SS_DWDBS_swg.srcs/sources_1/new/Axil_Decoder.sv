`timescale 1ns / 1ps

//==================================================================
// Axil_Decoder
//
// One AXI4-Lite master to N_SLAVES slaves. Slave i owns the 4 KB
// window i * 0x1000 (decoded from address bits [31:12]); addresses
// past the last window get a DECERR from the decoder itself, so
// every transaction is answered. Address, write data and strobes
// are broadcast; VALID/READY and the responses are switched.
//
// One write and one read can be in flight at a time. wr_ok[i]
// pulses for one cycle when a write to slave i completes with OKAY.
//==================================================================

module Axil_Decoder #(
  parameter int N_SLAVES = 9
)(
  input  logic                aclk,
  input  logic                aresetn,

  // From the master
  input  logic [31:0]         s_awaddr,
  input  logic                s_awvalid,
  output logic                s_awready,
  input  logic [31:0]         s_wdata,
  input  logic [3:0]          s_wstrb,
  input  logic                s_wvalid,
  output logic                s_wready,
  output logic [1:0]          s_bresp,
  output logic                s_bvalid,
  input  logic                s_bready,
  input  logic [31:0]         s_araddr,
  input  logic                s_arvalid,
  output logic                s_arready,
  output logic [31:0]         s_rdata,
  output logic [1:0]          s_rresp,
  output logic                s_rvalid,
  input  logic                s_rready,

  // To the slaves (address/data shared, handshakes per slave)
  output logic [11:0]         m_awaddr,
  output logic [N_SLAVES-1:0] m_awvalid,
  input  logic [N_SLAVES-1:0] m_awready,
  output logic [31:0]         m_wdata,
  output logic [3:0]          m_wstrb,
  output logic [N_SLAVES-1:0] m_wvalid,
  input  logic [N_SLAVES-1:0] m_wready,
  input  logic [1:0]          m_bresp [N_SLAVES],
  input  logic [N_SLAVES-1:0] m_bvalid,
  output logic [N_SLAVES-1:0] m_bready,
  output logic [11:0]         m_araddr,
  output logic [N_SLAVES-1:0] m_arvalid,
  input  logic [N_SLAVES-1:0] m_arready,
  input  logic [31:0]         m_rdata [N_SLAVES],
  input  logic [1:0]          m_rresp [N_SLAVES],
  input  logic [N_SLAVES-1:0] m_rvalid,
  output logic [N_SLAVES-1:0] m_rready,

  output logic [N_SLAVES-1:0] wr_ok
);

  localparam int SEL_W = (N_SLAVES > 1) ? $clog2(N_SLAVES) : 1;

  function automatic logic hit(input logic [31:0] a);
    return (a[31:12] < N_SLAVES);
  endfunction

  assign m_awaddr = s_awaddr[11:0];
  assign m_wdata  = s_wdata;
  assign m_wstrb  = s_wstrb;
  assign m_araddr = s_araddr[11:0];

  //----------------------------------------------------------------
  // Write path: decode on AWVALID, pass AW and W through to the
  // selected slave, then pass its B back.
  //----------------------------------------------------------------

  typedef enum logic [1:0] {W_IDLE, W_XFER, W_RESP} w_state_t;

  w_state_t   w_state;
  logic [SEL_W-1:0] w_sel;
  logic       w_err;
  logic       aw_done, w_done;

  always_comb begin
    m_awvalid = '0;
    m_wvalid  = '0;
    m_bready  = '0;
    s_awready = 1'b0;
    s_wready  = 1'b0;
    s_bvalid  = 1'b0;
    s_bresp   = 2'b00;
    case (w_state)
      W_XFER: begin
        if (w_err) begin
          s_awready = !aw_done;
          s_wready  = !w_done;
        end else begin
          m_awvalid[w_sel] = s_awvalid && !aw_done;
          m_wvalid[w_sel]  = s_wvalid  && !w_done;
          s_awready        = m_awready[w_sel] && !aw_done;
          s_wready         = m_wready[w_sel]  && !w_done;
        end
      end
      W_RESP: begin
        if (w_err) begin
          s_bvalid = 1'b1;
          s_bresp  = 2'b11;  // DECERR
        end else begin
          s_bvalid        = m_bvalid[w_sel];
          s_bresp         = m_bresp[w_sel];
          m_bready[w_sel] = s_bready;
        end
      end
      default: ;
    endcase
  end

  always_ff @(posedge aclk) begin
    wr_ok <= '0;
    if (!aresetn) begin
      w_state <= W_IDLE;
      aw_done <= 1'b0;
      w_done  <= 1'b0;
    end else begin
      case (w_state)
        W_IDLE: begin
          if (s_awvalid) begin
            w_sel   <= SEL_W'(s_awaddr[31:12]);
            w_err   <= !hit(s_awaddr);
            aw_done <= 1'b0;
            w_done  <= 1'b0;
            w_state <= W_XFER;
          end
        end
        W_XFER: begin
          if (s_awvalid && s_awready) aw_done <= 1'b1;
          if (s_wvalid  && s_wready)  w_done  <= 1'b1;
          if ((aw_done || (s_awvalid && s_awready)) && (w_done || (s_wvalid && s_wready))) begin
            w_state <= W_RESP;
          end
        end
        default: begin  // W_RESP
          if (s_bvalid && s_bready) begin
            if (!w_err && s_bresp == 2'b00) wr_ok[w_sel] <= 1'b1;
            w_state <= W_IDLE;
          end
        end
      endcase
    end
  end

  //----------------------------------------------------------------
  // Read path
  //----------------------------------------------------------------

  typedef enum logic [1:0] {R_IDLE, R_ADDR, R_DATA} r_state_t;

  r_state_t   r_state;
  logic [SEL_W-1:0] r_sel;
  logic       r_err;

  always_comb begin
    m_arvalid = '0;
    m_rready  = '0;
    s_arready = 1'b0;
    s_rvalid  = 1'b0;
    s_rresp   = 2'b00;
    s_rdata   = 32'h0;
    case (r_state)
      R_ADDR: begin
        if (r_err) begin
          s_arready = 1'b1;
        end else begin
          m_arvalid[r_sel] = s_arvalid;
          s_arready        = m_arready[r_sel];
        end
      end
      R_DATA: begin
        if (r_err) begin
          s_rvalid = 1'b1;
          s_rresp  = 2'b11;  // DECERR
        end else begin
          s_rvalid        = m_rvalid[r_sel];
          s_rresp         = m_rresp[r_sel];
          s_rdata         = m_rdata[r_sel];
          m_rready[r_sel] = s_rready;
        end
      end
      default: ;
    endcase
  end

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      r_state <= R_IDLE;
    end else begin
      case (r_state)
        R_IDLE: begin
          if (s_arvalid) begin
            r_sel   <= SEL_W'(s_araddr[31:12]);
            r_err   <= !hit(s_araddr);
            r_state <= R_ADDR;
          end
        end
        R_ADDR: begin
          if (s_arvalid && s_arready) r_state <= R_DATA;
        end
        default: begin  // R_DATA
          if (s_rvalid && s_rready) r_state <= R_IDLE;
        end
      endcase
    end
  end

endmodule

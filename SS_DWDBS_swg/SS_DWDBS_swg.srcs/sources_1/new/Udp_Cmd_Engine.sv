`timescale 1ns / 1ps

//==================================================================
// Udp_Cmd_Engine
//
// Turns UDP command packets into AXI4-Lite reads/writes and answers
// each one with a reply packet. Everything is big-endian.
//
// Request payload (to UDP_PORT):
//   0   u32  MAGIC 0x5357_4731 ("SWG1")
//   4   u16  SEQ   (echoed back)
//   6   u16  COUNT number of ops, 0..MAX_OPS
//   8   COUNT x { u32 ADDR, u32 DATA }
//            ADDR bit 31 = 1 read, 0 write; bits 30:0 = bus address
//
// Reply payload (to the sender's IP/port):
//   0   u32  MAGIC
//   4   u16  SEQ
//   6   u16  DONE  number of ops executed
//   8   u32  CODE  0 OK, 1 bad magic, 2 bad length/COUNT,
//                  3 an op failed (it is the last one executed)
//   12  u32  STATE Run_Control STATE register, read after the ops
//   16  DONE x { u32 RESP (AXI response), u32 DATA (read data, else 0) }
//
// A packet is buffered completely and only executed if it arrived
// intact and is well-formed, so the bus never sees part of a
// packet. Ops run in order, one at a time, and stop at the first
// non-OKAY response. Packets with a bad frame (tuser) are dropped
// silently; packets to other ports are ignored.
//==================================================================

module Udp_Cmd_Engine #(
  parameter logic [15:0] UDP_PORT    = 16'd1234,
  parameter logic [31:0] MAGIC       = 32'h5357_4731,
  parameter int unsigned MAX_OPS     = 128,
  parameter logic [31:0] STATUS_ADDR = 32'h0000_0004
)(
  input  logic        clk,
  input  logic        rst,
  input  logic [31:0] local_ip,

  // UDP receive (from udp_complete)
  input  logic        s_udp_hdr_valid,
  output logic        s_udp_hdr_ready,
  input  logic [31:0] s_udp_ip_source_ip,
  input  logic [15:0] s_udp_source_port,
  input  logic [15:0] s_udp_dest_port,
  input  logic [7:0]  s_udp_payload_axis_tdata,
  input  logic        s_udp_payload_axis_tvalid,
  output logic        s_udp_payload_axis_tready,
  input  logic        s_udp_payload_axis_tlast,
  input  logic        s_udp_payload_axis_tuser,

  // UDP transmit (to udp_complete)
  output logic        m_udp_hdr_valid,
  input  logic        m_udp_hdr_ready,
  output logic [5:0]  m_udp_ip_dscp,
  output logic [1:0]  m_udp_ip_ecn,
  output logic [7:0]  m_udp_ip_ttl,
  output logic [31:0] m_udp_ip_source_ip,
  output logic [31:0] m_udp_ip_dest_ip,
  output logic [15:0] m_udp_source_port,
  output logic [15:0] m_udp_dest_port,
  output logic [15:0] m_udp_length,
  output logic [15:0] m_udp_checksum,
  output logic [7:0]  m_udp_payload_axis_tdata,
  output logic        m_udp_payload_axis_tvalid,
  input  logic        m_udp_payload_axis_tready,
  output logic        m_udp_payload_axis_tlast,
  output logic        m_udp_payload_axis_tuser,

  // Bus transactions (Axil_Master_Cdc)
  output logic        req_start,
  input  logic        req_busy,
  output logic        req_we,
  output logic [31:0] req_addr,
  output logic [31:0] req_wdata,
  input  logic        rsp_valid,
  input  logic [1:0]  rsp_resp,
  input  logic [31:0] rsp_rdata,

  output logic        packet_done  // pulse per reply sent
);

  localparam int OP_W  = $clog2(MAX_OPS);
  localparam int CNT_W = $clog2(MAX_OPS + 1);

  localparam logic [31:0] CODE_OK        = 32'd0;
  localparam logic [31:0] CODE_BAD_MAGIC = 32'd1;
  localparam logic [31:0] CODE_BAD_LEN   = 32'd2;
  localparam logic [31:0] CODE_OP_FAILED = 32'd3;

  typedef enum logic [3:0] {
    E_IDLE, E_RX, E_DROP, E_CHECK, E_EXEC, E_EXEC_WAIT,
    E_STATUS, E_STATUS_WAIT, E_TX_HDR, E_TX_PAYLOAD
  } e_state_t;

  e_state_t e_state;

  // Ops are stored as {ADDR, DATA}; each entry is overwritten with
  // {RESP, DATA} once executed. Asynchronous read (LUT RAM).
  logic [63:0] op_ram [MAX_OPS];

  logic [31:0] src_ip_q;
  logic [15:0] src_port_q;
  logic [31:0] magic_q;
  logic [15:0] seq_q;
  logic [15:0] count_q;
  logic [55:0] asm_q;
  logic [10:0] rx_n;          // payload bytes received (saturating)
  logic        rx_long;       // more than fits in rx_n
  logic [CNT_W-1:0] op_k;     // next op to execute
  logic [CNT_W-1:0] done_n;   // ops executed
  logic [31:0] code_q;
  logic [31:0] state_q;
  logic [11:0] tx_n;

  logic [7:0]  rx_byte;
  logic        rx_beat;
  logic [7:0]  rx_op;         // op index of the byte being received
  logic [63:0] op_word;
  logic [11:0] tx_len;        // reply payload length

  assign rx_byte = s_udp_payload_axis_tdata;
  assign rx_beat = s_udp_payload_axis_tvalid && s_udp_payload_axis_tready;
  assign rx_op   = 8'((rx_n - 11'd8) >> 3);
  assign op_word = op_ram[op_k[OP_W-1:0]];
  assign tx_len  = 12'd16 + {done_n, 3'b000};

  assign s_udp_hdr_ready           = (e_state == E_IDLE);
  assign s_udp_payload_axis_tready = (e_state == E_RX) || (e_state == E_DROP);

  assign m_udp_ip_dscp      = 6'd0;
  assign m_udp_ip_ecn       = 2'd0;
  assign m_udp_ip_ttl       = 8'd64;
  assign m_udp_ip_source_ip = local_ip;
  assign m_udp_ip_dest_ip   = src_ip_q;
  assign m_udp_source_port  = UDP_PORT;
  assign m_udp_dest_port    = src_port_q;
  assign m_udp_length       = 16'd8 + 16'(tx_len);
  assign m_udp_checksum     = 16'd0;   // filled in by udp_complete
  assign m_udp_hdr_valid    = (e_state == E_TX_HDR);

  //----------------------------------------------------------------
  // Reply byte stream: 16-byte header from registers, then results
  //----------------------------------------------------------------

  logic [127:0] tx_hdr;
  logic [63:0]  tx_word;
  logic [11:0]  tx_res;

  assign tx_hdr  = {MAGIC, seq_q, 16'(done_n), code_q, state_q};
  assign tx_res  = tx_n - 12'd16;
  assign tx_word = op_ram[tx_res[OP_W+2:3]];

  always_comb begin
    if (tx_n < 12'd16) m_udp_payload_axis_tdata = tx_hdr[8'd127 - {tx_n[3:0], 3'b000} -: 8];
    else               m_udp_payload_axis_tdata = tx_word[8'd63 - {tx_res[2:0], 3'b000} -: 8];
  end

  assign m_udp_payload_axis_tvalid = (e_state == E_TX_PAYLOAD);
  assign m_udp_payload_axis_tlast  = (tx_n == tx_len - 12'd1);
  assign m_udp_payload_axis_tuser  = 1'b0;

  //----------------------------------------------------------------
  // Control
  //----------------------------------------------------------------

  always_ff @(posedge clk) begin
    if (rx_beat && e_state == E_RX && rx_n >= 11'd8 && rx_n[2:0] == 3'd7 && rx_op < MAX_OPS) begin
      op_ram[rx_op[OP_W-1:0]] <= {asm_q, rx_byte};
    end else if (e_state == E_EXEC_WAIT && rsp_valid) begin
      op_ram[op_k[OP_W-1:0]] <= {30'h0, rsp_resp, (req_we ? 32'h0 : rsp_rdata)};
    end
  end

  always_ff @(posedge clk) begin
    req_start   <= 1'b0;
    packet_done <= 1'b0;
    if (rst) begin
      e_state <= E_IDLE;
    end else begin
      case (e_state)
        E_IDLE: begin
          if (s_udp_hdr_valid) begin
            src_ip_q   <= s_udp_ip_source_ip;
            src_port_q <= s_udp_source_port;
            rx_n       <= '0;
            rx_long    <= 1'b0;
            e_state    <= (s_udp_dest_port == UDP_PORT) ? E_RX : E_DROP;
          end
        end

        E_DROP: begin
          if (rx_beat && s_udp_payload_axis_tlast) e_state <= E_IDLE;
        end

        E_RX: begin
          if (rx_beat) begin
            if      (rx_n < 11'd4) magic_q <= {magic_q[23:0], rx_byte};
            else if (rx_n < 11'd6) seq_q   <= {seq_q[7:0],    rx_byte};
            else if (rx_n < 11'd8) count_q <= {count_q[7:0],  rx_byte};
            else                   asm_q   <= {asm_q[47:0],   rx_byte};
            if (rx_n == 11'h7FF) rx_long <= 1'b1;
            else                 rx_n    <= rx_n + 1'b1;
            if (s_udp_payload_axis_tlast) begin
              e_state <= s_udp_payload_axis_tuser ? E_IDLE : E_CHECK;
            end
          end
        end

        E_CHECK: begin
          op_k   <= '0;
          done_n <= '0;
          if (rx_n < 11'd8 || magic_q != MAGIC) begin
            code_q  <= (rx_n < 11'd8) ? CODE_BAD_LEN : CODE_BAD_MAGIC;
            e_state <= E_STATUS;
          end else if (rx_long || count_q > MAX_OPS || {5'h0, rx_n} != 16'd8 + {count_q[12:0], 3'b000}) begin
            code_q  <= CODE_BAD_LEN;
            e_state <= E_STATUS;
          end else begin
            code_q  <= CODE_OK;
            e_state <= E_EXEC;
          end
        end

        E_EXEC: begin
          if (op_k == count_q[CNT_W-1:0]) begin
            e_state <= E_STATUS;
          end else if (!req_busy) begin
            req_we    <= !op_word[63];
            req_addr  <= {1'b0, op_word[62:32]};
            req_wdata <= op_word[31:0];
            req_start <= 1'b1;
            e_state   <= E_EXEC_WAIT;
          end
        end

        E_EXEC_WAIT: begin
          if (rsp_valid) begin
            op_k   <= op_k + 1'b1;
            done_n <= op_k + 1'b1;
            if (rsp_resp != 2'b00) begin
              code_q  <= CODE_OP_FAILED;
              e_state <= E_STATUS;
            end else begin
              e_state <= E_EXEC;
            end
          end
        end

        E_STATUS: begin
          if (!req_busy) begin
            req_we    <= 1'b0;
            req_addr  <= STATUS_ADDR;
            req_start <= 1'b1;
            e_state   <= E_STATUS_WAIT;
          end
        end

        E_STATUS_WAIT: begin
          if (rsp_valid) begin
            state_q <= (rsp_resp == 2'b00) ? rsp_rdata : 32'hFFFF_FFFF;
            e_state <= E_TX_HDR;
          end
        end

        E_TX_HDR: begin
          tx_n <= '0;
          if (m_udp_hdr_ready) e_state <= E_TX_PAYLOAD;
        end

        default: begin  // E_TX_PAYLOAD
          if (m_udp_payload_axis_tready) begin
            if (m_udp_payload_axis_tlast) begin
              packet_done <= 1'b1;
              e_state     <= E_IDLE;
            end else begin
              tx_n <= tx_n + 1'b1;
            end
          end
        end
      endcase
    end
  end

endmodule

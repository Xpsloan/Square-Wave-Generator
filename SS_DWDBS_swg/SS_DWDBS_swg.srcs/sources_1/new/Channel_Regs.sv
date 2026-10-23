`timescale 1ns / 1ps

//==================================================================
// Channel_Regs
//
// AXI4-Lite register block for one square-wave channel. Holds that
// channel's two 32-bit DDS words:
//
//   Offset  Name         Access  Reset value
//   0x00    PHASE_WORD   R/W     RESET_PHASE_WORD   (DDS phase_change)
//   0x04    START_PHASE  R/W     RESET_START_PHASE  (DDS start_phase)
//   other   -            RAZ/WI (reads 0, writes ignored, OKAY)
//
// Clocked by s_axi_aclk (the 50 MHz clk_sync); s_axi_aresetn is the
// usual synchronous active-low AXI reset. Byte strobes are honoured.
// AW and W are accepted independently, in either order. One write
// and one read can be outstanding at a time; every response is OKAY.
//==================================================================

module Channel_Regs #(
  parameter int          AXI_ADDR_WIDTH    = 4,  // >= 3; all bits are decoded, so no aliases
  parameter logic [31:0] RESET_PHASE_WORD  = 32'h0666_6666,
  parameter logic [31:0] RESET_START_PHASE = 32'h8000_0000 - RESET_PHASE_WORD * 32'd100_000
)(
  input  logic                      s_axi_aclk,
  input  logic                      s_axi_aresetn,

  // Write address channel
  input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
  input  logic [2:0]                s_axi_awprot,  // unused
  input  logic                      s_axi_awvalid,
  output logic                      s_axi_awready,

  // Write data channel
  input  logic [31:0]               s_axi_wdata,
  input  logic [3:0]                s_axi_wstrb,
  input  logic                      s_axi_wvalid,
  output logic                      s_axi_wready,

  // Write response channel
  output logic [1:0]                s_axi_bresp,
  output logic                      s_axi_bvalid,
  input  logic                      s_axi_bready,

  // Read address channel
  input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
  input  logic [2:0]                s_axi_arprot,  // unused
  input  logic                      s_axi_arvalid,
  output logic                      s_axi_arready,

  // Read data channel
  output logic [31:0]               s_axi_rdata,
  output logic [1:0]                s_axi_rresp,
  output logic                      s_axi_rvalid,
  input  logic                      s_axi_rready,

  // Register contents (s_axi_aclk domain)
  output logic [31:0]               phase_word,
  output logic [31:0]               start_phase
);

  localparam int                   WORD_BITS       = AXI_ADDR_WIDTH - 2;
  localparam logic [WORD_BITS-1:0] PHASE_WORD_IDX  = 0;
  localparam logic [WORD_BITS-1:0] START_PHASE_IDX = 1;

  //----------------------------------------------------------------
  // Write path
  //
  // AW and W are each captured into a holding register as soon as
  // they arrive. Once both are held and the B channel is free, the
  // register is updated and BVALID is raised in the same cycle.
  //----------------------------------------------------------------

  logic                 aw_held;
  logic                 w_held;
  logic [WORD_BITS-1:0] aw_word;
  logic [31:0]          w_data;
  logic [3:0]           w_strb;
  logic                 write_go;

  assign s_axi_awready = ~aw_held;
  assign s_axi_wready  = ~w_held;
  assign s_axi_bresp   = 2'b00;  // OKAY
  assign write_go      = aw_held & w_held & (~s_axi_bvalid | s_axi_bready);

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      aw_held      <= 1'b0;
      w_held       <= 1'b0;
      s_axi_bvalid <= 1'b0;
    end else begin
      if (s_axi_awvalid && s_axi_awready) begin
        aw_held <= 1'b1;
      end
      if (s_axi_wvalid && s_axi_wready) begin
        w_held <= 1'b1;
      end
      if (write_go) begin
        aw_held      <= 1'b0;
        w_held       <= 1'b0;
        s_axi_bvalid <= 1'b1;
      end else if (s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end
    end
  end

  always_ff @(posedge s_axi_aclk) begin
    if (s_axi_awvalid && s_axi_awready) begin
      aw_word <= s_axi_awaddr[AXI_ADDR_WIDTH-1:2];
    end
    if (s_axi_wvalid && s_axi_wready) begin
      w_data <= s_axi_wdata;
      w_strb <= s_axi_wstrb;
    end
  end

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      phase_word  <= RESET_PHASE_WORD;
      start_phase <= RESET_START_PHASE;
    end else if (write_go) begin
      for (int i = 0; i < 4; i++) begin
        if (w_strb[i]) begin
          if (aw_word == PHASE_WORD_IDX)  phase_word [8*i +: 8] <= w_data[8*i +: 8];
          if (aw_word == START_PHASE_IDX) start_phase[8*i +: 8] <= w_data[8*i +: 8];
        end
      end
    end
  end

  //----------------------------------------------------------------
  // Read path
  //
  // An AR is accepted whenever no read response is pending; the data
  // is registered with the handshake and held until RREADY.
  //----------------------------------------------------------------

  assign s_axi_arready = ~s_axi_rvalid;
  assign s_axi_rresp   = 2'b00;  // OKAY

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      s_axi_rvalid <= 1'b0;
    end else if (s_axi_arvalid && s_axi_arready) begin
      s_axi_rvalid <= 1'b1;
    end else if (s_axi_rready) begin
      s_axi_rvalid <= 1'b0;
    end
  end

  always_ff @(posedge s_axi_aclk) begin
    if (s_axi_arvalid && s_axi_arready) begin
      case (s_axi_araddr[AXI_ADDR_WIDTH-1:2])
        PHASE_WORD_IDX:  s_axi_rdata <= phase_word;
        START_PHASE_IDX: s_axi_rdata <= start_phase;
        default:         s_axi_rdata <= '0;
      endcase
    end
  end

endmodule

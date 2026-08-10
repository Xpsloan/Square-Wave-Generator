`timescale 1ns/1ps
//==================================================================
// DWDBS_system
//
// Direct-digital-synthesis (DDS) square-wave generator.
//
// Two phase accumulators run in parallel - one clocked on the
// posedge of clk_slw, one on the posedge of qclk_slw (i.e. a 90
// degree phase shift from clk_slw) - each producing two samples
// per clk_slw cycle. Those samples are handed to a pair of
// shift registers/pointers that feed a DDR output (ODDR), clocked
// by clk_spd, to produce a square wave whose period is set by
// `phase_change`.
//
// Clocking assumption: clk_spd, clk_slw, and qclk_slw must all be
// derived from the same clock source with a fixed, known phase
// relationship (e.g. outputs of a single MMCM/PLL). The reset
// synchronization below relies on that relationship - it is NOT
// safe if these clocks are asynchronous to one another.
//==================================================================

module DWDBS_system #(
  parameter int ACCUMULATOR_WIDTH = 32
)(
  input  logic clk_spd,        // fast clock, 2x clk_slw; clocks the ODDR/pointer (600 MHz-class) domain
  input  logic clk_slw,        // slow clock; posedge-domain phase accumulator (300 MHz-class)
  input  logic qclk_slw,       // same speed as clk_slw, 90 deg shifted; quadrature-domain phase accumulator

  input  logic reset,          // async input, resets phase accumulators and sample pointers
  input  logic enable,         // active-low elsewhere in the design; drives ODDR reset directly
                                // (R asserted => Q held low), so enable=0 => running, enable=1 => held low
  input  logic [ACCUMULATOR_WIDTH-1:0] dither,

  input  logic [ACCUMULATOR_WIDTH-1:0] phase_change,
  output logic dirty_swo_p,
  output logic dirty_swo_n
);

  //----------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------

  // clk_slw posedge-domain phase accumulator + samples
  logic [ACCUMULATOR_WIDTH-1:0]   pos_phase_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   pos_sample0_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   pos_sample1_accum;
  logic [1:0]                     pos_next_bits;
  (* keep = "true" *) logic [1:0] pos_shift_reg;

  // qclk_slw (quadrature) domain phase accumulator + samples
  logic [ACCUMULATOR_WIDTH-1:0]   neg_phase_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   neg_sample0_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   neg_sample1_accum;
  logic [1:0]                     neg_next_bits;
  (* keep = "true" *) logic [1:0] neg_shift_reg;

  // clk_spd domain pointers/data
  (* keep = "true" *) logic pos_pointer;
  (* keep = "true" *) logic neg_pointer;
  (* keep = "true" *) logic pos_ddr_data;
  (* keep = "true" *) logic neg_ddr_data;

  // Locally-registered (single-flop-deep) reset signals.
  // These are what let async accum_reset/pointer_reset meet timing
  // easily downstream: fan-out is high, but logic depth is ~0.
  (* keep = "true" *) logic full_sync_accum_reset;
  (* keep = "true" *) logic pos_sync_reset;
  (* keep = "true" *) logic neg_sync_reset; // to match pos_sync_reset

  // ODDR logic
  logic oddr_out;


  //----------------------------------------------------------------
  // Reset synchronization
  //
  // The single `reset` input is captured locally, one flop deep,
  // in each domain that consumes it - this is what keeps these
  // paths trivial to close timing on (high fan-out, ~0 logic
  // depth) despite `reset` itself being async.
  //
  // full_sync_accum_reset is captured on qclk_slw, half a clk_slw
  // period ahead of clk_slw's next posedge, so it is already
  // stable and available to BOTH the clk_slw and qclk_slw
  // accumulator blocks below.
  //
  // neg_sync_reset reuses full_sync_accum_reset directly (no
  // separate flop) since it needs exactly the same qclk_slw-
  // registered value that full_sync_accum_reset already provides.
  //----------------------------------------------------------------

  always_ff @(posedge qclk_slw) begin
    full_sync_accum_reset <= reset;
  end

  always_ff @(posedge qclk_slw) begin
    neg_sync_reset <= reset;
  end

  always_ff @(posedge clk_slw) begin
    pos_sync_reset <= reset;
  end

  //----------------------------------------------------------------
  // clk_slw posedge domain
  // Computes the next two clk_spd-domain positive-edge samples.
  //----------------------------------------------------------------

  always_ff @(posedge clk_slw) begin
    if (full_sync_accum_reset) begin
      pos_phase_accum   <= '0;
      pos_sample0_accum <= '0;
      pos_sample1_accum <= '0;
      pos_next_bits     <= 2'b00;
      pos_shift_reg     <= 2'b00;
    end else begin
      pos_sample0_accum <= pos_phase_accum;
      pos_sample1_accum <= pos_phase_accum + (phase_change << 1);
      pos_phase_accum   <= pos_phase_accum + (phase_change << 2) + dither;

      pos_next_bits <= {
        pos_sample1_accum[ACCUMULATOR_WIDTH-1],
        pos_sample0_accum[ACCUMULATOR_WIDTH-1]
      };

      pos_shift_reg <= pos_next_bits; // extra stage to break up logic depth
    end
  end


  //----------------------------------------------------------------
  // qclk_slw domain
  // Computes the next two clk_spd-domain negative-edge samples.
  //----------------------------------------------------------------

  always_ff @(posedge qclk_slw) begin
    if (full_sync_accum_reset) begin
      neg_phase_accum   <= phase_change;
      neg_sample0_accum <= '0;
      neg_sample1_accum <= '0;
      neg_next_bits     <= 2'b00;
      neg_shift_reg     <= 2'b00;
    end else begin
      neg_sample0_accum <= neg_phase_accum;
      neg_sample1_accum <= neg_phase_accum + (phase_change << 1);
      neg_phase_accum   <= neg_phase_accum + (phase_change << 2) + dither;

      neg_next_bits <= {
        neg_sample1_accum[ACCUMULATOR_WIDTH-1],
        neg_sample0_accum[ACCUMULATOR_WIDTH-1]
      };

      neg_shift_reg <= neg_next_bits;
    end
  end


  //----------------------------------------------------------------
  // clk_spd posedge domain
  // Load and shift positive ODDR data.
  //----------------------------------------------------------------

  logic pos_pointer_d;
  assign pos_pointer_d = pos_sync_reset ? 1'b0 : ~pos_pointer;

  (* keep = "true" *)
  FDRE #(.INIT(1'b0)) pos_pointer_reg (
    .C  (clk_spd),
    .CE (1'b1),
    .R  (1'b0),       // hard-tied to GND - nothing for synthesis to absorb
    .D  (pos_pointer_d),
    .Q  (pos_pointer)
  );

  always_ff @(posedge clk_spd) begin
    pos_ddr_data <= pos_shift_reg[pos_pointer];
  end


  //----------------------------------------------------------------
  // clk_spd negedge domain
  // Load and shift negative ODDR data.
  //----------------------------------------------------------------

  logic neg_pointer_d;
  assign neg_pointer_d = neg_sync_reset ? 1'b0 : ~neg_pointer;

  (* keep = "true" *)
  FDRE #(.INIT(1'b0)) neg_pointer_reg (
    .C  (~clk_spd),   // negedge behavior via inverted clock, same as always_ff @(negedge clk_spd)
    .CE (1'b1),
    .R  (1'b0),       // hard-tied to GND - nothing for synthesis to absorb
    .D  (neg_pointer_d),
    .Q  (neg_pointer)
  );

  always_ff @(negedge clk_spd) begin
    neg_ddr_data <= neg_shift_reg[neg_pointer];
  end


  //----------------------------------------------------------------
  // ODDR output
  //
  // Note: `enable` is wired to the ODDR reset (R) pin, not a clock
  // enable. When enable = 0, R is asserted and Q is held at 0;
  // when enable = 1, R is deasserted and normal DDR operation
  // proceeds. This is intentional but worth a comment since "R"
  // reads as "reset" rather than "enable" at the instantiation site.
  //----------------------------------------------------------------

  ODDR #(
    .DDR_CLK_EDGE ("OPPOSITE_EDGE"),
    .INIT         (1'b0),
    .SRTYPE       ("ASYNC")
  ) ODDR_inst (
    .Q  (oddr_out),
    .C  (clk_spd),
    .CE (1'b1),
    .D1 (pos_ddr_data),
    .D2 (neg_ddr_data),
    .R  (enable),     // active-low-style enable via reset pin (see note above)
    .S  (1'b0)
  );


  //----------------------------------------------------------------
  // Differential output buffer
  //----------------------------------------------------------------

  OBUFDS obufds_init_0 (
    .I  (oddr_out),
    .O  (dirty_swo_p),
    .OB (dirty_swo_n)
  );

endmodule
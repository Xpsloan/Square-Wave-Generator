`timescale 1ns/1ps
//==================================================================
// DWDBS_system
//
// Direct-digital-synthesis (DDS) square-wave generator.
//
// Two phase accumulators run in parallel - one clocked on the
// posedge of clk_slow, one on the posedge of qclk_slow (i.e. a 90
// degree phase shift from clk_slow) - each producing two samples
// per clk_slow cycle. Those samples are handed to a pair of
// shift registers/pointers that feed a DDR output (ODDR), clocked
// by clk_quick, to produce a square wave whose period is set by
// `phase_change`.
//
// Clocking assumption: clk_quick, clk_slow, and qclk_slow must all
// be derived from the same clock source with a fixed, known phase
// relationship (e.g. outputs of a single MMCM/PLL). The reset
// synchronization below relies on that relationship - it is NOT
// safe if these clocks are asynchronous to one another.
//==================================================================

module SIM_DWDBS_system #(
  parameter int ACCUMULATOR_WIDTH = 32
)(
  input  logic clk_quick,       // fast clock, 2x clk_slow; clocks the ODDR/pointer (600 MHz-class) domain
  input  logic clk_slow,        // slow clock; posedge-domain phase accumulator (300 MHz-class)
  input  logic qclk_slow,       // same speed as clk_slow, 90 deg shifted; quadrature-domain phase accumulator

  input  logic sw_reset,         // async input, resets phase accumulators and sample pointers
  input  logic oddr_reset,       // async input, resets the ODDR output stage (R pin) directly;
                                  // caller combines whatever reset sources should hold the
                                  // output low (system reset, button-press reset, enable, ...)
                                  // into this single signal
  input  logic [ACCUMULATOR_WIDTH-1:0] phase_change,
  input  logic [ACCUMULATOR_WIDTH-1:0] start_phase,

  output logic dirty_sw
);

  //----------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------

  // clk_slow posedge-domain phase accumulator + samples
  logic [ACCUMULATOR_WIDTH-1:0]   pos_phase_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   pos_sample0_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   pos_sample1_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   pos_phase_change;
  logic [1:0]                     pos_delayed;
  logic [1:0]                     pos_next_bits;
  (* keep = "true" *) logic [1:0] pos_shift_reg;

  // qclk_slow (quadrature) domain phase accumulator + samples
  logic [ACCUMULATOR_WIDTH-1:0]   neg_phase_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   neg_sample0_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   neg_sample1_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   neg_phase_change;
  logic [1:0]                     neg_delayed;
  logic [1:0]                     neg_next_bits;
  (* keep = "true" *) logic [1:0] neg_shift_reg;

  // clk_quick domain pointers/data
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


  //----------------------------------------------------------------
  // Reset synchronization
  //
  // The single `reset` input is captured locally, one flop deep,
  // in each domain that consumes it - this is what keeps these
  // paths trivial to close timing on (high fan-out, ~0 logic
  // depth) despite `reset` itself being async.
  //
  // full_sync_accum_reset is captured on qclk_slow, half a clk_slow
  // period ahead of clk_slow's next posedge, so it is already
  // stable and available to BOTH the clk_slow and qclk_slow
  // accumulator blocks below.
  //
  // neg_sync_reset reuses full_sync_accum_reset directly (no
  // separate flop) since it needs exactly the same qclk_slow-
  // registered value that full_sync_accum_reset already provides.
  //----------------------------------------------------------------

  always_ff @(posedge qclk_slow) begin
    full_sync_accum_reset <= sw_reset;
  end

  always_ff @(posedge qclk_slow) begin
    neg_sync_reset <= sw_reset;
  end

  always_ff @(posedge clk_slow) begin
    pos_sync_reset <= sw_reset;
  end

  //----------------------------------------------------------------
  // clk_slow posedge domain
  // Computes the next two clk_quick-domain positive-edge samples.
  //----------------------------------------------------------------

  always_ff @(posedge clk_slow) begin
    if (full_sync_accum_reset) begin
      pos_phase_accum   <= start_phase;
      pos_phase_change  <= phase_change;
      pos_sample0_accum <= '0;
      pos_sample1_accum <= '0;
      pos_next_bits     <= 2'b00;
      pos_delayed       <= 2'b00;
      pos_shift_reg     <= 2'b00;
    end else begin
      pos_sample0_accum <= pos_phase_accum;
      pos_sample1_accum <= pos_phase_accum + (pos_phase_change << 1);
      pos_phase_accum   <= pos_phase_accum + (pos_phase_change << 2);

      pos_next_bits <= {
        pos_sample1_accum[ACCUMULATOR_WIDTH-1],
        pos_sample0_accum[ACCUMULATOR_WIDTH-1]
      };

      pos_delayed   <= pos_next_bits;
      pos_shift_reg <= pos_delayed; // extra stage to break up logic depth
    end
  end


  //----------------------------------------------------------------
  // qclk_slow domain
  // Computes the next two clk_quick-domain negative-edge samples.
  //----------------------------------------------------------------

  always_ff @(posedge qclk_slow) begin
    if (full_sync_accum_reset) begin
      neg_phase_accum   <= start_phase + phase_change;
      neg_phase_change  <= phase_change;
      neg_sample0_accum <= '0;
      neg_sample1_accum <= '0;
      neg_next_bits     <= 2'b00;
      neg_delayed       <= 2'b00;
      neg_shift_reg     <= 2'b00;
    end else begin
      neg_sample0_accum <= neg_phase_accum;
      neg_sample1_accum <= neg_phase_accum + (neg_phase_change << 1);
      neg_phase_accum   <= neg_phase_accum + (neg_phase_change << 2);

      neg_next_bits <= {
        neg_sample1_accum[ACCUMULATOR_WIDTH-1],
        neg_sample0_accum[ACCUMULATOR_WIDTH-1]
      };
      
      neg_delayed   <= neg_next_bits;
      neg_shift_reg <= neg_delayed;
    end
  end


  //----------------------------------------------------------------
  // clk_quick posedge domain
  // Load and shift positive ODDR data.
  //----------------------------------------------------------------

  logic pos_pointer_d;
  assign pos_pointer_d = pos_sync_reset ? 1'b0 : ~pos_pointer;

  (* keep = "true" *)
  FDRE #(.INIT(1'b0)) pos_pointer_reg (
    .C  (clk_quick),
    .CE (1'b1),
    .R  (1'b0),       // hard-tied to GND - nothing for synthesis to absorb
    .D  (pos_pointer_d),
    .Q  (pos_pointer)
  );

  always_ff @(posedge clk_quick) begin
    pos_ddr_data <= pos_shift_reg[pos_pointer];
  end


  //----------------------------------------------------------------
  // clk_quick negedge domain
  // Load and shift negative ODDR data.
  //----------------------------------------------------------------

  logic neg_pointer_d;
  assign neg_pointer_d = neg_sync_reset ? 1'b0 : ~neg_pointer;

  (* keep = "true" *)
  FDRE #(.INIT(1'b0)) neg_pointer_reg (
    .C  (~clk_quick),   // negedge behavior via inverted clock, same as always_ff @(negedge clk_quick)
    .CE (1'b1),
    .R  (1'b0),       // hard-tied to GND - nothing for synthesis to absorb
    .D  (neg_pointer_d),
    .Q  (neg_pointer)
  );

  always_ff @(negedge clk_quick) begin
    neg_ddr_data <= neg_shift_reg[neg_pointer];
  end


  //----------------------------------------------------------------
  // ODDR output
  //
  // `oddr_reset` is wired directly to the ODDR reset (R) pin. When
  // oddr_reset = 1, R is asserted and Q is held at 0; when
  // oddr_reset = 0, R is deasserted and normal DDR operation
  // proceeds.
  //----------------------------------------------------------------

  ODDR #(
    .DDR_CLK_EDGE ("OPPOSITE_EDGE"),
    .INIT         (1'b0),
    .SRTYPE       ("ASYNC")
  ) ODDR_inst (
    .Q  (dirty_sw),
    .C  (clk_quick),
    .CE (1'b1),
    .D1 (pos_ddr_data),
    .D2 (neg_ddr_data),
    .R  (oddr_reset),
    .S  (1'b0)
  );


endmodule
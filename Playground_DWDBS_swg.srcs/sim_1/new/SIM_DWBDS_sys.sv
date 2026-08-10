`timescale 1ns/1ps
//==================================================================
// DWDBS_system
//
// Direct-digital-synthesis (DDS) square-wave generator.
//
// Two phase accumulators run in parallel - one clocked on the
// posedge of clk_300, one on the posedge of qclk_300 (i.e. the
// negedge of the same 300 MHz clock) - each producing two 600 MHz
// sample bits per 300 MHz cycle. Those bits are handed to a pair
// of 600 MHz shift registers/pointers that feed a soft ODDR
// (behavioral, sim-only) to produce a 600 MHz-class square wave
// whose period is set by `phase_change`.
//
// Clocking assumption: clk_300, qclk_300, and clk_600 must all be
// derived from the same clock source with a fixed, known phase
// relationship (e.g. outputs of a single MMCM/PLL). The reset
// synchronization below relies on that relationship - it is NOT
// safe if these clocks are asynchronous to one another.
//==================================================================

module SIM_DWDBS_sys #(
  parameter int ACCUMULATOR_WIDTH = 32
)(
  input  logic clk_300,        // 300 MHz, posedge domain
  input  logic qclk_300,       // 300 MHz, 90 deg from clk_300 (negedge domain)
  input  logic clk_600,        // 600 MHz, phase-locked to clk_300/qclk_300
  input  logic reset,          // async input, resets phase accumulators and 600 MHz sample pointers
  input  logic [ACCUMULATOR_WIDTH-1:0] phase_change,
  output logic [ACCUMULATOR_WIDTH-1:0] DDS_out
);

  //----------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------

  // 300 MHz posedge-domain phase accumulator + samples
  logic [ACCUMULATOR_WIDTH-1:0]   pos_phase_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   pos_sample0_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   pos_sample1_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   pos_next_bits [1:0];
  (* keep = "true" *) logic [ACCUMULATOR_WIDTH-1:0] pos_shift_reg [1:0];

  // 300 MHz negedge-domain (qclk_300) phase accumulator + samples
  logic [ACCUMULATOR_WIDTH-1:0]   neg_phase_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   neg_sample0_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   neg_sample1_accum;
  logic [ACCUMULATOR_WIDTH-1:0]   neg_next_bits [1:0];
  (* keep = "true" *) logic [ACCUMULATOR_WIDTH-1:0] neg_shift_reg [1:0];

  // 600 MHz domain pointers/data
  (* keep = "true" *) logic pos_pointer;
  (* keep = "true" *) logic neg_pointer;
  (* keep = "true" *) logic [ACCUMULATOR_WIDTH-1:0] pos_ddr_data;
  (* keep = "true" *) logic [ACCUMULATOR_WIDTH-1:0] neg_ddr_data;

  // Locally-registered (single-flop-deep) reset signals.
  // These are what let async accum_reset/pointer_reset meet timing
  // easily downstream: fan-out is high, but logic depth is ~0.
  (* keep = "true" *) logic full_sync_accum_reset;
  (* keep = "true" *) logic pos_sync_reset;
  (* keep = "true" *) logic neg_sync_reset; // to match pos_sync_reset

  // Dither logic
  (* keep = "true" *) logic [ACCUMULATOR_WIDTH-1:0] dither;

  //----------------------------------------------------------------
  // Reset synchronization
  //
  // The single `reset` input is captured locally, one flop deep,
  // in each domain that consumes it - this is what keeps these
  // paths trivial to close timing on (high fan-out, ~0 logic
  // depth) despite `reset` itself being async.
  //
  // full_sync_accum_reset is captured on qclk_300, half a 300 MHz
  // period ahead of clk_300's next posedge, so it is already
  // stable and available to BOTH the clk_300 and qclk_300
  // accumulator blocks below.
  //
  // neg_sync_reset reuses full_sync_accum_reset directly (no
  // separate flop) since it needs exactly the same qclk_300-
  // registered value that full_sync_accum_reset already provides.
  //----------------------------------------------------------------

  always_ff @(posedge qclk_300) begin
    full_sync_accum_reset <= reset;
  end

  always_ff @(posedge qclk_300) begin
    neg_sync_reset <= reset;
  end

  always_ff @(posedge clk_300) begin
    pos_sync_reset <= reset;
  end

  //----------------------------------------------------------------
  // 300 MHz posedge domain
  // Computes the next two 600 MHz positive-edge samples.
  //----------------------------------------------------------------

  always_ff @(posedge clk_300) begin
    if (full_sync_accum_reset) begin
      pos_phase_accum          <= '0;
      pos_sample0_accum        <= '0;
      pos_sample1_accum        <= '0;
      pos_next_bits[0]         <= '0;
      pos_next_bits[1]         <= '0;
      pos_shift_reg[0]         <= '0;
      pos_shift_reg[1]         <= '0;
    end else begin
      pos_sample0_accum        <= pos_phase_accum;
      pos_sample1_accum        <= pos_phase_accum + (phase_change << 1);
      pos_phase_accum          <= pos_phase_accum + (phase_change << 2);

      pos_next_bits <= {
        pos_sample1_accum,
        pos_sample0_accum
      };

      pos_shift_reg <= pos_next_bits; // extra stage to break up logic depth
    end
  end


  //----------------------------------------------------------------
  // 300 MHz negedge domain (qclk_300)
  // Computes the next two 600 MHz negative-edge samples.
  //
  // neg_phase_accum resets to `phase_change` (not '0') so that this
  // domain's samples land exactly one phase_change step ahead of
  // the pos domain's - interleaving the two domains into a single
  // evenly-spaced 600 MHz sample stream (pos: 0, 2, 4...; neg: 1, 3,
  // 5... in units of phase_change).
  //----------------------------------------------------------------

  always_ff @(posedge qclk_300) begin
    if (full_sync_accum_reset) begin
      neg_phase_accum          <= phase_change;
      neg_sample0_accum        <= '0;
      neg_sample1_accum        <= '0;
      neg_next_bits[0]         <= '0;
      neg_next_bits[1]         <= '0;
      neg_shift_reg[0]         <= '0;
      neg_shift_reg[1]         <= '0;
    end else begin
      neg_sample0_accum        <= neg_phase_accum;
      neg_sample1_accum        <= neg_phase_accum + (phase_change << 1);
      neg_phase_accum          <= neg_phase_accum + (phase_change << 2);

      neg_next_bits <= {
        neg_sample1_accum,
        neg_sample0_accum
      };

      neg_shift_reg <= neg_next_bits; // extra stage to break up logic depth, mirrors pos side
    end
  end


  //----------------------------------------------------------------
  // 600 MHz posedge domain
  // Load and shift positive ODDR data.
  //----------------------------------------------------------------

  logic pos_pointer_d;
  assign pos_pointer_d = pos_sync_reset ? 1'b0 : ~pos_pointer;

  (* keep = "true" *)
  FDRE #(.INIT(1'b0)) pos_pointer_reg (
    .C  (clk_600),
    .CE (1'b1),
    .R  (1'b0),       // hard-tied to GND - nothing for synthesis to absorb
    .D  (pos_pointer_d),
    .Q  (pos_pointer)
  );

  always_ff @(posedge clk_600) begin
    pos_ddr_data <= pos_shift_reg[pos_pointer];
  end


  //----------------------------------------------------------------
  // 600 MHz negedge domain
  // Load and shift negative ODDR data.
  //----------------------------------------------------------------

  logic neg_pointer_d;
  assign neg_pointer_d = neg_sync_reset ? 1'b0 : ~neg_pointer;

  (* keep = "true" *)
  FDRE #(.INIT(1'b0)) neg_pointer_reg (
    .C  (~clk_600),   // negedge behavior via inverted clock
    .CE (1'b1),
    .R  (1'b0),       // hard-tied to GND - nothing for synthesis to absorb
    .D  (neg_pointer_d),
    .Q  (neg_pointer)
  );

  always_ff @(negedge clk_600) begin
    neg_ddr_data <= neg_shift_reg[neg_pointer];
  end


  //----------------------------------------------------------------
  // SOFT (behavioral) ODDR FOR SIMULATION
  //
  // Models a real ODDR primitive: DDS_out is updated with
  // pos_ddr_data on every posedge of clk_600, and with neg_ddr_data
  // on every negedge of clk_600. Two edge-triggered blocks driving
  // the same reg is safe here because clk_600's posedge and negedge
  // never coincide in simulation time.
  //----------------------------------------------------------------

  always_comb begin
    if (clk_600) begin
      DDS_out = pos_ddr_data;
    end else begin
      DDS_out = neg_ddr_data;
    end
  end

endmodule
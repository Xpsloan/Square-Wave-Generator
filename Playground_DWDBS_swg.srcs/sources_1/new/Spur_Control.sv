`timescale 1ns / 1ps
//==================================================================
// Spur_Control
//
// TPDN (triangular probability density) dither generator for the
// DWDBS phase accumulator.
//
// Two independent maximal-length 32-bit LFSRs are summed to form
// triangular-distributed noise, truncated/re-centered to a
// runtime-selectable width (dither_width), sign-extended back up
// to ACCUMULATOR_WIDTH, then shifted into position (dither_shift)
// before being added into the phase accumulator each cycle. This
// randomizes the accumulator's truncation error and pushes DDS
// spurs down into the noise floor instead of concentrating them
// at discrete tones.
//
// dither_width == 0 is treated as "dithering off": dither is held
// at zero regardless of dither_shift. (See Dither_Control, which
// drives dither_width/dither_shift from board buttons and keeps
// dither_width at 0 by default.)
//
// Pipelining: dither_width/dither_shift arrive combinationally from
// Dither_Control (a different module), and computing dither from
// them chains three separate variable-width shifts (the LFSR mask,
// the sign-extend, and the position shift). Chaining all of that in
// one cycle was the long pole for timing closure, so it's broken
// into four registered stages below (_p0.._p2 pipeline copies of
// dither_width/dither_shift, one register per shift). This adds a
// few fixed cycles of latency to the noise sequence, which doesn't
// matter functionally - dither_width/dither_shift themselves only
// ever change on debounced button presses, many orders of magnitude
// slower than this pipeline.
//==================================================================

module Spur_Control #(
  parameter int ACCUMULATOR_WIDTH = 32,
  parameter int MAX_DITHER_WIDTH  = 9    // compile-time upper bound on dither_width
)(
  input  logic                                   qclk_slw,
  input  logic                                   reset,
  input  logic [$clog2(MAX_DITHER_WIDTH+1)-1:0]  dither_width,  // runtime, <= MAX_DITHER_WIDTH; 0 = off
  input  logic [$clog2(ACCUMULATOR_WIDTH)-1:0]   dither_shift,  // runtime bit position
  output logic [ACCUMULATOR_WIDTH-1:0]           dither
);

  localparam int DITHER_WIDTH_BITS = $clog2(MAX_DITHER_WIDTH+1);
  localparam int DITHER_SHIFT_BITS = $clog2(ACCUMULATOR_WIDTH);
  localparam int MAX_UNIT_WIDTH    = MAX_DITHER_WIDTH - 1;

  //----------------------------------------------------------------
  // Two independent maximal-length LFSRs
  //----------------------------------------------------------------

  logic [31:0] lfsr_a, lfsr_b;
  logic        fb_a, fb_b;

  assign fb_a = lfsr_a[31] ^ lfsr_a[21] ^ lfsr_a[1] ^ lfsr_a[0];
  assign fb_b = lfsr_b[31] ^ lfsr_b[27] ^ lfsr_b[2] ^ lfsr_b[0];

  always_ff @(posedge qclk_slw) begin
    if (reset) begin
      lfsr_a <= 32'h1;
      lfsr_b <= 32'hACE1;
    end else begin
      lfsr_a <= {lfsr_a[30:0], fb_a};
      lfsr_b <= {lfsr_b[30:0], fb_b};
    end
  end

  //----------------------------------------------------------------
  // Pipeline stage 0: register dither_width/dither_shift right at
  // the module boundary. This turns the cross-module path from
  // Dither_Control's registers into its own timing stage instead of
  // letting it ride combinationally into the barrel-shift logic
  // below within the same cycle.
  //----------------------------------------------------------------

  logic [DITHER_WIDTH_BITS-1:0] dither_width_p0;
  logic [DITHER_SHIFT_BITS-1:0] dither_shift_p0;

  always_ff @(posedge qclk_slw) begin
    if (reset) begin
      dither_width_p0 <= '0;
      dither_shift_p0 <= '0;
    end else begin
      dither_width_p0 <= dither_width;
      dither_shift_p0 <= dither_shift;
    end
  end

  //----------------------------------------------------------------
  // Pipeline stage 1: mask each LFSR down to unit_width bits
  // (variable-width mask via shift, not replication), sum and
  // recenter to zero mean, and register the result as tri_sum.
  //----------------------------------------------------------------

  logic [DITHER_WIDTH_BITS-1:0] unit_width;
  assign unit_width = dither_width_p0 - 1'b1;   // valid only if dither_width_p0 >= 1

  logic [MAX_UNIT_WIDTH-1:0] mask_a, mask_b;

  always_comb begin
    mask_a = lfsr_a[MAX_UNIT_WIDTH-1:0] & ({MAX_UNIT_WIDTH{1'b1}} >> (MAX_UNIT_WIDTH - unit_width));
    mask_b = lfsr_b[MAX_UNIT_WIDTH-1:0] & ({MAX_UNIT_WIDTH{1'b1}} >> (MAX_UNIT_WIDTH - unit_width));
  end

  logic signed [MAX_DITHER_WIDTH-1:0] tri_sum;
  logic [DITHER_WIDTH_BITS-1:0]       dither_width_p1;
  logic [DITHER_SHIFT_BITS-1:0]       dither_shift_p1;

  always_ff @(posedge qclk_slw) begin
    if (reset) begin
      tri_sum         <= '0;
      dither_width_p1 <= '0;
      dither_shift_p1 <= '0;
    end else begin
      tri_sum <= signed'({1'b0, mask_a}) + signed'({1'b0, mask_b})
               - (1 <<< (unit_width - 1'b1));  // recenter to zero mean
      dither_width_p1 <= dither_width_p0;
      dither_shift_p1 <= dither_shift_p0;
    end
  end

  //----------------------------------------------------------------
  // Pipeline stage 2: sign-extend the dither_width-significant
  // result up to MAX_DITHER_WIDTH using the shift-left-then-
  // arithmetic-shift-right trick, and register it as its own stage
  // so it isn't chained with the position shift below.
  //----------------------------------------------------------------

  logic signed [MAX_DITHER_WIDTH-1:0] tri_noise_full;
  assign tri_noise_full = (tri_sum <<< (MAX_DITHER_WIDTH - dither_width_p1))
                                    >>> (MAX_DITHER_WIDTH - dither_width_p1);

  logic signed [MAX_DITHER_WIDTH-1:0] tri_noise_full_p2;
  logic [DITHER_WIDTH_BITS-1:0]       dither_width_p2;
  logic [DITHER_SHIFT_BITS-1:0]       dither_shift_p2;

  always_ff @(posedge qclk_slw) begin
    if (reset) begin
      tri_noise_full_p2 <= '0;
      dither_width_p2   <= '0;
      dither_shift_p2   <= '0;
    end else begin
      tri_noise_full_p2 <= tri_noise_full;
      dither_width_p2   <= dither_width_p1;
      dither_shift_p2   <= dither_shift_p1;
    end
  end

  //----------------------------------------------------------------
  // Pipeline stage 3: sign-extend to accumulator width, position via
  // the (now isolated) variable shift, and register the final
  // result. dither_width_p2 == 0 forces dither to 0 (dithering off).
  //----------------------------------------------------------------

  logic signed [ACCUMULATOR_WIDTH-1:0] tri_noise_accum_w;
  assign tri_noise_accum_w = ACCUMULATOR_WIDTH'(tri_noise_full_p2);  // sign-extends (signed source)

  logic dither_active_p2;
  assign dither_active_p2 = (dither_width_p2 != '0);

  always_ff @(posedge qclk_slw) begin
    if (reset || ~dither_active_p2) dither <= '0;
    else                            dither <= tri_noise_accum_w <<< dither_shift_p2;
  end

endmodule

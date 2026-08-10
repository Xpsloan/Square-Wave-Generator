`timescale 1ns / 1ps
//==================================================================
// Square_Wave_Generator
//
// Top-level DWDBS square-wave generator. This is the main engine
// of the design: it produces the DWDBS output square wave, adds
// TPDN dither to it to push spurs down into the noise floor, and
// manages the round-trip of that signal off-chip and back:
//
//   1. dither_width/dither_shift come in directly as inputs
//      (see Dither_Control, instantiated by the caller, which
//      derives a saturating setting from the board buttons).
//      dither_width == 0 means dithering is off.
//   2. Spur_Control turns that dither_width/dither_shift into
//      actual dither and feeds it to DWDBS_system.
//   3. DWDBS_system runs the DDS phase accumulators + ODDR and
//      drives the "dirty" (raw, un-cleaned) square wave out on
//      dirty_swo_p/n, through an OBUFDS.
//   4. Off-chip, dirty_swo_p/n is routed out through the FMC
//      connector and looped back in on dirty_swi_p/n.
//   5. dirty_swi_p/n is re-captured on-chip via IBUFDS/BUFG and:
//        - passed straight through as dirty_swo, for anyone who
//          wants the raw (un-cleaned) signal, and
//        - fed into a jitter cleaner (clock_cleaner, an MMCM-based
//          block) to produce clean_swo, a jitter-cleaned version
//          of the same signal for use elsewhere in the design.
//
// The FMC round-trip exists because the DWDBS output needs to pass
// through the board's physical clock-cleaner path rather than stay
// entirely on-chip.
//==================================================================

module Square_Wave_Generator #(
  parameter int ACCUMULATOR_WIDTH = 32,
  parameter int MAX_DITHER_WIDTH  = 9
)(
  // For the DWDBS system
  input  logic clk_spd,        // fast clock that runs 2x the speed of clk_slw
  input  logic clk_slw,        // slow clock that runs 1/2 the speed of clk_spd
  input  logic qclk_slw,       // same speed as clk_slw but 90 degree phase shift

  input  logic reset,          // async input, resets phase accumulators
  input  logic enable,         // active-low elsewhere in the design; drives ODDR reset directly
                                // (R asserted => Q held low), so enable=0 => running, enable=1 => held low

  // Dither setting, saturating (see Dither_Control at the caller).
  // dither_width == 0 means dithering is off.
  input  logic [$clog2(MAX_DITHER_WIDTH+1)-1:0] dither_width,
  input  logic [$clog2(ACCUMULATOR_WIDTH)-1:0]  dither_shift,

  input  logic [ACCUMULATOR_WIDTH-1:0] phase_change,

  // DWDBS "dirty" output, routed off-chip through the FMC connector
  output logic dirty_swo_p,
  output logic dirty_swo_n,

  // Same signal, looped back in from the FMC connector
  input  logic dirty_swi_p,
  input  logic dirty_swi_n,

  // Recovered outputs for use elsewhere in the design
  output logic clean_swo,      // jitter-cleaned, via the on-board clock cleaner
  output logic dirty_swo,      // raw/uncleaned pass-through

  // Status: high whenever dither_width != 0 (i.e. dithering is on)
  output logic dither_active
);

  //----------------------------------------------------------------
  // dither_active status
  //----------------------------------------------------------------

  assign dither_active = (dither_width != '0);

  //----------------------------------------------------------------
  // Dither generation
  //----------------------------------------------------------------

  logic [ACCUMULATOR_WIDTH-1:0] dither;

  Spur_Control #(
    .ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH),
    .MAX_DITHER_WIDTH  (MAX_DITHER_WIDTH)
  ) spur_controller (
    .qclk_slw      (qclk_slw),
    .reset         (reset),
    .dither_width  (dither_width),
    .dither_shift  (dither_shift),
    .dither        (dither)
  );

  //----------------------------------------------------------------
  // DWDBS DDS square-wave generation
  //
  // dirty_swo_p/n is driven off-chip here; it comes back in on
  // dirty_swi_p/n below after its round trip through the FMC
  // connector and the board's physical clock-cleaner path.
  //----------------------------------------------------------------

  DWDBS_system #(
    .ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH)
  ) DWDBS_system_init (
    .clk_spd      (clk_spd),
    .clk_slw      (clk_slw),
    .qclk_slw     (qclk_slw),
    .reset        (reset),
    .enable       (enable),
    .dither       (dither),
    .phase_change (phase_change),
    .dirty_swo_p  (dirty_swo_p),
    .dirty_swo_n  (dirty_swo_n)
  );

  //----------------------------------------------------------------
  // Re-capture the looped-back signal from the FMC connector
  //----------------------------------------------------------------

  logic dirty_sw;
  logic dirty_sw_buffered;

  IBUFDS ibufds_dirty_sw (
    .I  (dirty_swi_p),
    .IB (dirty_swi_n),
    .O  (dirty_sw)
  );

  // Raw/uncleaned pass-through, for anyone who wants it as-is
  assign dirty_swo = dirty_sw;

  BUFG bufg_clk_clean (
    .I (dirty_sw),
    .O (dirty_sw_buffered)
  );

  //----------------------------------------------------------------
  // Jitter cleaner (MMCM-based)
  //----------------------------------------------------------------

  logic cleaner_locked;  // available for status reporting if/when it's wired out

  clock_cleaner janitor (
    .dirty_clk (dirty_sw_buffered),
    .clean_clk (clean_swo),
    .reset     (reset),
    .locked    (cleaner_locked)
  );

endmodule
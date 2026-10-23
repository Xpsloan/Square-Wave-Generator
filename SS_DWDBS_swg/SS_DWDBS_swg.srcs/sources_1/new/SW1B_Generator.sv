`timescale 1ns / 1ps
//==================================================================
// SW1B_Generator
//
// Top-level DWDBS square-wave generator for channel 1, square wave
// B. This is the main engine of the design: it produces the DWDBS
// output square wave and manages the round-trip of that signal
// off-chip and back:
//
//   1. DWDBS_system runs the DDS phase accumulators + ODDR and
//      drives the "dirty" (raw, un-cleaned) square wave out on
//      dirty_swo1B_p/n, through an OBUFDS.
//   2. Off-chip, dirty_swo1B_p/n is routed out through the FMC
//      connector and looped back in on dirty_swi1B_p/n.
//   3. dirty_swi1B_p/n is re-captured on-chip via IBUFDS, delayed
//      by an IDELAYE2 (DIRTY_IDELAY_TAPS), buffered by a BUFG and
//      cleaned by this module's own sw1B_cleaner (clocking wizard/
//      MMCM) instance - each square wave gets its own clocking
//      wizard instead of sharing one, so every channel/wave can
//      lock and track independently.
//   4. A local Start_Signal_Generator drives start_signal1B, a
//      marker that goes high START_CYCLE_COUNT clk_sync cycles
//      after reset release. The DDS, the cleaner and the marker
//      are all released by this channel's one reset flop.
//==================================================================

module SW1B_Generator #(
  parameter int ACCUMULATOR_WIDTH = 32,
  parameter int DIRTY_IDELAY_TAPS = 0,  // 0-31 IDELAYE2 taps on the looped-back input
                                        // (~78 ps/tap with the 200 MHz IDELAYCTRL REFCLK)
  parameter int unsigned START_CYCLE_COUNT = 5_002 // clk_sync cycles from reset release to start_signal1B
)(
  // Shared DWDBS clocks (single MMCM upstream, phase-locked to each other)
  input  logic clk_quick,        // fast clock that runs 2x the speed of clk_slow
  input  logic clk_slow,         // slow clock that runs 1/2 the speed of clk_quick
  input  logic qclk_slow,        // same speed as clk_slow but 90 degree phase shift
  input  logic clk_sync,         // 50 MHz; clocks this channel's reset flop and start marker
  input  logic sys_reset,        // async, active-high (system_reset | ~locked); holds the ODDR low
  input  logic sw_reset,         // active-high, already synchronized to clk_sync by Reset_Master
  input  logic sw1B_enable,      // active-low; gates the cleaned output combinationally (a "soft"
                                  // pause that leaves the phase accumulators and ODDR running), so
                                  // enable=0 => running, enable=1 => sw1B held low

  input  logic [ACCUMULATOR_WIDTH-1:0] sw1B_phase_change,
  input  logic [ACCUMULATOR_WIDTH-1:0] sw1B_start_phase,

  // DWDBS "dirty" output, routed off-chip through the FMC connector
  output logic dirty_swo1B_p,
  output logic dirty_swo1B_n,

  // Same signal, looped back in from the FMC connector
  input  logic dirty_swi1B_p,
  input  logic dirty_swi1B_n,

  // Recaptured, cleaned, on-chip square wave
  output logic sw1B,

  // Start marker for this channel
  output logic start_signal1B
);

  //----------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------

  logic dirty_sw1B;
  logic unbuffed_dirty_sw1B;
  logic delayed_dirty_sw1B;
  logic buffed_dirty_sw1B;
  logic sw1B_locked;   // reserved for status reporting if/when it's wired out

  //----------------------------------------------------------------
  // Reset
  //
  // sw_reset arrives already synchronized to clk_sync (Reset_Master).
  // It is re-registered exactly once here, and that one flop releases
  // this channel's DDS, jitter cleaner and start marker together, so
  // the wave and its marker always leave reset on the same clk_sync
  // edge. Keeping the flop per channel keeps the short clk_sync ->
  // qclk_slow hop into the DDS local.
  //----------------------------------------------------------------

  (* keep = "true" *) logic sw_reset_local;
  logic cleaner_reset;

  always_ff @(posedge clk_sync) begin
    sw_reset_local <= sw_reset;
  end

  assign cleaner_reset = sw_reset_local | sys_reset;

  //----------------------------------------------------------------
  // DWDBS DDS square-wave generation
  //
  // dirty_sw1B is driven off-chip here; it comes back in on
  // dirty_swi1B_p/n below after its round trip through the FMC
  // connector and the board's physical clock-cleaner path.
  //----------------------------------------------------------------

  DWDBS_system #(
    .ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH)
  ) DWDBS_system_inst (
    .clk_quick    (clk_quick),
    .clk_slow     (clk_slow),
    .qclk_slow    (qclk_slow),
    .sw_reset     (sw_reset_local),
    .oddr_reset   (sys_reset),
    .start_phase  (sw1B_start_phase),
    .phase_change (sw1B_phase_change),
    .dirty_sw     (dirty_sw1B)
  );

  OBUFDS obufds_dirty_sw1B (
    .I  (dirty_sw1B),
    .O  (dirty_swo1B_p),
    .OB (dirty_swo1B_n)
  );

  //----------------------------------------------------------------
  // Re-capture the looped-back signal from the FMC connector
  //----------------------------------------------------------------

  IBUFDS ibufds_dirty_sw1B (
    .I  (dirty_swi1B_p),
    .IB (dirty_swi1B_n),
    .O  (unbuffed_dirty_sw1B)
  );

  //----------------------------------------------------------------
  // Input delay
  //
  // Fixed IDELAYE2 on the looped-back wave, ahead of the BUFG. Needs
  // the IDELAYCTRL instantiated in Top (200 MHz REFCLK).
  //----------------------------------------------------------------

  IDELAYE2 #(
    .IDELAY_TYPE           ("FIXED"),
    .DELAY_SRC             ("IDATAIN"),
    .IDELAY_VALUE          (DIRTY_IDELAY_TAPS),
    .HIGH_PERFORMANCE_MODE ("TRUE"),
    .SIGNAL_PATTERN        ("CLOCK"),
    .REFCLK_FREQUENCY      (200.0),
    .CINVCTRL_SEL          ("FALSE"),
    .PIPE_SEL              ("FALSE")
  ) idelay_dirty_sw1B (
    .IDATAIN     (unbuffed_dirty_sw1B),
    .DATAOUT     (delayed_dirty_sw1B),
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

  BUFG buf_dirty_sw1B (
    .I (delayed_dirty_sw1B),
    .O (buffed_dirty_sw1B)
  );

  //----------------------------------------------------------------
  // Jitter cleaner
  //
  // Own clocking-wizard MMCM instance (not shared with any other
  // channel/square wave) so this wave's cleaner can lock/track
  // independently.
  //----------------------------------------------------------------

  logic clean_sw1B;
  sw1B_cleaner sw1B_cleaner_inst (
    .dirty_sw1B (buffed_dirty_sw1B),
    .reset      (cleaner_reset),
    .clean_sw1B (clean_sw1B),
    .locked     (sw1B_locked)
  );

  // sw1B_enable is active-low: enable=0 => running (pass clean_sw1B
  // through), enable=1 => output held low.
  always_comb begin
    if (!sw1B_enable) begin
      sw1B = clean_sw1B;
    end else begin
      sw1B = 1'b0;
    end
  end

  //----------------------------------------------------------------
  // Start marker
  //
  // This channel's own Start_Signal_Generator (not shared with any
  // other channel), placed next to its output pin.
  //----------------------------------------------------------------

  Start_Signal_Generator #(
    .CYCLE_COUNT (START_CYCLE_COUNT)
  ) start_signal_inst (
    .clk_sync     (clk_sync),
    .sw_reset     (sw_reset_local),
    .start_signal (start_signal1B)
  );

endmodule

`timescale 1ns / 1ps
//==================================================================
// Dither_Control
//
// Turns the four raw board buttons (inc/dec dither_width, inc/dec
// dither_shift) into a saturating dither_width/dither_shift setting
// for Spur_Control:
//
//   1. Each button is synchronized and counter-debounced (~20ms at
//      CLK_FREQ_HZ), then edge-detected to a single one-cycle pulse
//      per press.
//   2. dither_width is a saturating up/down counter over
//      [0, MAX_DITHER_WIDTH]; it never wraps and starts at 0
//      (dithering off).
//   3. dither_shift is a saturating up/down counter, capped at
//      (ACCUMULATOR_WIDTH - dither_width) so that Spur_Control's
//      (dither << dither_shift) never shifts the dither_width
//      significant bits beyond the accumulator's width. Because the
//      cap depends on dither_width, dither_shift is also re-clamped
//      every cycle (not just on a button press) so a dither_width
//      increase that shrinks the cap takes effect immediately.
//==================================================================

module Dither_Control #(
  parameter int ACCUMULATOR_WIDTH = 32,
  parameter int MAX_DITHER_WIDTH  = 9,
  parameter int CLK_FREQ_HZ       = 300_000_000, // clk frequency, for debounce timing
  parameter int DEBOUNCE_MS       = 20           // required stable time before a press registers
)(
  input  logic clk,               // qclk_slw at the instantiation site
  input  logic reset,             // async, active-high

  input  logic inc_dither_width,
  input  logic dec_dither_width,
  input  logic inc_dither_shift,
  input  logic dec_dither_shift,

  output logic [$clog2(MAX_DITHER_WIDTH+1)-1:0] dither_width,
  output logic [$clog2(ACCUMULATOR_WIDTH)-1:0]  dither_shift
);

  //----------------------------------------------------------------
  // Button synchronization + debounce + one-pulse-per-press
  //----------------------------------------------------------------

  localparam int DEBOUNCE_CYCLES   = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
  localparam int DEBOUNCE_CNT_BITS = $clog2(DEBOUNCE_CYCLES);

  logic [3:0] btn_raw;
  logic [3:0] btn_pulse;

  assign btn_raw = {dec_dither_shift, inc_dither_shift, dec_dither_width, inc_dither_width};

  generate
    for (genvar i = 0; i < 4; i++) begin : g_debounce
      logic                        sync0, sync1;
      logic                        stable, stable_d;
      logic [DEBOUNCE_CNT_BITS-1:0] cnt;

      always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
          sync0 <= 1'b0;
          sync1 <= 1'b0;
        end else begin
          sync0 <= btn_raw[i];
          sync1 <= sync0;
        end
      end

      always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
          cnt    <= '0;
          stable <= 1'b0;
        end else if (sync1 != stable) begin
          if (cnt == DEBOUNCE_CNT_BITS'(DEBOUNCE_CYCLES) - 1'b1) begin
            stable <= sync1;
            cnt    <= '0;
          end else begin
            cnt <= cnt + 1'b1;
          end
        end else begin
          cnt <= '0;
        end
      end

      always_ff @(posedge clk or posedge reset) begin
        if (reset) stable_d <= 1'b0;
        else       stable_d <= stable;
      end

      assign btn_pulse[i] = stable & ~stable_d; // rising edge of the debounced level = press
    end
  endgenerate

  logic inc_width_pulse, dec_width_pulse, inc_shift_pulse, dec_shift_pulse;
  assign {dec_shift_pulse, inc_shift_pulse, dec_width_pulse, inc_width_pulse} = btn_pulse;

  //----------------------------------------------------------------
  // dither_width: saturating up/down counter, [0, MAX_DITHER_WIDTH]
  //----------------------------------------------------------------

  localparam int DITHER_WIDTH_BITS = $clog2(MAX_DITHER_WIDTH+1);
  localparam int DITHER_SHIFT_BITS = $clog2(ACCUMULATOR_WIDTH);

  logic [DITHER_WIDTH_BITS-1:0] dither_width_r;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      dither_width_r <= '0;
    end else if (inc_width_pulse && !dec_width_pulse &&
                 dither_width_r < DITHER_WIDTH_BITS'(MAX_DITHER_WIDTH)) begin
      dither_width_r <= dither_width_r + 1'b1;
    end else if (dec_width_pulse && !inc_width_pulse && dither_width_r > 0) begin
      dither_width_r <= dither_width_r - 1'b1;
    end
  end

  //----------------------------------------------------------------
  // dither_shift: saturating up/down counter, capped at
  // (ACCUMULATOR_WIDTH - dither_width_r), re-clamped every cycle.
  //----------------------------------------------------------------

  localparam int SHIFT_CALC_BITS = DITHER_SHIFT_BITS + 1; // headroom for the subtraction below

  logic [SHIFT_CALC_BITS-1:0] shift_cap_raw;
  logic [DITHER_SHIFT_BITS-1:0] dither_shift_max;

  assign shift_cap_raw   = SHIFT_CALC_BITS'(ACCUMULATOR_WIDTH) - SHIFT_CALC_BITS'(dither_width_r);
  assign dither_shift_max = (shift_cap_raw > SHIFT_CALC_BITS'({DITHER_SHIFT_BITS{1'b1}}))
                              ? {DITHER_SHIFT_BITS{1'b1}}
                              : DITHER_SHIFT_BITS'(shift_cap_raw);

  logic [DITHER_SHIFT_BITS-1:0] dither_shift_r;
  logic [DITHER_SHIFT_BITS-1:0] dither_shift_next;

  always_comb begin
    dither_shift_next = dither_shift_r;
    if (inc_shift_pulse && !dec_shift_pulse && dither_shift_r < dither_shift_max) begin
      dither_shift_next = dither_shift_r + 1'b1;
    end else if (dec_shift_pulse && !inc_shift_pulse && dither_shift_r > 0) begin
      dither_shift_next = dither_shift_r - 1'b1;
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      dither_shift_r <= '0;
    end else begin
      // Re-clamp every cycle (not just on a press) so a dither_width
      // increase that shrinks dither_shift_max takes effect immediately.
      dither_shift_r <= (dither_shift_next > dither_shift_max) ? dither_shift_max : dither_shift_next;
    end
  end

  //----------------------------------------------------------------
  // Outputs
  //----------------------------------------------------------------

  assign dither_width = dither_width_r;
  assign dither_shift = dither_shift_r;

endmodule

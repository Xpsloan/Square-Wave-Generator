`timescale 1ns/1ps
//==================================================================
// Top
//
// Board-level top module. Generates all clocks from a single
// differential 200 MHz reference and instantiates
// Square_Wave_Generator, which does all of the real work: DWDBS
// square-wave generation with button-controlled dither, the FMC
// round-trip, and jitter cleaning. This module is just a thin
// wrapper that wires up clocks/resets and board I/O around it,
// plus a heartbeat/status LED pair.
//==================================================================
module Top (
  input  logic clk_in1_p,
  input  logic clk_in1_n,

  input  logic reset,          // async, active-high (board button/pin)
  input  logic enable,         // active-low: enable=0 => running

  input  logic inc_dither_width,
  input  logic dec_dither_width,

  input  logic inc_dither_shift,
  input  logic dec_dither_shift,
  
  output logic dirty_swo_p,
  output logic dirty_swo_n,

  input  logic dirty_swi_p,
  input  logic dirty_swi_n,

  output logic clean_swo,
  output logic dirty_swo,

  output logic [1:0] led
);

  //----------------------------------------------------------------
  // Master 200 MHz clock
  //----------------------------------------------------------------

  logic clk_200_ibuf, clk_200;
  logic master_reset;

  assign master_reset = reset;

  IBUFDS ibufds_clk_200 (
    .I  (clk_in1_p),
    .IB (clk_in1_n),
    .O  (clk_200_ibuf)
  );

  BUFG bufg_clk_200 (
    .I (clk_200_ibuf),
    .O (clk_200)
  );

  //----------------------------------------------------------------
  // DWDBS clock generation
  //----------------------------------------------------------------

  logic clk_spd;
  logic clk_slw;
  logic qclk_slw;
  logic DWDBS_clks_locked;
  logic DWDBS_clks_reset;

  assign DWDBS_clks_reset = master_reset;

  DWDBS_clks DWDBS_clks_init (
    .clk_200  (clk_200),
    .reset    (DWDBS_clks_reset),
    .clk_spd  (clk_spd),
    .clk_slw  (clk_slw),
    .qclk_slw (qclk_slw),
    .locked   (DWDBS_clks_locked)
  );

  //----------------------------------------------------------------
  // Dither_Control
  //
  // DWDBS_sys_reset is registered on qclk_slw to line up with the
  // reset-capture scheme inside DWDBS_system (see that module's
  // header comment) and holds the system in reset until the DWDBS
  // clocks report locked. That includes Dither_Control, so the
  // dither_width/dither_shift buttons only take effect once the
  // clocks are locked.
  //----------------------------------------------------------------

  localparam int ACCUMULATOR_WIDTH = 32;
  localparam int MAX_DITHER_WIDTH  = 9;

  logic DWDBS_sys_reset;

  assign DWDBS_sys_reset = DWDBS_clks_reset | ~DWDBS_clks_locked;

  logic [$clog2(MAX_DITHER_WIDTH+1)-1:0] dither_width;
  logic [$clog2(ACCUMULATOR_WIDTH)-1:0]  dither_shift;

  Dither_Control #(
    .ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH),
    .MAX_DITHER_WIDTH  (MAX_DITHER_WIDTH)
  ) dither_control (
    .clk              (qclk_slw),
    .reset            (DWDBS_sys_reset),
    .inc_dither_width (inc_dither_width),
    .dec_dither_width (dec_dither_width),
    .inc_dither_shift (inc_dither_shift),
    .dec_dither_shift (dec_dither_shift),
    .dither_width     (dither_width),
    .dither_shift     (dither_shift)
  );

  //----------------------------------------------------------------
  // Square_Wave_Generator
  //----------------------------------------------------------------

  logic [ACCUMULATOR_WIDTH-1:0] phase_change;
  logic dither_active;

  //assign phase_change = 32'h1B3F_C2D5;              // 127.73 MHz 1.2 GHz
  //assign phase_change = 32'h4C4C_5975;              // 298.04 MHz 1.0 GHz
  //assign phase_change = 32'h3F94_FC74;              // 298.04 MHz 1.2 GHz
  assign phase_change = 32'h065B_B21F;              // 29.804 MHz 1.2 GHz

  Square_Wave_Generator #(
    .ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH),
    .MAX_DITHER_WIDTH  (MAX_DITHER_WIDTH)
  ) square_wave_generator (
    .clk_spd           (clk_spd),
    .clk_slw           (clk_slw),
    .qclk_slw          (qclk_slw),

    .reset             (DWDBS_sys_reset),
    .enable            (enable),

    .dither_width      (dither_width),
    .dither_shift      (dither_shift),

    .phase_change      (phase_change),

    .dirty_swo_p       (dirty_swo_p),
    .dirty_swo_n       (dirty_swo_n),

    .dirty_swi_p       (dirty_swi_p),
    .dirty_swi_n       (dirty_swi_n),

    .clean_swo         (clean_swo),
    .dirty_swo         (dirty_swo),

    .dither_active     (dither_active)
  );

  //----------------------------------------------------------------
  // Debug LEDs
  //
  // led[0]: ~1.5 Hz-ish heartbeat off clk_200 (toggles as long as
  //         clk_200 is present and master_reset is deasserted).
  // led[1]: lit whenever dithering is currently active
  //         (dither_width != 0).
  //----------------------------------------------------------------

  logic [26:0] led_counter;

  always_ff @(posedge clk_200 or posedge master_reset) begin
    if (master_reset) led_counter <= 27'd0;
    else               led_counter <= led_counter + 1'b1;
  end

  assign led[0] = led_counter[26];
  assign led[1] = dither_active;

endmodule
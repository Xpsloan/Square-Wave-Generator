`timescale 1ns/1ps
//==================================================================
// Top
//
// Board-level top module. Generates all clocks from a single
// differential 200 MHz reference and instantiates all 8 independent
// DWDBS square-wave channels (4 channels x {A,B}) off those shared
// clocks. Each SW{n}{A,B}_Generator does all of the real work: DWDBS
// square-wave generation, the FMC round-trip, and jitter cleaning
// (its own clocking-wizard/MMCM instance, so every wave locks and
// tracks independently). All 8 waves share clocks, the two reset
// sources (system/clock-lock-derived, and manual button-press), and
// enable, but each has its own phase_change/start_phase (so they
// can run at different frequencies) and its own FMC round-trip I/O.
// Each generator also has its own Start_Signal_Generator driving a
// per-channel start marker (start_signal{n}{A,B}).
// Host_Control takes UDP commands over the SP701's Ethernet port:
// it holds every channel's phase word and start phase, and its run
// state machine is what releases (TRIGGER) and holds (STOP) the
// waves. See host/swg_host.py for the host side.
// This module is just a thin wrapper that wires up clocks/resets
// and board I/O around them, plus a heartbeat/status LED pair.
//==================================================================
module Top (
  input  logic clk_in1_p,
  input  logic clk_in1_n,

  input  logic system_reset,       // async, active-high (board button/pin); system reset - gates all 8
                                   // waves' DDS accumulators/ODDR/cleaners until DWDBS_clks locks
  input  logic square_wave_reset,  // async, active-high (North button): local STOP - stops the
                                   // waves if they are running (same as the host's STOP command)
  input  logic enable,             // active-low: enable=0 => running; shared by all 8 waves

  // Channel 0, square wave A
  output logic dirty_swo0A_p,
  output logic dirty_swo0A_n,
  input  logic dirty_swi0A_p,
  input  logic dirty_swi0A_n,
  output logic sw0A,
  output logic start_signal0A,

  // Channel 0, square wave B
  output logic dirty_swo0B_p,
  output logic dirty_swo0B_n,
  input  logic dirty_swi0B_p,
  input  logic dirty_swi0B_n,
  output logic sw0B,
  output logic start_signal0B,

  // Channel 1, square wave A
  output logic dirty_swo1A_p,
  output logic dirty_swo1A_n,
  input  logic dirty_swi1A_p,
  input  logic dirty_swi1A_n,
  output logic sw1A,
  output logic start_signal1A,

  // Channel 1, square wave B
  output logic dirty_swo1B_p,
  output logic dirty_swo1B_n,
  input  logic dirty_swi1B_p,
  input  logic dirty_swi1B_n,
  output logic sw1B,
  output logic start_signal1B,

  // Channel 2, square wave A
  output logic dirty_swo2A_p,
  output logic dirty_swo2A_n,
  input  logic dirty_swi2A_p,
  input  logic dirty_swi2A_n,
  output logic sw2A,
  output logic start_signal2A,

  // Channel 2, square wave B
  output logic dirty_swo2B_p,
  output logic dirty_swo2B_n,
  input  logic dirty_swi2B_p,
  input  logic dirty_swi2B_n,
  output logic sw2B,
  output logic start_signal2B,

  // Channel 3, square wave A
  output logic dirty_swo3A_p,
  output logic dirty_swo3A_n,
  input  logic dirty_swi3A_p,
  input  logic dirty_swi3A_n,
  output logic sw3A,
  output logic start_signal3A,

  // Channel 3, square wave B
  output logic dirty_swo3B_p,
  output logic dirty_swo3B_n,
  input  logic dirty_swi3B_p,
  input  logic dirty_swi3B_n,
  output logic sw3B,
  output logic start_signal3B,

  // Ethernet: RGMII to the SP701's ethernet_1 PHY (Marvell 88E1111)
  input  logic       phy_rx_clk,
  input  logic [3:0] phy_rxd,
  input  logic       phy_rx_ctl,
  output logic       phy_tx_clk,
  output logic [3:0] phy_txd,
  output logic       phy_tx_ctl,
  output logic       phy_reset_n,
  output logic       phy_mdc,
  inout  wire        phy_mdio,

  // the sync clock
  output logic clk_sync,

  // the led output so that we know the fpga is actually on
  output logic [1:0] led
);

  //----------------------------------------------------------------
  // Master 200 MHz clock
  //----------------------------------------------------------------

  logic clk_200_ibuf, clk_200;

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
  // IDELAY calibration
  //
  // One IDELAYCTRL for the IDELAYE2s on every channel's looped-back
  // input (dirty_swi*). Vivado replicates it into each bank/clock
  // region that has IDELAYs. 200 MHz REFCLK => ~78 ps per tap.
  //----------------------------------------------------------------

  (* keep = "true" *) logic idelayctrl_rdy;   // calibration done (status only)

  IDELAYCTRL idelayctrl_inst (
    .REFCLK (clk_200),
    .RST    (system_reset),
    .RDY    (idelayctrl_rdy)
  );

  //----------------------------------------------------------------
  // DWDBS clock generation
  //----------------------------------------------------------------

  logic clk_quick;
  logic clk_slow;
  logic qclk_slow;
  logic locked;
  logic sys_reset;
  logic sw_reset;
  logic hold_reset;   // from Host_Control: high = waves held in reset

  DWDBS_clks DWDBS_clks_init (
    .clk_200   (clk_200),
    .reset     (system_reset),
    .clk_quick (clk_quick),
    .clk_slow  (clk_slow),
    .qclk_slow (qclk_slow),
    .clk_sync  (clk_sync),
    .locked    (locked)
  );

  localparam int ACCUMULATOR_WIDTH = 32;

  //----------------------------------------------------------------
  // Reset sequencing
  //
  // Reset_Master derives the shared sys_reset/sw_reset pair from the
  // board's reset inputs and clock-lock status. Its "square wave
  // reset" input is now Host_Control's hold_reset, so the waves only
  // leave reset when the host sends TRIGGER. sw_reset is the only
  // synchronizer for it; each channel re-registers it once and
  // releases its DDS and start marker from that flop.
  //----------------------------------------------------------------

  Reset_Master reset_master_inst (
    .clk_sync          (clk_sync),
    .locked            (locked),
    .system_reset      (system_reset),
    .square_wave_reset (hold_reset),
    .sys_reset         (sys_reset),
    .sw_reset          (sw_reset)
  );

  //----------------------------------------------------------------
  // Host control over Ethernet
  //
  // Each channel's DDS phase word and start phase live in an
  // AXI4-Lite register block inside Host_Control, written by the host
  // over UDP. They only reach the DDS while it is held in reset, and
  // hold_reset only releases on the host's TRIGGER command after a
  // COMMIT (IDLE -> ARMED -> TRIGGER -> OUTPUT), so values can never
  // change under a running wave. The constants below are each
  // channel's power-up value, used until the host writes new ones.
  //----------------------------------------------------------------

  // 0x0666_6666 / 2^32 * 1 GSa/s = 25 MHz
  localparam logic [31:0] PHASE_INC_25MHZ   = 32'h0666_6666;
  localparam logic [31:0] START_PHASE_25MHZ = 32'h8000_0000 - PHASE_INC_25MHZ * 32'd100_014;

  logic [31:0] ch_phase_word  [8];
  logic [31:0] ch_start_phase [8];
  logic        eth_status_led;

  Host_Control #(
    .N_CH              (8),
    .RESET_PHASE_WORD  (PHASE_INC_25MHZ),
    .RESET_START_PHASE (START_PHASE_25MHZ)
  ) host_ctrl_inst (
    .clk_200     (clk_200),
    .clk_sync    (clk_sync),
    .sys_reset   (sys_reset),
    .stop_btn    (square_wave_reset),
    .phy_rx_clk  (phy_rx_clk),
    .phy_rxd     (phy_rxd),
    .phy_rx_ctl  (phy_rx_ctl),
    .phy_tx_clk  (phy_tx_clk),
    .phy_txd     (phy_txd),
    .phy_tx_ctl  (phy_tx_ctl),
    .phy_reset_n (phy_reset_n),
    .phy_mdc     (phy_mdc),
    .phy_mdio    (phy_mdio),
    .phase_word  (ch_phase_word),
    .start_phase (ch_start_phase),
    .hold_reset  (hold_reset),
    .run_state   (),
    .status_led  (eth_status_led)
  );

  // Bus order: 0A, 0B, 1A, 1B, 2A, 2B, 3A, 3B at 0x1000 ... 0x8000
  logic [ACCUMULATOR_WIDTH-1:0] sw0A_phase_change, sw0B_phase_change;
  logic [ACCUMULATOR_WIDTH-1:0] sw1A_phase_change, sw1B_phase_change;
  logic [ACCUMULATOR_WIDTH-1:0] sw2A_phase_change, sw2B_phase_change;
  logic [ACCUMULATOR_WIDTH-1:0] sw3A_phase_change, sw3B_phase_change;
  logic [ACCUMULATOR_WIDTH-1:0] sw0A_start_phase, sw0B_start_phase;
  logic [ACCUMULATOR_WIDTH-1:0] sw1A_start_phase, sw1B_start_phase;
  logic [ACCUMULATOR_WIDTH-1:0] sw2A_start_phase, sw2B_start_phase;
  logic [ACCUMULATOR_WIDTH-1:0] sw3A_start_phase, sw3B_start_phase;

  assign sw0A_phase_change = ch_phase_word[0];  assign sw0A_start_phase = ch_start_phase[0];
  assign sw0B_phase_change = ch_phase_word[1];  assign sw0B_start_phase = ch_start_phase[1];
  assign sw1A_phase_change = ch_phase_word[2];  assign sw1A_start_phase = ch_start_phase[2];
  assign sw1B_phase_change = ch_phase_word[3];  assign sw1B_start_phase = ch_start_phase[3];
  assign sw2A_phase_change = ch_phase_word[4];  assign sw2A_start_phase = ch_start_phase[4];
  assign sw2B_phase_change = ch_phase_word[5];  assign sw2B_start_phase = ch_start_phase[5];
  assign sw3A_phase_change = ch_phase_word[6];  assign sw3A_start_phase = ch_start_phase[6];
  assign sw3B_phase_change = ch_phase_word[7];  assign sw3B_start_phase = ch_start_phase[7];

  //----------------------------------------------------------------
  // Per-wave IDELAYE2 tap settings (0-31) for the looped-back input
  //----------------------------------------------------------------

  localparam int SW0A_IDELAY_TAPS = 0, SW0B_IDELAY_TAPS = 0;
  localparam int SW1A_IDELAY_TAPS = 0, SW1B_IDELAY_TAPS = 0;
  localparam int SW2A_IDELAY_TAPS = 0, SW2B_IDELAY_TAPS = 0;
  localparam int SW3A_IDELAY_TAPS = 0, SW3B_IDELAY_TAPS = 0;

  //----------------------------------------------------------------
  // Start marker delay, shared by every channel's own
  // Start_Signal_Generator: clk_sync (50 MHz) cycles from reset
  // release to start_signal{n}{A,B} going high (~100 us).
  //----------------------------------------------------------------

  localparam int unsigned START_CYCLE_COUNT = 5_002;

  //----------------------------------------------------------------
  // Eight independent square-wave generators
  //----------------------------------------------------------------

  SW0A_Generator #(.ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH), .DIRTY_IDELAY_TAPS (SW0A_IDELAY_TAPS),
                   .START_CYCLE_COUNT (START_CYCLE_COUNT)) sw0A_inst (
    .clk_quick (clk_quick), .clk_slow (clk_slow), .qclk_slow (qclk_slow),
    .clk_sync (clk_sync), .sys_reset (sys_reset), .sw_reset (sw_reset),
    .sw0A_enable (enable),
    .sw0A_phase_change (sw0A_phase_change), .sw0A_start_phase (sw0A_start_phase),
    .dirty_swo0A_p (dirty_swo0A_p), .dirty_swo0A_n (dirty_swo0A_n),
    .dirty_swi0A_p (dirty_swi0A_p), .dirty_swi0A_n (dirty_swi0A_n), .sw0A (sw0A),
    .start_signal0A (start_signal0A)
  );

  SW0B_Generator #(.ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH), .DIRTY_IDELAY_TAPS (SW0B_IDELAY_TAPS),
                   .START_CYCLE_COUNT (START_CYCLE_COUNT)) sw0B_inst (
    .clk_quick (clk_quick), .clk_slow (clk_slow), .qclk_slow (qclk_slow),
    .clk_sync (clk_sync), .sys_reset (sys_reset), .sw_reset (sw_reset),
    .sw0B_enable (enable),
    .sw0B_phase_change (sw0B_phase_change), .sw0B_start_phase (sw0B_start_phase),
    .dirty_swo0B_p (dirty_swo0B_p), .dirty_swo0B_n (dirty_swo0B_n),
    .dirty_swi0B_p (dirty_swi0B_p), .dirty_swi0B_n (dirty_swi0B_n), .sw0B (sw0B),
    .start_signal0B (start_signal0B)
  );

  SW1A_Generator #(.ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH), .DIRTY_IDELAY_TAPS (SW1A_IDELAY_TAPS),
                   .START_CYCLE_COUNT (START_CYCLE_COUNT)) sw1A_inst (
    .clk_quick (clk_quick), .clk_slow (clk_slow), .qclk_slow (qclk_slow),
    .clk_sync (clk_sync), .sys_reset (sys_reset), .sw_reset (sw_reset),
    .sw1A_enable (enable),
    .sw1A_phase_change (sw1A_phase_change), .sw1A_start_phase (sw1A_start_phase),
    .dirty_swo1A_p (dirty_swo1A_p), .dirty_swo1A_n (dirty_swo1A_n),
    .dirty_swi1A_p (dirty_swi1A_p), .dirty_swi1A_n (dirty_swi1A_n), .sw1A (sw1A),
    .start_signal1A (start_signal1A)
  );

  SW1B_Generator #(.ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH), .DIRTY_IDELAY_TAPS (SW1B_IDELAY_TAPS),
                   .START_CYCLE_COUNT (START_CYCLE_COUNT)) sw1B_inst (
    .clk_quick (clk_quick), .clk_slow (clk_slow), .qclk_slow (qclk_slow),
    .clk_sync (clk_sync), .sys_reset (sys_reset), .sw_reset (sw_reset),
    .sw1B_enable (enable),
    .sw1B_phase_change (sw1B_phase_change), .sw1B_start_phase (sw1B_start_phase),
    .dirty_swo1B_p (dirty_swo1B_p), .dirty_swo1B_n (dirty_swo1B_n),
    .dirty_swi1B_p (dirty_swi1B_p), .dirty_swi1B_n (dirty_swi1B_n), .sw1B (sw1B),
    .start_signal1B (start_signal1B)
  );

  SW2A_Generator #(.ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH), .DIRTY_IDELAY_TAPS (SW2A_IDELAY_TAPS),
                   .START_CYCLE_COUNT (START_CYCLE_COUNT)) sw2A_inst (
    .clk_quick (clk_quick), .clk_slow (clk_slow), .qclk_slow (qclk_slow),
    .clk_sync (clk_sync), .sys_reset (sys_reset), .sw_reset (sw_reset),
    .sw2A_enable (enable),
    .sw2A_phase_change (sw2A_phase_change), .sw2A_start_phase (sw2A_start_phase),
    .dirty_swo2A_p (dirty_swo2A_p), .dirty_swo2A_n (dirty_swo2A_n),
    .dirty_swi2A_p (dirty_swi2A_p), .dirty_swi2A_n (dirty_swi2A_n), .sw2A (sw2A),
    .start_signal2A (start_signal2A)
  );

  SW2B_Generator #(.ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH), .DIRTY_IDELAY_TAPS (SW2B_IDELAY_TAPS),
                   .START_CYCLE_COUNT (START_CYCLE_COUNT)) sw2B_inst (
    .clk_quick (clk_quick), .clk_slow (clk_slow), .qclk_slow (qclk_slow),
    .clk_sync (clk_sync), .sys_reset (sys_reset), .sw_reset (sw_reset),
    .sw2B_enable (enable),
    .sw2B_phase_change (sw2B_phase_change), .sw2B_start_phase (sw2B_start_phase),
    .dirty_swo2B_p (dirty_swo2B_p), .dirty_swo2B_n (dirty_swo2B_n),
    .dirty_swi2B_p (dirty_swi2B_p), .dirty_swi2B_n (dirty_swi2B_n), .sw2B (sw2B),
    .start_signal2B (start_signal2B)
  );

  SW3A_Generator #(.ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH), .DIRTY_IDELAY_TAPS (SW3A_IDELAY_TAPS),
                   .START_CYCLE_COUNT (START_CYCLE_COUNT)) sw3A_inst (
    .clk_quick (clk_quick), .clk_slow (clk_slow), .qclk_slow (qclk_slow),
    .clk_sync (clk_sync), .sys_reset (sys_reset), .sw_reset (sw_reset),
    .sw3A_enable (enable),
    .sw3A_phase_change (sw3A_phase_change), .sw3A_start_phase (sw3A_start_phase),
    .dirty_swo3A_p (dirty_swo3A_p), .dirty_swo3A_n (dirty_swo3A_n),
    .dirty_swi3A_p (dirty_swi3A_p), .dirty_swi3A_n (dirty_swi3A_n), .sw3A (sw3A),
    .start_signal3A (start_signal3A)
  );

  SW3B_Generator #(.ACCUMULATOR_WIDTH (ACCUMULATOR_WIDTH), .DIRTY_IDELAY_TAPS (SW3B_IDELAY_TAPS),
                   .START_CYCLE_COUNT (START_CYCLE_COUNT)) sw3B_inst (
    .clk_quick (clk_quick), .clk_slow (clk_slow), .qclk_slow (qclk_slow),
    .clk_sync (clk_sync), .sys_reset (sys_reset), .sw_reset (sw_reset),
    .sw3B_enable (enable),
    .sw3B_phase_change (sw3B_phase_change), .sw3B_start_phase (sw3B_start_phase),
    .dirty_swo3B_p (dirty_swo3B_p), .dirty_swo3B_n (dirty_swo3B_n),
    .dirty_swi3B_p (dirty_swi3B_p), .dirty_swi3B_n (dirty_swi3B_n), .sw3B (sw3B),
    .start_signal3B (start_signal3B)
  );

  //----------------------------------------------------------------
  // Debug LEDs
  //
  // led[0]: ~1.5 Hz-ish heartbeat off clk_200 (toggles as long as
  //         clk_200 is present and sys_reset is deasserted).
  // led[1]: Ethernet: on once the PHY is configured, blinks off
  //         for each command packet answered.
  //----------------------------------------------------------------

  logic [26:0] led_counter;

  always_ff @(posedge clk_200 or posedge sys_reset) begin
    if (sys_reset)  led_counter <= 27'd0;
    else            led_counter <= led_counter + 1'b1;
  end

  assign led[0] = led_counter[26];
  assign led[1] = eth_status_led;

endmodule

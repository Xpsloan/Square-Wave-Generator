`timescale 1ns/1ps

module DWDBS_tb;

  localparam int ACCUMULATOR_WIDTH = 32;

  // ------------------------------------------------------------
  // Testbench signals
  // ------------------------------------------------------------

  logic clk_600;
  logic clk_300;
  logic qclk_300;      // 90-deg shifted 300 MHz domain (was nclk_300)
  logic reset;

  logic [ACCUMULATOR_WIDTH-1:0] phase_change;

  // Full-width sample-stream output from the DUT.
  logic [ACCUMULATOR_WIDTH-1:0] dds_out;

  // Main signals to compare in the waveform
  // (square wave taken from the MSB of dds_out, same convention
  //  the reference model below uses)
  logic dwdbs_square_wave_out;
  logic dds_square_wave_out;

  // Pure DDS reference accumulator
  logic [ACCUMULATOR_WIDTH-1:0] dds_phase_accum;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------

  SIM_DWDBS_sys #(
    .ACCUMULATOR_WIDTH(ACCUMULATOR_WIDTH)
  ) dut (
    .clk_300      (clk_300),
    .qclk_300     (qclk_300),
    .clk_600      (clk_600),
    .reset        (reset),
    .phase_change (phase_change),
    .DDS_out      (dds_out)
  );

  assign dwdbs_square_wave_out = dds_out[ACCUMULATOR_WIDTH-1];

  // ------------------------------------------------------------
  // Clocks
  //
  // Not meant to be literally 600 MHz / 300 MHz - #5/#10 are just
  // convenient units. What matters is the relationship: clk_300
  // toggles once per clk_600 period (half the frequency), and
  // qclk_300 toggles on the opposite clk_600 edge from clk_300,
  // which puts it a quarter of a clk_300 period later - i.e. a
  // 90-degree shift - regardless of the actual time unit chosen.
  // ------------------------------------------------------------

  initial begin
    clk_600 = 0;
    forever #5 clk_600 = ~clk_600;
  end

  initial begin
    clk_300 = 0;
    forever @(posedge clk_600)
      clk_300 = ~clk_300;
  end

  initial begin
    qclk_300 = 0;
    forever @(negedge clk_600)
      qclk_300 = ~qclk_300;
  end

  // ------------------------------------------------------------
  // Pure DDS reference
  //
  // The DWDBS/ODDR emits a new sample on both edges of clk_600.
  // Therefore, the reference accumulator must also advance on
  // both edges to represent the same effective sampling behavior.
  // ------------------------------------------------------------

  // Trying to align the square_wave_outs....
  logic dwdbs_started;

  always @(posedge reset or posedge dwdbs_square_wave_out) begin
    if (reset) begin
      dwdbs_started <= 1'b0;
    end else begin
      dwdbs_started <= 1'b1;
    end
  end

  always @(posedge clk_600 or negedge clk_600) begin
    if (reset || ~dwdbs_started) begin
      dds_phase_accum <= '0;
    end else begin
      dds_phase_accum <= dds_phase_accum + phase_change;
    end
  end

  // Square wave generated from accumulator MSB
  assign dds_square_wave_out = dds_phase_accum[ACCUMULATOR_WIDTH-1];

  // ------------------------------------------------------------
  // Test task
  // ------------------------------------------------------------

  task automatic run_test(
    input logic [ACCUMULATOR_WIDTH-1:0] test_phase_change,
    input int                           test_cycles
  );
    begin
      reset        = 1'b1;
      phase_change = test_phase_change;

      repeat (10) @(posedge clk_600);

      reset = 1'b0;

      repeat (test_cycles) @(posedge clk_600);
    end
  endtask

  // ------------------------------------------------------------
  // Stimulus
  // ------------------------------------------------------------

  initial begin
    reset         = 1'b1;
    phase_change  = '0;
    dwdbs_started = 1'b0;

    run_test(32'h1000_0000, 1000);
    run_test(32'h287A_26C5, 1000);
    run_test(32'h0234_5678, 1000);

    // Finest-resolution step: with a 32-bit accumulator, phase_change
    // of 1 needs ~2^31 samples before the MSB (the square wave bit)
    // would ever flip - far more than is practical to simulate here.
    // This run isn't meant to show a toggle; it's here to confirm the
    // accumulator/pipeline still counts correctly one LSB at a time
    // at the finest possible step size.
    run_test(32'h0000_0001, 500);

    $finish;
  end



endmodule
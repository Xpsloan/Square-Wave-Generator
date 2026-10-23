`timescale 1ns / 1ps

//==================================================================
// Start_Signal_Generator
//
// start_signal goes high CYCLE_COUNT clk_sync cycles after sw_reset
// releases. sw_reset must be the same clk_sync-synchronous reset that
// releases this channel's DDS (no synchronizer of its own here), so
// the marker and the wave always come out of reset together.
//==================================================================

module Start_Signal_Generator #(
  parameter int unsigned CYCLE_COUNT = 5_000
)(
  input  logic clk_sync,
  input  logic sw_reset,
  output logic start_signal
);

  localparam int COUNTER_WIDTH = $clog2(CYCLE_COUNT + 1);

  logic [COUNTER_WIDTH-1:0] counter;

  always_ff @(posedge clk_sync) begin
    if (sw_reset) begin
      counter      <= '0;
      start_signal <= 1'b0;
    end else if (counter < CYCLE_COUNT) begin
      counter <= counter + 1'b1;
      if (counter == CYCLE_COUNT - 1) begin
        start_signal <= 1'b1;
      end
    end
  end

endmodule

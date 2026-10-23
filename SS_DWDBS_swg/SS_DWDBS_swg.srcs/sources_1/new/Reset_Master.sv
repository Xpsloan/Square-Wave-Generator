`timescale 1ns / 1ps

//==================================================================
// Reset_Master
//
// The one place the asynchronous reset inputs are synchronized.
//
//   sys_reset - async, active-high: system_reset | ~locked. Only for
//               things that must be held off immediately and whose
//               release timing does not matter (ODDR R pins, MMCMs).
//   sw_reset  - active-high, asserts immediately on square_wave_reset
//               or sys_reset, and releases on a clk_sync edge after a
//               2-flop synchronizer. Every channel re-registers this
//               once and drives its DDS and its start marker from
//               that one flop, so all waves and markers leave reset
//               on the same clk_sync edge.
//==================================================================

module Reset_Master (
  input  logic clk_sync,
  input  logic locked,
  input  logic system_reset,
  input  logic square_wave_reset,
  output logic sys_reset,
  output logic sw_reset
);

  assign sys_reset = system_reset | ~locked;

  logic sw_reset_async;
  (* ASYNC_REG = "TRUE" *) logic [1:0] sw_reset_sync;

  assign sw_reset_async = square_wave_reset | sys_reset;

  always_ff @(posedge clk_sync or posedge sw_reset_async) begin
    if (sw_reset_async) begin
      sw_reset_sync <= 2'b11;
    end else begin
      sw_reset_sync <= {sw_reset_sync[0], 1'b0};
    end
  end

  assign sw_reset = sw_reset_sync[1];

endmodule

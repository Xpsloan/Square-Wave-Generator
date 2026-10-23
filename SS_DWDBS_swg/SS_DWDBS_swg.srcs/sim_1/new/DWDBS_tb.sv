`timescale 1ns/1ps

module DWDBS_tb;

  localparam int ACCUMULATOR_WIDTH = 32;

  // ------------------------------------------------------------
  // Testbench signals
  // ------------------------------------------------------------

  logic clk_500MHz;
  logic qclk_250MHz; 
  logic clk_250MHz;
  logic clk_50MHz;
  
  logic sw_reset;
  logic sys_reset;
  logic system_reset;
  logic square_wave_reset;

  logic sw;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------

  DWDBS_system dut (
      .clk_quick   (clk_500MHz),       
      .clk_slow    (clk_250MHz),        
      .qclk_slow   (qclk_250MHz),       
      .sw_reset    (sw_reset),         
      .oddr_reset  (sys_reset),    
      .phase_change(32'd0),
      .start_phase (32'h8000_0000),
      .dirty_sw    (sw)
  );
    
  //RESET MODULE
  logic locked;
  assign locked = 1'b1;
  
  Reset_Master reset_dut (
    .clk_sync          (clk_50MHz),
    .locked            (locked),
    .system_reset      (system_reset),
    .square_wave_reset (square_wave_reset),
    .sys_reset         (sys_reset),
    .sw_reset          (sw_reset)
  );
    

  // ------------------------------------------------------------
  // Clocks with the intended relationships with one another
  // ------------------------------------------------------------

  initial begin clk_500MHz  = 1'b1; forever #1  clk_500MHz = ~clk_500MHz; end         // 2 ns  (clk_quick)
  initial clk_250MHz        = 1'b1; always #2  clk_250MHz = ~clk_250MHz;         // 4 ns, 0 deg
  initial begin qclk_250MHz = 1'b1; #1 forever #2 qclk_250MHz = ~qclk_250MHz; end  // 4 ns, 90 deg (1 ns lag)
  initial begin clk_50MHz   = 1'b1; #2 forever #10 clk_50MHz = ~clk_50MHz;  end   // 20 ns, 36 deg (2 ns)

  
  // The actual testing begins, just do random resets and ensure that the start up for valid data is deterministic
  
  initial begin
    square_wave_reset  = 1'b0;
    system_reset       = 1'b1;
    
    repeat (10) @(posedge clk_50MHz);
    system_reset  = 1'b0;
    repeat (20) @(posedge clk_50MHz);
    
    square_wave_reset  = 1'b1;
    repeat (3) @(posedge clk_500MHz);
    square_wave_reset  = 1'b0;
    repeat (11) @(posedge clk_50MHz);
    
    $finish;
  end



endmodule
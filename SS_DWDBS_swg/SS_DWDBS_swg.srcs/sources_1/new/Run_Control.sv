`timescale 1ns / 1ps

//==================================================================
// Run_Control
//
// AXI4-Lite slave that owns the square-wave run state and is the
// only thing that releases the waves from reset:
//
//   IDLE    --config write------------> ARMED
//   ARMED   --COMMIT-------------------> TRIGGER
//   TRIGGER --TRIGGER------------------> OUTPUT   (waves released)
//   TRIGGER --config write------------> ARMED
//   OUTPUT  --STOP or stop button-----> IDLE     (waves held)
//
// hold_reset is high in every state except OUTPUT. A config write
// (cfg_wr, from the decoder) can never coincide with the release:
// the bus has one master doing one transaction at a time, and the
// release only happens as the result of the TRIGGER write itself.
// Config writes during OUTPUT are kept and used on the next run.
//
//   Offset  Name           Access
//   0x00    ID             RO   0x5357_4731 ("SWG1")
//   0x04    STATE          RO   [1:0] state (0 IDLE, 1 ARMED,
//                               2 TRIGGER, 3 OUTPUT), [8] hold_reset
//   0x08    COMMAND        WO   1 COMMIT, 2 TRIGGER, 3 STOP
//   0x0C    TRIGGER_COUNT  RO   runs started since reset
//
// A command that does not apply in the current state returns
// SLVERR and changes nothing; repeating the command that got you
// into the current state (e.g. a retried TRIGGER while in OUTPUT)
// returns OKAY. Writes to read-only registers return SLVERR.
//==================================================================

module Run_Control (
  input  logic        s_axi_aclk,
  input  logic        s_axi_aresetn,

  input  logic [11:0] s_axi_awaddr,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  input  logic [11:0] s_axi_araddr,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready,

  input  logic        cfg_wr,      // pulse: a channel register write completed
  input  logic        stop_btn,    // async, active-high: same as STOP while in OUTPUT

  output logic [1:0]  state,
  output logic        hold_reset   // registered; high = waves held in reset
);

  localparam logic [31:0] ID = 32'h5357_4731;

  localparam logic [1:0] S_IDLE    = 2'd0;
  localparam logic [1:0] S_ARMED   = 2'd1;
  localparam logic [1:0] S_TRIGGER = 2'd2;
  localparam logic [1:0] S_OUTPUT  = 2'd3;

  localparam logic [31:0] CMD_COMMIT  = 32'd1;
  localparam logic [31:0] CMD_TRIGGER = 32'd2;
  localparam logic [31:0] CMD_STOP    = 32'd3;

  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] SLVERR = 2'b10;

  (* ASYNC_REG = "TRUE" *) logic [1:0] stop_sync;
  logic [31:0] trigger_count;

  always_ff @(posedge s_axi_aclk) begin
    stop_sync <= {stop_sync[0], stop_btn};
  end

  //----------------------------------------------------------------
  // Write path (same handshake scheme as Channel_Regs)
  //----------------------------------------------------------------

  logic        aw_held, w_held, write_go;
  logic [9:0]  aw_word;
  logic [31:0] w_data;

  assign s_axi_awready = ~aw_held;
  assign s_axi_wready  = ~w_held;
  assign write_go      = aw_held & w_held & (~s_axi_bvalid | s_axi_bready);

  always_ff @(posedge s_axi_aclk) begin
    if (s_axi_awvalid && s_axi_awready) aw_word <= s_axi_awaddr[11:2];
    if (s_axi_wvalid  && s_axi_wready)  w_data  <= s_axi_wdata;
  end

  // Next state and response for a write, given the current state
  logic [1:0] cmd_next;
  logic [1:0] cmd_resp;

  always_comb begin
    cmd_next = state;
    cmd_resp = SLVERR;
    if (aw_word == 10'd2) begin
      case (w_data)
        CMD_COMMIT: begin
          if (state == S_ARMED)        begin cmd_next = S_TRIGGER; cmd_resp = OKAY; end
          else if (state == S_TRIGGER) begin                       cmd_resp = OKAY; end
        end
        CMD_TRIGGER: begin
          if (state == S_TRIGGER)      begin cmd_next = S_OUTPUT;  cmd_resp = OKAY; end
          else if (state == S_OUTPUT)  begin                       cmd_resp = OKAY; end
        end
        CMD_STOP: begin
          if (state == S_OUTPUT)       begin cmd_next = S_IDLE;    cmd_resp = OKAY; end
          else if (state == S_IDLE)    begin                       cmd_resp = OKAY; end
        end
        default: ;
      endcase
    end
  end

  logic [1:0] state_next;

  always_comb begin
    state_next = state;
    if (write_go) begin
      state_next = cmd_next;
    end else if (cfg_wr) begin
      if (state != S_OUTPUT) state_next = S_ARMED;
    end else if (stop_sync[1] && state == S_OUTPUT) begin
      state_next = S_IDLE;
    end
  end

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      aw_held       <= 1'b0;
      w_held        <= 1'b0;
      s_axi_bvalid  <= 1'b0;
      s_axi_bresp   <= OKAY;
      state         <= S_IDLE;
      hold_reset    <= 1'b1;
      trigger_count <= '0;
    end else begin
      if (s_axi_awvalid && s_axi_awready) aw_held <= 1'b1;
      if (s_axi_wvalid  && s_axi_wready)  w_held  <= 1'b1;
      if (write_go) begin
        aw_held      <= 1'b0;
        w_held       <= 1'b0;
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= cmd_resp;
      end else if (s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      state      <= state_next;
      hold_reset <= (state_next != S_OUTPUT);
      if (state != S_OUTPUT && state_next == S_OUTPUT) trigger_count <= trigger_count + 1'b1;
    end
  end

  //----------------------------------------------------------------
  // Read path
  //----------------------------------------------------------------

  assign s_axi_arready = ~s_axi_rvalid;
  assign s_axi_rresp   = OKAY;

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      s_axi_rvalid <= 1'b0;
    end else if (s_axi_arvalid && s_axi_arready) begin
      s_axi_rvalid <= 1'b1;
    end else if (s_axi_rready) begin
      s_axi_rvalid <= 1'b0;
    end
  end

  always_ff @(posedge s_axi_aclk) begin
    if (s_axi_arvalid && s_axi_arready) begin
      case (s_axi_araddr[11:2])
        10'd0:   s_axi_rdata <= ID;
        10'd1:   s_axi_rdata <= {23'h0, hold_reset, 6'h0, state};
        10'd3:   s_axi_rdata <= trigger_count;
        default: s_axi_rdata <= 32'h0;
      endcase
    end
  end

endmodule

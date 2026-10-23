`timescale 1ns / 1ps

//==================================================================
// Mdio_Phy_Init
//
// Brings up the SP701's Marvell 88E1111 RGMII PHY:
//   1. holds phy_reset_n low for RESET_HOLD_CYCLES, then waits
//      RESET_WAIT_CYCLES for the PHY to come out of reset;
//   2. scans MDIO addresses 0-31 for the Marvell OUI (register 2 =
//      0x0141), since the board files don't give the PHY address;
//   3. sets register 20 bits 7 and 1 (RGMII RX and TX clock delay)
//      with a read-modify-write, then soft-resets the PHY (register
//      0 bit 15) so the new delays take effect.
// This design relies on those PHY delays instead of a 90-degree TX
// clock (there is no BUFG left for one).
// If no PHY answers, the scan repeats after RESET_WAIT_CYCLES.
// MDC = clk / (2 * MDC_DIV): 2.5 MHz from 125 MHz by default.
//==================================================================

module Mdio_Phy_Init #(
  parameter int unsigned RESET_HOLD_CYCLES = 1_250_000,  // 10 ms at 125 MHz
  parameter int unsigned RESET_WAIT_CYCLES = 625_000,    // 5 ms
  parameter int unsigned MDC_DIV           = 25
)(
  input  logic       clk,
  input  logic       rst,

  output logic       phy_reset_n,
  output logic       mdc,
  output logic       mdio_o,
  output logic       mdio_oe,
  input  logic       mdio_i,

  output logic       done,       // PHY found and configured
  output logic [4:0] phy_addr
);

  localparam logic [15:0] MARVELL_ID1   = 16'h0141;
  localparam logic [15:0] REG20_DELAYS  = 16'h0082;  // bit 7 RX delay, bit 1 TX delay
  localparam logic [15:0] REG0_SOFT_RST = 16'h8000;

  //----------------------------------------------------------------
  // MDC and one-cycle strobes on its edges
  //----------------------------------------------------------------

  logic [$clog2(MDC_DIV)-1:0] div_cnt;
  logic mdc_fall;      // one cycle after MDC falls
  logic mdc_rising;    // the cycle in which MDC is about to rise

  assign mdc_rising = (div_cnt == MDC_DIV - 1) && !mdc;

  always_ff @(posedge clk) begin
    mdc_fall <= 1'b0;
    if (rst) begin
      div_cnt <= '0;
      mdc     <= 1'b0;
    end else if (div_cnt == MDC_DIV - 1) begin
      div_cnt  <= '0;
      mdc      <= ~mdc;
      mdc_fall <= mdc;
    end else begin
      div_cnt <= div_cnt + 1'b1;
    end
  end

  //----------------------------------------------------------------
  // MDIO frame engine (clause 22). Bits are driven after MDC falls
  // and sampled by the PHY when it rises. Read data is sampled just
  // before MDC rises, since the PHY may change it right after.
  //----------------------------------------------------------------

  logic        f_start, f_read, f_busy, f_done;
  logic [4:0]  f_phy, f_reg;
  logic [15:0] f_wdata, f_rdata;
  logic [63:0] f_shift;
  logic [6:0]  f_bit;

  always_ff @(posedge clk) begin
    f_done <= 1'b0;
    if (rst) begin
      f_busy  <= 1'b0;
      mdio_oe <= 1'b0;
      mdio_o  <= 1'b1;
    end else if (!f_busy) begin
      mdio_oe <= 1'b0;
      if (f_start) begin
        f_shift <= {32'hFFFF_FFFF, 2'b01, (f_read ? 2'b10 : 2'b01), f_phy, f_reg,
                    (f_read ? 2'b11 : 2'b10), (f_read ? 16'hFFFF : f_wdata)};
        f_bit   <= '0;
        f_busy  <= 1'b1;
      end
    end else begin
      if (mdc_fall) begin
        if (f_bit == 7'd64) begin
          mdio_oe <= 1'b0;
          f_busy  <= 1'b0;
          f_done  <= 1'b1;
        end else begin
          mdio_o  <= f_shift[63];
          mdio_oe <= !(f_read && f_bit >= 7'd46);
          f_shift <= {f_shift[62:0], 1'b1};
          f_bit   <= f_bit + 1'b1;
        end
      end
      if (mdc_rising && f_read && f_bit >= 7'd49) begin
        f_rdata <= {f_rdata[14:0], mdio_i};
      end
    end
  end

  //----------------------------------------------------------------
  // Bring-up sequence
  //----------------------------------------------------------------

  typedef enum logic [3:0] {
    P_RESET, P_WAIT, P_SCAN, P_SCAN_WAIT,
    P_RD20, P_RD20_WAIT, P_WR20, P_WR20_WAIT,
    P_RD0,  P_RD0_WAIT,  P_WR0,  P_WR0_WAIT, P_DONE
  } p_state_t;

  p_state_t    p_state;
  logic [31:0] p_cnt;
  logic [4:0]  scan_addr;

  always_ff @(posedge clk) begin
    f_start <= 1'b0;
    if (rst) begin
      p_state     <= P_RESET;
      p_cnt       <= '0;
      phy_reset_n <= 1'b0;
      done        <= 1'b0;
      phy_addr    <= '0;
      scan_addr   <= '0;
    end else begin
      case (p_state)
        P_RESET: begin
          phy_reset_n <= 1'b0;
          p_cnt       <= p_cnt + 1'b1;
          if (p_cnt >= RESET_HOLD_CYCLES - 1) begin
            phy_reset_n <= 1'b1;
            p_cnt       <= '0;
            p_state     <= P_WAIT;
          end
        end
        P_WAIT: begin
          p_cnt <= p_cnt + 1'b1;
          if (p_cnt >= RESET_WAIT_CYCLES - 1) begin
            scan_addr <= '0;
            p_state   <= P_SCAN;
          end
        end
        P_SCAN: begin
          f_start <= 1'b1; f_read <= 1'b1; f_phy <= scan_addr; f_reg <= 5'd2;
          p_state <= P_SCAN_WAIT;
        end
        P_SCAN_WAIT: begin
          if (f_done) begin
            if (f_rdata == MARVELL_ID1) begin
              phy_addr <= scan_addr;
              p_state  <= P_RD20;
            end else if (scan_addr == 5'd31) begin
              p_cnt   <= '0;
              p_state <= P_WAIT;
            end else begin
              scan_addr <= scan_addr + 1'b1;
              p_state   <= P_SCAN;
            end
          end
        end
        P_RD20: begin
          f_start <= 1'b1; f_read <= 1'b1; f_phy <= phy_addr; f_reg <= 5'd20;
          p_state <= P_RD20_WAIT;
        end
        P_RD20_WAIT: if (f_done) p_state <= P_WR20;
        P_WR20: begin
          f_start <= 1'b1; f_read <= 1'b0; f_phy <= phy_addr; f_reg <= 5'd20;
          f_wdata <= f_rdata | REG20_DELAYS;
          p_state <= P_WR20_WAIT;
        end
        P_WR20_WAIT: if (f_done) p_state <= P_RD0;
        P_RD0: begin
          f_start <= 1'b1; f_read <= 1'b1; f_phy <= phy_addr; f_reg <= 5'd0;
          p_state <= P_RD0_WAIT;
        end
        P_RD0_WAIT: if (f_done) p_state <= P_WR0;
        P_WR0: begin
          f_start <= 1'b1; f_read <= 1'b0; f_phy <= phy_addr; f_reg <= 5'd0;
          f_wdata <= f_rdata | REG0_SOFT_RST;
          p_state <= P_WR0_WAIT;
        end
        P_WR0_WAIT: if (f_done) p_state <= P_DONE;
        default: done <= 1'b1;  // P_DONE
      endcase
    end
  end

endmodule

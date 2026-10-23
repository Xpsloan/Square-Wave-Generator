
#--------------------------------------------------------------------------
# ETHERNET (Host_Control): SP701 ethernet_1, Marvell 88E1111, RGMII, bank 33
#
# The verilog-ethernet CDC constraints come from the .tcl scripts imported
# next to its sources (sources_1/imports/verilog-ethernet/**/syn/vivado).
#--------------------------------------------------------------------------

set_property -dict {PACKAGE_PIN AF8 IOSTANDARD LVCMOS25} [get_ports phy_rx_clk]
set_property -dict {PACKAGE_PIN AE3 IOSTANDARD LVCMOS25} [get_ports {phy_rxd[0]}]
set_property -dict {PACKAGE_PIN AF2 IOSTANDARD LVCMOS25} [get_ports {phy_rxd[1]}]
set_property -dict {PACKAGE_PIN AF3 IOSTANDARD LVCMOS25} [get_ports {phy_rxd[2]}]
set_property -dict {PACKAGE_PIN AC2 IOSTANDARD LVCMOS25} [get_ports {phy_rxd[3]}]
set_property -dict {PACKAGE_PIN AF7 IOSTANDARD LVCMOS25} [get_ports phy_rx_ctl]

set_property -dict {PACKAGE_PIN AC3 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports phy_tx_clk]
set_property -dict {PACKAGE_PIN AF4 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[0]}]
set_property -dict {PACKAGE_PIN AD3 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[1]}]
set_property -dict {PACKAGE_PIN AF5 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[2]}]
set_property -dict {PACKAGE_PIN AC4 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[3]}]
set_property -dict {PACKAGE_PIN AD4 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports phy_tx_ctl]

set_property -dict {PACKAGE_PIN AE1 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 8} [get_ports phy_mdc]
set_property -dict {PACKAGE_PIN AC7 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 8 PULLUP true} [get_ports phy_mdio]
set_property -dict {PACKAGE_PIN AD1 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 8} [get_ports phy_reset_n]

# RX: the PHY's RGMII RX clock delay (88E1111 reg 20.7, set by
# Mdio_Phy_Init) makes RXD/RX_CTL center-aligned on RXC, valid at least
# 1.2 ns before and after each edge. Eth_Host_Link's RX IDELAYs
# (RX_IDELAY_TAPS) offset the BUFIO clock insertion delay.
create_clock -period 8.000 -name phy_rx_clk [get_ports phy_rx_clk]
set_input_delay -clock phy_rx_clk -max 2.800 [get_ports {phy_rxd[*] phy_rx_ctl}]
set_input_delay -clock phy_rx_clk -min 1.200 [get_ports {phy_rxd[*] phy_rx_ctl}]
set_input_delay -clock phy_rx_clk -clock_fall -max 2.800 -add_delay [get_ports {phy_rxd[*] phy_rx_ctl}]
set_input_delay -clock phy_rx_clk -clock_fall -min 1.200 -add_delay [get_ports {phy_rxd[*] phy_rx_ctl}]

# TX: TXC leaves edge-aligned with TXD/TX_CTL from matching ODDRs in bank
# 33 and the PHY's RGMII TX clock delay (reg 20.1) centers it, so the TX
# outputs are correct by construction and not constrained here.

# MDIO / MDC / PHY reset are slow (2.5 MHz MDC)
set_false_path -to [get_ports {phy_mdc phy_mdio phy_reset_n}]
set_false_path -from [get_ports phy_mdio]

# 125 MHz PLL next to bank 33, on the one bottom-half BUFG the locked
# clocking leaves free (see Top.xdc)
set_property LOC PLLE2_ADV_X1Y0 [get_cells host_ctrl_inst/eth_link/eth_pll]
set_property BEL BUFG [get_cells host_ctrl_inst/eth_link/eth_clk_bufg]
set_property LOC BUFGCTRL_X0Y15 [get_cells host_ctrl_inst/eth_link/eth_clk_bufg]

# Ethernet (125 MHz) <-> AXI bus (clk_sync): only Axil_Master_Cdc crosses.
# Its 4-phase handshake holds the fields stable for >= 2 destination
# cycles, so the field paths just need a bounded delay.
set eth_clk  [get_clocks -of_objects [get_pins host_ctrl_inst/eth_link/eth_pll/CLKOUT0]]
set sync_clk [get_clocks -of_objects [get_pins DWDBS_clks_init/inst/plle2_adv_inst/CLKOUT3]]
set_max_delay -datapath_only -from $eth_clk -to $sync_clk 8.000
set_max_delay -datapath_only -from $sync_clk -to $eth_clk 8.000

# Channel words feed the DDS (clk_slow / qclk_slow), which only loads
# them while held in reset; Run_Control releases it microseconds after
# the last write, so these paths only need a bounded delay.
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ host_ctrl_inst/g_ch*regs/phase_word_reg* || NAME =~ host_ctrl_inst/g_ch*regs/start_phase_reg*}] 20.000

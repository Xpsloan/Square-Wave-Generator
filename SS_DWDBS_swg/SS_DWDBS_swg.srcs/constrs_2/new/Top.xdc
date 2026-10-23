set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# SP701 constraints for square wave generator

# System clock (200 MHz LVDS, Bank 33, VCCO 2.5V)

set_property PACKAGE_PIN AE8 [get_ports clk_in1_p]
set_property PACKAGE_PIN AE7 [get_ports clk_in1_n]
set_property IOSTANDARD LVDS_25 [get_ports clk_in1_p]
set_property IOSTANDARD LVDS_25 [get_ports clk_in1_n]
create_clock -period 5.000 -name clk_in1_p [get_ports clk_in1_p]

# CPU Reset (active-high pushbutton, Bank 13, 1.8V)
set_property PACKAGE_PIN AE15    [get_ports system_reset]
set_property IOSTANDARD LVCMOS18 [get_ports system_reset]

# Square Wave Generator Reset
set_property PACKAGE_PIN AB22    [get_ports square_wave_reset] ; # North Button
set_property IOSTANDARD LVCMOS18 [get_ports square_wave_reset]

# Enable button, active-low for all channels
set_property PACKAGE_PIN AA20    [get_ports enable] ; # Middle Button
set_property IOSTANDARD LVCMOS18 [get_ports enable]


# sync clock output to measure against the other channels and ensure they are phase aligned
set_property PACKAGE_PIN F14     [get_ports clk_sync]  ; # PMOD6_PIN1
set_property IOSTANDARD LVCMOS33 [get_ports clk_sync]

# LEDs (Bank 15, 3.3V)
set_property PACKAGE_PIN J25 [get_ports {led[0]}]
set_property PACKAGE_PIN M24 [get_ports {led[1]}]

# >>> BEGIN LOCKED LOOPBACK PATH (generated) >>>
#--------------------------------------------------------------------------
# SHARED CLOCKING - LOCKED
#
# 30 of 32 BUFGCTRLs are used and the per-channel loopback BUFGs are
# LOC'd in sw*.xdc, so the remaining clock buffers and the DWDBS_clks
# PLL are pinned to the sites they were verified at.
#--------------------------------------------------------------------------

set_property BEL BUFG [get_cells DWDBS_clks_init/inst/clkf_buf]
set_property LOC BUFGCTRL_X0Y20 [get_cells DWDBS_clks_init/inst/clkf_buf]
set_property BEL BUFG [get_cells DWDBS_clks_init/inst/clkout1_buf]
set_property LOC BUFGCTRL_X0Y19 [get_cells DWDBS_clks_init/inst/clkout1_buf]
set_property BEL BUFG [get_cells DWDBS_clks_init/inst/clkout2_buf]
set_property LOC BUFGCTRL_X0Y17 [get_cells DWDBS_clks_init/inst/clkout2_buf]
set_property BEL BUFG [get_cells DWDBS_clks_init/inst/clkout3_buf]
set_property LOC BUFGCTRL_X0Y16 [get_cells DWDBS_clks_init/inst/clkout3_buf]
set_property BEL BUFG [get_cells DWDBS_clks_init/inst/clkout4_buf]
set_property LOC BUFGCTRL_X0Y18 [get_cells DWDBS_clks_init/inst/clkout4_buf]
set_property LOC PLLE2_ADV_X0Y3 [get_cells DWDBS_clks_init/inst/plle2_adv_inst]
set_property BEL BUFG [get_cells bufg_clk_200]
set_property LOC BUFGCTRL_X0Y0 [get_cells bufg_clk_200]
# <<< END LOCKED LOOPBACK PATH <<<

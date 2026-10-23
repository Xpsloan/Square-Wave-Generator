
#--------------------------------------------------------------------------
# CHANNEL 2 - FOR THE SECOND SQUARE WAVE CHANNEL, SAME ROUND-TRIP SHAPE
# AS CHANNEL 1 ABOVE (OUT THROUGH THE FMC, BACK IN, THEN OUT AS A PMOD).
#
# TODO: pin numbers below are placeholders (NOT real package pins) -
# fill in real, free FMC/PMOD pins for this board before running
# synthesis/implementation, then update the IOSTANDARDs to match
# whichever bank each pin lives in.
#--------------------------------------------------------------------------

set_property LOC OLOGIC_X1Y142 [get_cells sw0B_inst/DWDBS_system_inst/ODDR_inst]
set_property PACKAGE_PIN H6 [get_ports dirty_swo0B_p]
set_property PACKAGE_PIN G6 [get_ports dirty_swo0B_n]
set_property IOSTANDARD LVDS_25 [get_ports dirty_swo0B_p]
set_property IOSTANDARD LVDS_25 [get_ports dirty_swo0B_n]

set_property PACKAGE_PIN G4 [get_ports dirty_swi0B_p]
set_property PACKAGE_PIN F4 [get_ports dirty_swi0B_n]
set_property IOSTANDARD LVDS_25 [get_ports dirty_swi0B_p]
set_property IOSTANDARD LVDS_25 [get_ports dirty_swi0B_n]

# Clean square wave output for channel 0, wave B -> PMOD1, pin 2
set_property PACKAGE_PIN D14     [get_ports sw0B]
set_property IOSTANDARD LVCMOS33 [get_ports sw0B]

# Start marker for channel 0, wave B -> PMOD1, pin 8
set_property PACKAGE_PIN C14     [get_ports start_signal0B]
set_property IOSTANDARD LVCMOS33 [get_ports start_signal0B]
set_property IOB TRUE            [get_ports start_signal0B]

# Keep this channel's own start generator next to its output pin
create_pblock sw0B_start_signal_pblock
add_cells_to_pblock [get_pblocks sw0B_start_signal_pblock] [get_cells -quiet [list sw0B_inst/start_signal_inst]]
resize_pblock [get_pblocks sw0B_start_signal_pblock] -add {SLICE_X0Y187:SLICE_X3Y190}

# NOTE: the A23/reference_swo2 debug pin previously echoed the raw,
# uncleaned wave. SW0B_Generator no longer exposes that internal
# signal as a port, so this pin assignment was dropped. Re-add a
# port for it in SW0B_Generator.sv if that debug tap is still needed.

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets sw0B_inst/delayed_dirty_sw0B]

#--------------------------------------------------------------------------
# ROUTING CONSTRAINTS HERE TO MEET TIMING CLOSURE
#--------------------------------------------------------------------------

############################################
# FROM POS_SHIFT_REGISTERS TO POS_DDR_DATA #
############################################


set_property BEL AFF [get_cells sw0B_inst/DWDBS_system_inst/pos_ddr_data_reg]
set_property LOC SLICE_X85Y142 [get_cells sw0B_inst/DWDBS_system_inst/pos_ddr_data_reg]


set_property BEL CFF [get_cells {sw0B_inst/DWDBS_system_inst/pos_shift_reg_reg[1]}]
set_property LOC SLICE_X85Y143 [get_cells {sw0B_inst/DWDBS_system_inst/pos_shift_reg_reg[1]}]
set_property BEL BFF [get_cells {sw0B_inst/DWDBS_system_inst/pos_shift_reg_reg[0]}]
set_property LOC SLICE_X85Y143 [get_cells {sw0B_inst/DWDBS_system_inst/pos_shift_reg_reg[0]}]




set_property BEL AFF [get_cells sw0B_inst/DWDBS_system_inst/pos_sync_reset_reg]
set_property LOC SLICE_X82Y142 [get_cells sw0B_inst/DWDBS_system_inst/pos_sync_reset_reg]



set_property BEL AFF [get_cells sw0B_inst/DWDBS_system_inst/pos_pointer_reg]
set_property LOC SLICE_X83Y142 [get_cells sw0B_inst/DWDBS_system_inst/pos_pointer_reg]



############################################
# FROM NEG_SHIFT_REGISTERS TO NEG_DDR_DATA #
############################################


set_property BEL AFF [get_cells sw0B_inst/DWDBS_system_inst/neg_ddr_data_reg]
set_property LOC SLICE_X85Y140 [get_cells sw0B_inst/DWDBS_system_inst/neg_ddr_data_reg]


set_property BEL CFF [get_cells {sw0B_inst/DWDBS_system_inst/neg_shift_reg_reg[1]}]
set_property LOC SLICE_X85Y141 [get_cells {sw0B_inst/DWDBS_system_inst/neg_shift_reg_reg[1]}]
set_property BEL BFF [get_cells {sw0B_inst/DWDBS_system_inst/neg_shift_reg_reg[0]}]
set_property LOC SLICE_X85Y141 [get_cells {sw0B_inst/DWDBS_system_inst/neg_shift_reg_reg[0]}]






set_property BEL AFF [get_cells sw0B_inst/DWDBS_system_inst/neg_sync_reset_reg]
set_property LOC SLICE_X82Y141 [get_cells sw0B_inst/DWDBS_system_inst/neg_sync_reset_reg]




set_property BEL A6LUT [get_cells sw0B_inst/DWDBS_system_inst/pos_ddr_data_i_1__0]
set_property LOC SLICE_X85Y142 [get_cells sw0B_inst/DWDBS_system_inst/pos_ddr_data_i_1__0]
set_property BEL A6LUT [get_cells sw0B_inst/DWDBS_system_inst/neg_ddr_data_i_1__0]
set_property LOC SLICE_X85Y140 [get_cells sw0B_inst/DWDBS_system_inst/neg_ddr_data_i_1__0]
set_property BEL A6LUT [get_cells sw0B_inst/DWDBS_system_inst/neg_pointer_i_1__0]
set_property LOC SLICE_X83Y141 [get_cells sw0B_inst/DWDBS_system_inst/neg_pointer_i_1__0]
set_property BEL A6LUT [get_cells sw0B_inst/DWDBS_system_inst/pos_pointer_i_1__0]
set_property LOC SLICE_X83Y142 [get_cells sw0B_inst/DWDBS_system_inst/pos_pointer_i_1__0]

set_property BEL AFF [get_cells sw0B_inst/DWDBS_system_inst/neg_pointer_reg]
set_property LOC SLICE_X83Y141 [get_cells sw0B_inst/DWDBS_system_inst/neg_pointer_reg]



set_property LOCK_PINS {I2:A4 I0:A6} [get_cells sw0B_inst/DWDBS_system_inst/pos_ddr_data_i_1__0]
set_property DONT_TOUCH true         [get_cells sw0B_inst/DWDBS_system_inst/pos_ddr_data_i_1__0]

set_property LOCK_PINS {I0:A6}  [get_cells sw0B_inst/DWDBS_system_inst/pos_pointer_i_1__0]
set_property DONT_TOUCH true    [get_cells sw0B_inst/DWDBS_system_inst/pos_pointer_i_1__0]

set_property LOCK_PINS {I2:A4 I0:A6} [get_cells sw0B_inst/DWDBS_system_inst/neg_ddr_data_i_1__0]
set_property DONT_TOUCH true         [get_cells sw0B_inst/DWDBS_system_inst/neg_ddr_data_i_1__0]

set_property LOCK_PINS {I0:A6}  [get_cells sw0B_inst/DWDBS_system_inst/neg_pointer_i_1__0]
set_property DONT_TOUCH true    [get_cells sw0B_inst/DWDBS_system_inst/neg_pointer_i_1__0]






set_property FIXED_ROUTE { { CLBLM_L_CQ CLBLM_LOGIC_OUTS2 ER1BEG3 SL1BEG3 SR1BEG_S0 WL1BEG_N3 NL1BEG_N3 IMUX5 CLBLM_L_A6 } } [get_nets {sw0B_inst/DWDBS_system_inst/pos_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLM_L_BQ CLBLM_LOGIC_OUTS1 EE4BEG1 WL1BEG_N3 SR1BEG_S0 IMUX10 CLBLM_L_A4 } } [get_nets {sw0B_inst/DWDBS_system_inst/pos_shift_reg[0]}]
set_property FIXED_ROUTE { { CLBLL_LL_AQ CLBLL_LOGIC_OUTS4 EE4BEG0 NE6BEG0 SW6BEG3 NL1BEG_N3 IMUX_L5 CLBLL_L_A6 }  } [get_nets sw0B_inst/DWDBS_system_inst/pos_sync_reset]
set_property FIXED_ROUTE { { CLBLM_L_CQ CLBLM_LOGIC_OUTS2 ER1BEG3 SL1BEG3 SR1BEG_S0 WL1BEG_N3 NL1BEG_N3 IMUX5 CLBLM_L_A6 } } [get_nets {sw0B_inst/DWDBS_system_inst/neg_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLM_L_BQ CLBLM_LOGIC_OUTS1 EE4BEG1 WL1BEG_N3 SR1BEG_S0 IMUX10 CLBLM_L_A4 } } [get_nets {sw0B_inst/DWDBS_system_inst/neg_shift_reg[0]}]
set_property FIXED_ROUTE { { CLBLL_LL_AQ CLBLL_LOGIC_OUTS4 EE4BEG0 NE6BEG0 SW6BEG3 NL1BEG_N3 IMUX_L5 CLBLL_L_A6 }  } [get_nets {sw0B_inst/DWDBS_system_inst/neg_sync_reset}]

# >>> BEGIN LOCKED LOOPBACK PATH (generated) >>>
#--------------------------------------------------------------------------
# LOOPBACK RETURN PATH - SKEW-MATCHED AND LOCKED
#
# sw0B_inst/delayed_dirty_sw0B (IDELAYE2 -> BUFG) is hand-routed to
# the same delay as the other 7 channels (2.69 ns slow-max / 1.28 ns fast-min, all 8 within 15 ps).
# Everything after the IDELAY (BUFG, cleaner MMCM + its BUFGs, the
# enable gate LUT and its routes) is locked too, so changing
# DIRTY_IDELAY_TAPS and rebuilding does not move or reroute anything.
# Tied to the current pins/IP: regenerate if those change.
#--------------------------------------------------------------------------

# IDELAYE2 -> BUFG (skew-matched)
set_property BEL IDELAYE2 [get_cells sw0B_inst/idelay_dirty_sw0B]
set_property LOC IDELAY_X1Y144 [get_cells sw0B_inst/idelay_dirty_sw0B]
set_property BEL BUFG [get_cells sw0B_inst/buf_dirty_sw0B]
set_property LOC BUFGCTRL_X0Y24 [get_cells sw0B_inst/buf_dirty_sw0B]
set_property FIXED_ROUTE { RIOI_IDELAY0_DATAOUT RIOI_ILOGIC0_DDLY IOI_ILOGIC0_O IOI_LOGIC_OUTS18_1 INT_INTERFACE_LOGIC_OUTS18 WW4BEG0 LV18 <1>LH0 LV18 SS6BEG0 SE2BEG0 SS2BEG0 WW4BEG1 WW2BEG0 NW6BEG1 SW2BEG0 IMUX24 CLK_BUFG_BUFGCTRL8_I0 } [get_nets {sw0B_inst/delayed_dirty_sw0B}]

# Jitter-cleaner MMCM and its BUFGs
set_property LOC MMCME2_ADV_X0Y2 [get_cells sw0B_inst/sw0B_cleaner_inst/inst/mmcm_adv_inst]
set_property BEL BUFG [get_cells sw0B_inst/sw0B_cleaner_inst/inst/clkf_buf]
set_property LOC BUFGCTRL_X0Y25 [get_cells sw0B_inst/sw0B_cleaner_inst/inst/clkf_buf]
set_property BEL BUFG [get_cells sw0B_inst/sw0B_cleaner_inst/inst/clkout1_buf]
set_property LOC BUFGCTRL_X0Y26 [get_cells sw0B_inst/sw0B_cleaner_inst/inst/clkout1_buf]

# Enable gate LUT next to the sw0B OBUF, and its two routes
set_property BEL A6LUT [get_cells sw0B_inst/sw0B_OBUF_inst_i_1]
set_property LOC SLICE_X1Y190 [get_cells sw0B_inst/sw0B_OBUF_inst_i_1]
set_property LOCK_PINS {I0:A6 I1:A5} [get_cells sw0B_inst/sw0B_OBUF_inst_i_1]
set_property DONT_TOUCH true [get_cells sw0B_inst/sw0B_OBUF_inst_i_1]
set_property FIXED_ROUTE { CLK_BUFG_BUFGCTRL10_O CLK_BUFG_CK_GCLK26 CLK_BUFG_REBUF_R_CK_GCLK26_TOP CLK_BUFG_REBUF_R_CK_GCLK26_TOP CLK_BUFG_REBUF_R_CK_GCLK26_TOP CLK_HROW_CK_MUX_OUT_L9 CLK_HROW_CK_HCLK_OUT_L9 CLK_HROW_CK_BUFHCLK_L9 <14>HCLK_LEAF_CLK_B_TOPL4 <16>GCLK_L_B10_WEST GFAN1 IMUX_L5 CLBLL_L_A6 } [get_nets {sw0B_inst/clean_sw0B}]
set_property FIXED_ROUTE { CLBLL_L_A CLBLL_L_AMUX CLBLL_LOGIC_OUTS16 NW2BEG2 SW2BEG1 IMUX_L34 IOI_OLOGIC0_D1 LIOI_OLOGIC0_OQ LIOI_O0 } [get_nets {sw0B_OBUF}]
# <<< END LOCKED LOOPBACK PATH <<<

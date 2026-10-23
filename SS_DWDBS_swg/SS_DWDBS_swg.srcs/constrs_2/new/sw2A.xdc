
#--------------------------------------------------------------------------
# CHANNEL 2 - SQUARE WAVE A, SAME ROUND-TRIP SHAPE AS CHANNEL 0 ABOVE
# (OUT THROUGH THE FMC, BACK IN, THEN OUT AS A PMOD).
#
# NOTE: dirty_swo2A/dirty_swi2A pin numbers below are now channel-2-
# specific (no longer copied from sw0B.xdc). Double-check they're free,
# and that the IOSTANDARDs match whichever bank each pin lives in,
# before synthesizing this channel standalone.
#--------------------------------------------------------------------------

set_property LOC OLOGIC_X1Y116   [get_cells sw2A_inst/DWDBS_system_inst/ODDR_inst]
set_property PACKAGE_PIN M5      [get_ports dirty_swo2A_p]
set_property PACKAGE_PIN M4      [get_ports dirty_swo2A_n]
set_property IOSTANDARD LVDS_25  [get_ports dirty_swo2A_p]
set_property IOSTANDARD LVDS_25  [get_ports dirty_swo2A_n]

set_property PACKAGE_PIN N6      [get_ports dirty_swi2A_p]
set_property PACKAGE_PIN M6      [get_ports dirty_swi2A_n]
set_property IOSTANDARD LVDS_25  [get_ports dirty_swi2A_p]
set_property IOSTANDARD LVDS_25  [get_ports dirty_swi2A_n]

# Clean square wave output for channel 2, wave A -> PMOD3, pin 1
set_property PACKAGE_PIN C22     [get_ports sw2A]
set_property IOSTANDARD LVCMOS33 [get_ports sw2A]

# Start marker for channel 2, wave A -> PMOD3, pin 7
set_property PACKAGE_PIN D21     [get_ports start_signal2A]
set_property IOSTANDARD LVCMOS33 [get_ports start_signal2A]
set_property IOB TRUE            [get_ports start_signal2A]

# Keep this channel's own start generator next to its output pin
create_pblock sw2A_start_signal_pblock
add_cells_to_pblock [get_pblocks sw2A_start_signal_pblock] [get_cells -quiet [list sw2A_inst/start_signal_inst]]
resize_pblock [get_pblocks sw2A_start_signal_pblock] -add {SLICE_X0Y160:SLICE_X3Y163}

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets sw2A_inst/delayed_dirty_sw2A]

#--------------------------------------------------------------------------
# ROUTING CONSTRAINTS HERE TO MEET TIMING CLOSURE
#--------------------------------------------------------------------------

############################################
# FROM POS_SHIFT_REGISTERS TO POS_DDR_DATA #
############################################


set_property BEL AFF           [get_cells sw2A_inst/DWDBS_system_inst/pos_ddr_data_reg]
set_property LOC SLICE_X85Y116 [get_cells sw2A_inst/DWDBS_system_inst/pos_ddr_data_reg]


set_property BEL CFF           [get_cells sw2A_inst/DWDBS_system_inst/pos_shift_reg_reg[1]]
set_property LOC SLICE_X85Y117 [get_cells sw2A_inst/DWDBS_system_inst/pos_shift_reg_reg[1]]
set_property BEL BFF           [get_cells sw2A_inst/DWDBS_system_inst/pos_shift_reg_reg[0]]
set_property LOC SLICE_X85Y117 [get_cells sw2A_inst/DWDBS_system_inst/pos_shift_reg_reg[0]]

set_property FIXED_ROUTE { { CLBLM_L_CQ CLBLM_LOGIC_OUTS2 ER1BEG3 SL1BEG3 SR1BEG_S0 WL1BEG_N3 NL1BEG_N3 IMUX5 CLBLM_L_A6 } } [get_nets {sw2A_inst/DWDBS_system_inst/pos_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLM_L_BQ CLBLM_LOGIC_OUTS1 EE4BEG1 WL1BEG_N3 SR1BEG_S0 IMUX10 CLBLM_L_A4 } } [get_nets {sw2A_inst/DWDBS_system_inst/pos_shift_reg[0]}]

set_property BEL A6LUT               [get_cells sw2A_inst/DWDBS_system_inst/pos_ddr_data_i_1__3]
set_property LOC SLICE_X85Y116       [get_cells sw2A_inst/DWDBS_system_inst/pos_ddr_data_i_1__3]
set_property LOCK_PINS {I2:A4 I0:A6} [get_cells sw2A_inst/DWDBS_system_inst/pos_ddr_data_i_1__3]
set_property DONT_TOUCH true         [get_cells sw2A_inst/DWDBS_system_inst/pos_ddr_data_i_1__3]


set_property BEL AFF            [get_cells sw2A_inst/DWDBS_system_inst/pos_sync_reset_reg]
set_property LOC SLICE_X82Y116  [get_cells sw2A_inst/DWDBS_system_inst/pos_sync_reset_reg]

set_property FIXED_ROUTE { { CLBLL_LL_AQ CLBLL_LOGIC_OUTS4 EE4BEG0 NE6BEG0 SW6BEG3 NL1BEG_N3 IMUX_L5 CLBLL_L_A6 }  } [get_nets sw2A_inst/DWDBS_system_inst/pos_sync_reset]

set_property BEL A6LUT          [get_cells sw2A_inst/DWDBS_system_inst/pos_pointer_i_1__3]
set_property LOC SLICE_X83Y116  [get_cells sw2A_inst/DWDBS_system_inst/pos_pointer_i_1__3]
set_property LOCK_PINS {I0:A6}  [get_cells sw2A_inst/DWDBS_system_inst/pos_pointer_i_1__3]
set_property DONT_TOUCH true    [get_cells sw2A_inst/DWDBS_system_inst/pos_pointer_i_1__3]

set_property BEL AFF            [get_cells sw2A_inst/DWDBS_system_inst/pos_pointer_reg]
set_property LOC SLICE_X83Y116  [get_cells sw2A_inst/DWDBS_system_inst/pos_pointer_reg]



############################################
# FROM NEG_SHIFT_REGISTERS TO NEG_DDR_DATA #
############################################


set_property BEL AFF           [get_cells sw2A_inst/DWDBS_system_inst/neg_ddr_data_reg]
set_property LOC SLICE_X85Y114 [get_cells sw2A_inst/DWDBS_system_inst/neg_ddr_data_reg]


set_property BEL CFF           [get_cells sw2A_inst/DWDBS_system_inst/neg_shift_reg_reg[1]]
set_property LOC SLICE_X85Y115 [get_cells sw2A_inst/DWDBS_system_inst/neg_shift_reg_reg[1]]
set_property BEL BFF           [get_cells sw2A_inst/DWDBS_system_inst/neg_shift_reg_reg[0]]
set_property LOC SLICE_X85Y115 [get_cells sw2A_inst/DWDBS_system_inst/neg_shift_reg_reg[0]]


set_property FIXED_ROUTE { { CLBLM_L_CQ CLBLM_LOGIC_OUTS2 ER1BEG3 SL1BEG3 SR1BEG_S0 WL1BEG_N3 NL1BEG_N3 IMUX5 CLBLM_L_A6 } } [get_nets {sw2A_inst/DWDBS_system_inst/neg_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLM_L_BQ CLBLM_LOGIC_OUTS1 EE4BEG1 WL1BEG_N3 SR1BEG_S0 IMUX10 CLBLM_L_A4 } } [get_nets {sw2A_inst/DWDBS_system_inst/neg_shift_reg[0]}]


set_property BEL A6LUT               [get_cells sw2A_inst/DWDBS_system_inst/neg_ddr_data_i_1__3]
set_property LOC SLICE_X85Y114       [get_cells sw2A_inst/DWDBS_system_inst/neg_ddr_data_i_1__3]
set_property LOCK_PINS {I2:A4 I0:A6} [get_cells sw2A_inst/DWDBS_system_inst/neg_ddr_data_i_1__3]
set_property DONT_TOUCH true         [get_cells sw2A_inst/DWDBS_system_inst/neg_ddr_data_i_1__3]


set_property BEL AFF            [get_cells sw2A_inst/DWDBS_system_inst/neg_sync_reset_reg]
set_property LOC SLICE_X82Y115  [get_cells sw2A_inst/DWDBS_system_inst/neg_sync_reset_reg]

set_property FIXED_ROUTE { { CLBLL_LL_AQ CLBLL_LOGIC_OUTS4 EE4BEG0 NE6BEG0 SW6BEG3 NL1BEG_N3 IMUX_L5 CLBLL_L_A6 }  } [get_nets {sw2A_inst/DWDBS_system_inst/neg_sync_reset}]

set_property BEL A6LUT          [get_cells sw2A_inst/DWDBS_system_inst/neg_pointer_i_1__3]
set_property LOC SLICE_X83Y115  [get_cells sw2A_inst/DWDBS_system_inst/neg_pointer_i_1__3]
set_property LOCK_PINS {I0:A6}  [get_cells sw2A_inst/DWDBS_system_inst/neg_pointer_i_1__3]
set_property DONT_TOUCH true    [get_cells sw2A_inst/DWDBS_system_inst/neg_pointer_i_1__3]

set_property BEL AFF            [get_cells sw2A_inst/DWDBS_system_inst/neg_pointer_reg]
set_property LOC SLICE_X83Y115  [get_cells sw2A_inst/DWDBS_system_inst/neg_pointer_reg]

# >>> BEGIN LOCKED LOOPBACK PATH (generated) >>>
#--------------------------------------------------------------------------
# LOOPBACK RETURN PATH - SKEW-MATCHED AND LOCKED
#
# sw2A_inst/delayed_dirty_sw2A (IDELAYE2 -> BUFG) is hand-routed to
# the same delay as the other 7 channels (2.69 ns slow-max / 1.28 ns fast-min, all 8 within 15 ps).
# Everything after the IDELAY (BUFG, cleaner MMCM + its BUFGs, the
# enable gate LUT and its routes) is locked too, so changing
# DIRTY_IDELAY_TAPS and rebuilding does not move or reroute anything.
# Tied to the current pins/IP: regenerate if those change.
#--------------------------------------------------------------------------

# IDELAYE2 -> BUFG (skew-matched)
set_property BEL IDELAYE2 [get_cells sw2A_inst/idelay_dirty_sw2A]
set_property LOC IDELAY_X1Y118 [get_cells sw2A_inst/idelay_dirty_sw2A]
set_property BEL BUFG [get_cells sw2A_inst/buf_dirty_sw2A]
set_property LOC BUFGCTRL_X0Y3 [get_cells sw2A_inst/buf_dirty_sw2A]
set_property FIXED_ROUTE { RIOI_IDELAY0_DATAOUT RIOI_ILOGIC0_DDLY IOI_ILOGIC0_O IOI_LOGIC_OUTS18_1 INT_INTERFACE_LOGIC_OUTS18 WW4BEG0 LV18 <1>LH0 SW6BEG0 SW6BEG0 SE2BEG0 EE2BEG0 SW6BEG0 LV_L0 WW4BEG1 WR1BEG2 IMUX27 CLK_BUFG_BUFGCTRL3_I0 } [get_nets {sw2A_inst/delayed_dirty_sw2A}]

# Jitter-cleaner MMCM and its BUFGs
set_property LOC MMCME2_ADV_X0Y0 [get_cells sw2A_inst/sw2A_cleaner_inst/inst/mmcm_adv_inst]
set_property BEL BUFG [get_cells sw2A_inst/sw2A_cleaner_inst/inst/clkf_buf]
set_property LOC BUFGCTRL_X0Y4 [get_cells sw2A_inst/sw2A_cleaner_inst/inst/clkf_buf]
set_property BEL BUFG [get_cells sw2A_inst/sw2A_cleaner_inst/inst/clkout1_buf]
set_property LOC BUFGCTRL_X0Y5 [get_cells sw2A_inst/sw2A_cleaner_inst/inst/clkout1_buf]

# Enable gate LUT next to the sw2A OBUF, and its two routes
set_property BEL A6LUT [get_cells sw2A_inst/sw2A_OBUF_inst_i_1]
set_property LOC SLICE_X1Y148 [get_cells sw2A_inst/sw2A_OBUF_inst_i_1]
set_property LOCK_PINS {I0:A6 I1:A5} [get_cells sw2A_inst/sw2A_OBUF_inst_i_1]
set_property DONT_TOUCH true [get_cells sw2A_inst/sw2A_OBUF_inst_i_1]
set_property FIXED_ROUTE { CLK_BUFG_BUFGCTRL5_O CLK_BUFG_CK_GCLK5 CLK_BUFG_REBUF_R_CK_GCLK5_TOP CLK_HROW_CK_MUX_OUT_L5 CLK_HROW_CK_HCLK_OUT_L5 CLK_HROW_CK_BUFHCLK_L5 <11>HCLK_LEAF_CLK_B_TOP5 <24>GCLK_B5_WEST GFAN1 IMUX_L5 CLBLL_L_A6 } [get_nets {sw2A_inst/clean_sw2A}]
set_property FIXED_ROUTE { CLBLL_L_A CLBLL_LOGIC_OUTS8 NW2BEG0 NW2BEG0 NW2BEG0 NN2BEG0 SR1BEG_S0 IMUX_L34 IOI_OLOGIC0_D1 LIOI_OLOGIC0_OQ LIOI_O0 } [get_nets {sw2A_OBUF}]
# <<< END LOCKED LOOPBACK PATH <<<

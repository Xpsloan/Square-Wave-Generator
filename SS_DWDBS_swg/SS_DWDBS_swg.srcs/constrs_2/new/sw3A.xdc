
#--------------------------------------------------------------------------
# CHANNEL 3 - SQUARE WAVE A, SAME ROUND-TRIP SHAPE AS CHANNEL 0 ABOVE
# (OUT THROUGH THE FMC, BACK IN, THEN OUT AS A PMOD).
#
# NOTE: dirty_swo3A/dirty_swi3A pin numbers below are now channel-3-
# specific (no longer copied from sw0B.xdc). Double-check they're free,
# and that the IOSTANDARDs match whichever bank each pin lives in,
# before synthesizing this channel standalone.
#--------------------------------------------------------------------------

set_property LOC OLOGIC_X1Y168   [get_cells sw3A_inst/DWDBS_system_inst/ODDR_inst]
set_property PACKAGE_PIN F7      [get_ports dirty_swo3A_p]
set_property PACKAGE_PIN E7      [get_ports dirty_swo3A_n]
set_property IOSTANDARD LVDS_25  [get_ports dirty_swo3A_p]
set_property IOSTANDARD LVDS_25  [get_ports dirty_swo3A_n]

set_property PACKAGE_PIN E6      [get_ports dirty_swi3A_p]
set_property PACKAGE_PIN D6      [get_ports dirty_swi3A_n]
set_property IOSTANDARD LVDS_25  [get_ports dirty_swi3A_p]
set_property IOSTANDARD LVDS_25  [get_ports dirty_swi3A_n]

# Clean square wave output for channel 3, wave A -> PMOD4, pin 1
set_property PACKAGE_PIN A23     [get_ports sw3A]
set_property IOSTANDARD LVCMOS33 [get_ports sw3A]

# Start marker for channel 3, wave A -> PMOD4, pin 7
set_property PACKAGE_PIN B22     [get_ports start_signal3A]
set_property IOSTANDARD LVCMOS33 [get_ports start_signal3A]
set_property IOB TRUE            [get_ports start_signal3A]

# Keep this channel's own start generator next to its output pin
create_pblock sw3A_start_signal_pblock
add_cells_to_pblock [get_pblocks sw3A_start_signal_pblock] [get_cells -quiet [list sw3A_inst/start_signal_inst]]
resize_pblock [get_pblocks sw3A_start_signal_pblock] -add {SLICE_X0Y152:SLICE_X3Y155}

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets sw3A_inst/delayed_dirty_sw3A]

#--------------------------------------------------------------------------
# ROUTING CONSTRAINTS HERE TO MEET TIMING CLOSURE
#--------------------------------------------------------------------------

############################################
# FROM POS_SHIFT_REGISTERS TO POS_DDR_DATA #
############################################


set_property BEL AFF           [get_cells sw3A_inst/DWDBS_system_inst/pos_ddr_data_reg]
set_property LOC SLICE_X85Y168 [get_cells sw3A_inst/DWDBS_system_inst/pos_ddr_data_reg]


set_property BEL CFF           [get_cells sw3A_inst/DWDBS_system_inst/pos_shift_reg_reg[1]]
set_property LOC SLICE_X85Y169 [get_cells sw3A_inst/DWDBS_system_inst/pos_shift_reg_reg[1]]
set_property BEL BFF           [get_cells sw3A_inst/DWDBS_system_inst/pos_shift_reg_reg[0]]
set_property LOC SLICE_X85Y169 [get_cells sw3A_inst/DWDBS_system_inst/pos_shift_reg_reg[0]]

set_property FIXED_ROUTE { { CLBLM_L_CQ CLBLM_LOGIC_OUTS2 ER1BEG3 SL1BEG3 SR1BEG_S0 WL1BEG_N3 NL1BEG_N3 IMUX5 CLBLM_L_A6 } } [get_nets {sw3A_inst/DWDBS_system_inst/pos_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLM_L_BQ CLBLM_LOGIC_OUTS1 EE4BEG1 WL1BEG_N3 SR1BEG_S0 IMUX10 CLBLM_L_A4 } } [get_nets {sw3A_inst/DWDBS_system_inst/pos_shift_reg[0]}]

set_property BEL A6LUT               [get_cells sw3A_inst/DWDBS_system_inst/pos_ddr_data_i_1__5]
set_property LOC SLICE_X85Y168       [get_cells sw3A_inst/DWDBS_system_inst/pos_ddr_data_i_1__5]
set_property LOCK_PINS {I2:A4 I0:A6} [get_cells sw3A_inst/DWDBS_system_inst/pos_ddr_data_i_1__5]
set_property DONT_TOUCH true         [get_cells sw3A_inst/DWDBS_system_inst/pos_ddr_data_i_1__5]


set_property BEL AFF            [get_cells sw3A_inst/DWDBS_system_inst/pos_sync_reset_reg]
set_property LOC SLICE_X82Y168  [get_cells sw3A_inst/DWDBS_system_inst/pos_sync_reset_reg]

set_property FIXED_ROUTE { { CLBLL_LL_AQ CLBLL_LOGIC_OUTS4 EE4BEG0 NE6BEG0 SW6BEG3 NL1BEG_N3 IMUX_L5 CLBLL_L_A6 }  } [get_nets sw3A_inst/DWDBS_system_inst/pos_sync_reset]

set_property BEL A6LUT          [get_cells sw3A_inst/DWDBS_system_inst/pos_pointer_i_1__5]
set_property LOC SLICE_X83Y168  [get_cells sw3A_inst/DWDBS_system_inst/pos_pointer_i_1__5]
set_property LOCK_PINS {I0:A6}  [get_cells sw3A_inst/DWDBS_system_inst/pos_pointer_i_1__5]
set_property DONT_TOUCH true    [get_cells sw3A_inst/DWDBS_system_inst/pos_pointer_i_1__5]

set_property BEL AFF            [get_cells sw3A_inst/DWDBS_system_inst/pos_pointer_reg]
set_property LOC SLICE_X83Y168  [get_cells sw3A_inst/DWDBS_system_inst/pos_pointer_reg]



############################################
# FROM NEG_SHIFT_REGISTERS TO NEG_DDR_DATA #
############################################


set_property BEL AFF           [get_cells sw3A_inst/DWDBS_system_inst/neg_ddr_data_reg]
set_property LOC SLICE_X85Y166 [get_cells sw3A_inst/DWDBS_system_inst/neg_ddr_data_reg]


set_property BEL CFF           [get_cells sw3A_inst/DWDBS_system_inst/neg_shift_reg_reg[1]]
set_property LOC SLICE_X85Y167 [get_cells sw3A_inst/DWDBS_system_inst/neg_shift_reg_reg[1]]
set_property BEL BFF           [get_cells sw3A_inst/DWDBS_system_inst/neg_shift_reg_reg[0]]
set_property LOC SLICE_X85Y167 [get_cells sw3A_inst/DWDBS_system_inst/neg_shift_reg_reg[0]]


set_property FIXED_ROUTE { { CLBLM_L_CQ CLBLM_LOGIC_OUTS2 ER1BEG3 SL1BEG3 SR1BEG_S0 WL1BEG_N3 NL1BEG_N3 IMUX5 CLBLM_L_A6 } } [get_nets {sw3A_inst/DWDBS_system_inst/neg_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLM_L_BQ CLBLM_LOGIC_OUTS1 EE4BEG1 WL1BEG_N3 SR1BEG_S0 IMUX10 CLBLM_L_A4 } } [get_nets {sw3A_inst/DWDBS_system_inst/neg_shift_reg[0]}]


set_property BEL A6LUT               [get_cells sw3A_inst/DWDBS_system_inst/neg_ddr_data_i_1__5]
set_property LOC SLICE_X85Y166       [get_cells sw3A_inst/DWDBS_system_inst/neg_ddr_data_i_1__5]
set_property LOCK_PINS {I2:A4 I0:A6} [get_cells sw3A_inst/DWDBS_system_inst/neg_ddr_data_i_1__5]
set_property DONT_TOUCH true         [get_cells sw3A_inst/DWDBS_system_inst/neg_ddr_data_i_1__5]


set_property BEL AFF            [get_cells sw3A_inst/DWDBS_system_inst/neg_sync_reset_reg]
set_property LOC SLICE_X82Y167  [get_cells sw3A_inst/DWDBS_system_inst/neg_sync_reset_reg]

set_property FIXED_ROUTE { { CLBLL_LL_AQ CLBLL_LOGIC_OUTS4 EE4BEG0 NE6BEG0 SW6BEG3 NL1BEG_N3 IMUX_L5 CLBLL_L_A6 }  } [get_nets {sw3A_inst/DWDBS_system_inst/neg_sync_reset}]

set_property BEL A6LUT          [get_cells sw3A_inst/DWDBS_system_inst/neg_pointer_i_1__5]
set_property LOC SLICE_X83Y167  [get_cells sw3A_inst/DWDBS_system_inst/neg_pointer_i_1__5]
set_property LOCK_PINS {I0:A6}  [get_cells sw3A_inst/DWDBS_system_inst/neg_pointer_i_1__5]
set_property DONT_TOUCH true    [get_cells sw3A_inst/DWDBS_system_inst/neg_pointer_i_1__5]

set_property BEL AFF            [get_cells sw3A_inst/DWDBS_system_inst/neg_pointer_reg]
set_property LOC SLICE_X83Y167  [get_cells sw3A_inst/DWDBS_system_inst/neg_pointer_reg]

# >>> BEGIN LOCKED LOOPBACK PATH (generated) >>>
#--------------------------------------------------------------------------
# LOOPBACK RETURN PATH - SKEW-MATCHED AND LOCKED
#
# sw3A_inst/delayed_dirty_sw3A (IDELAYE2 -> BUFG) is hand-routed to
# the same delay as the other 7 channels (2.69 ns slow-max / 1.28 ns fast-min, all 8 within 15 ps).
# Everything after the IDELAY (BUFG, cleaner MMCM + its BUFGs, the
# enable gate LUT and its routes) is locked too, so changing
# DIRTY_IDELAY_TAPS and rebuilding does not move or reroute anything.
# Tied to the current pins/IP: regenerate if those change.
#--------------------------------------------------------------------------

# IDELAYE2 -> BUFG (skew-matched)
set_property BEL IDELAYE2 [get_cells sw3A_inst/idelay_dirty_sw3A]
set_property LOC IDELAY_X1Y170 [get_cells sw3A_inst/idelay_dirty_sw3A]
set_property BEL BUFG [get_cells sw3A_inst/buf_dirty_sw3A]
set_property LOC BUFGCTRL_X0Y9 [get_cells sw3A_inst/buf_dirty_sw3A]
set_property FIXED_ROUTE { RIOI_IDELAY0_DATAOUT RIOI_ILOGIC0_DDLY IOI_ILOGIC0_O IOI_LOGIC_OUTS18_1 INT_INTERFACE_LOGIC_OUTS18 WW4BEG0 LV18 <1>LH0 LV18 LV18 LV18 WW4BEG0 WW4BEG0 NL1BEG_N3 IMUX29 CLK_BUFG_BUFGCTRL9_I0 } [get_nets {sw3A_inst/delayed_dirty_sw3A}]

# Jitter-cleaner MMCM and its BUFGs
set_property LOC MMCME2_ADV_X0Y1 [get_cells sw3A_inst/sw3A_cleaner_inst/inst/mmcm_adv_inst]
set_property BEL BUFG [get_cells sw3A_inst/sw3A_cleaner_inst/inst/clkf_buf]
set_property LOC BUFGCTRL_X0Y10 [get_cells sw3A_inst/sw3A_cleaner_inst/inst/clkf_buf]
set_property BEL BUFG [get_cells sw3A_inst/sw3A_cleaner_inst/inst/clkout1_buf]
set_property LOC BUFGCTRL_X0Y11 [get_cells sw3A_inst/sw3A_cleaner_inst/inst/clkout1_buf]

# Enable gate LUT next to the sw3A OBUF, and its two routes
set_property BEL A6LUT [get_cells sw3A_inst/sw3A_OBUF_inst_i_1]
set_property LOC SLICE_X1Y159 [get_cells sw3A_inst/sw3A_OBUF_inst_i_1]
set_property LOCK_PINS {I0:A6 I1:A5} [get_cells sw3A_inst/sw3A_OBUF_inst_i_1]
set_property DONT_TOUCH true [get_cells sw3A_inst/sw3A_OBUF_inst_i_1]
set_property FIXED_ROUTE { CLK_BUFG_BUFGCTRL11_O CLK_BUFG_CK_GCLK11 CLK_BUFG_REBUF_R_CK_GCLK11_TOP CLK_BUFG_REBUF_R_CK_GCLK11_TOP CLK_BUFG_REBUF_R_CK_GCLK11_TOP CLK_HROW_CK_MUX_OUT_L8 CLK_HROW_CK_HCLK_OUT_L8 CLK_HROW_CK_BUFHCLK_L8 <14>HCLK_LEAF_CLK_B_BOTL2 <16>GCLK_L_B8_WEST GFAN1 IMUX_L5 CLBLL_L_A6 } [get_nets {sw3A_inst/clean_sw3A}]
set_property FIXED_ROUTE { CLBLL_L_A CLBLL_LOGIC_OUTS8 SW2BEG0 NW2BEG1 IMUX_L34 IOI_OLOGIC1_D1 LIOI_OLOGIC1_OQ LIOI_O1 } [get_nets {sw3A_OBUF}]
# <<< END LOCKED LOOPBACK PATH <<<

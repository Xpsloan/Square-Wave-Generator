
# SP701 constraints for square wave generator

# System clock (200 MHz LVDS, Bank 33, VCCO 2.5V)

set_property PACKAGE_PIN AE8               [get_ports clk_in1_p]
set_property PACKAGE_PIN AE7               [get_ports clk_in1_n]
set_property IOSTANDARD LVDS_25            [get_ports clk_in1_p]
set_property IOSTANDARD LVDS_25            [get_ports clk_in1_n]
create_clock -period 5.000 -name clk_in1_p [get_ports clk_in1_p]

# CPU Reset (active-high pushbutton, Bank 13, 1.8V)
set_property PACKAGE_PIN AE15    [get_ports reset]
set_property IOSTANDARD LVCMOS18 [get_ports reset]

# button instantiation
set_property PACKAGE_PIN AA20    [get_ports enable]
set_property IOSTANDARD LVCMOS18 [get_ports enable]


# Dither control for testing
set_property PACKAGE_PIN AB20    [get_ports inc_dither_width]
set_property IOSTANDARD LVCMOS18 [get_ports inc_dither_width]

set_property PACKAGE_PIN AF23    [get_ports dec_dither_width]
set_property IOSTANDARD LVCMOS18 [get_ports dec_dither_width]

set_property PACKAGE_PIN AB22    [get_ports inc_dither_shift]
set_property IOSTANDARD LVCMOS18 [get_ports inc_dither_shift]

set_property PACKAGE_PIN AC22    [get_ports dec_dither_shift]
set_property IOSTANDARD LVCMOS18 [get_ports dec_dither_shift]


#--------------------------------------------------------------------------
# FOR THE SQUARE WAVE CHANNEL WHERE IT WILL COME OUT, COME BACK IN,
# AND THEN COME BACK OUT AS A PMOD.
#--------------------------------------------------------------------------

# PMOD1 output pins connected to square_wave_out to display square waves
set_property LOC OLOGIC_X1Y134       [get_cells square_wave_generator/DWDBS_system_init/ODDR_inst]
set_property PACKAGE_PIN F3          [get_ports dirty_swo_p]   ;# IO_L1P_T0_AD4P_35 - true P
set_property PACKAGE_PIN E3          [get_ports dirty_swo_n]   ;# IO_L1N_T0_AD4N_35 - true N
set_property IOSTANDARD LVDS_25      [get_ports dirty_swo_p]
set_property IOSTANDARD LVDS_25      [get_ports dirty_swo_n]

# IN pin for the FMC FMC_LA23_P and FMC_LA23_N
set_property PACKAGE_PIN G2       [get_ports dirty_swi_p] 
set_property PACKAGE_PIN F2       [get_ports dirty_swi_n] 
set_property IOSTANDARD  LVDS_25  [get_ports dirty_swi_p] 
set_property IOSTANDARD  LVDS_25  [get_ports dirty_swi_n] 

# Square wave going back out again
set_property PACKAGE_PIN C13      [get_ports clean_swo]
set_property IOSTANDARD LVCMOS33  [get_ports clean_swo]

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets square_wave_generator/dirty_swo_OBUF]

# Square wave dirty
set_property PACKAGE_PIN D16      [get_ports dirty_swo]
set_property IOSTANDARD LVCMOS33  [get_ports dirty_swo]


#--------------------------------------------------------------------------
# FOR THE COMPARE CHANNEL
#--------------------------------------------------------------------------

# LEDs (Bank 15, 3.3V)
set_property PACKAGE_PIN J25     [get_ports {led[0]}]
set_property PACKAGE_PIN M24     [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]



## ----------------------------------------------------------------------------------------------------------
##                               DESIGN STUFF
## ----------------------------------------------------------------------------------------------------------

############################################
# FROM POS_SHIFT_REGISTERS TO POS_DDR_DATA #
############################################


set_property BEL AFF           [get_cells square_wave_generator/DWDBS_system_init/pos_ddr_data_reg]
set_property LOC SLICE_X85Y134 [get_cells square_wave_generator/DWDBS_system_init/pos_ddr_data_reg]


set_property BEL CFF           [get_cells square_wave_generator/DWDBS_system_init/pos_shift_reg_reg[1]]
set_property LOC SLICE_X85Y135 [get_cells square_wave_generator/DWDBS_system_init/pos_shift_reg_reg[1]]
set_property BEL BFF           [get_cells square_wave_generator/DWDBS_system_init/pos_shift_reg_reg[0]]
set_property LOC SLICE_X85Y135 [get_cells square_wave_generator/DWDBS_system_init/pos_shift_reg_reg[0]]

set_property FIXED_ROUTE { { CLBLM_L_CQ CLBLM_LOGIC_OUTS2 ER1BEG3 SL1BEG3 SR1BEG_S0 WL1BEG_N3 NL1BEG_N3 IMUX5 CLBLM_L_A6 } } [get_nets {square_wave_generator/DWDBS_system_init/pos_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLM_L_BQ CLBLM_LOGIC_OUTS1 EE4BEG1 WL1BEG_N3 SR1BEG_S0 IMUX10 CLBLM_L_A4 } } [get_nets {square_wave_generator/DWDBS_system_init/pos_shift_reg[0]}]

set_property BEL A6LUT               [get_cells square_wave_generator/DWDBS_system_init/pos_ddr_data_i_1]
set_property LOC SLICE_X85Y134       [get_cells square_wave_generator/DWDBS_system_init/pos_ddr_data_i_1]
set_property LOCK_PINS {I2:A4 I0:A6} [get_cells square_wave_generator/DWDBS_system_init/pos_ddr_data_i_1]
set_property DONT_TOUCH true         [get_cells square_wave_generator/DWDBS_system_init/pos_ddr_data_i_1]


set_property BEL AFF            [get_cells square_wave_generator/DWDBS_system_init/pos_sync_reset_reg]
set_property LOC SLICE_X82Y134  [get_cells square_wave_generator/DWDBS_system_init/pos_sync_reset_reg]

set_property FIXED_ROUTE { { CLBLL_LL_AQ CLBLL_LOGIC_OUTS4 EE4BEG0 NE6BEG0 SW6BEG3 NL1BEG_N3 IMUX_L5 CLBLL_L_A6 }  } [get_nets square_wave_generator/DWDBS_system_init/pos_sync_reset]

set_property BEL A6LUT          [get_cells square_wave_generator/DWDBS_system_init/pos_pointer_i_1]
set_property LOC SLICE_X83Y134  [get_cells square_wave_generator/DWDBS_system_init/pos_pointer_i_1]
set_property LOCK_PINS {I0:A6}  [get_cells square_wave_generator/DWDBS_system_init/pos_pointer_i_1]
set_property DONT_TOUCH true    [get_cells square_wave_generator/DWDBS_system_init/pos_pointer_i_1]

set_property BEL AFF            [get_cells square_wave_generator/DWDBS_system_init/pos_pointer_reg]
set_property LOC SLICE_X83Y134  [get_cells square_wave_generator/DWDBS_system_init/pos_pointer_reg]



############################################
# FROM NEG_SHIFT_REGISTERS TO NEG_DDR_DATA #
############################################


set_property BEL AFF           [get_cells square_wave_generator/DWDBS_system_init/neg_ddr_data_reg]
set_property LOC SLICE_X85Y132 [get_cells square_wave_generator/DWDBS_system_init/neg_ddr_data_reg]


set_property BEL CFF           [get_cells square_wave_generator/DWDBS_system_init/neg_shift_reg_reg[1]]
set_property LOC SLICE_X85Y133 [get_cells square_wave_generator/DWDBS_system_init/neg_shift_reg_reg[1]]
set_property BEL BFF           [get_cells square_wave_generator/DWDBS_system_init/neg_shift_reg_reg[0]]
set_property LOC SLICE_X85Y133 [get_cells square_wave_generator/DWDBS_system_init/neg_shift_reg_reg[0]]


set_property FIXED_ROUTE { { CLBLM_L_CQ CLBLM_LOGIC_OUTS2 ER1BEG3 SL1BEG3 SR1BEG_S0 WL1BEG_N3 NL1BEG_N3 IMUX5 CLBLM_L_A6 } } [get_nets {square_wave_generator/DWDBS_system_init/neg_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLM_L_BQ CLBLM_LOGIC_OUTS1 EE4BEG1 WL1BEG_N3 SR1BEG_S0 IMUX10 CLBLM_L_A4 } } [get_nets {square_wave_generator/DWDBS_system_init/neg_shift_reg[0]}]


set_property BEL A6LUT               [get_cells square_wave_generator/DWDBS_system_init/neg_ddr_data_i_1]
set_property LOC SLICE_X85Y132       [get_cells square_wave_generator/DWDBS_system_init/neg_ddr_data_i_1]
set_property LOCK_PINS {I2:A4 I0:A6} [get_cells square_wave_generator/DWDBS_system_init/neg_ddr_data_i_1]
set_property DONT_TOUCH true         [get_cells square_wave_generator/DWDBS_system_init/neg_ddr_data_i_1]


set_property BEL AFF            [get_cells square_wave_generator/DWDBS_system_init/neg_sync_reset_reg]
set_property LOC SLICE_X82Y133  [get_cells square_wave_generator/DWDBS_system_init/neg_sync_reset_reg]

set_property FIXED_ROUTE { { CLBLL_LL_AQ CLBLL_LOGIC_OUTS4 EE4BEG0 NE6BEG0 SW6BEG3 NL1BEG_N3 IMUX_L5 CLBLL_L_A6 }  } [get_nets {square_wave_generator/DWDBS_system_init/neg_sync_reset}]

set_property BEL A6LUT          [get_cells square_wave_generator/DWDBS_system_init/neg_pointer_i_1]
set_property LOC SLICE_X83Y133  [get_cells square_wave_generator/DWDBS_system_init/neg_pointer_i_1]
set_property LOCK_PINS {I0:A6}  [get_cells square_wave_generator/DWDBS_system_init/neg_pointer_i_1]
set_property DONT_TOUCH true    [get_cells square_wave_generator/DWDBS_system_init/neg_pointer_i_1]

set_property BEL AFF            [get_cells square_wave_generator/DWDBS_system_init/neg_pointer_reg]
set_property LOC SLICE_X83Y133  [get_cells square_wave_generator/DWDBS_system_init/neg_pointer_reg]


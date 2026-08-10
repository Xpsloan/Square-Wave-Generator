
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

set_property PACKAGE_PIN AB20    [get_ports dither_enable]
set_property IOSTANDARD LVCMOS18 [get_ports dither_enable]


# PMOD1 output pins connected to square_wave_out to display square waves
set_property LOC OLOGIC_X0Y192       [get_cells DWDBS_system_init/ODDR_inst]
set_property PACKAGE_PIN B14         [get_ports square_wave_out_p]
set_property PACKAGE_PIN B15         [get_ports square_wave_out_n]
set_property IOSTANDARD DIFF_SSTL135 [get_ports square_wave_out_p]
set_property IOSTANDARD DIFF_SSTL135 [get_ports square_wave_out_n]


# PMOD1 output pins connected to square_wave_out to display square waves
set_property PACKAGE_PIN B16         [get_ports compare_p]
set_property PACKAGE_PIN B17         [get_ports compare_n]
set_property IOSTANDARD DIFF_SSTL135 [get_ports compare_p]
set_property IOSTANDARD DIFF_SSTL135 [get_ports compare_n]

# LEDs (Bank 15, 3.3V)
set_property PACKAGE_PIN J25     [get_ports {led[0]}]
set_property PACKAGE_PIN M24     [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]



## ----------------------------------------------------------------------------------------------------------
##                               DESIGN STUFF
## ----------------------------------------------------------------------------------------------------------

# FROM POS_SHIFT_REGISTERS TO POS_DDR_DATA

set_property BEL A5FF         [get_cells {DWDBS_system_init/pos_shift_reg_reg[0]}]
set_property LOC SLICE_X1Y191 [get_cells {DWDBS_system_init/pos_shift_reg_reg[0]}]

set_property BEL CFF          [get_cells {DWDBS_system_init/pos_shift_reg_reg[1]}]
set_property LOC SLICE_X1Y191 [get_cells {DWDBS_system_init/pos_shift_reg_reg[1]}]

set_property FIXED_ROUTE { { CLBLL_L_CQ CLBLL_LOGIC_OUTS2 WW4BEG2 ER1BEG3 IMUX_L38 CLBLL_LL_D3 } } [get_nets {DWDBS_system_init/pos_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLL_L_AMUX CLBLL_LOGIC_OUTS16 SW6BEG2 NW6BEG3 EL1BEG2 IMUX_L43 CLBLL_LL_D6 } } [get_nets {DWDBS_system_init/pos_shift_reg[0]}]

set_property BEL D6LUT               [get_cells DWDBS_system_init/pos_ddr_data_i_1]
set_property LOC SLICE_X0Y191        [get_cells DWDBS_system_init/pos_ddr_data_i_1]
set_property LOCK_PINS {I0:A3 I2:A6} [get_cells DWDBS_system_init/pos_ddr_data_i_1]
set_property DONT_TOUCH true         [get_cells DWDBS_system_init/pos_ddr_data_i_1]

set_property BEL DFF          [get_cells DWDBS_system_init/pos_ddr_data_reg]
set_property LOC SLICE_X0Y191 [get_cells DWDBS_system_init/pos_ddr_data_reg]


# FROM NEG_SHIFT_REGISTERS TO NEG_DDR_DATA

set_property BEL A5FF         [get_cells {DWDBS_system_init/neg_shift_reg_reg[0]}]
set_property LOC SLICE_X1Y193 [get_cells {DWDBS_system_init/neg_shift_reg_reg[0]}]

set_property BEL CFF          [get_cells {DWDBS_system_init/neg_shift_reg_reg[1]}]
set_property LOC SLICE_X1Y193 [get_cells {DWDBS_system_init/neg_shift_reg_reg[1]}]

set_property FIXED_ROUTE { { CLBLL_L_CQ CLBLL_LOGIC_OUTS2 WW4BEG2 ER1BEG3 IMUX_L38 CLBLL_LL_D3 } } [get_nets {DWDBS_system_init/neg_shift_reg[1]}]
set_property FIXED_ROUTE { { CLBLL_L_AMUX CLBLL_LOGIC_OUTS16 SW6BEG2 NW6BEG3 EL1BEG2 IMUX_L43 CLBLL_LL_D6 } } [get_nets {DWDBS_system_init/neg_shift_reg[0]}]

set_property BEL D6LUT               [get_cells DWDBS_system_init/neg_ddr_data_i_1]
set_property LOC SLICE_X0Y193        [get_cells DWDBS_system_init/neg_ddr_data_i_1]
set_property LOCK_PINS {I0:A3 I2:A6} [get_cells DWDBS_system_init/neg_ddr_data_i_1]
set_property DONT_TOUCH true         [get_cells DWDBS_system_init/neg_ddr_data_i_1]

set_property BEL DFF          [get_cells DWDBS_system_init/neg_ddr_data_reg]
set_property LOC SLICE_X0Y193 [get_cells DWDBS_system_init/neg_ddr_data_reg]


# POS_SYNC_RESET TO POS_POINTER
set_property BEL BFF          [get_cells DWDBS_system_init/pos_sync_reset_reg]
set_property LOC SLICE_X1Y190 [get_cells DWDBS_system_init/pos_sync_reset_reg]

set_property FIXED_ROUTE { { CLBLL_L_BQ CLBLL_LOGIC_OUTS1 EE4BEG1 SS2BEG1 WW4BEG2 NN2BEG2 IMUX_L43 CLBLL_LL_D6 }  } [get_nets DWDBS_system_init/pos_sync_reset]

set_property BEL D6LUT         [get_cells DWDBS_system_init/pos_pointer_i_1]
set_property LOC SLICE_X0Y190  [get_cells DWDBS_system_init/pos_pointer_i_1]
set_property LOCK_PINS {I0:A6} [get_cells DWDBS_system_init/pos_pointer_i_1]
set_property DONT_TOUCH true   [get_cells DWDBS_system_init/pos_pointer_i_1]

set_property BEL DFF          [get_cells DWDBS_system_init/pos_pointer_reg]
set_property LOC SLICE_X0Y190 [get_cells DWDBS_system_init/pos_pointer_reg]



# NEG_SYNC_RESET TO NEG_POINTER
set_property BEL BFF          [get_cells DWDBS_system_init/neg_sync_reset_reg]
set_property LOC SLICE_X1Y192 [get_cells DWDBS_system_init/neg_sync_reset_reg]

set_property FIXED_ROUTE { { CLBLL_L_BQ CLBLL_LOGIC_OUTS1 EE4BEG1 SS2BEG1 WW4BEG2 NN2BEG2 IMUX_L43 CLBLL_LL_D6 }  } [get_nets DWDBS_system_init/neg_sync_reset]

set_property BEL D6LUT         [get_cells DWDBS_system_init/neg_pointer_i_1]
set_property LOC SLICE_X0Y192  [get_cells DWDBS_system_init/neg_pointer_i_1]
set_property LOCK_PINS {I0:A6} [get_cells DWDBS_system_init/neg_pointer_i_1]
set_property DONT_TOUCH true   [get_cells DWDBS_system_init/neg_pointer_i_1]

set_property BEL DFF          [get_cells DWDBS_system_init/neg_pointer_reg]
set_property LOC SLICE_X0Y192 [get_cells DWDBS_system_init/neg_pointer_reg]

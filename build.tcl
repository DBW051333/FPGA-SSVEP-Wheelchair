set root [file normalize [file dirname [info script]]]
cd $root
open_project [file join $root fusion.gprj]
set_option -top_module fusion_top
set_option -output_base_name fusion_single_board
set_option -verilog_std sysv2017
set_option -include_path [file join $root src]
set_option -frequency 50
set_option -timing_driven 1
set_option -correct_hold_violation 1
set_option -route_option 0
set_option -place_option 1
set_option -use_sspi_as_gpio 1
set_option -gen_text_timing_rpt 1
set_option -replicate_resources 1
set_option -clock_route_order 1
run all


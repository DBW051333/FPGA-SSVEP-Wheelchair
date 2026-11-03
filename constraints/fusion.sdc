create_clock -name clk50 -period 20 [get_ports {clk}]
create_generated_clock -name ref27 -source [get_ports {clk}] -multiply_by 27 -divide_by 50 [get_pins {refpll/core/PLL_inst/CLKOUT0}]
create_clock -name serial_source -period 2.693602694 [get_pins {pll/core/PLL_inst/CLKOUT1}]
create_generated_clock -name serial -source [get_pins {pll/core/PLL_inst/CLKOUT1}] -divide_by 1 [get_pins {serial_gate/CLKOUT}]
create_generated_clock -name pixel -source [get_pins {serial_gate/CLKOUT}] -divide_by 5 [get_pins {pixel_div/CLKOUT}]
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {key_n[*]}] -to [get_cells {*sync1*}]
# Dedicated four-stage pixel reset synchronizer: asynchronous assertion,
# release propagates through four pixel-clock flip-flops before reaching logic.
set_false_path -to [get_pins {reset_sync*/CLEAR}]
# DHCE has an internal four-stage falling-edge enable synchronizer.
set_false_path -to [get_pins {serial_gate/CEN}]
# startup_shift[0] releases RESET while DHCE is disabled. startup_shift[3]
# requests HCLK enable three 50 MHz periods (60 ns) later. This excludes only
# the inactive-clock recovery checks, not any serializer data path.
set_false_path -to [get_pins {tx/l*/ser/RESET pixel_div/RESETN}]


# External TTL UART is asynchronous; only the first receive synchronizer is excluded.
set_false_path -from [get_ports {receiver_rx}] -to [get_cells {*frontend/serial_rx/rx1*}]
# Reset assertion is asynchronous; four 50MHz stages synchronize release.
set_false_path -to [get_pins {system_reset_sync*/CLEAR}]

# First-stage CDC exceptions only. Bundled command reaches data_meta within
# 10ns; request is delayed three 50MHz stages before consumption.
set_false_path -to [get_regs {*motion/req_meta* *motion/ack_meta* *motion/hb_meta*}]
set_max_delay 10.000 -from [get_regs {*motion/held_command*}] -to [get_regs {*motion/data_meta*}]
# First bundled-data samples may be asynchronous; the request settling stage
# and display stable filter are the consumers. Do not relax later stages.
set_false_path -hold -from [get_regs {*motion/held_command*}] -to [get_regs {*motion/data_meta*}]
set_false_path -from [get_ports {mute_led sos_led d5 d6 ser rclk srclk}] -to [get_regs {*panel/sync_meta*}]
set_false_path -from [get_ports {sw_n[*]}] -to [get_regs {*sw_meta*}]
set_false_path -from [get_ports {key_n[1]}] -to [get_regs {*session_cancelled*}]
set_false_path -from [get_regs {*session_cancelled*}] -to [get_regs {*cancel_meta*}]
# Asynchronous reset assertion, synchronous release in each local domain.
set_false_path -to [get_pins {*motion/src_reset_sync*/CLEAR *motion/dst_reset_sync*/CLEAR panel_reset_sync*/CLEAR}]
set_max_delay 10.000 -from [get_clocks {clk50}] -to [get_ports {dac_din dac_sclk dac_cs_n}]
# Static analog-switch inputs use the original wheelchair 20ns bound.
set_max_delay 20.000 -from [get_clocks {clk50}] -to [get_ports {key_in[*]}]
set_max_delay 20.000 -from [get_clocks {clk50}] -to [get_ports {led[*]}]

# Atomic status mailboxes: bounded bundled data, only first handshake stages asynchronous.
set_false_path -to [get_regs {*vehicle_cdc/req_sync_0_s0 *vehicle_cdc/ack_sync_0_s0 *result_cdc/req_sync_0_s0 *result_cdc/ack_sync_0_s0}]
set_max_delay 10.000 -from [get_regs {*vehicle_cdc/mailbox* *result_cdc/mailbox*}] -to [get_regs {*vehicle_cdc/pending* *result_cdc/pending*}]
set_false_path -hold -from [get_regs {*vehicle_cdc/mailbox* *result_cdc/mailbox*}] -to [get_regs {*vehicle_cdc/pending* *result_cdc/pending*}]
set_false_path -to [get_pins {status_src_reset*/CLEAR status_ref_reset*/CLEAR status_dst_reset*/CLEAR}]
set_false_path -from [get_ports {page_next_n}] -to [get_cells {*next_key/sync1*}]
set_false_path -to [get_regs {*key_link/req_meta* *key_link/ack_meta* *key_link/hb_meta*}]
set_max_delay 10.000 -from [get_regs {*key_link/held_command*}] -to [get_regs {*key_link/data_meta*}]
set_false_path -hold -from [get_regs {*key_link/held_command*}] -to [get_regs {*key_link/data_meta*}]
set_false_path -to [get_pins {*key_link/src_reset_sync*/CLEAR *key_link/dst_reset_sync*/CLEAR}]

# S2 power key: only first input synchronizers are asynchronous.
set_false_path -from [get_ports {panel_view_n}] -to [get_cells {*s2_key/sync1*}]
set_false_path -from [get_ports {panel_view_n}] -to [get_regs {*s2_release_meta*}]

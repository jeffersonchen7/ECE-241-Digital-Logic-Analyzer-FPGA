catch {quit -sim}
vlib work
vlog logic_analyzer.v sim/tb_logic_analyzer.v
vsim work.tb_logic_analyzer

add wave -divider "Clock & Control"
add wave sim:/tb_logic_analyzer/u_dut/clk
add wave sim:/tb_logic_analyzer/u_dut/reset_n
add wave sim:/tb_logic_analyzer/u_dut/arm
add wave sim:/tb_logic_analyzer/u_dut/rate_sel

add wave -divider "Probes & Trigger"
add wave sim:/tb_logic_analyzer/u_dut/probes_in
add wave sim:/tb_logic_analyzer/u_dut/synced_sample
add wave sim:/tb_logic_analyzer/u_dut/trig_mode
add wave sim:/tb_logic_analyzer/u_dut/trig_fire

add wave -divider "FSM & RAM"
add wave -radix unsigned sim:/tb_logic_analyzer/u_dut/state_dbg
add wave sim:/tb_logic_analyzer/u_dut/wr_en
add wave -radix unsigned sim:/tb_logic_analyzer/u_dut/wr_addr
add wave sim:/tb_logic_analyzer/u_dut/done
add wave -radix unsigned sim:/tb_logic_analyzer/u_dut/rd_addr
add wave sim:/tb_logic_analyzer/u_dut/rd_data

configure wave -signalnamewidth 1

run -all

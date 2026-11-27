catch {quit -sim}
vlib work
vlog logic_analyzer.v vga_display.v sim/tb_vga.v
vsim work.tb_vga

add wave -divider "VGA Timing"
add wave sim:/tb_vga/VGA_CLK
add wave sim:/tb_vga/VGA_HS
add wave sim:/tb_vga/VGA_VS
add wave sim:/tb_vga/VGA_BLANK_N
add wave -radix unsigned sim:/tb_vga/u_dut/h_cnt
add wave -radix unsigned sim:/tb_vga/u_dut/v_cnt

add wave -divider "RAM & Pixels"
add wave -radix unsigned sim:/tb_vga/u_dut/rd_addr
add wave sim:/tb_vga/u_dut/rd_data
add wave -radix unsigned sim:/tb_vga/VGA_R
add wave -radix unsigned sim:/tb_vga/VGA_G
add wave -radix unsigned sim:/tb_vga/VGA_B

configure wave -signalnamewidth 1
run -all

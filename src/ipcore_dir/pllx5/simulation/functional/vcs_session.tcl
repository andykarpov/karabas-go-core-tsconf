gui_open_window Wave
gui_sg_create pllx5_group
gui_list_add_group -id Wave.1 {pllx5_group}
gui_sg_addsignal -group pllx5_group {pllx5_tb.test_phase}
gui_set_radix -radix {ascii} -signals {pllx5_tb.test_phase}
gui_sg_addsignal -group pllx5_group {{Input_clocks}} -divider
gui_sg_addsignal -group pllx5_group {pllx5_tb.CLK_IN1}
gui_sg_addsignal -group pllx5_group {{Output_clocks}} -divider
gui_sg_addsignal -group pllx5_group {pllx5_tb.dut.clk}
gui_list_expand -id Wave.1 pllx5_tb.dut.clk
gui_sg_addsignal -group pllx5_group {{Status_control}} -divider
gui_sg_addsignal -group pllx5_group {pllx5_tb.LOCKED}
gui_sg_addsignal -group pllx5_group {{Counters}} -divider
gui_sg_addsignal -group pllx5_group {pllx5_tb.COUNT}
gui_sg_addsignal -group pllx5_group {pllx5_tb.dut.counter}
gui_list_expand -id Wave.1 pllx5_tb.dut.counter
gui_zoom -window Wave.1 -full

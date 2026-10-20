create_clock -name clk -period 10.0 [get_ports clk]

set_input_delay  2.0 -clock clk [get_ports {rst cfg_we cfg_addr[*] cfg_data[*] in_valid in_data[*]}]
set_output_delay 2.0 -clock clk [get_ports {out_valid out_idx[*] out_re[*] out_im[*]}]

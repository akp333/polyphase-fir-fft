read_lef NangateOpenCellLibrary.tech.lef
read_lef NangateOpenCellLibrary.macro.lef
read_liberty NangateOpenCellLibrary_typical.lib
read_verilog channelizer_netlist.v
link_design channelizer_top
read_sdc channelizer.sdc

report_checks -path_delay max -digits 3
report_checks -path_delay min -digits 3
report_worst_slack -max -digits 3
report_worst_slack -min -digits 3
report_tns -digits 3

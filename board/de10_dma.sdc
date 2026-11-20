create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_clock_uncertainty
# Button reset asserts asynchronously; reset_release synchronizes release.
set_false_path -from [get_ports KEY0]
# LEDs are human-observed outputs, not clocked external interfaces.
set_false_path -to [get_ports {LEDR[*]}]

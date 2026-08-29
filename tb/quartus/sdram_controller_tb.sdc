create_clock -period 20.000 -name i_clk [get_ports {i_clk}]
create_generated_clock -name DRAM_CLK -source [get_ports {i_clk}] [get_ports {DRAM_CLK}]
derive_pll_clocks
derive_clock_uncertainty

set_false_path -from [get_ports {i_rst_n}]
set_false_path -to [get_ports {o_uart_tx}]

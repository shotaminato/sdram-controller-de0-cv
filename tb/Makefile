# Compare Verilog vs SystemVerilog sdram_controller with the same testbench:
#   make cmp
ROOT ?= ..
TB   := .
RTL  := $(ROOT)/rtl
OUT  := $(TB)/out

.PHONY: all v sv cmp clean

all: cmp

$(OUT):
	mkdir -p $(OUT)

v: $(OUT)
	iverilog -g2012 -o $(OUT)/sim_v.vvp \
	  $(RTL)/sdram_controller.v $(TB)/sdram_model.v $(TB)/sdram_controller_tb.v
	vvp $(OUT)/sim_v.vvp +LOG=$(OUT)/v.log

sv: $(OUT)
	iverilog -g2012 -I $(RTL) -o $(OUT)/sim_sv.vvp \
	  $(RTL)/dff.sv $(RTL)/sdram_controller.sv \
	  $(TB)/sdram_model.v $(TB)/sdram_controller_tb.v
	vvp $(OUT)/sim_sv.vvp +LOG=$(OUT)/sv.log

cmp:
	./run_cmp.sh

clean:
	rm -rf $(OUT)

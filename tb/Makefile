# Simulate sdram_controller
#   make sim
ROOT   ?= ..
TB     := .
OUT    := $(TB)/out
BENDER ?= bender

SV_SRCS := $(shell cd $(ROOT) && $(BENDER) script flist -t test)

.PHONY: all sim clean

all: sim

$(OUT):
	mkdir -p $(OUT)

sim: $(OUT)
	iverilog -g2012 -o $(OUT)/sim.vvp $(SV_SRCS)
	vvp $(OUT)/sim.vvp

clean:
	rm -rf $(OUT)

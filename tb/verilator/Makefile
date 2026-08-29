# Simulate sdram_controller with Verilator
#   make sim
#   need Ubuntu 24.04 or later
ROOT      ?= ../..
TB        := .
OUT       := $(TB)/out
TOP       := sdram_controller_tb
PRIM_ROOT ?= $(ROOT)/deps/rtl_primitive

VERILATOR := verilator

VERILATOR_FLAGS := \
	--binary \
	--timing \
	-j 0 \
	--top-module $(TOP) \
	-Wno-WIDTHEXPAND \
	-CFLAGS -O2 \
	-Mdir $(OUT)/obj_dir \
	-o sim \
	-I$(PRIM_ROOT)/pkg \
	-I$(ROOT)/rtl \
	-I$(TB)

.PHONY: all sim clean

all: sim

$(OUT):
	mkdir -p $(OUT)

sim: $(OUT)
	@test -d "$(PRIM_ROOT)/pkg" || (echo "FAIL: missing $(PRIM_ROOT); run bender update" && exit 1)
	$(VERILATOR) $(VERILATOR_FLAGS) $(TB)/verilator_top.sv
	$(OUT)/obj_dir/sim $(PLUSARGS)

clean:
	rm -rf $(OUT)

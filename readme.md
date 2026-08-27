# _SDRAM Memory Controller_

`CURRENT STATUS : ported to DE0-CV`

This is a very simple sdram controller which works on the Terasic DE0-CV
(Cyclone V `5CEBA4F23C7`). The project also contains a simple push button
interface for testing on the dev board.

This repository is a port of the original [stffrdhrn/sdram-controller](https://github.com/stffrdhrn/sdram-controller)
DE0-Nano design.

Basic features
 - Operates at 100Mhz, CAS 3, 64MB, 16-bit data
 - Geometry: 4 banks x 8192 rows x 1024 columns (host address `{bank,row,col}` is 25 bits)
 - On reset will go into `INIT` sequnce
 - After `INIT` the controller sits in `IDLE` waiting for `REFRESH`, `READ` or `WRITE`
 - `REFRESH` operations are spaced evenly 8192 times every 64ms
 - `READ` is always single read with auto precharge
 - `WRITE` is always single write with auto precharge

Target hardware (from the DE0-CV User Manual)
 - FPGA: Cyclone V `5CEBA4F23C7N`
 - SDRAM: 64MB (32M x 16), ISSI IS42S16320F or equivalent, 3.3-V LVCMOS
 - Clock: `CLOCK_50` (PIN_M9), multiplied to 100 MHz for SDRAM
 - Quartus II / Quartus Prime **14.0 or later** is required for Cyclone V

## SystemVerilog version

For integration with SystemVerilog RTL, use these files instead of `rtl/sdram_controller.v`:

 - `rtl/sdram_controller.sv` — same module name and host/SDRAM ports
 - `rtl/dff.sv` / `rtl/dff.svh` — DFF / DFFE macros (no `always_ff` in the controller)

Combinational logic is `assign` only. Do not compile `.v` and `.sv` in the same project (duplicate module). Add `rtl/` to the include path so `` `include "dff.svh" `` resolves.

The module name is `sdram_controller`, so instantiation is unchanged. Override `CLK_FREQUENCY` if the clock is not 100 MHz.

## Simulation (Verilog vs SystemVerilog)

`tb/` is a standalone Icarus Verilog test (no FuseSoC). The same self-checking bench is compiled once with `rtl/sdram_controller.v` and once with `rtl/sdram_controller.sv`, then per-cycle pin dumps are compared.

```
# requires iverilog / vvp
make -C tb cmp
```

```

 Host Interface          SDRAM Interface

   /-----------------------------\
   |      sdram_controller       |
==> wr_addr                  addr ==>
==> wr_data             bank_addr ==>
--> wr_enable                data <=>
   |                 clock_enable -->
==> rd_addr                  cs_n -->
--> rd_enable               ras_n -->
<== rd_data                 cas_n -->
<-- rd_ready                 we_n -->
<-- busy            data_mask_low -->
   |               data_mask_high -->
--> rst_n                        |
--> clk                          |
   \-----------------------------/

```

From the above diagram most signals should be pretty much self explainatory. Here are some important points for now.  It will be expanded on later.
 - `wr_addr` and `rd_addr` are equivelant to the concatenation of `{bank, row, column}`
 - `rd_enable` should be set to high once an address is presented on the `addr` bus and we wish to read data.
 - `wr_enable` should be set to high once `addr` and `data` is presented on the bus
 - `busy` will go high when the read or write command is acknowledged. `busy` will go low when the write or read operation is complete.
 - `rd_ready` will go high when data `rd_data` is available on the `data` bus.
 - **NOTE** For single reads and writes `wr_enable` and `rd_enable` should be set low once `busy` is observed.  This will protect from the controller thinking another request is needed if left higher any longer.

## Build

The recommended way to build is to use `fusesoc`.  The build steps are then:

```
# Build the project with quartus
fusesoc build dram_controller
# Program the project to DE0-CV
fusesoc pgm dram_controller

# Build with icarus verilog and test
fusesoc sim dram_controller --vcd
gtkwave $fusebuild/dram_controller/sim-icarus/testlog.vcd

# Run other test cases
fusesoc sim --testbench fifo_tb dram_controller --vcd
fusesoc sim --testbench double_click_tb dram_controller --vcd
```

The Quartus project in `quartus/` can also be opened directly. Top-level ports use
Terasic DE0-CV names (`CLOCK_50`, `RESET_N`, `KEY`, `SW`, `LEDR`, `DRAM_*`).

## State machine

Verilog (`rtl/sdram_controller.v`) and SystemVerilog (`rtl/sdram_controller.sv`) share this FSM.
`state_cnt != 0` holds the current state (and the current SDRAM command). The command shown in each bubble is what is on the bus while that state is active. `busy` is `state[STATE_WIDTH-1]` (high in READ_* and WRIT_* only).

IDLE priority: refresh, then `rd_enable`, then `wr_enable`.

```mermaid
stateDiagram-v2
    [*] --> INIT_NOP1: reset / NOP, cnt=15

    state INIT {
        INIT_NOP1 --> INIT_NOP1: cnt!=0
        INIT_NOP1 --> INIT_PRE1: cnt=0
        INIT_PRE1 --> INIT_NOP2
        INIT_NOP2 --> INIT_REF1
        INIT_REF1 --> INIT_NOP3: load 7
        INIT_NOP3 --> INIT_NOP3: cnt!=0
        INIT_NOP3 --> INIT_REF2: cnt=0
        INIT_REF2 --> INIT_NOP4: load 7
        INIT_NOP4 --> INIT_NOP4: cnt!=0
        INIT_NOP4 --> INIT_LOAD: cnt=0
        INIT_LOAD --> INIT_NOP5: load 1
        INIT_NOP5 --> INIT_NOP5: cnt!=0
        INIT_NOP5 --> IDLE: cnt=0
    }

    IDLE --> IDLE: else / NOP
    IDLE --> REF_PRE: refresh due
    IDLE --> READ_ACT: rd_enable
    IDLE --> WRIT_ACT: wr_enable

    state REFRESH {
        REF_PRE --> REF_NOP1
        REF_NOP1 --> REF_REF
        REF_REF --> REF_NOP2: load 7
        REF_NOP2 --> REF_NOP2: cnt!=0
        REF_NOP2 --> IDLE: cnt=0
    }

    state READ {
        READ_ACT --> READ_NOP1: load 1
        READ_NOP1 --> READ_NOP1: cnt!=0
        READ_NOP1 --> READ_CAS: cnt=0
        READ_CAS --> READ_NOP2: load 1
        READ_NOP2 --> READ_NOP2: cnt!=0
        READ_NOP2 --> READ_READ: cnt=0
        READ_READ --> IDLE
    }

    state WRITE {
        WRIT_ACT --> WRIT_NOP1: load 1
        WRIT_NOP1 --> WRIT_NOP1: cnt!=0
        WRIT_NOP1 --> WRIT_CAS: cnt=0
        WRIT_CAS --> WRIT_NOP2: load 1
        WRIT_NOP2 --> WRIT_NOP2: cnt!=0
        WRIT_NOP2 --> IDLE: cnt=0
    }
```

| State | Command | Stay (clk) | Notes |
| --- | --- | ---: | --- |
| INIT_NOP1 | NOP | 16 | reset loads `cnt=15` |
| INIT_PRE1 | PALL | 1 | precharge all |
| INIT_NOP2 | NOP | 1 | |
| INIT_REF1 | REF | 1 | |
| INIT_NOP3 | NOP | 8 | tRFC (`cnt=7`) |
| INIT_REF2 | REF | 1 | |
| INIT_NOP4 | NOP | 8 | tRFC (`cnt=7`) |
| INIT_LOAD | MRS | 1 | CAS 3, BL 1 |
| INIT_NOP5 | NOP | 2 | tMRD (`cnt=1`) |
| IDLE | NOP | — | wait for refresh / read / write |
| REF_PRE | PALL | 1 | |
| REF_NOP1 | NOP | 1 | |
| REF_REF | REF | 1 | |
| REF_NOP2 | NOP | 8 | tRFC (`cnt=7`) |
| READ_ACT / WRIT_ACT | BACT | 1 | row address |
| READ_NOP1 / WRIT_NOP1 | NOP | 2 | tRCD (`cnt=1`) |
| READ_CAS | READ | 1 | col, A10 auto-precharge |
| WRIT_CAS | WRIT | 1 | col, A10 auto-precharge, DQ |
| READ_NOP2 | NOP | 2 | CAS latency (`cnt=1`) |
| READ_READ | NOP | 1 | `rd_ready`, capture DQ |
| WRIT_NOP2 | NOP | 2 | (`cnt=1`) then IDLE |

## Timings

# Initialization
![wave init](https://raw.githubusercontent.com/stffrdhrn/sdram-controller/master/readme/wave-init.png)

Initialization process showing:
 - Precharge all banks
 - 2 refresh cycles
 - Mode programming

# Refresh
![wave refresh](https://raw.githubusercontent.com/stffrdhrn/sdram-controller/master/readme/wave-refresh.png)

Refresh process showing:
 - Precharge all banks
 - Single Refresh

# Writes
![wave write](https://raw.githubusercontent.com/stffrdhrn/sdram-controller/master/readme/wave-write.png)

Write operation showing:
 - Bank Activation & Row Address Strobe
 - Column Address Strobe with Auto Precharge set and Data on bus

# Reads
![wave read](https://raw.githubusercontent.com/stffrdhrn/sdram-controller/master/readme/wave-read.png)

Read operation showing:
 - Bank Activation & Row Address Strobe
 - Column Address Strobe with Auto Precharge set
 - Data on bus


## Test Application

![Test Application](https://raw.githubusercontent.com/stffrdhrn/sdram-controller/master/readme/block.png)
*Figure - test application block diagram*

The test application provides a simple user interface for testing the functionality
of the sdram controller on the DE0-CV.

Basics:
 - The clock input should be 50Mhz (`CLOCK_50`; a pll multiplies it to 100Mhz for SDRAM and 2Mhz for the board test interface)
 - `RESET_N` is used for `reset`
 - `KEY0` (`KEY` port) is used for `read` and `write`
   - single click for `write`
   - double click for `read`
 - `SW[3:0]` are used for inputting addresses and data
   - Upon `reset` the read/write addresses are read from the switches
   - When `writing` the switch data is written to the sdram
   - Address and data busses are greater than 4 bits, data is duplicated to fill the bus
 - `LEDR[7:0]` display the data read from the sdram. The data bus is 16-bits, high and low bytes are alternated on the LEDs about every half second.

## Project Status/TODO
 - [x] Compiles
 - [x] Simulated `Init`
 - [x] Simulated `Refresh`
 - [x] Simulated `Read`
 - [x] Simulated `Write`
 - [x] Ported pinout / device / SDRAM geometry to DE0-CV
 - [ ] Confirmed on DE0-CV hardware


## Project Setup
This project has been developed with Altera Quartus II / Intel Quartus Prime.
DE0-CV requires Quartus 14.0 or later.

## License
BSD

## Further Reading
I didn't look at these when designing my controller.  But it might be good to take a look at for ideas.
 - http://hamsterworks.co.nz/mediawiki/index.php/Simple_SDRAM_Controller - featured on hackaday
 - http://ladybug.xs4all.nl/arlet/fpga/source/sdram.v - Arlet's implementation from a comment on the hackaday article

//////////////////////////////////////////////////////////////////////
//
// toplevel for dram controller DE0-CV board
//
//////////////////////////////////////////////////////////////////////
//
// This source file may be used and distributed without
// restriction provided that this copyright statement is not
// removed from the file and that any derivative work contains
// the original copyright notice and the associated disclaimer.
//
// This source file is free software; you can redistribute it
// and/or modify it under the terms of the GNU Lesser General
// Public License as published by the Free Software Foundation;
// either version 2.1 of the License, or (at your option) any
// later version.
//
// This source is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
// PURPOSE.  See the GNU Lesser General Public License for more
// details.
//
// You should have received a copy of the GNU Lesser General
// Public License along with this source; if not, download it
// from http://www.opencores.org/lgpl.shtml
//
//////////////////////////////////////////////////////////////////////

module toplevel (
    input         CLOCK_50,
    input         RESET_N,
    input         KEY,

    output [1:0]  DRAM_BA,
    output [12:0] DRAM_ADDR,
    output        DRAM_CS_N,
    output        DRAM_RAS_N,
    output        DRAM_CAS_N,
    output        DRAM_WE_N,
    inout  [15:0] DRAM_DQ,
    output        DRAM_LDQM,
    output        DRAM_UDQM,
    output        DRAM_CKE,
    output        DRAM_CLK,

    output [7:0]  LEDR,
    input  [3:0]  SW
);

localparam HADDR_WIDTH = 25;

wire clk100m;
wire clk2m;

assign DRAM_CLK = clk100m;

// PLLs
pll pll_i (
    .refclk      (CLOCK_50),
    .rst         (~RESET_N),
    .outclk_0    (clk100m),
    .outclk_1    (clk2m)
);

// Cross Clock FIFOs
/* Address 25-bit and 16-bit Data transfers from in:2m out:100m */

/* 2 mhz side wires */
wire [HADDR_WIDTH+16-1:0] wr_fifo;
wire wr_enable;      /* wr_enable ] <-> [ wr : wr_enable to push fifo */
wire wr_full;        /* wr_full   ] <-> [ full : signal that we are full */
/* 100mhz side wires */
wire [HADDR_WIDTH+16-1:0] wro_fifo;
wire ctrl_busy;       /* rd ] <-> [ busy : pop fifo when ctrl not busy */
wire ctrl_wr_enable;  /* .empty_n-wr_enable : signal ctrl data is ready */

fifo #(.BUS_WIDTH(HADDR_WIDTH+16)) wr_fifoi (
    .wr_clk        (clk2m),
    .rd_clk        (clk100m),
    .wr_data       (wr_fifo),
    .rd_data       (wro_fifo),
    .rd            (ctrl_busy),
    .wr            (wr_enable),
    .full          (wr_full),
    .empty_n       (ctrl_wr_enable),
    .rst_n         (RESET_N)
);

/* Address 25-bit transfers from in:2m out:100m */
/* 2 mhz side wires */
wire        rd_enable;  /*  rd_enable -wr : rd_enable to push rd addr to fifo */
wire        rdaddr_full;/* rdaddr_full-full : signal we cannot read more */

/* 100mhz side wires */
wire [HADDR_WIDTH-1:0] rdao_fifo;
wire ctrl_rd_enable;     /* empty_n - rd_enable: signal ctrl addr ready */

fifo #(.BUS_WIDTH(HADDR_WIDTH)) rdaddr_fifoi (
    .wr_clk        (clk2m),
    .rd_clk        (clk100m),
    .wr_data       (wr_fifo[HADDR_WIDTH+16-1:16]),
    .rd_data       (rdao_fifo),
    .rd            (ctrl_busy),
    .wr            (rd_enable),
    .full          (rdaddr_full),
    .empty_n       (ctrl_rd_enable),
    .rst_n         (RESET_N)
);

/* 100mhz side wires */
wire [15:0] rddo_fifo;
wire ctrl_rd_ready;     /* wr - rd_ready - push data from dram to fifo */

/* 2mhz side wires */
wire [15:0] rddata_fifo;
wire        rd_ready;   /* rd_ready-empty_n- signal interface data ready */
wire        rd_ack;     /* rd_ack - rd     - pop fifo after data read */

/* Incoming 16-bit data transfers from in:100m out:2m */
fifo #(.BUS_WIDTH(16)) rddata_fifoi (
    .wr_clk        (clk100m),
    .rd_clk        (clk2m),
    .wr_data       (rddo_fifo),
    .rd_data       (rddata_fifo),
    .rd            (rd_ack),
    .wr            (ctrl_rd_ready),
    .full          (),
    .empty_n       (rd_ready),
    .rst_n         (RESET_N)
);


/* SDRAM */


sdram_controller sdram_controlleri (
    /* HOST INTERFACE */
    .wr_addr       (wro_fifo[HADDR_WIDTH+16-1:16]),
    .wr_data       (wro_fifo[15:0]),
    .wr_enable     (ctrl_wr_enable),

    .rd_addr       (rdao_fifo),
    .rd_data       (rddo_fifo),
    .rd_ready      (ctrl_rd_ready),
    .rd_enable     (ctrl_rd_enable),

    .busy          (ctrl_busy),
    .rst_n         (RESET_N),
    .clk           (clk100m),

    /* SDRAM SIDE */
    .addr          (DRAM_ADDR),
    .bank_addr     (DRAM_BA),
    .data          (DRAM_DQ),
    .clock_enable  (DRAM_CKE),
    .cs_n          (DRAM_CS_N),
    .ras_n         (DRAM_RAS_N),
    .cas_n         (DRAM_CAS_N),
    .we_n          (DRAM_WE_N),
    .data_mask_low (DRAM_LDQM),
    .data_mask_high(DRAM_UDQM)
);

wire        busy;

assign busy = wr_full | rdaddr_full;

de0cv_interface #(.HADDR_WIDTH(HADDR_WIDTH)) de0cv_interfacei (
  /* Human Interface */
    .button_n     (KEY),
    .sw           (SW),
    .leds         (LEDR),

  /* Controller Interface */
    .haddr        (wr_fifo[HADDR_WIDTH+16-1:16]),// RW-FIFO- data1
    .busy         (busy),          // RW-FIFO- full

    .wr_enable    (wr_enable),     // WR-FIFO- write
    .wr_data      (wr_fifo[15:00]),// WR-FIFO- data2

    .rd_enable    (rd_enable),     // RO-FIFO- write

    .rd_data      (rddata_fifo),   // RI-FIFO- data
    .rd_rdy       (rd_ready),      // RI-FIFO-~empty
    .rd_ack       (rd_ack),        // RI-FIFO- read

  /* basics */
    .rst_n        (RESET_N),
    .clk          (clk2m)

);

endmodule // toplevel

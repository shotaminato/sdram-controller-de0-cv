/**
 * SystemVerilog SDRAM controller for ISSI IS42S16320F on DE0-CV
 *  32M x 16 (64 megabytes), CAS 3
 *
 * Combinational logic is assign-only. Sequential logic uses DFF macros.
 */

`include "dff.svh"

module sdram_controller #(
    parameter int ROW_WIDTH     = 13,
    parameter int COL_WIDTH     = 10,
    parameter int BANK_WIDTH    = 2,
    parameter int SDRADDR_WIDTH = (ROW_WIDTH > COL_WIDTH) ? ROW_WIDTH : COL_WIDTH,
    parameter int HADDR_WIDTH   = BANK_WIDTH + ROW_WIDTH + COL_WIDTH,
    parameter int CLK_FREQUENCY = 100,  // MHz
    parameter int REFRESH_TIME  = 64,   // ms
    parameter int REFRESH_COUNT = 8192
) (
    //--------------------------------------------------------------------------
    // Host interface
    //--------------------------------------------------------------------------
    input  logic [HADDR_WIDTH-1:0] wr_addr,
    input  logic [15:0]            wr_data,
    input  logic                   wr_enable,

    input  logic [HADDR_WIDTH-1:0] rd_addr,
    output logic [15:0]            rd_data,
    input  logic                   rd_enable,
    output logic                   rd_ready,

    output logic                   busy,
    input  logic                   rst_n,
    input  logic                   clk,

    //--------------------------------------------------------------------------
    // SDRAM interface
    //--------------------------------------------------------------------------
    output logic [SDRADDR_WIDTH-1:0] addr,
    output logic [BANK_WIDTH-1:0]    bank_addr,
    inout  wire  [15:0]              data,
    output logic                     clock_enable,
    output logic                     cs_n,
    output logic                     ras_n,
    output logic                     cas_n,
    output logic                     we_n,
    output logic                     data_mask_low,
    output logic                     data_mask_high
);

    //==========================================================================
    // Refresh interval
    //==========================================================================
    localparam int CYCLES_BETWEEN_REFRESH = (CLK_FREQUENCY
                                             * 1_000
                                             * REFRESH_TIME
                                            ) / REFRESH_COUNT;

    //==========================================================================
    // FSM states
    //==========================================================================
    localparam logic [4:0] IDLE       = 5'b00000;

    // Init
    localparam logic [4:0] INIT_NOP1  = 5'b01000;
    localparam logic [4:0] INIT_PRE1  = 5'b01001;
    localparam logic [4:0] INIT_NOP1_1= 5'b00101;
    localparam logic [4:0] INIT_REF1  = 5'b01010;
    localparam logic [4:0] INIT_NOP2  = 5'b01011;
    localparam logic [4:0] INIT_REF2  = 5'b01100;
    localparam logic [4:0] INIT_NOP3  = 5'b01101;
    localparam logic [4:0] INIT_LOAD  = 5'b01110;
    localparam logic [4:0] INIT_NOP4  = 5'b01111;

    // Refresh
    localparam logic [4:0] REF_PRE    = 5'b00001;
    localparam logic [4:0] REF_NOP1   = 5'b00010;
    localparam logic [4:0] REF_REF    = 5'b00011;
    localparam logic [4:0] REF_NOP2   = 5'b00100;

    // Read
    localparam logic [4:0] READ_ACT   = 5'b10000;
    localparam logic [4:0] READ_NOP1  = 5'b10001;
    localparam logic [4:0] READ_CAS   = 5'b10010;
    localparam logic [4:0] READ_NOP2  = 5'b10011;
    localparam logic [4:0] READ_READ  = 5'b10100;

    // Write
    localparam logic [4:0] WRIT_ACT   = 5'b11000;
    localparam logic [4:0] WRIT_NOP1  = 5'b11001;
    localparam logic [4:0] WRIT_CAS   = 5'b11010;
    localparam logic [4:0] WRIT_NOP2  = 5'b11011;

    //==========================================================================
    // SDRAM commands  {CKE, CS_n, RAS_n, CAS_n, WE_n, BA1, BA0, A10}
    //==========================================================================
    localparam logic [7:0] CMD_PALL = 8'b10010001;
    localparam logic [7:0] CMD_REF  = 8'b10001000;
    localparam logic [7:0] CMD_NOP  = 8'b10111000;
    localparam logic [7:0] CMD_MRS  = 8'b10000000;
    localparam logic [7:0] CMD_BACT = 8'b10011000;
    localparam logic [7:0] CMD_READ = 8'b10101001;
    localparam logic [7:0] CMD_WRIT = 8'b10100001;

    //==========================================================================
    // Registers (DFF)
    //==========================================================================
    logic [HADDR_WIDTH-1:0]   haddr_r;
    logic [15:0]              wr_data_r;
    logic [15:0]              rd_data_r;
    logic [3:0]               state_cnt;
    logic [9:0]               refresh_cnt;
    logic [7:0]               command;
    logic [4:0]               state;
    logic                     rd_ready_r;

    //==========================================================================
    // Combinational next / address
    //==========================================================================
    logic [4:0]               next;
    logic [7:0]               command_nxt;
    logic [3:0]               state_cnt_nxt;
    logic [SDRADDR_WIDTH-1:0] addr_r;
    logic [BANK_WIDTH-1:0]    bank_addr_r;

    logic [HADDR_WIDTH-1:0]   haddr_n;
    logic [3:0]               state_cnt_n;
    logic [9:0]               refresh_cnt_n;
    logic                     haddr_en;
    logic                     wr_data_en;
    logic                     rd_data_en;

    //--------------------------------------------------------------------------
    // FSM decode
    //--------------------------------------------------------------------------
    logic                     in_idle;
    logic                     cnt_zero;
    logic                     need_ref;
    logic                     idle_rd;
    logic                     idle_wr;
    logic                     idle_hold;
    logic                     hold;
    logic                     advance;

    //--------------------------------------------------------------------------
    // SDRAM address select
    //--------------------------------------------------------------------------
    logic                     is_rw_act;
    logic                     is_rw_cas;
    logic                     is_init_load;
    logic                     use_addr_r;
    logic [SDRADDR_WIDTH-1:0] addr_act;
    logic [SDRADDR_WIDTH-1:0] addr_cas;
    logic [SDRADDR_WIDTH-1:0] addr_mrs;
    logic [SDRADDR_WIDTH-1:0] addr_cmd;

    //--------------------------------------------------------------------------
    // One-cycle advance strobes (state_cnt == 0)
    //--------------------------------------------------------------------------
    logic                     adv_init_nop1;
    logic                     adv_init_pre1;
    logic                     adv_init_nop1_1;
    logic                     adv_init_ref1;
    logic                     adv_init_nop2;
    logic                     adv_init_ref2;
    logic                     adv_init_nop3;
    logic                     adv_init_load;
    logic                     adv_ref_pre;
    logic                     adv_ref_nop1;
    logic                     adv_ref_ref;
    logic                     adv_writ_act;
    logic                     adv_writ_nop1;
    logic                     adv_writ_cas;
    logic                     adv_read_act;
    logic                     adv_read_nop1;
    logic                     adv_read_cas;
    logic                     adv_read_nop2;
    logic                     adv_to_idle;
    logic                     adv_cmd_nop;

    //==========================================================================
    // Host-side outputs
    //==========================================================================
    assign {clock_enable, cs_n, ras_n, cas_n, we_n} = command[7:3];

    assign data_mask_high = ~state[4];
    assign data_mask_low  = ~state[4];
    assign rd_data        = rd_data_r;
    assign rd_ready       = rd_ready_r;

    //==========================================================================
    // FSM: IDLE / wait-counter / refresh vs read vs write
    //==========================================================================
    assign in_idle  = (state == IDLE);
    assign cnt_zero = ~|state_cnt;
    assign need_ref = in_idle & (refresh_cnt >= CYCLES_BETWEEN_REFRESH);
    assign idle_rd  = in_idle & ~need_ref &  rd_enable;
    assign idle_wr  = in_idle & ~need_ref & ~rd_enable &  wr_enable;
    assign idle_hold= in_idle & ~need_ref & ~rd_enable & ~wr_enable;
    assign hold     = ~in_idle & ~cnt_zero;
    assign advance  = ~in_idle &  cnt_zero;

    //==========================================================================
    // FSM: per-state advance strobes
    //==========================================================================
    assign adv_init_nop1   = advance & (state == INIT_NOP1);
    assign adv_init_pre1   = advance & (state == INIT_PRE1);
    assign adv_init_nop1_1 = advance & (state == INIT_NOP1_1);
    assign adv_init_ref1   = advance & (state == INIT_REF1);
    assign adv_init_nop2   = advance & (state == INIT_NOP2);
    assign adv_init_ref2   = advance & (state == INIT_REF2);
    assign adv_init_nop3   = advance & (state == INIT_NOP3);
    assign adv_init_load   = advance & (state == INIT_LOAD);
    assign adv_ref_pre     = advance & (state == REF_PRE);
    assign adv_ref_nop1    = advance & (state == REF_NOP1);
    assign adv_ref_ref     = advance & (state == REF_REF);
    assign adv_writ_act    = advance & (state == WRIT_ACT);
    assign adv_writ_nop1   = advance & (state == WRIT_NOP1);
    assign adv_writ_cas    = advance & (state == WRIT_CAS);
    assign adv_read_act    = advance & (state == READ_ACT);
    assign adv_read_nop1   = advance & (state == READ_NOP1);
    assign adv_read_cas    = advance & (state == READ_CAS);
    assign adv_read_nop2   = advance & (state == READ_NOP2);

    assign adv_to_idle = advance & ~(
        adv_init_nop1   | adv_init_pre1   | adv_init_nop1_1 | adv_init_ref1 |
        adv_init_nop2   | adv_init_ref2   | adv_init_nop3   | adv_init_load |
        adv_ref_pre     | adv_ref_nop1    | adv_ref_ref     |
        adv_writ_act    | adv_writ_nop1   | adv_writ_cas    |
        adv_read_act    | adv_read_nop1   | adv_read_cas    | adv_read_nop2
    );

    //==========================================================================
    // FSM: next state
    //==========================================================================
    assign next =
          (need_ref        ? REF_PRE    : '0)
        | (idle_rd         ? READ_ACT   : '0)
        | (idle_wr         ? WRIT_ACT   : '0)
        | (idle_hold       ? IDLE       : '0)
        | (hold            ? state      : '0)
        | (adv_init_nop1   ? INIT_PRE1  : '0)
        | (adv_init_pre1   ? INIT_NOP1_1: '0)
        | (adv_init_nop1_1 ? INIT_REF1  : '0)
        | (adv_init_ref1   ? INIT_NOP2  : '0)
        | (adv_init_nop2   ? INIT_REF2  : '0)
        | (adv_init_ref2   ? INIT_NOP3  : '0)
        | (adv_init_nop3   ? INIT_LOAD  : '0)
        | (adv_init_load   ? INIT_NOP4  : '0)
        | (adv_ref_pre     ? REF_NOP1   : '0)
        | (adv_ref_nop1    ? REF_REF    : '0)
        | (adv_ref_ref     ? REF_NOP2   : '0)
        | (adv_writ_act    ? WRIT_NOP1  : '0)
        | (adv_writ_nop1   ? WRIT_CAS   : '0)
        | (adv_writ_cas    ? WRIT_NOP2  : '0)
        | (adv_read_act    ? READ_NOP1  : '0)
        | (adv_read_nop1   ? READ_CAS   : '0)
        | (adv_read_cas    ? READ_NOP2  : '0)
        | (adv_read_nop2   ? READ_READ  : '0)
        | (adv_to_idle     ? IDLE       : '0);

    //==========================================================================
    // FSM: next command
    //==========================================================================
    assign adv_cmd_nop = advance & ~(
        adv_init_nop1 | adv_init_nop1_1 | adv_init_nop2 | adv_init_nop3 |
        adv_ref_nop1  | adv_writ_nop1   | adv_read_nop1
    );

    assign command_nxt =
          (need_ref        ? CMD_PALL : '0)
        | (idle_rd         ? CMD_BACT : '0)
        | (idle_wr         ? CMD_BACT : '0)
        | (idle_hold       ? CMD_NOP  : '0)
        | (hold            ? command  : '0)
        | (adv_init_nop1   ? CMD_PALL : '0)
        | (adv_init_nop1_1 ? CMD_REF  : '0)
        | (adv_init_nop2   ? CMD_REF  : '0)
        | (adv_init_nop3   ? CMD_MRS  : '0)
        | (adv_ref_nop1    ? CMD_REF  : '0)
        | (adv_writ_nop1   ? CMD_WRIT : '0)
        | (adv_read_nop1   ? CMD_READ : '0)
        | (adv_cmd_nop     ? CMD_NOP  : '0);

    //==========================================================================
    // FSM: wait-counter load value
    //==========================================================================
    assign state_cnt_nxt =
          ((adv_init_ref1 | adv_init_ref2 | adv_ref_ref) ? 4'd7 : '0)
        | ((adv_init_load | adv_writ_act | adv_writ_cas
            | adv_read_act | adv_read_cas)               ? 4'd1 : '0);

    //==========================================================================
    // SDRAM address / bank / DQ
    //==========================================================================
    assign is_rw_act    = (state == READ_ACT) | (state == WRIT_ACT);
    assign is_rw_cas    = (state == READ_CAS) | (state == WRIT_CAS);
    assign is_init_load = (state == INIT_LOAD);

    assign bank_addr_r = ((is_rw_act | is_rw_cas)
                          ? haddr_r[HADDR_WIDTH-1:HADDR_WIDTH-BANK_WIDTH]
                          : '0);

    assign addr_act = haddr_r[HADDR_WIDTH-(BANK_WIDTH+1):HADDR_WIDTH-(BANK_WIDTH+ROW_WIDTH)];
    assign addr_cas = {{(SDRADDR_WIDTH-11){1'b0}}, 1'b1, haddr_r[COL_WIDTH-1:0]};
    assign addr_mrs = {{(SDRADDR_WIDTH-10){1'b0}}, 10'b1000110000};

    assign addr_r =
          (is_rw_act    ? addr_act : '0)
        | (is_rw_cas    ? addr_cas : '0)
        | (is_init_load ? addr_mrs : '0);

    assign use_addr_r = state[4] | is_init_load;
    assign addr_cmd   = {{(SDRADDR_WIDTH-11){1'b0}}, command[0], 10'd0};

    assign addr =
          (use_addr_r  ? addr_r   : '0)
        | (~use_addr_r ? addr_cmd : '0);

    assign bank_addr =
          (state[4]  ? bank_addr_r     : '0)
        | (~state[4] ? command[2:1]    : '0);

    assign data = (state == WRIT_CAS) ? wr_data_r : 16'bz;

    //==========================================================================
    // DFF data / enables
    //==========================================================================
    assign haddr_en    = rd_enable | wr_enable;
    assign haddr_n     = (rd_enable ? rd_addr : '0) | (~rd_enable & wr_enable ? wr_addr : '0);
    assign wr_data_en  = wr_enable;
    assign rd_data_en  = (state == READ_READ);
    assign state_cnt_n = (cnt_zero ? state_cnt_nxt : '0) | (~cnt_zero ? (state_cnt - 4'd1) : '0);
    assign refresh_cnt_n =
          ((state == REF_NOP2) ? 10'd0 : '0)
        | ((state != REF_NOP2) ? (refresh_cnt + 10'd1) : '0);

    //==========================================================================
    // Sequential elements (DFF / DFFE macros)
    //==========================================================================
    `DFF(u_state,       5,           state,       next,                   clk, rst_n, INIT_NOP1)
    `DFF(u_command,     8,           command,     command_nxt,            clk, rst_n, CMD_NOP)
    `DFF(u_state_cnt,   4,           state_cnt,   state_cnt_n,            clk, rst_n, 4'hf)
    `DFF(u_refresh_cnt, 10,          refresh_cnt, refresh_cnt_n,          clk, rst_n, 10'b0)
    `DFF(u_busy,        1,           busy,        state[4],               clk, rst_n, 1'b0)
    `DFF(u_rd_ready,    1,           rd_ready_r,  (state == READ_READ),   clk, rst_n, 1'b0)
    `DFFE(u_haddr,      HADDR_WIDTH, haddr_r,     haddr_n,    haddr_en,   clk, rst_n, {HADDR_WIDTH{1'b0}})
    `DFFE(u_wr_data,    16,          wr_data_r,   wr_data,    wr_data_en, clk, rst_n, 16'b0)
    `DFFE(u_rd_data,    16,          rd_data_r,   data,       rd_data_en, clk, rst_n, 16'b0)

endmodule

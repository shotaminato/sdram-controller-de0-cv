`timescale 1ns/1ps

/**
 * Synthesizable SDRAM test for DE0-CV.
 *
 * Quick tests write an expected value, read the same address, then print
 * `addr expected got` as hex over UART (115200 8N1).
 * After that the host stays idle for two refresh windows (128 ms) so the
 * controller can refresh, then the same locations are read back.
 *
 *   00000001 1111 1111\r\n
 */
module sdram_controller_tb #(
    parameter int CLK_FREQUENCY   = 50,
    parameter int UART_BAUD       = 115200,
    parameter int REFRESH_TEST_MS = 128
) (
    input  logic        i_clk,
    input  logic        i_rst_n,

    output logic [1:0]  DRAM_BA,
    output logic [12:0] DRAM_ADDR,
    output logic        DRAM_CS_N,
    output logic        DRAM_RAS_N,
    output logic        DRAM_CAS_N,
    output logic        DRAM_WE_N,
    inout  wire  [15:0] DRAM_DQ,
    output logic        DRAM_LDQM,
    output logic        DRAM_UDQM,
    output logic        DRAM_CKE,
    output logic        DRAM_CLK,

    output logic        o_uart_tx
);

    localparam int HADDR_WIDTH     = 25;
    localparam int N_QUICK         = 5;
    localparam int N_REFRESH       = 4;
    localparam int N_TEST          = N_QUICK + N_REFRESH;
    localparam int MSG_LEN         = 20;
    localparam int PAUSE_CYCLES    = CLK_FREQUENCY * 1_000 * REFRESH_TEST_MS;
    localparam int PAUSE_CNT_WIDTH = $clog2(PAUSE_CYCLES);

    localparam logic [2:0] ST_WR_REQ  = 3'd0;
    localparam logic [2:0] ST_WR_WAIT = 3'd1;
    localparam logic [2:0] ST_RD_REQ  = 3'd2;
    localparam logic [2:0] ST_RD_WAIT = 3'd3;
    localparam logic [2:0] ST_UART    = 3'd4;
    localparam logic [2:0] ST_DONE    = 3'd5;
    localparam logic [2:0] ST_PAUSE   = 3'd6;

    logic        rst_n_meta;
    logic        rst_n;
    logic [2:0]  state;
    logic [2:0]  state_n;
    logic [3:0]  test_idx;
    logic [3:0]  test_idx_n;
    logic [15:0] rd_captured;
    logic        rd_got_ready;
    logic        rd_got_ready_n;
    logic [4:0]  uart_idx;
    logic [4:0]  uart_idx_n;
    logic [PAUSE_CNT_WIDTH-1:0] pause_cnt;
    logic [PAUSE_CNT_WIDTH-1:0] pause_cnt_n;

    logic [HADDR_WIDTH-1:0] wr_addr;
    logic [15:0]            wr_data;
    logic                   wr_enable;
    logic [HADDR_WIDTH-1:0] rd_addr;
    logic [15:0]            rd_data;
    logic                   rd_enable;
    logic                   rd_ready;
    logic                   busy;

    logic [HADDR_WIDTH-1:0] cur_addr;
    logic [15:0]            cur_exp;
    logic [31:0]            addr_ext;
    logic [MSG_LEN*8-1:0]   uart_message;
    logic [7:0]             uart_data;
    logic                   uart_valid;
    logic                   uart_ready;
    logic                   uart_fire;
    logic                   uart_last;
    logic                   last_test;
    logic                   leave_rd_wait;
    logic                   pause_done;
    logic                   after_quick;
    logic                   in_refresh_rd;

    logic in_wr_req;
    logic in_wr_wait;
    logic in_rd_req;
    logic in_rd_wait;
    logic in_uart;
    logic in_done;
    logic in_pause;

    logic [7:0] hex_addr0, hex_addr1, hex_addr2, hex_addr3;
    logic [7:0] hex_addr4, hex_addr5, hex_addr6, hex_addr7;
    logic [7:0] hex_exp0,  hex_exp1,  hex_exp2,  hex_exp3;
    logic [7:0] hex_got0,  hex_got1,  hex_got2,  hex_got3;

    function automatic logic [7:0] nibble_ascii(input logic [3:0] nibble);
        nibble_ascii =
            ((nibble <= 4'h9) ? (8'h30 + {4'h0, nibble}) : '0) |
            ((nibble >= 4'hA) ? (8'h37 + {4'h0, nibble}) : '0);
    endfunction

    assign DRAM_CLK = i_clk;

    `DFFR(rst_n_meta, 1'b1,      1'b1, i_clk, i_rst_n)
    `DFFR(rst_n,      rst_n_meta, 1'b1, i_clk, i_rst_n)

    assign cur_addr =
        ((test_idx == 4'd0) ? 25'h000_0001 : '0) |
        ((test_idx == 4'd1) ? 25'h000_0002 : '0) |
        ((test_idx == 4'd2) ? 25'h000_0400 : '0) |
        ((test_idx == 4'd3) ? {2'b01, 13'd5, 10'd7} : '0) |
        ((test_idx == 4'd4) ? 25'h000_0001 : '0) |
        ((test_idx == 4'd5) ? 25'h000_0001 : '0) |
        ((test_idx == 4'd6) ? 25'h000_0002 : '0) |
        ((test_idx == 4'd7) ? 25'h000_0400 : '0) |
        ((test_idx == 4'd8) ? {2'b01, 13'd5, 10'd7} : '0);

    assign cur_exp =
        ((test_idx == 4'd0) ? 16'h1111 : '0) |
        ((test_idx == 4'd1) ? 16'h2222 : '0) |
        ((test_idx == 4'd2) ? 16'h3333 : '0) |
        ((test_idx == 4'd3) ? 16'hABCD : '0) |
        ((test_idx == 4'd4) ? 16'hF00F : '0) |
        ((test_idx == 4'd5) ? 16'hF00F : '0) |
        ((test_idx == 4'd6) ? 16'h2222 : '0) |
        ((test_idx == 4'd7) ? 16'h3333 : '0) |
        ((test_idx == 4'd8) ? 16'hABCD : '0);

    assign wr_addr   = cur_addr;
    assign wr_data   = cur_exp;
    assign rd_addr   = cur_addr;
    assign wr_enable = (state == ST_WR_REQ);
    assign rd_enable = (state == ST_RD_REQ);

    assign in_wr_req  = (state == ST_WR_REQ);
    assign in_wr_wait = (state == ST_WR_WAIT);
    assign in_rd_req  = (state == ST_RD_REQ);
    assign in_rd_wait = (state == ST_RD_WAIT);
    assign in_uart    = (state == ST_UART);
    assign in_done    = (state == ST_DONE);
    assign in_pause   = (state == ST_PAUSE);

    assign last_test     = (test_idx == 4'(N_TEST - 1));
    assign after_quick   = (test_idx == 4'(N_QUICK - 1));
    assign in_refresh_rd = (test_idx >= 4'(N_QUICK));
    assign leave_rd_wait = in_rd_wait & (rd_got_ready | rd_ready) & ~busy;
    assign pause_done    = in_pause & (pause_cnt == PAUSE_CNT_WIDTH'(PAUSE_CYCLES - 1));

    assign uart_valid = in_uart;
    assign uart_fire  = uart_valid & uart_ready;
    assign uart_last  = uart_fire & (uart_idx == 5'(MSG_LEN - 1));

    assign state_n =
        ((in_wr_req  & ~busy)                                      ? ST_WR_REQ  : '0) |
        ((in_wr_req  &  busy)                                      ? ST_WR_WAIT : '0) |
        ((in_wr_wait &  busy)                                      ? ST_WR_WAIT : '0) |
        ((in_wr_wait & ~busy)                                      ? ST_RD_REQ  : '0) |
        ((in_rd_req  & ~busy)                                      ? ST_RD_REQ  : '0) |
        ((in_rd_req  &  busy)                                      ? ST_RD_WAIT : '0) |
        ((in_rd_wait & ~leave_rd_wait)                             ? ST_RD_WAIT : '0) |
        ((in_rd_wait &  leave_rd_wait)                             ? ST_UART    : '0) |
        ((in_uart    & ~uart_last)                                 ? ST_UART    : '0) |
        ((in_uart    &  uart_last & ~after_quick & ~in_refresh_rd) ? ST_WR_REQ  : '0) |
        ((in_uart    &  uart_last &  after_quick)                  ? ST_PAUSE   : '0) |
        ((in_uart    &  uart_last &  in_refresh_rd & ~last_test)   ? ST_RD_REQ  : '0) |
        ((in_uart    &  uart_last &  last_test)                    ? ST_DONE    : '0) |
        ((in_pause   & ~pause_done)                                ? ST_PAUSE   : '0) |
        ((in_pause   &  pause_done)                                ? ST_RD_REQ  : '0) |
        ( in_done                                                  ? ST_DONE    : '0);

    assign test_idx_n = test_idx + 4'd1;
    assign pause_cnt_n =
        ((in_pause & ~pause_done) ? (pause_cnt + PAUSE_CNT_WIDTH'(1)) : '0);
    assign rd_got_ready_n =
        (((in_rd_req | in_rd_wait) ? (rd_got_ready | rd_ready) : '0));

    assign uart_idx_n =
        ((~in_uart)              ? 5'd0              : '0) |
        (( in_uart &  uart_fire) ? (uart_idx + 5'd1) : '0) |
        (( in_uart & ~uart_fire) ? uart_idx          : '0);

    assign addr_ext = {7'b0, cur_addr};

    assign hex_addr0 = nibble_ascii(addr_ext[31:28]);
    assign hex_addr1 = nibble_ascii(addr_ext[27:24]);
    assign hex_addr2 = nibble_ascii(addr_ext[23:20]);
    assign hex_addr3 = nibble_ascii(addr_ext[19:16]);
    assign hex_addr4 = nibble_ascii(addr_ext[15:12]);
    assign hex_addr5 = nibble_ascii(addr_ext[11:8]);
    assign hex_addr6 = nibble_ascii(addr_ext[7:4]);
    assign hex_addr7 = nibble_ascii(addr_ext[3:0]);
    assign hex_exp0  = nibble_ascii(cur_exp[15:12]);
    assign hex_exp1  = nibble_ascii(cur_exp[11:8]);
    assign hex_exp2  = nibble_ascii(cur_exp[7:4]);
    assign hex_exp3  = nibble_ascii(cur_exp[3:0]);
    assign hex_got0  = nibble_ascii(rd_captured[15:12]);
    assign hex_got1  = nibble_ascii(rd_captured[11:8]);
    assign hex_got2  = nibble_ascii(rd_captured[7:4]);
    assign hex_got3  = nibble_ascii(rd_captured[3:0]);

    assign uart_message = {
        hex_addr0, hex_addr1, hex_addr2, hex_addr3,
        hex_addr4, hex_addr5, hex_addr6, hex_addr7,
        8'h20,
        hex_exp0, hex_exp1, hex_exp2, hex_exp3,
        8'h20,
        hex_got0, hex_got1, hex_got2, hex_got3,
        8'h0D, 8'h0A
    };

    assign uart_data = uart_message[(MSG_LEN - 1 - uart_idx)*8 +: 8];

    `DFFR_VAL(state,        state_n,              1'b1,              i_clk, rst_n, ST_WR_REQ)
    `DFFR    (test_idx,     test_idx_n,           uart_last & ~last_test, i_clk, rst_n)
    `DFFR    (rd_captured,  rd_data,              rd_ready,          i_clk, rst_n)
    `DFFR    (rd_got_ready, rd_got_ready_n,       1'b1,              i_clk, rst_n)
    `DFFR    (uart_idx,     uart_idx_n,           1'b1,              i_clk, rst_n)
    `DFFR    (pause_cnt,    pause_cnt_n,          1'b1,              i_clk, rst_n)

    sdram_controller #(
        .CLK_FREQUENCY(CLK_FREQUENCY)
    ) u_sdram_controller (
        .wr_addr        (wr_addr),
        .wr_data        (wr_data),
        .wr_enable      (wr_enable),
        .rd_addr        (rd_addr),
        .rd_data        (rd_data),
        .rd_enable      (rd_enable),
        .rd_ready       (rd_ready),
        .busy           (busy),
        .rst_n          (rst_n),
        .clk            (i_clk),
        .addr           (DRAM_ADDR),
        .bank_addr      (DRAM_BA),
        .data           (DRAM_DQ),
        .clock_enable   (DRAM_CKE),
        .cs_n           (DRAM_CS_N),
        .ras_n          (DRAM_RAS_N),
        .cas_n          (DRAM_CAS_N),
        .we_n           (DRAM_WE_N),
        .data_mask_low  (DRAM_LDQM),
        .data_mask_high (DRAM_UDQM)
    );

    uart_tx #(
        .BAUD_RATE   (UART_BAUD),
        .CLK_FREQ_MHZ(CLK_FREQUENCY)
    ) u_uart_tx (
        .i_clk   (i_clk),
        .i_rst_n (rst_n),
        .o_tx    (o_uart_tx),
        .i_wdata (uart_data),
        .i_wvalid(uart_valid),
        .o_wready(uart_ready)
    );

endmodule

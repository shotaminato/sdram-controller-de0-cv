`timescale 1ns/1ps

/**
 * Minimal SDRAM behavioral model for controller tests.
 * Burst length 1, CAS latency 3, auto-precharge is ignored (row stays tracked).
 *
 * Commands and DQ are sampled on negedge so registered controller outputs have
 * settled. Read data is then pipelined to be valid on the posedge where the
 * controller captures (READ_READ / rd_ready).
 */
module sdram_model (
    input  logic        clk,
    input  logic [12:0] addr,
    input  logic [1:0]  ba,
    inout  wire  [15:0] dq,
    input  logic        cke,
    input  logic        cs_n,
    input  logic        ras_n,
    input  logic        cas_n,
    input  logic        we_n
);

    // CKE x is treated as 1; the controller never parks CKE low.
    logic        cke_en;
    logic        act;
    logic        rd;
    logic        wr;
    logic        act_r;
    logic        rd_r;
    logic        wr_r;
    logic [12:0] addr_r;
    logic [1:0]  ba_r;
    logic [15:0] dq_r;
    logic [12:0] open_row [4];
    // {ba, row[3:0], col[9:0]} — enough unique rows for the self-check
    logic [15:0] mem [65536];
    logic [9:0]  col;
    logic [15:0] mem_idx;
    logic        rd_v0;
    logic        rd_v1;
    logic        rd_v2;
    logic [15:0] rd_d0;
    logic [15:0] rd_d1;
    logic [15:0] rd_d2;

    assign cke_en  = (cke === 1'b0) ? 1'b0 : 1'b1;
    assign act     = cke_en & ~cs_n & ~ras_n &  cas_n &  we_n;
    assign rd      = cke_en & ~cs_n &  ras_n & ~cas_n &  we_n;
    assign wr      = cke_en & ~cs_n &  ras_n & ~cas_n & ~we_n;
    assign col     = addr_r[9:0];
    assign mem_idx = {ba_r, open_row[ba_r][3:0], col};
    assign dq      = rd_v2 ? rd_d2 : 16'hzzzz;

    initial begin
        for (int i = 0; i < 4; i++)
            open_row[i] = 13'd0;
        for (int i = 0; i < 65536; i++)
            mem[i] = 16'd0;
        act_r  = 1'b0;
        rd_r   = 1'b0;
        wr_r   = 1'b0;
        addr_r = 13'd0;
        ba_r   = 2'd0;
        dq_r   = 16'd0;
        rd_v0  = 1'b0;
        rd_v1  = 1'b0;
        rd_v2  = 1'b0;
        rd_d0  = 16'd0;
        rd_d1  = 16'd0;
        rd_d2  = 16'd0;
    end

    always_ff @(negedge clk) begin
        act_r  <= act;
        rd_r   <= rd;
        wr_r   <= wr;
        addr_r <= addr;
        ba_r   <= ba;
        dq_r   <= dq;
    end

    always_ff @(posedge clk) begin
        if (act_r)
            open_row[ba_r] <= addr_r;

        if (wr_r)
            mem[mem_idx] <= dq_r;

        rd_v0 <= rd_r;
        rd_d0 <= mem[mem_idx];
        rd_v1 <= rd_v0;
        rd_d1 <= rd_d0;
        rd_v2 <= rd_v1;
        rd_d2 <= rd_d1;
    end

endmodule

/**
 * Minimal SDRAM behavioral model for controller tests.
 * Burst length 1, CAS latency 3, auto-precharge is ignored (row stays tracked).
 *
 * Commands and DQ are sampled on negedge so registered controller outputs have
 * settled. Read data is then pipelined to be valid on the posedge where the
 * controller captures (READ_READ / rd_ready).
 */
module sdram_model (
    input         clk,
    input  [12:0] addr,
    input  [1:0]  ba,
    inout  [15:0] dq,
    input         cke,
    input         cs_n,
    input         ras_n,
    input         cas_n,
    input         we_n
);

    /* CKE x (Verilog don't-care) is treated as 1; the controller never parks CKE low. */
    wire cke_en = (cke === 1'b0) ? 1'b0 : 1'b1;
    wire act    = cke_en & ~cs_n & ~ras_n &  cas_n &  we_n;
    wire rd     = cke_en & ~cs_n &  ras_n & ~cas_n &  we_n;
    wire wr     = cke_en & ~cs_n &  ras_n & ~cas_n & ~we_n;

    reg        act_r, rd_r, wr_r;
    reg [12:0] addr_r;
    reg [1:0]  ba_r;
    reg [15:0] dq_r;

    reg [12:0] open_row [0:3];
    /* {ba, row[3:0], col[9:0]} — enough unique rows for the self-check */
    reg [15:0] mem [0:65535];

    wire [9:0]  col    = addr_r[9:0];
    wire [15:0] mem_idx = {ba_r, open_row[ba_r][3:0], col};

    reg        rd_v0, rd_v1, rd_v2;
    reg [15:0] rd_d0, rd_d1, rd_d2;

    assign dq = rd_v2 ? rd_d2 : 16'hzzzz;

    integer i;
    initial begin
        for (i = 0; i < 4; i = i + 1)
            open_row[i] = 13'd0;
        for (i = 0; i < 65536; i = i + 1)
            mem[i] = 16'd0;
        act_r = 1'b0;
        rd_r  = 1'b0;
        wr_r  = 1'b0;
        addr_r = 13'd0;
        ba_r   = 2'd0;
        dq_r   = 16'd0;
        rd_v0 = 1'b0;
        rd_v1 = 1'b0;
        rd_v2 = 1'b0;
        rd_d0 = 16'd0;
        rd_d1 = 16'd0;
        rd_d2 = 16'd0;
    end

    always @(negedge clk) begin
        act_r  <= act;
        rd_r   <= rd;
        wr_r   <= wr;
        addr_r <= addr;
        ba_r   <= ba;
        dq_r   <= dq;
    end

    always @(posedge clk) begin
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

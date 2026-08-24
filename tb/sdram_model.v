/**
 * Minimal SDRAM behavioral model for controller tests.
 * Burst length 1, CAS latency 3, auto-precharge is ignored (row stays tracked).
 *
 * Commands are sampled #1 after posedge so registered controller outputs have
 * settled (same timing for Verilog and SystemVerilog DUTs).
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

    reg [12:0] open_row [0:3];
    /* {ba, row[3:0], col[9:0]} — enough unique rows for the self-check */
    reg [15:0] mem [0:65535];

    wire [9:0] col = addr[9:0];
    wire [15:0] wr_idx = {ba, open_row[ba][3:0], col};
    wire [15:0] rd_idx = wr_idx;

    reg        rd_v0, rd_v1, rd_v2;
    reg [15:0] rd_d0, rd_d1, rd_d2;

    assign dq = rd_v2 ? rd_d2 : 16'hzzzz;

    integer i;
    initial begin
        for (i = 0; i < 4; i = i + 1)
            open_row[i] = 13'd0;
        for (i = 0; i < 65536; i = i + 1)
            mem[i] = 16'd0;
        rd_v0 = 1'b0;
        rd_v1 = 1'b0;
        rd_v2 = 1'b0;
        rd_d0 = 16'd0;
        rd_d1 = 16'd0;
        rd_d2 = 16'd0;
    end

    always @(posedge clk) begin
        #1;
        rd_v0 <= 1'b0;
        rd_d0 <= 16'd0;

        if (act)
            open_row[ba] <= addr;

        if (wr)
            mem[wr_idx] <= dq;

        if (rd) begin
            rd_v0 <= 1'b1;
            rd_d0 <= mem[rd_idx];
        end

        rd_v1 <= rd_v0;
        rd_d1 <= rd_d0;
        rd_v2 <= rd_v1;
        rd_d2 <= rd_d1;
    end

endmodule

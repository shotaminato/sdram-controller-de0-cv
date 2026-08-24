/**
 * Self-checking SDRAM controller testbench.
 *
 * Compile with either the Verilog or SystemVerilog controller (same module
 * name). Dumps a per-cycle pin log for comparing the two implementations.
 *
 *   +LOG=<path>   cycle dump file (optional)
 */
module sdram_controller_tb;

    localparam HADDR_WIDTH = 25;
    localparam integer TIMEOUT = 20000;

    reg                      clk;
    reg                      rst_n;
    reg  [HADDR_WIDTH-1:0]   wr_addr;
    reg  [15:0]              wr_data;
    reg                      wr_enable;
    reg  [HADDR_WIDTH-1:0]   rd_addr;
    reg                      rd_enable;

    wire [15:0]              rd_data;
    wire                     rd_ready;
    wire                     busy;

    wire [12:0]              dram_addr;
    wire [1:0]               dram_ba;
    wire [15:0]              dram_dq;
    wire                     dram_cke;
    wire                     dram_cs_n;
    wire                     dram_ras_n;
    wire                     dram_cas_n;
    wire                     dram_we_n;
    wire                     dram_ldqm;
    wire                     dram_udqm;

    integer                  log;
    integer                  errors;
    integer                  cycle;
    integer                  t;
    reg [15:0]               got;
    reg [8*256-1:0]          log_path;

    sdram_controller dut (
        .wr_addr        (wr_addr),
        .wr_data        (wr_data),
        .wr_enable      (wr_enable),
        .rd_addr        (rd_addr),
        .rd_data        (rd_data),
        .rd_enable      (rd_enable),
        .rd_ready       (rd_ready),
        .busy           (busy),
        .rst_n          (rst_n),
        .clk            (clk),
        .addr           (dram_addr),
        .bank_addr      (dram_ba),
        .data           (dram_dq),
        .clock_enable   (dram_cke),
        .cs_n           (dram_cs_n),
        .ras_n          (dram_ras_n),
        .cas_n          (dram_cas_n),
        .we_n           (dram_we_n),
        .data_mask_low  (dram_ldqm),
        .data_mask_high (dram_udqm)
    );

    sdram_model mem (
        .clk  (clk),
        .addr (dram_addr),
        .ba   (dram_ba),
        .dq   (dram_dq),
        .cke  (dram_cke),
        .cs_n (dram_cs_n),
        .ras_n(dram_ras_n),
        .cas_n(dram_cas_n),
        .we_n (dram_we_n)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        cycle = 0;
        forever begin
            @(posedge clk);
            cycle = cycle + 1;
            if (cycle > TIMEOUT) begin
                $display("FAIL: timeout at cycle %0d", cycle);
                if (log) $fclose(log);
                $finish;
            end
        end
    end

    initial begin
        log = 0;
        if ($value$plusargs("LOG=%s", log_path)) begin
            log = $fopen(log_path, "w");
            if (log == 0) begin
                $display("FAIL: cannot open log %0s", log_path);
                $finish;
            end
            $fwrite(log, "# cycle rst_n wr_en rd_en busy rd_rdy wr_data rd_data addr ba cke cs ras cas we ldqm udqm dq\n");
        end
    end

    always @(posedge clk) begin
        #1;
        /* Skip reset: Verilog rd_ready_r is not reset, SV DFF is async/sync-x until rst. */
        if (log && rst_n)
            $fwrite(log,
                "%0d %b %b %b %b %b %04h %04h %04h %b %b %b %b %b %b %b %b %04h\n",
                cycle, rst_n, wr_enable, rd_enable, busy, rd_ready,
                wr_data, rd_data, dram_addr, dram_ba,
                dram_cke, dram_cs_n, dram_ras_n, dram_cas_n, dram_we_n,
                dram_ldqm, dram_udqm, dram_dq);
    end

    task do_write;
        input [HADDR_WIDTH-1:0] a;
        input [15:0]            d;
        begin
            @(posedge clk);
            wr_addr   <= a;
            wr_data   <= d;
            rd_addr   <= {HADDR_WIDTH{1'b0}};
            wr_enable <= 1'b1;
            rd_enable <= 1'b0;
            @(posedge clk);
            while (!busy) @(posedge clk);
            wr_enable <= 1'b0;
            while (busy) @(posedge clk);
        end
    endtask

    task do_read;
        input  [HADDR_WIDTH-1:0] a;
        output [15:0]            d;
        begin
            @(posedge clk);
            rd_addr   <= a;
            wr_addr   <= {HADDR_WIDTH{1'b0}};
            wr_data   <= 16'd0;
            rd_enable <= 1'b1;
            wr_enable <= 1'b0;
            @(posedge clk);
            while (!busy) @(posedge clk);
            rd_enable <= 1'b0;
            while (!rd_ready) @(posedge clk);
            d = rd_data;
            while (busy) @(posedge clk);
        end
    endtask

    task expect_eq;
        input [HADDR_WIDTH-1:0] a;
        input [15:0]            exp;
        input [15:0]            act;
        begin
            if (act !== exp) begin
                $display("FAIL: addr %h expected %04h got %04h (cycle %0d)",
                         a, exp, act, cycle);
                errors = errors + 1;
            end else
                $display("PASS: addr %h = %04h", a, act);
        end
    endtask

    initial begin
        errors    = 0;
        rst_n     = 1'b0;
        wr_addr   = {HADDR_WIDTH{1'b0}};
        wr_data   = 16'd0;
        wr_enable = 1'b0;
        rd_addr   = {HADDR_WIDTH{1'b0}};
        rd_enable = 1'b0;

        /* Change reset on negedge so both sync (Verilog) and async (SV) DFFs agree. */
        repeat (8) @(negedge clk);
        rst_n = 1'b1;

        /* INIT: reset wait 15, precharge, two refreshes, MRS */
        repeat (80) @(posedge clk);

        do_write(25'h000_0001, 16'h1111);
        do_write(25'h000_0002, 16'h2222);
        do_write(25'h000_0400, 16'h3333);
        do_write({2'b01, 13'd5, 10'd7}, 16'hABCD);

        do_read(25'h000_0001, got);
        expect_eq(25'h000_0001, 16'h1111, got);
        do_read(25'h000_0002, got);
        expect_eq(25'h000_0002, 16'h2222, got);
        do_read(25'h000_0400, got);
        expect_eq(25'h000_0400, 16'h3333, got);
        do_read({2'b01, 13'd5, 10'd7}, got);
        expect_eq({2'b01, 13'd5, 10'd7}, 16'hABCD, got);

        do_write(25'h000_0001, 16'hF00F);
        do_read(25'h000_0001, got);
        expect_eq(25'h000_0001, 16'hF00F, got);
        do_read(25'h000_0002, got);
        expect_eq(25'h000_0002, 16'h2222, got);

        if (errors) begin
            $display("FAIL: %0d mismatches", errors);
            if (log) $fclose(log);
            $finish;
        end

        $display("PASS: sdram_controller_tb");
        if (log) $fclose(log);
        $finish;
    end

endmodule

`timescale 1ns/1ps

/**
 * Self-checking SDRAM controller testbench.
 *
 *   +LOG=<path>   optional per-cycle pin dump
 */
module sdram_controller_tb;

    localparam int  HADDR_WIDTH = 25;
    localparam int  TIMEOUT     = 30000;
    localparam time CLK_PERIOD  = 10ns;

    logic                    clk;
    logic                    rst_n;
    logic [HADDR_WIDTH-1:0]  wr_addr;
    logic [15:0]             wr_data;
    logic                    wr_enable;
    logic [HADDR_WIDTH-1:0]  rd_addr;
    logic                    rd_enable;
    logic [15:0]             rd_data;
    logic                    rd_ready;
    logic                    busy;
    logic [12:0]             dram_addr;
    logic [1:0]              dram_ba;
    wire  [15:0]             dram_dq;
    logic                    dram_cke;
    logic                    dram_cs_n;
    logic                    dram_ras_n;
    logic                    dram_cas_n;
    logic                    dram_we_n;
    logic                    dram_ldqm;
    logic                    dram_udqm;
    logic [15:0]             got;

    int    log;
    int    errors;
    int    cycle;
    string log_path;

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

    task automatic do_write(
        input logic [HADDR_WIDTH-1:0] a,
        input logic [15:0]            d
    );
        @(posedge clk);
        wr_addr   = a;
        wr_data   = d;
        rd_addr   = '0;
        wr_enable = 1'b1;
        rd_enable = 1'b0;
        @(posedge clk);
        while (!busy) @(posedge clk);
        wr_enable = 1'b0;
        while (busy) @(posedge clk);
    endtask

    task automatic do_read(
        input  logic [HADDR_WIDTH-1:0] a,
        output logic [15:0]            d
    );
        @(posedge clk);
        rd_addr   = a;
        wr_addr   = '0;
        wr_data   = 16'd0;
        rd_enable = 1'b1;
        wr_enable = 1'b0;
        @(posedge clk);
        while (!busy) @(posedge clk);
        rd_enable = 1'b0;
        while (!rd_ready) @(posedge clk);
        d = rd_data;
        while (busy) @(posedge clk);
    endtask

    task automatic expect_eq(
        input logic [HADDR_WIDTH-1:0] a,
        input logic [15:0]            exp,
        input logic [15:0]            act
    );
        if (act !== exp) begin
            $display("FAIL: addr %h expected %04h got %04h (cycle %0d)",
                     a, exp, act, cycle);
            errors = errors + 1;
        end else begin
            $display("PASS: addr %h = %04h", a, act);
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    initial begin
        cycle = 0;
        forever begin
            @(posedge clk);
            cycle = cycle + 1;
            if (cycle > TIMEOUT) begin
                $display("FAIL: timeout at cycle %0d", cycle);
                if (log != 0) $fclose(log);
                $fatal;
            end
        end
    end

    initial begin
        log = 0;
        if ($value$plusargs("LOG=%s", log_path)) begin
            log = $fopen(log_path, "w");
            if (log == 0) begin
                $display("FAIL: cannot open log %0s", log_path);
                $fatal;
            end
            $fwrite(log, "# cycle rst_n wr_en rd_en busy rd_rdy wr_data rd_data addr ba cke cs ras cas we ldqm udqm dq\n");
        end
        forever begin
            @(posedge clk);
            #1ns;
            if ((log != 0) && rst_n)
                $fwrite(log,
                    "%0d %b %b %b %b %b %04h %04h %04h %b %b %b %b %b %b %b %b %04h\n",
                    cycle, rst_n, wr_enable, rd_enable, busy, rd_ready,
                    wr_data, rd_data, dram_addr, dram_ba,
                    dram_cke, dram_cs_n, dram_ras_n, dram_cas_n, dram_we_n,
                    dram_ldqm, dram_udqm, dram_dq);
        end
    end

    initial begin
        errors    = 0;
        rst_n     = 1'b0;
        wr_addr   = '0;
        wr_data   = 16'd0;
        wr_enable = 1'b0;
        rd_addr   = '0;
        rd_enable = 1'b0;

        repeat (8) @(negedge clk);
        rst_n = 1'b1;

        // INIT: 100 µs NOP, precharge, two refreshes, MRS
        // wr_enable is held until busy, so this can overlap the long NOP
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

        if (errors != 0) begin
            $display("FAIL: %0d mismatches", errors);
            if (log != 0) $fclose(log);
            $fatal;
        end

        $display("PASS: sdram_controller_tb");
        if (log != 0) $fclose(log);
        $finish;
    end

endmodule

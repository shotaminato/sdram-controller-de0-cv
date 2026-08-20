// DFF primitive. Sequential always is allowed only in this module.
module dff #(
    parameter int WIDTH = 1,
    parameter logic [WIDTH-1:0] RST_VAL = '0
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) q <= RST_VAL;
        else        q <= d;
    end
endmodule

module dffe #(
    parameter int WIDTH = 1,
    parameter logic [WIDTH-1:0] RST_VAL = '0
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             en,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);
    logic [WIDTH-1:0] d_in;

    assign d_in = (en ? d : '0) | (~en ? q : '0);

    dff #(
        .WIDTH   (WIDTH),
        .RST_VAL (RST_VAL)
    ) u_dff (
        .clk   (clk),
        .rst_n (rst_n),
        .d     (d_in),
        .q     (q)
    );
endmodule

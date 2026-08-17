// Cyclone V PLL for DE0-CV
//  CLOCK_50 (50 MHz) -> 100 MHz SDRAM clock
//  1 MHz UI clock is divided in fabric: Cyclone V fPLL
//  minimum output is about 1.2 MHz, so 1 MHz cannot be generated directly.

module pll (
    input  refclk,
    input  rst,
    output outclk_0,
    output outclk_1
);

    wire clk100m;
    wire locked;

    altera_pll #(
        .fractional_vco_multiplier("false"),
        .reference_clock_frequency("50.0 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(1),
        .output_clock_frequency0("100.000000 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .rst      (rst),
        .outclk   (clk100m),
        .locked   (locked),
        .fboutclk (),
        .fbclk    (1'b0),
        .refclk   (refclk)
    );

    assign outclk_0 = clk100m;

    // 100 MHz / 100 = 1 MHz (toggle every 50 cycles)
    reg [5:0] div_cnt;
    reg       clk1m_r;
    wire      div_rst;

    assign div_rst = rst | ~locked;

    always @(posedge clk100m)
      if (div_rst)
        begin
        div_cnt <= 6'd0;
        clk1m_r <= 1'b0;
        end
      else if (div_cnt == 6'd49)
        begin
        div_cnt <= 6'd0;
        clk1m_r <= ~clk1m_r;
        end
      else
        div_cnt <= div_cnt + 1'b1;

    assign outclk_1 = clk1m_r;

endmodule

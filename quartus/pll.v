// Cyclone V PLL for DE0-CV
//  CLOCK_50 (50 MHz) -> 100 MHz SDRAM clock
//                     -> 2 MHz board test interface clock
//  2 MHz is used instead of the original 1 MHz because Cyclone V fPLL
//  cannot generate 1 MHz (minimum output is about 1.2 MHz).

module pll (
    input  refclk,
    input  rst,
    output outclk_0,
    output outclk_1
);

    wire [1:0] pll_clk;

    altera_pll #(
        .fractional_vco_multiplier("false"),
        .reference_clock_frequency("50.0 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(2),
        .output_clock_frequency0("100.000000 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1("2.000000 MHz"),
        .phase_shift1("0 ps"),
        .duty_cycle1(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .rst      (rst),
        .outclk   (pll_clk),
        .locked   (),
        .fboutclk (),
        .fbclk    (1'b0),
        .refclk   (refclk)
    );

    assign outclk_0 = pll_clk[0];
    assign outclk_1 = pll_clk[1];

endmodule

`default_nettype none

/*
 * HDMI Clock Generator for Tang Nano 20K (Gowin GW2AR-18)
 * 
 * Multiplies onboard 27.0 MHz oscillator (pin 4) via Gowin rPLL and CLKDIV:
 * - 371.25 MHz serial clock (5x TMDS bit clock for 720p60 HDMI)
 * - 74.25 MHz pixel clock (video timing, pixel generation)
 * Refer to the Gowin Clock User Guide PDF in documentation for port list
 */

module hdmi_clock_gen (
    input wire clk_in,
    input wire rst,
    output wire pixel_clk,
    output wire serial_clk,
    output wire locked
);

    wire clk_serial;
    rPLL #(
        .FCLKIN          ("27"),
        .DEVICE          ("GW2AR-18C"),
        .IDIV_SEL        (3),            // PFD = 27 / 4 = 6.75 MHz
        .FBDIV_SEL       (54),           // CLKOUT = 6.75 * 55 = 371.25 MHz
        .ODIV_SEL        (2),            // VCO = 371.25 * 2 = 742.5 MHz
        .DYN_IDIV_SEL    ("false"),
        .DYN_FBDIV_SEL   ("false"),
        .DYN_ODIV_SEL    ("false"),
        .DYN_DA_EN       ("true"),
        .DUTYDA_SEL      ("1000"),
        .CLKFB_SEL       ("internal"),
        .CLKOUT_FT_DIR   (1'b1),
        .CLKOUTP_FT_DIR  (1'b1),
        .CLKOUT_DLY_STEP (0),
        .CLKOUTP_DLY_STEP(0),
        .CLKOUT_BYPASS   ("false"),
        .CLKOUTP_BYPASS  ("false"),
        .CLKOUTD_BYPASS  ("false"),
        .DYN_SDIV_SEL    (2),
        .CLKOUTD_SRC     ("CLKOUT"),
        .CLKOUTD3_SRC    ("CLKOUT")
    ) pll_inst (
        .CLKIN   (clk_in),
        .CLKOUT  (clk_serial),
        .LOCK    (locked),
        .CLKOUTP (),
        .CLKOUTD (),
        .CLKOUTD3(),
        .RESET   (rst),
        .RESET_P (1'b0),
        .CLKFB   (1'b0),
        .FBDSEL  (6'b0),
        .IDSEL   (6'b0),
        .ODSEL   (6'b0),
        .PSDA    (4'b0),
        .DUTYDA  (4'b0),
        .FDLY    (4'b0)
    );

    CLKDIV #(
        .DIV_MODE("5"),
        .GSREN("false")
    ) clkdiv_inst (
        .CLKOUT(pixel_clk),
        .HCLKIN(clk_serial),
        .RESETN(~rst & locked),
        .CALIB (1'b1)
    );

    assign serial_clk = clk_serial;

endmodule

`default_nettype wire

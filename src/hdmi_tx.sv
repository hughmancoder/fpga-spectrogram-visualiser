`default_nettype none

/*
 HDMI / DVI Transmitter Wrapper
 
 This module serves as the top-level wrapper for the TMDS encoders and the 
 physical FPGA high-speed serialisers

Refer to Gowin DVI TX RX IP guide chapter 3.3.1
 
 1. It instantiates three TMDS Encoders (one for each color channel).
 2. It takes the 10-bit parallel output from the encoders and feeds it into 
    OSER10 primitives. OSER10 is a Gowin hardware primitive that takes 10 parallel 
    bits and perfectly serializes them into a 1-bit high-speed stream using a 
    Double Data Rate (DDR) fast clock.
 3. It takes the single-ended high-speed bitstream and passes it through a 
    ELVDS_OBUF primitive. This is another Gowin hardware primitive that converts 
    a single voltage signal into a true differential signal pair (P and N) required 
    by the physical HDMI cable.
*/

module hdmi_tx (
    input wire pixel_clk,  // 74.25 MHz
    input wire serial_clk,  // 371.25 MHz
    input wire rst_n,

    // Video signals
    input wire [7:0] red,
    input wire [7:0] green,
    input wire [7:0] blue,
    input wire hsync,
    input wire vsync,
    input wire de,

    // Differential HDMI outputs
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n
);

    wire [9:0] encoded_r;
    wire [9:0] encoded_g;
    wire [9:0] encoded_b;

    // TMDS Encoders
    tmds_encoder enc_b (
        .clk     (pixel_clk),
        .rst_n   (rst_n),
        .data_in (blue),
        .ctrl_in ({vsync, hsync}),
        .de      (de),
        .tmds_out(encoded_b)
    );

    tmds_encoder enc_g (
        .clk     (pixel_clk),
        .rst_n   (rst_n),
        .data_in (green),
        .ctrl_in (2'b00),
        .de      (de),
        .tmds_out(encoded_g)
    );

    tmds_encoder enc_r (
        .clk     (pixel_clk),
        .rst_n   (rst_n),
        .data_in (red),
        .ctrl_in (2'b00),
        .de      (de),
        .tmds_out(encoded_r)
    );

    // OSER10 Instantiations
    wire [2:0] tmds_serial;
    wire tmds_clk_serial;

    /*
    After encoding, the 8-bit video data is converted into 10-bit data, and then
    the parallel data is converted into serial data by the serializer OSER10.
    */

    // Data channels, Refer to 3.4 IOB in datasheet for OSER specifications. 
    OSER10 oser_b (
        .Q    (tmds_serial[0]),
        .D0   (encoded_b[0]),
        .D1   (encoded_b[1]),
        .D2   (encoded_b[2]),
        .D3   (encoded_b[3]),
        .D4   (encoded_b[4]),
        .D5   (encoded_b[5]),
        .D6   (encoded_b[6]),
        .D7   (encoded_b[7]),
        .D8   (encoded_b[8]),
        .D9   (encoded_b[9]),
        .FCLK (serial_clk),      // fast clock
        .PCLK (pixel_clk),       // slow clock
        .RESET(~rst_n)
    );

    OSER10 oser_g (
        .Q    (tmds_serial[1]),
        .D0   (encoded_g[0]),
        .D1   (encoded_g[1]),
        .D2   (encoded_g[2]),
        .D3   (encoded_g[3]),
        .D4   (encoded_g[4]),
        .D5   (encoded_g[5]),
        .D6   (encoded_g[6]),
        .D7   (encoded_g[7]),
        .D8   (encoded_g[8]),
        .D9   (encoded_g[9]),
        .FCLK (serial_clk),
        .PCLK (pixel_clk),
        .RESET(~rst_n)
    );

    OSER10 oser_r (
        .Q    (tmds_serial[2]),
        .D0   (encoded_r[0]),
        .D1   (encoded_r[1]),
        .D2   (encoded_r[2]),
        .D3   (encoded_r[3]),
        .D4   (encoded_r[4]),
        .D5   (encoded_r[5]),
        .D6   (encoded_r[6]),
        .D7   (encoded_r[7]),
        .D8   (encoded_r[8]),
        .D9   (encoded_r[9]),
        .FCLK (serial_clk),
        .PCLK (pixel_clk),
        .RESET(~rst_n)
    );

    // Clock channel (outputs 10'b0000011111 matching Gowin DVI IP core)
    OSER10 oser_clk (
        .Q    (tmds_clk_serial),
        .D0   (1'b0),
        .D1   (1'b0),
        .D2   (1'b0),
        .D3   (1'b0),
        .D4   (1'b0),
        .D5   (1'b1),
        .D6   (1'b1),
        .D7   (1'b1),
        .D8   (1'b1),
        .D9   (1'b1),
        .FCLK (serial_clk),
        .PCLK (pixel_clk),
        .RESET(~rst_n)
    );

    // Differential Output Buffers
    TLVDS_OBUF tlvds_b (
        .I (tmds_serial[0]),
        .O (tmds_data_p[0]),
        .OB(tmds_data_n[0])
    );

    TLVDS_OBUF tlvds_g (
        .I (tmds_serial[1]),
        .O (tmds_data_p[1]),
        .OB(tmds_data_n[1])
    );

    TLVDS_OBUF tlvds_r (
        .I (tmds_serial[2]),
        .O (tmds_data_p[2]),
        .OB(tmds_data_n[2])
    );

    TLVDS_OBUF tlvds_c (
        .I (tmds_clk_serial),
        .O (tmds_clk_p),
        .OB(tmds_clk_n)
    );

endmodule

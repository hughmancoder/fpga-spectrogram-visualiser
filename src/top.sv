`default_nettype none


module top (
    input wire clk,  // 27 MHz onboard crystal oscillator
    input wire [1:0] btn,  // Onboard buttons (active-low: 0 = pressed, 1 = released)

    // HDMI / TMDS Outputs
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n,
    output wire [5:0] led,  // Onboard LEDs (active-low: 0 = lit)

    // I2S microphone pins 
    output wire i2s_sck,  // Pin 27
    output wire i2s_ws,  // Pin 28
    input wire i2s_sd  // Pin 29
);

    localparam int NUM_BARS = 32;

    // Clock generation 
    //  74.25 MHz pixel clock, 371.25 MHz 5x TMDS serial clock
    logic clk_pixel, clk_serial;
    logic sys_rst_n;  // active low system reset, high once the PLL has locked
    logic rst_n_audio, rst_n_pixel;  // sys_rst_n synchronised to each clock domain

    assign led[0] = !sys_rst_n;

    hdmi_clock_gen u_clock_gen (
        .clk_in    (clk),
        .rst       (1'b0),        // active high reseta
        .pixel_clk (clk_pixel),
        .serial_clk(clk_serial),
        .locked    (sys_rst_n)    // outputs 1 when clocks are stable
    );

    // PLL lock is asynchronous to every clock, so each domain releases reset on its own clock edge
    reset_sync u_reset_sync_audio (
        .clk   (clk),
        .arst_n(sys_rst_n),
        .rst_n (rst_n_audio)
    );

    reset_sync u_reset_sync_pixel (
        .clk   (clk_pixel),
        .arst_n(sys_rst_n),
        .rst_n (rst_n_pixel)
    );

    // Video sync and timing generation 
    logic hsync, vsync, data_enable;
    logic [11:0] pixel_x, pixel_y;


    video_sync u_video_sync (
        .clk        (clk_pixel),
        .rst_n      (rst_n_pixel),
        .hsync      (hsync),
        .vsync      (vsync),
        .data_enable(data_enable),
        .pixel_x    (pixel_x),
        .pixel_y    (pixel_y)
    );

    // Audio path runs from the 27 MHz crystal clock
    logic signed [23:0] sample_data;
    logic sample_valid;

    // 27 MHz / 10 = 2.7 MHz SCK -> 42.19 kHz sample rate (INMP441 SCK limit is 3.2 MHz)
    i2s_rx #(
        .CLK_DIV(10)
    ) u_i2s_rx (
        .clk         (clk),
        .rst_n       (rst_n_audio),
        .i2s_sck     (i2s_sck),
        .i2s_ws      (i2s_ws),
        .i2s_sd      (i2s_sd),
        .sample_data (sample_data),
        .sample_valid(sample_valid)
    );


    logic [$clog2(NUM_BARS)-1:0] bin_idx;
    logic [7:0] mag_out;
    logic mag_valid;

    fft u_fft (
        .clk         (clk),
        .rst_n       (rst_n_audio),
        .sample_in   (sample_data),
        .sample_valid(sample_valid),
        .bin_idx     (bin_idx),
        .mag_out     (mag_out),
        .mag_valid   (mag_valid)
    );

    // Display bar ram
    logic [7:0] bars[0:NUM_BARS-1];
    logic [4:0] bar_addr;
    logic [7:0] bar_level;

    initial begin
        for (int i = 0; i < NUM_BARS; i = i + 1) begin
            bars[i] = 8'd0;
        end
    end

    // Written from the audio clock domain, read from the pixel clock domain.
    // A value changing mid read only affects one pixel of one bar.
    always_ff @(posedge clk) begin
        if (mag_valid) bars[bin_idx] <= mag_out;
    end

    always_ff @(posedge clk_pixel) begin
        bar_level <= bars[bar_addr];
    end

    // single-clock-cycle pulse on first pixel frame entry 
    logic frame_tick;
    assign frame_tick = (pixel_x == '0 && pixel_y == '0 && data_enable);

    // Graphic computation module
    logic [23:0] bar_rgb_data;

    bar_renderer #(
        .NUM_BARS  (32),
        .BAR_WIDTH (40),
        .GAP_WIDTH (4),
        .Y_BOTTOM  (450),
        .MAX_HEIGHT(256)
    ) u_bar_renderer (
        .clk         (clk_pixel),
        .rst_n       (rst_n_pixel),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .active_video(data_enable),
        .bar_level   (bar_level),
        .bar_addr    (bar_addr),
        .rgb_out     (bar_rgb_data)
    );

    // 2-Cycle pipeline matching delay for video sync signals
    // hdmi_tx needs two sets of signals to arrive at its inputs on the exact same clock cycle for every pixel. Namely rgb_out data from bar_render and video timing data from video_sync. 
    // rgb_data is delayed by two clock cycles due to two ffs inside bar_renderer. 
    // Delay video_sync data by two clock cycles to align display data

    logic [1:0] hsync_f, vsync_f, data_enable_f;
    always_ff @(posedge clk_pixel or negedge rst_n_pixel) begin
        if (!rst_n_pixel) begin
            hsync_f <= 2'b00;
            vsync_f <= 2'b00;
            data_enable_f <= 2'b00;
        end else begin
            hsync_f <= {hsync_f[0], hsync};
            vsync_f <= {vsync_f[0], vsync};
            data_enable_f    <= {data_enable_f[0],    data_enable};
        end
    end


    // TMDS Encoding and HDMI Output (hdmi_tx)
    hdmi_tx u_hdmi_tx (
        .pixel_clk  (clk_pixel),
        .serial_clk (clk_serial),
        .rst_n      (rst_n_pixel),
        .red        (bar_rgb_data[23:16]),
        .green      (bar_rgb_data[15:8]),
        .blue       (bar_rgb_data[7:0]),
        .hsync      (hsync_f[1]),
        .vsync      (vsync_f[1]),
        .de         (data_enable_f[1]),
        .tmds_clk_p (tmds_clk_p),
        .tmds_clk_n (tmds_clk_n),
        .tmds_data_p(tmds_data_p),
        .tmds_data_n(tmds_data_n)
    );

endmodule

`default_nettype wire

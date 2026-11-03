`default_nettype none


module top (
    input  wire       clk,      // 27 MHz onboard crystal oscillator
    input  wire [1:0] btn,      // Onboard buttons (active-low: 0 = pressed, 1 = released)
    
    // HDMI / TMDS Outputs
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n,
    output wire [5:0] led       // Onboard LEDs (active-low: 0 = lit)

    // I2S Microphone Pins 
    output wire       i2s_sck, // 73
    output wire       i2s_ws, // 74
    input  wire       i2s_sd // 75
);

    // Clock Generation 
    //  74.25 MHz pixel clock, 371.25 MHz 5x TMDS serial clock
    logic clk_pixel, clk_serial;
    logic sys_rst_n;   // active low system reset 

    assign led[0] = !sys_rst_n;

    hdmi_clock_gen u_clock_gen (
    .clk_in     (clk),
    .rst        (1'b0), // active high reseta
    .pixel_clk  (clk_pixel),
    .serial_clk (clk_serial),
    .locked(sys_rst_n) // outputs 1 when clocks are stable
    );

    // Video Sync and Timing Generation 
    logic hsync, vsync, data_enable; 
    logic [11:0] pixel_x, pixel_y;

    video_sync u_video_sync(
        .clk(clk_pixel), 
        .rst_n(sys_rst_n),
        .hsync(hsync),
        .vsync(vsync), 
        .data_enable(data_enable),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y)
    );

    
    
    // NUM_BARS * BAR_WIDTH = 1280  -->  32 bars * 40 px = 1280 px
    // bar_addr width = $clog2(NUM_BARS) = $clog2(32) = 5 bits 
    logic [4:0] bar_addr;
    logic [7:0] bar_level;

    // single-clock-cycle pulse on first pixel frame entry 
    logic frame_tick;
    assign frame_tick = (pixel_x == '0 && pixel_y == '0 && data_enable);

    spectrum_pattern_gen #(
        .NUM_BARS       (32),
        .BAR_HEIGHT_MAX (255),
        .DATA_WIDTH     (8)
    ) u_pattern_gen (
        .clk        (clk_pixel),
        .rst_n      (sys_rst_n),
        .tick       (frame_tick),
        .bar_idx    (bar_addr),
        .bar_level  (bar_level),
        .write_addr (),
        .write_data (),
        .write_en   ()
    );


    // Graphic computation module
    logic [23:0] bar_rgb_data;

    bar_renderer #(
        .NUM_BARS   (32),
        .BAR_WIDTH  (40),
        .GAP_WIDTH  (4),
        .Y_BOTTOM   (450),
        .MAX_HEIGHT (256)
    ) u_bar_renderer (
        .clk(clk_pixel),
        .rst_n(sys_rst_n),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .active_video(data_enable),
        .bar_level(bar_level),
        .bar_addr(bar_addr),
        .rgb_out(bar_rgb_data)
    );

    // 2-Cycle Pipeline Matching Delay for Video Sync Signals
    // hdmi_tx needs two sets of signals to arrive at its inputs on the exact same clock cycle for every pixel. Namely rgb_out data from bar_render and video timing data from video_sync. 
    // rgb_data is delayed by two clock cycles due to two ffs inside bar_renderer. 
    // Delay video_sync data by two clock cycles to align display data

    logic [1:0] hsync_f, vsync_f, data_enable_f;
    always_ff @(posedge clk_pixel or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
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
    hdmi_tx u_hdmi_tx(
        .pixel_clk(clk_pixel), 
        .serial_clk(clk_serial), 
        .rst_n(sys_rst_n),
        .red(bar_rgb_data[23:16]),
        .green(bar_rgb_data[15:8]),
        .blue(bar_rgb_data[7:0]),
        .hsync(hsync_f[1]),
        .vsync(vsync_f[1]),
        .de(data_enable_f[1]),
        .tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p),
        .tmds_data_n(tmds_data_n)
    );

endmodule

`default_nettype wire

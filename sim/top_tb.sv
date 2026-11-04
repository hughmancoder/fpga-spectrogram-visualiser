`timescale 1ns / 1ps
`default_nettype none

/*
Full chip test: behavioural INMP441 -> i2s_rx -> fft -> bars -> bar_renderer -> hdmi_tx
*/
module top_tb;

    localparam int BAR_PITCH = 40;  // Must match the BAR_WIDTH passed to bar_renderer
    localparam int Y_BOTTOM = 450;  // Must match the Y_BOTTOM passed to bar_renderer
    localparam int TONE_AMPLITUDE = 262144;  // 24-bit peak (2^18), loud but inside mic range

    reg clk = 1'b0;
    reg [1:0] btn = 2'b11;  // Buttons released
    wire [5:0] led;

    wire tmds_clk_p;
    wire tmds_clk_n;
    wire [2:0] tmds_data_p;
    wire [2:0] tmds_data_n;

    wire i2s_sck;
    wire i2s_ws;
    tri i2s_sd;

    // Instantiate Unit Under Test
    top uut (
        .clk        (clk),
        .btn        (btn),
        .tmds_clk_p (tmds_clk_p),
        .tmds_clk_n (tmds_clk_n),
        .tmds_data_p(tmds_data_p),
        .tmds_data_n(tmds_data_n),
        .led        (led),
        .i2s_sck    (i2s_sck),
        .i2s_ws     (i2s_ws),
        .i2s_sd     (i2s_sd)
    );

    // 27 MHz reference clock (period = 37.037 ns, half-period = 18.5185 ns)
    always #18.5185 clk = ~clk;

    // -------------------------------------------------------------------------
    // Behavioural INMP441 with L/R tied low (left channel only)
    // -------------------------------------------------------------------------
    // Plays a cosine at FFT bin `tone_bin`. SD is driven on falling SCK, starts one
    // SCK after WS falls, and tri-states outside the 24 data bits as the real mic does.
    int tone_bin = 8;
    int mic_sample_index = 0;
    int mic_bit_idx = -1;
    reg mic_prev_ws = 1'b1;
    reg mic_drive = 1'b0;
    reg mic_sd = 1'b0;
    reg [23:0] mic_word = 24'd0;
    real mic_angle;

    assign i2s_sd = mic_drive ? mic_sd : 1'bz;

    always @(negedge i2s_sck) begin
        mic_prev_ws <= i2s_ws;

        if (mic_prev_ws === 1'b1 && i2s_ws === 1'b0) begin
            mic_angle = 2.0 * 3.141592653589793 * tone_bin * mic_sample_index / 64.0;
            mic_word = $rtoi($cos(mic_angle) * TONE_AMPLITUDE);
            mic_sample_index <= mic_sample_index + 1;
            mic_bit_idx <= 23;
            mic_drive <= 1'b0;
        end else if (mic_bit_idx >= 0) begin
            mic_drive <= 1'b1;
            mic_sd <= mic_word[mic_bit_idx];
            mic_bit_idx <= mic_bit_idx - 1;
        end else begin
            mic_drive <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    realtime t_start, t_period, t_high, t_low;
    real freq_pixel_mhz, freq_serial_mhz, sample_rate_khz;
    int de_active_pixels;
    int hsync_pulse_pixels;
    int line_total_pixels;
    int sck_per_frame;
    int test_errors = 0;

    task automatic check(input bit condition, input string description);
        if (condition) begin
            $display("  -> PASS: %s", description);
        end else begin
            $display("  -> FAIL: %s", description);
            test_errors++;
        end
    endtask

    // Wait for a full FFT frame, so `bars` holds only data from the current tone
    task automatic wait_fft_frames(input int frames);
        repeat (frames) begin
            @(posedge uut.mag_valid);
            wait (uut.bin_idx == 5'd31);
            @(posedge uut.clk_pixel);
        end
    endtask

    task automatic check_peak_bar(input int expected_bin);
        int peak_bin = 0;
        int peak_level = -1;
        int next_level = -1;

        for (int i = 0; i < 32; i++) begin
            if (int'(uut.bars[i]) > peak_level) begin
                next_level = peak_level;
                peak_level = int'(uut.bars[i]);
                peak_bin = i;
            end else if (int'(uut.bars[i]) > next_level) begin
                next_level = int'(uut.bars[i]);
            end
        end

        $display("  -> Peak bar %0d (level=%0d, next highest=%0d, target bar %0d)", peak_bin,
                 peak_level, next_level, expected_bin);
        check(peak_bin == expected_bin, "Tone lands in the expected bar");
        check(peak_level > 4 * next_level, "Tone stands well above the other bars");
    endtask

    // Sample the pixel colour at the centre of bar `bar` on line `y`.
    // bar_renderer has two cycles of latency, so look two clocks after the coordinate.
    task automatic sample_bar_pixel(input int bar, input int y, output logic [23:0] rgb);
        int x = bar * BAR_PITCH + BAR_PITCH / 4;

        wait (uut.pixel_y == 12'(y - 1));
        wait (uut.pixel_y == 12'(y) && uut.pixel_x == 12'(x) && uut.data_enable);
        repeat (2) @(posedge uut.clk_pixel);
        #1;
        rgb = uut.bar_rgb_data;
    endtask

    // A hung PLL, I2S or FFT must fail rather than simulate forever
    initial begin
        #60ms;
        $display("  -> FAIL: Watchdog expired before all tests completed");
        $display(" [TESTBENCH RESULT] TEST FAILED");
        $finish(1);
    end

    logic [23:0] rgb_tone, rgb_quiet;

    initial begin

        // TEST 1: PLL Lock and LED Status
        $display("\n[TEST 1] Checking PLL lock and status LED...");
        wait (uut.sys_rst_n == 1'b1);
        $display("  -> PLL locked at %0t ps", $time);
        #1;
        check(led[0] === 1'b0, "LED0 is lit (0) once the PLL has locked");

        // TEST 2: Clock Frequencies (Pixel: 74.25 MHz, Serial: 371.25 MHz)
        $display("\n[TEST 2] Measuring Clock Frequencies...");

        @(posedge uut.clk_pixel);
        t_start = $realtime;
        @(posedge uut.clk_pixel);
        t_period = $realtime - t_start;
        freq_pixel_mhz = 1000.0 / t_period;
        $display("  -> Pixel Clock Period:  %0.3f ns (Freq: %0.2f MHz, Target: 74.25 MHz)",
                 t_period, freq_pixel_mhz);
        check(freq_pixel_mhz >= 73.0 && freq_pixel_mhz <= 75.5, "Pixel clock within tolerance");

        @(posedge uut.clk_serial);
        t_start = $realtime;
        @(posedge uut.clk_serial);
        t_period = $realtime - t_start;
        freq_serial_mhz = 1000.0 / t_period;
        $display("  -> Serial Clock Period: %0.3f ns (Freq: %0.2f MHz, Target: 371.25 MHz)",
                 t_period, freq_serial_mhz);
        check(freq_serial_mhz >= 365.0 && freq_serial_mhz <= 375.0, "Serial clock within tolerance");

        // TEST 3: Video Timings (720p60: 1280x720, H_TOTAL=1650, HSYNC=40)
        $display("\n[TEST 3] Verifying 720p Video Timings & Blanking intervals...");

        @(posedge uut.data_enable);
        #1;
        de_active_pixels = 0;
        while (uut.data_enable == 1'b1) begin
            de_active_pixels++;
            @(posedge uut.clk_pixel);
            #1;
        end
        $display("  -> Measured Active Line Width: %0d pixels (Target: 1280)", de_active_pixels);
        check(de_active_pixels == 1280, "Active video width is 1280 pixels");

        @(posedge uut.hsync);
        #1;
        hsync_pulse_pixels = 0;
        while (uut.hsync == 1'b1) begin
            hsync_pulse_pixels++;
            @(posedge uut.clk_pixel);
            #1;
        end
        $display("  -> Measured HSYNC Pulse Width: %0d pixels (Target: 40)", hsync_pulse_pixels);
        check(hsync_pulse_pixels == 40, "HSYNC pulse width matches CTA-861");

        @(posedge uut.data_enable);
        #1;
        line_total_pixels = 0;
        while (uut.data_enable == 1'b1) begin
            line_total_pixels++;
            @(posedge uut.clk_pixel);
            #1;
        end
        while (uut.data_enable == 1'b0) begin
            line_total_pixels++;
            @(posedge uut.clk_pixel);
            #1;
        end
        $display("  -> Measured Total Horizontal Line: %0d pixels (Target: 1650)",
                 line_total_pixels);
        check(line_total_pixels == 1650, "Total horizontal line is 1650 pixels");

        // TEST 4: TMDS Encoding & Control Tokens
        $display("\n[TEST 4] Verifying TMDS Encoder outputs...");

        // During blanking the Blue channel transmits control tokens:
        // When hsync=0, vsync=0 -> ctrl=2'b00 -> TMDS out should be 10'b1101010100
        wait (uut.data_enable_f[1] == 1'b0 && uut.hsync_f[1] == 1'b0 && uut.vsync_f[1] == 1'b0);
        repeat (2) @(posedge uut.clk_pixel);
        #1;
        $display("  -> Blanking TMDS Token (hsync=0, vsync=0): 10'b%b (Expected: 10'b1101010100)",
                 uut.u_hdmi_tx.encoded_b);
        check(uut.u_hdmi_tx.encoded_b === 10'b1101010100, "TMDS control token 00 matches DVI spec");

        // TEST 5: I2S clocks must meet the INMP441 datasheet limits
        $display("\n[TEST 5] Verifying I2S clocks against the INMP441 datasheet...");

        @(posedge i2s_sck);
        t_start = $realtime;
        @(negedge i2s_sck);
        t_high = $realtime - t_start;
        t_start = $realtime;
        @(posedge i2s_sck);
        t_low = $realtime - t_start;
        t_period = t_high + t_low;
        $display("  -> SCK period %0.1f ns (%0.3f MHz), high %0.1f ns, low %0.1f ns", t_period,
                 1000.0 / t_period, t_high, t_low);
        check(t_period >= 312.0 && t_period <= 2000.0, "SCK inside 0.5-3.2 MHz");
        check(t_high >= 50.0 && t_low >= 50.0, "SCK high and low times at least 50 ns");

        @(negedge i2s_ws);
        t_start = $realtime;
        sck_per_frame = 0;
        fork : count_sck
            forever begin
                @(posedge i2s_sck);
                sck_per_frame++;
            end
            @(negedge i2s_ws);
        join_any
        disable count_sck;
        t_period = $realtime - t_start;
        sample_rate_khz = 1000000.0 / t_period;
        $display("  -> %0d SCK per WS frame, sample rate %0.2f kHz", sck_per_frame,
                 sample_rate_khz);
        check(sck_per_frame == 64, "64 SCK cycles per stereo frame");
        check(sample_rate_khz >= 7.8 && sample_rate_khz <= 52.1, "Sample rate inside mic range");

        // TEST 6: Tone from the mic must reach the correct bar
        $display("\n[TEST 6] Mic tone -> FFT -> bars...");

        tone_bin = 8;
        wait_fft_frames(3);
        check_peak_bar(8);

        // TEST 7: The tone's bar must appear on screen and a quiet bar must not
        $display("\n[TEST 7] Bars -> rendered pixels...");

        sample_bar_pixel(8, Y_BOTTOM - 100, rgb_tone);
        sample_bar_pixel(20, Y_BOTTOM - 100, rgb_quiet);
        $display("  -> Bar 8 pixel=%06h, Bar 20 pixel=%06h", rgb_tone, rgb_quiet);
        check(rgb_tone !== 24'h000000 && !$isunknown(rgb_tone), "Bar 8 is drawn on screen");
        check(rgb_quiet === 24'h000000, "Quiet bar 20 stays black");

        // TEST 8: Bars must follow the audio, not hold stale values
        $display("\n[TEST 8] Changing tone moves the bar...");

        tone_bin = 20;
        wait_fft_frames(3);
        check_peak_bar(20);

        // Final Summary
        $display("\n==================================================================");
        if (test_errors == 0) begin
            $display(" [TESTBENCH RESULT] ALL CHECKS PASSED SUCCESSFULLY!");
        end else begin
            $display(" [TESTBENCH RESULT] %0d CHECKS FAILED!", test_errors);
            $display(" [TESTBENCH RESULT] TEST FAILED");
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule

`default_nettype wire

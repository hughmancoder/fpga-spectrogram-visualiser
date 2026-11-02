`timescale 1ns / 1ps

module top_tb;

    reg clk = 0;
    reg [1:0] btn = 2'b00; // Buttons idle (pulled down on Tang Nano 20K)
    wire [5:0] led;

    wire       tmds_clk_p;
    wire       tmds_clk_n;
    wire [2:0] tmds_data_p;
    wire [2:0] tmds_data_n;

    // Instantiate Unit Under Test
    top uut (
        .clk        (clk),
        .btn        (btn),
        .tmds_clk_p (tmds_clk_p),
        .tmds_clk_n (tmds_clk_n),
        .tmds_data_p(tmds_data_p),
        .tmds_data_n(tmds_data_n),
        .led        (led)
    );

    // 27 MHz reference clock (period = 37.037 ns, half-period = 18.5185 ns)
    always #18.5185 clk = ~clk;

    realtime t_start, t_period;
    real freq_pixel_mhz, freq_serial_mhz;
    int de_active_pixels;
    int hsync_pulse_pixels;
    int line_total_pixels;
    int test_errors = 0;

    initial begin


        // TEST 1: PLL Lock and LED Status
        $display("\n[TEST 1] Checking PLL lock and status LEDs...");
        wait(uut.pll_locked == 1'b1);
        $display("  -> PLL locked at %0t ps", $time);

        #1;
        // Verify outer LEDs (led[0] and led[5]) are lit (active-low: 0 = lit)
        if (led[0] === 1'b0 && led[5] === 1'b0) begin
            $display("  -> PASS: Lock LEDs (LED0 & LED5) are ON (0).");
        end else begin
            $display("  -> FAIL: Lock LEDs not asserting ON (led[0]=%b, led[5]=%b)", led[0], led[5]);
            test_errors++;
        end

        // TEST 2: Clock Frequencies (Pixel: 74.25 MHz, Serial: 371.25 MHz)
        $display("\n[TEST 2] Measuring Clock Frequencies...");

        // Measure Pixel Clock
        @(posedge uut.clk_pixel);
        t_start = $realtime;
        @(posedge uut.clk_pixel);
        t_period = $realtime - t_start;
        freq_pixel_mhz = 1000.0 / t_period;
        $display("  -> Pixel Clock Period:  %0.3f ns (Freq: %0.2f MHz, Target: 74.25 MHz)", t_period, freq_pixel_mhz);

        if (freq_pixel_mhz >= 73.0 && freq_pixel_mhz <= 75.5) begin
            $display("  -> PASS: Pixel clock frequency within 720p specification!");
        end else begin
            $display("  -> FAIL: Pixel clock frequency out of tolerance!");
            test_errors++;
        end

        // Measure Serial Clock
        @(posedge uut.clk_serial);
        t_start = $realtime;
        @(posedge uut.clk_serial);
        t_period = $realtime - t_start;
        freq_serial_mhz = 1000.0 / t_period;
        $display("  -> Serial Clock Period: %0.3f ns (Freq: %0.2f MHz, Target: 371.25 MHz)", t_period, freq_serial_mhz);

        if (freq_serial_mhz >= 365.0 && freq_serial_mhz <= 375.0) begin
            $display("  -> PASS: Serial 5x TMDS clock within specification!");
        end else begin
            $display("  -> FAIL: Serial clock frequency out of tolerance!");
            test_errors++;
        end

        // TEST 3: Video Timings (720p60: 1280x720, H_TOTAL=1650, HSYNC=40)
        $display("\n[TEST 3] Verifying 720p Video Timings & Blanking intervals...");

        // Wait for start of an active display line (posedge DE)
        @(posedge uut.de);
        #1;
        de_active_pixels = 0;
        while (uut.de == 1'b1) begin
            de_active_pixels++;
            @(posedge uut.clk_pixel);
            #1;
        end
        $display("  -> Measured Active Line Width: %0d pixels (Target: 1280)", de_active_pixels);
        if (de_active_pixels == 1280) begin
            $display("  -> PASS: Active video width exactly 1280 pixels!");
        end else begin
            $display("  -> FAIL: Expected 1280 active pixels, got %0d", de_active_pixels);
            test_errors++;
        end

        // Wait for HSYNC pulse
        @(posedge uut.hsync);
        #1;
        hsync_pulse_pixels = 0;
        while (uut.hsync == 1'b1) begin
            hsync_pulse_pixels++;
            @(posedge uut.clk_pixel);
            #1;
        end
        $display("  -> Measured HSYNC Pulse Width: %0d pixels (Target: 40)", hsync_pulse_pixels);
        if (hsync_pulse_pixels == 40) begin
            $display("  -> PASS: HSYNC pulse width matches CTA-861 standard!");
        end else begin
            $display("  -> FAIL: Expected 40 HSYNC pixels, got %0d", hsync_pulse_pixels);
            test_errors++;
        end

        // Measure Total Horizontal Line period (DE to next DE)
        @(posedge uut.de);
        #1;
        line_total_pixels = 0;
        while (uut.de == 1'b1) begin
            line_total_pixels++;
            @(posedge uut.clk_pixel);
            #1;
        end
        while (uut.de == 1'b0) begin
            line_total_pixels++;
            @(posedge uut.clk_pixel);
            #1;
        end
        $display("  -> Measured Total Horizontal Line: %0d pixels (Target: 1650)", line_total_pixels);
        if (line_total_pixels == 1650) begin
            $display("  -> PASS: Total horizontal line duration is exactly 1650 pixels (720p60)!");
        end else begin
            $display("  -> FAIL: Expected 1650 total pixels, got %0d", line_total_pixels);
            test_errors++;
        end

        // TEST 4: TMDS Encoding & Control Tokens
        $display("\n[TEST 4] Verifying TMDS Encoder outputs...");

        // During blanking (vid_de == 0), Blue channel transmits control tokens:
        // When hsync=0, vsync=0 -> ctrl=2'b00 -> TMDS out should be 10'b1101010100
        wait(uut.vid_de == 1'b0 && uut.vid_hsync == 1'b0 && uut.vid_vsync == 1'b0);
        repeat (2) @(posedge uut.clk_pixel);
        #1;
        $display("  -> Blanking TMDS Token (hsync=0, vsync=0): 10'b%b (Expected: 10'b1101010100)", uut.u_hdmi.encoded_b);
        if (uut.u_hdmi.encoded_b === 10'b1101010100) begin
            $display("  -> PASS: TMDS control token 00 matches DVI specification!");
        end else begin
            $display("  -> FAIL: Incorrect TMDS control token!");
            test_errors++;
        end

        // Test active video color output:
        // First test: Diagnostic mode (btn[1] == 0)
        btn = 2'b00;
        wait(uut.vid_de == 1'b1);
        repeat (10) @(posedge uut.clk_pixel);
        #1;
        $display("  -> Diagnostic Pattern Sample at (x=%0d, y=%0d): RGB=(%0h, %0h, %0h)", 
                 uut.pixel_x, uut.pixel_y, uut.red, uut.green, uut.blue);
        if (uut.red !== 8'h00 || uut.green !== 8'h00 || uut.blue !== 8'h00) begin
            $display("  -> PASS: Diagnostic test pattern actively produces pixel colors!");
        end else begin
            $display("  -> FAIL: Diagnostic test pattern output is unexpectedly blank!");
            test_errors++;
        end

        // Second test: Real-time animated equalizer visualizer mode (btn[1] == 1, default on hardware)
        btn = 2'b11; // Buttons released (idle state with pull-up)
        // Wait for an active line within the bar display region (e.g. pixel_y = 445, baseline is 450)
        wait(uut.pixel_y == 12'd445 && uut.vid_de == 1'b1);
        repeat (5) @(posedge uut.clk_pixel); // Position inside Bar 0
        #1;
        $display("  -> Equalizer Visualizer Sample at (x=%0d, y=%0d): RGB=(%0h, %0h, %0h)", 
                 uut.pixel_x, uut.pixel_y, uut.red, uut.green, uut.blue);
        if (uut.red !== 8'h00 || uut.green !== 8'h00 || uut.blue !== 8'h00) begin
            $display("  -> PASS: Real-time audio equalizer bars are actively rendered!");
        end else begin
            $display("  -> FAIL: Equalizer visualizer output is unexpectedly blank!");
            test_errors++;
        end

        // Final Summary
        $display("\n==================================================================");
        if (test_errors == 0) begin
            $display(" [TESTBENCH RESULT] ALL CHECKS PASSED SUCCESSFULLY!");
        end else begin
            $display(" [TESTBENCH RESULT] %0d CHECKS FAILED!", test_errors);
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule

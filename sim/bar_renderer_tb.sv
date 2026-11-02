`timescale 1ns / 1ps
`default_nettype none

module bar_renderer_tb;

    localparam int NUM_BARS    = 64;
    localparam int BAR_WIDTH   = 20;
    localparam int GAP_WIDTH   = 4;
    localparam int SOLID_WIDTH = BAR_WIDTH - GAP_WIDTH; // 16
    localparam int Y_BOTTOM    = 450;
    localparam int MAX_HEIGHT  = 256;
    localparam int CAP_HEIGHT  = 3;

    localparam logic [23:0] RED         = 24'hFF0000;
    localparam logic [23:0] LIGHT_GREEN = 24'h00FF00;
    localparam logic [23:0] DARK_GREEN  = 24'h005500;
    localparam logic [23:0] WHITE       = 24'hFFFFFF;
    localparam logic [23:0] BLACK       = 24'h000000;

    reg clk = 0;
    reg rst_n = 0;
    reg [11:0] pixel_x = 0;
    reg [11:0] pixel_y = 0;
    reg active_video = 0;
    reg frame_tick = 0;

    reg [7:0] bar_ram [0:NUM_BARS-1];
    wire [5:0] bar_addr;
    reg [7:0] bar_level = 0;
    wire [23:0] rgb_out;

    wire [7:0] anim_level;
    reg use_animator = 0;

    spectrum_pattern_gen #(
        .NUM_BARS       (NUM_BARS),
        .BAR_HEIGHT_MAX (255),
        .DATA_WIDTH     (8)
    ) u_anim (
        .clk        (clk),
        .rst_n      (rst_n),
        .tick       (frame_tick),
        .bar_idx    (bar_addr),
        .bar_level  (anim_level),
        .write_addr (),
        .write_data (),
        .write_en   ()
    );

    // 74.25 MHz clock (~13.468 ns period)
    always #6.734 clk = ~clk;

    bar_renderer #(
        .NUM_BARS   (NUM_BARS),
        .BAR_WIDTH  (BAR_WIDTH),
        .GAP_WIDTH  (GAP_WIDTH),
        .Y_BOTTOM   (Y_BOTTOM),
        .MAX_HEIGHT (MAX_HEIGHT)
    ) uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .bar_level    (bar_level),
        .bar_addr     (bar_addr),
        .rgb_out      (rgb_out)
    );

    // Synchronous memory read modeling 1-cycle BRAM latency
    always @(posedge clk) begin
        if (use_animator)
            bar_level <= anim_level;
        else
            bar_level <= bar_ram[bar_addr];
    end

    int errors = 0;
    int t5_lit_pixels = 0;
    int t5_gap_pixels = 0;
    int t5_sample_x = 0;
    int t5_sub_x = 0;

    task check_color(input string desc, input logic [23:0] actual, input logic [23:0] expected);
        if (actual !== expected) begin
            $display("[FAIL] %s: Expected %06h, got %06h at time %0t", desc, expected, actual, $time);
            errors++;
        end else begin
            $display("[PASS] %s: Got %06h", desc, actual);
        end
    endtask

    // Helper task to sample output of bar 0 (pixel 0) at a given Y coordinate
    task sample_bar0_pixel0(input int y_coord, output logic [23:0] result);
        @(posedge clk);
        active_video <= 1'b0;
        pixel_x      <= 12'd0;
        pixel_y      <= y_coord[11:0];
        @(posedge clk);
        active_video <= 1'b1;
        pixel_x      <= 12'd0;
        @(posedge clk);
        pixel_x      <= 12'd1;
        @(posedge clk);
        pixel_x      <= 12'd2;
        @(posedge clk);
        #1;
        result = rgb_out;
        active_video <= 1'b0;
        @(posedge clk);
    endtask

    initial begin
        $dumpfile("build/bar_renderer_tb.vcd");
        $dumpvars(0, bar_renderer_tb);

        for (int i = 0; i < NUM_BARS; i++) begin
            bar_ram[i] = 8'd0;
        end

        // TEST 1: Reset behavior
        $display("\n[TEST 1] Checking Reset State...");
        #20;
        if (rgb_out !== BLACK) begin
            $display("[FAIL] rgb_out not BLACK during reset: %06h", rgb_out);
            errors++;
        end else begin
            $display("[PASS] rgb_out is BLACK during reset");
        end

        @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // TEST 2: Horizontal Bar and Gap Geometry
        $display("\n[TEST 2] Verifying Horizontal Bar Width (16px) & Gap (4px)...");
        for (int i = 0; i < NUM_BARS; i++) begin
            bar_ram[i] = 8'd100; // All bars height 100
        end

        // Hold inactive video before starting raster line
        active_video <= 1'b0;
        pixel_y      <= 12'd400; // dist_from_bottom = 450 - 400 = 50 <= 100 (in lit region)
        pixel_x      <= 12'd0;
        repeat (2) @(posedge clk);

        // Scan full line of 1280 pixels
        for (int x = 0; x < 1280; x++) begin
            active_video <= 1'b1;
            pixel_x      <= x[11:0];
            @(posedge clk);
            #1;
            if (x >= 1) begin
                int sample_x;
                int sub_x;
                int bar_k;
                sample_x = x - 1;
                sub_x = sample_x % BAR_WIDTH;
                bar_k = sample_x / BAR_WIDTH;
                if (sub_x < SOLID_WIDTH) begin
                    if (rgb_out === BLACK) begin
                        $display("[FAIL] Expected solid bar at x=%0d (sub_x=%0d, bar=%0d), got BLACK",
                                 sample_x, sub_x, bar_k);
                        errors++;
                    end
                end else begin
                    if (rgb_out !== BLACK) begin
                        $display("[FAIL] Expected gap (BLACK) at x=%0d (sub_x=%0d, bar=%0d), got %06h",
                                 sample_x, sub_x, bar_k, rgb_out);
                        errors++;
                    end
                end
            end
        end

        // Sample last pixel (1279)
        active_video <= 1'b0;
        @(posedge clk);
        #1;
        begin
            int sample_x;
            int sub_x;
            sample_x = 1279;
            sub_x = sample_x % BAR_WIDTH;
            if (sub_x < SOLID_WIDTH) begin
                if (rgb_out === BLACK) errors++;
            end else begin
                if (rgb_out !== BLACK) errors++;
            end
        end

        repeat (2) @(posedge clk);

        if (errors == 0)
            $display("[PASS] All 64 bars verified: 16px lit solid + 4px black gap!");

        // TEST 3: Vertical Color Gradients (Green / Yellow / Red)
        $display("\n[TEST 3] Verifying Vertical Color Gradients...");
        // THRESH_YELLOW = 256 / 3 = 85
        // THRESH_RED    = 256 * 2 / 3 = 170
        bar_ram[0] = 8'd220; // Bar 0 height = 220 pixels

        // Sub-test 3A: Baseline (dist=0) -> DARK_GREEN
        begin
            logic [23:0] res;
            sample_bar0_pixel0(450, res); // dist = 0
            check_color("dist=0 (Baseline)", res, DARK_GREEN);
        end

        // Sub-test 3B: Lower amplitude (dist=50 < 85) -> DARK_GREEN
        begin
            logic [23:0] res;
            sample_bar0_pixel0(400, res); // dist = 50
            check_color("dist=50 (Lower zone)", res, DARK_GREEN);
        end

        // Sub-test 3C: Mid amplitude (dist=120: 85 <= dist < 170) -> LIGHT_GREEN
        begin
            logic [23:0] res;
            sample_bar0_pixel0(330, res); // dist = 120
            check_color("dist=120 (Mid zone)", res, LIGHT_GREEN);
        end

        // Sub-test 3D: High amplitude (dist=190: >= 170) -> RED
        begin
            logic [23:0] res;
            sample_bar0_pixel0(260, res); // dist = 190
            check_color("dist=190 (High zone)", res, RED);
        end

        // Sub-test 3E: Above bar height (dist=230 > 220 + CAP_HEIGHT 3) -> BLACK
        begin
            logic [23:0] res;
            sample_bar0_pixel0(220, res); // dist = 230
            check_color("dist=230 (Above bar)", res, BLACK);
        end

        // Sub-test 3F: Below floor (pixel_y = 500 > Y_BOTTOM 450) -> BLACK
        begin
            logic [23:0] res;
            sample_bar0_pixel0(500, res); // dist = 0, above_floor = 0
            check_color("pixel_y=500 (Below floor)", res, BLACK);
        end

        // TEST 4: Integrated Test with spectrum_pattern_gen Driving bar_renderer
        $display("\n[TEST 4] Testing spectrum_pattern_gen Driving bar_renderer...");
        use_animator = 1;
        active_video <= 1'b0;

        // Run 5 animation frames
        for (int frame = 0; frame < 5; frame++) begin
            @(posedge clk);
            frame_tick <= 1'b1;
            @(posedge clk);
            frame_tick <= 1'b0;
            repeat (75) @(posedge clk); // Allow spectrum_pattern_gen to write all 64 bars
        end

        // Verify that animated bars produce non-zero colors on display
        pixel_y <= 12'd445; // dist_from_bottom = 5 (below min_floor = 8 for all bars)
        active_video <= 1'b0;
        repeat (2) @(posedge clk);

        t5_lit_pixels = 0;
        t5_gap_pixels = 0;
        for (int x = 0; x < 1280; x++) begin
            active_video <= 1'b1;
            pixel_x      <= x[11:0];
            @(posedge clk);
            #1;
            if (x >= 1) begin
                t5_sample_x = x - 1;
                t5_sub_x = t5_sample_x % BAR_WIDTH;
                if (t5_sub_x < SOLID_WIDTH) begin
                    if (rgb_out !== BLACK) t5_lit_pixels++;
                end else begin
                    if (rgb_out === BLACK) t5_gap_pixels++;
                end
            end
        end
        active_video <= 1'b0;
        @(posedge clk);
        #1;
        t5_sample_x = 1279;
        t5_sub_x = t5_sample_x % BAR_WIDTH;
        if (t5_sub_x < SOLID_WIDTH) begin
            if (rgb_out !== BLACK) t5_lit_pixels++;
        end else begin
            if (rgb_out === BLACK) t5_gap_pixels++;
        end

        if (t5_lit_pixels == 64 * SOLID_WIDTH && t5_gap_pixels == 64 * GAP_WIDTH) begin
            $display("[PASS] Integrated test: all %0d solid bar pixels lit, all %0d gap pixels dark!",
                     t5_lit_pixels, t5_gap_pixels);
        end else begin
            $display("[FAIL] Integrated test pixel counts mismatch: lit=%0d (expected %0d), gap=%0d (expected %0d)",
                     t5_lit_pixels, 64 * SOLID_WIDTH, t5_gap_pixels, 64 * GAP_WIDTH);
            errors++;
        end

        // Final Summary
        $display("\n=============================================================");
        if (errors == 0) begin
            $display(" [bar_renderer_tb] ALL CHECKS PASSED SUCCESSFULLY!");
        end else begin
            $display(" [bar_renderer_tb] %0d ERRORS DETECTED!", errors);
            $finish(1);
        end
        $display("=============================================================\n");

        $finish;
    end

endmodule

`default_nettype wire

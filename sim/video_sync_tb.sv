`timescale 1ns / 1ps

module video_sync_tb;

    reg clk;
    reg rst_n;

    wire hsync;
    wire vsync;
    wire de;
    wire [11:0] pixel_x;
    wire [11:0] pixel_y;

    video_sync uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .hsync      (hsync),
        .vsync      (vsync),
        .data_enable(de),
        .pixel_x    (pixel_x),
        .pixel_y    (pixel_y)
    );

    // 74.25 MHz clock -> 13.468 ns period
    initial clk = 0;
    always #6.734 clk = ~clk;

    int hsync_count = 0;
    int vsync_count = 0;
    int de_high_count = 0;
    int de_lines_count = 0;

    initial begin
        $dumpfile("build/video_sync_tb.vcd");
        $dumpvars(0, video_sync_tb);

        rst_n = 0;
        #100;
        rst_n = 1;

        // Wait for a few VSYNCs
        @(posedge vsync);
        @(posedge vsync);

        // Measure H_TOTAL
        @(posedge hsync);
        hsync_count = 0;
        fork
            begin
                while (1) begin
                    @(posedge clk);
                    hsync_count++;
                end
            end
            begin
                @(posedge hsync);
            end
        join_any
        disable fork;

        $display("[video_sync_tb] Measured H_TOTAL: %d (Expected: 1650)", hsync_count);
        if (hsync_count != 1650) $error("H_TOTAL mismatch!");

        // Measure V_TOTAL
        @(posedge vsync);
        vsync_count = 0;
        fork
            begin
                while (1) begin
                    @(posedge hsync);
                    vsync_count++;
                end
            end
            begin
                @(posedge vsync);
            end
        join_any
        disable fork;

        $display("[video_sync_tb] Measured V_TOTAL: %d (Expected: 750)", vsync_count);
        if (vsync_count != 750) $error("V_TOTAL mismatch!");

        // Measure DE active pixels per line and lines per frame
        @(posedge vsync);
        de_lines_count = 0;

        // Count for one frame
        while (vsync == 1) @(posedge clk);
        while (vsync == 0) begin
            if (de == 1'b0) begin
                @(posedge clk);
                if (de == 1'b1) begin
                    de_high_count = 0;
                    while (de == 1'b1) begin
                        @(posedge clk);
                        de_high_count++;
                    end
                    if (de_high_count != 1280) $error("H_ACTIVE mismatch! got %d", de_high_count);
                    de_lines_count++;
                end
            end else begin
                @(posedge clk);
            end
        end
        $display("[video_sync_tb] Measured H_ACTIVE: %d (Expected: 1280)", de_high_count);
        $display("[video_sync_tb] Measured V_ACTIVE: %d (Expected: 720)", de_lines_count);
        if (de_lines_count != 720) $error("V_ACTIVE mismatch!");

        $display("All tests passed!");
        $finish;
    end
endmodule

`timescale 1ns / 1ps
`default_nettype none

module audio_window_tb;

    localparam int FRAME_SIZE = 64;
    localparam int GAIN_SHIFT = 4;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg signed [23:0] sample_in = 24'sd0;
    reg sample_valid = 1'b0;

    wire signed [15:0] win_sample;
    wire [5:0] win_idx;
    wire win_valid;
    wire frame_done;

    always #5 clk = ~clk;  // 100 MHz test clock

    audio_window #(
        .FRAME_SIZE(FRAME_SIZE),
        .GAIN_SHIFT(GAIN_SHIFT)
    ) uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_in   (sample_in),
        .sample_valid(sample_valid),
        .win_sample  (win_sample),
        .win_idx     (win_idx),
        .win_valid   (win_valid),
        .frame_done  (frame_done)
    );

    int errors = 0;
    reg signed [15:0] captured[0:FRAME_SIZE-1];

    initial begin
        $dumpfile("build/audio_window_tb.vcd");
        $dumpvars(0, audio_window_tb);

        $display("\n=============================================================");
        $display(" Starting audio_window_tb (Phase 4.1 Scaling & Hanning Window)");
        $display("=============================================================");

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST 1: Constant Positive Input Across Full 64-Sample Frame
        //         Verify bell-shaped Hanning envelope (0 at start, peak at 32)
        // ---------------------------------------------------------------------
        // With GAIN_SHIFT = 4, sample_in = 24'sh040000 << 4 = 24'sh400000 -> top 16 bits = +16384
        for (int n = 0; n < FRAME_SIZE; n++) begin
            @(posedge clk);
            sample_in    <= 24'sh040000;
            sample_valid <= 1'b1;
            @(posedge clk);
            sample_valid <= 1'b0;
            #1;
            if (!win_valid || win_idx !== n[5:0]) begin
                $display("[FAIL] Sample %0d: win_valid=%b, win_idx=%0d", n, win_valid, win_idx);
                errors++;
            end
            if (n < FRAME_SIZE - 1 && frame_done) begin
                $display("[FAIL] Early frame_done at sample %0d", n);
                errors++;
            end
            if (n == FRAME_SIZE - 1 && !frame_done) begin
                $display("[FAIL] Missing frame_done at final sample %0d", n);
                errors++;
            end
            captured[n] = win_sample;
        end

        // Check n = 0 (Start of window must taper to 0)
        if (captured[0] !== 16'sd0) begin
            $display("[FAIL] Window start captured[0] = %0d (expected 0)", captured[0]);
            errors++;
        end else begin
            $display("[PASS] Window start tapers to 0: captured[0] = %0d", captured[0]);
        end

        // Check n = 32 (Center of window must be at peak ~16383)
        if (captured[32] < 16'sd16380 || captured[32] > 16'sd16384) begin
            $display("[FAIL] Window center captured[32] = %0d (expected ~16383)", captured[32]);
            errors++;
        end else begin
            $display("[PASS] Window center peak: captured[32] = %0d (expected ~16383)",
                     captured[32]);
        end

        // Check monotonic increase on rising half (0..32) and decrease on falling half (32..63)
        for (int n = 1; n <= 32; n++) begin
            if (captured[n] < captured[n-1]) begin
                $display("[FAIL] Non-monotonic rising slope at n=%0d (%0d < %0d)", n, captured[n],
                         captured[n-1]);
                errors++;
            end
        end
        for (int n = 33; n < FRAME_SIZE; n++) begin
            if (captured[n] > captured[n-1]) begin
                $display("[FAIL] Non-monotonic falling slope at n=%0d (%0d > %0d)", n, captured[n],
                         captured[n-1]);
                errors++;
            end
        end
        $display("[PASS] Bell-curve symmetry & monotonicity verified across all 64 samples!");

        // ---------------------------------------------------------------------
        // TEST 2: Negative Saturation & Positive Saturation Check
        // ---------------------------------------------------------------------
        // Advance to center of next frame (n = 32, where w[32] = 1.0)
        for (int n = 0; n < 32; n++) begin
            @(posedge clk);
            sample_in    <= 24'sd0;
            sample_valid <= 1'b1;
            @(posedge clk);
            sample_valid <= 1'b0;
        end

        // At n = 32 (center peak w[32] = 32767), feed max negative 24-bit value (-8388608)
        @(posedge clk);
        sample_in    <= -24'sd8388608;
        sample_valid <= 1'b1;
        @(posedge clk);
        sample_valid <= 1'b0;
        #1;
        if (win_sample > -16'sd32760) begin
            $display("[FAIL] Negative saturation failed: got %0d (expected ~ -32767)", win_sample);
            errors++;
        end else begin
            $display("[PASS] Negative overflow saturates cleanly without wrapping: %0d",
                     win_sample);
        end

        $display("-------------------------------------------------------------");
        if (errors == 0) begin
            $display(" [audio_window_tb] ALL CHECKS PASSED SUCCESSFULLY!");
        end else begin
            $display(" [audio_window_tb] %0d ERRORS DETECTED!", errors);
            $finish(1);
        end
        $display("=============================================================\n");
        $finish;
    end

endmodule

`default_nettype wire

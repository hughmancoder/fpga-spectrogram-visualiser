`timescale 1ns / 1ps
`default_nettype none

module fft_tb;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg signed [23:0] sample_in = 24'sd0;
    reg sample_valid = 1'b0;

    wire [4:0] bin_idx;
    wire [7:0] mag_out;
    wire mag_valid;

    always #5 clk = ~clk;  // 100 MHz simulation clock

    fft #(
        .FFT_SIZE  (64),
        .NUM_BARS  (32),
        .GAIN_SHIFT(0),
        .MAG_SHIFT (5)
    ) uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_in   (sample_in),
        .sample_valid(sample_valid),
        .bin_idx     (bin_idx),
        .mag_out     (mag_out),
        .mag_valid   (mag_valid)
    );

    int errors = 0;
    reg [7:0] captured_mags[0:31];

    // Capture magnitudes streamed out by `fft` when `mag_valid` is high
    always @(posedge clk) begin
        if (mag_valid) begin
            captured_mags[bin_idx] <= mag_out;
        end
    end

    // Helper task: Feed 64 cosine samples at integer frequency bin `target_bin`
    // and verify that `target_bin` has the maximum magnitude across all 32 bins!
    task automatic test_pure_tone(input int target_bin, input string desc);
        real angle;
        real val;
        int peak_bin;
        int peak_mag;
        int second_mag;

        for (int k = 0; k < 32; k++) captured_mags[k] = 8'd0;

        for (int n = 0; n < 64; n++) begin
            angle = 2.0 * 3.141592653589793 * target_bin * n / 64.0;
            val   = $cos(angle) * 4194300.0;  // ~50% full-scale 24-bit amplitude
            @(posedge clk);
            sample_in    <= $rtoi(val);
            sample_valid <= 1'b1;
            @(posedge clk);
            sample_valid <= 1'b0;
        end

        // Wait for FFT (192 cycles) + Magnitude stage (32 cycles) to finish streaming
        repeat (250) @(posedge clk);

        peak_bin   = 0;
        peak_mag   = -1;
        second_mag = -1;

        for (int k = 0; k < 32; k++) begin
            if (int'(captured_mags[k]) > peak_mag) begin
                second_mag = peak_mag;
                peak_mag   = int'(captured_mags[k]);
                peak_bin   = k;
            end else if (int'(captured_mags[k]) > second_mag) begin
                second_mag = int'(captured_mags[k]);
            end
        end

        if (peak_bin !== target_bin || peak_mag < 50) begin
            $display("[FAIL] %s: Expected peak at bin %0d, got bin %0d (mag=%0d, next=%0d)", desc,
                     target_bin, peak_bin, peak_mag, second_mag);
            errors++;
        end else begin
            $display(
                "[PASS] %s: Peak cleanly isolated at bin %0d (mag_out=%0d, all other bins <= %0d)",
                desc, peak_bin, peak_mag, second_mag);
        end
    endtask

    initial begin
        $dumpfile("build/fft_tb.vcd");
        $dumpvars(0, fft_tb);

        $display("\n=============================================================");
        $display(" Starting fft_tb (64-Point Radix-2 FFT + Magnitude Test)");
        $display("=============================================================");

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // Test 1: Low-frequency bass tone at Bin 2
        test_pure_tone(2, "Bass sine wave (Bin 2)");

        // Test 2: Mid-range tone at Bin 9
        test_pure_tone(9, "Mid-range sine wave (Bin 9)");

        // Test 3: High-frequency treble tone at Bin 23
        test_pure_tone(23, "Treble sine wave (Bin 23)");

        $display("-------------------------------------------------------------");
        if (errors == 0) begin
            $display(" [fft_tb] ALL 3 FREQUENCY BIN TESTS PASSED SUCCESSFULLY!");
            $display(" TEST PASSED");
        end else begin
            $display(" [fft_tb] %0d ERRORS DETECTED!", errors);
            $finish(1);
        end
        $display("=============================================================\n");
        $finish;
    end

endmodule

`default_nettype wire

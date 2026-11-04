`timescale 1ns / 1ps
`default_nettype none

module i2s_rx_tb;

    localparam int CLK_DIV = 8;  // 27 MHz / 8 = 3.375 MHz SCK

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire i2s_sck;
    wire i2s_ws;
    reg i2s_sd = 1'b0;
    wire signed [23:0] sample_data;
    wire sample_valid;

    // 27 MHz system clock (~37.037 ns period)
    always #18.5185 clk = ~clk;

    i2s_rx #(
        .CLK_DIV(CLK_DIV)
    ) uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .i2s_sck     (i2s_sck),
        .i2s_ws      (i2s_ws),
        .i2s_sd      (i2s_sd),
        .sample_data (sample_data),
        .sample_valid(sample_valid)
    );

    // -------------------------------------------------------------------------
    // Behavioral INMP441 I2S Slave Model
    // -------------------------------------------------------------------------
    // Shifts out `tx_left_word[23:0]` on `i2s_sd` during Left channel (i2s_ws == 0)
    // with the standard 1-SCK-cycle Philips I2S delay after `i2s_ws` falls.
    reg [23:0] tx_left_word = 24'h000000;
    reg prev_ws = 1'b1;
    int slave_bit_idx = -1;

    always @(negedge i2s_sck or negedge rst_n) begin
        if (!rst_n) begin
            prev_ws       <= 1'b1;
            slave_bit_idx <= -1;
            i2s_sd        <= 1'b0;
        end else begin
            prev_ws <= i2s_ws;

            // Detect falling edge of WS (start of Left channel);
            // current falling SCK edge is the 1-cycle delay slot, so MSB
            // will be driven on the NEXT falling SCK edge!
            if (prev_ws == 1'b1 && i2s_ws == 1'b0) begin
                slave_bit_idx <= 23;
                i2s_sd        <= 1'b0;
            end else if (slave_bit_idx >= 0) begin
                i2s_sd        <= tx_left_word[slave_bit_idx];
                slave_bit_idx <= slave_bit_idx - 1;
            end else begin
                i2s_sd <= 1'b0;  // Padding / Right-channel tri-state
            end
        end
    end

    // -------------------------------------------------------------------------
    // Test Sequence
    // -------------------------------------------------------------------------
    int errors = 0;

    task automatic verify_sample(input signed [23:0] expected, input string label);
        tx_left_word = expected;
        // Wait for start of a fresh Left frame (falling edge of i2s_ws)
        @(negedge i2s_ws);
        // Wait for uut to assert sample_valid at the end of the 24-bit word
        @(posedge clk);
        while (!sample_valid) @(posedge clk);

        if (sample_data !== expected) begin
            $display("[FAIL] %s: Expected 24'h%06x (%0d), got 24'h%06x (%0d)", label, expected,
                     expected, sample_data, sample_data);
            errors++;
        end else begin
            $display("[PASS] %s: Captured 24'h%06x (%0d)", label, sample_data, sample_data);
        end
    endtask

    initial begin
        $dumpfile("build/i2s_rx_tb.vcd");
        $dumpvars(0, i2s_rx_tb);

        $display("\n=============================================================");
        $display(" Starting i2s_rx_tb (INMP441 I2S Receiver Verification)");
        $display("=============================================================");

        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        verify_sample(24'sh5A3C9F, "Positive 24-bit PCM sample");
        verify_sample(-24'sd456789, "Negative 24-bit 2's complement sample");
        verify_sample(24'sh7FFFFF, "Max positive full-scale (+8388607)");
        verify_sample(24'sh800000, "Min negative full-scale (-8388608)");
        verify_sample(24'shA5A5A5, "Alternating bit pattern (0xA5A5A5)");

        $display("-------------------------------------------------------------");
        if (errors == 0) begin
            $display(" [i2s_rx_tb] ALL 5 I2S AUDIO FRAME CHECKS PASSED!");
            $display(" TEST PASSED");
        end else begin
            $display(" [i2s_rx_tb] %0d ERRORS DETECTED!", errors);
            $finish(1);
        end
        $display("=============================================================\n");
        $finish;
    end

endmodule

`default_nettype wire


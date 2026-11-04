`timescale 1ns / 1ps
`default_nettype none

module spectrum_pattern_gen_tb;

    reg clk = 0;
    reg rst_n = 0;
    reg tick = 0;

    reg [5:0] bar_idx = 0;
    wire [7:0] bar_level;
    wire [5:0] write_addr;
    wire [7:0] write_data;
    wire write_en;

    spectrum_pattern_gen #(
        .NUM_BARS(64),
        .BAR_HEIGHT_MAX(255),
        .DATA_WIDTH(8)
    ) uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .tick      (tick),
        .bar_idx   (bar_idx),
        .bar_level (bar_level),
        .write_addr(write_addr),
        .write_data(write_data),
        .write_en  (write_en)
    );

    always #5 clk = ~clk;

    int write_count = 0;
    always @(posedge clk) begin
        if (write_en) begin
            write_count++;
            if (write_data < 8'd8 || write_data > 8'd255) begin
                $display("[FAIL] write_data out of bounds: %0d", write_data);
                $finish(1);
            end
        end
    end

    initial begin
        $dumpfile("build/spectrum_pattern_gen_tb.vcd");
        $dumpvars(0, spectrum_pattern_gen_tb);

        #20;
        rst_n = 1;
        #20;

        // Simulate 5 animation frames
        for (int frame = 0; frame < 5; frame++) begin
            @(posedge clk);
            tick <= 1;
            @(posedge clk);
            tick <= 0;

            repeat (70) @(posedge clk);
        end

        // Verify bar reads
        for (int i = 0; i < 64; i++) begin
            bar_idx = i[5:0];
            #1;
            if (bar_level < 8'd8 || bar_level > 8'd255) begin
                $display("[FAIL] bar_level out of bounds at bar %0d: %0d", i, bar_level);
                $finish(1);
            end
        end

        if (write_count == 5 * 64) begin
            $display("[spectrum_pattern_gen_tb] PASS: Total writes = %0d (expected %0d)",
                     write_count, 5 * 64);
            $display("ALL CHECKS PASSED");
        end else begin
            $display("[FAIL] Unexpected write count: %0d", write_count);
            $finish(1);
        end

        $finish;
    end

endmodule

`default_nettype wire

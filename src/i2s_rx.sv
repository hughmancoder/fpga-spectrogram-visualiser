/*
 I2S Master to drive an INMP441 digital microphone 
 FPGA clock: 27 MHz
 Target microphone sample rate: ~48 kHz
 Stereo I2S frame width: 64 SCK clock cycles (32 Left + 32 Right)
 Target SCK frequency: 48 kHz x 64 = 3,072 kHz = 3.072 MHz
 Full Clock Divider: 27 MHz / 3.072 MHz = 8.79 -> ~8 FPGA clocks per full SCK cycle
   (Actual SCK = 27 MHz / 8 = 3.375 MHz -> 52.73 kHz sample rate)

 Note on Half-Period Toggle (CLK_DIV / 2 = 4):
   1 full SCK period (8 FPGA clocks) consists of 4 clocks LOW + 4 clocks HIGH,
   so the counter toggles `i2s_sck <= ~i2s_sck` every (CLK_DIV / 2) = 4 cycles.


   Note: docs/inmp441-datasheet.pdf documents the I2S interface on page 11
   Frame count: 64 SCK cycles
   The output data word length is 24 bits per channel. 
   WS = 0 ? left : right
 */

module i2s_rx #(
    parameter int CLK_DIV = 8
) (
    input logic clk,
    input logic rst_n,

    // physical I2S microphone pins
    output logic i2s_sck,  // serial clock to drive microphone
    output logic i2s_ws,
    input logic i2s_sd,

    // captured 24-bit PCM audio  
    output logic signed [23:0] sample_data,
    output logic sample_valid
);

    // flip flop synchroniser built with two ff internal shift registers to prevent metatability 
    logic [1:0] sd_sync;
    always_ff @(posedge clk) begin
        if (!rst_n) sd_sync <= 2'b00;
        else begin
            sd_sync = {sd_sync[0], i2s_sd};
        end

    end

    // synchronise I2S clock divider
    localparam int POSITIVE_CYCLES_COUNT = (CLK_DIV >= 2) ? (CLK_DIV / 2) : 1;
    localparam int DIV_WIDTH = (POSITIVE_CYCLES_COUNT > 1) ? $clog2(POSITIVE_CYCLES_COUNT) : 1;
    logic [DIV_WIDTH-1:0] divide_count;

    wire sck_edge = divide_count == POSITIVE_CYCLES_COUNT - 1;
    wire sck_rise = ((i2s_sck == 1'b0) && sck_edge);
    wire sck_fall = ((i2s_sck == 1'b1) && sck_edge);



    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            divide_count <= '0;
            i2s_sck <= 1'b0;
        end else if (sck_edge) begin
            divide_count <= 0;
            i2s_sck <= ~i2s_sck;  // pulse the slower serial clock
        end else begin
            divide_count += 1'b1;
        end
    end

    // i2s frame counter, ws generation and 24-bit shift register
    logic [23:0] shift_reg;  // 24 bits per channel
    logic [5:0] frame_count;  // 64 bits of data per frame

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg    <= 24'd0;
            frame_count  <= 6'd0;

            i2s_ws       <= 1'b0;
            sample_data  <= 24'sd0;
            sample_valid <= '0;
        end else begin
            sample_valid <= 1'b0;

            if (sck_rise) begin
                if (frame_count >= 6'd1 && frame_count <= 6'd24) begin
                    shift_reg <= {shift_reg[22:0], sd_sync[1]};

                    if (frame_count == 6'd24) begin
                        sample_data  <= {shift_reg[22:0], sd_sync[1]};
                        sample_valid <= 1'b1;
                    end
                end
            end

            if (sck_fall) begin
                frame_count <= frame_count + 6'd1;
                if (frame_count == 6'd31) begin
                    i2s_ws <= 1'b1;  // right channel data
                end else if (frame_count == 6'd63) begin
                    i2s_ws <= 1'b0;  // loops back to left channel data
                end
            end

        end
    end

endmodule

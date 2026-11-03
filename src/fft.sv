module fft #(
    parameter int FFT_SIZE   = 64,               
    parameter int NUM_BARS   = FFT_SIZE / 2,     // 32 positive frequency bins 
    parameter int GAIN_SHIFT = 4,                // Microphone input gain shift 
    parameter int MAG_SHIFT  = 4,                // Post-FFT magnitude shift to 8-bit 
    parameter int DECAY_STEP = 4                 // Bar fall speed per FFT frame
)(
    input  wire                        clk,
    input  wire                        rst_n,

    // Upstream Audio Input 
    input  wire signed [23:0]          sample_in,
    input  wire                        sample_valid,
 
    // Direct Read Port for Display 
    input  wire [$clog2(NUM_BARS)-1:0] bar_idx,
    output wire [7:0]                  bar_level,

    // Diagnostic / Verification Outputs 
    output reg  [$clog2(NUM_BARS)-1:0] bin_idx,
    output reg  signed [15:0]          bin_re,
    output reg  signed [15:0]          bin_im,
    output reg  [7:0]                  bin_mag,
    output reg                         bin_valid,
    output reg                         fft_done
);

    localparam int LOG2_N   = $clog2(FFT_SIZE); // 6 stages for 64-point FFT
    localparam int HALF_N   = FFT_SIZE / 2;     // 32 butterflies per stage


    // bit reverse input collection 

    // The Cooley–Tukey Decimation-in-Time (DIT) FFT requires the 64 input samples to be stored at bit-reversed addresses so output frequendcy bins come out in normal order 
    logic signed [15:0] fft_buffer_re [0:FFT_SIZE-1];
    logic signed [15:0] fft_buffer_im [0:FFT_SIZE-1];
    
    // FFT state machine
    localparam logic [1:0] S_COLLECT   = 2'd0,
                           S_BUTTERFLY = 2'd1,
                           S_MAGNITUDE = 2'd2;
    logic [1:0] state;
    logic [5:0] sample_index;

    
    function automatic [5:0] bit_reverse6(input [5:0] idx);
        bit_reverse6 = {idx[0], idx[1], idx[2], idx[3], idx[4], idx[5]};
    endfunction
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_COLLECT;
            sample_index <= 6'd0;
        end else begin
            case (state) begin
                S_COLLECT: begin
                    if (sample_valid) begin
                        // reversing the index bits is a smart way to give the shuffled order after even and odd index splits
                        fft_buffer_re[bit_reverse6(sample_index)] <= scaled_sample;
                        fft_buffer_im[bit_reverse6(sample_index)] <= 16'sd0;

                        if (sample_index == 6'd63) begin
                            sample_index <= 6'd0;
                            state      <= S_BUTTERFLY; 
                        end
                        else begin
                            sample_index <= sample_index + 1'b1;
                        end
                    end
                end 
                S_BUTTERFLY: begin
                    
                end
                S_MAGNITUDE: begin
                    // Step 3: Compute magnitudes for bins 0..31
                end
            end
    end


endmodule
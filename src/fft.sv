/*
Implements iterative fft on hardware
*/

module fft #(
    parameter int FFT_SIZE   = 64,
    parameter int NUM_BARS   = FFT_SIZE / 2,  // 32 positive frequency bins 
    parameter int GAIN_SHIFT = 4,             // Microphone input gain shift 
    parameter int MAG_SHIFT  = 4,             // Post-FFT magnitude shift to 8-bit 
    parameter int DECAY_STEP = 4              // Bar fall speed per FFT frame
) (
    input wire clk,
    input wire rst_n,

    // audio inputss 
    input wire signed [23:0] sample_in,
    input wire sample_valid,

    output logic [$clog2(NUM_BARS)-1:0] bin_idx,
    output logic [7:0] mag_out,
    output logic mag_valid
);

    localparam int STAGES   = $clog2(FFT_SIZE); // 6 stages for 64-point FFT (p)
    localparam int HALF_N   = FFT_SIZE / 2;     // 32 butterflies per stage (n / 2)


    logic signed [15:0] X_re[0:FFT_SIZE-1];
    logic signed [15:0] X_im[0:FFT_SIZE-1];
    logic [7:0] bars[0:NUM_BARS-1];

    // FFT state machine
    localparam logic [1:0] S_COLLECT = 2'd0, S_BUTTERFLY = 2'd1, S_MAGNITUDE = 2'd2;
    logic [1:0] state;
    logic [5:0] sample_index;


    function automatic [5:0] bit_reverse6(input [5:0] idx);
        bit_reverse6 = {idx[0], idx[1], idx[2], idx[3], idx[4], idx[5]};
    endfunction

    // Twiddle factor computation lookup tables
    logic signed [15:0] twiddle_cos_rom[0:HALF_N-1];
    logic signed [15:0] twiddle_sin_rom[0:HALF_N-1];

    initial begin
        $readmemh("src/rom/twiddle_cos.hex", twiddle_cos_rom);
        $readmemh("src/rom/twiddle_sin.hex", twiddle_sin_rom);
    end

    // hardware loop counter registers
    logic [2:0] s;  // DFT stage
    logic [5:0] k;  // group start index
    logic [5:0] j;  // pair offset index

    logic [6:0] m;
    logic [5:0] half_m;
    logic signed [15:0] w_re, w_im;
    logic [5:0] idx_u, idx_t;
    logic signed [15:0] u_re, u_im;
    logic signed [15:0] x_re, x_im;
    logic signed [31:0] ac, bd, ad, bc;
    logic signed [16:0] t_re, t_im;

    // magnitude
    logic [4:0] bin_cnt;
    logic [31:0] mag;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_COLLECT;
            sample_index <= 6'd0;
            bin_cnt      <= 5'd0;
            mag_valid    <= 1'b0;
        end else begin
            mag_valid <= 1'b0;
            case (state)
                S_COLLECT: begin
                    if (sample_valid) begin
                        // reversing the index bits is a smart way to give the shuffled order after even and odd index splits
                        // shift bit right 8 + 6 = 14 stages so input has 6 bits of headroom to grow across 6 stages without overflowing. We reduce sample by 8 bits to go from 24 to 16. Additionally each of the 6 butterfly stages can use an extra bit of headroom for u + t additions per stage
                        X_re[bit_reverse6(
                            sample_index
                        )] <= (sample_in <<< GAIN_SHIFT) >>> (8 + STAGES);
                        X_im[bit_reverse6(sample_index)] <= 16'sd0;

                        if (sample_index == 6'd63) begin
                            sample_index <= 6'd0;
                            // loop variables to pipline for loops
                            s            <= 3'd1;
                            k            <= 6'd0;
                            j            <= 6'd0;

                            // state machine
                            state        <= S_BUTTERFLY;
                        end else begin
                            sample_index <= sample_index + 1'b1;
                        end
                    end
                end

                // compute iterative fft computations and update X
                S_BUTTERFLY: begin
                    // Sub dft size (m = 2^s, half_m = m / 2)
                    m      = 7'd1 << s;
                    half_m = m[6:1];

                    // Twiddle factor w = (w_re + j*w_im) from ROM
                    w_re   = twiddle_cos_rom[j<<(STAGES-s)];
                    w_im   = twiddle_sin_rom[j<<(STAGES-s)];

                    // Array indices for u = X[k + j] 
                    idx_u  = k + j;
                    u_re   = X_re[idx_u];
                    u_im   = X_im[idx_u];

                    // Array index for t = X[k + j + m/2]
                    idx_t  = k + j + half_m;
                    x_re   = X_re[idx_t];
                    x_im   = X_im[idx_t];

                    // Complex multiplication: t = w * X[k + j + m/2]
                    // (a + jb)(c + jd) = (ac - bd) + j(ad + bc)
                    ac     = x_re * w_re;
                    bd     = x_im * w_im;
                    ad     = x_re * w_im;
                    bc     = x_im * w_re;

                    // Shift right by 15 to return from Q2.30 to Q1.15 fixed-point
                    t_re   = (ac - bd) >>> 15;
                    t_im   = (ad + bc) >>> 15;

                    // arithmetic shift is divide by two 
                    // X[k + j] = (u + t) 
                    X_re[idx_u] <= u_re + t_re[15:0];
                    X_im[idx_u] <= u_im + t_im[15:0];


                    // X[k + j + m/2] = (u - t) 
                    X_re[idx_t] <= u_re - t_re[15:0];
                    X_im[idx_t] <= u_im - t_im[15:0];


                    // loops are written outwards on hardaware, starting from fastest inner loop (s)
                    if (j + 6'd1 < half_m) begin
                        // inner loop
                        j <= j + 6'd1;
                    end else begin
                        // middle loop 
                        j <= 6'd0;
                        if (k + m < 7'(FFT_SIZE)) begin
                            // Middle loop (k) still has steps left -> step k by m!
                            k <= k + m[5:0];
                        end else begin
                            k <= 6'd0;
                            if (s < STAGES) begin
                                // outer loop
                                s <= s + 3'd1;
                            end else begin
                                // all three loops done
                                state <= S_MAGNITUDE;
                            end
                        end
                    end

                end
                S_MAGNITUDE: begin
                    mag = (X_re[bin_cnt] * X_re[bin_cnt] + X_im[bin_cnt] * X_im[bin_cnt]) >> (2 * MAG_SHIFT);

                    bin_idx   <= bin_cnt;
                    mag_out   <= (mag > 32'd255) ? 8'd255 : mag[7:0];
                    mag_valid <= 1'b1;

                    if (bin_cnt == 5'd31) begin
                        bin_cnt <= 5'd0;
                        state   <= S_COLLECT;
                    end else begin
                        bin_cnt <= bin_cnt + 5'd1;
                    end
                end

                default: state <= S_COLLECT;
            endcase
        end
    end





endmodule

`default_nettype wire

`default_nettype none

/*
TMDS Encoder (Transition Minimised Differential Signaling).

Implemented from gowin user guide
Refer to Gowin DVI TX RX IP guide 

This module implements the standard DVI 1.0 / HDMI TMDS encoding algorithm.
It takes 8-bit parallel color data (Red, Green, or Blue) and encodes it into 
a 10-bit symbol.

1. Transition Minimisation: The data is XOR'd or XNOR'd to minimise the number of 
0->1 and 1->0 transitions. This reduces electromagnetic interference (EMI) 
over the high-speed HDMI cable.
2. DC Balancing: It keeps track of the "disparity" (the running difference between 
the number of 1s and 0s transmitted) and optionally inverts the output to ensure 
that over time, the number of 1s and 0s is exactly equal. This keeps the DC voltage 
on the physical wire balanced at exactly 0V differential.

During the "blanking" periods (when DE is 0), it transmits special 10-bit control 
tokens that encode the HSYNC and VSYNC signals.
*/

module tmds_encoder (
    input wire clk,
    input wire rst_n,
    input wire [7:0] data_in,
    input wire [1:0] ctrl_in,
    input wire de,
    output reg [9:0] tmds_out
);

    // Count 1s in input data
    wire [3:0] n1_d;
    assign n1_d = data_in[0] + data_in[1] + data_in[2] + data_in[3] +
                  data_in[4] + data_in[5] + data_in[6] + data_in[7];

    // Stage 1: Transition minimization
    wire xnor_sel;
    assign xnor_sel = (n1_d > 4) || (n1_d == 4 && data_in[0] == 0);

    wire [8:0] q_m;
    assign q_m[0] = data_in[0];
    assign q_m[1] = xnor_sel ? (q_m[0] ^~ data_in[1]) : (q_m[0] ^ data_in[1]);
    assign q_m[2] = xnor_sel ? (q_m[1] ^~ data_in[2]) : (q_m[1] ^ data_in[2]);
    assign q_m[3] = xnor_sel ? (q_m[2] ^~ data_in[3]) : (q_m[2] ^ data_in[3]);
    assign q_m[4] = xnor_sel ? (q_m[3] ^~ data_in[4]) : (q_m[3] ^ data_in[4]);
    assign q_m[5] = xnor_sel ? (q_m[4] ^~ data_in[5]) : (q_m[4] ^ data_in[5]);
    assign q_m[6] = xnor_sel ? (q_m[5] ^~ data_in[6]) : (q_m[5] ^ data_in[6]);
    assign q_m[7] = xnor_sel ? (q_m[6] ^~ data_in[7]) : (q_m[6] ^ data_in[7]);
    assign q_m[8] = ~xnor_sel;

    // Count 1s and 0s in q_m[7:0]
    wire [3:0] n1_q_m;
    wire [3:0] n0_q_m;
    assign n1_q_m = q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7];
    assign n0_q_m = 4'd8 - n1_q_m;

    // Disparity counter
    reg signed [4:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmds_out <= 10'b0;
            cnt <= 5'd0;
        end else begin
            // Encoding algorithm in 3.2.1 DVI TX
            if (de) begin
                if (cnt == 0 || n1_q_m == n0_q_m) begin
                    tmds_out[9]   <= ~q_m[8];
                    tmds_out[8]   <= q_m[8];
                    tmds_out[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];

                    if (q_m[8]) begin
                        cnt <= cnt + (n1_q_m - n0_q_m);
                    end else begin
                        cnt <= cnt + (n0_q_m - n1_q_m);
                    end
                end else begin
                    if ((cnt > 0 && n1_q_m > n0_q_m) || (cnt < 0 && n0_q_m > n1_q_m)) begin
                        tmds_out[9] <= 1'b1;
                        tmds_out[8] <= q_m[8];
                        tmds_out[7:0] <= ~q_m[7:0];
                        cnt <= cnt + 2 * q_m[8] + (n0_q_m - n1_q_m);
                    end else begin
                        tmds_out[9] <= 1'b0;
                        tmds_out[8] <= q_m[8];
                        tmds_out[7:0] <= q_m[7:0];
                        cnt <= cnt - 2 * (~q_m[8]) + (n1_q_m - n0_q_m);
                    end
                end
            end else begin

                case (ctrl_in)
                    2'b00: tmds_out <= 10'b1101010100;
                    2'b01: tmds_out <= 10'b0010101011;
                    2'b10: tmds_out <= 10'b0101010100;
                    2'b11: tmds_out <= 10'b1010101011;
                endcase
                cnt <= 5'd0;
            end
        end
    end

endmodule

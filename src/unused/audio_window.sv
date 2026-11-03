`default_nettype none


/*
Audio scaling, saturation and hanning window

Takes 24 bit signed audio and processes it
*/

module audio_window #(
    parameter int FRAME_SIZE = 64,  // Samples per FFT frame
    parameter int GAIN_SHIFT = 4   
)(
    input  logic                          clk,
    input  logic                          rst_n,

    //  I2S Receiver Interface
    input  logic signed [23:0]            sample_in,
    input  logic                          sample_valid,

    // Downstream Windowed Sample Stream (to fft_core.sv)
    output logic signed [15:0]            win_sample,
    output logic [$clog2(FRAME_SIZE)-1:0] win_idx,
    output logic                          win_valid,
    output logic                          frame_done
);

    localparam int ADDR_WIDTH = $clog2(FRAME_SIZE);

    // -------------------------------------------------------------------------
    // Precomputed 128-Point Q0.15 Hanning Window LUT (0 .. 32767)
    //   w[k] = round(32767 * 0.5 * (1 - cos(2 * pi * k / 128)))
    //   Uses cosine symmetry to fold k = 65..127 onto 63..1.
    // -------------------------------------------------------------------------
    function automatic [15:0] get_hanning_q15(input [6:0] k);
        reg [6:0] sym_k;
        begin
            sym_k = (k > 7'd64) ? (7'd0 - k) : k;
            case (sym_k)
                7'd0:   get_hanning_q15 = 16'd0;     7'd1:   get_hanning_q15 = 16'd20;
                7'd2:   get_hanning_q15 = 16'd79;    7'd3:   get_hanning_q15 = 16'd178;
                7'd4:   get_hanning_q15 = 16'd315;   7'd5:   get_hanning_q15 = 16'd492;
                7'd6:   get_hanning_q15 = 16'd707;   7'd7:   get_hanning_q15 = 16'd961;
                7'd8:   get_hanning_q15 = 16'd1252;  7'd9:   get_hanning_q15 = 16'd1580;
                7'd10:  get_hanning_q15 = 16'd1946;  7'd11:  get_hanning_q15 = 16'd2347;
                7'd12:  get_hanning_q15 = 16'd2785;  7'd13:  get_hanning_q15 = 16'd3257;
                7'd14:  get_hanning_q15 = 16'd3765;  7'd15:  get_hanning_q15 = 16'd4306;
                7'd16:  get_hanning_q15 = 16'd4880;  7'd17:  get_hanning_q15 = 16'd5486;
                7'd18:  get_hanning_q15 = 16'd6124;  7'd19:  get_hanning_q15 = 16'd6792;
                7'd20:  get_hanning_q15 = 16'd7490;  7'd21:  get_hanning_q15 = 16'd8216;
                7'd22:  get_hanning_q15 = 16'd8970;  7'd23:  get_hanning_q15 = 16'd9750;
                7'd24:  get_hanning_q15 = 16'd10555; 7'd25:  get_hanning_q15 = 16'd11383;
                7'd26:  get_hanning_q15 = 16'd12234; 7'd27:  get_hanning_q15 = 16'd13105;
                7'd28:  get_hanning_q15 = 16'd13996; 7'd29:  get_hanning_q15 = 16'd14905;
                7'd30:  get_hanning_q15 = 16'd15830; 7'd31:  get_hanning_q15 = 16'd16384;
                7'd32:  get_hanning_q15 = 16'd16384; 7'd33:  get_hanning_q15 = 16'd17937;
                7'd34:  get_hanning_q15 = 16'd18771; 7'd35:  get_hanning_q15 = 16'd19601;
                7'd36:  get_hanning_q15 = 16'd20426; 7'd37:  get_hanning_q15 = 16'd21244;
                7'd38:  get_hanning_q15 = 16'd22053; 7'd39:  get_hanning_q15 = 16'd22851;
                7'd40:  get_hanning_q15 = 16'd23637; 7'd41:  get_hanning_q15 = 16'd24408;
                7'd42:  get_hanning_q15 = 16'd25163; 7'd43:  get_hanning_q15 = 16'd25900;
                7'd44:  get_hanning_q15 = 16'd26618; 7'd45:  get_hanning_q15 = 16'd27314;
                7'd46:  get_hanning_q15 = 16'd27987; 7'd47:  get_hanning_q15 = 16'd28636;
                7'd48:  get_hanning_q15 = 16'd29258; 7'd49:  get_hanning_q15 = 16'd29853;
                7'd50:  get_hanning_q15 = 16'd30419; 7'd51:  get_hanning_q15 = 16'd30955;
                7'd52:  get_hanning_q15 = 16'd31459; 7'd53:  get_hanning_q15 = 16'd31930;
                7'd54:  get_hanning_q15 = 16'd32368; 7'd55:  get_hanning_q15 = 16'd32589;
                7'd56:  get_hanning_q15 = 16'd32688; 7'd57:  get_hanning_q15 = 16'd32747;
                7'd58:  get_hanning_q15 = 16'd32760; 7'd59:  get_hanning_q15 = 16'd32764;
                7'd60:  get_hanning_q15 = 16'd32765; 7'd61:  get_hanning_q15 = 16'd32766;
                7'd62:  get_hanning_q15 = 16'd32766; 7'd63:  get_hanning_q15 = 16'd32767;
                7'd64:  get_hanning_q15 = 16'd32767;
                default: get_hanning_q15 = 16'd0;
            endcase
        end
    endfunction

    
endmodule

`default_nettype wire


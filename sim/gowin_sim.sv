`timescale 1ns / 100fs
`default_nettype none

/*
 * Behavioral simulation models for Gowin GW2AR-18 primitives
 * Used by simulation tools (iverilog, Verilator, etc.) without polluting synthesizable RTL.
 */

// rPLL Behavioral Simulation Model
module rPLL #(
    parameter FCLKIN           = "27",
    parameter DEVICE           = "GW2AR-18C",
    parameter IDIV_SEL         = 3,
    parameter FBDIV_SEL        = 54,
    parameter ODIV_SEL         = 2,
    parameter DYN_IDIV_SEL     = "false",
    parameter DYN_FBDIV_SEL    = "false",
    parameter DYN_ODIV_SEL     = "false",
    parameter DYN_DA_EN        = "true",
    parameter DUTYDA_SEL       = "1000",
    parameter CLKFB_SEL        = "internal",
    parameter CLKOUT_FT_DIR    = 1'b1,
    parameter CLKOUTP_FT_DIR   = 1'b1,
    parameter CLKOUT_DLY_STEP  = 0,
    parameter CLKOUTP_DLY_STEP = 0,
    parameter CLKOUT_BYPASS    = "false",
    parameter CLKOUTP_BYPASS   = "false",
    parameter CLKOUTD_BYPASS   = "false",
    parameter DYN_SDIV_SEL     = 2,
    parameter CLKOUTD_SRC      = "CLKOUT",
    parameter CLKOUTD3_SRC     = "CLKOUT"
)(
    input  wire       CLKIN,
    input  wire       CLKFB,
    input  wire       RESET,
    input  wire       RESET_P,
    input  wire [5:0] FBDSEL,
    input  wire [5:0] IDSEL,
    input  wire [5:0] ODSEL,
    input  wire [3:0] PSDA,
    input  wire [3:0] DUTYDA,
    input  wire [3:0] FDLY,
    output wire       CLKOUT,
    output wire       CLKOUTP,
    output wire       CLKOUTD,
    output wire       CLKOUTD3,
    output reg        LOCK
);

    // 371.25 MHz clock generation:
    // Period = 1000 / 371.25 = 2.6936027 ns -> Half-period = 1.3468013 ns
    reg clk_gen = 1'b0;

    always #1.3468 clk_gen = ~clk_gen;

    // Lock generation after reset deassertion
    initial begin
        LOCK = 1'b0;
        #100;
        if (!RESET) LOCK = 1'b1;
    end

    always @(posedge RESET) begin
        LOCK <= 1'b0;
    end

    always @(negedge RESET) begin
        LOCK <= 1'b0;
        #100;
        if (!RESET) LOCK <= 1'b1;
    end

    assign CLKOUT   = (RESET) ? 1'b0 : clk_gen;
    assign CLKOUTP  = 1'b0;
    assign CLKOUTD  = 1'b0;
    assign CLKOUTD3 = 1'b0;

endmodule

// CLKDIV Behavioral Simulation Model
module CLKDIV #(
    parameter DIV_MODE = "5",
    parameter GSREN    = "false"
)(
    input  wire HCLKIN,
    input  wire RESETN,
    input  wire CALIB,
    output reg  CLKOUT
);

    int div_cnt = 0;

    initial CLKOUT = 1'b0;

    always @(posedge HCLKIN or negedge RESETN) begin
        if (!RESETN) begin
            div_cnt <= 0;
            CLKOUT  <= 1'b0;
        end else begin
            if (div_cnt == 4) begin
                div_cnt <= 0;
                CLKOUT  <= 1'b1;
            end else if (div_cnt == 2) begin
                div_cnt <= div_cnt + 1;
                CLKOUT  <= 1'b0;
            end else begin
                div_cnt <= div_cnt + 1;
            end
        end
    end

endmodule

// OSER10 Behavioral 10:1 Serializer Simulation Model
module OSER10 (
    input  wire D0,
    input  wire D1,
    input  wire D2,
    input  wire D3,
    input  wire D4,
    input  wire D5,
    input  wire D6,
    input  wire D7,
    input  wire D8,
    input  wire D9,
    input  wire FCLK,
    input  wire PCLK,
    input  wire RESET,
    output reg  Q
);

    reg [9:0] load_buf = 10'd0;
    reg [9:0] shift_reg = 10'd0;
    reg [3:0] bit_cnt = 4'd0;

    initial begin
        Q = 1'b0;
    end

    // Parallel load on pixel clock
    always @(posedge PCLK or posedge RESET) begin
        if (RESET) begin
            load_buf <= 10'd0;
        end else begin
            load_buf <= {D9, D8, D7, D6, D5, D4, D3, D2, D1, D0};
        end
    end

    // High-speed serialization on fast serial clock
    always @(posedge FCLK or posedge RESET) begin
        if (RESET) begin
            shift_reg <= 10'd0;
            bit_cnt   <= 4'd0;
            Q         <= 1'b0;
        end else begin
            if (bit_cnt == 4'd0) begin
                shift_reg <= load_buf >> 1;
                Q         <= load_buf[0];
                bit_cnt   <= 4'd1;
            end else begin
                Q         <= shift_reg[0];
                shift_reg <= shift_reg >> 1;
                if (bit_cnt == 4'd9) begin
                    bit_cnt <= 4'd0;
                end else begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end
        end
    end

endmodule

// TLVDS_OBUF True LVDS Differential Output Buffer Simulation Model
module TLVDS_OBUF (
    input  wire I,
    output wire O,
    output wire OB
);

    assign O  = I;
    assign OB = ~I;

endmodule

`default_nettype wire

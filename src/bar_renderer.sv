module bar_renderer #(
    parameter int NUM_BARS   = 64,
    parameter int BAR_WIDTH  = 20,
    parameter int GAP_WIDTH  = 4,
    parameter int Y_BOTTOM   = 450,  // Baseline Y coordinate
    parameter int MAX_HEIGHT = 256   // Max bar height in pixels
)(
    input  logic        clk,          // Pixel clock
    input  logic        rst_n,        // Active low
    
    // Video timing inputs
    input  logic [11:0] pixel_x,
    input  logic [11:0] pixel_y,
    input  logic        active_video, // Active inside 1280x720 box

    // Interface to bar_levels memory
    input  logic [7:0]                  bar_level, // Current height of bar_addr
    output logic [$clog2(NUM_BARS)-1:0] bar_addr,  // Current bar index (0..63)

    // RGB Output
    output logic [23:0] rgb_out       // 8-bit RGB streams
);

    localparam logic [23:0] RED         = 24'hFF0000;
    localparam logic [23:0] LIGHT_GREEN = 24'h00FF00;
    localparam logic [23:0] DARK_GREEN  = 24'h005500;
    localparam logic [23:0] BLACK       = 24'h000000;

    localparam int THRESH_MID = MAX_HEIGHT / 3;       
    localparam int THRESH_RED = (MAX_HEIGHT * 2) / 3; 
    localparam int SOLID_WIDTH = BAR_WIDTH - GAP_WIDTH; 

    // Horizontal Tracking (Running counter method for 20px pitch)
    // 64 x 20 = 1280
    logic [$clog2(NUM_BARS):0]    current_bar_idx;
    logic [$clog2(BAR_WIDTH)-1:0] sub_bar_x;
    logic                         in_gap;

    assign bar_addr = current_bar_idx;
    assign in_gap   = (sub_bar_x >= SOLID_WIDTH);

    always_ff @(posedge clk) begin
        if (!rst_n || !active_video) begin
            current_bar_idx <= 0;
            sub_bar_x       <= 0;
        end else begin
            if (sub_bar_x == BAR_WIDTH - 1) begin
                sub_bar_x       <= 0;
                current_bar_idx <= current_bar_idx + 1'b1;
            end else begin
                sub_bar_x <= sub_bar_x + 1;
            end
        end
    end

    // Introduce 1 cycle delay to match BRAM read latency to sync with bar_addr
    logic        in_gap_d1;
    logic [11:0] pixel_y_d1;
    logic        active_video_d1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            in_gap_d1       <= 1'b1;
            pixel_y_d1      <= '0;
            active_video_d1 <= 1'b0;
        end else begin
            in_gap_d1       <= in_gap;
            pixel_y_d1      <= pixel_y;
            active_video_d1 <= active_video;
        end
    end

    // Vertical calculation and colour picker
    logic        above_floor;
    logic [11:0] dist_from_bottom;

    assign above_floor      = (pixel_y_d1 <= Y_BOTTOM);
    assign dist_from_bottom = above_floor ? (Y_BOTTOM - pixel_y_d1) : 12'd0;

    always_ff @(posedge clk) begin
        if (!rst_n || !active_video_d1) begin
            rgb_out <= BLACK;
        end else if ((!in_gap_d1) && above_floor &&
                     (bar_level > 8'd0) &&
                     (dist_from_bottom <= bar_level)) begin
            if (dist_from_bottom >= THRESH_RED) begin
                rgb_out <= RED;
            end else if (dist_from_bottom >= THRESH_MID) begin
                rgb_out <= DARK_GREEN;
            end else begin
                rgb_out <= LIGHT_GREEN;
            end
        end else begin
            rgb_out <= BLACK;
        end
    end

endmodule

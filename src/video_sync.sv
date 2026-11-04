`default_nettype none

// Sweeps across each 1650x750 frame at the pixel clock rate (74.25 MHz) to:
//   1. Output the current visible screen coordinates (pixel_x, pixel_y).
//   2. Assert Data Enable (de = 1) inside the 1280x720 active video region.
//   3. Generate horizontal and vertical sync pulses (hsync, vsync) during
//      blanking intervals so the monitor can align each row and frame.

module video_sync #(
    // 1280x720 @ 60Hz settings
    parameter H_ACTIVE      = 1280,
    parameter H_FRONT_PORCH = 110,
    parameter H_SYNC_PULSE  = 40,
    parameter H_BACK_PORCH  = 220,

    parameter V_ACTIVE      = 720,
    parameter V_FRONT_PORCH = 5,
    parameter V_SYNC_PULSE  = 5,
    parameter V_BACK_PORCH  = 20,

    parameter H_POLARITY = 1,  // 1 for positive, 0 for negative
    parameter V_POLARITY = 1   // 1 for positive, 0 for negative
) (
    input wire clk,
    input wire rst_n,
    output reg hsync,
    output reg vsync,
    output reg data_enable,
    output reg [11:0] pixel_x,
    output reg [11:0] pixel_y
);

    localparam H_TOTAL = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
    localparam V_TOTAL = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

    reg [11:0] h_count = 12'd0;
    reg [11:0] v_count = 12'd0;

    initial begin
        h_count     = 12'd0;
        v_count     = 12'd0;
        hsync       = ~H_POLARITY;
        vsync       = ~V_POLARITY;
        data_enable = 1'b0;
        pixel_x     = 12'd0;
        pixel_y     = 12'd0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 0;
                end else begin
                    v_count <= v_count + 1;
                end
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hsync <= ~H_POLARITY;
            vsync <= ~V_POLARITY;
            data_enable    <= 0;
            pixel_x <= 0;
            pixel_y <= 0;
        end else begin
            // HSYNC generation
            if (h_count >= H_ACTIVE + H_FRONT_PORCH && h_count < H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE)
                hsync <= H_POLARITY;
            else hsync <= ~H_POLARITY;

            // VSYNC generation
            if (v_count >= V_ACTIVE + V_FRONT_PORCH && v_count < V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE)
                vsync <= V_POLARITY;
            else vsync <= ~V_POLARITY;

            // DE generation
            if (h_count < H_ACTIVE && v_count < V_ACTIVE) data_enable <= 1'b1;
            else data_enable <= 1'b0;

            // Coordinates
            if (h_count < H_ACTIVE) pixel_x <= h_count;
            else pixel_x <= 0;

            if (v_count < V_ACTIVE) pixel_y <= v_count;
            else pixel_y <= 0;
        end
    end

endmodule

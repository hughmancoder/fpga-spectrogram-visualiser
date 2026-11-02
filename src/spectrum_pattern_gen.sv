`default_nettype none

/*
 * spectrum_pattern_gen: Standalone synthetic audio equalizer test pattern generator.
 *
 * Simulates dynamic audio spectrum bars to verify the video visualizer on hardware
 * before connecting microphone/I2S/FFT audio processing.
 *
 * Key features:
 * 1. Traveling Waves: Combines two counter-propagating triangle waves for ripple effects.
 * 2. Bass Pulse: Rhythmic low-frequency beat on bars 0-15 every 32 frames with gradual decay.
 * 3. Resonance Sweep: Bounces a bell-shaped pulse back and forth across the 64 frequency bars.
 * 4. Dual Interface: Direct memory read (bar_idx -> bar_level) and sequential frame writes.
 */
module spectrum_pattern_gen #(
    parameter int NUM_BARS       = 64,
    parameter int BAR_HEIGHT_MAX = 255,
    parameter int DATA_WIDTH     = 8
)(
    input  wire                          clk,        // System / pixel clock
    input  wire                          rst_n,      // Active-low reset
    input  wire                          tick,       // 1-cycle pulse per video frame (~60 Hz)

    // Direct read port (for bar_renderer)
    input  wire [$clog2(NUM_BARS)-1:0]   bar_idx,    // Bar index to read
    output wire [DATA_WIDTH-1:0]         bar_level,  // Current height of bar_idx

    // Sequential write port (for external dual-port RAM)
    output reg  [$clog2(NUM_BARS)-1:0]   write_addr,
    output reg  [DATA_WIDTH-1:0]         write_data,
    output reg                           write_en
);

    localparam int ADDR_WIDTH = $clog2(NUM_BARS);

    // Internal bar height storage (initialized to minimum visible floor)
    reg [DATA_WIDTH-1:0] bars [0:NUM_BARS-1];

    initial begin
        for (int i = 0; i < NUM_BARS; i++) begin
            bars[i] = (DATA_WIDTH > 8) ? 9'd16 : 8'd8;
        end
    end

    reg [7:0] frame_cnt;   // Global frame counter for animation time
    reg [7:0] bass_pulse;  // Decaying bass kick amplitude
    reg [5:0] sweep_pos;   // Current center position of sweeping pulse
    reg       sweep_dir;   // Sweep direction (0 = sweeping up, 1 = sweeping down)

    reg [ADDR_WIDTH-1:0] update_idx; // Current bar being updated across clock cycles
    reg                  updating;   // High while recalculating bar heights

    // Symmetrical 8-bit triangle wave generator (0 -> 254 -> 0)
    function automatic [7:0] tri_wave(input [7:0] phase);
        tri_wave = phase[7] ? (~phase[6:0] << 1) : (phase[6:0] << 1);
    endfunction

    // 1. Dual-wave interference pattern across frequency bars
    wire [7:0] wave1 = tri_wave((update_idx << 2) + (frame_cnt << 2));
    wire [7:0] wave2 = tri_wave((update_idx << 3) - (frame_cnt << 1));
    wire [DATA_WIDTH-1:0] base_level = (DATA_WIDTH > 8) ? ((wave1 + wave2) >> 1) : ((wave1 + wave2) >> 2);

    // 2. Rhythmic low-frequency thump on bass bins (bars 0-15)
    wire [7:0]            bass_scale = (update_idx < 16) ? (16 - update_idx) : 8'd0;
    wire [DATA_WIDTH-1:0] bass_add   = (DATA_WIDTH > 8) ? (bass_scale * bass_pulse[7:4]) :
                                                          ((bass_scale * bass_pulse[7:4]) >> 1);

    // 3. Resonant pulse sweeping back and forth across the spectrum
    wire [5:0] sweep_diff = (update_idx > sweep_pos) ? (update_idx - sweep_pos) : (sweep_pos - update_idx);
    wire [DATA_WIDTH-1:0] pulse_add = (DATA_WIDTH > 8) ?
        ((sweep_diff == 0) ? 9'd90 : (sweep_diff == 1) ? 9'd60 : (sweep_diff == 2) ? 9'd30 : 9'd0) :
        ((sweep_diff == 0) ? 8'd45 : (sweep_diff == 1) ? 8'd30 : (sweep_diff == 2) ? 8'd15 : 8'd0);

    // Minimum visible height floor so all bars remain visible
    wire [DATA_WIDTH-1:0] min_floor = (DATA_WIDTH > 8) ? 9'd16 : 8'd8;

    // 4. Composite height clamped between min floor and max ceiling
    wire [DATA_WIDTH+1:0] raw_sum = base_level + bass_add + pulse_add + min_floor;
    wire [DATA_WIDTH-1:0] clamped_level = (raw_sum > BAR_HEIGHT_MAX[DATA_WIDTH-1:0]) ? BAR_HEIGHT_MAX[DATA_WIDTH-1:0] :
                                          (raw_sum < min_floor)                       ? min_floor :
                                          raw_sum[DATA_WIDTH-1:0];

    // Frame update sequencer: recalculates and writes all bars sequentially on each tick
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_cnt   <= 8'd0;
            bass_pulse  <= 8'd0;
            sweep_pos   <= 6'd0;
            sweep_dir   <= 1'b0;
            update_idx  <= '0;
            updating    <= 1'b0;
            write_en    <= 1'b0;
            write_addr  <= '0;
            write_data  <= '0;
        end else begin
            write_en <= 1'b0;

            if (tick && !updating) begin
                updating   <= 1'b1;
                update_idx <= '0;
                frame_cnt  <= frame_cnt + 1'b1;

                if (frame_cnt[4:0] == 5'd0)
                    bass_pulse <= 8'd180;
                else if (bass_pulse > 8'd6)
                    bass_pulse <= bass_pulse - 8'd6;

                if (!sweep_dir) begin
                    if (sweep_pos == NUM_BARS - 1) sweep_dir <= 1'b1;
                    else sweep_pos <= sweep_pos + 1'b1;
                end else begin
                    if (sweep_pos == 6'd0) sweep_dir <= 1'b0;
                    else sweep_pos <= sweep_pos - 1'b1;
                end
            end else if (updating) begin
                bars[update_idx] <= clamped_level;
                write_addr       <= update_idx;
                write_data       <= clamped_level;
                write_en         <= 1'b1;

                if (update_idx == NUM_BARS - 1) begin
                    updating <= 1'b0;
                end else begin
                    update_idx <= update_idx + 1'b1;
                end
            end
        end
    end

    assign bar_level = bars[bar_idx];

endmodule

`default_nettype wire

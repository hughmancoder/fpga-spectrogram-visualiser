/*
    Clock Domain Crossing Synchroniser
    Multi-Stage Flip-Flop Synchroniser defaulting to 2 stages
    It safely passes signals from one clock domain (d) into a completely separate clock domain.
    Using multiple registers to delay the signal prevents metastability. 
 */

/*
module cdc_sync #(
    parameter int WIDTH  = 1,
    parameter int STAGES = 2      // >= 2
)(
    input  wire             clk,      // destination clock
    input  wire             rst_n,    // destination-domain async reset
    input  wire [WIDTH-1:0] d,        // signal from source domain
    output wire [WIDTH-1:0] q         // synchronised signal
);

// internal storage
(* async_reg = "true" *) logic [WIDTH-1:0] reg_q [STAGES-1:0];

// negedge for async reset
always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        // reset all stages to zero on reset
        for (int i = 0; i < STAGES; i++) begin
            reg_q[i] <= '0;
        end
    end else begin
        // Shift registers cascade
        reg_q[0] <= d;
        for (int i = 1; i < STAGES; i++) begin
            reg_q[i] <= reg_q[i - 1];
        end
    end
end

 assign q = reg_q[STAGES-1];


endmodule
*/
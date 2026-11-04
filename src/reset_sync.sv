/*
Reset synchroniser: asynchronous assert, synchronous deassert

arst_n can change at any time relative to clk. Releasing flip-flops directly from it can
violate recovery time, so they could leave reset on different clock edges or go metastable.

Assert:   arst_n low clears the shift register and drives rst_n low immediately, even if clk
          is stopped.
Deassert: arst_n high lets 1s shift through STAGES flip-flops, so rst_n rises on a clk edge.
          The first flip-flop may go metastable, and the stages after it give it time to settle.

Use one instance per clock domain.
*/

module reset_sync #(
    parameter int STAGES = 2  // Number of synchronisation stages (>= 2)
) (
    input wire clk,  // Destination clock
    input wire arst_n,  // Asynchronous active low reset
    output wire rst_n  // Synchronised active low reset
);

    logic [STAGES-1:0] sync_ff;

    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            sync_ff <= '0;
        end else begin
            // shift left and insert 1
            sync_ff <= {sync_ff[STAGES-2:0], 1'b1};
        end
    end

    // Drive rst_n from MSB
    assign rst_n = sync_ff[STAGES-1];

endmodule

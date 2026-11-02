/*
asynchronous reset to reset ff 
The moment arst_n goes low, every single flip-flop clears instantly
This guarantees every register comes out of reset on the exact same clock edge
*/

module reset_sync #(
    parameter int STAGES = 2 // Number of synchronisation stages (>= 2)
) (
    input wire clk, // Dest clock
    input wire arst_n, // active low reset
    output wire rst_n // synchronised active low reset
);

    logic [STAGES-1:0] sync_ff;
    always_ff @(posedge clk or negedge arst_n) begin 
        if (!arst_n) begin 
            sync_ff <= '0;
        end
        else begin
            // shift left and insert 1
            sync_ff <= {sync_ff[STAGES-2:0], 1'b1};
        end
    end

   //w Drive rst_n from MSB
   assign rst_n = sync_ff[STAGES - 1];

   
endmodule
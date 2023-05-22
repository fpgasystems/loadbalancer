
module upcounter #(
    parameter COUNT_BITS = 3,
    parameter MAX = 2**COUNT_BITS - 1
) (
    input   clk,
    input   resetn,
    input   enable,

    output  logic [COUNT_BITS-1:0] count,
    output  logic max_tick
);
    logic [COUNT_BITS-1:0] next_count;
    // localparam int MAX = 2**COUNT_BITS - 1;

    always_ff @( posedge clk ) begin : StateUpdate
        if (resetn == 1'b0 || enable == 1'b0) begin
            count <= '0;
        end else begin
            count <= next_count;
        end
    end

    always_comb begin : NextState
        if (max_tick == 1'b0) begin
            next_count = count + 1'b1;            
        end else begin
            next_count = count;
        end
    end

    always_comb begin : OutputLogic
        if (count == MAX) begin
            max_tick = 1'b1;
        end else begin
            max_tick = 1'b0;
        end
    end
endmodule
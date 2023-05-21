`include "../src/upcounter.sv"


module upcounter_tb ();
    logic clk;
    logic resetn;
    logic enable;

    localparam COUNT_BITS = 2;
    logic [COUNT_BITS-1:0] count_out;
    logic max_tick_out;

    upcounter #(
        .COUNT_BITS(COUNT_BITS)
    ) counter (
        .clk(clk),
        .resetn(resetn),
        .enable(enable),
        .count(count_out),
        .max_tick(max_tick_out)
    );

    always @* begin
      #1
      clk <= ~clk;
    end

    initial begin
        $display("Testbech::upcounter started");
        $dumpfile("counter_tb.vcd");
        $dumpvars(1);

        clk <= 1'b1;
        resetn <= 1'b0;
        enable <= 1'b0;

        #2
        resetn <= 1'b1;

        #2 
        enable <= 1'b1;

        #6
        enable <= 0'b0;

        #4
        enable <= 1'b1;

        #8
        enable <= 1'b0; 

        #2
        $finish;
        $stop(0);
    end
    
endmodule
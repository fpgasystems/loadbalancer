`include "../src/loadbalancer.sv"
`include "../src/axis_intf.sv"
`include "../src/queues/fifo.sv"

module loadBalancer_tb ();
    reg clk;
    reg resetn;

    AXI4S meta_src();
    AXI4S hdr_src();
    AXI4S bdy_src();

    logic [4*16-1:0] region_stats_out;

    wire [32-1:0] lb_ctrl;
    wire [32-1:0] pr_ctrl;

    loadBalancer #(
        .HTTP_DATA_WIDTH(8),
        .QDEPTH(4)
    ) lb (
        .aclk(clk),
        .aresetn(resetn),
        .meta_snk(meta_src),
        .hdr_snk(hdr_src),
        .bdy_snk(bdy_src),
        .region_stats_in(region_stats_out),
        .lb_ctrl(lb_ctrl),
        .pr_ctrl(pr_ctrl)
    );

    logic [4-1:0][8-1:0] queue_data;
    logic [8-1:0] queue_in;
    logic q_is_full;
    logic q_is_empty;
    assign queue_data = lb.meta_queue.inst_fifo.data;
    assign queue_in = lb.meta_queue.inst_fifo.data_in;
    assign q_is_full = lb.meta_queue.inst_fifo.is_full;
    assign q_is_empty = lb.meta_queue.inst_fifo.is_empty;

    always @* begin
      // * To prevent racing, we should set delay first 
      // * s.t. the clock can be initialized to a known value 
      // * (by the below initial block) before flipping.
      #1
      clk <= ~clk;
    end

    initial begin
        $dumpfile("lb_tb.vcd");
        $dumpvars(1);
        clk <= 1'b1;
        resetn <= 1'b0;
        region_stats_out <= 64'hFFFF_FFFF_FFFF_FFFF;
        $display("Testbech::loadBalancer started");
        
        #2
        resetn <= 1'b1;
        meta_src.tvalid <= 1'b0;
        lb.meta_snk.tready <= 1'b0;
        meta_src.tdata <= 8'hAA;

        #2
        meta_src.tvalid <= 1'b0;
        lb.meta_snk.tready <= 1'b1;
        meta_src.tdata <= 8'hAA;

        #2
        // meta_src.tvalid <= 1'b1;
        region_stats_out <= 64'h0123_4567_89AB_CDEF;

        #2
        meta_src.tvalid <= 1'b1;
        // ? Why controlling slave ready here doesn't work?
        lb.meta_snk.tready <= 1'b0;
        meta_src.tdata <= 8'hBB;

        #2
        meta_src.tvalid <= 1'b0;
        // lb.meta_snk.tready <= 1'b1;
        meta_src.tdata <= 8'hCC;

        #2
        // ? Why can't we push another request into the queue (depth=4)?
        meta_src.tvalid <= 1'b1;
        // lb.meta_snk.tready <= 1'b1;
        meta_src.tdata <= 8'hCC;
        
        #10 $finish;
        $stop(0);
    end

    
endmodule
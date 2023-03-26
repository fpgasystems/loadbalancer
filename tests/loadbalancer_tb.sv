`include "../src/loadbalancer.sv"
`include "../src/axis_intf.sv"
`include "../src/queues/fifo.sv"

module loadBalancer_tb ();
    reg clk;
    reg resetn;

    localparam OPERATOR_ID_WIDTH = 16;
    localparam HTTP_META_WIDTH = 8;
    localparam N_REGIONS = 4;
    localparam QDEPTH = 4;

    // * Instantiate interfaces.
    AXI4S #(.AXI4S_DATA_BITS(8)) meta_src(clk);
    AXI4S hdr_src(clk);
    AXI4S bdy_src(clk);

    wire [2*OPERATOR_ID_WIDTH-1:0] lb_ctrl;
    wire [2*OPERATOR_ID_WIDTH-1:0] pr_ctrl;

    logic [N_REGIONS*OPERATOR_ID_WIDTH-1:0] region_stats_out;

    loadbalancer #(
        .HTTP_META_WIDTH(8),
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

    logic [N_REGIONS*OPERATOR_ID_WIDTH-1:0] region_stats_in;
    logic [QDEPTH-1:0][HTTP_META_WIDTH-1:0] meta_q_data;
    logic [HTTP_META_WIDTH-1:0] meta_q_in;
    logic [$clog2(QDEPTH)-1:0] meta_q_n_entries;
    logic meta_q_is_full;
    logic meta_q_is_empty;

    assign region_stats_in = lb.region_stats_in;
    
    assign meta_q_data = lb.meta_queue.inst_fifo.data;
    assign meta_q_in = lb.meta_queue.inst_fifo.data_in;

    assign meta_q_src_val = meta_src.tvalid;
    assign meta_q_rdy_snk = lb.meta_queue.rdy_snk;
    
    assign meta_q_is_full = lb.meta_queue.inst_fifo.is_full;
    assign meta_q_is_empty = lb.meta_queue.inst_fifo.is_empty;
    assign meta_q_n_entries = lb.meta_queue.inst_fifo.n_entries;


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
        $display("Testbech::loadbalancer started");
        
        #2
        resetn <= 1'b1;
        meta_src.tvalid <= 1'b0;
        meta_src.tdata <= 8'hAA;

        #2
        meta_src.tvalid <= 1'b0;
        meta_src.tdata <= 8'hAA;

        #2
        region_stats_out <= 64'h0123_4567_89AB_CDEF;

        #2
        meta_src.tvalid <= 1'b1;
        meta_src.tdata <= 8'hBB;

        #2
        meta_src.tvalid <= 1'b1;
        meta_src.tdata <= 8'hCC;

        #2
        meta_src.tvalid <= 1'b0;
        meta_src.tdata <= 8'hDD;

        #2
        meta_src.tvalid <= 1'b1;
        meta_src.tdata <= 8'hEE;

        #2
        meta_src.tvalid <= 1'b1;
        meta_src.tdata <= 8'hFF;

        #2
        meta_src.tvalid <= 1'b1;
        meta_src.tdata <= 8'hAA;

        #1
        meta_src.tvalid <= 1'b0;
        
        #3 $finish;
        $stop(0);
    end

    
endmodule
`include "../src/loadbalancer.sv"
`include "../src/axis_intf.sv"
`include "../src/queues/fifo.sv"

module loadbalancer_tb ();
    reg clk;
    reg resetn;

    localparam OPERATOR_ID_WIDTH = 2;
    localparam HTTP_META_WIDTH = 8;
    localparam N_REGIONS = 4;
    localparam QDEPTH = 4;
    localparam PNTR_BITS = $clog2(QDEPTH);

    // * Instantiate interfaces.
    AXI4S #(.AXI4S_DATA_BITS(HTTP_META_WIDTH)) meta_src(clk);
    AXI4S hdr_src(clk);
    AXI4S bdy_src(clk);
    
    logic  [$clog2(N_REGIONS)-1:0]lb_ctrl;
    // logic [2*OPERATOR_ID_WIDTH-1:0] pr_ctrl;

    logic [N_REGIONS*(OPERATOR_ID_WIDTH+PNTR_BITS)-1:0] region_stats_out;

    loadbalancer #(
        .HTTP_META_WIDTH(HTTP_META_WIDTH),
        .OPERATOR_ID_WIDTH(OPERATOR_ID_WIDTH),
        .N_REGIONS(N_REGIONS),
        .QDEPTH(QDEPTH)
    ) lb (
        .aclk(clk),
        .aresetn(resetn),
        .meta_in(meta_src),
        .hdr_in(hdr_src),
        .bdy_in(bdy_src),
        .region_stats_in(region_stats_out),
        .lb_ctrl(lb_ctrl)
        // .pr_ctrl(pr_ctrl)
    );

    // [ [region1: oid, load], [region2: oid, load] ] -> 4 * (2+2) = 16
    logic [N_REGIONS-1:0][(OPERATOR_ID_WIDTH+PNTR_BITS)-1:0] region_stats;
    logic [QDEPTH-1:0][HTTP_META_WIDTH-1:0] meta_q_data;
    logic [HTTP_META_WIDTH-1:0] meta_q_in;
    logic [PNTR_BITS-1:0] meta_q_n_entries;
    logic [PNTR_BITS-1:0] meta_q_wr_pntr;
    logic [PNTR_BITS-1:0] meta_q_rd_pntr;
    logic meta_q_is_full;
    logic meta_q_is_empty;
    logic [HTTP_META_WIDTH-1:0] meta_data_taken;

    assign region_stats = lb.region_stats;
    
    assign meta_q_data = lb.meta_queue.inst_fifo.data;
    assign meta_q_in = lb.meta_queue.inst_fifo.data_in;

    assign meta_q_val_src = lb.meta_queue.val_src;
    assign meta_q_rdy_snk = lb.meta_queue.rdy_snk;
    assign meta_q_is_full = lb.meta_queue.inst_fifo.is_full;
    assign meta_q_is_empty = lb.meta_queue.inst_fifo.is_empty;
    assign meta_q_n_entries = lb.meta_queue.inst_fifo.n_entries;
    assign meta_q_wr_pntr = lb.meta_queue.inst_fifo.wr_pntr;
    assign meta_q_rd_pntr = lb.meta_queue.inst_fifo.rd_pntr;

    assign meta_out_val = meta_src.tvalid;
    assign meta_rdy_src = lb.meta_rdy_src;
    assign meta_data_taken = lb.meta_data_taken;

    always @* begin
      // * To prevent racing, we should set delay first 
      // * s.t. the clock can be initialized to a known value 
      // * (by the below initial block) before flipping.
      #1
      clk <= ~clk;
    end

    initial begin
        /** This testbench interacts with the load balancer as an HTTP module. */
        $display("Testbech::loadbalancer started");
        $dumpfile("lb_tb.vcd");
        $dumpvars(1);
        clk <= 1'b1;
        resetn <= 1'b0;
        region_stats_out <= 16'h0000;
        
        #2
        resetn <= 1'b1;
                
        meta_src.tvalid <= 1'b0;
        meta_src.tdata <= 8'hAA;

        #2
        region_stats_out <= 16'bXX00_1101_1010_0111;

        meta_src.tvalid <= 1'b1;
        meta_src.tdata <= 8'hAA;

        #2
        meta_src.tvalid <= 1'b0;
        meta_src.tdata <= 8'h99;
        // region_stats_out <= 64'h0123_4567_89AB_CDEF;

        #2
        region_stats_out <= 16'b0010_1100_1011_0110;
        meta_src.tvalid <= 1'b1;
        meta_src.tdata <= 8'hBB;

        #2
        region_stats_out <= 16'b0011_1111_1001_0110;

        meta_src.tvalid <= 1'b1;
        meta_src.tdata <= 8'hCC;

        #2
        meta_src.tvalid <= 1'b0;
        meta_src.tdata <= 8'hDD;

        #2
        region_stats_out <= 16'b0011_1110_1011_0110;

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
`include "../src/loadbalancer.sv"
`include "../src/interfaces/axis_intf.sv"
`include "../src/queues/fifo.sv"

module loadbalancer_tb ();
    logic clk;
    logic resetn;

    localparam OPERATOR_ID_WIDTH = 4;
    localparam HTTP_META_WIDTH = 8;
    localparam N_REGIONS = 4;
    localparam QDEPTH = 16;
    localparam PNTR_BITS = $clog2(QDEPTH);

    // * Instantiate interfaces.
    AXI4S #(.AXI4S_DATA_BITS(HTTP_META_WIDTH)) meta_q_src(clk);
    AXI4S #(.AXI4S_DATA_BITS(HTTP_META_WIDTH)) meta_q_snk(clk);
    AXI4S #(.AXI4S_DATA_BITS(HTTP_META_WIDTH)) proxy_meta_snk(clk);
    // ! Unused.
    AXI4S hdr_src(clk);
    AXI4S bdy_src(clk);
    
    logic  [$clog2(N_REGIONS)-1:0]lb_ctrl;

    // *  4 x (OID: 4bits + load: 4 bits) = 32.
    logic [N_REGIONS*(OPERATOR_ID_WIDTH+PNTR_BITS)-1:0] region_stats_src;

    loadbalancer #(
        .HTTP_META_WIDTH(HTTP_META_WIDTH),
        .OPERATOR_ID_WIDTH(OPERATOR_ID_WIDTH),
        .N_REGIONS(N_REGIONS),
        .QDEPTH(QDEPTH)
    ) lb (
        .aclk(clk),
        .aresetn(resetn),
        .meta_q_in(meta_q_src),
        .hdr_q_in(hdr_src),
        .bdy_q_in(bdy_src),
        .region_stats_in(region_stats_src),
        .meta_q_out(meta_q_snk),
        .proxy_meta_out(proxy_meta_snk),
        .lb_ctrl(lb_ctrl)
        // .pr_ctrl(pr_ctrl)
    );

    // [ [region1: oid, load], [region2: oid, load] ] -> 4 x (4+4) = 32
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

    assign meta_src_val = meta_q_src.tvalid;
    assign meta_snk_rdy = meta_q_snk.tready;
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
        region_stats_src <= '0;
        
        #2 /** 1st request. */
        resetn <= 1'b1;    
        meta_q_src.tvalid <= 1'b1; // * Valid input meta.
        meta_q_src.tdata <= 8'hF9;

        // meta_q_snk.tready <= 1'b0; // * Force LB to be NOT ready.
        region_stats_src <= 32'hX0_35_61_74; // * Update region status.

        #2 
        meta_q_src.tvalid <= 1'b0; // * Stop pushing (duplicated) meta data to the queue.
        meta_q_src.tdata <= 8'hXX; // * No requests coming in.
        meta_q_snk.tready <= 1'b1; // * Allow LB to accept meta data.

        #2 /** 2nd request. */
        meta_q_src.tvalid <= 1'b1;
        meta_q_src.tdata <= 8'hF5;

        region_stats_src <= 32'h91_34_60_73;

        #2 /** 3rd request. */
        meta_q_src.tvalid <= 1'b1;
        meta_q_src.tdata <= 8'hF5;

        meta_q_snk.tready <= 1'b0; // * Force LB to be NOT ready.

        #2 /** 4th request (should be queued behind request3). */
        meta_q_src.tvalid <= 1'b1;
        meta_q_src.tdata <= 8'hF9;
        
        meta_q_snk.tready <= 1'b1; // * Let LB be ready.
        region_stats_src <= 32'h91_13_51_72;

        #2 /** LB decision should've be made at this point. */
        meta_q_src.tvalid <= 1'b0;
        meta_q_src.tdata <= 8'hXX; // * No requests coming in.
        meta_q_snk.tready <= 1'b0; // * Force LB to be NOT ready.

        #2 
        meta_q_src.tvalid <= 1'b0;
        meta_q_src.tdata <= 8'hXX; // * No requests coming in.
        meta_q_snk.tready <= 1'b1; // * Let LB be ready.
        // meta_q_snk.tready <= 1'b0; // * Force LB to be NOT ready.

        #2 /** Handling 4th request. */
        meta_q_src.tvalid <= 1'b0;
        meta_q_src.tdata <= 8'hXX; // * No requests coming in.
        // meta_q_snk.tready <= 1'b1; // * Let LB be ready.
        
        region_stats_src <= 32'h90_13_52_71;

        #2 
        meta_q_src.tvalid <= 1'b0;
        meta_q_src.tdata <= 8'hXX; // * No requests coming in.
        #2 
        meta_q_src.tvalid <= 1'b0;
        meta_q_src.tdata <= 8'hXX; // * No requests coming in.


        #2 /** 5th request. */
        meta_q_src.tvalid <= 1'b1;
        meta_q_src.tdata <= 8'hF9;

        region_stats_src <= 32'h91_12_52_70;

        #2 /** LB decision should've be made at this point. */
        meta_q_src.tvalid <= 1'b0;
        meta_q_src.tdata <= 8'hXX; // * No requests coming in.

        
        #2 $finish;
        $stop(0);
    end

    
endmodule
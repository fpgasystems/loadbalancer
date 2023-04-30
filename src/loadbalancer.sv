`timescale 1ns/1ps

`include "queues/queue_stream.sv"
`include "axis_intf.sv"

module loadbalancer #(
    parameter HTTP_DATA_WIDTH = 512,
    parameter HTTP_META_WIDTH = 98, // 48 + 32 + 16
    parameter HTTP_META_META_WIDTH = 48,
    parameter HTTP_METHOD_WIDTH = 32,
    parameter OPERATOR_ID_WIDTH = 16,
    parameter QDEPTH = 16,
    parameter N_REGIONS = 4
) (
    input logic aclk,
    input logic aresetn,
    
    // * Load balancer is on the slave side relative to the HTTP module.
    AXI4S.s meta_in,
    AXI4S.s hdr_in,
    AXI4S.s bdy_in,

    AXI4S.m meta_out,

    input logic [N_REGIONS*2*OPERATOR_ID_WIDTH-1:0] region_stats_in,

    output logic [$clog2(N_REGIONS)-1:0] lb_ctrl
    // output logic[($clog2(N_REGIONS)+OPERATOR_ID_WIDTH)-1:0] pr_ctrl
    
);
    /** Meta queue
        * Push a request into the queue on every posedge. (not considering the queue is full)
        * Pull a request out of the queue if no data is recieved for processing
    */
    logic meta_val_src;
    logic meta_rdy_src;
    logic [HTTP_META_WIDTH-1:0] meta_data;

    queue_stream #(
        .QTYPE(logic[HTTP_META_WIDTH-1:0]),
        .QDEPTH(QDEPTH)
    ) meta_queue (
        .aclk(aclk),
        .aresetn(aresetn),
        // * Enqueue
        .rdy_snk(meta_in.tready),
        .val_snk(meta_in.tvalid),
        .data_snk(meta_in.tdata),
        // * Dequeue
        .val_src(meta_val_src),
        .rdy_src(meta_rdy_src),
        .data_src(meta_data)
    );


    /** Pull status of all regions upon a positive edge.
    */    
    localparam integer LOAD_BITS = $clog2(QDEPTH);
    logic [N_REGIONS-1:0][(OPERATOR_ID_WIDTH+LOAD_BITS)-1:0] region_stats;

    always_ff @( posedge aclk ) begin : update_region_status
        if (aresetn == 1'b0) begin
            region_stats <= '0;
        end else begin
            region_stats <= region_stats_in;
        end
    end

    /** Load balancing logic. 
    */  

    logic [HTTP_META_WIDTH-1:0] meta_data_taken;
    logic meta_received;

    // * Interface with the HTTP module 
    logic [HTTP_METHOD_WIDTH-1:0] http_method;
    logic has_headers;
    logic has_body;
    logic [OPERATOR_ID_WIDTH-1:0] requested_oid;
    // * Little endian: (MSB) [meta_meta, method, hdr, bdy, oid] (LSB)
    assign requested_oid = meta_data_taken[0 +: OPERATOR_ID_WIDTH];
    assign has_body = meta_data_taken[OPERATOR_ID_WIDTH];
    assign has_hdr = meta_data_taken[OPERATOR_ID_WIDTH+1];
    assign http_method = meta_data_taken[(HTTP_META_WIDTH-1) -: HTTP_META_META_WIDTH];
    
    always_ff @( posedge aclk ) begin : load_balance
        if (aresetn == 1'b0) begin
            lb_ctrl <= 'X;
            meta_received <= 1'b0;
        end
        
        if (meta_rdy_src && meta_queue.val_src) begin
            meta_data_taken <= meta_data;
            meta_received <= 1'b1;
        end else begin
            // * Assign values in all branches to prevent meta stability issues.
            meta_received <= 1'b0;
            meta_data_taken <= 'X;
        end
    end

    reg [$clog2(N_REGIONS)-1:0] min_load_vfid = 'X;
    reg [OPERATOR_ID_WIDTH-1:0] last_oid_in_q;
    // ? Why assigning a parameter doesn't work?
    reg [LOAD_BITS-1:0] min_load; // = QDEPTH;
    reg [LOAD_BITS-1:0] cur_load;
    // ? Why doesn't the waveform show the intended behavior of the flag?
    reg lb_flag;

    integer vfid;
    always_comb begin : find_min_load
        min_load = '1;
        lb_flag = 1'b0;
        for (vfid = 0; vfid < N_REGIONS; vfid=vfid+1) begin
            // * [ [(region1): oid, load], [(region2): oid, load] ]
            cur_load = region_stats[vfid][0 +: LOAD_BITS];
            last_oid_in_q = region_stats[vfid][LOAD_BITS +: OPERATOR_ID_WIDTH];

            if (cur_load < min_load) begin
                min_load = cur_load;
                min_load_vfid = vfid;
            end else if (cur_load == min_load && last_oid_in_q == requested_oid) begin
                // * To break ties, prefer a region with requested oid for mitigating cold start
                min_load_vfid = vfid;
            end
        end
        lb_flag = 1'b1;
    end

    // always_ff @( posedge aclk, meta_received ) begin
    always_ff @( posedge aclk ) begin
        if (lb_flag) begin
            lb_ctrl <= min_load_vfid;
            // * TODO: The LB may not always ready whenever the queue has data.
            // * Also, it seems that this signal has a one-cycle delay.
            meta_rdy_src <= ~meta_queue.inst_fifo.is_empty;
        end
    end
    
endmodule : loadbalancer
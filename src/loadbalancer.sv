`timescale 1ns/1ps

`include "queues/queue_stream.sv"

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
    // ? How can I change the data width of the interface while specifying the modport `s`?
    AXI4S.s meta_snk,
    AXI4S.s hdr_snk,
    AXI4S.s bdy_snk,

    input logic [N_REGIONS*2*OPERATOR_ID_WIDTH-1:0] region_stats_in,

    output logic[32-1:0] lb_ctrl,
    output logic[32-1:0] pr_ctrl
);
    /** Meta queue
        * Push a request into the queue on every posedge. (not considering the queue is full)
        * Pull a request out of the queue if no data is recieved for processing
    */
    logic meta_val_src;
    logic meta_rdy_src;
    logic meta_data_received;
    logic [HTTP_META_WIDTH-1:0] meta_data;

    queue_stream #(
        .QTYPE(logic[HTTP_META_WIDTH-1:0]),
        .QDEPTH(QDEPTH)
    ) meta_queue (
        .aclk(aclk),
        .aresetn(aresetn),
        // * Enqueue
        .rdy_snk(meta_snk.tready),
        .val_snk(meta_snk.tvalid),
        .data_snk(meta_snk.tdata),
        // * Dequeue
        .val_src(meta_val_src),
        .rdy_src(meta_rdy_src),
        .data_src(meta_data)
    );

    // TODO: LB may not be able to process data as fast as it receives.
    assign meta_rdy_src = ~meta_queue.inst_fifo.is_empty;

    // always_ff @( posedge aclk ) begin : manage_meta_queue
        // if (aresetn == 1'b0) begin
        //     meta_data_received <= 1'b0;
        // end

        // ? How can I read once and set 
        // if (!meta_data_received) begin
        //     meta_rdy_src <= 1'b1;
        //     // if (meta_queue.val_src && !meta_queue.inst_fifo.is_empty) begin
        //     //     meta_data_received <= 1'b1;
        //     //     // meta_rdy_src <= 0'b0;
        //     // end
        // end 

        // // * Handshake
        // if (meta_rdy_src && meta_queue.val_src) begin
        //     meta_data_received <= 1'b1;
        // end else begin
        //     meta_data_received <= 1'b0;
        // end
    // end
    
    // * Interface with the HTTP module 
    // * {meta_meta, method, hdr, bdy, oid}
    logic [HTTP_METHOD_WIDTH-1:0] http_method;
    logic has_headers;
    logic has_body;
    logic [OPERATOR_ID_WIDTH-1:0] operator_id;
    assign http_method = meta_data[HTTP_META_META_WIDTH +: HTTP_METHOD_WIDTH];
    assign has_headers = meta_data[HTTP_META_META_WIDTH+HTTP_METHOD_WIDTH];
    assign has_body = meta_data[HTTP_META_META_WIDTH+HTTP_METHOD_WIDTH+1];
    assign operator_id = meta_data[HTTP_META_WIDTH-1 -: OPERATOR_ID_WIDTH];

    /** Pull status of all regions.
    */    
    logic[N_REGIONS-1:0][OPERATOR_ID_WIDTH*2-1:0] region_stats;

    always_ff @( posedge aclk ) begin : upate_region_status
        if (aresetn == 1'b01) begin
            int region;
            for (region = 0; region < N_REGIONS; region=region+1) begin
                region_stats[region] = 0;
            end
        end else begin
            int region;
            for (region = 0; region < N_REGIONS; region=region+1) begin
                region_stats[region] <= region_stats_in[region*2 +: OPERATOR_ID_WIDTH];
            end
        end
    end

    /** Load balancing logic. 
    */     
    logic [HTTP_META_WIDTH-1:0] meta_data_taken;
    
    always_ff @( posedge aclk ) begin : load_balance
        if (aresetn == 1'b0) begin
            lb_ctrl <= 32'b0;
            pr_ctrl <= 32'b0;
        end
        
        // TODO: Once reveived a meta (via handshake), send out control signals.
        if (meta_rdy_src && meta_queue.val_src) begin
            meta_data_taken <= meta_data;
        end
    end
    
endmodule : loadbalancer
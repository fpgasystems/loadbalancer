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

    // * Status collected from all region proxies.
    input logic [N_REGIONS*2*OPERATOR_ID_WIDTH-1:0] region_stats_in,

    // * LB decision on to which region the incoming request shoule be forwarded.
    output logic [$clog2(N_REGIONS)-1:0] lb_ctrl

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

    // ! Assume #regions is a power of two number. 
    localparam int N_LAYERS = $clog2(N_REGIONS);
    // * Sum of an arithmetic progression + 1.
    reg [N_LAYERS-1:0][N_LAYERS-1:0][(LOAD_BITS)-1:0] load_comparison_results;
    reg [N_LAYERS-1:0][N_LAYERS-1:0][N_LAYERS-1:0] min_load_vfids;

    
    genvar layer;
    genvar index;
    generate
        for (layer = 0; layer < N_LAYERS; layer++) begin : tree_comparator_layers
            // ? How can I make the following layers sequential?            
            for (index = 0; index < 2**(N_LAYERS-layer); index+=2) begin : comparator_single_layer
                // * Blocks on the same layer can be parallel.
                always_comb begin : load_comparator
                    // * The first layer makes decisions based on the region status (`region_stats`).
                    if (layer == 0) begin
                        if ((region_stats[index][0 +: LOAD_BITS] < region_stats[index+1][0 +: LOAD_BITS])) begin

                            load_comparison_results[layer][index/2] = region_stats[index][0 +: LOAD_BITS];
                            min_load_vfids[layer][index/2] = index;

                        end else if ((region_stats[index][0 +: LOAD_BITS] > region_stats[index+1][0 +: LOAD_BITS])) begin

                            load_comparison_results[layer][index/2] = region_stats[index+1][0 +: LOAD_BITS];
                            min_load_vfids[layer][index/2] = index + 1;
                            
                        end else if ((region_stats[index][0 +: LOAD_BITS] == region_stats[index+1][0 +: LOAD_BITS])) begin

                            if (region_stats[index][LOAD_BITS +: OPERATOR_ID_WIDTH] == requested_oid) begin
                                load_comparison_results[layer][index/2] = region_stats[index][0 +: LOAD_BITS];
                                min_load_vfids[layer][index/2] = index; 
                            end else begin
                                // * Fall back to the second region (index+1).
                                load_comparison_results[layer][index/2] = region_stats[index+1][0 +: LOAD_BITS];
                                min_load_vfids[layer][index/2] = index + 1;
                            end

                        end 

                    // * The following layers make decisions based on results from previous layers (`load_comparison_results`).
                    end else begin
                        if (load_comparison_results[layer-1][index] < load_comparison_results[layer-1][index+1]) begin

                            load_comparison_results[layer][index/2] = load_comparison_results[layer-1][index];
                            min_load_vfids[layer][index/2] = min_load_vfids[layer-1][index];

                        end else if (load_comparison_results[layer-1][index] > load_comparison_results[layer-1][index+1]) begin

                            load_comparison_results[layer][index/2] = load_comparison_results[layer-1][index+1];
                            min_load_vfids[layer][index/2] = min_load_vfids[layer-1][index+1];
                            
                        end else if ((load_comparison_results[layer-1][index] == load_comparison_results[layer-1][index+1])) begin

                            if (min_load_vfids[layer-1][index] == requested_oid) begin
                                load_comparison_results[layer][index/2] = load_comparison_results[layer-1][index];
                                min_load_vfids[layer][index/2] = min_load_vfids[layer-1][index];
                            end else begin
                                // * Fall back to the second region (index+1).
                                load_comparison_results[layer][index/2] = load_comparison_results[layer-1][index+1];
                                min_load_vfids[layer][index/2] = min_load_vfids[layer-1][index+1];
                            end

                        end 
                        
                    end
                end
            end
            
        end
    endgenerate

    // * Set the output lb_ctrl to be the first entry in the last row of the comparison results.
    assign lb_ctrl = min_load_vfids[N_LAYERS-1][0];
    assign meta_rdy_src = ~meta_queue.inst_fifo.is_empty;
    
endmodule : loadbalancer
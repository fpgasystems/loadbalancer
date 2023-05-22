`timescale 1ns/1ps

`include "upcounter.sv"
`include "queues/queue_stream.sv"
`include "interfaces/axis_intf.sv"

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
    AXI4S.s meta_q_in,
    AXI4S.s hdr_q_in,
    AXI4S.s bdy_q_in,

    AXI4S.m meta_q_out,

    // ?
    // AXI4S.m [N_REGIONS-1:0] meta_pxy_outs,
    AXI4S.m proxy_meta_out,


    // * Status collected from all region proxies.
    input logic [N_REGIONS*2*OPERATOR_ID_WIDTH-1:0] region_stats_in,

    // * LB decision on to which region the incoming request shoule be forwarded.
    output logic [$clog2(N_REGIONS)-1:0] lb_ctrl

);

    /** Counter
        * Counts the comparison pipeline stage once it starts.
        * A valid LB decision is available once `max_tick` is reached. 
    */
    localparam int N_LAYERS = $clog2(N_REGIONS);
    // localparam int COUNT_BITS = N_LAYERS - 1;
    logic [N_LAYERS-1:0] count;
    logic enable_counter;
    logic max_tick;

    upcounter #(
        // * E.g., 4 regions -> 2-layer tree -> 2-bit counter: 0,1,2,3(max)
        .COUNT_BITS(N_LAYERS),
        .MAX(N_LAYERS)
    ) counter (
        .clk(aclk),
        .resetn(aresetn),
        .enable(enable_counter),
        .count(count),
        .max_tick(max_tick)
    );

    /** Meta queue
        * Push a received request into the queue on every posedge (done by `stream_queue`).
        * Pull a queued request out and store it in `meta_q_out.tdata`.
    */
    queue_stream #(
        .QTYPE(logic[HTTP_META_WIDTH-1:0]),
        .QDEPTH(QDEPTH)
    ) meta_queue (
        .aclk(aclk),
        .aresetn(aresetn),
        // * Enqueue
        .rdy_snk(meta_q_in.tready),
        .val_snk(meta_q_in.tvalid),
        .data_snk(meta_q_in.tdata),
        // * Dequeue
        .val_src(meta_q_out.tvalid),
        .rdy_src(meta_q_out.tready),
        .data_src(meta_q_out.tdata)
    );


    /** Gets status of all regions.
        ! Assumes that all status come from a single bus.
    */    
    localparam integer LOAD_BITS = $clog2(QDEPTH);
    logic [N_REGIONS-1:0][(OPERATOR_ID_WIDTH+LOAD_BITS)-1:0] region_stats;

    assign region_stats = region_stats_in;

    /** Load balancing logic. 
    */  

    //
    // * Define FSM states
    //
    typedef enum logic [1:0] { IDLE, ACPT, SCHD } LB_STATE;
    LB_STATE current_state, next_state;
    
    always_ff @( posedge aclk ) begin : StateUpdate
        if (aresetn == 1'b0) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    reg enable_counter;
    // ? Why can we assign a register value to wire?
    // ? Why is `counter.enable` a wire?
    assign counter.enable = enable_counter;
    
    always_comb begin : NextState
        case (current_state)
            IDLE: begin
                // * If there's valid data in queue AND counter hasn't started.
                if (meta_queue.val_src == 1'b1 && enable_counter == 1'b0) begin
                    next_state = ACPT;
                end else begin
                    next_state = IDLE;
                end
            end
            ACPT: begin
                // * If clock has started.
                if (enable_counter == 1'b1) begin
                    next_state = SCHD;
                    // * Stop pulling new meta while scheduling the current one.
                    meta_q_out.tready = 1'b0;
                    
                    // * Start counter.
                    // counter.enable = 1'b1;
                end else begin
                    next_state = ACPT;
                    // * Ready to pull out a piece of new meta data from `meta_qeueu`.
                    meta_q_out.tready = 1'b1;

                    // counter.enable = 1'b0;
                end
            end
            SCHD: begin
                // * Detected a valid handshake between LB and the destined proxy.
                // ! Error: 'lb_ctrl' is not a constant
                // if (counter.max_tick == 1'b1 && meta_pxy_outs[lb_ctrl].tready == 1'b1) begin
                if (layer == N_LAYERS && proxy_meta_out.tready == 1'b1) begin
                    next_state = IDLE;
                    // counter.enable = 1'b0;
                end else begin
                    next_state = SCHD;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    logic [HTTP_META_WIDTH-1:0] meta_data_taken;
    // * Interface with the HTTP module 
    logic [HTTP_METHOD_WIDTH-1:0] http_method;
    logic has_headers;
    logic has_body;
    logic [OPERATOR_ID_WIDTH-1:0] requested_oid;
    // * Little endian: (MSB) [meta_meta, method, has_headers, has_body, oid] (LSB)
    assign requested_oid = meta_data_taken[0 +: OPERATOR_ID_WIDTH];
    assign has_body = meta_data_taken[OPERATOR_ID_WIDTH];
    assign has_hdr = meta_data_taken[OPERATOR_ID_WIDTH+1];
    assign http_method = meta_data_taken[(HTTP_META_WIDTH-1) -: HTTP_META_META_WIDTH];
    
    logic [N_LAYERS-1:0] layer;
    // * Stores the least loads of the previous layers.
    // * The 1st layer of comparison needs log(#regions) of slots.
    // * The following layers use logarithmically less slots -> overwrite the buffer.
    logic [N_LAYERS-1:0][LOAD_BITS-1:0] load_comparison_results;
    // * Stores the vFIDs of least-loaded regions of the previous layers.
    logic [N_LAYERS-1:0][N_LAYERS-1:0] min_load_vfids;

    always_ff @(posedge aclk) begin: LoadBalancingOutput
        if (aresetn == 1'b0) begin
            enable_counter <= 1'b0;
            meta_data_taken <= 'X;
            lb_ctrl <= 'X;
            layer <= '0;
            load_comparison_results <= 'X;
            min_load_vfids <= 'X;
        end else begin
            case (current_state)
                IDLE: begin
                    // * Disable counter when idling.
                    enable_counter <= 1'b0;

                    meta_data_taken <= 'X;
                    lb_ctrl <= 'X;
                    layer <= '0;
                    load_comparison_results <= 'X;
                    min_load_vfids <= 'X;
                end
                    
                ACPT: begin
                    // * Start counter once accepting a request from the queue.
                    // * We don't start the counter at SCHD since it has 1 cycle delay.
                    enable_counter <= 1'b1;
                    // * Only pull the data upon a valid handshake. Otherwise the data could be invalid.
                    if (meta_queue.val_src == 1'b1 && meta_q_out.tready == 1'b1) begin
                        // * Accept a piece of meta from the queue.
                        meta_data_taken <= meta_q_out.tdata;
                    end
                end

                SCHD: begin
                    // * Use counter to locate the next layer at which comparisons should be carried out.
                    layer <= counter.count;
                    
                    if (layer == 0) begin
                        // * Deal with data from `region_stats`.
                        for (int index = 0; index < N_REGIONS; index += 2) begin
                            if ((region_stats[index][0 +: LOAD_BITS] < region_stats[index+1][0 +: LOAD_BITS])) begin

                                load_comparison_results[index/2] <= region_stats[index][0 +: LOAD_BITS];
                                min_load_vfids[index/2] <= index;

                            end else if ((region_stats[index][0 +: LOAD_BITS] > region_stats[index+1][0 +: LOAD_BITS])) begin

                                load_comparison_results[index/2] <= region_stats[index+1][0 +: LOAD_BITS];
                                min_load_vfids[index/2] <= index + 1;
                                
                            end else if (region_stats[index][0 +: LOAD_BITS] == region_stats[index+1][0 +: LOAD_BITS]) begin
                                // * Break ties.
                                if (region_stats[index][LOAD_BITS +: OPERATOR_ID_WIDTH] == requested_oid) begin
                                    load_comparison_results[index/2] <= region_stats[index][0 +: LOAD_BITS];
                                    min_load_vfids[index/2] <= index; 
                                end else begin
                                    // * Fall back to the second region (index+1).
                                    load_comparison_results[index/2] <= region_stats[index+1][0 +: LOAD_BITS];
                                    min_load_vfids[index/2] <= index + 1;
                                end

                            end                             
                        end
                    end else if (layer < N_LAYERS) begin
                        // * Deal with data in the buffer from previous results.
                        for (int index = 0; index < 2**(N_LAYERS-layer); index += 2) begin
                            if (load_comparison_results[index] < load_comparison_results[index+1]) begin
                                // * Overwrite the buffer after use.
                                load_comparison_results[index/2] <= load_comparison_results[index];
                                min_load_vfids[index/2] <= min_load_vfids[index];

                            end else if (load_comparison_results[index] > load_comparison_results[index+1]) begin

                                load_comparison_results[index/2] <= load_comparison_results[index+1];
                                min_load_vfids[index/2] <= min_load_vfids[index+1];
                                
                            end else if (load_comparison_results[index] == load_comparison_results[index+1]) begin
                                
                                // ! Check region status with `vfid=min_load_vfids[index]`.
                                if (region_stats[ min_load_vfids[index] ][LOAD_BITS +: OPERATOR_ID_WIDTH] == requested_oid) begin
                                    load_comparison_results[index/2] <= load_comparison_results[index];
                                    min_load_vfids[index/2] <= min_load_vfids[index];
                                end else begin
                                    // * Fall back to the second region (index+1).
                                    load_comparison_results[index/2] <= load_comparison_results[index+1];
                                    min_load_vfids[index/2] <= min_load_vfids[index+1];
                                end

                            end 
                        end
                    end
                    else begin
                        MaxTick: assert (counter.max_tick == 1'b1) else $error("Assertion MaxTick failed!");
                        // * Output decision.
                        lb_ctrl <= min_load_vfids[0];
                        // ! Do NOT clear the results YET, 
                        // ! since LB may need to hold on to that value until a valid handshake with the proxy.
                        // load_comparison_results <= 'X;
                        // min_load_vfids <= 'X;
                    end
                end

                default: begin
                    enable_counter <= 1'b0;
                    meta_data_taken <= 'X;
                    lb_ctrl <= 'X;
                    layer <= '0;
                    load_comparison_results <= 'X;
                    min_load_vfids <= 'X;
                end
            endcase
        end
        
    end


    

    // always_ff @( posedge aclk ) begin : pull_meta_data
    //     if (meta_q_out.tready && meta_queue.val_src) begin
    //         meta_received <= 1'b1;
    //         meta_data_taken <= meta_q_out.tdata;
    //     end 
    // end

    // // always_ff @( posedge aclk ) begin : load_balance
    // //     if (aresetn == 1'b0) begin
    // //         lb_ctrl <= 'X;
    // //         meta_received <= 1'b0;
    // //     end
        
    // //     if (meta_q_out.tready && meta_queue.val_src) begin
    // //         meta_received <= 1'b1;
    // //         meta_data_taken <= meta_q_out.tdata;
    // //     end 
    // //     else begin
    // //         // * Assign values in all branches to prevent meta stability issues.
    // //         meta_received <= 1'b0;
    // //         // meta_data_taken <= 'X;
    // //     end
    // // end

    // // ! Assume #regions is a power of two number. 
    // // * Sum of an arithmetic progression + 1.
    // logic [N_LAYERS-1:0][N_LAYERS-1:0][(LOAD_BITS)-1:0] load_comparison_results;
    // logic [N_LAYERS-1:0][N_LAYERS-1:0][N_LAYERS-1:0] min_load_vfids;

    
    // genvar layer;
    // genvar index;
    // generate
    //     for (layer = 0; layer < N_LAYERS; layer++) begin : tree_comparator_layers
    //         // ? How can I make the following layers sequential?            
    //         for (index = 0; index < 2**(N_LAYERS-layer); index+=2) begin : comparator_single_layer
    //             // * Blocks on the same layer can be parallel.
    //             always_comb begin : load_comparator
    //                 // * The first layer makes decisions based on the region status (`region_stats`).
    //                 if (layer == 0) begin
    //                     if ((region_stats[index][0 +: LOAD_BITS] < region_stats[index+1][0 +: LOAD_BITS])) begin

    //                         load_comparison_results[layer][index/2] = region_stats[index][0 +: LOAD_BITS];
    //                         min_load_vfids[layer][index/2] = index;

    //                     end else if ((region_stats[index][0 +: LOAD_BITS] > region_stats[index+1][0 +: LOAD_BITS])) begin

    //                         load_comparison_results[layer][index/2] = region_stats[index+1][0 +: LOAD_BITS];
    //                         min_load_vfids[layer][index/2] = index + 1;
                            
    //                     end else if (region_stats[index][0 +: LOAD_BITS] == region_stats[index+1][0 +: LOAD_BITS]) begin

    //                         if (region_stats[index][LOAD_BITS +: OPERATOR_ID_WIDTH] == requested_oid) begin
    //                             load_comparison_results[layer][index/2] = region_stats[index][0 +: LOAD_BITS];
    //                             min_load_vfids[layer][index/2] = index; 
    //                         end else begin
    //                             // * Fall back to the second region (index+1).
    //                             load_comparison_results[layer][index/2] = region_stats[index+1][0 +: LOAD_BITS];
    //                             min_load_vfids[layer][index/2] = index + 1;
    //                         end

    //                     end 

    //                 // * The following layers make decisions based on results from previous layers (`load_comparison_results`).
    //                 end else begin
    //                     if (load_comparison_results[layer-1][index] < load_comparison_results[layer-1][index+1]) begin

    //                         load_comparison_results[layer][index/2] = load_comparison_results[layer-1][index];
    //                         min_load_vfids[layer][index/2] = min_load_vfids[layer-1][index];

    //                     end else if (load_comparison_results[layer-1][index] > load_comparison_results[layer-1][index+1]) begin

    //                         load_comparison_results[layer][index/2] = load_comparison_results[layer-1][index+1];
    //                         min_load_vfids[layer][index/2] = min_load_vfids[layer-1][index+1];
                            
    //                     end else if (load_comparison_results[layer-1][index] == load_comparison_results[layer-1][index+1]) begin
                            
    //                         // ! Check region status with `vfid=min_load_vfids[layer-1][index]`.
    //                         if (region_stats[ min_load_vfids[layer-1][index] ][LOAD_BITS +: OPERATOR_ID_WIDTH] == requested_oid) begin
    //                             load_comparison_results[layer][index/2] = load_comparison_results[layer-1][index];
    //                             min_load_vfids[layer][index/2] = min_load_vfids[layer-1][index];
    //                         end else begin
    //                             // * Fall back to the second region (index+1).
    //                             load_comparison_results[layer][index/2] = load_comparison_results[layer-1][index+1];
    //                             min_load_vfids[layer][index/2] = min_load_vfids[layer-1][index+1];
    //                         end

    //                     end 
                        
    //                 end
    //             end
    //         end
            
    //     end
    // endgenerate

    // // * Set the output lb_ctrl to be the first entry in the last row of the comparison results.
    // assign lb_ctrl = (meta_received)? min_load_vfids[N_LAYERS-1][0] : 'X;
    // // assign lb_ctrl = min_load_vfids[N_LAYERS-1][0];

    // // * Let LB be ready whenever there's valid
    // assign meta_q_out.tready = ~meta_queue.inst_fifo.is_full;
    
endmodule : loadbalancer
module JAM (
    input CLK,
    input RST,
    output reg [2:0] W,
    output reg [2:0] J,
    input [6:0] Cost,
    output reg [3:0] MatchCount,
    output reg [9:0] MinCost,
    output reg Valid
);

    reg [2:0] curr_J [0:7];
    reg [2:0] next_J [0:7];

    // Permutation Engine Variables
    integer i;
    reg [2:0] pivot;
    reg [2:0] K;    // pivot_idx
    reg [2:0] swap_idx;

    // Combinational Logic for Next Permutation
    always @(*) begin
        //========================================================
        // Step 1: Initialize
        //========================================================
        for(i=0; i<=7; i=i+1) next_J[i] = curr_J[i];
        
        //========================================================
        // Step 2: Find pivot
        //========================================================
        if      (curr_J[6] < curr_J[7]) K = 6;
        else if (curr_J[5] < curr_J[6]) K = 5;
        else if (curr_J[4] < curr_J[5]) K = 4;
        else if (curr_J[3] < curr_J[4]) K = 3;
        else if (curr_J[2] < curr_J[3]) K = 2;
        else if (curr_J[1] < curr_J[2]) K = 1;
        else if (curr_J[0] < curr_J[1]) K = 0;
        else K = 7;     // Not found (End of Permutations)
        
        // Prevent Latches
        pivot = 0;
        swap_idx = 0;

        //========================================================
        // Step 3: Swap & Step 4: Reverse (Only if K found)
        //========================================================
        if (K < 7) begin
            pivot = curr_J[K];
            
            // Find the smallest element greater than pivot to the right
            for(i=0; i<=7; i=i+1) begin
                if(i > K) begin
                    if (curr_J[i] > pivot) begin
                        swap_idx = i[2:0];
                    end
                end
            end
            
            // Execute Swap
            next_J[K] = curr_J[swap_idx];
            next_J[swap_idx]  = curr_J[K];
            
            // Execute Reverse
            case (K)
                7,6: ; // Only one element left, no reverse needed
                5: {next_J[6], next_J[7]} = {next_J[7], next_J[6]};
                4: {next_J[5], next_J[6], next_J[7]} = {next_J[7], next_J[6], next_J[5]};
                3: {next_J[4], next_J[5], next_J[6], next_J[7]} = {next_J[7], next_J[6], next_J[5], next_J[4]};
                2: {next_J[3], next_J[4], next_J[5], next_J[6], next_J[7]} = {next_J[7], next_J[6], next_J[5], next_J[4], next_J[3]};
                1: {next_J[2], next_J[3], next_J[4], next_J[5], next_J[6], next_J[7]} = {next_J[7], next_J[6], next_J[5], next_J[4], next_J[3], next_J[2]};
                0: {next_J[1], next_J[2], next_J[3], next_J[4], next_J[5], next_J[6], next_J[7]} = {next_J[7], next_J[6], next_J[5], next_J[4], next_J[3], next_J[2], next_J[1]};
            endcase
        end
    end

    //================================================================
    // Sequential Logic (FSM & Datapath)
    //================================================================
    reg [6:0] Cost_reg [0:7]; // Cost Cache
    
    reg [1:0] state;
    reg [3:0] cnt;           // Counter for ROM access
    // reg [3:0] start_idx;  // Removed: Unused in Async version
    
    integer j; // Separate iterator for sequential logic

    // States
    parameter S_READ   = 0;
    parameter S_CALC   = 1;
    parameter S_FINISH = 2;

    // Total Cost Adder
    wire [9:0] current_total_cost;
    assign current_total_cost = Cost_reg[0] + Cost_reg[1] + Cost_reg[2] + Cost_reg[3] + 
                                Cost_reg[4] + Cost_reg[5] + Cost_reg[6] + Cost_reg[7];

    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            state <= S_READ;
            cnt <= 0;
            MinCost <= 10'd1023;
            MatchCount <= 1;
            Valid <= 0;
            
            // Initial Permutation: 0,1,2,3,4,5,6,7
            curr_J[0]<=0; curr_J[1]<=1; curr_J[2]<=2; curr_J[3]<=3;
            curr_J[4]<=4; curr_J[5]<=5; curr_J[6]<=6; curr_J[7]<=7;
            
            for(j=0; j<=7; j=j+1) Cost_reg[j] <= 0;

        end else begin
            case (state)
                S_READ: begin
                    //--- Async ROM Access ---
                    // Cost is valid immediately for current W (which is cnt)
                    // We only need to update the registers that correspond to the changed workers (from K to 7)
                    if (cnt <= 7) begin
                         Cost_reg[cnt] <= Cost;
                    end

                    // Count until 7, then switch to CALC
                    if (cnt == 7) begin
                        state <= S_CALC;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end

                S_CALC: begin
                    // 1. Update MinCost
                    if (current_total_cost < MinCost) begin
                        MinCost <= current_total_cost;
                        MatchCount <= 1;
                    end else if (current_total_cost == MinCost) begin
                        MatchCount <= MatchCount + 1;
                    end

                    // 2. Check Finish
                    if (K == 7) begin
                        Valid <= 1;
                        state <= S_FINISH;
                    end else begin
                        // 3. Update Permutation
                        for(j=0; j<=7; j=j+1) curr_J[j] <= next_J[j];
                        
                        // 4. Setup next read (Optimization)
                        // Directly set cnt to K. 
                        // Cost_reg[0] to Cost_reg[K-1] will retain their values (Data Reuse)
                        cnt <= {1'b0, K}; 
                        
                        state <= S_READ;
                    end
                end

                S_FINISH: begin
                    Valid <= 0;
                end
            endcase
        end
    end

    //================================================================
    // Output Logic
    //================================================================
    always @(*) begin
        if (cnt <= 7) begin
            W = cnt[2:0];
            J = curr_J[cnt];
        end else begin
            W = 0; 
            J = 0;
        end
    end

endmodule
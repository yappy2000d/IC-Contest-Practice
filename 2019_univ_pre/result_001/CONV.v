`timescale 1ns/10ps

module CONV(
    input         clk,
    input         reset,
    output reg    busy,    
    input         ready,    
            
    output reg [11:0] iaddr,
    input signed [19:0] idata,    
    
    output reg        cwr,
    output reg [11:0] caddr_wr,
    output reg [19:0] cdata_wr,
    
    output reg        crd,
    output reg [11:0] caddr_rd,
    input  [19:0] cdata_rd,
    
    output reg [2:0]  csel
);

// ==========================================
// 1. 權重與 Bias 宣告
// ==========================================
localparam signed [19:0] w0 = 20'h0A89E;
localparam signed [19:0] w1 = 20'h092D5;
localparam signed [19:0] w2 = 20'h06D43;
localparam signed [19:0] w3 = 20'h01004;
localparam signed [19:0] w4 = 20'hF8F71;
localparam signed [19:0] w5 = 20'hF6E54;
localparam signed [19:0] w6 = 20'hFA6D7;
localparam signed [19:0] w7 = 20'hFC834;
localparam signed [19:0] w8 = 20'hFAC19;
localparam signed [19:0] bias = 20'h01310;

wire signed [39:0] bias_40 = { {4{bias[19]}}, bias, 16'd0 };

// ==========================================
// 2. 狀態與座標暫存器
// ==========================================
localparam IDLE = 0, L0_PROC = 1, FLUSH_L0 = 2, L1_PROC = 3, DONE = 4;
reg [2:0] state;

reg [4:0] l1_x, l1_y; 
reg signed [19:0] max_val; 

reg signed [7:0] col_x, out_y; 
reg [2:0] step;
reg signed [39:0] feature [0:2]; 
reg valid_data; 

// ==========================================
// 3. SRAM 管線化預判斷與偷跑邏輯
// ==========================================
wire signed [7:0] req_y = (step == 0) ? out_y - 1 :
                          (step == 1) ? out_y     :
                                        out_y + 1 ;
wire valid_req = (col_x >= 0 && col_x <= 63 && req_y >= 0 && req_y <= 63);

wire signed [7:0] next_col_x = (col_x == 64) ? -1 : (col_x + 1);
wire signed [7:0] next_out_y = (col_x == 64) ? (out_y + 1) : out_y;
wire signed [7:0] next_req_y = next_out_y - 1; 
wire next_valid_req = (next_col_x >= 0 && next_col_x <= 63 && next_req_y >= 0 && next_req_y <= 63);

// ==========================================
// 4. 通用乘法器與暫存器
// ==========================================
reg signed [19:0] cur_data_reg; 
reg signed [19:0] w_left, w_mid, w_right; 

wire signed [39:0] mult_left  = cur_data_reg * w_left;
wire signed [39:0] mult_mid   = cur_data_reg * w_mid;
wire signed [39:0] mult_right = cur_data_reg * w_right;

wire signed [39:0] f0_next = feature[0] + mult_left;
wire signed [39:0] f1_next = feature[1] + mult_mid;
wire signed [39:0] f2_next = feature[2] + mult_right;

// ==========================================
// ★ 5. Write Buffer (斬斷時序瓶頸的神器) ★
// ==========================================
reg signed [39:0] out_buffer;
reg [11:0]        out_addr_buffer;
reg               out_valid;

// ==========================================
// 6. 主狀態機 (FSM)
// ==========================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        busy <= 0; state <= IDLE;
        cwr <= 0; csel <= 3'b000; crd <= 0;
        iaddr <= 0; caddr_wr <= 0; cdata_wr <= 0; caddr_rd <= 0;
        col_x <= 0; out_y <= 0; step <= 0; valid_data <= 0;
        l1_x <= 0; l1_y <= 0; max_val <= 0;
        cur_data_reg <= 0;
        w_left <= 0; w_mid <= 0; w_right <= 0;
        
        feature[0] <= bias_40; feature[1] <= bias_40; feature[2] <= bias_40;
        out_valid <= 0; out_buffer <= 0; out_addr_buffer <= 0;
    end else begin
        cur_data_reg <= valid_data ? idata : 20'd0; 
        
        case(state)
            IDLE: begin
                if (ready) begin
                    busy <= 1; 
                    state <= L0_PROC;
                    col_x <= -1; out_y <= 0; step <= 0;
                    cwr <= 0; crd <= 0;
                    feature[0] <= bias_40; feature[1] <= bias_40; feature[2] <= bias_40;
                    out_valid <= 0;
                end
            end
            
            L0_PROC: begin
                // ========================================================
                // ★ 獨立的 Write Buffer 寫出邏輯 (保證不會被 step 跳躍漏掉) ★
                // ========================================================
                if (out_valid) begin
                    csel <= 3'b001; 
                    cwr <= 1;
                    caddr_wr <= out_addr_buffer;
                    // 同時完成四捨五入與 ReLU
                    cdata_wr <= (out_buffer > 0) ? (out_buffer[35:16] + out_buffer[15]) : 20'd0;
                    out_valid <= 0; // 寫完自動清空
                end else begin
                    cwr <= 0;
                end
                
                case(step)
                    0: begin
                        iaddr <= valid_req ? (req_y * 64 + col_x) : 12'd0;
                        valid_data <= valid_req; 
                        step <= 1;
                    end
                    1: begin
                        iaddr <= valid_req ? (req_y * 64 + col_x) : 12'd0;
                        valid_data <= valid_req; 
                        w_left <= w2; w_mid <= w1; w_right <= w0;
                        step <= 2;
                    end
                    2: begin
                        iaddr <= valid_req ? (req_y * 64 + col_x) : 12'd0;
                        valid_data <= valid_req; 
                        w_left <= w5; w_mid <= w4; w_right <= w3;
                        feature[0] <= feature[0] + mult_left;
                        feature[1] <= feature[1] + mult_mid;
                        feature[2] <= feature[2] + mult_right;
                        step <= 3;
                    end
                    3: begin
                        w_left <= w8; w_mid <= w7; w_right <= w6;
                        feature[0] <= feature[0] + mult_left;
                        feature[1] <= feature[1] + mult_mid;
                        feature[2] <= feature[2] + mult_right;
                        step <= 4;
                    end
                    4: begin
                        // ★ 算好的特徵值丟入 Buffer，下一個 cycle 就會自動被上面的邏輯寫出
                        if (col_x >= 1) begin
                            out_buffer <= f0_next;
                            out_addr_buffer <= out_y * 64 + (col_x - 1);
                            out_valid <= 1;
                        end else begin
                            out_valid <= 0;
                        end
                        
                        feature[0] <= f1_next;
                        feature[1] <= f2_next;
                        feature[2] <= bias_40;
                        
                        col_x <= next_col_x;
                        out_y <= next_out_y;
                        
                        if (col_x == 64 && out_y == 63) begin
                            state <= FLUSH_L0; 
                        end else begin
                            iaddr <= next_valid_req ? (next_req_y * 64 + next_col_x) : 12'd0;
                            valid_data <= next_valid_req; 
                            step <= 1; 
                        end
                    end
                endcase
            end
            
            FLUSH_L0: begin
                if (out_valid) begin
                    csel <= 3'b001; 
                    cwr <= 1;
                    caddr_wr <= out_addr_buffer;
                    cdata_wr <= (out_buffer > 0) ? (out_buffer[35:16] + out_buffer[15]) : 20'd0;
                    out_valid <= 0;
                end else begin
                    cwr <= 0;
                    state <= L1_PROC;
                    l1_x <= 0; l1_y <= 0; step <= 0;
                end
            end
            
            L1_PROC: begin
                csel <= 3'b001; crd <= 1; cwr <= 0;       
                case(step)
                    0: begin
                        caddr_rd <= {l1_y, 1'b0} * 64 + {l1_x, 1'b0};
                        step <= 1;
                    end
                    1: begin
                        caddr_rd <= {l1_y, 1'b0} * 64 + {l1_x, 1'b0} + 1;
                        max_val <= cdata_rd; 
                        step <= 2;
                    end
                    2: begin
                        caddr_rd <= ({l1_y, 1'b0} + 1) * 64 + {l1_x, 1'b0};
                        if ($signed(cdata_rd) > $signed(max_val)) max_val <= cdata_rd;
                        step <= 3;
                    end
                    3: begin
                        caddr_rd <= ({l1_y, 1'b0} + 1) * 64 + {l1_x, 1'b0} + 1;
                        if ($signed(cdata_rd) > $signed(max_val)) max_val <= cdata_rd;
                        step <= 4;
                    end
                    4: begin
                        crd <= 0; 
                        csel <= 3'b011; cwr <= 1;
                        caddr_wr <= l1_y * 32 + l1_x;
                        cdata_wr <= ($signed(cdata_rd) > $signed(max_val)) ? cdata_rd : max_val;

                        if (l1_x == 31) begin
                            l1_x <= 0;
                            if (l1_y == 31) begin
                                state <= DONE; 
                            end else begin
                                l1_y <= l1_y + 1;
                            end
                        end else begin
                            l1_x <= l1_x + 1;
                        end
                        step <= 0; 
                    end
                endcase
            end
            
            DONE: begin
                busy <= 0; 
                state <= IDLE;
            end
        endcase
    end
end

endmodule

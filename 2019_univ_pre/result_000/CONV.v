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
// 1. 權重與 Bias 宣告 (常數摺疊架構)
// ==========================================
localparam signed [19:0] w0 = 20'h0A89E, w1 = 20'h092D5, w2 = 20'h06D43;
localparam signed [19:0] w3 = 20'h01004, w4 = 20'hF8F71, w5 = 20'hF6E54;
localparam signed [19:0] w6 = 20'hFA6D7, w7 = 20'hFC834, w8 = 20'hFAC19;
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
// 3. 預計算邏輯 (為了 Pre-fetch 偷跑)
// ==========================================
// 預測下一個座標點
wire signed [7:0] next_col_x = (col_x == 64) ? -1 : (col_x + 1);
wire signed [7:0] next_out_y = (col_x == 64) ? (out_y + 1) : out_y;
// 下一點的地址判斷
wire next_valid_req = (next_col_x >= 0 && next_col_x <= 63 && (next_out_y-1) >= 0 && (next_out_y-1) <= 63);

// ==========================================
// 4. 常數乘法網路與 Pipeline Register
// ==========================================
reg signed [19:0] cur_data_reg;

// 9 組平行常數乘法，雖然面積比通用版大，但組合邏輯深度最淺
wire signed [39:0] m0 = cur_data_reg * w0, m1 = cur_data_reg * w1, m2 = cur_data_reg * w2;
wire signed [39:0] m3 = cur_data_reg * w3, m4 = cur_data_reg * w4, m5 = cur_data_reg * w5;
wire signed [39:0] m6 = cur_data_reg * w6, m7 = cur_data_reg * w7, m8 = cur_data_reg * w8;

// 下一個 Cycle 的累加值 (已包含 Bias 預載，所以這就是最終結果)
wire signed [39:0] f0_next = feature[0] + m8;
wire signed [39:0] f1_next = feature[1] + m7;
wire signed [39:0] f2_next = feature[2] + m6;

// ==========================================
// 5. Write Buffer (解決 Data-Dependent 時序違例)
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
        iaddr <= 0; caddr_wr <= 0; cdata_wr <= 0;
        col_x <= 0; out_y <= 0; step <= 0; valid_data <= 0;
        feature[0] <= 0; feature[1] <= 0; feature[2] <= 0;
        out_valid <= 0; cur_data_reg <= 0;
    end else begin
        // Pipeline 入口：永遠比 iaddr 晚一拍接收資料
        cur_data_reg <= valid_data ? idata : 20'd0; 
        
        case(state)
            IDLE: begin
                if (ready) begin
                    busy <= 1; state <= L0_PROC;
                    col_x <= -1; out_y <= 0; step <= 0;
                    cwr <= 0; crd <= 0; out_valid <= 0;
                    // 初始化時即預載 Bias
                    feature[0] <= bias_40; feature[1] <= bias_40; feature[2] <= bias_40;
                end
            end
            
            L0_PROC: begin
                // --- 獨立寫入塊：確保資料不被 FSM 跳轉吃掉 ---
                if (out_valid) begin
                    csel <= 3'b001; cwr <= 1;
                    caddr_wr <= out_addr_buffer;
                    cdata_wr <= (out_buffer > 0) ? (out_buffer[35:16] + out_buffer[15]) : 20'd0;
                    out_valid <= 0;
                end else begin
                    cwr <= 0;
                end
                
                case(step)
                    0: begin // 僅在開始時執行，請求 (y-1, x) 的 Top 地址
                        iaddr <= (out_y > 0 && col_x >= 0 && col_x <= 63) ? ((out_y-1)*64 + col_x) : 12'd0;
                        valid_data <= (out_y > 0 && col_x >= 0 && col_x <= 63);
                        step <= 1;
                    end
                    1: begin // 請求 (y, x) 的 Mid 地址
                        iaddr <= (col_x >= 0 && col_x <= 63) ? (out_y*64 + col_x) : 12'd0;
                        valid_data <= (col_x >= 0 && col_x <= 63);
                        step <= 2;
                    end
                    2: begin // 請求 (y+1, x) 的 Bot 地址，並累加 Top 資料
                        iaddr <= (out_y < 63 && col_x >= 0 && col_x <= 63) ? ((out_y+1)*64 + col_x) : 12'd0;
                        valid_data <= (out_y < 63 && col_x >= 0 && col_x <= 63);
                        feature[0] <= feature[0] + m2;
                        feature[1] <= feature[1] + m1;
                        feature[2] <= feature[2] + m0;
                        step <= 3;
                    end
                    3: begin // 累加 Mid 資料
                        feature[0] <= feature[0] + m5;
                        feature[1] <= feature[1] + m4;
                        feature[2] <= feature[2] + m3;
                        step <= 4;
                    end
                    4: begin // 累加 Bot 資料並「預抓取」下一點的 Top 地址
                        if (col_x >= 1) begin
                            out_buffer <= f0_next; // f0_next 包含 Bot + 之前的累積
                            out_addr_buffer <= out_y * 64 + (col_x - 1);
                            out_valid <= 1;
                        end
                        // 平移暫存器並預載下一個 Bias
                        feature[0] <= f1_next;
                        feature[1] <= f2_next;
                        feature[2] <= bias_40;
                        
                        col_x <= next_col_x;
                        out_y <= next_out_y;
                        
                        if (col_x == 64 && out_y == 63) begin
                            state <= FLUSH_L0; 
                        end else begin
                            // ★ 修復點：在這裡發送地址後，step 1 不應覆蓋它
                            iaddr <= next_valid_req ? ((next_out_y - 1) * 64 + next_col_x) : 12'd0;
                            valid_data <= next_valid_req; 
                            step <= 1; 
                        end
                    end
                endcase
            end
            
            FLUSH_L0: begin
                if (out_valid) begin
                    csel <= 3'b001; cwr <= 1;
                    caddr_wr <= out_addr_buffer;
                    cdata_wr <= (out_buffer > 0) ? (out_buffer[35:16] + out_buffer[15]) : 20'd0;
                    out_valid <= 0;
                end else begin
                    cwr <= 0; state <= L1_PROC;
                    l1_x <= 0; l1_y <= 0; step <= 0;
                end
            end
            
            L1_PROC: begin
                csel <= 3'b001; crd <= 1; cwr <= 0;       
                case(step)
                    0: begin caddr_rd <= {l1_y, 1'b0} * 64 + {l1_x, 1'b0}; step <= 1; end
                    1: begin caddr_rd <= {l1_y, 1'b0} * 64 + {l1_x, 1'b0} + 1; max_val <= cdata_rd; step <= 2; end
                    2: begin caddr_rd <= ({l1_y, 1'b0} + 1) * 64 + {l1_x, 1'b0}; if ($signed(cdata_rd) > $signed(max_val)) max_val <= cdata_rd; step <= 3; end
                    3: begin caddr_rd <= ({l1_y, 1'b0} + 1) * 64 + {l1_x, 1'b0} + 1; if ($signed(cdata_rd) > $signed(max_val)) max_val <= cdata_rd; step <= 4; end
                    4: begin
                        crd <= 0; csel <= 3'b011; cwr <= 1;
                        caddr_wr <= l1_y * 32 + l1_x;
                        cdata_wr <= ($signed(cdata_rd) > $signed(max_val)) ? cdata_rd : max_val;
                        if (l1_x == 31) begin
                            l1_x <= 0;
                            if (l1_y == 31) state <= DONE; else l1_y <= l1_y + 1;
                        end else l1_x <= l1_x + 1;
                        step <= 0; 
                    end
                endcase
            end
            
            DONE: begin busy <= 0; state <= IDLE; end
            default: state <= IDLE;
        endcase
    end
end

endmodule
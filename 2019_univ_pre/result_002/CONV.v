`timescale 1ns/10ps

module CONV(
    input              clk,
    input              reset,
    output reg         busy,    
    input              ready,    
            
    output reg [11:0]  iaddr,
    input signed [19:0] idata,    
    
    output reg         cwr,
    output reg [11:0]  caddr_wr,
    output reg [19:0]  cdata_wr,
    
    output reg         crd,
    output reg [11:0]  caddr_rd,
    input [19:0]       cdata_rd,
    
    output reg [2:0]   csel
);

    // ===============================================================
    // 1. 常數與權重宣告 (Weights & Bias)
    // ===============================================================
    localparam signed [19:0] w0 = 20'h0A89E, w1 = 20'h092D5, w2 = 20'h06D43;
    localparam signed [19:0] w3 = 20'h01004, w4 = 20'hF8F71, w5 = 20'hF6E54;
    localparam signed [19:0] w6 = 20'hFA6D7, w7 = 20'hFC834, w8 = 20'hFAC19;
    localparam signed [19:0] bias = 20'h01310;

    // 將 Bias 擴展至 40-bit 並左移 16 位以對齊定點數格式
    wire signed [39:0] bias_40 = { {4{bias[19]}}, bias, 16'd0 };

    // ===============================================================
    // 2. 狀態與暫存器定義
    // ===============================================================
    localparam IDLE     = 3'd0;
    localparam L0_PROC  = 3'd1; // Layer 0: Convolution + ReLU
    localparam FLUSH_L0 = 3'd2; // 清空最後一個 Write Buffer
    localparam L1_PROC  = 3'd3; // Layer 1: Max Pooling
    localparam DONE     = 3'd4;

    reg [2:0] state;
    reg [2:0] step;
    reg signed [7:0] col_x, out_y; 

    // 運算相關暫存器
    reg signed [39:0] feature [0:2]; 
    reg signed [19:0] max_val;
    reg               valid_data;
    reg signed [19:0] cur_data_reg;

    // Write Buffer: 用於平衡運算流水線與記憶體寫入
    reg signed [19:0] out_buffer; 
    reg [11:0]        out_addr_buffer;
    reg               out_valid;

    // ===============================================================
    // 3. 資源共享乘法器 (Resource Sharing Multipliers)
    // ===============================================================
    reg signed [19:0] wl, wm, wr;   
    wire signed [39:0] ml = cur_data_reg * wl;
    wire signed [39:0] mm = cur_data_reg * wm;
    wire signed [39:0] mr = cur_data_reg * wr;
    wire signed [39:0] res = feature[0] + ml;

    // ===============================================================
    // 4. 輔助控制邏輯 (Combinational Logic)
    // ===============================================================
    wire signed [7:0] next_col_x = (col_x == 64) ? 8'shFF : (col_x + 8'd1);
    wire signed [7:0] next_out_y = (col_x == 64) ? (out_y + 8'd1) : out_y;
    
    // 安全判定：利用 next_out_y 和 next_col_x 判定邊界
    wire next_v_top = (next_out_y != 0) && (!next_col_x[7]) && (!next_col_x[6]);

    // ===============================================================
    // 5. 主狀態機 (FSM)
    // ===============================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy        <= 0;
            state       <= IDLE;
            cwr         <= 0;
            csel        <= 3'b000;
            crd         <= 0;
            col_x       <= 0;
            out_y       <= 0;
            step        <= 0;
            valid_data  <= 0;
            feature[0]  <= 0; feature[1] <= 0; feature[2] <= 0;
            out_valid   <= 0;
            cur_data_reg <= 0;
        end else begin
            // 讀取資料流水線
            cur_data_reg <= valid_data ? idata : 20'd0;
            
            case(state)
                IDLE: begin
                    if (ready) begin
                        busy    <= 1;
                        state   <= L0_PROC;
                        col_x   <= -1;
                        out_y   <= 0;
                        step    <= 0;
                        feature[0] <= bias_40;
                        feature[1] <= bias_40;
                        feature[2] <= bias_40;
                        cwr     <= 0;
                        crd     <= 0;
                        out_valid <= 0;
                    end
                end
                
                L0_PROC: begin
                    // --- Write Buffer 處理 ---
                    if (out_valid) begin
                        csel     <= 3'b001; 
                        cwr      <= 1;
                        caddr_wr <= out_addr_buffer;
                        cdata_wr <= out_buffer;
                        out_valid <= 0;
                    end else begin
                        cwr <= 0;
                    end
                    
                    // --- 捲積步進處理 ---
                    case(step)
                        0: begin 
                            iaddr <= (out_y != 0 && !col_x[7] && !col_x[6]) ? 
                                     (((out_y-8'd1) << 6) + col_x) : 0; 
                            valid_data <= (out_y != 0 && !col_x[7] && !col_x[6]); 
                            step <= 1;
                        end
                        1: begin 
                            iaddr <= (!col_x[7] && !col_x[6]) ? 
                                     ((out_y << 6) + col_x) : 0; 
                            valid_data <= (!col_x[7] && !col_x[6]); 
                            wl <= w2; wm <= w1; wr <= w0;
                            step <= 2;
                        end
                        2: begin 
                            iaddr <= (out_y != 63 && !col_x[7] && !col_x[6]) ? 
                                     (((out_y+8'd1) << 6) + col_x) : 0; 
                            valid_data <= (out_y != 63 && !col_x[7] && !col_x[6]); 
                            wl <= w5; wm <= w4; wr <= w3;
                            feature[0] <= feature[0] + ml; 
                            feature[1] <= feature[1] + mm; 
                            feature[2] <= feature[2] + mr;
                            step <= 3;
                        end
                        3: begin 
                            wl <= w8; wm <= w7; wr <= w6;
                            feature[0] <= feature[0] + ml; 
                            feature[1] <= feature[1] + mm;
                            feature[2] <= feature[2] + mr; 
                            step <= 4;
                        end
                        4: begin 
                            if (!col_x[7] && col_x != 0) begin
                                out_buffer <= (res > 0) ? (res[35:16] + res[15]) : 20'd0; 
                                out_addr_buffer <= (out_y << 6) + (col_x - 1); 
                                out_valid <= 1;
                            end
                            feature[0] <= feature[1] + mm;
                            feature[1] <= feature[2] + mr; 
                            feature[2] <= bias_40;
                            
                            col_x <= next_col_x; 
                            out_y <= next_out_y;
                            if (col_x == 64 && out_y == 63) state <= FLUSH_L0;
                            else begin 
                                iaddr <= next_v_top ? (((next_out_y-8'd1) << 6) + next_col_x) : 0;
                                valid_data <= next_v_top; 
                                step <= 1;
                            end
                        end
                    endcase
                end
                
                FLUSH_L0: begin
                    if (out_valid) begin 
                        csel     <= 3'b001; 
                        cwr      <= 1; 
                        caddr_wr <= out_addr_buffer; 
                        cdata_wr <= out_buffer; 
                        out_valid <= 0;
                    end else begin
                        cwr   <= 0; 
                        state <= L1_PROC; 
                        col_x <= 0; 
                        out_y <= 0; 
                        step  <= 0;
                    end
                end
                
                L1_PROC: begin 
                    csel <= 3'b001; crd <= 1; cwr <= 0;       
                    case(step)
                        0: begin 
                            caddr_rd <= {out_y[4:0], 1'b0, 6'd0} + {col_x[4:0], 1'b0};
                            step <= 1; 
                        end
                        1: begin 
                            caddr_rd <= (out_y[4:0] << 7) + (col_x[4:0] << 1) + 1;
                            max_val <= cdata_rd; 
                            step <= 2; 
                        end
                        2: begin 
                            caddr_rd <= {({out_y[4:0], 1'b0} + 1), col_x[4:0], 1'b0}; 
                            if ($signed(cdata_rd) > $signed(max_val)) max_val <= cdata_rd; 
                            step <= 3; 
                        end
                        3: begin 
                            caddr_rd <= {({out_y[4:0], 1'b0} + 1), col_x[4:0], 1'b0} + 1;
                            if ($signed(cdata_rd) > $signed(max_val)) max_val <= cdata_rd; 
                            step <= 4; 
                        end
                        4: begin
                            crd  <= 0; 
                            csel <= 3'b011; 
                            cwr  <= 1;
                            caddr_wr <= {out_y[4:0], col_x[4:0]};
                            cdata_wr <= ($signed(cdata_rd) > $signed(max_val)) ? cdata_rd : max_val;
                            
                            if (col_x == 31) begin
                                col_x <= 0; 
                                if (out_y == 31) state <= DONE; 
                                else out_y <= out_y + 1;
                            end else begin
                                col_x <= col_x + 1;
                            end
                            step <= 0; 
                        end
                    endcase
                end
                
                DONE: begin 
                    busy  <= 0; 
                    state <= IDLE; 
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
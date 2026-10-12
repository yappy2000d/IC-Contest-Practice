module SET ( clk , rst, en, central, radius, mode, busy, valid, candidate );

input clk, rst;
input en;
input [23:0] central;
input [11:0] radius;
input [1:0] mode;
output reg busy;
output reg valid;
output reg [7:0] candidate;

reg [23:0] central_r;
reg [11:0] radius_r;
reg [1:0] mode_r;

// 座標計數器 (1~8)
reg [3:0] x_cnt, y_cnt; 

// =========================================================
// 1. 解壓縮與參數 (Unpack)
// =========================================================
wire [3:0] ax, ay, bx, by, cx, cy;
wire [3:0] ra, rb, rc;

assign ax = central_r[23:20]; assign ay = central_r[19:16]; 
assign bx = central_r[15:12]; assign by = central_r[11:8]; 
assign cx = central_r[7:4];   assign cy = central_r[3:0];
assign ra = radius_r[11:8];
assign rb = radius_r[7:4];
assign rc = radius_r[3:0];

// =========================================================
// 2. 單點幾何運算 (Single Point Geometry Logic)
//    這裡完全沒有 Loop，只做一次運算
// =========================================================
reg is_in_a, is_in_b, is_in_c; 
reg point_match; // 目前這個點是否符合 Mode

reg [7:0] ra2, rb2, rc2; 
reg [8:0] sum_sq_a, sum_sq_b, sum_sq_c; // 9-bit 避免溢位

always @(*) begin
    // 計算半徑平方
    ra2 = square(ra);
    rb2 = square(rb);
    rc2 = square(rc);
    
    // 計算 A 圓 (只算目前 x_cnt, y_cnt 這個點)
    sum_sq_a = {1'b0, square(diff_abs(x_cnt, ax))} + {1'b0, square(diff_abs(y_cnt, ay))};
    is_in_a  = (sum_sq_a <= {1'b0, ra2});

    // 計算 B 圓
    sum_sq_b = {1'b0, square(diff_abs(x_cnt, bx))} + {1'b0, square(diff_abs(y_cnt, by))};
    is_in_b  = (sum_sq_b <= {1'b0, rb2});

    // 計算 C 圓
    sum_sq_c = {1'b0, square(diff_abs(x_cnt, cx))} + {1'b0, square(diff_abs(y_cnt, cy))};
    is_in_c  = (sum_sq_c <= {1'b0, rc2});

    // Mode 判斷
    case (mode_r)
        2'b00: point_match = is_in_a;
        2'b01: point_match = is_in_a & is_in_b;
        2'b10: point_match = is_in_a ^ is_in_b;
        2'b11: point_match = ( (is_in_a & is_in_b) | (is_in_b & is_in_c) | (is_in_c & is_in_a) ) & ~(is_in_a & is_in_b & is_in_c);
    endcase
end

// =========================================================
// 3. 控制與累加邏輯 (Control & Accumulator)
// =========================================================
always @(posedge clk, posedge rst) begin
    if(rst) begin
        busy <= 0;
        valid <= 0;
        candidate <= 0;
        central_r <= 0;
        radius_r <= 0;
        mode_r <= 0;
        x_cnt <= 1; // 座標從 1 開始
        y_cnt <= 1;
    end
    else begin
        if(en) begin
            busy <= 1;
            valid <= 0;
            candidate <= 0;
            central_r <= central;
            radius_r <= radius;
            mode_r <= mode;
            x_cnt <= 1; // Reset 座標
            y_cnt <= 1;
        end
        else if (busy) begin
            // 累加分數
            if (point_match) begin
                candidate <= candidate + 1;
            end

            // 座標移動邏輯 (類似巢狀迴圈)
            if (x_cnt == 4'd8) begin
                x_cnt <= 1;
                if (y_cnt == 4'd8) begin
                    // 算完 (8,8) 了
                    busy <= 0;
                    valid <= 1;
                end
                else begin
                    y_cnt <= y_cnt + 1;
                end
            end
            else begin
                x_cnt <= x_cnt + 1;
            end
        end
        else begin
            valid <= 0;
        end
    end
end

// =========================================================
// Functions
// =========================================================
function [3:0] diff_abs;
    input [3:0] c1, c2;
    begin
        diff_abs = (c1 > c2) ? (c1 - c2) : (c2 - c1);
    end
endfunction

function [7:0] square;
    input [3:0] in;
    begin
        case(in)
            4'd0:  square = 8'd0;
            4'd1:  square = 8'd1;
            4'd2:  square = 8'd4;
            4'd3:  square = 8'd9;
            4'd4:  square = 8'd16;
            4'd5:  square = 8'd25;
            4'd6:  square = 8'd36;
            4'd7:  square = 8'd49;
            4'd8:  square = 8'd64;
            4'd9:  square = 8'd81;
            4'd10: square = 8'd100;
            4'd11: square = 8'd121;
            4'd12: square = 8'd144;
            4'd13: square = 8'd169;
            4'd14: square = 8'd196;
            4'd15: square = 8'd225;
            default: square = 8'd0;
        endcase
    end
endfunction

endmodule
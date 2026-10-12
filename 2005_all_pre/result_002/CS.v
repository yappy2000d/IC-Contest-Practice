`timescale 1ns/10ps
/*
 * IC Contest Computational System (CS) - The Ultimate Hybrid Version
 * 1. Sequential Path: sum truncated to 11-bit.
 * 2. Combinational Path: Pre-compute diff (13-bit signed) to isolate late-arriving X.
 * 3. Output Path: Equivalent math truncation (10-bit adder) to save output area.
*/
// module CS(Y, X, reset, clk);
//     input clk, reset; 
//     input [7:0] X;
//     output [9:0] Y;

//     reg [7:0] XS [1:8]; 
//     // 【優點結合 1】 255*8 = 2040，sum 極限只需 11 bits (省 1 個 FF 與部分加法邏輯)
//     reg [10:0] sum;

//     // base_sum 配合降為 11 bits
//     wire [10:0] base_sum = sum - {3'd0, XS[1]};

//     always @(posedge clk or posedge reset) begin
//         if(reset) begin
//             XS[1] <= 8'd0; XS[2] <= 8'd0; XS[3] <= 8'd0; XS[4] <= 8'd0;
//             XS[5] <= 8'd0; XS[6] <= 8'd0; XS[7] <= 8'd0; XS[8] <= 8'd0;
//             sum <= 11'd0;
//         end else begin
//             XS[1] <= XS[2]; XS[2] <= XS[3]; XS[3] <= XS[4]; XS[4] <= XS[5];
//             XS[5] <= XS[6]; XS[6] <= XS[7]; XS[7] <= XS[8]; XS[8] <= X;     
//             sum <= base_sum + {3'd0, X}; 
//         end
//     end

//     // 【優點結合 2】 保留減法移項！讓 DC 用最小面積的 Adder 去慢慢算這 8 個門檻值
//     // 注意：sum 現在是 11 bits，所以補 2'b0 擴充成 13 bits signed
//     wire signed [12:0] diff1 = $signed({1'b0, ({4'd0, XS[1]}<<3) + {4'd0, XS[1]}}) - $signed({2'b0, sum});
//     wire signed [12:0] diff2 = $signed({1'b0, ({4'd0, XS[2]}<<3) + {4'd0, XS[2]}}) - $signed({2'b0, sum});
//     wire signed [12:0] diff3 = $signed({1'b0, ({4'd0, XS[3]}<<3) + {4'd0, XS[3]}}) - $signed({2'b0, sum});
//     wire signed [12:0] diff4 = $signed({1'b0, ({4'd0, XS[4]}<<3) + {4'd0, XS[4]}}) - $signed({2'b0, sum});
//     wire signed [12:0] diff5 = $signed({1'b0, ({4'd0, XS[5]}<<3) + {4'd0, XS[5]}}) - $signed({2'b0, sum});
//     wire signed [12:0] diff6 = $signed({1'b0, ({4'd0, XS[6]}<<3) + {4'd0, XS[6]}}) - $signed({2'b0, sum});
//     wire signed [12:0] diff7 = $signed({1'b0, ({4'd0, XS[7]}<<3) + {4'd0, XS[7]}}) - $signed({2'b0, sum});
//     wire signed [12:0] diff8 = $signed({1'b0, ({4'd0, XS[8]}<<3) + {4'd0, XS[8]}}) - $signed({2'b0, sum});

//     // 晚來的 X (負緣到達) 直接進入純比較器，不經過加減法
//     wire [7:0] c1 = ($signed({5'b0, X}) >= diff1) ? XS[1] : 8'b0;
//     wire [7:0] c2 = ($signed({5'b0, X}) >= diff2) ? XS[2] : 8'b0;
//     wire [7:0] c3 = ($signed({5'b0, X}) >= diff3) ? XS[3] : 8'b0;
//     wire [7:0] c4 = ($signed({5'b0, X}) >= diff4) ? XS[4] : 8'b0;
//     wire [7:0] c5 = ($signed({5'b0, X}) >= diff5) ? XS[5] : 8'b0;
//     wire [7:0] c6 = ($signed({5'b0, X}) >= diff6) ? XS[6] : 8'b0;
//     wire [7:0] c7 = ($signed({5'b0, X}) >= diff7) ? XS[7] : 8'b0;
//     wire [7:0] c8 = ($signed({5'b0, X}) >= diff8) ? XS[8] : 8'b0;
//     // sum 除以 8 (右移 3 位)，直接取 sum 的高 8 位 [10:3] 即可，省去移位器
//     wire [7:0] c9 = (X <= sum[10:3])              ? X     : 8'b0;

//     // 平行二元樹 MUX Tree 
//     wire [7:0] m12 = (c1 > c2) ? c1 : c2;
//     wire [7:0] m34 = (c3 > c4) ? c3 : c4;
//     wire [7:0] m56 = (c5 > c6) ? c5 : c6;
//     wire [7:0] m78 = (c7 > c8) ? c7 : c8;
//     wire [7:0] m1234 = (m12 > m34) ? m12 : m34;
//     wire [7:0] m5678 = (m56 > m78) ? m56 : m78;
//     wire [7:0] m1_to_8 = (m1234 > m5678) ? m1234 : m5678;
//     wire [7:0] Xappr   = (m1_to_8 > c9)  ? m1_to_8 : c9;

//     // 【優點結合 3】 拔除肥大的 13-bit Y_full，使用極簡的 10-bit 輸出加法
//     wire [11:0] cur_sum = {1'b0, sum} + {4'd0, X};
//     wire [11:0] sum_Xappr = cur_sum + {4'd0, Xappr};
//     // 取高位元 (除以 8)，加上 Xappr (最高只需 10-bit 加法器)
//     assign Y = {1'b0, sum_Xappr[11:3]} + {2'b0, Xappr};

// endmodule

module CS(Y, X, reset, clk);
    input clk, reset; 
    input [7:0] X;
    output [9:0] Y;

    reg [7:0] XS [1:8];
    reg [10:0] sum;
    reg [7:0] Xr;

    wire [10:0] base_sum = sum - {3'd0, XS[1]};

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            Xr <= 8'd0;
            XS[1] <= 8'd0; XS[2] <= 8'd0; XS[3] <= 8'd0; XS[4] <= 8'd0;
            XS[5] <= 8'd0; XS[6] <= 8'd0; XS[7] <= 8'd0; XS[8] <= 8'd0;
            sum <= 11'd0;
        end else begin
            Xr <= X;
            XS[1] <= XS[2]; XS[2] <= XS[3]; XS[3] <= XS[4]; XS[4] <= XS[5];
            XS[5] <= XS[6]; XS[6] <= XS[7]; XS[7] <= XS[8]; XS[8] <= Xr;     
            sum <= base_sum + {3'd0, Xr}; 
        end
    end

    wire signed [12:0] diff1 = $signed({1'b0, ({4'd0, XS[1]}<<3) + {4'd0, XS[1]}}) - $signed({2'b0, sum});
    wire signed [12:0] diff2 = $signed({1'b0, ({4'd0, XS[2]}<<3) + {4'd0, XS[2]}}) - $signed({2'b0, sum});
    wire signed [12:0] diff3 = $signed({1'b0, ({4'd0, XS[3]}<<3) + {4'd0, XS[3]}}) - $signed({2'b0, sum});
    wire signed [12:0] diff4 = $signed({1'b0, ({4'd0, XS[4]}<<3) + {4'd0, XS[4]}}) - $signed({2'b0, sum});
    wire signed [12:0] diff5 = $signed({1'b0, ({4'd0, XS[5]}<<3) + {4'd0, XS[5]}}) - $signed({2'b0, sum});
    wire signed [12:0] diff6 = $signed({1'b0, ({4'd0, XS[6]}<<3) + {4'd0, XS[6]}}) - $signed({2'b0, sum});
    wire signed [12:0] diff7 = $signed({1'b0, ({4'd0, XS[7]}<<3) + {4'd0, XS[7]}}) - $signed({2'b0, sum});
    wire signed [12:0] diff8 = $signed({1'b0, ({4'd0, XS[8]}<<3) + {4'd0, XS[8]}}) - $signed({2'b0, sum});

    wire [7:0] c1 = ($signed({5'b0, Xr}) >= diff1) ? XS[1] : 8'b0;
    wire [7:0] c2 = ($signed({5'b0, Xr}) >= diff2) ? XS[2] : 8'b0;
    wire [7:0] c3 = ($signed({5'b0, Xr}) >= diff3) ? XS[3] : 8'b0;
    wire [7:0] c4 = ($signed({5'b0, Xr}) >= diff4) ? XS[4] : 8'b0;
    wire [7:0] c5 = ($signed({5'b0, Xr}) >= diff5) ? XS[5] : 8'b0;
    wire [7:0] c6 = ($signed({5'b0, Xr}) >= diff6) ? XS[6] : 8'b0;
    wire [7:0] c7 = ($signed({5'b0, Xr}) >= diff7) ? XS[7] : 8'b0;
    wire [7:0] c8 = ($signed({5'b0, Xr}) >= diff8) ? XS[8] : 8'b0;
    
    wire [7:0] c9 = (Xr <= sum[10:3]) ? Xr : 8'b0;

    wire [7:0] m12 = (c1 > c2) ? c1 : c2;
    wire [7:0] m34 = (c3 > c4) ? c3 : c4;
    wire [7:0] m56 = (c5 > c6) ? c5 : c6;
    wire [7:0] m78 = (c7 > c8) ? c7 : c8;
    wire [7:0] m1234 = (m12 > m34) ? m12 : m34;
    wire [7:0] m5678 = (m56 > m78) ? m56 : m78;
    wire [7:0] m1_to_8 = (m1234 > m5678) ? m1234 : m5678;
    wire [7:0] Xappr   = (m1_to_8 > c9)  ? m1_to_8 : c9;

    wire [11:0] cur_sum = {1'b0, sum} + {4'd0, Xr};
    wire [11:0] sum_Xappr = cur_sum + {4'd0, Xappr};
    assign Y = {1'b0, sum_Xappr[11:3]} + {2'b0, Xappr};

endmodule

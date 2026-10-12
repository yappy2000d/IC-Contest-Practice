`timescale 1ns/10ps
/*
 * IC Contest Computational System (CS)
*/
module CS(Y, X, reset, clk);

input clk, reset; 
input [7:0] X;
output [9:0] Y;

reg [7:0] XS [1:9];    // X Series
reg [11:0] sum;        // sum of X Series

// caculate average
wire [7:0] Xavg;
assign Xavg = sum / 9;

// find approximate
reg [7:0] Xappr;
reg [7:0] Xappr_tmp1;
reg [7:0] Xappr_tmp2;
reg [7:0] Xappr_tmp3;
reg [7:0] max_tmp;

always @(*) begin
    Xappr_tmp1 = 8'b0;
    Xappr_tmp2 = 8'b0;
    Xappr_tmp3 = 8'b0;
    
    Xappr_tmp1 = (Xavg >= XS[1] && XS[1] > Xappr_tmp1)? XS[1] : Xappr_tmp1;
    Xappr_tmp1 = (Xavg >= XS[2] && XS[2] > Xappr_tmp1)? XS[2] : Xappr_tmp1;
    Xappr_tmp1 = (Xavg >= XS[3] && XS[3] > Xappr_tmp1)? XS[3] : Xappr_tmp1;
    
    Xappr_tmp2 = (Xavg >= XS[4] && XS[4] > Xappr_tmp2)? XS[4] : Xappr_tmp2;
    Xappr_tmp2 = (Xavg >= XS[5] && XS[5] > Xappr_tmp2)? XS[5] : Xappr_tmp2;
    Xappr_tmp2 = (Xavg >= XS[6] && XS[6] > Xappr_tmp2)? XS[6] : Xappr_tmp2;
    
    Xappr_tmp3 = (Xavg >= XS[7] && XS[7] > Xappr_tmp3)? XS[7] : Xappr_tmp3;
    Xappr_tmp3 = (Xavg >= XS[8] && XS[8] > Xappr_tmp3)? XS[8] : Xappr_tmp3;
    Xappr_tmp3 = (Xavg >= XS[9] && XS[9] > Xappr_tmp3)? XS[9] : Xappr_tmp3;
    
    max_tmp = (Xappr_tmp1 > Xappr_tmp2)? Xappr_tmp1: Xappr_tmp2;
    Xappr = (Xappr_tmp3 > max_tmp)? Xappr_tmp3: max_tmp;
end

// caculate output
assign Y = ( (sum + Xappr) >> 3 ) + Xappr;

// input
always @(posedge clk or posedge reset) begin
    if(reset) begin
        XS[1] <= 8'b0;
        XS[2] <= 8'b0;
        XS[3] <= 8'b0;
        XS[4] <= 8'b0;
        XS[5] <= 8'b0;
        XS[6] <= 8'b0;
        XS[7] <= 8'b0;
        XS[8] <= 8'b0;
        XS[9] <= 8'b0;
        sum <= 'd0;
    end
    else begin
        // shift left
        XS[1] <= XS[2];
        XS[2] <= XS[3];
        XS[3] <= XS[4];
        XS[4] <= XS[5];
        XS[5] <= XS[6];
        XS[6] <= XS[7];
        XS[7] <= XS[8];
        XS[8] <= XS[9];
        XS[9] <= X;
        
        sum <= sum + (X - XS[1]);
    end
end
 
endmodule

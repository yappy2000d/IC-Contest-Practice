module CS(
    input clk,
    input reset,
    input [7:0] X,
    output [9:0] Y
);

reg [7:0] XS [1:9];    // X Series

// caculate average
wire [7:0] Xavg;
assign Xavg = ( XS[1] + XS[2] + XS[3]
              + XS[4] + XS[5] + XS[6]
              + XS[7] + XS[8] + XS[9] ) / 9;

// find approximate
reg [7:0] Xappr;
always @(*) begin
    Xappr = 8'b0;
    Xappr = (Xavg >= XS[1] && XS[1] > Xappr)? XS[1] : Xappr;
    Xappr = (Xavg >= XS[2] && XS[2] > Xappr)? XS[2] : Xappr;
    Xappr = (Xavg >= XS[3] && XS[3] > Xappr)? XS[3] : Xappr;
    Xappr = (Xavg >= XS[4] && XS[4] > Xappr)? XS[4] : Xappr;
    Xappr = (Xavg >= XS[5] && XS[5] > Xappr)? XS[5] : Xappr;
    Xappr = (Xavg >= XS[6] && XS[6] > Xappr)? XS[6] : Xappr;
    Xappr = (Xavg >= XS[7] && XS[7] > Xappr)? XS[7] : Xappr;
    Xappr = (Xavg >= XS[8] && XS[8] > Xappr)? XS[8] : Xappr;
    Xappr = (Xavg >= XS[9] && XS[9] > Xappr)? XS[9] : Xappr;
end

// caculate output
assign Y = ( XS[1] + Xappr
           + XS[2] + Xappr
           + XS[3] + Xappr
           + XS[4] + Xappr
           + XS[5] + Xappr
           + XS[6] + Xappr
           + XS[7] + Xappr
           + XS[8] + Xappr
           + XS[9] + Xappr ) / 8;

// input
always @(posedge clk or posedge reset) begin
    if(reset) begin
        XS[1] <= 8'b0; XS[2] <= 8'b0; XS[3] <= 8'b0;
        XS[4] <= 8'b0; XS[5] <= 8'b0; XS[6] <= 8'b0;
        XS[7] <= 8'b0; XS[8] <= 8'b0; XS[9] <= 8'b0;
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
    end
end

endmodule

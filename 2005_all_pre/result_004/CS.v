module CS(Y, X, reset, clk);
    input clk, reset; 
    input [7:0] X;
    output [9:0] Y;

    // keep Y at 0 while reset is asserted so it does not settle X->value near a clock edge
    wire valid = ~reset;

    // X[1]~X[9]: the 9 most recent inputs, all registered
    reg [7:0] XS [1:9];
    reg [11:0] S [1:9];             // S[i] = 9*XS[i]
    reg [11:0] sum;                 // sum = XS[1] + ... + XS[9]

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            XS[1] <= 8'd0; XS[2] <= 8'd0; XS[3] <= 8'd0; XS[4] <= 8'd0; XS[5] <= 8'd0;
            XS[6] <= 8'd0; XS[7] <= 8'd0; XS[8] <= 8'd0; XS[9] <= 8'd0;
            sum <= 12'd0;
            S[1] <= 12'd0; S[2] <= 12'd0; S[3] <= 12'd0; S[4] <= 12'd0; S[5] <= 12'd0;
            S[6] <= 12'd0; S[7] <= 12'd0; S[8] <= 12'd0; S[9] <= 12'd0;
        end else begin
            XS[1] <= XS[2]; XS[2] <= XS[3]; XS[3] <= XS[4]; XS[4] <= XS[5]; XS[5] <= XS[6];
            XS[6] <= XS[7]; XS[7] <= XS[8]; XS[8] <= XS[9]; XS[9] <= X;
            sum <= sum - {4'd0, XS[1]} + {4'd0, X};
            S[1] <= S[2]; S[2] <= S[3]; S[3] <= S[4]; S[4] <= S[5]; S[5] <= S[6];
            S[6] <= S[7]; S[7] <= S[8]; S[8] <= S[9]; S[9] <= ({4'd0, X} << 3) + {4'd0, X};
        end
    end


    wire [7:0] c1 = (S[1] <= sum) ? XS[1] : 8'b0;
    wire [7:0] c2 = (S[2] <= sum) ? XS[2] : 8'b0;
    wire [7:0] c3 = (S[3] <= sum) ? XS[3] : 8'b0;
    wire [7:0] c4 = (S[4] <= sum) ? XS[4] : 8'b0;
    wire [7:0] c5 = (S[5] <= sum) ? XS[5] : 8'b0;
    wire [7:0] c6 = (S[6] <= sum) ? XS[6] : 8'b0;
    wire [7:0] c7 = (S[7] <= sum) ? XS[7] : 8'b0;
    wire [7:0] c8 = (S[8] <= sum) ? XS[8] : 8'b0;
    wire [7:0] c9 = (S[9] <= sum) ? XS[9] : 8'b0;

    wire [7:0] m12 = (c1 > c2) ? c1 : c2;
    wire [7:0] m34 = (c3 > c4) ? c3 : c4;
    wire [7:0] m56 = (c5 > c6) ? c5 : c6;
    wire [7:0] m78 = (c7 > c8) ? c7 : c8;
    wire [7:0] m1234 = (m12 > m34) ? m12 : m34;
    wire [7:0] m5678 = (m56 > m78) ? m56 : m78;
    wire [7:0] m1_to_8 = (m1234 > m5678) ? m1234 : m5678;
    wire [7:0] Xappr   = (m1_to_8 > c9)  ? m1_to_8 : c9;

    // Y = (sum + 9*Xappr) / 8, one 3-operand add
    wire [12:0] ysum = {1'b0, sum} + {5'b0, Xappr} + {2'b0, Xappr, 3'b0};
    wire [9:0] Ycomb = ysum[12:3];
    assign Y = valid ? Ycomb : 10'd0;

endmodule

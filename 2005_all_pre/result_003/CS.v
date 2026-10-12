`timescale 1ns/10ps

module CS(Y, X, reset, clk);
    input clk, reset; 
    input [7:0] X;
    output [9:0] Y;

    reg [3:0] cnt;
    always @(posedge clk or posedge reset)
        if (reset) cnt <= 4'd0;
        else if (cnt != 4'd9) cnt <= cnt + 4'd1;
    wire valid = (cnt == 4'd9);

    // X[1]~X[9]: the 9 most recent inputs, all registered
    reg [7:0] XS [1:9];
    reg [11:0] sum;                 // sum = XS[1] + ... + XS[9]

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            XS[1] <= 8'd0; XS[2] <= 8'd0; XS[3] <= 8'd0; XS[4] <= 8'd0; XS[5] <= 8'd0;
            XS[6] <= 8'd0; XS[7] <= 8'd0; XS[8] <= 8'd0; XS[9] <= 8'd0;
            sum <= 12'd0;
        end else begin
            XS[1] <= XS[2]; XS[2] <= XS[3]; XS[3] <= XS[4]; XS[4] <= XS[5]; XS[5] <= XS[6];
            XS[6] <= XS[7]; XS[7] <= XS[8]; XS[8] <= XS[9]; XS[9] <= X;
            sum <= sum - {4'd0, XS[1]} + {4'd0, X};
        end
    end

    // XS[i] <= avg  <=>  9*XS[i] <= sum
    wire [11:0] s1 = ({4'd0, XS[1]} << 3) + {4'd0, XS[1]};
    wire [11:0] s2 = ({4'd0, XS[2]} << 3) + {4'd0, XS[2]};
    wire [11:0] s3 = ({4'd0, XS[3]} << 3) + {4'd0, XS[3]};
    wire [11:0] s4 = ({4'd0, XS[4]} << 3) + {4'd0, XS[4]};
    wire [11:0] s5 = ({4'd0, XS[5]} << 3) + {4'd0, XS[5]};
    wire [11:0] s6 = ({4'd0, XS[6]} << 3) + {4'd0, XS[6]};
    wire [11:0] s7 = ({4'd0, XS[7]} << 3) + {4'd0, XS[7]};
    wire [11:0] s8 = ({4'd0, XS[8]} << 3) + {4'd0, XS[8]};
    wire [11:0] s9 = ({4'd0, XS[9]} << 3) + {4'd0, XS[9]};

    wire [7:0] c1 = (s1 <= sum) ? XS[1] : 8'b0;
    wire [7:0] c2 = (s2 <= sum) ? XS[2] : 8'b0;
    wire [7:0] c3 = (s3 <= sum) ? XS[3] : 8'b0;
    wire [7:0] c4 = (s4 <= sum) ? XS[4] : 8'b0;
    wire [7:0] c5 = (s5 <= sum) ? XS[5] : 8'b0;
    wire [7:0] c6 = (s6 <= sum) ? XS[6] : 8'b0;
    wire [7:0] c7 = (s7 <= sum) ? XS[7] : 8'b0;
    wire [7:0] c8 = (s8 <= sum) ? XS[8] : 8'b0;
    wire [7:0] c9 = (s9 <= sum) ? XS[9] : 8'b0;

    wire [7:0] m12 = (c1 > c2) ? c1 : c2;
    wire [7:0] m34 = (c3 > c4) ? c3 : c4;
    wire [7:0] m56 = (c5 > c6) ? c5 : c6;
    wire [7:0] m78 = (c7 > c8) ? c7 : c8;
    wire [7:0] m1234 = (m12 > m34) ? m12 : m34;
    wire [7:0] m5678 = (m56 > m78) ? m56 : m78;
    wire [7:0] m1_to_8 = (m1234 > m5678) ? m1234 : m5678;
    wire [7:0] Xappr   = (m1_to_8 > c9)  ? m1_to_8 : c9;

    // Y = (sum + 9*Xappr) / 8 = (sum + Xappr)/8 + Xappr
    wire [11:0] sum_Xappr = sum + {4'd0, Xappr};
    wire [9:0] Ycomb = {1'b0, sum_Xappr[11:3]} + {2'b0, Xappr};
    assign Y = valid ? Ycomb : 10'd0;

endmodule

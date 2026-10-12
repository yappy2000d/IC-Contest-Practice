module CTE_YUVtoRGB ( clk, rst, in_en, yuv_in, busy, out_valid, rgb_out );
    input  clk;
    input  rst;
    input  in_en;
    output reg busy;
    output reg out_valid;
    input  [7:0]  yuv_in;
    output reg [23:0] rgb_out; // 保持 reg，在時序邏輯中鎖存輸出

    localparam S0 = 0;  // GET_U_DATA
    localparam S1 = 1;  // GET_Y_DATA_1
    localparam S2 = 2;  // GET_V_DATA
    localparam S3 = 3;  // CAL_RESULT_1
    localparam S4 = 4;  // OUT_RESULT_1
    localparam S5 = 5;  // GET_Y_DATA_2
    localparam S6 = 6;  // CAL_RESULT_2
    localparam S7 = 7;  // OUT_RESULT_2

    reg [2:0] CS, NS;
    reg signed [12:0] extend_U, extend_Y, extend_V;

    always @(posedge clk or posedge rst) begin
        if (rst) CS <= S0;
        else CS <= NS;
    end

    always @(*) begin
        case(CS)
            S0: NS = in_en ? S1 : S0;
            S1: NS = S2;
            S2: NS = S3;
            S3: NS = S4;
            S4: NS = S5;
            S5: NS = S6;
            S6: NS = S7;
            S7: NS = S0;
            default: NS = S0;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            extend_U <= 13'd0;
            extend_Y <= 13'd0;
            extend_V <= 13'd0;
        end else begin
            case(CS)
                S0:     extend_U <= $signed(yuv_in);
                S1:     extend_Y <= {5'd0, yuv_in};
                S2:     extend_V <= $signed(yuv_in);
                S5:     extend_Y <= {5'd0, yuv_in};
            endcase
        end
    end

    // R = Y + 1.625*V = Y + (1+0.5+0.125)V
	// G = Y - 0.25*U - 0.75*V = Y - 0.25*U - (0.5+0.25)*V
	// B = Y + 2*U
    wire signed [12:0] extend_R = (extend_Y <<< 3) + extend_V + (extend_V <<< 2) + (extend_V <<< 3);
    wire signed [12:0] extend_G = (extend_Y <<< 3) - (extend_U <<< 1) - (extend_V <<< 2) - (extend_V <<< 1);
    wire signed [12:0] extend_B = extend_Y + (extend_U <<< 1);

    // 四捨五入與算術右移還原
    wire signed [12:0] R_val = (extend_R + 13'sd4) >>> 3;
    wire signed [12:0] G_val = (extend_G + 13'sd4) >>> 3;
    wire signed [12:0] B_val = extend_B;

    // 飽和截斷電路
    wire [7:0] R_clip = R_val[12] ? 8'd0 : ( |R_val[11:8] ? 8'd255 : R_val[7:0] );
    wire [7:0] G_clip = G_val[12] ? 8'd0 : ( |G_val[11:8] ? 8'd255 : G_val[7:0] );
    wire [7:0] B_clip = B_val[12] ? 8'd0 : ( |B_val[11:8] ? 8'd255 : B_val[7:0] );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rgb_out <= 24'd0;
        end else begin
            // 在 S3 和 S6 (運算狀態)，把算好的三路數值鎖進暫存器，以便在下一個狀態順利輸出
            if (CS == S3 || CS == S6) begin
                rgb_out <= {R_clip, G_clip, B_clip};
            end
        end
    end

    always @(*) begin
        case(CS)
            S3, S6: begin
                busy = 1'b1;
                out_valid = 1'b0;
            end
            S4, S7: begin
                busy = 1'b1;
                out_valid = 1'b1;
            end
            default: begin
                busy = 1'b0;
                out_valid = 1'b0;
            end
        endcase
    end

endmodule
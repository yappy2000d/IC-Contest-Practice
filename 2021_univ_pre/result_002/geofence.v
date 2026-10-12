module geofence ( clk,reset,X,Y,valid,is_inside);
input clk;
input reset;
input [9:0] X;
input [9:0] Y;
output valid;
output is_inside;
reg valid;
//reg is_inside;

localparam READ = 0;
localparam SORT = 1;
localparam ABCD = 2;
localparam EFGH = 3;

reg [2:0] cnt;
reg [1:0] CS, NS;

reg [9:0] obj_X, obj_Y;
reg [9:0] O_X, O_Y;

reg signed [10:0] vec_X [0:5];
reg signed [10:0] vec_Y [0:5];

reg signed [10:0] obj_vec_X [0:5];
reg signed [10:0] obj_vec_Y [0:5];

wire signed [10:0] sorted_X [0:4];
wire signed [10:0] sorted_Y [0:4];

wire [21:0] sort_in_0 = {vec_X[0], vec_Y[0]};
wire [21:0] sort_in_1 = {vec_X[1], vec_Y[1]};
wire [21:0] sort_in_2 = {vec_X[2], vec_Y[2]};
wire [21:0] sort_in_3 = {vec_X[3], vec_Y[3]};
wire [21:0] sort_in_4 = {vec_X[4], vec_Y[4]};

wire [21:0] sort_out_0, sort_out_1, sort_out_2, sort_out_3, sort_out_4;

sort sort_inst(
    .in_0(sort_in_0), .in_1(sort_in_1), .in_2(sort_in_2), .in_3(sort_in_3), .in_4(sort_in_4),
    .out_0(sort_out_0), .out_1(sort_out_1), .out_2(sort_out_2), .out_3(sort_out_3), .out_4(sort_out_4)
);

assign {sorted_X[0], sorted_Y[0]} = sort_out_0;
assign {sorted_X[1], sorted_Y[1]} = sort_out_1;
assign {sorted_X[2], sorted_Y[2]} = sort_out_2;
assign {sorted_X[3], sorted_Y[3]} = sort_out_3;
assign {sorted_X[4], sorted_Y[4]} = sort_out_4;

wire signed [10:0] vec_O_to_Obj_X = $signed({1'b0, O_X}) - $signed({1'b0, obj_X});
wire signed [10:0] vec_O_to_Obj_Y = $signed({1'b0, O_Y}) - $signed({1'b0, obj_Y});

// 宣告儲存 6 個邊判斷結果的暫存器
reg [5:0] inside_flag_reg;

// 宣告 MUX 的輸出，作為共用乘法器的輸入
reg signed [10:0] cur_vec_X_0, cur_vec_Y_0, cur_obj_vec_X_0, cur_obj_vec_Y_0;
reg signed [10:0] cur_vec_X_1, cur_vec_Y_1, cur_obj_vec_X_1, cur_obj_vec_Y_1;

always @(*) begin
    case(cnt)
        3'd0: begin
            cur_vec_X_0 = vec_X[0]; cur_vec_Y_0 = vec_Y[0];
            cur_obj_vec_X_0 = obj_vec_X[0]; cur_obj_vec_Y_0 = obj_vec_Y[0];
            cur_vec_X_1 = vec_X[1]; cur_vec_Y_1 = vec_Y[1];
            cur_obj_vec_X_1 = obj_vec_X[1]; cur_obj_vec_Y_1 = obj_vec_Y[1];
        end
        3'd1: begin
            cur_vec_X_0 = vec_X[2]; cur_vec_Y_0 = vec_Y[2];
            cur_obj_vec_X_0 = obj_vec_X[2]; cur_obj_vec_Y_0 = obj_vec_Y[2];
            cur_vec_X_1 = vec_X[3]; cur_vec_Y_1 = vec_Y[3];
            cur_obj_vec_X_1 = obj_vec_X[3]; cur_obj_vec_Y_1 = obj_vec_Y[3];
        end
        default: begin // 3'd2
            cur_vec_X_0 = vec_X[4]; cur_vec_Y_0 = vec_Y[4];
            cur_obj_vec_X_0 = obj_vec_X[4]; cur_obj_vec_Y_0 = obj_vec_Y[4];
            cur_vec_X_1 = vec_X[5]; cur_vec_Y_1 = vec_Y[5];
            cur_obj_vec_X_1 = obj_vec_X[5]; cur_obj_vec_Y_1 = obj_vec_Y[5];
        end
    endcase
end

// 實體化的 4 個乘法器與 2 個比較器
wire signed [21:0] cross_A_0 = cur_vec_X_0 * cur_obj_vec_Y_0;
wire signed [21:0] cross_B_0 = cur_obj_vec_X_0 * cur_vec_Y_0;
wire inside_0 = cross_A_0 < cross_B_0;

wire signed [21:0] cross_A_1 = cur_vec_X_1 * cur_obj_vec_Y_1;
wire signed [21:0] cross_B_1 = cur_obj_vec_X_1 * cur_vec_Y_1;
wire inside_1 = cross_A_1 < cross_B_1;

// 將 output is_inside 接到暫存器的邏輯 NOR
assign is_inside = (~|inside_flag_reg);

always @(posedge clk, posedge reset) begin
    if(reset) begin
        cnt <= 3'd0;
    end
    else begin
        valid <= 0;
        
        case(CS)
            READ: begin
                cnt <= (cnt == 3'd6)? 3'd0: cnt + 3'd1;
                
                if(cnt == 3'd0) begin
                    obj_X <= X;
                    obj_Y <= Y;
                end
                else if(cnt == 3'd1) begin
                    O_X <= X;
                    O_Y <= Y;
                end
                else begin
                    vec_X[cnt - 3'd2] <= $signed({1'b0, X}) - $signed({1'b0, O_X});
                    vec_Y[cnt - 3'd2] <= $signed({1'b0, Y}) - $signed({1'b0, O_Y});
                end
            end
            
            SORT: begin
                cnt <= cnt + 3'd1;
                
                vec_X[0] <= sorted_X[0]; vec_Y[0] <= sorted_Y[0];
                vec_X[1] <= sorted_X[1]; vec_Y[1] <= sorted_Y[1];
                vec_X[2] <= sorted_X[2]; vec_Y[2] <= sorted_Y[2];
                vec_X[3] <= sorted_X[3]; vec_Y[3] <= sorted_Y[3];
                vec_X[4] <= sorted_X[4]; vec_Y[4] <= sorted_Y[4];
                // vec_X[5] <= sorted_X[5]; vec_Y[5] <= sorted_Y[5];
            end
            
            ABCD: begin
                // 計算 Edge
                vec_X[0] <= vec_X[0];
                vec_Y[0] <= vec_Y[0];
                
                vec_X[1] <= vec_X[1] - vec_X[0];
                vec_Y[1] <= vec_Y[1] - vec_Y[0];
                
                vec_X[2] <= vec_X[2] - vec_X[1];
                vec_Y[2] <= vec_Y[2] - vec_Y[1];
                
                vec_X[3] <= vec_X[3] - vec_X[2];
                vec_Y[3] <= vec_Y[3] - vec_Y[2];
                
                vec_X[4] <= vec_X[4] - vec_X[3];
                vec_Y[4] <= vec_Y[4] - vec_Y[3];
                
                vec_X[5] <= 11'sd0 - vec_X[4];
                vec_Y[5] <= 11'sd0 - vec_Y[4];
                
                // 在排序後、變 Edge 前，計算排序過的 obj vec
                obj_vec_X[0] <= 11'sd0 + vec_O_to_Obj_X;
                obj_vec_Y[0] <= 11'sd0 + vec_O_to_Obj_Y;
                
                obj_vec_X[1] <= vec_X[0] + vec_O_to_Obj_X;
                obj_vec_Y[1] <= vec_Y[0] + vec_O_to_Obj_Y;
                                                                  
                obj_vec_X[2] <= vec_X[1] + vec_O_to_Obj_X;
                obj_vec_Y[2] <= vec_Y[1] + vec_O_to_Obj_Y;
                                                                  
                obj_vec_X[3] <= vec_X[2] + vec_O_to_Obj_X;
                obj_vec_Y[3] <= vec_Y[2] + vec_O_to_Obj_Y;
                                                                  
                obj_vec_X[4] <= vec_X[3] + vec_O_to_Obj_X;
                obj_vec_Y[4] <= vec_Y[3] + vec_O_to_Obj_Y;
                                                                  
                obj_vec_X[5] <= vec_X[4] + vec_O_to_Obj_X;
                obj_vec_Y[5] <= vec_Y[4] + vec_O_to_Obj_Y;
                
                cnt <= 3'd0;
            end
            
            // 2.3.3
            EFGH: begin                
                if (cnt == 3'd0) begin
                    inside_flag_reg[0] <= inside_0;
                    inside_flag_reg[1] <= inside_1;
                    cnt <= 3'd1;
                end
                else if (cnt == 3'd1) begin
                    inside_flag_reg[2] <= inside_0;
                    inside_flag_reg[3] <= inside_1;
                    cnt <= 3'd2;
                end
                else if (cnt == 3'd2) begin
                    inside_flag_reg[4] <= inside_0;
                    inside_flag_reg[5] <= inside_1;
                    cnt <= 3'd3;
                    valid <= 1'b1; // 第 3 個 cycle 運算完畢，拉高 valid 信號
                end
                else if (cnt == 3'd3) begin
                    valid <= 1'b0; // 滿足「在下一 cycle 將 valid 拉回 low」的要求
                    cnt <= 3'd0;
                end
            end
        endcase
    end
end

always @(posedge clk, posedge reset) begin
    if(reset) CS <= READ;
    else CS <= NS;
end

always @(*) begin
    case(CS)
        READ: NS = (cnt == 3'd6)? SORT : READ;
        SORT: NS = (cnt == 3'd2)? ABCD : SORT;
        ABCD: NS = EFGH;
        EFGH: NS = (cnt == 3'd3) ? READ : EFGH;
    endcase
end

endmodule

module sort(
    input [21:0] in_0, 
    input [21:0] in_1,
    input [21:0] in_2, 
    input [21:0] in_3,
    input [21:0] in_4,
    output [21:0] out_0,
    output [21:0] out_1,
    output [21:0] out_2,
    output [21:0] out_3,
    output [21:0] out_4
);

wire [21:0] tmp_0 ,tmp_1, tmp_2;

comp comp_11(in_0, in_1, out_0, tmp_0);
comp comp_12(in_2, in_3, tmp_1, tmp_2);

comp comp_21(tmp_0, tmp_1, out_1, out_2);
comp comp_22(tmp_2, in_4, out_3, out_4);
    
endmodule

module comp(
    input [21:0] in_0, 
    input [21:0] in_1,
    output reg [21:0] out_0,
    output reg [21:0] out_1
);

wire signed [10:0] Ax, Ay;
wire signed [10:0] Bx, By;

assign {Ax, Ay} = in_0;
assign {Bx, By} = in_1;

wire signed [21:0] cross_A, cross_B;
assign cross_A = Ax * By;
assign cross_B = Bx * Ay;

always @(*) begin
    if(cross_A > cross_B) begin 
        out_0 = in_1;
        out_1 = in_0;
    end
    else begin
        out_0 = in_0;
        out_1 = in_1;
    end
end

endmodule

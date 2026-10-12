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

wire [5:0] inside_flag;

wire signed [21:0] cross_A [0:5];
wire signed [21:0] cross_B [0:5];

genvar i;
generate
    for(i=0; i<6; i=i+1) begin : calc_cross_prod
        assign cross_A[i] = vec_X[i] * obj_vec_Y[i];
        assign cross_B[i] = obj_vec_X[i] * vec_Y[i];
        
        assign inside_flag[i] = cross_A[i] < cross_B[i];
    end
endgenerate

assign is_inside = (~|inside_flag);

always @(posedge clk, posedge reset) begin
    if(reset) begin
        cnt <= 3'd0;
    end
    else begin
        valid <= 0;
        
        case(CS)
            READ: begin
                cnt <= (cnt == 3'd6)? 0: cnt + 1;
                
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
                cnt <= cnt + 1;
                
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
                
                vec_X[5] <= 0 - vec_X[4];
                vec_Y[5] <= 0 - vec_Y[4];
                
                // 在排序後、變 Edge 前，計算排序過的 obj vec
                obj_vec_X[0] <= 0 - ($signed({1'b0, obj_X}) - $signed({1'b0, O_X}));
                obj_vec_Y[0] <= 0 - ($signed({1'b0, obj_Y}) - $signed({1'b0, O_Y}));
                
                obj_vec_X[1] <= vec_X[0] - $signed({1'b0, obj_X}) + $signed({1'b0, O_X});
                obj_vec_Y[1] <= vec_Y[0] - $signed({1'b0, obj_Y}) + $signed({1'b0, O_Y});
                                                                  
                obj_vec_X[2] <= vec_X[1] - $signed({1'b0, obj_X}) + $signed({1'b0, O_X});
                obj_vec_Y[2] <= vec_Y[1] - $signed({1'b0, obj_Y}) + $signed({1'b0, O_Y});
                                                                  
                obj_vec_X[3] <= vec_X[2] - $signed({1'b0, obj_X}) + $signed({1'b0, O_X});
                obj_vec_Y[3] <= vec_Y[2] - $signed({1'b0, obj_Y}) + $signed({1'b0, O_Y});
                                                                  
                obj_vec_X[4] <= vec_X[3] - $signed({1'b0, obj_X}) + $signed({1'b0, O_X});
                obj_vec_Y[4] <= vec_Y[3] - $signed({1'b0, obj_Y}) + $signed({1'b0, O_Y});
                                                                  
                obj_vec_X[5] <= vec_X[4] - $signed({1'b0, obj_X}) + $signed({1'b0, O_X});
                obj_vec_Y[5] <= vec_Y[4] - $signed({1'b0, obj_Y}) + $signed({1'b0, O_Y});
                
                valid <= 1;
            end
            
            // 2.3.3
            EFGH: begin                
                cnt <= 3'd0;
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
        SORT: NS = (cnt == 3'd3)? ABCD : SORT;
        ABCD: NS = EFGH;
        EFGH: NS = READ;
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
    if(Ax * By > Bx * Ay) begin 
        out_0 = in_1;
        out_1 = in_0;
    end
    else begin
        out_0 = in_0;
        out_1 = in_1;
    end
end

endmodule

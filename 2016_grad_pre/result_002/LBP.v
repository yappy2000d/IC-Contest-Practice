`timescale 1ns/10ps
module LBP ( clk, reset, gray_addr, gray_req, gray_ready, gray_data, lbp_addr, lbp_valid, lbp_data, finish);
input       clk;
input       reset;
output reg [13:0]   gray_addr;
output              gray_req;
input               gray_ready;
input [7:0]         gray_data;
output reg [13:0]   lbp_addr;
output reg          lbp_valid;
output [7:0]        lbp_data;
output reg          finish;

//====================================================================

reg [7:0] prev, curr, next;     // gc
reg [7:0] prev_lbp, curr_lbp, next_lbp;
reg [13:0] prev_addr;
reg [1:0] CS, NS;

wire [6:0] valid_cnt;

always @(posedge clk or posedge reset) begin
    if(reset)
        CS <= 2'b0;
    else begin
        CS <= NS;
    end
end

always @(*) begin
    case(CS)
        2'b00: NS = 2'b01;
        2'b01: NS = 2'b10;
        2'b10: NS = 2'b11;
        2'b11: NS = 2'b01;
    endcase
end

always @(posedge clk or posedge reset) begin
    if(reset) begin
        prev_addr <= 14'd126;
        finish <= 0;
    end
    else begin
        case(CS)
            2'b00:
            begin
                gray_addr <= prev_addr + 2;
            end
            2'b01:
            begin
                curr_lbp[4] <= (gray_data >= next);
                next_lbp[3] <= (next >= gray_data);
                
                curr_lbp[3] <= next_lbp[3];
                curr_lbp[0] <= next_lbp[0];
                curr_lbp[5] <= next_lbp[5];
                
                prev_lbp[3] <= curr_lbp[3];
                prev_lbp[0] <= curr_lbp[0];
                prev_lbp[5] <= curr_lbp[5];
                
                prev_lbp[4] <= curr_lbp[4];
                prev_lbp[1] <= curr_lbp[1];
                prev_lbp[6] <= curr_lbp[6];
                
                gray_addr <= prev_addr - 127;
                
                next <= gray_data;
                curr <= next;
                prev <= curr;
                
                prev_addr <= prev_addr + 1;
                lbp_valid <= 0;
                
                lbp_addr <= prev_addr;
            end
            2'b10:
            begin
                next_lbp[0] <= (gray_data >= next);
                curr_lbp[1] <= (gray_data >= curr);
                prev_lbp[2] <= (gray_data >= prev);
                
                gray_addr <= prev_addr + 128;
                lbp_valid <= 0;
            end
            2'b11: begin
                next_lbp[5] <= (gray_data >= next);
                curr_lbp[6] <= (gray_data >= curr);
                prev_lbp[7] <= (gray_data >= prev);
                
                gray_addr <= prev_addr + 2;     // back to state 01
                
                lbp_valid <= (valid_cnt != 0 && valid_cnt != 1 && prev_addr != 14'd127);
                finish <= (prev_addr == 14'd16255)? 1 : 0;
            end
        endcase
    end
end

assign valid_cnt = prev_addr[6:0];
assign lbp_data = prev_lbp;
assign gray_req = 1;

//====================================================================
endmodule

`timescale 1ns/10ps
module LBP ( clk, reset, gray_addr, gray_req, gray_ready, gray_data, lbp_addr, lbp_valid, lbp_data, finish);
input       clk;
input       reset;
output reg [13:0]   gray_addr;
output              gray_req;
input               gray_ready;
input [7:0]         gray_data;
output reg [13:0]   lbp_addr;
output              lbp_valid;
output [7:0]        lbp_data;
output              finish;
//====================================================================

reg [13:0] addr;
reg [8:0] rcnt;
reg [7:0] gc;
reg [7:0] lbp_buf;

reg [6:0] x_cnt, y_cnt;
reg [6:0] x_cnt_d, y_cnt_d;     // delay


// Ring Counter
always @(posedge clk or posedge reset) begin
    if (reset) rcnt <= 9'b1_0000_0000;
    else if (gray_ready) rcnt <= {rcnt[0], rcnt[8:1]};
end

reg start_flag;
always @(posedge clk or posedge reset) begin
    if(reset) start_flag <= 0;
    else if(gray_ready || start_flag) start_flag <= 1;
end

always @(posedge clk or posedge reset) begin
    if (reset) begin
        x_cnt <= 7'd1;
        y_cnt <= 7'd1;
        addr <= 14'd129;
    end
    else if (gray_ready) begin
        lbp_buf <= {(gray_data >= gc), lbp_buf[7:1]};
        if(rcnt == 9'b0_0000_0001) begin
            addr <= addr + 1;
            
            if (x_cnt == 7'd127) begin
                x_cnt <= 7'd0;
                y_cnt <= y_cnt + 1;
            end
            else begin
                x_cnt <= x_cnt + 1;
            end
            x_cnt_d <= x_cnt;
            y_cnt_d <= y_cnt;
        end
        if(rcnt == 9'b1_0000_0000) begin
            lbp_addr <= addr;       // 鎖住此時的 addr
            gc <= gray_data;
        end
    end
end

assign gray_req = ~finish;
assign lbp_valid = (rcnt == 9'b1_0000_0000) && start_flag;
assign lbp_data = (x_cnt_d == 7'd0 || x_cnt_d == 7'd127 || y_cnt_d == 7'd0 || y_cnt_d == 7'd127)? 0: lbp_buf;
assign finish = (addr == 14'd16255);

always @(*) begin
    gray_addr = lbp_addr;
    case(rcnt)
        9'b100000000: gray_addr = addr;
        9'b010000000: gray_addr = addr - 14'd129; // Top-Left
        9'b001000000: gray_addr = addr - 14'd128; // Top-Middle
        9'b000100000: gray_addr = addr - 14'd127; // Top-Right
        9'b000010000: gray_addr = addr - 14'd1;   // Middle-Left
        9'b000001000: gray_addr = addr + 14'd1;   // Middle-Right
        9'b000000100: gray_addr = addr + 14'd127; // Bottom-Left
        9'b000000010: gray_addr = addr + 14'd128; // Bottom-Middle
        9'b000000001: gray_addr = addr + 14'd129; // Bottom-Right
    endcase
end

//====================================================================
endmodule

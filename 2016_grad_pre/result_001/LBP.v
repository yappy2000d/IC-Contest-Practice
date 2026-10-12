`timescale 1ns/10ps
module LBP ( clk, reset, gray_addr, gray_req, gray_ready, gray_data, lbp_addr, lbp_valid, lbp_data, finish);
input       clk;
input       reset;
output reg [13:0]   gray_addr;
output reg          gray_req;
input               gray_ready;
input [7:0]         gray_data;
output reg [13:0]   lbp_addr;
output              lbp_valid;
output reg [7:0]    lbp_data;
output reg          finish;

//====================================================================

localparam IDLE = 2'b00;
localparam INIT = 2'b01;
localparam PROC = 2'b10;
localparam DONE = 2'b11;

reg [7:0] img_buf [0:257];
reg [1:0] CS, NS;
reg [6:0] x_cnt;    // PROC-used counter
reg [7:0] lbp_buf;

reg lbp_valid_raw, lbp_valid_d;

assign lbp_valid = lbp_valid_raw | lbp_valid_d;  // delay 1 clock

always @(posedge clk or posedge reset) begin
    if(reset) begin
        lbp_addr <= 14'd129;
        lbp_valid_d <= 0;
    end
    else begin
        if(gray_addr > 14'd258)
            lbp_addr <= lbp_addr + 1;
        
        lbp_data <= {
            gray_data >= img_buf[129],
            img_buf[257] >= img_buf[129],
            img_buf[256] >= img_buf[129],
            img_buf[130] >= img_buf[129],
            img_buf[128] >= img_buf[129],
            img_buf[2] >= img_buf[129],
            img_buf[1] >= img_buf[129],
            img_buf[0] >= img_buf[129]
        };
        
        lbp_valid_d <= lbp_valid_raw;
    end
end

always @(posedge clk or posedge reset) begin
    if(reset) CS <= IDLE;
    else CS <= NS;
end

integer i;
always @(posedge clk or posedge reset) begin
    if(reset) begin
        NS <= IDLE;
        x_cnt <= 7'd0;
        gray_addr <= 14'd0;
    end
    else begin
        case(CS)
            IDLE: begin
                if(gray_ready)
                    NS <= INIT;
            end
            INIT: begin
                gray_addr <= gray_addr + 1;
                
                img_buf[257] <= gray_data;
                for(i=0; i<257; i=i+1)
                    img_buf[i] <= img_buf[i+1];
                
                if(gray_addr == 14'd255 - 1)
                    NS <= PROC;
            end
            PROC: begin
                x_cnt <= x_cnt + 1;
                gray_addr <= gray_addr + 1;
                
                img_buf[257] <= gray_data;
                for(i=0; i<257; i=i+1)
                    img_buf[i] <= img_buf[i+1];
                
                if(gray_addr == 14'd16383)
                    NS <= DONE;
            end
            DONE:;
        endcase
    end
end

always @(*) begin
    case(CS)
        IDLE: begin
             gray_req      = 0;
             lbp_valid_raw = 0;
             finish    = 0;
        end
        INIT: begin
            gray_req      = 1;
            lbp_valid_raw = 0;
            finish    = 0;
        end
        PROC: begin
            gray_req      = 1;
            lbp_valid_raw = x_cnt > 2;
            finish    = 0; 
        end
        DONE: begin
            gray_req      = 0;
            lbp_valid_raw = 0;
            finish = 1; 
        end
    endcase
end

//============================================================
endmodule

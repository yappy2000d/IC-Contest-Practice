module LCD_CTRL(clk, reset, cmd, cmd_valid, IROM_Q, IROM_rd, IROM_A, IRAM_valid, IRAM_D, IRAM_A, busy, done);
input clk;
input reset;
input [3:0] cmd;
input cmd_valid;
input [7:0] IROM_Q;
output IROM_rd;
output [5:0] IROM_A;
output reg IRAM_valid;
output reg [7:0] IRAM_D;
output reg [5:0] IRAM_A;
output reg busy;
output reg done;

// 狀態定義
localparam INIT = 2'b00;
localparam WAIT = 2'b01;
localparam PROC = 2'b10;
localparam WRITE = 2'b11;

reg [1:0] CS, NS;
reg [3:0] cmd_reg;
reg [7:0] image [0:63];
reg done_d;
reg [5:0] addr;

wire flag;
wire [2:0] cur_y, cur_x;

assign IROM_A = addr;
assign flag = (addr == 63);
assign {cur_y, cur_x} = addr;
assign IROM_rd = 1;

always @(posedge clk)
    done <= done_d;

wire [7:0] max, max1, max2; 
wire [7:0] min, min1, min2;
wire cmp1, cmp2, cmp3, cmp4;
wire [7:0] p0, p1, p2, p3;

assign p0 = image[{cur_y-3'd1, cur_x-3'd1}];    // upper left
assign p1 = image[{cur_y-3'd1, cur_x}];         // upper right
assign p2 = image[{cur_y,      cur_x-3'd1}];    // lower left
assign p3 = image[{cur_y,      cur_x}];         // lower right

assign cmp1 = (p0 > p1); 
assign max1 = cmp1 ? p0 : p1;
assign min1 = cmp1 ? p1 : p0;

assign cmp2 = (p2 > p3); 
assign max2 = cmp2 ? p2 : p3;
assign min2 = cmp2 ? p3 : p2;

assign cmp3 = (max1 > max2);
assign max  = cmp3 ? max1 : max2;

assign cmp4 = (min1 < min2);
assign min  = cmp4 ? min1 : min2;

wire [9:0] sum;
wire [7:0] avg;
assign sum = p0 + p1 + p2 + p3;
assign avg = sum[9:2];

// FSM State Register
always @(posedge clk) begin
    if(reset)
        CS <= INIT;
    else
        CS <= NS;
end

// FSM Next State Logic
always @(*) begin
    case(CS)
        INIT: NS = (addr == 6'h3f) ? WAIT : INIT;
        WAIT: NS = (cmd_valid) ? PROC : WAIT;
        PROC: NS = (cmd_reg == 4'h0) ? WRITE : WAIT; // cmd 0 是 Write 指令
        WRITE: NS = WRITE;
    endcase
end

// Output Logic (Combinational)
always @(*) begin
    if(CS == WAIT) busy = 0;
    else busy = 1;
end

// Data Path & Control
always @(posedge clk, posedge reset) begin
    if(reset) begin
        addr <= 6'h0;
        IRAM_D <= 8'h0;
        IRAM_valid <= 0;
        done_d <= 0;
        cmd_reg <= 0;
    end
    else begin
        case(CS)
            INIT: begin
                image[addr] <= IROM_Q;
                if (flag)
                    addr <= {3'd4, 3'd4};
                else
                    addr <= addr + 1;
            end
            
            WAIT: begin
                if(cmd_valid) begin
                    cmd_reg <= cmd;
                end
            end
            
            PROC: begin
                case(cmd_reg)
                    4'h0: addr <= 6'd0;
                    
                    4'h1: addr[5:3] <= cur_y - (cur_y != 3'd1); // Shift Up
                    4'h2: addr[5:3] <= cur_y + (cur_y != 3'd7); // Shift Down
                    4'h3: addr[2:0] <= cur_x - (cur_x != 3'd1); // Shift Left
                    4'h4: addr[2:0] <= cur_x + (cur_x != 3'd7); // Shift Right
                    
                    4'h5: begin // Max
                        image[{cur_y-3'd1, cur_x-3'd1}] <= max; // P0
                        image[{cur_y-3'd1, cur_x     }] <= max; // P1
                        image[{cur_y,      cur_x-3'd1}] <= max; // P2
                        image[{cur_y,      cur_x     }] <= max; // P3
                    end
                    
                    4'h6: begin // Min
                        image[{cur_y-3'd1, cur_x-3'd1}] <= min;
                        image[{cur_y-3'd1, cur_x     }] <= min;
                        image[{cur_y,      cur_x-3'd1}] <= min;
                        image[{cur_y,      cur_x     }] <= min;
                    end
                    
                    4'h7: begin // Average
                        image[{cur_y-3'd1, cur_x-3'd1}] <= avg;
                        image[{cur_y-3'd1, cur_x     }] <= avg;
                        image[{cur_y,      cur_x-3'd1}] <= avg;
                        image[{cur_y,      cur_x     }] <= avg;
                    end
                    
                    4'h8: begin // Counterclockwise Rotation
                        image[{cur_y-3'd1, cur_x-3'd1}] <= p1;
                        image[{cur_y-3'd1, cur_x     }] <= p3;
                        image[{cur_y,      cur_x-3'd1}] <= p0;
                        image[{cur_y,      cur_x     }] <= p2;
                    end
                    
                    4'h9: begin // Clockwise Rotation
                        image[{cur_y-3'd1, cur_x-3'd1}] <= p2;
                        image[{cur_y-3'd1, cur_x     }] <= p0;
                        image[{cur_y,      cur_x-3'd1}] <= p3;
                        image[{cur_y,      cur_x     }] <= p1;
                    end
                    
                    4'ha: begin // Mirror X
                        image[{cur_y-3'd1, cur_x-3'd1}] <= p2;
                        image[{cur_y-3'd1, cur_x     }] <= p3;
                        image[{cur_y,      cur_x-3'd1}] <= p0;
                        image[{cur_y,      cur_x     }] <= p1;
                    end

                    4'hb: begin // Mirror Y
                        image[{cur_y-3'd1, cur_x-3'd1}] <= p1;
                        image[{cur_y-3'd1, cur_x     }] <= p0;
                        image[{cur_y,      cur_x-3'd1}] <= p3;
                        image[{cur_y,      cur_x     }] <= p2;
                    end
                endcase
            end
            
            WRITE: begin
                IRAM_D <= image[addr]; 
                IRAM_A <= addr;
                IRAM_valid <= 1;
                addr <= addr + 1;
                done_d <= flag; 
            end
        endcase
    end
end

endmodule 
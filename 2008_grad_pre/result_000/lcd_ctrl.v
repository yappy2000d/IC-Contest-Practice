module LCD_CTRL(clk, reset, datain, cmd, cmd_valid, dataout, output_valid, busy);
input            clk;
input            reset;
input   [7:0]    datain;
input   [3:0]    cmd;
input            cmd_valid;
output reg [7:0] dataout;
output reg       output_valid;
output reg       busy;

localparam s_IDLE = 2'd0;
localparam s_LOAD = 2'd1;
localparam s_CALC = 2'd2;
localparam s_OPUT = 2'd3;

localparam LOAD_DATA    = 4'd0;
localparam ROTATE_LEFT  = 4'd1;
localparam ROTATE_RIGHT = 4'd2;
localparam ZOOM_IN      = 4'd3;
localparam ZOOM_FIT     = 4'd4;
localparam SHIFT_RIGHT  = 4'd5;
localparam SHIFT_LEFT   = 4'd6;
localparam SHIFT_UP     = 4'd7;
localparam SHIFT_DOWN   = 4'd8;

reg [1:0] CS, NS;
reg [3:0] cmd_reg;
reg [6:0] counter;
reg [7:0] img_buf [0:107];
reg mode;   // 0: ZOOM_FIT, 1: ZOOM_IN
reg [3:0]  origin_l, origin_w;
reg [1:0] rotate;  // 0: no, 1: left, 2: right
reg [6:0] result [0:15];    // result index of img buffer
wire [6:0] index;

assign index = result[counter[3:0]];

always @(posedge clk, posedge reset) begin
    if(reset) CS <= s_IDLE;
    else      CS <= NS;
end

always @(*) begin
    case(CS)
        s_IDLE: begin
            if(cmd_valid) begin
                if(cmd == LOAD_DATA) NS = s_LOAD;
                else                 NS = s_CALC;
            end
            else NS = s_IDLE;
        end
        
        s_LOAD: begin
            if(counter == 8'd107) NS = s_OPUT; 
            else                  NS = s_LOAD;
        end
        
        s_CALC:
            NS = s_OPUT; 
        
        s_OPUT: begin
            // 輸出 16 筆資料後，回到 IDLE 等下一個指令
            if(counter == 15) NS = s_IDLE;
            else              NS = s_OPUT;
        end
        
        default: NS = s_IDLE;
    endcase
end

always @(posedge clk, posedge reset) begin
    if(reset) begin
        counter      <= 0;
        busy         <= 0;
        output_valid <= 0;
        mode         <= 0; // 預設 Zoom Fit
        origin_l     <= 0;
        origin_w     <= 0;
        dataout      <= 0;
        rotate       <= 0;
    end
    else begin
        case(CS)
            s_IDLE: begin
                output_valid <= 0;
                counter <= 0;
                if(cmd_valid) begin
                    busy <= 1;        // 收到指令，開始 Busy
                    cmd_reg <= cmd;
                end
            end
            
            s_LOAD: begin
                // [Load Data] 區塊功能
                img_buf[counter] <= datain;
                if(counter < 107)
                    counter <= counter + 1;
                else begin
                    counter <= 0;       // 重置計數器給 Output 用
                    mode    <= 0;       // Load Data 強制切回 Zoom Fit
                    rotate  <= 0;     // Load Data 強制歸零旋轉角度
                end
            end
            
            s_CALC: begin
                counter <= 0;           // 重置計數器給 Output 用
                case(cmd_reg)
                    ZOOM_FIT: begin
                        mode <= 0;
                    end
                    
                    ZOOM_IN: begin
                        mode <= 1;
                        // 題目: Zoom In 指令會自動將原點 origin 指向(6,5)。 [page: 9]
                        origin_l <= 6; 
                        origin_w <= 5;
                    end
                    
                    ROTATE_LEFT: begin
                        if(mode == 0) begin         // 題目: 只有在 Zoom Fit State 時，旋轉指令才有作用。 [page: 8]
                            case(rotate)
                                0: rotate <= 1;     // no -> left
                                2: rotate <= 0;     // right -> no
                                default: ;          // 題目: 主辦單位所提供之左旋轉指令，不會讓畫面旋轉 180 度，最多只有向左旋轉 90 度。 [page: 8]
                            endcase
                        end
                    end
                    
                    ROTATE_RIGHT: begin
                        if(mode == 0) begin         // 題目: 只有在 Zoom Fit State 時，旋轉指令才有作用。 [page: 8]
                            case(rotate)
                                0: rotate <= 2;     // no -> right
                                1: rotate <= 0;     // left -> no
                                default: ;          // 題目: 主辦單位所提供之右旋轉指令，不會讓畫面旋轉 180 度，最多只有向右旋轉 90 度。 [page: 8]
                            endcase
                        end
                    end
                    
                    SHIFT_RIGHT: begin
                        if(mode == 1) begin         // 題目: 移動(Shift)指令，只有在該 Zoom In State 才有效用。 [page: 9]
                            case(rotate)
                                0: origin_l <= (origin_l == 4'ha)? 4'ha: origin_l + 1;
                                1: origin_w <= (origin_w == 4'h7)? 4'h7: origin_w + 1;
                                2: origin_w <= (origin_w == 4'h2)? 4'h2: origin_w - 1;
                            endcase
                        end
                    end
                    
                    SHIFT_LEFT: begin
                        if(mode == 1) begin         // 題目: 移動(Shift)指令，只有在該 Zoom In State 才有效用。 [page: 9]
                            case(rotate)
                                0: origin_l <= (origin_l == 4'h2)? 4'h2: origin_l - 1;
                                1: origin_w <= (origin_w == 4'h2)? 4'h2: origin_w - 1;
                                2: origin_w <= (origin_w == 4'h7)? 4'h7: origin_w + 1;
                            endcase
                        end
                    end
                    
                    SHIFT_UP: begin
                        if(mode == 1) begin         // 題目: 移動(Shift)指令，只有在該 Zoom In State 才有效用。 [page: 9]
                            case(rotate)
                                0: origin_w <= (origin_w == 4'h2)? 4'h2: origin_w - 1;
                                1: origin_l <= (origin_l == 4'ha)? 4'ha: origin_l + 1;
                                2: origin_l <= (origin_l == 4'h2)? 4'h2: origin_l - 1;
                            endcase
                        end
                    end
                    
                    SHIFT_DOWN: begin
                        if(mode == 1) begin         // 題目: 移動(Shift)指令，只有在該 Zoom In State 才有效用。 [page: 9]
                            case(rotate)
                                0: origin_w <= (origin_w == 4'h7)? 4'h7: origin_w + 1;
                                1: origin_l <= (origin_l == 4'h2)? 4'h2: origin_l - 1;
                                2: origin_l <= (origin_l == 4'ha)? 4'ha: origin_l + 1;
                            endcase
                        end
                    end
                endcase
            end
            
            s_OPUT: begin
                output_valid <= 1;
                dataout <= img_buf[index];
                if(counter == 15)
                    busy <= 0;
                else
                    counter <= counter + 1;
            end
        endcase
    end
end

integer i;

always @(*) begin
    case(rotate)
        // no
        2'd0: begin
            if(mode == 0) begin
                result['h0] = 7'hd;
                result['h1] = 7'h10;
                result['h2] = 7'h13;
                result['h3] = 7'h16;
                result['h4] = 7'h25;
                result['h5] = 7'h28;
                result['h6] = 7'h2b;
                result['h7] = 7'h2e;
                result['h8] = 7'h3d;
                result['h9] = 7'h40;
                result['ha] = 7'h43;
                result['hb] = 7'h46;
                result['hc] = 7'h55;
                result['hd] = 7'h58;
                result['he] = 7'h5b;
                result['hf] = 7'h5e;
            end
            else begin
                for(i=0; i<16; i=i+1) begin
                    result[i] = (origin_w - 2 + i[3:2]) * 12 + (origin_l - 2 + i[1:0]);
                end
            end
        end
        
        // left
        2'd1: begin
            if(mode == 0) begin
                result['h0] = 7'h16;
                result['h1] = 7'h2e;
                result['h2] = 7'h46;
                result['h3] = 7'h5e;
                result['h4] = 7'h13;
                result['h5] = 7'h2b;
                result['h6] = 7'h43;
                result['h7] = 7'h5b;
                result['h8] = 7'h10;
                result['h9] = 7'h28;
                result['ha] = 7'h40;
                result['hb] = 7'h58;
                result['hc] = 7'hd;
                result['hd] = 7'h25;
                result['he] = 7'h3d;
                result['hf] = 7'h55;
            end
            else begin
                for(i=0; i<16; i=i+1) begin
                    result[i] = (origin_w - 2 + i[1:0]) * 12 + (origin_l + 1 - i[3:2]);
                end
            end
        end
        
        // right
        2'd2: begin
            if(mode == 0) begin
                result['h0] = 7'h55;
                result['h1] = 7'h3d;
                result['h2] = 7'h25;
                result['h3] = 7'hd;
                result['h4] = 7'h58;
                result['h5] = 7'h40;
                result['h6] = 7'h28;
                result['h7] = 7'h10;
                result['h8] = 7'h5b;
                result['h9] = 7'h43;
                result['ha] = 7'h2b;
                result['hb] = 7'h13;
                result['hc] = 7'h5e;
                result['hd] = 7'h46;
                result['he] = 7'h2e;
                result['hf] = 7'h16;
            end
            else begin
                for(i=0; i<16; i=i+1) begin
                    result[i] = (origin_w + 1 - i[1:0]) * 12 + (origin_l - 2 + i[3:2]);
                end
            end
        end
        
        default: begin
            result['h0] = 7'h0;
            result['h1] = 7'h0;
            result['h2] = 7'h0;
            result['h3] = 7'h0;
            result['h4] = 7'h0;
            result['h5] = 7'h0;
            result['h6] = 7'h0;
            result['h7] = 7'h0;
            result['h8] = 7'h0;
            result['h9] = 7'h0;
            result['ha] = 7'h0;
            result['hb] = 7'h0;
            result['hc] = 7'h0;
            result['hd] = 7'h0;
            result['he] = 7'h0;
            result['hf] = 7'h0;
        end
    endcase
end

endmodule

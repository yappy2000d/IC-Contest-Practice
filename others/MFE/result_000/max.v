module max(
	input wire [7:0] a, b,
	output reg [7:0] hi, lo
);

always @(*) begin
	if(a >= b) begin
		hi = a;
		lo = b;
	end
	else begin
		hi = b;
		lo = a;
	end
end

endmodule

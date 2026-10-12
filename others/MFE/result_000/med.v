module med(
	input wire [7:0] a, b, c,
	output reg [7:0] hi, md, lo
);

// Assume a >= b
always @(*) begin
	hi = a;
	md = c;
	lo = b;
	if(c >= a) begin
		hi = c;
		md = a;
		lo = b;
	end
	if(b >= c) begin
		hi = a;
		md = b;
		lo = c;
	end
end

endmodule

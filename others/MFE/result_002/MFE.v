// ============================================================================
// MFE fold3 -- 2021 DIC HW4 Median Filter Engine (128x128, zero padding)
//
//  Everything after the column sorter is now LANE-SERIAL:
//    * each sorted column leaves C2 as a stream  hi, md, lo  (1 value / cycle)
//    * "same lane, previous column" = the stream 3 cycles ago, so C1 and R
//      become plain 3-deep shift registers (no enable, no mux)
//    * ONE row max + ONE row med handle the 3 lanes in turn
//    * the final med consumes m1, m2, m3 as they arrive (insertion fold)
//
//  Folded units (all built from max.v / med.v):
//    S1 column : med  (k=1 CAS, k=2 sort3)                -- as fold2
//    S2 row    : max  (1 lane / cycle)
//    S3 row    : med  (1 lane / cycle, output .lo/.md/.hi by lane)
//    S4 final  : med  (m1 load, m2 CAS, m3 median)
//
//  Padding: the right/left pad column is fetched as a real 3-cycle column
//  (c = 128, pixels forced to 0), so every column is exactly 3 cycles apart.
//  Cost: 3 extra cycles per row (+384 cycles total); the inj logic is gone.
// ============================================================================
module MFE (
    input             clk,
    input             reset,      // active-high asynchronous
    output reg        busy,
    input             ready,
    output reg [13:0] iaddr,
    input      [7:0]  idata,
    input      [7:0]  data_rd,    // unused
    output reg [7:0]  data_wr,
    output reg [13:0] addr,
    output reg        wen
);

    // ------------------------------------------------------------------
    // Fetch control : r = 0..127, c = 0..128 (128 = pad column), k = 0..2
    // ------------------------------------------------------------------
    reg  [6:0] r;
    reg  [7:0] c;
    reg  [1:0] k;
    reg        fetching, fin;
    reg        f_v, f_pad, f_k0, f_k2, f_c0;

    wire last_fetch = (r == 7'd127) && (c == 8'd128) && (k == 2'd2);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 1'b0; fetching <= 1'b0;
            r <= 7'd0; c <= 8'd0; k <= 2'd0;
            iaddr <= 14'd0;
            f_v <= 1'b0; f_pad <= 1'b0; f_k0 <= 1'b0; f_k2 <= 1'b0; f_c0 <= 1'b0;
        end else begin
            f_v <= 1'b0;
            if (!busy) begin
                if (ready) begin busy <= 1'b1; fetching <= 1'b1; end
            end else if (fin) begin
                busy <= 1'b0;
            end

            if (fetching) begin
                iaddr  <= {r + {5'd0, k} - 7'd1, c[6:0]};
                f_v    <= 1'b1;
                f_pad  <= c[7] || (r == 7'd0 && k == 2'd0) || (r == 7'd127 && k == 2'd2);
                f_k0   <= (k == 2'd0);
                f_k2   <= (k == 2'd2);
                f_c0   <= (c == 8'd0);
                if (last_fetch) fetching <= 1'b0;
                if (k == 2'd2) begin
                    k <= 2'd0;
                    if (c == 8'd128) begin c <= 8'd0; r <= r + 7'd1; end
                    else               c <= c + 8'd1;
                end else begin
                    k <= k + 2'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // R0 + S1 : A and column fold (unchanged from fold2)
    // ------------------------------------------------------------------
    reg [7:0] A, T_hi, T_lo;
    reg       a_k0, col_rdy, rdy_c0;

    always @(posedge clk) begin
        if (f_v) A <= f_pad ? 8'd0 : idata;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            a_k0 <= 1'b0; col_rdy <= 1'b0; rdy_c0 <= 1'b0;
        end else begin
            a_k0    <= f_v & f_k0;
            col_rdy <= f_v & f_k2;
            rdy_c0  <= f_c0;
        end
    end

    wire [7:0] s_hi, s_md, s_lo;
    med u_col_med (.a(T_hi), .b(T_lo), .c(A), .hi(s_hi), .md(s_md), .lo(s_lo));

    always @(posedge clk) begin
        if (a_k0) begin
            T_hi <= A;     T_lo <= 8'd0;
        end else if (!col_rdy) begin
            T_hi <= s_hi;  T_lo <= s_md;
        end
    end

    // ------------------------------------------------------------------
    // R1 : C2 as a 3-entry parallel-load / shift register -> lane stream E0
    //      load (col_rdy) : {E0,E1,E2} <= {hi, md, lo}
    //      otherwise      : shift, zeros enter from E2
    //      C1 = stream delayed 3 cycles (same lane, previous column)
    // ------------------------------------------------------------------
    reg [7:0] E0, E1, E2;
    reg [7:0] D0, D1, D2;          // C1 : D2 = E0 three cycles ago
    reg [2:0] ph;                  // one-hot lane of E0 : 001 hi, 010 md, 100 lo
    reg       e_first;             // E holds column 0 of a row (window invalid)

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            E0 <= 8'd0; E1 <= 8'd0; E2 <= 8'd0;     // zero stream before the first
            ph <= 3'b000; e_first <= 1'b0;          // column = left pad of row 0
        end else begin
            E0 <= col_rdy ? s_hi : E1;
            E1 <= col_rdy ? s_md : E2;
            E2 <= col_rdy ? s_lo : 8'd0;
            ph <= col_rdy ? 3'b001 : {ph[1:0], 1'b0};
            if (col_rdy) e_first <= rdy_c0;
        end
    end

    always @(posedge clk) begin
        D0 <= E0; D1 <= D0; D2 <= D1;
    end

    // ------------------------------------------------------------------
    // S2 / R2 : ONE row max per cycle, pair stream delayed 3 (R)
    // S3 / R3 : ONE row med per cycle -> M (lane-selected output)
    // ------------------------------------------------------------------
    wire [7:0] p_hi, p_lo;
    max u_row_max (.a(D2), .b(E0), .hi(p_hi), .lo(p_lo));

    reg [7:0] R0_hi, R0_lo, R1_hi, R1_lo, R2_hi, R2_lo;
    always @(posedge clk) begin
        R0_hi <= p_hi;  R0_lo <= p_lo;
        R1_hi <= R0_hi; R1_lo <= R0_lo;
        R2_hi <= R1_hi; R2_lo <= R1_lo;          // pair of the previous two columns
    end

    wire [7:0] rm_hi, rm_md, rm_lo;
    med u_row_med (.a(R2_hi), .b(R2_lo), .c(E0), .hi(rm_hi), .md(rm_md), .lo(rm_lo));

    // hi lane -> .lo (min of maxima), md lane -> .md, lo lane -> .hi (max of minima)
    wire [7:0] m_sel = ph[0] ? rm_lo : (ph[1] ? rm_md : rm_hi);

    reg [7:0] M;
    reg [2:0] m_ph;                // one-hot: M holds m1 / m2 / m3 of a valid window
    always @(posedge clk) begin
        M <= m_sel;
    end
    always @(posedge clk or posedge reset) begin
        if (reset) m_ph <= 3'b000;
        else       m_ph <= ph & {3{~e_first}};
    end

    // ------------------------------------------------------------------
    // S4 / R4 : final med, insertion fold over m1, m2, m3
    //   m1 : Q <- {m1, 0}
    //   m2 : Q <- med(Q_hi, 0, m2).{hi,md}        = CAS(m1, m2)
    //   m3 : data_wr <- med(Q_hi, Q_lo, m3).md
    // ------------------------------------------------------------------
    reg  [7:0] Q_hi, Q_lo;
    wire [7:0] o_hi, o_md;
    med u_fin_med (.a(Q_hi), .b(Q_lo), .c(M), .hi(o_hi), .md(o_md), .lo());

    always @(posedge clk) begin
        if (m_ph[0]) begin
            Q_hi <= M;     Q_lo <= 8'd0;
        end else if (m_ph[1]) begin
            Q_hi <= o_hi;  Q_lo <= o_md;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            wen <= 1'b0; addr <= 14'd0; data_wr <= 8'd0; fin <= 1'b0;
        end else begin
            wen <= m_ph[2];
            if (m_ph[2]) data_wr <= o_md;
            if (wen) begin
                addr <= addr + 14'd1;
                if (addr == 14'h3fff) fin <= 1'b1;
            end
        end
    end

endmodule

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

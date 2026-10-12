// MFE (fold2): folded column sorter (subsumes split1) + folded final stage.
// Verified: HW4 testfixture + 5 extra images, 49164 cycles.
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
    // Control : fetch address generator
    // ------------------------------------------------------------------
    reg  [6:0] r, c;          // current output row / column being fetched
    reg  [1:0] k;             // 0: row r-1, 1: row r, 2: row r+1
    reg        fetching;
    reg        fin;           // last result has been written

    wire last_fetch = (r == 7'd127) && (c == 7'd127) && (k == 2'd2);

    // tags that travel with the fetched pixel (aligned with idata)
    reg        f_v, f_pad, f_k0, f_k2, f_c0, f_c127;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy     <= 1'b0;
            fetching <= 1'b0;
            r <= 7'd0;  c <= 7'd0;  k <= 2'd0;
            iaddr    <= 14'd0;
            f_v <= 1'b0; f_pad <= 1'b0; f_k0 <= 1'b0; f_k2 <= 1'b0; f_c0 <= 1'b0; f_c127 <= 1'b0;
        end else begin
            f_v <= 1'b0;
            if (!busy) begin
                if (ready) begin
                    busy     <= 1'b1;
                    fetching <= 1'b1;
                end
            end else if (fin) begin
                busy <= 1'b0;
            end

            if (fetching) begin
                // issue address; idata for it is sampled on the next edge
                iaddr  <= {r + {5'd0, k} - 7'd1, c};
                f_v    <= 1'b1;
                f_pad  <= (r == 7'd0 && k == 2'd0) || (r == 7'd127 && k == 2'd2);
                f_k0   <= (k == 2'd0);
                f_k2   <= (k == 2'd2);
                f_c0   <= (c == 7'd0);
                f_c127 <= (c == 7'd127);

                if (last_fetch) fetching <= 1'b0;
                if (k == 2'd2) begin
                    k <= 2'd0;
                    c <= c + 7'd1;
                    if (c == 7'd127) r <= r + 7'd1;
                end else begin
                    k <= k + 2'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 0 + 1 (folded) : online column sort, ONE med unit reused
    //   A holds the newest pixel (tag a_k0 / col_rdy tell which one).
    //   k=0 : T_hi <= p0 , T_lo <= 0
    //   k=1 : {T_hi,T_lo} <= med(T_hi, T_lo=0, p1).{hi,md} = CAS(p0,p1)
    //   k=2 : C2 <= med(T_hi, T_lo, p2)                  = sort3
    //   med needs a >= b : k=1 -> b=0, k=2 -> T_hi >= T_lo.  Both hold.
    // ------------------------------------------------------------------
    reg [7:0] A, T_hi, T_lo;
    reg       a_k0, col_rdy, rdy_c0, rdy_c127;

    always @(posedge clk) begin
        if (f_v) A <= f_pad ? 8'd0 : idata;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            a_k0 <= 1'b0; col_rdy <= 1'b0; rdy_c0 <= 1'b0; rdy_c127 <= 1'b0;
        end else begin
            a_k0     <= f_v & f_k0;
            col_rdy  <= f_v & f_k2;      // A holds p2 -> column complete
            rdy_c0   <= f_c0;
            rdy_c127 <= f_c127;
        end
    end

    wire [7:0] s_hi, s_md, s_lo;
    // b needs 0 at k=1 : T_lo is cleared together with the p0 load, so the
    // med input needs no mux (keeps the select off the compare path)
    med u_col_med (.a(T_hi), .b(T_lo), .c(A), .hi(s_hi), .md(s_md), .lo(s_lo));

    always @(posedge clk) begin
        if (a_k0) begin
            T_hi <= A;                   // p0
            T_lo <= 8'd0;                // so that k=1 computes med(p0, 0, p1)
        end else if (!col_rdy) begin     // k=1 (also harmless when idle)
            T_hi <= s_hi;
            T_lo <= s_md;
        end
    end

    reg  [7:0] C2_hi, C2_md, C2_lo, C1_hi, C1_md, C1_lo;
    reg        inj1, inj;  // inj: load an all-zero column into C2 (2 cycles after col 127)
    reg        e2;         // C2 was updated in the previous edge
    reg        c2_first;   // C2 holds column 0 (window not valid yet)

    wire ld_c2 = col_rdy | inj;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            C2_hi <= 8'd0; C2_md <= 8'd0; C2_lo <= 8'd0;   // left pad of stripe 0
            inj1 <= 1'b0; inj <= 1'b0; e2 <= 1'b0; c2_first <= 1'b0;
        end else begin
            inj1 <= col_rdy & rdy_c127;   // col 127 just loaded
            inj  <= inj1;                 // use the 2nd idle slot so that the two
                                          // last outputs of a row are 2 cycles apart
            e2  <= ld_c2;
            if (ld_c2) begin
                C2_hi <= inj ? 8'd0 : s_hi;
                C2_md <= inj ? 8'd0 : s_md;
                C2_lo <= inj ? 8'd0 : s_lo;
                c2_first <= col_rdy & rdy_c0;
            end
        end
    end

    always @(posedge clk) begin
        if (ld_c2) begin
            C1_hi <= C2_hi; C1_md <= C2_md; C1_lo <= C2_lo;   // reuse sorted column
        end
    end

    // ------------------------------------------------------------------
    // Stage 2 : row max(C1,C2) -> R (en e2) ; row med(R, C2) -> Q/M (en e2 & valid)
    // ------------------------------------------------------------------
    wire [7:0] r1_hi, r1_lo, r2_hi, r2_lo, r3_hi, r3_lo;
    wire [7:0] m1_w, m2_w, m3_w;
    reg  [7:0] R1_hi, R1_lo, R2_hi, R2_lo, R3_hi, R3_lo;
    reg  [7:0] Q_hi, Q_lo, M2, M3;       // Q_hi = old M1 ; Q_lo : fold partner
    reg        v_m, v_f;

    max u_row1_max (.a(C1_hi), .b(C2_hi), .hi(r1_hi), .lo(r1_lo));
    max u_row2_max (.a(C1_md), .b(C2_md), .hi(r2_hi), .lo(r2_lo));
    max u_row3_max (.a(C1_lo), .b(C2_lo), .hi(r3_hi), .lo(r3_lo));

    med u_row1_med (.a(R1_hi), .b(R1_lo), .c(C2_hi), .hi(),     .md(),     .lo(m1_w));
    med u_row2_med (.a(R2_hi), .b(R2_lo), .c(C2_md), .hi(),     .md(m2_w), .lo());
    med u_row3_med (.a(R3_hi), .b(R3_lo), .c(C2_lo), .hi(m3_w), .md(),     .lo());

    wire m_ld = e2 & ~c2_first;          // a valid window is being latched

    always @(posedge clk) begin
        if (e2) begin
            R1_hi <= r1_hi; R1_lo <= r1_lo;
            R2_hi <= r2_hi; R2_lo <= r2_lo;
            R3_hi <= r3_hi; R3_lo <= r3_lo;
        end
    end

    // ------------------------------------------------------------------
    // Stage 3+4 (folded) : ONE med unit, 2 cycles per output
    //   load (m_ld) : Q_hi <= m1 , Q_lo <= 0 , M2 <= m2 , M3 <= m3
    //   v_m cycle   : {Q_hi,Q_lo} <= med(Q_hi, 0, M2).{hi,md} = CAS(m1,m2) ; M2 <= M3
    //   v_f cycle   : data_wr     <= med(Q_hi, Q_lo, M2=m3).md
    //   med needs a >= b : 0 in the first pass, Q_hi >= Q_lo in the second.
    //   Valid loads are >= 2 cycles apart (inj moved), so the passes never overlap.
    // ------------------------------------------------------------------
    wire [7:0] o_hi, o_md;
    med u_fin_med (.a(Q_hi), .b(Q_lo), .c(M2), .hi(o_hi), .md(o_md), .lo());

    always @(posedge clk) begin
        if (m_ld) begin
            Q_hi <= m1_w;  Q_lo <= 8'd0;
            M2   <= m2_w;  M3   <= m3_w;
        end else if (v_m) begin
            Q_hi <= o_hi;  Q_lo <= o_md;
            M2   <= M3;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            v_m <= 1'b0; v_f <= 1'b0;
            wen <= 1'b0; addr <= 14'd0; data_wr <= 8'd0;
            fin <= 1'b0;
        end else begin
            v_m <= m_ld;
            v_f <= v_m;
            wen <= v_f;
            if (v_f)  data_wr <= o_md;
            if (wen) begin
                addr <= addr + 14'd1;                 // raster order
                if (addr == 14'h3fff) fin <= 1'b1;    // busy drops next edge
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


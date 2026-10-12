// ============================================================================
// MFE fold4 (fold3b + raw-window sel3 row unit) -- 2021 DIC HW4 Median Filter Engine (128x128, zero padding)
//
//  Everything after the column sorter is now LANE-SERIAL:
//    * each sorted column leaves C2 as a stream  hi, md, lo  (1 value / cycle)
//    * "same lane, previous columns" = the stream 3 / 6 cycles ago, so the
//      window's raw lane values sit in a plain 6-deep shift register
//    * ONE sel3 (3 parallel compares + one AND-OR select) handles the lanes
//    * the final med consumes m1, m2, m3 as they arrive (insertion fold)
//
//  Folded units (all built from max.v / med.v):
//    S1 column : med  (k=1 CAS, k=2 sort3)                -- as fold2
//    S2 row    : sel3 (1 lane / cycle; min3 / med3 / max3 of the raw lane values)
//    S4 final  : med  (m1 load, m2 CAS, m3 median)
//
//  Padding (no pad column is fetched):
//    The window whose newest column is col 0 is useless anyway, so its 3 lane
//    cycles are reused; the zero column is handled purely in sel3's select
//    logic (no data gating):
//      col-0 slot : window (126, 127, 0)   -> output 127 of the previous row
//      col-1 slot : window (0, col0, col1) -> output 0 of this row
//    The pad slot of row 0 has no previous row: it writes garbage to 3FFF
//    (addr starts at 3FFF) which the very last output overwrites.
//    Only the very last output needs one dummy column at the end (+3 cycles once).
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
    reg  [6:0] r, c;
    reg  [1:0] k;
    reg        fetching, fin, tail;       // tail : one dummy column after (127,127)
    reg        f_v, f_pad, f_k0, f_k2, f_c0;

    wire last_fetch = tail && (k == 2'd2);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 1'b0; fetching <= 1'b0;
            r <= 7'd0; c <= 7'd0; k <= 2'd0; tail <= 1'b0;
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
                iaddr  <= {r + {5'd0, k} - 7'd1, c};
                f_v    <= 1'b1;
                f_pad  <= tail || (r == 7'd0 && k == 2'd0) || (r == 7'd127 && k == 2'd2);
                f_k0   <= (k == 2'd0);
                f_k2   <= (k == 2'd2);
                f_c0   <= (c == 7'd0);                       // tail also has c = 0
                if (last_fetch) fetching <= 1'b0;
                if (k == 2'd2) begin
                    k <= 2'd0;
                    c <= c + 7'd1;                           // wraps 127 -> 0
                    if (c == 7'd127) begin
                        r <= r + 7'd1;
                        if (r == 7'd127) tail <= 1'b1;
                    end
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
    reg [2:0] ph;                  // one-hot lane of E0 : 001 hi, 010 md, 100 lo
    reg       e_first;             // E holds col 0 of a row -> newest column of the window is the pad
    reg       e_old;               // E holds col 1 of a row -> oldest column of the window is the pad

    always @(posedge clk) begin
        E0 <= col_rdy ? s_hi : E1;
        E1 <= col_rdy ? s_md : E2;
        E2 <= s_lo;                // only its value at the load edge is ever used
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ph <= 3'b000; e_first <= 1'b0; e_old <= 1'b0;
        end else begin
            ph <= col_rdy ? 3'b001 : {ph[1:0], 1'b0};
            if (col_rdy) begin
                e_first <= rdy_c0;
                e_old   <= e_first;
            end
        end
    end

    // ------------------------------------------------------------------
    // R1..R2 : raw lane stream delayed 3 and 6 cycles (no pairs stored)
    //   c = E0 (column k) , b = D2 (column k-1) , a = D5 (column k-2)
    // ------------------------------------------------------------------
    reg [7:0] D0, D1, D2, D3, D4, D5;
    always @(posedge clk) begin
        D0 <= E0; D1 <= D0; D2 <= D1; D3 <= D2; D4 <= D3; D5 <= D4;
    end

    // ------------------------------------------------------------------
    // S2 : ONE sel3 per cycle -> M
    //   hi lane : min3 , md lane : med3 , lo lane : max3
    //   col-0 slot (e_first) : c is the zero pad column
    //   col-1 slot (e_old)   : a is the zero pad column
    // ------------------------------------------------------------------
    wire [7:0] m_w;
    sel3 u_row_sel (.a(D5), .b(D2), .c(E0), .lane(ph), .pad_c(e_first), .pad_a(e_old), .y(m_w));

    reg [7:0] M;
    reg [2:0] m_ph;                // one-hot: M holds m1 / m2 / m3
    always @(posedge clk) begin
        M <= m_w;
    end
    always @(posedge clk or posedge reset) begin
        if (reset) m_ph <= 3'b000;
        else       m_ph <= ph;     // every slot writes (the very first one is garbage, see addr)
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
            wen <= 1'b0; addr <= 14'h3fff; data_wr <= 8'd0; fin <= 1'b0;
        end else begin
            wen <= m_ph[2];
            if (m_ph[2]) data_wr <= o_md;
            if (wen) begin
                addr <= addr + 14'd1;
                // 1st write (garbage, pad slot of row 0) -> 3FFF, then 0 .. 3FFF;
                // the last write (127,127) overwrites 3FFF, and only then tail = 1
                if (addr == 14'h3fff && tail) fin <= 1'b1;
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

// ============================================================================
// sel3 : order statistic of three UNSORTED values, chosen per lane.
//   3 compares in parallel, then a one-hot AND-OR select of a / b / c / 0.
// ============================================================================
module sel3(
    input  wire [7:0] a, b, c,
    input  wire [2:0] lane,        // 001 : min3 , 010 : med3 , 100 : max3
    input  wire       pad_c,       // treat c as 0
    input  wire       pad_a,       // treat a as 0
    output wire [7:0] y
);
    // 3 compares in parallel
    wire ab = (a >= b);
    wire bc = (b >= c);
    wire ac = (a >= c);

    // a pad operand is 0, so its compares are known: force them (one gate level)
    //   c = 0 : b >= c , a >= c      a = 0 : a < b , a < c
    wire abf = ab & ~pad_a;
    wire bcf = bc |  pad_c;
    wire acf = (ac | pad_c) & ~pad_a;

    // same 2-level mux trees as med.v, driven straight by the compare bits
    wire [7:0] mn = bcf ? (acf ? c : a) : (abf ? b : a);                       // min3
    wire [7:0] md = (abf ~^ bcf) ? b : ((abf ~^ acf) ? c : a);                 // med3
    wire [7:0] mx = bcf ? (abf ? a : b) : (acf ? a : c);                       // max3

    // deepest tree (med3) enters the last mux level; min3 with a 0 -> 0
    wire [7:0] mnz = mn & {8{~(pad_c | pad_a)}};
    assign y = lane[1] ? md : (lane[0] ? mnz : mx);
endmodule

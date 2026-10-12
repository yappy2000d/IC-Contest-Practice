// ============================================================================
// MFE.v (variant: split1) -- 2021 DIC HW4 Median Filter Engine
//
//  跟 handwritten_rtl/MFE.v 唯一的差異：把目前的 critical path
//  (u_col_max -> u_col_med, 同拍直接串接) 從中間切開，插一級暫存器
//  (S_hi0/S_lo0/A_d)，把 max 的輸出跟 A 先存起來，下一拍才餵給 med。
//  這樣整條路徑多了 1 cycle 的 latency，換來 col chain 本身的組合邏輯
//  深度砍半，用來量化「往瓶頸多切一刀」能把 fmax 推多高。
//
//  所有跟著 col_rdy 走的控制訊號 (rdy_c0/rdy_c127/inj/e2/c2_first 的判斷
//  基準) 都要跟著多存一拍，才能對齊新插入的暫存器。
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
    // Control : fetch address generator
    // ------------------------------------------------------------------
    reg  [6:0] r, c;          // current output row / column being fetched
    reg  [1:0] k;             // 0: row r-1, 1: row r, 2: row r+1
    reg        fetching;
    reg        fin;           // last result has been written

    wire last_fetch = (r == 7'd127) && (c == 7'd127) && (k == 2'd2);

    // tags that travel with the fetched pixel (aligned with idata)
    reg        f_v, f_pad, f_k2, f_c0, f_c127;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy     <= 1'b0;
            fetching <= 1'b0;
            r <= 7'd0;  c <= 7'd0;  k <= 2'd0;
            iaddr    <= 14'd0;
            f_v <= 1'b0; f_pad <= 1'b0; f_k2 <= 1'b0; f_c0 <= 1'b0; f_c127 <= 1'b0;
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
    // Stage 0 : A -> B -> C  (serial column assembly)
    // ------------------------------------------------------------------
    reg [7:0] A, B, C;
    reg       col_rdy, rdy_c0, rdy_c127;

    always @(posedge clk) begin
        if (f_v) begin
            A <= f_pad ? 8'd0 : idata;   // newest (row r+1)
            B <= A;
            C <= B;                      // oldest (row r-1)
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            col_rdy <= 1'b0; rdy_c0 <= 1'b0; rdy_c127 <= 1'b0;
        end else begin
            col_rdy  <= f_v & f_k2;
            rdy_c0   <= f_c0;
            rdy_c127 <= f_c127;
        end
    end

    // ------------------------------------------------------------------
    // Stage 1a : max(C,B) -> S_hi0/S_lo0 (registered), A -> A_d (registered)
    //   拆開瓶頸的第一刀：max 的輸出先存起來，med 下一拍才吃。
    // ------------------------------------------------------------------
    wire [7:0] s_hi0, s_lo0;
    max u_col_max (.a(C), .b(B), .hi(s_hi0), .lo(s_lo0));

    reg [7:0] S_hi0, S_lo0, A_d;
    reg       col_rdy2, rdy_c0_d, rdy_c127_d;

    always @(posedge clk) begin
        if (col_rdy) begin
            S_hi0 <= s_hi0;
            S_lo0 <= s_lo0;
            A_d   <= A;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            col_rdy2 <= 1'b0; rdy_c0_d <= 1'b0; rdy_c127_d <= 1'b0;
        end else begin
            col_rdy2   <= col_rdy;
            rdy_c0_d   <= rdy_c0;
            rdy_c127_d <= rdy_c127;
        end
    end

    // ------------------------------------------------------------------
    // Stage 1b : med(S_hi0,S_lo0,A_d) -> C2 ; C2 -> C1 ; zero-column inject
    //   跟原本一樣，只是輸入來源、判斷用的 col_rdy/rdy_c0/rdy_c127 都換成
    //   多存一拍後的版本 (col_rdy2/rdy_c0_d/rdy_c127_d)。
    // ------------------------------------------------------------------
    wire [7:0] s_hi, s_md, s_lo;
    med u_col_med (.a(S_hi0), .b(S_lo0), .c(A_d), .hi(s_hi), .md(s_md), .lo(s_lo));

    reg  [7:0] C2_hi, C2_md, C2_lo, C1_hi, C1_md, C1_lo;
    reg        inj;        // load an all-zero column into C2
    reg        e2;         // C2 was updated in the previous edge
    reg        c2_first;   // C2 holds column 0 (window not valid yet)

    wire ld_c2 = col_rdy2 | inj;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            C2_hi <= 8'd0; C2_md <= 8'd0; C2_lo <= 8'd0;   // left pad of stripe 0
            inj <= 1'b0; e2 <= 1'b0; c2_first <= 1'b0;
        end else begin
            inj <= col_rdy2 & rdy_c127_d;
            e2  <= ld_c2;
            if (ld_c2) begin
                C2_hi <= inj ? 8'd0 : s_hi;
                C2_md <= inj ? 8'd0 : s_md;
                C2_lo <= inj ? 8'd0 : s_lo;
                c2_first <= col_rdy2 & rdy_c0_d;
            end
        end
    end

    always @(posedge clk) begin
        if (ld_c2) begin
            C1_hi <= C2_hi; C1_md <= C2_md; C1_lo <= C2_lo;   // reuse sorted column
        end
    end

    // ------------------------------------------------------------------
    // Stage 2 : row max(C1,C2) -> R ; row med(R, C2) -> M   (both on e2)
    // ------------------------------------------------------------------
    wire [7:0] r1_hi, r1_lo, r2_hi, r2_lo, r3_hi, r3_lo;
    wire [7:0] m1_w, m2_w, m3_w;
    reg  [7:0] R1_hi, R1_lo, R2_hi, R2_lo, R3_hi, R3_lo;
    reg  [7:0] M1, M2, M3;
    reg        v_m;

    max u_row1_max (.a(C1_hi), .b(C2_hi), .hi(r1_hi), .lo(r1_lo));
    max u_row2_max (.a(C1_md), .b(C2_md), .hi(r2_hi), .lo(r2_lo));
    max u_row3_max (.a(C1_lo), .b(C2_lo), .hi(r3_hi), .lo(r3_lo));

    med u_row1_med (.a(R1_hi), .b(R1_lo), .c(C2_hi), .hi(),     .md(),     .lo(m1_w));
    med u_row2_med (.a(R2_hi), .b(R2_lo), .c(C2_md), .hi(),     .md(m2_w), .lo());
    med u_row3_med (.a(R3_hi), .b(R3_lo), .c(C2_lo), .hi(m3_w), .md(),     .lo());

    always @(posedge clk) begin
        if (e2) begin
            R1_hi <= r1_hi; R1_lo <= r1_lo;
            R2_hi <= r2_hi; R2_lo <= r2_lo;
            R3_hi <= r3_hi; R3_lo <= r3_lo;
            M1 <= m1_w;  M2 <= m2_w;  M3 <= m3_w;
        end
    end

    // ------------------------------------------------------------------
    // Stage 3 : max(M1,M2), M3 delay -> F
    // ------------------------------------------------------------------
    wire [7:0] f_hi, f_lo, o_md;
    reg  [7:0] F_hi, F_lo, F3;
    reg        v_f;

    max u_fin_max (.a(M1), .b(M2), .hi(f_hi), .lo(f_lo));

    always @(posedge clk) begin
        if (v_m) begin
            F_hi <= f_hi;
            F_lo <= f_lo;
            F3   <= M3;
        end
    end

    // ------------------------------------------------------------------
    // Stage 4 : final med -> result memory write
    // ------------------------------------------------------------------
    med u_fin_med (.a(F_hi), .b(F_lo), .c(F3), .hi(), .md(o_md), .lo());

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            v_m <= 1'b0; v_f <= 1'b0;
            wen <= 1'b0; addr <= 14'd0; data_wr <= 8'd0;
            fin <= 1'b0;
        end else begin
            v_m <= e2 & ~c2_first;
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

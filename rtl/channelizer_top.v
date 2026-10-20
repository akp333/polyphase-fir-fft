`timescale 1ns/1ps

module channelizer_top (
    input  wire clk,
    input  wire rst, // synchronous, active high
    input  wire cfg_we, // write enable for h storage
    input  wire [4:0]  cfg_addr, // address for h
    input  wire signed [15:0] cfg_data, // data stored in h storage at address
    input  wire in_valid, // in_data is meaningful this cycle
    input  wire signed [15:0] in_data, // input sample
    output reg out_valid, // out_data is meaningful this cycle
    output reg [2:0]  out_idx, // which bin is on the output
    output reg signed [15:0] out_re, // real part of output bin
    output reg signed [15:0] out_im // imaginary part of output bin
);

    function signed [15:0] rnd15_sat;
        input signed [33:0] s;
        reg signed [33:0] q;
        reg signed [33:0] r;
        reg [14:0] rem;
        reg up;
        begin
            q = s >>> 15;
            rem = s[14:0];
            up = (rem > 15'h4000) || ((rem == 15'h4000) && q[0]);
            r = q + $signed({33'd0, up});
            if (r > 34'sd32767) rnd15_sat = 16'sh7FFF;
            else if (r < -34'sd32768) rnd15_sat = 16'sh8000;
            else rnd15_sat = r[15:0];
        end
    endfunction

    function signed [15:0] rnd3_sat;
        input signed [18:0] s;
        reg signed [18:0] q;
        reg signed [19:0] r;
        reg [2:0]  rem;
        reg up;
        begin
            q = s >>> 3;
            rem = s[2:0];
            up = (rem > 3'd4) || ((rem == 3'd4) && q[0]);
            r = q + $signed({19'd0, up});
            if (r > 20'sd32767) rnd3_sat = 16'sh7FFF;
            else if (r < -20'sd32768) rnd3_sat = 16'sh8000;
            else rnd3_sat = r[15:0];
        end
    endfunction

    reg [511:0] hflat;
    integer kc;
    always @(posedge clk) begin
        for (kc = 0; kc < 32; kc = kc + 1)
            if (cfg_we && (cfg_addr == kc))
                hflat[16*kc +: 16] <= cfg_data;
    end

    reg [2:0] cnt; // counts 7...0, equals branch index r of the sample being accepted
    reg s0_v, s1_v, s2_v; // valid tags 
    reg [2:0] s0_r, s1_r, s2_r; // branch tags
    reg s3_done, f0_done; // s3_done implies all values of v are ready...
    reg ser_active; // output active
    reg [2:0] ser_idx; // output bin index

    always @(posedge clk) begin
        if (rst) begin
            cnt <= 3'd7;
            s0_v <= 1'b0;
            s1_v <= 1'b0;
            s2_v <= 1'b0;
            s3_done <= 1'b0;
            f0_done <= 1'b0;
            ser_active <= 1'b0;
            ser_idx <= 3'd0;
            out_valid <= 1'b0;
            out_idx <= 3'd0;
        end 
        else begin
            s0_v <= in_valid;
            s1_v <= s0_v;
            s2_v <= s1_v;
            s3_done <= s2_v && (s2_r == 3'd0);
            f0_done <= s3_done;
            if (in_valid) cnt <= cnt - 3'd1; // 0 wraps to 7

            if (f0_done) begin
                ser_active <= 1'b1;
                ser_idx    <= 3'd0;
            end else if (ser_active) begin
                if (ser_idx == 3'd7) ser_active <= 1'b0;
                ser_idx <= ser_idx + 3'd1; // 7 wraps to 0
            end

            out_valid <= ser_active;
            out_idx   <= ser_idx;
        end
    end

    // S0

    reg [399:0] dl;
    always @(posedge clk) begin
        if (rst) dl <= 400'd0;
        else if (in_valid) dl <= {dl[383:0], in_data};
    end

    wire signed [15:0] tap0 = dl[0 +: 16];
    wire signed [15:0] tap1 = dl[128 +: 16];
    wire signed [15:0] tap2 = dl[256 +: 16];
    wire signed [15:0] tap3 = dl[384 +: 16];

    wire [8:0] ha0 = {2'd0, cnt, 4'd0};
    wire [8:0] ha1 = {2'd1, cnt, 4'd0};
    wire [8:0] ha2 = {2'd2, cnt, 4'd0};
    wire [8:0] ha3 = {2'd3, cnt, 4'd0};
    
    wire signed [15:0] c0_w = hflat[ha0 +: 16];
    wire signed [15:0] c1_w = hflat[ha1 +: 16];
    wire signed [15:0] c2_w = hflat[ha2 +: 16];
    wire signed [15:0] c3_w = hflat[ha3 +: 16];

    reg signed [15:0] s0_c0, s0_c1, s0_c2, s0_c3;

    // S1

    reg signed [31:0] s1_p0, s1_p1, s1_p2, s1_p3;
    reg signed [33:0] s2_sum;
    reg [127:0] vreg; 

    wire signed [32:0] sum_a = s1_p0 + s1_p1;
    wire signed [32:0] sum_b = s1_p2 + s1_p3;
    wire signed [33:0] sum_t = sum_a + sum_b;
    wire signed [15:0] v_new = rnd15_sat(s2_sum);

    integer kv;

    // F0

    wire signed [15:0] v0 = vreg[0 +: 16];
    wire signed [15:0] v1 = vreg[16 +: 16];
    wire signed [15:0] v2 = vreg[32 +: 16];
    wire signed [15:0] v3 = vreg[48 +: 16];
    wire signed [15:0] v4 = vreg[64 +: 16];
    wire signed [15:0] v5 = vreg[80 +: 16];
    wire signed [15:0] v6 = vreg[96 +: 16];
    wire signed [15:0] v7 = vreg[112 +: 16];

    wire signed [16:0] e_s0 = v0 + v4;
    wire signed [16:0] e_s1 = v2 + v6;
    wire signed [16:0] e_d0 = v0 - v4;
    wire signed [16:0] e_d1 = v2 - v6;
    wire signed [17:0] e_x0 = e_s0 + e_s1;
    wire signed [17:0] e_x2 = e_s0 - e_s1;

    wire signed [16:0] o_s0 = v1 + v5;
    wire signed [16:0] o_s1 = v3 + v7;
    wire signed [16:0] o_d0 = v1 - v5;
    wire signed [16:0] o_d1 = v3 - v7;
    wire signed [17:0] o_x0 = o_s0 + o_s1;
    wire signed [17:0] o_x2 = o_s0 - o_s1;
    wire signed [17:0] o_a = o_d0 - o_d1;
    wire signed [17:0] o_b = o_d0 + o_d1;

    reg signed [17:0] f0_e0, f0_e2, f0_o0, f0_o2, f0_a, f0_b;
    reg signed [16:0] f0_ed0, f0_ed1;

    // F1

    wire signed [26:0] mu = f0_a * 9'sd181;
    wire signed [26:0] mw = f0_b * 9'sd181;
    wire signed [17:0] u  = mu >>> 8;
    wire signed [17:0] w  = mw >>> 8;

    wire signed [18:0] y0r = f0_e0 + f0_o0;
    wire signed [18:0] y4r = f0_e0 - f0_o0;
    wire signed [18:0] y2r = f0_e2;
    wire signed [18:0] y2i = -f0_o2;
    wire signed [18:0] y6r = f0_e2;
    wire signed [18:0] y6i = f0_o2;
    wire signed [18:0] y1r = f0_ed0 + u;
    wire signed [18:0] y1i = -f0_ed1 - w;
    wire signed [18:0] y5r = f0_ed0 - u;
    wire signed [18:0] y5i = -f0_ed1 + w;
    wire signed [18:0] y3r = f0_ed0 - u;
    wire signed [18:0] y3i = f0_ed1 - w;
    wire signed [18:0] y7r = f0_ed0 + u;
    wire signed [18:0] y7i = f0_ed1 + w;

    reg [151:0] f1_re, f1_im;

    // F2

    wire signed [18:0] sel_re = f1_re[19*ser_idx +: 19];
    wire signed [18:0] sel_im = f1_im[19*ser_idx +: 19];

    // datapath registers

    always @(posedge clk) begin
        // S0
        s0_r  <= cnt;
        s0_c0 <= c0_w;
        s0_c1 <= c1_w;
        s0_c2 <= c2_w;
        s0_c3 <= c3_w;
        // S1
        s1_r  <= s0_r;
        s1_p0 <= tap0 * s0_c0;
        s1_p1 <= tap1 * s0_c1;
        s1_p2 <= tap2 * s0_c2;
        s1_p3 <= tap3 * s0_c3;
        // S2
        s2_r   <= s1_r;
        s2_sum <= sum_t;
        // S3
        for (kv = 0; kv < 8; kv = kv + 1)
            if (s2_v && (s2_r == kv))
                vreg[16*kv +: 16] <= v_new;
        // F0
        f0_e0  <= e_x0;
        f0_e2  <= e_x2;
        f0_o0  <= o_x0;
        f0_o2  <= o_x2;
        f0_a   <= o_a;
        f0_b   <= o_b;
        f0_ed0 <= e_d0;
        f0_ed1 <= e_d1;
        // F1
        if (f0_done) begin
            f1_re <= {y7r, y6r, y5r, y4r, y3r, y2r, y1r, y0r};
            f1_im <= {y7i, y6i, y5i, 19'sd0, y3i, y2i, y1i, 19'sd0};
        end
        // F2
        out_re <= rnd3_sat(sel_re);
        out_im <= rnd3_sat(sel_im);
    end

endmodule

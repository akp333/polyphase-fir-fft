`timescale 1ns/1ps

module tb_channelizer;

    localparam integer MAXN = 16384;

    reg clk = 1'b0;
    always #5 clk = ~clk; // 10 ns period = 100 MHz

    reg rst = 1'b1;
    reg cfg_we = 1'b0;
    reg [4:0]  cfg_addr = 5'd0;
    reg signed [15:0] cfg_data = 16'sd0;
    reg in_valid = 1'b0;
    reg signed [15:0] in_data = 16'sd0;
    wire out_valid;
    wire [2:0]  out_idx;
    wire signed [15:0] out_re, out_im;

    channelizer_top dut (
        .clk(clk), .rst(rst),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_data(cfg_data),
        .in_valid(in_valid), .in_data(in_data),
        .out_valid(out_valid), .out_idx(out_idx), .out_re(out_re), .out_im(out_im)
    );

    reg [15:0] x_mem [0:MAXN-1];
    reg [15:0] h_mem [0:31];
    reg [15:0] e_mem [0:2*MAXN-1];

    reg [8*256-1:0] fx, fh, fe, tag;
    integer N, F, GAP, SKIP;
    integer i;

    integer cyc = 0;
    integer in_cnt = 0;
    integer out_cnt = 0;
    integer t_newest = -1, t_first = -1;
    integer max_err = 0;  // frames >= SKIP
    integer max_err_all = 0; // all frames
    integer bad = 0, idx_err = 0, x_err = 0, extra = 0;
    integer d_re, d_im, fr;

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (!rst && in_valid) begin
            if (in_cnt == 7) t_newest = cyc;
            in_cnt = in_cnt + 1;
        end
        if (!rst && out_valid) begin
            if (out_idx !== (out_cnt % 8)) idx_err = idx_err + 1;
            if (out_cnt == 0) t_first = cyc;
            if (out_cnt >= 8*F) begin
                extra = extra + 1;
            end else if ((^{out_re, out_im}) === 1'bx) begin
                x_err = x_err + 1;
            end else begin
                d_re = $signed(out_re) - $signed(e_mem[2*out_cnt]);
                d_im = $signed(out_im) - $signed(e_mem[2*out_cnt + 1]);
                if (d_re < 0) d_re = -d_re;
                if (d_im < 0) d_im = -d_im;
                if (d_re > max_err_all) max_err_all = d_re;
                if (d_im > max_err_all) max_err_all = d_im;
                fr = out_cnt / 8;
                if (fr >= SKIP) begin
                    if (d_re > max_err) max_err = d_re;
                    if (d_im > max_err) max_err = d_im;
                    if (d_re > 2 || d_im > 2) begin
                        bad = bad + 1;
                        if (bad <= 5)
                            $display("  MISMATCH frame %0d bin %0d: got (%0d,%0d) exp (%0d,%0d)",
                                     fr, out_cnt % 8, $signed(out_re), $signed(out_im),
                                     $signed(e_mem[2*out_cnt]), $signed(e_mem[2*out_cnt+1]));
                    end
                end
            end
            out_cnt = out_cnt + 1;
        end
    end

    initial begin
        if (!$value$plusargs("XF=%s", fx) || !$value$plusargs("HF=%s", fh) ||
            !$value$plusargs("EF=%s", fe)) begin
            $display("ERROR: need +XF=<x.hex> +HF=<h.hex> +EF=<exp.hex>");
            $finish;
        end
        if (!$value$plusargs("N=%d", N)) N = 1024;
        if (!$value$plusargs("GAP=%d", GAP)) GAP = 0;
        if (!$value$plusargs("SKIP=%d", SKIP)) SKIP = 3;
        if (!$value$plusargs("TAG=%s", tag)) tag = "test";
        F = N / 8;

        $readmemh(fx, x_mem);
        $readmemh(fh, h_mem);
        $readmemh(fe, e_mem);

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        // load the 32 prototype-filter coefficients
        for (i = 0; i < 32; i = i + 1) begin
            cfg_we <= 1'b1; cfg_addr <= i[4:0]; cfg_data <= h_mem[i];
            @(posedge clk);
        end
        cfg_we <= 1'b0;
        repeat (3) @(posedge clk);

        // stream the samples (one per cycle, optional random stalls)
        i = 0;
        while (i < N) begin
            if (GAP > 0 && ($urandom_range(99, 0) < GAP)) begin
                in_valid <= 1'b0;
            end else begin
                in_valid <= 1'b1;
                in_data  <= x_mem[i];
                i = i + 1;
            end
            @(posedge clk);
        end
        in_valid <= 1'b0;
        repeat (60) @(posedge clk);

        if (bad == 0 && idx_err == 0 && x_err == 0 && extra == 0 && out_cnt == 8*F)
            $display("PASS  %0s : frames=%0d outputs=%0d max_err=%0d LSB (all frames: %0d) latency=%0d cycles",
                     tag, F, out_cnt, max_err, max_err_all, t_first - t_newest);
        else
            $display("FAIL  %0s : outputs=%0d (expected %0d) bad=%0d idx_err=%0d x_err=%0d extra=%0d max_err=%0d",
                     tag, out_cnt, 8*F, bad, idx_err, x_err, extra, max_err);
        $finish;
    end

endmodule

`timescale 1ns/1ps
`default_nettype none

module tb_renderer_visibility_bist;
    localparam integer PASS_CLOCKS = 1060;
    localparam [6:0] SEG_P = 7'b1110011;
    localparam [6:0] SEG_MINUS = 7'b1000000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] request = 8'h00;
    wire [7:0] healthy_diag, black_diag, glow_diag, transient_diag;
    wire [7:0] video;
    integer elapsed;

    tt_um_rayforge_3d healthy (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(request), .uio_in(8'h00),
        .uio_out(healthy_diag), .uio_oe(), .uo_out(video)
    );
    tt_um_rayforge_3d stuck_black (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(request), .uio_in(8'h00),
        .uio_out(black_diag), .uio_oe(), .uo_out()
    );
    tt_um_rayforge_3d blanking_leak (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(request), .uio_in(8'h00),
        .uio_out(glow_diag), .uio_oe(), .uo_out()
    );
    tt_um_rayforge_3d single_drop (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(request), .uio_in(8'h00),
        .uio_out(transient_diag), .uio_oe(), .uo_out()
    );

    always #19.861 clk = ~clk;

    initial begin
        force stuck_black.red_sig = 2'b00;
        force stuck_black.green_sig = 2'b00;
        force stuck_black.blue_sig = 2'b00;
        force blanking_leak.red_sig = 2'b10;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (40) @(negedge clk);
        request[7] = 1'b1;

        for (elapsed = 0; elapsed <= PASS_CLOCKS; elapsed = elapsed + 1) begin
            if (healthy_diag[7] !== (elapsed == PASS_CLOCKS))
                $fatal(1, "Healthy diagnostic PASS timing changed at clock %0d", elapsed);
            if ({black_diag[7], glow_diag[7], transient_diag[7]} !== 3'b000)
                $fatal(1, "Faulty renderer reported PASS at clock %0d", elapsed);

            // Force precisely one sampled active pixel black during capture.
            if (elapsed == 110) begin
                force single_drop.red_sig = 2'b00;
                force single_drop.green_sig = 2'b00;
                force single_drop.blue_sig = 2'b00;
            end
            if (elapsed == 111) begin
                release single_drop.red_sig;
                release single_drop.green_sig;
                release single_drop.blue_sig;
            end
            @(negedge clk);
        end

        if (healthy_diag !== {1'b1, SEG_P})
            $fatal(1, "Healthy renderer did not retain the steady P indicator");
        if (black_diag !== {1'b0, SEG_MINUS} || glow_diag !== {1'b0, SEG_MINUS} ||
            transient_diag !== {1'b0, SEG_MINUS})
            $fatal(1, "Faulty renderer did not retain the failed status");

        $display("PASS healthy BIST at %0d clocks, persistent black, blanking leak, and single active drop detected",
                 PASS_CLOCKS);

        // Repeat from the visible VSYNC edge. This captures only blanking,
        // so a black clamp is unactivated but a blanking leak is detected.
        request[7] = 1'b0;
        @(negedge video[3]);
        @(negedge clk);
        request[7] = 1'b1;
        repeat (PASS_CLOCKS) @(negedge clk);
        if ({healthy_diag[7], black_diag[7], glow_diag[7], transient_diag[7]} !== 4'b1101)
            $fatal(1, "Unexpected verdicts for a wholly blank capture window");
        $display("PASS vertical blank capture detected the leak and left the black clamp unactivated");
        $finish;
    end

    initial begin
        repeat (800 * 525 * 2) @(posedge clk);
        $fatal(1, "Timed out waiting for the vertical blank diagnostic case");
    end
endmodule
`default_nettype wire

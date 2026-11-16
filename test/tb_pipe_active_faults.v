`timescale 1ns/1ps
`default_nettype none

module tb_pipe_active_faults;
    localparam integer FRAME = 800 * 525;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] ui = 8'h00;
    wire [7:0] healthy_video, stuck_low_video, stuck_high_video;
    wire [7:0] healthy_diag, stuck_low_diag, stuck_high_diag;

    tt_um_rayforge_3d healthy (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(ui), .uio_in(8'h00),
        .uo_out(healthy_video), .uio_out(healthy_diag), .uio_oe()
    );
    tt_um_rayforge_3d stuck_low (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(ui), .uio_in(8'h00),
        .uo_out(stuck_low_video), .uio_out(stuck_low_diag), .uio_oe()
    );
    tt_um_rayforge_3d stuck_high (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(ui), .uio_in(8'h00),
        .uo_out(stuck_high_video), .uio_out(stuck_high_diag), .uio_oe()
    );
    always #19.861 clk = ~clk;

    integer moved, expected_reject;
    reg old_vsync, found_vsync;
    initial begin
        if (!$value$plusargs("expected_reject=%d", expected_reject)
            || (expected_reject != 0 && expected_reject != 1))
            $fatal(1, "Specify +expected_reject=0 (old) or 1 (independent reference)");
        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        old_vsync = 1'b1;
        found_vsync = 1'b0;
        for (moved = 0; moved < FRAME && !found_vsync; moved = moved + 1) begin
            @(negedge clk);
            found_vsync = old_vsync && healthy_video[3] === 1'b0;
            old_vsync = healthy_video[3];
        end
        if (!found_vsync) $fatal(1, "Could not reach vertical blank");

        force stuck_low.pipe_active = 1'b0;
        force stuck_high.pipe_active = 1'b1;
        ui[7] = 1'b1;
        repeat (1100) @(negedge clk);
        if ((healthy_video & 8'h77) !== 8'h00 || (stuck_high_video & 8'h77) === 8'h00)
            $fatal(1, "SA1 was not activated in vertical blank");
        $display("VBLANK: healthy=%0d SA0=%0d SA1=%0d", healthy_diag[7], stuck_low_diag[7], stuck_high_diag[7]);
        if (healthy_diag[7] !== 1'b1 || stuck_low_diag[7] !== 1'b1
            || stuck_high_diag[7] !== !expected_reject[0])
            $fatal(1, "Unexpected diagnostic result in vertical blank");

        ui[7] = 1'b0;
        repeat (45 * 800 - 1100) @(negedge clk); // x=0,y=10 in the next frame
        ui[7] = 1'b1;
        repeat (1100) @(negedge clk);
        if ((healthy_video & 8'h77) === 8'h00 || (stuck_low_video & 8'h77) !== 8'h00)
            $fatal(1, "SA0 was not activated in visible scanout");
        $display("ACTIVE: healthy=%0d SA0=%0d SA1=%0d", healthy_diag[7], stuck_low_diag[7], stuck_high_diag[7]);
        if (healthy_diag[7] !== 1'b1 || stuck_low_diag[7] !== !expected_reject[0])
            $fatal(1, "Unexpected diagnostic result in visible scanout");
        release stuck_low.pipe_active;
        release stuck_high.pipe_active;
        $display("PASS expected renderer-enable fault behavior (expected_reject=%0d)", expected_reject);
        $finish;
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_scene_stability;
    localparam integer LINE = 800;
    localparam integer FRAME = LINE * 525;
    localparam integer VBLANK = FRAME - 10 * LINE;
    localparam integer CUBE_SAMPLE = VBLANK + FRAME;
    localparam integer TORUS_ONLY = (525 - 490 + 100) * LINE + 320;
    localparam integer CUBE_ONLY = (525 - 490 + 190) * LINE + 320;
    localparam [5:0] YELLOW = 6'b11_11_00;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] ui = 8'h18; // torus silhouette
    wire [7:0] video;
    wire [5:0] rgb = {video[0], video[4], video[1], video[5], video[2], video[6]};
    wire [7:0] diag, oe;
    integer elapsed, frame_number, frame_cycle;
    reg expect_cube;

    tt_um_rayforge_3d dut (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(ui), .uio_in(8'h00),
        .uo_out(video), .uio_out(diag), .uio_oe(oe)
    );

    always #19.861 clk = ~clk;

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        wait (video[3] === 1'b1);
        @(negedge video[3]);
        @(negedge clk);

        for (elapsed = 0; elapsed <= 4 * FRAME + CUBE_ONLY; elapsed = elapsed + 1) begin
            frame_number = elapsed / FRAME;
            frame_cycle = elapsed % FRAME;
            expect_cube = frame_number == 4;
            // The two shapes disagree at both recovered pixel positions.
            if (frame_number > 0 && frame_cycle == TORUS_ONLY &&
                (rgb == YELLOW) !== !expect_cube)
                $fatal(1, "Frame %0d: wrong silhouette at (320,100), expected cube=%0b", frame_number, expect_cube);
            if (frame_number > 0 && frame_cycle == CUBE_ONLY &&
                (rgb == YELLOW) !== expect_cube)
                $fatal(1, "Frame %0d: wrong silhouette at (320,190), expected cube=%0b", frame_number, expect_cube);

            if (elapsed == CUBE_SAMPLE - 1024)
                ui = 8'h1a;
            // Both endpoint samples see the cube request. Briefly change
            // another scene bit between them before restoring the request.
            if (elapsed == CUBE_SAMPLE + FRAME / 2)
                ui = 8'h3a;
            if (elapsed == CUBE_SAMPLE + FRAME / 2 + 16)
                ui = 8'h1a;
            @(negedge clk);
        end
        $display("PASS scene word excursion between vblanks rejected, stable cube committed");
        $finish;
    end

    initial begin
        repeat (6 * FRAME) @(posedge clk);
        $fatal(1, "Timed out verifying scene stability");
    end
endmodule
`default_nettype wire

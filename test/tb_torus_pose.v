`timescale 1ns/1ps
`default_nettype none

module tb_torus_pose;
    localparam integer H_TOTAL = 800;
    localparam integer V_TOTAL = 525;
    localparam integer FRAME_SAMPLES = H_TOTAL * V_TOTAL;
    localparam [5:0] OBJECT_YELLOW = 6'b11_11_00;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] scene = 8'h18;
    wire [7:0] video;
    wire [5:0] rgb = {video[0], video[4], video[1], video[5], video[2], video[6]};
    integer frame, sample, x, y, dx_abs, dy, from_cap, distance_sq, hits;
    reg edge_on, visible, expected_hit;

    tt_um_rayforge_3d dut (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(scene), .uio_in(8'h00),
        .uo_out(video), .uio_out(), .uio_oe()
    );

    always #19.861 clk = ~clk;

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        wait (video[3] === 1'b1);
        @(negedge video[3]);
        // Derive x=0,y=0 from the observed falling edge at x=0,y=490.
        repeat ((V_TOTAL - 490) * H_TOTAL + 1) @(negedge clk);

        for (frame = 0; frame < 7; frame = frame + 1) begin
            hits = 0;
            edge_on = frame == 4 || frame == 5;
            for (sample = 0; sample < FRAME_SAMPLES; sample = sample + 1) begin
                x = sample % H_TOTAL;
                y = sample / H_TOTAL;
                visible = x < 640 && y < 480;
                if (video[7] !== !(656 <= x && x < 752) ||
                    video[3] !== !(490 <= y && y < 492) ||
                    (rgb != 0) !== visible || (^video) === 1'bx)
                    $fatal(1, "VGA sync, blanking or unknown state at frame %0d pixel (%0d,%0d)", frame, x, y);

                if (frame != 0) begin
                    dx_abs = x < 320 ? 320 - x : x - 320;
                    dy = y - 190;
                    if (edge_on) begin
                        from_cap = dx_abs > 75 ? dx_abs - 75 : 0;
                        expected_hit = from_cap * from_cap + dy * dy <= 1225;
                    end else begin
                        distance_sq = dx_abs * dx_abs + dy * dy;
                        expected_hit = 1600 <= distance_sq && distance_sq <= 12100;
                    end
                    if ((rgb == OBJECT_YELLOW) !== expected_hit)
                        $fatal(1, "Mask mismatch in frame %0d edge_on=%0b pixel (%0d,%0d)", frame, edge_on, x, y);
                    hits = hits + expected_hit;
                end

                if (frame == 1 && sample == H_TOTAL * 10)
                    scene[2] = 1'b1;
                // Reject an intervening toggle even though both vblanks match.
                if (frame == 2 && sample == H_TOTAL * 100)
                    scene[2] = 1'b0;
                if (frame == 2 && sample == H_TOTAL * 100 + 16)
                    scene[2] = 1'b1;
                if (frame == 4 && sample == H_TOTAL * 10)
                    scene[2] = 1'b0;
                @(negedge clk);
            end
            if (frame != 0 && hits != (edge_on ? 14503 : 32968))
                $fatal(1, "Bad silhouette population: %0d", hits);
            $display("Frame %0d: edge_on=%0b, checked object pixels=%0d", frame, edge_on, hits);
        end
        $display("PASS full VGA mask and blanking-qualified pose on/off transitions");
        $finish;
    end

    initial begin
        repeat (9 * FRAME_SAMPLES) @(posedge clk);
        $fatal(1, "VGA pose test timed out");
    end
endmodule
`default_nettype wire

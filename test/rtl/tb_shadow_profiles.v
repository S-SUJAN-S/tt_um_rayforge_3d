`timescale 1ns/1ps
`default_nettype none

module tb_shadow_profiles;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg [9:0] x = 10'd320;
    reg [9:0] y = 10'd320;
    reg video_active = 1'b1;
    reg [2:0] light_angle;
    reg cube_select, capsule_shape, profile_mode;
    reg [1:0] profile_size;
    wire in_shadow;

    perspective_ground dut (
        .clk(clk), .rst_n(rst_n), .pixel_x(x), .pixel_y(y),
        .video_active(video_active), .light_angle(light_angle),
        .cube_select(cube_select), .capsule_shape(capsule_shape),
        .profile_mode(profile_mode), .profile_shadow_size(profile_size),
        .is_floor(), .floor_check(), .in_shadow(in_shadow), .fog_level()
    );

    function automatic bit footprint(input integer scene, angle, px, py);
        integer center, dx, dy, width, depth, size_group;
        bit hollow_center, corner, trimmed_edge;
        begin
            case (angle)
                0: center = 296;
                1, 7: center = 304;
                3, 5: center = 336;
                4: center = 344;
                default: center = 320;
            endcase
            // Half-open intervals give equal coverage on both sides of a center.
            dx = (px < center ? center - 1 - px : px - center) / 8;
            dy = (py < 320 ? 319 - py : py - 320) / 8;
            size_group = scene >= 7 ? scene - 7 : scene - 3;
            case (scene)
                0: begin width = 6; depth = 3; end
                1: begin width = 4; depth = 3; end
                2: begin width = 9; depth = 1; end
                default: begin
                    width = size_group + (scene >= 7 ? 8 : 1);
                    depth = size_group;
                end
            endcase
            hollow_center = scene == 0 && dx < 3 && dy < 2;
            corner = (scene == 1 && dx >= 2 && dy >= 2) || (dy == 3 && dx >= 5);
            trimmed_edge = ((angle % 4) != 0) &&
                ((angle < 4 && py >= 324 + depth * 8) ||
                 (angle >= 4 && py < 316 - depth * 8));
            footprint = px < 640 && px >= 192 && px < 448 && py >= 256 && py < 384 &&
                        dx <= width && dy <= depth && !hollow_center &&
                        !corner && !trimmed_edge;
        end
    endfunction

    integer scene, angle, px, py, coverage;
    integer previous_radius_coverage [0:7];
    initial begin
        repeat (2) @(negedge clk);
        if (in_shadow !== 1'b0) $fatal(1, "Shadow must be off during reset");
        rst_n = 1'b1;
        for (scene = 0; scene < 11; scene = scene + 1) begin
            cube_select = (scene == 1);
            capsule_shape = (scene == 2 || scene >= 7);
            profile_mode = (scene >= 3);
            profile_size = scene >= 7 ? scene - 7 : scene - 3;
            for (angle = 0; angle < 8; angle = angle + 1) begin
                coverage = 0;
                light_angle = angle;
                // Every predicate boundary is a multiple of four coordinates.
                for (py = 0; py < 525; py = py + 4) begin
                    for (px = 0; px < 800; px = px + 4) begin
                        x = px;
                        y = py;
                        video_active = px < 640 && py < 480;
                        @(negedge clk);
                        if (in_shadow !== footprint(scene, angle, px, py))
                            $fatal(1, "Shadow mismatch scene=%0d angle=%0d at (%0d,%0d)",
                                   scene, angle, px, py);
                        if (in_shadow) coverage = coverage + 1;
                    end
                end
                if (coverage == 0 || ((scene > 3 && scene < 7 || scene > 7) &&
                                      coverage <= previous_radius_coverage[angle]))
                    $fatal(1, "Shadow area must grow with radius group");
                previous_radius_coverage[angle] = coverage;
            end
        end
        $display("PASS 11 shadow profiles, 8 light directions and VGA blanking");
        $finish;
    end
endmodule

`default_nettype wire

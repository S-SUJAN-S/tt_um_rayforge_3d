`timescale 1ps/1ps
`default_nettype none

module tb_user_profiles;
    localparam integer LINE = 800;
    localparam integer FRAME = LINE * 525;
    localparam [5:0] YELLOW = 6'b11_11_00;
    localparam integer FACE_TORUS = -1, CUBE = -2, EDGE_TORUS = -3;

    reg clk = 1'b0;
    always #19861 clk = ~clk;
    reg rst_n = 1'b0;
    reg [7:0] scene = 8'h06;
    wire [7:0] video, diagnostic;
    wire [5:0] rgb = {video[0], video[4], video[1], video[5], video[2], video[6]};

    tt_um_rayforge_3d dut (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(scene), .uio_in(8'h00),
        .uo_out(video), .uio_out(diagnostic), .uio_oe()
    );

    function automatic [7:0] scene_word(input integer profile);
        case (profile)
            FACE_TORUS: scene_word = 8'h18;
            CUBE:       scene_word = 8'h1a;
            EDGE_TORUS: scene_word = 8'h1c;
            default:    scene_word = {1'b0, profile[3:0], 2'b11, profile[4]};
        endcase
    endfunction

    task automatic check_frame(
        input integer profile,
        input bit exercise_bist,
        input string capture_path
    );
        integer sample, x, y, horizontal, vertical, distance_squared, radius_squared, pixels, stream;
        reg expected_hit, visible;
        begin
            radius_squared = 256 + 128 * (profile % 16);
            pixels = 0;
            stream = 0;
            if (capture_path != "") begin
                stream = $fopen(capture_path, "wb");
                if (!stream) $fatal(1, "Could not open %s", capture_path);
            end
            for (sample = 0; sample < FRAME; sample = sample + 1) begin
                x = sample % LINE;
                y = sample / LINE;
                visible = x < 640 && y < 480;
                if (video[7] !== !(x >= 656 && x < 752) ||
                    video[3] !== !(y >= 490 && y < 492) ||
                    (rgb != 0) !== visible || (^video) === 1'bx)
                    $fatal(1, "Bad VGA sync or blanking at %0d,%0d", x, y);
                horizontal = x < 320 ? 320 - x : x - 320;
                if (profile == EDGE_TORUS)
                    horizontal = horizontal > 75 ? horizontal - 75 : 0;
                else if (profile >= 16)
                    horizontal = horizontal > 64 ? horizontal - 64 : 0;
                vertical = y - 190;
                distance_squared = horizontal * horizontal + vertical * vertical;
                case (profile)
                    FACE_TORUS: expected_hit = visible && distance_squared >= 1600 &&
                        distance_squared <= 12100;
                    EDGE_TORUS: expected_hit = visible && distance_squared <= 1225;
                    CUBE: expected_hit = visible && horizontal < 64 &&
                        vertical >= -32 + horizontal / 2 && vertical <= 96 - horizontal / 2;
                    default: expected_hit = visible && distance_squared <= radius_squared;
                endcase
                if ((rgb == YELLOW) !== expected_hit)
                    $fatal(1, "Profile %0d mismatch at %0d,%0d, r2=%0d",
                           profile, x, y, radius_squared);
                pixels = pixels + expected_hit;
                if (stream) $fwrite(stream, "%c", video);
                if (exercise_bist && sample == 0) scene[7] = 1'b1;
                if (exercise_bist && sample == 1100 && diagnostic !== 8'hf3)
                    $fatal(1, "Profile mode BIST did not produce PASS");
                if (exercise_bist && sample == 1150) scene[7] = 1'b0;
                @(negedge clk);
            end
            if (stream) $fclose(stream);
            if (profile < 0)
                $display("PASS legacy scene word=%02x pixels=%0d", scene_word(profile), pixels);
            else
                $display("PASS profile=%0d word=%02x r_squared=%0d pixels=%0d",
                         profile, scene_word(profile), radius_squared, pixels);
        end
    endtask

    integer index, count, requested_profile;
    reg mixed_modes;
    integer profiles [0:31];
    string capture_dir, target;
    initial begin
        capture_dir = "";
        if ($value$plusargs("capture=%s", capture_dir))
            $display("Capture directory %s", capture_dir);
        mixed_modes = $test$plusargs("mixed");
        if (mixed_modes) begin
            count = 7;
            profiles[0] = 0;
            profiles[1] = FACE_TORUS;
            profiles[2] = 31;
            profiles[3] = CUBE;
            profiles[4] = 15;
            profiles[5] = EDGE_TORUS;
            profiles[6] = 16;
        end else if ($value$plusargs("profile=%d", requested_profile)) begin
            if (requested_profile < EDGE_TORUS || requested_profile > 31)
                $fatal(1, "Profile must be in 0..31 or a legacy silhouette index (-1, -2, -3)");
            count = 1;
            profiles[0] = requested_profile;
            scene = scene_word(requested_profile);
        end else if ($test$plusargs("quick")) begin
            count = 6;
            profiles[0] = 0;
            profiles[1] = 7;
            profiles[2] = 15;
            profiles[3] = 16;
            profiles[4] = 23;
            profiles[5] = 31;
        end else begin
            count = 32;
            for (index = 0; index < count; index = index + 1)
                profiles[index] = index;
        end

        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        @(negedge video[3]);
        @(negedge clk);
        repeat (2 * FRAME + 35 * LINE) @(negedge clk);

        for (index = 0; index < count; index = index + 1) begin
            target = "";
            if (capture_dir != "")
                target = $sformatf("%s/profile-%02d.bin", capture_dir, profiles[index]);
            check_frame(profiles[index], index == 0, target);
            if (index + 1 < count) begin
                scene = scene_word(profiles[index + 1]);
                if (mixed_modes || index == 0) begin
                    // A new input word must leave the old profile in place
                    // through the next complete active frame.
                    check_frame(profiles[index], 1'b0, "");
                    repeat (FRAME) @(negedge clk);
                end else begin
                    repeat (2 * FRAME) @(negedge clk);
                end
            end
        end
        if (mixed_modes)
            $display("PASS 7 mixed scene frames and 6 full retained frames across qualification");
        else if (count == 1)
            $display("PASS selected user geometry frame and BIST");
        else
            $display("PASS %0d user geometry frames, frame qualification and BIST", count);
        $finish;
    end

    initial begin
        repeat (100 * FRAME) @(posedge clk);
        $fatal(1, "User profile test timed out");
    end
endmodule

`default_nettype wire

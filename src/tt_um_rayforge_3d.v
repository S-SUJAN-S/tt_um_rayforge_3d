// =============================================================================
// File: tt_um_rayforge_3d.v
// Module: tt_um_rayforge_3d (Top-Level Tiny Tapeout ASIC Wrapper)
// Description: RayForge-X: Multiplierless analytic VGA scene renderer
// Author: Sujan S & Team (RVCE ECE)
// Target Foundry: SkyWater 130nm CMOS (Tiny Tapeout 1x1 Standard Tile)
// =============================================================================

`default_nettype none

module tt_um_rayforge_3d (
    input  wire [7:0] ui_in,    // Dedicated inputs: Control & Scene Configuration
    output wire [7:0] uo_out,   // Dedicated outputs: Tiny VGA PMOD (RGB + HSYNC + VSYNC)
    input  wire [7:0] uio_in,   // IOs: Input path (unused)
    output wire [7:0] uio_out,  // IOs: Output path (7-Segment display + BIST status)
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 1=output, 0=input)
    input  wire       ena,      // Always 1 when the design is powered
    input  wire       clk,      // System clock (25.175 MHz VGA pixel clock)
    input  wire       rst_n     // Asynchronous active-low reset from button
);

    // =========================================================================
    // 1. RESET SYNCHRONIZER (Asynchronous Assert, Synchronous Release)
    // =========================================================================
    wire async_rst_n = rst_n & ena;
    (* async_reg = "true" *) reg rst_sync_stage1;
    (* async_reg = "true" *) reg rst_sync_stage2;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            rst_sync_stage1 <= 1'b0;
            rst_sync_stage2 <= 1'b0;
        end else begin
            rst_sync_stage1 <= 1'b1;
            rst_sync_stage2 <= rst_sync_stage1;
        end
    end

    wire clean_rst_n = rst_sync_stage2;

    // =========================================================================
    // 2. BIDIRECTIONAL PIN CONFIGURATION
    // =========================================================================
    assign uio_oe = 8'b1111_1111;
    wire _unused_inputs = &{uio_in, 1'b0};

    // =========================================================================
    // 3. VGA TIMING GENERATOR INSTANTIATION
    // =========================================================================
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire       video_active;
    wire       core_hsync;
    wire       core_vsync;
    wire       frame_pulse;

    vga_timing_gen u_vga_timing (
        .clk          (clk),
        .rst_n        (clean_rst_n),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .video_active (video_active),
        .hsync        (core_hsync),
        .vsync        (core_vsync),
        .frame_pulse  (frame_pulse)
    );

    // =========================================================================
    // 4. Synchronize external controls and update the scene in vertical blank.
    // =========================================================================
    wire [6:0] scene_pins = {ui_in[2], ui_in[6:3], ui_in[1:0]};
    (* async_reg = "true" *) reg [6:0] scene_meta, scene_sync;
    (* async_reg = "true" *) reg bist_meta, bist_sync;
    reg [6:0] sampled_scene, active_scene;
    reg       scene_changed;
    reg [4:0] bist_stable;
    reg bist_request;

    // First-stage samples feed only the second stage.
    always @(posedge clk) begin
        scene_meta <= scene_pins;
        scene_sync <= scene_meta;
        bist_meta  <= ui_in[7];
        bist_sync  <= bist_meta;
    end

    // Compare the synchronized word on every clock after its vblank sample.
    // A mismatch invalidates the interval even if the value later returns.
    // Commit one coherent word only after a full stable frame interval.
    wire scene_sample = (pixel_x == 10'd0) && (pixel_y == 10'd480);
    wire scene_matches_sample = scene_sync == sampled_scene;
    always @(posedge clk) begin
        if (!clean_rst_n) begin
            sampled_scene <= 7'd0;
            active_scene  <= 7'd0;
            scene_changed <= 1'b0;
        end else if (scene_sample) begin
            sampled_scene <= scene_sync;
            scene_changed <= 1'b0;
            if (!scene_changed && scene_matches_sample)
                active_scene <= sampled_scene;
        end else if (!scene_matches_sample) begin
            scene_changed <= 1'b1;
        end
    end

    // BIST retains a sub-1100-clock start-and-pass response. Reject requests
    // shorter than 32 consecutive synchronized clocks (about 1.27 us).
    always @(posedge clk) begin
        if (!clean_rst_n) begin
            bist_request <= 1'b0;
            bist_stable  <= 5'd0;
        end else if (bist_sync == bist_request) begin
            bist_stable <= 5'd0;
        end else begin
            bist_stable <= bist_stable + 5'd1;
            if (&bist_stable)
                bist_request <= bist_sync;
        end
    end

    wire anim_en = active_scene[0];
    reg [2:0] anim_light;
    reg [1:0] frame_div;
    always @(posedge clk) begin
        if (!clean_rst_n) begin
            anim_light <= 3'd0;
            frame_div  <= 2'd0;
        end else if (scene_sample && anim_en) begin
            frame_div <= frame_div + 2'd1;
            if (&frame_div)
                anim_light <= anim_light + 3'd1;
        end
    end

    wire [2:0] active_light = anim_en ? anim_light : {active_scene[5:4], 1'b0};
    wire       geom_sel     = active_scene[1];
    wire       torus_edge_on = active_scene[6];
    wire [1:0] shading_mode = active_scene[3:2];

    // =========================================================================
    // 5. ANALYTICAL PERSPECTIVE GROUND PLANE & SHADOW ENGINE
    // =========================================================================
    wire       floor_hit_raw;
    wire       floor_check_raw;
    wire       floor_shadow_raw;
    wire [1:0] floor_fog_raw;

    perspective_ground u_ground (
        .clk         (clk),
        .rst_n       (clean_rst_n),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .video_active(video_active),
        .light_angle (active_light),
        .is_floor    (floor_hit_raw),
        .floor_check (floor_check_raw),
        .in_shadow   (floor_shadow_raw),
        .fog_level   (floor_fog_raw)
    );

    // =========================================================================
    // 6. TWO-STAGE ANALYTIC GEOMETRY PIPELINE
    // =========================================================================
    wire              obj_hit;
    wire signed [7:0] hit_px, hit_py, hit_pz;
    wire              pipe_active;

    sphere_tracer_pipeline u_tracer (
        .clk            (clk),
        .rst_n          (clean_rst_n),
        .pixel_x        (pixel_x),
        .pixel_y        (pixel_y),
        .video_active   (video_active),
        .geom_sel       (geom_sel),
        .torus_edge_on  (torus_edge_on),
        .hit_out        (obj_hit),
        .hit_px         (hit_px),
        .hit_py         (hit_py),
        .hit_pz         (hit_pz),
        .pipeline_active(pipe_active)
    );

    // =========================================================================
    // 7. PIPELINE LATENCY ALIGNMENT DELAY REGISTERS
    // =========================================================================
    // Delay ground by 1 cycle to match sphere tracer stage 2:
    reg [4:0] floor_d1;
    always @(posedge clk) begin
        // Shading ignores the fields when the aligned pixel is invalid.
        floor_d1 <= {floor_hit_raw, floor_check_raw, floor_shadow_raw, floor_fog_raw};
    end

    wire       aligned_floor        = floor_d1[4];
    wire       aligned_floor_check  = floor_d1[3];
    wire       aligned_floor_shadow = floor_d1[2];
    wire [1:0] aligned_floor_fog    = floor_d1[1:0];

    // Sample the stable row bits two clocks after line wrap, just before
    // the shader consumes the first corresponding pixel.
    reg [1:0] sky_band;
    always @(posedge clk) begin
        if (pixel_x == 10'd1)
            sky_band <= pixel_y[7:6];
    end

    // =========================================================================
    // 8. PHONG SHADING, NORMAL MAPPING & COLOR PALETTE ENGINE
    // =========================================================================
    wire [1:0] red_sig;
    wire [1:0] green_sig;
    wire [1:0] blue_sig;

    phong_shading u_shading (
        .clk         (clk),
        .rst_n       (clean_rst_n),
        .hit_in      (obj_hit),
        .hit_px      (hit_px),
        .hit_py      (hit_py),
        .hit_pz      (hit_pz),
        .is_floor    (aligned_floor),
        .floor_check (aligned_floor_check),
        .in_shadow   (aligned_floor_shadow),
        .fog_level   (aligned_floor_fog),
        .light_angle (active_light),
        .shading_mode(shading_mode),
        .sky_band    (sky_band),
        .video_active(pipe_active),
        .red_out     (red_sig),
        .green_out   (green_sig),
        .blue_out    (blue_sig)
    );

    // =========================================================================
    // 10. BUILT-IN SELF-TEST & 7-SEGMENT DIAGNOSTICS INSTANTIATION
    // =========================================================================
    wire [6:0] seg_cathodes;
    wire       bist_pass;
    reg        expected_rgb_active;
    always @(posedge clk) begin
        // RGB uses the beam position from two clocks earlier. The first two
        // clocks of each line correspond to blanking on the previous line.
        // Decode this reference independently of the renderer validity bit.
        expected_rgb_active <= clean_rst_n && (pixel_x[9:1] != 9'd0) &&
                               (pixel_x[9:1] < 9'd321) && (pixel_y < 10'd480);
    end
    wire rgb_active = |{red_sig, green_sig, blue_sig};
    wire render_visibility_error = rgb_active ^ expected_rgb_active;

    bist_diagnostic u_bist (
        .clk           (clk),
        .rst_n         (clean_rst_n),
        .bist_en       (bist_request),
        .frame_pulse   (frame_pulse),
        .visibility_error(render_visibility_error),
        .seven_seg_out (seg_cathodes),
        .bist_pass_led (bist_pass)
    );

    // =========================================================================
    // 11. OUTPUT PIN MAPPING (Official Tiny VGA PMOD Standard)
    // =========================================================================
    assign uo_out[0] = red_sig[1];   // R1 (Red MSB)
    assign uo_out[1] = green_sig[1]; // G1 (Green MSB)
    assign uo_out[2] = blue_sig[1];  // B1 (Blue MSB)
    assign uo_out[3] = core_vsync;   // VSYNC (Active Low)
    assign uo_out[4] = red_sig[0];   // R0 (Red LSB)
    assign uo_out[5] = green_sig[0]; // G0 (Green LSB)
    assign uo_out[6] = blue_sig[0];  // B0 (Blue LSB)
    assign uo_out[7] = core_hsync;   // HSYNC (Active Low)

    assign uio_out = {bist_pass, seg_cathodes};

endmodule

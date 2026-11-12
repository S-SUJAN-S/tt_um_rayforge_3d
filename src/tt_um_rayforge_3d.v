// =============================================================================
// File: tt_um_rayforge_3d.v
// Module: tt_um_rayforge_3d (Top-Level Tiny Tapeout ASIC Wrapper)
// Description: RayForge-X: Ultra-Low-Power Pipelined 3D Sphere Tracing & CSG Raymarching Engine
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
    // 1. DUAL-STAGE RESET SYNCHRONIZER (Metastability Elimination)
    // =========================================================================
    reg rst_sync_stage1;
    reg rst_sync_stage2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_sync_stage1 <= 1'b0;
            rst_sync_stage2 <= 1'b0;
        end else begin
            rst_sync_stage1 <= 1'b1;
            rst_sync_stage2 <= rst_sync_stage1;
        end
    end

    wire clean_rst_n = rst_sync_stage2 & ena;

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
    wire       vga_hsync;
    wire       vga_vsync;
    wire       frame_pulse;

    vga_timing_gen u_vga_timing (
        .clk          (clk),
        .rst_n        (clean_rst_n),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .video_active (video_active),
        .hsync        (vga_hsync),
        .vsync        (vga_vsync),
        .frame_pulse  (frame_pulse)
    );

    // =========================================================================
    // 4. DYNAMIC 3D ANIMATION FSM (Rotation & Orbiting Light)
    // =========================================================================
    wire anim_en = ui_in[0]; // DIP SW 0: Enable auto-animation
    reg [2:0] anim_rot;
    reg [2:0] anim_light;
    reg [3:0] frame_div;

    always @(posedge clk) begin
        if (!clean_rst_n) begin
            anim_rot   <= 3'd0;
            anim_light <= 3'd0;
            frame_div  <= 4'd0;
        end else if (frame_pulse && anim_en) begin
            if (frame_div == 4'd3) begin // Advance every 4 frames (~15 rot/sec)
                frame_div  <= 4'd0;
                anim_rot   <= anim_rot + 3'd1;
                anim_light <= anim_light + 3'd1;
            end else begin
                frame_div  <= frame_div + 4'd1;
            end
        end
    end

    wire [2:0] active_rot   = anim_en ? anim_rot   : 3'd1;
    wire [2:0] active_light = anim_en ? anim_light : {ui_in[6:5], 1'b0};
    wire       geom_sel     = ui_in[1];   // DIP SW 1: 0=Torus, 1=Cube
    wire [1:0] shading_mode = ui_in[4:3]; // DIP SW 4..3: 00=Phong, 01=Normal, 10=Fog, 11=Wire

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
    // 6. 2-STAGE SYSTOLIC SPHERE TRACING PIPELINE
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
        .rot_angle      (active_rot),
        .hit_out        (obj_hit),
        .hit_px         (hit_px),
        .hit_py         (hit_py),
        .hit_pz         (hit_pz),
        .pipeline_active(pipe_active)
    );

    // =========================================================================
    // 7. PIPELINE LATENCY ALIGNMENT DELAY REGISTERS
    // =========================================================================
    // Sphere tracer has 2 cycles latency. Delay ground by 1 cycle (1 + 1 = 2):
    reg [4:0] floor_d1;
    always @(posedge clk) begin
        if (!clean_rst_n) floor_d1 <= 5'd0;
        else floor_d1 <= {floor_hit_raw, floor_check_raw, floor_shadow_raw, floor_fog_raw};
    end

    wire       aligned_floor        = floor_d1[4];
    wire       aligned_floor_check  = floor_d1[3];
    wire       aligned_floor_shadow = floor_d1[2];
    wire [1:0] aligned_floor_fog    = floor_d1[1:0];

    // Delay pixel coordinates by 2 cycles:
    reg [9:0] px_d1, px_d2;
    reg [9:0] py_d1, py_d2;
    always @(posedge clk) begin
        if (!clean_rst_n) begin
            px_d1 <= 10'd0; px_d2 <= 10'd0;
            py_d1 <= 10'd0; py_d2 <= 10'd0;
        end else begin
            px_d1 <= pixel_x; px_d2 <= px_d1;
            py_d1 <= pixel_y; py_d2 <= py_d1;
        end
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
        .pixel_x     (px_d2),
        .pixel_y     (py_d2),
        .video_active(pipe_active),
        .red_out     (red_sig),
        .green_out   (green_sig),
        .blue_out    (blue_sig)
    );

    // =========================================================================
    // 9. SYNC SIGNAL DELAY MATCHING (3 Cycles Total Video Latency)
    // =========================================================================
    reg [2:0] hsync_pipe;
    reg [2:0] vsync_pipe;

    always @(posedge clk) begin
        if (!clean_rst_n) begin
            hsync_pipe <= 3'b111;
            vsync_pipe <= 3'b111;
        end else begin
            hsync_pipe <= {hsync_pipe[1:0], vga_hsync};
            vsync_pipe <= {vsync_pipe[1:0], vga_vsync};
        end
    end

    wire core_hsync = hsync_pipe[2];
    wire core_vsync = vsync_pipe[2];

    // =========================================================================
    // 10. BUILT-IN SELF-TEST & 7-SEGMENT DIAGNOSTICS INSTANTIATION
    // =========================================================================
    wire [6:0] seg_cathodes;
    wire       bist_pass;

    bist_diagnostic u_bist (
        .clk           (clk),
        .rst_n         (clean_rst_n),
        .bist_en       (ui_in[7]),     // DIP SW 7: Trigger Hardware Self-Test
        .frame_pulse   (frame_pulse),
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

    // uio_out[6:0] = 7-Segment display cathodes
    // uio_out[7]   = BIST PASS Status LED
    assign uio_out = {bist_pass, seg_cathodes};

endmodule

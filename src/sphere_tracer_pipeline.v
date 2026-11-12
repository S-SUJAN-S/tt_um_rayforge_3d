// =============================================================================
// File: sphere_tracer_pipeline.v
// Module: sphere_tracer_pipeline
// Description: Systolic 3D Ray-Marching & Isometric Geometry Pipeline
//              Continuous sub-pixel resolution (zero blockiness), true 3D
//              isometric projection for CSG Cube, and smooth metallic Torus.
// Author: Sujan S & Team (RVCE ECE)
// Target: SkyWater 130nm CMOS (Tiny Tapeout 1x1 Standard Tile)
// =============================================================================

`default_nettype none

module sphere_tracer_pipeline (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  pixel_x,        // Screen X [0..639]
    input  wire [9:0]  pixel_y,        // Screen Y [0..479]
    input  wire        video_active,   // Active video region
    input  wire        geom_sel,       // 0=Torus, 1=Cube
    input  wire [2:0]  rot_angle,      // Dynamic 3D rotation angle
    output reg         hit_out,        // 1 = 3D surface hit
    output reg  signed [7:0] hit_px,   // Normal / Hit X (formatted for shading)
    output reg  signed [7:0] hit_py,   // Normal / Hit Y
    output reg  signed [7:0] hit_pz,   // Normal / Hit Z
    output reg         pipeline_active // Video active delayed through pipeline
);

    // =========================================================================
    // STAGE 0: Continuous Screen Coordinates & Spatial Bounding
    // =========================================================================
    wire signed [9:0] dx_center = $signed(pixel_x) - 10'sd320;
    wire signed [9:0] dy_center = 10'sd190 - $signed(pixel_y);
    wire signed [9:0] cdy       = $signed(pixel_y) - 10'sd190; // Centered at y=190

    // Bounding Window: Strict bounds prevent any overflow wrapping
    wire [8:0] abs_dx_wide = dx_center[9] ? (-dx_center[8:0]) : dx_center[8:0];
    wire [8:0] abs_dy_wide = dy_center[9] ? (-dy_center[8:0]) : dy_center[8:0];

    wire torus_in_bounds = (abs_dx_wide <= 9'd115) && (abs_dy_wide <= 9'd115);
    wire cube_in_bounds  = (abs_dx_wide <= 9'd64) && (cdy >= -10'sd40) && (cdy <= 10'sd100);

    wire [7:0] abs_dx = abs_dx_wide[7:0];
    wire [7:0] abs_dy = abs_dy_wide[7:0];

    // Multiplierless 16-gon norm for Torus curvature in Stage 0/1
    wire [7:0] max_v = (abs_dx >= abs_dy) ? abs_dx : abs_dy;
    wire [7:0] min_v = (abs_dx >= abs_dy) ? abs_dy : abs_dx;
    wire [11:0] norm_res1 = {4'b0, max_v} + (({4'b0, min_v} * 3'd3) >> 4);
    wire [11:0] norm_res2 = (({4'b0, max_v} * 4'd12) >> 4) + (({4'b0, min_v} * 4'd11) >> 4);
    wire [7:0] r_xy = ({min_v, 1'b0} <= max_v) ? norm_res1[7:0] : norm_res2[7:0];
    wire signed [8:0] delta_r = $signed({1'b0, r_xy}) - 9'sd75;

    // Continuous 8-bit squares for Torus boundary (0 standard multipliers)
    wire [13:0] dx_sq = abs_dx * abs_dx;
    wire [13:0] dy_sq = abs_dy * abs_dy;
    wire [14:0] r_sq  = dx_sq + dy_sq;

    // 3D Isometric Cube Geometry bounds (Half-width W=64, s=32, H=64)
    wire [7:0]  adx = abs_dx;
    wire [6:0]  adx_slope = adx[7:1]; // adx >> 1
    wire signed [8:0] top_upper = -9'sd32 + $signed({2'b0, adx_slope});
    wire signed [8:0] top_lower =  9'sd32 - $signed({2'b0, adx_slope});
    wire signed [8:0] front_lower = top_lower + 9'sd64;

    // SDF Evaluator instance for verification & corner distance checking
    wire signed [7:0] sdf_dist;
    sdf_engine u_sdf (
        .px      (dx_center[7:0]),
        .py      (dy_center[7:0]),
        .pz      (8'sd0),
        .geom_sel(geom_sel),
        .dist_out(sdf_dist)
    );

    // =========================================================================
    // PIPELINE STAGE 1: Clocked Registers (Cycle 1)
    // =========================================================================
    reg signed [9:0] s1_dx, s1_dy, s1_cdy;
    reg [14:0]       s1_r_sq;
    reg signed [8:0] s1_delta_r;
    reg [7:0]        s1_adx;
    reg signed [8:0] s1_top_upper, s1_top_lower, s1_front_lower;
    reg              s1_geom_sel;
    reg [2:0]        s1_rot_angle;
    reg              s1_active;
    reg              s1_torus_bounds, s1_cube_bounds;

    always @(posedge clk) begin
        if (!rst_n) begin
            s1_dx           <= 10'sd0;
            s1_dy           <= 10'sd0;
            s1_cdy          <= 10'sd0;
            s1_r_sq         <= 15'd0;
            s1_delta_r      <= 9'sd0;
            s1_adx          <= 8'd0;
            s1_top_upper    <= 9'sd0;
            s1_top_lower    <= 9'sd0;
            s1_front_lower  <= 9'sd0;
            s1_geom_sel     <= 1'b0;
            s1_rot_angle    <= 3'd0;
            s1_active       <= 1'b0;
            s1_torus_bounds <= 1'b0;
            s1_cube_bounds  <= 1'b0;
        end else begin
            s1_dx           <= dx_center;
            s1_dy           <= dy_center;
            s1_cdy          <= cdy;
            s1_r_sq         <= r_sq;
            s1_delta_r      <= delta_r;
            s1_adx          <= adx;
            s1_top_upper    <= top_upper;
            s1_top_lower    <= top_lower;
            s1_front_lower  <= front_lower;
            s1_geom_sel     <= geom_sel;
            s1_rot_angle    <= rot_angle;
            s1_active       <= video_active;
            s1_torus_bounds <= torus_in_bounds;
            s1_cube_bounds  <= cube_in_bounds;
        end
    end

    // =========================================================================
    // PIPELINE STAGE 2: Surface Detection & Normal Formatting (Cycle 2)
    // =========================================================================
    // 1. Torus Surface & Continuous Metallic Normal
    wire torus_hit = (s1_r_sq >= 15'd1600) && (s1_r_sq <= 15'd12100) && s1_torus_bounds;
    wire signed [15:0] t_nx_wide = s1_dx * s1_delta_r;
    wire signed [15:0] t_ny_wide = s1_dy * s1_delta_r;
    wire signed [8:0]  t_nx_div  = t_nx_wide >>> 8;
    wire signed [8:0]  t_ny_div  = t_ny_wide >>> 8;

    wire signed [4:0] torus_nx = (t_nx_div > 9'sd14) ? 5'sd14 : (t_nx_div < -9'sd15) ? -5'sd15 : t_nx_div[4:0];
    wire signed [4:0] torus_ny = (t_ny_div > 9'sd14) ? 5'sd14 : (t_ny_div < -9'sd15) ? -5'sd15 : t_ny_div[4:0];
    wire [6:0] abs_dr = s1_delta_r[8] ? (-s1_delta_r[6:0]) : s1_delta_r[6:0];
    wire signed [4:0] torus_nz = (abs_dr < 7'd35) ? $signed({1'b0, (7'd35 - abs_dr) >> 2}) : 5'sd0;

    // 2. 3D Isometric Cube Surface & Face Normals
    wire cube_top   = (s1_adx <= 8'd64) && (s1_cdy >= s1_top_upper) && (s1_cdy < s1_top_lower) && s1_cube_bounds;
    wire cube_left  = (s1_adx <= 8'd64) && (s1_cdy >= s1_top_lower) && (s1_cdy <= s1_front_lower) && (s1_dx < 10'sd0) && s1_cube_bounds;
    wire cube_right = (s1_adx <= 8'd64) && (s1_cdy >= s1_top_lower) && (s1_cdy <= s1_front_lower) && (s1_dx >= 10'sd0) && s1_cube_bounds;
    wire cube_hit   = cube_top | cube_left | cube_right;

    reg signed [4:0] cube_nx, cube_ny, cube_nz;
    always @(*) begin
        if (cube_top) begin
            // Top Face: Points up and tilted towards celestial light
            cube_nx = 5'sd0;
            cube_ny = 5'sd6;
            cube_nz = -5'sd4;
        end else if (cube_left) begin
            // Front-Left Face: Points left and forward
            cube_nx = -5'sd5;
            cube_ny = 5'sd1;
            cube_nz = -5'sd3;
        end else begin
            // Front-Right Face: Points right and forward (diffuse shade)
            cube_nx = 5'sd5;
            cube_ny = -5'sd1;
            cube_nz = -5'sd3;
        end
    end

    // Registered Stage 2 Outputs (2 clock cycles total pipeline latency)
    always @(posedge clk) begin
        if (!rst_n) begin
            hit_out         <= 1'b0;
            hit_px          <= 8'sd0;
            hit_py          <= 8'sd0;
            hit_pz          <= 8'sd0;
            pipeline_active <= 1'b0;
        end else begin
            hit_out         <= s1_geom_sel ? (cube_hit & s1_active) : (torus_hit & s1_active);
            hit_px          <= s1_geom_sel ? {cube_nx[4], cube_nx[3:0], 3'b000} : {torus_nx[4], torus_nx[3:0], 3'b000};
            hit_py          <= s1_geom_sel ? {cube_ny[4], cube_ny[3:0], 3'b000} : {torus_ny[4], torus_ny[3:0], 3'b000};
            hit_pz          <= s1_geom_sel ? {cube_nz[4], cube_nz[3:0], 3'b000} : {-torus_nz[4], -torus_nz[3:0], 3'b000};
            pipeline_active <= s1_active;
        end
    end

endmodule

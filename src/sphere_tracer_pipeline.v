// =============================================================================
// File: sphere_tracer_pipeline.v
// Module: sphere_tracer_pipeline
// Description: Ultra-compact, zero-multiplier 3D sphere tracer & isometric engine
//              Optimized for 1x1 SkyWater 130nm tile (<9,000 um^2 cell area)
// Author: Sujan S & Team (RVCE ECE)
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
    // STAGE 0: Centered Coordinates & Fast Norm
    // =========================================================================
    wire signed [9:0] dx_center = $signed(pixel_x) - 10'sd320;
    wire signed [9:0] dy_center = 10'sd190 - $signed(pixel_y);

    wire [8:0] abs_dx_wide = dx_center[9] ? (-dx_center[8:0]) : dx_center[8:0];
    wire [8:0] abs_dy_wide = dy_center[9] ? (-dy_center[8:0]) : dy_center[8:0];

    wire torus_in_bounds = (abs_dx_wide <= 9'd115) && (abs_dy_wide <= 9'd115);
    wire cube_in_bounds  = (abs_dx_wide <= 9'd64) && (dy_center <= 10'sd40) && (dy_center >= -10'sd100);

    wire [7:0] abs_dx = abs_dx_wide[7:0];
    wire [7:0] abs_dy = abs_dy_wide[7:0];

    // Fast Octagonal Norm: r_xy = max(a, b) + (min(a, b) >> 1)
    wire [7:0] max_v = (abs_dx >= abs_dy) ? abs_dx : abs_dy;
    wire [7:0] min_v = (abs_dx >= abs_dy) ? abs_dy : abs_dx;
    wire [7:0] r_xy   = max_v + {1'b0, min_v[7:1]};

    // Delta from major torus ring (R = 75): minor radius r = 35
    wire signed [8:0] delta_r = $signed({1'b0, r_xy}) - 9'sd75;

    // =========================================================================
    // PIPELINE STAGE 1: Minimal Clocked Registers (Cycle 1)
    // =========================================================================
    reg signed [9:0] s1_dx, s1_dy;
    reg [7:0]        s1_r_xy;
    reg signed [8:0] s1_delta_r;
    reg [5:0]        s1_adx;
    reg              s1_geom_sel;
    reg              s1_active;
    reg              s1_torus_bounds, s1_cube_bounds;

    always @(posedge clk) begin
        if (!rst_n) begin
            s1_dx           <= 10'sd0;
            s1_dy           <= 10'sd0;
            s1_r_xy         <= 8'd0;
            s1_delta_r      <= 9'sd0;
            s1_adx          <= 6'd0;
            s1_geom_sel     <= 1'b0;
            s1_active       <= 1'b0;
            s1_torus_bounds <= 1'b0;
            s1_cube_bounds  <= 1'b0;
        end else begin
            s1_dx           <= dx_center;
            s1_dy           <= dy_center;
            s1_r_xy         <= r_xy;
            s1_delta_r      <= delta_r;
            s1_adx          <= abs_dx[5:0];
            s1_geom_sel     <= geom_sel;
            s1_active       <= video_active;
            s1_torus_bounds <= torus_in_bounds;
            s1_cube_bounds  <= cube_in_bounds;
        end
    end

    // =========================================================================
    // PIPELINE STAGE 2: Zero-Multiplier Surface Detection & Normals (Cycle 2)
    // =========================================================================
    // 1. Torus Surface: Tube boundary is 40 <= r_xy <= 110
    wire torus_hit = (s1_r_xy >= 8'd40) && (s1_r_xy <= 8'd110) && s1_torus_bounds;

    // Zero-multiplier metallic normal:
    wire signed [4:0] dx_scaled = s1_dx[7:3];
    wire signed [4:0] dy_scaled = s1_dy[7:3];
    wire signed [4:0] torus_nx = s1_delta_r[8] ? (-dx_scaled) : dx_scaled;
    wire signed [4:0] torus_ny = s1_delta_r[8] ? (-dy_scaled) : dy_scaled;

    wire [6:0] abs_dr = s1_delta_r[8] ? (-s1_delta_r[6:0]) : s1_delta_r[6:0];
    wire [4:0] torus_nz_mag = (7'd35 - abs_dr) >> 2;
    wire signed [4:0] torus_nz = (abs_dr < 7'd35) ? $signed({1'b0, torus_nz_mag[3:0]}) : 5'sd0;

    // 2. 3D Isometric Cube Surface (7-bit compact arithmetic)
    wire signed [7:0] cdy = -s1_dy[7:0];
    wire [4:0]  adx_slope = s1_adx[5:1];
    wire signed [6:0] top_upper   = -7'sd32 + $signed({2'b0, adx_slope});
    wire signed [6:0] top_lower   =  7'sd32 - $signed({2'b0, adx_slope});
    wire signed [7:0] front_lower = {top_lower[6], top_lower} + 8'sd64;

    wire cube_top   = (cdy >= {{1{top_upper[6]}}, top_upper}) && (cdy < {{1{top_lower[6]}}, top_lower}) && s1_cube_bounds;
    wire cube_left  = (cdy >= {{1{top_lower[6]}}, top_lower}) && (cdy <= front_lower) && (s1_dx < 10'sd0) && s1_cube_bounds;
    wire cube_right = (cdy >= {{1{top_lower[6]}}, top_lower}) && (cdy <= front_lower) && (s1_dx >= 10'sd0) && s1_cube_bounds;
    wire cube_hit   = cube_top | cube_left | cube_right;

    reg signed [4:0] cube_nx, cube_ny, cube_nz;
    always @(*) begin
        if (cube_top) begin
            cube_nx = 5'sd0;
            cube_ny = 5'sd6;
            cube_nz = -5'sd4;
        end else if (cube_left) begin
            cube_nx = -5'sd5;
            cube_ny = 5'sd1;
            cube_nz = -5'sd3;
        end else begin
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

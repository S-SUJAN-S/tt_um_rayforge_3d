// =============================================================================
// File: sphere_tracer_pipeline.v
// Module: sphere_tracer_pipeline
// Description: Exact orthographic torus silhouette and projected cube faces.
// The module name is retained for the Tiny Tapeout source manifest.
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
    input  wire        torus_edge_on,  // 0=face on, 1=edge on
    output reg         hit_out,        // 1 = 3D surface hit
    output reg  signed [7:0] hit_px,   // Normal / Hit X (formatted for shading)
    output reg  signed [7:0] hit_py,   // Normal / Hit Y
    output reg  signed [7:0] hit_pz,   // Normal / Hit Z
    output reg         pipeline_active // Video active delayed through pipeline
);

    // =========================================================================
    // Stage 1: centered beam coordinates and squared-radius classification.
    // =========================================================================
    wire signed [7:0] dx_center = $signed(pixel_x[7:0]) - 8'sd64;
    wire signed [7:0] dy_center = $signed(pixel_y[7:0]) - 8'sd190;
    wire [5:0] abs_dx = dx_center[7] ? -dx_center[5:0] : dx_center[5:0];
    wire cube_in_bounds = (pixel_x > 10'd256) && (pixel_x < 10'd384) &&
                          (pixel_y >= 10'd158) && (pixel_y <= 10'd286);

    // Face on, step the square of x-320. Edge on, the projected centerline
    // is the segment x=245..395; step the square of the signed distance to
    // the nearer endpoint outside that segment. Inside, preserve the Y term.
    // At x=192 and x=448 the two X terms are symmetric in each pose, so the
    // Y step at line wrap preserves the next scanline's starting invariant.
    wire radial_columns = (pixel_x[9:6] >= 4'd3) && (pixel_x[9:6] <= 4'd6);
    wire radial_rows = (pixel_y >= 10'd80) && (pixel_y <= 10'd300);
    wire end_of_line = (pixel_x == 10'd799);
    wire start_radial_rows = end_of_line && (pixel_y == 10'd79);
    // In the left cap block (x=192..255), add 11 to the low six X bits.
    // For the right block (x=384..447), invert before and after the same
    // add to subtract 11. The carry rejects positions inside the segment.
    // In the face-on pose the unchanged low bits represent x-320.
    wire reflect_cap = torus_edge_on && pixel_x[8];
    wire [5:0] cap_bits = pixel_x[5:0] ^ {6{reflect_cap}};
    wire [6:0] cap_sum = {1'b0, cap_bits} + (torus_edge_on ? 7'd11 : 7'd0);
    wire [5:0] step_x_low = cap_sum[5:0] ^ {6{reflect_cap}};
    wire [1:0] step_x_high = torus_edge_on ? {2{!pixel_x[8]}} : dx_center[7:6];
    wire [7:0] step_x_coordinate = {step_x_high, step_x_low};
    wire outside_segment = !cap_sum[6] && (!pixel_x[8] || pixel_x[7]);
    wire step_x = radial_columns && (!torus_edge_on || outside_segment);
    wire [7:0] step_coordinate = end_of_line ? dy_center : step_x_coordinate;
    wire [14:0] radial_delta = {{6{step_coordinate[7]}}, step_coordinate, 1'b1};
    reg [14:0] radius_sq;

    always @(posedge clk) begin
        if (start_radial_rows)
            // The capsule adds a constant bias 10875 to its true squared
            // distance. It then shares the face-on upper bound: 10875 +
            // 35^2 = 12100. Its encoded minimum is above the lower bound.
            radius_sq <= torus_edge_on ? 15'd25784 : 15'd28484;
        else if (radial_rows && (step_x || end_of_line))
            radius_sq <= radius_sq + radial_delta;
    end

    wire torus_hit = radial_rows && radial_columns &&
                     (radius_sq >= 15'd1600) && (radius_sq <= 15'd12100);
    wire inner_wall = (radius_sq < 15'd5625);

    // Compare 32-pixel bins of |dx| and |dy|, using one's complement for
    // negative coordinates to avoid negation. Ties retain both components.
    wire [1:0] dx_bin = dx_center[6:5] ^ {2{dx_center[7]}};
    wire [1:0] dy_bin = dy_center[6:5] ^ {2{dy_center[7]}};
    // In the capsule's visible domain (|dy|<=35), promote the X component
    // near the ends and the Y component near its top or bottom. The central
    // region uses the higher front-facing Z magnitude. Distances of negative
    // coordinates are one's-complement magnitudes, as in the face-on bins.
    wire edge_x_major = dx_bin[1];
    wire edge_y_major = dy_bin[0] || (dy_center[4] ^ dy_center[7]);

    reg signed [7:0] s1_dy;
    reg s1_nx_negative, s1_ny_negative;
    reg s1_x_major, s1_y_major;
    reg [4:0] s1_adx_slope;
    reg s1_left, s1_cube_bounds, s1_torus_hit;
    reg s1_geom_sel, s1_active;
    reg s1_tube_band;

    always @(posedge clk) begin
        // Validity is reset independently. These fields are consumed only
        // for a live beam coordinate.
        s1_active      <= rst_n && video_active;
        s1_dy          <= dy_center;
        s1_nx_negative <= dx_center[7] ^ inner_wall;
        s1_ny_negative <= !dy_center[7] ^ inner_wall;
        s1_x_major     <= torus_edge_on ? edge_x_major : (dx_bin >= dy_bin);
        s1_y_major     <= torus_edge_on ? edge_y_major : (dy_bin >= dx_bin);
        s1_adx_slope   <= abs_dx[5:1];
        s1_left        <= dx_center[7];
        s1_cube_bounds <= cube_in_bounds;
        s1_torus_hit   <= torus_hit;
        s1_geom_sel    <= geom_sel;
        // On the face-on view this band corresponds to front depth >= 28.
        s1_tube_band   <= torus_edge_on ? !(edge_x_major || edge_y_major) :
                          ((radius_sq >= 15'd2916) && (radius_sq <= 15'd9216));
    end

    // =========================================================================
    // Stage 2: face selection and quantized shading coordinates.
    // =========================================================================
    // The smaller XY component has magnitude 1. Each major component has
    // magnitude 2 in the deeper band and 3 elsewhere. Form signed values
    // directly while retaining the existing signed format and scaling.
    function automatic [3:0] torus_xy(input negative, input major, input tube_band);
        torus_xy = {negative, negative, (major ^ negative) | (negative & tube_band),
                    ~(major & tube_band)};
    endfunction
    wire signed [3:0] torus_nx = torus_xy(s1_nx_negative, s1_x_major, s1_tube_band);
    wire signed [3:0] torus_ny = torus_xy(s1_ny_negative, s1_y_major, s1_tube_band);
    wire signed [3:0] torus_nz = s1_tube_band ? -4'sd7 : -4'sd2;

    // For the top diamond, cdy >= -32+slope and cdy < 32-slope.
    // The front extends to cdy <= 96-slope. The bounding box limits
    // cdy to [-32,96], making cdy+slope fit its signed byte.
    wire signed [7:0] top_upper = $signed({3'b111, s1_adx_slope});
    wire signed [7:0] face_y = s1_dy + $signed({3'b000, s1_adx_slope});
    wire cube_hit = s1_cube_bounds && (s1_dy >= top_upper) && (face_y <= 8'sd96);
    wire cube_top = (face_y < 8'sd32);

    reg signed [4:0] cube_nx, cube_ny, cube_nz;
    always @(*) begin
        if (cube_top) begin
            cube_nx = 5'sd0;
            cube_ny = 5'sd6;
            cube_nz = -5'sd4;
        end else if (s1_left) begin
            cube_nx = -5'sd5;
            cube_ny = 5'sd1;
            cube_nz = -5'sd3;
        end else begin
            cube_nx = 5'sd5;
            cube_ny = -5'sd1;
            cube_nz = -5'sd3;
        end
    end

    // Registered Stage 2 outputs.
    always @(posedge clk) begin
        pipeline_active <= rst_n && s1_active;
        hit_out         <= rst_n && s1_active && (s1_geom_sel ? cube_hit : s1_torus_hit);
        hit_px          <= s1_geom_sel ? {cube_nx, 3'b000} : {torus_nx[3], torus_nx, 3'b000};
        hit_py          <= s1_geom_sel ? {cube_ny, 3'b000} : {torus_ny[3], torus_ny, 3'b000};
        hit_pz          <= s1_geom_sel ? {cube_nz, 3'b000} : {torus_nz[3], torus_nz, 3'b000};
    end

endmodule

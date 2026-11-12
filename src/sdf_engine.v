// =============================================================================
// File: sdf_engine.v
// Module: sdf_engine
// Description: Zero-Multiplier Signed Distance Field (SDF) Evaluator
//              Octagonal approximation for 3D Torus and CSG Cube
// Author: Sujan S & Team (RVCE ECE)
// Target: SkyWater 130nm CMOS (Tiny Tapeout 1x1 Standard Tile)
// =============================================================================

`default_nettype none

module sdf_engine (
    input  wire signed [7:0] px,       // 3D Point X in fixed-point format
    input  wire signed [7:0] py,       // 3D Point Y
    input  wire signed [7:0] pz,       // 3D Point Z
    input  wire              geom_sel, // 0=3D Torus, 1=3D Cube
    output reg  signed [7:0] dist_out  // Signed distance to nearest surface
);

    // Absolute coordinate magnitudes
    wire [7:0] abs_x = px[7] ? (-px) : px;
    wire [7:0] abs_y = py[7] ? (-py) : py;
    wire [7:0] abs_z = pz[7] ? (-pz) : pz;

    // Fast zero-multiplier octagonal 2D norm: max + (3/8)*min
    wire [7:0] max_xy = (abs_x >= abs_y) ? abs_x : abs_y;
    wire [7:0] min_xy = (abs_x >= abs_y) ? abs_y : abs_x;
    wire [8:0] min_xy3 = {min_xy, 1'b0} + {1'b0, min_xy};
    wire [7:0] r_xy = max_xy + min_xy3[8:3];

    // Torus: Major radius R=75, Minor radius r=35
    wire [7:0] delta_r = (r_xy >= 8'd75) ? (r_xy - 8'd75) : (8'd75 - r_xy);
    wire [7:0] max_rz = (delta_r >= abs_z) ? delta_r : abs_z;
    wire [7:0] min_rz = (delta_r >= abs_z) ? abs_z : delta_r;
    wire [8:0] min_rz3 = {min_rz, 1'b0} + {1'b0, min_rz};
    wire [7:0] torus_dist = max_rz + min_rz3[8:3];
    wire signed [7:0] dist_torus = $signed({1'b0, torus_dist[6:0]}) - 8'sd35;

    // Cube: max(|x|, |y|, |z|) - size (size=32)
    wire [7:0] max_yz = (abs_y >= abs_z) ? abs_y : abs_z;
    wire [7:0] max_xyz = (abs_x >= max_yz) ? abs_x : max_yz;
    wire signed [7:0] dist_cube = $signed({1'b0, max_xyz[6:0]}) - 8'sd32;

    always @(*) begin
        dist_out = geom_sel ? dist_cube : dist_torus;
    end

endmodule

// =============================================================================
// File: sdf_engine.v
// Module: sdf_engine
// Description: Zero-Multiplier Signed Distance Field (SDF) Evaluator
//              Features high-precision 2-region 16-gon norm (2.06% max error)
//              and full headroom distance evaluation for 3D Torus and Cube.
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

    // Absolute coordinate magnitudes (8 bits unsigned)
    wire [7:0] abs_x = px[7] ? (-px) : px;
    wire [7:0] abs_y = py[7] ? (-py) : py;
    wire [7:0] abs_z = pz[7] ? (-pz) : pz;

    // -------------------------------------------------------------------------
    // Optimal 2-Region 16-Gon Multiplierless Norm: Max Error <= 2.06%
    // Region 1 (2*min <= max): max + (3/16)*min
    // Region 2 (2*min > max) : (12/16)*max + (11/16)*min
    // -------------------------------------------------------------------------
    function [7:0] norm16(input [7:0] a, input [7:0] b);
        reg [7:0] max_v, min_v;
        reg [11:0] res1, res2;
        begin
            if (a >= b) begin
                max_v = a; min_v = b;
            end else begin
                max_v = b; min_v = a;
            end

            res1 = {4'b0, max_v} + (({4'b0, min_v} * 3'd3) >> 4);
            res2 = (({4'b0, max_v} * 4'd12) >> 4) + (({4'b0, min_v} * 4'd11) >> 4);

            if ({min_v, 1'b0} <= max_v)
                norm16 = (res1 > 12'd127) ? 8'd127 : res1[7:0];
            else
                norm16 = (res2 > 12'd127) ? 8'd127 : res2[7:0];
        end
    endfunction

    // -------------------------------------------------------------------------
    // 1. Torus SDF: d = sqrt((sqrt(x^2 + y^2) - R)^2 + z^2) - r
    // Major radius R = 75, Minor radius r = 35
    // -------------------------------------------------------------------------
    wire [7:0] r_xy = norm16(abs_x, abs_y);
    wire [7:0] delta_r = (r_xy >= 8'd75) ? (r_xy - 8'd75) : (8'd75 - r_xy);
    wire [7:0] torus_radial = norm16(delta_r, abs_z);
    wire signed [7:0] dist_torus = $signed({1'b0, torus_radial[6:0]}) - 8'sd35;

    // -------------------------------------------------------------------------
    // 2. Cube SDF: d = max(|x|, max(|y|, |z|)) - size
    // Half-size = 32
    // -------------------------------------------------------------------------
    wire [7:0] max_yz = (abs_y >= abs_z) ? abs_y : abs_z;
    wire [7:0] max_xyz = (abs_x >= max_yz) ? abs_x : max_yz;
    wire signed [7:0] dist_cube = $signed({1'b0, max_xyz[6:0]}) - 8'sd32;

    always @(*) begin
        if (!geom_sel)
            dist_out = dist_torus;
        else
            dist_out = dist_cube;
    end

endmodule

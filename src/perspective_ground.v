// =============================================================================
// File: perspective_ground.v
// Module: perspective_ground
// Description: Compact Perspective Ground Plane & Dynamic Shadow Engine
//              Piecewise-linear perspective step generator, non-tearing accumulator,
//              dynamic shadow receiver, and atmospheric horizon fog.
// Author: Sujan S & Team (RVCE ECE)
// Target: SkyWater 130nm CMOS (Tiny Tapeout 1x1 Standard Tile)
// =============================================================================

`default_nettype none

module perspective_ground (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  pixel_x,       // Screen X [0..639]
    input  wire [9:0]  pixel_y,       // Screen Y [0..479]
    input  wire        video_active,  // Active video region
    input  wire [2:0]  light_angle,   // Orbital light angle (0..7)
    input  wire        cube_select,
    input  wire        capsule_shape, // Edge-on torus or programmable capsule
    input  wire        profile_mode,
    input  wire [1:0]  profile_shadow_size, // Upper radius-code bits
    output reg         is_floor,      // 1 = Ray hits floor plane
    output reg         floor_check,   // 1 = Light tile, 0 = Dark tile
    output reg         in_shadow,     // 1 = Floor pixel is occluded by shadow
    output reg  [1:0]  fog_level      // Depth fog attenuation
);

    // One decode controls pitch, line seed and vertical parity. Visible
    // rows grow taller away from the horizon. Pitch is held through each
    // complete checker row so a pitch transition cannot leave a thin strip.
    wire is_below_horizon = (pixel_y > 10'd230) && video_active;
    wire [7:0] delta_y = pixel_y[7:0] - 8'd230;
    wire [5:0] row_group = delta_y[7:2];
    reg [6:0] k_step;
    reg [4:0] line_phase;
    reg v_tile_bit;
    always @(*) begin
        if      (row_group < 6'd9)  {k_step, line_phase, v_tile_bit} = {7'd56, 5'd8,  1'b1};
        else if (row_group < 6'd13) {k_step, line_phase, v_tile_bit} = {7'd56, 5'd8,  1'b0};
        else if (row_group < 6'd18) {k_step, line_phase, v_tile_bit} = {7'd40, 5'd24, 1'b1};
        else if (row_group < 6'd24) {k_step, line_phase, v_tile_bit} = {7'd40, 5'd24, 1'b0};
        else if (row_group < 6'd31) {k_step, line_phase, v_tile_bit} = {7'd24, 5'd8,  1'b1};
        else if (row_group < 6'd39) {k_step, line_phase, v_tile_bit} = {7'd24, 5'd8,  1'b0};
        else if (row_group < 6'd48) {k_step, line_phase, v_tile_bit} = {7'd13, 5'd31, 1'b1};
        else if (row_group < 6'd58) {k_step, line_phase, v_tile_bit} = {7'd9,  5'd19, 1'b0};
        else                       {k_step, line_phase, v_tile_bit} = {7'd9,  5'd19, 1'b1};
    end

    // Project an eight-pixel-block footprint. Light azimuth shifts the
    // footprint laterally and adjusts the depth edge.
    reg [4:0] shadow_center_x;
    always @(*) begin
        case (light_angle)
            3'd0: shadow_center_x = 5'd5;
            3'd1, 3'd7: shadow_center_x = 5'd6;
            3'd3, 3'd5: shadow_center_x = 5'd10;
            3'd4: shadow_center_x = 5'd11;
            default: shadow_center_x = 5'd8;
        endcase
    end
    wire [4:0] shadow_dx = pixel_x[7:3] - shadow_center_x;
    wire [3:0] shadow_dy = pixel_y[6:3];
    // Fold about the center between blocks, with paired distances 0, 0, 1, 1, ...
    wire [3:0] x_band = shadow_dx[3:0] ^ {4{shadow_dx[4]}};
    wire [2:0] y_band = shadow_dy[2:0] ^ {3{!shadow_dy[3]}};

    // Profile shadows have four sizes. Their axes grow with the top two
    // radius bits; the lower bits select finer sizes for the object itself.
    wire [1:0] size_group = profile_shadow_size;
    wire [3:0] horizontal_limit = profile_mode ?
        (capsule_shape ? {2'b10, size_group} : 4'd1 + {2'b00, size_group}) :
        capsule_shape ? 4'd9 : cube_select ? 4'd4 : 4'd6;
    wire [2:0] vertical_limit = profile_mode ? {1'b0, size_group} :
                                 capsule_shape ? 3'd1 : 3'd3;
    wire torus_hole = !profile_mode && !capsule_shape && !cube_select &&
                      (x_band < 4'd3) && (y_band < 3'd2);
    // The cube is tapered more sharply than the curved silhouettes.
    wire corner_cut = (cube_select && (x_band >= 4'd2) && y_band[1]) ||
                      ((y_band[1:0] == 2'd3) && (x_band >= 4'd5));
    // Shorten the far edge by half a row block under a depth-directed light.
    wire depth_edge = (|light_angle[1:0]) && (y_band == vertical_limit) &&
                      (pixel_y[6] != light_angle[2]) && (pixel_y[2] == pixel_y[6]);
    // In active VGA these tests bound the footprint to x=192..447, y=256..383.
    wire inside_shadow_window = (pixel_x[8] ^ (&pixel_x[7:6])) && (pixel_y[8:7] == 2'd2);
    wire shadow_hit = inside_shadow_window && (x_band <= horizontal_limit) &&
                      (y_band <= vertical_limit) && !torus_hole && !corner_cut && !depth_edge;

    // -------------------------------------------------------------------------
    // 3. Horizontal checker phase modulo 2048
    // -------------------------------------------------------------------------
    reg [10:0] u_accum;
    // line_init_offset is -320 * k_step modulo 2048.
    wire [10:0] pixel_phase = (pixel_x == 10'd0) ? {line_phase, 6'd0} : u_accum;

    // x=0 always selects the starting phase before the first visible floor pixel.
    always @(posedge clk)
        u_accum <= pixel_phase + {4'b0, k_step};

    wire u_tile_bit = pixel_phase[10];
    wire check_parity = u_tile_bit ^ v_tile_bit;

    // -------------------------------------------------------------------------
    // 4. Output Registering & Atmospheric Horizon Fog
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        is_floor    <= rst_n && is_below_horizon;
        floor_check <= check_parity;
        in_shadow   <= rst_n && shadow_hit && is_below_horizon;

        if (delta_y < 8'd24)
            fog_level <= 2'b10;
        else
            fog_level <= 2'b00;
    end

endmodule

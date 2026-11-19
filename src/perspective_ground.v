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

    // -------------------------------------------------------------------------
    // 2. Dynamic Shadow Position based on light_angle
    // -------------------------------------------------------------------------
    reg signed [5:0] shadow_x_center;
    always @(*) begin
        case (light_angle)
            3'd0: shadow_x_center = -6'sd24;
            3'd1: shadow_x_center = -6'sd16;
            3'd2: shadow_x_center =  6'sd0;
            3'd3: shadow_x_center =  6'sd16;
            3'd4: shadow_x_center =  6'sd24;
            3'd5: shadow_x_center =  6'sd16;
            3'd6: shadow_x_center =  6'sd0;
            3'd7: shadow_x_center = -6'sd16;
        endcase
    end

    // Both the row bands and horizontal spans are nested, so their union
    // selects exactly the widest span applicable at a given row.
    wire row_near = pixel_y >= 10'd286 && pixel_y <= 10'd344;
    wire row_mid  = pixel_y >= 10'd294 && pixel_y <= 10'd336;
    wire row_wide = pixel_y >= 10'd304 && pixel_y <= 10'd326;

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

    // Reflect negative distances with one's complement instead of
    // negation. Their absolute magnitude is one more than the reflected
    // value, so the strict negative-side cutoffs are 15, 31 and 43.
    // The 256-pixel window excludes modular aliases outside the shadow.
    wire signed [7:0] screen_dx = $signed(pixel_x[7:0]) - 8'sd64;
    wire signed [7:0] shadow_dx = screen_dx - $signed({{2{shadow_x_center[5]}}, shadow_x_center});
    wire neg_side = shadow_dx[7];
    wire [3:0] abs_block = shadow_dx[6:3] ^ {4{neg_side}};
    wire [2:0] offset = pixel_x[2:0];
    wire neg_excluded_edge = neg_side && (offset == 3'd0);
    wire x_near = (abs_block < 4'd2) && !(neg_excluded_edge && abs_block[0]);
    wire x_mid  = (abs_block < 4'd4) && !(neg_excluded_edge && (&abs_block[1:0]));
    wire x_wide = (abs_block < 4'd5) || ((abs_block == 4'd5) &&
                   (neg_side ? (offset > 3'd4) : (offset < 3'd4)));
    wire shadow_hit = (pixel_x >= 10'd192) && (pixel_x < 10'd448) &&
                      ((row_near && x_near) || (row_mid && x_mid) || (row_wide && x_wide));

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

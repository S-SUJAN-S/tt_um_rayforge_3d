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

    // Decode the shared step and start phase from the scanline.
    wire is_below_horizon = (pixel_y > 10'd230) && video_active;
    wire [7:0] delta_y = pixel_y[7:0] - 8'd230;
    reg [6:0] k_step;
    reg [4:0] line_phase;
    always @(*) begin
        if      (delta_y < 8'd20)  {k_step, line_phase} = {7'd110, 5'd26};
        else if (delta_y < 8'd28)  {k_step, line_phase} = {7'd80,  5'd16};
        else if (delta_y < 8'd40)  {k_step, line_phase} = {7'd56,  5'd8};
        else if (delta_y < 8'd60)  {k_step, line_phase} = {7'd40,  5'd24};
        else if (delta_y < 8'd90)  {k_step, line_phase} = {7'd28,  5'd20};
        else if (delta_y < 8'd130) {k_step, line_phase} = {7'd18,  5'd6};
        else if (delta_y < 8'd180) {k_step, line_phase} = {7'd13,  5'd31};
        else                       {k_step, line_phase} = {7'd9,   5'd19};
    end

    wire v_tile_bit = delta_y[5] ^ delta_y[4];

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

    // Width bands centered at scanline 315.
    reg [5:0] shadow_half_w;
    always @(*) begin
        if      (pixel_y >= 10'd304 && pixel_y <= 10'd326) shadow_half_w = 6'd44;
        else if (pixel_y >= 10'd294 && pixel_y <= 10'd336) shadow_half_w = 6'd32;
        else if (pixel_y >= 10'd286 && pixel_y <= 10'd344) shadow_half_w = 6'd16;
        else                                               shadow_half_w = 6'd0;
    end

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

    // Shadow test
    // The 256-pixel window excludes modular aliases outside the shadow.
    wire signed [7:0] screen_dx = $signed(pixel_x[7:0]) - 8'sd64;
    wire signed [7:0] shadow_dx = screen_dx - $signed({{2{shadow_x_center[5]}}, shadow_x_center});
    wire [7:0] abs_shadow_dx = shadow_dx[7] ? -shadow_dx : shadow_dx;
    wire shadow_hit = (pixel_x >= 10'd192) && (pixel_x < 10'd448) &&
                      (abs_shadow_dx < {2'b0, shadow_half_w});

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

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

    // Horizon at Y = 230
    wire is_below_horizon = (pixel_y > 10'd230) && video_active;
    wire [9:0] dy_full = pixel_y - 10'd230;
    wire [7:0] delta_y = is_below_horizon ? dy_full[7:0] : 8'd0;

    // -------------------------------------------------------------------------
    // 1. Zero-FF Perspective Step Generator (k_step ~ 2048 / delta_y)
    // -------------------------------------------------------------------------
    reg [7:0] k_step;
    always @(*) begin
        if (delta_y < 8'd20)       k_step = 8'd110;
        else if (delta_y < 8'd28)  k_step = 8'd80;
        else if (delta_y < 8'd40)  k_step = 8'd56;
        else if (delta_y < 8'd60)  k_step = 8'd40;
        else if (delta_y < 8'd90)  k_step = 8'd28;
        else if (delta_y < 8'd130) k_step = 8'd18;
        else if (delta_y < 8'd180) k_step = 8'd13;
        else                       k_step = 8'd9;
    end

    wire v_tile_bit = (delta_y[5] ^ delta_y[4]);

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

    // Elliptical Shadow Half-Width for scanline
    wire signed [8:0] sy = $signed({1'b0, delta_y}) - 9'sd85;
    wire [6:0] abs_sy = sy[8] ? (-sy[6:0]) : sy[6:0];
    reg [5:0] shadow_half_w;
    always @(*) begin
        if (abs_sy < 7'd12)      shadow_half_w = 6'd44;
        else if (abs_sy < 7'd22) shadow_half_w = 6'd32;
        else if (abs_sy < 7'd30) shadow_half_w = 6'd16;
        else                     shadow_half_w = 6'd0;
    end

    // -------------------------------------------------------------------------
    // 3. Compact 16-Bit Perspective Accumulator
    // -------------------------------------------------------------------------
    reg signed [15:0] u_accum;
    // -320 * k_step = -(k_step << 8 + k_step << 6)
    wire signed [15:0] line_init_offset = -($signed({1'b0, k_step[6:0], 8'd0}) +
                                            $signed({3'b0, k_step[6:0], 6'd0}));

    always @(posedge clk) begin
        if (!rst_n) begin
            u_accum <= 16'sd0;
        end else if (!video_active || pixel_x == 10'd0) begin
            u_accum <= line_init_offset;
        end else begin
            u_accum <= u_accum + $signed({9'd0, k_step[6:0]});
        end
    end

    wire signed [15:0] u_offset = u_accum + 16'sd16384;
    wire u_tile_bit = u_offset[10];
    wire check_parity = u_tile_bit ^ v_tile_bit;

    // Shadow test
    wire signed [9:0] screen_dx = $signed(pixel_x) - 10'sd320;
    wire signed [9:0] shadow_dx = screen_dx - {{4{shadow_x_center[5]}}, shadow_x_center};
    wire [8:0] abs_shadow_dx = shadow_dx[9] ? (-shadow_dx[8:0]) : shadow_dx[8:0];
    wire shadow_hit = (abs_shadow_dx < {3'b0, shadow_half_w}) && (shadow_half_w > 6'd0);

    // -------------------------------------------------------------------------
    // 4. Output Registering & Atmospheric Horizon Fog
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            is_floor    <= 1'b0;
            floor_check <= 1'b0;
            in_shadow   <= 1'b0;
            fog_level   <= 2'b00;
        end else begin
            is_floor    <= is_below_horizon;
            floor_check <= check_parity;
            in_shadow   <= shadow_hit & is_below_horizon;

            if (delta_y < 8'd16)
                fog_level <= 2'b11;
            else if (delta_y < 8'd24)
                fog_level <= 2'b10;
            else if (delta_y < 8'd60)
                fog_level <= 2'b01;
            else
                fog_level <= 2'b00;
        end
    end

endmodule

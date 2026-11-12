// =============================================================================
// File: perspective_ground.v
// Module: perspective_ground
// Description: Continuous Perspective Ground Plane & Dynamic Shadow Engine
//              Zero-multiplier scanline reciprocal divider during HBLANK,
//              true linear perspective checkerboard, non-tearing accumulator,
//              dynamic elliptical cast shadow, and atmospheric horizon fog.
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

    // Horizon at Y = 230 (10-bit subtraction prevents modulo 256 wrapping)
    wire is_below_horizon = (pixel_y > 10'd230) && video_active;
    wire [9:0] dy_full = pixel_y - 10'd230;
    wire [7:0] delta_y = is_below_horizon ? dy_full[7:0] : 8'd0;

    // Detect falling edge of video_active (start of HBLANK) to trigger division
    reg video_active_d;
    always @(posedge clk) begin
        if (!rst_n) video_active_d <= 1'b0;
        else video_active_d <= video_active;
    end
    wire hblank_start = video_active_d && !video_active;

    // -------------------------------------------------------------------------
    // 1. Sequential 15-Bit Restoring Divider (Runs during 160-cycle HBLANK)
    // Computes: k_step = 16384 / delta_y in 15 clock cycles!
    // -------------------------------------------------------------------------
    reg [3:0]  div_count;
    reg [14:0] div_dividend;
    reg [8:0]  div_rem;
    reg [7:0]  div_denom;
    reg [13:0] div_quot;
    reg [13:0] k_step_reg;

    wire [8:0] next_rem = {div_rem[7:0], div_dividend[14]};
    wire [8:0] sub_rem  = next_rem - {1'b0, div_denom};
    wire       rem_ge   = (next_rem >= {1'b0, div_denom});
    wire [9:0] div_diff = pixel_y - 10'd229;

    always @(posedge clk) begin
        if (!rst_n) begin
            div_count    <= 4'd0;
            div_dividend <= 15'd0;
            div_rem      <= 9'd0;
            div_denom    <= 8'd1;
            div_quot     <= 14'd0;
            k_step_reg   <= 14'd128;
        end else if (hblank_start) begin
            div_count    <= 4'd15;
            div_dividend <= 15'd16384;
            div_rem      <= 9'd0;
            div_denom    <= (pixel_y >= 10'd230) ? div_diff[7:0] : 8'd1;
            div_quot     <= 14'd0;
        end else if (div_count > 4'd0) begin
            div_count    <= div_count - 4'd1;
            div_dividend <= {div_dividend[13:0], 1'b0};
            if (rem_ge) begin
                div_rem  <= sub_rem;
                div_quot <= {div_quot[12:0], 1'b1};
            end else begin
                div_rem  <= next_rem;
                div_quot <= {div_quot[12:0], 1'b0};
            end

            if (div_count == 4'd1) begin
                k_step_reg <= rem_ge ? {div_quot[12:0], 1'b1} : {div_quot[12:0], 1'b0};
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. True 3D Linear Perspective Tile Parity (k_step is exact Z depth)
    // -------------------------------------------------------------------------
    wire v_tile_bit = k_step_reg[5];

    // Dynamic Shadow Position based on light_angle
    reg signed [6:0] shadow_x_center;
    always @(*) begin
        case (light_angle)
            3'd0: shadow_x_center = -7'sd24;
            3'd1: shadow_x_center = -7'sd16;
            3'd2: shadow_x_center =  7'sd0;
            3'd3: shadow_x_center =  7'sd16;
            3'd4: shadow_x_center =  7'sd24;
            3'd5: shadow_x_center =  7'sd16;
            3'd6: shadow_x_center =  7'sd0;
            3'd7: shadow_x_center = -7'sd16;
        endcase
    end

    // Elliptical Shadow Half-Width for this scanline: sy = delta_y - 85 (9-bit prevents +128 overflow)
    wire signed [8:0] sy = $signed({1'b0, delta_y}) - 9'sd85;
    wire [7:0] abs_sy = sy[8] ? (-sy[7:0]) : sy[7:0];
    reg [5:0] shadow_half_w;
    always @(*) begin
        if (abs_sy < 8'd10)      shadow_half_w = 6'd48;
        else if (abs_sy < 8'd18) shadow_half_w = 6'd40;
        else if (abs_sy < 8'd25) shadow_half_w = 6'd28;
        else if (abs_sy < 8'd30) shadow_half_w = 6'd14;
        else                     shadow_half_w = 6'd0;
    end

    // -------------------------------------------------------------------------
    // 3. Pixel-Rate Multiplierless Perspective Accumulator
    // -------------------------------------------------------------------------
    reg signed [21:0] u_accum;
    // Initial line offset: -320 * k_step = -((k_step << 8) + (k_step << 6))
    wire signed [21:0] line_init_offset = -($signed({1'b0, k_step_reg, 8'd0}) +
                                            $signed({3'b0, k_step_reg, 6'd0}));

    always @(posedge clk) begin
        if (!rst_n) begin
            u_accum <= 22'sd0;
        end else if (!video_active || pixel_x == 10'd0) begin
            u_accum <= line_init_offset;
        end else begin
            u_accum <= u_accum + $signed({8'd0, k_step_reg});
        end
    end

    // Parity calculation: U tile parity ^ V tile parity
    wire signed [21:0] u_offset = u_accum + 22'sd32768;
    wire u_tile_bit = u_offset[12];
    wire check_parity = u_tile_bit ^ v_tile_bit;

    // Shadow test
    wire signed [9:0] screen_dx = $signed(pixel_x) - 10'sd320;
    wire signed [9:0] shadow_dx = screen_dx - {{3{shadow_x_center[6]}}, shadow_x_center};
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
                fog_level <= 2'b11; // Horizon fog blend
            else if (delta_y < 8'd24)
                fog_level <= 2'b10;
            else if (delta_y < 8'd60)
                fog_level <= 2'b01;
            else
                fog_level <= 2'b00;
        end
    end

endmodule

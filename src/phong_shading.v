// =============================================================================
// File: phong_shading.v
// Module: phong_shading
// Description: Quantized normal/light dot product and seven-level object palette.
//              Composites the banded sky, checkerboard, and screen-space shadow.
// Author: Sujan S & Team (RVCE ECE)
// Target: SkyWater 130nm CMOS (Tiny Tapeout 1x1 Standard Tile)
// =============================================================================

`default_nettype none

module phong_shading (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        hit_in,         // 1 = 3D object hit
    input  wire signed [7:0] hit_px,   // Hit coordinate / Normal X
    input  wire signed [7:0] hit_py,   // Hit coordinate / Normal Y
    input  wire signed [7:0] hit_pz,   // Hit coordinate / Normal Z
    input  wire        is_floor,       // 1 = Floor plane hit
    input  wire        floor_check,    // 1 = Light tile, 0 = Dark tile
    input  wire        in_shadow,      // 1 = Floor pixel in screen-space shadow
    input  wire [1:0]  fog_level,      // Floor depth fog
    input  wire [2:0]  light_angle,    // Light orbital angle
    input  wire [1:0]  shading_mode,   // 00=Lit, 01=Normal, 10=Depth, 11=Silhouette
    input  wire [1:0]  sky_band,       // High bits of pixel_y for cosmic twilight gradient
    input  wire        video_active,   // Active video region
    output reg  [1:0]  red_out,        // 2-bit Red DAC
    output reg  [1:0]  green_out,      // 2-bit Green DAC
    output reg  [1:0]  blue_out        // 2-bit Blue DAC
);

    // Compact 4-bit signed normal components (-8 to +7)
    wire signed [3:0] nx = hit_px[6:3];
    wire signed [3:0] ny = hit_py[6:3];
    wire signed [3:0] nz = hit_pz[6:3];

    // Opposite lights negate the same XZ term. Cardinal lights double one
    // component, and diagonal lights add or subtract the two components.
    wire signed [4:0] nx_ext = {nx[3], nx};
    wire signed [4:0] nz_ext = {nz[3], nz};
    wire signed [4:0] cardinal = light_angle[1] ? {nz, 1'b0} : {nx, 1'b0};
    wire signed [4:0] dx_diagonal = light_angle[1] ? -nx_ext : nx_ext;
    wire signed [4:0] diagonal = nz_ext + dx_diagonal;
    wire signed [4:0] folded_dot = light_angle[0] ? diagonal : cardinal;
    wire signed [5:0] folded_ext = {folded_dot[4], folded_dot};
    wire signed [5:0] dot_xz = light_angle[2] ? -folded_ext : folded_ext;
    wire signed [5:0] ny_x2 = {ny[3], ny, 1'b0};

    // Four-bit signed input components bound the total dot to [-32,30].
    wire signed [5:0] total_dot = dot_xz + ny_x2;
    wire specular_hit = (total_dot > 7'sd14);

    always @(posedge clk) begin
        if (!rst_n || !video_active) begin
            red_out   <= 2'b00;
            green_out <= 2'b00;
            blue_out  <= 2'b00;
        end else if (hit_in) begin
            case (shading_mode)
                2'b01: begin
                    // MODE 01: Normal Map Visualizer
                    red_out   <= nx[3:2] + 2'b10;
                    green_out <= ny[3:2] + 2'b10;
                    blue_out  <= nz[3:2] + 2'b10;
                end
                2'b10: begin
                    // MODE 10: Depth proxy
                    red_out   <= 2'b00;
                    green_out <= hit_pz[4:3];
                    blue_out  <= 2'b11;
                end
                2'b11: begin
                    // MODE 11: Filled silhouette
                    red_out   <= 2'b11;
                    green_out <= 2'b11;
                    blue_out  <= 2'b00;
                end
                default: begin
                    // MODE 00: Seven-level lighting palette
                    if (specular_hit) begin
                        red_out   <= 2'b11; // 1. Brilliant Specular White Glint (#FFFFFF)
                        green_out <= 2'b11;
                        blue_out  <= 2'b11;
                    end else if (total_dot > 7'sd8) begin
                        red_out   <= 2'b01; // 2. Radiant Cyan (#55FFFF)
                        green_out <= 2'b11;
                        blue_out  <= 2'b11;
                    end else if (total_dot > 7'sd4) begin
                        red_out   <= 2'b00; // 3. Ice Blue (#00AAFF)
                        green_out <= 2'b10;
                        blue_out  <= 2'b11;
                    end else if (total_dot > 7'sd0) begin
                        red_out   <= 2'b00; // 4. Metallic Teal (#00AAAA)
                        green_out <= 2'b10;
                        blue_out  <= 2'b10;
                    end else if (total_dot > -7'sd4) begin
                        red_out   <= 2'b01; // 5. Cobalt highlight (#5555FF)
                        green_out <= 2'b01;
                        blue_out  <= 2'b11;
                    end else if (total_dot > -7'sd8) begin
                        red_out   <= 2'b00; // 6. Deep Emerald (#005555)
                        green_out <= 2'b01;
                        blue_out  <= 2'b01;
                    end else begin
                        red_out   <= 2'b01; // 7. Ambient purple (#550055)
                        green_out <= 2'b00;
                        blue_out  <= 2'b01;
                    end
                end
            endcase
        end else if (is_floor) begin
            if (fog_level >= 2'b10) begin
                red_out   <= 2'b00;
                green_out <= 2'b01;
                blue_out  <= 2'b10;
            end else if (in_shadow) begin
                if (floor_check) begin
                    red_out   <= 2'b01;
                    green_out <= 2'b01;
                    blue_out  <= 2'b10;
                end else begin
                    red_out   <= 2'b00;
                    green_out <= 2'b00;
                    blue_out  <= 2'b01;
                end
            end else begin
                if (floor_check) begin
                    red_out   <= 2'b10;
                    green_out <= 2'b10;
                    blue_out  <= 2'b11; // Bright lilac / lavender
                end else begin
                    red_out   <= 2'b00;
                    green_out <= 2'b01;
                    blue_out  <= 2'b10; // Royal cobalt blue
                end
            end
        end else begin
            // Cosmic Sky Twilight Gradient (from sky_band = pixel_y[7:6])
            case (sky_band)
                2'b00: begin
                    red_out   <= 2'b00;
                    green_out <= 2'b00;
                    blue_out  <= 2'b01; // Deep space navy black
                end
                2'b01: begin
                    red_out   <= 2'b00;
                    green_out <= 2'b00;
                    blue_out  <= 2'b10; // Cosmic indigo
                end
                default: begin
                    red_out   <= 2'b00;
                    green_out <= 2'b01;
                    blue_out  <= 2'b10; // Atmospheric twilight cyan
                end
            endcase
        end
    end

endmodule

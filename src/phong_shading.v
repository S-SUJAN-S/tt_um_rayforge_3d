// =============================================================================
// File: phong_shading.v
// Module: phong_shading
// Description: Zero-Multiplier 7-Level Metallic Phong Shading & Color Palette Engine
//              Blends 3D specular highlights, dynamic shadows, checkered floor,
//              smooth atmospheric depth fog, and clean cosmic twilight gradient.
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
    input  wire        in_shadow,      // 1 = Floor in 3D object shadow
    input  wire [1:0]  fog_level,      // Floor depth fog
    input  wire [2:0]  light_angle,    // Light orbital angle
    input  wire [1:0]  shading_mode,   // 00=Phong, 01=Normal, 10=Fog, 11=Wire
    input  wire [9:0]  pixel_x,        // Screen coordinates
    input  wire [9:0]  pixel_y,
    input  wire        video_active,   // Active video region
    output reg  [1:0]  red_out,        // 2-bit Red DAC
    output reg  [1:0]  green_out,      // 2-bit Green DAC
    output reg  [1:0]  blue_out        // 2-bit Blue DAC
);

    // Surface Normal Vector (sign-extended 6-bit)
    wire signed [5:0] norm_x = {{2{hit_px[7]}}, hit_px[6:3]};
    wire signed [5:0] norm_y = {{2{hit_py[7]}}, hit_py[6:3]};
    wire signed [5:0] norm_z = {{2{hit_pz[7]}}, hit_pz[6:3]};

    // Zero-multiplier shift-add dot product: N . L
    wire signed [7:0] nx_times_4 = norm_x <<< 2;
    wire signed [7:0] ny_times_4 = norm_y <<< 2;
    wire signed [7:0] nz_times_4 = norm_z <<< 2;
    wire signed [7:0] nx_times_3 = (norm_x <<< 1) + norm_x;
    wire signed [7:0] nz_times_3 = (norm_z <<< 1) + norm_z;

    reg signed [8:0] total_dot;
    always @(*) begin
        case (light_angle)
            3'd0: total_dot = nx_times_4 + ny_times_4;
            3'd1: total_dot = nx_times_3 + nz_times_3 + ny_times_4;
            3'd2: total_dot = nz_times_4 + ny_times_4;
            3'd3: total_dot = -nx_times_3 + nz_times_3 + ny_times_4;
            3'd4: total_dot = -nx_times_4 + ny_times_4;
            3'd5: total_dot = -nx_times_3 - nz_times_3 + ny_times_4;
            3'd6: total_dot = -nz_times_4 + ny_times_4;
            3'd7: total_dot = nx_times_3 - nz_times_3 + ny_times_4;
        endcase
    end

    wire specular_hit = (total_dot > 9'sd26);

    always @(posedge clk) begin
        if (!rst_n || !video_active) begin
            red_out   <= 2'b00;
            green_out <= 2'b00;
            blue_out  <= 2'b00;
        end else if (hit_in) begin
            case (shading_mode)
                2'b01: begin
                    // MODE 01: Normal Map Visualizer (XYZ -> RGB)
                    red_out   <= norm_x[3:2] + 2'b10;
                    green_out <= norm_y[3:2] + 2'b10;
                    blue_out  <= norm_z[3:2] + 2'b10;
                end
                2'b10: begin
                    // MODE 10: Depth Fog Visualizer
                    red_out   <= 2'b00;
                    green_out <= hit_pz[4:3];
                    blue_out  <= 2'b11;
                end
                2'b11: begin
                    // MODE 11: Edge Silhouette
                    red_out   <= 2'b11;
                    green_out <= 2'b11;
                    blue_out  <= 2'b00;
                end
                default: begin
                    // MODE 00: Full 7-Level Metallic Phong Shading Palette
                    if (specular_hit) begin
                        red_out   <= 2'b11; // 1. Brilliant Specular White Glint (#FFFFFF)
                        green_out <= 2'b11;
                        blue_out  <= 2'b11;
                    end else if (total_dot > 9'sd16) begin
                        red_out   <= 2'b01; // 2. Radiant Cyan (#55FFFF)
                        green_out <= 2'b11;
                        blue_out  <= 2'b11;
                    end else if (total_dot > 9'sd8) begin
                        red_out   <= 2'b00; // 3. Ice Blue (#00AAFF)
                        green_out <= 2'b10;
                        blue_out  <= 2'b11;
                    end else if (total_dot > 9'sd0) begin
                        red_out   <= 2'b00; // 4. Metallic Teal (#00AAAA)
                        green_out <= 2'b10;
                        blue_out  <= 2'b10;
                    end else if (total_dot > -9'sd8) begin
                        red_out   <= 2'b00; // 5. Royal Cobalt (#0055AA)
                        green_out <= 2'b01;
                        blue_out  <= 2'b10;
                    end else if (total_dot > -9'sd18) begin
                        red_out   <= 2'b00; // 6. Deep Emerald (#005555)
                        green_out <= 2'b01;
                        blue_out  <= 2'b01;
                    end else begin
                        red_out   <= 2'b00; // 7. Ambient Indigo (#000055)
                        green_out <= 2'b00;
                        blue_out  <= 2'b01;
                    end
                end
            endcase
        end else if (is_floor) begin
            if (fog_level >= 2'b10) begin
                // Horizon fog blend: Eliminates high-frequency spatial aliasing / moire
                red_out   <= 2'b00;
                green_out <= 2'b01;
                blue_out  <= 2'b10;
            end else if (in_shadow) begin
                // Deep elliptical drop shadow on floor
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
                // Perspective checkerboard floor
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
            // Cosmic Sky Twilight Gradient
            if (pixel_y < 10'd80) begin
                red_out   <= 2'b00;
                green_out <= 2'b00;
                blue_out  <= 2'b01; // Deep space navy black
            end else if (pixel_y < 10'd160) begin
                red_out   <= 2'b00;
                green_out <= 2'b00;
                blue_out  <= 2'b10; // Cosmic indigo
            end else begin
                red_out   <= 2'b00;
                green_out <= 2'b01;
                blue_out  <= 2'b10; // Atmospheric twilight cyan
            end
        end
    end

endmodule

// =============================================================================
// File: vga_timing_gen.v
// Module: vga_timing_gen
// Description: Standard 640x480 @ 60Hz VGA timing generator (25.175 MHz pixel clock)
//              Ultra-compact: direct counter wire outputs save 20 flip-flops
// Author: Sujan S & Team (RVCE ECE)
// Target: SkyWater 130nm CMOS (Tiny Tapeout 1x1 Standard Tile)
// =============================================================================

`default_nettype none

module vga_timing_gen (
    input  wire        clk,          // 25.175 MHz pixel clock
    input  wire        rst_n,        // Synchronous active-low reset
    output wire [9:0]  pixel_x,      // Current X coordinate [0..639]
    output wire [9:0]  pixel_y,      // Current Y coordinate [0..479]
    output reg         video_active, // High when inside 640x480 active display
    output reg         hsync,        // Horizontal sync (active low)
    output reg         vsync,        // Vertical sync (active low)
    output reg         frame_pulse   // 1-cycle pulse at start of vertical blank (60 Hz)
);

    localparam H_ACTIVE     = 10'd640;
    localparam H_FRONT      = 10'd16;
    localparam H_SYNC_PULSE = 10'd96;
    localparam H_BACK       = 10'd48;
    localparam H_TOTAL      = 10'd800;

    localparam V_ACTIVE     = 10'd480;
    localparam V_FRONT      = 10'd10;
    localparam V_SYNC_PULSE = 10'd2;
    localparam V_BACK       = 10'd33;
    localparam V_TOTAL      = 10'd525;

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    // Direct wire outputs save 20 flip-flops and mux logic!
    assign pixel_x = h_cnt;
    assign pixel_y = v_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            h_cnt        <= 10'd0;
            v_cnt        <= 10'd0;
            video_active <= 1'b0;
            hsync        <= 1'b1;
            vsync        <= 1'b1;
            frame_pulse  <= 1'b0;
        end else begin
            if (h_cnt == H_TOTAL - 10'd1) begin
                h_cnt <= 10'd0;
                if (v_cnt == V_TOTAL - 10'd1) begin
                    v_cnt       <= 10'd0;
                    frame_pulse <= 1'b1;
                end else begin
                    v_cnt       <= v_cnt + 10'd1;
                    frame_pulse <= 1'b0;
                end
            end else begin
                h_cnt       <= h_cnt + 10'd1;
                frame_pulse <= 1'b0;
            end

            hsync <= ~((h_cnt >= (H_ACTIVE + H_FRONT)) && 
                       (h_cnt <  (H_ACTIVE + H_FRONT + H_SYNC_PULSE)));

            vsync <= ~((v_cnt >= (V_ACTIVE + V_FRONT)) && 
                       (v_cnt <  (V_ACTIVE + V_FRONT + V_SYNC_PULSE)));

            video_active <= (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);
        end
    end

endmodule

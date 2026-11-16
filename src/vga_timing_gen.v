// =============================================================================
// File: vga_timing_gen.v
// Module: vga_timing_gen
// Description: Standard 640x480 @ 60Hz VGA timing generator (25.175 MHz pixel clock)
//              Registered sync matches the three-clock renderer latency.
// Author: Sujan S & Team (RVCE ECE)
// Target: SkyWater 130nm CMOS (Tiny Tapeout 1x1 Standard Tile)
// =============================================================================

`default_nettype none

module vga_timing_gen (
    input  wire        clk,          // 25.175 MHz pixel clock
    input  wire        rst_n,        // Synchronous active-low reset
    output wire [9:0]  pixel_x,      // Current X coordinate [0..639]
    output wire [9:0]  pixel_y,      // Current Y coordinate [0..479]
    output wire        video_active, // High when inside 640x480 active display
    output reg         hsync,        // Horizontal sync (active low)
    output reg         vsync,        // Vertical sync (active low)
    output reg         frame_pulse   // 1-cycle pulse on frame wrap
);

    localparam H_ACTIVE     = 10'd640;
    localparam H_FRONT      = 10'd16;
    localparam H_SYNC_PULSE = 10'd96;
    localparam H_TOTAL      = 10'd800;

    localparam V_ACTIVE     = 10'd480;
    localparam V_FRONT      = 10'd10;
    localparam V_SYNC_PULSE = 10'd2;
    localparam V_TOTAL      = 10'd525;

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    wire end_of_line = (h_cnt == H_TOTAL - 10'd1);
    wire end_of_frame = (v_cnt == V_TOTAL - 10'd1);

    // Counter decodes are sampled by the synchronous rendering stages.
    assign pixel_x = h_cnt;
    assign pixel_y = v_cnt;
    assign video_active = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    always @(posedge clk) begin
        if (!rst_n) begin
            h_cnt        <= 10'd0;
            v_cnt        <= 10'd0;
            hsync        <= 1'b1;
            vsync        <= 1'b1;
            frame_pulse  <= 1'b0;
        end else begin
            if (end_of_line) begin
                h_cnt <= 10'd0;
                if (end_of_frame) begin
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

            // The counter advances on the same edge as the registered pins.
            // Offset the transitions so the pin sync follows the rendered beam.
            if (h_cnt == (H_ACTIVE + H_FRONT + 10'd2))
                hsync <= 1'b0;
            else if (h_cnt == (H_ACTIVE + H_FRONT + H_SYNC_PULSE + 10'd2))
                hsync <= 1'b1;
            if (h_cnt == 10'd2) begin
                if (v_cnt == (V_ACTIVE + V_FRONT))
                    vsync <= 1'b0;
                else if (v_cnt == (V_ACTIVE + V_FRONT + V_SYNC_PULSE))
                    vsync <= 1'b1;
            end
        end
    end

endmodule

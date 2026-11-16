// =============================================================================
// File: bist_diagnostic.v
// Module: bist_diagnostic
// Description: Built-in Self-Test (BIST) with 16-bit LFSR & 7-Segment Status Driver
// Author: Sujan S & Team (RVCE ECE)
// Target: SkyWater 130nm CMOS (Tiny Tapeout 1x1 Standard Tile)
// =============================================================================

`default_nettype none

module bist_diagnostic (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bist_en,       // Trigger BIST mode via DIP Switch 7
    input  wire        frame_pulse,   // 60Hz heartbeat for 7-seg character cycling
    input  wire        visibility_error, // RGB active/blank mismatch at the output
    output reg  [6:0]  seven_seg_out, // 7-Segment display cathodes (g-f-e-d-c-b-a)
    output reg         bist_pass_led  // Status LED (1 = PASS, 0 = Testing / Fail)
);

    // -------------------------------------------------------------------------
    // 16-bit Galois LFSR using feedback mask 16'hA011, with a visibility
    // mismatch injected into the least significant bit during capture.
    // -------------------------------------------------------------------------
    reg [15:0] lfsr;
    reg [10:0] test_cycles;
    reg        signature_valid;

    // Expected golden signature after 1024 test cycles
    localparam [15:0] GOLDEN_SIG = 16'h0CB8;

    // Capture the signature on the first edge after all 1,024 shifts.
    // The frozen LFSR retains that signature while the request is held.
    always @(posedge clk) begin
        if (!rst_n || !bist_en) begin
            lfsr            <= 16'hACE1;
            test_cycles     <= 11'd0;
            signature_valid <= 1'b0;
        end else if (!test_cycles[10]) begin
            test_cycles <= test_cycles + 11'd1;
            lfsr <= {lfsr[14:0], visibility_error} ^ (lfsr[15] ? 16'hA011 : 16'h0000);
        end else begin
            signature_valid <= (lfsr == GOLDEN_SIG);
        end
    end

    // -------------------------------------------------------------------------
    // 7-Segment Display Animator
    // -------------------------------------------------------------------------
    localparam [6:0] SEG_P = 7'b1110011; // 'P'
    localparam [6:0] SEG_3 = 7'b1001111; // '3'
    localparam [6:0] SEG_D = 7'b1011110; // 'd'
    localparam [6:0] SEG_MINUS = 7'b1000000; // '-'

    reg idle_glyph;
    reg [4:0] idle_frames;

    always @(posedge clk) begin
        if (!rst_n) begin
            idle_glyph <= 1'b0;
            idle_frames <= 5'd0;
        end else if (frame_pulse && !bist_en) begin
            idle_frames <= idle_frames + 5'd1;
            if (&idle_frames)
                idle_glyph <= ~idle_glyph;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            seven_seg_out <= SEG_3;
            bist_pass_led <= 1'b0;
        end else begin
            bist_pass_led <= bist_en && signature_valid;
            if (bist_en)
                seven_seg_out <= signature_valid ? SEG_P : SEG_MINUS;
            else
                seven_seg_out <= idle_glyph ? SEG_D : SEG_3;
        end
    end

endmodule

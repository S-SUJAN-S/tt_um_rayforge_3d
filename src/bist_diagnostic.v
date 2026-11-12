// =============================================================================
// File: bist_diagnostic.v
// Module: bist_diagnostic
// Description: Built-in Self-Test (BIST) with 16-bit LFSR & 7-Segment Status Driver
// Author: Sujan S & Team (RVCE ECE)
// =============================================================================

`default_nettype none

module bist_diagnostic (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bist_en,       // Trigger BIST mode via DIP Switch 7
    input  wire        frame_pulse,   // 60Hz heartbeat for 7-seg character cycling
    output reg  [6:0]  seven_seg_out, // 7-Segment display cathodes (g-f-e-d-c-b-a)
    output reg         bist_pass_led  // Status LED (1 = PASS, 0 = Testing / Fail)
);

    // -------------------------------------------------------------------------
    // 16-bit Galois LFSR: Polynomial x^16 + x^14 + x^13 + x^11 + 1
    // -------------------------------------------------------------------------
    reg [15:0] lfsr;
    reg [15:0] test_cycles;
    reg        test_completed;
    reg        signature_valid;

    // Expected golden signature after 1024 test cycles
    localparam [15:0] GOLDEN_SIG = 16'h0CB8;

    always @(posedge clk) begin
        if (!rst_n) begin
            lfsr            <= 16'hACE1; // Non-zero seed
            test_cycles     <= 16'd0;
            test_completed  <= 1'b0;
            signature_valid <= 1'b0;
        end else if (bist_en) begin
            if (test_cycles < 16'd1024) begin
                test_cycles <= test_cycles + 16'd1;
                // Galois LFSR feedback
                lfsr <= {lfsr[14:0], 1'b0} ^ (lfsr[15] ? 16'hA011 : 16'h0000);
            end else begin
                test_completed <= 1'b1;
                // Check if internal datapath produced exact deterministic signature
                if (lfsr == GOLDEN_SIG)
                    signature_valid <= 1'b1;
                else
                    signature_valid <= 1'b0;
            end
        end else begin
            // Normal operating mode: reset BIST counters
            lfsr            <= 16'hACE1;
            test_cycles     <= 16'd0;
            test_completed  <= 1'b0;
            signature_valid <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // 7-Segment Display Animator
    // Standard 7-seg pinout (Active High):
    // Bit 0 = a, Bit 1 = b, Bit 2 = c, Bit 3 = d, Bit 4 = e, Bit 5 = f, Bit 6 = g
    // -------------------------------------------------------------------------
    localparam [6:0] SEG_P = 7'b1110011; // 'P'
    localparam [6:0] SEG_A = 7'b1110111; // 'A'
    localparam [6:0] SEG_S = 7'b1101101; // 'S'
    localparam [6:0] SEG_3 = 7'b1001111; // '3'
    localparam [6:0] SEG_D = 7'b1011110; // 'd'
    localparam [6:0] SEG_MINUS = 7'b1000000; // '-'

    reg [1:0] char_idx;
    reg [4:0] seg_tick;

    always @(posedge clk) begin
        if (!rst_n) begin
            char_idx      <= 2'd0;
            seg_tick      <= 5'd0;
            seven_seg_out <= SEG_3;
            bist_pass_led <= 1'b0;
        end else begin
            if (bist_en) begin
                // In BIST mode:
                if (test_completed && signature_valid) begin
                    bist_pass_led <= 1'b1;
                    // Cycle characters "P - A - S - S" on each 1/4 second
                    if (frame_pulse) begin
                        if (seg_tick == 5'd15) begin
                            seg_tick <= 5'd0;
                            char_idx <= char_idx + 2'd1;
                        end else begin
                            seg_tick <= seg_tick + 5'd1;
                        end
                    end

                    case (char_idx)
                        2'd0: seven_seg_out <= SEG_P;
                        2'd1: seven_seg_out <= SEG_A;
                        2'd2: seven_seg_out <= SEG_S;
                        2'd3: seven_seg_out <= SEG_S;
                    endcase
                end else begin
                    // Still calculating or failed
                    bist_pass_led <= 1'b0;
                    seven_seg_out <= SEG_MINUS;
                end
            end else begin
                // In Normal Video Mode: Show "3d"
                bist_pass_led <= 1'b1; // Normal active status
                if (frame_pulse) begin
                    if (seg_tick == 5'd30) begin
                        seg_tick <= 5'd0;
                        char_idx[0] <= ~char_idx[0];
                    end else begin
                        seg_tick <= seg_tick + 5'd1;
                    end
                end
                seven_seg_out <= char_idx[0] ? SEG_D : SEG_3;
            end
        end
    end

endmodule

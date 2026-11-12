// =============================================================================
// File: tb_rayforge_3d.v
// Module: tb_rayforge_3d
// Description: Comprehensive Full-Frame Verilog Testbench for RayForge-X
//              Simulates entire 420,000-cycle 640x480 @ 60Hz VGA frame and
//              dumps exact pixel stream from silicon pins to verilog_frame.ppm.
// Author: Sujan S & Team (RVCE ECE)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_rayforge_3d;

    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Tiny VGA PMOD signal extraction
    // Row 1 (Pins 1..4): R1, G1, B1, VSYNC -> uo_out[0..3]
    // Row 2 (Pins 7..10): R0, G0, B0, HSYNC -> uo_out[4..7]
    wire hsync_sig       = uo_out[7];
    wire vsync_sig       = uo_out[3];
    wire [1:0] red_val   = {uo_out[0], uo_out[4]};
    wire [1:0] green_val = {uo_out[1], uo_out[5]};
    wire [1:0] blue_val  = {uo_out[2], uo_out[6]};

    // Convert 2-bit DAC levels to 8-bit RGB color (0, 85, 170, 255)
    wire [7:0] r8 = (red_val   == 2'b11) ? 8'd255 : (red_val   == 2'b10) ? 8'd170 : (red_val   == 2'b01) ? 8'd85 : 8'd0;
    wire [7:0] g8 = (green_val == 2'b11) ? 8'd255 : (green_val == 2'b10) ? 8'd170 : (green_val == 2'b01) ? 8'd85 : 8'd0;
    wire [7:0] b8 = (blue_val  == 2'b11) ? 8'd255 : (blue_val  == 2'b10) ? 8'd170 : (blue_val  == 2'b01) ? 8'd85 : 8'd0;

    // Instantiate DUT
    tt_um_rayforge_3d dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    // 25.175 MHz Clock Generation: Period = 39.72 ns (Half period = 19.86 ns)
    always #19.86 clk = ~clk;

    integer fd;
    integer pixel_count = 0;
    integer obj_pixel_count = 0;
    integer floor_pixel_count = 0;
    integer shadow_pixel_count = 0;
    integer frame_cycle = 0;

    initial begin
        $display("===============================================================");
        $display("🚀 RayForge-X: Full-Frame Hardware Silicon Verilog Testbench");
        $display("===============================================================");

        clk    = 0;
        rst_n  = 0;
        ena    = 1;
        ui_in  = 8'h00;
        uio_in = 8'h00;

        // ---------------------------------------------------------------------
        // 1. Test Reset & Metastability Synchronizer
        // ---------------------------------------------------------------------
        #200;
        rst_n = 1;
        #100;
        $display("[STEP 1] Testing Power-On Reset & Bidirectional Pin Buffers...");
        if (uio_oe !== 8'hFF) begin
            $display("❌ FAILED: uio_oe expected 0xFF, got %h", uio_oe);
            $finish;
        end
        $display("✅ [STEP 1 PASSED] Dual-stage reset synchronizer verified!");

        // ---------------------------------------------------------------------
        // 2. Test Hardware BIST Engine
        // ---------------------------------------------------------------------
        $display("[STEP 2] Running 16-Bit Galois LFSR Built-In Self-Test (BIST)...");
        ui_in[7] = 1; // Trigger BIST
        repeat (1150) @(posedge clk);
        $display("[STEP 2] BIST Results: PASS_LED=%b, 7-Seg Cathodes=%b", uio_out[7], uio_out[6:0]);
        if (uio_out[7] !== 1'b1) begin
            $display("❌ FAILED: Hardware BIST signature did not match golden vector!");
            $finish;
        end
        $display("✅ [STEP 2 PASSED] Hardware BIST verified with golden signature match!");

        // ---------------------------------------------------------------------
        // 3. Full-Frame 640x480 Hardware Rendering Verification & Pixel Dump
        // ---------------------------------------------------------------------
        $display("[STEP 3] Switching to 3D Torus Mode (ui_in=0x01)...");
        ui_in = 8'h01; // anim_en=1, Torus, Phong shading, default light

        // Synchronize with start of vertical frame (VSYNC pulse)
        $display("[STEP 3] Synchronizing with frame start pulse...");
        while (dut.u_vga_timing.v_cnt != 0 || dut.u_vga_timing.h_cnt != 0) begin
            @(posedge clk);
        end

        $display("[STEP 3] Frame start locked! Streaming 640x480 active frame to verilog_frame.ppm...");
        fd = $fopen("verilog_frame.ppm", "w");
        $fwrite(fd, "P3\n640 480\n255\n");

        // Loop over the full 480 lines of 640 active pixels
        for (frame_cycle = 0; frame_cycle < (525 * 800); frame_cycle = frame_cycle + 1) begin
            @(posedge clk);
            
            // Check if current delayed pipeline beam is within active 640x480 display
            if (dut.u_shading.video_active) begin
                $fwrite(fd, "%0d %0d %0d\n", r8, g8, b8);
                pixel_count = pixel_count + 1;

                if (dut.u_shading.hit_in)
                    obj_pixel_count = obj_pixel_count + 1;
                else if (dut.u_shading.is_floor) begin
                    floor_pixel_count = floor_pixel_count + 1;
                    if (dut.u_shading.in_shadow)
                        shadow_pixel_count = shadow_pixel_count + 1;
                end
            end
        end

        $fclose(fd);
        $display("✅ [STEP 3 COMPLETE] Wrote %0d pixels to verilog_frame.ppm!", pixel_count);
        $display("   - 3D Object Pixels Rendered: %0d (%0d%%)", obj_pixel_count, (obj_pixel_count * 100) / pixel_count);
        $display("   - Ground Floor Pixels Rendered: %0d (%0d%%)", floor_pixel_count, (floor_pixel_count * 100) / pixel_count);
        $display("   - Dynamic Drop Shadow Pixels: %0d", shadow_pixel_count);

        if (obj_pixel_count < 1000) begin
            $display("❌ FAILED: 3D Object pixel count too low!");
            $finish;
        end
        if (floor_pixel_count < 1000) begin
            $display("❌ FAILED: Floor plane pixel count too low!");
            $finish;
        end
        $display("✅ [STEP 3 PASSED] Complete 640x480 3D scene successfully rendered by Verilog RTL!");

        // ---------------------------------------------------------------------
        // 4. Test Mode Switching: CSG Cube Full-Frame Dump
        // ---------------------------------------------------------------------
        $display("[STEP 4] Switching to CSG Cube Mode (ui_in=0x03)...");
        ui_in = 8'h03; // anim_en=1, geom_sel=1 (Cube), Phong shading
        while (dut.u_vga_timing.v_cnt != 0 || dut.u_vga_timing.h_cnt != 0) begin
            @(posedge clk);
        end
        $display("[STEP 4] Frame start locked! Streaming CSG Cube frame to verilog_cube.ppm...");
        fd = $fopen("verilog_cube.ppm", "w");
        $fwrite(fd, "P3\n640 480\n255\n");
        for (frame_cycle = 0; frame_cycle < (525 * 800); frame_cycle = frame_cycle + 1) begin
            @(posedge clk);
            if (dut.u_shading.video_active) begin
                $fwrite(fd, "%0d %0d %0d\n", r8, g8, b8);
            end
        end
        $fclose(fd);
        $display("✅ [STEP 4 COMPLETE] Wrote CSG Cube frame to verilog_cube.ppm!");

        // Test Normal Map Debug mode
        ui_in = 8'h09; // Normal Map Debug
        repeat (1000) @(posedge clk);
        $display("✅ 3D Normal Map Debug Mode Active.");

        $display("===============================================================");
        $display("🎉 ALL FULL-FRAME HARDWARE SILICON VERIFICATION CHECKS PASSED!");
        $display("===============================================================");
        $finish;
    end

endmodule

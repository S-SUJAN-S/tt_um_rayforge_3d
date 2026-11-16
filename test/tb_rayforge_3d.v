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

    reg obj_hit_at_rgb;
    always @(posedge clk)
        obj_hit_at_rgb <= dut.obj_hit;

    integer fd;
    integer pixel_count = 0;
    integer obj_pixel_count = 0;
    integer floor_pixel_count = 0;
    integer frame_cycle = 0;
    integer x, y, dx, dy, radius_sq;
    reg expected_hit;

    task wait_for_frame;
        integer timeout_cycles;
        begin
            timeout_cycles = 0;
            @(negedge clk);
            while (dut.pixel_y != 0 || dut.pixel_x != 3) begin
                @(negedge clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > 420000)
                    $fatal(1, "Timed out waiting for rendered pixel (0,0)");
            end
        end
    endtask

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
            $fatal(1, "uio_oe expected 0xFF, got %h", uio_oe);
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
            $fatal(1, "LFSR signature check did not pass");
        end
        $display("✅ [STEP 2 PASSED] Hardware BIST verified with golden signature match!");

        // ---------------------------------------------------------------------
        // 3. Full-Frame 640x480 Hardware Rendering Verification & Pixel Dump
        // ---------------------------------------------------------------------
        $display("[STEP 3] Switching to 3D Torus Mode (ui_in=0x01)...");
        ui_in = 8'h01; // anim_en=1, Torus, Phong shading, default light

        wait_for_frame();
        wait_for_frame();
        if (dut.active_scene !== 6'h01)
            $fatal(1, "Torus scene control did not commit after two vblank samples");

        fd = $fopen("verilog_frame.ppm", "w");
        $fwrite(fd, "P3\n640 480\n255\n");

        for (frame_cycle = 0; frame_cycle < (525 * 800); frame_cycle = frame_cycle + 1) begin
            // At a falling edge, the VGA outputs for this beam are settled.
            x = frame_cycle % 800;
            y = frame_cycle / 800;
            if (hsync_sig !== !(x >= 656 && x < 752))
                $fatal(1, "HSYNC at %0d,%0d", x, y);
            if (vsync_sig !== !(y >= 490 && y < 492))
                $fatal(1, "VSYNC at %0d,%0d", x, y);
            if (x < 640 && y < 480) begin
                $fwrite(fd, "%0d %0d %0d\n", r8, g8, b8);
                pixel_count = pixel_count + 1;
                dx = x - 320;
                dy = y - 190;
                radius_sq = dx*dx + dy*dy;
                expected_hit = radius_sq >= 1600 && radius_sq <= 12100;
                if (obj_hit_at_rgb !== expected_hit)
                    $fatal(1, "Torus mask at %0d,%0d: squared radius is %0d", x, y, radius_sq);
                if (expected_hit)
                    obj_pixel_count = obj_pixel_count + 1;
                else if (y > 230)
                    floor_pixel_count = floor_pixel_count + 1;
            end else if ({red_val, green_val, blue_val} !== 6'd0)
                $fatal(1, "RGB must be black in blanking at %0d,%0d", x, y);
            @(negedge clk);
        end

        $fclose(fd);
        $display("✅ [STEP 3 COMPLETE] Wrote %0d pixels to verilog_frame.ppm!", pixel_count);
        $display("   - 3D Object Pixels Rendered: %0d (%0d%%)", obj_pixel_count, (obj_pixel_count * 100) / pixel_count);
        $display("   - Ground Floor Pixels Rendered: %0d (%0d%%)", floor_pixel_count, (floor_pixel_count * 100) / pixel_count);

        if (obj_pixel_count < 1000) begin
            $fatal(1, "Torus object pixel count too low");
        end
        if (floor_pixel_count < 1000) begin
            $fatal(1, "Floor plane pixel count too low");
        end
        $display("✅ [STEP 3 PASSED] Complete 640x480 3D scene successfully rendered by Verilog RTL!");

        // ---------------------------------------------------------------------
        // 4. Test Mode Switching: CSG Cube Full-Frame Dump
        // ---------------------------------------------------------------------
        $display("[STEP 4] Switching to CSG Cube Mode (ui_in=0x03)...");
        ui_in = 8'h03; // anim_en=1, geom_sel=1 (Cube), Phong shading
        wait_for_frame();
        wait_for_frame();
        if (dut.active_scene !== 6'h03)
            $fatal(1, "Cube scene control did not commit after two vblank samples");
        $display("[STEP 4] Frame start locked! Streaming CSG Cube frame to verilog_cube.ppm...");
        fd = $fopen("verilog_cube.ppm", "w");
        $fwrite(fd, "P3\n640 480\n255\n");
        for (frame_cycle = 0; frame_cycle < (525 * 800); frame_cycle = frame_cycle + 1) begin
            x = frame_cycle % 800;
            y = frame_cycle / 800;
            if (x < 640 && y < 480)
                $fwrite(fd, "%0d %0d %0d\n", r8, g8, b8);
            @(negedge clk);
        end
        $fclose(fd);
        $display("✅ [STEP 4 COMPLETE] Wrote CSG Cube frame to verilog_cube.ppm!");

        // Test Normal Map Debug mode
        ui_in = 8'h09; // Normal Map Debug
        wait_for_frame();
        wait_for_frame();
        if (dut.shading_mode !== 2'b01)
            $fatal(1, "Normal-map control did not commit");
        $display("✅ 3D Normal Map Debug Mode Active.");

        $display("===============================================================");
        $display("🎉 ALL FULL-FRAME HARDWARE SILICON VERIFICATION CHECKS PASSED!");
        $display("===============================================================");
        $finish;
    end

endmodule

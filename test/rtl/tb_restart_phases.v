`timescale 1ps/1ps
`default_nettype none

module tb_restart_phases;
    localparam [7:0] INACTIVE = 8'h88;
    reg clk = 0;
    always #19861 clk = ~clk;
    reg rst_n = 0;
    reg ena = 0;
    wire [7:0] video, diag, oe;

    tt_um_rayforge_3d dut (
        .clk(clk), .rst_n(rst_n), .ena(ena), .ui_in(8'b0), .uio_in(8'b0),
        .uo_out(video), .uio_out(diag), .uio_oe(oe)
    );

    // Assert while a bright pixel is streaming. Pin output must hold until
    // the next clock and then remain inactive while either control is low.
    task automatic restart(input bit select_enable, input integer offset, input integer expected_first_sync,
                           output integer first_sync);
        integer cycles;
        reg [7:0] before_assert;
        begin
            @(negedge clk);
            before_assert = video;
            if (before_assert == INACTIVE)
                $fatal(1, "Restart stimulus must begin during active video");
            #101;
            if (select_enable)
                ena = 0;
            else
                rst_n = 0;
            #1;
            if (video !== before_assert)
                $fatal(1, "VGA pin changed without an output clock");
            repeat (4) begin
                @(negedge clk);
                if (video !== INACTIVE || diag[7] !== 1'b0 || oe !== 8'hff)
                    $fatal(1, "Wrong inactive pins with reset or enable asserted");
            end

            #(offset);
            if (select_enable)
                ena = 1;
            else
                rst_n = 1;
            // Both clocks used for synchronized release precede streaming.
            repeat (2) begin
                @(posedge clk);
                #1;
                if (video !== INACTIVE)
                    $fatal(1, "VGA started before synchronized release");
            end
            first_sync = 0;
            for (cycles = 3; cycles <= 800 && first_sync == 0; cycles = cycles + 1) begin
                @(posedge clk);
                #1;
                if (video[3] !== 1'b1 || (video[7] !== 1'b0 && video[7] !== 1'b1))
                    $fatal(1, "Unknown or incorrect sync at restart clock %0d", cycles);
                if (video[7] == 1'b0)
                    first_sync = cycles;
            end
            if (first_sync == 0 || (expected_first_sync != 0 && first_sync != expected_first_sync))
                $fatal(1, "Restart sync latency %0d differs from %0d at phase %0d",
                       first_sync, expected_first_sync, offset);

            // Reach active video on the next line for the next trial.
            repeat (200) @(negedge clk);
        end
    endtask

    integer control, phase, first_sync, reference_sync;
    initial begin
        repeat (8) @(negedge clk);
        rst_n = 1;
        ena = 1;
        repeat (10) @(negedge clk);
        reference_sync = 0;
        for (control = 0; control < 2; control = control + 1) begin
            // Sweep the period and test 2 ps on both sides of the rising edge.
            for (phase = 1; phase < 39722; phase = phase + 993) begin
                if (phase != 19861) begin
                    restart(control != 0, phase, reference_sync, first_sync);
                    reference_sync = first_sync;
                end
            end
            restart(control != 0, 19859, reference_sync, first_sync);
            restart(control != 0, 19863, reference_sync, first_sync);
        end
        $display("PASS 84 phased restarts through reset and enable, first HSYNC at clock %0d", reference_sync);
        $finish;
    end
endmodule

`timescale 1ns/1ps
`default_nettype none

module tb_lfsr_faults;
    reg clk = 0;
    reg rst_n = 0;
    reg enable = 0;
    wire [32:0] pass;
    wire [7*33-1:0] segment;

    always #19.861 clk = ~clk;

    generate
        genvar index;
        for (index = 0; index < 33; index = index + 1) begin : scenarios
            bist_diagnostic diag (
                .clk(clk), .rst_n(rst_n), .bist_en(enable), .frame_pulse(1'b0),
                .visibility_error(1'b0),
                .seven_seg_out(segment[index*7+:7]), .bist_pass_led(pass[index])
            );
            if (index < 16) begin : stuck_at_zero
                initial force diag.lfsr[index] = 1'b0;
            end else if (index < 32) begin : stuck_at_one
                initial force diag.lfsr[index-16] = 1'b1;
            end
        end
    endgenerate

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        enable = 1;
        repeat (1024) @(negedge clk);
        if (pass !== 33'd0)
            $fatal(1, "Diagnostic PASS before the 1024-shift stress completed");
        repeat (3) @(negedge clk);
        if (pass[32] !== 1'b1 || segment[32*7+:7] !== 7'b1110011)
            $fatal(1, "Fault-free self-check failed");
        if (pass[31:0] !== 32'd0)
            $fatal(1, "An injected LFSR register fault aliased to PASS: %08h", pass[31:0]);
        $display("PASS fault-free control and 32/32 persistent LFSR state bit stuck-at cases");
        $finish;
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_geometry_equivalence;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [9:0] x = 10'd0, y = 10'd0;
    reg edge_on = 1'b0;
    reg cube = 1'b0;
    wire active_in = (x < 640) && (y < 480);
    wire [3:0] active, hit;
    wire [23:0] normal_biased, normal_unbiased, normal_separate, normal_direct;
    integer scene, px, py, hits, samples = 0;

    sphere_tracer_pipeline_biased baseline (
        .clk(clk), .rst_n(rst_n), .pixel_x(x), .pixel_y(y), .video_active(active_in),
        .geom_sel(cube), .torus_edge_on(edge_on), .pipeline_active(active[0]), .hit_out(hit[0]),
        .hit_px(normal_biased[23:16]), .hit_py(normal_biased[15:8]), .hit_pz(normal_biased[7:0])
    );
    sphere_tracer_pipeline_unbiased shared_unbiased (
        .clk(clk), .rst_n(rst_n), .pixel_x(x), .pixel_y(y), .video_active(active_in),
        .geom_sel(cube), .torus_edge_on(edge_on), .pipeline_active(active[1]), .hit_out(hit[1]),
        .hit_px(normal_unbiased[23:16]), .hit_py(normal_unbiased[15:8]), .hit_pz(normal_unbiased[7:0])
    );
    sphere_tracer_pipeline_separate separate_accumulators (
        .clk(clk), .rst_n(rst_n), .pixel_x(x), .pixel_y(y), .video_active(active_in),
        .geom_sel(cube), .torus_edge_on(edge_on), .pipeline_active(active[2]), .hit_out(hit[2]),
        .hit_px(normal_separate[23:16]), .hit_py(normal_separate[15:8]), .hit_pz(normal_separate[7:0])
    );
    sphere_tracer_pipeline_direct direct_squares (
        .clk(clk), .rst_n(rst_n), .pixel_x(x), .pixel_y(y), .video_active(active_in),
        .geom_sel(cube), .torus_edge_on(edge_on), .pipeline_active(active[3]), .hit_out(hit[3]),
        .hit_px(normal_direct[23:16]), .hit_py(normal_direct[15:8]), .hit_pz(normal_direct[7:0])
    );

    always #5 clk = ~clk;

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        for (scene = 0; scene < 4; scene = scene + 1) begin
            cube = scene[1];
            edge_on = scene[0];
            hits = 0;
            for (py = 0; py < 525; py = py + 1) begin
                for (px = 0; px < 800; px = px + 1) begin
                    x = px;
                    y = py;
                    @(negedge clk);
                    if (active !== {4{active[0]}} || hit !== {4{hit[0]}} ||
                        (^active) === 1'bx || (^hit) === 1'bx)
                        $fatal(1, "Geometry validity or hit differed in scene %0d at sample %0d,%0d", scene, px, py);
                    if (hit[0]) begin
                        if (normal_biased !== normal_unbiased || normal_biased !== normal_separate ||
                            normal_biased !== normal_direct ||
                            (^normal_biased) === 1'bx)
                            $fatal(1, "Hit normals differed in scene %0d at sample %0d,%0d", scene, px, py);
                        hits = hits + 1;
                    end
                    samples = samples + 1;
                end
            end
            if (hits != (cube ? 12415 : (edge_on ? 14503 : 32968)))
                $fatal(1, "Unexpected object coverage %0d in scene %0d", hits, scene);
            $display("Scene %0d, cube=%0b edge_on=%0b: %0d matching hits and normal vectors", scene, cube, edge_on, hits);
        end
        $display("PASS all %0d cycle-aligned geometry samples", samples);
        $finish;
    end
endmodule
`default_nettype wire

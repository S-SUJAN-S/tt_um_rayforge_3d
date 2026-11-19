# Architecture

RayForge-X generates the scene directly in raster order. It has one pixel clock domain. From the beam coordinate to RGB, one register classifies the pixel, one selects the geometry and shading vector, and one registers the palette output. The ground compositor has an alignment register so the object, floor and sky refer to the same coordinate. The timing generator aligns the sync pins with RGB.

| Source | Role |
| --- | --- |
| [`tt_um_rayforge_3d.v`](../src/tt_um_rayforge_3d.v) | Tiny Tapeout wrapper, reset and switch synchronizers, scene qualification, pipeline alignment, independent visibility reference and pin mapping |
| [`vga_timing_gen.v`](../src/vga_timing_gen.v) | Raster counters, active region, aligned sync and frame tick |
| [`sphere_tracer_pipeline.v`](../src/sphere_tracer_pipeline.v) | Two-stage torus, programmable disk and capsule, and cube scan converter |
| [`perspective_ground.v`](../src/perspective_ground.v) | Progressive checker rows, checkerboard phase and screen-space shadow |
| [`phong_shading.v`](../src/phong_shading.v) | Shift-add light dot product, object palette and background compositor |
| [`bist_diagnostic.v`](../src/bist_diagnostic.v) | Signature capture, independent timer, PASS and seven-segment status |
| [`config.json`](../src/config.json) | 39.72 ns timing constraint and one-tile placement, routing and repair settings |

## VGA timing

| Axis | Active | Front porch | Low sync pulse | Back porch | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Horizontal, clocks | 640 | 16 | 96 | 48 | 800 |
| Vertical, lines | 480 | 10 | 2 | 33 | 525 |

The output runs at 25.175 million raster samples and 18.414 million active pixels per second. At the pins, sync is low on horizontal clocks 656–751 and lines 490–491. RGB is zero outside active video. Each of the three color channels maps to two Tiny VGA PMOD pins.

## Torus and cube

The torus is a radius-35 tube around a circle of radius 75. The screen-space center is `(320,190)`. Projection of the tube onto the image plane expands the projected centerline by a radius-35 disk. If `x` and `y` are centered integer pixel coordinates, face-on and edge-on visibility are

```text
face-on   1600 ≤ x² + y² ≤ 12100
edge-on   max(|x| − 75, 0)² + y² ≤ 1225
```

The implementation adds 10,875 to the edge-on quantity. Both poses can then use thresholds 1,600 and 12,100. The biased capsule always clears the lower threshold. A 15-bit accumulator uses `(d+1)²−d² = 2d+1` to step horizontal and vertical terms. In the middle of the edge-on capsule, the horizontal term stays at zero. A reflected six-bit addition generates signed cap steps. The scan window and symmetric end points keep the state and scanline restart bounded.

The cube uses fixed integer comparisons for the top diamond and two sides. These intervals give one of three fixed normal vectors. The torus classifiers generate pose-aware quantized normals from screen-coordinate bands and the radius state. The depth view displays a proxy derived from the same shading vector.

The programmable mode loads a radius-dependent seed into the same accumulator. A shape bit selects a disk or a capsule and the radius code sets the exact coverage bound. [Geometry command and derivation](programmable-geometry.md)

## Lighting and ground

The light uses a fixed positive vertical component and eight signed horizontal/depth directions. Opposite directions share the same arithmetic. A six-bit signed dot product selects one of seven object colors. The lit palette uses distinct RGB codes from the sky, floor and shadow. The normal, depth and silhouette modes use alternate object colors with the same background.

The checkerboard becomes visible at row 254. A shared row decoder selects horizontal pitch, line phase and vertical parity. The complete checker rows grow from 12 to 40 scanlines toward the foreground. Shadow width changes in screen-space row bands, with an X offset selected by the light angle. The resulting shadow is a screen-space effect.

## Controls and diagnostic

Reset or deselection asserts an internal reset asynchronously. Two flip-flops synchronize release to the pixel clock. The seven scene bits pass through two synchronizer stages. The renderer commits a word at vertical blank only after it stays stable across a complete interval between blanking samples. A transient excursion between samples invalidates the interval.

The diagnostic request uses a separate two-stage synchronizer and a 32-cycle qualifier. The observer compares actual pre-pad RGB visibility with an independently decoded beam reference, adjusted for renderer latency. It compacts 1,024 mismatch bits into a 16-bit signature. A 10-bit recurrence times the capture independently of the signature and parks after completion. The expected signature is `0x0CB8`. A healthy request produces a steady `P` and PASS output. The sampled window and the black-versus-nonblack observation define the coverage. [Pin controls](info.md) · [Verification scope](verification.md)

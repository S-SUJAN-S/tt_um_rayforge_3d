# RayForge-X: Exact Parametric Silhouettes on a Single-Tile VGA ASIC

Sujan S, Tejasvi R Shankar, Yogesh Mahesh Bisnal, and Prathik P Kekare

Revision 17 November 2026. The routing measurements in this draft describe the earlier programmable RTL before the checkerboard and palette update. The current source and its separate synthesis result are documented in [Verification](verification.md).

## Abstract

RayForge-X is a Sky130HD design that emits a 640×480 VGA image from integer beam coordinates at one sample per 25.175 MHz clock. A single 15-bit squared-distance accumulator and two fixed coverage comparisons serve two orthographic torus projections and two runtime-selectable shape families with 16 radii each. A mode-dependent additive offset moves every curved visibility test into a common fixed interval. Finite differences maintain the resulting squared distance across consecutive pixels and scanlines. The programmable candidate mapped to 11,462.2432 µm² and passed local routing and Tiny Tapeout precheck in a 1×1 TTSKY26e tile. An independent coverage oracle passed all 32 programmable masks in two RTL simulators. In a separate, controlled Yosys/ABC mapping experiment, the shared threshold design used 101.3472 µm² less cell area than the same-function design with raw squared distances and separate coverage comparisons.

## 1. Contribution and related work

Incremental evaluation of conics and linear edge functions has a long history. Dedicated VGA hardware already demonstrates torus rendering, framebufferless procedural video, and triangles with user-specified vertices. The contribution here is a particular finite-difference datapath that handles an annulus and multiple disk/capsule predicates with the same 15-bit register and fixed visibility interval. The area comparison tests the value of that transformation while holding the pixel contract and surrounding chip fixed. [Pitteway’s conic plotting](https://doi.org/10.1093/comjnl/10.3.282) · [Bresenham’s circle algorithm](https://doi.org/10.1145/359423.359432) · [VGA Donut](https://tinytapeout.com/chips/tt08/tt_um_a1k0n_vgadonut) · [Warp](https://tinytapeout.com/chips/tt08/tt_um_silice) · [Hardware Triangle Rasterizer](https://tinytapeout.com/chips/ttsky26b/tt_um_pzhu2)

Bouarah and de Dinechin compare fixed-point norm architectures under a common faithful-rounding requirement. We compare binary coverage for an identical raster instead of measuring numerical error of a full norm. The Columbia 2026 prototype evaluates linear edge functions incrementally and writes covered pixels to a buffered FPGA display. Its CPU and memory interfaces serve a general triangle workload. Unterguggenberger et al. study quality and adaptive sampling for general parametric geometry on GPUs. We fix the sampling rule to one integer center per pixel and test every supported input code. [ARITH 2025](https://arith2025.org/proceedings/215900a029.pdf) · [Columbia 2026 course report](https://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/reports/3D-Hardware-Rasterizer-report.pdf) · [IEEE TVCG 2026](https://www.cg.tuwien.ac.at/research/publications/2026/UNTERGUGGENBERGER-2026-ALOD/)

Sphere Carving uses a conservative SDF oracle to build tight bounds. Points as Tori fits local tori to oriented points and combines their signed distances. SDFRaster differentiably rasterizes a tetrahedral SDF for mesh reconstruction. These studies address different geometry inputs, outputs, and metrics. RayForge-X reports exact silhouette membership in its specified projection modes and evaluates shading separately. [Sphere Carving](https://aparis69.github.io/SphereCarving/index.html) · [Points as Tori](https://nzfeng.github.io/research/PointsAsTori/) · [SDFRaster](https://ustc3dv.github.io/SDFRaster/)

## 2. Coverage and finite differences

Use integer pixel centers and coordinates `x = pixel_x - 320` and `y = pixel_y - 190`. A ring torus with major radius `R = 75` and minor radius `r = 35` projects face-on to the annulus

```text
1600 = (R - r)^2 <= x^2 + y^2 <= (R + r)^2 = 12100.
```

The edge-on projection is the Minkowski sum of the line segment `[-R,R]` and a disk of radius `r`. Its squared distance function is `D = max(|x| - R, 0)^2 + y^2`. It covers a pixel iff `D <= r^2 = 1225`. Setting `A = D + 10875` expresses that result as `1600 <= A <= 12100`. In general, for a ring torus `R > r > 0`, the added bias `(R+r)^2 - r^2` exceeds the lower annulus threshold by `r(4R-r)`.

In the programmable disk or capsule, the user selects `k` in `[0,15]`, with `r² = 256 + 128k`. Use `D = x² + y²` for the disk and `D = max(|x| - 64,0)² + y²` for the capsule. The bias `12100 - r²` is at least 9924, so the same lower comparison always passes. The upper comparison accepts iff `D <= r²`. These comparisons include boundary pixels. The center and capsule length are fixed.

An integer coordinate `u` contributes `2u + 1` to the state when it advances by one. On a capsule's center segment the X term stays zero. Each scanline uses symmetric X endpoints, so the X term at the end of the row equals the next row's initial X term. At line wrap the same adder advances the Y square. The accumulator starts each active geometry region at its known squared distance plus bias. The programmable seed is `28040 - 128k`, implemented as `(219 - k) * 128 + 8` by concatenation. The scan bounds contain every contributing pixel. Across the evaluated windows `|y| <= 110`, and the maximum state is 28484 for the annulus, 25784 for the edge-on torus, and 28040 for the programmable profiles. The final Y advance to the unused row adds 221 at most. These bounds fit in 15 unsigned bits, including intermediate states retained between updates. [Architecture](architecture.md) · [Control inputs and proof of the seed](programmable-geometry.md)

## 3. Architecture and experimental controls

The VGA beam generates coordinates, blanking and synchronization. The geometry block registers coverage data then selects the quantized normal or face data. The rendering path composites shading and background and aligns RGB with synchronization. A frame-qualified input word selects the mode. The visible raster has 307,200 pixels per frame, and the full timing raster has 420,000 clocks per frame. At 25.175 MHz the actual frame rate is 59.9405 Hz. The implementation synthesizes silhouettes directly and supplies quantized shading for the fixed torus and cube. The programmable profiles use a solid silhouette.

The comparison generates a second implementation from the same RTL. It seeds a raw squared distance and selects among an annulus interval, the fixed capsule threshold, and the radius input threshold. It preserves the scan update, state width, pipeline, pinout, synchronizers, shading qualification, VGA timing and diagnostic circuitry. The SAT harness takes the actual seed, update, and classification expressions from both implementations. The miter checks that the fixed bias relation holds after every update and that all three geometry/shading classification bits agree for any encoded state that fits the 15-bit register. The scan bounds above show that the actual state always fits. [Ablation and proof procedure](../research/README.md)

## 4. Results

| Question | Result | Scope |
| --- | --- | --- |
| Does input data change the geometry correctly? | 32/32 input combinations passed in Icarus and Verilator, 13,440,000 VGA samples per run, plus frame-qualification checks. Zero silhouette mismatches give IoU 1 for the evaluated programmable masks. | Candidate RTL sampled on VGA pins. |
| Does the candidate meet the project area limit? | 11,462.2432 µm², 37.7568 µm² below the 11,500 µm² gate. | Pinned LibreLane 3.0.14 local flow, 1×1 Sky130HD. |
| What does shared threshold encoding save? | 11,542.3200 versus 11,643.6672 µm², a 101.3472 µm² (0.87%) reduction relative to separate comparisons. | Standalone Yosys 0.66 and ABC. Both variants mapped against the same Sky130HD typical-corner Liberty. Absolute area is specific to this mapping experiment. |
| Does the pinned candidate close physically? | Reported minimum setup +27.5560 ns and hold +0.0975 ns, zero slew, fanout, capacitance, DRC, LVS and antenna violations. Local precheck passed. | Extracted routed candidate across nine corners. |
| How much routed VGA coverage has been compared? | Six independently captured profile frames match RTL across 2,520,000 samples. Both routed Cocotb suites passed four tests each. | Functional routed netlist. |
| Does the programmable extension preserve the original scenes? | Seven routed legacy rasters matched 2,940,000 bytes from the earlier RTL. Seven further routed rasters passed the original torus pose sequence. One pose frame checks sync and blanking, and six also check exact silhouettes. | Functional routed netlist. |
| Does the netlist preserve the RTL behavior in the digital model? | All 217 matched points passed equivalence. A separate bounded proof passed at the output pins for 13 cycles after a three-cycle reset. | Zero-delay functional model, with the Yosys asynchronous-reset abstraction. |
| What happens when a new shape command replaces an original scene, or the other way around? | Seven mixed-scene frames and six full retained frames pass the independent shape and VGA checks. | RTL and routed pin-level sequence, 5,460,000 samples per run. |

The published fixed-geometry revision occupies 11,363.3984 µm² in the pinned flow. The 98.8448 µm² increment to the programmable candidate measures the entire change in feature set. The standalone ablation above measures threshold encoding with the same feature set. The candidate’s earlier energy baseline belongs to the fixed-geometry revision and has its own workload and activity assumptions. [Candidate evidence](programmable-geometry.md) · [Fixed revision energy and experimental limits](research.md)

## 5. Limits

The exactness claim applies to integer pixel-center coverage for the specified circles and segments, plus the two orthographic views of the fixed torus. The projected cube is independently defined. The visuals use discrete colors without multisampling. User inputs select shape and radius, with fixed position and capsule length. This evaluation contains two synthesis flows and a local routed candidate, with no candidate silicon measurements. The related work supports a contribution framed around the shared datapath and its measured cost.

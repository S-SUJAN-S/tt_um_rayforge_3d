# Research evidence

RayForge-X evaluates two fixed orthographic torus projections using a shared finite-difference datapath. For integer radii `R > r > 0`, the face-on mask has bounds `L=(R−r)²` and `U=(R+r)²`. The edge-on mask uses a squared distance to the projected centerline segment with bound `r²`. Adding the constant `B=U−r²` lets both masks use `L` and `U`. The biased quantity automatically clears the lower threshold because `B−L=r(4R−r)>0`. The chip realizes `R=75` and `r=35`. [Architecture derivation](architecture.md)

## Same-output synthesis comparison

The four full-chip measurements hold the downstream renderer, diagnostic, clock and pinned synthesis flow constant. The baselines retain the exact two masks and the same geometry latency.

| Geometry implementation | Mapped area | Margin to 11,500 µm² |
| --- | ---: | ---: |
| Direct exact squares | 13,663.1040 µm² | −2,163.1040 µm² |
| Separate finite-difference accumulators | 12,345.5904 µm² | −845.5904 µm² |
| Shared accumulator, separate threshold tests | 11,412.1952 µm² | +87.8048 µm² |
| Shared accumulator, biased thresholds | 11,363.3984 µm² | +136.6016 µm² |

Sharing saves 933.3952 µm² before biasing. Sharing the threshold tests saves a further 48.7968 µm². These are flattened full-chip synthesis results in LibreLane 3.0.14 with Sky130HD and PDK revision `8afc8346a57fe1ab7934ba5a6056ea8b43078e71`. The four implementations matched at 1,680,000 cycle-aligned geometry samples, including all hit vectors. Each alternative also passed the same seven-frame pose test. [Comparison sources and replay](../research/README.md)

## Shading accuracy

The integer masks match the analytic reference exactly at both tested viewpoints. Lighting uses quantized normal proxies. At 14,503 visible edge-on pixels, the new classifier reduces mean angular error from 32.186° to 15.377°. Across eight light directions and 116,024 pixel/light samples, mean error against the analytic normal passed through the same seven-level palette falls from 1.1194 to 0.7012 palette steps at reference gain 7. Mean palette error also improves at gains 6 and 8. The face-on rendering is identical. [Matched routed VGA frames](images/edge-lighting.png)

## Physical and diagnostic evidence

The pinned local biased design fits the 161.000 × 111.520 µm tile. Its configuration targets a maximum fanout of nine. Worst extracted setup and hold slack are +27.6625 ns and +0.0620 ns. The nine extracted corners report zero setup, hold, slew, capacitance and fanout violations. Detailed-route and Magic DRC, LVS and antenna counts are zero. Tiny Tapeout precheck passed 15 of 15 in the local replay. The hosted Actions artifacts identify the GDS for the Git revision selected for fabrication. [Verification procedure](verification.md)

The nominal post-route macro estimate is 0.47152 mW for a static face-on torus with fully annotated gate activity at 1.80 V and 25 °C. This is 25.61 pJ per active pixel, using the active-pixel rate of the complete VGA raster. The corresponding diagnostic estimate over 1,060 clocks is 21.69 nJ. These are model-based estimates ahead of pads, board and DAC. Digital reset-phase and timing checks characterize the implemented synchronizers. Measured silicon power and analog metastability behavior are beyond these experiments.

The exact routed fault campaign activated 152 persistent stuck-at cases at 76 named renderer register outputs. External VGA comparisons detected all 152 across lit, normal and depth workloads. The on-chip pre-pad visibility diagnostic detected 12 in the sampled windows. Coverage applies to those locations, workloads and observer.

## Related work

- Andy Sloane’s fabricated VGA donut uses multiplierless CORDIC sphere tracing. Pauline Zhu’s hardware triangle rasterizer uses incremental edge equations. These are direct shuttle precedents for procedural VGA and incremental scan conversion. [VGA Donut](https://tinytapeout.com/chips/tt08/tt_um_a1k0n_vgadonut) · [Hardware Triangle Rasterizer](https://tinytapeout.com/chips/ttsky26b/tt_um_pzhu2)
- Bouarah and de Dinechin compare fixed-point hardware norm implementations. Their evaluation motivates explicit arithmetic contracts and controlled cost comparisons. [IEEE ARITH 2025](https://arith2025.org/proceedings/215900a029.pdf)
- Schott et al. use conservative enclosing volumes to accelerate signed-distance queries. Feng et al. fit local tori to point clouds for approximate signed-distance evaluation. Cui et al. rasterize tetrahedral distance fields for mesh reconstruction. These works use different input, geometry and execution contracts. [Sphere Carving, ACM TOG 2025](https://aparis69.github.io/SphereCarving/index.html) · [Points as Tori, ACM TOG 2026](https://doi.org/10.1145/3811385) · [SDFRaster, SIGGRAPH 2026](https://ustc3dv.github.io/SDFRaster/)

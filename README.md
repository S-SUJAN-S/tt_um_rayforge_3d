# RayForge-X

RayForge-X is a single-tile VGA graphics ASIC for Tiny Tapeout TTSKY26e. It draws a face-on or edge-on torus, a projected cube, or a disk or capsule whose size comes from a user input word. It generates every pixel as the VGA beam advances, using one 25.175 MHz clock and no framebuffer or external memory. [Programmable geometry and example input words](docs/programmable-geometry.md)

![Before-and-after VGA crops showing the checkerboard and palette fixes](docs/images/visual-cleanup.png)

[Open the interactive VGA demo](docs/demo.html) · [Browse the updated scene gallery](docs/images/visual-gallery.png)

The demo is a self-contained HTML file. Download it and open it in your browser to inspect the 40 captured rasters.

## What the chip does

| Feature | Implementation |
| --- | --- |
| Video | 640×480 visible pixels, 800×525 total raster, 59.94 Hz at 25.175 MHz |
| Throughput | One sample per clock through three registered rendering stages |
| Torus | Exact integer annulus face-on and exact integer capsule edge-on, using the same 15-bit recurrence |
| User geometry | Disk or capsule with an input-defined squared radius, 16 values per family |
| Other geometry | Projected cube with three fixed face normals |
| Display | Six-bit RGB on the Tiny VGA PMOD, with lit, normal, depth-proxy and silhouette views |
| Controls | Four manual light directions or eight animated directions. Scene updates qualify during vertical blank. |
| Diagnostic | 1,024-sample pre-pad RGB visibility check with a seven-segment status and PASS output |
| Physical target | Sky130HD, 1×1 tile, 161.000 × 111.520 µm |

“Exact” applies to the torus, disk, and capsule silhouettes at integer pixel centers. Lighting uses quantized normals and a fixed palette. The light can orbit automatically while the torus has two switch-selected poses.

## Run it

For hardware, connect a Tiny VGA PMOD, supply a 25.175 MHz clock, select the design and release reset. With all scene switches low, the first scene is the lit face-on torus. [Pinout and bring-up](docs/info.md)

For simulation, install Icarus Verilog, GNU Make and Python, then run these commands from the repository root.

```sh
python -m pip install -r test/requirements.txt
make -C test
bash test/run-rtl.sh
```

The standalone suite generates VGA frame captures under `test/sim_build/standalone/`. [Test coverage and commands](docs/verification.md)

## Repository guide

| Path | Purpose |
| --- | --- |
| [`src/`](src) | Synthesizable RTL and the single-tile physical configuration |
| [`info.yaml`](info.yaml) | Tiny Tapeout source manifest, clock, tile size and pin labels |
| [`docs/info.md`](docs/info.md) | Shuttle datasheet with hardware setup and controls |
| [`docs/architecture.md`](docs/architecture.md) | Pipeline, VGA timing, geometry arithmetic and diagnostic contract |
| [`docs/research.md`](docs/research.md) | Prior art, same-output area comparison, lighting accuracy and limitations |
| [`docs/manuscript.md`](docs/manuscript.md) | Research manuscript for the programmable candidate, including the literature, coverage proof and results |
| [`research/`](research/README.md) | Reproducible Sky130HD comparator ablation and SAT equivalence check for the programmable geometry |
| [Fixed-geometry research archive](https://github.com/S-SUJAN-S/tt_um_rayforge_3d/tree/32cfd45/research) | Independent torus reference and geometry comparison RTL for the fixed-geometry revision |
| [`test/`](test) | Cocotb, full-frame hardware simulation and fault tests |
| [CI workflows](.github/workflows) | RTL regression and Tiny Tapeout GDS, precheck, gate simulation, datasheet and viewer builds |

The 1×1 Sky130HD design targets an **11,500 µm²** mapped area cap. The checkerboard and palette update mapped to **11,407.1904 µm²** in standalone synthesis. GitHub Actions reports the Tiny Tapeout build and precheck for each published commit. [Verification evidence](docs/verification.md) · [GitHub Actions](https://github.com/S-SUJAN-S/tt_um_rayforge_3d/actions)

## Credits & Course Affiliation

This project was executed by **Sujan S, Tejasvi R Shankar, Yogesh Mahesh Bisnal, and Prathik P Kekare** as an **Experiential Learning (EL)** project under the **VLSI Physical Design course (EC373TA)**.

[Apache 2.0 license](LICENSE)

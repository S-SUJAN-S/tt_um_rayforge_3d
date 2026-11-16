# RayForge-X

RayForge-X generates 640×480 VGA video from a 25.175 MHz pixel clock. The 800×525 raster runs at 59.9405 Hz. The design emits one pixel per clock with a three-register path from the raster coordinate to the VGA pins. It targets one 161.000 × 111.520 µm Sky130HD tile on Tiny Tapeout TTSKY26e.

## Renderer

- **Torus.** The face-on silhouette is the integer annulus `1600 <= (x−320)^2 + (y−190)^2 <= 12100`. At a 90° turn, the silhouette becomes the capsule `max(abs(x−320)−75, 0)^2 + (y−190)^2 <= 1225`. Both orthographic masks use the same finite-difference accumulator. Shading uses approximate normals in both views.
- **Cube.** Signed comparisons classify the projected top and two side faces. Each face has a fixed shading normal.
- **Ground.** Eight fixed scanline bands approximate horizontal perspective on the checkerboard. The line phase starts at `(-320*k) mod 2048`. A scanline width and light-dependent x offset generate the moving shadow.
- **Lighting.** Opposite pairs of the eight light directions share the same shift-add arithmetic and use opposite signs in the XZ plane. The fixed palette supports normal, depth and silhouette views. Auto-orbit moves the light and shadow. The streaming datapath needs no framebuffer or external memory.

## Controls

| Pins | Function |
| --- | --- |
| `ui_in[0]` | Enable automatic light orbit |
| `ui_in[1]` | 0 = torus, 1 = projected cube |
| `ui_in[2]` | Torus view, 0 = face-on, 1 = edge-on |
| `ui_in[4:3]` | 00 = lit palette, 01 = normal view, 10 = depth view, 11 = filled silhouette |
| `ui_in[6:5]` | Manual light angle when auto-orbit is off |
| `ui_in[7]` | Start LFSR diagnostic |
| `uo_out` | Tiny VGA PMOD pinout |
| `uio_out[6:0]` | Seven-segment status |
| `uio_out[7]` | Qualified LFSR pass |

Scene switches are synchronized into the pixel domain. A complete switch word is accepted at vertical blank after it stays unchanged for the full interval between two blanking starts. The default scene is a lit face-on torus. BIST accepts a separate request after 32 stable synchronized cycles. Over 1,024 cycles it compares pre-pad RGB visibility against the independently decoded beam position and compacts discrepancies into a signature. A signature of `16'h0CB8` lights the diagnostic LED and displays a steady `P`. Coverage depends on the pixels sampled during the diagnostic window.

## Verify and build

Run the repository Cocotb suite with Icarus Verilog and the versions in `test/requirements.txt`.

```sh
python3 -m pip install -r test/requirements.txt
cd test
make
```

From the repository root, run the standalone full-raster test. It also emits 640×480 PPMs.

```sh
iverilog -g2012 -s tb_rayforge_3d -o sim_rayforge test/tb_rayforge_3d.v src/*.v
vvp sim_rayforge
```

Run the independent pin checks for both torus views and the corrected BIST observer.

```sh
iverilog -g2012 -s tb_torus_pose -o sim_pose test/tb_torus_pose.v src/*.v
vvp sim_pose
iverilog -g2012 -s tb_pipe_active_faults -o sim_visibility test/tb_pipe_active_faults.v src/*.v
vvp sim_visibility +expected_reject=1
```

Use the commit's Tiny Tapeout Actions artifacts for mapped area, post-route timing and the GDS/shuttle status. Check the 11,500 µm² mapped-area ceiling and the extracted slew reports before selecting a revision. Record power with a specified activity profile, operating corner and power boundary.

## Authors

Sujan S, Tejasvi R Shankar, Yogesh Mahesh Bisnal, and Prathik P Kekare.

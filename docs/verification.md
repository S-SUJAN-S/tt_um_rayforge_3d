# Verification

From the repository root, install Icarus Verilog, GNU Make and the Python dependencies in [`test/requirements.txt`](../test/requirements.txt). Run the Cocotb smoke tests and the standalone RTL suite.

```sh
python -m pip install -r test/requirements.txt
make -C test
bash test/run-rtl.sh
```

## Test inventory

| Test | Evidence |
| --- | --- |
| [`test.py`](../test/test.py) and [`tb.v`](../test/tb.v) | Startup, output enables, HSYNC width, default active RGB and healthy BIST. The same suite runs on the RTL and the Tiny Tapeout routed model. |
| [`tb_torus_pose.v`](../test/rtl/tb_torus_pose.v) | Seven full rasters with sync, blanking, the exact 32,968-pixel annulus and 14,503-pixel capsule, and qualified pose transitions |
| [`tb_user_profiles.v`](../test/rtl/tb_user_profiles.v) | All 32 disk and capsule profiles, exact silhouettes, sync and blanking, plus mixed scene transitions and diagnostic entry |
| [`tb_rayforge_3d.v`](../test/rtl/tb_rayforge_3d.v) | Full-frame torus checks, scene switching, cube and torus PPM captures, and normal display selection |
| [`tb_shadow_profiles.v`](../test/rtl/tb_shadow_profiles.v) | Eleven shadow footprints across all eight light directions, radius-group growth, reset and raster blanking |
| [`tb_scene_stability.v`](../test/rtl/tb_scene_stability.v) | Rejects an excursion between matching blanking samples and accepts a stable cube request |
| [`tb_restart_phases.v`](../test/rtl/tb_restart_phases.v) | Pin behavior through 84 phased reset and enable releases |
| [`tb_renderer_visibility_bist.v`](../test/rtl/tb_renderer_visibility_bist.v) | 1,060-clock healthy PASS and injected active-black, blanking-leak and single-pixel faults |
| [`tb_pipe_active_faults.v`](../test/rtl/tb_pipe_active_faults.v) | Independently observes stuck-low renderer validity during active display and stuck-high validity in blanking |
| [`tb_lfsr_faults.v`](../test/rtl/tb_lfsr_faults.v) | Healthy signature and 32 isolated stuck-at faults in its 16 state bits |

The standalone runner puts logs and the two PPM captures in `test/sim_build/standalone/`. The [RTL workflow](../.github/workflows/test.yaml) runs both suites and uploads the logs, Cocotb results and waveform.

## Routed build and shuttle artifacts

The [GDS workflow](../.github/workflows/gds.yaml) builds the Sky130A macro using the `ttsky26e` flow. Its jobs also run Tiny Tapeout precheck, the routed Cocotb suite and the layout viewer. The [Docs workflow](../.github/workflows/docs.yaml) builds the shuttle datasheet from `info.yaml` and `docs/info.md`.

Placement and routing target seven loads per driver to allow room for antenna diodes. Extracted sign-off loads its own SDC and uses the nine-load limit. [Implementation constraints](../src/pnr.sdc) · [Sign-off constraints](../src/signoff.sdc) · [LibreLane timing closure](https://librelane.readthedocs.io/en/stable/usage/timing_closure/index.html)

Use the Actions run for the exact source commit. Check the mapped area against 11,500 µm², setup and hold, the 0.75 ns transition limit, the configured fanout limit, route DRC, LVS, antenna and precheck. Selecting that revision in the Tiny Tapeout portal is a separate fabrication step. [GitHub Actions](https://github.com/S-SUJAN-S/tt_um_rayforge_3d/actions) · [Tiny Tapeout submission guide](https://tinytapeout.com/guides/advanced-workshop/submit-your-design/)

## VGA captures

The [interactive demo](demo.html) contains 40 RTL VGA pin captures. Each capture covers the complete 800×525 raster and was checked for sync polarity and blanking before decoding to 640×480 display pixels. The demo covers eight fixed views and all 32 programmable disk and capsule profiles. The decoder uses the Tiny VGA pin mapping and the four digital levels 0, 85, 170 and 255. [Scene gallery](images/visual-gallery.png) · [All-profile pin oracle log](../evaluation/all-profiles-check.txt)

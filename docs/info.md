## How it works

RayForge-X generates 640×480 VGA at 59.94 Hz with a 25.175 MHz clock. It scans an 800×525 raster and emits one sample per clock. The two torus views use one finite-difference circuit for exact integer silhouettes. The cube uses signed comparator tests for the projected faces. Quantized lighting, an eight-band checkerboard and a screen-space shadow complete the scene.

The video outputs follow the Tiny VGA PMOD pinout. Each color uses two bits. HSYNC and VSYNC are active low. The bidirectional pins are all configured as outputs.

## Pin controls

| Pins | Function |
| --- | --- |
| `ui[0]` | Automatically advance the light through eight directions, once every four frames |
| `ui[1]` | 0 torus, 1 projected cube |
| `ui[2]` | Torus pose, 0 face-on, 1 edge-on |
| `ui[4:3]` | 00 lit palette, 01 normal colors, 10 depth proxy, 11 yellow silhouette |
| `ui[6:5]` | Manual light direction when orbit is off. Codes 00, 01, 10, 11 select directions 0, 2, 4, 6. |
| `ui[7]` | Visibility self-test request |
| `uo[7:0]` | HSYNC, B0, G0, R0, VSYNC, B1, G1, R1 |
| `uio[6:0]` | Seven-segment pattern in bit order g through a |
| `uio[7]` | Self-test PASS |

## How to test

1. Connect a Tiny VGA PMOD and supply a 25.175 MHz pixel clock. Select the design and assert then release reset while the clock runs.
2. Start with all scene inputs low. The display shows a lit face-on torus.
3. Change the pose, cube, lighting, or palette controls. Leave the whole scene word stable for up to two frames. The design applies the qualified word at vertical blank.
4. Hold `ui[7]` high to run the independent pre-pad RGB visibility check. A healthy diagnostic produces a steady `P` pattern and asserts `uio[7]` after 1,060 clocks in the testbench. Lower `ui[7]` to re-arm the test. The check observes black versus nonblack RGB during its finite window.

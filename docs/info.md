## How it works

RayForge-X generates 640×480 VGA with a 25.175 MHz clock and an 800×525 raster. It processes one pixel per clock. One incremental squared-radius circuit produces the torus's exact face-on annulus or edge-on capsule, and signed comparisons produce the isometric cube faces. A checkerboard, a moving screen-space shadow, and a shift-add lighting palette complete the scene.

Scene controls update at vertical blank after the synchronized switch word stays unchanged for the full interval between two blanking starts. The diagnostic derives expected visibility from the beam position and compares it with the black versus nonblack pre-pad RGB output. It checks the signature after 1,024 steps and shows a steady `P` and a lit LED on a match.

## How to test

1. Connect a Tiny VGA PMOD to `uo_out` and supply a 25.175 MHz pixel clock.
2. Apply and release reset while the clock is running. The default display is a lit torus.
3. Set `ui_in[0]` for light orbit, `ui_in[1]` for the cube, `ui_in[2]` for the edge-on torus view, `ui_in[4:3]` for the display palette, and `ui_in[6:5]` for the manual light angle. Give scene switches up to two frames to take effect.
4. Hold `ui_in[7]` high. The display shows the diagnostic result and `uio_out[7]` asserts when the golden LFSR signature matches.

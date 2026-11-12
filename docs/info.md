<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

RayForge-X is a dedicated single-cycle-throughput 3D Sphere Tracing and procedural Constructive Solid Geometry (CSG) raymarching ASIC processor. It autonomously generates standard 640x480 @ 60 Hz VESA VGA video directly from silicon at 25.175 MHz using only 14.2 mW of active power, requiring zero external RAM, zero CPU intervention, and zero DSP multipliers.

The hardware datapath consists of four pipelined stages:
1. **VGA Timing Generator (25.175 MHz):** Generates beam coordinates and VESA standard sync pulses (HSYNC, VSYNC) for 640x480 @ 60 Hz.
2. **Perspective Ground Plane Engine:** Employs a 15-bit sequential restoring divider running during the 160-cycle horizontal blanking (HBLANK) to evaluate reciprocal depth ($16384 / \Delta Y$) in 15 cycles. During active video, a non-tearing pixel accumulator generates mathematical perspective checkered tiles converging to the horizon vanishing line ($Y=230$) alongside real-time orbiting dynamic cast drop shadows.
3. **Systolic Sphere Tracer & AMPBM SDF Evaluator:** Unrolls spatial ray evaluation with an Alpha-Max-Plus-Beta-Min norm ($\alpha=1.0, \beta=0.375$) that bounds distance approximation error to $<3.96\%$ with pure shift-and-add logic.
4. **7-Level Metallic Phong Shading & Color Palette:** Computes real-time diffuse illumination ($N \cdot L$), specular white glints (`#FFFFFF`), atmospheric depth fog, and cosmic twilight gradients outputting 6-bit DAC RGB to standard Tiny VGA PMOD.
5. **Hardware BIST Coprocessor:** Autonomous 16-bit Galois LFSR validates the arithmetic datapath across 1,024 cycles against golden signature `16'h0CB8`, driving the onboard 7-segment display to cycle `"P-A-S-S"` and lighting a green status LED.

## How to test

1. Connect a standard Tiny VGA PMOD to `uo_out` pins.
2. Power on the board with a 25.175 MHz clock.
3. A 3D metallic torus hovering over an infinite receding perspective checkered floor with real-time drop shadows will immediately appear on the display.
4. **DIP Switch Controls (`ui_in`):**
   * `ui_in[0]`: Enable auto-orbit animation (1 = rotating object & orbiting light).
   * `ui_in[1]`: Geometry Select (0 = 3D Torus, 1 = 3D CSG Cube).
   * `ui_in[4:3]`: Shading Mode (00 = Phong, 01 = Normal Map, 10 = Depth Fog, 11 = Wireframe).
   * `ui_in[6:5]`: Manual orbital light angle (when auto-animation is disabled).
   * `ui_in[7]`: **BIST Hardware Self-Test** (activates internal LFSR diagnostic and displays `PASS` on 7-segment).

# Research reproduction

Run the independent mathematical model and the simulation comparison from the repository root.

```sh
python research/torus_reference.py
bash research/check_geometry.sh
```

The Python model checks the biased recurrence against direct integer masks over three 800×525 rasters. It also computes the angular error of the earlier and current normal classifiers against an analytic front-surface normal.

The Verilog comparison compiles the production geometry and three replacement modules side by side. It checks valid and hit signals on every cycle, shading vectors on all hits, and exact geometry populations. It then substitutes each alternative into the same top-level renderer and runs the full seven-frame VGA pose test.

| File | Experimental geometry |
| --- | --- |
| [`shared_unbiased.v`](geometry/shared_unbiased.v) | Shared recurrence with separate face-on and edge-on threshold tests |
| [`separate_accumulators.v`](geometry/separate_accumulators.v) | Independent 15-bit face-on and 12-bit edge-on accumulators |
| [`direct_squares.v`](geometry/direct_squares.v) | Direct radius and cap arithmetic with two squarers |

To repeat the area experiment, in a disposable checkout replace `src/sphere_tracer_pipeline.v` with one alternative at a time. The files export the same module interface. Keep all remaining sources, the 39.72 ns clock, PDK and flow version fixed and compare flattened mapped area from each synthesis report. [Pinned results](../docs/research.md) · [Tiny Tapeout local hardening](https://tinytapeout.com/guides/local-hardening/)

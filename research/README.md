# Comparator sharing experiment

Both designs accept the same scene words and run the same accumulator schedule at the same pipeline latency. The alternative uses raw squared distances and chooses from three coverage predicates. The candidate encodes each predicate in the same fixed interval by changing the accumulator seed. The surrounding synthesizable files are copied byte for byte.

From the project root, use Python 3 and Yosys with ABC. Pass the same Sky130HD typical-corner Liberty to both variants.

```sh
python research/make_unbiased_variant.py ../rayforge-unbiased
python research/prove_comparator_equivalence.py --unbiased ../rayforge-unbiased --work ../proof
python research/compare_mapped_area.py --unbiased ../rayforge-unbiased --work ../mapping --liberty /path/to/sky130-hd.lib
```

The SAT miter checks the initial seed, enabled increments, holds, and all three geometry/shading classification bits. Given a mode and an unencoded 15-bit distance, the miter adds the expected bias and feeds the two states to the two implementations. The one-step difference holds for every RTL input and 15-bit state under modular arithmetic. The classification check applies when the biased state fits without wrap, which is guaranteed by the scan bounds. A scene commits in vertical blank before the next scan reseeds. This proves the changed geometry logic under the same scan schedule. [Mathematical bounds](../docs/manuscript.md) · [SAT proof log](../evaluation/comparator-ablation-proof.txt)

The ablation also passed the independent Icarus pin oracle on all 32 input codes. This checks the full 800×525 raster for each case, including VGA sync and blanking, plus frame qualification and a healthy BIST request. [Ablation RTL replay](../evaluation/unbiased-profiles.txt)

| Standalone mapping | Standard-cell area |
| --- | ---: |
| Biased recurrence and fixed thresholds | 11,542.3200 µm² |
| Raw recurrence and separate thresholds | 11,643.6672 µm² |
| Savings from bias encoding | 101.3472 µm², 0.87% |

The table records the original programmable revision before the checkerboard and palette changes. The standalone experiment used Yosys 0.66 with ABC and the archived Sky130HD 25 °C, 1.80 V synthesis library. Its file hash is in the result. ABC used a delay target of 39,720 ps. The current source can reproduce the comparison using identical surrounding RTL for both variants. [Standalone mapping result](../evaluation/comparator-ablation-area.txt) · [Candidate physical and full-frame results](../docs/programmable-geometry.md)

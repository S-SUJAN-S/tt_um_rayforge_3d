# Programmable geometry

Set `ui[2:1]=11` to supply shape data. The type bit and radius code are sampled through the existing scene synchronizer and committed during vertical blank. The output is a yellow silhouette over the existing VGA background. Hold the scene word through a stable frame interval to commit the update.

| Input bits | Meaning in this mode |
| --- | --- |
| `ui[0]` | 0 disk, 1 capsule |
| `ui[6:3]` | Unsigned radius code `k` from 0 through 15 |
| `ui[7]` | Independent visibility diagnostic request |

| Input word | Visible result |
| --- | --- |
| `0x06` | Disk, radius 16 px |
| `0x3E` | Disk, radius about 33.94 px |
| `0x7E` | Disk, radius about 46.65 px |
| `0x07` | Capsule, radius 16 px |
| `0x3F` | Capsule, radius about 33.94 px |
| `0x7F` | Capsule, radius about 46.65 px |

The other three values of `ui[2:1]` select the original face-on torus, cube and edge-on torus. The programmable profiles have a fixed center at screen coordinate (320,190). The capsule's projected segment extends 64 pixels on either side of that center.

## Shared distance recurrence

The extension evaluates `D = x² + y²` for the disk and `D = max(|x| − 64, 0)² + y²` for the capsule. The user sets the upper distance limit `r² = 256 + 128k`. The circuit adds `B = 12100 − r²` to the accumulated distance. The smallest possible bias is 9,924, so the original lower threshold 1,600 is always satisfied. The upper comparison against 12,100 evaluates `D ≤ r²` for every code.

The disk walks screen columns 256 through 383. The capsule walks 192 through 447 and holds the horizontal term across its central segment. Both walks begin and end with the same horizontal squared distance `64²`. At the first candidate row, the accumulator seeds to `64² + 110² + B = 28040 − 128k`. Only the seed depends on the input radius. The same 15-bit state, signed difference adder and comparator pair render the fixed torus poses and both programmable families.

This mode synthesizes analytic silhouettes from a geometry word. The available inputs cover two shape families and 16 radius codes, with a constant center and capsule length. The floor uses a coarser screen-space footprint. Radius codes 0–3, 4–7, 8–11, and 12–15 select four increasing shadow sizes per family.

## Verify

Run `bash test/run-rtl.sh` to check all 32 input codes and mixed-scene transitions. [Captured programmable and original scenes](images/visual-gallery.png) · [Verification evidence](verification.md)

"""Independent integer and normal checks for both RayForge-X torus views."""

from math import acos, degrees, hypot, sqrt
from statistics import mean


R, r = 75, 35
LOWER, UPPER = (R - r) ** 2, (R + r) ** 2
EDGE_BIAS = UPPER - r ** 2


def signed_byte(value):
    return value - 256 if value & 128 else value


def cap_step(beam_x, edge):
    """Return the modeled RTL step coordinate and horizontal enable."""
    left = not (beam_x & 256)
    reflect = 63 if edge and not left else 0
    cap_sum = ((beam_x & 63) ^ reflect) + (11 if edge else 0)
    low = (cap_sum & 63) ^ reflect
    high = (3 if left else 0) if edge else ((beam_x - 320) >> 6) & 3
    outside_segment = cap_sum < 64 and (left or bool(beam_x & 128))
    return signed_byte((high << 6) | low), not edge or outside_segment


def raster_frames():
    accumulator = 0
    for edge in (True, False, True):
        hits = 0
        for beam_y in range(525):
            y = beam_y - 190
            radial_row = 80 <= beam_y <= 300
            for beam_x in range(800):
                x = beam_x - 320
                radial_column = 192 <= beam_x <= 447
                horizontal = max(abs(x) - R, 0) if edge else x
                squared = horizontal ** 2 + y ** 2
                expected_hit = squared <= r ** 2 if edge else LOWER <= squared <= UPPER
                actual_hit = radial_row and radial_column and LOWER <= accumulator <= UPPER
                assert expected_hit == actual_hit, (edge, beam_x, beam_y)
                if radial_row and radial_column:
                    expected_state = squared + (EDGE_BIAS if edge else 0)
                    assert accumulator == expected_state, (edge, beam_x, beam_y)
                hits += actual_hit

                if beam_x == 799 and beam_y == 79:
                    accumulator = 25784 if edge else 28484
                elif radial_row and beam_x == 799:
                    accumulator = (accumulator + 2 * y + 1) & 32767
                elif radial_row and radial_column:
                    step, enabled = cap_step(beam_x, edge)
                    if enabled:
                        accumulator = (accumulator + 2 * step + 1) & 32767
        assert hits == (14503 if edge else 32968)
        print("edge" if edge else "face", "hits", hits)


def torus_normal(x, y, edge):
    """Analytic front normal under the RTL screen-Y sign convention."""
    if edge:
        h = sqrt(r ** 2 - y ** 2)
        radius = R + h
        z_front = -sqrt(max(0, radius ** 2 - x ** 2))
        return h * x / (r * radius), -y / r, h * z_front / (r * radius)

    radius = hypot(x, y)
    t = (radius - R) / r
    return t * x / radius, -t * y / radius, -sqrt(max(0, 1 - t ** 2))


def normal_errors():
    models = (("face-on", False, False),
              ("edge-on, earlier classifier", True, False),
              ("edge-on, pose-aware classifier", True, True))
    for model, edge, pose_aware in models:
        errors = []
        for y in range(-110, 111):
            for x in range(-110, 111):
                horizontal = max(abs(x) - R, 0) if edge else x
                squared = horizontal ** 2 + y ** 2
                hit = squared <= r ** 2 if edge else LOWER <= squared <= UPPER
                if not hit:
                    continue
                state = squared + (EDGE_BIAS if edge else 0)
                depth_band = 2916 <= state <= 9216
                inner = state < 5625
                x_magnitude = abs(x + (x < 0))
                y_magnitude = abs(y + (y < 0))
                x_bin = x_magnitude >> 5
                y_bin = y_magnitude >> 5
                if pose_aware:
                    x_major = x_magnitude >= 64
                    y_major = y_magnitude >= 16
                    depth_band = not (x_major or y_major)
                else:
                    x_major = x_bin >= y_bin
                    y_major = y_bin >= x_bin
                major = 2 if depth_band else 3
                x_sign = -1 if (x < 0) ^ inner else 1
                y_sign = -1 if (y >= 0) ^ inner else 1
                proxy = (
                    x_sign * (major if x_major else 1),
                    y_sign * (major if y_major else 1),
                    -7 if depth_band else -2,
                )
                exact = torus_normal(x, y, edge)
                cosine = sum(a * b for a, b in zip(proxy, exact)) / hypot(*proxy)
                errors.append(degrees(acos(min(1, max(-1, cosine)))))

        errors.sort()
        assert len(errors) == (14503 if edge else 32968)
        p95 = errors[int(0.95 * (len(errors) - 1))]
        print(model, "normal error",
              f"mean={mean(errors):.6f} p95={p95:.6f} max={errors[-1]:.6f} degrees")


if __name__ == "__main__":
    raster_frames()
    normal_errors()

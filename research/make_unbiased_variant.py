"""Make a same-pin, same-latency comparator ablation of the RayForge-X RTL."""

import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]

REPLACEMENTS = (
    (
        """    // At the left boundary both user profiles have X distance -64:
    // the disk starts at x=256; the capsule starts at x=192 and its left
    // endpoint is x=256. Add a bias 12100 - (256 + 128*code) to the seed
    // so both profiles keep the original pair of threshold comparators.
    wire [7:0] profile_seed_hi = 8'd219 - {4'b0, profile_radius};
    wire [14:0] profile_seed = {profile_seed_hi, 7'd8};""",
        """    // Raw squared distance at the left boundary and first row.
    localparam [14:0] PROFILE_SEED = 15'd16196; // 64^2 + 110^2
    wire [4:0] profile_limit_hi = {1'b0, profile_radius} + 5'd2;
    wire [14:0] profile_limit = {3'b000, profile_limit_hi, 7'b0000000};""",
    ),
    (
        """            radius_sq <= profile_mode ? profile_seed :
                         (torus_edge_on ? 15'd25784 : 15'd28484);""",
        """            radius_sq <= profile_mode ? PROFILE_SEED :
                         (torus_edge_on ? 15'd14909 : 15'd28484);""",
    ),
    (
        """    wire torus_hit = radial_rows && radial_columns &&
                     (radius_sq >= 15'd1600) && (radius_sq <= 15'd12100);
    wire inner_wall = (radius_sq < 15'd5625);""",
        """    wire annulus_hit = (radius_sq >= 15'd1600) && (radius_sq <= 15'd12100);
    wire capsule_hit = radius_sq <= 15'd1225;
    wire profile_hit = radius_sq <= profile_limit;
    wire torus_hit = radial_rows && radial_columns &&
                     (profile_mode ? profile_hit : (torus_edge_on ? capsule_hit : annulus_hit));
    // The biased capsule and user profiles never selected the inner wall.
    wire inner_wall = !profile_mode && !torus_edge_on && (radius_sq < 15'd5625);""",
    ),
    (
        """    s1_tube_band   <= torus_edge_on ? !(edge_x_major || edge_y_major) :""",
        """    s1_tube_band   <= torus_edge_on ? !(edge_x_major || edge_y_major) :
                          profile_mode ? 1'b0 :""",
    ),
)


def build(destination):
    if destination.exists():
        raise FileExistsError(f"Choose a new output directory: {destination}")
    source = ROOT / "src" / "sphere_tracer_pipeline.v"
    variant = source.read_text(encoding="utf-8")
    for original, replacement in REPLACEMENTS:
        if variant.count(original) != 1:
            raise ValueError(f"Source changed around {original.splitlines()[0].strip()}")
        variant = variant.replace(original, replacement, 1)
    destination.mkdir(parents=True)
    shutil.copy2(ROOT / "info.yaml", destination)
    for subdir in ("src", "test"):
        shutil.copytree(ROOT / subdir, destination / subdir,
                        ignore=shutil.ignore_patterns("sim_build", "__pycache__"))
    (destination / source.relative_to(ROOT)).write_text(variant, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New directory for the synthesis experiment")
    build(parser.parse_args().output)

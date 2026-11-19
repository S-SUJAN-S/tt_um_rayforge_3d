"""Prove the real RTL's radius-state update and coverage controls against its ablation."""

import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GEOMETRY = Path("src/sphere_tracer_pipeline.v")
STATE_UPDATE = re.compile(
    r"    always @\(posedge clk\) begin\n"
    r"        if \(start_radial_rows\)\n"
    r"            radius_sq <= (.*?);\n"
    r"        else if \(radial_rows && \(step_x \|\| end_of_line\)\)\n"
    r"            radius_sq <= radius_sq \+ radial_delta;\n"
    r"    end",
    re.DOTALL,
)
TUBE_BAND = re.compile(r"s1_tube_band\s*<=\s*([^;]+);")


def unique(pattern, source):
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise ValueError(f"Expected one RTL block matching {pattern.pattern}")
    return matches[0]


def instrument(path, module):
    source = path.read_text(encoding="utf-8")
    update = unique(STATE_UPDATE, source)
    tube = unique(TUBE_BAND, source)
    for marker in ("    reg [14:0] radius_sq;", "module sphere_tracer_pipeline (", "endmodule"):
        if source.count(marker) != 1:
            raise ValueError(f"Expected one RTL marker {marker!r} in {path}")
    next_state = (
        f"assign proof_next = start_radial_rows ? ({update[1]}) :\n"
        "    (radial_rows && (step_x || end_of_line)) ? radius_sq + radial_delta : radius_sq;"
    )
    proof_flags = f"assign proof_flags = {{torus_hit, inner_wall, ({tube[1]})}};\n"
    source = source.replace(update[0], next_state, 1)
    source = source.replace("    reg [14:0] radius_sq;", "    wire [14:0] radius_sq = proof_state;", 1)
    source = source.replace("endmodule", proof_flags + "endmodule", 1)
    return source.replace(
        "module sphere_tracer_pipeline (",
        f"module {module} (\n"
        "    input wire [14:0] proof_state,\n"
        "    output wire [14:0] proof_next,\n"
        "    output wire [2:0] proof_flags,",
        1,
    )


MITER = """
module comparator_miter(
    input wire [9:0] x, y,
    input wire edge_on, profile,
    input wire [3:0] code,
    input wire [14:0] raw,
    output wire next_matches, flags_match
);
    wire [15:0] r2 = 16'd256 + {5'b0, code, 7'b0};
    wire [15:0] bias = profile ? 16'd12100 - r2 : edge_on ? 16'd10875 : 16'd0;
    wire [15:0] encoded = {1'b0, raw} + bias;
    wire [14:0] biased_next, unbiased_next;
    wire [2:0] biased_flags, unbiased_flags;

    biased b (.clk(1'b0), .rst_n(1'b1), .video_active(1'b1), .geom_sel(1'b0),
        .pixel_x(x), .pixel_y(y), .torus_edge_on(edge_on), .profile_mode(profile),
        .profile_radius(code), .proof_state(encoded[14:0]), .proof_next(biased_next),
        .proof_flags(biased_flags));
    unbiased u (.clk(1'b0), .rst_n(1'b1), .video_active(1'b1), .geom_sel(1'b0),
        .pixel_x(x), .pixel_y(y), .torus_edge_on(edge_on), .profile_mode(profile),
        .profile_radius(code), .proof_state(raw), .proof_next(unbiased_next),
        .proof_flags(unbiased_flags));

    wire [14:0] expected_next = unbiased_next + bias[14:0];
    assign next_matches = biased_next == expected_next;
    assign flags_match = encoded[15] || biased_flags == unbiased_flags;
endmodule
"""


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--unbiased", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    design = instrument(ROOT / GEOMETRY, "biased")
    design += instrument(args.unbiased.resolve() / GEOMETRY, "unbiased") + MITER
    (work / "comparator_miter.v").write_text(design, encoding="utf-8")
    yosys = str(Path(args.yosys).resolve()) if Path(args.yosys).exists() else args.yosys
    subprocess.run(
        [yosys, "-Q", "-p",
         "read_verilog comparator_miter.v; prep -top comparator_miter -flatten; "
         "sat -verify -prove next_matches 1 -prove flags_match 1 -show-inputs -show-outputs"],
        cwd=work, check=True,
    )

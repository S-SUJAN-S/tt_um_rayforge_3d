#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
geometry="$root/research/geometry"
work=$(mktemp -d)
trap 'rm -f -- "$work"/*.v "$work"/*.vvp; rmdir -- "$work"' EXIT

rename_module() {
    sed "s/^module sphere_tracer_pipeline (/module sphere_tracer_pipeline_$2 (/" "$1" > "$work/$2.v"
}

rename_module "$root/src/sphere_tracer_pipeline.v" biased
rename_module "$geometry/shared_unbiased.v" unbiased
rename_module "$geometry/separate_accumulators.v" separate
rename_module "$geometry/direct_squares.v" direct

iverilog -g2012 -s tb_geometry_equivalence -o "$work/compare.vvp" \
    "$geometry/tb_geometry_equivalence.v" "$work"/*.v
vvp "$work/compare.vvp"

sources=()
for source in "$root"/src/*.v; do
    if [[ $source != "$root/src/sphere_tracer_pipeline.v" ]]; then
        sources+=("$source")
    fi
done
for variant in shared_unbiased separate_accumulators direct_squares; do
    echo "Checking VGA pins for $variant"
    iverilog -g2012 -s tb_torus_pose -o "$work/pose.vvp" \
        "$root/test/rtl/tb_torus_pose.v" "$geometry/$variant.v" "${sources[@]}"
    vvp "$work/pose.vvp"
done

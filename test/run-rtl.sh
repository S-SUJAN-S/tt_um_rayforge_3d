#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build="$root/test/sim_build/standalone"
mkdir -p -- "$build"
cd -- "$build"

benches=(
    tb_lfsr_faults
    tb_renderer_visibility_bist
    tb_pipe_active_faults
    tb_restart_phases
    tb_scene_stability
    tb_torus_pose
    tb_rayforge_3d
    tb_user_profiles
)

for bench in "${benches[@]}"; do
    echo "Running $bench"
    args=()
    if [[ $bench == tb_pipe_active_faults ]]; then
        args+=(+expected_reject=1)
    fi
    iverilog -g2012 -s "$bench" -o "$bench.vvp" \
        "$root/test/rtl/$bench.v" "$root"/src/*.v
    vvp "$bench.vvp" "${args[@]}" | tee "$bench.log"
    if [[ $bench == tb_user_profiles ]]; then
        vvp "$bench.vvp" +mixed | tee "$bench-mixed.log"
    fi
done

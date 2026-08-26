#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIFT_BIN="${NIFT_BIN:-${1:-nift}}"
if command -v "$NIFT_BIN" >/dev/null 2>&1; then NIFT_BIN="$(command -v "$NIFT_BIN")"; fi
[[ -x "$NIFT_BIN" ]] || { echo "NIFT_BIN not found: $NIFT_BIN" >&2; exit 2; }

python3 "$ROOT/benchmarks/tracking_scaling_benchmark.py" --nift "$NIFT_BIN"
python3 "$ROOT/benchmarks/full_build_scaling_benchmark.py" --nift "$NIFT_BIN"
python3 "$ROOT/benchmarks/memory_10k_benchmark.py" --nift "$NIFT_BIN"
if [[ -f "$ROOT/benchmarks/performance_10k.py" ]]; then
  python3 "$ROOT/benchmarks/performance_10k.py" --nift "$NIFT_BIN"
fi

# CP18 part A: the roadmap CLI/build workload set (10k full/no-op/single-page/
# shared-dependency, many-directory, modified/hash/hybrid modes).
python3 "$ROOT/benchmarks/cp18_cli_build_workload.py" --nift "$NIFT_BIN"

# CP18 part B: raw render + repeated/server workload across C++, C ABI, Go,
# C#, Node, Python (needs NIFT_C_ABI / built harnesses).
if [[ -x "$ROOT/benchmarks/embed/run_cp18_embed.sh" ]]; then
  NIFT_C_ABI="${NIFT_C_ABI:-$(dirname "$NIFT_BIN")/libnift_c.so}" "$ROOT/benchmarks/embed/run_cp18_embed.sh" 2>/dev/null ||     echo "CP18 part B skipped (embed bindings not built; set NIFT_C_ABI)"
fi

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

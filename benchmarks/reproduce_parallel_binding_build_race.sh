#!/usr/bin/env bash
# Stress/regression reproducer for the PARALLEL-BINDING-BUILD RACE discovered
# during the anomaly investigation. This is NOT a historical-sequence reproducer
# (the three historical events used SEQUENTIAL builds; see
# reproduce_historical_sequential.sh). Here the main make and the python/node
# build.sh run CONCURRENTLY, racing on the (now-fixed) intermediate object
# paths. With the per-invocation-temp-dir + atomic-publication build.sh fix this
# is expected to always pass; a failure here means the build race has regressed.
#
# Each trial:
#   STATE A (cold artifacts)
#   -> PARALLEL build (main make | cpp | go | rust | cs | node | python)
#   -> FIRST corpus run (exactly once)
#   -> durable diagnostics on any failure
#   -> return to STATE A
#
# Usage: reproduce_parallel_binding_build_race.sh [trials]
set -u
TRIALS="${1:-20}"
EMBED=/home/nick/Repositories/nift/nift-embed
SUITE=/home/nick/Repositories/nift/nift-embed-regression-suite
RUNS=/home/nick/Repositories/nift/nift-rs

clean_cold() {
  ( cd "$EMBED" && make clean >/dev/null 2>&1; rm -rf .build libnift_c.a libnift_c.so nift \
      bindings/go/embed-harness bindings/node/build bindings/python/build 2>/dev/null )
  ( cd "$EMBED/bindings/csharp" && find . -type d \( -name bin -o -name obj \) -exec rm -rf {} + 2>/dev/null )
  ( cd "$EMBED/bindings/python" && rm -f nift/_nift*.so 2>/dev/null; find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null )
  ( cd "$RUNS" && cargo clean >/dev/null 2>&1 )
  ( cd "$SUITE/benchmarks/embed" && rm -f cpp_bench cabi_bench 2>/dev/null )
}

heavy_build() {
  # Parallel build: this reproduces the binding-build race found during
  # investigation (concurrent writers to .build/pic). NOT the historical
  # sequence, which was sequential across these commands.
  ( cd "$EMBED" && make -j2 libnift_c.a libnift_c.so nift >/dev/null 2>&1 ) &
  B1=$!
  ( cd "$EMBED" && mkdir -p .build && g++ -std=c++17 -O2 -pthread -Isrc -Iinclude -Iminifypp/include -Iminifypp/src \
      tests/engine_harness.cpp src/Engine.cpp src/Context.cpp src/Value.cpp src/FileSystem.cpp \
      src/JsonFile.cpp src/JsonSchema.cpp src/Parser.cpp src/ProjectOwnership.cpp src/ProjectInfo.cpp \
      src/ProjectRead.cpp src/ProjectState.cpp src/WatchList.cpp src/BuildProgress.cpp \
      minifypp/src/Minify.cpp -o .build/engine-harness >/dev/null 2>&1 ) &
  B2=$!
  ( cd "$EMBED/bindings/go" && go build -o embed-harness ./cmd/embed-harness >/dev/null 2>&1 ) &
  B3=$!
  ( cd "$RUNS" && cargo build --example engine_harness >/dev/null 2>&1 ) &
  B4=$!
  ( cd "$EMBED/bindings/csharp/apps/NiftEmbedHarness" && dotnet build -v q --nologo >/dev/null 2>&1 ) &
  B5=$!
  ( cd "$EMBED/bindings/node" && bash build.sh >/dev/null 2>&1 ) &
  B6=$!
  ( cd "$EMBED/bindings/python" && bash build.sh >/dev/null 2>&1 ) &
  B7=$!
  wait $B1 $B2 $B3 $B4 $B5 $B6 $B7 2>/dev/null
}

run_perf_campaign() {
  # The full CP18 performance campaign: Part A workloads + Part B binding
  # benches (C++, C ABI, Go, C#, Node, Python) - exactly what preceded events
  # 2 and 3.
  timeout 1800 bash "$SUITE/run-performance.sh" "$EMBED/nift" >/dev/null 2>&1
}

run_corpus_once() {
  ( cd "$SUITE" && CPP_HARNESS="$EMBED/.build/engine-harness" \
      RUST_HARNESS="$RUNS/target/debug/examples/engine_harness" \
      NIFT_C_ABI="$EMBED/libnift_c.so" ./embed/run-embed.py > "$SUITE/embed/failures/trial-run.log" 2>&1 )
  local rc=$?
  if [ $rc -ne 0 ] || grep -q "^FAIL " "$SUITE/embed/failures/trial-run.log"; then
    echo "=== FAILURE CAPTURED (trial=$1, rc=$rc) ==="
    grep -A18 "^FAIL " "$SUITE/embed/failures/trial-run.log" | head -24
    echo "--- durable diagnostics ---"
    for f in "$SUITE/embed/failures/"*.json; do
      [ -f "$f" ] && { echo "== $f =="; head -50 "$f"; }
    done
    return 1
  fi
  return 0
}

rm -rf "$SUITE/embed/failures"
mkdir -p "$SUITE/embed/failures"
for t in $(seq 1 "$TRIALS"); do
  echo "TRIAL $t/$TRIALS: cold -> build -> perf campaign -> first corpus run"
  clean_cold
  heavy_build
  run_perf_campaign
  if ! run_corpus_once "$t"; then
    exit 1
  fi
  tail -1 "$SUITE/embed/failures/trial-run.log" | sed "s/^/  trial $t first-run: /"
done
echo "cold-transition campaign: $TRIALS complete cycles, no reproduction"

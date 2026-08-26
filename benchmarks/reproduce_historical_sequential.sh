#!/usr/bin/env bash
# Faithful reproduction of the THREE HISTORICAL 35/36 sequences (sequential
# builds). Reconstructed from the session:
#
#   event 1 (CP17 round-4): make -> cpp harness -> go -> rust -> cs -> node ->
#                          python -> FIRST corpus run  (no perf campaign)
#   event 2 (CP18):        make -> cpp -> go -> rust -> cs -> node -> python ->
#                          full CP18 perf campaign -> FIRST corpus run
#   event 3 (CP18 median): make -> cpp -> go -> rust ->
#                          full CP18 perf campaign -> FIRST corpus run
#
# Builds are SEQUENTIAL exactly as they were historically; the -j2 is internal
# to the single make. The first corpus invocation is the only observation.
#
# Usage: reproduce_historical_sequential.sh [perf|noperf] [trials]
set -u
PERF="${1:-perf}"
TRIALS="${2:-20}"
EMBED=/home/nick/Repositories/nift/nift-embed
SUITE=/home/nick/Repositories/nift/nift-embed-regression-suite
RUNS=/home/nick/Repositories/nift/nift-rs

clean_cold() {
  ( cd "$EMBED" && make clean >/dev/null 2>&1; rm -rf .build libnift_c.a libnift_c.so nift \
      bindings/go/embed-harness bindings/node/build bindings/python/build 2>/dev/null )
  ( cd "$EMBED/bindings/csharp" && find . -type d \( -name bin -o -name obj \) -exec rm -rf {} + 2>/dev/null )
  ( cd "$EMBED/bindings/python" && rm -f nift/_nift*.so 2>/dev/null; find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null )
  ( cd "$RUNS" && cargo clean >/dev/null 2>&1 )
}

sequential_build() {
  # Exact historical ORDER: one command at a time, no concurrency between them.
  ( cd "$EMBED" && make -j2 libnift_c.a libnift_c.so nift >/dev/null 2>&1 ) || return 1
  ( cd "$EMBED" && mkdir -p .build && g++ -std=c++17 -O2 -pthread -Isrc -Iinclude -Iminifypp/include -Iminifypp/src \
      tests/engine_harness.cpp src/Engine.cpp src/Context.cpp src/Value.cpp src/FileSystem.cpp \
      src/JsonFile.cpp src/JsonSchema.cpp src/Parser.cpp src/ProjectOwnership.cpp src/ProjectInfo.cpp \
      src/ProjectRead.cpp src/ProjectState.cpp src/WatchList.cpp src/BuildProgress.cpp \
      minifypp/src/Minify.cpp -o .build/engine-harness >/dev/null 2>&1 ) || return 1
  ( cd "$EMBED/bindings/go" && go build -o embed-harness ./cmd/embed-harness >/dev/null 2>&1 ) || return 1
  ( cd "$RUNS" && cargo build --example engine_harness >/dev/null 2>&1 ) || return 1
  ( cd "$EMBED/bindings/csharp/apps/NiftEmbedHarness" && dotnet build -v q --nologo >/dev/null 2>&1 ) || return 1
  ( cd "$EMBED/bindings/node" && bash build.sh >/dev/null 2>&1 ) || return 1
  ( cd "$EMBED/bindings/python" && bash build.sh >/dev/null 2>&1 ) || return 1
  return 0
}

run_perf_campaign() {
  timeout 1800 bash "$SUITE/run-performance.sh" "$EMBED/nift" >/dev/null 2>&1
}

run_corpus_once() {
  ( cd "$SUITE" && CPP_HARNESS="$EMBED/.build/engine-harness" \
      RUST_HARNESS="$RUNS/target/debug/examples/engine_harness" \
      NIFT_C_ABI="$EMBED/libnift_c.so" ./embed/run-embed.py > "$SUITE/embed/failures/trial-run.log" 2>&1 )
  local rc=$?
  if [ $rc -ne 0 ] || grep -q "^FAIL " "$SUITE/embed/failures/trial-run.log"; then
    echo "=== FAILURE CAPTURED (trial=$1, rc=$rc, perf=$PERF) ==="
    grep -A18 "^FAIL " "$SUITE/embed/failures/trial-run.log" | head -24
    for f in "$SUITE/embed/failures/"*.json; do
      [ -f "$f" ] && { echo "== $f =="; head -60 "$f"; }
    done
    return 1
  fi
  return 0
}

rm -rf "$SUITE/embed/failures"
mkdir -p "$SUITE/embed/failures"
for t in $(seq 1 "$TRIALS"); do
  echo "TRIAL $t/$TRIALS ($PERF): cold -> SEQUENTIAL build -> [perf] -> first corpus run"
  clean_cold
  if ! sequential_build; then
    echo "build failed (trial $t)"; exit 2
  fi
  if [ "$PERF" = "perf" ]; then
    run_perf_campaign
  fi
  if ! run_corpus_once "$t"; then
    exit 1
  fi
  tail -1 "$SUITE/embed/failures/trial-run.log" | sed "s/^/  trial $t first-run: /"
done
echo "historical-sequential campaign ($PERF): $TRIALS complete cold cycles, no reproduction"

#!/usr/bin/env bash
# Hypothesis-driven reproduction: fresh heavy build -> immediately run the
# seven-adapter corpus ONCE, capturing everything. Variants vary the rebuild
# conditions. Stops on the first failure and prints the durable diagnostic.
#
# Usage: reproduce_corpus_anomaly.sh [serial|parallel|delay|memory|cpu] [iterations]
set -u
MODE="${1:-parallel}"
ITERS="${2:-15}"
EMBED="${NIFT_CANONICAL_DIR:-}"
[ -n "$EMBED" ] && [ -d "$EMBED" ] || { echo "EMBED (NIFT_CANONICAL_DIR) must point to a Nift checkout" >&2; exit 2; }
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELAY="${DELAY:-3}"

clean_all() {
  ( cd "$EMBED" && make clean >/dev/null 2>&1; rm -rf .build libnift_c.a libnift_c.so nift \
      bindings/go/embed-harness bindings/node/build bindings/python/build \
      bindings/csharp/apps/NiftEmbedHarness/bin bindings/csharp/apps/NiftEmbedHarness/obj 2>/dev/null )
  ( cd "$EMBED/bindings/python" && rm -f nift/_nift*.so; find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null )
  ( cd "$EMBED/bindings/csharp" && find . -name bin -o -name obj | xargs -r rm -rf 2>/dev/null )
  ( cd "$RUNS" && cargo clean >/dev/null 2>&1 )
}

heavy_build() {
  case "$MODE" in
    serial)
      ( cd "$EMBED" && make -j2 libnift_c.a libnift_c.so nift >/dev/null 2>&1 )
      ( cd "$EMBED" && mkdir -p .build && g++ -std=c++17 -O2 -pthread -Isrc -Iinclude -Iminifypp/include -Iminifypp/src \
          tests/engine_harness.cpp src/Engine.cpp src/Context.cpp src/Value.cpp src/FileSystem.cpp \
          src/JsonFile.cpp src/JsonSchema.cpp src/Parser.cpp src/ProjectOwnership.cpp src/ProjectInfo.cpp \
          src/ProjectRead.cpp src/ProjectState.cpp src/WatchList.cpp src/BuildProgress.cpp \
          minifypp/src/Minify.cpp -o .build/engine-harness >/dev/null 2>&1 )
      ( cd "$EMBED/bindings/go" && go build -o embed-harness ./cmd/embed-harness >/dev/null 2>&1 )
      ( cd "$RUNS" && cargo build --example engine_harness >/dev/null 2>&1 )
      ( cd "$EMBED/bindings/csharp/apps/NiftEmbedHarness" && dotnet build -v q --nologo >/dev/null 2>&1 )
      ( cd "$EMBED/bindings/node" && bash build.sh >/dev/null 2>&1 )
      ( cd "$EMBED/bindings/python" && bash build.sh >/dev/null 2>&1 )
      ;;
    parallel|delay|memory|cpu)
      ( cd "$EMBED" && make -j2 libnift_c.a libnift_c.so nift >/dev/null 2>&1 ) &
      P1=$!
      ( cd "$EMBED" && mkdir -p .build && g++ -std=c++17 -O2 -pthread -Isrc -Iinclude -Iminifypp/include -Iminifypp/src \
          tests/engine_harness.cpp src/Engine.cpp src/Context.cpp src/Value.cpp src/FileSystem.cpp \
          src/JsonFile.cpp src/JsonSchema.cpp src/Parser.cpp src/ProjectOwnership.cpp src/ProjectInfo.cpp \
          src/ProjectRead.cpp src/ProjectState.cpp src/WatchList.cpp src/BuildProgress.cpp \
          minifypp/src/Minify.cpp -o .build/engine-harness >/dev/null 2>&1 ) &
      P2=$!
      ( cd "$EMBED/bindings/go" && go build -o embed-harness ./cmd/embed-harness >/dev/null 2>&1 ) &
      P3=$!
      ( cd "$RUNS" && cargo build --example engine_harness >/dev/null 2>&1 ) &
      P4=$!
      ( cd "$EMBED/bindings/csharp/apps/NiftEmbedHarness" && dotnet build -v q --nologo >/dev/null 2>&1 ) &
      P5=$!
      ( cd "$EMBED/bindings/node" && bash build.sh >/dev/null 2>&1 ) &
      P6=$!
      ( cd "$EMBED/bindings/python" && bash build.sh >/dev/null 2>&1 ) &
      P7=$!
      wait $P1 $P2 $P3 $P4 $P5 $P6 $P7 2>/dev/null
      ;;
  esac
}

cold_start_probes() {
  # One known-good case per adapter immediately after rebuild.
  local req='{"root":"/tmp","page":"<p>probe</p>","template":"<main>@content</main>","mode":"composed","seam":"-","bindings":{}}'
  for a in cpp rust c-abi go cs js py; do
    echo "$req" | "$SUITE/embed/adapters/$a-embed" > /dev/null 2>&1 \
      || echo "  cold-start probe FAILED for $a"
  done
}

run_corpus_once() {
  ( cd "$SUITE" && CPP_HARNESS="$EMBED/.build/engine-harness" \
      RUST_HARNESS="$RUNS/target/debug/examples/engine_harness" \
      NIFT_C_ABI="$EMBED/libnift_c.so" ./embed/run-embed.py > "$SUITE/embed/failures/last-run.log" 2>&1 )
  local rc=$?
  if [ $rc -ne 0 ] || grep -q "^FAIL " "$SUITE/embed/failures/last-run.log"; then
    echo "=== FAILURE CAPTURED (rc=$rc) ==="
    grep -A18 "^FAIL " "$SUITE/embed/failures/last-run.log" | head -24
    echo "--- durable diagnostics ---"
    ls -t "$SUITE/embed/failures/"*.json 2>/dev/null | head -1 | xargs cat 2>/dev/null | head -40
    return 1
  fi
  return 0
}

rm -rf "$SUITE/embed/failures"
mkdir -p "$SUITE/embed/failures"
for i in $(seq 1 "$ITERS"); do
  LOADER_PIDS=""
  clean_all
  heavy_build
  case "$MODE" in
    delay) sleep "$DELAY";;
    memory) for _ in $(seq 1 2); do head -c 900M /dev/zero > "/tmp/memfill.$$.$_" & LOADER_PIDS="$LOADER_PIDS $!"; done; sleep 2;;
    cpu) for _ in 1 2 3 4; do while :; do :; done & LOADER_PIDS="$LOADER_PIDS $!"; done;;
  esac
  echo "iteration $i/$ITERS mode=$MODE: built; first corpus run..."
  if ! run_corpus_once; then
    kill -9 $LOADER_PIDS 2>/dev/null
    exit 1
  fi
  tail -1 "$SUITE/embed/failures/last-run.log" | sed "s/^/  run: /"
  # Clean up background loaders by PID (their subshell cmdline inherits the
  # script's argv, so pkill -f patterns cannot match them).
  kill -9 $LOADER_PIDS 2>/dev/null
  wait 2>/dev/null
  sleep 1
done
echo "campaign mode=$MODE: $ITERS fresh-build -> first-run cycles, no reproduction"

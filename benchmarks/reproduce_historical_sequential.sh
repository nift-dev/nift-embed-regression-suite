#!/usr/bin/env bash
# Faithful reproduction of the THREE HISTORICAL 35/36 workflows, each with its
# own starting artifact state and command sequence (reconstructed from the
# session). The only observation per trial is the FIRST corpus invocation.
#
#   event1 (CP17 round-4): cold -> make -j2 libnift_c.a libnift_c.so nift ->
#                          cpp harness -> go -> rust -> cs -> node (conditional:
#                          build only if addon absent) -> python -> corpus
#   event2 (CP18):         cold -> make -j2 libnift_c.a libnift_c.so nift ->
#                          cpp -> go -> rust -> cs -> node -> python ->
#                          full run-performance.sh -> corpus
#   event3 (CP18 median):  WARM managed binding artifacts (cs/node/python built
#                          beforehand, NOT rebuilt) -> make -j2 nift -> cpp ->
#                          go -> rust -> full run-performance.sh -> corpus
#
# Usage: reproduce_historical_sequential.sh event1|event2|event3 [trials]
set -u
EVENT="${1:?usage: reproduce_historical_sequential.sh event1|event2|event3 [trials]}"
TRIALS="${2:-20}"
EMBED=/home/nick/Repositories/nift/nift-embed
SUITE=/home/nick/Repositories/nift/nift-embed-regression-suite
RUNS=/home/nick/Repositories/nift/nift-rs

MANAGED_SNAPSHOT=/tmp/nift-event3-managed.tar.gz

clean_cold() {
  ( cd "$EMBED" && make clean >/dev/null 2>&1; rm -rf .build libnift_c.a libnift_c.so nift \
      bindings/go/embed-harness bindings/node/build bindings/python/build 2>/dev/null )
  ( cd "$EMBED/bindings/csharp" && find . -type d \( -name bin -o -name obj \) -exec rm -rf {} + 2>/dev/null )
  ( cd "$EMBED/bindings/python" && rm -f nift/_nift*.so 2>/dev/null; find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null )
  ( cd "$RUNS" && cargo clean >/dev/null 2>&1 )
  ( cd "$SUITE/benchmarks/embed" && rm -f cpp_bench cabi_bench 2>/dev/null )
}

build_cpp() {
  ( cd "$EMBED" && mkdir -p .build && g++ -std=c++17 -O2 -pthread -Isrc -Iinclude -Iminifypp/include -Iminifypp/src \
      tests/engine_harness.cpp src/Engine.cpp src/Context.cpp src/Value.cpp src/FileSystem.cpp \
      src/JsonFile.cpp src/JsonSchema.cpp src/Parser.cpp src/ProjectOwnership.cpp src/ProjectInfo.cpp \
      src/ProjectRead.cpp src/ProjectState.cpp src/WatchList.cpp src/BuildProgress.cpp \
      minifypp/src/Minify.cpp -o .build/engine-harness >/dev/null 2>&1 )
}
build_go()   { ( cd "$EMBED/bindings/go" && go build -o embed-harness ./cmd/embed-harness >/dev/null 2>&1 ); }
build_rust() { ( cd "$RUNS" && cargo build --example engine_harness >/dev/null 2>&1 ); }
build_cs()   { ( cd "$EMBED/bindings/csharp/apps/NiftEmbedHarness" && dotnet build -v q --nologo >/dev/null 2>&1 ); }
build_node() { ( cd "$EMBED/bindings/node" && bash build.sh >/dev/null 2>&1 ); }
build_py()   { ( cd "$EMBED/bindings/python" && bash build.sh >/dev/null 2>&1 ); }

# Event-1 historical Node step: the addon was only rebuilt if absent.
build_node_conditional() {
  ( cd "$EMBED/bindings/node" && { [ -f build/nift_node.node ] || bash build.sh >/dev/null 2>&1; } )
}

run_perf_campaign() {
  timeout 1800 bash "$SUITE/run-performance.sh" "$EMBED/nift" >/dev/null 2>&1
}

run_corpus_once() {
  local label="$1" trial="$2"
  ( cd "$SUITE" && CPP_HARNESS="$EMBED/.build/engine-harness" \
      RUST_HARNESS="$RUNS/target/debug/examples/engine_harness" \
      NIFT_C_ABI="$EMBED/libnift_c.so" ./embed/run-embed.py > "$SUITE/embed/failures/trial-run.log" 2>&1 )
  local rc=$?
  if [ $rc -ne 0 ] || grep -q "^FAIL " "$SUITE/embed/failures/trial-run.log"; then
    echo "=== FAILURE CAPTURED (event=$label, trial=$trial, rc=$rc) ==="
    grep -A18 "^FAIL " "$SUITE/embed/failures/trial-run.log" | head -24
    for f in "$SUITE/embed/failures/"*.json; do
      [ -f "$f" ] && { echo "== $f =="; head -60 "$f"; }
    done
    return 1
  fi
  return 0
}

# event3: establish the warm managed-artifact state ONCE (cs/node/python built
# and snapshot), then per trial restore that snapshot WITHOUT rebuilding them.
setup_event3() {
  clean_cold
  ( cd "$EMBED" && make -j2 libnift_c.a libnift_c.so nift >/dev/null 2>&1 ) || return 1
  build_cpp || return 1
  build_go   || return 1
  build_rust || return 1
  build_cs   || return 1
  build_node || return 1
  build_py   || return 1
  tar czf "$MANAGED_SNAPSHOT" \
    -C "$EMBED/bindings/csharp/apps" NiftEmbedHarness/bin NiftEmbedHarness/obj \
    -C "$EMBED/bindings/node" build \
    -C "$EMBED/bindings/python" nift 2>/dev/null
  echo "event3 warm-artifact snapshot established"
}
restore_event3_managed() {
  tar xzf "$MANAGED_SNAPSHOT" -C "$EMBED/bindings/csharp/apps" NiftEmbedHarness/bin NiftEmbedHarness/obj 2>/dev/null
  ( cd "$EMBED/bindings/node" && tar xzf "$MANAGED_SNAPSHOT" -C . build/nift_node.node 2>/dev/null )
  ( cd "$EMBED/bindings/python" && tar xzf "$MANAGED_SNAPSHOT" -C . nift 2>/dev/null )
}

rm -rf "$SUITE/embed/failures"
mkdir -p "$SUITE/embed/failures"

case "$EVENT" in
  event1)
    for t in $(seq 1 "$TRIALS"); do
      echo "TRIAL $t/$TRIALS (event1): cold -> make -> cpp/go/rust/cs -> node(if absent) -> python -> first corpus"
      clean_cold
      ( cd "$EMBED" && make -j2 libnift_c.a libnift_c.so nift >/dev/null 2>&1 ) || { echo "make failed"; exit 2; }
      build_cpp && build_go && build_rust && build_cs || { echo "build failed"; exit 2; }
      build_node_conditional && build_py || { echo "binding build failed"; exit 2; }
      run_corpus_once event1 "$t" || exit 1
      tail -1 "$SUITE/embed/failures/trial-run.log" | sed "s/^/  event1 t$t first-run: /"
    done
    ;;
  event2)
    for t in $(seq 1 "$TRIALS"); do
      echo "TRIAL $t/$TRIALS (event2): cold -> make -> cpp/go/rust/cs/node/python -> perf -> first corpus"
      clean_cold
      ( cd "$EMBED" && make -j2 libnift_c.a libnift_c.so nift >/dev/null 2>&1 ) || { echo "make failed"; exit 2; }
      build_cpp && build_go && build_rust && build_cs && build_node && build_py || { echo "build failed"; exit 2; }
      run_perf_campaign
      run_corpus_once event2 "$t" || exit 1
      tail -1 "$SUITE/embed/failures/trial-run.log" | sed "s/^/  event2 t$t first-run: /"
    done
    ;;
  event3)
    setup_event3 || { echo "event3 setup failed"; exit 2; }
    for t in $(seq 1 "$TRIALS"); do
      echo "TRIAL $t/$TRIALS (event3): restore warm cs/node/python (NOT rebuilt) -> make nift -> cpp/go/rust -> perf -> first corpus"
      restore_event3_managed
      ( cd "$EMBED" && make -j2 nift >/dev/null 2>&1 ) || { echo "make nift failed"; exit 2; }
      build_cpp && build_go && build_rust || { echo "build failed"; exit 2; }
      run_perf_campaign
      run_corpus_once event3 "$t" || exit 1
      tail -1 "$SUITE/embed/failures/trial-run.log" | sed "s/^/  event3 t$t first-run: /"
    done
    ;;
  *)
    echo "unknown event: $EVENT (use event1|event2|event3)" >&2
    exit 2
    ;;
esac
echo "historical campaign ($EVENT): $TRIALS complete cycles, no reproduction"

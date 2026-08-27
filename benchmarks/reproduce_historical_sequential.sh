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
#                          beforehand, snapshot restored NOT rebuilt) ->
#                          make -j2 nift -> cpp -> go -> rust ->
#                          full run-performance.sh -> corpus
#
# FAIL-FAST evidence discipline: every required step (build, performance
# campaign, snapshot creation, snapshot restore, restore verification) must
# complete successfully or the trial aborts and is NOT counted. The perf
# campaign output is saved per event/trial (distinguishing timeout rc=124 from
# benchmark failure) and event-3 restored-artifact hashes are compared against
# the established warm snapshot.
#
# Usage: reproduce_historical_sequential.sh event1|event2|event3 [trials]
set -u
EVENT="${1:?usage: reproduce_historical_sequential.sh event1|event2|event3 [trials]}"
TRIALS="${2:-20}"
EMBED="${NIFT_CANONICAL_DIR:-}"
[ -n "$EMBED" ] && [ -d "$EMBED" ] || { echo "EMBED (NIFT_CANONICAL_DIR) must point to a Nift checkout" >&2; exit 2; }
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS="${NIFT_RS_DIR:-}"
[ -n "$RUNS" ] && [ -d "$RUNS" ] || { echo "RUNS (NIFT_RS_DIR) must point to the nift-rs checkout" >&2; exit 2; }

MANAGED_SNAPSHOT=/tmp/nift-event3-managed.tar.gz
# Per-invocation log dir: NEVER destroyed so evidence accumulates across runs.
PERF_LOG_DIR="$SUITE/benchmarks/perf-logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$PERF_LOG_DIR"
echo "perf logs: $PERF_LOG_DIR"

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

build_node_conditional() {
  ( cd "$EMBED/bindings/node" && { [ -f build/nift_node.node ] || bash build.sh >/dev/null 2>&1; } )
}

# Fail-fast performance campaign: output saved per event/trial; rc=124 is a
# timeout, anything else a benchmark failure. Never proceeds on non-zero.
run_perf_campaign() {
  local label="$1" trial="$2"
  local out="$PERF_LOG_DIR/${label}-t${trial}.log"
  timeout 1800 env REQUIRE_CP18_PART_B=1 bash "$SUITE/run-performance.sh" "$EMBED/nift" >"$out" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    local why="failed"
    [ $rc -eq 124 ] && why="TIMEOUT"
    echo "=== PERF $why (event=$label, trial=$trial, rc=$rc) log: $out ==="
    tail -30 "$out"
    return 1
  fi
  return 0
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

# Managed artifacts and their hashes for event-3 warm-state enforcement.
cs_dll() { find "$EMBED/bindings/csharp/apps/NiftEmbedHarness/bin" -name 'embed-harness.dll' -print -quit 2>/dev/null; }
node_addon() { echo "$EMBED/bindings/node/build/nift_node.node"; }
py_ext() { find "$EMBED/bindings/python/nift" -maxdepth 1 -name '_nift*.so' -print -quit 2>/dev/null; }
managed_hash() {
  local p="$1"
  if [ -n "$p" ] && [ -f "$p" ]; then sha256sum "$p" | cut -d' ' -f1; else echo "MISSING"; fi
}
managed_state() {
  echo "cs=$(managed_hash "$(cs_dll)") node=$(managed_hash "$(node_addon)") py=$(managed_hash "$(py_ext)")"
}

# event3: build everything once, snapshot cs/node/python, record the warm
# hashes, then per trial restore the snapshot WITHOUT rebuilding them.
setup_event3() {
  clean_cold
  ( cd "$EMBED" && make -j2 libnift_c.a libnift_c.so nift >/dev/null 2>&1 ) || return 1
  build_cpp || return 1
  build_go   || return 1
  build_rust || return 1
  build_cs   || return 1
  build_node || return 1
  build_py   || return 1
  if ! tar czf "$MANAGED_SNAPSHOT" \
      -C "$EMBED/bindings/csharp/apps" NiftEmbedHarness/bin NiftEmbedHarness/obj \
      -C "$EMBED/bindings/node" build/nift_node.node \
      -C "$EMBED/bindings/python" nift 2>/dev/null; then
    echo "event3 snapshot creation FAILED" >&2
    return 1
  fi
  tar tzf "$MANAGED_SNAPSHOT" 2>/dev/null | grep -q "NiftEmbedHarness/bin" || { echo "snapshot missing cs" >&2; return 1; }
  tar tzf "$MANAGED_SNAPSHOT" 2>/dev/null | grep -q "nift_node.node" || { echo "snapshot missing node" >&2; return 1; }
  tar tzf "$MANAGED_SNAPSHOT" 2>/dev/null | grep -q "nift/" || { echo "snapshot missing py" >&2; return 1; }
  echo "event3 warm-artifact snapshot established: $(managed_state)"
}

restore_event3_managed() {
  # Remove the managed artifacts FIRST so a failed extraction cannot silently
  # fall back to the previous trial's files; verification below catches it.
  rm -rf "$EMBED/bindings/csharp/apps/NiftEmbedHarness/bin" "$EMBED/bindings/csharp/apps/NiftEmbedHarness/obj"
  rm -f  "$EMBED/bindings/node/build/nift_node.node"
  rm -f  "$EMBED/bindings/python/nift/_nift"*.so
  tar xzf "$MANAGED_SNAPSHOT" -C "$EMBED/bindings/csharp/apps" NiftEmbedHarness/bin NiftEmbedHarness/obj 2>/dev/null || return 1
  ( cd "$EMBED/bindings/node" && tar xzf "$MANAGED_SNAPSHOT" -C . build/nift_node.node 2>/dev/null ) || return 1
  ( cd "$EMBED/bindings/python" && tar xzf "$MANAGED_SNAPSHOT" -C . nift 2>/dev/null ) || return 1
  [ -n "$(cs_dll)" ] || { echo "restore: cs dll MISSING" >&2; return 1; }
  [ -f "$(node_addon)" ] || { echo "restore: node addon MISSING" >&2; return 1; }
  [ -n "$(py_ext)" ] || { echo "restore: py ext MISSING" >&2; return 1; }
  return 0
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
      run_perf_campaign event2 "$t" || exit 2
      run_corpus_once event2 "$t" || exit 1
      tail -1 "$SUITE/embed/failures/trial-run.log" | sed "s/^/  event2 t$t first-run: /"
    done
    ;;
  event3)
    setup_event3 || { echo "event3 setup failed"; exit 2; }
    SNAP_HASH="$(managed_state)"
    for t in $(seq 1 "$TRIALS"); do
      echo "TRIAL $t/$TRIALS (event3): restore warm cs/node/python (NOT rebuilt) -> make nift -> cpp/go/rust -> perf -> first corpus"
      restore_event3_managed || { echo "event3 restore FAILED (trial $t)"; exit 2; }
      local_hash="$(managed_state)"
      [ "$local_hash" = "$SNAP_HASH" ] || { echo "restore hash MISMATCH (trial $t): got $local_hash want $SNAP_HASH" >&2; exit 2; }
      echo "  restored: $local_hash"
      ( cd "$EMBED" && make -j2 nift >/dev/null 2>&1 ) || { echo "make nift failed"; exit 2; }
      build_cpp && build_go && build_rust || { echo "build failed"; exit 2; }
      run_perf_campaign event3 "$t" || exit 2
      run_corpus_once event3 "$t" || exit 1
      tail -1 "$SUITE/embed/failures/trial-run.log" | sed "s/^/  event3 t$t first-run: /"
    done
    ;;
  *)
    echo "unknown event: $EVENT (use event1|event2|event3)" >&2
    exit 2
    ;;
esac
echo "historical campaign ($EVENT): $TRIALS complete fail-fast cycles, no reproduction"

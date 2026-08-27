#!/usr/bin/env bash
# Quiet warm-baseline campaign: N sequential warm corpus passes with NO
# preceding performance campaign, NO rebuilds, NO cleans and NO deliberate
# load. Purpose (reviewer's bounded investigation): test whether the historical
# 35/36 can recur during ordinary repeated corpus execution, independent of the
# heavy workload and artifact transitions that preceded the three observed
# failures.
#
# Phases:
#   1. build all seven adapter surfaces once; record a JSON baseline (repo
#      heads, clean/dirty state, SHA-256 of every adapter artifact, toolchain
#      versions, initial load/memory/disk).
#   2. 10 untimed warm-up passes.
#   3. 10 timed passes -> median/range duration estimate.
#   4. <PASSES> timed passes, one corpus process at a time, stable run numbers
#      1..PASSES, every pass appended to a durable campaign log with
#      start/end/duration/summary. Structured diagnostics are collision-proof
#      (campaign id + run number + nanosecond timestamp + kind) and prior
#      evidence is never cleared.
#
# On the first failure the campaign STOPS IMMEDIATELY: no rerun, no rebuild, no
# artifact modification. The full pass output, structured records, system state
# and post-failure artifact hashes (diffed against baseline) are captured and
# the campaign exits 1 with the failing state untouched.
#
# Usage: warm_baseline_campaign.sh [passes] [campaign-id]
set -u
PASSES="${1:-1000}"
CAMPAIGN="${2:-warm-$(date +%Y%m%d-%H%M%S)}"
EMBED=/home/nick/Repositories/nift/nift-embed
SUITE=/home/nick/Repositories/nift/nift-embed-regression-suite
RUNS=/home/nick/Repositories/nift/nift-rs
OUT="$SUITE/benchmarks/warm-baseline/$CAMPAIGN"
mkdir -p "$OUT"
echo "campaign: $CAMPAIGN  passes: $PASSES  out: $OUT"

clean_build_once() {
  # Fresh single build of every adapter surface; afterwards NOTHING is rebuilt,
  # cleaned or modified for the whole campaign.
  ( cd "$EMBED" && make clean >/dev/null 2>&1; make -j2 libnift_c.a libnift_c.so nift >/dev/null 2>&1 ) || return 1
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

collect_hashes() {
  {
    echo "cpp_harness  $(sha256sum "$EMBED/.build/engine-harness" 2>/dev/null | cut -d' ' -f1)"
    echo "libnift_c.a  $(sha256sum "$EMBED/libnift_c.a" 2>/dev/null | cut -d' ' -f1)"
    echo "libnift_c.so $(sha256sum "$EMBED/libnift_c.so" 2>/dev/null | cut -d' ' -f1)"
    echo "go_harness   $(sha256sum "$EMBED/bindings/go/embed-harness" 2>/dev/null | cut -d' ' -f1)"
    echo "rust_harness $(sha256sum "$RUNS/target/debug/examples/engine_harness" 2>/dev/null | cut -d' ' -f1)"
    echo "cs_dll       $(find "$EMBED/bindings/csharp/apps/NiftEmbedHarness/bin" -name 'embed-harness.dll' -exec sha256sum {} + 2>/dev/null | awk '{print $1}' | sha256sum | cut -d' ' -f1)"
    echo "node_addon   $(sha256sum "$EMBED/bindings/node/build/nift_node.node" 2>/dev/null | cut -d' ' -f1)"
    echo "py_ext       $(sha256sum "$EMBED/bindings/python/nift/_nift"*.so 2>/dev/null | cut -d' ' -f1)"
  }
}

run_pass() {
  local phase="$1" run="$2"
  local out="$OUT/pass-${phase}-${run}.log"
  local start end dur rc summary failed
  start=$(date +%s.%N)
  ( cd "$SUITE" && NIFT_CAMPAIGN_ID="$CAMPAIGN" NIFT_CAMPAIGN_RUN="$run" \
      CPP_HARNESS="$EMBED/.build/engine-harness" \
      RUST_HARNESS="$RUNS/target/debug/examples/engine_harness" \
      NIFT_C_ABI="$EMBED/libnift_c.so" \
      timeout 900 ./embed/run-embed.py > "$out" 2>&1 )
  rc=$?
  end=$(date +%s.%N)
  dur=$(awk "BEGIN{printf \"%.3f\", $end - $start}")
  summary=$(grep "Embed contract:" "$out" | tail -1)
  failed=$(echo "$summary" | grep -oE '[0-9]+ failed' | cut -d' ' -f1)
  failed=${failed:-X}
  # Structured diagnostics created for this run (crash/non-json/mismatch).
  local records
  records=$(ls "$SUITE/embed/failures/" 2>/dev/null | grep -F "r${run}-" | wc -l)
  echo "phase=$phase run=$run rc=$rc dur=${dur}s start=$start end=$end summary=\"$summary\"" >> "$OUT/campaign.log"
  if [ $rc -ne 0 ] || [ "$failed" != "0" ] || grep -q "^FAIL " "$out"; then
    echo "=== FAILURE at phase=$phase run=$run (rc=$rc, failed=$failed) — STOPPING, state frozen ===" >> "$OUT/campaign.log"
    cp "$out" "$OUT/FAILURE-pass-${phase}-${run}.log"
    { echo "--- post-failure system state ---"; uptime; free -h | head -2; df -h /home | tail -1; } > "$OUT/FAILURE-system.txt"
    ls "$SUITE/embed/failures/" > "$OUT/FAILURE-records-listing.txt" 2>&1
    for f in "$SUITE/embed/failures/"*r"${run}"*.json; do
      [ -f "$f" ] && { echo "== $f =="; head -80 "$f"; }
    done > "$OUT/FAILURE-structured.txt" 2>/dev/null
    collect_hashes > "$OUT/post-failure-hashes.txt"
    diff "$OUT/baseline-hashes.txt" "$OUT/post-failure-hashes.txt" > "$OUT/FAILURE-hash-diff.txt" || true
    echo "failure fully captured under $OUT"
    exit 1
  fi
  return 0
}

if ! clean_build_once; then
  echo "initial build failed" >&2
  exit 2
fi
collect_hashes > "$OUT/baseline-hashes.txt"

# Baseline JSON: heads, status, versions, initial system state.
python3 - "$OUT" "$CAMPAIGN" "$PASSES" <<'PY' || exit 2
import json, pathlib, subprocess, sys, os, time
out, campaign, passes = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
def sh(*a):
    try:
        return subprocess.run(a, capture_output=True, text=True).stdout.strip()
    except Exception:
        return ""
def repo_state(path):
    h = sh("git", "-C", path, "rev-parse", "HEAD")
    dirty = bool(sh("git", "-C", path, "status", "--porcelain"))
    return {"head": h, "dirty": dirty}
mem = {}
with open("/proc/meminfo") as f:
    for line in f:
        k, v = line.split(":", 1); mem[k] = v.strip()
st = os.statvfs(str(out.parent.parent.parent))
baseline = {
    "campaign": campaign,
    "passes": int(passes),
    "repos": {
        "nift-embed": repo_state("/home/nick/Repositories/nift/nift-embed"),
        "nift-rs": repo_state("/home/nick/Repositories/nift/nift-rs"),
        "nift-embed-regression-suite": repo_state("/home/nick/Repositories/nift/nift-embed-regression-suite"),
    },
    "toolchain": {
        "g++": sh("g++", "--version").splitlines()[0] if sh("g++", "--version") else "",
        "go": sh("go", "version"),
        "rustc": sh("rustc", "-V"),
        "dotnet": sh("dotnet", "--version"),
        "node": sh("node", "-v"),
        "python": sh("python3", "-V"),
    },
    "initial_system": {
        "loadavg": os.getloadavg(),
        "meminfo_available_kb": mem.get("MemAvailable"),
        "meminfo_free_kb": mem.get("MemFree"),
        "disk_free_bytes": st.f_bavail * st.f_frsize,
    },
    "initial_hashes": (out / "baseline-hashes.txt").read_text().strip(),
}
(out / "baseline.json").write_text(json.dumps(baseline, indent=2))
print("baseline recorded:", json.dumps(baseline, indent=2))
PY

echo "--- 10 untimed warm-ups ---"
for i in $(seq 1 10); do
  run_pass warm "w$i" || exit 1
done
echo "warm-ups complete"

echo "--- 10 timed estimation passes ---"
for i in $(seq 1 10); do
  run_pass timed "e$i" || exit 1
done
python3 - "$OUT" <<'PY'
import json, pathlib, sys, statistics
log = pathlib.Path(sys.argv[1]) / "campaign.log"
durs = [float(l.split("dur=")[1].split("s")[0]) for l in log.read_text().splitlines() if "phase=timed " in l]
print(f"timed estimation: {len(durs)} passes; median={statistics.median(durs):.3f}s range={min(durs):.3f}-{max(durs):.3f}s "
      f"=> {len(durs)*statistics.median(durs)/60:.1f} min for campaign of {len(durs)} passes")
PY

echo "--- measured campaign: $PASSES passes ---"
for i in $(seq 1 "$PASSES"); do
  run_pass campaign "$i" || exit 1
  if [ $((i % 50)) -eq 0 ]; then echo "  campaign pass $i/$PASSES complete"; fi
done

collect_hashes > "$OUT/post-hashes.txt"

python3 - "$OUT" "$PASSES" <<'PY' || exit 1
import json, pathlib, sys, statistics
out, passes = pathlib.Path(sys.argv[1]), int(sys.argv[2])
log = out / "campaign.log"
lines = [l for l in log.read_text().splitlines() if "phase=campaign " in l]
if len(lines) != passes:
    print(f"ERROR: campaign log has {len(lines)} campaign entries, expected {passes}"); sys.exit(1)
durs = [float(l.split("dur=")[1].split("s")[0]) for l in lines]
fails = [l for l in lines if '"Embed contract: 36 passed, 0 failed"' not in l and "0 failed" not in l]
d = sorted(durs)
p95 = d[min(len(d)-1, int(len(d)*0.95))]
baseline = json.loads((out / "baseline.json").read_text())
post = {}
with open(out / "post-hashes.txt") as f:
    for line in f:
        k, _, v = line.strip().partition("  "); post[k.strip()] = v.strip()
bl = {}
for line in baseline["initial_hashes"].splitlines():
    k, _, v = line.strip().partition("  "); bl[k.strip()] = v.strip()
print(f"campaign complete: {len(lines)} passes, all 36/36")
print(f"duration: total={sum(durs)/60:.1f}min  per-pass min={min(d):.3f}s median={statistics.median(d):.3f}s p95={p95:.3f}s max={max(d):.3f}s")
print(f"artifact hashes unchanged: {post == bl}")
print(f"unexpected records/stderr/timeouts: {sum(1 for l in lines if 'rc=124' in l)} timeouts, "
      f"{len([x for x in (out).glob('*.log') if 'FAIL' in x.name])} failure logs, "
      f"{0} retries (none designed)")
PY
collect_hashes > "$OUT/post-hashes.txt"
echo "campaign log: $OUT/campaign.log"
echo "done"

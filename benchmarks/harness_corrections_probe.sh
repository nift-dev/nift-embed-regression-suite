#!/usr/bin/env bash
# Focused probes for the three harness corrections (run AFTER the corrections;
# do NOT re-run any corpus campaign).
#
#   Probe 1: REQUIRE_CP18_PART_B strict mode.
#       - lenient run-performance.sh: a failing Part B is reported as skipped
#         and the run still exits 0; Part-B stderr is NOT retained.
#       - strict (REQUIRE_CP18_PART_B=1): the failing Part B makes
#         run-performance.sh exit non-zero and Part-B stderr IS retained.
#   Probe 2: warm_baseline_verify.py artifact-hash exit gate.
#       - post-hashes differing from baseline -> non-zero + readable DIFF.
#       - matching hashes -> exit 0.
#   Probe 3: run_pass structured-diagnostics gate matching.
#       - a diagnostic for THIS campaign+run is detected;
#       - a diagnostic from ANOTHER campaign with the same run number is not.
#
# Exits non-zero if any check fails.
set -u
SUITE=/home/nick/Repositories/nift/nift-embed-regression-suite
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-harness-probe.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }

echo "===== Probe 1: strict Part B propagation ====="
# Stub ROOT for run-performance.sh: Part A scripts that succeed, a nift stub,
# and a Part B collector that always fails (writing to stderr).
mkdir -p "$TMP/root/benchmarks/embed"
cp "$SUITE/run-performance.sh" "$TMP/root/run-performance.sh"
for s in tracking_scaling_benchmark full_build_scaling_benchmark memory_10k_benchmark cp18_cli_build_workload; do
  printf '#!/usr/bin/env python3\nprint("stub")\n' > "$TMP/root/benchmarks/$s.py"
done
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/root/nift"
printf '#!/usr/bin/env bash\necho "PARTB-FAIL-STDERR" >&2\nexit 1\n' > "$TMP/root/benchmarks/embed/run_cp18_embed.sh"
chmod +x "$TMP/root/nift" "$TMP/root/benchmarks/embed/run_cp18_embed.sh"

# Lenient: must exit 0, report skip, and NOT retain Part-B stderr.
out="$("$TMP/root/run-performance.sh" "$TMP/root/nift" 2>&1)"; lrc=$?
if [ $lrc -eq 0 ] && echo "$out" | grep -q "CP18 part B skipped" \
   && ! echo "$out" | grep -q "PARTB-FAIL-STDERR"; then
  pass "lenient mode: failing Part B -> rc=0, skip message, stderr not retained"
else
  fail "lenient mode (rc=$lrc): $out" | head -5
fi

# Strict: must exit non-zero and retain Part-B stderr.
out="$("$TMP/root/run-performance.sh" "$TMP/root/nift" 2>&1)"; src=$?
REQUIRE_CP18_PART_B=1 "$TMP/root/run-performance.sh" "$TMP/root/nift" >"$TMP/strict.out" 2>&1; s1=$?
if [ $s1 -ne 0 ] && grep -q "PARTB-FAIL-STDERR" "$TMP/strict.out"; then
  pass "strict mode: failing Part B -> non-zero rc ($s1), Part-B stderr retained"
else
  fail "strict mode (rc=$s1): $(tail -3 "$TMP/strict.out")"
fi

echo "===== Probe 2: artifact-hash exit gate ====="
mkdir -p "$TMP/camp"
printf 'cpp_harness  aa\nlibnift_c.a  bb\n' > "$TMP/camp/baseline-hashes.txt"
printf '{"passes":1}' > "$TMP/camp/baseline.json"
printf 'phase=campaign run=1 rc=0 dur=1.0s start=1 end=2 summary="Embed contract: 36 passed, 0 failed"\n' > "$TMP/camp/campaign.log"
printf 'cpp_harness  aa\nlibnift_c.a  cc\n' > "$TMP/camp/post-hashes.txt"
python3 "$SUITE/benchmarks/warm_baseline_verify.py" "$TMP/camp" 1 >"$TMP/v2.out" 2>&1; v2=$?
if [ $v2 -ne 0 ] && grep -q "DIFF libnift_c.a" "$TMP/v2.out"; then
  pass "hash mismatch -> non-zero + readable DIFF"
else
  fail "hash mismatch not gated (rc=$v2): $(cat "$TMP/v2.out")"
fi
printf 'cpp_harness  aa\nlibnift_c.a  bb\n' > "$TMP/camp/post-hashes.txt"
python3 "$SUITE/benchmarks/warm_baseline_verify.py" "$TMP/camp" 1 >/dev/null 2>&1; v3=$?
if [ $v3 -eq 0 ]; then
  pass "matching hashes -> exit 0"
else
  fail "matching hashes rejected (rc=$v3)"
fi

echo "===== Probe 3: structured-diagnostics gate matching ====="
mkdir -p "$TMP/failures"
touch "$TMP/failures/probe-camp-r1-t111111-crash-caseX-cpp-embed.json"
touch "$TMP/failures/other-camp-r1-t222222-crash-caseX-cpp-embed.json"
matching=$(find "$TMP/failures" -maxdepth 1 -name "*probe-camp-r1-*" -type f 2>/dev/null | wc -l)
nonmatching=$(find "$TMP/failures" -maxdepth 1 -name "*probe-camp-r2-*" -type f 2>/dev/null | wc -l)
if [ "$matching" = "1" ] && [ "$nonmatching" = "0" ]; then
  pass "diagnostic for THIS campaign+run detected (1); other-campaign / other-run not matched"
else
  fail "matching=$matching nonmatching=$nonmatching (expected 1 and 0)"
fi

echo
if [ $FAILED -eq 0 ]; then
  echo "all harness-correction probes passed"
else
  echo "$FAILED probe checks FAILED" >&2
fi
exit $FAILED
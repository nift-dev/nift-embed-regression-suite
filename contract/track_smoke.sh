#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-track.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .nift content templates public
cat > .nift/config.json <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","incremental-mode":"modified"}}
JSON
cat > .nift/tracked.json <<'JSON'
{"tracked":[{"name":"/","title":"index","template":"templates/template.html"}]}
JSON
cat > templates/template.html <<'EOF'
<main>@content</main>
EOF
printf '<p>home</p>\n' > content/index.html
"$NIFT_BIN" build >/dev/null 2>&1

fail() { echo "$*" >&2; exit 1; }

tracked_hash() { sha256sum .nift/tracked.json | cut -d' ' -f1; }

# Malformed / invalid track invocations must fail before ANY mutation: no
# tracked.json change, no content file, and crucially no .unfinished (a track
# command never begins build-state mutation; the ownership epoch is only for
# builds and the untrack/rm mutators).
check_no_mutation() {
  local desc="$1"; shift
  local before
  before="$(tracked_hash)"
  local rc
  set +e
  "$NIFT_BIN" "$@" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "$desc unexpectedly succeeded"
  [ "$(tracked_hash)" == "$before" ] || fail "$desc changed tracked.json"
  test ! -e .nift/.unfinished || fail "$desc created .unfinished"
  local content_files
  content_files="$(find content -type f | wc -l)"
  [ "$content_files" -eq 1 ] || fail "$desc created a content file"
}

check_no_mutation "too many arguments"  track a b c d
check_no_mutation "five names"          track a a a a a
check_no_mutation "absolute name"       track /abs
check_no_mutation "parent traversal"    track ../escape
check_no_mutation "duplicate of tracked" track /
check_no_mutation "missing name"        track

# The unified CLI grammar is single-name: `track <name> [title] [template]`.
# `track a b` is VALID and tracks "a" with title "b" (there is no multi-name
# form); it must not create .unfinished.
"$NIFT_BIN" track alpha beta >/dev/null 2>&1 || fail 'track <name> <title> failed'
test ! -e .nift/.unfinished || fail 'valid track created .unfinished'
grep -q '"name": "alpha"' .nift/tracked.json || fail 'tracked name alpha missing'
grep -q '"title": "beta"' .nift/tracked.json || fail 'title beta not applied'
test -e content/alpha.html || fail 'track did not create content file'
"$NIFT_BIN" build >/dev/null 2>&1 || fail 'build after track failed'
test ! -e .nift/.unfinished || fail 'build after valid track created .unfinished'

# .unfinished + build --repair is the recovery path ONLY for a build that
# mutated generated state and then failed (never for a track command).
cat > .nift/tracked.json <<'JSON'
{"tracked":[{"name":"good","title":"Good","template":"templates/template.html"},{"name":"bad","title":"Bad","template":"templates/template.html"}]}
JSON
printf '<p>GOOD</p>\n' > content/good.html
printf '@input("missing-part")\n' > content/bad.html
"$NIFT_BIN" build --all >/dev/null 2>&1 && fail 'build with broken page succeeded'
test -e .nift/.unfinished || fail 'mutated-then-failed build did not create .unfinished'
"$NIFT_BIN" build >/dev/null 2>&1 && fail 'ordinary build proceeded past a stale marker'
printf '<p>BAD-FIXED</p>\n' > content/bad.html
"$NIFT_BIN" build >/dev/null 2>&1 && fail 'ordinary build proceeded after source fix but before repair'
"$NIFT_BIN" build --repair >/dev/null 2>&1 || fail 'build --repair failed to reconstruct'
test ! -e .nift/.unfinished || fail 'build --repair left the marker'
"$NIFT_BIN" build >/dev/null 2>&1 || fail 'ordinary build failed after repair'

echo 'Track transactionality / .unfinished contract smoke test passed'

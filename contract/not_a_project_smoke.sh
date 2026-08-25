#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-not-a-project.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# There is no global Nift configuration. A project exists only where the
# relevant project state exists (.nift/config.json AND .nift/tracked.json).
# Project-requiring commands outside a project must fail cleanly as
# "not a Nift project" with zero filesystem mutation, and must never consult a
# historical global config (e.g. ~/.nift/config.json with old keys such as
# "lolcat-default").
fail() { echo "$*" >&2; exit 1; }

EMPTY="$TMP/empty"
mkdir -p "$EMPTY"

check_outside() {
  local cmd="$1"; shift
  local before
  before="$(cd "$EMPTY" && find . -mindepth 1 | sort)"
  local out rc
  set +e
  out="$(cd "$EMPTY" && "$NIFT_BIN" "$@" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "$cmd outside a project returned success"
  case "$out" in
    *"not a Nift project"*) ;;
    *) fail "$cmd outside a project did not report 'not a Nift project' (got: $out)";;
  esac
  case "$out" in
    *config*|*lolcat*|*tracked*) fail "$cmd outside a project leaked a config/tracking diagnostic (got: $out)";;
  esac
  local after
  after="$(cd "$EMPTY" && find . -mindepth 1 | sort)"
  [ "$before" == "$after" ] || fail "$cmd outside a project mutated the filesystem"
}

check_outside "build"       build
check_outside "build --all" build --all
check_outside "build --repair" build --repair
check_outside "status"      status
check_outside "info --all"  info --all
check_outside "track"       track p
check_outside "rm"          rm p

# Hostile historical global config: ~/.nift/config.json with old keys. Must be
# completely ignored from a non-project directory.
FAKE_HOME="$TMP/fake-home"
mkdir -p "$FAKE_HOME/.nift"
cat > "$FAKE_HOME/.nift/config.json" <<'JSON'
{"config":{"lolcat-default":true,"whatever-other-old-key":true}}
JSON
out="$(cd "$EMPTY" && HOME="$FAKE_HOME" "$NIFT_BIN" status 2>&1)" && fail "status under hostile HOME returned success"
case "$out" in
  *"not a Nift project"*) ;;
  *) fail "status under hostile HOME did not report 'not a Nift project' (got: $out)";;
esac
case "$out" in
  *lolcat*|*config*) fail "status under hostile HOME leaked the global config (got: $out)";;
esac

# Distinction preserved: a real project with a malformed config is a config
# error, not "not a Nift project".
BROKEN="$TMP/broken"
mkdir -p "$BROKEN/.nift"
printf '%s\n' '{ not json' > "$BROKEN/.nift/config.json"
printf '%s\n' '{"tracked":[]}' > "$BROKEN/.nift/tracked.json"
out="$(cd "$BROKEN" && "$NIFT_BIN" status 2>&1)" && fail "status in broken project returned success"
case "$out" in
  *"invalid project config"*) ;;
  *) fail "broken project did not report a config error (got: $out)";;
esac

# Distinction preserved: a real project with an unknown config key is an
# unknown-config-key error, not "not a Nift project".
UNKNOWN="$TMP/unknown"
mkdir -p "$UNKNOWN/.nift"
printf '%s\n' '{"config":{"lolcat-default":true}}' > "$UNKNOWN/.nift/config.json"
printf '%s\n' '{"tracked":[]}' > "$UNKNOWN/.nift/tracked.json"
out="$(cd "$UNKNOWN" && "$NIFT_BIN" status 2>&1)" && fail "status in unknown-key project returned success"
case "$out" in
  *"unknown config key"*) ;;
  *) fail "unknown-key project did not report an unknown-config-key error (got: $out)";;
esac

# Standalone commands retain their behaviour outside a project.
"$NIFT_BIN" version >/dev/null 2>&1 || fail 'version failed outside a project'
"$NIFT_BIN" commands >/dev/null 2>&1 || fail 'commands failed outside a project'
"$NIFT_BIN" --help >/dev/null 2>&1 || fail '--help failed outside a project'

echo 'Not-a-project / global-config smoke test passed'

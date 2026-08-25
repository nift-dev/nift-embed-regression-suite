#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-config-validation.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .nift content templates public

fail() { echo "$*" >&2; exit 1; }

mkproj() {
  local d="$1"
  mkdir -p "$d/.nift" "$d/content" "$d/templates" "$d/public"
  printf '{"config":{"content-dir":"content/","output-dir":"public/","default-template":"templates/template.html","incremental-mode":"modified"}}' > "$d/.nift/config.json"
  printf '{"tracked":[{"name":"/","title":"index","template":"templates/template.html"}]}' > "$d/.nift/tracked.json"
  printf '<main>@content</main>' > "$d/templates/template.html"
  printf '<p>home</p>\n' > "$d/content/index.html"
}

# A real project with malformed config.json -> config error, never "not a project".
mkproj malformed-config
printf '{ not json' > malformed-config/.nift/config.json
out="$(cd malformed-config && "$NIFT_BIN" build 2>&1)" && fail 'malformed config build succeeded'
printf '%s' "$out" | grep -Fq 'invalid project config' || fail "malformed config wrong diagnostic: $out"
printf '%s' "$out" | grep -Fq 'not a Nift project' && fail 'malformed config misreported as not-a-project' || true

# Unknown config key -> unknown-config-key error, not a generic config error.
mkproj unknown-key
printf '%s\n' '{"config":{"lolcat-default":true}}' > unknown-key/.nift/config.json
out="$(cd unknown-key && "$NIFT_BIN" build 2>&1)" && fail 'unknown-key build succeeded'
printf '%s' "$out" | grep -Fq 'unknown config key' || fail "unknown-key wrong diagnostic: $out"

# Malformed tracked.json -> tracking error, never not-a-project.
mkproj malformed-tracking
printf '%s\n' '{"tracked": nope' > malformed-tracking/.nift/tracked.json
out="$(cd malformed-tracking && "$NIFT_BIN" build 2>&1)" && fail 'malformed tracking build succeeded'
printf '%s' "$out" | grep -Fq 'invalid tracked.json' || fail "malformed tracking wrong diagnostic: $out"

# A valid project still builds.
mkproj valid
(cd valid && "$NIFT_BIN" build >/dev/null 2>&1) || fail 'valid project build failed'

echo 'Config validation contract smoke test passed'

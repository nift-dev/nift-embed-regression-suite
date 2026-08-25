#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-unified-cli.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

# The unified CLI grammar (CP1): `build [names...] [--all|--auto|--repair]`,
# `info [names...] [--all|--watching|--tracking|--names]`, with modes mutually
# exclusive. Historical spellings were removed and must fail with a hint.
mkdir -p .nift content templates public
cat > .nift/config.json <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","incremental-mode":"modified"}}
JSON
cat > .nift/tracked.json <<'JSON'
{"tracked":[
 {"name":"/","title":"Home","template":"templates/template.html"},
 {"name":"about","title":"About","template":"templates/template.html"}
]}
JSON
cat > templates/template.html <<'EOF'
<main>@content</main>
EOF
printf '<p>home</p>\n' > content/index.html
printf '<p>about</p>\n' > content/about.html

fail() { echo "$*" >&2; exit 1; }

"$NIFT_BIN" build --all >/dev/null || fail 'build --all failed'
test -f public/index.html || fail 'build --all did not emit primary output'
test -f public/about.html || fail 'build --all did not emit named page'

"$NIFT_BIN" build about >/dev/null || fail 'build <name> failed'

# Mutually exclusive modes are rejected.
if "$NIFT_BIN" build --all about >/dev/null 2>&1; then fail 'build --all with a name succeeded'; fi
if "$NIFT_BIN" build --all --repair >/dev/null 2>&1; then fail 'build --all with --repair succeeded'; fi
if "$NIFT_BIN" build --all --auto >/dev/null 2>&1; then fail 'build --all with --auto succeeded'; fi
if "$NIFT_BIN" info --all about >/dev/null 2>&1; then fail 'info --all with a name succeeded'; fi
if "$NIFT_BIN" info --names --watching >/dev/null 2>&1; then fail 'info --names with --watching succeeded'; fi

# Unknown options are rejected cleanly.
if "$NIFT_BIN" build -definitely-invalid >/dev/null 2>&1; then fail 'build accepted an unknown option'; fi
if "$NIFT_BIN" info -definitely-invalid >/dev/null 2>&1; then fail 'info accepted an unknown option'; fi
if "$NIFT_BIN" status -definitely-invalid >/dev/null 2>&1; then fail 'status accepted an unknown option'; fi
if "$NIFT_BIN" status stray >/dev/null 2>&1; then fail 'status accepted a stray positional argument'; fi

# Removed historical spellings fail with a replacement hint and do no work.
removed() {
  local cmd="$1" hint="$2"
  local out
  out="$("$NIFT_BIN" "$cmd" 2>&1)" && fail "$cmd unexpectedly succeeded"
  case "$out" in
    *"$hint"*) ;;
    *) fail "$cmd did not emit replacement hint '$hint' (got: $out)";;
  esac
}
removed build-all      "use 'nift build --all' instead"
removed build-updated  "use 'nift build' instead"
removed build-names    "use 'nift build <names...>' instead"
removed build-auto     "use 'nift build --auto' instead"
removed info-all       "use 'nift info --all' instead"
removed info-watching  "use 'nift info --watching' instead"
removed info-tracking  "use 'nift info --tracking' instead"
removed info-names     "use 'nift info --names' instead"

# info modes emit their JSON documents.
"$NIFT_BIN" info --all | grep -Fq '"name": "/"' || fail 'info --all did not list tracked entry'
"$NIFT_BIN" info --names | grep -Fq '"tracked"' || fail 'info --names did not emit tracked-names JSON'
"$NIFT_BIN" info --tracking | grep -Fq '"tracked-count"' || fail 'info --tracking did not emit tracking JSON'
"$NIFT_BIN" info --watching | grep -Fq '"watched"' || fail 'info --watching did not emit watching JSON'

# build --repair on a clean project is a no-op success and leaves no marker.
"$NIFT_BIN" build --repair >/dev/null || fail 'build --repair on clean project failed'
test ! -e .nift/.unfinished || fail 'build --repair left an unfinished marker'

echo 'Unified CLI grammar smoke test passed'

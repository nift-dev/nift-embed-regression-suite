#!/usr/bin/env bash
# Nift Embed contract runner (capability layer 2 of the regression suite).
#
# Executes the same neutral Embed cases through the C++ Embed adapter and the
# nift-rs adapter and requires byte-identical neutral JSON results. The suite
# tests Nift Embed *semantics*; only the adapter knows the implementation
# language/API. nift-rs does not implement the Nift CLI/build orchestrator and
# is NOT expected to run contract/ (capability layer 1).
#
# Adapter protocol (see embed/README.md):
#   adapter <root> <page_text|-> <template_text|-> <page_name|->
#           <current_output|-> <page_path|-> <template_path|-> <mode> [seam|-]
#   bindings on stdin (name=value; "json:" prefix binds a JSON value)
#   -> one JSON line on stdout:
#      {"ok":true,"output":"...","dependencies":[...],"requirements":[...],
#       "pagination":[{"page":N,"output":"..."},...],"loaderKeys":[...]}
#      or {"ok":false,"error":"..."}
#
# Required: CPP_HARNESS (C++ Embed harness binary, from nift-embed
# .build/engine-harness) and RUST_HARNESS (nift-rs target/debug/examples/
# engine_harness).
set -euo pipefail

CPP_HARNESS="${CPP_HARNESS:-}"
RUST_HARNESS="${RUST_HARNESS:-}"
if [ -z "$CPP_HARNESS" ] || [ -z "$RUST_HARNESS" ]; then
    echo "error: set CPP_HARNESS (C++ Embed harness) and RUST_HARNESS (nift-rs harness)" >&2
    exit 2
fi
if [ ! -x "$CPP_HARNESS" ] || [ ! -x "$RUST_HARNESS" ]; then
    echo "error: harness binaries not executable" >&2
    exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nift-embed-contract.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/content" "$WORK/templates" "$WORK/public"
printf '<p>PATH-CONTENT</p>\n' >"$WORK/content/blog.html"
printf 'P\n' >"$WORK/content/part.html"
printf '<main>@content</main>\n' >"$WORK/templates/template.html"
printf 'x\n' >"$WORK/public/app.js"

pass=0
fail=0

# run_case <name> <page> <tpl> <pname> <co> <ppath> <tpath> <mode> [bindings] [seam]
run_case() {
    local name="$1" page="$2" tpl="$3" pname="$4" co="$5" ppath="$6" tpath="$7" mode="$8"
    local bindings="${9:-}" seam="${10:-}"
    local cpp_out rust_out
    cpp_out="$(printf '%s' "$bindings" | "$CPP_HARNESS" "$WORK" "$page" "$tpl" "$pname" "$co" "$ppath" "$tpath" "$mode" "$seam")"
    rust_out="$(printf '%s' "$bindings" | "$RUST_HARNESS" "$WORK" "$page" "$tpl" "$pname" "$co" "$ppath" "$tpath" "$mode" "$seam")"
    if [ "$cpp_out" == "$rust_out" ]; then
        pass=$((pass + 1))
    else
        echo "FAIL $name"
        echo "  C++ : $cpp_out"
        echo "  Rust: $rust_out"
        fail=$((fail + 1))
    fi
}

# --- General Embed cases (migrated from NR6) --------------------------------
CO="$WORK/public/about.html"
run_case "composed text render"              '<h2>P</h2>' '<main>@content</main>' - - - - composed ''
run_case "composed path render"              - - - - content/blog.html templates/template.html composed ''
run_case "partial render"                    '<p>x</p>' - - - - - partial ''
run_case "defaults binding"                  'site=$[site]@content' '<main>@content</main>' - - - - composed 'site=hello'
run_case "explicit output -> pathto"         '@pathto("public/app.js")@content' - about "$CO" - - composed ''
run_case "absent output -> pathto error"     '@pathto("public/app.js")@content' - about - - - composed ''
run_case "content/output authority (name)"   'cp=$[content-path] op=$[output-path]@content' - blog "$CO" content/blog.html - composed ''
run_case "content authority (no name)"       'cp=$[content-path]@content' - - - content/blog.html - composed ''
run_case "@input relative to loaded source"  '@input("part.html")@content' - - - content/blog.html - composed ''
run_case "dependencies/requirements spelling" '@content' - blog - content/blog.html templates/template.html composed ''
run_case "missing JSON controlled error"     '@json("data.json", d)$[d.v]@content' - - - - - composed ''
run_case "loader: path keys + content"       - - - - content/blog.html templates/template.html composed '' loader
run_case "loader: @input through loader"     - '<main>@content</main>' - - content/post.html - composed '' loader
run_case "env: provider values"              '@getenv(NIFT_ENV_A)|@getenv(NIFT_ENV_B)' '<main>@content</main>' - - - - composed '' env
run_case "env: missing value empty"          '@getenv(NIFT_ENV_MISSING)' '<main>@content</main>' - - - - composed '' env
run_case "no provider: unset var empty"      '@getenv(NIFT_DIFF_UNSET_VAR)' '<main>@content</main>' - - - - composed '' -

# --- Pagination Embed cases (migrated from NR12) ----------------------------
PG="$WORK/pg"
mkdir -p "$PG/"{.nift,content,templates,public}
cat > "$PG/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","output-dir":"public/","default-template":"templates/template.html","incremental-mode":"modified"}}
JSON
printf '<main>$[title]</main>\n@content' > "$PG/templates/template.html"
PAG_TMPL='<section>page $[paginate.current]/$[paginate.total]:[$[paginate.items]]</section>'

# run_pagination_case <name> <page_name> <items_text> <items_per_page> [tracked_extra] [bindings]
run_pagination_case() {
    local name="$1" page_name="$2" items="$3" ipp="$4" extra="${5:-}" bindings="${6:-}"
    local tracked
    if [ -n "$extra" ]; then
        tracked="{\"tracked\":[{\"name\":\"blog\",\"title\":\"Blog\",\"template\":\"templates/template.html\",\"paginate\":{\"items-per-page\":$ipp}$extra}]}"
    else
        tracked="{\"tracked\":[{\"name\":\"blog\",\"title\":\"Blog\",\"template\":\"templates/template.html\"}]}"
    fi
    printf '%s' "$tracked" > "$PG/.nift/tracked.json"
    printf '%s' "$items" > "$PG/content/blog.html"
    printf '%s' "$PAG_TMPL" > "$PG/content/blog.paginate.html"
    run_case "$name" - - "$page_name" - - - page "$bindings"
}

run_pagination_case "non-paginated -> empty pagination" blog '<p>static</p>' 1
run_pagination_case "single page paginated" blog '@item{only}@paginate' 1 ',"template":"content/blog.paginate.html"'
run_pagination_case "three pages" blog '@item{one}@item{two}@item{three}@paginate' 1 ',"template":"content/blog.paginate.html"'
run_pagination_case "four items ipp2" blog '@item{a}@item{b}@item{c}@item{d}@paginate' 2 ',"template":"content/blog.paginate.html"'
run_pagination_case "partial final page" blog '@item{A}@item{B}@item{C}@paginate' 2 ',"template":"content/blog.paginate.html"'
run_pagination_case "unicode items" blog '@item{日本語}@item{émoji 😀}@item{e\u0301 combining}@paginate' 1 ',"template":"content/blog.paginate.html"'
run_pagination_case "seven pages" blog '@item{n1}@item{n2}@item{n3}@item{n4}@item{n5}@item{n6}@item{n7}@paginate' 1 ',"template":"content/blog.paginate.html"'
run_case "unknown page controlled error" - - nope - - - page ''
# JSON binding in the pagination template.
printf '%s' '{"tracked":[{"name":"blog","title":"Blog","template":"templates/template.html","paginate":{"items-per-page":1,"template":"content/blog.paginate.html"}}]}' > "$PG/.nift/tracked.json"
printf '%s' '@item{one}@item{two}@paginate' > "$PG/content/blog.html"
printf '%s' '<section>$[site.name] page $[paginate.current]/$[paginate.total]</section>' > "$PG/content/blog.paginate.html"
run_case "json binding in paginate template" - - blog - - - page 'site=json:{"name":"Acme"}'
# Dependencies + requirements + partial in the paginate template.
printf '%s' '{"tracked":[{"name":"blog","title":"Blog","template":"templates/template.html","paginate":{"items-per-page":1,"template":"content/blog.paginate.html"}}]}' > "$PG/.nift/tracked.json"
printf '%s' '@item{one}@item{two}@paginate' > "$PG/content/blog.html"
printf '%s' '<section>@dep('"'"'app.js'"'"')@pathto('"'"'asset.js'"'"')@input('"'"'part.html'"'"')</section>' > "$PG/content/blog.paginate.html"
printf '%s' '<p>PART</p>' > "$PG/content/part.html"
run_case "deps + pathto requirement + input partial" - - blog - - - page ''

echo
echo "Embed contract: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

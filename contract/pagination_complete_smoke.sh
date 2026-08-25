#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-pagination-complete.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .nift content templates public
cat > .nift/config.json <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","incremental-mode":"modified"}}
JSON
cat > templates/template.html <<'EOF'
<main>$[title]</main>
@content
EOF

# CP8 complete pagination contract: the CLI emits page 1 under the primary
# name plus pages 2..N under canonical N>=2 names (no leading zeros), for the
# full rendered page set; non-paginated pages emit only their primary output.
cat > .nift/tracked.json <<'JSON'
{"tracked":[
 {"name":"/","title":"Home","template":"templates/template.html"},
 {"name":"blog","title":"Blog","template":"templates/template.html","paginate":{"items-per-page":1}}
]}
JSON
printf '<p>home</p>\n' > content/index.html
printf '@item{n1}@item{n2}@item{n3}@item{n4}@item{n5}@item{n6}@item{n7}@item{n8}@item{n9}@item{n10}@paginate' > content/blog.html
cat > content/blog.paginate.html <<'EOF'
<section>page $[paginate.current]/$[paginate.total]:$[paginate.items]</section>
EOF
"$NIFT_BIN" build --all >/dev/null

# Primary + pages 2..10, canonical names without leading zeros.
test -f public/blog.html || { echo 'missing primary blog.html' >&2; exit 1; }
for p in 2 3 4 5 6 7 8 9 10; do
  test -f "public/blog-$p.html" || { echo "missing pagination page blog-$p.html" >&2; exit 1; }
done
test ! -e "public/blog-01.html" || { echo 'leading-zero pagination name emitted' >&2; exit 1; }
test ! -e "public/blog-0.html" || { echo 'zero-prefixed pagination name emitted' >&2; exit 1; }
test ! -e "public/blog-11.html" || { echo 'extra pagination page emitted' >&2; exit 1; }

# Every page renders its own item window in ascending order.
grep -F '<section>page 1/10:n1</section>' public/blog.html >/dev/null
grep -F '<section>page 5/10:n5</section>' public/blog-5.html >/dev/null
grep -F '<section>page 10/10:n10</section>' public/blog-10.html >/dev/null

# Non-paginated page emits only its primary output, never a pagination set.
test -f public/index.html || { echo 'missing non-paginated output' >&2; exit 1; }
test ! -e public/index-2.html || { echo 'non-paginated page gained a pagination page' >&2; exit 1; }

# Single-page pagination (1 item) emits only the primary page.
cat > .nift/tracked.json <<'JSON'
{"tracked":[{"name":"blog","title":"Blog","template":"templates/template.html","paginate":{"items-per-page":1}}]}
JSON
printf '@item{solo}@paginate' > content/blog.html
"$NIFT_BIN" build --all >/dev/null
test -f public/blog.html || { echo 'missing single-page primary' >&2; exit 1; }
test ! -e public/blog-2.html || { echo 'single-page pagination emitted page 2' >&2; exit 1; }
grep -F 'page 1/1:solo' public/blog.html >/dev/null

echo 'Complete pagination contract smoke test passed'

#!/usr/bin/env bash
# Portability test (P7): the seven-adapter shared conformance corpus must run
# from UNRELATED temporary directory paths with no dependency on any
# developer's home-directory layout.
#
#  1. copies canonical and this regression suite under fresh temporary dirs;
#  2. builds the required canonical targets in the copy;
#  3. runs the complete corpus with every adapter configured explicitly;
#  4. asserts 36/36 plus anti-agreement, and that no adapter references the
#     original (home) location.
#
# The nift-rs adapter is the independent experimental conformance
# implementation, so its harness must be supplied explicitly via RUST_HARNESS.
#
# Usage: benchmarks/portability_test.sh [canonical-checkout]
set -euo pipefail
CANON="${1:-/home/nick/Repositories/nift/nift}"
SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -n "${RUST_HARNESS:-}" ] || { echo "RUST_HARNESS must point to a built nift-rs engine_harness" >&2; exit 2; }
[ -d "$CANON" ] || { echo "canonical checkout not found: $CANON" >&2; exit 2; }

WORK="$(mktemp -d /tmp/nift-port-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
echo "portability work dir: $WORK"

cp -r "$CANON" "$WORK/canon"
cp -r "$SUITE_DIR" "$WORK/suite"

echo "--- building canonical targets in the copy ---"
cd "$WORK/canon"
make -j2 nift >/dev/null 2>&1 || { echo "FAIL: make nift in copy"; exit 1; }
make -j2 embed >/dev/null 2>&1 || { echo "FAIL: make embed in copy"; exit 1; }
mkdir -p .build
g++ -std=c++17 -O2 -pthread -Isrc -Iinclude -Iminifypp/include -Iminifypp/src \
  tests/engine_harness.cpp src/embed/Engine.cpp src/embed/Context.cpp src/Value.cpp \
  src/FileSystem.cpp src/JsonFile.cpp src/JsonSchema.cpp src/Parser.cpp \
  src/ProjectOwnership.cpp src/ProjectInfo.cpp src/ProjectRead.cpp \
  src/ProjectState.cpp src/WatchList.cpp src/BuildProgress.cpp \
  minifypp/src/Minify.cpp -o .build/engine-harness 2>/dev/null || { echo "FAIL: engine_harness in copy"; exit 1; }
(cd bindings/go && go build -o embed-harness ./cmd/embed-harness >/dev/null 2>&1) || { echo "FAIL: go binding"; exit 1; }
(cd bindings/csharp/apps/NiftEmbedHarness && dotnet build -v q --nologo >/dev/null 2>&1) || { echo "FAIL: csharp binding"; exit 1; }
(cd bindings/node && bash build.sh >/dev/null 2>&1) || { echo "FAIL: node binding"; exit 1; }
(cd bindings/python && bash build.sh >/dev/null 2>&1) || { echo "FAIL: python binding"; exit 1; }

echo "--- running the seven-adapter corpus from the copy ---"
cd "$WORK/suite"
rm -rf embed/failures
OUT="$(env CPP_HARNESS="$WORK/canon/.build/engine-harness" \
  RUST_HARNESS="$RUST_HARNESS" \
  NIFT_C_ABI="$WORK/canon/libnift_c.so" \
  NIFT_GO_DIR="$WORK/canon/bindings/go" \
  NIFT_CSHARP_DIR="$WORK/canon/bindings/csharp" \
  NIFT_NODE_DIR="$WORK/canon/bindings/node" \
  NIFT_PYTHON_DIR="$WORK/canon/bindings/python" \
  ./embed/run-embed.py 2>&1 | tail -1)"
echo "corpus: $OUT"
echo "$OUT" | grep -q "36 passed, 0 failed" || { echo "FAIL: corpus not 36/36"; exit 1; }
SELF="$(env CPP_HARNESS="$WORK/canon/.build/engine-harness" \
  RUST_HARNESS="$RUST_HARNESS" \
  NIFT_C_ABI="$WORK/canon/libnift_c.so" \
  NIFT_GO_DIR="$WORK/canon/bindings/go" \
  NIFT_CSHARP_DIR="$WORK/canon/bindings/csharp" \
  NIFT_NODE_DIR="$WORK/canon/bindings/node" \
  NIFT_PYTHON_DIR="$WORK/canon/bindings/python" \
  ./embed/run-embed.py --self-test 2>&1 | tail -1)"
echo "self-test: $SELF"
echo "$SELF" | grep -q "negative checks passed" || { echo "FAIL: anti-agreement self-test"; exit 1; }

echo "--- asserting no home-directory dependency in adapters ---"
if grep -rq "/home/nick" "$WORK/suite/embed/adapters/"; then
  echo "FAIL: an adapter references the original home directory"; exit 1
fi

echo "PORTABILITY PASS: corpus ran from unrelated temporary paths (36/36 + self-test), adapters have no home-dir defaults"
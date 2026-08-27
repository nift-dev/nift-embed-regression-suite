#!/usr/bin/env bash
# CP18 part B collector: raw render + repeated/server workload for C++, C ABI,
# Go, C#, Node, Python. Results are evidence, not gates.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
EMBED="$(cd "$HERE/../../../nift-embed" && pwd)"
NIFT_C_ABI="${NIFT_C_ABI:-$EMBED/libnift_c.so}"
export NIFT_C_ABI
BIN="$(mktemp -d "${TMPDIR:-/tmp}/nift-cp18b.XXXXXX")"
trap 'rm -rf "$BIN"' EXIT

echo "building C++ / C ABI benches"
g++ -std=c++17 -O2 -pthread -I"$EMBED/include" -I"$EMBED/src" -I"$EMBED/minifypp/include" -I"$EMBED/minifypp/src" \
  "$HERE/cpp_bench.cpp" "$EMBED/src/Engine.cpp" "$EMBED/src/Context.cpp" "$EMBED/src/Value.cpp" \
  "$EMBED/src/FileSystem.cpp" "$EMBED/src/JsonFile.cpp" "$EMBED/src/JsonSchema.cpp" "$EMBED/src/Parser.cpp" \
  "$EMBED/src/ProjectOwnership.cpp" "$EMBED/src/ProjectInfo.cpp" "$EMBED/src/ProjectRead.cpp" \
  "$EMBED/src/ProjectState.cpp" "$EMBED/src/WatchList.cpp" "$EMBED/src/BuildProgress.cpp" \
  "$EMBED/minifypp/src/Minify.cpp" -o "$BIN/cpp_bench"
g++ -std=c++17 -O2 -pthread -I"$EMBED/include" "$HERE/cabi_bench.cpp" "$EMBED/libnift_c.a" \
  -lstdc++ -lm -pthread -o "$BIN/cabi_bench"

echo "== C++ =="
"$BIN/cpp_bench"
echo "== C ABI =="
"$BIN/cabi_bench"
echo "== Go =="
( cd "$EMBED/bindings/go" && go build -o "$BIN/bench_go" ./bench && "$BIN/bench_go" )
echo "== C# =="
( cd "$EMBED/bindings/csharp/bench" || exit 1
  NIFT_NATIVE_LIB="$NIFT_C_ABI" dotnet run -v q --nologo 2>&1 | tee "$BIN/cs.out"
  rc=${PIPESTATUS[0]}
  grep -q "cs raw=" "$BIN/cs.out" || rc=1
  [ $rc -eq 0 ] )
echo "== Node =="
( cd "$EMBED/bindings/node" && node bench/bench.js )
echo "== Python =="
( cd "$EMBED/bindings/python" && python3 bench/bench.py )

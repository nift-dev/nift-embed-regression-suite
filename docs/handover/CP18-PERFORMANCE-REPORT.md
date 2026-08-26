# CP18 — final performance campaign report

Status: 2026-08-26. Measurements are evidence, not gates; no correctness,
lifetime, diagnostic, ownership or contract semantics were changed to obtain
them. Benchmark-only changes: corrected two stale suite benchmark commands
(`info --names` -> `info --tracking` with separate args; `build --all` split),
and removed a generated Go benchmark binary from the tree.

## Part A — CLI/build: pre-Embed baseline vs current candidate

Baseline: `8a818f2` (immediate parent of CP1 `c02e88d`, i.e. the pre-Embed
Nift), built from an isolated worktree with the same `-std=c++17 -O2` settings.
Candidate: current CP18 head. Same generated projects, same workload
definitions; only the baseline's older CLI spelling was shimmed
(`build --all` -> `build-all`) to express the same semantic operation.
Interleaved/alternating runs, 3 rounds, medians.

| workload / metric        | baseline (s) | candidate (s) | ratio (cand/base) |
|--------------------------|-------------:|--------------:|------------------:|
| flat 10k full            | 0.123        | 0.112         | 0.91x             |
| flat 10k no-op           | 0.078        | 0.080         | 1.03x             |
| flat 10k single-page     | 0.094        | 0.089         | 0.94x             |
| flat 10k shared-dep      | 0.159        | 0.143         | 0.90x             |
| many-dir 10k full        | 0.148        | 0.128         | 0.87x             |
| many-dir 10k no-op       | 0.088        | 0.087         | 0.98x             |
| many-dir 10k single      | 0.093        | 0.090         | 0.97x             |
| many-dir 10k shared      | 0.186        | 0.162         | 0.87x             |
| mode modified full       | 0.129        | 0.117         | 0.91x             |
| mode modified no-op      | 0.083        | 0.082         | 0.98x             |
| mode hash full           | 0.165        | 0.153         | 0.93x             |
| mode hash no-op          | 0.093        | 0.097         | 1.04x             |
| mode hybrid full         | 0.167        | 0.153         | 0.92x             |
| mode hybrid no-op        | 0.099        | 0.098         | 0.99x             |

Conclusion: the current candidate is within 0.87-1.04x of the pre-Embed
baseline across every CLI/build workload (mostly slightly faster). The Embed
programme did not slow ordinary Nift builds down; ratios at/above 1.0 are
within run-to-run noise on a 10k-page ~0.1 s build.

## Part B — Embed/API/bindings (normalized workload)

Raw workload (all six surfaces): one long-lived Engine, engine-level
`site="nift"` binding, identical in-memory page/template
(`<p>$[site]</p>` in `<main>@content</main>`), NO request Context, 50,000
renders, one unreported warm-up round + three measured rounds, reported value
is the MEDIAN of the three measured rounds. C++/C ABI use their no-context
render path; C ABI passes a NULL context. Go/C#/Node/Python pass nil/no
context. This is an apples-to-apples raw binding-overhead comparison.

Request-loop workload (all six): 1,000 requests, each with a fresh request
Context carrying a request-level binding, render, destroy Context (includes
context lifecycle cost deliberately); same warm-up + median-of-3 scheme.

| binding | raw ns/render (median) | request-loop ms/1000 (median) | rounds |
|--------:|-----------------------:|------------------------------:|-------:|
| C++     | 1300                   | 2                             | 3      |
| C ABI   | 1368                   | 2                             | 3      |
| Go      | 2112                   | 2                             | 3      |
| C#      | 2346                   | 3                             | 3      |
| Node    | 12038                  | 11                            | 3      |
| Python  | 2786                   | 3                             | 3      |

C++/C ABI/Go/C#/Python are within ~2x of each other; Node is ~5-9x higher per
render, consistent with the async render + threadsafe-function callback bridge
(a deliberate runtime-model property, not a correctness defect). Request-loop
totals stay sub-15 ms/1000 on every surface. These are in-process request
loops, not HTTP-server measurements.

## Existing suite performance gates (now green after the stale-command fixes)

run-performance.sh: tracked-project loading 2k/10k ratio 4.56x (PASS <=8x);
full-build 1k/4k ratio 3.74x (PASS); 10k memory peaks <= 11.8 MiB (PASS
<=16 MiB); performance_10k and the CP18 workloads all complete.

## Repository hygiene

A generated `bindings/go/bench/bench_go` ELF binary committed during CP18 was
removed from Git (now gitignored); only bench source/config files are tracked.
Audit found no other tracked ELF/.so/.node/.dll/.a artifacts.

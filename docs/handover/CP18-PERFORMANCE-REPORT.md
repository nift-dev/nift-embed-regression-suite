# CP18 — final performance campaign report

Status: 2026-08-26. Measurements are evidence, not gates; no correctness,
lifetime, diagnostic, ownership or contract semantics were changed to obtain
them. Benchmark-only fixes: two stale suite benchmark commands were brought in
line with the unified CLI grammar (`info --names` -> `info --tracking` with
separate args, and `build --all` split into separate args).

## Part A — Nift CLI/build (10k pages, `benchmarks/cp18_cli_build_workload.py`)

| workload                    | full       | no-op      | single-page | shared-dep |
|-----------------------------|-----------:|-----------:|------------:|-----------:|
| flat 10k                    | 0.116 s    | 0.084 s    | 0.092 s     | 0.149 s    |
| many-directory (200 dirs)   | 0.137 s    | 0.088 s    | 0.090 s     | 0.162 s    |

Incremental-mode comparison (10k pages):

| mode     | full       | no-op      |
|----------|-----------:|-----------:|
| modified | 0.121 s    | 0.080 s    |
| hash     | 0.147 s    | 0.093 s    |
| hybrid   | 0.150 s    | 0.094 s    |

Existing suite performance gates (run-performance.sh, now green after the stale
command fixes): tracked-project loading 2k/10k ratio 4.55x (PASS, <=8x);
full-build 1k/4k ratio 3.35x (PASS); 10k memory peaks <= 11.8 MiB (PASS
<=16 MiB); performance_10k full/no-op/single/shared confirmed. 10k-page builds
complete in ~0.1 s and scale near-linearly; hash/hybrid are slightly higher
than modified (evidence, not a blocker).

## Part B — Embed/API/bindings (`benchmarks/embed/run_cp18_embed.sh`)

Consistent workload: render `<p>$[site]</p>` in `<main>@content</main>` with an
engine-default binding, 50,000 raw renders and 1,000 repeated server renders
(each with a fresh request Context where applicable).

| binding | raw ns/render | server ms/1000 |
|--------:|--------------:|---------------:|
| C++     | 1360          | 2              |
| C ABI   | 1390          | 1              |
| Go      | 2111          | 2              |
| C#      | 2549          | 4              |
| Node    | 12810         | 15             |
| Python  | 2758          | 3              |

Observations (evidence, not blockers): the C++/C ABI/Go/C#/Python surfaces are
within ~2x of each other; Node is ~5-10x higher per render, consistent with the
async render + threadsafe-function callback bridge (a deliberate runtime-model
property, not a correctness defect). Server-loop totals stay sub-20 ms/1000 on
every surface.

## No optimization performed
The campaign measures the implementation as it is; no optimization that could
change observable semantics/lifetime/diagnostics was introduced.

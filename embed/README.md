# Nift Embed contract (capability layer 2)

This regression suite is one repository with one contract corpus, but it does
**not** assume one universal executable interface. It understands capabilities:

- **Layer 1 — Nift CLI/build contract** (`contract/`, via `run-contract.sh` and
  `NIFT_BIN`): build grammar, incremental behaviour, `status`/`info`,
  `.unfinished` ownership, `build --repair`, filesystem persistence/recovery,
  `watch`, init/deployment, output ownership. This applies to the canonical
  executable. `nift-rs` deliberately does not implement the build orchestrator
  and is **not expected to participate** in this layer. This layer is
  implementation-neutral **for compatible Nift CLI implementations**, not a
  universal implementation-independent framework.
- **Layer 2 — Nift Embed contract** (`embed/`, via `run-embed.py`): rendering
  semantics — templates, content, `@input`/`@pathto`/`@json`/`@dep`/
  `@getenv`, bindings, dependencies/requirements, and the complete pagination
  set (`RenderResult.output` = page 1; `RenderResult.pagination` = pages 2..N).
  This applies to C++ Nift Embed, `nift-rs`, and future canonical binding
  surfaces. The same cases run through tiny implementation adapters.

## Cases are CASE + FROZEN EXPECTATION

Each case in `embed/cases/` is static committed data: a fixture, a neutral
request, and an **independent frozen expected result** (rendered output,
pagination page numbers + outputs, dependencies, requirements, loader keys, or
controlled error). Expectations are NOT derived from any implementation at test
time.

```text
CASE + FROZEN EXPECTATION
         |             \
   C++ adapter    nift-rs adapter
         |             |
   result ──compare── result
         |     (secondary invariant)
         v
  C++ == EXPECTATION  and  nift-rs == EXPECTATION
```

Cross-implementation equality is reported as an additional invariant, never as
the definition of correctness. Two implementations that agree on the same wrong
result fail against the frozen expectation. `./embed/run-embed.py --self-test`
proves this: a perturbed expectation fails both adapters, and an agreement-only
wrong result fails too.

## Neutral adapter protocol (JSON request -> JSON result)

A case is a neutral request; only the adapter knows the implementation
language/API:

```text
case (fixture, request)
        |
        v
neutral request (JSON, on stdin)
        |
   +----+----+
   |         |
 C++     nift-rs
adapter  adapter
   |         |
   +----+----+
        |
        v
neutral result (JSON, on stdout)
        |
        v
assert vs frozen expectation
```

Request (one JSON document on stdin):

```json
{"root": "<case root>",
 "page": "<text>"|null, "template": "<text>"|null,
 "page_name": "<name>"|null, "current_output": "<path>"|null,
 "page_path": "<path>"|null, "template_path": "<path>"|null,
 "mode": "composed"|"partial"|"page", "seam": "-"|"loader"|"env",
 "bindings": {"name": "value", ...}}
```

- `page_path`/`template_path` are resolved against `root` and override the text
  arguments when present.
- A binding value with a `json:` prefix binds a JSON value instead of a string.
- `mode` `composed` = page+template render, `partial` = partial render, `page` =
  project-aware tracked-page render (the pagination path).

Result (one JSON document on stdout):

```json
{"ok": true, "output": "...", "dependencies": [...], "requirements": [...],
 "pagination": [{"page": N, "output": "..."}, ...], "loaderKeys": [...]}
{"ok": false, "error": "..."}
```

`loaderKeys` are normalized to root-relative spellings so the result is
independent of where the case fixture is materialized. The pagination
collection is the in-memory Embed guarantee (page 1 + pages 2..N with page
numbers); file naming (`blog-2.html` etc.) belongs to layer 1 and is covered by
`contract/pagination_complete_smoke.sh`.

### Cross-platform note (retained for hardening)

The adapters strip `root + "/"` from absolute `loaderKeys` to make them
root-relative. This assumes forward-slash separators. When this corpus is run
on Windows, explicitly verify separator normalization (`C:\...\root\content\
file` → `content/file`) rather than assuming the harness always emits forward
slashes. Out of scope for the current checkpoint.

## Expectation provenance

The initial frozen expectations were migrated from the previously reviewed
NR6/NR12 behavioural contracts, whose semantics were established during earlier
checkpoints. Implementation output may be used as a migration aid, but
new/changed expectations require human/contract review; **the test runner never
regenerates or blesses expectations automatically**.

Rules for changing expectations:

```text
failing implementation
    ≠ update expected until green

changed expectation requires:
    explicit contract decision
    rationale/history
```

There is deliberately **no** `--bless` / `--update-goldens` command. If one is
ever added it must be deliberately guarded and must not silently rewrite the
contract corpus.

## Running

```bash
CPP_HARNESS=/path/to/nift-embed/.build/engine-harness \
RUST_HARNESS=/path/to/nift-rs/target/debug/examples/engine_harness \
./embed/run-embed.py
./embed/run-embed.py --self-test   # negative checks
```

Adapters: `embed/adapters/cpp-embed`, `embed/adapters/rust-embed`, and
`embed/adapters/c-abi` (the C ABI, consumed through its public C symbols by a
foreign ctypes consumer, including the loader/env seams via the C callback
API). The shared runner knows only these adapters and the neutral protocol; it
never invokes an implementation harness directly. It requires C++ == frozen
expectation, nift-rs == frozen expectation, AND C ABI == frozen expectation for
every case.

The initial corpus is **16 general + 10 pagination = 26 cases**, migrated from
the NR6/NR12 implementation differentials. The standalone NR6/NR12 scripts in
nift-rs remain as implementation-local gates; new Embed cases should be added
here, in the shared repository, rather than duplicated per implementation tree.

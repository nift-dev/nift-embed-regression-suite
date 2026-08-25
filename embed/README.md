# Nift Embed contract (capability layer 2)

This regression suite is one repository with one contract corpus, but it does
**not** assume one universal executable interface. It understands capabilities:

- **Layer 1 — Nift CLI/build contract** (`contract/`, via `run-contract.sh` and
  `NIFT_BIN`): build grammar, incremental behaviour, `status`/`info`,
  `.unfinished` ownership, `build --repair`, filesystem persistence/recovery,
  `watch`, init/deployment, output ownership. This applies to the canonical
  executable. `nift-rs` deliberately does not implement the build orchestrator
  and is **not expected to participate** in this layer.
- **Layer 2 — Nift Embed contract** (`embed/`, via `run-embed.sh`): rendering
  semantics — templates, content, `@input`/`@pathto`/`@json`/`@dep`/
  `@getenv`, bindings, dependencies/requirements, and the complete pagination
  set (`RenderResult.output` = page 1; `RenderResult.pagination` = pages 2..N).
  This applies to C++ Nift Embed, `nift-rs`, and future canonical binding
  surfaces. The same cases run through tiny implementation adapters.

The current `contract/` layer was historically described as
"implementation-independent". More precisely it is **implementation-neutral
for compatible Nift CLI implementations**: it needs a complete Nift executable
that implements the CLI/build orchestrator. It is not a framework that every
Nift implementation can run.

## Neutral adapter protocol

A case is a neutral request; only the adapter knows the implementation
language/API:

```text
case (template, content, context, operation=render)
            |
            v
   neutral request
        /        \
 C++ adapter     nift-rs adapter
        \        /
   neutral result
            |
            v
   common assertions
```

Request (adapter invocation):

```text
adapter <root> <page_text|-> <template_text|-> <page_name|->
        <current_output|-> <page_path|-> <template_path|-> <mode> [seam|-]
```

- `-` for a text argument means empty; `page_path`/`template_path` override the
  text arguments when non-`-`.
- Bindings are passed as `name=value` lines on stdin; a `json:` value prefix
  binds a JSON value instead of a string.
- `mode` is `composed` (page+template), `partial` (partial render), or `page`
  (project-aware tracked-page render, the pagination path).
- `seam` is `-` (no loader/env override), `loader` (deterministic fixture
  loader), or `env` (deterministic environment provider).

Result (one JSON line on stdout):

```text
{"ok":true,"output":"...","dependencies":[...],"requirements":[...],
 "pagination":[{"page":N,"output":"..."},...],"loaderKeys":[...]}
{"ok":false,"error":"..."}
```

Both adapters must emit byte-identical results for the same request. The
pagination collection is the in-memory Embed guarantee (page 1 + pages 2..N
with page numbers); file naming (`blog-2.html` etc.) belongs to layer 1 and is
covered by `contract/pagination_complete_smoke.sh`.

## Running

```bash
CPP_HARNESS=/path/to/nift-embed/.build/engine-harness \
RUST_HARNESS=/path/to/nift-rs/target/debug/examples/engine_harness \
./embed/run-embed.sh
```

Adaptors: `embed/adapters/cpp-embed`, `embed/adapters/rust-embed`.

The initial corpus (16 general + 9 pagination cases) was migrated from the
NR6/NR12 implementation differentials; the standalone scripts in nift-rs
remain as implementation-local gates. New Embed cases should be added here, in
the shared repository, rather than duplicated per implementation tree.

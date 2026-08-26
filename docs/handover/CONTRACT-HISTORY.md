# Contract history and institutional context

> This is a living historical companion to the repository's operational handover. The live repository remains authoritative. Maintain, correct, reorganize, or supersede this material as project evidence evolves while retaining durable rationale.

# Nift Regression Suite

## Project Context, Testing Philosophy, Development and Production-Readiness Handover

# 1. Identity

The standalone Nift regression suite is not merely a convenient collection of tests.

It is intended to act as an **implementation-independent behavioral contract** for Nift.

Conceptually:

```text
arbitrary Nift executable
        ↓
real CLI operations
        ↓
observable filesystem/output/status behavior
        ↓
PASS / FAIL
```

This independence is one of its most valuable properties.

---

# 2. Why it matters

The suite became central during Nift's architectural simplification.

It allowed us to remove/rewrite large amounts of implementation while asking:

> Did the external behavior we actually care about survive?

That makes it architectural infrastructure, not cleanup tooling.

---

# 3. Independence from implementation

Prefer black-box behavior.

Do not make the standalone suite depend on:

```text
Parser internals
C++ class names
private headers
internal data structures
```

unless there is an extraordinary reason.

A future Nift implementation in another language should theoretically be testable against much of the same suite.

---

# 4. Historical growth

The suite expanded through multiple checkpoints, historically reaching milestones around:

```text
146
211
245+
492+
```

checks/assertions/tests depending on stage and counting method.

Do not preserve those numbers as current documentation unless verified.

The important history is that coverage became progressively more adversarial.

---

# 5. Major bug families discovered

Historical regression work exposed or hardened areas including:

```text
backtick quote ambiguity
function-name lexical boundaries
CSS @media coexistence
unknown @ syntax
watch initialization
malformed watch JSON
empty tracked state
JSON escaping
JSON structural validation
CLI exit status
build-updated status propagation
missing generated outputs
directory dependencies
hash-cache refresh
path traversal
tracked/content/output collisions
sub-second mtimes
32-bit hash collision
dependency sidecar lifecycle
lexical JSON scope
control-flow interactions
```

These should inform future testing.

---

# 6. Deterministic rapid-edit testing

One particularly useful lesson came from same-second modification testing.

A timing-based test could flake.

The better test explicitly set timestamps such that:

```text
page-info mtime = second + .100...
dependency mtime = same second + .200...
```

This reliably tested sub-second behavior without hoping the filesystem scheduler cooperated.

General rule:

> Prefer controlled state over sleeps.

---

# 7. 32-bit collision testing

We deliberately constructed a hash collision rather than assuming collisions were merely theoretical.

That led to 64-bit hashing.

This is representative of the suite's intended adversarial character.

---

# 8. Test assumptions, not just features

When reviewing implementation, ask:

```text
What does this code assume can never happen?
```

Then attack it.

Examples:

```text
collection always non-empty
JSON value always string
path always stays inside project
hash never collides
mtime always distinguishes writes
dependency never changes identity
output always exists
function name always followed by whitespace
```

This methodology produced some of the highest-value Nift bugs.

---

# 9. Regression workflow

Preferred bug process:

```text
reproduce
↓
reduce
↓
make deterministic
↓
write failing black-box regression
↓
verify failure against old candidate
↓
fix implementation
↓
focused pass
↓
attack neighboring cases
↓
full suite
```

---

# 10. Test families, not isolated symptoms

If one malformed persistent JSON file crashes:

```text
watched.json
```

inspect siblings:

```text
exts.json
tracked.json
deps sidecars
configuration
```

If one path traversal exists in:

```text
track
```

inspect:

```text
cp
mv
rm
other filesystem commands
```

This is a core methodology.

---

# 11. Failure diagnostics

A large suite needs useful failure localization.

Historically test numbering and failure-focused output improved usability.

Preserve that.

A test suite that technically detects failures but makes them painful to diagnose damages development velocity.

---

# 12. Isolation

Tests should establish their own state.

Avoid:

```text
test 81 only works because test 80 created X
```

unless a deliberate lifecycle sequence is being tested.

Small temporary Nift projects are cheap.

Use them.

---

# 13. Current `$[...]` parameter-interpolation work

This should become a substantial new contract family.

Likely cases include:

```text
whole parameter:
    @input($[partial])

prefix:
    @input('partials/$[layout]')

suffix:
    @input('$[name].html')

multiple:
    @input('$[dir]/$[file]')

built-in metadata
JSON string values
loop-local values
nested lexical scope
shadowing
```

Failure/boundary cases:

```text
missing value
non-string JSON value
null
array
object
number
boolean
malformed $[
escaped syntax
quotes
parentheses
commas
$ signs in resolved values
@ signs in resolved values
empty strings
```

---

# 14. Directive integration

Test all directives whose parameter contract permits textual value interpolation.

Likely candidates requiring repository verification:

```text
@input
@dep
@pathto
@json path
```

and any others sharing the same parameter path.

Do not assume uniformity merely because they all use parentheses.

---

# 15. Non-recursive expansion

A particularly important language boundary:

If:

```text
$[x]
```

resolves to:

```text
$[y]
```

that result should normally remain data rather than triggering another evaluation pass, unless the settled implementation explicitly says otherwise.

Likewise a resolved value containing:

```text
@input(...)
```

must not suddenly become executable Nift syntax.

Test this explicitly.

---

# 16. Dynamic dependency lifecycle

This is probably the highest-risk interaction.

Example:

```text
selector = a.html
@input($[selector])
```

then selector changes to:

```text
b.html
```

The graph must evolve correctly.

Test transitions such as:

```text
A → B
B → A
A → missing
missing → A
A deleted after switching to B
B modified
selector source modified
```

as appropriate.

Dependency sidecars deserve direct attention.

---

# 17. Loops and lexical scope

Because loops and `@json` already exist, parameter interpolation must be tested inside lexical contexts.

For example conceptually:

```text
@for(item in data.items) {
    @input('partials/$[item.partial]')
}
```

Then test:

```text
nested loops
shadowing
outer variable
inner variable
scope exit
```

according to current semantics.

---

# 18. Internal versus external tests

Use both layers.

Internal C++ tests can efficiently test:

```text
parameter resolver
value lookup
scope handling
parser helper
dependency registration
```

The standalone suite tests:

```text
what the user actually experiences
```

Neither replaces the other.

---

# 19. Role in Nift production status

The regression suite is one of the principal gates for calling Nift production-ready.

The objective is **not**:

```text
reach arbitrary test count
```

It is:

```text
major public behavior protected
known historical bug families protected
new language features protected
filesystem mutations protected
incremental behavior protected
watch behavior protected
dependency/requirement behavior protected
error paths controlled
adversarial interactions exercised
```

---

# 20. Nift production-readiness goal

The current high-level goal for Nift is:

> Reach a point where the stripped/current architecture has sufficient cumulative correctness evidence, real-world dogfooding, documentation accuracy, performance stability, and release-process confidence that it can reasonably be presented as production-ready rather than merely an impressive development build.

Historically, Nift is the closest of the three products to this state.

---

# 21. Current Nift production roadmap from the suite perspective

**CURRENT — MUST BE REVISED CONTINUOUSLY**

The present direction is approximately:

```text
finish current intended language semantics
    including $[...] parameter interpolation
↓
encode those semantics in independent regression suite
↓
run existing full suite
↓
perform targeted interaction/adversarial audit
↓
run sanitizer/native validation
↓
validate incremental/watch/dependency behavior
↓
validate candidate against Nift website
↓
recheck performance
↓
resolve release-blocking defects
↓
documentation/release reconciliation
↓
production release decision
```

This is not a frozen checklist.

If parameter interpolation exposes a deeper dependency-model weakness, for example, the roadmap must expand accordingly.

---

# 22. Production does not end testing

After production status:

```text
every bug gets regression where appropriate
new features expand contract
new bug families trigger adversarial audits
new platforms expand validation
performance regressions remain monitored
```

Production means confidence in the development/release process, not that testing is finished.

---

# 23. Roadmap maintenance rule

Put this in durable suite documentation:

> The production-readiness and ongoing quality roadmap is a living artifact. At each significant development checkpoint, review new failures, new coverage, unresolved risks, architecture changes, platform evidence and real-world behavior. Reorder, expand, reduce or replace roadmap items based on evidence. A historical roadmap must never override newly discovered project reality.

---

# 24. Canonical ownership

Codex should determine the relationship between:

```text
Nift-local tests
standalone regression suite
```

and document where new black-box regressions originate.

Do not allow silent divergence.

---

# 25. Definition of success

A strong suite is one where future Codex can make a deep Nift refactor and receive a credible answer to:

> Did I preserve Nift?

That is the long-term objective.

---

---

## CLI unification reconciliation (2026-08-25)

The suite was reconciled with the unified CLI grammar (`nift build [names...]
[--all|--auto|--repair]`, `nift info [names...] [--all|--watching|--tracking|
--names]`), which removed the historical spellings `build-all`, `build-updated`,
`build-names`, `build-auto`, `info-all`, `info-watching`, `info-tracking`,
`info-names`. The removed spellings now fail with a replacement hint and perform
no action, so the suite migrated every invocation to the unified form:

```text
build-all      -> build --all
build-updated  -> build
build-names X  -> build X
build-auto     -> build --auto
info-all       -> info --all
info-watching  -> info --watching
info-tracking  -> info --tracking
info-names     -> info --names
```

Semantic adjustments recorded during the migration:

- The old "build-names -p with no names must fail" check is obsolete: under the
  unified grammar `build -p` (explain + incremental) is valid. It was replaced
  with the mutually-exclusive-mode checks (`build --all <name>` and
  `build --all --repair` must fail).
- The `status` command now rejects unknown options and stray positional
  arguments (consistent with build/info); the suite's status checks were
  retained and now pass against the corrected implementation.
- Failed mutating builds leave the durable `.unfinished` ownership marker
  (CP2/CP3); a subsequent build is refused until `build --repair` reconstructs
  and clears it. The pagination and persistence/concurrency failure modules now
  exercise that recovery path explicitly where they intentionally induce a
  failure after a mutation.
- Recovery of crash-leftover `.nift-tmp-*` files was restored on the direct
  (non-temp) build-output write path: the direct-write optimization (CP3) had
  dropped the stale-temp recovery scan, so the filesystem-recovery module
  failed. `write_direct_file` now performs the once-per-epoch-per-parent
  recovery scan, and the module passes.

## New focused modules (2026-08-25)

- `contract/unified_cli_smoke.sh` -- unified grammar, mutually-exclusive modes,
  unknown-option rejection, removed-spelling replacement hints, info JSON
  modes, and clean-project `build --repair`.
- `contract/pagination_complete_smoke.sh` -- CP8 complete pagination contract:
  primary page + pages 2..N under canonical N>=2 names with no leading zeros,
  per-page item windows ascending, non-paginated pages emitting only their
  primary output, and single-page pagination emitting no page 2.
## Capability-layer architecture + direct-write recovery performance (2026-08-25)

- Corrected the terminology: the `contract/` layer is implementation-neutral
  **for compatible Nift CLI implementations**, not a universal
  implementation-independent framework. `nift-rs` deliberately does not
  implement the CLI/build orchestrator and cannot run that layer.
- Introduced capability layer 2: `embed/` — the shared Nift Embed contract.
  Neutral adapter protocol (JSON request/result; see `embed/README.md`) with
  C++ and nift-rs adapters. Migrated the NR6 general corpus (16 cases) and
  NR12 pagination corpus (10 cases) into `embed/run-embed.sh`; all 26 cases
  pass byte-identically against both adapters. The standalone NR6/NR12 scripts
  in nift-rs remain as implementation-local gates, with a migration plan to
  make the shared corpus canonical.
- Performance sanity for the restored direct-write stale-temp recovery
  (nift-embed adc3ac3, 10k interleaved methodology): the initial
  `directory_iterator` scan added ~13 ms to a flat 10k forced full build and
  ~8 ms to a 2000-distinct-dir build. Replacing the scan with raw
  `readdir`/`FindFirstFile` enumeration (allocation-free per entry) reduced
  this to ~9 ms flat (~+8.8%, at/near the readdir floor) and ~3 ms
  many-dir. No-op builds are unchanged (no writes => no scans). The recovery
  contract is preserved; the recovery-epoch guard still bounds scans to one
  per distinct parent per epoch.
## No-global-config / outside-project contract (2026-08-25, pre-CP10)

Removed the historical global-config fallback. There is no global Nift
configuration: a directory is a Nift project root only where the relevant
project state exists (`.nift/config.json` AND `.nift/tracked.json`). The CLI's
upward project walk previously accepted any directory with `.nift/config.json`,
so the historical `~/.nift` global config dir (config.json with old keys such
as `lolcat-default`, no tracked.json) was mistaken for a project root whenever
a command ran under the home directory, leaking an "unknown config key
'lolcat-default'" diagnostic. Both the C++ CLI and the C++/Rust embed
project-open paths now gate on the two state files BEFORE any parsing:

```text
project absent                 -> "not a Nift project" (NotProject)
project config malformed       -> "invalid project config (...)"
project config unknown key     -> "unknown config key '...'"
project tracking malformed     -> "invalid tracked.json (...)"
```

`contract/not_a_project_smoke.sh` covers build/build --all/--repair/status/
info --all/track/rm outside a project (non-zero + canonical diagnostic + zero
filesystem mutation), a hostile `~/.nift/config.json` (lolcat keys) ignored,
and the malformed/unknown-key distinctions. Rust `nr14_project_discovery.rs`
covers the equivalent project-open semantics with a `NotProject` error kind
(corpus class `not-a-project`).

### Frozen two-file project-identity rule (2026-08-25)

A Nift project is identified by the presence of BOTH `.nift/config.json` and
`.nift/tracked.json`. A directory containing only one of those files is not a
complete Nift project and is classified as `NotProject` ("not a Nift project").

This rule is deliberate, not incidental. Lifecycle verification:
- `nift init` creates both files in the same project; there is no init phase
  that leaves config.json present and tracked.json absent.
- `tracked.json` is written atomically (temp+rename via `filesystem::write_file`,
  the authoritative-state write); an interrupted write leaves either the old or
  the new file, never a missing one, so crash/recovery cannot produce a
  config-only recoverable project.
- `build --repair` operates on an already-discovered project (both files); a
  config-only directory is not a project and is not a repair target.
- The useful consequence is the historical `~/.nift/config.json` global config
  dir (no tracked.json) can never be mistaken for a project.

Do not change this rule unless a lifecycle change makes a config-present /
tracked-absent state a legitimate recovery target.

## Embed host-resource contract: value / absent / error (2026-08-25, CP10.2)

The Embed loader/environment provider contract is now `Found(value)` /
`NotFound` / `Error(diagnostic)` in C++, nift-rs and the C ABI. A host error
travels through the render computation itself (including the pagination
worker threads) and fails the RenderResult with the diagnostic; `NotFound`
remains the ordinary unset/missing case. The C ABI's previous thread_local
callback-error side channel was removed - there is no ABI-only failure
semantics; the engine models the contract directly. C++ `tests/host_seam.cpp`,
Rust `nr15_host_seam.rs` and the C ABI adversarial battery cover standalone
and paginated host failures, not-found vs present-empty, and deterministic
concurrent attribution.

## Pagination separator + host-error message preservation (2026-08-25, CP10.3)

`HostResult::Error` is never "optional absence": the pagination separator
distinguishes NotFound (no separator) from Error (render fails with the host
diagnostic) in both C++ and Rust. The shared corpus gained three frozen
host-error cases (env standalone, env pagination, loader standalone) with
`env-error`/`loader-error` adapter seams; total 29/29 across C++ API, nift-rs
and C ABI. The pagination-separator loader-error path is covered by parser-level
custom-host tests in both implementations (the project render reads the
separator from the project snapshot/filesystem, not the engine loader seam, so
it is not expressible through the neutral corpus).

## CP10.4 (2026-08-25)

Rust pagination-template host errors are now preserved (NotFound keeps the
canonical diagnostic, host Error keeps its own message), matching C++. The
final semantic host-read audit found no remaining Error suppression in either
implementation.

## CP11 (2026-08-25)

The Go production binding (`nift-embed/bindings/go`) participates in the shared
implementation-neutral Embed corpus as a fourth adapter (`embed/adapters/go-embed`):
the frozen 29 cases now require C++ API == expectation, nift-rs == expectation,
C ABI == expectation AND Go == expectation, with the negative anti-agreement
self-test passing across all four.

## Multi-name `track` incident — forensic classification (2026-08-25)

Investigation of an AI-agent report that a "malformed multi-name tracking
command left an unfinished-build marker" on the Warden/Cortex sites.

- The unified CLI grammar is single-name: `track <name> [title] [template]`.
  There is no multi-name form. `track a b` is VALID and tracks "a" with title
  "b"; `track a b c d` / five names error "track received too many arguments".
- `track` never acquires the ownership epoch and can never create `.unfinished`
  (unlike builds and the `untrack`/`rm` mutators). Every malformed form fails
  before any mutation: tracked.json unchanged, no content file, no `.unfinished`.
- `.unfinished` + `build --repair` is the recovery path ONLY for a build that
  mutated generated state and then failed (reproduced: force-rebuild where one
  page succeeds and another fails). Ordinary builds refuse until repair.
- An AI agent reported that a malformed tracking command had left `.unfinished`,
  but the original state was not independently captured. Investigation found
  that `track` has no path that creates `.unfinished` and no tested malformed
  tracking invocation produced one. The original report is therefore unverified
  and its claimed cause is disproven. Classification F (cannot be reproduced;
  narration unsupported). Whether `.unfinished` even existed at the time (let
  alone who created it) was not established. No Nift fix is required for the
  reported incident.
- Minor observation (not the incident): `track` writes the content file before
  `save_tracking` commits, so a save failure (e.g. unwritable `.nift` dir)
  leaves an orphaned untracked content file. Candidate small improvement under
  review (persist tracking before, or atomically with, content creation); not
  applied in this checkpoint.

`contract/track_smoke.sh` freezes the invariants: malformed/invalid track
invocations fail with zero mutation and no `.unfinished`; the single-name
grammar (`track a b` = name a, title b); re-track of a tracked page is a clean
error; and `.unfinished` + `build --repair` is required only after a
mutated-then-failed build.

## Track ordering decision (2026-08-25)

`track` now persists tracking state FIRST and then creates the missing content
file (order B), replacing the previous content-before-save order (order A).
Rationale: tracked.json is the authoritative project model, so the least-bad
recoverable failure state is "tracked entry with a missing content file" (the
next build reports precisely "content file does not exist", and recovery uses
the standard build --repair path) rather than an orphan content file Nift has no
knowledge of. No rollback or cross-filesystem transaction machinery is added.
`track` still never participates in the build ownership epoch. `contract/track_smoke.sh`
covers the B-state: failed content creation leaves truthful tracked metadata, no
.unfinished from track itself, and the missing-content recovery path.

## C ABI callback diagnostic transport (2026-08-25, CP11.1)

The shared corpus host-error expectations moved from the generic
"host callback failed" to the exact supplied diagnostic: a hard callback status
with a non-empty `out` preserves that `out` as the failed RenderResult
diagnostic (empty `out` falls back to the generic message). All four adapters
agree on `host exploded` / `getenv: host exploded` for the three host-error
cases; corpus total remains 29/29.

## CP12 — contract strengthening (2026-08-25)

Expanded the implementation-neutral corpus and CLI contract layer.

New shared Embed cases (32 total):
- `embed-deps-dedupe` — repeated @input of the same partial produces ONE
  deduplicated dependency (rendered content repeats; the dependency set does
  not).
- `embed-json-value-types` — JSON int/float/bool bindings render exactly
  ("1|1.5|true").
- `embed-missing-input-error` — a missing @input partial is a controlled
  "@input path does not exist" error, distinct from a host failure.

New CLI contract module (27 total): `contract/config_validation_smoke.sh` —
malformed config.json -> "invalid project config" (never "not a project");
unknown config key -> "unknown config key"; malformed tracked.json -> "invalid
tracked.json"; valid project builds.

Cross-adapter consistency fixes found by the new cases:
- The Go harness no longer emits loaderKeys on error results (the other three
  adapters omit them).

Ambiguity STOP (per CP12 instruction, awaiting review): a @json read of a
MALFORMED file produces a controlled JSON parse error whose diagnostic TEXT
differs between implementations — C++/Go/C ABI say "expected quoted object key
at line 1, column 2", Rust (jsonic-rs) says "failed to parse JSON (expected
'\"' at position 1 (found 'n'))". Recommendation: the Embed contract requires a
controlled JSON parse error (semantic family), not byte-identical diagnostic
text (the parser message is an implementation detail; host-error diagnostics
remain exact per CP11.1). Recommended corpus mechanism: an error-family
(substring/class) expectation mode for implementation-detail diagnostics.
Not added yet — awaiting review. (Gap noted: context-over-engine binding
precedence is genuine Embed semantics but needs a neutral-protocol extension;
deferred.)

## CP12.1 — contract strengthenings (2026-08-26, per CP12 review)

- Expectation mechanism: corpus gained a deliberately narrow `error_prefix`
  mode (exact `error` stays the default; specifying both is an invalid case).
  Used ONLY for implementation-detail diagnostics (JSON parser wording);
  host-error diagnostics remain exact per CP11.1. Added
  `embed-malformed-json-error` (malformed @json content -> controlled
  "json: failed to parse content/bad.json (...)" failure; exact wording is NOT
  contract; the frozen prefix IS).
- Neutral protocol: requests may now carry `context_bindings` (per-render
  Context) alongside `bindings` (Engine defaults). All four adapters/harnesses
  updated. Added `embed-context-over-engine`: same name on both -> Context wins
  ("context"). Frozen for C# to implement.
- Binding-setup failures: rule frozen — a binding/setup operation rejected by
  the underlying API must be surfaced as a controlled setup failure
  ({"ok":false,"error":"invalid binding name: <name>"}), never silently
  ignored. All four adapters audited and fixed (c-abi previously returned a
  differing message; harnesses previously ignored setter failures). Added
  `embed-invalid-engine-binding` and `embed-invalid-context-binding` (name
  "9bad" rejected identically by all four APIs -> exact expectation).
- Corpus now 36 shared cases (was 32); all four adapters agree 36/36 + negative
  self-test; CLI/build unchanged at 27 modules.

## CP13 — C# production binding (2026-08-26)

- New C# binding at `nift-embed/bindings/csharp`: `Nift` library (net10.0),
  a thin P/Invoke adapter over the frozen C ABI. No Nift semantics are
  reimplemented. Surface: Engine, Context, string/int/number/bool/JSON
  bindings, composed/partial/page renders, pagination, dependencies,
  requirements, loader + environment providers, Found/NotFound/Error(diagnostic),
  invalid-binding/setup failures, malformed-JSON failure family.
- Lifetime design: SafeHandle-based deterministic disposal (Engine/Context/
  result handles), GCHandle-passed user_data, delegates rooted as strong fields
  for the engine lifetime, per-thread unmanaged callback scratch (safe because
  the C ABI copies callback `out` synchronously after the callback returns -
  c_abi.cpp callback_result; NOT global free-on-next-callback).
- Fifth shared-corpus adapter `adapters/cs-embed` + harness
  `apps/NiftEmbedHarness`: Embed corpus now 36/36 x5 (C++, nift-rs, C ABI, Go,
  C#) + negative anti-agreement self-test.
- C# binding tests: 20 focused tests (bindings, precedence, pagination,
  concurrency x64, delegate rooting under GC, repeated create/dispose x200,
  disposal safety) - all green.
- ASP.NET Core dogfood `apps/NiftAspDogfood` (dotnet SDK 10.0.111 + ASP.NET
  Core runtime 10.0.11, no separate runtime package needed): long-lived
  Engine, repeated + concurrent requests (24/24 external + 32/request
  internal), request-specific Context, Engine-default + Context precedence,
  project page/pagination render, loader-seam render, environment callback,
  Error(diagnostic) -> 500 with verbatim diagnostic, malformed-JSON family,
  deterministic disposal on shutdown. smoke.sh: PASS.

## CP14 — Node/JavaScript production binding (2026-08-26)

- New Node binding at `nift-embed/bindings/node`: idiomatic JS API (Engine,
  Context) over an N-API addon (raw N-API, no npm dependency) which is a thin
  adapter over the frozen C ABI. No Nift semantics reimplemented. Surface:
  engine defaults / context bindings / precedence, string/int/number/bool/JSON,
  composed / {path}|{text} source / partial / page-pagination renders,
  dependencies, requirements, loader + environment providers, Found/NotFound/
  Error(diagnostic) with exact host diagnostics, malformed-JSON error_prefix
  family, invalid binding/setup failures, ABI compatibility, lifetime/disposal.
- Threading model (deliberate): renders are ASYNC via napi_async_work on a
  libuv worker thread so the JS event loop stays free to service the
  synchronous-from-C++ host callbacks through napi_threadsafe_function + a
  condition variable. User loader/env callbacks run on the JS thread and must
  return synchronously. Per-native-thread callback scratch buffers (provably
  safe: the C ABI copies out synchronously after the callback returns; not the
  CP11-unsafe cross-thread free-on-next-callback). See
  docs/handover/CP14-NODE-DESIGN.md.
- Sixth shared-corpus adapter `adapters/js-embed` + harness
  `test/embed-harness.js`: Embed corpus now 36/36 x6 (C++, nift-rs, C ABI, Go,
  C#, Node) + negative anti-agreement self-test.
- Node focused tests: 18 (bindings, precedence, invalid bindings, malformed
  JSON family, loader/env Found/NotFound/Error, page/pagination, partial,
  64-way concurrent renders with callbacks, pagination callbacks from C++
  worker threads, callbacks surviving GC, repeated create/dispose, GC pressure,
  disposed-object rejection, quiescent shutdown, exception containment,
  long-lived engine).
- Real HTTP dogfood `app/server.js` + `app/smoke.sh` (built-in node:http):
  long-lived Engine, repeated + concurrent requests (24/24 external + 32
  in-request), request Context, engine defaults + precedence, loader seam,
  environment callback, Error(diagnostic) -> 500 verbatim, malformed-JSON
  family, pagination, graceful disposal. smoke.sh: PASS.
- API contract note: because renders are async, an Engine/Context must not be
  closed while its render is in flight (the dogfood surfaced this twice and was
  corrected to await before closing).

## CP14 lifetime repair (2026-08-26, per CP14 review)

Review found a native lifetime hole: explicit close() freed the Engine/Context
while an async render was in flight (UAF), because BeginRender stored raw
native pointers and napi_refs only prevented GC, not explicit disposal.

Fix (enforced binding invariant, not a caller obligation):
- BeginRender stores the Engine/Context WRAPS and increments a per-wrapper
  render_count; RenderComplete decrements it.
- close() marks disposed immediately (new operations throw "has been
  disposed") and destroys the native resource immediately when no render is in
  flight, otherwise defers destruction to the last RenderComplete.
- TSFNs survive while any render is in flight, so in-flight loader/env
  callbacks remain serviceable after close().
- GC finalizer destroys only when render_count == 0 and is idempotent; the
  JS wrapper's explicit close remains idempotent.

New adversarial lifetime tests (Node suite 18 -> 24): close engine during
render, close context during render, close engine during a render using
loader/env callbacks (tsfns survive), close engine + contexts during 24
concurrent renders, repeated/idempotent close, GC pressure after
close-during-render. All green; corpus still 36/36 x6 + anti-agreement.

## CP15 — Python production binding (2026-08-26)

- New Python binding at `nift-embed/bindings/python`: idiomatic Python API
  (Engine, Context, RenderResult) over a CPython C extension (no pip
  dependencies at runtime) which is a thin adapter over the frozen C ABI. No
  Nift semantics reimplemented. Surface: engine defaults / context bindings /
  precedence, string/int/number/bool/JSON, composed / {path}|{text} source /
  partial / page-pagination renders, dependencies, requirements, loader +
  environment providers, Found/NotFound/Error(diagnostic) exact, malformed-JSON
  error_prefix family, invalid binding/setup failures, ABI compatibility,
  lifetime/disposal.
- GIL/threading model (deliberate): renders are SYNCHRONOUS with the GIL
  released (Py_BEGIN_ALLOW_THREADS) around the C ABI call; loader/env callbacks
  from C++ pagination worker threads re-acquire the GIL via PyGILState_Ensure.
  Per-native-thread callback scratch buffers (provably safe: the C ABI copies
  out synchronously after the callback returns; not the CP11-unsafe cross-thread
  free-on-next-callback). See docs/handover/CP15-PYTHON-DESIGN.md.
- Lifetime invariant (same as Node): a render holds a strong reference to the
  Engine/Context; close() rejects new operations immediately and defers native
  destruction until the last in-flight render quiesces.
- Seventh shared-corpus adapter `adapters/py-embed` + harness
  `tests/embed_harness.py`: Embed corpus now 36/36 x7 (C++, nift-rs, C ABI, Go,
  C#, Node, Python) + negative anti-agreement self-test.
- Python focused tests: 20 (bindings, precedence, invalid bindings, malformed
  JSON family, loader/env Found/NotFound/Error, page/pagination, partial, path
  sources, 64-way concurrent renders with callbacks, pagination callbacks from
  C++ worker threads, close-during-render lifetime adversarial cases, repeated
  close, GC pressure, disposed-use rejection, exception containment, long-lived
  engine).
- Real WSGI dogfood `app/app.py` + `app/smoke.sh` (stdlib wsgiref): long-lived
  Engine, repeated + concurrent requests (24/24 external + 32 in-request
  threads), request Context, engine defaults + precedence, loader seam,
  environment callback, Error(diagnostic) -> 500 verbatim, malformed-JSON
  family, pagination, graceful disposal. smoke.sh: PASS.

This is the final planned initial production binding; after Python we stop
adding languages by default (per the CP13 product-scope decision).

## CP15 hardening (2026-08-26, per CP15 review)

- Python close-during-render lifetime tests made DETERMINISTIC: the loader/
  environment callback is a rendezvous (it fires only after the render entered
  native execution and incremented render_count), so the test provably calls
  close() during an in-flight native render rather than relying on scheduler
  luck. Deterministic tests for: engine close during render, context close
  during render, engine close while loader AND environment callback
  infrastructure is still required, and close under 24 concurrent renders with
  an explicit in-flight latch. Repeated-close and GC-pressure remain stress.
  Python suite 20 -> 21, all green.
- CI investigation: Checkpoint-10 run 32926885753 (triggered by the CP15 push,
  which matched its path filter via test-integrity.yml) failed at
  test-ownership-concurrency step 8 ("8 concurrent builds: >=1 succeeds and
  refusals are live-lock" + "8 no marker left"). Reproduced locally (1-in-20):
  a genuine ProjectOwnership acquire race - the marker is created with
  O_CREAT|O_EXCL and flocked in a separate syscall, so a concurrent process can
  open and flock the freshly-created marker first, classify it as Stale
  ("unfinished build detected") and refuse, while the creator then fails to
  flock (Live) and refuses too: BOTH builds refuse and the marker remains.
  Fixed in ProjectOwnership::acquire: (1) the creator, on flock-failure after
  creating its own fresh marker, briefly retries reopening+flocking (a genuine
  concurrent build would have made exclusive_create fail first, so this only
  runs in the race); (2) a stale-acquirer releases the lock and briefly watches
  for a live owner before reporting Stale, so the race loser reports Live
  instead of a misleading "unfinished build" message. Stress: ownership
  concurrency 20/20, race-pattern hammer 40/40 (previously ~1/14 reproduced).
  Zero-mutation, repair-campaign, conformance 9/9, host seam, C ABI x2 all
  green. No test weakened.

## CP15 hardening round 2 (2026-08-26, per CP15 review)

- test_gc_pressure_after_close_during_render made deterministic (loader
  callback rendezvous; close() + gc.collect() while the native render is
  provably in-flight).
- Ownership race fix replaced with a protocol-correct ownership GATE:
  ProjectOwnership::acquire() takes a blocking advisory lock on
  .nift/.ownership-gate and holds it across the marker create+lock critical
  section, so a fresh marker is never observable unlocked (mutual exclusion,
  no timing heuristics). The prior asymmetric retry windows (creator ~100ms
  vs stale-acquirer ~5ms) were reviewed and rejected. Evidence: ownership
  concurrency 25/25, race hammer 80x12 zero repro (pre-fix ~1/14). See
  docs/handover/CP2-OWNERSHIP-GATE.md.

## CP16 — full historical + expanded regression campaign (2026-08-26)

Scope (from EMBED-ROADMAP.md): run the complete campaign now that the
production binding set is present — historical Nift regression suite,
ruthless/focused suites, and the shared Embed corpus across all seven
adapters. Divergence becomes an explicit contract decision, not an adapter
exception. No new scope added.

Results:
- Legacy historical suite (legacy/scripts/run-tests.sh): PASS, 576
  assertions/tests (incl. the ruthless adversarial extension, 192 checks).
- Ruthless adversarial (legacy/scripts/ruthless-adversarial.sh): PASS, 192
  checks.
- Full nift-embed make correctness sweep: all test-* targets green except two
  environment-dependent dev targets (test-jsonic-sync requires an external
  JSONIC_DIR checkout; test-guarantee-registry requires sibling regression/
  website repos — its CI variant test-guarantee-registry-ci is the gate and
  passes). Excluded as environment limitations, not product failures.
- Shared Embed corpus: 36/36 x7 adapters + negative anti-agreement self-test.
- CLI/build contracts: 27/27.
- nift-rs: 221/221; NR6 PASS; NR12 10/10.
- Binding gates: Go test + -race, C# 20/20, Node 24/24, Python 21/21; Python
  WSGI + Node HTTP dogfoods PASS.

Divergences found and resolved as explicit contract decisions (both were
stale TESTS, not product regressions):
- tests/project_host.cpp did not compile: it expected read_shared_source to
  return const std::string*, but the frozen RenderHost contract returns
  HostSource{status, content, error} (the loader/host-resource contract). The
  test now consumes the HostSource. (It was not compiled by any CI workflow.)
- tests/persistence_concurrency_failure_smoke.sh used plain `build` to recover
  after a failed epoch; the frozen CP3 marker-retention contract requires
  `build --repair` (an ordinary build refuses on a stale marker). Recovery
  steps now use `build --repair`. (It was not run by any CI workflow.)

No product behavior changed during CP16.

## CP17 — sanitizer / memory / platform campaign (2026-08-26)

Scope (from EMBED-ROADMAP.md): ASan/UBSan, TSan where applicable, race
detectors, native/FFI lifetime stress, repeated engine construction/
destruction, concurrent renders, malformed foreign inputs, callback
failure/panic/exception boundaries, Windows/macOS/Linux; plus the retained
items (Go callback-output buffer lifetime bound, loaderKeys separator
normalization, write_file_atomic-style helper audit, cross-platform binding
behaviour).

Results:
- ASan/UBSan: test-sanitize + test-pagination-sanitize PASS (leak detection on).
- TSan: test-pagination-tsan, test-engine-concurrency-tsan, test-engine-
  reload-tsan PASS.
- Go callback-output buffer lifetime bound (FIXED): the Go binding retained
  every callback C buffer until Engine.Close() (unbounded over engine
  lifetime). Now each render increments a per-engine renderCount and the
  buffers are reclaimed when the last in-flight render completes (render-
  active lifetime: the C ABI copies each callback `out` synchronously, and no
  callback can run while no render is in flight, so freeing at renderCount==0
  is provably safe). Bounded by peak concurrent render activity; NOT
  free-on-next-callback. New tests assert 0 buffers retained after each of
  200 sequential renders and after 16x100 concurrent renders (go test -race).
- loaderKeys separator normalization (FIXED across all five adapters): the
  engine reports loader keys with forward slashes on every platform, but a
  Windows corpus root is backslash-separated; the adapters trimmed only the
  root's trailing separators without normalizing, so a Windows prefix would
  never match. Each adapter (c-abi, go, cs, js, py) now normalizes '\' -> '/'
  on both the root prefix and every key. Go unit tests + direct checks; corpus
  remains 36/36.
- write_file_atomic-style helper audit: temp names are PID+counter-unique;
  write_file/write_readonly_file use temp sibling + atomic rename
  (fs::rename / MoveFileExW REPLACE_EXISTING|WRITE_THROUGH); write_direct_file
  is the accepted CP3 direct-write path with mode preservation and stale-temp
  recovery. filesystem-boundary (BH9), repair-campaign, pagination-ordering,
  recovery-epoch all PASS.
- Callback exception boundaries: Go recovers panics (existing test); Node and
  Python contribute exception messages (existing tests); C# was MISSING
  containment - a throwing user delegate could unwind through the native
  callback into C++ (undefined behaviour). Fixed: OnLoader/OnEnvironment now
  contain and surface the exception message as the exact host diagnostic; new
  test (C# suite 20 -> 21).
- Cross-platform binding behaviour: audit recorded in
  docs/handover/CP17-CROSS-PLATFORM-AUDIT.md. The C ABI is 3-OS verified by
  Checkpoint-10; the bindings are Linux-built/tested; per-OS library naming /
  header discovery / extension suffix for C#/Node/Python remains for the
  packaging/release phase.

## CP17 round 2 (2026-08-26, per CP17 review)

Review found the round-1 Go callback-buffer reclamation raced with new-render
admission (an atomic counter is not an epoch boundary), and that Go
Engine/Context Close and C# Dispose freed native state during an in-flight
render. Repaired as enforced synchronization invariants:
- Go: an Engine.lifecycle mutex couples render admission with quiescent
  reclamation (no new render between zero-transition and buffer free); Close
  is logical and defers native destruction until the last render quiesces;
  Context likewise; new operations rejected via alive()/beginRender. Lock
  order lifecycle -> callbackSet.mu (no inversion). Deterministic tests:
  close-during-render via loader-callback rendezvous (engine + context), and a
  test-only hook forcing the reclamation-vs-admission window. go test -race
  green.
- C#: Engine/Context Dispose is logical with deferred destruction until the
  last in-flight render quiesces (entered-flag try/finally so a rejected
  EnterRender never decrements); deterministic dispose-during-render tests via
  loader-callback rendezvous. C# suite 21 -> 23.

## CP17 round 3 (2026-08-26, per CP17 review)

Review found the lifetime admission was enforced only around renders; non-render
native operations (setters, queries, Reload, loader/env install) still checked
disposed then called native with Close able to destroy in between. Repaired as
a general native-handle admission protocol in Go and C#: every public
native-touching method now holds the Engine/Context lifecycle mutex across the
native call and rejects a disposed object inside that critical section, so
Close/Dispose can never free the handle mid-call (invariant: admitted operation
keeps its native resource alive until it returns; Close wins admission -> the
operation is rejected before native use). Deterministic adversarial tests via
a test-only admission hook forcing the window: Go (engine setter, context
setter, query vs Close) and C# (engine setter, query, context setter vs
Dispose). Go test -race and C# suite (23 -> 26) green.

## CP17 round 4 (2026-08-26, per CP17 review)

Review found Go SetLoader / SetEnvironmentProvider accessed the callback
registry and read e.id OUTSIDE the lifecycle mutex: after Close (e.id==0,
registry entry deleted) they could nil-dereference before the closed check, and
the e.id read raced Close. Both methods now begin with the lifecycle admission
(lock, closed check, test hook, e.id read, registry lookup with an explicit
!ok guard, callback-state mutation, native install) as one protected
operation. Regression tests: provider setters after Close do not panic; a
provider install races Close deterministically (admitted under lifecycle, Close
blocked until the install completes). Final audit of every e.engine / e.id /
callbackRegistry / c.ctx access confirms each is lifecycle-gated, render-count
protected, or construction/destruction-only. Go test -race green.

## CP17 round 5 (2026-08-26, per CP17 review)

Final evidence issue: one seven-adapter corpus run produced "35 passed, 1
failed" during the round-4 reverification, but the failing case/adapter was not
captured (the invocation was piped through `tail -1`, discarding the runner's
per-case FAIL detail). Investigation:
- 58 consecutive full seven-adapter corpus runs (standard, fresh C# harness
  rebuild before each, and under background CPU load) all 36/36, full output
  preserved, immediate stop-and-capture on any failure.
- Focused stress of the 19 callback/pagination cases (loader/env seams and
  pagination worker callbacks - the most timing-sensitive surface) x 7 adapters
  x 30 rounds = 3990 adapter invocations: no crashes, no non-JSON output.
- No reproducible defect. The one-offs have occurred three times across the
  programme, each on the FIRST corpus run immediately after heavy parallel
  builds (make -j2 + go/cargo/dotnet/node/python), each never reproduced; the
  most consistent (but not directly observed) explanation is a one-off
  process-level transient under that build load. No test-harness defect was
  found (the runner already reports per-case adapter results + stderr; no blind
  retries were added). Future failures will be investigated with full output
  preserved.
- Stale Go comment cleanup: callbackSet.bufs/putC now describe the
  lifecycle-gated quiescent-render-epoch reclamation (not "retained until
  Engine.Close").

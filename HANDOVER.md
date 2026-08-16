# Nift regression-suite handover

This repository is the canonical implementation-independent behavioral contract
for the Nift v4 family as currently exercised by rewrite checkpoint 1.0.42. It is
not an implementation test directory extracted from the C++ tree.

## Authority and purpose

The runner accepts an arbitrary Nift executable and observes CLI status,
filesystem state, generated output, project metadata, incrementality, and failure
behavior. It must not include private Nift headers or depend on C++ class layout.
A future independent implementation should be able to pass by implementing the
same observable contract.

Current suite behavior and runner files are authoritative. Nift source/tests are
authoritative for implementation internals. Nift's core handover owns product
history; this repository owns black-box contract methodology.

## Layout

- `run-contract.sh`: resolves the candidate executable, creates disposable state,
  and runs all correctness modules.
- `legacy/`: accumulated historical and ruthless black-box suite; copied before
  execution because it intentionally mutates its fixture.
- `contract/`: focused executable-level modules previously mirrored near Nift.
- `benchmarks/`: optional performance/scaling/RSS guards, intentionally separate
  from correctness.
- `docs/handover/TESTING.md`: detailed contract-development guidance and history.
- `docs/handover/ROADMAP.md`: living suite/production-gate priorities.
- `docs/handover/CONTRACT-HISTORY.md`: detailed contract history and
  institutional context, including failure families, parameter
  interpolation coverage, and production-readiness responsibilities.

The README currently records 578 historical assertions plus focused contract
modules. Treat counts as checkpoint facts, not the quality claim.

## Running

```bash
NIFT_BIN=/absolute/path/to/nift ./run-contract.sh
# or
./run-contract.sh /absolute/path/to/nift
```

Performance entry points are documented by `run-performance.sh` and scripts in
`benchmarks/`. Absolute timings and RSS depend on the host; correctness does not.

## Adding behavior

For a bug: reproduce externally, reduce, make deterministic, add the failing
regression, confirm the expected baseline failure, fix Nift separately, run the
focused family, then run the entire contract.

For a deliberate language change: specify the new external behavior first, retain
old tests unless the contract intentionally changes, record the rationale, and
test high-risk interactions rather than one happy path.

Tests should own machine-checkable behavior. This handover owns why the suite is
structured this way. Individual bugs generally belong in named fixtures/tests and
Git history unless they reveal a durable testing rule.

## Independence and synchronization

Focused modules currently also exist under Nift's implementation repository. The
standalone suite declares itself canonical for the external contract. Before
editing mirrored material, compare current copies and document/automate the
intended synchronization direction. Do not allow silent divergence or couple the
standalone runner to Nift internals for convenience.

## Checkpoint standard

A suite checkpoint can be valuable without source changes: new failure-family
coverage, deterministic fixtures, clearer failure localization, or contract
organization all improve evidence. Report the executable tested, baseline,
modules/assertions, new families, exact failures/skips, environment-sensitive
checks, and repository state.

## Public actions

Local suite changes and validation are authorized development. Do not commit,
push, tag, publish, or redefine public Nift behavior without explicit direction.

## Maintaining this handover

This is living project infrastructure. Review it when runner interfaces, suite
ownership, synchronization, fixture strategy, major failure families, or
production-gate responsibilities change. Correct and consolidate it over time;
do not append a diary. Every substantial checkpoint must review handover and
roadmap impact.

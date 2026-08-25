# Nift contract-suite roadmap

This is a living production-gate risk assessment. Revisit it whenever Nift gains
behavior, a regression exposes a new family, fixtures become flaky, platform
coverage changes, or production confidence changes.

## Capability layers

The suite is one corpus organized by capability, not one executable interface:

- Layer 1 (`run-contract.sh`, `NIFT_BIN`) — Nift CLI/build contract; requires a
  complete Nift CLI implementation. `nift-rs` does not participate.
- Layer 2 (`embed/run-embed.sh`) — Nift Embed contract through neutral adapters;
  C++ Nift Embed and `nift-rs` both participate.

New Embed behavior belongs in `embed/` (shared cases + adapters), not duplicated
per implementation tree. The standalone NR6/NR12 differential scripts in nift-rs
remain implementation-local gates; migrate their cases here as the canonical
home, then reduce the scripts to thin wrappers over this corpus.

## Current priorities

1. Reconcile local and standalone focused modules and establish an automated
   synchronization/ownership check where exact mirroring is intended.
2. Preserve and extend the now-green 73-check `$[...]` parameter-value contract,
   including one-pass injection boundaries and A→B dependency/requirement
   lifecycle, without making parameters recursive Nift templates.
3. Run and preserve all existing historical/focused coverage against the
   candidate. The suite is now reconciled with the unified CLI grammar and
   includes the complete-pagination (CP8) and unified-CLI contracts; keep both
   as permanent gates as the independent Rust implementation matures.
4. Expand source-guided interaction tests around JSON, scope, control flow,
   dependencies, requirements, path containment, and failed-build recovery.
5. Review relevant modified/hash/hybrid and watch-mode transitions.
6. Use the full suite as a sanitized-candidate workload.
7. Keep performance/RSS evidence reproducible but separate from correctness.
8. Strengthen platform/fresh-install evidence as release scope requires.

The objective is not a target count. It is credible coverage of public behavior
and historical failure families sufficient to answer whether a refactor preserved
Nift. After production, every important defect should still become a minimized
regression and new features should expand the contract.

## Project contracts

Keep the new config-declared project-contract module in the canonical runner and extend it whenever contract namespace semantics, dependency lifecycle, or path/error behavior changes. Full-suite green evidence is required before treating the feature checkpoint as trusted.

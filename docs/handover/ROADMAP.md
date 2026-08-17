# Nift contract-suite roadmap

This is a living production-gate risk assessment. Revisit it whenever Nift gains
behavior, a regression exposes a new family, fixtures become flaky, platform
coverage changes, or production confidence changes.

## Current priorities

1. Reconcile local and standalone focused modules and establish an automated
   synchronization/ownership check where exact mirroring is intended.
2. Preserve and extend the now-green 73-check `$[...]` parameter-value contract,
   including one-pass injection boundaries and A→B dependency/requirement
   lifecycle, without making parameters recursive Nift templates.
3. Run and preserve all existing historical/focused coverage against the
   candidate.
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

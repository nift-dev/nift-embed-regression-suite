# Results against supplied `nift-stripped-v0.5`

- v0.5 compiles successfully with its own Makefile.
- The previous 146-test suite passes **146/146** before adding the new adversarial probes.
- The expanded project contains 31 browsable positive test pages.
- The expanded runner includes parser, CLI, watch, persistent-state, incremental-mode and build-auto regression probes.
- Successful assertions stay quiet; only regressions are printed.

Run:

```sh
TERM=xterm NIFT_BIN=/path/to/v0.5/nift ./scripts/run-tests.sh
```

See `KNOWN-ISSUES-v0.5.md` for the source-level reasoning behind the currently reproduced failures.

Current expanded-suite result against the supplied v0.5 binary: **211 assertions/tests, 27 reproduced failures/candidates**.

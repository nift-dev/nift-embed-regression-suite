# Nift deep regression test suite — v6

This is the current black-box regression suite for Nift.

It is designed to exercise the executable from the outside using temporary
projects, including ordinary workflows and adversarial edge cases found during
source review.

## Current baseline

Validated against:

```text
Nift v4.0.0 (C++ rewrite 1.0.12)
PASS: 279 assertions/tests
```

The v6 suite reflects the simplified comment language in Nift 1.0.12:
`<#-- ... --#>`, `@# ...` and `@// ...` are non-executing Nift comments, and
the removed parsed-block-comment syntax is no longer tested.

The suite also treats the `info*` commands as structured JSON where appropriate
instead of depending on the older human-readable presentation format.

## Running

Point `NIFT_BIN` at the executable to test:

```bash
NIFT_BIN=/path/to/nift ./scripts/run-tests.sh
```

A successful complete run prints only the final summary:

```text
PASS: 279 assertions/tests
```

Failures include a test number and description.

## Coverage

The suite includes parser boundaries, escaping, comments and `<pre>` behaviour,
`@content`, nested `@input`, `@pathto`, `@dep`, metadata, tracking and watched
directories, malformed JSON/state, filesystem/path safety, build error status,
incremental modified/hash/hybrid modes, user `*.deps.json` dependencies,
recursive directory hashing, `build-auto`, and CLI operations.

Some cases deliberately sleep long enough to create reliable filesystem mtime
changes, so a complete run can take a while.

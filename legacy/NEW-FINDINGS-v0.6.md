# Nift stripped v0.6 — fresh adversarial pass

Baseline: the v0.5 deep regression suite passes **211/211** against the supplied stripped v0.6 source.

This pass expands the suite to **245 assertions/tests**. Against the supplied v0.6 build, **27 assertions fail** (218 pass). Several failures share one root cause.

## High-confidence findings

### Watch JSON structural validation
`WatchList::open()` validates the outer JSON documents/arrays but does not validate array-member types before using RapidJSON accessors. The new probes reproduce controlled-input aborts for:

- non-string member in `watched.json`'s `watched` array;
- non-object member in an `exts.json` `exts` array;
- missing/wrong-type `content-ext`;
- missing/wrong-type `template`;
- missing/wrong-type `output-ext`.

These are one robustness family: validate `IsString()` on watched entries, and `IsObject()` + required string members on each exts entry before `GetString()`.

### JSON escaping is still incomplete
`save_tracking()` now escapes titles, but names are still written raw. A tracked name containing `"` corrupts `tracked.json`; the same happens via `cp`/`mv` destinations. `WatchList::save()` uses `double_quote()`, which surrounds strings but does not JSON-escape embedded quotes, so a watched directory containing `"` corrupts `watched.json`.

A general JSON-string writer/escape helper (or RapidJSON writer) should be used for every user-controlled JSON string, not only titles.

### `cp` / `mv` path traversal
Direct `track ../escape` is now rejected, but `cp / ../...` and `mv / ../...` still accept destinations outside the configured content/output roots. Embedded traversal such as `nested/../../escape` also bypasses the current `name.substr(0,2) == ".."` track guard.

Normalize/resolve the resulting content/output path and verify it remains under the configured roots rather than checking only the first two name characters.

### Watch path traversal
`watch content/../outside/` and deeper variants pass the lexical prefix check even though the normalized path escapes the content directory. This should use normalized containment rather than string-prefix containment.

### `build-names` unknown options
`build-names -x /`, `--bad /`, and `--progress /` are accepted because any unrecognised option falls through to `build_names(2, ...)`. Explicitly whitelist `-s`, `-n`, and `-p` (or whatever options are intended) and reject other leading `-` arguments.

### Directory `@dep` in hash/hybrid probes
The existing suite covered unchanged directory dependencies in modified mode. New probes add a file inside a directory dependency after the baseline build. The supplied v0.6 does not rebuild in hash mode; the hybrid probe also currently fails.

The parser/hash path uses `FNVHash(string_from_file(depPath))`, which is not a meaningful content hash for a directory. Decide directory dependency semantics explicitly: recursive/deterministic directory hash, or use directory mtime for directories even when file dependencies use hash mode.

## Lower-priority / policy candidates

### Duplicate extension entries in watched `exts.json`
A manually edited `exts.json` can contain duplicate `content-ext` objects with conflicting template/output mappings; the reader silently accepts them and the later map assignment wins. Old watch-list code explicitly diagnosed duplicate extensions. The new test expects a controlled rejection, but this is mostly corrupted/manual state rather than normal operation.

### Quote-containing names/watch directories
These are valid Unix filesystem names but uncommon. The tests currently expect that if Nift accepts them, it must preserve valid JSON. An alternative product decision is to reject such names/directories explicitly. Either contract is preferable to accepting them and corrupting persistent state.

## New positive coverage that passes

The expansion also adds passing probes for: multiple-name `info`, malformed config structure, wrong-type optional tracked extension fields, direct and indirect `@input` recursion termination, custom-extension watch persistence/reopen, quoted extension handling during init, and backslash-containing title JSON round-tripping.

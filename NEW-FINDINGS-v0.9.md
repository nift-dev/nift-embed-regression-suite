# Nift v0.9 fresh adversarial/code-review findings

This pass adds 16 assertions/tests beyond the previous 264-test suite. Against the uploaded v0.9 source, the new-only block produces 12 failing assertions. They cluster into three main implementation issues rather than 12 unrelated bugs.

## 1. Directory dependencies are always dirty in hash/hybrid mode

`dep_has_changed()` currently begins with `!file_exists(path.str())`. `file_exists()` deliberately returns false for directories, so a directory dependency is treated as changed on every hash/hybrid incremental check.

New failures cover both parser `@dep` directories and `*.deps.json` directory dependencies, in hash and hybrid modes.

Likely fix: use `path_exists()` for the existence test, then apply mode-specific mtime/hash logic.

## 2. Hash mode currently includes mtime semantics

`dep_has_changed()` currently returns `path.modified_after(infoPath) || path_has_changed_hash(path)`. That makes pure hash mode rebuild after a timestamp-only `touch`, even when file contents are byte-identical.

New tests distinguish intended semantics:

- modified: mtime
- hash: hash only
- hybrid: mtime OR hash

This affects ordinary `@dep`, `*.deps.json`, tracked content and template dependencies.

## 3. Directory hash does not fully represent the directory tree

`hash_directory()` uses `Path(dir, files[f])`. `Path` concatenates its directory and filename components; it does not insert a separator. If `dir` lacks a trailing slash, `data-dir` + `a.txt` becomes `data-dira.txt`.

Direct stored-hash tests show that the current directory hash does not change when:

- an existing child file's contents change;
- a nested child file's contents change;
- a child file is renamed while preserving contents;
- a nested directory is renamed while preserving contents.

A robust directory hash should join child paths correctly and include entry names/type plus recursive child hashes in deterministic order.

## Additional source-audit candidate

`ProjectInfo::buildThreads` and `incrMode` are primitive members without explicit initialization. Wrong-type/missing config values can leave them indeterminate. A wrong-type `build-threads` probe produced a `std::system_error` abort in one manual run, but the behaviour is undefined/nondeterministic, so this pass does not include a flaky assertion for it. Initializing these members before parsing config would remove the UB cheaply.

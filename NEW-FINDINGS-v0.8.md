# Nift stripped v0.8 — fresh adversarial/code-review findings

Baseline: the corrected v3 suite passes **245/245** against the supplied v0.8 binary.

This pass adds 19 assertions, bringing the suite to **264**. The new assertions reproduce 19 failures, but they group into a much smaller number of likely root causes.

## 1. User-defined `.deps.json` structural validation

Tests 211–212 in the expanded ordering deliberately replace `content/index.deps.json` with malformed or non-object JSON. `ProjectInfo::dep_thread()` calls `HasMember()` without first checking parse success / `IsObject()`, so RapidJSON aborts instead of Nift returning a controlled error.

Likely fix: mirror the validation already added for tracked/watch JSON: `HasParseError() || !IsObject()` before `HasMember("dependencies")`.

## 2. User-defined dependencies ignore hash/hybrid semantics

Tests 213–214 modify a user-defined dependency while restoring its original mtime. Hash and hybrid modes miss the change because the user-defined dependency path near the end of `dep_thread()` is still checked only with `dep.modified_after(infoPath)`.

Likely fix: use the same incremental-mode dispatch / hash-path logic as parser-recorded `@dep` dependencies, and ensure user deps get hash files refreshed on successful builds.

## 3. Directory hashing does not actually hash child paths correctly without a trailing slash

Tests 215–218 and 225–226 exercise existing child-content changes, nested child-content changes, and additions below an existing nested directory.

`hash_directory()` currently calls:

```cpp
hash_path(Path(dir, files[f]))
```

`Path::str()` concatenates `dir + file`; it does not add a separator. For `dir == "data-dir"` and `file == "a.txt"`, that hashes `data-dira.txt`, not `data-dir/a.txt`. The existing directory-membership tests passed because the entry *name* itself is separately mixed into the aggregate hash.

Likely fix: normalize `dir` to end in `/` (or construct the child path through `set_file_path_from`) before recursion.

## 4. Generated page `.info.json` does not JSON-escape strings

Tests 219–220, 223–224 and 264 cover quoted titles, tracked names, template paths, `@input` paths and `@dep` paths. `Parser::build()` writes these directly into JSON:

```cpp
infoStream << "\t\"name\": \"" << toBuild.name << "\",\n";
infoStream << "\t\"title\": \"" << unquote(toBuild.title.str) << "\",\n";
infoStream << "\t\"template\": \"" << toBuild.templatePath.str() << "\",\n";
...
infoStream << "\t\t\"" << depFile->str() << "\"";
```

Likely fix: apply the existing `json_escape()` helper at this serialization boundary, just as `save_tracking()` now does.

## 5. `cp` / `mv` double-escape quoted destination names

Tests 221–222 show a subtler serialization bug. `cp()` / `mv()` assign:

```cpp
newInfo.name = json_escape(newName);
```

and then `save_tracking()` escapes `tInfo->name` again. The JSON remains valid but the in-memory logical name is changed; reopening the same quoted name reports that Nift is not tracking it.

Likely fix: keep `TrackedInfo::name` unescaped and escape only when serializing JSON.

## 6. Watch `exts.json` strings are not escaped

Tests 227+ cover quoted watched content/output extensions. `WatchList::save()` JSON-escapes `watchDir`, but writes `content-ext`, `template`, and `output-ext` through `double_quote()` only. Accepted quote-containing values therefore produce invalid JSON.

Likely fix: `double_quote(json_escape(...))` for all three fields, or use RapidJSON Writer for the file.

## Overall impression

The failure pattern is substantially narrower than the previous passes. The 245 established tests all pass, and the new findings are dominated by a handful of serialization/incremental-state abstractions that were fixed in one location but not yet applied consistently everywhere.

# v0.5 source-audit notes

These are code observations from the v0.5 pass. Items already reproduced by the runner are documented in `KNOWN-ISSUES-v0.5.md`.

## Progress mutex has a double unlock path

`build_progress()` currently contains a phase/finished branch equivalent to:

```cpp
if(cPhase != phaseToCheck || cFinished >= total_no_to_build)
{
    os_mtx.unlock();
    os_mtx.unlock();
    break;
}
```

The expanded suite exercises `status -p`, `build-updated -p`, `build-all -p` and newline variants without reproducing a visible failure on this Linux run, but unlocking a `std::mutex` twice is undefined behaviour and is worth fixing independently of whether it manifested here.

## `read_params()` still treats backticks as quoted sections

The public suite now deliberately treats only single and double quotes as supported string quoting. The source branch still checks:

```cpp
'  "  `
```

when entering a quoted section. The outward backtick `@input` test fails as desired because `unquote()` strips only `'`/`"`, but simplifying the parameter reader would make the implementation match the intended grammar.

## JSON is written manually in several places

`save_tracking()` and parser info-file serialization interpolate strings directly into JSON. The quoted-title regression demonstrates one concrete breakage. Similar escaping problems are possible for unusual names/template/dependency paths containing JSON-special characters. A shared JSON-string escaping/writer path would remove an entire class of edge cases.

## Manual malformed JSON handling is inconsistent

Project config and much of tracked/info parsing perform useful type checks, but WatchList and array-element handling have unchecked RapidJSON access. The regression suite now includes crash probes specifically because these inconsistencies are easy to reintroduce.

# Quote syntax used by this regression suite

The v4 public test suite treats only single quotes (`'`) and double quotes (`"`) as string/path quote delimiters.

Backticks are intentionally not considered a supported quoting form. The earlier probe that expected:

```text
@input(`templates/child.html`)
```

to behave like single/double-quoted input has been removed.

This keeps the public language smaller and avoids turning an internal parser quoting convention into an accidental language feature.

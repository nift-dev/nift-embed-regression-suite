# v11 `@if` ordering-relation regression coverage

This revision adds regression coverage for the ordering operators introduced in rewrite v1.0.17:

- numeric `<`, `<=`, `>` and `>=`;
- equality boundaries for `<=` and `>=`;
- negative numeric ordering;
- JSON-path-to-JSON-path ordering;
- lexicographic string ordering;
- operator-looking text inside quoted strings;
- rejection of mixed-type ordering;
- rejection of boolean ordering.

The ordering cases are represented in both the main control-flow regression coverage and the ruthless adversarial extension. Validation against rewrite v1.0.17 completed with **386/386 main checks** and **154/154 ruthless checks**.

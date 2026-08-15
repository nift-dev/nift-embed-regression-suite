# v10 control-flow indentation regression coverage

Added focused coverage requiring multiline `@for` and `@if` blocks to render at the directive insertion point, matching `@input` semantics.

Coverage includes:

- basic `@for` indentation
- repeated loop iterations
- basic `@if` indentation
- selected `else` indentation
- nested `@for` + `@if`
- preservation of relative indentation inside a block
- `@input` inside `@for`
- inline `@for` insertion-column alignment
- inline `@if` insertion-point alignment

The same cases are included in the main regression runner and the ruthless adversarial extension. The ruthless extension is now 143 checks and passes 143/143 against rewrite v1.0.16.

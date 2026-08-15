# v12 feature coverage

This regression revision accompanies C++ rewrite v1.0.18.

It adds adversarial coverage for:

- optional `@json(path, binding, schema)` validation;
- schema-file dependency recording and schema-change invalidation;
- nested validation error paths and required/type failures;
- explicitly unsupported schema keywords;
- local schema references;
- reserved `loop` binding collisions;
- `$[loop.index]`, `$[loop.index0]`, `$[loop.first]`, `$[loop.last]`, `$[loop.length]`;
- nested loop metadata restoration;
- stable numeric/string ordering with `by ... asc|desc`;
- scalar-array and object sorting;
- missing directions/members, mixed sort-key types, and non-scalar sort keys.

The ruthless extension reports **170 checks, 0 failures** against rewrite v1.0.18.

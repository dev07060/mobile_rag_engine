# High-Level Hybrid Transition

This note tracks the post-cutover stabilization work for
`searchHybridWithContext()`.
The high-level entrypoint now assembles `full` results from the low-level
handle lane and keeps the public API unchanged.
This is a parity-first transition.
It does not promise a new performance contract, and it does not reopen
`preview` or other mode work that is still under review elsewhere.

## Scope

- `searchHybridWithContext()` is the only high-level path covered here.
- `search()` remains out of scope for implementation in this workstream.
- Follow-up work is about diagnostics and soak readiness for the cutover path.

## Parity Diagnostics

Parity diagnostics compare the low-level handle-backed result against the
legacy Dart assembly path.
The comparison is deterministic and reports mismatches with:

- field path
- list index when applicable
- expected value
- actual value

Current parity coverage checks:

- `context.text`
- `context.estimatedTokens`
- `context.remainingBudget`
- hydrated `chunks` length, order, and fields
- `context.includedChunks` length, order, and fields

Primary regression coverage lives in:

- `test/native/low_level_lane_test.dart`
- `test/unit/high_level_hybrid_transition_test.dart`

## Soak Checklist

This transition is not considered settled just because parity tests pass once.
During soak, watch for the following:

### Parity regressions

- Run the low-level lane parity regression tests after changes to search
  ranking, context packing, or chunk hydration.
- Investigate any field-level mismatch before accepting behavior changes as
  intentional.

### Lifecycle and retry regressions

- Confirm search handles are always disposed, including failure paths.
- Recheck stale-handle behavior after collection mutation.
- Watch for any retry path that accidentally reuses invalid handles instead of
  reissuing the search.

### UI hitching

- Exercise the example app search flow while issuing repeated hybrid queries.
- Watch for frame drops or visible stalls around search, hydrate, and context
  assembly.
- Treat hitching in representative app flows as a soak blocker even when
  parity still passes.

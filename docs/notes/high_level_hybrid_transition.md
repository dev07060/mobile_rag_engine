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

## Legacy Oracle Boundary

The legacy Dart assembly path is retained only as an internal parity oracle.
It is not a public mode, rollout fallback, or alternate production path.

Current boundary:

- legacy assembly logic is used from regression helpers only
- production `searchHybridWithContext()` goes through the low-level handle path
- no public flag or mode switches back to the legacy path

Removal criteria:

- one release cycle with stable parity coverage
- no unresolved lifecycle or retry regressions tied to the handle path
- no unresolved UI hitching findings in representative flows
- no outstanding contract clarifications that require legacy-vs-low-level
  comparisons to stay live

## `search()` Migration Gate

Current decision: `require more parity/soak work first`

Why this remains deferred:

- `searchHybridWithContext()` has only just moved onto the low-level lane
- soak evidence is still needed for lifecycle, retry, and UI behavior
- parity coverage exists, but it has not yet accumulated release-level
  confidence

Preconditions before revisiting `search()`:

- parity regressions remain clean through soak
- handle lifecycle behavior is boring under normal mutation and retry paths
- no significant UI hitching is observed in representative flows
- the high-level contract is stable enough that a second migration would not
  pile ambiguity on top of the first

Allowed outcomes when revisiting the decision:

- `migrate next`
- `defer`
- `require more parity/soak work first`

The current state remains the third option.

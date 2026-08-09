# macOS FRB process linkage qualification

**Verdict:** the macOS process-ABI blocker recorded in
`2026-08-09-hosted-companion-qualification.md` is resolved for the local
candidate `rag_engine_flutter 0.20.0-dev.11`. A fresh macOS consumer using the
clean candidate snapshot and an explicit local `rag_engine_flutter` override
initializes Flutter Rust Bridge, completes a Model Pack first search, and
builds in release mode. This is local path-override evidence only; it is not a
hosted or override-free proof and does not publish the package.

## Root cause and minimal fix

The previous fresh consumer had `-force_load` in its generated Pods xcconfig,
and the arm64 static archive contained `_frb_get_rust_content_hash`, but the
final application executable did not make that symbol visible through
`dlsym(RTLD_DEFAULT, ...)`. FRB initialization therefore stopped before
ingestion with `Failed to lookup symbol 'frb_get_rust_content_hash'`.

Apple's current linker accepted `-export_dynamic` in a small static-archive
probe (`xcrun clang ... -Wl,-export_dynamic`). The sole functional source
change is the macOS plugin's `user_target_xcconfig`:

```diff
- $(inherited) -force_load ${BUILT_PRODUCTS_DIR}/rag_engine_flutter/librag_engine_flutter.a
+ $(inherited) -force_load ${BUILT_PRODUCTS_DIR}/rag_engine_flutter/librag_engine_flutter.a -Wl,-export_dynamic
```

It is intentionally limited to
`rust_builder/macos/rag_engine_flutter.podspec`; the iOS podspec is unchanged.
After a new consumer's CocoaPods generation, its Profile xcconfig contains:

```text
OTHER_LDFLAGS = $(inherited) -ObjC -Wl,-export_dynamic ... \
  -force_load ${BUILT_PRODUCTS_DIR}/rag_engine_flutter/librag_engine_flutter.a
```

This is the plugin podspec propagating the fix; the consumer Podfile contains
only the existing macOS 14.0 and `use_frameworks! :linkage => :static`
onboarding settings, with no symbol workaround.

## Clean candidate and code generation

- Source commit: `b0ae208a260879bdecaaae1e6ba7f2d9c60af11c`.
- Input: tracked-files-only `git archive` snapshot at
  `/private/tmp/mobile-rag-session10-process-linkage`; no worktree or clone.
- FRB generator/runtime: `2.11.1`; `flutter_rust_bridge_codegen generate
  --config-file flutter_rust_bridge.yaml` was zero-diff.
- The four generated output SHA-256 values remain `cd2336044`, `a02958fb`,
  `62bb418c`, and `b6ffa3f4` (the previously qualified values); generated
  content hash remains `-941343322`.

## Native process-symbol evidence

The new local consumer lives at
`/private/tmp/mobile_rag_session10_consumer`. It resolves the root package from
the clean snapshot and overrides only `rag_engine_flutter` to that snapshot's
`rust_builder` directory, resolving `0.20.0-dev.11`.

`nm -arch arm64 -gU` on the Profile static archive reports
`_frb_get_rust_content_hash` and the
`_frbgen_mobile_rag_engine_rust_arc_increment_strong_count...` bridge
entrypoint. The final universal application executable's arm64 export trie
reports both symbols too. The separate Release archive and Release executable
report the same two symbols.

Most importantly, the profile integration run invoked `MobileRag.initialize`,
which performs FRB's process lookup, without a lookup error. It then logged:

```text
MODEL_PACK_FIRST_SEARCH_OK hits=1 context_chars=107
```

The search added `Flutter builds applications from one Dart codebase.`, rebuilt
and warmed the index, and returned a non-empty source-grounded chunk and
context before disposal. The Model Pack setup printed both `MODEL_PACK_READY`
and `MODEL_PACK_VERIFIED`; its model and tokenizer SHA-256 values match the
immutable MiniLM preset.

## Build, package, and regression evidence

- `flutter drive --profile -d macos ...model_pack_first_search_test.dart`:
  passed; profile app built at 207.7 MB.
- `flutter build macos --release`: passed; release app built at 181.4 MB.
- Release executable and static library are universal arm64/x86_64 artifacts;
  their arm64 app export trie exposes the FRB content-hash and representative
  bridge entrypoint.
- `flutter pub publish --dry-run` from the snapshot companion: passed,
  234 KB compressed archive, **0 warnings**. No publish occurred.
- `flutter analyze lib test`: no issues.
- `flutter test test/unit`: passed.
- `cd example && flutter test`: passed, 33 tests.
- `cargo test --manifest-path rust_builder/rust/Cargo.toml --lib --features
  'vector_quant_i8,vector_faer' -- --test-threads=1`: 185 passed, 10 ignored,
  0 failed (five pre-existing compiler warnings).
- `git diff --check` for the linkage commit is clean.

## Boundary and next authorization

All evidence above uses a clean root snapshot plus explicit local path override
for the not-yet-published companion. It clears the prior **local-candidate
process-linkage** blocker, not the separate hosted/override-free distribution
gate. No push, PR, merge, tag, or publish was performed. A separate user
approval is still required before any actual publish, and hosted-consumer
qualification must be rerun after publication.

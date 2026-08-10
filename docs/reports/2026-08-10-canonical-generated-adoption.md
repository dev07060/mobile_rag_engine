# Canonical generated adoption — `rag_engine_flutter 0.20.0-dev.11`

## 판정

**다음 세션의 companion 실제 발행 및 hosted consumer 검증 진행 가능.** 이
세션에서는 실제 `pub publish`, push, PR, merge, tag, yank를 수행하지 않았다.

## 입력과 도구체인

- 채택 전 source HEAD: `7e55f199c04e6ebb47b065fa0ceb0cf26bd75388`
  (`feats/triage-rust-qualification-dev11`).
- canonical 생성물 커밋: `e61ca4348c35d0f931ac8bbb608bebbf115706e7`
  (`chore(codegen): adopt canonical generated outputs`).
- 모든 생성/검증은 `git archive HEAD`로 만든 tracked-files-only clean snapshot에서
  수행했다. working tree에서 generator, formatter, build_runner를 실행하지 않았다.
- Flutter `3.35.5`, Dart `3.9.2`,
  `flutter_rust_bridge_codegen 2.11.1`, `freezed 3.2.4`,
  `build_runner 2.10.5`, rustc/cargo `1.91.1`을 사용했다.
- canonical pipeline:

  ```text
  flutter pub get
  flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
  flutter pub run build_runner build --delete-conflicting-outputs
  /Users/dev_bh/flutter/bin/cache/dart-sdk/bin/dart format lib/src/rust
  ```

## 채택한 정확한 18개 생성물

1. `lib/src/rust/api/bm25_search.dart`
2. `lib/src/rust/api/compression_utils.dart`
3. `lib/src/rust/api/db_pool.dart`
4. `lib/src/rust/api/document_parser.dart`
5. `lib/src/rust/api/hnsw_index.dart`
6. `lib/src/rust/api/hybrid_search.dart`
7. `lib/src/rust/api/incremental_index.dart`
8. `lib/src/rust/api/ingest_session.dart`
9. `lib/src/rust/api/migration_meta.dart`
10. `lib/src/rust/api/query_metrics.dart`
11. `lib/src/rust/api/semantic_chunker.dart`
12. `lib/src/rust/api/simple_rag.dart`
13. `lib/src/rust/api/source_rag.dart`
14. `lib/src/rust/api/error.freezed.dart`
15. `lib/src/rust/api/ingest_metrics.dart`
16. `lib/src/rust/api/migration_meta.freezed.dart`
17. `lib/src/rust/api/tokenizer.dart`
18. `lib/src/rust/api/user_intent.freezed.dart`

13개는 FRB Dart wrapper, 3개는 Freezed output, 2개는 formatter output이다.
FRB 핵심 4개(`frb_generated.dart`, `.io.dart`, `.web.dart`, Rust
`frb_generated.rs`)는 생성 전후 HEAD와 byte-for-byte 동일했다. Dart/Rust content
hash `-941343322`, `loaded_hnsw_node_count`, Rust dispatcher ID `102`도 clean
snapshot에서 일치했다.

## index-only 채택과 working tree 보존

시작 시 index에 staged 변경이 없음을 확인했다. 기존 dirty tracked 21개 각각의
경로, SHA-256, mode를 `/private/tmp/mobile-rag-canonical-adoption-GL6jIH/`에
manifest, binary patch, 원본 사본으로 기록했다. untracked 목록도 같은 외부
경로에 기록했으며 저장소 안에 backup을 만들지 않았다.

clean canonical 파일별 blob을 `git hash-object -w`로 기록한 뒤, 각 HEAD mode와
정확한 path를 사용해 `git update-index --cacheinfo`로만 index에 넣었다. broad
`git add`는 사용하지 않았다. stage 직후 cached path는 위 18개와 정확히 같았고,
각 index blob은 clean snapshot의 대응 파일과 `cmp`로 byte-for-byte 일치했다.

21개 기존 dirty tracked 파일의 SHA-256/mode를 stage 전, stage 후, 첫 커밋 후에
재확인했다. 세 시점 모두 일치했다. 따라서 canonical adoption은 user-owned dirty
working file을 overwrite, format, stage, restore하지 않았다.

## generated-output whitespace 예외

승인된 예외는 generator가 결정적으로 만든 아래 Freezed 파일의 trailing whitespace
18건뿐이다.

| 파일 | 건수 |
| --- | ---: |
| `lib/src/rust/api/error.freezed.dart` | 10 |
| `lib/src/rust/api/migration_meta.freezed.dart` | 3 |
| `lib/src/rust/api/user_intent.freezed.dart` | 5 |

다른 15개 adopted 생성물이나 수동 파일에는 cached whitespace diagnostic이 없었다.
이 18건은 clean canonical temp 결과와 cached blob이 byte-for-byte 같아서,
generator output 예외로 기록하고 수동 수정하지 않았다. 새 HEAD clean snapshot을
동일 pipeline으로 다시 생성했을 때 18개는 모두 zero-diff였고, clean snapshot의
`git diff --check HEAD`도 통과했다.

## 재생성/qualification 결과

- 새 HEAD clean snapshot의 전체 tracked content 차이는 `example/pubspec.lock`
  하나뿐이었다. 이는 `flutter pub get`이 example의 transitive dependency를
  해석하며 만든 lockfile 부수 효과이고 adoption 대상이 아니다. 18개 canonical
  파일과 핵심 FRB 4개는 모두 zero-diff였다.
- `flutter analyze lib test`: pass, no issues.
- `flutter test test/unit`: pass, 69 tests.
- `example/`의 `flutter test test`: pass, 33 tests. tracked archive에 포함되지 않은
  corpus/eval asset directory에 대한 9개 diagnostic은 출력됐지만 test command는
  성공했다.
- Source RAG regression/ingestion focused tests: pass, 9 tests.
- `cargo test --manifest-path rust_builder/rust/Cargo.toml --features
  'vector_faer,vector_quant_i8' -- --test-threads=1`: lib 185 passed, 0 failed,
  10 ignored; doc-test 1 passed, 0 failed, 1 ignored. Compiler output은 8 warning,
  0 error였다.
- `rust_builder/`의 `flutter pub publish --dry-run`: pass. compressed archive
  234 KB, package warnings 0, package errors 0.

## dependency/override 경계

root `pubspec.yaml`은 정확히 `flutter_rust_bridge: 2.11.1` 및
`rag_engine_flutter: 0.20.0-dev.11`을 선언한다. 이 source HEAD에는 이미 tracked
`dependency_overrides.rag_engine_flutter.path: ./rust_builder`가 있어 clean root
qualification은 local companion을 사용했다. 이 세션은 `pubspec_overrides.yaml`을
새로 만들지 않았고(`0` files), lockfile 변화를 채택하지 않았다.

따라서 이번 검증은 companion package shape와 source-tree compatibility 증거다.
실제 companion 발행 뒤의 override-free hosted consumer 검증은 다음 세션의 별도
필수 단계다.

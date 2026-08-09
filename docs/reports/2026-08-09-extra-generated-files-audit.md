# 추가 generated 파일 5개 감사 — 전체 generation zero-diff 경계

**판정:** 5개는 이전 세션의 canonical 스냅샷과 byte-for-byte 일치한다. 이 중
`*.freezed.dart` 3개는 `build_runner`/Freezed의 stale 산출물이므로 채택 필수이고,
`ingest_metrics.dart`, `tokenizer.dart` 2개는 별도 Dart formatter가 만든 순수 서식
정규화다. 이번 릴리스에서 **프로젝트 전체 generation zero-diff**를 gate로 삼는다면
5개 모두 13개 FRB wrapper와 함께 사전 채택해야 한다. FRB Rust ABI나 실제
모델·직렬화 계약의 변화는 발견하지 못했다.

## 범위와 보호 경계

- 시작 HEAD: `8ab5608da44843cdb0671b7f12d38d74cf872441`
  (`feats/audit-frb-wrapper-diff-dev11`).
- 시작 working tree에는 21개의 수정된 FRB/API 파일과 여러 untracked 문서·도구
  파일이 있었다. 이 세션은 이들을 수정, format, stage, commit하지 않았다.
- 감사 브랜치: `feats/audit-extra-generated-files-dev11`.
- 재현은 `git archive HEAD`로 만든 다음 clean snapshot에서만 했다.
  - 주 스냅샷: `/private/tmp/mobile-rag-extra-generated-dev11-h09A9H`
  - FRB 독립성 대조 스냅샷: `/private/tmp/mobile-rag-extra-generated-control-dev11-UFqtFw`
  - 이전 canonical 비교 스냅샷:
    `/private/tmp/mobile-rag-frb-wrapper-audit-0dTrdJ`
- 도구: Flutter 3.35.5, Dart 3.9.2,
  `flutter_rust_bridge_codegen 2.11.1`, lockfile의 `freezed 3.2.4` 및
  `build_runner 2.10.5`.

13번째 보고서가 전체 tracked-file 비교에서 발견한 정확한 추가 5개는 다음과 같다.

1. `lib/src/rust/api/error.freezed.dart`
2. `lib/src/rust/api/ingest_metrics.dart`
3. `lib/src/rust/api/migration_meta.freezed.dart`
4. `lib/src/rust/api/tokenizer.dart`
5. `lib/src/rust/api/user_intent.freezed.dart`

`example/pubspec.lock`의 8행 추가는 `flutter pub get`이 example의 transitive
`crypto 3.0.7`을 해석하며 만든 별도 lockfile 부수 효과다. 생성물 채택 목록에는
넣지 않는다.

## 단계별 attribution

모든 명령은 프로세스 종료 뒤에만 다음 단계와 비교했다.

| 단계 | 명령 | 5개에 미친 결과 | 기타 관찰 |
| --- | --- | --- | --- |
| A 기준 | `git archive HEAD` | 5개 모두 HEAD hash | clean snapshot |
| B 의존성 | `flutter pub get` | 5개 변화 없음 | `example/pubspec.lock`만 수정 |
| C FRB 직접 출력 | `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` | 5개 변화 없음 | formatter 전 intermediate Dart 출력이 생김 |
| D 후속 생성 | `flutter pub run build_runner build --delete-conflicting-outputs` | `error.freezed.dart`, `migration_meta.freezed.dart`, `user_intent.freezed.dart` 3개만 변경 | `freezed`가 3 outputs를 썼으며 `json_serializable` output은 없음 |
| E formatter | `/Users/dev_bh/flutter/bin/cache/dart-sdk/bin/dart format lib/src/rust` | 남은 `ingest_metrics.dart`, `tokenizer.dart` 2개만 변경 | 30 files를 검사해 20 files를 format; 최종 tracked diff는 13 wrapper + 이 5개 |

FRB를 아예 실행하지 않은 대조 snapshot에서도 B → D가 같은 3개의 Freezed hash를
만들었고, 이어서 두 파일만 format해 같은 나머지 2개 hash를 만들었다. 따라서
Freezed 3개를 Rust API 변경 탓으로, formatter 2개를 FRB 직접 출력 탓으로
귀속할 근거는 없다.

FRB 직접 출력 직후 Dart primary 파일에는 formatter 전의 큰 서식 diff가 있었지만,
단계 E 뒤 `frb_generated.dart`, `frb_generated.io.dart`,
`frb_generated.web.dart`, `rust_builder/rust/src/frb_generated.rs`의 hash는 모두
HEAD 및 13번째 canonical 스냅샷과 다시 일치했다. 따라서 이 보고서의 5개 판단은
기존의 핵심 FRB 4개 무변경 결론과 충돌하지 않는다.

## 파일별 hash, diff, 의미

`A`는 archive HEAD, `D`는 build_runner 뒤, `E`는 전체 formatter 뒤의 SHA-256이다.

| 파일 | A | D | E (canonical) | +/- (A→E) | attribution / 의미 | 채택 |
| --- | --- | --- | --- | ---:| --- | --- |
| `error.freezed.dart` | `37bca6c6291b7bc3e1bb21e1a4a94c753050d0353695c44173ae52692f94cb6b` | `d1c15c93a0d5b3d3200bf99517c10d1ab06fa697da39a63e29587600d4ccc4c9` | `d1c15c93a0d5b3d3200bf99517c10d1ab06fa697da39a63e29587600d4ccc4c9` | +680/-905 | Freezed 3.2.4 재생성. `error.dart`의 `RagError` variant/field 계약은 같은 상태이며 generated layout·helper 정규화만 stale였다. | **필수** |
| `ingest_metrics.dart` | `65c9ecb7a6faa36483fa6d4fd527c08a5ad832a07c80a462a5440ec3da9ec220` | 동일 | `25523c0d2df4d62a9d39f48da82623646c92c705c425537c80e976ee4aaa364d` | +2/-2 | `legacyTextTrafficTotal`, `sessionTextTrafficTotal`의 method-chain indentation만 변경. | **권고**; 전체 gate면 필수 |
| `migration_meta.freezed.dart` | `753c4fce078d0d456c205d9e90c1ff2e98278744697707cc7e515d469807b2a3` | `3b7525752732185a16232d0fddf9ea1a671e029386210ac6e864311cbd62719a` | `3b7525752732185a16232d0fddf9ea1a671e029386210ac6e864311cbd62719a` | +268/-340 | Freezed 3.2.4 재생성. `EmbeddingFingerprintGate`/`MigrationAxes`의 variant, field, public method shape는 동일하다. | **필수** |
| `tokenizer.dart` | `6c59b7e6d8d438f0344a749dd651c66566d9f999dcdd4407d3895501edc899ef` | 동일 | `0215569f8d2ae460ab19eab19111d48fd4a087e164bf38a95eff04be2f797da5` | +4/-3 | `initTokenizer`의 chained-call line break만 변경; parameter/return/FRB call은 동일. | **권고**; 전체 gate면 필수 |
| `user_intent.freezed.dart` | `0f931da4855d4d2289d5cb011eecf02ef5934ef7ec8165505f3e2f52c503a88e` | `1ab76597b4439f82e0124c4bc394706f9cd0a7c586045ed34c7c8bc34a6c7e7f` | `1ab76597b4439f82e0124c4bc394706f9cd0a7c586045ed34c7c8bc34a6c7e7f` | +392/-461 | Freezed 3.2.4 재생성. `UserIntent` 5 variants와 `ParsedIntent` public shape는 동일하다. | **필수** |

세 Freezed 파일 모두 generated header는 기존과 같은 `FreezedGenerator`이며 버전
문자열 변경은 없다. class/mixin/extension 및 `copyWith`, `when`, `map` 계열의
선언 수를 A와 E에서 비교해 일치시켰다. source `error.dart`,
`migration_meta.dart`, `user_intent.dart`의 이번 FRB 전후 diff도 parameter,
return/nullability, variant/field를 바꾸지 않는 서식 변화뿐이었다. 그러므로
실제 모델·직렬화 계약 변화나 Rust API 신규 노출로 분류할 파일은 이 5개에 없다.

## 최소 release gate 경계

두 zero-diff 주장을 섞지 않는다.

| gate | canonical 절차 | 비교 대상 / 의미 |
| --- | --- | --- |
| **FRB wrapper canonical** | `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` 후 Dart formatter | 13개 wrapper가 FRB/API 정규 생성물인지 확인하는 좁은 gate. 여기에는 Freezed output은 포함하지 않는다. |
| **프로젝트 전체 generation canonical** | 위 FRB 절차 + `flutter pub run build_runner build --delete-conflicting-outputs` + Dart formatter | 13 wrapper **및** 이 보고서의 5개, 합계 18개를 비교한다. clean committed tree에서 위 절차 뒤 이 18개에 `git diff --exit-code -- <18 paths>`가 성공해야 한다. |
| **의존성 lock 별도 gate** | `flutter pub get` | `example/pubspec.lock` 변화는 codegen이 아니므로 별도 검토·승인 대상이다. 이를 해결하지 않고 전체 tracked tree zero-diff라고 주장하지 않는다. |

따라서 `flutter_rust_bridge_codegen generate` 단독을 committed-source zero-diff
gate로 삼으면 안 된다. generator의 formatter 전 intermediate 출력까지 잡히기
때문이다. release에서 무엇을 canonical으로 볼지 위의 명시적 pipeline으로 고정해야
한다.

## 전체 최소 채택 목록

이번 릴리스가 프로젝트 전체 generation zero-diff를 요구하는 경우, 승인 후
채택할 정확한 18개 파일은 다음이다.

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

1–13은 13번째 보고서의 FRB wrapper cohort다. 14, 16, 18은 stale Freezed
산출물이므로 build_runner를 release 절차에 포함한다면 릴리스 전 채택해야 한다.
15와 17은 독립 기능·계약 관점에서는 후속 format-only 정리로 미룰 수 있으나,
그 경우 이번 릴리스에 “프로젝트 전체 generation zero-diff” gate를 붙일 수 없다.
그 gate를 채택하는 현재 목표에서는 두 파일도 릴리스 전 필수다.

## 최소 검증과 다음 승인 조건

- 최종 canonical 5개는 이전 canonical snapshot과 모두 byte-for-byte 일치했다.
- `flutter analyze lib/src/rust/api`를 주 snapshot에서 실행해 `No issues found`를
  확인했다. 기능 계약 변화가 없어 Rust test 확대나 광범위 unit test는 실행하지
  않았다.
- 저장소에는 generated patch를 적용하지 않았다. 이 보고서 외 사용자 dirty 파일은
  보존한다.

다음 세션에서 18개를 실제 채택하려면 소유자가 현재 dirty 생성/API 변경을
patch 또는 stash 등으로 보존하는 방법을 먼저 승인해야 한다. 그 뒤 clean committed
HEAD에서 위 pipeline을 재실행하고, 명시 경로 18개만 검토·stage하며,
`example/pubspec.lock`은 별도 승인으로 다뤄야 한다. publish, push, PR, merge,
tag, yank는 이 세션에서 하지 않았다.

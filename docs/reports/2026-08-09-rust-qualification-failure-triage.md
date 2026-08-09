# Rust qualification failure triage — `0.20.0-dev.11`

**판정: B — 테스트 격리 문제이며, 출시 feature 조합의 직렬 전체 suite가 통과하면 이 항목은 companion 발행 비차단이다.**

이 문서는 Rust 코드나 테스트를 수정하지 않은 독립 진단 기록이다. `cargo test`
기본 병렬 실행의 실패는 실제 native ABI/컴파일 오류나 Q8_0 Model Pack 공개 경로의
제품 실패로 확인되지 않았다. 다만 공유 전역 상태를 가진 테스트 suite이므로, 이
repository의 Rust release qualification은 아래의 **직렬 전체 suite**여야 한다.

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --features 'vector_faer,vector_quant_i8' -- --test-threads=1
```

통과 기준은 lib test와 doc-test 모두 `0 failed`이다. 테스트를 제외하거나 필터로
통과시키는 명령이 아니며, `cargokit.yaml`의 profile/release feature 조합
`vector_faer,vector_quant_i8`도 포함한다.

## 범위와 입력

- 시작 checkout/HEAD: `feats/audit-extra-generated-files-dev11` /
  `bd805a9424b5ed0dcd24674e6eeafcd69526e7c2`.
- 진단 브랜치: `feats/triage-rust-qualification-dev11`.
- 시작 시점부터 존재한 dirty Dart/FRB 파일과 untracked 문서는 읽거나 수정하지
  않았고, 이후에도 stage/commit 대상이 아니다.
- 모든 재현 입력은 `git archive HEAD`로 각각 생성한 tracked-files-only snapshot:
  `/private/tmp/mobile-rag-rust-triage-21u0eK`,
  `/private/tmp/mobile-rag-rust-serial-3J6Xyt`,
  `/private/tmp/mobile-rag-rust-isolated-3RMOIk`,
  `/private/tmp/mobile-rag-rust-release-oI1zfL`.
- 도구: rustc `1.91.1 (ed61e7d7e, aarch64-apple-darwin)`, cargo `1.91.1`.
  `rust_builder/rust/Cargo.lock` SHA-256은
  `eea09647a5342ad68569ee25187ab2bd4638e3da7c72cbc555a51ad151ca0415`.
- 환경에는 `CARGO_HOME`과 `RUST_LOG=warn`만 있었고, RAG/VABQ 선택을 바꾸는
  환경변수는 없었다.

## 이전 기록과 이번 명령

12번째 clean-candidate 기록
(`2026-08-09-frb-generated-bindings-reconciliation.md`)은 기본 `cargo test`가
**159 passed, 25 failed, 10 ignored**였다고 요약했다. 14번째 관련 macOS process
linkage 기록은 release feature를 명시하고 직렬로 실행한

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib --features 'vector_quant_i8,vector_faer' -- --test-threads=1
```

에서 **185 passed, 10 ignored, 0 failed**를 기록했다. 그 뒤 `HEAD`까지
`rust_builder/rust`의 소스 diff는 없다.

이번 clean HEAD 재현은 다음과 같다.

| 조건 | 명령 | 결과 |
| --- | --- | --- |
| 기본 병렬 | `cargo test --manifest-path rust_builder/rust/Cargo.toml` | lib **163 passed, 21 failed, 10 ignored**. 첫 실패는 `custom_hnsw`의 864 대 789 blob 길이 assertion. |
| 기본 직렬 | `cargo test --manifest-path rust_builder/rust/Cargo.toml -- --test-threads=1` | lib **184 passed, 0 failed, 10 ignored**; doc-test **1 passed, 0 failed, 1 ignored**. |
| 단독 대표 | `cargo test ... --lib api::custom_hnsw::tests::bge_base_profile_survives_hnsw_save_and_load_without_q8_fallback -- --exact --test-threads=1` | **1 passed, 0 failed**. |
| 관련 모듈 단독 | `cargo test ... --lib api::hybrid_search::tests -- --test-threads=1` | **7 passed, 0 failed**. |
| release feature 직렬 전체 | 권장 명령과 동일 | lib **185 passed, 0 failed, 10 ignored**; doc-test **1 passed, 0 failed, 1 ignored**. |

따라서 이전 기본 병렬의 `159 + 25 = 184`와 이번 기본 병렬의
`163 + 21 = 184`는 같은 lib test 총수다. 이전 보고서는 25개의 정확한 이름을
남기지 않았으므로, 이번에 재현되지 않은 4개를 특정 테스트라고 꾸며 쓰지 않았다.
이는 실패 수가 스케줄에 따라 변하는 공유 상태 race라는 추가 근거다.

## 기본 병렬에서 실패한 목록과 분류

| # | 테스트 | 분류 | 기본 병렬의 관찰 오류 | 직렬/단독 근거 |
| ---: | --- | --- | --- | --- |
| 1 | `custom_hnsw::...bge_base_profile_survives_hnsw_save_and_load_without_q8_fallback` | VABQ 전역 상태 | blob 길이 `864`, 기대 `789` | 단독 통과 |
| 2 | `db_pool::tests::test_pool_stats` | 전역 DB pool | active/idle/max 수 assertion `2 != 4` | 직렬 통과 |
| 3 | `hybrid_search::tests::test_collection_filter_only_uses_post_filter_not_exact_scan` | DB/HNSW/BM25 공유 상태 | `UNIQUE constraint failed: sources.id` | 모듈 직렬 통과 |
| 4 | `hybrid_search::tests::test_hybrid_search_integration` | 전역 DB pool | `no such table: docs` | 모듈 직렬 통과 |
| 5 | `hybrid_search::tests::test_hybrid_source_filter_exact_scan_keeps_scoped_bm25` | 전역 DB pool | `no such table: sources` | 모듈 직렬 통과 |
| 6 | `hybrid_search::tests::test_scoped_exact_scan_skips_content_when_bm25_disabled` | 전역 DB pool | `no such table: sources` | 모듈 직렬 통과 |
| 7 | `ingest_session::tests::test_prepare_from_file_reads_txt_and_md_with_auto_strategy` | 전역 DB pool/temp fixture | `no such table: sources` | 직렬 통과 |
| 8 | `ingest_session::tests::test_prepare_from_utf8_empty_input_creates_zero_chunks` | 전역 DB schema | `no such column: embedding` | 직렬 통과 |
| 9 | `ingest_session::tests::test_prepare_from_utf8_matches_string_path` | 전역 DB pool | `DB pool is None` | 직렬 통과 |
| 10 | `ingest_session::tests::test_prepare_from_utf8_records_bytes_len_into_counter` | 전역 DB pool | `DB pool is None` | 직렬 통과 |
| 11 | `ingest_session::tests::test_prepare_from_utf8_rejects_invalid_bytes` | 전역 DB pool | `DB pool is None` | 직렬 통과 |
| 12 | `ingest_session::tests::test_prepare_new_source_creates_ready_session` | 전역 DB pool | `DB pool is None` | 직렬 통과 |
| 13 | `ingest_session::tests::test_prepare_pending_duplicate_resumes` | 전역 DB schema | `no such column: chunks.source_id` | 직렬 통과 |
| 14 | `ingest_session::tests::test_take_rejects_back_to_back_without_commit` | 전역 DB schema | `no such table: collections` | 직렬 통과 |
| 15 | `migration_meta::tests::clear_requires_confirmation_token` | 전역 DB schema | `NOT NULL constraint failed: chunks.source_id` | 직렬 통과 |
| 16 | `migration_meta::tests::future_axis_rejects_boot` | 전역 DB pool | `no such table: migration_meta` | 직렬 통과 |
| 17 | `migration_meta::tests::gate_mismatch_reports_remaining_chunks` | 전역 DB schema | `no such table: migration_meta` | 직렬 통과 |
| 18 | `migration_meta::tests::gate_requires_baseline_on_empty_fingerprint` | 전역 DB schema | `no such table: migration_meta` | 직렬 통과 |
| 19 | `semantic_chunker::tests::test_semantic_chunk_respects_tokenizer_budget_before_runtime_truncation` | 전역 tokenizer | tokenizer-budget assertion | 직렬 통과 |
| 20 | `source_rag::tests::add_chunks_fails_instead_of_storing_unreadable_mmap_reference` | DB/MMAP 공유 상태 | `database is locked` | 직렬 통과 |
| 21 | `source_rag::tests::add_chunks_rolls_back_when_mmap_append_fails` | 전역 DB pool | `DB pool is None` | 직렬 통과 |
| 22–25 | 이전 보고서에만 포함된 4건 | 미기록 스케줄 의존 실패 | 테스트 이름/first failure 미기록 | 이번 기본 병렬에서는 발생하지 않음; 184개 직렬 전체 통과 |

## 코드 근거와 원인

`db_pool.rs`의 `DB_POOL`은 프로세스 전역 `OnceCell<RwLock<Option<Pool<_>>>>`이고,
`init_db_pool`은 같은 전역 pool을 재초기화하며 `close_db_pool`은 `None`으로 만든다.
테스트들은 모듈마다 다른 고정 `temp_dir()` 파일명, 서로 다른 schema, 그리고
`init_db_pool`/`close_db_pool`을 사용한다. 따라서 한 모듈의 teardown이 다른
모듈의 실행 중 pool을 바꾸면 `DB pool is None`, 테이블/컬럼 누락, SQLite lock 및
중복 ID가 자연스럽게 발생한다.

추가로 HNSW searcher/builder, BM25 index, MMAP store, 그리고
`ACTIVE_VABQ_PROFILE`도 모두 프로세스 전역 `Lazy<RwLock<...>>`다.
`custom_hnsw` 테스트는 768차원 BGE profile을 선택해 789-byte blob을 기대하는 반면,
동시에 실행되는 다른 VABQ 테스트도 같은 profile을 설정/해제한다. 기본 병렬의
864 대 789 불일치는 이 공유 profile의 관찰 가능한 race다. `semantic_chunker`는
자체 tokenizer mutex가 있으나, 전역 tokenizer를 쓰는 다른 모듈과는 그 mutex를
공유하지 않는다.

`ingest_session`과 `source_rag`의 `test_guard`, `migration_meta`의 `POOL_GUARD`는
각각의 모듈 내부에서만 직렬화한다. 그들은 공통 DB pool/HNSW/BM25/MMAP/VABQ
상태를 사용하는 다른 모듈을 막지 못한다. 즉 고정 DB path, fixture asset, 또는
환경변수가 native ABI를 깨뜨렸다는 증거는 없고, 여기서 필요한 후속 작업은 제품
코드가 아니라 장기적으로 test fixture/state 격리 방식을 정리하는 것이다.

## 발행 및 hosted MiniLM 경계

- 이 실패는 **native library compile/runtime ABI 실패가 아니다.** clean HEAD의
  release feature 직렬 전체 suite가 통과했고, 이전 macOS linkage 보고서의
  Model Pack first-search/FRB process-symbol 증거와 모순되지 않는다.
- 실패 표본에는 VABQ 384/768 profile, HNSW/DB 연구·내구성 테스트가 포함되지만,
  그것이 VABQ 알고리즘 결함이라는 판정은 아니다. 단독과 직렬에서 모두 통과했다.
- Q8_0/Model Pack 공개 경로를 이 Rust 실패만으로 막지 않는다. 이 판정은 Rust
  qualification gate에 한정한다. 아직 필요한 clean codegen, package dry-run,
  실제 발행 후 override-free hosted consumer 검증은 별도의 gate이며 자동으로
  통과한 것이 아니다.
- 따라서 `rag_engine_flutter 0.20.0-dev.11` companion은 이 테스트 문제 때문에
  차단되지 않는다. 실제 publish, push, PR, merge, tag, yank는 이 세션에서 하지
  않았고 별도 사용자 승인이 필요하다.

## 결론

**B.** 기본 병렬 `cargo test`의 21–25개 변동 실패는 suite 내부의 전역 상태와
고정 temp DB/fixture 경합이다. clean HEAD에서 release feature를 포함한 직렬 전체
suite가 lib 185 통과/10 ignored, doc-test 1 통과/1 ignored로 끝났으므로, companion
발행 재시도 시 Rust qualification은 위 권장 명령을 실행해 `0 failed`를 확인하는
것으로 충분하다. 이 Rust gate는 비차단이다.

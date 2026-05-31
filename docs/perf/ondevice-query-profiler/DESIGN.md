# On-Device RAG Query Profiler — Design Spec

- 작성: 2026-06-01
- 상태: 설계 승인됨 (스펙 리뷰 대기)
- Linear: [LOC-65](https://linear.app/loceract/issue/LOC-65) · 프로젝트 [온디바이스 RAG 쿼리 프로파일러](https://linear.app/loceract/project/온디바이스-rag-쿼리-프로파일러-25df240c4262)
- 1차 목표: **실기에서 쿼리 1회의 단계별 지연을 분해**해 진짜 병목을 찾고, baseline을 박제(재실행/비교 가능)한다.

## 1. 배경 / 검증된 아키텍처 사실
직전 결론: vector_math 커널 슬라이스는 거의 최적이나, **온디바이스 RAG end-to-end는 미측정**이며 병목은 십중팔구 임베딩 추론 등 다른 곳. 이 프로파일러로 그걸 데이터로 확정한다.

설계의 전제는 모두 코드로 검증함:
- **One-Active-Collection 싱글톤**: `ACTIVE_HNSW_COLLECTION`/`ACTIVE_BM25_COLLECTION: RwLock<Option<String>>` ([source_rag.rs:55-56](../../../rust_builder/rust/src/api/source_rag.rs#L55)) + 단일 전역 `INVERTED_INDEX`([bm25_search.rs:24](../../../rust_builder/rust/src/api/bm25_search.rs#L24)) · 단일 전역 `HNSW_INDEX`([hnsw_index.rs:47](../../../rust_builder/rust/src/api/hnsw_index.rs#L47)). 한 번에 한 컬렉션만 warm.
- **컬렉션 스위치 비용은 별도 명시 호출 `activateCollectionForHybridSearch`에 있음** ([source_rag_service.dart:948/1453](../../../lib/services/source_rag_service.dart#L948)), `search_meta_hybrid` 본문에 숨지 않음. 활성화 시: BM25를 `bm25_clear_index()` 후 컬렉션 전 청크 재토큰화로 **디스크 영속 없이 재구축**([source_rag.rs:930-965](../../../rust_builder/rust/src/api/source_rag.rs#L930)); HNSW는 디스크 `load_hnsw_index`(또는 없으면 rebuild) + `Box::leak`([hnsw_index.rs:196](../../../rust_builder/rust/src/api/hnsw_index.rs#L196), [source_rag.rs:1018-1026](../../../rust_builder/rust/src/api/source_rag.rs#L1018)).
- **활성 컬렉션 내 쿼리는 BM25 재토큰화 0회** (0.18.4 픽스, term stats가 사전구축 active index에서 옴 — [hybrid_search.rs:215-218](../../../rust_builder/rust/src/api/hybrid_search.rs#L215)).
- **Filtered(source_ids) 검색은 i8 exact-scan 핫커널로 라우팅** ([hybrid_search.rs:183](../../../rust_builder/rust/src/api/hybrid_search.rs#L183) "switching to exact scan").
- 반복 스위치 시 `Box::leak`로 메모리 증가 — 메모리 측정 시 증가 지점(현 범위 밖, 기록만).

## 2. 목표 / 비목표
**In**: 쿼리 지연 단계분해(Phase1 coarse) + 조건부 Phase2 드릴다운, 컬렉션 스위치(A→B→A) 지터 측정, JSON/CSV export + 구조화 로그, 연결된 1대, 출시 설정(`vector_faer,vector_quant_i8`).
**Out(후속)**: 인덱싱 플로우 프로파일, 메모리/배터리, CI 회귀 게이트, iOS↔Android 비교, recall/품질 검증.

## 3. 접근법 — Approach C (단계적)
Phase1(coarse, Rust 0변경)로 큰 그림 + baseline → 데이터가 가리키는 버킷만 Phase2로 드릴다운. "측정 먼저, 입증된 곳만 손댄다" 원칙의 재귀 적용.

## 4. 측정 세그먼트 (쿼리/활성화 경로)
- `embed`: query 임베딩(ONNX, Dart) — Stopwatch
- `activate`: `activateCollectionForHybridSearch` — Stopwatch. **cold/switch에서 bm25-rebuild vs hnsw-load 의무 분해**(Phase2-activation)
- `search`: search FFI 총시간 — Stopwatch (warm steady-state에서 지배 시 Phase2-search로 ANN vs BM25-rank vs RRF 분해)
- `hydrate`: 콘텐츠 hydrate — Stopwatch
- I/O 카운터: `query_metrics` 스냅샷(쿼리 전후) — rows/bytes/tokenization nanos ([query_metrics.rs](../../../rust_builder/rust/src/api/query_metrics.rs))
- **FFI 오버헤드 수식(저널 명시)**: `Dart Stopwatch(segment) − Rust 내부 계측(segment) = 순수 FFI 마샬링 + Isolate 컨텍스트 스위치 비용`

## 5. 쿼리 2레인
- **Lane 1 Unfiltered**: 프로덕션 기본 패스 = f32 HNSW + BM25 via RRF.
- **Lane 2 Filtered**: `source_ids` 강제 주입 → i8 exact-scan 핫커널 (DRAM-bound 여부 실측).

## 6. Cold/Warm 분류 + 시나리오
- **Pure Cold**: 앱 최초 실행 후 첫 쿼리 (ONNX init + SQLite page cache cold).
- **Switching Cold**: 컬렉션 B 활성 상태에서 A로 전환 직후 첫 쿼리 — `activate` 세그먼트가 BM25 전체 재토큰화 + HNSW 디스크 재로드를 흡수.
- **Pure Warm**: 동일 컬렉션 연속 쿼리(2번째~).
- 필수 시나리오: **A 활성 → B 활성 → A 쿼리**(inter-collection 지터). 순수 warm만 재면 "가짜 초록"이 되므로 스위치 시나리오는 In.

## 7. Phase 게이트 (두 종류 분리)
- **Phase2-activation (cold/switch 의무)**: `activate`를 bm25-rebuild vs hnsw-load로 분해. Rust 계측 또는 기존 로그 타임스탬프 활용.
- **Phase2-search (조건부)**: warm steady-state에서 `search`가 지배하면 Rust `QueryTimings`(thread-local Instant, `query_metrics` 패턴, FFI 스냅샷)로 ANN/BM25-rank/RRF 분해.
- **embed 지배 시**: Rust 계측 불필요 → 다음 대상은 추론(ONNX, 크레이트 밖). 그 사실이 결론.

## 8. 컴포넌트
- **고정 픽스처**: 결정적 코퍼스(시드 N청크) + 최소 2개 컬렉션(A/B, 스위치용) + 고정 쿼리셋(M개, 두 레인). 출시 feature.
- **프로파일 드라이버**(`integration_test/query_profile_test.dart`): warmup→measured 루프, 세그먼트 측정 + `query_metrics` 스냅샷. `benchmark_service.dart`의 `collectSamples`/`_percentileFromSorted`/`_stdDev` 재사용.
- **결과 모델 + 익스포터**: `QueryProfileSample`(레인/카테고리/세그먼트별 ms, I/O 카운터, 실행 메타) → app docs dir에 JSON+CSV, 실행당 로그 1줄. 가능하면 `benchmark_models.dart` 재사용.
- **(Phase2-search 조건부) Rust `QueryTimings`**: search 내부 단계 Instant + FFI 스냅샷/reset.

## 9. 데이터 흐름 (측정 쿼리 1회)
`query_metrics reset → [필요시 activate(A) 측정] → t0 → embed(query) → t1 → search(emb,top_k,filter?) → t2 → hydrate(top_k) → t3 → metrics snapshot`. 세그먼트 = embed/activate/search/hydrate. N회 후 카테고리·레인별 p50/p95/mean/stddev 집계 → export.

## 10. 방법론 / 타당성
- warmup 폐기(JIT·파일캐시·ONNX 세션·page cache). Pure Cold/Switching Cold는 별도 1회성 측정으로 분리 기록.
- 기기 상태 export 메타에 기록: **충전 연결(써멀 스로틀 방지)**, 화면 ON, 백그라운드 최소화.
- fail-closed: measured N>0 & 각 세그먼트 기록 검증(PDF 스모크식). 원시 샘플 JSON 보존.
- 오버헤드: Stopwatch/atomics는 ms 스케일 대비 무시 가능 — 명시.
- export 메타: 기기/OS, 코퍼스 크기, top_k, feature 플래그, 레인, 카테고리, HNSW/exact, 충전상태.

## 11. 산출물 (export 스키마 핵심 필드)
`{device, os, ts, corpus_size, top_k, features, lane, category, segments_ms:{embed,activate,hydrate,search}, search_breakdown_ms?:{ann,bm25,rrf}, activate_breakdown_ms?:{bm25_rebuild,hnsw_load}, io:{rows,bytes,tok_nanos}, ffi_overhead_ms, samples:[...], p50/p95/mean/stddev per segment}`

## 12. 테스트 (하니스 자체 검증)
세그먼트 합 ≈ end-to-end 총시간(sanity), 결정적 코퍼스→재현 카운트, 연결 기기에서 green, fail-closed 동작.

## 13. 미해결/후속 (Out)
인덱싱 플로우, 메모리(Box::leak 누수 포함)·배터리, CI 회귀 게이트, iOS↔Android 비교, recall/품질. 1차(프로파일링) 종료 후 데이터 기반 재평가.

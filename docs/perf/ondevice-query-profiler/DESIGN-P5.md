# On-Device RAG Query Profiler — Phase 2 Design Spec (P5)

- 작성: 2026-06-01
- 상태: 설계 (P3/P4 머지 후 착수)
- Linear: [LOC-70](https://linear.app/loceract/issue/LOC-70) · 프로젝트 [온디바이스 RAG 쿼리 프로파일러](https://linear.app/loceract/project/온디바이스-rag-쿼리-프로파일러-25df240c4262)
- 선행: [DESIGN.md](DESIGN.md)(Phase-1 스펙) · [PLAN.md](PLAN.md) · P3([#72](https://github.com/dev07060/mobile_rag_engine/pull/72)) · P4([#73](https://github.com/dev07060/mobile_rag_engine/pull/73))
- 목표: latency baseline을 넘어 **검색 품질 · 동시성 경합 · 스케일 한계**를 실기 숫자로 증명한다.

---

## 1. 배경 — Phase-1이 답한 것과 답하지 못한 것

P1–P4(LOC-66~69)로 **지연(latency) baseline**을 확보했다(iPhone iOS 26.5, profile 빌드, 출시 `vector_faer,vector_quant_i8`, 컬렉션당 500 docs):

| lane | category | embed | activate | search | hydrate |
|---|---|---|---|---|---|
| unfiltered | pure_cold (n=1) | 25.2 | **247.3** | 2.20 | 0.42 |
| unfiltered | pure_warm (n=30) | **26.7 / 36.7** | — | 1.60 / 2.08 | 0.27 / 0.41 |
| filtered(i8) | pure_warm (n=30) | **27.6 / 37.6** | — | 0.76 / 0.92 | 0.19 / 0.30 |
| unfiltered | switching_cold (n=30) | 25.7 / 37.0 | (콘솔 트렁케이션 유실) | 1.47 / 1.90 | (유실) |

**결론:** warm은 `embed`(ONNX) 지배(~27ms, 타 세그먼트 15–37배), cold는 `activate`(HNSW build/load) 지배(247ms).

**그러나 baseline은 지연만 측정한다.** 측정하지 못한 것:
1. 실제 출시 경로의 **검색 품질(recall)** — i8-HNSW + BM25 RRF가 정답을 얼마나 놓치는가.
2. 멀티 컬렉션 **동시성 경합**으로 인한 지터·랭킹 오염.
3. 후보 문서 수가 늘 때 `filtered` 레인의 **SQLite I/O 스케일 한계**.

> ⚠️ LOC-64의 `recall@10 = 0.997`은 **i8 exact-scan vs f32 전수조사의 수학적 충실도**(양자화 커널 정확도)일 뿐, 그래프 검색 품질이 아니다. "i8 빠름 + 0.997"을 "출시 검색 품질 우수"로 읽으면 안 된다.

---

## 2. 검증된 아키텍처 사실 (재도출 금지)

코드 오딧으로 확정한, P5 측정 설계의 전제. 모두 file:line으로 검증됨.

### 2.1 ⚠️ HNSW는 출시 빌드에서 **i8-dequant 벡터** 위에 빌드된다
`rebuild_chunk_hnsw_index_for_collection`(source_rag.rs:886-899)는 `#[cfg(feature = "vector_quant_i8")]`에서 다음을 수행한다:

```rust
let embedding = if let (Some(qblob), Some(scale)) = (embedding_i8_blob.as_deref(), embedding_scale) {
    let restored = dequantize_i8_to_f32(&i8_vec_from_blob(qblob), scale); // ← i8 복원본
    if restored.is_empty() { decode_f32_embedding_or_warn(&embedding_blob, id) } else { restored }
} else {
    decode_f32_embedding_or_warn(&embedding_blob, id) // 원본 f32는 i8 부재 시 fallback
};
// build_hnsw_index(points: Vec<(i64, Vec<f32>)>) ← 위 embedding을 투입
```

HNSW 타입은 `Hnsw<'static, f32, DistCosine>`(hnsw_index.rs:47)지만 **값은 i8 복원본**이다. 즉 출시 그래프는 **찌그러진 i8 공간**을 탐색한다. 따라서 §3.1의 recall은 **그래프 근사 오차 + i8 양자화 왜곡을 동시에** 잰다.

### 2.2 전역 단일 인덱스 슬롯 + RwLock
- `HNSW_INDEX: Lazy<RwLock<Option<Hnsw<'static, f32, DistCosine>>>>`(hnsw_index.rs:47) — 프로세스 전역 **단일 슬롯**(모든 컬렉션 공유, per-collection 인덱스 없음).
- `ACTIVE_HNSW_COLLECTION: Lazy<RwLock<Option<String>>>`(source_rag.rs:55).
- activate = write lock으로 인덱스 교체, search = read lock(hnsw_index.rs:252).
- `data_generation` 가드(source_rag.rs:1492/1577)는 컬렉션 내부 mutation만 막고 **전역 active-collection 스왑은 막지 못한다** → in-flight search 중 스왑 시 stale 인덱스/cross-collection 오염 가능.

### 2.3 activate(247ms) 구성
`activate_collection_for_hybrid_search`(source_rag.rs:1006-1030)는 순차로:
- (a) **BM25 인메모리 재구축** — 전체 chunk `SELECT c.id, c.content`(source_rag.rs:930-968) + 재토큰화(bm25_search.rs:280-287). **O(n)** → 문서 수 증가 시 thrashing 위험.
- (b) **HNSW 디스크 load** — `.hnsw.data/.graph` 역직렬화 + `Box::leak`(hnsw_index.rs:167-214, :196). load 실패 시 (c) DB로부터 rebuild(§2.1).

### 2.4 `filtered` exact-scan I/O
filtered(sourceIds) 레인은 행마다 `(c.id, c.embedding f32, c.embedding_i8)`를 fetch하며 SQLite cursor stepping(hybrid_search.rs:229-260, 274-315). i8 dot 커널은 zero-copy ~29µs(benches/vector_math.rs:136-161)지만, 실기 0.76ms는 **SQLite stepping + blob fetch I/O가 지배**한다. `scoped_exact_scan_rows`는 증가 지점이 없어 항상 0(미계측).

### 2.5 FRB 직렬화
flutter_rust_bridge는 isolate당 FFI 호출을 **직렬화**한다(rag_engine.dart:76, 86-97; async task executor 미사용). → 순수 Dart isolate 2개로는 Rust 내부 경합이 재현 안 될 수 있다(§3.3 참고).

---

## 3. 측정 타깃

각 타깃은 P3/P4 하니스(`example/lib/profiling/`, `example/integration_test/query_profile_measure_test.dart`)를 확장한다. 계측 hook은 `query_metrics.rs`(snapshot/reset + `#[frb(sync)]`) 패턴을 미러한다.

### 3.1 e2e 하이브리드 리콜 실측 (품질, 1순위)

**목표.** 폰에서 `[원본 f32 전수조사 top-K]`(ground truth) 대비 `[출시 searchMetaHybrid = i8-HNSW + BM25 RRF top-K]`의 교집합률 `recall@10`을 산출. vector-only(bm25_weight=0) 변형으로 BM25 간섭을 분리.

**앵커.** §2.1(HNSW i8-dequant). 원본 f32 = `chunks.embedding` blob(source_rag.rs:291) + `decode_f32_embedding`(vector_math.rs:23-31). RRF k=60(hybrid_search.rs:417-462). `ef_search = max(100, topK*5)`, M/ef_construction는 코퍼스 크기별 **const**(hnsw_index.rs:69-75, 259) — 런타임 튜닝 API 없음.

**레시피 (feasibility: no Rust change — Dart-side 권장).**
```text
1. clearAllData → seed(N) → 인덱스 warm
2. 결정적 쿼리셋 Q(임베딩 freeze: 1회 계산 후 고정)
3. for q in Q:
   GT  = Dart-side: SELECT c.id,c.embedding FROM chunks WHERE collection_id=?
         → ByteData.asFloat32List() → f32 cosine → top-10 chunkId
   PROD= searchMetaHybrid(q).hitMeta() → top-10 chunkId
   recall@10 = |GT ∩ PROD| / 10
4. 평균 + per-query 분해(vector-dominated vs bm25-dominated)
```
(대안 A: feature-gated Rust `brute_force_f32_cosine_search` — 정밀도/속도↑, 단 Rust 빌드 필요.)

**판정.** `recall < 0.90` → 모바일용 M/ef_search 상향(현재 const → config/const 변경 필요). → 상용 "컬렉션별 자동 품질 보증(SLA)·파라미터 최적화"의 단가 근거.

**위험.** 쿼리 임베딩 freeze(부동소수 변동), i8 on/off 변형 비교(왜곡 격리), 코퍼스 분포 편향(within/cross-cluster 분해 보고).

### 3.2 `activate`(247ms) 내부 분해 (cold 게이트, 의무)

**목표.** 247ms를 (a) BM25 rebuild vs (b) HNSW load vs (c) HNSW rebuild로 분리.

**앵커.** §2.3.

**계측 델타 (feasibility: needs-rust-change — 1 hook).** `query_metrics.rs` 패턴 미러:
```rust
// source_rag.rs
pub struct ActivateTimings { pub bm25_rebuild_nanos: u64, pub hnsw_load_nanos: u64,
                             pub hnsw_rebuild_nanos: u64, pub total_nanos: u64 }
// activate_collection_for_hybrid_search 안에 Instant::now() 5지점 (entry / bm25후 / load후 / rebuild후 / return전)
#[frb(sync)] pub fn get_activate_timings() -> ActivateTimings { ... }
#[frb(sync)] pub fn reset_activate_timings() { ... }
```
하니스: cold activate 직후 `getActivateTimings()` 스냅샷.

**판정.** BM25가 doc 수에 선형 폭발 → 인메모리 토큰 캐시. HNSW load I/O 지배 → 커넥션 풀링/포맷 최적화. → 오케스트레이터 아키텍처 우선순위.

**위험.** `Instant::now()` ~50–100ns × 5 = 무시 가능. load 실패→rebuild 분기 시 실패한 load 시간도 포함(주석 명시). BM25는 doc 수가 아니라 **총 토큰 수**에 비례(고변동 시 하위 계측 필요).

### 3.3 동시성 스위칭 지터 + 랭킹 무결성 (아키텍처 사각지대)

**목표.** `search 루프` vs `0.5s마다 컬렉션 activate 스왑` 동시 구동 → search p50/p95/max 지터(baseline 1.6ms 대비)와 잘못된 컬렉션 데이터 유입 에러율.

**앵커.** §2.2 (전역 싱글톤 + data_generation 미가드).

**⚠️ 측정 한계(검증됨).** §2.5 — FRB 직렬화로 **순수 2-isolate 하니스로는 진짜 경합이 재현 안 될 수 있다.** 두 경로:
- (a) Rust 내부 `thread::spawn` 스트레스(또는 `compute_hybrid_rrf_scores`의 `thread::scope` 활용)로 진짜 동시 read/write 강제.
- (b) **더 확실한 산출물:** 랭킹 무결성 가드 — hydrate 전 `chunk.collection_id ⊆ handle.collection_id` 검사 + `RankingIntegrityViolation` 에러. 위반이 잡히면 전역 싱글톤이 동시성에서 깨짐을 **물리적으로 입증**.

**계측 델타 (feasibility: needs-rust-change).** lock-hold/activate-during-flight 카운터(`lock_contention_metrics.rs`, query_metrics 패턴) + (b)의 무결성 가드(hydrate 경로 + `RagError::RankingIntegrityViolation`).

**판정.** 무결성 위반 **0**이어야 함. 위반 시 → 상용 Rust `CollectionRouter`(per-collection 격리 레지스트리)가 동시성 크래시·데이터 누수를 막는다는 방어선(Moat)의 근거.

### 3.4 SQLite I/O 스케일 한계 (`filtered` lane)

**목표.** 후보 row 수 ↔ filtered `search` ms 상관. row 수 스윕(10→5k)으로 `search`가 `embed`(27ms)를 역전하는 **임계점(Inversion Point)** 산출.

**앵커.** §2.4. `scoped_exact_scan_rows`는 미계측(증가 지점 없음); `hybrid_result_rows`는 top_k 출력 수일 뿐 평가 후보 수가 아님.

**계측 델타 (feasibility: needs-rust-change — 1 counter).**
```rust
// query_metrics.rs: 새 카운터 SCOPED_EXACT_SCAN_ROWS_EVALUATED + record_*(count)
// QueryContentReadStats에 scoped_exact_scan_rows_evaluated 필드 추가
// hybrid_search.rs:314 (행 추출 성공 직후) record_exact_scan_rows_evaluated(1)
```
하니스: 단일 source에 N∈{10,100,500,1k,2k,5k} chunk 시드 → filtered search → `search` ms vs rows_evaluated 플롯.

**판정.** 임계 `N_critical` → "컬렉션당 최대 문서 수 권장(예: 5,000)" 오픈소스 스케일 한계선 문서화.

**위험.** SQLite 캐시 cold/warm·WAL·source_id 인덱스 카디널리티 고정. f32 blob(4·dim) vs i8 blob(dim) 비용 분리. candidate_k = 4·top_k(hybrid_search.rs:119)라 평가 후보 ≠ 최종 결과. BM25 leg 비용(bm25_weight>0) 합산 측정.

---

## 4. 하니스 델타 / 산출물

- `example/integration_test/`: recall / jitter / scale 시나리오 테스트(측정은 §P3와 동일하게 `flutter drive --profile`).
- `example/lib/profiling/`: GT 계산(Dart-side f32 brute-force), 시나리오 러너 확장.
- Rust hook: `ActivateTimings`(§3.2), `scoped_exact_scan_rows_evaluated`(§3.4), lock/무결성 가드(§3.3) — 모두 `query_metrics.rs` 패턴.
- `PR-P5.md` + Linear 결과 박제. **품질<0.90 · 무결성 위반 · 스케일 임계**는 각각 상용 기능(품질 SLA, `CollectionRouter`, 스케일 가드)의 근거.

## 5. 시퀀싱

1. **선행:** P3(#72)→main 머지, P4(#73)를 main으로 retarget 후 머지.
2. main에서 `feat/loc-70-*` 분기. **§3.1 e2e 리콜**(무 Rust 변경, Dart-side)을 1순위로 — 가장 빠르게 품질 숫자 확보.
3. §3.2 activate 분해(cold 게이트, 의무) → §3.4 스케일 → §3.3 동시성(가장 무거움, Rust 변경 多).
4. 각 타깃은 독립 측정 가능 — 데이터가 나오는 대로 PR-P5.md/Linear 갱신.

## 6. 코드 앵커 인덱스

| 주제 | 위치 |
|---|---|
| HNSW i8-dequant 빌드 | source_rag.rs:886-899 |
| HNSW 타입/슬롯/params | hnsw_index.rs:47, 69-75, 252, 259 |
| HNSW load (Box::leak) | hnsw_index.rs:167-214 (:196) |
| activate 진입 | source_rag.rs:1006-1030 |
| BM25 rebuild (O(n)) | source_rag.rs:930-968 · bm25_search.rs:280-287 |
| ACTIVE_HNSW_COLLECTION | source_rag.rs:55 |
| data_generation 가드 | source_rag.rs:1492, 1577 |
| RRF 융합 | hybrid_search.rs:417-462 |
| filtered exact-scan SQL/loop | hybrid_search.rs:229-260, 274-315 |
| 원본 f32 / decode | source_rag.rs:291 · vector_math.rs:23-31 |
| query_metrics 패턴 | query_metrics.rs:179-225 |
| FRB 직렬화 | rag_engine.dart:76, 86-97 |
| i8 커널 벤치 | benches/vector_math.rs:136-161 |

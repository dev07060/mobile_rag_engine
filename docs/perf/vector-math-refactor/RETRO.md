# 회고 (RETRO) — vector_math 리팩터링

작성: 2026-05-30. 착수 가설([00-review-and-analysis.md](00-review-and-analysis.md))과 실제 결과 대조 +
[risk-register.md](risk-register.md) 처리 결과 확정.

## 1. 무엇을 바꿨나 (PR별)
- **PR0** ([#63](https://github.com/dev07060/mobile_rag_engine/pull/63), 🟩): 작업 저널 스캐폴드 — PR 단위 결과/피드백 보존 체계.
- **PR1** ([#64](https://github.com/dev07060/mobile_rag_engine/pull/64), 🟩): criterion 벤치 + faer/fused 패리티 안전망. **핵심 발견의 출처.**
- **PR2** ([#65](https://github.com/dev07060/mobile_rag_engine/pull/65), 🟩): 출시 faer+quant 백엔드를 CI에서 빌드+테스트(N2 닫음). *원안 "faer 제거"에서 피벗.*
- **PR5** ([#66](https://github.com/dev07060/mobile_rag_engine/pull/66), 🟩): 손상 블롭 `log::warn`(N6) + 엔디안 문서화(N5).
- **PR3** ❌ 폐기(출시 i8 빌드서 f32 decode 비핫 — §5), **PR4** ❌ 폐기(faer 유지로 무의미).

## 2. 측정 결과 (가설 대조)
- **착수 가설(틀림):** "faer가 1-D 닷에서 fused보다 느리니 제거하고 fused로 통일하면 빨라진다."
- **PR1 실측(반증):** faer가 **2–8× 빠름** (cosine 768 3.3×, dot 1536 7.8×, **exact_scan 2000×768 2.8×**). decode는 백엔드 무관(=, sanity ✓).
- **원인:** f32 리덕션은 fast-math 미허용으로 **자동 벡터화 안 됨 → fused는 스칼라(latency-bound)**. faer는 SIMD gemm 마이크로커널.
- **정적 분석은 옳았으나 결론이 틀린 부분:** N1(호출당 힙 할당)·2-pass는 실재 → 그러나 **throughput에 무의미**(4000회 할당하는 scan에서도 faer 우위). "분석으로 옳아 보여도 측정 없이는 방향을 틀린다"의 표본.
- 캐비엇: 수치는 개발기(Apple Silicon). 방향(스칼라 vs SIMD)은 폰 NEON에서도 견고 예상, 크기는 온디바이스 프로파일로 확인 권장(미수행).

## 3. 리스크 처리 결과
- **R1**(배치 gemv 경로) 🟩 — faer 유지로 경로 보존.
- **R2**(수치 변동) 🟩 — 백엔드 교체 없음. (참고: 컷오프 의존 0, RRF 랭크 기반 — 분석 §3에서 코드 근거 확정.)
- **R3**(스칼라 throughput-bound) 🟥 확정 — 단 faer 유지로 **출시 문제 아님**.
- **R7**(엔디안 호환성) 🟩 — PR5는 포맷 미변경(문서화).
- **R9**(PR2 전제 반증) 🟩 — faer 유지 확정 + PR2를 N2로 전환.
- **N2**(출시 백엔드 CI 미검증) 🟩 — PR2가 빌드+테스트 게이트 추가.
- **N6**(손상 무음 드롭) 🟩 — PR5 `log::warn`.
- **R5**(스택 PR 고아화) 🟨 — 매 PR을 main 머지 후 분기하여 회피(스택 안 씀).
- **R8**(SQLite 테스트 플레이크) 🟨 — `--test-threads=1` 고정 유지.
- **미해결/잔여:** R3(고차원 스칼라)는 faer 유지로 비활성. 온디바이스 실측 미수행(아래 후속).

## 4. 배운 점 / 다음에 다르게 할 것
- **"측정 먼저" 원칙이 회귀(2.8–8×)를 막았다.** 코드 리뷰(외부 + 자체)가 만장일치로 틀린 방향을 가리켰고, 벤치 한 번이 뒤집었다. 성능 변경은 **파괴 전 벤치 PR을 선행**한다 — 이번 워크플로(PR1→PR2)를 표준으로.
- **f32 리덕션 = 스칼라**라는 사실은 일반적으로 재사용 가능한 교훈(다른 핫 루프에도 적용).
- 정적 분석은 "무엇이 비싼가"는 잘 잡지만 "무엇이 지배적인가"는 못 잡는다 → 둘을 분리해서 말할 것.

## 5. 후속 작업 (다음 세션)
- **[LOC-61] PR3 — ❌ 폐기 확정** (2026-05-30, 코드 검증). 출시 빌드(`vector_faer,vector_quant_i8`)에서 per-candidate 스캔의 1차 경로는 `cosine_with_query_norm_i8_blob`(무디코드·무할당, [hybrid_search.rs:281](../../../rust_builder/rust/src/api/hybrid_search.rs)); `decode_f32_embedding`는 i8 blob 누락 시 폴백일 뿐이고, 순수 f32 스캔 루프는 `#[cfg(not(feature="vector_quant_i8"))]`라 릴리스에 컴파일조차 안 됨 → **f32 decode는 출시 핫패스 아님**. Gate2: PR1에서 alloc은 throughput 비지배(faer가 row당 alloc을 더 안고도 2.8× 우세). 두 게이트 모두 실패 → 폐기. 적대적 검증 3개 렌즈 전부 결론 유지.
  - ⚠️ **dequant ≠ decode 뉘앙스**: 유일하게 출시 빌드에서 row당 `Vec<f32>`를 만드는 곳은 HNSW 빌드 루프지만, i8 빌드의 1차 arm은 `dequantize_i8_to_f32`([vector_quant.rs:34](../../../rust_builder/rust/src/api/vector_quant.rs))로 **이것도 row당 할당**이며 비용은 `Hnsw::insert`가 지배. PR3의 decode 버퍼 재사용은 이 경로에 적용 대상조차 아님. 향후 HNSW-빌드 할당을 미세최적화한다면 타깃은 *dequant* 경로지 decode가 아님.
- **온디바이스 벤치**: 실제 폰(arm64)에서 faer 우위 크기 확인(선택).
- **공유 encode 헬퍼**: 5개 인코딩 사이트(`to_ne_bytes`) dedup + 원하면 LE 정규화(저가치).
- **(선택) N1 무할당 faer**: `faer::linalg::matmul`로 결과 할당 제거 — throughput 무의미하므로 마이크로옵트로만.

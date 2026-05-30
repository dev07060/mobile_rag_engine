# 00 — 리뷰 및 분석 (보존: 작업 착수 근거)

작성: 2026-05-30. 대상: `rust_builder/rust/src/api/vector_math.rs` (전부 검증 완료, 코드 인용 기준).

## 0. 어떤 백엔드가 출시되는가 (가장 중요한 컨텍스트)
- `Cargo.toml`: `default = []` → 기본은 **fallback 백엔드**.
- `cargokit.yaml:5`: release 빌드가 `--features vector_faer,vector_quant_i8` 주입 → **출시 = faer**.
- 따라서: 디버그/`cargo test` = fallback, **release = faer**. 즉 단위 테스트는 출시되는 faer 경로를
  한 번도 검증하지 않음(테스트 갭, 아래 N2).
- faer 사용처는 이 파일 1곳뿐 (`use faer::MatRef` + `MatRef * MatRef`), 다른 사용처 0건.

## 1. 외부 리뷰 3개 주장 판정
### Claim 1 — `decode_f32_embedding` "가짜 무할당", "가장 심각" → **메커니즘 맞음 / 심각도 과장 / 제안 해법 위험**
- `collect()` 가 행마다 `Vec<f32>` 힙 할당하는 것은 사실. 스캔 루프 per-row 호출 확인
  (`hybrid_search.rs:274-315`, `source_rag.rs:2333-2382`, `simple_rag.rs:449-471`).
- 그러나 "가장 심각"은 틀림:
  - 제안된 zero-copy `&[u8]→&[f32]` 캐스팅은 **언사운드**. SQLite 블롭/`Vec<u8>` 버퍼는 4-byte 정렬
    미보장 → `bytemuck::cast_slice` 패닉 또는 `unsafe` UB. 현재 `chunks_exact(4)+from_ne_bytes` 가
    오히려 **정렬·엔디안 안전한 정답**.
  - 출시 빌드는 `vector_quant_i8` 라 루프 안에서 **i8 경로 우선**, f32 decode는 폴백 분기
    (`hybrid_search.rs:279-307`). i8 인덱싱 DB에선 핫 패스가 아닐 수 있음.
- 올바른 해법: 언세이프 캐스팅이 아니라 **재사용 버퍼** (`decode_..._into(&[u8], &mut Vec<f32>)`).

### Claim 2 — faer 2-pass vs fallback 단일패스 → **사실이나 과소평가**
- faer 경로는 target을 두 번 읽음(`l2_norm_f32(target)` 후 `dot_f32(query,target)`) — `vector_math.rs:87-91`. 사실.
- 더 큰 비용을 놓침: `lhs.transpose() * rhs` (`:65`) 는 **소유 `Mat<f32>` 를 힙 할당**(1×1라도).
  → cosine 1회당 힙 할당 **2회** + matmul 디스패치 2회. 이것이 출시 바이너리에서 "allocation-free"
  주석을 실제로 깨는 지점(= N1).
- "faer가 384/768에서 느릴 것"은 타당하나 **미측정 가설** → 벤치 필요.

### Claim 3 — 1-D 행렬 추상화 오버헤드 → **인정, 방향 정확**
- `MatRef`+`transpose()`+matmul은 닷곱엔 과함(할당+gemm 디스패치 지배).
- 단 `pulp`/`std::simd` 이전에 **fused 스칼라 루프**(이미 fallback에 존재)가 가장 단순·빠른 정답.
- ⚠️ 보정: 리뷰가 말한 "LLVM 자동 NEON 벡터화"는 **f32 리덕션에선 기본적으로 안 일어남**
  (Rust는 fast-math 재결합 비허용). 진짜 처리량은 **다중 누산기 언롤**로 의존성 체인을 끊어야 유도됨(= PR4).

## 2. 외부 리뷰가 놓친 부분 (신규)
| # | 심각도 | 내용 |
|---|--------|------|
| N1 | 높음 | faer `dot_f32` 가 호출당 `Mat` 힙 할당 → 출시 핫 패스 cosine당 2회 (`vector_math.rs:65`). 진짜 무할당 위반. |
| N2 | 높음 | 테스트 갭: 테스트는 fallback만, 출시는 faer. faer 수치/할당 미검증. |
| N3 | 컨텍스트(중요) | 출시 빌드 `vector_quant_i8` → f32 decode/cosine은 폴백 분기. Claim1 우선순위 재평가. |
| N4 | 낮음 | `cosine_f32` fallback 3-pass 비융합 (`:34-46`), 단 콜드 패스(`simple_rag.rs:62`). |
| N5 | note | `from_ne_bytes` 네이티브 엔디안 — 모바일(LE) OK이나 DB 이식 함정. |
| N6 | 낮음 | `decode_..().unwrap_or_default()` 가 손상 블롭을 빈 벡터→cosine 0으로 조용히 흡수. |

## 3. faer 제거의 trade-off (검증됨)
- **Trade-off 1 (본체)**: faer의 진짜 강점은 1-D 닷이 아니라 **배치 gemv**(query × 전체후보행렬).
  현재 코드는 안 쓰지만, 대규모 exact scan을 빠르게 만드는 정석 경로 → 제거 시 그 길을 닫음(재도입은 가능).
- **Trade-off 2 (실효 ≈ 0, 코드 근거)**: 수치 ~1e-6 변동의 노출 범위.
  - Rust 검색은 전부 `sort + top_k`, **유사도 임계값 컷오프 0건**.
  - 하이브리드는 **랭크 기반 RRF**(`hybrid_search.rs:81-82, 446-450`) → raw 점수 미세변동 흡수.
  - 유일한 컷오프 `minSimilarity>=0.2`는 **순수 Dart 구현**(`prompt_compressor.dart:207,311-325`) → Rust 커널 무관.
  - 계산값 exact 단언 테스트 0건 (가드 리터럴 0.0 / 0.9 마진뿐).
  - 실효: top_k 내 ~1e-6 동률 항목의 상대 순서가 바뀔 수 있음 — 이미 SQLite row-order tie-break 비결정성 범위.
    통일하면 오히려 **test == prod** (이득).
- **Trade-off 3 (제한적)**: 고차원·대량 linear scan에서 스칼라 fused가 throughput-bound 가능 →
  PR4(언롤)로 보완. 단 출시 핫패스는 i8라 영향 제한적.

자세한 대화 맥락 요약은 PR1 본문 및 [risk-register.md](risk-register.md) 참조.

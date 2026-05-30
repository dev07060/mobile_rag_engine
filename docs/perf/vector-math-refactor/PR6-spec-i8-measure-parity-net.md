# PR6 설계 스펙 — i8 출시 핫패스 측정 + ε/recall 안전망 [측정 먼저]

- 작성: 2026-05-31
- 상태: 📝 설계(브레인스토밍 산출물) — 승인 후 writing-plans로 구현 계획 작성
- Linear: [LOC-64](https://linear.app/loceract/issue/LOC-64)
- 브랜치: `feat/loc-64-i8-measure-parity-net` — base = `main` (PR #67 머지 완료, `1217123`). 스택 트랩 회피됨.
- 접근법: **A — "PR1 리플레이, i8로 확장"**

## 1. 배경 / 왜 (Problem)

이번 세션의 코드 검증으로 드러난 사실: **출시 빌드(`vector_faer,vector_quant_i8`)의 per-candidate 핫패스는 i8 경로**(`cosine_with_query_norm_i8_blob`)인데,

- 그동안의 모든 리뷰·벤치(PR1 포함)·faer/fused 논쟁은 **f32 경로**를 봤고, f32는 출시 빌드에선 **폴백**이다.
- 정작 출시되는 i8 핫커널은 **마이크로벤치 0개**(`benches/vector_math.rs`는 f32 dot/l2/cosine/decode만).
- i8 양자화의 **검색 품질(랭킹/리콜)을 검증하는 테스트가 없다**. 기존 i8 테스트([vector_quant.rs:129-200](../../../rust_builder/rust/src/api/vector_quant.rs))는 (a) quantize↔dequantize 라운드트립 오차 `<0.05`, (b) 거친 방향 sanity(`>0.9`/`<-0.9`), (c) blob↔slice 진입점 일치(`<1e-6`)뿐 — **양자화가 근접 이웃 top-k 순위를 뒤집는지는 미검증**.

따라서 "어떤 커널도 바꾸기 전에 지금 상태를 박제한다"는 PR1 원칙을, 이번엔 **출시 핫패스(i8)** 에 적용한다. 이 PR이 머지되면 향후 i8 변경이 검색 품질을 무너뜨릴 때 CI가 수학적으로 차단한다.

## 2. 비목표 (Non-goals)

- **커널/양자화 코드 변경 0줄.** 이 PR은 측정 + 안전망만. i8 최적화는 이 네트 위에 별도 PR로.
- f32 경로 재측정/재설계 아님(PR1에서 완료, faer 유지 확정).
- 온디바이스 벤치 아님(별도 선택 작업).

## 3. 컴포넌트 1 — 측정 (bench)

- `src/bench_api.rs`에 i8 표면 노출(`#[cfg(feature = "bench")]`, 기존 f32 노출과 동일 패턴): `quantize_f32_to_i8`, `l2_norm_i8`, `cosine_with_query_norm_i8_blob`, `i8_blob_from_slice`. (대상 함수는 이미 `pub` — 가시성 변경 불필요, re-export만.)
- `benches/vector_math.rs` 추가 타깃:
  - `bench_cosine_i8[dim]` — `DIMS`(384/768/1024/1536)별 i8 코사인 마이크로벤치.
  - `bench_scan_i8` — 1 쿼리 vs `SCAN_N`(2000) 후보 i8-blob 스캔(출시 핫루프 모사), 기존 f32 `exact_scan`과 나란히.
- 실행:
  - `cargo bench --manifest-path rust_builder/rust/Cargo.toml --features "bench,vector_quant_i8"` (i8 핫커널)
  - 기존 f32: `--features "bench,vector_faer"` (비교 기준)
  - `bench_api::BACKEND` 라벨로 구분.
- **저널 기록**: i8 핫커널 throughput(차원별) + i8 vs f32-faer 스캔 배수를 `PR6.md`에 박제.
- 얻는 것: "출시 핫커널 수치 0개" 해소 + i8이 f32 대비 실제로 얼마나 버는지 정량화.

## 4. 컴포넌트 2 — 수치 ε 네트 (커널 정확성)

- 위치: `vector_quant.rs` 테스트 모듈(기존 i8 테스트 옆), `#[cfg(feature = "vector_quant_i8")]`.
- 모델: PR1의 [`faer_parity_tests`](../../../rust_builder/rust/src/api/vector_math.rs#L208) (커널 ≈ 독립 참조, ε 내 일치).
- 단언: `cosine_with_query_norm_i8_blob`(커널) ≈ **독립 참조 재구현** 을 차원별로 `ε = 1e-4` 내 일치.
  - 독립 참조: 동일 i8 입력에 대해 dot·sq_sum을 **f64**로 누산 후 `sqrt`/나눗셈 → 커널과 다른 누산 폭/구현.
- **ε 근거**: 커널의 `dot_i8_i32`/`sq_sum`은 i32 정수 누산이라 **정확**(dim 1536서 max ~2.5e7 ≪ i32 max 2.1e9, 오버플로 없음). 유일한 부동소수점 오차원은 최종 `(sq_sum as f32).sqrt()` + `query_norm`(f32)으로 나눗셈. `1e-4`는 이 캐스팅의 플랫폼 간 오차를 허용하면서 로직 버그(SIMD 재작성·인덱싱·norm 오류)를 잡는 합리적 바운더리.
- 기존 테스트와 차별: 기존 건 blob↔slice **진입점 일치**만 봄. 이건 *수학 자체*를 독립 구현과 대조 → **미래 i8 커널 재작성 버그**를 잡음.

## 5. 컴포넌트 3 — recall@k 네트 (양자화 품질) ★핵심

- 위치: `vector_quant.rs` 테스트 모듈, `#[cfg(feature = "vector_quant_i8")]`.
- **합성 클러스터 코퍼스**(결정론·무 rand 의존, `pseudo_vec` 스타일 시드 생성기):
  - C개 클러스터 중심(단위벡터) + 가우시안풍 노이즈 → 정규화. "몇 개는 가깝고 대부분 멀다"는 임베딩 분포 모사.
  - 기본값: **N=2000** 후보(= `SCAN_N` 재사용), **Q=32** 쿼리, **dim=768**, **k=10** (recall@10, 상위 0.5%).
- **정답(ground truth)**: 각 쿼리의 **f32 코사인 top-k** (f32 코퍼스 기준 = 진짜 랭킹).
- **i8 랭킹**: 코퍼스/쿼리를 i8 양자화 후 **i8 코사인 top-k**.
- **전순서 비교자(필수)**: i8·f32 **양쪽 모두** `(score 내림차순, index 오름차순)` 총순서로 정렬. i8은 i32 정수 점수라 **동점이 대량 발생**하므로(커널 누산 구조상), index 타이브레이크를 명시 강제하지 않으면 플랫폼(Ubuntu vs macOS) sort 구현 차이로 **플레이키**. 동일 비교자 적용 → 진짜 양자화 재정렬만 recall에 반영.
- **지표**: `recall@k = |topk_i8 ∩ topk_f32| / k`, 쿼리 평균. 고정 시드 → **완전 재현(비통계적·비플레이키)**.
- **임계값 = 측정 먼저의 산물**:
  1. 구현 첫 실행이 실제 `recall@10` 측정.
  2. **포화 점검**: 측정이 ~1.0이면 게이트가 장식 → 클러스터 밀도/노이즈/중첩을 올려 recall이 **민감 구간(0.85~0.98)** 에 들 때까지 코퍼스 보정.
  3. CI 게이트를 `recall@10 ≥ FLOOR` 로 고정(FLOOR = 측정값 − 마진 ≈ 0.03).
  4. 측정값·FLOOR·코퍼스 파라미터를 `PR6.md`에 기록.
- 얻는 것: 양자화가 근접 이웃 순위를 무너뜨리면 CI 빨개짐 — 지금 비어 있는 그 안전망. 측정이 임계값을 만들고, 그게 회귀 게이트가 됨.

## 6. 컴포넌트 4 — CI 게이팅 (fail-closed)

- `scripts/test_ci.sh`에 추가: `cargo test --lib --features "vector_quant_i8,vector_faer" -- --test-threads=1`
  - **출시 컴파일 트리(faer+quant) 100% 일치** — feature 간 매크로/컴파일 충돌까지 CI에서 선제 검출.
  - PR2의 faer 스텝처럼 **≥1 test 통과 요구(fail-closed)** — 0건 통과(미수집)면 실패 처리.
  - `--test-threads=1` 유지([[project_rust_tests_need_single_thread]] 규약).
- 출시 빌드는 PR2가 이미 `vector_faer,vector_quant_i8`로 **빌드** → 여기에 **i8 테스트 실행**을 더해 N2식 사각지대를 원천 차단.

## 7. 추적 (tracking)

- 새 Linear 이슈: **"PR6 — i8 출시 핫패스 측정 + ε/recall 안전망 [측정 먼저]"** (프로젝트 하위, 우선순위 High — 출시 검색 품질 직결).
- `docs/perf/vector-math-refactor/PR6.md` 신규(저널 템플릿: 결과 Before→After·피드백·리스크/롤백·결정 로그).
- README PR 상태표에 PR6 행 추가 + RETRO §5 "다음 작업"의 i8 검증 항목과 연결.
- ✅ **머지 순서**: #67(클로즈아웃) 머지 완료(`1217123`) → 현재 `main`에서 분기하므로 README PR 상태표 충돌·스택 트랩 없음.

## 8. 수용 기준 (Acceptance criteria)

- [ ] i8 마이크로벤치 + i8 스캔 벤치 동작, 수치가 `PR6.md`에 기록(i8 throughput + i8 vs f32-faer 배수).
- [ ] 수치 ε 네트: 차원별 i8 커널 ≈ f64 참조 `<1e-4` green.
- [ ] recall@k 네트: 결정론적, 코퍼스가 민감 구간(0.85~0.98)에 위치, `recall@10 ≥ FLOOR` green, FLOOR/측정값 기록.
- [ ] CI `--features "vector_quant_i8,vector_faer" -- --test-threads=1` fail-closed로 i8 테스트 실행, 기존 잡 회귀 없음.
- [ ] 커널/양자화 코드 변경 0줄(비파괴) 확인.

## 9. 리스크 / 완화

| 리스크 | 완화 |
|---|---|
| recall 게이트 포화(거짓 안심) | §5-2 포화 점검 + 코퍼스 민감도 보정 후 FLOOR 고정 |
| i8 동점으로 플랫폼 간 플레이키 | §5 전순서 비교자 `(score, index)` 양쪽 강제 |
| feature 조합 컴파일 충돌 | §6 출시 트리(faer+quant)로 CI 테스트 |
| #67과 README PR표 충돌 | §7 #67 머지 후 분기(스택 회피) |
| ε 너무 빡빡/느슨 | 정수 dot=정확, sqrt/div만 오차 → 1e-4 수학적 합리(검토 확인) |

## 10. 튜닝 가능한 기본값 (스펙 명시, 구현 중 조정 가능)

| 파라미터 | 기본값 | 비고 |
|---|---|---|
| ε (수치 네트) | `1e-4` | 정수 dot 정확, sqrt/div 오차만 허용 |
| k (recall) | `10` | recall@10 |
| N (코퍼스) | `2000` | `SCAN_N` 재사용, 상위 0.5% |
| Q (쿼리) | `32` | |
| dim | `768` | 출시 임베딩 대표 차원 |
| recall 마진 | `측정 − 0.03` | 첫 측정 후 FLOOR 확정 |
| 클러스터 수/노이즈 | 측정으로 보정 | recall 0.85~0.98 민감 구간 목표 |

---

구현 단계: 승인 후 **writing-plans** 스킬로 단계별 구현 계획 작성 → `feat/loc-64-i8-measure-parity-net` 브랜치에서 실행.

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

## 5. 컴포넌트 3 — 양자화 품질 네트 (recall@k floor + 코사인 fidelity) ★핵심

> ⚠️ **사전 적대적 검증 발견(2026-05-31):** i8 per-vector 양자화는 768d에서 너무 정확해 top-10을 거의 재정렬하지 않음 — recall@10 ≈ 0.997. '민감 밴드(0.85~0.98)'는 출시 설정에서 **도달 불가**이며, 억지로 맞추려면(저차원·global scale) 출시 경로를 반영 못 함. 따라서 (a) recall은 **측정된 높은 baseline을 잠그고**(밴드 강제 안 함), (b) 진짜 민감·결정론 게이트로 **코사인 fidelity**를 추가.

- 위치: `vector_quant.rs` 테스트 모듈, `#[cfg(feature = "vector_quant_i8")]`.
- **합성 클러스터 코퍼스**(결정론·무 rand): C개 클러스터 중심 + 노이즈 → 정규화. **출시 설정 유지**(N=2000, Q=32, dim=768, per-vector scale). 코퍼스는 현실적 분포일 뿐 민감도 노브 아님(clusters=16 고정).

### 5a. recall@k floor
- **정답(GT)**: 각 쿼리의 **f64 코사인 top-k** (원본 f32를 f64로 누산 → 경계 gap ≫ x86/ARM 1-ULP jitter라 **플랫폼 안정**). k=10.
- **i8 랭킹**: i8 양자화 후 i8 커널 top-k.
- **전순서 비교자**: 양쪽 `(score desc, index asc)` — 결정론적 타이브레이크(i8 정수 점수 동점 대량 → index로 확정).
- **게이트**: `recall@10 ≥ FLOOR`, **FLOOR = floor(baseline − 0.02) = 0.98** (측정 baseline 0.996875 = 319/320, dev arm64·결정론). 밴드 강제·포화 가드 폐기 — baseline이 ~1.0인 게 현실이자 좋은 결과.

### 5b. 코사인 fidelity (결정론·민감 백스톱)
- 모든 (쿼리, 후보) 쌍에서 `max|cosine_i8 − cosine_f32_true(f64)|` 측정.
- **게이트**: `max ≤ ε_q`, **ε_q ≈ 4 × 측정 max = 0.005** (측정 max 0.00121). ranking 무관 → 경계 jitter 0, 양자화 품질 저하에 가장 민감.

### 측정 먼저 → 임계값
1. 첫 실행(planning, dev arm64)이 recall@10=X=0.996875·max fidelity err=M=0.00121 측정.
2. `FLOOR = floor(X − 0.02) = 0.98`, `ε_q ≈ 4·M = 0.005` **사전 고정**(결정론적이라 CI/플랫폼 동일값). `const _: () = assert!(...)`로 vacuous(<0.5 floor / ≥0.1 ε_q) 임계값 **컴파일 차단**.
3. X·M·FLOOR·ε_q를 `PR6.md`에 기록, 구현 시 동일값 확인.
- 얻는 것: 미래 i8/양자화 변경이 검색 품질을 떨어뜨리면 CI 빨개짐. recall=거시 회귀, fidelity=미세 회귀.

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
- [ ] recall@k floor: 결정론적(f64 GT), `recall@10 ≥ FLOOR(=baseline−0.02)` green, baseline/FLOOR 기록.
- [ ] 코사인 fidelity: `max|cosine_i8−cosine_f32_true| ≤ ε_q` green, 측정 max/ε_q 기록.
- [ ] CI `--features "vector_quant_i8,vector_faer" -- --test-threads=1` fail-closed + 3개 네트 이름별 가드, 기존 잡 회귀 없음.
- [ ] 커널/양자화 코드 변경 0줄(비파괴) 확인.

## 9. 리스크 / 완화

| 리스크 | 완화 |
|---|---|
| recall baseline ~1.0(거시 둔감) | 미세 회귀는 코사인 fidelity 백스톱(ε_q)이 담당 |
| f32 GT 경계 1-ULP jitter | GT를 **f64**로 계산 → 경계 gap ≫ jitter, recall 플랫폼 안정 |
| vacuous 게이트(미보정 임계값) | `const _ assert` 컴파일 가드 + CI 3개 네트 이름별 fail-closed |
| feature 조합 컴파일 충돌 | §6 출시 트리(faer+quant)로 CI 테스트 |
| #67과 README PR표 충돌 | 해소(#67 머지 완료, `main`에서 분기) |
| ε 너무 빡빡/느슨 | 정수 dot=정확, sqrt/div만 오차 → 1e-4 수학적 합리(검토 확인) |

## 10. 튜닝 가능한 기본값 (스펙 명시, 구현 중 조정 가능)

| 파라미터 | 기본값 | 비고 |
|---|---|---|
| ε (커널 ε 네트) | `1e-4` | 정수 dot 정확, sqrt/div 오차만 |
| k (recall) | `10` | recall@10 |
| N / Q / dim | `2000 / 32 / 768` | 출시 설정(per-vector scale); N=`SCAN_N` 재사용 |
| recall FLOOR | `floor(X−0.02) = 0.98` | 측정 X 0.996875; const guard `≥0.5` |
| fidelity ε_q | `≈4·M = 0.005` | 측정 max 0.00121; const guard `<0.1` |
| 클러스터 수 | `16` (고정) | 현실적 분포; 민감도 노브 아님 |

---

구현 단계: 승인 후 **writing-plans** 스킬로 단계별 구현 계획 작성 → `feat/loc-64-i8-measure-parity-net` 브랜치에서 실행.

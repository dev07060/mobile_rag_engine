# PR6 — i8 출시 핫패스 측정 + ε/recall/fidelity 안전망 (N: 측정 먼저)

- 브랜치: `feat/loc-64-i8-measure-parity-net`
- Linear: [LOC-64](https://linear.app/loceract/issue/LOC-64)
- 상태: 🟦 진행 (PR 열림, CI green 대기)
- 설계: [PR6-spec-i8-measure-parity-net.md](PR6-spec-i8-measure-parity-net.md) · 계획: [PR6-plan-i8-measure-parity-net.md](PR6-plan-i8-measure-parity-net.md)

## 스코프 (비파괴 — 커널/양자화 0줄 변경)
출시 핫패스(i8 `cosine_with_query_norm_i8_blob`)에 PR1 패턴 적용: 측정 + 수치 ε 네트 + recall@k floor + 코사인 fidelity 네트 + CI fail-closed.

## 결과 (측정, dev arm64)
- **i8 핫커널 마이크로벤치** (ns): 384=7.87 / 768=14.97 / 1024=21.12 / 1536=31.28
- **스캔(2000×768)**: `exact_scan[faer]`(f32 decode+cosine) **452.82 µs** vs `exact_scan_i8`(i8 blob) **29.98 µs** → i8가 f32-faer 대비 **≈15.1× 빠름**.
- **핵심 발견**: 출시 i8 핫패스는 f32 폴백보다 ~15× 빠르면서 **recall@10 ≈ 0.997**(=319/320, 거의 무손실) — 빠르고 정확.
- **수치 ε 네트**: 차원 {1,2,3,16,384,768,1024,1536}에서 kernel ≈ 독립 f64 참조, ε=1e-4 green.
- **recall@k floor 네트**: N=2000, Q=32, dim=768, k=10, clusters=16 → recall@10 = **0.996875**, FLOOR = **0.98**. GT는 f64(플랫폼 jitter 제거), 전순서 `(score desc, index asc)`는 `total_cmp`(NaN-safe).
- **코사인 fidelity 네트**: `max|cosine_i8 − cosine_f32_true|` = **0.00121**, 게이트 **ε_q = 0.005**(≈4× baseline). ranking 무관·완전 결정론.
- **CI**: `--features "vector_quant_i8,vector_faer" -- --test-threads=1` fail-closed + 3개 네트 이름별 가드, 7 passed.

## 받은 피드백 (리뷰 / 사전검증)
- 사전 적대적 검증이 잡은 것: recall@10이 768d에서 포화(~0.997)→'민감 밴드' 불가 → **recall floor + cosine fidelity 백스톱**으로 재설계; f32 GT 1-ULP 경계 jitter → **f64 GT**; vacuous 게이트 위험 → `const _` 컴파일 가드 + CI 이름별 가드.
- 구현 리뷰: `order_desc`를 `partial_cmp().unwrap_or(Equal)`(NaN 비전이성)에서 `total_cmp` 기반 concrete 헬퍼로 교체; CI per-net 정규식을 `\.\.\. ok`로 타이트닝.

## 리스크 / 롤백
- 비파괴(커널 0줄) → 동작 변경 없음. 롤백: PR revert.
- 결정론: i8 dot 정수 정확 + f64 GT → 플랫폼 무관(측정값 bit-identical). fidelity는 ranking 무관(경계 jitter 0).
- vacuous 게이트: `const _: () = assert!(...)` 컴파일 가드 + CI 이름별 fail-closed.

## 결정 로그
- 출시 핫패스가 i8임을 확정(이전 세션) → 측정/검증 초점을 f32(폴백)에서 i8로 이동.
- 품질 게이트는 측정 baseline에서 FLOOR(0.98)/ε_q(0.005) 도출(측정 먼저). 코퍼스는 출시 설정(768d·per-vector) 유지 — 강제 민감화 안 함.

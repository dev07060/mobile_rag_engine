# PR2 — 출시 faer 백엔드 CI 커버리지 (N2) [faer 유지]

- 브랜치: `feat/loc-60-faer-ci-coverage`
- Linear: [LOC-60](https://linear.app/loceract/issue/LOC-60)
- 상태: 🟦 진행 (PR 열림, CI green 대기)

## 재설계 배경
PR1([PR1.md](PR1.md)) 벤치가 원안("faer 제거 → fused 통일")의 전제를 반증 — faer가 2–8× 빠름.
따라서 faer를 **유지**하고, 대신 PR1이 드러낸 **N2 갭**(출시되는 faer+quant 백엔드가 CI에서 빌드/테스트
0회)을 닫는 것으로 PR2를 재설계.

## 스코프 (무엇을/왜)
[scripts/test_ci.sh](../../../scripts/test_ci.sh) `native` 잡 확장:
1. **faer-백엔드 vector_math 테스트** — `cargo test --lib --features vector_faer vector_math -- --test-threads=1`,
   PDF 스모크와 동일한 **fail-closed**(≥1 test 통과 요구). PR1의 faer↔fused 패리티 테스트가 여기서 실행됨.
2. **출시 feature 조합 릴리스 빌드** — `cargo build --release --features vector_faer,vector_quant_i8`
   (기존 default-feature 빌드를 출시 조합으로 교체 → 실제 출시 백엔드를 컴파일 게이트).
3. [vector_math.rs](../../../rust_builder/rust/src/api/vector_math.rs) 모듈 doc 정정 — "allocation-free" 문구를
   faer 백엔드 현실(per-call 할당, but SIMD로 2–8× 빠름)에 맞게 수정.

## 결과 (Before → After)
- N2 갭: **닫힘** — 출시 faer+quant 경로가 CI에서 빌드 + 테스트됨.
- 로컬 검증: `bash -n` OK; faer 테스트 4개(패리티 포함) green, fail-closed PASS; `cargo build --release
  --features vector_faer,vector_quant_i8` 성공(50s, 기존 dead_code 경고만).
- CI: (PR #__ green 후 갱신)

## 받은 피드백 (리뷰)
- (PR 리뷰 후 갱신)

## 리스크 / 롤백
- CI native 잡 시간 증가(faer 2회 컴파일: test+release 프로파일). 게이트 가치 대비 수용.
- 롤백: test_ci.sh 변경 revert. 동작 코드 변경 없음(테스트/스크립트/주석만).
- R8(공유 SQLite 플레이크): faer 테스트도 `--test-threads=1` 고정으로 회피.

## 결정 로그
- N1(무할당화)은 PR1에서 throughput 무의미 확인 → PR2 범위 제외(추후 선택적 마이크로옵트).
- R9(전제 반증) 해소: faer 유지 확정, N2로 전환.

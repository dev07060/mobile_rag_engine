# PR1 — criterion 벤치 + faer/fused 패리티 안전망

- 브랜치: `feat/loc-59-vector-math-bench`
- Linear: [LOC-59](https://linear.app/loceract/issue/LOC-59)
- 상태: 🟩 머지(#64)

## 스코프 (무엇을/왜)
faer 삭제 **전에** 성능 베이스라인을 캡처하고, fused가 faer와 등가임을 박아 PR2를 안전화하기 위함.
- `Cargo.toml`: `bench` feature, `criterion`(default-features off) dev-dep, `[[bench]]` 타깃, `[lib] crate-type`에 `"lib"` 추가(벤치가 크레이트를 Rust 의존성으로 링크하려면 rlib 필요)
- `src/bench_api.rs` (+ lib.rs 1줄, `#[cfg(feature="bench")]`): `pub(crate)` 커널을 벤치에서 접근하기 위한 bench 전용 re-export
- `benches/vector_math.rs`: dot/l2_norm/cosine/decode + 실제 exact-scan 루프(2000×768) 벤치
- `vector_math.rs`: `#[cfg(all(test, feature="vector_faer"))] faer_parity_tests` — faer-백엔드 커널 ≈ 인라인 fused 참조 (ε=1e-3), dim {1,2,3,16,384,768,1024,1536}

## 결과 (Before → After)
### 패리티 (등가성)
`cargo test --features vector_faer --lib -- --test-threads=1` → **green**. faer ≈ fused 1e-3 이내(전 차원). PR2 백엔드 교체가 동작 보존임을 증명.

### 벤치 (Apple Silicon, bench profile=release/opt-3, median)
| 벤치 | fused | faer | faer 우위 |
|---|---|---|---|
| cosine/384 | 233 ns | 114 ns | 2.0× |
| cosine/768 | 518 ns | 156 ns | 3.3× |
| cosine/1024 | 706 ns | 188 ns | 3.8× |
| cosine/1536 | 1067 ns | 252 ns | 4.2× |
| dot/384 | 170 ns | 56 ns | 3.0× |
| dot/768 | 443 ns | 83 ns | 5.3× |
| dot/1024 | 632 ns | 95 ns | 6.7× |
| dot/1536 | 987 ns | 127 ns | 7.8× |
| decode/384..1536 | 33–96 ns | 33–95 ns | = (백엔드 무관, 하니스 sanity 검증) |
| **exact_scan 2000×768 (decode+cosine)** | **1204 µs** | **435 µs** | **2.8×** |

## ⚠️ 핵심 발견 — PR2 전제 반증(REFUTED)
**faer는 더 느리지 않다. 2–8× 더 빠르다.** 외부 리뷰 Claim 2/3과 00-분석의 가설(“faer가 1-D에서 fused보다 느릴 것”)은 **실측으로 반증**됨. 이유: f32 리덕션은 fast-math 미허용으로 **자동 벡터화되지 않아 fused가 스칼라(latency-bound)** 로 도는 반면, faer는 SIMD gemm 마이크로커널을 사용. N1(호출당 힙 할당)은 실재하나 **커널 속도 이득에 압도되어 throughput에 무의미**(exact_scan에서 4000회 할당에도 faer가 2.8× 빠름).

→ **PR2(“faer 제거”)는 그대로 진행하면 핫 패스를 2.8×(scan)~8×(대형 dot) 회귀시킨다.** 계획 재검토 필요(아래 결정 로그).

## 받은 피드백 (리뷰)
- (PR 리뷰 후 갱신)

## 리스크 / 롤백
- PR1 자체는 추가만(비파괴). `crate-type`에 `"lib"` 추가는 rlib 산출물만 늘 뿐 앱이 링크하는 cdylib/staticlib 불변.
- 벤치/패리티는 CI에서 안 돎(`bench`·`vector_faer` 미설정) → 로컬 실행/기록이 본 PR의 산출.

## 결정 로그
- **PR2 전제 반증** → PR2를 “faer 제거”에서 **“faer 유지 + N2(CI 커버리지)”로 피벗**했고, PR2(#65)에서 완료.
- 디바이스 캐비엇: 위 수치는 개발기(Apple Silicon). 방향(faer 우위)은 스칼라-vs-SIMD 차이라 폰 NEON에서도 견고할 것으로 예상하나, 크기는 온디바이스 프로파일로 확인 권장.

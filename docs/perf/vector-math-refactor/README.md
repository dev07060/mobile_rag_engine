# vector_math.rs 성능 리팩터링 — 작업 저널

> 목적: 이 리팩터링을 **PR(히스토리) 단위로 결과·피드백을 보존**하여, 종료 후 회고와
> 잠재 리스크 대응이 가능하도록 한다. 각 PR은 머지 전 자신의 항목을 채운다.

## 배경 한 줄
온디바이스 RAG 핫 패스(`rust_builder/rust/src/api/vector_math.rs`)의 코사인/닷곱 커널을
외부 리뷰 + 자체 검증을 통해 재설계한다. 자세한 근거는 [00-review-and-analysis.md](00-review-and-analysis.md).

## 핵심 결론 (요약)
- **출시(release) 빌드는 `vector_faer` 백엔드**, 디버그/`cargo test`는 fallback — [cargokit.yaml:5](../../../rust_builder/rust/cargokit.yaml).
- faer는 이 파일의 1-D 닷곱에서만 쓰이며(다른 사용처 0건), `*` 연산이 **호출당 힙 할당** + 2-pass +
  gemm 디스패치를 유발 → 현재 호출 형태에선 fused 스칼라 루프보다 느릴 가능성이 큼.
- ~~가장 큰 실효 조치: faer 제거 → fused 커널 통일~~ → **⚠️ PR1 실측으로 반증됨 (아래)**.

> **⚠️ 2026-05-30 PR1 업데이트:** 벤치 결과 **faer가 fused보다 2–8× 빠름**(exact_scan 2.8×). f32 리덕션이
> 자동 벡터화되지 않아 fused가 스칼라로 도는 반면 faer는 SIMD gemm 사용. **PR2 “faer 제거” 전제는 반증.**
> **결정: faer 유지.** PR2는 N2(출시 faer 백엔드 CI 커버리지)로 전환(진행). 상세 [PR1.md](PR1.md) · [PR2.md](PR2.md).

## PR 분할 / 상태

**Linear 프로젝트**: [vector_math 커널 성능 리팩터링](https://linear.app/loceract/project/vector-math-커널-성능-리팩터링-faer-제거-fused-통일-a8ea581c6220) — 각 PR을 이슈로 미러링(결과·피드백은 이슈와 PRn.md 양쪽).

| PR | 제목 | 해소 | 리스크 | 의존 | Linear | 상태 |
|----|------|------|--------|------|--------|------|
| PR0 | 작업 저널 스캐폴드 | 보존 체계 | 없음(문서) | — | [LOC-58](https://linear.app/loceract/issue/LOC-58) | 🟩 머지(#63) |
| PR1 | 벤치 하니스 + faer/fused 패리티 안전망 | 측정근거, N2 선제 | 없음 | — | [LOC-59](https://linear.app/loceract/issue/LOC-59) | 🟩 머지(#64, [PR1.md](PR1.md)) |
| PR2 | 출시 faer 백엔드 **CI 커버리지** (N2) [faer 유지] | N2 | 낮음 | PR1 ✅ | [LOC-60](https://linear.app/loceract/issue/LOC-60) | 🟩 머지(#65, [PR2.md](PR2.md)) |
| PR3 | decode 버퍼 재사용 | Claim1 | 낮음~중 | 벤치/N3 게이트 | [LOC-61](https://linear.app/loceract/issue/LOC-61) | ❌ 폐기(출시 i8 빌드서 f32 decode 비핫, 코드검증) |
| PR4 | ~~다중 누산기 언롤~~ | — | — | — | [LOC-62](https://linear.app/loceract/issue/LOC-62) | ❌ 폐기(faer 유지로 무의미) |
| PR5 | 위생: 손상 로깅(N6) + 엔디안 문서화(N5) | N6, N5 | 낮음(독립) | — | [LOC-63](https://linear.app/loceract/issue/LOC-63) | 🟩 머지(#66, [PR5.md](PR5.md)) |
| PR6 | i8 출시 핫패스 **측정 + ε/recall/fidelity 안전망** | i8 검증갭 | 낮음(비파괴) | main(#67) | [LOC-64](https://linear.app/loceract/issue/LOC-64) | 🟦 진행([PR6.md](PR6.md)) |

종료 회고: [RETRO.md](RETRO.md) · PR3([LOC-61](https://linear.app/loceract/issue/LOC-61)) ❌ 폐기 확정(RETRO §5) · 잔여(선택): 온디바이스 벤치 / encode 헬퍼 dedup — 프로젝트 핸드오프 노트 참조.

상태 범례: ⬜ TODO · 🟦 진행 · 🟩 머지 · ⏸ 보류 · ❌ 폐기 · PR별 상세는 `PRn.md`

## 의존/머지 순서
```
main
 ├─ PR1 ──► 머지 ──► PR2 ──┬─► PR4 (PR2 위 스택)
 │                          └─► PR5 (PR2 이후)
 ├─ PR3  (대체로 독립: 스캔 루프)
 └─ PR5  (단독 선행도 가능)
```
⚠️ **스택 PR 함정**: PR4/PR5를 PR2 브랜치 위에 올렸다면, PR2가 main에 머지되는 순간
base가 사라져 고아가 될 수 있음 → PR2 머지 직후 base를 main으로 **retarget**.

## 규약
- CI: `cargo test -- --test-threads=1` (공유 SQLite DB 병렬 실패 회피). fmt는 게이트 아님.
- 커밋/PR: Claude 귀속(footer·Co-Authored-By) **미포함**, 작성자 = 본인 계정.
- 머지: PR은 열고 CI green까지만, **머지는 본인이 직접**.
- 사용자 노출 변경은 [CHANGELOG.md](../../../CHANGELOG.md)에도 한 줄 기록.

## 각 PR 항목 템플릿 (PRn.md)
```md
# PRn — <제목>
- 브랜치 / PR 링크:
- 상태:
## 스코프 (무엇을/왜)
## 결과 (Before → After)
- 벤치 수치 / 바이너리 크기 / 테스트(test-threads=1) 결과
## 받은 피드백 (리뷰)
- (코멘트 요약 + 반영/반박 결정)
## 리스크 / 롤백
- 식별된 리스크 · 트리거 · 완화 · 되돌리기 절차
## 결정 로그
- (예: 데이터가 X라 PR3 진행/보류)
```

종료 후: [risk-register.md](risk-register.md) 최종화 + [RETRO.md](RETRO.md) 작성.

# 온디바이스 RAG 쿼리 프로파일러 — 작업 저널

> 직전 vector-math-refactor와 동일 방식: PR(히스토리) 단위로 결과·피드백 보존, Linear 미러링.

## 배경 한 줄
vector_math 커널 슬라이스는 거의 최적임을 확인했으나 **온디바이스 RAG end-to-end는 미측정**. 실기에서 쿼리 단계별 지연을 분해해 진짜 병목을 데이터로 찾는다.

## 문서
- [DESIGN.md](DESIGN.md) — 승인된 설계 스펙(검증된 아키텍처 사실 포함). 구현 계획은 writing-plans 산출 후 추가.
- Linear 프로젝트: [온디바이스 RAG 쿼리 프로파일러](https://linear.app/loceract/project/온디바이스-rag-쿼리-프로파일러-25df240c4262) · 설계 이슈 [LOC-65](https://linear.app/loceract/issue/LOC-65)

## 핵심 설계 결론 (요약)
- Approach C(단계적): Phase1 coarse(Rust 0변경) baseline → 지배 버킷만 Phase2 드릴다운.
- 측정 세그먼트: embed / **activate(스위치 비용)** / search / hydrate + I/O 카운터 + FFI 오버헤드 수식.
- 2레인: Unfiltered(f32 HNSW+BM25 RRF) / Filtered(i8 exact-scan).
- Cold/Warm 3분류 + **A→B→A 스위치 시나리오 필수**(순수 warm만 재면 가짜 초록).

## PR 분할 / 상태
(구현 계획 확정 후 채움 — 직전 저널 형식과 동일한 상태표·PRn.md)

| PR | 제목 | Linear | 상태 |
|----|------|--------|------|
| — | 설계 스펙 (이 문서) | [LOC-65](https://linear.app/loceract/issue/LOC-65) | 🟦 진행 |

## 규약 (프로젝트 공통)
- CI: `cargo test -- --test-threads=1`. 커밋/PR에 Claude 귀속 미포함. PR은 열고 CI green까지만, 머지는 본인.

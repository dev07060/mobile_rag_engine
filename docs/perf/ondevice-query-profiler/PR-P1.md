# PR P1 — 프로파일러 report 모델 + JSON/CSV (host-TDD)

- 브랜치: `feat/loc-66-profiler-stats-report`
- PR: [#70](https://github.com/dev07060/mobile_rag_engine/pull/70) · Linear [LOC-66](https://linear.app/loceract/issue/LOC-66)
- 상태: 🟩 머지

## 스코프 (무엇을/왜)
프로파일러 결과 모델 + 직렬화(순수 로직, 기기 불필요). subagent-driven으로 실행(구현→spec→quality 2단계 리뷰).
- `example/lib/profiling/query_profile_report.dart`: `SegmentSamples` / `QueryProfileRun` / `QueryProfileReport` — 세그먼트 샘플을 **기존 `BenchmarkService.summarizeSamples`로 집계**, JSON/CSV 직렬화, `ffiOverheadMs`(Dart−Rust, clamp 0).
- `example/test/profiling/query_profile_report_test.dart`: 4 테스트.

## 결과 (Before → After)
- 호스트 테스트 **4/4 green**. CI 6/6 green(#70).
- spec-compliance ✅ / code-quality ✅(analyzer clean).

## 받은 피드백 (리뷰)
- code-quality minor 반영: CSV `n`=`s.measuredIterations`(일관성), ffiOverhead 테스트 허용오차 1e-9→1e-6, empty-segment 테스트 추가.

## 결정 로그 (계획 대비 변경)
- **원안 P1.1 `BenchmarkService.statsFromSamples` 폐기 (DRY).** 구현 착수 후 기존 `summarizeSamples(samples, warmupIterations:0)`가 동일 기능임을 발견(초기 Explore가 놓침) → 중복 메서드 추가 대신 기존 것 재사용. "구현 중 검증"이 중복을 잡은 사례.

## 리스크 / 롤백
- 순수 로직·추가만. 롤백: PR revert. 동작 코드 영향 없음.

# PR P3 — 세그먼트 타이밍 + 3시나리오 × 2레인

- 브랜치: `feat/loc-68-profiler-timing`
- Linear: [LOC-68](https://linear.app/loceract/issue/LOC-68)
- 상태: 🟩 머지(#72, iPhone 실기 profile 런 green)

## 스코프
실 ONNX 자산 example 앱에서 쿼리 단계를 **격리 계측**하는 디바이스 프로파일러 본체.
- `example/lib/profiling/query_profiler.dart` — `SourceRagService.searchMeta`(:933-995) 경로를 미러링해 embed / activate(스위치) / search / hydrate를 단계별로 `Stopwatch` 계측. 엔진 private 헬퍼 2개를 인용과 함께 복제: `_indexPath`(FNV-1a, :283-309), `_toInt64List`(FRB generalized Int64List, :261-268). `activateOnly`/`deleteOnDiskIndex`로 결정적 cold 셋업, hit의 sourceId 반환으로 필터 fail-closed.
- `example/integration_test/query_profile_measure_test.dart` — 측정 엔트리(단독 파일). pure_cold(evicted cold activate) / pure_warm(2레인) / switching_cold(A→B→A) × Unfiltered·Filtered(i8). P1의 `SegmentSamples`/`QueryProfileRun` 집계, 콘솔에 행 단위 `PROFILE_CSV`.
- `example/test_driver/integration_test.dart` — `flutter drive` 엔트리(profile 빌드 필수).
- `example/pubspec.yaml` — `flutter_rust_bridge ^2.11.1`(프로파일러가 FRB i64 리스트 생성에 필요).

## 측정 방법 (중요: `flutter test` 아님 → `flutter drive`)
`flutter test`는 빌드 모드를 debug로 하드핀 → cargokit debug → **fallback 백엔드**(출시 `vector_faer,vector_quant_i8` 미적용)라 baseline 무효. profile 빌드는 `flutter drive`로만:

```
cd example && flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/query_profile_measure_test.dart \
  --profile -d 00008110-001524992E38801E
```

fail-closed: `kDebugMode` skip+assert(프로필 강제) / 필터레인 hit sourceId ⊆ 요청 / 세그먼트별 N>0.

## 결과 (iPhone iOS 26.5, profile, 컬렉션당 500 docs, topK=10)
| lane | category | embed p50/p95 | activate | search p50/p95 | hydrate p50/p95 |
|---|---|---|---|---|---|
| unfiltered | pure_cold (n=1) | 25.2 | **247.3** | 2.20 | 0.42 |
| unfiltered | pure_warm (n=30) | **26.7 / 36.7** | — | 1.60 / 2.08 | 0.27 / 0.41 |
| filtered(i8) | pure_warm (n=30) | **27.6 / 37.6** | — | 0.76 / 0.92 | 0.19 / 0.30 |
| unfiltered | switching_cold (n=30) | 25.7 / 37.0 | (로그 트렁케이션 유실) | 1.47 / 1.90 | (유실) |

- embed(ONNX)가 warm 정상상태 지배(~27ms, 타 세그먼트 15–37배). cold는 activate 지배(247ms). 필터 i8 search가 unfiltered보다 빠름(0.76 vs 1.60ms).
- 전체 결과/디바이스/방법은 [LOC-68 코멘트](https://linear.app/loceract/issue/LOC-68) 참조.

## 받은 피드백 / 디버그 로그 (실기에서만 드러남)
- 어드버서리얼 리뷰가 분석 단계에서 2 critical 차단: ① `flutter test --profile`는 무효(빌드 debug 고정) → `flutter drive` + test_driver 추가. ② 필터레인의 `scoped_exact_scan_rows>0` 단언은 항상 실패(엔진이 그 카운터를 증가시키지 않음, 셰일드 러스트 테스트가 ==0 단언) → sourceId⊆요청 검사로 대체.
- 실기 런에서 ③ 기본 테스트 타임아웃 30s 초과(2×500 ONNX 임베드) → `Timeout(15분)`. ④ `clearAllData` 비동기 재초기화가 첫 seed와 경합 → `database is locked` → 측정을 **자체 파일 분리** + init 전 DB 삭제(clearAllData 미사용). ⑤ 콘솔이 큰 단일 print를 잘라먹음 → CSV 행 단위 print.
- DDS 간헐 실패: profile 런 성공 1·실패 2 관측, kill 후 재실행.

## 리스크 / 롤백 / 다음
- 동작 코드 변경 없음(example 프로파일링 + test_driver + dep). 롤백: PR revert.
- 다음: **P4(LOC-69)** = JSON/CSV export + 메타(baseline 산출). 본 PR 위에 스택.

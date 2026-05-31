# PR P2 — example integration_test 배선 + A/B 픽스처

- 브랜치: `feat/loc-67-profiler-fixture`
- Linear: [LOC-67](https://linear.app/loceract/issue/LOC-67)
- 상태: 🟦 진행 (PR 열림, 기기 스모크 green)

## 스코프
실 ONNX 자산이 있는 example 앱에서 구동하는 디바이스 프로파일러의 기반.
- `example/pubspec.yaml`: `integration_test` dev-dep.
- `example/lib/profiling/query_fixture.dart`: 결정적 A/B 코퍼스(`MobileRag.inCollection(id).addDocumentUtf8`) + 2레인 쿼리셋.
- `example/integration_test/query_profile_test.dart`: 엔진 init(실 ONNX) + 픽스처 시드 스모크.
- (P1 저널 동기화 a3f35f7 포함: PR-P1.md + README 상태표.)

## 결과 (실기 검증, iPhone iOS 26.5)
- **`flutter test integration_test/query_profile_test.dart -d <iphone>` → `+1: All tests passed!`**
- 엔진 init(실 ONNX 모델 107MB) + 40×2 = 80 소스 시드 + assertion 통과.

## 받은 피드백 / 디버그 로그
- 1차: `testWidgets` 의 end-of-test `SemanticsHandle` 검증 실패(본문은 정상 실행). → **비-UI 본문이라 `test()` 로 교체**(위젯-테스터 검증 회피). 검증된 픽스.
- 2차: 물리 iOS에서 `Dart VM Service not discovered`(DDS) — macOS **Xcode 자동화 권한** 미허가 + stale 프로세스. → 권한 허가 + stale 종료 후 재실행 green.

## 리스크 / 롤백 / 다음
- 동작 코드 변경 없음(테스트/픽스처/스크립트/dep). 롤백: PR revert.
- ⚠️ **P3/P4는 profile 모드 필수** — `flutter test integration_test`는 기본 debug → cargokit debug → fallback 백엔드. 출시 `vector_faer,vector_quant_i8` 측정하려면 profile 모드로 실행해야 함(P3 진입 시 invocation 확정).
- ⚠️ 물리 iOS 구동 전제: Xcode 자동화 권한 + 기기 unlocked. (CI 비포함 — 로컬 기기 측정 전용)

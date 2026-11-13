# 마일스톤

이 저장소에서 작업하는 모든 세션이 따르는 범위 문서다. 사용자가 합의한 범위만 진행한다.

## 규칙

1. **마일스톤 하나 = PR 하나.** 마일스톤 일부만 담은 PR은 사용자가 요청할 때만 연다.
2. **이 문서에 없는 작업은 PR로 올리지 않는다.** 새 작업이 생기면 먼저 이 문서에 마일스톤으로 적고 사용자 합의를 받는다.
3. **착수 전에 담당 세션과 브랜치를 적는다.** "손대는 파일"이 겹치는 마일스톤은 동시에 진행하지 않는다.
4. **범위를 바꿔야 하면 코드보다 이 문서를 먼저 고친다.** 예: 문서만 고치기로 한 마일스톤에서 코드 수정이 필요해진 경우.
5. **배포는 내부 점검을 끝낸 뒤에만 한다 (2026-11-06 사용자 지시: 보류하고, 내부에서 문제를 찾아 전부 고친 뒤 발행).** 0.22.0~0.22.3이 이틀 안에 연달아 나가 핫픽스가 이어진 일을 되풀이하지 않기 위해서다. 배포 마일스톤을 만들거나 버전을 올리지 않는다. 변경 기록은 `CHANGELOG.md`의 `## Unreleased`에 쌓는다. 사용자가 배포를 요청하면 그때 배포 마일스톤을 적고, 발행 전에 아래를 모두 끝낸다.
   1. 알려진 문제와 점검에서 나온 문제를 모두 고친다(남기는 것은 이유와 함께 `Unreleased`에 적는다).
   2. 마지막 배포 버전이 남긴 DB와 파일 상태에서의 업그레이드, 새 앱 기준 release 빌드(Android, iOS, macOS, Windows), 실제 기기 한 대 이상의 확인을 발행 전에 통과시킨다.
   3. 발행 뒤의 pub 모드 확인은 최종 점검이다. 여기서 문제가 나오면 핫픽스가 아니라 점검이 빠뜨린 것으로 보고 원인을 기록한다.
6. **머지는 사용자가 한다.** 세션은 "PR 열림, CI 통과"에서 멈춘다.
7. **착수는 사용자가 마일스톤 번호로 지시할 때만 한다** (예: "M2 착수"). 순서는 아래 목록 순서를 기본으로 한다.
8. **모든 마일스톤의 완료 기준에 아래 네 가지를 넣는다 (2026-11-03 리뷰 뒤 합의).** 기존 검증이 새로 설치한 상태와 가짜 값만 봐서 맹점이 생겼기 때문이다. 작업을 마치기 전에 세션이 직접 확인하고, PR 본문의 같은 내용 절에 결과를 적는다. PR 본문은 영어로만 쓰고 한국어를 섞지 않는다(2026-11-13 사용자 지시). 절 이름은 `## Upgrade path`, `## Real engine output`, `## Caller's view`, `## Surrounding code and what could break`이고, 해당 없으면 "Not applicable."과 이유를 쓴다. CI로 강제하거나 GitHub rules를 바꾸지 않는다(2026-11-03 사용자: 혼자 관리하는 패키지라 머지 부담만 커진다).
   1. **업그레이드 경로:** 마지막 배포 버전(0.23.0)이 남긴 DB와 파일 상태에서 시작해 확인한다. Upgrade E2E의 기준 버전은 아직 0.22.3이다(후보 목록 참고).
   2. **실제 출력:** 가짜 값이 아니라 실제 엔진 출력으로 최소 한 번 확인한다.
   3. **사용하는 쪽 관점:** 여러 번 호출할 때와 토큰 비용을 확인한다.
   4. **주변 코드:** 수정과 맞물리는 코드를 읽고, 무엇이 깨질 수 있는지 PR에 적는다.
9. **성능·품질 측정에는 환경과 임베딩 모델을 반드시 남긴다 (2026-11-12 사용자 지시).** README의 `passage_recall@10 = 0.925`가 모델 이름 없이 기본값처럼 적혀 있었는데, 실제로는 BGE-m3로 잰 값이어서 기본 모델이 나빠진 것처럼 보였다(B1). 수치를 쓰는 모든 곳(보고서, PR 본문, 이 문서의 결과 절, CHANGELOG, README)에 아래를 함께 적는다. 형식은 [`docs/perf/passage-benchmark-2026-11/README.md`](perf/passage-benchmark-2026-11/README.md)의 "조건" 표를 따른다. 측정 결과 파일에도 모델과 fingerprint를 넣는다. 모델이 적혀 있지 않은 과거 수치를 인용할 때는 "모델 미기재"라고 밝힌다.
   1. 임베딩 모델 이름과 fingerprint(`model.onnx|차원|…|sha256:…`) 또는 파일 해시
   2. 엔진 커밋, 빌드 모드(debug/profile/release)와 켜진 Rust feature
   3. 기기, OS, Xcode/Flutter/rustc 버전
   4. 데이터셋, 청크 수, 측정일, 다른 작업이 함께 돌았는지
10. **범용 패키지다. 한 앱만을 위해 고치지 않는다 (2026-11-09 사용자: "현재 프로젝트에만 맞추어 수정할 순 없어").** 특정 앱 연동에서 나온 항목은 착수 전에 범용과 앱 전용으로 나눠 이 문서에 적는다.
   1. 패키지에는 다른 앱도 쓰는 장치만 넣는다. 예: 인자를 열기, 결과에 신호를 더 돌려주기, 기본으로 꺼진 선택 옵션.
   2. 값과 규칙은 앱에 둔다. 예: 가중치 값, 거르는 기준값, 신호 조합 방식, 한 데이터에 맞춘 휴리스틱.
   3. 기본 동작과 기본값은 바꾸지 않는다. 바꾸려면 성격이 다른 문서 묶음 여러 개와 모델 여러 개로 측정한 근거를 PR에 적는다. 앱 하나의 측정은 사례 한 건이지 기본값의 근거가 아니다.
   4. 문서의 재현 예시에 특정 플러그인이나 앱을 쓸 수는 있지만, 설명은 그 원인 일반으로 쓴다.

## 현재 상태 (2026-11-13)

- main: `3505825` (#135 머지). **새 배포는 보류**(규칙 5). 다음 배포는 내부 점검으로 문제를 모두 고친 뒤에 한다.
- 0.23.0 배포 뒤 main에 머지된 것: Q1 (#132, 2026-11-09)와 D1 (#133)·S1 (#134)·B1 (#135) (셋 다 2026-11-12). 아직 배포하지 않았다. 코드 변경(Q1, S1)은 `CHANGELOG.md`의 `## Unreleased`에 있고, D1과 B1은 문서와 측정만 바꿨다.
  - S1은 Rust 코어를 바꿨다. 다음 `rag_engine_flutter` 배포가 있어야 pub 사용자에게 닿는다.
- 열린 PR 없음. D2 (#136)는 2026-11-13에 머지됐다.
- **다음 순서 (2026-11-13 합의):** W1(#137) 머지 → F1(검색 평가 기반, 범위 초안) → Q2 → Q3 → Q4 → Q5. F1은 합의 대기 중인 초안이고 착수는 사용자가 번호로 지시할 때 한다(규칙 7).

2026-11-06 기준으로 적었던 내용:
- 마지막 배포: `mobile_rag_engine` 0.23.0과 `rag_engine_flutter` 0.22.0 (pub.dev, 2026-11-04). R1 완료(태그 `v0.23.0`, pub 모드 확인 통과, 2026-11-06).
- 2026-11-06 내부 점검(`docs/reports/2026-11-06-hotfix-retrospective.md`)의 수정 묶음을 Q1~Q5로 적었다. Q1의 문서 부분은 #130.
- 아래 목록은 0.23.0에 담긴 변경이다(0.22.3 뒤 `Unreleased`였던 것).
  - 512 토큰 truncation (#115)
  - HNSW 빌드와 검색 속도, 한국어 BM25, 한국어 청킹 속도 (#116)
  - flutter_rust_bridge 2.13 (#117)
  - 모델 파일 해시 fingerprint (#118)
  - 레거시 자산 복사본 갱신 (#120). Dart만 바뀌어 `rag_engine_flutter` 배포는 필요 없고, 다음 `mobile_rag_engine` 배포에 들어간다.
  - LLM용 검색 결과 JSON과 `RagSearchTool` (#121). Dart만 바뀌었다.
- 이 항목들은 다음 `rag_engine_flutter` 배포가 있어야 pub 사용자에게 동작한다. 배포 전까지 문서는 0.22.3 기준 안내를 유지한다 (M1 레시피가 그렇게 쓰여 있다).

## 마일스톤 목록 (착수 전 합의 필요)

### H1. 회귀 하네스 (맹점 재현)

- **담당:** 세션 "H1 회귀 하네스", 브랜치 `feats/h1-regression-harness-408509`
- **상태:** 완료 (#122, 2026-11-03). M6·M7이 이 하네스를 쓰므로 이 절은 완료 목록으로 옮기지 않고 둔다. 순서는 H1 → M7 → M6 → M4 (사용자 합의).

**배경:** 2026-11-03 리뷰에서 맹점 여섯 개가 나왔다(아래 목록). 코드를 읽고 판단했고 실행으로 재현하지는 않았다. 원인은 검증이 새로 설치한 상태와 가짜 값만 봤다는 것이다. 시뮬레이터 검증은 실행마다 새 DB 이름을 썼고, 단위 테스트는 가짜 점수를 썼다. 사람이 조심하는 대신 자동 하네스로 막는다.

**맹점 목록 (2026-11-03 리뷰)**
1. **[심각] 업그레이드하면서 모델을 바꾸면 잠금이 걸리지 않는다.** 0.22.3이 만든 DB는 3칸 fingerprint `model.onnx|384|f32+vabq:none`을 가진다. `RagEngine._extendFingerprintWithoutModelIdentity`와 Rust `extend_embedding_fingerprint`는 이를 4칸으로 늘릴 때 그 순간 디스크에 있는 모델 파일의 해시를 그대로 붙인다. 그래서 업데이트 한 번에 패키지를 올리면서 KoEn(같은 `model.onnx`, 384차원)으로 바꾸면 잠금 없이 벡터가 섞인다. #120의 asset 갱신은 이 확장보다 먼저 실행되므로 같은 이름의 legacy asset 교체도 같은 구멍에 빠진다. `docs/guides/model_setup.md`의 "Later releases ... lock" 문단은 이 경로에서 틀렸다.
2. **M3 `score`:** 하이브리드 검색의 `similarity`는 RRF 점수(`1/(60+rank)`의 가중합, 최대 약 0.016)다. `toLlmJson`이 소수 셋째 자리로 반올림하면 순위 차이가 사라지고, 점수 자체도 오해를 부른다.
3. **본문 중복:** tool 결과에 `context`와 `results[].text`가 둘 다 들어가 토큰이 약 2배가 된다.
4. **인용 id 충돌:** 인용 id가 호출마다 "1"부터 다시 시작해서, 여러 번 검색하면 겹친다.
5. **[낮음] 메모리:** asset 동기화가 매 시작마다 asset 전체를 로드하고 isolate로 복사해서, 순간 메모리가 모델 크기의 약 2배가 된다.
6. **[낮음] 자잘한 점:** tool 호출마다 `listSources()` 전체를 읽는다. tool이 `dispose` 이전의 `MobileRag` 인스턴스를 붙잡고 있다. `contextOnly` 결과에서는 `results`가 비어 있다.

**목표:** 맹점 1~4번을 자동 하네스로 재현하고, 고친 뒤(M6, M7)에는 같은 하네스가 회귀를 막게 한다.

**포함**
- **H1-a. 업그레이드 E2E** (새 워크플로 `.github/workflows/upgrade_e2e.yml`, macOS만). `flutter create`로 앱을 만들고 pub.dev의 0.22.3으로 문서를 색인한 뒤 종료한다. 같은 앱(같은 데이터 컨테이너)의 의존성을 PR head로 바꿔 다시 실행한다.

  | 시나리오 | 0.22.3에서 | PR head에서 | 기대 결과 |
  |---|---|---|---|
  | S1 같은 모델 그대로 | Model Pack MiniLM | 같은 Model Pack | 잠금 없음, 재임베딩 없음 |
  | S2 같은 이름의 다른 모델 | 앱이 둔 `model.onnx`(MiniLM, prepared path) | 같은 경로의 파일을 KoEn으로 덮어씀 | 잠금 |
  | S3 legacy asset 교체 | `modelAsset: assets/mobile_rag/model.onnx` | `modelAsset: assets/h1/koen/model.onnx` | 잠금 |
  | S4 Model Pack 교체 | Model Pack MiniLM | KoEn Model Pack | 잠금 |

- **H1-b. 실제 출력 계약 테스트.** 같은 E2E 앱에서 PR head로 실제 하이브리드 검색을 돌려 검사한다. 상위 결과의 `score`가 서로 구별된다. `RagSearchTool.callJson` 결과에 같은 본문이 중복되지 않는다. tool을 두 번 호출해도 인용 id가 겹치지 않는다. 출력이 토큰 예산을 크게 넘지 않는다.
- **H1-c. PR 템플릿.** `.github/pull_request_template.md`에 "업그레이드 경로", "실제 출력으로 확인한 것", "맞물리는 코드와 깨질 수 있는 것" 절을 넣는다. 처음에는 비어 있으면 실패하는 CI job도 두었으나, 2026-11-03 사용자 지시로 뺐다. 세 절은 세션이 마무리 때 채운다.
- **재현 확인:** main에서 H1-a의 S2~S4와 H1-b가 실패하는지 확인하고 결과를 이 절과 PR 본문에 남긴다.

**재현 중 실패하는 체크의 처리:** H1 PR에서 S2~S4와 H1-b는 일부러 실패한다. 이 체크는 필수 체크로 두지 않는다. 고치기 전인 시나리오는 워크플로의 `H1_KNOWN_FAILING` 목록에 두고, 목록에 있는 시나리오의 실패는 job을 실패시키지 않고 요약에 "재현됨"으로 남긴다. 목록에 없는 시나리오가 실패하거나, 목록에 있는 시나리오가 통과하면(고쳐졌는데 목록을 안 지운 경우) job이 실패한다. M6은 S2~S4를, M7은 H1-b 항목을 목록에서 지운다.

**제외**
- 맹점 수정 (M6, M7). 맹점 5·6번 하네스 (낮음).
- 하네스를 필수 체크로 바꾸는 일 (사용자가 GitHub 설정에서 한다).

**완료 기준**
- 이 문서가 갱신돼 있다. 세 하네스가 들어 있다.
- main에서 맹점이 재현된 기록이 이 절과 PR 본문에 있다.
- 규칙 8의 네 항목을 PR 본문에 적는다.
- PR 하나, 기존 CI 통과.

**손대는 파일:** 새 파일 `.github/workflows/upgrade_e2e.yml`, `.github/pull_request_template.md`, 새 디렉터리 `tool/upgrade_e2e/**`, `analysis_options.yaml`(exclude 한 줄), `docs/milestones.md`

**재현 결과 (2026-11-03, 로컬 macOS, lib/ = main `f8838b2`, `tool/upgrade_e2e/run.sh` path 모드):** 맹점 1~4번이 모두 재현됐다.
- 0.22.3은 네 시나리오 모두 3칸 fingerprint `model.onnx|384|f32+vabq:none`(청크 8개)을 남겼다.
- macOS는 `flutter test integration_test -d macos`를 여러 번 실행해도 데이터 컨테이너(`~/Library/Containers/com.example.h1UpgradeApp`)가 남는다(p0 PASS). 실행마다 앱이 지워지는 iOS 시뮬레이터와 다르다.

| 체크 | 결과 | 내용 |
|---|---|---|
| p0 | PASS | phase A 파일이 phase B에서 보인다 |
| s1 | PASS | 잠금 없음. fingerprint가 `…|sha256:e9246dc3…`(MiniLM)로 늘어남. 청크 8→8, 검색 정상 |
| s2 | **FAIL (맹점 1)** | 잠금 없음. `…|sha256:fd688b15…`(KoEn 해시)가 붙어 MiniLM 벡터를 KoEn으로 검색한다 |
| s3 | **FAIL (맹점 1)** | s2와 같음 (legacy asset 교체) |
| s4 | **FAIL (맹점 1)** | s2와 같음 (Model Pack 교체) |
| b1 | **FAIL (맹점 2)** | 상위 3개 `score`가 `[0.016, 0.016, 0.016]` |
| b2 | **FAIL (맹점 3)** | 결과 3개 본문이 `context`와 `results[].text`에 두 번씩 들어감 |
| b3 | **FAIL (맹점 4)** | 두 번 호출한 인용 id가 둘 다 `{1, 2, 3}` |
| b4 | **FAIL (맹점 3)** | 예산 300토큰에 출력 717토큰 (한도 470 = 300 + 결과당 40 + 50) |


### M5. iPhone 실기기 측정 (KoEn)

- **상태:** 범위 초안. 합의 대기. 사용자의 실기기 연결이 필요하다.

**목표:** KoEn-E5-Tiny의 실기기 지연·메모리를 잰다. 지금은 데스크톱과 시뮬레이터 수치만 있다.

**포함**
- 기존 `query_profile_measure_test.dart` 방식(`flutter drive`)으로 MiniLM 대비 임베딩 지연, 색인 시간, 메모리를 측정
- 결과를 `docs/perf/multilingual-embedding/`에 기록하고, `model_setup.md` 비용 절의 수치를 실측으로 바꾼다.

**제외**
- 성능 개선 작업 (측정 결과에 따라 따로 적는다)

**완료 기준**
- 실기기 결과 JSON과 문서 갱신. PR 하나, CI 통과.

**손대는 파일:** `docs/perf/multilingual-embedding/**`, `docs/guides/model_setup.md`(비용 절), `example/integration_test/`(측정 테스트가 필요하면 새 파일)

### D1. 문서 정비 (README 첫 화면 + 틀린 안내 수정)

- **담당:** 세션 "D1 문서 정비", 브랜치 `docs/readme-first-screen` (worktree `.claude/worktrees/readme-restructure`)
- **상태:** 머지 완료 (#133, 2026-11-12). 2026-11-11 사용자 합의 "D1 착수는 새 세션에서 하자"로 착수했다.
- **출처:** 2026-11-11 README 검토와 설치 경로 점검, 회고(`docs/reports/2026-11-06-hotfix-retrospective.md`) 6절의 C4~C6과 "낮음" 문서 항목(지금까지 "새 문서 묶음 후보"로만 남아 있었다).
- **순서:** I1과 `docs/guides/{troubleshooting,faq}.md`가 겹친다. D1을 먼저 머지하고 I1을 그 위에서 진행한다(규칙 3).

**목표:** 처음 온 사람이 첫 화면에서 무엇을 하는 패키지인지와 쓰는 코드를 보게 하고, 따라 하면 실패하거나 틀린 결과가 나오는 문서 안내를 고친다.

**포함**
- **README 첫 화면:** 한 줄 소개 바로 아래에 문서 추가 → 검색 → `ask` 예제. "Why"는 세 줄(오프라인, 하이브리드 검색, LLM 무관). 검증 범위 표와 요구사항은 아래로 옮긴다.
- **README에서 빼는 것:** `Core-Rust` 배지, "No Rust Toolchain Required" 절, 상단의 0.20.x 안내문, 본문의 "0.2x.y부터" 표기, 근거 없는 "Pure Dart 대 Rust" 표. 빌드 때 `github.com` 접근이 필요하다는 것과 `rustup`이 있으면 소스에서 빌드한다는 것은 Requirements에 남긴다.
- **README의 틀린 내용:** Android 최소 버전(API 21 → ONNX Runtime이 요구하는 값. 착수 때 AAR에서 확인한다), Flutter 하한(3.9 → Dart 3.9.2에 맞는 값), 컴파일되지 않는 `MySearchScreen` 예제. `quick_start.md`의 같은 표기도 함께 고친다.
- **영어 전용 안내:** 기본 Model Pack이 영어 전용이라는 안내를 Installation의 설치 명령 바로 위에 둔다. 한국어는 KoEn-E5-Tiny 절차로 보낸다.
- **한국어 모델 권장 통일:** `faq.md`의 "Does it support Korean?" 답을 BGE-m3(542MB)에서 `model_setup.md`와 같은 KoEn-E5-Tiny로 바꾼다.
- **모델 교체 복구 안내 (C4):** `faq.md`, `troubleshooting.md`, `index_management.md`의 `regenerateAllEmbeddings()` 안내를 실제로 잠금을 푸는 `reembedAll()`/`clearAndRestart()`로 고치고, 오류 형식을 `embeddingFingerprintMismatch`로 맞춘다.
- **저장 파일과 백업 안내 (C6):** `faq.md`와 `index_management.md`의 파일 구성(`rag.vec`, WAL, `<base>.hnsw`), 플랫폼별 경로, 백업 대상을 실제와 맞춘다. `.dirty` 설명을 고친다.
- **단위 테스트 문서 (C5):** `docs/test/unit_testing.md`의 mock 설정을 그대로 따라 하면 통과하게 고친다.
- **지원 플랫폼 표기:** `faq.md`의 "iOS, Android, macOS만"과 `troubleshooting.md`의 "Android, iOS and macOS용 바이너리"에 Windows를 넣는다. `troubleshooting.md`의 Windows 저장 경로 예시(`getApplicationDocumentsDirectory`)를 AppSupport로 고친다.
- **`pod install` 실패 안내:** 기존 `Podfile.lock`이 옛 `onnxruntime-objc`를 고정해 실패하는 경우의 `pod update onnxruntime-objc onnxruntime-c`를 `troubleshooting.md`의 "iOS: Pod Install Failed"에 넣는다(지금은 CHANGELOG에만 있다).
- **`faq.md`의 LLM 연동 답:** `ask`를 먼저 보여 주고 `formatPrompt` 방식은 직접 조립하는 경우로 둔다.
- **pub.dev 토픽:** `pubspec.yaml`의 `flutter`를 `embeddings`로 바꾼다. 다음 배포 때 반영된다.

**제외**
- 패키지 코드 변경. `setup`의 메시지·한국어 프리셋·로컬 파일 설치·언어 불일치 경고는 따로 적는다.
- I1의 항목(정적 링크와 vendored 라이브러리 충돌, 웹 빌드, 모델 파일을 git 밖에 두기, 문서 나누는 요령, Foundation Models 예시).
- Xcode 27 안내(C1, C2): Q5에서 정한다.
- 새 스크린샷과 `pubspec.yaml`의 `screenshots`. 지금 `sample_app.png`는 답변이 모두 "정보 없음"이라 위로 올리지 않는다. 새 화면을 찍은 뒤 따로 적는다.
- `SemanticChunk.startPos`/`endPos` 단위 문서화(Q3에 있다).

**완료 기준**
- README 상단 예제와 고친 문서의 코드 예제를 실제 엔진으로 한 번씩 실행해 통과를 확인한다(회고 5절 3번: 가이드를 아무도 실행하지 않아 A1이 생겼다). 단위 테스트 문서의 예제는 그대로 옮겨 `flutter test`로 통과시킨다.
- 모델 교체 안내는 MiniLM으로 만든 DB를 다른 모델로 열어 잠금을 재현한 뒤, 문서의 절차만으로 풀리는지 확인한다.
- 백업 안내는 문서가 말한 파일만 옮긴 뒤 검색 결과가 같은지 확인한다.
- README와 문서 안의 링크와 앵커가 모두 열린다.
- 규칙 8의 네 항목. 문서만 바뀌므로 업그레이드 경로는 "해당 없음"과 이유를 적는다. PR 하나, CI 통과.

**손대는 파일:** `README.md`, `pubspec.yaml`(topics), `docs/guides/{faq,troubleshooting,quick_start}.md`, `docs/features/index_management.md`, `docs/test/unit_testing.md`, `docs/milestones.md`, `docs/guides/model_setup.md`(2026-11-12 추가, 아래 "범위 변경")

**범위 변경 (2026-11-12, 규칙 4):** `docs/guides/model_setup.md`를 손대는 파일에 넣었다. 두 곳만 고친다.
- 모델 비교 표의 깨진 앵커(`#korean-koen-e5-tiny` → `#korean-documents-koen-e5-tiny`). FAQ와 README가 한국어 사용자를 이 문서로 보낸다.
- "Switching an existing database" 절의 `clearAndRestart` 안내. 그대로 따르면 문서를 다시 넣을 수 없다(아래 실행 결과 3번).

**실행 결과 (2026-11-12, 로컬 macOS, Xcode 27.1, Flutter 3.35.5, 새 `flutter create` 앱 + 이 브랜치 path 의존성 + `rust_builder` 소스 빌드, MiniLM Model Pack과 KoEn-E5-Tiny):**
1. **버전 표기.** `onnxruntime-android` 1.23.0(`flutter_onnxruntime` 1.8.3~1.8.4)과 1.28.0(1.9.0) AAR의 매니페스트가 모두 `minSdkVersion="24"`다. Dart 3.9.2는 Flutter 3.35.3부터 들어 있다(3.35.0~3.35.2는 Dart 3.9.0). 문서를 Android API 24, Flutter 3.35.3으로 고쳤다.
2. **README 예제.** 상단 예제, "Adding Documents and Searching", `ask`, `searchMeta`, 컬렉션 예제를 실제 엔진으로 실행해 통과했다. 단, 상단 예제의 PDF 자리에 `sample_eng.pdf`(1820 청크)를 넣으면 환불 문장이 검색되지 않는다. 코드 문제라 후보 목록에 적었다(아래 후보 "큰 문서와 함께 넣은 짧은 문서"). 통과한 실행은 5 청크짜리 텍스트 PDF를 썼다.
3. **모델 교체 (C4).** MiniLM으로 만든 DB를 KoEn으로 열면 `initialize`는 성공하고 `search`와 `addDocument`가 `RagError.embeddingFingerprintMismatch(stored, current, 5)`를 던진다.
   - `reembedAll()`: 잠금이 풀리고 5개 문서가 그대로 검색된다. 이어서 한국어 문서를 넣고 한국어로 검색해 맞는 문서가 1위로 나왔다.
   - `clearAllData()`: 잠금이 풀리고 다시 넣은 문서가 검색된다.
   - `clearAndRestart()`: 잠금은 풀리지만 `sources` 5행이 남아, 같은 문서를 다시 넣으면 `isDuplicate: true, chunkCount: 0`("Source ingestion already in progress")이 돌아오고 검색 결과가 0개다. `listSources()`의 소스를 `removeSource`로 지운 뒤 넣으면 된다(실행 확인). 문서는 "처음부터"를 `clearAllData()`로 안내하고, `clearAndRestart()`에는 이 절차를 붙였다. 코드 쪽은 후보 목록에 적었다.
   - `regenerateAllEmbeddings()`: 오류 없이 끝나지만 잠금이 그대로다(C4 확인).
4. **저장 파일과 백업 (C6).** 실제 파일은 `<이름>.sqlite`, 열려 있는 동안의 `-wal`/`-shm`, `<이름>.vec`, `<이름>_hnsw.hnsw`와 컬렉션별 `<이름>_hnsw_<8 hex>.hnsw`다. 회고는 `.dirty` 파일이 없다고 했지만, 인덱스 갱신이 밀려 있는 동안에는 `<이름>.dirty`(컬렉션은 `<이름>.<8 hex>.dirty`)가 있고 재빌드 뒤 지워진다. 문서를 그렇게 고쳤다. 엔진이 열려 있을 때 `.sqlite`는 4 KB였고 내용은 `-wal`에 있었다. `MobileRag.dispose()` 뒤에는 `-wal`이 합쳐져 사라졌다. FAQ의 백업 코드가 옮긴 파일(`.sqlite`, `.vec`)만으로 다른 이름의 DB를 열어, 질의 3개의 결과(본문과 similarity 소수 6자리)와 컬렉션 검색 결과가 같음을 확인했다. `.sqlite`만 옮기면 회고의 설명처럼 조용히 비는 것이 아니라 `initialize`가 `RagError.invalidInput(... missing or invalid persisted embedding)`으로 실패한다.
5. **단위 테스트 문서 (C5).** 문서의 예제를 그대로 옮긴 테스트 4개가 `flutter test`로 통과했다. `mock.engine` stub을 빼면 3개가 `type 'Null' is not a subtype of type 'RagEngine'`으로 실패한다(재현).
6. **링크.** 바뀐 문서 7개의 링크와 앵커 74개(외부 14개 포함)가 모두 열린다.
7. **D1이 가정한 것과 달랐던 점.** `troubleshooting.md`의 Windows 저장 경로 예시는 이미 `getApplicationSupportDirectory`를 쓰고 있어 고치지 않았다. 앱은 `RagError`의 종류를 `when`/`maybeWhen`으로 구분할 수 없어서(후보 목록), 문서는 오류를 잡는 대신 `isEmbeddingFingerprintLocked`를 확인하게 했다.
- **실행하지 않고 읽기만 한 것:** iOS·Android·Windows의 저장 경로(`path_provider` 코드), `pod update onnxruntime-objc onnxruntime-c`(각 `flutter_onnxruntime` 버전의 podspec 고정값만 확인), 크래시 뒤 `.dirty` 마커로 재빌드하는 경로(코드).

### S1. 검색 누락과 재등록 (짧은 문서가 검색에서 빠짐, `clearAndRestart` 뒤 재등록 불가)

- **담당:** 세션 "S1 검색 누락과 재등록", 브랜치 `feats/s1-search-missing-short-docs-7eae01` (worktree `.claude/worktrees/s1-search-missing-short-docs-7eae01`, D1 브랜치 끝에서 땄다)
- **상태:** 머지 완료 (#134, 2026-11-12, #133 다음). 2026-11-12 사용자 "S1 착수".
- **출처:** D1 실행 결과(위 D1 절)와 후보 목록의 [높음], [중간] `clearAndRestart` 항목. 재현에 쓴 테스트와 출력은 D1 세션의 메모(`d1-docs-verification/`)에 있다.
- **순서:** Q2·Q3와 `rust_builder/rust/src/api/{source_rag,ingest_session,migration_meta,hnsw_index}.rs`가 겹친다. S1을 먼저 하고 Q2는 그 위에서 진행한다(규칙 3). D1(#133)과는 `docs/milestones.md`와 아래 문서 두 개만 겹치므로 #133 머지 뒤에 브랜치를 딴다.

**배경**
- **A. 짧은 문서가 벡터 검색에 나오지 않는다.** 환불 문장 하나와 1820 청크 PDF를 넣으면, 단독일 때 similarity 0.7295로 1위이던 문장이 `search(topK: 50)`에 없다. `sourceIds`를 준 exact scan은 찾는다. main의 Rust 코어는 배포된 `rag_engine_flutter` 0.22.0과 같으므로 0.23.0 사용자도 같을 가능성이 높다(배포 바이너리로는 재현하지 않았다).
  - 코드로 본 추정 원인(실행으로 확정하지 않음): `custom_hnsw.rs`의 `insert`는 새 노드의 이웃을 가장 가까운 M개로 고르고, 역방향 링크는 이웃의 연결이 `m_max`를 넘으면 가까운 순으로 자른다. 한 문서의 청크가 수십 개 이상 모여 있으면 멀리 있는 노드로 들어오는 링크가 모두 잘려, 나가는 링크만 있고 들어오는 링크가 없는 노드가 된다. 다양성을 보는 이웃 선택(HNSW 논문의 heuristic)이나 연결 보장이 없다.
- **B. `clearAndRestart()` 뒤에 같은 문서를 다시 넣을 수 없다.** `acknowledge_and_clear_embeddings`는 `chunks`만 지우고 `sources.status`는 `completed`로 둔다. 다시 넣으면 `decide_duplicate_decision`이 "completed, 청크 0개"를 `ResetAndResume`으로 보내지만, `claim_source_for_ingestion`은 `pending`·`failed`만 잡으므로 실패하고 "Source ingestion already in progress"가 돌아온다. 청크가 0개인 `completed` 소스는 어떤 경로로 생겼든 같은 결과다.

**목표:** 저장된 청크는 문서 크기 구성과 관계없이 벡터 검색으로 찾을 수 있고, `clearAndRestart()` 뒤에 같은 문서를 `addDocument`로 다시 넣을 수 있다.

**포함**
- **A-1. 원인 확정.** D1의 재현(짧은 문서 + `sample_eng.pdf`)을 Rust 테스트로 옮긴다: 한 군집 1800개와 떨어진 벡터 몇 개로 인덱스를 만들고, 떨어진 벡터 자신을 질의로 넣어 top-1로 나오는지 본다. main에서 실패하는지와, 들어오는 링크가 0개인 노드 수를 기록한다. 추정이 틀리면 이 절을 먼저 고친다(규칙 4).
- **A-2. 수정.** 방법은 A-1 결과로 정하고, 아래 순서로 검토한다.
  1. 이웃 선택과 역방향 가지치기를 다양성 heuristic으로 바꾼다.
  2. 빌드 뒤 들어오는 링크가 없는 노드를 찾아 연결을 보장한다.
  3. 청크 수가 적은 컬렉션은 HNSW 대신 exact scan을 쓴다(i8 scan이 f32보다 빠르고 recall@10 손실이 거의 없다는 PR6 측정이 있다). 기준 청크 수는 측정으로 정한다.
- **A-3. 회귀 방지.** A-1의 테스트를 CI에 둔다. 기존 recall 테스트(`builder_recall_at_10_matches_exact_search`, `mmap_recall_at_10_survives_save_and_load`)는 고르게 퍼진 난수 벡터만 써서 이 경우를 못 잡았다. 군집 + 외톨이 벡터 fixture를 더하고, "모든 노드가 자기 자신을 질의로 넣으면 top-10 안에 나온다"를 검사한다. Dart 쪽은 D1의 실제 엔진 재현(짧은 문서 + 큰 PDF)을 통합 테스트로 둔다.
- **A-4. 기존 인덱스.** 저장된 `.hnsw` 파일은 고쳐진 코드로 다시 만들어져야 한다. 인덱스 형식 버전을 올리거나 재빌드 조건을 넣어, 업그레이드한 앱이 옛 그래프를 그대로 쓰지 않게 한다.
- **B-1. 수정.** `clearAndRestart()` 뒤 같은 내용을 `addDocument`하면 청크가 만들어지게 한다. `claim_source_for_ingestion`이 청크 0개인 `completed` 소스를 잡게 할지, clear가 소스 상태를 바꿀지는 Dart 쪽 `decideDuplicateSourceIngestion`과 함께 읽고 정한다. 잠금 해제 → 재등록 → 검색을 Rust 테스트와 실제 엔진 실행으로 확인한다.
- **문서.** `index_management.md` 3절과 `model_setup.md` 4번의 `removeSource` 우회 안내를 고쳐진 동작에 맞춰 줄인다. `CHANGELOG.md`의 `## Unreleased`에 두 수정을 적는다.

**제외**
- 하이브리드 가중치와 불용어 문제(후보 목록 [중간]). `feat/ask-search-weights` 작업과 겹칠 수 있어 따로 정한다.
- 후보 목록 [낮음] 네 가지(`RagError` export, `pubspec.yaml`의 Flutter 하한, `sourceName` null, `DocumentParser.parse` 초기화 순서).
- HNSW 증분 삽입, ef 상한 같은 성능 후보.
- 배포와 버전 올리기(규칙 5). A의 수정은 Rust 코어를 바꾸므로 `rag_engine_flutter` 배포가 있어야 pub 사용자에게 닿는다. 배포 시점은 사용자가 정한다.

**완료 기준**
- A-1의 테스트가 수정 전 main에서 실패하고 수정 뒤 통과한다. 두 결과를 이 절과 PR 본문에 적는다.
- 실제 엔진(macOS)에서 짧은 문서 + `sample_eng.pdf` 뒤 `search`와 `searchHybrid`가 환불 문장을 돌려준다. 순서를 바꾼 경우와 짧은 문서 6개인 경우도 확인한다.
- 기존 recall·속도 기준이 나빠지지 않는다: Rust recall 테스트, `hnsw_build_benchmark`, 80-query passage 평가(`passage_recall@10` 0.925)를 수정 전후로 비교해 적는다. 빌드 시간이 늘면 수치와 함께 적는다.
- B-1: MiniLM으로 만든 DB를 KoEn으로 열고 `clearAndRestart()` 뒤 같은 문서 5개를 다시 넣어 `isDuplicate: false`와 검색 결과를 확인한다.
- 규칙 8의 네 항목. 업그레이드 경로는 0.23.0이 남긴 DB와 `.hnsw` 파일에서 시작해, 업그레이드 뒤 첫 실행에 짧은 문서가 검색되는지 확인한다(A-4).
- PR 하나, CI 통과. `Cargo.toml` 버전과 `pubspec.yaml` 버전은 올리지 않는다.

**손대는 파일:** `rust_builder/rust/src/api/{custom_hnsw,hnsw_index,source_rag,ingest_session,migration_meta}.rs`, `lib/services/source_rag_service.dart`(중복 판정, 필요하면), `test/**`와 `example/integration_test/`(새 테스트), `docs/features/index_management.md`, `docs/guides/model_setup.md`, `CHANGELOG.md`, `docs/milestones.md`

**범위 변경 (2026-11-12, 규칙 4, 실행 결과를 보고 고쳤다)**
- **A의 원인:** 추정이 맞았다. 다만 들어오는 링크가 0개인 노드만이 아니었다. 같은 짧은 문서들끼리만 서로 이어져 군집에서 들어가는 길이 없는 작은 덩어리가 생겼고, 도달할 수는 있어도 먼 노드에서 들어오는 링크 하나뿐이라 검색 빔이 지나가지 않는 노드도 있었다(아래 A-1 결과).
- **완료 기준의 `searchHybrid`:** 기본 가중치(벡터 0.2, BM25 0.8)에서는 고친 뒤에도 환불 문장이 top 50에 없다. 벡터 검색은 1위로 돌려주지만, BM25가 "How/long/is/the/period"로 맞힌 PDF 청크 약 180개가 RRF에서 벡터 1위(0.2/61)보다 앞선다. 이것은 후보 목록의 [중간] 하이브리드 가중치 문제이고 S1 제외 항목이다. 완료 기준을 "`search`가 돌려주고, 같은 가중치(0.5/0.5) `searchHybrid`의 융합 후보에 들어온다"로 바꿨다. 기본 가중치 순위는 기록만 한다.
- **B의 `isDuplicate`:** 같은 소스 행을 다시 쓰는 재개 경로라 `isDuplicate: true`, `message: "Source resumed and completed"`와 새 청크가 돌아온다. 실패한 소스를 다시 넣을 때와 같은 기존 계약이다. 이 값을 false로 바꾸면 실패 재개 경로도 함께 바뀌므로 바꾸지 않았다. 완료 기준을 "`isDuplicate: false`"에서 "청크가 만들어지고(`chunkCount` > 0) 검색된다"로 바꿨다.
- **손대는 파일 추가:** `lib/src/rust/api/source_rag.dart`(`claim_source_for_ingestion` doc 주석이 바뀌어 `flutter_rust_bridge_codegen generate`로 다시 만들었다. 바뀐 것은 주석뿐이다).
- **A-4 방식:** `.hnsw` 파일 헤더의 버전 바이트만 1에서 2로 올렸다(파일 배치는 그대로). DB의 `migration_meta.hnsw_format_version` 축은 올리지 않았다. 올리면 0.23.0으로 되돌린 앱이 `UnsupportedMigrationVersion`으로 DB를 열지 못한다. 지금 방식에서는 0.23.0이 v2 파일을 거부하고 한 번 다시 만든다.

**실행 결과 (2026-11-12, 로컬 macOS, Xcode 27.1, Flutter 3.35.5)**
1. **A-1 (Rust, 수정 전 `390cd19`):** 군집 1800개(중심과 cos 약 0.8) + 떨어진 벡터 6개(cos 약 0.4)로 만든 인덱스에서, 떨어진 벡터를 자기 벡터로 검색해도 1위가 아니었다.

   | 넣는 순서 | 들어오는 링크 0개 노드 | 진입점에서 도달 불가 노드 | 1위가 아닌 외톨이 |
   |---|---|---|---|
   | 외톨이 먼저 | 6 | 7 | 5/6 |
   | 외톨이 나중 | 11 | 10 | 6/6 |

   "모든 노드가 자기 자신을 질의로 넣으면 top-10 안에 나온다"는 1806개 중 15개, 14개가 실패했다. 수정 뒤에는 모든 값이 0이고 두 테스트가 통과한다.
2. **A-2 수정:** 이웃 선택과 역방향 가지치기에 HNSW 논문의 heuristic(Algorithm 4)을 쓰고, 빌드 끝에 진입점에서 도달할 수 없는 노드를 가장 가까운 도달 가능 노드에 잇는다(`connect_unreachable_nodes`). heuristic만으로는 외톨이 나중 순서에서 1개가 남았고, 도달 보장만으로는 외톨이 먼저 순서에서 5/6이 여전히 1위가 아니었다. 그래서 둘 다 넣었다. 작은 컬렉션 exact scan(방법 3)은 쓰지 않았다.
3. **Rust 테스트:** `cargo test --lib -- --test-threads=1` 257개 통과(무시 13). 기존 recall@10: builder 0.984 → 0.99, mmap(Q8_0) 0.978 → 0.984.
4. **빌드 시간 (`hnsw_build_benchmark`, release + `vector_faer`):** 수정 전(`390cd19`)과 수정 후를 같은 조건에서 번갈아 돌렸다(2000/군집은 3회, 균일 5000은 12회, 20000은 1회).

   | 데이터 | 빌드 시간 전 → 후 | 검색 1회 전 → 후 | recall@10 전 → 후 |
   |---|---|---|---|
   | 균일 난수 2000 | 0.43~0.46초 → 0.51~0.53초 (+약 17%) | 약 155µs → 약 155µs | 0.98 → 0.98 |
   | 균일 난수 5000 | 1.49~1.69초 → 5.30~6.31초 (약 3.6배) | 약 230µs → 약 230µs | 0.85 → 0.85 |
   | 균일 난수 20000 | 18.4초 → 68.8초 (약 3.7배) | 0.81ms → 0.99ms | 0.56 → 0.57 |
   | 군집 20개 × 100 (2000) | 0.29초 → 0.22초 | 22µs → 63µs | 0.72~0.83 → 1.0 |
   | 군집 20개 × 250 (5000) | 0.75초 → 0.55초 | 37µs → 56µs | 0.77~0.86 → 1.0 |

   균일 난수는 heuristic이 거의 아무것도 걸러내지 않는 최악의 경우다. 모든 가지치기가 O(M²) 거리 계산을 하므로 1000개를 넘는 크기(M0=40)에서 빌드가 약 3.6배 느려졌다. 문서처럼 뭉친 데이터에서는 빌드가 오히려 빨라졌고 recall@10이 1.0이 됐다. 대신 검색 1회는 20~40µs 늘었다(이전 그래프가 탐색을 일찍 끝내던 만큼이다). 실제 문서 1820 청크 PDF의 재빌드 시간은 따로 재지 않았다.
5. **실제 엔진 A (새 macOS 앱, MiniLM Model Pack, `example/integration_test/short_document_recall_test.dart`):**
   - pub.dev 0.23.0: 환불 문장 + `sample_eng.pdf`(1821 청크) 뒤 `search(topK: 50)`에 없음(topSim 0.4377). `.hnsw` 파일 헤더 v1.
   - 같은 앱 컨테이너를 이 브랜치로 열고 문서를 더 넣지 않은 채 첫 `search`: 환불 문장이 vector 1위(sim 0.7295). 파일은 v1에서 v2로 다시 만들어졌다.
   - 이 브랜치에서 새로 만든 DB: 짧은 문서 → PDF, PDF → 짧은 문서, 다시 연 뒤 모두 vector 1위(sim 0.7295). 짧은 문서 6개 + PDF에서는 다섯 질의가 각자의 문서를 vector 1위로 찾았고, HNSW 질의만 2위였다(sim 0.3375).
   - `searchHybrid` 순위(0.2/0.8, 0.5/0.5): 환불 질의 -1, 32~35. 나머지 네 질의는 0, 0(HNSW 질의는 2, 1).
6. **실제 엔진 B:** MiniLM으로 만든 DB(문서 5개)를 KoEn-E5-Tiny로 열면 잠김(remaining=5). `clearAndRestart()` 뒤 sources=5, chunks=0. 같은 5개를 `addDocument`하면 각각 chunks=1, "Source resumed and completed". 질의 5개가 모두 맞는 문서를 1위로 돌려준다. 수정 전에는 "Source ingestion already in progress", chunks=0이었다(D1 실행 결과 3번, Rust 테스트도 수정 전 `DuplicateInProgress`로 실패).
7. **80-query passage 평가** (`hybrid_passage_relevance_measure_test.dart`, 80 balanced, `example/assets/backup_onnx/model.onnx`):

   | 가중치 | passage_recall@10 전 → 후 | answerable_context@10 전 → 후 | passage_mrr@10 전 → 후 |
   |---|---|---|---|
   | default_hybrid (0.2/0.8) | 0.9125 → 0.9375 | 0.8875 → 0.9125 | 0.660 → 0.763 |
   | vector_only | 0.475 → 0.650 | 0.400 → 0.600 | 0.369 → 0.468 |
   | bm25_only | 0.900 → 0.900 | 0.875 → 0.875 | 0.791 → 0.791 |
   | 0.4/0.6 | 0.800 → 0.925 | 0.788 → 0.825 | 0.579 → 0.725 |
   | 0.6/0.4 | 0.6125 → 0.8125 | 0.450 → 0.6875 | 0.499 → 0.627 |

   Xcode 27에서는 `flutter drive --profile`이 cargokit의 Rust 빌드에서 실패해서 두 번 모두 debug 모드로 돌렸다. 같은 조건에서 전후만 비교한 수치다. 6월 profile 기록(0.925, vector_only 0.95)과 절대값을 비교하면 안 된다.
- **실행하지 않고 읽기만 한 것:** Android·iOS·Windows의 같은 경로(Rust 코드는 같다), `hnsw_streaming_rebuild`가 꺼진 플랫폼의 수집 경로(`build_hnsw_index`도 같은 함수를 거친다), 0.23.0으로 되돌렸을 때 v2 파일을 거부하고 다시 만드는 경로(0.23.0의 `version != 1` 검사를 읽었다).

### B1. 기본 모델 passage 평가 재측정 (MiniLM, KoEn-E5-Tiny)

- **담당:** 세션 "S1 검색 누락과 재등록"(S1에 이어 같은 세션에서 진행, 2026-11-12 사용자 "진행해"), 브랜치 `feats/b1-passage-remeasure` (`4e2ed87`에서 땄다)
- **상태:** 머지 완료 (#135, 2026-11-12, #133 → #134 → #135 순서). 2026-11-12 사용자 "착수해줘".
- **출처:** S1 조사(후보 목록의 "6월 기록은 같은 조건의 수치가 아니다"). README와 `docs/local-rag-engine.md`의 `passage_recall@10 = 0.925`는 BGE-m3(1024차원)로 잰 값이다. 6월에 시험한 1024차원 모델은 BGE-m3뿐이다(사용자 확인).
- **순서:** S1(#134) 머지 뒤 main에서 재기로 했으나, #133과 #134가 열려 있는 동안 착수했다(규칙 4로 고침). 그래서 #134 브랜치 끝 `4e2ed87`의 코드로 잰다. `cf37f76` 뒤로 바뀐 것은 문서와 테스트뿐이라 엔진 코드는 머지될 것과 같다. S1 전후로 벡터 결과가 크게 다르다(`vector_only` 38/80 → 52/80).

**배경:** 기본 Model Pack(MiniLM)으로 S1 브랜치에서 잰 값(debug)은 다음과 같다.
- default_hybrid 0.9375: 영어 30/32, 한국어 29/32로 BGE-m3 6월 기록(0.925)과 비슷하다.
- vector_only 0.650: 영어 30/32, 한국어 11/32다. 한국어는 영어 전용 모델의 한계다.

문서는 한국어 사용자를 KoEn-E5-Tiny로 보내지만, 이 질의셋으로 KoEn을 잰 적이 없다.

**목표:** 지금 코드와 패키지가 권장하는 두 모델로 80-query passage 평가를 같은 조건에서 재고, 어떤 모델과 조건의 수치인지 함께 남긴다.

**포함**
- 80 balanced 질의셋(`wiki_article_sources_manifest_80_balanced_v1.json` 등 세 파일)으로 두 모델을 잰다. 다섯 가중치 프로필 전부를 재고, 언어별·질의 종류별 결과도 남긴다.
  - MiniLM: `stable-minilm-l6-v2-arm64-en` Model Pack
  - KoEn-E5-Tiny: `docs/guides/model_setup.md` 절차
- 같은 조건: 같은 main 커밋, 같은 빌드 모드, 새 DB.
  - 빌드 모드는 profile을 우선으로 한다. Xcode 27에서 profile Rust 빌드가 실패하면(후보 목록) 우회해서 재거나, debug로 재고 그렇게 적는다.
- 기준선이 같은 조건인지 확인하려고 vector_only는 exact scan 결과도 함께 잰다. 6월 기록과 맞춰 보려면 BGE-m3도 같은 조건으로 한 번 잰다. BGE-m3 파일이 로컬에 없으면 받아서 쓴다.
- 결과 기록: `docs/perf/`에 새 보고서를 두고 artifact JSON을 넣는다. 모델, fingerprint, 커밋, 빌드 모드, 청크 수를 적는다.

**제외**
- README와 `docs/local-rag-engine.md`의 수치 변경. 결과를 본 뒤 따로 정한다.
- 모델 추가, 기본 모델 변경, e5 계열의 `query:`/`passage:` 접두어 지원(후보 목록에 따로 있다). KoEn은 지금 엔진 그대로(접두어 없이) 잰다.
- 하이브리드 가중치 조정(후보 목록 [중간]).
- 측정 하네스를 저장소에 넣는 일. 하네스와 평가셋은 지금 gitignore 대상이다. 넣을지는 따로 정한다.

**완료 기준**
- 두 모델(가능하면 BGE-m3까지)의 다섯 프로필 결과가 같은 조건으로 보고서에 있고, 각 수치에 모델과 조건이 붙어 있다.
- vector_only가 exact scan과 같은지 확인한 결과가 있다.
- 규칙 8의 네 항목. 측정만 하므로 업그레이드 경로는 "해당 없음"과 이유를 적는다. PR 하나, CI 통과.

**손대는 파일:** `docs/perf/passage-benchmark-2026-11/`(새 보고서와 `results/`), `docs/milestones.md`

**범위 변경 (2026-11-12, 규칙 4)**
- **담당 세션:** 새 세션을 띄울 수 없는 상태(Remote Control)라 S1 세션이 이어서 진행했다. 이 세션은 자기 worktree 밖에 쓸 수 없어서, worktree `s1-search-missing-short-docs-7eae01`에서 브랜치를 `feats/b1-passage-remeasure`로 바꿔 작업했다.
- **artifact:** 원본 JSON(각 약 3.5 MB, 코퍼스 미리보기 포함)은 넣지 않았다. 메타데이터, 집계, 질의별 정답 순위만 담은 요약(각 약 110 KB)을 넣었다. 폴더 이름은 `results/`다. `artifacts/`는 `.gitignore`에 걸린다. 원본은 공유 메모 폴더에 있다.
- **BGE-m3:** 내려받지 않았다. 6월 예제 앱 컨테이너(`com.example.mobileRagEngineExample`)에 남아 있던 같은 파일(569 MB, 토크나이저 Unigram 250,002)을 복사해 썼다.

**결과 (2026-11-12, `4e2ed87`, profile, 로컬 Mac)** — 자세한 표는 [`docs/perf/passage-benchmark-2026-11/README.md`](perf/passage-benchmark-2026-11/README.md)

| `passage_recall@10` | MiniLM | KoEn-E5-Tiny | BGE-m3 | 6월 BGE-m3 |
|---|---|---|---|---|
| default_hybrid | 0.9375 | 0.9625 | 0.975 | 0.925 |
| vector_only | 0.650 (한국어 11/32) | 0.950 | 0.975 | 0.950 |

- **같은 조건:** 세 모델 모두 vector_only의 질의별 정답 순위가 exact scan과 80개 전부 같다.
- **빌드 모드:** MiniLM은 debug 값과 profile 값이 같았다.
- **profile 빌드 우회:** Xcode 27 profile 빌드는 링커 래퍼(`-no_fixup_chains`)와 arm64 단일 빌드로 우회했다. 원인은 후보 목록의 Xcode 27 항목에 적었다.
- **남은 결정:** README 수치를 어떻게 바꿀지는 B1 제외 항목이라 따로 정한다.

### D2. 검색 품질 수치를 모델별로 고치기 (README, `docs/local-rag-engine.md`)

- **담당:** 세션 "D2 수치 모델별", 브랜치 `claude/d2-metrics-by-model-eed8b3` (worktree `.claude/worktrees/d2-metrics-by-model-eed8b3`, main `3505825`에서 땄다)
- **상태:** 머지 완료 (#136, 2026-11-13). 2026-11-13 사용자 "새 세션 하나 파서 D2 진행". BGE-m3는 `docs/local-rag-engine.md`에만 참고 한 줄로 넣고 README에는 넣지 않았다(이유는 PR 본문). 범위 초안은 2026-11-12 사용자 "위 수치도 마일스톤에 작성해줘"로 적었다.
- **시점 (2026-11-13 합의):** 문서는 지금 바꾼다. 수치가 S1 수정이 들어간 코드의 값이고, 그 수정은 다음 `rag_engine_flutter` 배포부터 pub 사용자에게 닿는다는 점을 한 줄로 적는다. 배포 버전 번호는 적지 않는다.
- **출처:** B1 결과(#135, `docs/perf/passage-benchmark-2026-11/README.md`).
- **순서:** #133 → #134(S1) → #135(B1) 머지 뒤에 main에서 브랜치를 딴다. README는 D1(#133)도 고치므로 D1 머지 뒤여야 한다(규칙 3).

**배경**
- README "Verified scope" 표(297행)와 `docs/local-rag-engine.md`(72행)는 `passage_recall@10 = 0.925`, `answerable_context@10 = 0.938`을 모델 이름 없이 "shipped default hybrid profile"의 값으로 적고 있다.
- 이 값은 2026-06-12에 BGE-m3(569 MB)로 잰 것이다. 기본 Model Pack(MiniLM)의 값이 아니다.
- B1 측정(`4e2ed87`, profile, 같은 80 질의, 모델마다 새 DB)은 다음과 같다.

| 모델 | default_hybrid `passage_recall@10` | `answerable_context@10` | vector_only `passage_recall@10` |
|---|---|---|---|
| MiniLM (기본 Model Pack, 23 MB) | 0.9375 | 0.9125 | 0.650 (영어 30/32, 한국어 11/32) |
| KoEn-E5-Tiny (한국어 권장, 38 MB) | 0.9625 | 0.975 | 0.950 |
| BGE-m3 (569 MB) | 0.975 | 0.9875 | 0.975 |

- **S1 수정 포함:** 이 수치는 S1의 HNSW 수정이 들어간 엔진의 값이다. 배포된 `rag_engine_flutter` 0.22.0(지금 pub 사용자)에는 그 수정이 없다. S1 수정 전 코드에서 MiniLM은 default_hybrid 0.9125, vector_only 0.475였다(debug, S1 실행 결과 7번).

**목표:** 문서의 검색 품질 수치에 어떤 모델과 조건으로 잰 값인지 붙이고, 지금 코드의 기본 모델 값을 보여 준다.

**포함**
- README 297행과 `docs/local-rag-engine.md` 72행의 0.925/0.938을 모델별 수치로 바꾼다.
  - 기본 MiniLM과 한국어 KoEn-E5-Tiny는 꼭 넣는다. BGE-m3는 참고로 넣을지 착수 때 정한다.
- 수치마다 조건을 짧게 붙인다(80 질의, 영어 32·한국어 32·다국어 16, profile, 측정일). 자세한 내용은 B1 보고서로 링크한다.
- MiniLM이 영어 전용이라 한국어 벡터 검색이 약하다는 점과 한국어는 KoEn을 쓰라는 안내를 같은 줄이나 바로 아래에 둔다. README에 이미 있는 영어 전용 안내(D1)와 문구를 맞춘다.
- 배포 버전과의 관계를 적는다. 이 수치는 S1 수정이 들어간 다음 `rag_engine_flutter` 배포부터의 값이다. 문서를 언제 바꿀지(지금 바꾸고 버전을 적을지, 배포 때 바꿀지)는 착수 전에 정한다. 규칙 5의 "배포 전까지 문서는 배포된 버전 기준 안내를 유지한다"와 맞춰야 한다.

**제외**
- 새 측정. B1 수치를 쓴다. 코드가 바뀌어 다시 재야 하면 마일스톤을 먼저 고친다.
- 하이브리드 가중치 조정(후보 목록 [중간]). B1에서 KoEn·BGE-m3는 벡터 비중을 높일수록 좋아졌지만 이 마일스톤에서는 다루지 않는다.
- 측정 하네스를 저장소에 넣는 일, 다른 문서의 수치(`docs/perf/` 아래 과거 보고서는 그대로 둔다).

**완료 기준**
- 바꾼 두 곳의 수치가 B1 보고서의 값과 같고, 각 수치에 모델이 적혀 있다.
- 링크와 앵커가 열린다.
- 규칙 8의 네 항목. 문서만 바뀌므로 업그레이드 경로는 "해당 없음"과 이유를 적는다. PR 하나, CI 통과.

**손대는 파일:** `README.md`, `docs/local-rag-engine.md`, `docs/milestones.md`

### W1. 하이브리드 순위 (흔한 단어만 맞은 청크가 정답을 밀어냄, `ask` 가중치 인자)

- **담당:** 세션 "W1 어간 처리 재작업"(2026-11-13~), worktree `.claude/worktrees/w1-stemmer-rework-195896`(브랜치 `claude/w1-stemmer-rework-195896`, PR #137 끝 `529e5ea`에서 땄다). 커밋은 PR #137의 브랜치 `claude/w1-hybrid-ranking-95dfb8`에 fast-forward로 올린다. 처음 담당은 세션 "W1 하이브리드 순위"(worktree `.claude/worktrees/w1-hybrid-ranking-95dfb8`, W1 초안 커밋 `9f88185`에서 땄다. 그 아래는 main `a6992cc`)였다.
- **상태:** PR #137 열림, 재작업(S1) 반영 (2026-11-13). 착수는 사용자 "새 세션에서 W1 착수", 재작업은 사용자 "새 세션으로 진행"(2026-11-13). 범위 초안은 2026-11-13 사용자 "가중치 초안 써줘"로 적었다.

**범위 변경: 손으로 짠 복수형 규칙을 표준 어간 처리로 바꾼다 (2026-11-13, 규칙 4)**
- **이유:** PR #137 검토에서 `bm25_search.rs`의 `plural_forms`가 무관한 낱말을 서로 맞추는 것이 나왔다(`not`↔`notes`, `car`→`cares`, `plan`→`planes`, `times`→`tim`, `new`→`news`). 또 `score_groups`가 형태마다 그 형태의 IDF로 점수를 매겨 최댓값을 취하므로, 질의의 흔한 낱말("not")이 문서의 드문 형태("notes")의 높은 IDF를 받는다. 사용자는 이를 오류로 판단했고, 손으로 짠 규칙 대신 표준 알고리즘을 쓰기로 했다.
- **바뀌는 것:** 손으로 짠 `plural_forms`와 형태별 IDF 최댓값을 버린다. 영어 어간 처리는 표준 Snowball English(Porter2)를 `rust-stemmers` 크레이트로 쓴다. **새 Rust 의존성이 생긴다.**
- **후보 둘을 같은 조건으로 잰다.**
  - (S1) 색인과 질의 양쪽에서 ASCII 영문 토큰을 Snowball English로 어간 처리한다. 한글·CJK 토큰과 Hangul bigram은 그대로다. 형태 확장 코드와 "두 가중치가 모두 0이 아닐 때만" 스위치를 지운다. **BM25 색인 토큰이 바뀐다**(`bm25_only`도 바뀐다). BM25 색인은 디스크에 저장되지 않고 활성화 때 `chunks` 테이블에서 메모리로 다시 만들어지므로(`rebuild_chunk_bm25_index_for_collection_inner`) 저장 데이터 마이그레이션은 없다.
  - (S2) 색인은 그대로 두고 하이브리드 질의에서만, 같은 Snowball 어간을 가진 색인 내 형태를 한 묶음으로 찾는다. 묶음의 IDF는 묶음 전체의 문서 수로 계산한다(Lucene `SynonymQuery` 방식).
- **고르는 기준:** (S1)이 README 예제를 고치고 default_hybrid `passage_recall@10`이 세 모델 모두 PR #137의 값(0.9375 / 0.950 / 0.975) 이상이면 (S1). 아니면 (S2)를 본다. 둘 다 PR #137 값보다 낮으면 푸시 전에 수치를 보이고 묻는다. (S1)의 `bm25_only` 변화는 실패로 보지 않고 수치만 적는다.
- **추가 완료 기준:** 위 오탐(`not`/`notes`, `car`/`cares`, `plan`/`planes`)이 서로 맞지 않는다는 Rust 테스트와, 질의의 흔한 낱말이 다른 형태의 높은 IDF를 받지 않는다는 Rust 테스트(수정 전 코드에서 실패 확인). 표준 어간 처리의 알려진 오탐(예: university/universe)과 영어 전용이라는 점을 가이드에 적는다. BM25 한 번의 시간과 색인 빌드 시간을 잰다.
- **그대로 두는 것:** `prepareAsk`/`ask`의 가중치 인자, 인용 괄호, `test/unit/ask_test.dart`, `short_document_recall_test.dart`의 `prepareAsk` 단계, 규칙 10·I1·후보 줄, `ask.md`의 "Short documents next to a large one" 절(복수형 문장만 고친다). `MobileRag.useEngineForTest`는 범위 밖에서 들어간 공개 테스트용 API라 PR 본문에 "받아들일지 결정 필요"로 적는다.
- **출처:** 후보 목록의 "[중간] 기본 하이브리드 가중치에서 불용어만 맞은 청크가 정답보다 앞선다"(D1), S1 PR(#134) 본문의 "`searchHybrid` with the default weights still does not return the refund sentence", 메인 체크아웃 브랜치 `feat/ask-search-weights`의 커밋 안 된 작업(2026-11-09).
- **순서:** D2(#136) 머지 뒤 main에서 브랜치를 딴다. Q4와 `lib/services/ask.dart`가 겹치므로 Q4보다 먼저 한다(규칙 3). Q2·Q3과는 Rust 파일이 겹치지 않는다.

**배경**
- **README 첫 화면 예제가 `ask`에서 정답을 못 찾는다.**
  - 예제는 환불 문장 하나와 PDF를 넣고 `rag.ask('How long is the refund period?')`를 부른다.
  - `ask`와 `prepareAsk`는 `searchHybridWithContext`를 기본 가중치(벡터 0.2, BM25 0.8)로 부르고 상위 5개만 프롬프트에 넣는다.
  - S1 뒤 실측(MiniLM, 1821 청크): 환불 문장은 벡터 1위(0.7295)인데 `searchHybrid(topK: 50)`에 없다. 0.5/0.5로 바꿔도 32~35위다.
  - `rag.search`(예제 2번)는 S1 뒤 1위로 나온다. 깨지는 것은 3번(`ask`)이다.
- **원인 (코드로 확인, `hybrid_search.rs`의 RRF와 `bm25_search.rs`의 토큰화):**
  - 결합은 순위만 쓴다: `vector_weight / (60 + 벡터 순위) + bm25_weight / (60 + BM25 순위)`.
  - BM25 목록에는 질의 단어가 하나라도 맞은 청크가 모두 들어온다. 토큰화는 한 글자 `a`·`i`만 빼므로 "how", "is", "the"만 맞은 청크도 순위를 받는다.
  - 기본 가중치에서는 BM25 r위(벡터 순위 없음)가 `0.8 / (60 + r)`이고 벡터 1위(BM25 불일치)가 `0.2 / 61`이다. r이 184 이하이면 BM25 쪽이 앞선다. 큰 문서가 있으면 흔한 단어만 맞은 청크 180여 개가 정답 앞에 선다.
  - 질의의 "refund"와 문서의 "Refunds"는 다른 토큰이라 BM25에서 맞지 않는다(어간 처리 없음).
- **가중치만으로는 풀리지 않는다.** 0.5/0.5에서도 32~35위다. B1 측정에서 가중치의 좋은 값은 모델마다 반대였다.

  | `passage_recall@10` | MiniLM | KoEn-E5-Tiny | BGE-m3 |
  |---|---|---|---|
  | 0.2/0.8 (기본) | 0.9375 | 0.9625 | 0.975 |
  | 0.4/0.6 | 0.925 | 0.9875 | 1.000 |
  | 0.6/0.4 | 0.8125 | 0.9875 | 1.000 |

- **`feat/ask-search-weights`의 커밋 안 된 작업 (main `7a67b09` 기준, 파일 6개):**
  - `prepareAsk`/`ask`에 `vectorWeight`/`bm25Weight` 인자(`MobileRag`, `CollectionRag`). 기본값은 그대로다.
  - 인용 파싱이 `「1」`·`『1』`도 읽는다(Q4 B12의 일부).
  - `docs/milestones.md`에 "범용 패키지" 규칙과 I1 마일스톤, 후보 몇 줄. 이 규칙의 번호 9는 main의 규칙 9(측정 기록)와 겹친다.

**목표:** 벡터 검색이 분명하게 찾은 구절이, 흔한 단어만 맞은 BM25 결과에 밀려 하이브리드 상위에서 빠지지 않게 한다. `ask`에서 가중치를 바꿀 수 있게 한다.

**포함**
- **W-1. 재현 테스트부터.** 고치기 전에 실패하는 테스트를 만든다.
  - Rust 단위 테스트: 벡터 1위이고 BM25 불일치인 문서와, 흔한 단어만 맞은 문서 200개를 넣었을 때의 결합 순위.
  - `example/integration_test/short_document_recall_test.dart`에 `prepareAsk`(topK 5, 기본 인자) 단계를 더한다.
- **W-2. 고칠 방식을 측정으로 정한다.** 아래 후보를 같은 조건으로 재고 하나를 고른다. 고른 이유와 버린 후보의 수치를 PR에 적는다.
  - (a) BM25 후보 거르기: 질의 토큰 가운데 드문 것(IDF 기준)이 하나도 맞지 않은 청크를 BM25 목록에서 뺀다. 언어별 불용어 목록이 필요 없다. **권장 출발점.**
  - (b) BM25 점수 기준 거르기: 점수가 1위 점수의 일정 비율보다 낮은 청크를 뺀다.
  - (c) 결합 방식: 한쪽 목록에만 있는 문서의 처리(없는 쪽에 큰 순위를 주는 방식 등)를 바꾼다.
  - (d) 영어 복수형 정도의 가벼운 어간 처리. "refund"/"Refunds"를 맞게 한다. BM25 인덱스 토큰이 바뀌므로 기존 DB의 인덱스가 어떻게 다시 만들어지는지 먼저 확인한다.
- **W-3. `ask` 가중치 인자.** `feat/ask-search-weights`의 `lib/mobile_rag.dart`, `test/unit/ask_test.dart`, `CHANGELOG.md` 변경을 main 위로 옮긴다.
- **W-4. 브랜치의 나머지 변경 정리.** 인용 괄호(`「1」`·`『1』`)와 `docs/milestones.md` 변경(범용 패키지 규칙을 규칙 10으로, I1, 후보 줄)을 이 PR에 함께 넣는다. 그 뒤 `feat/ask-search-weights`는 지운다. 따로 나누려면 착수 전에 정한다.
- **W-5. 문서.** `docs/guides/ask.md`와 검색 가이드에 가중치 인자와 바뀐 동작을 적는다. `CHANGELOG.md` `## Unreleased`.

**제외**
- 기본 가중치 0.2/0.8 변경. 좋은 값이 모델마다 반대라(위 표) 모델별 기본값은 별도 후보로 남긴다.
- 리랭커, 관련 없는 질문 거르기 신호(후보 목록), e5 계열 `query:`/`passage:` 접두어, 한국어 프리셋.
- 언어별 불용어 목록을 넣는 일. (a)~(d)로 풀리지 않으면 마일스톤을 먼저 고친다(규칙 4).
- 버전 변경과 배포. Rust 코어가 바뀌므로 다음 `rag_engine_flutter` 배포가 있어야 pub 사용자에게 닿는다.

**완료 기준**
- **README 예제:** 환불 문장 + `sample_eng.pdf`(MiniLM Model Pack, 새 DB)에서 `prepareAsk('How long is the refund period?')`의 구절 5개 안에 환불 문장이 있다. PDF를 먼저 넣어도, 짧은 문서가 6개여도 같다.
- **80 질의 평가가 나빠지지 않는다.** MiniLM, KoEn-E5-Tiny, BGE-m3의 default_hybrid `passage_recall@10`이 B1 값(0.9375 / 0.9625 / 0.975)보다 낮지 않고, 언어별 수치와 `answerable_context@10`, `passage_mrr@10`도 함께 적는다. 하나라도 떨어지면 PR을 열기 전에 수치를 사용자에게 보이고 묻는다.
  - 측정 하네스와 평가셋은 저장소에 없다(gitignore). B1 세션이 쓴 로컬 파일과 공유 메모 폴더의 원본을 쓴다.
  - 규칙 9대로 모델 fingerprint, 커밋, 빌드 모드, 기기, 청크 수, 측정일을 적는다.
- **성격이 다른 문서 묶음 둘 이상에서 확인한다:** 위키 문서 80개(평가셋)와 짧은 문서 + 긴 PDF(README 형태). `vector_only`와 `bm25_only` 프로필의 결과는 바뀌지 않아야 한다.
- **검색 시간:** `searchHybrid` 한 번의 시간을 수정 전후로 잰다(1,821 청크와 평가셋 4,492 청크).
- **`ask` 인자:** 기본 인자의 결과가 수정 전과 같은 검색 호출을 만든다는 단위 테스트, 가중치를 준 호출이 그 값으로 검색한다는 단위 테스트.
- 규칙 8의 네 항목. 업그레이드 경로는 0.23.0이 남긴 DB에서 시작해 첫 검색이 되는지와, BM25 인덱스가 다시 만들어지는지를 본다. PR 하나, CI 통과.

**손대는 파일:** `rust_builder/rust/src/api/{hybrid_search,bm25_search}.rs`, `lib/mobile_rag.dart`, `lib/services/ask.dart`, `test/unit/ask_test.dart`, `example/integration_test/short_document_recall_test.dart`, `docs/guides/ask.md`, 검색 가이드, `CHANGELOG.md`, `docs/milestones.md`

**측정 (2026-11-13)**
- 조건: 엔진 `9f88185` + 실험 코드(변형을 파일로 고르는 임시 코드, 커밋하지 않음), 로컬 Mac(macOS 27, Xcode 27.1, Flutter 3.35.5, rustc 1.91.1). README 형태는 debug(`short_document_recall_test.dart`), 80 질의는 profile(링커 래퍼 + arm64, B1과 같은 하네스·평가셋). 세 모델의 기준선(none)이 B1 값과 fingerprint까지 같다: MiniLM `…e9246dc3…` 4667 청크, KoEn-E5-Tiny `…fd688b15…` 4492 청크, BGE-m3 `…b089a980…` 4492 청크(Teradata/bge-m3 `53f88357`에서 다시 받음).
- **W-1 재현(수정 전):** Rust 테스트 실패(벡터 1위 문서가 top 5 밖, BM25 일치 없음). 실제 엔진(MiniLM, 1821 청크)에서 세 경우 모두 `prepareAsk` 5개 구절에 환불 문장이 없다. 환불 문장의 BM25 순위는 0(불일치)으로, "refund"와 "Refunds"가 실제로 맞지 않는다. PDF는 IFRS 회계 문서라 질의 토큰 df가 how 25, long 3, is 214, the 1037, period 141, refund 0(1826 청크 중)이다.
- **README 형태 `prepareAsk`(구절 5개 안 환불 문장 위치, 짧은→PDF / PDF→짧은 / 짧은 6개):** none -/-/-, (a) 5% -/-/-, (a) 1% 2/2/2(HNSW 질의가 빠짐), (b) 0.5 -/-/-, (c1) 없는 쪽 순위=후보 수+1 -/-/-, (c2) BM25 몫에 질의 IDF 커버리지를 곱함 5/5/5, (d) 색인·질의 복수형 접기 1/1/1, (e) 하이브리드 질의에서만 단·복수형을 함께 찾음(색인 그대로) 1/1/1.
- **80 질의 default_hybrid `passage_recall@10` (B1: 0.9375 / 0.9625 / 0.975):** none 0.9375 / 0.9625 / 0.975. (e) 0.9375 / **0.950** / 0.975. (c2) 0.9125 / **0.950** / –. (d) 0.925 / **0.950** / –, `bm25_only`도 바뀜(MiniLM 0.900→0.8875). (a) 5%·(c1)은 MiniLM에서 0.9375 그대로지만 README를 못 고친다. (b) 0.925.
- KoEn의 (e) 하락은 질의 하나다: "What are the key concepts and features of Cultural imperialism?" 정답이 10위→밖. "features/concepts"가 "feature/concept"까지 맞아 일반 청크가 올라왔다. (e)는 BGE-m3에서도 `answerable_context@10` 0.9875→0.975, MRR 0.839→0.823으로 내려간다.

**처음 고른 방식과 수치 (2026-11-13, PR #137 첫 판. 아래 재작업으로 대체됨)**
- **고른 것: (e) 질의 쪽 단·복수형 확장.** 하이브리드 검색(두 가중치가 모두 0이 아닐 때)에서만, 질의의 영어 낱말이 색인에 있는 다른 형태도 함께 찾는다. 색인 토큰은 그대로이므로 마이그레이션이 없고, `bm25_only`(벡터 가중치 0)와 `vector_only`는 전과 같다. 문서마다 한 낱말은 한 번만 센다(여러 형태가 있어도 가장 높은 점수 하나).
- **버린 것:** (a) 흔한 단어만 맞은 청크 거르기는 README를 못 고친다(남은 청크가 "how" 25개·"long" 3개로 5개보다 많다). (b) 점수 비율 거르기는 README를 못 고치고 MiniLM 0.925로 내려간다. (c1)은 README를 못 고친다. (c2) IDF 커버리지 곱은 README를 5위로만 올리고 MiniLM 0.9125로 내려간다. (d) 색인까지 복수형을 접으면 README는 1위가 되지만 MiniLM 0.925, `bm25_only`도 0.900→0.8875로 바뀌고 기존 DB의 BM25 토큰이 달라진다.
- **KoEn은 0.9625 → 0.950으로 내려간다.** 2026-11-13 사용자 결정: "0.950을 받아들이고" 한계는 문서에 적는다. 내려가는 질의는 하나다("What are the key concepts and features of Cultural imperialism?", 정답이 10위 → 밖). BGE-m3는 `answerable_context@10` 0.9875→0.975, MRR 0.8388→0.8229이고 `passage_recall@10`은 그대로다.
- **조건(규칙 9):** 엔진 `9f88185` + 이 브랜치의 최종 코드, 로컬 Mac(macOS 27.2, Xcode 27.1, Flutter 3.35.5, rustc 1.91.1, 2026-11-13). README 형태는 debug(`short_document_recall_test.dart`, MiniLM 1,821~1,826 청크), 80 질의는 profile(B1과 같은 하네스·평가셋, `--dart-define=HYBRID_PASSAGE_REUSE_EXISTING_INDEX=true`로 수정 전에 만든 색인을 다시 열어 검색만 새 코드로 했다).

| 80 질의, default_hybrid | MiniLM (4,667 청크, `…e9246dc3…`) | KoEn-E5-Tiny (4,492, `…fd688b15…`) | BGE-m3 (4,492, `…b089a980…`) |
|---|---|---|---|
| `passage_recall@10` 전 → 후 | 0.9375 → **0.9375** | 0.9625 → **0.950** | 0.975 → **0.975** |
| `answerable_context@10` | 0.9125 → 0.900 | 0.975 → 0.9625 | 0.9875 → 0.975 |
| `passage_mrr@10` | 0.7633 → 0.7414 | 0.8169 → 0.8086 | 0.8388 → 0.8229 |
| 언어별(ko/en/other, 후) | 29/32, 30/32, 16/16 | 31/32, 29/32, 16/16 | 32/32, 30/32, 16/16 |
| `vector_only` | 0.65 → 0.65 | 0.95 → 0.95 | 0.975 → 0.975 |
| `bm25_only` | 0.90 → 0.90 | 0.925 → 0.925 | 0.925 → 0.925 |

- **README 형태(구절 5개 안 환불 문장 위치):** 짧은→PDF 1위, PDF→짧은 1위, 짧은 6개 1위. 짧은 문서 6개 모두 1위다(전에는 환불 문장이 세 경우 모두 없었다). 환불 문장의 BM25 순위는 0(불일치) → 2위가 됐다.
- **남는 한계(측정):** 같은 묶음에서 "How many days do I have to return an item?"(공통 낱말은 "days" 하나, 벡터 50위 안에 없음)는 기본 가중치에서 두 번째 구절, 0.5/0.5에서 첫 구절이다. 짧은 문서만 담은 컬렉션(`inCollection('faq')`)에서는 두 질문 모두 첫 구절이다. 낱말이 하나도 겹치지 않는 질문은 여전히 빠질 수 있다(측정하지 않았다). 이 세 가지를 `docs/guides/ask.md`의 "Short documents next to a large one"과 FAQ에 적었다.
- **검색 시간:** 질의 쪽 확장은 색인에 있는 형태만 더 찾으므로 질의 낱말 수에 비례한다. Rust 벤치(release, 5,000 문서, 질의 7낱말, `cargo test --release --lib bm25_expand_search_benchmark -- --ignored`): 462µs → 1.03ms. 앱 수준 `searchHybrid` 중위수(profile, 80 질의 × 5 프로필)는 수정 전 1.8~2.6ms, 후 1.75~2.7ms로 실행 간 변동 안이다(BM25와 벡터 검색을 동시에 돌리고 벡터 쪽이 더 오래 걸린다).
- **업그레이드 경로(실측):** pub `mobile_rag_engine` 0.23.0 + `rag_engine_flutter` 0.22.0(경로 override 없이 배포본)으로 환불 문장 + PDF를 색인해 DB를 만들었다(1,821 청크, `.hnsw`는 형식 v1). 같은 DB를 이 브랜치로 열었더니 source 2개·청크 1,821개가 그대로 읽히고, 첫 검색이 되고(`vectorRank=0`), 기본 가중치 하이브리드에서도 1위다. `.hnsw`는 v1 → v2로 한 번 다시 만들어진다(S1에서 이미 들어간 동작). BM25 인덱스는 활성화 때 DB 내용에서 메모리로 다시 만들므로 단·복수형 확장이 바로 적용된다. 저장되는 데이터는 바뀌지 않아 마이그레이션이 없다. 참고로 0.23.0 쪽에서는 같은 질문에 환불 문장이 어떤 프로필에서도 나오지 않는다(S1 버그, `vectorRank=-1`).

**재작업 결과: (S1) 표준 어간 처리로 간다 (2026-11-13)**
- **결정:** 2026-11-13 사용자 "W1은 표준 방식으로 진행". (S1)과 (S2) 모두 README 예제는 고치지만 default_hybrid가 MiniLM·BGE-m3에서 PR #137 첫 판보다 질의 하나씩 낮다. **2026-11-13 사용자 합의:** MiniLM 0.9375 → 0.925, BGE-m3 0.975 → 0.9625, `bm25_only` MiniLM 0.900 → 0.8875 하락을 받아들인다. (S2) 코드는 넣지 않는다.
- **바뀐 코드:** `tokenize_for_bm25`가 ASCII 영문자로만 된 토큰을 Snowball English(`rust-stemmers` 1.2.0, MIT/BSD-3-Clause)로 어간 처리한다. 색인과 질의가 같은 함수를 지나므로 모든 BM25 경로(키워드 전용 포함)에 적용된다. 한글·CJK·악센트 문자·`iphone15` 같은 섞인 토큰과 Hangul bigram은 그대로다. PR #137 첫 판의 `plural_forms`, `query_groups`, 형태별 최댓값 점수, `expand_plurals` 스위치는 지웠다.
- **재현 테스트:** `not`/`notes`, `car`/`cares`, `plan`/`planes`, `new`/`news`가 서로 맞지 않는 테스트와 "Refunds"·"Refund"가 같은 점수를 받는 IDF 테스트. 둘 다 PR #137 첫 판 코드에서 실패했다(IDF 테스트: 4.25 대 0.78).
- **떨어진 질의:** 세 모델 모두 평가셋의 같은 틀 문장 "What are the key concepts and features of X?"이다(MiniLM: Dividend policy 6위→밖, BGE-m3·KoEn: Cultural imperialism 밖. Government는 세 모델 모두 1~2위 → 8~9위). "concepts/features"의 어간이 일반 청크의 "concept/feature…"와 맞는다. (S1)과 (S2)는 질의별 순위까지 같았다.
- **이 평가셋의 한계:** 영어 질의 32개 중 8개가 같은 틀 문장이라 틀 낱말 하나의 변화가 여러 질의에 함께 나타난다. 질문과 정답 구절이 통째 낱말을 하나도 공유하지 않는 질의는 영어 0개, 한국어 2개(둘 다 틀 문장 "…의 핵심 개념과 주요 특징을 설명해줘")뿐이라, 근본 원인(낱말이 안 겹치는 짧은 문서)은 이 평가셋으로 잴 수 없다(후보 목록).
- **조건(규칙 9):** 엔진 `529e5ea` + 이 재작업, 로컬 Mac(macOS 27.2, Xcode 27.1, Flutter 3.35.5, rustc 1.91.1, 2026-11-13, 다른 측정과 겹치지 않게 차례로 실행). 80 질의는 profile, README 형태는 debug(MiniLM, 1,821~1,826 청크). 80 질의는 수정 전에 만든 색인을 다시 열었다(`HYBRID_PASSAGE_REUSE_EXISTING_INDEX=true`). BM25 색인은 활성화 때 DB에서 메모리로 다시 만들어지므로(로그 "Building index from 4667 chunks") 어간 토큰이 적용된다. 같은 환경에서 수정 전 코드의 MiniLM이 B1 값과 정확히 같았다.

| 80 질의 default_hybrid (recall@10 / answerable@10 / MRR@10) | MiniLM (4,667 청크, `…e9246dc3…`) | KoEn-E5-Tiny (4,492, `…fd688b15…`) | BGE-m3 (4,492, `…b089a980…`) |
|---|---|---|---|
| B1 (수정 전) | 0.9375 / 0.9125 / 0.7633 | 0.9625 / 0.975 / 0.8169 | 0.975 / 0.9875 / 0.8388 |
| PR #137 첫 판 (손으로 짠 복수형) | 0.9375 / 0.900 / 0.7414 | 0.950 / 0.9625 / 0.8086 | 0.975 / 0.975 / 0.8229 |
| **(S1) 최종** | **0.925** / 0.900 / 0.7450 | **0.950** / 0.9625 / 0.8168 | **0.9625** / 0.9625 / 0.8211 |
| (S2) 질의 쪽 어간 묶음 | (S1)과 같음 | (S1)과 같음 | (S1)과 같음 |
| 언어별 (S1, ko/en/other) | 29/32, 29/32, 16/16 | 31/32, 29/32, 16/16 | 32/32, 29/32, 16/16 |
| `bm25_only` recall (S1) | 0.900 → 0.8875 | 0.925 → 0.925 | 0.925 → 0.925 |
| `bm25_only` recall (S2) | 그대로 | 그대로 | 그대로 |
| `vector_only` recall | 그대로 0.65 | 그대로 0.95 | 그대로 0.975 |

- **README 형태(구절 5개 안 환불 문장 위치):** (S1)·(S2) 모두 짧은→PDF 1위, PDF→짧은 1위, 짧은 6개 1위. 짧은 문서 6개 모두 자기 질문에서 1위.
- **시간(release, 문서 20,000개, `bm25_build_benchmark`/`bm25_search_benchmark`):** 영어 색인 빌드 290~317ms → 536~542ms(어간 처리 비용), 한국어 색인 빌드 328~359ms로 그대로. BM25 한 번(7낱말, top 40) 2.0~2.1ms로 그대로. 앱의 `searchHybrid` 중위수(80 질의 × 5 프로필)는 1.67~2.54ms로 수정 전(1.69~2.18ms, MiniLM)과 실행 간 변동 안이다. (S2)는 빌드는 그대로, BM25 한 번이 약 30% 느렸다.

**착수 전에 정한 것 (2026-11-13, 초안대로)**
1. W-4(인용 괄호, 문서 변경)는 이 PR에 함께 넣는다.
2. 80 질의 수치가 세 모델 중 하나라도 B1 값보다 떨어지면 PR을 열기 전에 수치를 보이고 묻는다.

### F1. 검색 평가 기반 (기존 자료 판정, 사람이 쓴 질의, `ask` 조건 측정)

- **담당:** 세션 "F1 검색 평가 기반", 브랜치 `claude/f1-eval-baseline-154010`
- **상태:** 착수 (2026-11-13 사용자 "새 세션에서 F1 착수"). F-0 판정을 마쳤고 갈래 (2)와 "착수 전에 정할 것"을 2026-11-13에 확정했다(사용자 "그대로 확정하고 F-3부터 시작해줘"). 진행 순서는 F-3 → F-2 → 나머지다. 초안은 사용자 "F1 마일스톤 초안 써줘"로 적었고, 같은 날 "F1 초안도 고쳐줘"로 결합 방식 준비에서 평가 기반으로 범위를 바꿨다.
- **출처:** 2026-11-13 사용자 "이 패키지를 배포하고 지금까지 제대로 된 평가셋을 가져보지 못한게 제일 크다". 후보 목록의 "[중간] 낱말이 겹치지 않는 짧은 문서는 RRF에서 여전히 밀린다"(W1), 2026-11-13 결합 방식 리서치.
- **순서 (2026-11-13 합의):** W1(#137) 머지 뒤, Q2~Q5보다 먼저 한다. 사용자: "저 문서 301개가 평가셋으로서의 가치가 있는지는 모르겠지만 일단 F1은 Q2~Q5보다 먼저 하자". main에서 브랜치를 딴다. 엔진 코드를 고치지 않으므로 Q2~Q5와 엔진 파일이 겹치지 않는다.
  - 먼저 하는 이유: 이후의 검색 판단(결합 방식, 기본 가중치, 한국어 프리셋, 어간 처리)이 모두 이 평가에 기댄다. 자료가 지금 Mac 한 대에만 있다.

**배경**
- **지금까지의 판단이 기댄 평가셋은 틀 문장 80개다.** 결합 방식, 기본 가중치, 한국어 모델 권장, W1의 어간 처리 판단이 모두 `hybrid_passage_gold_80_balanced_v1.jsonl`의 수치로 내려졌다. 2026-11-13 집계:
  - 질의와 정답 구절이 낱말을 하나도 공유하지 않는 것은 0개다(질의 토큰 중 정답 구절에 있는 비율: 중앙값 0.54, 최소 0.07. 엔진의 BM25 토큰화를 흉내 낸 스크립트로 셌다). 질의가 대부분 문서 제목을 포함한다.
  - "짧은 문서 + 큰 문서" 형태가 없다(위키 문서 80개, 622~71,225자).
  - 하네스는 `search_top_k` 100(후보 400개씩)으로 잰다. 파사드는 항상 컬렉션 필터를 넘겨 후보가 목록마다 `topK × 4`개이므로, `ask`(topK 5)는 20개씩만 본다. 후보 수가 결합 결과를 바꾸므로 README의 수치는 `ask`의 실제 품질을 잰 값이 아니다.
  - W1에서 수치가 떨어진 질의는 틀 문장("What are the key concepts and features of X?")이었다(W1 측정 절).
- **자료는 남아 있지만 저장소 밖에 있다 (2026-11-13, 메인 체크아웃을 읽어 확인).**
  - `example/assets/corpus/`: 위키 문서 300개(`.md`, en 105, ko 195, 4.3 MB).
  - `example/assets/evalsets/wiki_article_sources_manifest_v1.json`: 300개. 문서마다 `url`, `revision_id`, `domain`, `length_bucket`, `char_length`가 있다(전체 약 291만 자, short 100 / medium 101 / long 99).
  - `wiki_article_evalset_seed_v1.jsonl` 800줄(ko 539, en 261, 문서 277개를 가리킴)과 구절 정답 400줄(`templates/wiki_article_chunk_gold_seed_v1.jsonl`). 지금 쓰는 80개는 여기서 고른 부분집합을 넓힌 것이다.
  - `scripts/generate_evalset_seed.py`, `generate_p5_4_expanded_evalset.py`, `validate_evalset_bundle.py`, 측정 하네스(`example/integration_test/hybrid_passage_relevance_measure_test.dart`, `example/lib/profiling/relevance_*.dart`), `artifacts/wiki_*`의 2월 실행 기록.
  - 모두 `.gitignore` 대상이라 이 Mac에만 있다. 외장 백업(`mobile_rag_engine_work_trees`, 워크트리 26개)에서는 깊이 5까지 `corpus`·`evalsets`·`.sqlite`를 찾지 못했다. 사용자가 말한 위키 3만 청크 규모의 DB도 찾지 못했다.
- **800 질의는 전부 기계가 만들었다 (스크립트와 파일을 읽어 확인).**
  - `generate_evalset_seed.py`(seed 42)의 머리말이 "Manual review is still required before gate runs"라고 적고 있고, 검수 기록은 없다.
  - 종류: positive 440, hard_negative 200, paraphrase 80, noise 80.
  - positive는 절반이 틀 문장("X의 핵심 개념과 주요 특징을 설명해줘", "What are the key concepts and features of X?")이고 절반이 문서 문장을 그대로 120자까지 자른 것이다. paraphrase는 바꿔 말한 것이 아니라 틀 문장("X 문서의 핵심 내용을 한 문단으로 요약해줘")이다. hard_negative는 질의 뒤에 다른 문서 제목을 붙였고, noise는 모음과 공백을 뺀 문자열이다.
  - 문서 제목이 들어간 질의는 572/800이다(URL의 제목으로 셌다). 나머지 positive는 문서 문장 그대로라 낱말이 전부 겹친다.
  - 구절 정답은 문서마다 하나(`#seed-001`)를 스크립트가 고른 것이다.
- **기존 자료가 평가셋으로 값어치가 있는지는 아직 모른다 (2026-11-13 사용자).** 위 집계는 틀 문장과 기계 생성 정답이라는 약점을 보여 주지만, 800개 전체를 세 모델로 돌려 본 적도, 정답을 사람이 읽어 본 적도 없다. 그래서 "살린다"를 전제로 두지 않고, F1의 첫 단계에서 판정한다.

**목표:** 기존 평가 자료가 쓸 만한지 먼저 판정하고, 그 결과에 맞춰 검색 품질을 판단할 평가 자료와 실행 절차를 누구나(다른 Mac, 다른 세션) 다시 돌릴 수 있게 남긴다. 사람이 쓴 질의와 `ask` 조건의 측정을 더해, 이후의 검색 변경이 기댈 기준선을 만든다.

**포함**
- **F-0. 기존 자료의 값어치를 판정한다 (첫 단계).** 위키 문서 300개와 800 질의를 아래 기준으로 따지고, 결과와 갈래를 이 절에 적은 뒤 사용자에게 보이고 다음 단계로 간다(규칙 4).
  - **질의의 모양:** 틀 문장 비율, 제목을 포함하는 비율, 낱말이 겹치지 않는 질의 수. 2026-11-13에 센 값(제목 포함 572/800, positive의 절반이 틀 문장이고 절반이 문서 문장 그대로)을 800개 전체에 대해 엔진의 BM25 토큰화 기준으로 다시 세어 확정한다.
  - **정답 라벨:** 구절 정답은 스크립트가 문서마다 하나 고른 것이다. 표본 40개(영어 20, 한국어 20)를 사람이 읽어, 정답 구절이 그 질의의 답으로 맞는 비율을 센다.
  - **대표성:** 문서 종류가 위키 하나뿐이다. 실제 앱 문서(FAQ, 매뉴얼 PDF, 메모, 한국어 업무 문서)와 길이·문체·구조가 얼마나 다른지 적는다. 수치로 잴 수 없는 항목이라 차이를 글로 적고, 새 묶음이 메워야 할 것을 뽑는다.
  - **변별력:** 800개 전체를 세 모델로 한 번 돌려, 80개로 이미 본 것 말고 새로 알려 주는 것이 있는지 본다. 모델·프로필 사이의 차이가 80개 때보다 뚜렷해지는지, 질의 종류별로 천장(거의 전부 적중)이나 바닥에 붙는지를 본다.
  - **갈래 (판정 결과에 따라 하나를 고른다):**
    - (1) 쓸 만하다: 정리해서 기반으로 삼는다. F-1에서 전부 보관하고, 새 묶음(F-2)은 빈 곳을 메우는 보조로 둔다.
    - (2) 회귀 확인용으로만 쓸 만하다: 80개 묶음과 그 문서만 보관하고, 새 묶음을 주력으로 한다. 800개와 나머지 문서는 보관 여부를 따로 정한다.
    - (3) 값어치가 없다: 보관하지 않고 새로 만든다. 지금까지의 수치(B1, W1)가 이 자료로 잰 값이므로, 재현에 필요한 최소한(80개 묶음)을 남길지는 사용자가 정한다.
  - **갈래를 가르는 선(초안, 착수 때 사용자와 확정한다):** 정답 표본이 맞는 비율이 90% 이상이고 변별력이 있으면 (1). 정답은 맞지만 천장에 붙거나 틀 문장뿐이라 변별력이 없으면 (2). 정답 표본이 맞는 비율이 80% 아래면 (3).
  - **F-0 결과 (2026-11-13, 상세는 `docs/perf/f1-eval-baseline/f0_report.md`, 표본 표는 `f0_label_sample.md`).** 엔진 `76e27d2`, profile, M3 Pro / macOS 27.2.1 / Xcode 27.1 / Flutter 3.35.5 / rustc 1.91.1, 문서 300개, MiniLM(`sha256:e9246dc3…`, 13,941 청크)과 KoEn-E5-Tiny(`sha256:fd688b15…`, 13,218 청크). BGE-m3는 사용자가 취소했다.
    - 질의 모양: 800개 중 문서 문장 그대로 복사 437(1번째 문장 209, 3번째 228), 틀 문장 283, noise 80. 제목 포함 561. 정답 문서와 낱말이 하나도 안 겹치는 질의는 noise를 빼면 2개다. 한국어 noise 51개는 공백만 뺀 원문이라 noise가 아니다.
    - 정답 라벨: 표본 40개 중 맞음 22(55%), 애매 8, 틀림 10. 세션 판독이고 사람 검수가 아니다. 틀림은 전부 "3번째 문장 그대로" 질의다(스크립트가 질의와 관계없이 첫 문장을 정답으로 정한다). 실행에서도 이 모양에서 놓친 경우의 84%(MiniLM 48/57, KoEn 47/56)는 질의 문장 청크가 상위 10개에 있었다.
    - 대표성: 위키 정의문 하나뿐이고, 300자 아래 문서, 제목 구조, FAQ·매뉴얼 문체, 바꿔 말한 질문, 답 없는 질문이 없다.
    - 변별력: 문장 복사 질의는 천장(0.99)이거나 라벨 결함이고, noise는 의미가 없다. 80개로 본 결론(MiniLM 한국어 벡터 약점, 다국어 모델은 벡터 비중을 올릴수록 좋아짐)을 되풀이할 뿐이고, 새 정보는 틀 문장 283개에서 KoEn의 가중치 효과가 더 크다는 것 하나다.
    - 80개 묶음은 질의를 정답 구절의 낱말로 다시 만들어 라벨 결함이 없다. 대신 낱말이 겹치는 질의만 잰다.
    - **결정: 갈래 (2) (2026-11-13 사용자 확정).** 초안의 선으로는 (3)이다(표본 맞음 55% < 80%). 사용자 판단으로 (2)를 골랐다. 이유: 틀린 라벨이 전부 한 가지 질의 모양("3번째 문장 그대로")에 몰려 있어 스크립트로 가려낼 수 있고, 80개 묶음에는 그 결함이 없으며, 80개 묶음이 B1·W1 수치를 다시 낼 수 있는 유일한 자료다. 선은 결과를 본 뒤 고치지 않고 초안 그대로 기록한다. 다음 평가셋 판정 때는 질의 모양별로 보는 것을 참고한다.
    - **80개 묶음의 호칭:** 앞으로 README, PR, 보고서에서 품질 수치로 인용하지 않고 "회귀 확인용"으로만 부른다. 질의 64개가 정답 구절의 앞 낱말 8개를 나열한 것이기 때문이다.
    - 표본 40개 판정은 세션이 읽은 것이다. 사용자가 훑어보기 전까지 "사람 검수 전"으로 둔다.
- **F-1. 판정에서 남기기로 한 것을 보관한다.** F-0의 갈래에 따라 범위가 달라진다. 갈래 (1)은 코퍼스 300개, 매니페스트, 800 질의와 80 질의 묶음 전부, (2)는 80개 묶음과 그 문서다. 생성·검증 스크립트와 측정 하네스는 갈래와 관계없이 보관한다(새 묶음도 같은 하네스로 잰다).
  - 선택지:
    - (가) 이 저장소 안. `.pubignore`가 이미 `example/assets/`, `docs/`, `scripts/`를 빼므로 pub.dev 패키지에는 딸려 나가지 않는다(착수 때 `flutter pub publish --dry-run` 목록으로 확인한다). 저장소가 약 6 MB 늘어난다.
    - (나) 별도 저장소. 라이선스와 크기가 분리되지만 받아오는 단계와 버전 맞추기가 생긴다.
    - (다) 매니페스트와 받아오는 스크립트만 저장소에 둔다. `revision_id`가 있어 같은 판을 받을 수는 있지만, 받아서 `.md`로 바꾸는 스크립트가 남아 있지 않아 새로 써야 하고, 본문이 한 글자라도 달라지면 정답 구절 위치가 어긋난다.
  - **권고: (가).** 한 저장소에서 한 명령으로 돌고, 정답과 본문이 함께 버전 관리된다. 6 MB는 감당할 크기다.
  - 위키 문서는 CC BY-SA다. 코퍼스 디렉터리에 출처 표기 파일(문서별 URL과 `revision_id`는 매니페스트에 있다)과 라이선스 안내를 두고, 저장소의 코드 라이선스(MIT)와 다르다는 것을 README에 한 줄 적는다.
  - 기계 생성 묶음이라는 사실과 위 집계(종류, 틀, 제목 포함 비율)를 자료 옆 README에 적어, 수치를 읽는 사람이 무엇을 잰 것인지 알게 한다.
  - **결과 (2026-11-13).** 갈래 (2)와 결정 1에 따라 보관했다.
    - 넣은 것: 위키 문서 300개(`example/assets/corpus/{en,ko}/`, 4.3 MB, main 체크아웃과 같은 파일), `wiki_article_sources_manifest_v1.json`, 80개 묶음 세 파일, `templates/`의 스키마와 예시, 생성·검증 스크립트 세 개, 하네스(`hybrid_passage_relevance_measure_test.dart`, `relevance_{evalset,metrics}.dart`)와 그 단위 테스트 둘.
    - 넣지 않은 것: 800개 질의, 400행 정답, `templates/`의 그 사본과 `sources_manifest.json` 사본, 20개 묶음, `_runtime_abs` 매니페스트. 80개 묶음은 800·400을 seed 42로 다시 만든 뒤 `generate_p5_4_expanded_evalset.py`를 돌리면 바이트 단위로 같게 나온다(2026-11-13 확인). 명령은 `example/assets/evalsets/README.md`.
    - 라이선스: `example/assets/corpus/README.md`에 CC BY-SA 4.0 고지, 출처(매니페스트의 URL과 `revision_id`), 바꾼 내용을 적었다. 루트 README의 License 절에 한 줄 더했다. `f1_short/`는 세션이 쓴 문서라 MIT다.
    - 예제 앱: 커밋된 `example/pubspec.yaml`로 `flutter build bundle`을 돌리면 자산이 0개다. `assets/`의 하위 폴더는 묶이지 않는다.
    - pub: `flutter pub publish --dry-run` 목록에 평가 자료, 스크립트, 하네스가 없다. 테스트 전용 `rust_builder/rust/src/api/eval_dump.rs`(1 KB, `#[cfg(test)]`)만 Rust 소스와 함께 들어간다.
    - 하네스 정리: W1 실험용 `W1_VARIANT`를 지우고, 모델 인자를 `EVAL_MODEL_ASSET`/`EVAL_TOKENIZER_ASSET`, 요약 줄을 `PASSAGE_SUMMARY`로 바꿨다. 단위 테스트의 20개 묶음 검사는 80개 묶음과 `f1/` 묶음 검사로 바꿨다.
- **F-2. 없는 것을 만든다.** 사람이 쓴 질의 30~40개와 정답을 영어·한국어로 만든다.
  - 큰 문서 옆에 넣는 짧은 문서 10~20개와 그 질의
  - 낱말이 겹치지 않는 바꿔 말한 질문 15~20개
  - 일부만 겹치는 질문 약 10개
  - 답이 없는 질문 약 10개
  - 정답 구절은 사람이 고르고, 겹침 여부는 엔진의 BM25 토큰화 기준으로 스크립트가 세어 함께 적는다.
  - **1단계 (2026-11-13 사용자 "세션 초안으로 F-2 진행해줘").** 사용자가 직접 쓰는 질의 몫은 두지 않고 세션 초안으로 간다. 작성자 필드는 `session_draft`로 두고, 사용자 검수를 거친 질의만 `session_draft+human_review`로 바꾼다. 보고서에 "사람이 쓴 질의"라고 적지 않는다.
    - 문서: 세션이 직접 쓴 짧은 문서 16개(영어 8, 한국어 8, FAQ·메모·매뉴얼·규정 문체, 1,500자 이하)를 80개 묶음의 위키 문서(622~71,225자) 옆에 넣는다. 세션이 쓴 문서라 외부 라이선스가 없다.
    - 질의 40개(영어 20, 한국어 20): 정답 구절과 BM25 토큰이 하나도 겹치지 않는 바꿔 말한 질문 14, 일부만 겹치는 질문 10, 낱말이 많이 겹치는 대조군 8, 답이 없는 질문 8. 답이 있는 32개 중 16개는 짧은 문서, 16개는 위키 문서를 가리킨다.
    - 겹침은 엔진의 `tokenize_for_bm25`를 그대로 옮긴 프로그램으로 세고, 유형은 그 값으로 확인한다.
    - 답이 없는 질문은 정답 지표에서 빼고, `ask` 조건의 상위 결과와 점수만 기록한다(점수 기준값을 정하는 것은 F1 범위 밖).
    - 사용자가 40개를 검수한 뒤 겹침 분포를 보고 늘린다.
    - **1단계 결과 (2026-11-13, `docs/perf/f1-eval-baseline/f2_stage1.md`, 검수표 `f2_review_sheet.md`).** 사람 검수 전이다. 문서 96개(위키 80 + 짧은 문서 16), 엔진 코드는 `28308ab`와 같고 테스트 전용 `eval_dump.rs`만 더했다. profile, M3 Pro / macOS 27.2.1 / Xcode 27.1 / Flutter 3.35.5 / rustc 1.91.1. default_hybrid의 `ask@5`는 MiniLM(`sha256:e9246dc3…`, 4718 청크) 0.531, KoEn-E5-Tiny(`sha256:fd688b15…`, 4543 청크) 0.594, BGE-m3(`sha256:b089a980…`, 4543 청크) 0.594다(80개 묶음 0.900~0.9125). 낱말이 안 겹치는 14개에서 KoEn과 BGE-m3의 vector_only는 11개와 12개를 찾는데, default_hybrid는 둘 다 4개만 남긴다. 답 없는 질문은 1위 RRF 점수로 가를 수 없다.
  - **F-0이 갈래 (2)나 (3)이면 규모를 키운다.** 새 묶음이 주력이 되므로 문서와 질의를 더 만든다. 문서 묶음의 후보는 공개 라이선스의 매뉴얼·FAQ류(라이선스와 출처 표기를 문서마다 확인한다), 직접 쓴 짧은 문서(FAQ, 메모, 한국어 업무 문서 형태), 큰 문서 역할의 PDF 한두 개(`sample_eng.pdf`와 한국어 문서)다. 규모의 초안은 문서 30~60개에 질의 100~150개(영어·한국어 절반씩)이고, 한 번에 다 쓰지 않고 유형별 최소 개수를 먼저 채운다. 확정은 판정 결과를 본 뒤 한다.
- **F-3. `ask` 조건 프로필 (F-2보다 먼저 한다, 2026-11-13 확정).** 80개 묶음만으로 잴 수 있어 새 질의 검수를 기다리지 않는다. `ask`는 `searchMetaHybrid`를 topK 5로 부르고(파사드가 늘 컬렉션 필터를 넘겨 목록마다 후보 20개), 그 결과를 토큰 예산 1500, `relevanceFirst`, 구분자 `\n\n---\n\n`으로 조립한다(코드 확인 2026-11-13). topK 5와 그때의 실제 후보 수로 재는 프로필과 `passage_recall@5`를 하네스에 더한다. **첫 결과물:** 세 모델에서 지금 README의 수치(topK 100 조건의 `@10`)와 `ask` 조건의 `@5`가 얼마나 다른지 보여 주는 표.
  - **결과 (2026-11-13, `docs/perf/f1-eval-baseline/f3_ask_condition.md`).** 80개 묶음(회귀 확인용), 엔진 `c3aa1a1`(코드는 `28308ab`), profile, M3 Pro / macOS 27.2.1 / Xcode 27.1 / Flutter 3.35.5 / rustc 1.91.1. default_hybrid의 `ask@5`는 MiniLM(`sha256:e9246dc3…`, 4667 청크) 0.900, KoEn-E5-Tiny(`sha256:fd688b15…`, 4492 청크) 0.900, BGE-m3(`sha256:b089a980…`, 4492 청크) 0.9125다. README(B1, W1 전 `@10`) 0.9375 / 0.9625 / 0.975보다 0.0375~0.0625 낮다. 차이는 주로 `@10` → `@5`에서 오고, 문맥 조립(토큰 예산 1500)에서 빠진 정답은 없었다. 놓친 질의는 세 모델 모두 틀 문장(semantic)에 몰려 있다. 후보 수(20 대 400)는 질의마다 순위를 양쪽으로 바꾼다. MiniLM 0.6/0.4에서는 0.7625 → 0.6125로 크게 떨어진다.
- **F-4. 한 명령 실행.** 모델 하나와 묶음 하나를 받아 색인하고 평가까지 도는 스크립트를 둔다. Xcode 27 profile 빌드 우회(링커 래퍼, arm64)를 스크립트 안에 넣는다. 모델 파일은 저장소에 넣지 않고 경로나 Model Pack id로 받는다.
- **F-5. 실행 기록 자동화 (규칙 9).** 모든 실행의 결과 파일에 모델 이름과 fingerprint, 엔진 커밋, 빌드 모드와 Rust feature, 기기와 도구 버전, 묶음 이름, 청크 수, 실행 시각이 자동으로 들어가게 한다. 지금은 B1 때 사람이 요약에 적어 넣었다.
  - **F-4·F-5 결과 (2026-11-13).** `scripts/eval/run_passage_eval.sh`(한 명령)와 `scripts/eval/collect_eval_run.py`(실행 기록). 모델은 `--model 디렉터리` 또는 `--model-pack 프리셋`으로 받는다. 추적 중인 파일은 고치지 않고 `example/`을 `build/eval_app/`에 복사해 그 사본에만 자산 선언과 Xcode 27 우회 세 가지를 넣는다. 결과 디렉터리의 `run_meta.json`과 결과 JSON의 `run_meta`에 규칙 9 항목이 자동으로 들어간다. 새로 클론한 저장소(`32ced9f`)에서 MiniLM 80개 묶음 default_hybrid가 0.925 / 0.900 / 0.7450(청크 4667)으로 재현됐다. 사용법과 기록은 `docs/perf/f1-eval-baseline/README.md`.
- **F-6. 큰 묶음 프로필 — F1에서 뺀다 (2026-11-13 확정).** 800 질의가 결함 있는 자료라 수치를 해석하기 어렵다. 규모 수치는 F-0에서 하나 얻었다(문서 300개, MiniLM 13,941 청크, 675초). 새 질의가 생기면 후보로 다시 적는다. 아래는 원래 초안이다. 문서 300개 전체를 색인하는 프로필. 글자 수 비율로 추정하면 약 1.4만 청크다(80개 묶음이 4,492~4,667 청크). 기기 규모의 상한에서 품질과 시간이 어떤지의 근거가 된다. BGE-m3는 80개에 1,050초가 걸렸으므로 큰 묶음은 작은 두 모델로만 잰다.
- **F-7. 오프라인 비교 도구 (평가 기반의 첫 사용처).** 질의마다 벡터 상위 N개(코사인)와 BM25 상위 N개(점수)를 덤프하고, 덤프만으로 결합 방식을 모의 비교하는 스크립트를 둔다. 엔진의 실제 `default_hybrid` 결과와 질의별 순위가 같은지로 스크립트를 검증한다. 처음 비교할 것은 2026-11-13 리서치의 후보다: 가중치만 조정, 목록 안 정규화 뒤 선형 결합, 벡터 1위 자리 보장, 뚜렷할 때만 자리 보장. 이 비교는 F1의 목적이 아니라 평가 기반이 쓸 만한지 확인하는 첫 사용이다.
  - **결과 (2026-11-13, `docs/perf/f1-eval-baseline/f7_fusion_compare.md`).** 결정 4대로 엔진 함수를 그대로 불렀다. 다만 Rust 테스트가 아니라 하네스(example)에서 FRB로 노출된 `searchHnswSlice`/`bm25Search`를 부르는 쪽이 같은 함수를 더 간단히 부를 수 있어 그쪽으로 했다. Rust는 바꾸지 않았다. 덤프는 `run_passage_eval.sh --dump-candidates`, 비교는 `scripts/eval/f7_fusion_compare.py`. 세 모델 × 두 묶음 × 다섯 가중치 × 두 조건(후보 20/400)의 3,360건에서 질의별 정답 순위가 엔진과 모두 같다. 구조적 사실: `ask` 조건(후보 20)에서 벡터 가중치가 61/141(≈0.433) 이하이면 벡터에만 있는 청크는 BM25 단독 청크를 넘지 못한다(기본값 0.2). 여섯 실행 모두에서 기본값보다 나빠지지 않은 방식은 "벡터 1위 자리 보장"과 "정규화 선형 0.5"였다. 비교일 뿐 기본값의 근거가 아니다(F2에서 다룬다).
- **F-8. 보고서.** `docs/perf/`에 기준선(세 모델 × 기존 80 질의, 사람이 쓴 묶음, `ask` 조건)과 F-7의 비교 결과를 적는다. 결합 변경을 할지(F2)는 이 보고서를 보고 따로 정한다.

**제외**
- 엔진의 검색 동작 변경과 기본값 변경(결합 방식, 가중치, 후보 수). F2 이후로 따로 적는다.
- 리랭커, e5 계열 `query:`/`passage:` 접두어, 언어별 처리.
- CI에서 PR마다 평가를 도는 일. 모델 파일이 필요해 무겁다. 수동으로 둘지 주간 실행으로 둘지는 후보 목록에 적는다.
- 800 질의를 사람이 전부 검수하는 일. F-0에서 표본만 읽는다.
- README와 문서의 품질 수치 변경. F-3의 표를 본 뒤 따로 정한다.
- 버전 변경과 배포.

**완료 기준**
- F-0의 네 기준별 결과(수치와 표본 판독 기록)와 고른 갈래, 그 이유가 이 절과 보고서에 있다.
- 새로 클론한 저장소(또는 정한 보관 위치)에서 문서의 한 명령으로 평가가 돈다. 80개 묶음을 보관한 경우 MiniLM의 `default_hybrid` 값(W1 머지 뒤의 기준값)이 재현된다.
- 결과 파일에 F-5의 항목이 사람 손을 거치지 않고 들어 있다.
- 사람이 쓴 묶음의 질의 유형별 개수, 언어별 개수, 낱말 겹침 집계가 자료 옆 README에 있다.
- 세 모델의 `ask` 조건 `passage_recall@5`가 보고서에 있고, README 수치와의 차이가 표로 있다.
- F-7의 기준 방식이 엔진 결과와 질의별 정답 순위까지 같다.
- 코퍼스의 출처·라이선스 표기가 있고, `flutter pub publish --dry-run` 목록에 평가 자료가 없다.
- 규칙 8의 네 항목. 엔진을 고치지 않으므로 업그레이드 경로는 "Not applicable."과 이유를 적는다. PR 하나, CI 통과.

**손대는 파일 ((가)를 고른 경우. 코퍼스와 평가셋의 범위는 F-0의 갈래에 따른다):** `.gitignore`, `.pubignore`(확인만, 필요하면 한 줄), `example/assets/corpus/**`, `example/assets/evalsets/**`, `example/integration_test/hybrid_passage_relevance_measure_test.dart`, `example/lib/profiling/relevance_*.dart`, `scripts/{generate_evalset_seed,generate_p5_4_expanded_evalset,validate_evalset_bundle}.py`, 새 실행 스크립트(위치는 착수 때 정한다), 새 디렉터리 `docs/perf/`(보고서), `docs/milestones.md`, F-7 덤프용 Rust 테스트(`rust_builder/rust/src/api/` 안의 `#[cfg(test)]` 코드 또는 `rust_builder/rust/tests/`, 2026-11-13 추가. 테스트 코드만 더하므로 배포 바이너리와 공개 API는 바뀌지 않는다)

**착수 전에 정할 것 — 결정 (2026-11-13, 사용자 "그대로 확정하고 F-3부터 시작해줘". 검토 세션 "결합 방식 수정 리스크·현실성 리서치"의 의견을 반영한 계획을 확정받았다)**
1. **자료를 둘 곳: (가) 이 저장소.** 80개 묶음과 그 문서, 생성·검증 스크립트, 하네스를 넣는다. 위키 문서 300개(4.3 MB)도 넣는다. 받아서 `.md`로 바꾸는 스크립트가 없어 잃으면 B1·W1 수치를 다시 낼 수 없기 때문이다.
   - 위키 문서는 별도 디렉터리에 CC BY-SA 고지와 매니페스트(URL, `revision_id`)를 함께 두어 MIT 코드와 섞지 않는다.
   - 예제 앱에 기본으로 묶이지 않는 경로에 둔다. `example/pubspec.yaml`은 `assets/`만 선언하는데, Flutter는 선언한 디렉터리의 하위 폴더를 묶지 않는 것으로 안다. 커밋 전에 빌드 결과물의 자산 목록으로 확인한다.
   - 위키 문서는 새 묶음(FAQ·매뉴얼)과 분야가 달라 어려운 방해 문서는 못 된다. 쓸모는 색인 규모를 키우는 쪽이다.
   - 800개 질의와 400행 정답은 평가 자료로 넣지 않는다. 생성 스크립트와 seed 42로 다시 만들 수 있고, 결함은 F-0 보고서에 적었다.
2. **새 질의: 세션 초안을 "사람이 쓴 질의"로 부르지 않는다.**
   - 질의마다 작성자 필드(`session_draft+human_review` / `human`)를 두고, 보고서에서 둘을 나눠 적는다.
   - 사용자가 정답 구절을 보지 않고 평소 묻는 식으로 10~20개를 직접 쓰면 세션 초안의 낱말 겹침과 견줄 기준이 된다. 사용자의 시간이 드는 일이라 따로 확인한다(2026-11-13 미정).
   - 검수는 40개를 먼저 하고, 낱말 겹침 분포를 본 뒤 늘린다. 한국어 질의는 사용자가 직접 읽어 자연스러운지 본다.
3. **큰 묶음(F-6): 뺀다.**
4. **BM25 점수(F-7): 엔진 함수를 그대로 부른다.** Rust 크레이트 안의 테스트에서 `tokenize_for_bm25`(`pub(crate)`)와 BM25 검색을 직접 불러 덤프한다. 공개 API와 검색 동작은 바꾸지 않고, 구현은 한 벌로 남긴다. 되는지 먼저 빌드로 확인하고, 안 되면 이유를 적고 스크립트로 다시 계산하는 안으로 돌아간다. 검증은 `bm25_only` 순위에 더해 모의 결합이 엔진의 `default_hybrid` 순위를 재현하는지까지 본다(후보 수 자르기 `top_k × 4`와 HNSW 근사 포함).
5. **갈래를 가르는 선: 초안(90%, 80%)을 고치지 않고 기록한다.** 위 "결정: 갈래 (2)" 참고.

### Q0. 내부 점검 묶음 (Q1~Q5) 공통

- **출처:** `docs/reports/2026-11-06-hotfix-retrospective.md`(2026-11-06 점검). 항목 번호 A1~A5, B1~B16은 그 문서의 번호다. 근거·재현 방법은 그 문서에 있다.
- **합의:** 2026-11-06 사용자 "순서대로 도입해봐". 순서는 Q1 → Q2 → Q3 → Q4 → Q5. 2026-11-13 합의로 F1을 Q2 앞에 둔다(W1 → F1 → Q2 → Q3 → Q4 → Q5). Q2와 Q3는 둘 다 `source_rag.rs`를 고치므로 동시에 진행하지 않는다(규칙 3).
- **공통 완료 기준:** 규칙 8의 네 항목에 더해, 고친 항목마다 같은 원인으로 다른 곳도 깨지는지 찾아 PR의 "맞물리는 코드" 절에 적는다(회고 5절 1). 테스트 텍스트에는 한국어·일본어·중국어, NFD 한글, 전각, 이모지, 소수점을 넣는다(회고 5절 2).
- **배포:** 이 묶음은 배포하지 않는다. 변경 기록은 `CHANGELOG.md`의 `## Unreleased`에 쌓는다(규칙 5).

### Q1. 0.23.0 회귀와 의존성

- **담당:** 이 대화의 세션, 브랜치 `feat/q1-asset-regression`(#128·#129·#130·#131 위에 쌓음)
- **상태:** 머지 완료 (#132, 2026-11-09). 2026-11-06 사용자: "착수해줘". 문서 부분은 #130으로 먼저 열었다.

**확인 결과 (2026-11-06, 로컬 macOS release 빌드, MiniLM Model Pack 파일, 같은 데이터 컨테이너에서 차례로 실행):**

| 단계 | 패키지 | 설정 | 결과 |
|---|---|---|---|
| p0 | pub 0.23.0 | asset 번들, 색인 | 청크 1개, 검색 1건, fingerprint `…|sha256:e9246dc3…` |
| p1 | pub 0.23.0 | asset 뺌 | **실패** `Unable to load asset: "assets/mobile_rag/tokenizer.json"` (A1 재현) |
| p2 | 수정본 | asset 뺌 | 성공. 같은 fingerprint, 잠금 없음, 검색 1건, 모델 파일 다시 쓰지 않음 |
| p3 | 수정본 | `tokenizerPath`/`modelPath` | 성공. 같은 fingerprint, 잠금 없음, 검색 1건 |
| p4 | 수정본 | asset 다시 번들 | 성공. 0.23.0의 `.asset-stamp`가 맞아 다시 복사하지 않음 |

수정본 단계는 `flutter_onnxruntime` 1.9.0으로 빌드했다. 로컬 Xcode 27.1에서 확인용 앱에 두 가지를 우회했다(아래 후보 참고). pod 배포 대상을 14.0으로 고정했고, arm64만 빌드했다. Rust는 crate hash가 0.23.0과 같아 서명된 precompiled binary를 썼다.

**착수 때 정한 방식 (2026-11-06)**
- **A1은 두 가지를 함께 한다.**
  - (a) 회귀 복구: `syncAssetToFile`이 asset을 읽다가 번들에 없다는 오류(`FlutterError`)가 나고 대상 파일이 이미 있으면, 0.22.3처럼 그 파일을 그대로 쓴다. 대상 파일이 없으면 지금처럼 실패한다. 다른 모델 파일이 놓여 있으면 fingerprint의 모델 해시(#118)가 잠그므로 안전장치는 남는다.
  - (b) 명시적 경로: `MobileRag.initialize(tokenizerPath:, modelPath:)`를 더한다. 앱이 준비한 파일을 asset 복사 없이 쓴다. `modelPack`, `tokenizerAsset`/`modelAsset`과 함께 쓰면 `ArgumentError`. 내부적으로 `RagConfig.preparedTokenizerPath`/`preparedModelPath`를 쓴다(차원 기대값 없음). fingerprint의 모델 이름은 파일 경로의 basename이라, 0.22.x 문서 방식(`<저장 디렉터리>/model.onnx`)에서 (b)로 옮겨도 잠기지 않는다.
  - 문서(`release_build.md`, `faq.md`)는 (b)를 권장하도록 되살리고, (a)는 기존 앱 호환으로 적는다.
- **A5:** `flutter_onnxruntime` 하한을 `^1.8.3`으로 올린다(1.8.1에서 A18/M4 OOM 수정, 1.8.3에서 ITMS-90208 수정, 해당 CHANGELOG로 확인). 2026-11-07 점검: 1.8.3의 ITMS-90208 수정은 SPM 빌드에만 해당한다(1.8.2와 1.8.3의 podspec이 같다). CocoaPods 사용자에게 실질적인 이유는 1.8.0의 OOM이다. 두 lockfile은 새 사용자가 받는 최신(1.9.0)으로 맞춰 CI가 그 버전을 검사하게 한다.

**목표:** 0.23.0에서 새로 생긴 회귀와, 지금 pub 사용자에게 영향을 주는 의존성·문서 문제를 고친다.

**포함**
- A1 코드: 모델 asset 없이 배포하고 실행 중에 모델을 내려받는 경로를 다시 지원한다. 대상 파일이 있고 asset이 번들되지 않았으면 그 파일을 쓰거나, `MobileRag.initialize`에 준비된 파일 경로 옵션(`RagConfig.preparedModelPath`/`preparedTokenizerPath`)을 공개한다. 방식은 착수 때 이 문서에 먼저 정한다. 고친 뒤 `release_build.md`의 안내를 되살린다.
- A5: `flutter_onnxruntime` 하한을 App Store 업로드 결함(ITMS-90208)이 고쳐진 버전 이상으로 올리고, lockfile 두 개를 갱신한다. 착수 때 해당 패키지 CHANGELOG로 버전을 다시 확인한다.
- 문서 버전 표기: `troubleshooting.md`의 `^0.22.2` 안내(→ `^0.23.0`).
- 착수 때 뺀 것: 배포되는 example이 `.pubignore`로 빠진 `assets/`를 선언하는 문제. 배포 아카이브는 `example/ios`·`example/macos`도 빼므로 pub cache의 example은 원래 빌드용이 아니라 읽기용이다. 고칠 실익이 없다.

**제외:** Q2~Q5 항목. 모델 다운로드 기능 자체(내려받기는 앱이 한다).

**완료 기준**
- asset을 뺀 release 빌드에서 미리 둔 모델 파일로 초기화와 첫 검색이 된다(실제 앱 한 번 이상).
- 0.23.0이 남긴 `.asset-stamp` 상태에서 업그레이드해도 다시 복사하거나 잠그지 않는다.
- 공통 완료 기준. PR 하나, CI 통과.

**손대는 파일:** `lib/src/internal/asset_file_sync.dart`, `lib/services/rag_engine.dart`(초기화), `lib/mobile_rag.dart`, `lib/services/rag_config.dart`, `pubspec.yaml`, `pubspec.lock`, `example/pubspec.lock`, `docs/guides/{release_build,troubleshooting,faq}.md`, `test/unit/**`, `CHANGELOG.md`, `docs/milestones.md`

### Q2. 상태 수명주기

- **상태:** 착수 대기.

**목표:** 새로 설치한 상태가 아닐 때만 드러나는 상태·수명주기 버그를 고치고 하네스로 막는다.

**포함**
- A3: `clearAndRestart` 뒤 같은 문서를 다시 추가하면 `DuplicateInProgress`로 막히는 문제. 청크 0개인 `completed` source를 다시 잡을 수 있게 한다.
- A4: 비하이브리드 `search()`가 다른 컬렉션의 로드된 HNSW로 검색하는 문제. `reembedAll` 뒤 옛 그래프도 같다.
- B3: 중간에 끊긴 재임베딩을 같은 모델로 돌아가면 받아들이고, 다른 모델로는 빠져나갈 수 없는 문제.
- B4: 이미 있는 문서를 다시 추가해도 generation이 올라 인덱스가 전부 다시 빌드되는 문제.
- B5: 임베딩 worker dispose 중의 `embed()`가 영원히 기다리는 문제와 `MobileRag.initialize` 동시 호출.
- B6: dispose 뒤에도 남는 500ms debounce 타이머.
- B7: `clearAllData`가 다른 컬렉션의 진행 중인 ingest·warmup을 기다리지 않는 문제.
- Upgrade E2E: 기준 버전에 0.23.0을 더하고(0.22.3은 유지할지 착수 때 정한다), `clearAndRestart` → 재추가, 컬렉션 전환 뒤 `search()` 시나리오를 넣는다.

**제외:** 낮음 항목(부팅 backfill, 0.12 이하 DB 중복, `.vec` offset 정체성, 동시 하이브리드 검색). 필요하면 후보로 둔다.

**완료 기준**
- 새 하네스 시나리오가 수정 전 main에서 실패하고 수정 뒤 통과한다(H1과 같은 `KNOWN_FAILING` 방식).
- 공통 완료 기준. PR 하나, CI 통과. Rust를 고치므로 `rag_engine_flutter` 배포가 필요하다(배포는 규칙 5).

**손대는 파일:** `rust_builder/rust/src/api/{source_rag,migration_meta,ingest_session,hnsw_index}.rs`, `lib/services/{rag_engine,source_rag_service,embedding_service}.dart`, `lib/mobile_rag.dart`, `.github/workflows/upgrade_e2e.yml`, `tool/upgrade_e2e/**`, `.github/pull_request_template.md`(기준 버전), `test/**`, `CHANGELOG.md`, `rust_builder/CHANGELOG.md`, `docs/milestones.md`

### Q3. 텍스트 경계

- **상태:** 착수 대기. Q2 뒤.

**목표:** 바이트·문자·토큰 경계와 비 ASCII 텍스트에서 깨지는 곳을 고친다.

**포함**
- A2: `compress_text`가 `。`에서 panic하는 문제와, `.`마다 문장을 나눠 `3.14` → `3. 14`가 되는 문제.
- B1: markdown 청크 예산이 `Header Path:` 접두어를 세지 않아 512토큰을 넘는 문제. 테스트도 실제 임베딩 입력으로 센다.
- B2: `reembedAll`이 색인 때와 다른 텍스트(`render_context_text` 없이 본문만)를 임베딩하는 문제.
- B8: BM25 Unicode 정규화(NFC, 전각, 합자). 중복 검사 해시에 미치는 영향도 정한다(기존 DB 해시와의 호환).
- B9: 한국어 bigram이 영문·숫자+조사(`RAG는`, `2024년`)와 한 음절 명사+조사를 놓치는 문제.
- 공개 `SemanticChunk.startPos`/`endPos`의 단위(UTF-8 바이트) 문서화, markdown 헤더 오인식(`#해시태그`, `~~~`, `.MD`).

**제외:** 토큰 예산 단위(B13, Q4).

**완료 기준**
- 위 항목마다 한·중·일 입력 회귀 테스트. 기존 DB의 BM25는 활성화 때 다시 빌드되므로 마이그레이션이 필요 없는지 확인한다.
- 공통 완료 기준. PR 하나, CI 통과. Rust 변경이 있다.

**손대는 파일:** `rust_builder/rust/src/api/{compression_utils,semantic_chunker,bm25_search,ingest_session,source_rag}.rs`, `lib/services/rag_engine.dart`(reembed 입력), `lib/services/source_rag_service.dart`(`.md` 판별), `test/**`, `CHANGELOG.md`, `rust_builder/CHANGELOG.md`, `docs/milestones.md`

### Q4. 출력 계약

- **상태:** 착수 대기.

**목표:** 사용자와 LLM이 읽는 점수·순서·인용·예산이 문서와 같게 동작하게 한다.

**포함**
- B10: `MobileRag.search`의 `similarity`가 `sourceIds` 유무에 따라 RRF 값과 코사인으로 바뀌는 문제.
- B11: `adjacentChunks > 0`이면 결과가 출처 순서로 정렬되어 relevanceFirst가 깨지는 문제.
- B12: 인용 파싱이 `［１］`, `【1】`, `[1、2]`, `[1-3]`을 놓치고 코드 안의 `items[2]`를 잡는 문제. `「1」`·`『1』`은 2026-11-09 게임 연동에서 Foundation Models가 실제로 쓴 형식이라 W1에서 먼저 읽게 했다(짝이 맞는 괄호 안 숫자, 준 번호만).
- B13: ask·tool 토큰 예산이 임베딩 tokenizer 단위라 UNK가 많은 언어에서 LLM 토큰과 크게 다른 문제. `PromptCompressor`의 char/4 근사. 해결 방식(예: `targetPromptTokenCounter` 연결)은 착수 때 정한다.

**제외:** LLM SDK 의존성.

**완료 기준:** 실제 엔진 출력으로 점수 단위·순서·인용 확인(H1-b와 같은 방식). 공통 완료 기준. PR 하나, CI 통과.

**손대는 파일:** `lib/services/{source_rag_service,ask,context_builder,prompt_compressor,llm_tool}.dart`, `rust_builder/rust/src/api/source_rag.rs`(assembly 순서), `docs/guides/{ask,llm_tools}.md`, `test/**`, `CHANGELOG.md`, `docs/milestones.md`

### Q5. 배포 검증 보강

- **상태:** 착수 대기.

**목표:** 발행 전에 배포 아카이브, release 빌드, 새 앱 설정을 실제로 확인한다(#129 규칙 5-2).

**포함**
- B14: setup의 Podfile 패치가 줄 끝 주석, `use_frameworks! linkage: :dynamic` 같은 변형에서 조용히 실패하고 `--check`가 통과하는 문제.
- B15: `flutter pub publish --dry-run` 아카이브를 path 의존성으로 설치하는 Quick Start 모드. PR 경로 트리거에 `pubspec.yaml`, `.pubignore`, `rust_builder/{windows,cargokit,rust}/**` 추가. iOS Release 바이너리 실행 또는 FRB가 찾는 심볼 전체 검사.
- B16: Android release arm64 빌드와 16 KB 정렬 검사, AAB 빌드.
- DB에 기록되는 엔진 버전(`Cargo.toml` 0.8.0)을 실제 버전과 맞춘다.

**제외:** 실기기 측정(M5). GitHub 필수 체크 변경(규칙 8).

**완료 기준:** 새 검사가 이전 버그(예: `.pubignore`로 빠진 파일)를 재현하는지 한 번 확인한다. 공통 완료 기준. PR 하나, CI 통과.

**손대는 파일:** `lib/src/model_pack/apple_host_configurator.dart`, `bin/**`, `.github/workflows/{quickstart_e2e,ci}.yml`, `tool/quickstart_e2e/**`, `rust_builder/rust/Cargo.toml`, `test/unit/apple_host_configurator_test.dart`, `docs/milestones.md`

### I1. 실제 앱 연동 마찰 문서

- **상태:** 착수 대기 (2026-11-09 사용자: "다음범위 문서에 써줘").
- **출처:** 2026-11-09 Flutter Flame 게임(`legendary-bow-master`, 브랜치 `feats/ios-guide-qa`)에 iOS 전용 가이드 Q&A를 붙인 경험. 0.23.0, KoEn-E5-Tiny int8, Apple Foundation Models를 `RagGenerate`로 연결했고 iPhone 17(iOS 27.0.1)에서 확인했다. 패키지 코드는 고치지 않았다. 핵심 API(`initialize` → `addDocument` → `prepareAsk`)는 바로 붙었고, 시간이 든 곳은 빌드·배포 단계에서 원인을 찾는 일이었다.
- **순서:** `troubleshooting.md`·`faq.md`·`release_build.md`를 고친 Q1(#132)과 README·가이드를 고친 D1(#133)은 머지됐다. W1과 `ask.md`가 겹치므로 W1 머지 뒤 main에서 브랜치를 딴다(규칙 3).

**목표:** 기존 앱(다른 플러그인이 있고, 웹 빌드도 하고, 한 플랫폼에서만 RAG를 쓰는 앱)에 붙일 때 만나는 문제를 증상으로 찾아 바로 고칠 수 있게 문서로 남긴다.

**포함**
- **정적 링크와 vendored 라이브러리 충돌:** `use_frameworks! :linkage => :static`으로 바꾸면 기기용·시뮬레이터용 `.a`를 따로 vendoring하는 플러그인(예: `flutter_soloud`의 `libflac_iOS-device.a`)이 SDK 구분 없이 앱 링크에 들어가 시뮬레이터 빌드가 `building for iOS Simulator, but linking in object file built for iOS`로 깨진다. 증상, 원인, `post_install`에서 `OTHER_LDFLAGS`를 `[sdk=iphoneos*]`/`[sdk=iphonesimulator*]`로 나누는 우회 예시를 `troubleshooting.md`에 적는다. 정적 링크 요구 자체는 `flutter_onnxruntime`에서 오므로 없애지 않는다.
- **한 플랫폼에서만 쓰는 앱:** (1) 웹 빌드: 조건부 import(`if (dart.library.io)`)로 FFI 코드를 빼는 예시. (2) 모델 asset이 웹 빌드에도 같이 들어가는 문제(Flutter asset은 플랫폼별로 뺄 수 없다)와 대응: 빌드 뒤 `build/web/assets/...`에서 지우거나, Q1의 `tokenizerPath`/`modelPath`로 asset 없이 배포하는 방법. `faq.md`의 "Does it support Web?" 답을 이 내용으로 고친다.
- **모델 파일을 git 밖에 둘 때:** 고정 revision에서 받아 Model Pack manifest의 sha256으로 확인하는 스크립트 예시와 `.gitignore` 안내를 `model_setup.md`에 넣는다.
- **짧은 문서 묶음을 넣을 때의 요령:** 긴 절 하나가 검색 결과를 계속 차지한 사례(게임 가이드의 「강화 카드」 절)를 바탕으로, 절을 주제 하나 단위로 나누는 기준을 적는다. 기본 가중치(`vectorWeight` 0.2 / `bm25Weight` 0.8)와 0.5 / 0.5를 같은 질문 묶음으로 비교해 보고 결과가 분명할 때만 권장값을 적는다. 측정 없이 권장값을 쓰지 않는다.
- **생성 연결 예시:** iOS Foundation Models를 메서드 채널로 `RagGenerate`에 붙이는 최소 예시(사용 가능 여부 확인, 가드레일·컨텍스트 초과 오류를 찾은 구절 보여주기로 대체)를 `ask.md`에 넣는다. 시뮬레이터에서는 사용 가능으로 나와도 생성이 실패한다는 점도 적는다.

**제외**
- 패키지 코드 변경. 정적 링크 요구 제거, 웹 지원.
- 답이 `[3]`처럼 인용 번호만 오는 경우 감지: Q4(인용·출력 계약)에서 함께 다룰지 착수 때 정한다.
- Xcode 27 시뮬레이터 lipo 문제(위 후보에 이미 있다), 작은 모델의 지어내기(모델 문제).

**완료 기준**
- 새로 만든 Flutter 앱에 `flutter_soloud`를 함께 넣고 정적 링크로 바꿔 시뮬레이터 링크 오류를 재현한 뒤, 문서의 우회법만으로 빌드가 되는지 확인한다.
- 조건부 import 예시로 `flutter build web`이 되고, 모델 파일이 빌드 결과에서 빠지는 것을 확인한다.
- 가중치 비교 결과(질문, 상위 결과, 판정)를 PR 본문에 적는다.
- 규칙 8의 네 항목. 문서만 바뀌므로 업그레이드 경로는 "해당 없음"과 이유를 적는다. PR 하나, CI 통과.

**손대는 파일:** `docs/guides/{troubleshooting,faq,model_setup,ask,quick_start}.md`, `README.md`(필요할 때 링크만), `docs/milestones.md`

### 아직 마일스톤으로 적지 않은 후보

착수하려면 위 형식으로 옮겨 적고 합의를 받는다.

- **[높음] 큰 문서와 함께 넣은 짧은 문서가 벡터 검색에 나오지 않는다 (2026-11-12 D1 실행 중 발견, 코드는 고치지 않음).** → S1 범위 초안으로 옮겼다. README 상단 예제의 형태다.
  - 재현(macOS, MiniLM Model Pack): `addDocument('Refunds are accepted within 14 days of purchase.')` 뒤 `addDocumentFromFile(example/assets/sample_data/sample_eng.pdf)`(1820 청크). `search('How long is the refund period?', topK: 50)`과 `searchHybrid(topK: 50)`에 환불 문장이 없다. 짧은 문서만 있을 때는 similarity 0.7295로 1위인데, PDF를 넣은 뒤에는 1위가 0.4377인 PDF 청크다.
  - 같은 결과: PDF를 먼저 넣어도, PDF 본문을 `addDocument(String)`으로 넣어도, `rebuildIndex()`를 불러도, `dispose` 후 다시 `initialize`해도, 짧은 문서를 더 넣어도, 짧은 문서가 6개여도(다른 질의로 다른 짧은 문서도 못 찾는다).
  - 데이터는 있다: `search(..., sourceIds: [1])`(exact scan)은 환불 문장을 돌려준다. 5 청크짜리 PDF와 함께일 때는 정상이다.
  - 추정(확인하지 않음): 한 문서의 청크가 빽빽이 모여 있을 때 멀리 떨어진 벡터로 들어오는 HNSW 링크가 모두 잘려 그래프에서 도달할 수 없게 된다. BM25는 "refund"와 "Refunds"가 달라 이 질의에서 맞지 않았다.
- **[중간] `clearAndRestart()` 뒤에 같은 문서를 다시 넣을 수 없다 (2026-11-12 D1).** → S1 범위 초안으로 옮겼다. `sources` 행이 남아 `addDocument`가 `isDuplicate: true, chunkCount: 0, message: "Source ingestion already in progress"`를 돌려준다. API 주석("`sources` 테이블을 남겨 `addDocument`로 다시 넣을 수 있다")과 다르다. 문서에는 `removeSource` 우회 절차를 적었다.
- **[중간] (→ W1로 옮겼다) 기본 하이브리드 가중치(벡터 0.2, BM25 0.8)에서 불용어만 맞은 청크가 정답보다 앞선다 (2026-11-12 D1).** 6 청크 코퍼스에서 "How long is the refund period?"의 정답(벡터 1위, BM25 불일치)이 `searchHybrid` 5위(0.0033)이고, "the"/"is"만 겹친 청크 넷이 0.016 안팎으로 앞선다. `ask`는 이 검색의 상위 5개만 쓴다. main 체크아웃의 `feat/ask-search-weights` 작업과 겹치는지 확인한다.
- **[중간] `ask` 조건(topK 5)에서 HNSW가 가장 가까운 청크를 놓친다 (2026-11-13 F1에서 발견, 고치지 않음).** `search_hnsw_slice`의 검색 폭이 `max(100, top_k × 5)`라서, `ask`(후보 20개)는 ef 100, 평가 하네스(topK 100, 후보 400개)는 ef 2000이다. vector_only에서도 topK 100이면 1위인 정답이 topK 5에서는 상위 5개 밖이다(F-2 1단계 MiniLM 2개, KoEn 2개. 80개 묶음 MiniLM vector_only `@5` 0.600 → 0.550). B1의 "HNSW 손실 없음"은 ef 2000 조건의 결론이다. exact scan과 나눠 보는 확인은 아직 하지 않았다. 재현과 수치는 `docs/perf/f1-eval-baseline/f2_stage1.md`.
- **[중간] (→ F1의 평가 기반을 먼저 만든다. 결합 변경은 그 뒤 F2로 따로 적는다) 낱말이 겹치지 않는 짧은 문서는 RRF에서 여전히 밀린다 (2026-11-13 W1에서 확인, 고치지 않음).** W1은 단·복수형이 달라 안 맞던 경우만 고쳤다. 질문과 낱말이 하나도 겹치지 않는 짧은 문서는 기본 가중치에서 상위 5개에 못 들 수 있다. 원인은 RRF가 두 목록 모두에 오른 문서에 점수를 더해 주는 구조라, 한쪽에서만 1위인 문서가 양쪽 중간인 문서에 지는 것이다(벡터 1위 단독 `0.2/61`, BM25 10위 `0.8/70`). 가중치만으로는 풀리지 않는다(0.5/0.5에서 W1 전 32~35위).
  - 생각해 둔 방식: 벡터 점수가 분명히 높은 문서에 상위 자리를 보장한다. 융합 설계를 바꾸는 일이다.
  - **먼저 평가셋이 필요하다.** 지금 80 질의 평가셋에는 "짧은 문서 + 낱말 안 겹침" 질문이 거의 없어서, 좋아졌는지 잴 수 없다. 그런 질문을 담은 평가셋을 만드는 것이 이 후보의 첫 단계다.
  - 지금은 `docs/guides/ask.md`의 "Short documents next to a large one"에 우회 세 가지(짧은 문서를 따로 컬렉션에 두기, 그 질문에만 벡터 가중치 올리기, 짧은 문서에 낱말 더하기)를 적어 두었다.
- **[낮음] 2026-11-12 D1에서 본 것:** (1) `mobile_rag_engine.dart`가 `RagError`만 `show`로 내보내, 앱이 `when`/`maybeWhen`과 `RagErrorUi.userFriendlyMessage`를 쓸 수 없다. (2) `pubspec.yaml`의 `flutter: ">=3.9.0"`이 실제 하한(Dart 3.9.2 = Flutter 3.35.3)과 다르다. (3) `name` 없이 넣은 문서는 `RagPassage.sourceName`이 null이라 `ask.md`와 README의 인용 출력 예제가 "null"을 찍는다. (4) `DocumentParser.parse`를 `MobileRag.initialize` 전에 부르면 `flutter_rust_bridge has not been initialized`가 난다.
- **[중간] Xcode 27에서 macOS profile/release 빌드의 Rust 소스 빌드가 실패한다 (2026-11-12 S1 실행 중 발견, B1에서 원인 확인, 고치지 않음).**
  - **증상:** cargokit이 `--features vector_faer,vector_quant_i8 --release`로 빌드하면 `error[E0463]: can't find crate for dyn_stack_macros`(또는 `paste`)로 멈춘다. debug 빌드는 faer가 없어 이 proc-macro들을 만들지 않으므로 된다.
  - **원인:** Xcode가 넘기는 `MACOSX_DEPLOYMENT_TARGET`이 12.0 이상이면 링커가 proc-macro dylib을 chained fixups 형식으로 만들고, rustc 1.91.1이 그 dylib의 메타데이터를 읽지 못한다.
    - Xcode 환경 변수 706개를 반씩 나눠 확인했다. 셸에서 `MACOSX_DEPLOYMENT_TARGET`만 줘도 11.0은 통과, 12.0·13.0·14.0은 실패한다.
    - 링커에 `-Wl,-no_fixup_chains`를 붙이는 래퍼(`CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER`)를 주면 14.0에서도 통과한다.
  - **Xcode 27과의 관계:** Xcode 27은 pod의 배포 대상을 12.0 아래로 허용하지 않아서, 앱이 Xcode 27로 빌드되려면 이 조건에 걸린다.
  - **두 번째 문제:** 링커 래퍼를 줘도 universal(`ARCHS = arm64 x86_64`) 빌드는 Flutter의 lipo 검사(아래 후보 (2))에서 다시 멈춘다. B1 측정은 앱의 `Runner/Configs/Release.xcconfig`에 `ARCHS = arm64`를 넣어 우회했다.
  - **영향:** 배포된 패키지는 rustup이 없으면 precompiled binary를 쓰므로 이 문제를 피한다. rustup이 설치된 Mac에서 소스로 빌드하는 사용자는 profile/release 빌드에서 이 문제를 만난다.
  - **할 일:** 고칠 곳을 정한다. 후보는 cargokit의 linker 설정, `-no_fixup_chains`, rustc 버전 확인이다. 회고 C1과 함께 Q5에서 볼지 정한다.
- **[낮음] (→ B1 범위 초안으로 옮겼다) 80-query passage 평가의 6월 기록(`passage_recall@10` 0.925, `vector_only` 0.95)은 지금과 같은 조건의 수치가 아니다 (2026-11-12 S1 조사).** 평가셋 세 파일(질의 80개, 정답 passage)은 6월 artifact와 같다. 다른 점은 다음과 같다.
  - **모델:** 6월은 1024차원 모델이다. 6월 실행이 남긴 DB(`com.example.mobileRagEngineExample` 컨테이너의 `hybrid_passage_relevance_80_balanced.sqlite`, 2026-06-13)의 fingerprint가 `model.onnx|1024|f32`이고, 사용자는 BGE-m3였다고 기억한다(2026-11-12). 지금 `example/assets/backup_onnx/model.onnx`는 MiniLM Model Pack과 같은 384차원 모델이다(`sha256:e9246dc3…`). 그래서 6월에는 벡터만으로 한국어 질의 30/32를 맞혔고, 지금 MiniLM은 exact scan으로도 11/32다. 영어 질의는 둘 다 30/32다.
  - **청킹:** 청크 수가 다르다(6월 DB 4937개, 지금 4667개). 6월 뒤의 512 토큰 truncation(#115)과 한국어 청킹 변경(#116)이 들어 있다.
  - **빌드 모드:** 6월은 profile, 지금은 debug(Xcode 27 profile 빌드 실패, 위 후보).
  - **검색은 원인이 아니다:** S1 수정 뒤 HNSW `vector_only`의 정답 순위가 80개 질의 모두 exact scan(`sourceIds`에 전체 소스)과 같다(52/80). 수정 전에는 38/80이었다.

  README와 `docs/local-rag-engine.md`의 0.925는 기본 Model Pack(MiniLM)이 아니라 BGE-m3로 잰 값이다. 지금 코드에서 기본 모델로 다시 재서 바꿀지, 모델을 함께 적을지 정한다.
- **[낮음] README의 `source_recall@10 = 1.000`에 모델이 적혀 있지 않다 (2026-11-13 D2, 규칙 9).** README "Supported and Verified Scope"의 "Hybrid source retrieval" 행이 "80-source balanced profile run"의 `default_hybrid` 값으로 적고 있다. D2 범위(passage 행)가 아니라 그대로 뒀다.
  - **출처:** 2026-06-19 `faa5079`("docs: sharpen local rag package positioning")에서 들어왔다. 어떤 실행의 값인지 가리키는 보고서나 artifact가 저장소에 없다. 6월 평가가 BGE-m3로 돌았으므로 같은 모델일 가능성이 높지만 확인하지 않았다.
  - **B1 결과에 있는 값:** B1의 passage 평가 결과 JSON(`docs/perf/passage-benchmark-2026-11/results/*_hnsw.json`)에도 `aggregates.default_hybrid.overall.source_recall@10`이 있고, MiniLM·KoEn-E5-Tiny·BGE-m3·6월 BGE-m3 모두 1.0이다. README의 "80-source balanced profile run"이 이 하네스의 값과 같은 측정인지는 확인하지 않았다.
  - **할 일:** 같은 측정이면 README 행을 B1 값으로 바꾸고 모델과 조건을 붙인다(새 측정 없음). 다른 측정이면 "모델 미기재"라고 밝히거나, 그 하네스로 다시 잴지 정한다. `docs/local-rag-engine.md`에는 이 수치가 없다.
- **[중간] S1의 HNSW 회귀 테스트가 흔들린다 (2026-11-13 D2 PR #136의 CI에서 발견, 고치지 않음).**
  - **증상:** `custom_hnsw::tests::far_vectors_next_to_a_dense_cluster_are_their_own_top_result`(`rust_builder/rust/src/api/custom_hnsw.rs`)가 Windows `Native Tests`에서 실패했다(run `43339546418`). 외톨이 나중 순서에서 들어오는 링크가 0개인 layer-0 노드가 1개, 자기 벡터로 검색해도 1위가 아닌 외톨이가 1/6(id 1803, builder와 파일 모두 487이 1위)이었다. 진입점에서 도달할 수 없는 노드는 0개였다.
  - **같은 코드에서 통과도 했다:** 바로 앞 실행(run `43336051835`, 같은 엔진 코드, 문서만 다름)에서는 통과했다. S1 PR(#134) CI와 S1 로컬 실행에서도 통과했다.
  - **추정 원인(확인하지 않음):** 노드의 층을 `random_layer`가 시드 없는 `rand::thread_rng()`로 정한다. 테스트 벡터는 고정 시드(`lcg_vectors`)지만 그래프 모양은 실행마다 다르다. 도달 보장(`connect_unreachable_nodes`)은 도달 가능성만 맞추므로, 먼 노드에서 들어오는 링크가 하나뿐이라 검색 빔이 지나가지 않는 경우(S1 범위 변경에 적은 두 번째 형태)가 드물게 남을 수 있다.
  - **영향:** 테스트만의 문제가 아니라면 S1 수정 뒤에도 짧은 문서가 가끔 벡터 검색 1위로 나오지 않을 수 있다. 1위가 아니어도 top-10에 드는지는 이 실패 기록으로는 모른다.
  - **할 일:** 층 결정을 시드 가능하게 해 실패하는 시드를 재현하고, 들어오는 링크 수 하한 같은 보강이 필요한지 정한다. 테스트만 고정 시드로 바꾸면 흔들림은 사라지지만 위 경우는 가려진다. Rust 코어가 바뀌면 `rag_engine_flutter` 배포가 필요하다.
- Windows `Native Tests`의 `ingest_ffi_traffic_test.dart` "Peak-RSS delta"가 가끔 실패한다(파일 경로가 UTF-8 경로보다 2MB 이상 적게 써야 하는데 0.7~0.8MB 차이만 났다. 11/1 `ci/quickstart-e2e`, 11/3 #125). 측정값이 흔들리는 테스트라 기준이나 측정 방식을 손봐야 한다.
- 성능 후보: `vector_math` 8-lane dot, HNSW 증분 삽입, prune 거리 캐싱, ef 상한, 짧은 문단 병합
- `lib/src/rust/api/mmap_store.dart` 잔존 파일 정리
- query/document 접두어 설정 (e5-small 계열을 권장 모델로 추가할 때)
- `AssembledContext.estimatedTokens` → `exactTokens` 이름 변경 (다음 breaking 배포 때)
- Xcode 27 + Flutter 3.35.5 (2026-11-06 Q1 확인 중 발견, 빈 `flutter create` 앱도 같다): (1) pod 배포 대상 macOS 10.15를 Xcode 27이 거부한다(12.0 이상). `setup`은 Podfile `platform`만 올리므로 pod target까지 맞추는 `post_install`을 넣을지 Q5에서 정한다. (2) Flutter의 release lipo 검사가 `ARCHS="arm64 x86_64"`를 아키텍처 하나로 읽어 universal macOS release 빌드가 실패한다. Flutter 쪽 문제라 문서(troubleshooting)에 우회법만 적을지 정한다. CI의 `macos-latest`가 Xcode 27로 바뀌면 macOS job이 함께 깨진다.
- 2026-11-07 추가 점검(회고 6절): C1 Xcode 27 Rust 소스 빌드 strip 문제(Q5에 넣을지 정한다, `rag_engine_flutter` 배포 필요), C2 Xcode 27 ↔ Flutter 3.47 요구와 CI Flutter 고정값(Q5), C3 직접 만든 Model Pack에서 setup이 멈추고 `--repair`가 모델을 덮어쓰는 문제(Q5), C4~C6과 낮음 문서 항목(새 문서 묶음 후보), inf/NaN 벡터 panic과 테스트 0개를 돌리는 Integration Tests job(가능성 있음, 착수 때 재현).
- 2026-11-06 점검의 낮음 항목: 부팅마다 기본 컬렉션 청크 전체를 UPDATE하는 backfill, 0.12 이하 DB의 dedup 해시 형식, `.vec` offset 정체성과 남는 `*.tmp-*` 파일, 동시 하이브리드 검색, Apple 정적 SQLite 심볼 노출(회고 2절 "낮음").
- 번들 문서 레시피 (2026-11-09 게임 가이드 연동, 규칙 10으로 다시 나눔): 앱과 함께 배포되는 문서 묶음이 바뀌었을 때 바뀐 문서만 갈아 끼우는 일은 지금 API로 된다. `listSources`로 목록을 보고, 바뀌었거나 없어진 문서를 `removeSource`로 지운 뒤 다시 `addDocument`하면, 그대로인 문서는 중복 검사가 건너뛴다. 게임은 더 간단해서 `clearAllData` 뒤 전부 다시 넣었다. 결함이 아니라 편의 기능이므로, 새 API보다 이 순서를 문서 레시피로 적을지 먼저 정한다. 새 API(예: `syncDocuments`)는 레시피로 부족하다는 근거가 생길 때 다시 검토한다.
- 2026-11-09 게임 가이드 연동에서 나온 검색 항목 (규칙 10으로 나눔, 앱 쪽 우회는 `legendary-bow-master` `lib/guide/guide_service_io.dart`):
  - **ask 검색 가중치 인자:** → W1(W-3)으로 옮겼다. `searchHybrid`에는 있는 `vectorWeight`/`bm25Weight`를 `prepareAsk`/`ask`에도 연다. 앱은 지금 `RagSearchTool`과 `prepareAskWith`로 우회한다. 범용: 인자. 앱 전용: 0.5/0.5 값. 기본값 0.2/0.8은 그대로 둔다.
  - **관련 없는 질문 거르기 신호 (리랭커 없이):** 하이브리드 결과는 RRF 순위 점수라 "관련 있음"을 나타내지 못한다. 그래서 가이드에 없는 질문(예: 날씨)에도 상위 K개가 오고, 작은 모델이 그 구절로 답을 지어냈다. 범용: 섞기 전의 신호(벡터 코사인, BM25 점수와 일치 여부)를 결과에 함께 돌려주고, 거를지 정하는 선택 옵션을 둔다(기본 꺼짐). 앱 전용: 기준값과 조합 규칙(앱은 지금 조사를 잘라 원문 문자열을 찾는 `guideCovers`를 쓴다). 패키지는 기준값을 넣지 않는다(코사인 분포가 모델마다 다르다). Q4의 B10(점수 단위)과 묶어 정한다. Rust 변경 가능성이 있다. 먼저 게임 가이드로 "가이드에 있음 / 다른 낱말로 물음 / 없음" 질문 묶음을 만들어 두 신호로 구분이 되는지 사례로 확인한다.
  - **문서별 청크 크기:** `maxChunkChars`/`overlapChars`는 `initialize`에서만 정하는 전역 설정이다. 길이가 다른 문서를 섞는 앱에서 필요할 수 있지만, 이 연동에서는 앱이 절을 미리 잘라 넣어 영향이 없었다. 근거가 생길 때까지 후보로만 둔다.
- 레거시 자산 확인 비용 절감: 전체 sha256 대신 크기 + 앞뒤 1MiB만 해시한다(#118 fingerprint와 같은 방식). 시뮬레이터에서 KoEn 매 시작 약 250ms와, 확인 중 모델 크기의 약 2배 순간 메모리를 줄인다. M5 실측을 본 뒤 판단한다.

## 완료

### R1. 배포 (`rag_engine_flutter` 0.22.0 + `mobile_rag_engine` 0.23.0) — 완료 (#127, 2026-11-06)

pub.dev 발행 2026-11-04(`mobile_rag_engine` 0.23.0, `rag_engine_flutter` 0.22.0). 2026-11-06 순서 6을 마쳤다.
- 머지 커밋 `11744c9`에 태그 `v0.23.0`을 달았다.
- pub 모드 Quick Start E2E(0.23.0)가 android·ios·macos·windows 모두 통과했다(run 42075253762).
- `no_rust_repro.yml`(0.23.0, Rust 숨김/설치 양쪽)이 12개 job 모두 통과했다(run 42075259650). `ios / Rust installed`는 GitHub macOS 러너를 배정받지 못해 한 번 취소됐고, 다시 실행해 통과했다.
- 이 확인은 asset을 번들하는 Quick Start를 따르므로 A1(asset 없이 배포)은 다루지 않는다(Q1).

### M8. 빈 DB·컬렉션 검색 오류 — 완료 (#126, 2026-11-03)

문서가 없는 DB·컬렉션에서 하이브리드 검색이 `HNSW cache parity failed`로 실패하던 문제. 빈 컬렉션의 HNSW 재구성은 인덱스를 두지 않는데 일치 검사가 노드 0개 인덱스를 기대했다. 0.22.3에서도 같았다(pub 0.22.3 앱에서 확인). 이미 빈 상태로 활성화된 컬렉션은 다음 검색에서 옛 HNSW 파일을 다시 읽거나 재구성하지 않는다. 실제 앱에서 빈 DB·빈 컬렉션·문서를 모두 지운 컬렉션 모두 결과 0개, `ask`는 `generate`를 부르지 않았다.

### M4. `rag.ask` 생성 브리지 — 완료 (#125, 2026-11-03)

`MobileRag.ask(question, generate: ...)`·`CollectionRag.ask`와 스트리밍용 `prepareAsk`/`RagAskPrompt.answer`. 구절 5개 기본 프롬프트는 실제 MiniLM 엔진에서 약 440토큰이었고, 인용 id는 질문마다 1부터, 지어낸 id는 `citations`에서 빠진다. 들어갈 구절이 없으면 `generate`를 부르지 않는다. 확인 중 빈 DB 검색 오류를 발견해 M8로 적었다.

### M6. fingerprint 이전 검증 — 완료 (#124, 2026-11-03)

0.22.3의 3칸 fingerprint를 4칸으로 늘리기 전에, 가장 짧은 저장 청크 3개를 지금 모델로 다시 임베딩해 저장된 벡터와 코사인 0.95 이상인지 본다. 하네스(0.22.3 DB, 로컬 macOS)에서 같은 모델은 1.0000, KoEn은 0.0289였고, s1~s4·b1~b4가 모두 통과했다. 구현 중 알게 된 점: 0.22.3은 청크별 fingerprint 태그를 비워 두고, 벡터는 `chunks.embedding`이 아니라 `.vec` MMAP 파일에 Q8_0으로 있다. Rust 표본 조회 함수가 더해져 다음 `rag_engine_flutter` 배포가 필요하다.

### M7. LLM JSON 보완 — 완료 (#123, 2026-11-03)

- **결과:** 실제 엔진 출력(macOS, MiniLM, 예산 300)으로 H1-b b1~b4 통과. 상위 3개 점수 `[1.0, 0.984, 0.962]`, 두 호출의 id `{1,2,3}`/`{4,5,6}`, 출력 717 → 405토큰.

**목표:** 맹점 2·3·4번과 6번 일부를 고친다.

**착수 때 정한 형식 (2026-11-03)**
- **본문은 `results[].text`에만 둔다.** `toLlmJson`과 tool 결과에서 `context`를 뺀다. 엔진의 `context.text`는 같은 청크를 `<document>` 블록과 메타데이터로 감싼 것이라, 인용 id가 붙은 `results` 쪽이 모델에 필요한 정보를 다 가진다.
- **`contextOnly` 결과:** 포함된 청크 목록이 비어 있고 `context.text`만 있으므로, 그 텍스트를 결과 하나(`id`와 `text`만, 출처·점수 없음)로 돌려준다. 결과 모양은 항상 `{"results": [...]}` 하나다.
- **`score`는 이 결과 안의 1위 대비 상대값이다** (`similarity / 최댓값`, 1위 = 1.0, 소수 셋째 자리). 하이브리드 점수는 순위 기반 RRF라 절댓값에 뜻이 없고(최대 약 0.016), 반올림하면 순위가 사라졌다. 상대값은 순위를 지키고 "1.0 = 가장 관련"으로 읽힌다. 다른 호출의 점수와는 비교하지 않는다고 문서에 적는다. 벡터 검색의 코사인 절댓값은 여기서 잃는다.
- **인용 id는 tool 인스턴스 안에서 이어진다.** 첫 호출이 "1"~"3"을 쓰면 다음 호출은 "4"부터다. 같은 청크가 두 번 나와도 새 id를 받는다. `toLlmJson`에는 `firstId`(기본 1)를 더한다. 대화를 새로 시작하면 tool도 새로 만든다고 문서에 적는다.
- **`listSources()`는 캐시하지 않는다 (범위 축소).** `sources.id`는 `INTEGER PRIMARY KEY`(AUTOINCREMENT 없음)라 지운 id가 재사용될 수 있어, 캐시하면 틀린 출처 이름을 줄 수 있다. 결과가 있을 때만 읽는 지금 동작을 유지한다. `SourceEntry`는 본문 없이 id·이름·시각만 읽는다.
- **dispose 뒤 인스턴스:** `MobileRag`의 메서드는 정적 엔진을 거치므로 `fromMobileRag`는 다시 초기화한 뒤에도 동작한다(`MobileRag._engine`이 static이다. 고칠 것 없음). `CollectionRag`은 만들 때의 엔진을 붙잡으므로 `fromCollection`은 컬렉션 id를 받아 호출마다 `MobileRag.instance.inCollection(id)`로 찾는다.

**포함**
- `score`: RRF 점수를 그대로 반올림하지 않는다. 순위를 잃지 않는 형식(예: 순위 `rank`, 또는 반올림 없는 값)과 문서화된 의미로 바꾼다. 형식은 착수 때 이 문서에 먼저 정한다.
- 본문 중복 제거: tool 결과에 본문이 한 번만 들어가게 한다(`context`와 `results[].text` 중 하나).
- 인용 id: 한 tool 인스턴스 안에서 호출마다 겹치지 않게 한다.
- 6번 일부: 호출마다 `listSources()` 전체를 읽는 것, `dispose` 이전 인스턴스를 붙잡는 것, `contextOnly` 결과의 빈 `results`.
- H1의 `H1_KNOWN_FAILING`에서 H1-b 항목을 지운다.

**제외:** 생성 호출(M4), LLM SDK 의존성.

**완료 기준**
- H1-b가 통과한다. 규칙 8의 네 항목. PR 하나, CI 통과.

**손대는 파일:** `lib/services/llm_tool.dart`, `lib/services/source_rag_service.dart`(`toLlmJson`), `docs/guides/llm_tools.md`, `test/unit/**`, `CHANGELOG.md`, `.github/workflows/upgrade_e2e.yml`(`H1_KNOWN_FAILING` 한 줄), `docs/milestones.md`

### M3. LLM용 검색 결과 — 완료 (#121, 2026-11-03)

`RagSearchResult.toLlmJson({sourceNames})`가 `{"context", "results"}`를 돌려주고, 새 `RagSearchTool`(`lib/services/llm_tool.dart`)이 공급자 중립 tool 정의(`{name, description, parameters}`)와 `call`/`callJson`을 준다. 검색은 `searchHybridWithContext`를 쓰고, 잘못된 인자는 `{"error": ...}`로 돌려준다. 공급자 형식 변환은 `docs/guides/llm_tools.md`에 예제로만 뒀다. 검증은 가짜 검색 결과로 한 단위 테스트였다. 리뷰에서 실제 출력 기준 맹점(H1 맹점 2~4번)이 나와 M7로 고친다.

### M2. 레거시 자산 복사 버그 — 완료 (#120, 2026-11-02)

`modelAsset`/`tokenizerAsset` 복사본 옆에 `.asset-stamp`(asset 경로·길이·sha256)를 두고, asset과 다르면 원자적으로 다시 복사한다. 시뮬레이터에서 한 프로세스 안에 KoEn → MiniLM → KoEn → KoEn 순서로 초기화해 확인했다. 수정 전 코드로 대조하면 MiniLM 차례에도 KoEn 모델을 썼다. 매 시작 확인 비용은 시뮬레이터에서 KoEn 모델 약 250ms, MiniLM 약 150ms다.

### M1. 한국어 임베딩 레시피 — 완료 (#119, 2026-11-02)

`docs/guides/model_setup.md`에 KoEn-E5-Tiny 레시피를 추가했다. nDCG@10 MiniLM 0.014~0.059 → KoEn 0.762~0.866. iOS 시뮬레이터 엔진 실행 결과는 `docs/perf/multilingual-embedding/README.md` §5. 엔진 코드는 고치지 않았다.

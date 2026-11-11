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
8. **모든 마일스톤의 완료 기준에 아래 네 가지를 넣는다 (2026-11-03 리뷰 뒤 합의).** 기존 검증이 새로 설치한 상태와 가짜 값만 봐서 맹점이 생겼기 때문이다. 작업을 마치기 전에 세션이 직접 확인하고, PR 본문의 같은 이름 절에 결과를 적는다. CI로 강제하거나 GitHub rules를 바꾸지 않는다(2026-11-03 사용자: 혼자 관리하는 패키지라 머지 부담만 커진다).
   1. **업그레이드 경로:** 마지막 배포 버전(0.23.0)이 남긴 DB와 파일 상태에서 시작해 확인한다. Upgrade E2E의 기준 버전은 아직 0.22.3이다(후보 목록 참고).
   2. **실제 출력:** 가짜 값이 아니라 실제 엔진 출력으로 최소 한 번 확인한다.
   3. **사용하는 쪽 관점:** 여러 번 호출할 때와 토큰 비용을 확인한다.
   4. **주변 코드:** 수정과 맞물리는 코드를 읽고, 무엇이 깨질 수 있는지 PR에 적는다.

## 현재 상태 (2026-11-06)

- main: `11744c9` (#127 머지). **새 배포는 보류**(규칙 5). 다음 배포는 내부 점검으로 문제를 모두 고친 뒤에 한다.
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
- **상태:** PR 열림 (#133, 2026-11-12). 머지 대기. 2026-11-11 사용자 합의 "D1 착수는 새 세션에서 하자"로 착수했다.
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

### Q0. 내부 점검 묶음 (Q1~Q5) 공통

- **출처:** `docs/reports/2026-11-06-hotfix-retrospective.md`(2026-11-06 점검). 항목 번호 A1~A5, B1~B16은 그 문서의 번호다. 근거·재현 방법은 그 문서에 있다.
- **합의:** 2026-11-06 사용자 "순서대로 도입해봐". 순서는 Q1 → Q2 → Q3 → Q4 → Q5. Q2와 Q3는 둘 다 `source_rag.rs`를 고치므로 동시에 진행하지 않는다(규칙 3).
- **공통 완료 기준:** 규칙 8의 네 항목에 더해, 고친 항목마다 같은 원인으로 다른 곳도 깨지는지 찾아 PR의 "맞물리는 코드" 절에 적는다(회고 5절 1). 테스트 텍스트에는 한국어·일본어·중국어, NFD 한글, 전각, 이모지, 소수점을 넣는다(회고 5절 2).
- **배포:** 이 묶음은 배포하지 않는다. 변경 기록은 `CHANGELOG.md`의 `## Unreleased`에 쌓는다(규칙 5).

### Q1. 0.23.0 회귀와 의존성

- **담당:** 이 대화의 세션, 브랜치 `feat/q1-asset-regression`(#128·#129·#130·#131 위에 쌓음)
- **상태:** PR 열림 (2026-11-06 사용자: "착수해줘"). 문서 부분은 #130으로 먼저 열었다.

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
- B12: 인용 파싱이 `［１］`, `【1】`, `[1、2]`, `[1-3]`을 놓치고 코드 안의 `items[2]`를 잡는 문제.
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

### 아직 마일스톤으로 적지 않은 후보

착수하려면 위 형식으로 옮겨 적고 합의를 받는다.

- **[높음] 큰 문서와 함께 넣은 짧은 문서가 벡터 검색에 나오지 않는다 (2026-11-12 D1 실행 중 발견, 코드는 고치지 않음).** README 상단 예제의 형태다.
  - 재현(macOS, MiniLM Model Pack): `addDocument('Refunds are accepted within 14 days of purchase.')` 뒤 `addDocumentFromFile(example/assets/sample_data/sample_eng.pdf)`(1820 청크). `search('How long is the refund period?', topK: 50)`과 `searchHybrid(topK: 50)`에 환불 문장이 없다. 짧은 문서만 있을 때는 similarity 0.7295로 1위인데, PDF를 넣은 뒤에는 1위가 0.4377인 PDF 청크다.
  - 같은 결과: PDF를 먼저 넣어도, PDF 본문을 `addDocument(String)`으로 넣어도, `rebuildIndex()`를 불러도, `dispose` 후 다시 `initialize`해도, 짧은 문서를 더 넣어도, 짧은 문서가 6개여도(다른 질의로 다른 짧은 문서도 못 찾는다).
  - 데이터는 있다: `search(..., sourceIds: [1])`(exact scan)은 환불 문장을 돌려준다. 5 청크짜리 PDF와 함께일 때는 정상이다.
  - 추정(확인하지 않음): 한 문서의 청크가 빽빽이 모여 있을 때 멀리 떨어진 벡터로 들어오는 HNSW 링크가 모두 잘려 그래프에서 도달할 수 없게 된다. BM25는 "refund"와 "Refunds"가 달라 이 질의에서 맞지 않았다.
- **[중간] `clearAndRestart()` 뒤에 같은 문서를 다시 넣을 수 없다 (2026-11-12 D1).** `sources` 행이 남아 `addDocument`가 `isDuplicate: true, chunkCount: 0, message: "Source ingestion already in progress"`를 돌려준다. API 주석("`sources` 테이블을 남겨 `addDocument`로 다시 넣을 수 있다")과 다르다. 문서에는 `removeSource` 우회 절차를 적었다.
- **[중간] 기본 하이브리드 가중치(벡터 0.2, BM25 0.8)에서 불용어만 맞은 청크가 정답보다 앞선다 (2026-11-12 D1).** 6 청크 코퍼스에서 "How long is the refund period?"의 정답(벡터 1위, BM25 불일치)이 `searchHybrid` 5위(0.0033)이고, "the"/"is"만 겹친 청크 넷이 0.016 안팎으로 앞선다. `ask`는 이 검색의 상위 5개만 쓴다. main 체크아웃의 `feat/ask-search-weights` 작업과 겹치는지 확인한다.
- **[낮음] 2026-11-12 D1에서 본 것:** (1) `mobile_rag_engine.dart`가 `RagError`만 `show`로 내보내, 앱이 `when`/`maybeWhen`과 `RagErrorUi.userFriendlyMessage`를 쓸 수 없다. (2) `pubspec.yaml`의 `flutter: ">=3.9.0"`이 실제 하한(Dart 3.9.2 = Flutter 3.35.3)과 다르다. (3) `name` 없이 넣은 문서는 `RagPassage.sourceName`이 null이라 `ask.md`와 README의 인용 출력 예제가 "null"을 찍는다. (4) `DocumentParser.parse`를 `MobileRag.initialize` 전에 부르면 `flutter_rust_bridge has not been initialized`가 난다.
- Windows `Native Tests`의 `ingest_ffi_traffic_test.dart` "Peak-RSS delta"가 가끔 실패한다(파일 경로가 UTF-8 경로보다 2MB 이상 적게 써야 하는데 0.7~0.8MB 차이만 났다. 11/1 `ci/quickstart-e2e`, 11/3 #125). 측정값이 흔들리는 테스트라 기준이나 측정 방식을 손봐야 한다.
- 성능 후보: `vector_math` 8-lane dot, HNSW 증분 삽입, prune 거리 캐싱, ef 상한, 짧은 문단 병합
- `lib/src/rust/api/mmap_store.dart` 잔존 파일 정리
- query/document 접두어 설정 (e5-small 계열을 권장 모델로 추가할 때)
- `AssembledContext.estimatedTokens` → `exactTokens` 이름 변경 (다음 breaking 배포 때)
- Xcode 27 + Flutter 3.35.5 (2026-11-06 Q1 확인 중 발견, 빈 `flutter create` 앱도 같다): (1) pod 배포 대상 macOS 10.15를 Xcode 27이 거부한다(12.0 이상). `setup`은 Podfile `platform`만 올리므로 pod target까지 맞추는 `post_install`을 넣을지 Q5에서 정한다. (2) Flutter의 release lipo 검사가 `ARCHS="arm64 x86_64"`를 아키텍처 하나로 읽어 universal macOS release 빌드가 실패한다. Flutter 쪽 문제라 문서(troubleshooting)에 우회법만 적을지 정한다. CI의 `macos-latest`가 Xcode 27로 바뀌면 macOS job이 함께 깨진다.
- 2026-11-07 추가 점검(회고 6절): C1 Xcode 27 Rust 소스 빌드 strip 문제(Q5에 넣을지 정한다, `rag_engine_flutter` 배포 필요), C2 Xcode 27 ↔ Flutter 3.47 요구와 CI Flutter 고정값(Q5), C3 직접 만든 Model Pack에서 setup이 멈추고 `--repair`가 모델을 덮어쓰는 문제(Q5), C4~C6과 낮음 문서 항목(새 문서 묶음 후보), inf/NaN 벡터 panic과 테스트 0개를 돌리는 Integration Tests job(가능성 있음, 착수 때 재현).
- 2026-11-06 점검의 낮음 항목: 부팅마다 기본 컬렉션 청크 전체를 UPDATE하는 backfill, 0.12 이하 DB의 dedup 해시 형식, `.vec` offset 정체성과 남는 `*.tmp-*` 파일, 동시 하이브리드 검색, Apple 정적 SQLite 심볼 노출(회고 2절 "낮음").
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

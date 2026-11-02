# 마일스톤

이 저장소에서 작업하는 모든 세션이 따르는 범위 문서다. 사용자가 합의한 범위만 진행한다.

## 규칙

1. **마일스톤 하나 = PR 하나.** 마일스톤 일부만 담은 PR은 사용자가 요청할 때만 연다.
2. **이 문서에 없는 작업은 PR로 올리지 않는다.** 새 작업이 생기면 먼저 이 문서에 마일스톤으로 적고 사용자 합의를 받는다.
3. **착수 전에 담당 세션과 브랜치를 적는다.** "손대는 파일"이 겹치는 마일스톤은 동시에 진행하지 않는다.
4. **범위를 바꿔야 하면 코드보다 이 문서를 먼저 고친다.** 예: 문서만 고치기로 한 마일스톤에서 코드 수정이 필요해진 경우.
5. **배포는 중단한다 (2026-11-02 사용자 지시: "배포 그만하고 마일스톤으로 쌓아").** 배포 마일스톤을 만들거나 버전을 올리지 않는다. 변경 기록은 `CHANGELOG.md`의 `## Unreleased`에 쌓고, 사용자가 배포를 다시 요청하면 그때 배포 마일스톤을 적는다.
6. **머지는 사용자가 한다.** 세션은 "PR 열림, CI 통과"에서 멈춘다.
7. **착수는 사용자가 마일스톤 번호로 지시할 때만 한다** (예: "M2 착수"). 순서는 아래 목록 순서를 기본으로 한다.
8. **모든 마일스톤의 완료 기준에 아래 네 가지를 넣는다 (2026-11-03 리뷰 뒤 합의).** 기존 검증이 새로 설치한 상태와 가짜 값만 봐서 맹점이 생겼기 때문이다. 작업을 마치기 전에 세션이 직접 확인하고, PR 본문의 같은 이름 절에 결과를 적는다. CI로 강제하거나 GitHub rules를 바꾸지 않는다(2026-11-03 사용자: 혼자 관리하는 패키지라 머지 부담만 커진다).
   1. **업그레이드 경로:** 마지막 배포 버전(0.22.3)이 남긴 DB와 파일 상태에서 시작해 확인한다.
   2. **실제 출력:** 가짜 값이 아니라 실제 엔진 출력으로 최소 한 번 확인한다.
   3. **사용하는 쪽 관점:** 여러 번 호출할 때와 토큰 비용을 확인한다.
   4. **주변 코드:** 수정과 맞물리는 코드를 읽고, 무엇이 깨질 수 있는지 PR에 적는다.

## 현재 상태 (2026-11-03)

- main: `e1da3b4` (#122 머지). 진행 중: M7.
- 마지막 배포: `mobile_rag_engine` 0.22.3. 그 뒤 변경은 모두 `## Unreleased`에 쌓여 있다.
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


### M7. LLM JSON 보완

- **담당:** 이 대화의 세션, 브랜치 `feat/m7-llm-json-fixes`
- **상태:** 진행 중 (2026-11-03 착수).

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

### M6. fingerprint 이전 검증 + 레시피 정정

- **상태:** 범위 초안, 합의 대기. M7 머지 뒤 착수한다. 착수는 사용자가 번호로 지시할 때만 한다.

**목표:** 맹점 1번을 고친다. 0.22.3의 3칸 fingerprint를 4칸으로 늘릴 때, 디스크의 모델이 그 DB를 만든 모델과 같은지 확인하지 않고 지금 파일의 해시를 붙이는 문제다.

**포함**
- `_extendFingerprintWithoutModelIdentity` 주변: 확장 전에 저장된 벡터와 지금 모델이 같은 모델인지 검증한다(예: 저장된 청크 몇 개를 다시 임베딩해 비교). 다르면 확장하지 않고 잠근다. 방식은 착수 때 이 문서에 먼저 정한다.
- `docs/guides/model_setup.md` 모델 전환 절의 "Later releases ... lock" 문단 정정.
- H1의 `H1_KNOWN_FAILING`에서 S2~S4를 지운다.

**제외:** asset 동기화 메모리(맹점 5번).

**완료 기준**
- H1-a S1~S4가 통과한다. 규칙 8의 네 항목. PR 하나, CI 통과.

**손대는 파일:** `lib/services/rag_engine.dart`(`_extendFingerprintWithoutModelIdentity` 주변), `docs/guides/model_setup.md`(모델 전환 절), `test/unit/**`, `CHANGELOG.md`, `.github/workflows/upgrade_e2e.yml`(`H1_KNOWN_FAILING` 한 줄), `docs/milestones.md`

> **겹치는 파일:** M7과 M6은 `CHANGELOG.md`·`upgrade_e2e.yml`·`test/unit/**`를 함께 고치므로 동시에 진행하지 않는다.

### M4. `rag.ask` 생성 브리지

- **상태:** 범위 초안. 합의 대기. M7 머지 뒤 착수한다 (M7에서 고친 결과 형식을 쓴다).

**목표:** 사용자가 넘긴 생성 함수(`Future<String> Function(prompt)` 또는 스트림)를 받아 검색 → 컨텍스트 조립 → 생성 → 인용 포함 답을 돌려주는 얇은 함수. LLM SDK는 넣지 않는다.

**포함**
- `ask(question, generate: ...)` API와 결과 타입(답, 사용한 청크/인용)
- 스트리밍 여부는 착수할 때 이 문서에 먼저 정한다.
- 가짜 생성 함수로 하는 단위 테스트, `CHANGELOG.md` 한 줄, 가이드

**제외**
- 특정 LLM 공급자 통합, 대화 기록 관리, 에이전트 루프

**완료 기준**
- 가짜 생성 함수로 질문 → 답 + 인용이 테스트로 검증된다.
- PR 하나, CI 통과.

**손대는 파일:** `lib/mobile_rag.dart`, 새 파일 `lib/services/ask.dart`(가칭), `lib/mobile_rag_engine.dart`(export), `test/unit/**`, `CHANGELOG.md`, `docs/guides/` 새 문서

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

### 아직 마일스톤으로 적지 않은 후보

착수하려면 위 형식으로 옮겨 적고 합의를 받는다.

- 성능 후보: `vector_math` 8-lane dot, HNSW 증분 삽입, prune 거리 캐싱, ef 상한, 짧은 문단 병합
- `lib/src/rust/api/mmap_store.dart` 잔존 파일 정리
- query/document 접두어 설정 (e5-small 계열을 권장 모델로 추가할 때)
- `AssembledContext.estimatedTokens` → `exactTokens` 이름 변경 (다음 breaking 배포 때)
- 레거시 자산 확인 비용 절감: 전체 sha256 대신 크기 + 앞뒤 1MiB만 해시한다(#118 fingerprint와 같은 방식). 시뮬레이터에서 KoEn 매 시작 약 250ms와, 확인 중 모델 크기의 약 2배 순간 메모리를 줄인다. M5 실측을 본 뒤 판단한다.

## 완료

### M3. LLM용 검색 결과 — 완료 (#121, 2026-11-03)

`RagSearchResult.toLlmJson({sourceNames})`가 `{"context", "results"}`를 돌려주고, 새 `RagSearchTool`(`lib/services/llm_tool.dart`)이 공급자 중립 tool 정의(`{name, description, parameters}`)와 `call`/`callJson`을 준다. 검색은 `searchHybridWithContext`를 쓰고, 잘못된 인자는 `{"error": ...}`로 돌려준다. 공급자 형식 변환은 `docs/guides/llm_tools.md`에 예제로만 뒀다. 검증은 가짜 검색 결과로 한 단위 테스트였다. 리뷰에서 실제 출력 기준 맹점(H1 맹점 2~4번)이 나와 M7로 고친다.

### M2. 레거시 자산 복사 버그 — 완료 (#120, 2026-11-02)

`modelAsset`/`tokenizerAsset` 복사본 옆에 `.asset-stamp`(asset 경로·길이·sha256)를 두고, asset과 다르면 원자적으로 다시 복사한다. 시뮬레이터에서 한 프로세스 안에 KoEn → MiniLM → KoEn → KoEn 순서로 초기화해 확인했다. 수정 전 코드로 대조하면 MiniLM 차례에도 KoEn 모델을 썼다. 매 시작 확인 비용은 시뮬레이터에서 KoEn 모델 약 250ms, MiniLM 약 150ms다.

### M1. 한국어 임베딩 레시피 — 완료 (#119, 2026-11-02)

`docs/guides/model_setup.md`에 KoEn-E5-Tiny 레시피를 추가했다. nDCG@10 MiniLM 0.014~0.059 → KoEn 0.762~0.866. iOS 시뮬레이터 엔진 실행 결과는 `docs/perf/multilingual-embedding/README.md` §5. 엔진 코드는 고치지 않았다.

## 보류

### R1. 다음 배포 (`mobile_rag_engine` 0.23.0 + `rag_engine_flutter` 0.22.0)

- **상태:** 보류 (2026-11-02, 규칙 5). 진행 중인 코드 작업과 열린 PR은 없다.
- 사용자가 배포를 다시 요청하면 그 시점의 main 기준으로 범위를 새로 적는다. 2026-11-02에 정리한 할 일은 남겨 둔다.
  - 버전: 루트 `pubspec.yaml`, `rust_builder/pubspec.yaml`, README·`docs/guides/quick_start.md`·`.github/workflows/quickstart_e2e.yml`의 버전 표기, lockfile
  - CHANGELOG: 두 파일의 `## Unreleased`를 버전 제목으로 바꾸고, `rust_builder/CHANGELOG.md`의 Chunking 중복 항목을 합치고, FRB 항목의 "FFI API is unchanged"를 #118에 맞게 고친다.
  - 순서: `rag_engine_flutter` 배포 → 루트 고정 → `mobile_rag_engine` 배포 → 태그 → pub 모드 Quick Start E2E. 배포는 사용자가 직접 한다.

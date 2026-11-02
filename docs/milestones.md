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

## 현재 상태 (2026-11-03)

- main: `7612899` (#120 머지). 진행 중: M3.
- 마지막 배포: `mobile_rag_engine` 0.22.3. 그 뒤 변경은 모두 `## Unreleased`에 쌓여 있다.
  - 512 토큰 truncation (#115)
  - HNSW 빌드와 검색 속도, 한국어 BM25, 한국어 청킹 속도 (#116)
  - flutter_rust_bridge 2.13 (#117)
  - 모델 파일 해시 fingerprint (#118)
  - 레거시 자산 복사본 갱신 (#120). Dart만 바뀌어 `rag_engine_flutter` 배포는 필요 없고, 다음 `mobile_rag_engine` 배포에 들어간다.
- 이 항목들은 다음 `rag_engine_flutter` 배포가 있어야 pub 사용자에게 동작한다. 배포 전까지 문서는 0.22.3 기준 안내를 유지한다 (M1 레시피가 그렇게 쓰여 있다).

## 마일스톤 목록 (착수 전 합의 필요)

### M3. LLM용 검색 결과

- **담당:** 세션 "RAG 엔진 아키텍처 방향", 브랜치 `feat/llm-tool-results`
- **상태:** PR 올림, 사용자 머지 대기 (2026-11-03). 방향 우선순위 2.

**설계 (착수 시 확정)**
- **결과 JSON:** `RagSearchResult.toLlmJson({sourceNames})`가 `{"context": ..., "results": [...]}`를 돌려준다.
  - `results`는 토큰 예산 안에 들어간 청크(`context.includedChunks`)만 담는다.
  - 항목 필드: `id`(인용 라벨 `"1"`, `"2"` …), `source_id`, `source_name`(알 때만), `chunk_id`, `chunk_index`, `score`(소수 셋째 자리), `text`
  - 키는 snake_case로 쓴다. LLM이 읽고 앱이 `source_id`/`chunk_id`로 원문에 되짚어 가게 한다.
  - `context`는 기존 `AssembledContext.text`다. 청크 metadata는 넣지 않는다(크기 때문).
- **tool:** 새 파일 `lib/services/llm_tool.dart`에 `RagSearchTool`을 둔다.
  - `definition`: 공급자 중립 형식 `{name, description, parameters}`. `parameters`는 JSON Schema로, `query`(string, 필수)와 `top_k`(integer, 1~`maxTopK`)를 받는다.
  - `call(Map arguments)`: 검색 결과 JSON을 돌려준다. 인자가 잘못되면 예외 대신 `{"error": ...}`를 돌려줘서 모델이 다시 시도하게 한다. 엔진 오류는 그대로 던진다.
  - `callJson(String)`: 인자를 문자열로 주는 SDK용. 결과도 문자열로 돌려준다.
  - 생성: `RagSearchTool.fromMobileRag(MobileRag)`, `RagSearchTool.fromCollection(CollectionRag)`. 검색은 `searchHybridWithContext`(BM25 포함)를 쓰고, `source_name`은 호출마다 `listSources()`로 채운다.
- 공급자 형식 변환(OpenAI `function`, Anthropic `input_schema`, Gemini `functionDeclarations`)은 가이드에 예제로만 둔다.
- `lib/mobile_rag.dart`와 `context_builder.dart`는 고치지 않는다(아래 손대는 파일에서 뺀다).

**목표:** 검색 결과를 어떤 LLM SDK에도 바로 넘길 수 있게 한다. 지금은 `RagSearchResult`(`chunks` + `AssembledContext.text`)와 `ContextBuilder.formatForPrompt`가 사람이 읽는 문자열만 준다.

**포함**
- 출처 인용이 가능한 구조화 결과: 청크별 출처 id, 청크 id, 점수, 본문을 담는 직렬화 형식(`toJson`). 기존 필드는 그대로 둔다.
- 검색을 LLM tool로 노출하기 위한 JSON Schema(이름, 설명, 파라미터)와, tool 호출 인자를 받아 검색을 실행하고 tool 결과 JSON을 돌려주는 함수.
- 공급자 형식(OpenAI/Anthropic/Gemini) 변환은 문서 예제로만 보여 준다.
- 단위 테스트, `CHANGELOG.md` 한 줄, 가이드 한 쪽.

**제외**
- LLM SDK 의존성 추가 (방향 원칙)
- 생성 호출 (M4)
- `AssembledContext.estimatedTokens` 이름 변경 같은 breaking change

**완료 기준**
- 예제 코드로 tool schema → 가짜 tool 호출 → 결과 JSON 왕복이 테스트로 검증된다.
- PR 하나, CI 통과.

**손대는 파일:** `lib/services/source_rag_service.dart`(`RagSearchResult`), 새 파일 `lib/services/llm_tool.dart`, `lib/mobile_rag_engine.dart`(export), `test/unit/**`, `CHANGELOG.md`, 새 문서 `docs/guides/llm_tools.md`, `README.md`(문서 목록에 한 줄), `docs/milestones.md`

### M4. `rag.ask` 생성 브리지

- **상태:** 범위 초안. 합의 대기. M3 머지 뒤에 착수한다 (M3 결과 형식을 쓴다).

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

> **겹치는 파일:** M3와 M4는 `CHANGELOG.md`·`lib/mobile_rag_engine.dart`를 함께 고치므로 동시에 진행하지 않는다.

### 아직 마일스톤으로 적지 않은 후보

착수하려면 위 형식으로 옮겨 적고 합의를 받는다.

- 성능 후보: `vector_math` 8-lane dot, HNSW 증분 삽입, prune 거리 캐싱, ef 상한, 짧은 문단 병합
- `lib/src/rust/api/mmap_store.dart` 잔존 파일 정리
- query/document 접두어 설정 (e5-small 계열을 권장 모델로 추가할 때)
- `AssembledContext.estimatedTokens` → `exactTokens` 이름 변경 (다음 breaking 배포 때)
- 레거시 자산 확인 비용 절감: 전체 sha256 대신 크기 + 앞뒤 1MiB만 해시한다(#118 fingerprint와 같은 방식). 시뮬레이터에서 KoEn 매 시작 약 250ms와, 확인 중 모델 크기의 약 2배 순간 메모리를 줄인다. M5 실측을 본 뒤 판단한다.

## 완료

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

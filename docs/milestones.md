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

## 현재 상태 (2026-11-02)

- main: `0979f57` (#119 머지). 열린 PR 없음. 진행 중: M2.
- 마지막 배포: `mobile_rag_engine` 0.22.3. 그 뒤 변경은 모두 `## Unreleased`에 쌓여 있다.
  - 512 토큰 truncation (#115)
  - HNSW 빌드와 검색 속도, 한국어 BM25, 한국어 청킹 속도 (#116)
  - flutter_rust_bridge 2.13 (#117)
  - 모델 파일 해시 fingerprint (#118)
- 이 항목들은 다음 `rag_engine_flutter` 배포가 있어야 pub 사용자에게 동작한다. 배포 전까지 문서는 0.22.3 기준 안내를 유지한다 (M1 레시피가 그렇게 쓰여 있다).

## 마일스톤 목록 (착수 전 합의 필요)

### M2. 레거시 자산 복사 버그

- **담당:** 세션 "RAG 엔진 아키텍처 방향", 브랜치 `fix/legacy-asset-copy`
- **상태:** PR 올림, 사용자 머지 대기 (2026-11-02)

**방식 (착수 시 합의):** 복사할 때 대상 파일 옆에 기록 파일 `<대상>.asset-stamp`을 남긴다. 여기에는 asset 경로, 길이, sha256을 적는다. 시작할 때마다 asset을 읽은 뒤 다음 중 하나면 원자적으로(임시 파일 → rename) 다시 복사한다.
- 기록 파일이 없다 (이 수정 이전에 복사된 파일 포함)
- asset 경로가 다르다
- 길이가 다르다
- 대상 파일 길이가 기록과 다르다
- 위 조건이 모두 같으면 sha256을 비교하고(UI isolate를 막지 않게 별도 isolate에서), 다르다

비용은 매 시작마다 asset 로드와 sha256 한 번이다.

**검증 결과 (2026-11-02, iPhone 16 Pro 시뮬레이터):**
- `flutter test`는 실행이 끝나면 앱을 지운다. 그래서 한 프로세스 안에서 KoEn → MiniLM → KoEn → KoEn 순서로 초기화하고 해제했다. 네 번 모두 통과했고, KoEn 차례에는 한국어 질의의 top-1이 기대한 문서였다.
- MiniLM 차례에서 기록 파일이 KoEn에서 MiniLM으로 바뀌었다. fingerprint의 모델 해시도 `fd688b…`에서 `e9246d…`로 바뀌었다.
- 대조 실행: 엔진만 수정 전 코드로 돌리면, MiniLM 차례의 fingerprint가 KoEn 해시로 남는다. 남아 있던 KoEn 모델로 임베딩한 것이다.
- 복사본이 이미 최신일 때 매 시작 확인 비용(Mac 위 시뮬레이터라 실기기는 다를 수 있다):

  | 파일 | 크기 | 확인 시간 |
  |---|---|---|
  | KoEn 모델 | 38MB | 약 250ms |
  | MiniLM 모델 | | 약 150ms |
  | 토크나이저 | | 3~20ms |

**문제:** `RagEngine._copyAssetToFile`(`lib/services/rag_engine.dart`)은 파일이 이미 있으면 복사하지 않는다. 토크나이저는 고정 이름 `tokenizer.json`으로, 모델은 asset 파일 이름으로 복사한다. 그래서 토크나이저를 바꾸거나, 앱 업데이트에서 같은 이름의 모델 파일 내용을 바꿔도 옛 파일을 계속 쓴다. M1 검증 중 시뮬레이터에서 KoEn 실행 뒤 MiniLM을 실행하니 KoEn 토크나이저가 남아 `Gather` 범위 오류로 실패했다. Model Pack 경로는 해시별 디렉터리라 영향 없다.

**포함**
- `modelAsset`/`tokenizerAsset` 경로에서 asset 내용이 바뀌면 다시 복사한다 (위 방식).
- 매 시작 비용(asset 로드 + sha256)을 시뮬레이터에서 잰다.
- 단위 테스트: 같은 이름의 asset 내용이 바뀐 경우, 토크나이저만 바뀐 경우.
- `CHANGELOG.md` `## Unreleased`에 한 줄.

**제외**
- Model Pack 경로 변경
- 오래된 복사본 정리(디스크 회수)는 필요하면 따로 적는다.

**완료 기준**
- 시뮬레이터에서 KoEn → MiniLM 순서로 앱을 재설치 없이 실행해 둘 다 동작한다.
- PR 하나, CI 통과.

**손대는 파일:** `lib/services/rag_engine.dart`(자산 복사 부분), 새 파일 `lib/src/internal/asset_file_sync.dart`, `test/unit/**`(새 테스트), `CHANGELOG.md`(`## Unreleased`), `docs/guides/model_setup.md`(Model Pack 권장 이유 문구만)

### M3. LLM용 검색 결과

- **상태:** 범위 초안. 합의 대기. (방향 우선순위 2)

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

**손대는 파일:** `lib/services/source_rag_service.dart`(결과 타입), `lib/services/context_builder.dart`, 새 파일 `lib/services/llm_tool.dart`(가칭), `lib/mobile_rag.dart`(공개 API), `lib/mobile_rag_engine.dart`(export), `test/unit/**`, `CHANGELOG.md`, `docs/guides/` 새 문서

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

> **겹치는 파일:** M2와 M5는 `docs/guides/model_setup.md`를, M3와 M4는 `lib/mobile_rag.dart`·`CHANGELOG.md`·`lib/mobile_rag_engine.dart`를 함께 고친다. 이 쌍은 동시에 진행하지 않는다. `CHANGELOG.md`는 M2·M3·M4가 모두 고치므로 한 번에 하나씩 진행한다.

### 아직 마일스톤으로 적지 않은 후보

착수하려면 위 형식으로 옮겨 적고 합의를 받는다.

- 성능 후보: `vector_math` 8-lane dot, HNSW 증분 삽입, prune 거리 캐싱, ef 상한, 짧은 문단 병합
- `lib/src/rust/api/mmap_store.dart` 잔존 파일 정리
- query/document 접두어 설정 (e5-small 계열을 권장 모델로 추가할 때)
- `AssembledContext.estimatedTokens` → `exactTokens` 이름 변경 (다음 breaking 배포 때)

## 완료

### M1. 한국어 임베딩 레시피 — 완료 (#119, 2026-11-02)

`docs/guides/model_setup.md`에 KoEn-E5-Tiny 레시피를 추가했다. nDCG@10 MiniLM 0.014~0.059 → KoEn 0.762~0.866. iOS 시뮬레이터 엔진 실행 결과는 `docs/perf/multilingual-embedding/README.md` §5. 엔진 코드는 고치지 않았다.

## 보류

### R1. 다음 배포 (`mobile_rag_engine` 0.23.0 + `rag_engine_flutter` 0.22.0)

- **상태:** 보류 (2026-11-02, 규칙 5). 진행 중인 코드 작업과 열린 PR은 없다.
- 사용자가 배포를 다시 요청하면 그 시점의 main 기준으로 범위를 새로 적는다. 2026-11-02에 정리한 할 일은 남겨 둔다.
  - 버전: 루트 `pubspec.yaml`, `rust_builder/pubspec.yaml`, README·`docs/guides/quick_start.md`·`.github/workflows/quickstart_e2e.yml`의 버전 표기, lockfile
  - CHANGELOG: 두 파일의 `## Unreleased`를 버전 제목으로 바꾸고, `rust_builder/CHANGELOG.md`의 Chunking 중복 항목을 합치고, FRB 항목의 "FFI API is unchanged"를 #118에 맞게 고친다.
  - 순서: `rag_engine_flutter` 배포 → 루트 고정 → `mobile_rag_engine` 배포 → 태그 → pub 모드 Quick Start E2E. 배포는 사용자가 직접 한다.

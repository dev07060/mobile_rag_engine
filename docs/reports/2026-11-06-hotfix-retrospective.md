# 0.23.0까지의 핫픽스 회고와 잠재 문제 점검 (2026-11-06)

배포를 멈추고 0.23.0까지의 핫픽스 이력을 돌아본 기록이다. 같은 계열의 문제가 더 남아 있는지 코드로 찾았고, 잘된 점도 함께 적었다. 이 문서는 진단 기록이다. 수정은 하지 않았다. 고칠 항목은 `docs/milestones.md`에 Q1~Q5 마일스톤으로 옮겼다(2026-11-06 사용자 합의).

- 기준: main `11744c9` (0.23.0 / `rag_engine_flutter` 0.22.0 발행 상태)
- 방법:
  - CHANGELOG 두 개와 git 이력으로 핫픽스를 분류했다.
  - 분류마다 코드를 읽어 같은 계열의 잠재 문제를 찾았다.
  - 의심 지점의 일부는 스크래치 복사본의 임시 테스트로 재현했다. 저장소는 바꾸지 않았다.
- 확인 수준 표기:
  - **[재현]** 실행해서 확인했다.
  - **[추적]** 코드 경로를 끝까지 따라가 확인했다.
  - **[추정]** 근거는 있지만 실행하지 않았다.
- 관련 PR: #128(0.22.x 알려진 문제 CHANGELOG), #129(배포 보류 규칙), #130(A1 문서 정정).

## 1. 핫픽스 이력에서 보이는 패턴

| # | 패턴 | 대표 사례 | 공통 원인 |
|---|---|---|---|
| P1 | 배포 산출물과 버전 어긋남 | 0.11.0+1 README, 0.12.0+1 엔진 버전, 0.18.1 native 제약 누락, 0.19.1 `lib/models` 누락, 0.20.1 "Rust 불필요" 오기, e42cc3f 하네스 포함 | 배포 아카이브를 그대로 설치해 보지 않음 |
| P2 | release 빌드와 스토어 제출에서만 실패 | 0.22.2: R8, iOS 심볼 strip, 16 KB 정렬, privacy manifest | debug 빌드로만 확인 |
| P3 | 새 앱 온보딩 | 0.22.1 `pod install` 실패 | README를 새 앱에 그대로 따라 해 보지 않음 |
| P4 | 디스크에 남은 상태의 재사용과 업그레이드 | 0.19.3/0.20.1 `processing` 고착, 0.21.0 `clearAllData` 잔존 파일, dev.12 락 경합, 0.22.3 삭제 청크 부활과 `database is locked`, 0.23.0 M6·M2·M8 | 새로 설치한 상태로만 검증 |
| P5 | 문자 수와 토큰 수의 경계 | 0.11.0 문자 수 기준 truncation → 0.23.0에서 512 토큰으로 수정, "청크가 토큰 한도에 맞는다" 두 번 수정(0.22.3, 0.23.0), 한국어 BM25 조사 | ASCII와 영어로만 테스트 |
| P6 | 가짜 값으로 놓친 출력 계약 | M7: RRF 점수 반올림, 본문 중복, 인용 id 충돌 | 단위 테스트가 가짜 점수를 씀 |
| P7 | 같은 기능의 dev 연타 | 0.21.0-dev.2~5: HNSW 바이너리 형식 버그 네 번 연속 | 형식 왕복(쓰기→읽기) 테스트 부재 |
| P8 | Windows 파일 잠금 | mmap 파일 삭제 거부, `close_db_pool` 뒤 락 | 비동기로 닫히는 핸들 |

**배포 속도:** 2026-11-01~02 이틀 동안 0.21.0, 0.22.0, 0.22.1, 0.22.2, 0.22.3 다섯 번을 배포했다. 0.22.1~0.22.3 세 번은 직전 배포의 문제를 고친 것이다.

**메타 원인 두 가지.**
1. **검증이 "깨끗한 조건"에만 있었다.** 새 DB, 가짜 값, debug 빌드, ASCII 텍스트, git 모드 설치만 확인했다. 규칙 8(업그레이드 경로·실제 출력)과 H1 하네스가 앞의 두 조건은 메웠다. 나머지 세 조건(release 빌드, CJK·정규화 텍스트, 배포 아카이브)은 아직 비어 있다.
2. **보고된 사례만 고치고 같은 계열은 찾지 않았다.** 그래서 같은 문제가 되풀이됐다.
   - "토큰 한도" 문제는 plain → markdown 본문 → (아래 B1) Header Path 접두어로 세 번째 구멍이 남았다.
   - M2 수정이 문서에 있는 운영 배포 경로를 새로 깨뜨렸다(아래 A1).

## 2. 새로 찾은 잠재 문제

### 높음

**A1. [추적, 0.23.0 회귀] asset 없이 배포하고 모델을 내려받는 문서 경로가 0.23.0에서 초기화 실패**
- 0.22.3은 대상 파일이 있으면 복사를 건너뛰었다.
- M2(#120) 이후 `syncAssetToFile`(`lib/src/internal/asset_file_sync.dart:33`)은 파일을 확인하기 전에 항상 `rootBundle.load(assetPath)`를 한다.
- `docs/guides/release_build.md:19-37`대로 pubspec에서 모델 asset을 뺀 운영 빌드는 `MobileRag.initialize`에서 "Unable to load asset"으로 실패한다. debug(번들 있음)는 정상이다. 그래서 P2 계열이다.
- `RagConfig`에 `preparedModelPath`가 있지만 `MobileRag.initialize`로는 넘길 수 없다.
- 같은 문서가 Windows에서 `getApplicationDocumentsDirectory()`를 쓰라고 안내하지만, 엔진은 0.22.0부터 AppSupport를 쓴다(`troubleshooting.md:137`도 같다).

**A2. [재현] 일본어·중국어 압축에서 Rust panic**
- `compression_utils.rs:134`의 `result[..=pos]`에서, `pos`는 `。`(3바이트)가 시작하는 위치다. 그래서 문자 중간에서 잘린다.
- `"東京は大きい。大阪も大きい。京都は古い"`, `maxChars=12`로 `byte index 19 is not a char boundary`가 났다.
- 이 경로를 쓰는 공개 API: `PromptCompressor.compress`, `ContextBuilder.buildWithCompression`의 잘라내기 단계.
- 같은 함수가 `.`마다 문장을 나누고 `" "`로 다시 이어서, `3.14`가 `3. 14`, `v1.2.3`이 `v1. 2. 3`이 된다. 둘 다 P5 계열이다.

**A3. [재현 + 추적] `clearAndRestart` 뒤 같은 문서를 다시 추가하면 영원히 `DuplicateInProgress`**
- `acknowledge_and_clear_embeddings`(`migration_meta.rs:610`)는 청크만 지우고 source 행은 `completed`로 둔다.
- 다시 추가할 때의 경로:
  1. "completed + 청크 0개"는 `ResetAndResume`으로 판정된다.
  2. `clear_source_chunks`는 상태를 바꾸지 않는다.
  3. `claim_source_for_ingestion`(`source_rag.rs:1025`)은 `pending`/`failed`만 잡으므로 실패한다.
  4. 결과는 `DuplicateInProgress`다.
- 문서가 약속한 복구 경로(재색인)가 막힌다. 청크를 0개 만든 문서를 다시 추가할 때도 같다. P4 계열이다.

**A4. [재현 + 추적] 비하이브리드 `search()`가 다른 컬렉션의 인덱스로 검색해 빈 결과**
- `search_chunks_in_collection`(`source_rag.rs:2829`)은 활성 컬렉션이 다르면 `HNSW_BUILDER`에 다시 빌드한다. 하지만 이미 로드된 `HNSW_INDEX`를 비우지 않는다(`clear_hnsw_index`는 0개일 때만 호출).
- `search_hnsw_slice`(`hnsw_index.rs:194`)는 `HNSW_INDEX`를 먼저 본다. 그래서 컬렉션 B를 A의 그래프로 검색하고, `collection_id = B` 필터가 모든 결과를 버린다.
- `sourceIds` 없이 `search()`를 호출하면(`source_rag_service.dart:1182`) 이 경로를 탄다.
- `reembedAll` 뒤에도 이전 그래프로 검색한다. P4 계열이다.

**A5. [추정] `flutter_onnxruntime: ^1.8.0` 하한에 알려진 운영 결함이 있음**
- 해당 패키지의 CHANGELOG에 따르면 1.8.0~1.8.2는 App Store Connect 업로드가 ITMS-90208로 거절된다(1.8.3에서 수정).
- 저장소 lockfile(`pubspec.lock:209`, `example/pubspec.lock`)은 1.8.0이다. 그래서 CI는 1.8.0을 검사하고, 새 사용자는 1.9.x를 받는다. lock이 있는 기존 사용자는 1.8.0에 남는다.
- 버전 범위를 직접 확인할 필요가 있다. P2 계열이다.

### 중간

| # | 내용 | 확인 | 계열 |
|---|---|---|---|
| B1 | markdown 청크 예산이 본문만 센다. 실제 임베딩 입력은 `"Header Path: …\n" + content`(`ingest_session.rs:174`)라서 헤더 3단이면 531~532토큰이 되고 뒤 약 20토큰이 잘린다. 테스트도 `chunk.content`만 검사한다. | 재현 | P5 (토큰 한도 세 번째 구멍) |
| B2 | `reembedAll`(`rag_engine.dart:1076`)은 `chunk.content`를 임베딩한다. 색인할 때는 `render_context_text`를 쓴다. 모델 교체 뒤 재임베딩하면 markdown 청크의 헤더 문맥이 사라지고, 다음 fingerprint 확장의 표본 검사가 잘못 잠글 수 있다. | 추적 | P4·P5 |
| B3 | 재임베딩 게이트가 stored == current이면 `pending`과 청크 태그를 무시한다. A→B 재임베딩이 50%에서 끊기고 앱이 A로 돌아가면 잠금 없이 벡터 절반이 B 모델 것으로 남는다. 세 번째 모델 C로 바꾸면 "cannot retarget"이 나서 `clearAndRestart`밖에 없고, 그러면 A3에 걸린다. | 추적 | P4 (M6와 같은 모델 정체성 구멍) |
| B4 | 이미 있는 문서를 다시 `addDocument`하면 `SkipCompleted`에서 같은 값으로 UPDATE해도 generation이 오른다. 매 실행마다 번들 문서를 다시 넣는 앱은 첫 검색마다 BM25와 HNSW를 전부 다시 빌드한다. | 재현 | P4 |
| B5 | 임베딩 worker를 dispose하는 중에 보낸 `embed()`는 응답을 영원히 기다린다(`embedding_service.dart:113`, timeout 없음). 그 source는 `processing`으로 남는다. 같은 프로세스에서 다시 초기화하면 복구 단계를 건너뛰므로 앱을 재시작할 때까지 다시 추가할 수 없다(0.20.1 버그가 프로세스 안에서 재발). `MobileRag.initialize` 동시 호출을 막는 장치도 없다. | 추적 | P4 |
| B6 | `RagEngine.dispose`는 static이라 인스턴스의 500ms debounce 타이머를 취소하지 못한다. dispose 직후 처리되지 않은 `RagError`가 나고, 다른 DB로 다시 초기화하면 옛 경로로 HNSW를 저장할 수 있다. | 추정 | P4 |
| B7 | `clearAllData`는 기본 컬렉션의 warmup만 기다린다. 다른 컬렉션의 ingest가 계속 돌다가, 새 DB에서 다시 1부터 시작하는 source id에 옛 청크를 쓸 수 있다. | 추정 | P4·P8 |
| B8 | BM25에 Unicode 정규화가 없다. NFD 한글 문서(macOS 파일, 일부 PDF), 전각 `ＲＡＧ`, 합자 `ﬁ`는 BM25(기본 가중치 0.8)에서 매칭되지 않는다. 중복 검사 해시도 같은 영향을 받는다. | 재현 | P5 |
| B9 | 한국어 bigram은 순수 한글 단어만 처리한다. `RAG는`, `API를`, `2024년`, `iPhone15에서`와 한 음절 명사 + 조사(`앱을`)는 어간 질의와 매칭되지 않는다. | 재현 | P5 (0.23.0 수정의 빈틈) |
| B10 | `MobileRag.search`의 `similarity`는 `sourceIds`를 주면 RRF 값(최대 약 0.016)이고, 안 주면 코사인이다. `> 0.5`로 거르면 필터를 줬을 때만 결과가 전부 사라진다. | 추적 | P6 (M7와 같은 원인) |
| B11 | `adjacentChunks > 0`이면 결과가 (source_id, chunk_index) 순으로 정렬돼 relevanceFirst가 깨진다. 예산이 빠듯하면 1위 결과가 빠질 수 있다. | 추적 | P6 |
| B12 | 인용 파싱(`ask.dart:144`)이 `［１］`, `【1】`, `[1、2]`, `[1-3]`을 놓친다. 앞의 셋은 한·중·일 LLM 출력에 흔하다. 코드 안의 `items[2]`는 인용으로 잘못 잡힌다. | 재현 | P6 |
| B13 | ask와 tool의 `tokenBudget`은 임베딩 tokenizer 단위다. UNK로 합쳐지는 텍스트(태국어 32자=1토큰, 이모지 10개=1토큰)는 LLM 기준 몇 배가 된다. `PromptCompressor`는 아직 char/4 근사다. | 재현 | P5 |
| B14 | setup의 Podfile 패치가 `platform :ios, '13.0' # 주석` 같은 줄에서 매칭되지 않는다. 그러면 새 줄을 하나 더 넣고 기존 13.0 줄을 남기는데, `--check`는 통과한다. `use_frameworks! linkage: :dynamic` 형태도 그대로 둔다(`apple_host_configurator.dart:117-170`). | 재현 | P3 |
| B15 | 배포 아카이브를 그대로 설치하는 검증이 발행 전에 없다(git 모드는 `.pubignore`가 빠진 상태로 돈다). Quick Start E2E의 PR 경로 트리거에 `pubspec.yaml`, `.pubignore`, `rust_builder/windows/**`, `cargokit/**`, `rust/**`가 빠져 있다. iOS Release 바이너리는 한 번도 실행되지 않는다(심볼 3개만 검사). | 추적 | P1·P2 |
| B16 | Android release 검증이 x86_64 APK뿐이다. 16 KB 정렬 검사의 arm64 분기는 항상 비어 있다. arm64 release와 AAB는 빌드되지 않는다. | 추적 | P2 |

### 낮음

- **엔진 버전:** DB에 기록되는 엔진 버전이 계속 `0.8.0`이다(`Cargo.toml` version → `migration_meta.rs:51`). 나중에 버전으로 마이그레이션을 나누면 틀린다. P1 계열이다.
- **문서·example 버전 표기:**
  - `troubleshooting.md:14,36`이 `^0.22.2`를 권한다. 0.x 캐럿이라 따르면 0.23.0을 받지 못한다.
  - 배포되는 example은 `assets/`를 선언하는데, `.pubignore`가 그 폴더를 뺀다.
- **[추정] Apple 정적 링크와 SQLite 심볼 충돌:** 정적 링크 + `-export_dynamic` 때문에 내장 SQLite 심볼이 앱 전체에 노출된다. 다른 정적 SQLite(drift 등)와 충돌할 수 있다.
- **부팅마다 전체 UPDATE:** 부팅마다 기본 컬렉션 청크 전체를 UPDATE하는 backfill이 돈다(`source_rag.rs:824`, 값 비교 없음).
- **0.12 이하 DB의 중복:** 0.12 이하 DB는 dedup 해시 형식이 달라 같은 문서를 다시 넣으면 중복된다.
- **`.vec` offset과 임시 파일:**
  - `.vec` offset에는 정체성 정보가 없다. DB는 남고 `.vec`만 잃으면 옛 행이 새 벡터를 가리킨다.
  - asset 복사가 중단되면 `*.tmp-*` 파일이 남고 아무도 지우지 않는다.
- **offset 단위가 공개 API에서 섞임:** 공개 `SemanticChunk.startPos`/`endPos`는 UTF-8 바이트 offset인데 문서에 없다. Dart `substring`에 쓰면 한글에서 틀린다.
- **markdown 구조 오인식:**
  - `#여행` 해시태그와 `#include`를 헤더로 인식한다.
  - `~~~` 펜스를 모른다.
  - `.MD` 대소문자를 경로마다 다르게 처리한다.
- **[추정] 동시 하이브리드 검색:** 서로 다른 컬렉션을 동시에 하이브리드 검색하면 전역 HNSW·BM25를 공유해서 결과가 비거나 나빠질 수 있다.

**찾지 못한 것:** release 빌드에서 사용자 텍스트나 임베딩이 로그로 나가는 곳(0.20.1 계열)은 없었다.

## 3. 잘된 점 (유지할 것)

**프로세스**
1. **규칙 8과 H1 Upgrade E2E.** 수정 전에 맹점을 먼저 재현하고, `H1_KNOWN_FAILING`으로 "고쳐졌는데 목록을 안 지운 경우"까지 실패시킨다. 그래서 M6·M7이 실제로 고쳐졌다는 증거가 남았다.
2. **Quick Start E2E가 실제 사용자 조건에 가깝다.** Rust를 숨긴 새 앱에서 Android R8 release, macOS archive, iOS archive의 심볼·privacy manifest, Windows release를 실행한다. 0.22.1·0.22.2 계열이 다시 나오는 것을 막는다.
3. **마일스톤 문서와 배포 보류.** 범위, 손대는 파일, 완료 기준을 먼저 적는 방식이 자리 잡았다. 11/03 이후 M2~M8을 0.23.0 한 번으로 묶어 배포했다.
4. **CHANGELOG 품질.** 사용자에게 보이는 증상, 영향받는 조건, 마이그레이션 비용을 구체적으로 적는다.

**릴리스 엔지니어링**
1. **precompiled binary.** crate hash를 로컬에서 다시 계산한 값이 `precompiled_…` 릴리스와 일치한다. 11개 target 모두 서명돼 있다.
2. **lockstep 강제.** `rag_engine_flutter` 정확 고정과 `flutter_rust_bridge` 2.13.0 양쪽 고정으로 0.18.1 같은 어긋남을 구조적으로 막는다.
3. **깨끗한 아카이브.** 모델, 로그, tmp, research, 하네스가 빠졌고, PrivacyInfo, proguard, cargokit, build.rs는 들어 있다. 크기는 root 2 MB, native 279 KB다.

**상태 관리**
1. **0.22.3 이후 인덱스 재사용 키.** (index generation, data generation, 파일 이름)으로 판단하고, generation을 행보다 먼저 읽어 경합을 막는다.
2. **파일 쓰기 순서.** HNSW와 asset은 tmp + rename으로 쓰고, asset stamp는 먼저 지우고 마지막에 쓴다. `.vec`는 SQLite commit 전에 flush하고 CRC 스캔으로 복구한다.
3. **검색 핸들과 fingerprint.**
   - `SearchHandle`은 generation을 앞뒤로 확인하고 한 번 재시도한다.
   - fingerprint는 `finalize`가 부분 실행을 거부하고, `extend`를 단일 트랜잭션으로 처리하며, M6 표본 재임베딩 검사를 거친다.

**텍스트와 출력**
1. **plain-text 토큰 예산.** 추정 뒤 정확한 수로 다시 확인하고, 조밀한 한국어로 테스트한다.
2. **안전한 excerpt.** `maxBytes`라는 이름이 명확하고, 문자 경계에서 안전하게 자른다.
3. **toLlmJson 계약.** 상대 점수, 호출 간 이어지는 인용 id, 본문 한 번만 넣기를 지킨다.
4. **DOCX reader.** `xml:space`, 표를 제자리에 두기, 삭제된 revision 건너뛰기, zip bomb 방어가 탄탄하다.
5. **결정적인 RRF.** 두 경로의 중복을 제거하고, 동점은 결정적으로 정렬한다.

## 4. 마일스톤 묶음

한 마일스톤 = PR 하나 원칙에 맞춰 손대는 파일 기준으로 묶었다. 순서는 사용자 영향 순이다. 범위와 완료 기준은 `docs/milestones.md`의 Q0~Q5에 있다.

| 묶음 | 항목 | 주로 손대는 곳 |
|---|---|---|
| Q1 0.23.0 회귀와 의존성 | A1, A5, 문서의 Windows 경로·`^0.22.2` 표기, example assets | `asset_file_sync.dart`, `mobile_rag.dart`, `pubspec.yaml`, `docs/guides/*` |
| Q2 상태 수명주기 | A3, A4, B3, B4, B5, B6, B7 (+ H1 하네스에 `clearAndRestart` → 재색인, 컬렉션 전환 검색 시나리오 추가) | `source_rag.rs`, `migration_meta.rs`, `ingest_session.rs`, `rag_engine.dart`, `embedding_service.dart` |
| Q3 텍스트 경계 | A2, B1, B2, B8, B9, offset 문서화, markdown 오인식 | `compression_utils.rs`, `semantic_chunker.rs`, `bm25_search.rs`, `rag_engine.dart`(reembed 입력) |
| Q4 출력 계약 | B10, B11, B12, B13 | `source_rag_service.dart`, `ask.dart`, `context_builder.dart`, `source_rag.rs`(assembly) |
| Q5 배포 검증 보강 | B14, B15, B16, 엔진 버전 기록 | `apple_host_configurator.dart`, `.github/workflows/*`, `Cargo.toml` |

Q2와 Q3는 둘 다 `source_rag.rs`를 건드리므로 동시에 진행하지 않는다(규칙 3).

## 5. 프로세스 제안

1. **수정할 때 같은 계열을 먼저 찾는다.** PR 본문 "맞물리는 코드" 절에 "같은 원인으로 다른 곳에서도 깨질 수 있는가"를 적는다. 예: 토큰 한도를 고칠 때는 임베딩 입력을 만드는 모든 경로(`render_context_text`, reembed, 표본 검사)를 본다.
2. **테스트 텍스트에 CJK, NFD 한글, 전각, 이모지, 소수점을 기본으로 넣는다.** A2, B8, B9, B12는 모두 ASCII 테스트에서 통과하던 것들이다.
3. **기존 문서 경로를 회귀 목록으로 둔다.** 가이드에 있는 코드 예제(특히 `release_build.md`의 운영 배포 흐름)를 E2E 시나리오나 최소한 단위 테스트로 묶는다. A1은 가이드를 아무도 실행하지 않아서 생겼다.
4. **발행 전에 `pub publish --dry-run` 아카이브를 path 의존성으로 설치해 E2E를 돌린다.** 발행 뒤 pub 모드 확인은 최종 점검으로만 둔다(#129의 규칙 5-3과 같은 방향).
5. **R1 순서 6(`v0.23.0` 태그, pub 모드 Quick Start E2E, `no_rust_repro.yml` 0.23.0)이 아직 남아 있다.** 원격 태그는 `v0.22.3`까지만 있다.

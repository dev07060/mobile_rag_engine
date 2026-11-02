# 마일스톤

이 저장소에서 작업하는 모든 세션이 따르는 범위 문서다. 사용자가 합의한 범위만 진행한다.

## 규칙

1. **마일스톤 하나 = PR 하나.** 마일스톤 일부만 담은 PR은 사용자가 요청할 때만 연다.
2. **이 문서에 없는 작업은 PR로 올리지 않는다.** 새 작업이 생기면 먼저 이 문서에 마일스톤으로 적고 사용자 합의를 받는다.
3. **착수 전에 담당 세션과 브랜치를 적는다.** "손대는 파일"이 겹치는 마일스톤은 동시에 진행하지 않는다.
4. **범위를 바꿔야 하면 코드보다 이 문서를 먼저 고친다.** 예: 문서만 고치기로 한 마일스톤에서 코드 수정이 필요해진 경우.
5. **배포는 사용자가 요청할 때만 한다.** 변경 기록은 `CHANGELOG.md`의 `## Unreleased`에 쌓는다.
6. **머지는 사용자가 한다.** 세션은 "PR 열림, CI 통과"에서 멈춘다.

## 현재 상태 (2026-11-02)

- main: `4e20e3b` (#118 머지). 열린 PR 없음.
- `## Unreleased`에 쌓인 항목은 모두 다음 `rag_engine_flutter` 배포가 있어야 동작한다.
  - 512 토큰 truncation (#115)
  - HNSW 빌드와 검색 속도, 한국어 BM25, 한국어 청킹 속도 (#116)
  - 모델 파일 해시 fingerprint (#118)
  - flutter_rust_bridge 2.13 (#117)

## 진행 중

### M1. 한국어 임베딩 레시피

- **담당:** 세션 "RAG 엔진 아키텍처 방향", 브랜치 `docs/korean-embedding`
- **상태:** PR 올림, 사용자 머지 대기 (2026-11-02)

**목표:** 사용자가 문서만 보고 기본 모델(all-MiniLM-L6-v2)을 KoEn-E5-Tiny로 바꿔 한국어 검색을 쓸 수 있게 한다. 엔진 코드는 고치지 않는다.

**포함**
- `docs/guides/model_setup.md`에 한국어 모델 레시피를 추가한다.
  - 모델 파일과 토크나이저를 받는 곳, 배치 위치, `RagModelPack` 설정
  - 측정 수치: nDCG@10 MiniLM 0.014~0.059 → KoEn 0.757~0.866, 배포 크기 39MB
  - 기존 DB에서 모델을 바꾸면 fingerprint 잠금이 걸린다는 점과 `reembedAll()` 사용법
- 측정 기록 커밋: `docs/perf/multilingual-embedding/`, `research/multilingual_embedding/`
- 계획 문서 `docs/superpowers/plans/2026-11-02-multilingual-embedding-preset.md` 정정
  - 옛 수치 +0.109를 청크 단위 측정값으로 바꾼다.
  - 프리셋 레지스트리 계획을 철회한다고 적는다.

**제외**
- **query/document 접두어 설정:** KoEn은 접두어 유무에 따른 점수 차이가 ±0.002라 필요 없다. e5-small 계열을 권장 모델로 추가할 때 다시 검토한다.
- 프리셋 레지스트리, `setup` 명령에 모델 선택 옵션 추가
- Dart·Rust 코드 변경. KoEn이 현재 코드로 동작하지 않으면 작업을 멈추고 이 문서부터 고친다.
- 배포, `CHANGELOG.md` 수정. 가이드는 GitHub 링크로 읽히므로 패키지 배포와 무관하다. 그래서 R1과 겹치는 파일이 없다.

**완료 기준**
- iOS 시뮬레이터의 example 앱에서 KoEn으로 한국어 문서를 색인하고, 한국어 질의로 기대한 문서가 상위에 나오는 것을 확인한다. 결과는 `docs/perf/multilingual-embedding/`에 남긴다.
- 레시피대로 따라 했을 때 빠진 단계가 없다.
- PR 하나를 올리고 CI가 통과한 상태에서 멈춘다.

**손대는 파일:** `docs/guides/model_setup.md`, `docs/perf/multilingual-embedding/**`, `research/multilingual_embedding/**`, `docs/superpowers/plans/2026-11-02-*`, `docs/milestones.md`(M1 섹션)

> `README.md`는 손대지 않는다. README의 다국어 안내(169행)는 이미 `model_setup.md`를 가리킨다.

## 대기 (착수 전 합의 필요)

| 마일스톤 | 내용 | 비고 |
|---|---|---|
| 다음 배포 | `rag_engine_flutter` + `mobile_rag_engine` 동시 배포 | 사용자가 요청할 때만 |
| LLM용 검색 결과 | LLM에 바로 넘길 결과 형식과 tool schema | 방향 우선순위 2 |
| `rag.ask` | LLM SDK를 넣지 않는 얇은 생성 브리지 | 방향 우선순위 3 |
| iPhone 실기기 측정 | KoEn 지연·메모리 | 데스크톱 수치만 있음 |
| 레거시 자산 복사 버그 | `modelAsset`/`tokenizerAsset` 경로가 토크나이저를 고정 이름 `tokenizer.json`으로, 모델을 파일 이름으로 복사하고, 파일이 이미 있으면 복사하지 않는다. 그래서 토크나이저를 바꾸거나, 앱 업데이트에서 같은 이름의 모델을 바꿔도 옛 파일을 계속 쓴다. | M1 검증 중 발견 (2026-11-02). 시뮬레이터에서 KoEn 실행 뒤 MiniLM을 실행하니 KoEn 토크나이저가 남아 `Gather` 범위 오류로 실패했다. Model Pack 경로는 해시별 디렉터리라 영향 없다. 코드 수정이라 M1에서 제외 |

## 다른 세션의 작업

다른 세션은 진행 중이거나 계획한 작업을 여기에 마일스톤 형식으로 적는다. 적기 전에는 착수하지 않는다.

### R1. 다음 배포 범위 확정 (`mobile_rag_engine` 0.23.0 + `rag_engine_flutter` 0.22.0)

- **담당:** 세션 "readme-version-mismatch" (`local_b8e15ee3`), 브랜치 `release/0.23.0` (예정)
- **상태:** 범위 제안만 했다. 사용자 결정 대기. 진행 중인 코드 작업과 열린 PR은 없다.

**포함**
- 지금 main(`4e20e3b`)에 있는 것만 넣는다: #114, #115, #116, #117, #118
- 버전 올리기
  - 루트 `pubspec.yaml`: 0.23.0, `rag_engine_flutter: 0.22.0`으로 고정
  - `rust_builder/pubspec.yaml`: 0.22.0
  - README, `docs/guides/quick_start.md`, `.github/workflows/quickstart_e2e.yml`의 버전 표기, 그리고 lockfile
- CHANGELOG 정리
  - 두 CHANGELOG의 `## Unreleased`를 버전 제목으로 바꾼다.
  - `rust_builder/CHANGELOG.md`에 Chunking 항목이 둘 있으니 하나로 합친다.
  - 같은 파일 FRB 항목의 "FFI API is unchanged"는 #118이 FFI 함수를 추가한 것과 모순되므로 고친다.
- 배포 순서: `rag_engine_flutter` 배포 → 루트를 그 버전으로 고정 → `mobile_rag_engine` 배포 → 태그 → pub 모드 Quick Start E2E. 배포는 사용자가 직접 한다.

**제외**
- 다국어 프리셋, 접두어
- M1 문서
- 보류 중인 성능 후보: `vector_math` 8-lane dot, HNSW 증분 삽입, prune 거리 캐싱, ef 상한, 짧은 문단 병합. 이 후보들은 계획에 없고, 착수하려면 이 문서에 따로 적어 합의를 받는다.
- `lib/src/rust/api/mmap_store.dart` 잔존 파일 정리
- 0.22.3 GitHub release 노트는 기존 태그에 노트만 붙이는 일이라 별도로 결정한다.

**완료 기준**
- main의 Precompile Binaries가 통과한다.
- 버전 PR 하나를 올리고 CI가 통과한 상태에서 멈춘다.
- 사용자가 배포한 뒤 pub 모드 E2E가 4개 플랫폼에서 통과한다.

**손대는 파일:** `pubspec.yaml`, `rust_builder/pubspec.yaml`, `CHANGELOG.md`, `rust_builder/CHANGELOG.md`, `README.md`(버전 표기만), `docs/guides/quick_start.md`, `.github/workflows/quickstart_e2e.yml`, lockfile

> **M1과 겹치는 파일:** 없음. M1은 `CHANGELOG.md`를 고치지 않는다. R1 PR은 `docs/milestones.md`를 고치지 않는다. 이 파일은 M1 PR로 커밋한다.

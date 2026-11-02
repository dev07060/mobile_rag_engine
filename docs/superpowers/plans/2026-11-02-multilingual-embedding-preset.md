# 다국어(한국어) 임베딩 프리셋 도입 계획

- 작성일: 2026-11-02
- 방향: 프로젝트 개선 방향 1순위 — "한국어 문서에서 검색이 제대로 돼야 그 위에 무엇이든 붙일 수 있다"
- 상태: **종료.** 프리셋 레지스트리 계획은 철회했다. 아래 "결정 변경"이 최종이고, 3·4절은 기록으로만 남긴다.
- 측정 결과: [docs/perf/multilingual-embedding/README.md](../../perf/multilingual-embedding/README.md). 아래 2절 표의 수치는 모델 카드 값이고, 직접 재현한 결과 512 고정 기준으로 ±0.002 안에서 일치했다.

## 결정 변경 (2026-11-02)

- **프리셋 레지스트리는 만들지 않는다.** 패키지는 언어와 무관한 장치만 제공하고, 언어별 모델 선택은 문서 레시피로 안내한다. → [Model Setup: 한국어](../../guides/model_setup.md#korean-koen-e5-tiny) (마일스톤 M1, [docs/milestones.md](../../milestones.md))
- **truncation:** 글자 수 기준 256/384/512 단계를 512 토큰 고정으로 바꿨다 (#115).
  - 이 계획의 초안에 적은 AutoRAG +0.109는 문서를 통째로 임베딩한 값이었다.
  - 엔진처럼 청크로 나눠 다시 재니 +0.00 ~ +0.034였고, markdown 청커로 청크를 키운 경우만 +0.09였다.
- **fingerprint:** 모델 파일 해시를 넣었다 (#118). 단계 2는 접두어를 빼고 끝났다.
- **질의/문서 접두어(단계 1)는 보류한다.** KoEn-E5-Tiny는 접두어 유무에 따른 점수 차이가 ±0.002다. e5-small 계열을 권장 모델로 추가할 때 다시 검토한다.
- 현재 MiniLM의 한국어 nDCG@10은 0.01 ~ 0.06이다.

## 1. 현재 구조에서 확인한 제약

| 항목 | 현재 상태 | 다국어 프리셋에 미치는 영향 |
|---|---|---|
| Model Pack v1 | 프리셋 1개 고정(`stable-minilm-l6-v2-arm64-en`, `lib/src/model_pack/model_pack_installer.dart`), `architecture == 'arm64'`만 허용, Q8_0 고정 | 프리셋 레지스트리로 일반화 필요 |
| 임베딩 API | `EmbeddingService.embed(text)` 하나뿐, 질의/문서 구분 없음 | **e5 계열은 `query: ` / `passage: ` 접두어가 필수**. 빠지면 성능이 크게 떨어진다고 모델 카드가 명시 → 엔진 변경 필수 |
| 풀링 | 3D 출력이면 mean pooling, `sentence_embedding` 출력이 있으면 그대로 사용 | e5 계열(mean pooling) 그대로 호환. CLS 풀링 모델(bge-m3, arctic-v2)은 풀링 포함 export가 필요 |
| 입력 | `input_ids`, `attention_mask`, 선택적 `token_type_ids` | XLM-R/BERT 계열 모두 호환 |
| 토크나이저 | Rust `tokenizers 0.22` + `tokenizer.json` | XLM-R Unigram(SentencePiece), Gemma BPE 모두 로드 가능. 길이 256/384/512 단계 truncation 그대로 사용 가능 |
| 모델 교체 감지 | fingerprint = `{modelBasename}\|{dim}\|{quant}` (`lib/src/internal/embedding_fingerprint.dart`) | **위험**: MiniLM과 KoEn-E5-Tiny 둘 다 파일명 `model_qint8_arm64.onnx`, 384차원 → fingerprint가 같아서 **모델을 바꿔도 감지되지 않고 벡터가 섞임**. 접두어 변경도 감지 불가 |

## 2. 후보 모델 비교

한국어 검색 nDCG@10 (MTEB 한국어 검색 7종 평균). 출처: dragonkue 모델 카드의 벤치마크 표.

| 모델 | 파라미터 | 한국어 평균 | AutoRAG | Ko-StrategyQA | arm64 int8 ONNX | 배포 크기(모델+토크나이저) | 라이선스 |
|---|---|---|---|---|---|---|---|
| (현재) all-MiniLM-L6-v2 | 22M | 측정 없음 (영어 전용) | – | – | 있음 | 약 23.5MB | Apache-2.0 |
| paraphrase-multilingual-MiniLM-L12-v2 | 118M | 0.410 | 0.423 | 0.459 | – | – | Apache-2.0 |
| granite-embedding-107m-multilingual | 107M | 0.600 | 0.682 | 0.705 | – | – | Apache-2.0 |
| intfloat/multilingual-e5-small | 118M | 0.671 | 0.801 | 0.752 | **없음** (x86 avx512 int8만 있음) | 약 135MB (직접 양자화 시 추정) | MIT |
| **exp-models/dragonkue-KoEn-E5-Tiny** | **37M** | **0.687** | **0.865** | 0.760 | **있음** (38.3MB) | **약 41MB** | Apache-2.0 |
| dragonkue/multilingual-e5-small-ko-v2 | 118M | 0.693 | 0.856 | 0.768 | 없음 (직접 export 필요) | 약 135MB (추정) | Apache-2.0 |
| intfloat/multilingual-e5-base | 278M | 0.689 | 0.798 | 0.764 | – | – | MIT |
| bge-m3 / arctic-embed-l-v2.0 / e5-large | 560M | 0.72 | 0.83~0.84 | 0.79~0.80 | – | 약 570MB 이상 | MIT / Apache-2.0 |
| EmbeddingGemma-300m | 308M | 한국어 수치 없음 | – | – | int8 있음 (외부 data 파일) | 약 329MB (309MB + 토크나이저 20MB) | Gemma 이용약관 (원본 gated) |

참고: KURE-v1/v2(MTEB-ko-retrieval 1위, nDCG@10 0.76/0.82)는 bge-m3 기반 560M 이상이라 모바일 기본값으로는 제외.

### 핵심 관찰

1. **KoEn-E5-Tiny가 크기 대비 압도적이다.** 37M 파라미터로 118M e5-small-ko와 거의 같은 점수(0.687 vs 0.689)를 내고, 278M e5-base와 비슷하다. 토크나이저가 17MB → 2.9MB로 줄어든 것으로 보아 어휘를 한국어+영어로 줄인(vocab pruning) 모델로 추정된다 (카드에 설명 없음).
   - 대가: 한국어·영어 이외 문자(일본어, 중국어 등)는 품질이 크게 떨어질 가능성이 높다 → 프리셋 이름에 `koen`을 명시해야 한다.
   - 위험: 개인 실험 저장소(다운로드 37회, 1년 이상 갱신 없음). revision SHA로 고정하면 내용은 불변이지만, 저장소 삭제에 대비해 미러링하거나 원본(`dragonkue/multilingual-e5-small-ko`)에서 직접 재현할 수 있는 경로를 남겨야 한다.
2. **100개 언어 지원이 필요하면 e5-small-ko-v2**(원본 e5-small과 병합한 모델이라 다국어 능력 유지)가 최선이다. 다만 arm64 int8 ONNX를 직접 만들어야 하고 크기가 약 135MB로 커진다(25만 어휘 임베딩 테이블이 대부분).
3. **EmbeddingGemma는 지금은 보류.** 크기(약 329MB), Gemma 이용약관(설치 도구에서 재배포할 때 약관 고지 필요), 외부 data 파일 로딩, 전용 프롬프트 형식, 한국어 수치 없음 — 넷 다 걸린다.
4. **관찰 대상**: Bekko Embedding(arXiv 2607.25180, mmBERT-small 가지치기 모델, 활성 파라미터 8M/25M, ONNX int8 124MiB, 8192 토큰). 한국어 수치가 없어 직접 평가해야 한다.

## 3. 추천 (철회: 프리셋 대신 문서 레시피)

| 프리셋 ID (안) | 모델 | 용도 | 우선순위 |
|---|---|---|---|
| `stable-koen-e5-tiny-arm64-koen` | dragonkue-KoEn-E5-Tiny (qint8 arm64) | **한국어 앱 기본값** — 41MB로 MiniLM의 2배 이내 | P0 |
| `stable-multilingual-e5-small-ko-v2-arm64` | multilingual-e5-small-ko-v2 (직접 양자화) | 한국어 + 기타 언어 혼합 | P1 |
| (기존) `stable-minilm-l6-v2-arm64-en` | all-MiniLM-L6-v2 | 영어 전용, 가장 작음 | 유지 |

## 4. 구현 단계 (기록용: 단계 0·2만 진행, 1·3은 보류·철회)

### 단계 0 — 직접 측정 (구현 전 필수)
- 모델 카드 수치는 **fp32 기준**이다. 실제 배포할 **qint8 arm64 ONNX + 우리 토크나이저 경로 + 우리 truncation(256/384/512)**로 Ko-StrategyQA, AutoRAGRetrieval을 재측정한다.
- 측정 대상: MiniLM(기준선), KoEn-E5-Tiny, e5-small, e5-small-ko-v2. 접두어 있음/없음 둘 다.
- 기기 지표: 모델 로드 시간, 질의 1건 embed 지연(iPhone 기준, 기존 on-device profiler 재사용), 메모리 최고치.
- 결과는 `docs/perf/multilingual-embedding/`에 남긴다.
- 통과 기준(안): 양자화 후 한국어 평균 하락 ≤ 0.01, warm embed 지연 ≤ MiniLM의 2배.

### 단계 1 — 엔진: 질의/문서 접두어
- manifest에 `queryPrefix`, `documentPrefix` 추가 (없으면 빈 문자열 → 기존 팩과 하위 호환).
- 내부적으로 `embedQuery` / `embedDocument` 경로를 분리. 공개 API `embed()`는 유지하되 문서 색인과 검색 경로가 올바른 접두어를 쓰도록 연결.
- 토큰 수 계산(context_builder 등)은 접두어 **없는** 원문 기준을 유지.

### 단계 2 — 엔진: fingerprint 강화 (안전장치, 단계 1과 함께)
- fingerprint에 모델 SHA-256(또는 프리셋 ID)과 접두어를 포함 → 같은 파일명·같은 차원의 모델 교체도 잡힌다.
- 기존 DB의 fingerprint 형식과의 호환: 구 형식 저장값은 "모델 정보 부족"으로 보고 마이그레이션 경로를 정한다 (자동 재색인을 강제하지 않도록 주의).

### 단계 3 — Model Pack 프리셋 레지스트리
- 단일 `StableMiniLmL6V2Arm64EnPreset`을 프리셋 목록으로 일반화. 설치 CLI에서 `--preset stable-koen-e5-tiny-arm64-koen` 선택.
- 스키마 버전: 접두어 필드를 선택 필드로 추가하면 v1 유지 가능, 필수로 하면 v2. → 선택 필드 + v1 유지 권장.
- `language` 필드를 `"Korean, English"`처럼 채움.

### 단계 4 — 문서
- README·model_setup 가이드에 "언어별 프리셋 고르기" 표 추가 (크기 / 언어 / 한국어 점수).
- 기존 MiniLM 사용자를 위한 교체 절차 (fingerprint lock → 재색인).

## 5. 열린 질문
- KoEn-E5-Tiny 원본 저장소를 그대로 쓸지, 우리가 재현·미러링한 사본을 쓸지 (재배포 시 Apache-2.0 고지 필요).
- 한국어 앱의 기본 프리셋을 패키지 쪽에서 바꿀지, 앱 개발자가 고르게 둘지 (권장: 기본값은 유지, 문서로 안내).
- VABQ 프로필: 현재 MiniLM/mpnet/bge 전용 → 새 모델은 Q8_0로만 시작 (Model Pack v1은 원래 Q8_0 고정).

## 출처
- [dragonkue/multilingual-e5-small-ko-v2 (한국어 벤치마크 표)](https://huggingface.co/dragonkue/multilingual-e5-small-ko-v2)
- [exp-models/dragonkue-KoEn-E5-Tiny-ONNX](https://huggingface.co/exp-models/dragonkue-KoEn-E5-Tiny-ONNX) (측정과 레시피에 쓴 저장소, revision `5cf599a8cd6577f2f12a026130ad50132e472cfd`)
- [intfloat/multilingual-e5-small](https://huggingface.co/intfloat/multilingual-e5-small)
- [Granite Embedding Models (Ko-StrategyQA 표)](https://arxiv.org/pdf/2502.20204)
- [google/embeddinggemma-300m](https://huggingface.co/google/embeddinggemma-300m), [onnx-community/embeddinggemma-300m-ONNX](https://huggingface.co/onnx-community/embeddinggemma-300m-ONNX)
- [Bekko Embedding (arXiv 2607.25180)](https://arxiv.org/abs/2607.25180)
- [임베딩 모델 선택 가이드 (MTEB-ko-retrieval / KURE 인용)](https://www.data-dynamics.io/en/blog/embedding-model-guide)

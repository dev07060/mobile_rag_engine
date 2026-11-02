# 다국어(한국어) 임베딩 후보 측정 — 단계 0

- 측정일: 2026-11-02
- 계획 문서: [2026-11-02-multilingual-embedding-preset.md](../../superpowers/plans/2026-11-02-multilingual-embedding-preset.md)
- 스크립트: [`research/multilingual_embedding/`](../../../research/multilingual_embedding/)
  - `eval_ko_retrieval.py`: 한국어 검색 품질
  - `bench_latency.py`: 로드 시간·지연·메모리
- 원본 결과: [`results/`](results/)
- 환경: Apple M3 Pro, Python 3.12, onnxruntime 1.31.1, tokenizers 0.23.3 (CPU EP)
- **기기(iPhone) 측정은 아직 하지 않았다.** 아래 지연·메모리는 데스크톱 기준이다.

## 요약

1. **현재 기본 모델(all-MiniLM-L6-v2)은 한국어 검색이 사실상 안 된다.** nDCG@10이 Ko-StrategyQA 0.014, AutoRAG 0.059로, 무작위에 가깝다.
2. **KoEn-E5-Tiny(int8, 공개된 arm64 파일 그대로)가 P0 후보로 확정적이다.**
   - 한국어 품질은 118M인 e5-small-ko-v2와 같거나 더 낫다.
   - 배포 크기는 39MB, 세션 메모리는 68MB, 토크나이저 로드 메모리는 44MB다.
   - 질의/문서 접두어가 있든 없든 점수 차이가 없다(±0.002).
3. **새로 발견한 엔진 문제: 글자 수로 truncation 길이를 정하는 규칙이 한국어에서 검색 품질을 크게 깎는다.**
   - 한국어는 글자당 약 0.55 토큰으로, 영어(약 0.25)의 두 배쯤 된다.
   - 그래서 1200자 미만 → 256 토큰 규칙이 긴 문서를 자른다. AutoRAG 문서는 78.6%가 잘렸다.
   - 문서를 통째로 임베딩하면 512 고정 시 AutoRAG 점수가 0.757 → 0.866 (+0.109)로 오른다.
   - **정정:** 엔진은 청크로 나눠 색인하므로 실제 효과는 더 작다. 청크 단위로 다시 재니 +0.00 ~ +0.034이고, markdown 청커로 청크를 키운 경우만 +0.09였다. 대신 청크 수가 26 ~ 43% 줄어든다(2-a 참고).
4. **e5-small 계열(25만 어휘)은 모바일에 무겁다.**
   - 배포 크기 129MB.
   - 토크나이저(17MB JSON) 로드 시 메모리 최고치가 +344MB, ORT 세션이 +267MB다.
   - 한국어 외 언어가 꼭 필요한 경우에만 고려할 가치가 있다.
5. 측정 스크립트를 검증했다. 512 고정 기준 점수가 모델 카드 값과 ±0.002 안에서 일치한다. 예: KoEn AutoRAG는 0.866(카드 0.865), e5-small-ko-v2 fp32 Ko-StrategyQA는 0.769(카드 0.768).

## 1. 한국어 검색 품질 (nDCG@10 / Recall@10)

엔진과 같은 경로로 측정했다.
- tokenizer.json, 특수 토큰 포함, padding 없음.
- ONNX CPU, attention mask를 반영한 mean pooling, 정확한 cosine top-10.
- 문서는 `"{title} {text}"` 형식(MTEB와 동일).
- HNSW와 Q8_0 벡터 저장은 이 측정에 포함하지 않았다. 이 둘의 손실은 [vector-math-refactor](../vector-math-refactor/)에서 recall 약 0.997로 따로 확인했다.

### 1-a. 엔진의 현재 truncation 규칙(256/384/512, 글자 수 기준)

| 설정 | Ko-StrategyQA | AutoRAG |
|---|---|---|
| all-MiniLM-L6-v2 int8 (현재 기본값) | 0.014 / 0.020 | 0.059 / 0.105 |
| KoEn-E5-Tiny fp32 | 0.758 / 0.826 | 0.759 / 0.868 |
| **KoEn-E5-Tiny int8 (공개 파일)** | **0.759 / 0.821** | **0.757 / 0.886** |
| KoEn-E5-Tiny int8 (직접 양자화) | 0.756 / 0.819 | 0.751 / 0.868 |
| KoEn-E5-Tiny int8 (공개 파일), 접두어 없음 | 0.759 / 0.819 | 0.759 / 0.851 |
| e5-small fp32 | 0.751 / 0.818 | 0.726 / 0.851 |
| e5-small int8 (직접 양자화) | 0.731 / 0.798 | 0.720 / 0.851 |
| e5-small int8, 접두어 없음 | 0.721 / 0.788 | 0.671 / 0.825 |
| e5-small-ko-v2 fp32 | 0.767 / 0.832 | 0.765 / 0.868 |
| e5-small-ko-v2 int8 (직접 양자화) | 0.760 / 0.819 | 0.763 / 0.877 |
| e5-small-ko-v2 int8, 접두어 없음 | 0.754 / 0.821 | 0.758 / 0.868 |

### 1-b. truncation 512 고정

| 설정 | Ko-StrategyQA | AutoRAG | AutoRAG 변화 (1-a 대비) |
|---|---|---|---|
| **KoEn-E5-Tiny int8 (공개 파일)** | **0.762 / 0.825** | **0.866 / 0.974** | **+0.109** |
| KoEn-E5-Tiny int8, 접두어 없음 | 0.763 / 0.823 | 0.866 / 0.974 | +0.107 |
| e5-small int8 | 0.727 / 0.795 | 0.761 / 0.930 | +0.041 |
| e5-small int8, 접두어 없음 | 0.721 / 0.785 | 0.719 / 0.886 | +0.048 |
| e5-small-ko-v2 fp32 | 0.769 / 0.834 | 0.856 / 0.974 | +0.092 |
| e5-small-ko-v2 int8 | 0.764 / 0.821 | 0.839 / 0.965 | +0.076 |
| e5-small-ko-v2 int8, 접두어 없음 | 0.758 / 0.828 | 0.822 / 0.956 | +0.064 |

### 관찰

- **int8 양자화 손실**
  - KoEn 공개 파일: −0.002 이내.
  - e5-small-ko-v2: Ko-StrategyQA −0.005, AutoRAG −0.017.
  - e5-small: Ko-StrategyQA −0.02로 손실이 가장 크다.
  - 직접 양자화한 파일(`quantize_dynamic`, QInt8, per_channel=False, Gather 포함)은 KoEn 공개 파일보다 약 0.005 낮다. 공개 파일은 optimum의 arm64 설정으로 만들어진 것으로 보인다. 직접 양자화할 때는 설정을 더 맞춰야 한다.
- **접두어 효과는 모델마다 다르다.**
  - KoEn: 차이 없음.
  - e5-small-ko-v2: −0.005 ~ −0.017.
  - 원본 e5-small: AutoRAG에서 −0.04 ~ −0.05.
  - 즉 접두어 지원은 KoEn에는 필수가 아니지만, e5 계열 프리셋을 추가하려면 필요하다.

## 2. 한국어 토큰 길이와 truncation

KoEn 토크나이저에 `passage: ` 접두어를 붙여 셌다.

| 데이터셋 | 글자 수 p50 / p90 | 토큰 수 p50 / p90 | 글자당 토큰 | 현재 규칙으로 잘린 비율 | 512에서 잘린 비율 |
|---|---|---|---|---|---|
| AutoRAG | 870 / 1255 | 458 / 682 | 0.53 | **78.6%** | 37.1% |
| Ko-StrategyQA | 275 / 526 | 153 / 293 | 0.55 | 15.2% | 1.5% |

- 기본 청크 크기 `kDefaultMaxChunkChars = 500`이면 한국어 청크는 약 275 토큰이라 256 토큰 예산을 넘는다.
  - semantic 청커 경로에서는 청크가 더 잘게 나뉜다.
  - markdown 청커 경로에서는 실제로 잘린다.
  - 자세한 영향은 2-a에 정리했다.
- truncation 규칙은 `5f506d7 fix(rag): improve hybrid retrieval quality`에서 들어왔다. 커밋에 근거가 적혀 있지 않다. 글자 수 기준값(1200/2400)은 영어(글자당 약 0.25 토큰)를 가정한 것으로 보인다.
- 제안: 토큰 수로 판단하거나, 상한을 모델의 최대 길이(512)로 일원화한다. 잘리지 않는 짧은 텍스트는 결과가 달라지지 않고, 긴 텍스트만 추론 비용이 늘어난다. 다만 **영어 MiniLM 사용자의 기존 인덱스도 벡터가 바뀌므로** fingerprint 변경과 재색인 안내가 필요하다.

### 2-a. 정정: 청크 단위로 다시 잰 truncation 영향 (KoEn-E5-Tiny int8)

위 +0.109는 **문서를 통째로 임베딩한** 수치다. 엔진은 문서를 그대로 임베딩하지 않는다.
- semantic 청커(`plan_plain_text_ranges` → `enforce_token_budget`)는 같은 `resolve_truncation_max_length` 예산을 넘지 않도록 청크를 더 잘게 나눈다. 그래서 잘림 대신 **분할**이 생긴다.
- markdown 청커(`split_by_line_ranges`)는 토큰 예산을 확인하지 않는다. 그래서 이 경로에서만 **실제 잘림**이 생긴다.

이 두 경로를 근사해 다시 측정했다(`eval_chunked.py`).
- 문장 단위로 묶고, 문서 점수는 청크 점수의 최댓값(MaxP)으로 냈다.
- 실제 청커와 문장 경계 처리가 달라 근사치다.
- AutoRAG는 질의가 114개뿐이라 ±0.01 수준 차이는 잡음일 수 있다.

| 데이터셋 | maxChunkChars | 경로 | 현재 규칙 | 토큰 512 기준 | 차이 | 청크 수 (현재 → 512) |
|---|---|---|---|---|---|---|
| Ko-StrategyQA | 500 | semantic | 0.762 | 0.761 | −0.001 | 11627 → 10603 |
| Ko-StrategyQA | 500 | markdown (9.6% 잘림) | 0.761 | 0.763 | +0.001 | 동일 |
| Ko-StrategyQA | 1000 | semantic | 0.760 | 0.761 | +0.000 | 11191 → 9549 |
| Ko-StrategyQA | 1000 | markdown (15.7% 잘림) | 0.757 | 0.759 | +0.002 | 동일 |
| AutoRAG | 500 | semantic | 0.907 | **0.942** | **+0.034** | 2116 → 1567 (−26%) |
| AutoRAG | 500 | markdown (35% 잘림) | 0.928 | 0.942 | +0.013 | 동일 |
| AutoRAG | 1000 | semantic | 0.905 | 0.910 | +0.005 | 1987 → 1140 (−43%) |
| AutoRAG | 1000 | markdown (**64% 잘림**) | **0.805** | **0.895** | **+0.090** | 동일 |

- **실제 효과는 +0.109보다 작고, 경로와 설정에 따라 다르다.**
  - 짧은 문서(Ko-StrategyQA)에서는 차이가 없다.
  - 긴 문서(AutoRAG)에서는 +0.005 ~ +0.034다.
  - markdown 청커로 청크를 키운 경우는 +0.09까지 차이 난다.
- 품질과 별개로 **청크 수가 26 ~ 43% 줄어든다.** 인덱스 크기와 색인 시간이 그만큼 줄어든다.
- 청크 단위 색인(0.90 ~ 0.94)이 문서 통째 임베딩(0.866)보다 낫다. 엔진의 청킹 방식 자체는 맞다.
- 수정 방향: 글자 수 규칙을 없애고 **토큰 수 기준(모델 최대 길이 512)**으로 통일한다. 512 토큰 이하 텍스트는 결과가 달라지지 않으므로 언어별 조정이 필요 없다. markdown 청커에도 같은 토큰 예산을 적용한다.

## 3. 크기·지연·메모리 (데스크톱 M3 Pro, ORT CPU)

batch 1, padding 없음, 50회 측정의 p50. 청크는 256 토큰이다.
- 질의 토큰 수: MiniLM 63, e5 계열 22. MiniLM은 한글을 거의 글자 단위로 쪼개서 토큰이 많다.
- 메모리는 `ru_maxrss` 증가분으로 쟀다(최고치 기준).

| 모델 | ONNX | tokenizer.json | 로드 | 질의 1스레드 / 4스레드 | 청크 1스레드 / 4스레드 | 토크나이저 로드 메모리 | 세션 메모리 |
|---|---|---|---|---|---|---|---|
| MiniLM-L6 int8 (현재) | 22.0MB | 0.4MB | 55ms | 6.2 / 2.3ms | 28.0 / 8.5ms | +13MB | +46MB |
| **KoEn-E5-Tiny int8** | **36.5MB** | **2.8MB** | **113ms** | **4.4 / 2.0ms** | **55.3 / 16.8ms** | **+44MB** | **+68MB** |
| e5-small int8 | 112.6MB | 16.3MB | 291ms | 4.3 / 1.9ms | 59.4 / 17.5ms | **+344MB** | +267MB |
| e5-small-ko-v2 int8 | 112.6MB | 16.3MB | 293ms | 4.3 / 1.9ms | 59.4 / 17.5ms | **+344MB** | +267MB |

- KoEn은 12층이라 6층인 MiniLM보다 청크 임베딩이 약 2배 느리다. 계획의 통과 기준(MiniLM의 2배 이하)에 겨우 들어온다. 질의는 토큰이 적어 오히려 더 빠르다.
- e5-small 계열의 토크나이저 로드 메모리(+344MB)는 엔진이 쓰는 Rust `tokenizers` 크레이트에서도 비슷할 가능성이 높다. Python 바인딩도 같은 Rust 구현이다. iOS의 메모리 제한을 고려하면 위험하다. ORT 그래프 최적화 수준(ALL/BASIC/DISABLE)을 바꿔도 세션 메모리는 그대로였다.

## 4. 계획에 반영할 결론

> **후속 결정 (2026-11-02):** 프리셋 레지스트리는 만들지 않고 문서 레시피로 안내한다([Model Setup: 한국어](../../guides/model_setup.md#korean-koen-e5-tiny)). truncation은 #115, fingerprint는 #118로 고쳤다. 접두어(3번)는 보류했다. 아래 목록은 측정 당시의 결론이다. 최종 결정은 [계획 문서](../../superpowers/plans/2026-11-02-multilingual-embedding-preset.md)의 "결정 변경"에 있다.

1. **P0 프리셋은 `KoEn-E5-Tiny`(공개 arm64 int8, revision `5cf599a8…`)로 확정한다.** e5-small-ko-v2는 품질 이점이 없고, 크기·메모리 비용만 크다.
2. **truncation 규칙 수정을 프리셋 도입과 같은 우선순위로 올린다.** 모델과 상관없이 한국어 품질에 영향이 크다(+0.04 ~ +0.11).
3. KoEn만 도입한다면 접두어 지원은 필수가 아니다. 다만 KoEn 모델 카드는 접두어를 권장하고, 모델 교체 시 fingerprint 문제는 그대로 남는다. 따라서 단계 1(접두어)은 유지하되, 단계 2(fingerprint)를 먼저 한다.
4. 직접 양자화가 필요해지면 optimum arm64 설정과 비교 검증부터 한다.

## 5. 엔진 전체 경로 확인 (iOS 시뮬레이터, 2026-11-02)

[Model Setup 한국어 레시피](../../guides/model_setup.md#korean-koen-e5-tiny)대로 KoEn-E5-Tiny Model Pack을 만들어 example 앱에서 실행했다. 엔진 코드는 main `4e20e3b`(512 토큰 truncation과 모델 해시 fingerprint 포함)다.

- 데이터: AutoRAGRetrieval 문서 720개, 질의 114개. 문서는 `"{title}\n{text}"`로 `addDocument`에 넣었다.
- 검색: `MobileRag.search(query, topK: 30)` 기본값(i8 HNSW + BM25 RRF). 청크를 문서 단위로 묶어 앞 10개 문서로 점수를 냈다.
- 확인용 테스트와 임시 자산은 커밋하지 않았다.

| 경로 | 청크 수 | nDCG@10 | Recall@10 | Top-1 | 색인 시간 | 질의 평균 |
|---|---|---|---|---|---|---|
| `modelAsset`/`tokenizerAsset` | 2152 | 0.894 | 1.000 | 0.772 | 70.3s | 332ms |
| Model Pack (`model-pack.json`) | 2152 | 0.894 | 1.000 | 0.772 | 79.8s | 362ms |

- 두 경로의 점수가 같다. 레시피의 Model Pack 경로가 동작한다.
- 데스크톱 Python 측정(청크 단위, semantic 500자 0.942)보다 조금 낮다. 질의 수가 114개뿐이고, 청커와 점수 계산 방식(MaxP 근사)이 달라 직접 비교하기는 어렵다.
- 시뮬레이터는 하드웨어 가속이 없어 시간 수치는 실기기 성능을 뜻하지 않는다.
- Model Pack의 fingerprint는 `model.onnx|384|f32+vabq:none|sha256:fd688b…`다. 설치 파일 이름이 MiniLM pack과 같은 `model.onnx`라서, 0.22.3 이하에서는 모델 교체를 감지하지 못한다. 그래서 레시피는 0.22.3 이하에서 새 `databaseName`을 쓰라고 안내한다.
- MiniLM 기준선은 12분 제한 안에 색인을 끝내지 못했다. MiniLM 토크나이저는 한글을 거의 글자 단위로 쪼개 청크가 훨씬 많아진다. MiniLM 점수는 1절의 데스크톱 값(AutoRAG 0.059)을 기준으로 삼는다.
- 이 실행 중 레거시 자산 경로의 버그를 발견했다. 토크나이저를 고정 이름으로 복사하고, 파일이 이미 있으면 다시 복사하지 않는다. 그래서 KoEn 실행 뒤 MiniLM을 실행하니 KoEn 토크나이저가 남아 실패했다. [docs/milestones.md](../../milestones.md)의 대기 목록에 올렸다.

## 남은 측정

- iPhone 실기기: 로드 시간, warm embed 지연, 메모리 최고치. 기존 [on-device query profiler](../ondevice-query-profiler/)를 재사용한다.
- 엔진 Rust `tokenizers`로 KoEn tokenizer.json을 로드했을 때 Python과 토큰 ID가 같은지 확인한다(교차 검증).
- 512 고정 시 영어(MiniLM) 품질·지연 변화: 회귀가 없는지 확인한다.

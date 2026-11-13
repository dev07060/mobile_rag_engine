# F-3 `ask` 조건 측정 (2026-11-13)

README와 `docs/local-rag-engine.md`의 passage 수치는 하네스의 `search_top_k` 100 조건에서 잰 `passage_recall@10`이다. 실제 `MobileRag.ask`는 정답 후보를 5개만 LLM에 넘긴다. 이 보고서는 같은 80개 묶음에서 `ask`와 같은 호출로 다시 잰 값이다. 마일스톤은 `docs/milestones.md`의 F1 (F-3)이다.

**80개 묶음은 회귀 확인용이다(F-0 결정).** 질의 64개가 정답 구절의 앞 낱말 8개를 나열한 것이라, 아래 값은 낱말이 겹치는 쉬운 질의에서 잰 값이다. 기본값이나 README의 근거로 쓰지 않는다.

## `ask`가 실제로 하는 일 (코드 확인 2026-11-13)

- `MobileRag.ask` / `inCollection(..).ask` → `RagSearchTool`(`defaultTopK`=`maxTopK`=5) → `searchHybridWithContext(topK: 5, tokenBudget: 1500)` (`lib/mobile_rag.dart`).
- `SourceRagService._searchHybridWithContextViaHandle` → `searchMetaHybrid(topK 5, sourceIds null)` → `assembleContext(tokenBudget 1500, relevanceFirst, separator '\n\n---\n\n', singleSourceMode false)` (`lib/services/source_rag_service.dart`).
- Rust `search_meta_hybrid`는 늘 컬렉션 필터를 넘기므로 `compute_hybrid_rrf_scores`의 후보 배수는 4다(`rust_builder/rust/src/api/hybrid_search.rs`의 `multiplier`). 그래서 `ask`는 벡터와 BM25 목록에서 각 20개, 하네스(topK 100)는 각 400개를 본다.

하네스에 `_askCondition`을 더해 같은 호출을 그대로 했다.

- **`ask@5`:** topK 5 검색 결과 5개 중에 정답 구절을 통째로 담은 청크가 있는 비율.
- **`ask 문맥`:** 토큰 예산 1500으로 조립한 문맥에 정답 구절이 들어 있는 비율. LLM이 실제로 받는 것이다.
- **topK 100 `@5` / `@10`:** 같은 실행에서 topK 100으로 검색한 결과의 앞 5개 / 10개.

## 조건

| 항목 | 값 |
|---|---|
| 엔진 코드 | `c3aa1a1` (코드는 W1 머지 `28308ab`와 같다. 문서 커밋만 더했다) |
| 하네스 | `example/integration_test/hybrid_passage_relevance_measure_test.dart` (gitignore 대상 로컬 파일. B1 다중 모델 사본 + F-3 `_askCondition`) |
| 빌드 | profile, arm64만, Rust feature `vector_faer,vector_quant_i8` |
| 기기 | Apple M3 Pro, macOS 27.2.1, Xcode 27.1, Flutter 3.35.5, rustc 1.91.1 |
| Xcode 27 우회 | 링커 래퍼(`-Wl,-no_fixup_chains`), `ARCHS = arm64`, Podfile `post_install` 배포 대상 14.0 (커밋하지 않음) |
| 질의셋 | 80개 묶음 (`wiki_article_sources_manifest_80_balanced_v1.json`, `hybrid_relevance_seed_80_balanced_v1.jsonl`, `hybrid_passage_gold_80_balanced_v1.jsonl`) |
| DB | 모델마다 새 DB, HNSW 기본 검색 |
| 측정일 | 2026-11-13, 다른 측정 작업 없음 |

| 모델 | fingerprint | 청크 | 실행 시간 (색인 + 검색) |
|---|---|---|---|
| MiniLM (Model Pack `stable-minilm-l6-v2-arm64-en`) | `model.onnx\|384\|f32+vabq:none\|sha256:e9246dc3…` | 4667 | 56초 |
| KoEn-E5-Tiny (`model_qint8_arm64.onnx`, 접두어 없음) | `model.onnx\|384\|f32+vabq:none\|sha256:fd688b15…` | 4492 | 57초 |
| BGE-m3 (`Teradata/bge-m3` `model_int8.onnx`) | `model.onnx\|1024\|f32+vabq:none\|sha256:b089a980…` | 4492 | 200초 |

같은 실행의 topK 100 `default_hybrid` 값이 W1 PR #137의 최종 측정과 세 모델 모두 같다(`recall@10` / `answerable@10` / `mrr@10`: MiniLM 0.925 / 0.900 / 0.7450, KoEn 0.950 / 0.9625 / 0.8168, BGE-m3 0.9625 / 0.9625 / 0.8211).

## 결과: README 수치와 `ask` 조건 (default_hybrid 0.2/0.8)

| 모델 | README (B1, W1 전) `@10` | 지금 topK 100 `@10` | 지금 topK 100 `@5` | **`ask@5`** | **`ask` 문맥** | 문맥 청크 / 토큰 (평균) |
|---|---|---|---|---|---|---|
| MiniLM | 0.9375 | 0.925 | 0.8625 | **0.900** | **0.900** | 4.84 / 760 |
| KoEn-E5-Tiny | 0.9625 | 0.950 | 0.900 | **0.900** | **0.900** | 5.00 / 500 |
| BGE-m3 (참고) | 0.975 | 0.9625 | 0.900 | **0.9125** | **0.9125** | 5.00 / 514 |

- **README 대비 차이:** `ask` 조건 값은 README보다 MiniLM −0.0375, KoEn −0.0625, BGE-m3 −0.0625 낮다. 차이의 대부분은 `@10` → `@5`(정답을 몇 번째까지 보느냐)에서 온다. 후보 수(400 → 20)는 이 묶음에서 오히려 몇 건을 살렸다(아래).
- **README 수치는 W1 전 값이다.** W1(Snowball 어간 처리)이 들어간 지금 코드의 topK 100 `@10`은 세 모델 모두 README보다 0.0125 낮다. W1 PR에 기록된 차이와 같다.
- **문맥 조립은 손실이 없었다.** 세 모델, 다섯 가중치 모두 `ask@5`와 `ask` 문맥이 질의마다 같다. 정답 청크가 예산 때문에 빠진 경우는 없었다. 토큰 예산 1500 안에 청크 5개가 대부분 들어간다(MiniLM은 400회 중 39회에서 3~4개).
- **모델 사이의 차이가 `ask` 조건에서 줄어든다.** topK 100 `@10`에서는 MiniLM < KoEn < BGE-m3(0.925 / 0.950 / 0.9625)인데, `ask@5`에서는 0.900 / 0.900 / 0.9125다. 놓친 질의는 세 모델 모두 틀 문장 질의(semantic)에 몰려 있다.

질의 종류별 `ask@5` / topK 100 `@5` / topK 100 `@10` (질의 수 16씩):

| 종류 | MiniLM | KoEn | BGE-m3 |
|---|---|---|---|
| lexical | 16 / 16 / 16 | 16 / 16 / 16 | 16 / 16 / 16 |
| mixed | 15 / 15 / 15 | 16 / 16 / 16 | 16 / 16 / 16 |
| hard_negative | 16 / 15 / 16 | 16 / 16 / 16 | 16 / 16 / 16 |
| multilingual | 16 / 16 / 16 | 16 / 16 / 16 | 16 / 16 / 16 |
| semantic (틀 문장) | **9** / 7 / 11 | **8** / 8 / 12 | **9** / 8 / 13 |

semantic 16개만 변별력이 있다. 나머지 64개는 세 모델과 두 조건 모두에서 거의 다 맞는다.

## 가중치별 (`ask@5`, 괄호는 같은 실행의 topK 100 `@5`)

| 가중치 (벡터/BM25) | MiniLM | KoEn | BGE-m3 |
|---|---|---|---|
| vector_only | 0.550 (0.600) | 0.925 (0.925) | 0.950 (0.950) |
| bm25_only | 0.8625 (0.8625) | 0.875 (0.875) | 0.875 (0.875) |
| default_hybrid 0.2/0.8 | 0.900 (0.8625) | 0.900 (0.900) | 0.9125 (0.900) |
| 0.4/0.6 | 0.8875 (0.8125) | 0.900 (0.925) | 0.9375 (0.9625) |
| 0.6/0.4 | 0.6125 (0.7625) | 0.9125 (0.925) | 0.9625 (0.9875) |

- **후보 수가 결과를 바꾼다.** 같은 가중치에서도 후보 20개(`ask`)와 400개(topK 100)의 앞 5개가 다르다. MiniLM default_hybrid에서는 `ask`에서만 맞은 질의 4건(semantic 3, hard_negative 1), topK 100에서만 맞은 질의 1건(semantic)이 있다. 한쪽 목록에서 20위 밖인 후보는 `ask`에서 RRF 점수를 받지 못해, 두 목록 모두 중간쯤에 있던 청크가 위로 올라오지 못한다. 방향은 질의마다 다르다.
- **MiniLM의 벡터 비중이 높은 가중치는 `ask` 조건에서 더 나쁘다.** 0.6/0.4에서 0.7625 → 0.6125. MiniLM의 한국어 벡터 후보가 약해서, 20개 안에서 BM25 후보를 밀어내는 것으로 보인다(추정, 질의별로 나누지 않았다).
- **vector_only도 후보 수에 따라 다르다(MiniLM 0.600 → 0.550).** HNSW 검색에 넘기는 후보 수가 줄면 근사 검색이 정답 청크를 놓치는 것으로 보인다(추정). KoEn과 BGE-m3에서는 차이가 없었다.
- 가중치 비교는 F2의 몫이다. 이 표는 기본값을 바꾸는 근거가 아니다(규칙 10.3, 80개 묶음은 회귀 확인용).

## 사용하는 쪽 관점 (규칙 8.3)

- `ask` 한 번이 LLM에 넘기는 문맥은 평균 500~760 토큰(청크 5개)이다. 토큰 수는 모델의 토크나이저로 센 값이라 모델마다 다르다(MiniLM이 가장 많다).
- 이 측정은 검색과 문맥 조립까지다. LLM 생성은 부르지 않았다.

## 재현

- 하네스: B1 다중 모델 사본(`.claude/local-models/hybrid_passage_relevance_measure_test.multimodel.dart`)에 F-3의 `_askCondition`과 `_writeAskRows`를 더한 로컬 파일. F-1에서 저장소에 넣는다.
- 실행 명령은 `docs/perf/passage-benchmark-2026-11/README.md`와 같다. 모델은 `--dart-define=B1_MODEL_ASSET=… --dart-define=B1_TOKENIZER_ASSET=…`로 넘긴다. 결과는 앱 Documents의 `f3_ask_<시각>.json`에 남는다.
- `results/f3_ask_<model>_80.json`: 모델 fingerprint, 청크 수, 빌드 모드, 가중치별 요약, 질의별 행(`ask_gold_rank`, `ask_in_context`, 문맥 청크·토큰 수, `top100_gold_rank`). 질의 원문은 들어 있지 않다.

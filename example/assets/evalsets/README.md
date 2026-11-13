# 검색 평가 묶음

검색 평가 하네스(`example/integration_test/hybrid_passage_relevance_measure_test.dart`)가 읽는 자료다. 범위와 결정은 `docs/milestones.md`의 F1, 측정 결과는 `docs/perf/f1-eval-baseline/`에 있다. 문서 본문은 `../corpus/`에 있고, 위키 문서는 CC BY-SA 4.0이다(`../corpus/README.md`).

## 들어 있는 것

| 파일 | 내용 |
|---|---|
| `wiki_article_sources_manifest_v1.json` | 위키 문서 300개의 매니페스트(URL, `revision_id`, 도메인, 길이 구간, 글자 수) |
| `wiki_article_sources_manifest_80_balanced_v1.json`, `hybrid_relevance_seed_80_balanced_v1.jsonl`, `hybrid_passage_gold_80_balanced_v1.jsonl` | **80개 묶음 (회귀 확인용)**. 문서 80개, 질의 80개, 정답 구절 80개 |
| `f1/` | F1의 새 묶음. 세션이 쓴 짧은 문서 16개 + 80개 묶음의 위키 문서, 질의 40개(답 없음 8 포함). 만드는 방법은 `scripts/f1/build_f1_bundle.py` |
| `templates/` | 스키마와 형식 예시 |

## 80개 묶음은 회귀 확인용이다

- **기계가 만든 자료다.** `scripts/generate_evalset_seed.py`(seed 42)가 위키 문서에서 질의 800개와 정답 400행을 만들고, `scripts/generate_p5_4_expanded_evalset.py`가 그중 언어·도메인별로 10개씩 골라 질의를 다시 만든 것이다. 사람이 검수한 기록은 없다.
- **질의 64개는 정답 구절의 낱말 앞 8개를 나열한 것이다**(lexical, mixed, hard_negative, multilingual 각 16). 나머지 16개는 "X의 핵심 개념과 주요 특징을 설명해줘" 같은 틀 문장(semantic)이다. 정답 구절과 낱말이 하나도 안 겹치는 질의는 0개다. 정답 구절은 80개 모두 문서의 첫 문장이다.
- 그래서 이 묶음의 수치는 "낱말이 겹치는 쉬운 질의"의 값이다. README나 PR에서 품질 수치로 인용하지 않고, 같은 코드에서 같은 값이 나오는지 보는 회귀 확인에만 쓴다(2026-11-13 결정).
- 현재 기준값(W1 머지 `28308ab` 뒤, topK 100 `passage_recall@10`, default_hybrid): MiniLM 0.925, KoEn-E5-Tiny 0.950, BGE-m3 0.9625. 조건은 `docs/perf/f1-eval-baseline/f3_ask_condition.md`.

## F1 묶음 (`f1/`)

- **작성자: 세션 초안(`author: session_draft`), 사람 검수 전이다.** 사람이 쓴 질의로 부르지 않는다. 검수표는 `docs/perf/f1-eval-baseline/f2_review_sheet.md`이고, 검수를 거친 질의는 `session_draft+human_review`로 바꾼다.
- 문서 96개: 80개 묶음의 위키 문서 80개 + 세션이 쓴 짧은 문서 16개(`../corpus/f1_short/`, 영어 8, 한국어 8, MIT).
- 겹침은 질의 토큰 중 정답 구절(또는 정답 문서)에도 있는 비율이다. 엔진 `tokenize_for_bm25`를 테스트 전용 덤프(`rust_builder/rust/src/api/eval_dump.rs`)로 그대로 불러 셌다. 질의별 값은 `f1/f1_overlap_v1.json`.

| 유형 | 질의 | 영어 / 한국어 | 짧은 문서 / 위키 | 정답 구절 겹침 (중앙값, 범위) | 정답 문서 겹침 (중앙값) |
|---|---|---|---|---|---|
| 안 겹침 (`none`) | 14 | 7 / 7 | 7 / 7 | 0 (0~0) | 0.366 |
| 일부 겹침 (`partial`, 0.5 미만) | 10 | 5 / 5 | 5 / 5 | 0.191 (0.062~0.444) | 0.446 |
| 많이 겹침 (`high`, 대조군) | 8 | 4 / 4 | 4 / 4 | 0.676 (0.500~0.833) | 0.787 |
| 답 없음 (`no_answer`) | 8 | 4 / 4 | – | – | – |
| 합계 | 40 | 20 / 20 | 16 / 16 | | |

- 의도한 유형과 잰 유형이 다른 질의는 없다. 정답 문서 전체와도 낱말이 안 겹치는 질의는 f1q-011 하나다.
- 다시 만들기: `python3 scripts/f1/build_f1_bundle.py` (질의 원본 `scripts/f1/f1_queries_v1_spec.py`, cargo가 필요하다).

## 넣지 않은 것과 다시 만드는 방법

질의 800개(`wiki_article_evalset_seed_v1.jsonl`)와 정답 400행(`wiki_article_chunk_gold_seed_v1.jsonl`)은 저장소에 넣지 않았다. 결함이 확인됐기 때문이다(`docs/perf/f1-eval-baseline/f0_report.md`). 질의의 29%는 정답 라벨이 질의와 맞지 않고, 한국어 noise 질의는 원문이다. 80개 묶음은 이 두 파일로 다시 만들 수 있고, 2026-11-13에 바이트 단위로 같게 나오는 것을 확인했다.

```bash
cp example/assets/evalsets/wiki_article_sources_manifest_v1.json example/assets/evalsets/templates/sources_manifest.json
python3 scripts/generate_evalset_seed.py \
  --manifest example/assets/evalsets/templates/sources_manifest.json \
  --out-evalset example/assets/evalsets/templates/wiki_article_evalset_seed_v1.jsonl \
  --out-chunk-gold example/assets/evalsets/templates/wiki_article_chunk_gold_seed_v1.jsonl \
  --total 800 --chunk-gold-max 400 --seed 42
python3 scripts/generate_p5_4_expanded_evalset.py
```

세 파일은 `.gitignore` 대상이다. 800개 질의의 `collected_at`은 실행한 날짜가 들어가서 원래 파일과 그 칸만 다르다.

## 검증

```bash
python3 scripts/validate_evalset_bundle.py \
  --manifest example/assets/evalsets/wiki_article_sources_manifest_80_balanced_v1.json \
  --evalset example/assets/evalsets/hybrid_relevance_seed_80_balanced_v1.jsonl \
  --chunk-gold example/assets/evalsets/hybrid_passage_gold_80_balanced_v1.jsonl
```

`example/test/profiling/relevance_evalset_test.dart`는 80개 묶음과 `f1/` 묶음이 매니페스트와 맞는지, 정답 구절이 문서에 있는지 확인한다.

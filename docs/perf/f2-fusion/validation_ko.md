# F2: 학습에 쓰이지 않은 한국어 자료로 다시 확인

F2-0은 MIRACL 한국어로 무게를 골랐다. KoEn-E5-Tiny의 바탕 모델(multilingual-e5-small)과 BGE-m3는 MIRACL train으로 미세조정됐으므로, 두 모델의 공개된 미세조정 자료 목록에 없는 한국어 자료 두 개로 다시 쟀다. 결과로 KoEn 레시피의 권장값을 0.6/0.4에서 **0.5/0.5**로 바꿨다(사용자 "한국어 한정 0.5/0.5로 바꿔서 진행해줘", 2026-11-14).

## 결론

- **0.5/0.5는 이 자료에서 기본값 0.2/0.8과 같거나 조금 낫다.** KorQuAD KoEn 483 → 484, BGE-m3 482 → 488. AutoRAG는 ±1개.
- **0.6/0.4는 KorQuAD에서 기본값보다 나빴다.** KoEn 483 → 477(+6/−12), BGE-m3 482 → 477(+9/−14).
- 모든 자료를 합치면 0.5와 0.6의 이득은 비슷하고(KoEn +36 대 +38, BGE-m3 +42 대 +44), 잃는 질의는 0.5가 절반 이하다(KoEn 7 대 19, BGE-m3 10 대 20). 0.6이 더 얻은 몫은 MIRACL, 즉 학습에 쓰인 자료에서 나왔다.
- 0.5는 벽 경계(벡터 무게 약 0.433, [`../f1-eval-baseline/f7_fusion_compare.md`](../f1-eval-baseline/f7_fusion_compare.md))보다 높아 MIRACL에서 본 손실도 대부분 고친다(MIRACL 5천 KoEn 167 → 182).
- **확신: 중간.** 0.5와 0.6의 차이는 자료마다 3~11개 질의다. KorQuAD의 손실은 두 모델에서 같은 방향이고 원인(아래)이 분명하지만, 자료 두 개 모두 위키백과나 공개 보고서이고 실제 앱 문서는 아니다.

## 자료

| 묶음 | 질의 | 말뭉치 | 낱말 겹침 | 출처·라이선스 |
|---|---|---|---|---|
| `koval_korquad` | KorQuAD 1.0 dev 5,774개 중 500개(씨앗 20261114), 조정용 250 / 확인용 250 | dev 문단 961개 전부 + MIRACL 한국어 말뭉치 방해 구절 4,039개 = 5,000 구절, 6,225 청크 | 많음 392, 일부 108 | [KorQuAD 1.0](https://korquad.github.io) CC BY-ND, 방해 구절은 MIRACL(위키백과 CC BY-SA) |
| `koval_autorag` | AutoRAG retrieval 114개 전부, 조정용 57 / 확인용 57 | 공개 PDF 보고서(금융, 공공, 의료, 법, 상거래) 조각 720개, 2,160 청크 | 많음 49, 일부 65 | `mteb/AutoRAGRetrieval` revision `43b8179`, MIT |

- **학습 겹침:** multilingual-e5 보고서 표 2, M3-Embedding 논문 3.1절, KoEn의 한국어 미세조정에 쓰인 AI Hub 기계독해 자료 목록에 두 자료 모두 없다. 위키백과 본문은 사전학습에서 봤을 수 있다.
- **KorQuAD:** 작업자가 위키백과 문단을 보면서 질문을 썼다. 정답 = 질문이 쓰인 문단. dev 140개 글의 문단을 모두 넣었으므로 같은 글의 다른 문단이 평균 6개 남짓 함께 있다. 방해 구절은 KorQuAD dev 글 제목과 같은 제목의 글을 빼고 골랐다(판정되지 않은 정답이 섞이지 않게).
- **AutoRAG:** 질문마다 정답 조각 하나. 그대로 썼다(방해 구절 없음).
- **내려받기:** 사용자 허락("AutoRAG와 KorQuAD dev 받아서 진행해줘"). KorQuAD train은 받지 않았다. AutoRAG는 Hugging Face 행 API가 응답하지 않아 parquet 파일 세 개를 받았고, pyarrow 없이 읽으려고 표준 라이브러리만 쓰는 [`scripts/f2/mini_parquet.py`](../../../scripts/f2/mini_parquet.py)를 썼다(이 파일들에 필요한 범위만 지원).
- **커밋하지 않은 것:** 본문(KorQuAD는 CC BY-ND, 방해 구절은 CC BY-SA). 커밋한 것은 만드는 스크립트 [`scripts/f2/build_ko_validation_bundles.py`](../../../scripts/f2/build_ko_validation_bundles.py)와 id·씨앗·입력 해시 [`scripts/f2/ko_validation_ids_v1.json`](../../../scripts/f2/ko_validation_ids_v1.json)이다.

## 결과 (`ask` 조건: topK 5, 목록마다 후보 20개, 정답 구절이 상위 5개에 든 질의 수)

괄호는 기본값 0.2/0.8 대비 새로 맞힘 / 잃음.

### KoEn-E5-Tiny

| 묶음 | 질의 | 벡터만 | BM25만 | 0.2/0.8 | 0.4/0.6 | **0.5/0.5** | 0.6/0.4 |
|---|---|---|---|---|---|---|---|
| KorQuAD | 조정용 250 | 227 | 234 | 241 | 242 (+1/−0) | 240 (+1/−2) | 237 (+2/−6) |
| KorQuAD | 확인용 250 | 227 | 238 | 242 | 243 (+1/−0) | 244 (+3/−1) | 240 (+4/−6) |
| KorQuAD | 합계 500 | 454 | 472 | 483 | 485 | **484 (+4/−3)** | 477 (+6/−12) |
| AutoRAG | 조정용 57 | 55 | 56 | 57 | 57 | 56 (+0/−1) | 56 (+0/−1) |
| AutoRAG | 확인용 57 | 56 | 54 | 55 | 55 | 56 (+1/−0) | 56 (+2/−1) |
| AutoRAG | 합계 114 | 111 | 110 | 112 | 112 | **112 (+1/−1)** | 112 (+2/−2) |

### BGE-m3

| 묶음 | 질의 | 벡터만 | BM25만 | 0.2/0.8 | 0.4/0.6 | **0.5/0.5** | 0.6/0.4 |
|---|---|---|---|---|---|---|---|
| KorQuAD | 조정용 250 | 228 | 234 | 240 | 240 (+2/−2) | 243 (+6/−3) | 237 (+6/−9) |
| KorQuAD | 확인용 250 | 227 | 238 | 242 | 243 (+1/−0) | 245 (+3/−0) | 240 (+3/−5) |
| KorQuAD | 합계 500 | 455 | 472 | 482 | 483 | **488 (+9/−3)** | 477 (+9/−14) |
| AutoRAG | 조정용 57 | 54 | 56 | 57 | 56 (+0/−1) | 55 (+0/−2) | 55 (+0/−2) |
| AutoRAG | 확인용 57 | 54 | 54 | 54 | 53 (+0/−1) | 55 (+2/−1) | 55 (+2/−1) |
| AutoRAG | 합계 114 | 108 | 110 | 111 | 109 | **110 (+2/−3)** | 110 (+2/−3) |

### 앞선 측정과 합친 표 (합계, 앞의 다섯 줄은 [`f2_0_report.md`](f2_0_report.md)의 같은 덤프)

| 자료 | KoEn 0.2 | KoEn 0.5 | KoEn 0.6 | BGE-m3 0.2 | BGE-m3 0.5 | BGE-m3 0.6 |
|---|---|---|---|---|---|---|
| MIRACL 5천 (213, 학습에 쓰임) | 167 | 182 (+15/−0) | 187 (+21/−1) | 173 | 186 (+15/−2) | 191 (+19/−1) |
| MIRACL 1.5만 (213, 학습에 쓰임) | 165 | 178 (+16/−3) | 181 (+20/−4) | 166 | 180 (+15/−1) | 186 (+21/−1) |
| F1 묶음 (답 있는 32) | 20 | 26 (+6/−0) | 27 (+7/−0) | 20 | 27 (+7/−0) | 28 (+8/−0) |
| 80개 묶음 | 72 | 73 (+1/−0) | 73 (+1/−0) | 73 | 76 (+4/−1) | 77 (+5/−1) |
| KorQuAD dev (500) | 483 | 484 (+4/−3) | 477 (+6/−12) | 482 | 488 (+9/−3) | 477 (+9/−14) |
| AutoRAG (114) | 112 | 112 (+1/−1) | 112 (+2/−2) | 111 | 110 (+2/−3) | 110 (+2/−3) |
| **변화 합계** | – | **+36, 잃음 7** | +38, 잃음 19 | – | **+42, 잃음 10** | +44, 잃음 20 |

MiniLM은 이 표에 없다. 무게는 모델별로 앱이 정하므로 MiniLM 앱은 기본값 0.2/0.8을 그대로 쓴다(80개 묶음 MiniLM 한국어에서 0.5는 27 → 24, 0.6은 27 → 8).

## 왜 KorQuAD에서 0.6이 잃나

- **BM25가 강한 자료다.** 질문을 문단을 보며 썼으므로 낱말이 많이 겹친다(500개 중 392개 "많음"). BM25만 472개, 벡터만 454개로, MIRACL(벡터 196 대 BM25 153)과 반대다. 하이브리드 기본값(483)이 둘 다보다 낫고, 정답이 거의 항상 BM25 후보 20개 안에 있어 벽이 문제가 되지 않는다.
- **잃은 질의를 하나씩 봤다(덤프에서, 0.2에서는 맞고 0.6에서는 틀린 KoEn 12개, BGE-m3 14개).** 정답은 모두 BM25 1~4위였고, 벡터 순위는 2~20위로 흩어져 있거나 20위 밖이었다(KoEn 3개, BGE-m3 7개). 0.6의 상위 5개 중 4~5개가 정답과 같은 글의 다른 문단인 경우가 KoEn 8/12, BGE-m3 8/14였다. 주제가 같은 문단은 벡터가 가깝다고 보므로, 벡터 무게를 올리면 이 문단들이 낱말로 맞힌 정답을 밀어낸다.
- 긴 문서 하나를 여러 청크로 나눠 넣는 앱에서도 같은 일이 생길 수 있다. 다만 이 구성은 묶음을 만들 때 dev 문단을 모두 넣은 결과이기도 하다.
- **AutoRAG는 무게를 가르지 못했다.** 기본값으로 114개 중 111~112개를 맞혀 거의 꽉 찼고, 차이는 ±1~3개다.

## 엔진과 맞는지

오프라인 재결합(`f7_fusion_compare.py`)이 엔진 하네스 결과를 재현하는지 봤다(`ask` 조건, 질의 × 프로필 5개).

| 실행 | 같음 | 다름 (모두 BM25 점수 동점) |
|---|---|---|
| KoEn KorQuAD | 2,484 / 2,500 | 16 |
| BGE-m3 KorQuAD | 2,495 / 2,500 | 5 |
| KoEn AutoRAG | 570 / 570 | 0 |
| BGE-m3 AutoRAG | 570 / 570 | 0 |

KorQuAD 정답 문장 하나(`korquad-6568398-7-2`)는 청크 경계에 걸려 어느 청크에도 통째로 들지 않는다. 위 표는 정답 구절(source) 기준이라 영향이 없다.

## 초기화 인자 0.5/0.5 실제 엔진 확인

KoEn-E5-Tiny, F1 묶음(답 있는 32개, 4,543 청크), `scripts/eval/run_passage_eval.sh --model <KoEn dir> --name koen --bundle f1 --init-weights 0.5,0.5`, 커밋 `ef7628d` 위의 작업 트리(라이브러리 코드는 `04d950d`와 같고, 바뀐 `lib/mobile_rag.dart`는 문서 주석뿐), 같은 기기·도구, 2026-11-14, 59초.

| 확인 | 결과 |
|---|---|
| 무게를 넘기지 않은 `inCollection(...).prepareAsk(q)`와 `prepareAsk(q, vectorWeight: 0.5, bm25Weight: 0.5)`: 같은 청크, 같은 순서 | 32 / 32 |
| 무게를 넘기지 않은 `prepareAsk`의 프롬프트에 정답 청크가 든 질의 | 26 / 32 (기본값 20, 0.6/0.4는 27. 오프라인 재결합의 0.5 값 26과 같음) |

출력은 [`results_init_weights_05_koen_f1.txt`](results_init_weights_05_koen_f1.txt)에 있다. 0.6/0.4로 한 같은 확인은 [`f2_0_report.md`](f2_0_report.md) "구현 뒤 확인"에 있다.

## 측정 조건 (규칙 9)

| 항목 | 값 |
|---|---|
| 모델 | KoEn-E5-Tiny `model.onnx|384|f32+vabq:none|sha256:fd688b1508532505ba91c93eb4ef9413`, BGE-m3 `model.onnx|1024|f32+vabq:none|sha256:b089a980c41f6158f8447400dd5b2abb` |
| 엔진 | 커밋 `ef7628d`(라이브러리 코드는 PR #139의 `04d950d`와 같음, 바뀐 추적 파일은 평가 스크립트와 `.gitignore`뿐), profile 빌드, Rust 기능 `vector_faer,vector_quant_i8`, 새 DB |
| 기기·도구 | Apple M3 Pro, macOS 27.2.1, Xcode 27.1, Flutter 3.35.5, Dart 3.9.2, rustc 1.91.1 |
| 청크 | KorQuAD 6,225, AutoRAG 2,160 |
| 날짜 | 2026-11-14(KST), 실행 시간 KoEn KorQuAD 356초, BGE-m3 KorQuAD 1,396초, KoEn AutoRAG 67초, BGE-m3 AutoRAG 571초 |
| 다른 작업 | 측정 중 다른 측정은 없음. 평가는 하나씩 차례로 돌렸다. 검색 시간은 이 문서에서 쓰지 않는다 |
| 자료 해시 | `run_meta.json`의 `dataset.sha256`, 입력 파일 해시는 `ko_validation_ids_v1.json` |
| 결과 파일 | [`results_validation_ko.json`](results_validation_ko.json)(`f2_0_compare.py --json`) |

## 다시 만들기

```bash
python3 -I scripts/f2/build_ko_validation_bundles.py --korquad <KorQuAD_v1.0_dev.json> --miracl-dir <MIRACL ko corpus dir> --autorag-dir <dir with autorag_{corpus,queries,qrels}.parquet>
scripts/eval/run_passage_eval.sh --model <KoEn dir> --name koen --bundle koval_korquad --dump-candidates --out build/eval_results/koval_koen_korquad
scripts/eval/run_passage_eval.sh --model <KoEn dir> --name koen --bundle koval_autorag --dump-candidates --out build/eval_results/koval_koen_autorag
python3 -I scripts/f2/f2_0_compare.py --miracl build/eval_results/koval_* --json docs/perf/f2-fusion/results_validation_ko.json
python3 -I scripts/eval/f7_fusion_compare.py build/eval_results/koval_*
```

BGE-m3는 `--model`과 `--name bgem3`, `--out`만 바꾼다. 잃은 질의의 "같은 글 문단" 분석은 덤프에서 따로 센 값이고 스크립트로 남기지 않았다.

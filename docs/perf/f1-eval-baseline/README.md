# 검색 평가 기반 (F1)

`docs/milestones.md` F1의 결과물이다. 이후의 검색 변경(결합 방식, 기본 가중치, 한국어 프리셋)은 여기의 묶음과 실행 절차로 잰다.

| 문서 | 내용 |
|---|---|
| [`f0_report.md`](f0_report.md) | F-0. 기존 위키 자료(질의 800개, 80개 묶음) 판정. 갈래 (2): 80개 묶음은 회귀 확인용으로만 쓴다 |
| [`f0_label_sample.md`](f0_label_sample.md) | F-0 정답 라벨 표본 40개(세션 판독, 사람 검수 전) |
| [`f3_ask_condition.md`](f3_ask_condition.md) | F-3. `ask` 조건(topK 5) 측정과 README 수치의 차이 |
| [`f2_stage1.md`](f2_stage1.md) | F-2 1단계. 세션 초안 질의 40개와 짧은 문서 16개 측정 |
| [`f2_review_sheet.md`](f2_review_sheet.md) | F-2 질의 40개 검수표 |
| [`f7_fusion_compare.md`](f7_fusion_compare.md) | F-7. 후보 목록 덤프와 오프라인 결합 비교(엔진 결과 3,360건 재현) |
| [`miracl_ko.md`](miracl_ko.md) | 공개 벤치마크 MIRACL 한국어 dev 213개로 잰 결합 손실과 원인(기본 하이브리드가 BM25 상위 20개 안에서만 순서를 바꾼다) |
| [`f8_report.md`](f8_report.md) | **F-8. 종합 보고서.** 기준선(세 모델 × 80개 묶음, F1 묶음, `ask` 조건), F-7 비교, F2로 넘기는 것 |

자료는 `example/assets/corpus/`(문서, 위키는 CC BY-SA 4.0)와 `example/assets/evalsets/`(묶음)에 있다. 각 디렉터리의 README를 본다.

## 한 명령 실행 (macOS)

```bash
scripts/eval/run_passage_eval.sh --model <model.onnx와 tokenizer.json이 있는 디렉터리> --bundle 80
```

```bash
scripts/eval/run_passage_eval.sh --model-pack stable-minilm-l6-v2-arm64-en --bundle f1
```

- `--bundle 80`은 80개 묶음(회귀 확인용), `--bundle f1`은 F1 묶음(문서 96개, 질의 40개)이다.
- 모델 파일은 저장소에 넣지 않는다. 디렉터리 경로로 넘기거나, `--model-pack`으로 `dart run mobile_rag_engine:setup`이 받게 한다.
- 스크립트는 추적 중인 파일을 고치지 않는다. `example/`을 `build/eval_app/`에 복사하고, 복사본에만 평가 자산 선언과 Xcode 27 우회 세 가지(링커 래퍼 `-Wl,-no_fixup_chains`, `ARCHS = arm64`, Pod 배포 대상 14.0)를 넣은 뒤, 하네스를 profile 빌드로 돌린다.
- 필요한 것: Flutter, Xcode, rustup(Rust 소스 빌드). 처음 실행은 Rust 빌드 때문에 몇 분 걸린다. BGE-m3처럼 큰 모델은 80개 묶음에 3~18분이 걸렸다.
- 결과는 `build/eval_results/<시각>_<이름>_<묶음>/`에 남는다.
- `--dump-candidates`를 주면 엔진의 벡터·BM25 후보 목록(`candidates.json`)과 색인 DB 사본(`index.sqlite`)도 남는다. `python3 scripts/eval/f7_fusion_compare.py <결과 디렉터리>...`로 결합 방식을 오프라인에서 비교한다(`f7_fusion_compare.md`).

| 파일 | 내용 |
|---|---|
| `run_meta.json` | 규칙 9 항목을 자동으로 적는다: 모델 이름, fingerprint, 모델·토크나이저 sha256(Model Pack이면 `model-pack.json`까지), 엔진 커밋과 고친 추적 파일 목록, 빌드 모드와 Rust feature(`cargokit.yaml`), CPU, macOS, Xcode·Flutter·Dart·rustc 버전, 묶음 파일 경로와 sha256, 청크 수, 끝난 시각, 걸린 시간, 끝날 때의 load average |
| `passage_result.json`, `.csv` | 하네스 원본(topK 100 조건의 5가지 가중치, 질의별 순위와 상위 청크). JSON에 `run_meta`를 넣었다 |
| `ask_condition.json` | `ask` 조건(topK 5, 토큰 예산 1500)의 질의별 결과. `f1` 묶음이면 답 없는 질문의 상위 출처와 점수까지. `run_meta`를 넣었다 |
| `summary.txt` | 가중치별 요약 줄 |
| `run.log` | `flutter drive` 전체 출력 |

## 재현 기준값 (2026-11-13)

같은 Mac(Apple M3 Pro, macOS 27.2.1, Xcode 27.1, Flutter 3.35.5, rustc 1.91.1), profile, `vector_faer,vector_quant_i8`, 80개 묶음, default_hybrid, topK 100:

| 모델 | fingerprint | 청크 | `passage_recall@10` / `answerable_context@10` / `passage_mrr@10` |
|---|---|---|---|
| MiniLM | `sha256:e9246dc3…` | 4667 | 0.925 / 0.900 / 0.7450 |
| KoEn-E5-Tiny | `sha256:fd688b15…` | 4492 | 0.950 / 0.9625 / 0.8168 |
| BGE-m3 | `sha256:b089a980…` | 4492 | 0.9625 / 0.9625 / 0.8211 |

새로 클론한 저장소에서 위 명령으로 MiniLM 값이 같게 나오는지 확인한 기록은 아래 "새 클론 확인"에 있다.

## 새 클론 확인 (2026-11-13)

- 브랜치 `claude/f1-eval-baseline-154010`의 `32ced9f`를 새 디렉터리에 `git clone`하고, Rust 빌드 캐시 없이 다음 한 명령을 돌렸다.

  ```bash
  scripts/eval/run_passage_eval.sh --model <MiniLM Model Pack 디렉터리> --name minilm --bundle 80
  ```

- 241초(첫 Rust 빌드 포함)에 끝났고, default_hybrid가 **0.925 / 0.900 / 0.7450**(청크 4667, fingerprint `sha256:e9246dc3…`)으로 위 기준값과 같았다. `ask` 조건 `ask@5`도 0.900으로 `f3_ask_condition.md`와 같다.
- `run_meta.json`이 사람 손 없이 채워졌다: 커밋 `32ced9f`, 고친 추적 파일 없음, profile, `vector_faer,vector_quant_i8`, Apple M3 Pro, macOS 27.2.1, Xcode 27.1, Flutter 3.35.5, Dart 3.9.2, rustc 1.91.1, Model Pack `stable-minilm-l6-v2-arm64-en`(revision `1110a243…`)과 파일 sha256, 묶음 파일 sha256, 청크 수.
- 실행 뒤 클론의 `git status`는 깨끗했다.
- 다른 실행과 달랐던 값: vector_only의 `answerable_context@10`이 0.6125 → 0.600, 0.6/0.4가 0.6875 → 0.675로 한 질의씩 다르다. HNSW를 새로 만들 때 근사 결과가 조금씩 달라지는 것으로 보인다(F-2 1단계의 MiniLM 재실행에서도 vector_only 한 질의가 달랐다). default_hybrid는 실행마다 같았다.
- 끝날 때의 load average는 7.27이었다. 같은 Mac에서 다른 측정은 돌지 않았지만, 다른 프로그램은 켜져 있었다.

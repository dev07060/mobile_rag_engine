# 80-query passage 평가 재측정 (B1, 2026-11-12)

README와 `docs/local-rag-engine.md`의 `passage_recall@10 = 0.925`는 2026-06-12에 BGE-m3로 잰 값이다. 이 보고서는 같은 질의셋을 지금 코드에서 세 모델로 같은 조건에서 다시 잰 결과다. 세 모델은 기본 Model Pack(MiniLM), 한국어 권장 모델(KoEn-E5-Tiny), 6월과 같은 BGE-m3 파일이다. 마일스톤은 `docs/milestones.md`의 B1이다.

## 조건

| 항목 | 값 |
|---|---|
| 엔진 코드 | `4e2ed87` (S1 PR #134의 브랜치 끝, S1의 HNSW 수정 포함) |
| 질의셋 | `wiki_article_sources_manifest_80_balanced_v1.json`, `hybrid_relevance_seed_80_balanced_v1.jsonl`, `hybrid_passage_gold_80_balanced_v1.jsonl` (질의 80개, 문서 80개, 6월 artifact와 같은 파일) |
| 하네스 | `example/integration_test/hybrid_passage_relevance_measure_test.dart` (gitignore 대상, main 체크아웃의 로컬 파일). `search_top_k` 100, `hydrated_top_k` 10 |
| 앱 | 새 `flutter create` macOS 앱, 패키지 path 의존성 + `rag_engine_flutter` path override (Rust 소스 빌드, `vector_faer,vector_quant_i8`) |
| 빌드 | **profile** (`flutter drive --profile -d macos`), arm64만 |
| 기기 | 로컬 Mac (Apple Silicon), macOS 27, Xcode 27.1, Flutter 3.35.5, rustc 1.91.1 |
| DB | 모델마다 앱 컨테이너를 비우고 새 DB로 색인 |
| exact scan | 같은 DB를 다시 열고 모든 검색에 `sourceIds`로 80개 소스 전부를 넘겨, HNSW 대신 exact scan을 쓰게 했다 (하네스 사본에만 넣은 옵션) |

모델과 청크 수:

| 모델 | 파일 | fingerprint | 청크 |
|---|---|---|---|
| MiniLM | `stable-minilm-l6-v2-arm64-en` Model Pack (all-MiniLM-L6-v2 int8, 23 MB) | `model.onnx\|384\|f32+vabq:none\|sha256:e9246dc3…` | 4667 |
| KoEn-E5-Tiny | `docs/guides/model_setup.md`의 `model_qint8_arm64.onnx` (38 MB), 접두어 없이 | `model.onnx\|384\|f32+vabq:none\|sha256:fd688b15…` | 4492 |
| BGE-m3 | `Teradata/bge-m3` `model_int8.onnx` (569 MB), 6월 예제 앱 컨테이너에 남아 있던 같은 파일 | `model.onnx\|1024\|f32+vabq:none\|sha256:b089a980…` | 4492 |
| (6월) BGE-m3 | 같은 모델 (6월 DB의 fingerprint `model.onnx\|1024\|f32+vabq:none`) | – | 4937 |

청크 수는 토크나이저에 따라 다르다. 6월과 지금 사이에 512 토큰 truncation(#115)과 청킹 변경(#116)이 들어갔다.

## 결과: `passage_recall@10`

| 가중치 (벡터/BM25) | MiniLM | KoEn-E5-Tiny | BGE-m3 | 6월 BGE-m3 |
|---|---|---|---|---|
| vector_only (1.0/0.0) | 0.650 | 0.950 | 0.975 | 0.950 |
| bm25_only (0.0/1.0) | 0.900 | 0.925 | 0.925 | 0.9125 |
| **default_hybrid (0.2/0.8)** | **0.9375** | **0.9625** | **0.975** | **0.925** |
| 0.4/0.6 | 0.925 | 0.9875 | 1.000 | 0.950 |
| 0.6/0.4 | 0.8125 | 0.9875 | 1.000 | 0.9875 |

`answerable_context@10` / `passage_mrr@10`:

| 가중치 | MiniLM | KoEn-E5-Tiny | BGE-m3 | 6월 BGE-m3 |
|---|---|---|---|---|
| vector_only | 0.600 / 0.468 | 0.950 / 0.763 | 0.975 / 0.864 | 0.950 / 0.783 |
| default_hybrid | 0.9125 / 0.763 | 0.975 / 0.817 | 0.9875 / 0.839 | 0.9375 / 0.838 |

## 언어별·질의 종류별

각 칸은 top-10 안에 정답 passage가 있는 질의 수이고, "default_hybrid / vector_only" 순서다.

| | MiniLM | KoEn-E5-Tiny | BGE-m3 | 6월 BGE-m3 |
|---|---|---|---|---|
| 영어 (32) | 30 / 30 | 30 / 30 | 30 / 31 | 30 / 30 |
| 한국어 (32) | 29 / **11** | 31 / 30 | 32 / 31 | 28 / 30 |
| 다국어 (16) | 16 / 11 | 16 / 16 | 16 / 16 | 16 / 16 |
| semantic (16) | 12 / 8 | 13 / 12 | 14 / 14 | 10 / 15 |
| lexical (16) | 16 / 11 | 16 / 16 | 16 / 16 | 16 / 15 |
| mixed (16) | 15 / 10 | 16 / 16 | 16 / 16 | 16 / 14 |
| hard_negative (16) | 16 / 12 | 16 / 16 | 16 / 16 | 16 / 16 |

## 읽는 법

- **기본 하이브리드 검색:** MiniLM(23 MB) 0.9375, KoEn-E5-Tiny(38 MB) 0.9625, BGE-m3(569 MB) 0.975다.
  - 지금 README의 0.925는 6월 BGE-m3 값이고, 지금 코드의 세 모델 모두 그보다 높다.
- **MiniLM의 벡터 검색:** 영어에서는 BGE-m3와 거의 같다(30/32 대 31/32). 한국어는 11/32다. 영어 전용 모델이라 예상된 결과이고, BM25가 받쳐서 하이브리드에서는 29/32가 된다.
- **KoEn-E5-Tiny의 벡터 검색:** 0.950이다. 6월 BGE-m3(0.950)와 같고, 지금 BGE-m3(0.975)와도 큰 차이가 없다. 크기는 BGE-m3의 약 1/15다. 질의·문서 접두어(`query:`/`passage:`) 없이 잰 값이다.
- **가중치:** 다국어 모델은 벡터 비중을 높일수록 좋아진다(KoEn·BGE-m3 모두 0.4/0.6 이상에서 0.99~1.0). MiniLM은 반대로 벡터 비중을 올리면 한국어가 떨어진다(0.6/0.4에서 한국어 18/32). 지금 기본 가중치 0.2/0.8은 MiniLM에 맞는 값이다. 가중치 조정은 B1 범위 밖이다(후보 목록 [중간]).
- **HNSW 손실:** 세 모델 모두 vector_only의 질의별 정답 순위가 exact scan과 80개 전부 같다. 하이브리드에서 순위가 다른 질의는 MiniLM 8건, KoEn 1건, BGE-m3 0건이다. exact 경로는 후보를 4배, HNSW 경로는 2배 가져오는 차이에서 온다.
- **빌드 모드:** MiniLM은 S1에서 debug로 잰 값(0.9375 / 0.650)과 profile 값이 같다. 이 평가에서 debug(faer 없음)와 profile의 차이는 순위를 바꾸지 않았다.
- **6월 대비 BGE-m3:** 0.925에서 0.975로 올랐다. 코드(S1 HNSW 수정, #115, #116)와 청크 수(4937 → 4492)가 함께 바뀌어서, 어느 쪽의 효과인지는 나누지 않았다.

## 시간 (참고)

| 모델 | 문서 80개 색인 + 검색 400회 |
|---|---|
| MiniLM | 58초 |
| KoEn-E5-Tiny | 59초 |
| BGE-m3 | 1050초 |

같은 Mac에서 profile 빌드로 잰 값이고, 다른 작업이 함께 돌고 있었다.

## 재현

1. 위 조건의 앱을 만든다. 하네스와 평가셋은 main 체크아웃의 gitignore 대상 파일이다(`example/integration_test/hybrid_passage_relevance_measure_test.dart`, `example/lib/profiling/relevance_*.dart`, `example/assets/evalsets/`, `example/assets/corpus/`).
2. 모델 파일을 앱 자산으로 넣는다.
3. Xcode 27에서는 profile 빌드에 우회 두 가지가 필요하다(`docs/milestones.md` 후보 목록의 Xcode 27 항목).
   - **링커 래퍼:** Rust proc-macro dylib이 chained fixups로 만들어지면 rustc가 읽지 못한다. `-Wl,-no_fixup_chains`를 붙이는 링커 래퍼를 `CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER`로 넘긴다.
   - **arm64만 빌드:** Flutter의 lipo 검사 때문에 `macos/Runner/Configs/Release.xcconfig`에 `ARCHS = arm64`를 넣는다.
4. 다음 명령으로 실행한다.

```bash
CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER=<래퍼 경로> flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/hybrid_passage_relevance_measure_test.dart \
  --profile -d macos \
  --dart-define=HYBRID_PASSAGE_MANIFEST_ASSET=assets/evalsets/wiki_article_sources_manifest_80_balanced_v1.json \
  --dart-define=HYBRID_PASSAGE_SOURCE_EVALSET_ASSET=assets/evalsets/hybrid_relevance_seed_80_balanced_v1.jsonl \
  --dart-define=HYBRID_PASSAGE_CHUNK_GOLD_ASSET=assets/evalsets/hybrid_passage_gold_80_balanced_v1.jsonl
```

이번 측정에서는 하네스 사본만 두 가지를 바꿨다. `MobileRag.initialize`의 자산 경로를 dart-define(`B1_MODEL_ASSET`, `B1_TOKENIZER_ASSET`)으로 바꿀 수 있게 했고, exact scan 옵션(`S1_EXACT`)을 넣었다.

## results

`results/`의 JSON은 하네스 출력을 요약한 것이다. 메타데이터, 집계, 질의별 정답 순위가 들어 있다.

- `<model>_hnsw.json`: 기본 HNSW 검색
- `<model>_exact.json`: exact scan
- `june_bgem3_hnsw.json`: 6월 artifact를 같은 형식으로 줄인 것

질의별 검색 결과 미리보기까지 담은 원본(각 약 3.5 MB)은 저장소에 넣지 않았다. 6월 원본도 gitignore 대상이다(`docs/perf/ondevice-query-profiler/artifacts/`).

# Benchmarks

Retrieval quality of `mobile_rag_engine` with the three embedding models it
supports, on a bilingual regression set and on five public datasets.

To run the same measurements on your own documents and hardware, see
[`benchmark_service`](https://github.com/dev07060/mobile_rag_engine/blob/main/lib/services/benchmark_service.dart).

## Models

| Model | Best for | Files to bundle | Install |
|:------|:---------|:---------------:|:--------|
| all-MiniLM-L6-v2 Model Pack (default) | English | about 23 MB | [one `setup` command](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md#recommended-stable-minilm-model-pack) |
| KoEn-E5-Tiny | Korean, or Korean and English | about 41 MB | [one `setup` command](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md#korean-documents-koen-e5-tiny) |
| BGE-m3 | Highest accuracy, larger apps | about 586 MB | [two files and a manifest](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md#bge-m3-model-pack) |

## Highlights

- **Small models, large-model accuracy.** On the public English sets the 23 MB
  default model finds the answer as often as the 586 MB BGE-m3. On KorQuAD 1.0
  and AutoRAG the 41 MB KoEn-E5-Tiny matches BGE-m3 to within one question.
- **Hybrid search beats keyword search alone** on SciFact, NFCorpus, KorQuAD 1.0
  and AutoRAG, with every model measured.
- **Korean works out of the box with KoEn-E5-Tiny:** 31 of 32 Korean questions
  on the regression set, 483 of 500 on KorQuAD 1.0.

## Bilingual regression set (80 queries)

80 questions over 80 Wikipedia articles: 32 English, 32 Korean, 16 mixed. The
set covers semantic, lexical, mixed and hard-negative questions. Default hybrid
search, top 10 of 100 results, a fresh database per model.

| Model | `passage_recall@10` | `answerable_context@10` | `source_recall@10` |
|:------|:---:|:---:|:---:|
| MiniLM Model Pack (default) | 0.925 | 0.900 | 1.000 |
| KoEn-E5-Tiny | 0.950 | 0.9625 | 1.000 |
| BGE-m3 | 0.9625 | 0.9625 | 1.000 |

Questions with the answer passage in the top 10, by language:

| Model | English, 32 | Korean, 32 | Mixed, 16 |
|:------|:---:|:---:|:---:|
| MiniLM Model Pack (default) | 29 | 29 | 16 |
| KoEn-E5-Tiny | 29 | 31 | 16 |
| BGE-m3 | 29 | 32 | 16 |

MiniLM is an English model: with vector search alone it finds 11 of the 32
Korean answers, and BM25 brings the hybrid result to 29. For Korean documents,
use KoEn-E5-Tiny or BGE-m3.

**Same results on iPhone 17.** The MiniLM and KoEn-E5-Tiny Model Packs,
installed with `setup --preset`, give the same `passage_recall@10`, the same
per-language counts and the same chunk counts on an iPhone 17 as on the Mac.
`answerable_context@10` for KoEn-E5-Tiny was 0.975 on the iPhone, one question
more than on the Mac. On the phone, a whole run (indexing about 4,500 chunks,
then searching the 80 questions with five weight settings) took about a minute
per model.

Conditions: `mobile_rag_engine` 0.24.0 code, profile builds on an Apple M3 Pro
Mac (2026-11-16) and on an iPhone 17 with iOS 27.2.1 (MiniLM and KoEn-E5-Tiny,
2026-11-22). BGE-m3 was measured on the Mac only. `searchHybridWithContext`,
`searchHybrid` and `ask` use this hybrid ranking; `search` is vector-only.
Records:
[`f1-eval-baseline`](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/perf/f1-eval-baseline/README.md#iphone-17에서-같은-80개-묶음-2026-11-22).

## Public English datasets

| Model | NFCorpus, 323 questions | SciFact, 300 claims |
|:------|:---:|:---:|
| MiniLM Model Pack (default) | 207 (64%) | 226 (75%) |
| KoEn-E5-Tiny | 207 (64%) | 219 (73%) |
| BGE-m3 | 205 (63%) | 224 (75%) |
| *BM25 keyword search alone* | *199 (62%)* | *211 (70%)* |

Questions with a relevant document among the 5 passages `ask` sends to the LLM.
The BM25 row is the same run's keyword-only ranking, as a baseline.

Both sets are from the [BEIR](https://github.com/beir-cellar/beir) suite and
search biomedical paper abstracts (3,633 and 5,183 documents), text far more
specialized than typical app content. NFCorpus queries are short titles from a
consumer nutrition site (median two words) matched against the papers they
cite, which makes it a hard set for any retriever; read the numbers against the
baseline rather than on their own. SciFact queries are scientific claims with
about one correct abstract each. MiniLM's training data includes citation pairs
from the SciFact paper collection, so its SciFact number may be higher than on
unrelated text.

Conditions: default hybrid search, profile build on an Apple M3 Pro Mac,
2026-11-14, engine commit `3f9df80`.

## Public Korean datasets

| Model | MIRACL Korean dev, 213 questions (5,000 / 15,000 passages) | KorQuAD 1.0 dev, 500 questions | AutoRAG Korean, 114 questions |
|:------|:---:|:---:|:---:|
| KoEn-E5-Tiny | 167 / 165 (78% / 77%) | 483 (97%) | 112 (98%) |
| BGE-m3 | 173 / 166 (81% / 78%) | 482 (96%) | 111 (97%) |
| *BM25 keyword search alone* | *–* | *472 (94%)* | *110 (96%)* |

Same metric and build as the English sets. MiniLM was not run, because it is an
English model. MIRACL's training split was used to train BGE-m3 and
KoEn-E5-Tiny's base model, so their MIRACL numbers may be higher than on your
documents.

Conditions: 2026-11-14, engine commits `28308ab` (MIRACL) and `04d950d`
(KorQuAD, AutoRAG).

## On-device speed and memory (iPhone 17)

56 app documents in English and Korean (about 2,300 chunks, two of them PDFs)
indexed with `addDocumentFromFile`, then 120 questions (60 English, 60 Korean)
searched in the `ask` condition (top 5).

| | MiniLM Model Pack (default) | KoEn-E5-Tiny |
|:--|:---:|:---:|
| Query embedding, English (median / p95) | 1.5 / 2.0 ms | 2.5 / 3.7 ms |
| Query embedding, Korean (median / p95) | 2.6 / 4.2 ms | 2.5 / 3.6 ms |
| Whole query: embedding, search and reading the chunks, top 5 (p95) | 3.5–4.7 ms | 4.7–4.8 ms |
| Ingestion per chunk | 4.7 ms | 6.4 ms |
| `initialize`, first launch / later launches | 425 / 111 ms | 859 / 160 ms |
| Memory added by `initialize` / peak RSS | 134 / 242 MB | 197 / 314 MB |

The first launch includes installing the Model Pack. Korean queries take the
same time with both models, because MiniLM splits Korean into about 2.5 times
as many tokens.

Conditions: iPhone 17 (iOS 27.0.1), profile build, engine commit `ffb0ab8`,
example app (hybrid weights 0.2 / 0.8 for MiniLM, 0.5 / 0.5 for
KoEn-E5-Tiny), 2026-11-16. Records:
[`multilingual-embedding` section 6](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/perf/multilingual-embedding/README.md#6-iphone-실기기-측정-m5-2026-11-16).

## Text-layer PDFs

`sample_eng.pdf` and `sample_kor.pdf` from `example/`: 8 of 8 questions written
from the PDFs reached the source, the answer passage and answerable context in
the top 10. Scanned or image-only PDFs are reported as extraction errors so your
app can route them to an OCR step.

## Measurement records

Run logs, harness settings and model fingerprints are in
[`docs/perf/`](https://github.com/dev07060/mobile_rag_engine/tree/main/docs/perf),
for example
[`passage-benchmark-2026-11`](https://github.com/dev07060/mobile_rag_engine/tree/main/docs/perf/passage-benchmark-2026-11),
[`f2-fusion`](https://github.com/dev07060/mobile_rag_engine/tree/main/docs/perf/f2-fusion)
and
[`multilingual-embedding`](https://github.com/dev07060/mobile_rag_engine/tree/main/docs/perf/multilingual-embedding).

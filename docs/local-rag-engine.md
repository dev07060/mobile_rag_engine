# Flutter Local RAG Engine Guide

This guide explains how to build local, on-device RAG in Flutter with
`mobile_rag_engine`.

Korean search intent: **Flutter 로컬 RAG 구현 방법**, **Flutter 온디바이스
RAG 패키지**, **Dart 로컬 문서 검색**, **Flutter PDF RAG**.

## What This Package Does

`mobile_rag_engine` provides the retrieval layer for local RAG apps:

- document ingest from local text-layer PDF, Markdown, plain text, and DOCX;
- chunking and embedding on the device;
- SQLite-backed document and chunk storage;
- HNSW vector search plus BM25 keyword search;
- RRF-based hybrid ranking;
- context assembly for an LLM prompt.

It does not bundle an LLM or OCR engine. Your app can pair the retrieved context
with a local model, remote model, or custom OCR pipeline.

## Basic Local RAG Flow

```dart
await MobileRag.initialize(
  tokenizerAsset: 'assets/tokenizer.json',
  modelAsset: 'assets/model.onnx',
  deferIndexWarmup: true,
);

await MobileRag.instance.addDocumentFromFile(
  '/path/to/manual.pdf',
  name: 'manual.pdf',
);

final result = await MobileRag.instance.search(
  'What does the manual say about setup?',
  tokenBudget: 2000,
);

final contextForLlm = result.context.text;
```

For full setup instructions, see [Quick Start](guides/quick_start.md) and
[Model Setup](guides/model_setup.md).

## Architecture

```text
Local file / text
  -> parser
  -> chunker
  -> embedding model
  -> SQLite chunks + metadata
  -> HNSW vector index + BM25 keyword index
  -> hybrid retrieval
  -> LLM-ready context
```

The public Dart API stays small while the hot path runs in Rust. This is useful
for Flutter apps that need private local search without running a backend vector
database.

## Supported vs Still Being Validated

| Area | Status | Notes |
|:-----|:-------|:------|
| Local document retrieval in Flutter | Supported | Use `MobileRag.initialize`, `addDocument`, `addDocumentFromFile`, and `search`. |
| Offline semantic search | Supported | Retrieval runs locally after model/tokenizer assets are bundled. |
| Hybrid search | Supported and benchmarked | HNSW vector search, BM25 keyword search, and RRF fusion are available through the default hybrid path. |
| Passage/context retrieval quality | Verified on benchmark fixtures | The 80-query passage benchmark with the default hybrid profile measured `passage_recall@10 = 0.9375` and `answerable_context@10 = 0.9125` with the default MiniLM Model Pack, and `0.9625` / `0.975` with KoEn-E5-Tiny. BGE-m3 (569 MB, for reference) measured `0.975` / `0.9875`. MiniLM is English-only: its vector search alone found 11 of 32 Korean queries. For Korean documents, follow the [KoEn-E5-Tiny recipe](guides/model_setup.md#korean-documents-koen-e5-tiny). Conditions are below the table. |
| Text-layer PDF-to-RAG | Verified on sample scope | The PDF-to-RAG smoke run covered `sample_eng.pdf` and `sample_kor.pdf`; all 8 PDF-derived queries reached source, passage, and answerable context at top-10. |
| Scanned/image-only PDFs | Detected, OCR not bundled | Extraction errors are classified as OCR-required so your UI can route to an OCR workflow. |
| Large/table-heavy/OCR-heavy PDFs | Still being validated | Do not generalize the two-sample PDF smoke result to every PDF layout or mobile memory/latency condition. |
| LLM generation | App responsibility | This package returns context; your app chooses the LLM. |

Passage numbers: 80 queries (32 English, 32 Korean, 16 multilingual), a fresh
database per model, profile build on an Apple Silicon Mac, measured 2026-11-12.
They include a vector-index fix that reaches pub.dev users with the next
`rag_engine_flutter` release. The earlier `0.925` / `0.938` in this guide was
measured with BGE-m3 in June 2026, not with the default model. Full conditions
and per-language results are in the
[passage benchmark report](perf/passage-benchmark-2026-11/README.md).

## PDF-to-RAG Boundary

The current PDF claim should be worded narrowly:

> In a profile-mode macOS run, `sample_eng.pdf` and `sample_kor.pdf` were parsed
> through the real PDF parser and `addDocumentFromFile()`. The shipped default
> hybrid profile retrieved the expected source, answer-bearing passage, and
> assembled context for 8/8 PDF-derived queries at top-10.

The current PDF claim should not be expanded to:

> All PDF document processing quality is validated.

Scanned/image-only PDFs require OCR before indexing. Table-heavy PDFs, very
large reports, layout-noisy documents, and mobile latency/memory behavior should
be validated separately.

## When To Use It

Use this package when you want:

- a local RAG engine inside a Flutter app;
- private document search without uploading user data;
- chat-with-document or chat-with-PDF retrieval;
- on-device semantic search with keyword fallback;
- a Dart API over a Rust retrieval core.

Use a server-side RAG stack instead when you need centralized multi-user
indexing, managed OCR at scale, or large shared vector databases.

## Related Docs

- [README](../README.md)
- [Quick Start](guides/quick_start.md)
- [Search Strategies](features/search_strategies.md)
- [Search by Source](features/search_by_source.md)
- [Troubleshooting](guides/troubleshooting.md)
- [Passage Benchmark Report (2026-11, per model)](perf/passage-benchmark-2026-11/README.md)
- [P5-4 Expanded Passage Relevance Report](perf/ondevice-query-profiler/PR-P5-4-expanded-passage-relevance.html)
- [P5-5 PDF-to-RAG Passage Relevance Report](perf/ondevice-query-profiler/PR-P5-5-pdf-to-rag-passage-relevance.html)

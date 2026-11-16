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
  modelPack: const RagModelPack.asset('assets/mobile_rag/model-pack.json'),
);

await MobileRag.instance.addDocumentFromFile(
  '/path/to/manual.pdf',
  name: 'manual.pdf',
);

final result = await MobileRag.instance.searchHybridWithContext(
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
| Hybrid search | Supported and benchmarked | HNSW vector search, BM25 keyword search, and RRF fusion are used by `searchHybridWithContext`, `searchHybrid` and `ask`; `search` is vector-only. |
| Passage/context retrieval quality | Verified on benchmark fixtures | The 80-query passage benchmark with the default hybrid profile measured `passage_recall@10 = 0.925` and `answerable_context@10 = 0.900` with the default MiniLM Model Pack, and `0.950` / `0.9625` with KoEn-E5-Tiny. BGE-m3 (569 MB, for reference) measured `0.9625` / `0.9625` (2026-11-13). MiniLM is English-only: its vector search alone found 11 of 32 Korean queries. For Korean documents, follow the [KoEn-E5-Tiny recipe](guides/model_setup.md#korean-documents-koen-e5-tiny). Conditions are below the table. |
| Text-layer PDF-to-RAG | Verified on sample scope | The PDF-to-RAG smoke run covered `sample_eng.pdf` and `sample_kor.pdf`; all 8 PDF-derived queries reached source, passage, and answerable context at top-10 (model and date not recorded). |
| Scanned/image-only PDFs | Detected, OCR not bundled | Extraction errors are classified as OCR-required so your UI can route to an OCR workflow. |
| Large/table-heavy/OCR-heavy PDFs | Still being validated | Do not generalize the two-sample PDF smoke result to every PDF layout or mobile memory/latency condition. |
| LLM generation | App responsibility | This package returns context; your app chooses the LLM. |

Passage numbers: 80 queries (32 English, 32 Korean, 16 mixed), a fresh
database per model, top 10 of 100 results, profile build on an Apple M3 Pro
Mac, `mobile_rag_engine` 0.24.0 code, measured 2026-11-16 (BGE-m3 2026-11-13).

## PDF-to-RAG Boundary

PDF support is verified on two sample PDFs (`sample_eng.pdf`, `sample_kor.pdf`).
Scanned or image-only PDFs need OCR before indexing. Table-heavy PDFs, very
large reports and layout-noisy documents are not verified.

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

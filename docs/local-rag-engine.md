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

## What's Supported

| Area | Status | Notes |
|:-----|:-------|:------|
| Local document retrieval in Flutter | Supported | Use `MobileRag.initialize`, `addDocument`, `addDocumentFromFile`, and `search`. |
| Offline semantic search | Supported | Retrieval runs locally once the model files are on the device. |
| Hybrid search | Supported and benchmarked | HNSW vector search, BM25 keyword search, and RRF fusion are used by `searchHybridWithContext`, `searchHybrid` and `ask`; `search` is vector-only. |
| Text-layer PDF, DOCX, Markdown, plain text | Supported | PDF and DOCX text is extracted on the device. |
| Scanned/image-only PDFs | Detected, OCR not bundled | Extraction errors are classified as OCR-required so your UI can route to an OCR workflow. |
| LLM generation | Your choice of LLM | This package returns context and calls the generation function you pass to `ask`. |

On an 80-question English/Korean benchmark, the right passage is in the top 10
for 92.5% of questions with the default MiniLM Model Pack, 95% with
KoEn-E5-Tiny and 96.25% with BGE-m3. For Korean documents, use
[KoEn-E5-Tiny](guides/model_setup.md#korean-documents-koen-e5-tiny). Results on
public datasets and the measurement conditions are in
[Benchmarks](benchmarks.md).

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

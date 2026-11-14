# Mobile RAG Engine Example

This example demonstrates the `mobile_rag_engine` package with the `MobileRag` facade.

## Choosing a model

The app initializes from a Model Pack and picks the model at build time:

| `--dart-define=EXAMPLE_MODEL=` | Model | Languages | Hybrid weights the app sets |
|---|---|---|---|
| `minilm` (default) | MiniLM, the default Model Pack | English | none, the engine default (vector 0.2 / BM25 0.8) |
| `koen` | KoEn-E5-Tiny | Korean, English | vector 0.5 / BM25 0.5, from the [KoEn-E5-Tiny recipe](../docs/guides/model_setup.md#korean-documents-koen-e5-tiny) |

```dart
await MobileRag.initialize(
  modelPack: const RagModelPack.asset('assets/models/koen/model-pack.json'),
  defaultVectorWeight: 0.5,
  defaultBm25Weight: 0.5,
);
```

See `lib/example_model.dart`. Each model uses its own database file, because
vectors from different models cannot be mixed.

## Running the Example

1. Install the Model Pack for the model you want. Model files are not in git.
   - MiniLM, from `example/`:
     ```bash
     dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en --output assets/models/minilm --skip-host-config
     ```
   - KoEn-E5-Tiny: follow `assets/models/koen/README.md`.

2. Run:
   ```bash
   flutter run --dart-define=EXAMPLE_MODEL=minilm
   ```

## Screens

- **Main screen:** add text or a file (PDF, DOCX, Markdown, text), search, list and delete sources, switch collections.
- **App docs (E1 questions)** in the menu: adds the E1 document set (GNOME Help pages, short app and office documents, the two sample PDFs; English and Korean) and lets you ask its 120 questions, or your own. Pick a weight setting (app default, 0.2 / 0.8, 0.5 / 0.5, 0.6 / 0.4, vector only, BM25 only) to see the top 5 that `ask` would use and whether the answer is among them. The measured results are in [`docs/perf/e1-app-docs/`](../docs/perf/e1-app-docs/README.md).
- **Chunking Test, Benchmark, Quality Test:** developer tools.

## Licenses of the bundled documents

- `assets/corpus/e1/gnome/`: GNOME Help pages, CC BY-SA 3.0 Unported. Authors, translators and the source URL are in each file's header.
- `assets/corpus/e1/own/`: short fictional documents written for this repository (MIT).
- `assets/corpus/en/`, `assets/corpus/ko/`: Wikipedia articles, CC BY-SA 4.0 (see `assets/corpus/README.md`).

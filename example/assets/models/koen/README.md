# KoEn-E5-Tiny Model Pack (not in git)

From `example/`, install the files here with:

```bash
dart run mobile_rag_engine:setup --preset koen-e5-tiny-arm64-koen --output assets/models/koen --skip-host-config
```

It writes `model.onnx`, `tokenizer.json` and `model-pack.json` with
`modelAsset` / `tokenizerAsset` already pointing at `assets/models/koen/`.

Then run the app with `--dart-define=EXAMPLE_MODEL=koen`. The app initializes
with this example's hybrid weights (vector 0.5 / BM25 0.5).

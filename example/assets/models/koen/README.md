# KoEn-E5-Tiny Model Pack (not in git)

Put `model.onnx`, `tokenizer.json` and `model-pack.json` here, following the
KoEn-E5-Tiny recipe in `docs/guides/model_setup.md`. In `model-pack.json`, set
`modelAsset` to `assets/models/koen/model.onnx` and `tokenizerAsset` to
`assets/models/koen/tokenizer.json`.

Then run the app with `--dart-define=EXAMPLE_MODEL=koen`. The app initializes
with the recipe's hybrid weights (vector 0.5 / BM25 0.5).

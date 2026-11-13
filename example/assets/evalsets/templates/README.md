# Evalset Templates

This folder provides drop-in templates for dataset onboarding.

Files:
- `sources_manifest.template.json`: source manifest template
- `sources_manifest.schema.json`: JSON schema for source manifest
- `evalset.template.jsonl`: 10-line query evalset sample
- `evalset.schema.json`: JSON schema for each JSONL line
- `chunk_gold.template.jsonl`: 10-line chunk quality sample
- `chunk_gold.schema.json`: JSON schema for each JSONL line

Quick usage:
1. Copy `sources_manifest.template.json` and `evalset.template.jsonl`.
2. Replace `dataset_id`, `source_key`, and `file_path` values.
3. Keep `expected_source_key` and `hard_negative_source_keys` aligned with manifest keys.
4. Run offline evaluation with:
   - `EVALSET_MANIFEST_ASSET=assets/evalsets/<your_manifest>.json`
   - `EVALSET_JSONL_ASSET=assets/evalsets/<your_evalset>.jsonl`

Notes:
- `offline_eval_runner` currently reads manifest + evalset only.
- `chunk_gold.template.jsonl` is for chunk-level quality expansion and reporting.

Validation:
- Bundle validation script:
  - `python3 scripts/validate_evalset_bundle.py --manifest example/assets/evalsets/templates/sources_manifest.template.json --evalset example/assets/evalsets/templates/evalset.template.jsonl --chunk-gold example/assets/evalsets/templates/chunk_gold.template.jsonl`

Seed generation from real manifest:
- `python3 scripts/generate_evalset_seed.py --manifest example/assets/evalsets/templates/sources_manifest.json --out-evalset example/assets/evalsets/templates/wiki_article_evalset_seed_v1.jsonl --out-chunk-gold example/assets/evalsets/templates/wiki_article_chunk_gold_seed_v1.jsonl --total 800 --chunk-gold-max 400 --seed 42`

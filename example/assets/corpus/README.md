# Search evaluation corpus

Documents used by the search evaluation harness
(`example/integration_test/hybrid_passage_relevance_measure_test.dart`).
See `docs/milestones.md` (F1) and `docs/perf/f1-eval-baseline/`.

These files are not bundled into the example app: `example/pubspec.yaml`
declares only `assets/`, and Flutter does not include subdirectories of a
declared asset directory. They are not part of the published package either
(`.pubignore` excludes `example/assets/`).

## `en/`, `ko/` — Wikipedia articles (CC BY-SA 4.0)

**License: these files are NOT under this repository's MIT license.** They are
text from Wikipedia, licensed under the
[Creative Commons Attribution-ShareAlike 4.0 License](https://creativecommons.org/licenses/by-sa/4.0/).
If you redistribute or adapt them, the same license applies.

- 300 articles (English 105, Korean 195) from en.wikipedia.org and
  ko.wikipedia.org, collected on 2026-02-22.
- Attribution: the authors are the contributors to each article. The article
  URL and the `revision_id` of the version used are listed for every file in
  `../evalsets/wiki_article_sources_manifest_v1.json`; each article's history
  page on Wikipedia lists its contributors.
- Changes: each article was converted to Markdown (the conversion script was not kept) and
  given a short metadata header (title, `source_key`, language, domain, length
  bucket, collection date, URL) followed by `---`.

## `f1_short/` — short documents written for this repository (MIT)

16 short FAQ, memo, manual, policy and release-note style documents
(English 8, Korean 8), written for the F1 evaluation (2026-11-13). They are
fictional and are covered by this repository's MIT license.

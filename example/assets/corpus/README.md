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

## `e1/` — E1 app-document set

Used by the E1 evaluation (`docs/milestones.md` E1, `docs/perf/e1-app-docs/`)
and by the example app's "App docs" screen. Rebuild the bundle with
`scripts/e1/build_e1_bundle.py`.

- `e1/gnome/en/`, `e1/gnome/ko/` — **not MIT.** 30 pages of GNOME Help
  (https://help.gnome.org/gnome-help/), English 15 and Korean 15, licensed under
  [CC BY-SA 3.0 Unported](https://creativecommons.org/licenses/by-sa/3.0/).
  Fetched 2026-11-14. Each file's header names the page URL, authors,
  editors and translators and the changes made: the article body was converted
  to Markdown, navigation, link lists and the footer were removed, and on
  Korean pages blocks left untranslated in English were removed (the count is
  in the header). `scripts/e1/gnome_help_to_md.py` does the conversion;
  `e1/gnome/gnome_pages_v1.json` lists the pages with hashes of the fetched
  HTML.
- `e1/own/en/`, `e1/own/ko/` — 24 short fictional documents (app FAQ, release
  notes, troubleshooting, internal policies and meeting notes; English 12,
  Korean 12), written for E1 on 2026-11-14 and covered by this repository's
  MIT license.
- The two large documents are `../sample_data/sample_eng.pdf` and
  `../sample_data/sample_kor.pdf`.

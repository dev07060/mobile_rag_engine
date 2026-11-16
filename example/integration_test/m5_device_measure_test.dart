// M5 (docs/milestones.md): iPhone measurement for one Model Pack per install.
//
// First launch after install:
//   initialize time and memory, E1 app-document ingestion (time, chunks,
//   memory), warm query embedding by language (E1 questions), warm query
//   segments by language (E1 collection), and the synthetic two-collection
//   fixture's segments (pure_cold / pure_warm / switching_cold).
// Second launch (start the installed app again, without reinstalling):
//   initialize time and memory with the database from the first launch, and
//   the first query after the restart (cold activate) in the E1 collection.
//
// Results go to Documents/m5_<model>_<launch>_<ts>.json (and to the log as
// `M5_JSON` lines when a debugger is attached). The second launch is detected
// by the marker file Documents/m5_<model>_first_done.json, which the first
// launch writes last.
//
// The test needs no driver, so a profile build can be installed and started
// directly (this is how M5 ran on an iPhone, docs/milestones.md):
//
//   cd example && flutter build ios --profile \
//     -t integration_test/m5_device_measure_test.dart \
//     --dart-define=EXAMPLE_MODEL=minilm|koen \
//     --dart-define=ENGINE_COMMIT=$(git rev-parse HEAD) \
//     --dart-define=DEVICE_LABEL=... --dart-define=HOST_TOOLCHAIN=... \
//     --dart-define=RUN_NOTE=...
//   xcrun devicectl device uninstall app --device <id> com.example.mobileRagEngineExample
//   xcrun devicectl device install app --device <id> build/ios/iphoneos/Runner.app
//   xcrun devicectl device process launch --device <id> com.example.mobileRagEngineExample
//   # second launch: the same launch command with --terminate-existing
//   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
//     --domain-identifier com.example.mobileRagEngineExample \
//     --source Documents/<result file> --destination .
//
// `flutter drive --profile` with the same target also works where the Dart VM
// can be reached. Profile mode only: debug builds use the fallback Rust
// backend. A simulator rehearsal may pass --dart-define=M5_REHEARSAL=true to
// run in debug; its numbers are marked `rehearsal` and are not results.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart' as rust_tok;
import 'package:mobile_rag_engine_example/e1/app_docs_bundle.dart';
import 'package:mobile_rag_engine_example/example_model.dart';
import 'package:mobile_rag_engine_example/profiling/fixture_cells.dart';
import 'package:mobile_rag_engine_example/profiling/query_fixture.dart';
import 'package:mobile_rag_engine_example/profiling/query_profile_report.dart';
import 'package:mobile_rag_engine_example/profiling/query_profiler.dart';
import 'package:mobile_rag_engine_example/profiling/rss_sampler.dart';
import 'package:mobile_rag_engine_example/profiling/run_conditions.dart';
import 'package:path_provider/path_provider.dart';

const _rehearsal = bool.fromEnvironment('M5_REHEARSAL');
const _fixtureDocs = 500; // per collection, as query_profile_measure_test
const _warmup = 5;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('M5 device measurement', () async {
    if (kDebugMode && !_rehearsal) {
      fail(
        'M5 measures profile builds only (flutter drive --profile). '
        'Debug uses the fallback Rust backend.',
      );
    }
    final model = resolveExampleModel();
    final docs = await getApplicationDocumentsDirectory();
    final marker = File('${docs.path}/m5_${model.id}_first_done.json');
    final secondLaunch = await marker.exists();
    final prefix = 'm5_${model.id}';

    if (!secondLaunch) {
      // Start from an empty database (this model's files only).
      for (final e in docs.listSync()) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name.startsWith(prefix) && e is File) await e.delete();
      }
    }
    final entriesBeforeInit = [
      for (final e in docs.listSync())
        e.uri.pathSegments.where((s) => s.isNotEmpty).last,
    ]..sort();

    // --- initialize ------------------------------------------------------
    final initRss = PeriodicRss.start();
    final initWatch = Stopwatch()..start();
    await model.initialize(databaseName: 'm5.sqlite');
    final initMs = initWatch.elapsedMicroseconds / 1000.0;
    final result = <String, Object?>{
      'milestone': 'M5',
      'launch': secondLaunch ? 'second' : 'first',
      'rehearsal': _rehearsal,
      'conditions': await collectRunConditions(model),
      'documents_entries_before_init': entriesBeforeInit,
      'init_ms': initMs,
      ...initRss.finish(prefix: 'rss_init'),
      'rss_after_init_bytes': ProcessInfo.currentRss,
      'fingerprint_lock': MobileRag.instance.embeddingFingerprintLock
          ?.toString(),
    };
    expect(MobileRag.instance.embeddingFingerprintLock, isNull);

    final bundle = await E1Bundle.load();
    final (vectorWeight, bm25Weight) = model.effectiveWeights;
    final profiler = QueryProfiler(
      dbPath: MobileRag.instance.dbPath,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
    );

    if (secondLaunch) {
      // First query after the restart: the E1 index is loaded from disk.
      final ko = bundle.questions.firstWhere(
        (q) => q.language == 'ko' && q.hasAnswer,
      );
      final en = bundle.questions.firstWhere(
        (q) => q.language == 'en' && q.hasAnswer,
      );
      final cold = await profiler.measureOnce(
        collectionId: e1CollectionId,
        query: ko.query,
        activate: true,
        topK: 5,
      );
      final next = await profiler.measureOnce(
        collectionId: e1CollectionId,
        query: en.query,
        topK: 5,
      );
      expect(cold.hitSourceIds, isNotEmpty);
      expect(next.hitSourceIds, isNotEmpty);
      result['e1_sources_after_restart'] =
          (await bundle.collection.listSources()).length;
      result['first_query_after_restart'] = {
        'query_id': ko.id,
        'ms': cold.ms,
        'hits': cold.hitSourceIds.length,
        'activation': _plain(cold.activation),
      };
      result['second_query_after_restart'] = {
        'query_id': en.id,
        'ms': next.ms,
        'hits': next.hitSourceIds.length,
      };
      result['rss_after_queries_bytes'] = ProcessInfo.currentRss;
      result['process_max_rss_bytes'] = ProcessInfo.maxRss;
      await _write(docs, prefix, 'second', result);
      return;
    }

    // --- E1 ingestion ----------------------------------------------------
    final tempDir = await getTemporaryDirectory();
    final perSource = <Map<String, Object?>>[];
    final ingestRss = PeriodicRss.start();
    final ingestWatch = Stopwatch()..start();
    var addMsTotal = 0.0;
    for (final source in bundle.sources) {
      final data = await rootBundle.load(source.filePath);
      final safe = source.filePath.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File('${tempDir.path}/m5_$safe');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      final sw = Stopwatch()..start();
      final r = await bundle.collection.addDocumentFromFile(
        file.path,
        name: source.key,
        metadata: jsonEncode({
          'source_key': source.key,
          'language': source.language,
        }),
      );
      final ms = sw.elapsedMicroseconds / 1000.0;
      addMsTotal += ms;
      await file.delete();
      expect(r.isDuplicate, isFalse, reason: source.key);
      perSource.add({
        'key': source.key,
        'language': source.language,
        'bytes': data.lengthInBytes,
        'chunks': r.chunkCount,
        'add_ms': ms,
      });
    }
    final rebuildWatch = Stopwatch()..start();
    await bundle.collection.rebuildIndex(force: true);
    final rebuildMs = rebuildWatch.elapsedMicroseconds / 1000.0;
    final ingestTotalMs = ingestWatch.elapsedMicroseconds / 1000.0;
    final chunks = perSource.fold<int>(0, (a, s) => a + (s['chunks'] as int));
    final sourcesListed = (await bundle.collection.listSources()).length;
    expect(sourcesListed, bundle.sources.length);
    result['e1_ingest'] = {
      'sources': bundle.sources.length,
      'sources_listed': sourcesListed,
      'chunks': chunks,
      'total_ms_including_asset_copy_and_rebuild': ingestTotalMs,
      'add_document_ms_sum': addMsTotal,
      'rebuild_index_ms': rebuildMs,
      'add_document_ms_per_chunk': addMsTotal / chunks,
      'by_language': {
        for (final lang in ['en', 'ko'])
          lang: _ingestSummary(
            perSource.where((s) => s['language'] == lang).toList(),
          ),
      },
      'per_source': perSource,
      ...ingestRss.finish(prefix: 'rss_ingest'),
    };

    // --- warm query embedding by language --------------------------------
    final embedRss = PeriodicRss.start();
    for (var i = 0; i < _warmup; i++) {
      await EmbeddingService.embed(bundle.questions[i].query);
    }
    final embedByLang = {
      'en': SegmentSamples('embed_en'),
      'ko': SegmentSamples('embed_ko'),
    };
    final tokensByLang = <String, List<int>>{'en': [], 'ko': []};
    for (final q in bundle.questions) {
      tokensByLang[q.language]!.add(rust_tok.countTokens(text: q.query));
      final sw = Stopwatch()..start();
      await EmbeddingService.embed(q.query);
      embedByLang[q.language]!.add(sw.elapsedMicroseconds / 1000.0);
    }
    result['e1_query_embed_warm'] = {
      for (final lang in ['en', 'ko'])
        lang: {
          ...embedByLang[lang]!.toJson(),
          'tokens_mean': _mean(tokensByLang[lang]!),
          'tokens_max': tokensByLang[lang]!.reduce((a, b) => a > b ? a : b),
          'samples_ms': embedByLang[lang]!.samplesMs,
        },
      ...embedRss.finish(prefix: 'rss_embed'),
    };

    // --- warm query segments by language (E1 collection, top 5 as ask) ---
    final queryRss = PeriodicRss.start();
    await profiler.activateOnly(e1CollectionId);
    for (var i = 0; i < _warmup; i++) {
      await profiler.measureOnce(
        collectionId: e1CollectionId,
        query: bundle.questions[i].query,
        topK: 5,
      );
    }
    final segByLang = {
      for (final lang in ['en', 'ko'])
        lang: {
          for (final s in ['embed', 'search', 'hydrate']) s: SegmentSamples(s),
          'total': SegmentSamples('total'),
        },
    };
    var emptyAnswerable = 0;
    for (final q in bundle.questions) {
      final r = await profiler.measureOnce(
        collectionId: e1CollectionId,
        query: q.query,
        topK: 5,
      );
      final segs = segByLang[q.language]!;
      r.ms.forEach((k, v) => segs[k]?.add(v));
      segs['total']!.add(r.ms.values.fold(0.0, (a, b) => a + b));
      if (q.hasAnswer && r.hitSourceIds.isEmpty) emptyAnswerable++;
    }
    expect(emptyAnswerable, 0);
    result['e1_query_segments_warm'] = {
      for (final lang in ['en', 'ko'])
        lang: {
          for (final e in segByLang[lang]!.entries) e.key: e.value.toJson(),
        },
      ...queryRss.finish(prefix: 'rss_query'),
    };

    // --- synthetic fixture: cold / warm / switching segments --------------
    final seedRss = PeriodicRss.start();
    final seedWatch = Stopwatch()..start();
    final ids = await QueryFixture.seed(docsPerCollection: _fixtureDocs);
    final seedMs = seedWatch.elapsedMicroseconds / 1000.0;
    final seedMem = seedRss.finish(prefix: 'rss_fixture_seed');
    final cellsRss = PeriodicRss.start();
    final runs = await runFixtureCells(
      profiler: profiler,
      sourceIds: ids,
      meta: const {},
    );
    final report = QueryProfileReport(runs: runs);
    result['fixture'] = {
      'docs_per_collection': _fixtureDocs,
      'seed_ms': seedMs,
      ...seedMem,
      'cells': [
        for (final r in report.toJson()['runs'] as List)
          Map<String, Object?>.from(r as Map)..remove('meta'),
      ],
      ...cellsRss.finish(prefix: 'rss_fixture_cells'),
    };
    result['process_max_rss_bytes'] = ProcessInfo.maxRss;

    await _write(docs, prefix, 'first', result);
    await marker.writeAsString(
      jsonEncode({'at': DateTime.now().toUtc().toIso8601String()}),
      flush: true,
    );
  }, timeout: const Timeout(Duration(minutes: 60)));
}

Map<String, Object?> _ingestSummary(List<Map<String, Object?>> rows) {
  final chunks = rows.fold<int>(0, (a, s) => a + (s['chunks'] as int));
  final ms = rows.fold<double>(0, (a, s) => a + (s['add_ms'] as double));
  return {
    'sources': rows.length,
    'chunks': chunks,
    'add_document_ms_sum': ms,
    'add_document_ms_per_chunk': chunks == 0 ? null : ms / chunks,
  };
}

double _mean(List<int> xs) => xs.fold<int>(0, (a, b) => a + b) / xs.length;

Map<String, Object?> _plain(Map<String, Object?> m) => {
  for (final e in m.entries)
    e.key: e.value is BigInt ? (e.value as BigInt).toInt() : e.value,
};

Future<void> _write(
  Directory docs,
  String prefix,
  String launch,
  Map<String, Object?> result,
) async {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final path = '${docs.path}/${prefix}_${launch}_$ts.json';
  final text = const JsonEncoder.withIndent(' ').convert(result);
  await File(path).writeAsString(text, flush: true);
  // ignore: avoid_print
  print('M5_FILE $path');
  // One print per line: the device log truncates long lines.
  for (final line in text.split('\n')) {
    // ignore: avoid_print
    print('M5_JSON $line');
  }
}

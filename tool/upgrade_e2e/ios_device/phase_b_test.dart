// Phase B (package under test, installed over phase A): the app opens the
// release's database without a lock, keeps the documents and still finds them.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

import 'upgrade_common.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M5 upgrade phase B', (tester) async {
    final state = await stateFile();
    expect(await state.exists(), isTrue, reason: 'phase A data is missing');
    final before = jsonDecode(await state.readAsString()) as Map;

    final watch = Stopwatch()..start();
    await initializeEngine();
    final initMs = watch.elapsedMilliseconds;
    final lock = MobileRag.instance.embeddingFingerprintLock;
    final sources = [
      for (final s in await MobileRag.instance.listSources()) s.name,
    ]..sort();
    final top = await topSources();
    final checks = {
      'initialized': true,
      'lock_is_null': lock == null,
      'sources_kept': jsonEncode(sources) == jsonEncode(before['sources']),
      'search_returns_results': top.values.every((v) => (v as List).isNotEmpty),
      'top_source_unchanged': [
        for (final q in queries)
          (top[q] as List).first == (before['top_sources'][q] as List).first,
      ].every((same) => same),
    };
    final record = {
      'init_ms': initMs,
      'fingerprint_before': before['fingerprint'],
      'fingerprint_after': MobileRag.instance.currentEmbeddingFingerprint,
      'lock': lock?.toString(),
      'sources': sources,
      'top_sources_before': before['top_sources'],
      'top_sources_after': top,
      'checks': checks,
    };
    await (await resultFile()).writeAsString(jsonEncode(record), flush: true);
    log('PHASE_B ${jsonEncode(record)}');
    for (final c in checks.entries) {
      expect(c.value, isTrue, reason: c.key);
    }
  });
}

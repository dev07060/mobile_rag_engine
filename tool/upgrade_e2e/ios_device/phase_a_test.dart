// Phase A (last release): index the documents and record what search returns.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

import 'upgrade_common.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M5 upgrade phase A', (tester) async {
    final state = await stateFile();
    expect(await state.exists(), isFalse, reason: 'start from a fresh install');
    await initializeEngine();
    for (final e in documents.entries) {
      final r = await MobileRag.instance.addDocument(e.value, name: e.key);
      expect(r.isDuplicate, isFalse);
    }
    await MobileRag.instance.rebuildIndex();
    final sources = [
      for (final s in await MobileRag.instance.listSources()) s.name,
    ]..sort();
    final top = await topSources();
    final record = {
      'fingerprint': MobileRag.instance.currentEmbeddingFingerprint,
      'sources': sources,
      'top_sources': top,
    };
    await state.writeAsString(jsonEncode(record), flush: true);
    log('PHASE_A ${jsonEncode(record)}');
    expect(sources.length, documents.length);
  });
}

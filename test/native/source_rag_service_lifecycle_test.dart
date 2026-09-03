import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/logger.dart';
import 'package:mobile_rag_engine/src/rust/api/migration_meta.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';

Future<void> _ensureRustLoaded() async {
  if (!RustLib.instance.initialized) {
    await RustLib.init();
  }
}

void main() {
  setUpAll(() async {
    await _ensureRustLoaded();
  });

  test('SourceRagService.dispose closes log stream without hanging', () async {
    final dir = await Directory.systemTemp.createTemp(
      'mobile_rag_source_lifecycle_',
    );
    final dbPath = '${dir.path}/source_lifecycle.sqlite';
    final service = SourceRagService(dbPath: dbPath);

    try {
      await initDbPool(dbPath: dbPath, maxSize: 2);
      await service.init(deferIndexWarmup: false);

      await service.dispose().timeout(const Duration(seconds: 2));
    } finally {
      try {
        closeLogStream();
      } catch (_) {}
      try {
        await closeDbPool();
      } catch (_) {}
      await dir.delete(recursive: true);
    }
  });

  test(
    'deferred warmup starts after fresh-database fingerprint initialization',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'mobile_rag_deferred_warmup_',
      );
      final dbPath = '${dir.path}/deferred_warmup.sqlite';
      final service = SourceRagService(dbPath: dbPath);
      const fingerprint = 'model.onnx|384|q8_0';
      var fingerprintReady = false;

      try {
        await initDbPool(dbPath: dbPath, maxSize: 2);
        await service.initForEngine(
          deferIndexWarmup: true,
          afterDatabaseInitialized: () async {
            final gate = await detectEmbeddingFingerprintGate(
              currentFingerprint: fingerprint,
            );
            expect(
              gate,
              isA<EmbeddingFingerprintGate_RequiresInitialBaseline>(),
            );
            await writeEmbeddingFingerprint(fingerprint: fingerprint);
            fingerprintReady = true;
          },
        );

        expect(
          fingerprintReady,
          isTrue,
          reason: 'database boot work must finish before init returns',
        );
        await service.warmupFuture;

        final gate = await detectEmbeddingFingerprintGate(
          currentFingerprint: fingerprint,
        );
        expect(gate, isA<EmbeddingFingerprintGate_Ok>());
        expect(service.isIndexReady, isTrue);
      } finally {
        try {
          await service.warmupFuture;
        } catch (_) {}
        try {
          await service.dispose();
        } catch (_) {}
        try {
          closeLogStream();
        } catch (_) {}
        try {
          await closeDbPool();
        } catch (_) {}
        await dir.delete(recursive: true);
      }
    },
  );
}

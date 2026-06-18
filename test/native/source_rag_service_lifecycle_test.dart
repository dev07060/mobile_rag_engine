import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/logger.dart';
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
}

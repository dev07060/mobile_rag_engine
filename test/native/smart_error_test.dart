import 'dart:io';
import 'dart:developer';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:mobile_rag_engine/src/rust/api/error.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';

void main() {
  test(
    'Smart Error Handling - Verify DatabaseError on missing pool',
    () async {
      // 1. Initialize FFI
      if (Platform.isMacOS) {
        await RustLib.init(
          externalLibrary: frb.ExternalLibrary.process(
            iKnowHowToUseIt: true,
          ),
        );
      } else {
        await RustLib.init();
      }

      // 2. Instantiate service *without* initializing DB Pool
      // This intentionally skips `initDbPool` to trigger the error check in Rust
      final service = SourceRagService(dbPath: 'test_dummy.db');

      // 3. Expect RagError
      try {
        await service.init();
        fail('Should have thrown RagError');
      } on RagError catch (e) {
        log('\n[Caught RagError Successfully]');

        e.when(
          databaseError: (msg) {
            log('✅ Type: DatabaseError');
            log('✅ Message: $msg');
            // Expect the message from get_connection() in db_pool.rs
            expect(msg, contains('DB pool not initialized'));
          },
          ioError: (msg) => fail('Unexpected IoError: $msg'),
          modelLoadError: (msg) => fail('Unexpected ModelLoadError: $msg'),
          invalidInput: (msg) => fail('Unexpected InvalidInput: $msg'),
          staleSearchHandle: (msg) =>
              fail('Unexpected StaleSearchHandle: $msg'),
          concurrentMutation: (msg) =>
              fail('Unexpected ConcurrentMutation: $msg'),
          internalError: (msg) => fail('Unexpected InternalError: $msg'),
          unknown: (msg) => fail('Unexpected Unknown error: $msg'),
        );
      }
    },
  );

  test(
    'Smart Error Handling - Verify RagError on listSources without DB',
    () async {
      final service = SourceRagService(dbPath: 'test_dummy_search.db');

      try {
        await service.listSources();
        fail('Should have thrown RagError');
      } on RagError catch (e) {
        log('\n[Caught RagError on listSources Successfully]');
        expect(e.message, contains('DB pool not initialized'));
      }
    },
  );
}

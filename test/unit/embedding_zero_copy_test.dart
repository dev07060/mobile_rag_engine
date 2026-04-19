import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/embedding_service.dart';

void main() {
  group('EmbeddingService zero-copy transport', () {
    test('embed() static signature returns Future<Float32List>', () {
      // Compile-time contract: guards against accidental return-type
      // widening back to List<double>, which would reintroduce the
      // f64 → f32 narrowing copy on every callsite.
      final Future<Float32List> Function(String) embedFn =
          EmbeddingService.embed;
      expect(embedFn, isNotNull);
    });

    test('embedBatch() static signature returns Future<List<Float32List>>', () {
      final Future<List<Float32List>> Function(
        List<String>, {
        int concurrency,
        void Function(int, int)? onProgress,
      })
      batchFn = EmbeddingService.embedBatch;
      expect(batchFn, isNotNull);
    });

    test(
      'TransferableTypedData round-trip preserves Float32List bit-exactly',
      () async {
        // Mirrors the worker→main transfer path used by the embed() worker
        // isolate: wrap a Float32List in TransferableTypedData, send it,
        // materialize on the receiver, and confirm values round-trip
        // without precision loss or truncation.
        final source = Float32List.fromList([
          0.0,
          1.0,
          -1.0,
          3.14159,
          -2.71828,
          1e-6,
          1e6,
        ]);

        final bridge = ReceivePort();
        bridge.sendPort.send(TransferableTypedData.fromList([source]));

        final received = await bridge.first as TransferableTypedData;
        bridge.close();

        final out = received.materialize().asFloat32List();
        expect(out, isA<Float32List>());
        expect(out.length, source.length);
        for (var i = 0; i < source.length; i++) {
          expect(out[i], source[i]);
        }
      },
    );

    test(
      'TransferableTypedData materialize() is single-shot and cannot be reused',
      () async {
        final source = Float32List.fromList([1.0, 2.0, 3.0]);
        final transferable = TransferableTypedData.fromList([source]);

        final first = transferable.materialize().asFloat32List();
        expect(first.length, 3);

        // Second materialize must throw; the worker relies on this
        // guarantee to avoid accidental double-consume bugs. The VM
        // raises ArgumentError on subsequent materialize calls.
        expect(() => transferable.materialize(), throwsArgumentError);
      },
    );
  });
}

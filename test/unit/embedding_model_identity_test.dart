import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/internal/embedding_fingerprint.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('model_identity_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, Uint8List bytes) {
    final file = File('${dir.path}/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  Uint8List bytes(int length, {int seed = 0}) =>
      Uint8List.fromList(List.generate(length, (i) => (i * 31 + seed) & 0xff));

  group('embeddingModelIdentity', () {
    test('depends on content, not on the file name', () async {
      final model = bytes(3 << 20);
      expect(
        await embeddingModelIdentity(write('a/model.onnx', model)),
        await embeddingModelIdentity(write('b/renamed.onnx', model)),
      );
    });

    test('differs for same-sized models with different weights', () async {
      // Two 384-dim exports both named model_qint8_arm64.onnx: same name and
      // dimension, different bytes at both ends of the file.
      final minilm = bytes(3 << 20);
      final koen = bytes(3 << 20, seed: 7);
      expect(
        await embeddingModelIdentity(write('x/model_qint8_arm64.onnx', minilm)),
        isNot(
          await embeddingModelIdentity(write('y/model_qint8_arm64.onnx', koen)),
        ),
      );
    });

    test('sees a change in the first or last MiB, or in the size', () async {
      final base = bytes(3 << 20);
      final id = await embeddingModelIdentity(write('base.onnx', base));

      final head = Uint8List.fromList(base)..[10] ^= 1;
      final tail = Uint8List.fromList(base)..[base.length - 10] ^= 1;
      final longer = Uint8List(base.length + 1)..setAll(0, base);
      for (final (name, changed) in [
        ('head.onnx', head),
        ('tail.onnx', tail),
        ('longer.onnx', longer),
      ]) {
        expect(
          await embeddingModelIdentity(write(name, changed)),
          isNot(id),
          reason: name,
        );
      }
    });

    test('handles files smaller than the sample size', () async {
      final id = await embeddingModelIdentity(write('tiny.onnx', bytes(100)));
      expect(id, startsWith('sha256:'));
      expect(id, isNot(contains('|')));
    });
  });

  group('computeEmbeddingFingerprint', () {
    test('appends the model identity as a fourth component', () {
      expect(
        computeEmbeddingFingerprint(
          modelBasename: 'model.onnx',
          dim: 384,
          quant: 'f32+vabq:none',
          modelIdentity: 'sha256:abc',
        ),
        'model.onnx|384|f32+vabq:none|sha256:abc',
      );
    });

    test('rejects an identity that would break the wire format', () {
      expect(
        () => computeEmbeddingFingerprint(
          modelBasename: 'model.onnx',
          dim: 384,
          quant: 'f32+vabq:none',
          modelIdentity: 'a|b',
        ),
        throwsArgumentError,
      );
    });
  });
}

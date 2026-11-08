import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

void main() {
  late Directory dir;
  late String tokenizer;
  late String model;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mobile_rag_init_args');
    tokenizer = '${dir.path}/tokenizer.json';
    model = '${dir.path}/model.onnx';
    File(tokenizer).writeAsStringSync('{}');
    File(model).writeAsBytesSync([0]);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Matcher argumentError(String message) => throwsA(
    isA<ArgumentError>().having((e) => '$e', 'message', contains(message)),
  );

  test('rejects file paths together with assets', () {
    expect(
      () => MobileRag.initialize(
        tokenizerPath: tokenizer,
        modelPath: model,
        tokenizerAsset: 'assets/tokenizer.json',
        modelAsset: 'assets/model.onnx',
      ),
      argumentError('Specify only one of'),
    );
  });

  test('rejects file paths together with a Model Pack', () {
    expect(
      () => MobileRag.initialize(
        tokenizerPath: tokenizer,
        modelPath: model,
        modelPack: const RagModelPack.asset('assets/pack/manifest.json'),
      ),
      argumentError('Specify only one of'),
    );
  });

  test('needs both file paths', () {
    expect(
      () => MobileRag.initialize(modelPath: model),
      argumentError('Specify both tokenizerPath and modelPath'),
    );
  });

  test('needs both assets', () {
    expect(
      () => MobileRag.initialize(modelAsset: 'assets/model.onnx'),
      argumentError('Specify both tokenizerAsset and modelAsset'),
    );
  });

  test('needs a model source', () {
    expect(() => MobileRag.initialize(), argumentError('Specify modelPack'));
  });

  test('reports a missing file before loading anything', () {
    expect(
      () => MobileRag.initialize(
        tokenizerPath: tokenizer,
        modelPath: '${dir.path}/missing.onnx',
      ),
      throwsA(
        isA<ArgumentError>()
            .having((e) => e.name, 'name', 'modelPath')
            .having((e) => '$e', 'message', contains('does not exist')),
      ),
    );
  });
}

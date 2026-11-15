// Q2 B5: two MobileRag.initialize calls in flight used to start two engines
// (two embedding workers, two database pools), and the second replaced the
// first engine's state underneath it.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mocktail/mocktail.dart';

class _MockRagEngine extends Mock implements RagEngine {}

void main() {
  late Directory dir;
  late String tokenizer;
  late String model;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mobile_rag_init_concurrency');
    tokenizer = '${dir.path}/tokenizer.json';
    model = '${dir.path}/model.onnx';
    File(tokenizer).writeAsStringSync('{}');
    File(model).writeAsBytesSync([0]);
  });

  tearDown(() {
    MobileRag.engineInitializer = RagEngine.initialize;
    MobileRag.setMockInstance(null);
    dir.deleteSync(recursive: true);
  });

  test('a second call made while the first runs waits for it', () async {
    final engine = _MockRagEngine();
    final release = Completer<void>();
    final databases = <String?>[];
    MobileRag.engineInitializer = ({required config, onProgress}) async {
      databases.add(config.databaseName);
      await release.future;
      return engine;
    };

    final first = MobileRag.initialize(
      tokenizerPath: tokenizer,
      modelPath: model,
      databaseName: '한국어_東京_北京.sqlite',
    );
    final progress = <String>[];
    final second = MobileRag.initialize(
      tokenizerPath: tokenizer,
      modelPath: model,
      databaseName: 'other.sqlite',
      onProgress: progress.add,
    );
    await pumpEventQueue();
    expect(MobileRag.isInitialized, isFalse);

    release.complete();
    await Future.wait([first, second]);
    expect(databases, ['한국어_東京_北京.sqlite']);
    expect(progress, ['Already initializing']);
    expect(MobileRag.instance.engine, same(engine));
  });

  test('a call after a failed one starts again', () async {
    var calls = 0;
    MobileRag.engineInitializer = ({required config, onProgress}) async {
      calls++;
      if (calls == 1) throw StateError('model failed to load');
      return _MockRagEngine();
    };

    final first = MobileRag.initialize(
      tokenizerPath: tokenizer,
      modelPath: model,
    );
    final joined = MobileRag.initialize(
      tokenizerPath: tokenizer,
      modelPath: model,
    );
    await expectLater(first, throwsStateError);
    await expectLater(joined, throwsStateError);
    expect(calls, 1);

    await MobileRag.initialize(tokenizerPath: tokenizer, modelPath: model);
    expect(calls, 2);
    expect(MobileRag.isInitialized, isTrue);
  });
}

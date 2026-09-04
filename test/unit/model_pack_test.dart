import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mobile_rag_engine/src/model_pack/model_pack_installer.dart';
import 'package:mobile_rag_engine/src/model_pack/model_pack_resolver.dart';

const _modelHash =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';
const _tokenizerHash =
    '2fa1b377bf67309f65e5e7bc9d924345ca648dec4e601a398a9cb497dcba3765';

Future<void> _legacyInitializeStillCompiles() => MobileRag.initialize(
  tokenizerAsset: 'assets/tokenizer.json',
  modelAsset: 'assets/model.onnx',
);

Future<void> _modelPackInitializeCompiles() => MobileRag.initialize(
  modelPack: const RagModelPack.asset('assets/mobile_rag/model-pack.json'),
);

RagModelPackManifest _fixtureManifest() => const RagModelPackManifest(
  schemaVersion: 1,
  preset: 'fixture-minilm',
  modelId: 'fixture/model',
  revision: '1110a243fdf4706b3f48f1d95db1a4f5529b4d41',
  modelAsset: 'assets/mobile_rag/model.onnx',
  tokenizerAsset: 'assets/mobile_rag/tokenizer.json',
  modelSha256: _modelHash,
  tokenizerSha256: _tokenizerHash,
  modelBytes: 3,
  tokenizerBytes: 2,
  architecture: 'arm64',
  embeddingDimension: 384,
  license: 'apache-2.0',
  language: 'English',
);

void main() {
  group('RagModelPackManifest', () {
    test('round-trips and permanently selects Q8_0', () {
      final manifest = _fixtureManifest();
      final parsed = RagModelPackManifest.fromJsonString(
        manifest.toJsonString(),
      );
      expect(parsed.toJson(), manifest.toJson());
      expect(parsed.vectorStorage, 'Q8_0');
    });

    test('rejects mutable revision, invalid asset and VABQ storage', () {
      final json = Map<String, dynamic>.from(_fixtureManifest().toJson());
      json['revision'] = 'main';
      expect(
        () => RagModelPackManifest.fromJson(json),
        throwsA(isA<RagModelPackException>()),
      );
      json['revision'] = _fixtureManifest().revision;
      json['modelAsset'] = '../model.onnx';
      expect(
        () => RagModelPackManifest.fromJson(json),
        throwsA(isA<RagModelPackException>()),
      );
      json['modelAsset'] = _fixtureManifest().modelAsset;
      json['vectorStorage'] = 'VABQ';
      expect(
        () => RagModelPackManifest.fromJson(json),
        throwsA(
          isA<RagModelPackException>().having(
            (error) => error.code,
            'code',
            RagModelPackErrorCode.unsupportedVectorStorage,
          ),
        ),
      );
    });

    test('dimension validation reports a typed failure', () {
      expect(
        () => _fixtureManifest().validateEmbeddingDimension(768),
        throwsA(
          isA<RagModelPackException>().having(
            (error) => error.code,
            'code',
            RagModelPackErrorCode.embeddingDimensionMismatch,
          ),
        ),
      );
    });
  });

  group('ModelPackInstaller', () {
    late Directory project;
    late ModelPackPresetDefinition preset;

    setUp(() async {
      project = await Directory.systemTemp.createTemp('model-pack-install-');
      preset = ModelPackPresetDefinition(
        id: 'fixture-minilm',
        manifest: ({required modelAsset, required tokenizerAsset}) =>
            RagModelPackManifest(
              schemaVersion: 1,
              preset: 'fixture-minilm',
              modelId: 'fixture/model',
              revision: _fixtureManifest().revision,
              modelAsset: modelAsset,
              tokenizerAsset: tokenizerAsset,
              modelSha256: _modelHash,
              tokenizerSha256: _tokenizerHash,
              modelBytes: 3,
              tokenizerBytes: 2,
              architecture: 'arm64',
              embeddingDimension: 384,
              license: 'apache-2.0',
              language: 'English',
            ),
        modelUrl: Uri.parse('https://fixtures.invalid/model'),
        tokenizerUrl: Uri.parse('https://fixtures.invalid/tokenizer'),
      );
    });

    tearDown(() => project.delete(recursive: true));

    ModelPackInstaller installer(int Function() calls) => ModelPackInstaller(
      projectDirectory: project,
      presetDefinition: preset,
      downloader: (url) async {
        if (url.path.endsWith('model')) return [1, 2, 3];
        return [4, 5];
      },
    );

    test('installs, checks and reuses verified artifacts', () async {
      var calls = 0;
      final subject = ModelPackInstaller(
        projectDirectory: project,
        presetDefinition: preset,
        downloader: (url) async {
          calls++;
          return url.path.endsWith('model') ? [1, 2, 3] : [4, 5];
        },
      );
      final first = await subject.install(preset: preset.id);
      expect(first.verified, isFalse);
      expect(calls, 2);
      final second = await subject.install(preset: preset.id);
      expect(second.verified, isFalse);
      expect(calls, 2);
      final checked = await subject.install(preset: preset.id, check: true);
      expect(checked.verified, isTrue);
    });

    test('requires repair for a mismatched existing artifact', () async {
      final subject = installer(() => 0);
      await subject.install(preset: preset.id);
      await File(
        '${project.path}/assets/mobile_rag/model.onnx',
      ).writeAsBytes([9]);
      await expectLater(
        subject.install(preset: preset.id),
        throwsA(isA<RagModelPackException>()),
      );
      await subject.install(preset: preset.id, repair: true);
      expect(
        await File(
          '${project.path}/assets/mobile_rag/model.onnx',
        ).readAsBytes(),
        [1, 2, 3],
      );
    });

    test('rejects output outside the project', () async {
      await expectLater(
        installer(() => 0).install(preset: preset.id, output: '../outside'),
        throwsA(
          isA<RagModelPackException>().having(
            (error) => error.code,
            'code',
            RagModelPackErrorCode.outputOutsideProject,
          ),
        ),
      );
    });
  });

  test(
    'resolver honors a non-zero ByteData offset and preserves Q8_0',
    () async {
      final manifest = _fixtureManifest();
      final assets = <String, Uint8List>{
        'assets/mobile_rag/model-pack.json': Uint8List.fromList(
          utf8.encode(manifest.toJsonString()),
        ),
        manifest.modelAsset: Uint8List.fromList([1, 2, 3]),
        manifest.tokenizerAsset: Uint8List.fromList([4, 5]),
      };
      final documents = await Directory.systemTemp.createTemp(
        'model-pack-resolve-',
      );
      addTearDown(() => documents.delete(recursive: true));
      final resolver = RagModelPackResolver(
        documentsDirectory: () async => documents,
        loadAsset: (path) async {
          final source = assets[path]!;
          final buffer = Uint8List(source.length + 4);
          buffer.setRange(2, 2 + source.length, source);
          return ByteData.view(buffer.buffer, 2, source.length);
        },
      );
      final resolved = await resolver.resolve(
        const RagModelPack.asset('assets/mobile_rag/model-pack.json'),
      );
      expect(await File(resolved.modelPath).readAsBytes(), [1, 2, 3]);
      expect(await File(resolved.tokenizerPath).readAsBytes(), [4, 5]);
      expect(resolved.manifest.vectorStorage, 'Q8_0');
    },
  );

  test('prepared model-pack config carries Q8_0 and expected dimension', () {
    final config = RagConfig.fromPreparedFiles(
      tokenizerPath: '/tmp/tokenizer.json',
      modelPath: '/tmp/model.onnx',
      expectedEmbeddingDimension: 384,
    );
    expect(config.vabqProfile, VabqProfile.none);
    expect(config.expectedEmbeddingDimension, 384);
  });

  test('legacy and model-pack initialize forms remain callable', () {
    expect(_legacyInitializeStillCompiles, isA<Function>());
    expect(_modelPackInitializeCompiles, isA<Function>());
  });
}

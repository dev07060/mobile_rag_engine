import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../model_pack.dart';

/// File locations produced by resolving a verified bundled model pack.
class ResolvedRagModelPack {
  const ResolvedRagModelPack({
    required this.manifest,
    required this.modelPath,
    required this.tokenizerPath,
  });

  final RagModelPackManifest manifest;
  final String modelPath;
  final String tokenizerPath;
}

/// Loads a bundled manifest and artifacts once, verifies them, then writes
/// them to a digest-namespaced documents directory for the existing ONNX flow.
class RagModelPackResolver {
  const RagModelPackResolver({this.loadAsset, this.documentsDirectory});

  final Future<ByteData> Function(String asset)? loadAsset;
  final Future<Directory> Function()? documentsDirectory;

  Future<ResolvedRagModelPack> resolve(RagModelPack pack) async {
    final manifestBytes = await _loadBytes(pack.manifestAsset);
    final manifest = RagModelPackManifest.fromJsonString(
      String.fromCharCodes(manifestBytes),
    );
    if (manifest.architecture != 'arm64') {
      throw const RagModelPackException(
        RagModelPackErrorCode.unsupportedArchitecture,
        'The active Model Pack v1 runtime supports only arm64 artifacts.',
      );
    }
    final modelBytes = await _loadBytes(manifest.modelAsset);
    final tokenizerBytes = await _loadBytes(manifest.tokenizerAsset);
    _verify(
      modelBytes,
      manifest.modelBytes,
      manifest.modelSha256,
      manifest.modelAsset,
    );
    _verify(
      tokenizerBytes,
      manifest.tokenizerBytes,
      manifest.tokenizerSha256,
      manifest.tokenizerAsset,
    );

    final directory =
        await (documentsDirectory ?? getApplicationDocumentsDirectory)();
    final packDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}mobile_rag_model_packs'
      '${Platform.pathSeparator}${manifest.modelSha256}-${manifest.tokenizerSha256}',
    );
    await packDirectory.create(recursive: true);
    final model = File(
      '${packDirectory.path}${Platform.pathSeparator}model.onnx',
    );
    final tokenizer = File(
      '${packDirectory.path}${Platform.pathSeparator}tokenizer.json',
    );
    await _writeIfDifferent(model, modelBytes);
    await _writeIfDifferent(tokenizer, tokenizerBytes);
    return ResolvedRagModelPack(
      manifest: manifest,
      modelPath: model.path,
      tokenizerPath: tokenizer.path,
    );
  }

  Future<Uint8List> _loadBytes(String asset) async {
    final data = await (loadAsset ?? rootBundle.load)(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  void _verify(
    Uint8List data,
    int expectedLength,
    String expectedHash,
    String asset,
  ) {
    if (data.lengthInBytes != expectedLength) {
      throw RagModelPackException(
        RagModelPackErrorCode.assetLengthMismatch,
        '$asset has ${data.lengthInBytes} bytes; expected $expectedLength.',
      );
    }
    if (sha256.convert(data).toString() != expectedHash) {
      throw RagModelPackException(
        RagModelPackErrorCode.assetHashMismatch,
        '$asset SHA-256 does not match the model-pack manifest.',
      );
    }
  }

  Future<void> _writeIfDifferent(File file, Uint8List data) async {
    if (await file.exists()) {
      final existing = await file.readAsBytes();
      if (existing.length == data.length &&
          sha256.convert(existing).toString() ==
              sha256.convert(data).toString()) {
        return;
      }
    }
    final temporary = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsBytes(data, flush: true);
    await temporary.rename(file.path);
  }
}

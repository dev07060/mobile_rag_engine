import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
///
/// The directory name is the pair of manifest SHA-256 digests, and a
/// `.verified` marker is written only after both files were verified and
/// written. Later cold starts that find the marker and the expected file
/// lengths reuse the install without loading the artifacts into the Dart
/// heap or hashing them. Hashing, when needed, runs on a background isolate.
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

    final directory =
        await (documentsDirectory ?? getApplicationDocumentsDirectory)();
    final packDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}mobile_rag_model_packs'
      '${Platform.pathSeparator}${manifest.modelSha256}-${manifest.tokenizerSha256}',
    );
    final model = File(
      '${packDirectory.path}${Platform.pathSeparator}model.onnx',
    );
    final tokenizer = File(
      '${packDirectory.path}${Platform.pathSeparator}tokenizer.json',
    );
    final marker = File(
      '${packDirectory.path}${Platform.pathSeparator}.verified',
    );
    final markerContent = jsonEncode({
      'modelSha256': manifest.modelSha256,
      'modelBytes': manifest.modelBytes,
      'tokenizerSha256': manifest.tokenizerSha256,
      'tokenizerBytes': manifest.tokenizerBytes,
    });

    if (await _isVerifiedInstall(
      marker: marker,
      markerContent: markerContent,
      model: model,
      tokenizer: tokenizer,
      manifest: manifest,
    )) {
      return ResolvedRagModelPack(
        manifest: manifest,
        modelPath: model.path,
        tokenizerPath: tokenizer.path,
      );
    }

    final modelBytes = await _loadBytes(manifest.modelAsset);
    final tokenizerBytes = await _loadBytes(manifest.tokenizerAsset);
    await _verify(
      modelBytes,
      manifest.modelBytes,
      manifest.modelSha256,
      manifest.modelAsset,
    );
    await _verify(
      tokenizerBytes,
      manifest.tokenizerBytes,
      manifest.tokenizerSha256,
      manifest.tokenizerAsset,
    );

    await packDirectory.create(recursive: true);
    if (await marker.exists()) {
      await marker.delete();
    }
    // The bundled bytes are verified, so overwrite rather than re-hashing the
    // existing copies.
    await _writeAtomically(model, modelBytes);
    await _writeAtomically(tokenizer, tokenizerBytes);
    await _writeAtomically(marker, utf8.encode(markerContent));
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

  Future<bool> _isVerifiedInstall({
    required File marker,
    required String markerContent,
    required File model,
    required File tokenizer,
    required RagModelPackManifest manifest,
  }) async {
    try {
      return await marker.readAsString() == markerContent &&
          await model.length() == manifest.modelBytes &&
          await tokenizer.length() == manifest.tokenizerBytes;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _verify(
    Uint8List data,
    int expectedLength,
    String expectedHash,
    String asset,
  ) async {
    if (data.lengthInBytes != expectedLength) {
      throw RagModelPackException(
        RagModelPackErrorCode.assetLengthMismatch,
        '$asset has ${data.lengthInBytes} bytes; expected $expectedLength.',
      );
    }
    // A 23 MB SHA-256 takes long enough to drop frames on the UI isolate.
    final actualHash = await Isolate.run(() => sha256.convert(data).toString());
    if (actualHash != expectedHash) {
      throw RagModelPackException(
        RagModelPackErrorCode.assetHashMismatch,
        '$asset SHA-256 does not match the model-pack manifest.',
      );
    }
  }

  Future<void> _writeAtomically(File file, List<int> data) async {
    final temporary = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsBytes(data, flush: true);
    await temporary.rename(file.path);
  }
}

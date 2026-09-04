import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mobile_rag_engine/model_pack.dart';

/// Downloads an immutable artifact. Tests can provide an in-memory downloader.
typedef ModelPackDownloader = Future<List<int>> Function(Uri url);

/// The single supported Model Pack v1 preset.
class StableMiniLmL6V2Arm64EnPreset {
  static const id = 'stable-minilm-l6-v2-arm64-en';
  static const modelId = 'sentence-transformers/all-MiniLM-L6-v2';
  static const revision = '1110a243fdf4706b3f48f1d95db1a4f5529b4d41';
  static const modelSha256 =
      '4278337fd0ff3c68bfb6291042cad8ab363e1d9fbc43dcb499fe91c871902474';
  static const tokenizerSha256 =
      'be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037';
  static const modelBytes = 23026053;
  static const tokenizerBytes = 466247;
  static const modelUrl =
      'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/$revision/onnx/model_qint8_arm64.onnx';
  static const tokenizerUrl =
      'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/$revision/tokenizer.json';

  static RagModelPackManifest manifest({
    required String modelAsset,
    required String tokenizerAsset,
  }) => const RagModelPackManifest(
    schemaVersion: 1,
    preset: id,
    modelId: modelId,
    revision: revision,
    modelAsset: '',
    tokenizerAsset: '',
    modelSha256: modelSha256,
    tokenizerSha256: tokenizerSha256,
    modelBytes: modelBytes,
    tokenizerBytes: tokenizerBytes,
    architecture: 'arm64',
    embeddingDimension: 384,
    license: 'apache-2.0',
    language: 'English',
  ).copyWithAssets(modelAsset, tokenizerAsset);
}

/// Artifact metadata used by the installer. The default is the sole public
/// preset; injecting one in tests keeps installer tests completely offline.
class ModelPackPresetDefinition {
  const ModelPackPresetDefinition({
    required this.id,
    required this.manifest,
    required this.modelUrl,
    required this.tokenizerUrl,
  });

  final String id;
  final RagModelPackManifest Function({
    required String modelAsset,
    required String tokenizerAsset,
  })
  manifest;
  final Uri modelUrl;
  final Uri tokenizerUrl;

  static final stableMiniLm = ModelPackPresetDefinition(
    id: StableMiniLmL6V2Arm64EnPreset.id,
    manifest: StableMiniLmL6V2Arm64EnPreset.manifest,
    modelUrl: Uri.parse(StableMiniLmL6V2Arm64EnPreset.modelUrl),
    tokenizerUrl: Uri.parse(StableMiniLmL6V2Arm64EnPreset.tokenizerUrl),
  );
}

extension on RagModelPackManifest {
  RagModelPackManifest copyWithAssets(
    String modelAsset,
    String tokenizerAsset,
  ) => RagModelPackManifest(
    schemaVersion: schemaVersion,
    preset: preset,
    modelId: modelId,
    revision: revision,
    modelAsset: modelAsset,
    tokenizerAsset: tokenizerAsset,
    modelSha256: modelSha256,
    tokenizerSha256: tokenizerSha256,
    modelBytes: modelBytes,
    tokenizerBytes: tokenizerBytes,
    architecture: architecture,
    embeddingDimension: embeddingDimension,
    license: license,
    language: language,
  );
}

/// Installs and verifies the immutable MiniLM assets during app development.
class ModelPackInstaller {
  ModelPackInstaller({
    required this.projectDirectory,
    ModelPackDownloader? downloader,
    ModelPackPresetDefinition? presetDefinition,
  }) : _downloader = downloader ?? _httpDownload,
       _presetDefinition =
           presetDefinition ?? ModelPackPresetDefinition.stableMiniLm;

  final Directory projectDirectory;
  final ModelPackDownloader _downloader;
  final ModelPackPresetDefinition _presetDefinition;

  static Future<List<int>> _httpDownload(Uri url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw RagModelPackException(
          RagModelPackErrorCode.downloadFailed,
          'Download failed with HTTP ${response.statusCode}: $url',
        );
      }
      return await response.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Installs or checks [preset] in [output].
  ///
  /// Existing valid files are reused. Invalid files are only replaced when
  /// [repair] is true. [check] never writes files.
  Future<ModelPackInstallResult> install({
    required String preset,
    String output = 'assets/mobile_rag',
    bool check = false,
    bool repair = false,
  }) async {
    if (preset != _presetDefinition.id) {
      throw RagModelPackException(
        RagModelPackErrorCode.unsupportedPreset,
        'Only ${_presetDefinition.id} is supported.',
      );
    }
    if (check && repair) {
      throw const RagModelPackException(
        RagModelPackErrorCode.invalidManifest,
        '--check and --repair cannot be used together.',
      );
    }

    final outputDirectory = _outputInsideProject(output);
    final model = File(
      '${outputDirectory.path}${Platform.pathSeparator}model.onnx',
    );
    final tokenizer = File(
      '${outputDirectory.path}${Platform.pathSeparator}tokenizer.json',
    );
    final manifestFile = File(
      '${outputDirectory.path}${Platform.pathSeparator}model-pack.json',
    );
    final rootPrefix =
        projectDirectory.absolute.path.endsWith(Platform.pathSeparator)
        ? projectDirectory.absolute.path
        : '${projectDirectory.absolute.path}${Platform.pathSeparator}';
    final assetDirectory = outputDirectory.path.substring(rootPrefix.length);
    final manifest = _presetDefinition.manifest(
      modelAsset: _assetPath(assetDirectory, 'model.onnx'),
      tokenizerAsset: _assetPath(assetDirectory, 'tokenizer.json'),
    );

    if (check) {
      await _verifyFile(model, manifest.modelBytes, manifest.modelSha256);
      await _verifyFile(
        tokenizer,
        manifest.tokenizerBytes,
        manifest.tokenizerSha256,
      );
      await _verifyManifest(manifestFile, manifest);
      return ModelPackInstallResult(
        verified: true,
        manifestPath: manifestFile.path,
      );
    }

    await outputDirectory.create(recursive: true);
    await _installArtifact(
      file: model,
      bytes: manifest.modelBytes,
      hash: manifest.modelSha256,
      url: _presetDefinition.modelUrl,
      repair: repair,
    );
    await _installArtifact(
      file: tokenizer,
      bytes: manifest.tokenizerBytes,
      hash: manifest.tokenizerSha256,
      url: _presetDefinition.tokenizerUrl,
      repair: repair,
    );
    await _writeAtomically(
      manifestFile,
      utf8.encode('${manifest.toJsonString()}\n'),
    );
    return ModelPackInstallResult(
      verified: false,
      manifestPath: manifestFile.path,
    );
  }

  Directory _outputInsideProject(String output) {
    final root = projectDirectory.absolute.path;
    final rootUri = Uri.directory('$root${Platform.pathSeparator}');
    final candidateUri = output.startsWith(Platform.pathSeparator)
        ? Uri.file(output)
        : rootUri.resolve(output);
    final candidate = Directory(candidateUri.toFilePath()).absolute.path;
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (!candidate.startsWith(prefix)) {
      throw const RagModelPackException(
        RagModelPackErrorCode.outputOutsideProject,
        'The output directory must be inside the Flutter project.',
      );
    }
    return Directory(candidate);
  }

  String _assetPath(String output, String name) {
    final path = output.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');
    return '$path/$name';
  }

  Future<void> _installArtifact({
    required File file,
    required int bytes,
    required String hash,
    required Uri url,
    required bool repair,
  }) async {
    if (await file.exists()) {
      try {
        await _verifyFile(file, bytes, hash);
        return;
      } on RagModelPackException {
        if (!repair) {
          throw RagModelPackException(
            RagModelPackErrorCode.existingFileMismatch,
            'Existing ${file.path} does not match the preset. Use --repair to replace it.',
          );
        }
      }
    }
    final downloaded = Uint8List.fromList(await _downloader(url));
    _verifyBytes(downloaded, bytes, hash, file.path);
    await _writeAtomically(file, downloaded);
  }

  Future<void> _verifyFile(File file, int bytes, String hash) async {
    if (!await file.exists()) {
      throw RagModelPackException(
        RagModelPackErrorCode.assetMissing,
        'Missing required model-pack asset: ${file.path}',
      );
    }
    _verifyBytes(await file.readAsBytes(), bytes, hash, file.path);
  }

  void _verifyBytes(List<int> data, int bytes, String hash, String label) {
    if (data.length != bytes) {
      throw RagModelPackException(
        RagModelPackErrorCode.assetLengthMismatch,
        '$label has ${data.length} bytes; expected $bytes.',
      );
    }
    if (sha256.convert(data).toString() != hash) {
      throw RagModelPackException(
        RagModelPackErrorCode.assetHashMismatch,
        '$label SHA-256 does not match the preset.',
      );
    }
  }

  Future<void> _verifyManifest(
    File manifestFile,
    RagModelPackManifest expected,
  ) async {
    if (!await manifestFile.exists()) {
      throw RagModelPackException(
        RagModelPackErrorCode.assetMissing,
        'Missing required model-pack manifest: ${manifestFile.path}',
      );
    }
    final actual = RagModelPackManifest.fromJsonString(
      await manifestFile.readAsString(),
    );
    if (actual.toJsonString() != expected.toJsonString()) {
      throw const RagModelPackException(
        RagModelPackErrorCode.invalidManifest,
        'The existing model-pack manifest does not match the selected preset.',
      );
    }
  }

  Future<void> _writeAtomically(File file, List<int> data) async {
    final temp = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsBytes(data, flush: true);
    await temp.rename(file.path);
  }
}

/// Successful setup/check output for the command-line entrypoint.
class ModelPackInstallResult {
  const ModelPackInstallResult({
    required this.verified,
    required this.manifestPath,
  });

  final bool verified;
  final String manifestPath;
}

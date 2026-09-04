/// Immutable, bundled embedding-model packs for MobileRag.
library;

import 'dart:convert';

/// A reference to a model-pack manifest bundled as a Flutter asset.
class RagModelPack {
  /// Creates a model-pack reference for [manifestAsset].
  const RagModelPack.asset(this.manifestAsset);

  /// Asset path of the JSON manifest.
  final String manifestAsset;
}

/// Error categories emitted while parsing, installing, or resolving a pack.
enum RagModelPackErrorCode {
  invalidManifest,
  unsupportedSchema,
  unsupportedPreset,
  invalidRevision,
  invalidAssetPath,
  invalidHash,
  invalidLength,
  unsupportedArchitecture,
  unsupportedVectorStorage,
  assetMissing,
  assetLengthMismatch,
  assetHashMismatch,
  outputOutsideProject,
  existingFileMismatch,
  downloadFailed,
  embeddingDimensionMismatch,
}

/// A typed failure in the Model Pack v1 contract.
class RagModelPackException implements Exception {
  const RagModelPackException(this.code, this.message);

  final RagModelPackErrorCode code;
  final String message;

  @override
  String toString() => 'RagModelPackException($code): $message';
}

/// Schema v1 metadata for one immutable, bundled model pack.
///
/// Model Pack v1 always uses Q8_0 vector storage. It deliberately has no
/// VABQ profile field: a manifest cannot silently opt into VABQ.
class RagModelPackManifest {
  const RagModelPackManifest({
    required this.schemaVersion,
    required this.preset,
    required this.modelId,
    required this.revision,
    required this.modelAsset,
    required this.tokenizerAsset,
    required this.modelSha256,
    required this.tokenizerSha256,
    required this.modelBytes,
    required this.tokenizerBytes,
    required this.architecture,
    required this.embeddingDimension,
    required this.license,
    required this.language,
    String? declaredVectorStorage,
  }) : _declaredVectorStorage = declaredVectorStorage;

  static const int supportedSchemaVersion = 1;
  static const String q8_0 = 'Q8_0';

  final int schemaVersion;
  final String preset;
  final String modelId;
  final String revision;
  final String modelAsset;
  final String tokenizerAsset;
  final String modelSha256;
  final String tokenizerSha256;
  final int modelBytes;
  final int tokenizerBytes;
  final String architecture;
  final int embeddingDimension;
  final String license;
  final String language;
  final String? _declaredVectorStorage;

  /// Model Pack v1 is intentionally fixed to Q8_0.
  String get vectorStorage => q8_0;

  factory RagModelPackManifest.fromJsonString(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const RagModelPackException(
          RagModelPackErrorCode.invalidManifest,
          'The model-pack manifest must be a JSON object.',
        );
      }
      return RagModelPackManifest.fromJson(decoded);
    } on FormatException catch (_) {
      throw const RagModelPackException(
        RagModelPackErrorCode.invalidManifest,
        'The model-pack manifest is not valid JSON.',
      );
    }
  }

  factory RagModelPackManifest.fromJson(Map<String, dynamic> json) {
    T requiredValue<T>(String name) {
      final value = json[name];
      if (value is! T) {
        throw RagModelPackException(
          RagModelPackErrorCode.invalidManifest,
          'Missing or invalid "$name" in the model-pack manifest.',
        );
      }
      return value;
    }

    final declaredVectorStorage = json['vectorStorage'];
    if (declaredVectorStorage != null && declaredVectorStorage is! String) {
      throw const RagModelPackException(
        RagModelPackErrorCode.invalidManifest,
        'vectorStorage must be a string when present.',
      );
    }
    final manifest = RagModelPackManifest(
      schemaVersion: requiredValue<int>('schemaVersion'),
      preset: requiredValue<String>('preset'),
      modelId: requiredValue<String>('modelId'),
      revision: requiredValue<String>('revision'),
      modelAsset: requiredValue<String>('modelAsset'),
      tokenizerAsset: requiredValue<String>('tokenizerAsset'),
      modelSha256: requiredValue<String>('modelSha256'),
      tokenizerSha256: requiredValue<String>('tokenizerSha256'),
      modelBytes: requiredValue<int>('modelBytes'),
      tokenizerBytes: requiredValue<int>('tokenizerBytes'),
      architecture: requiredValue<String>('architecture'),
      embeddingDimension: requiredValue<int>('embeddingDimension'),
      license: requiredValue<String>('license'),
      language: requiredValue<String>('language'),
      declaredVectorStorage: declaredVectorStorage as String?,
    );
    manifest._validate();
    return manifest;
  }

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'preset': preset,
    'modelId': modelId,
    'revision': revision,
    'modelAsset': modelAsset,
    'tokenizerAsset': tokenizerAsset,
    'modelSha256': modelSha256,
    'tokenizerSha256': tokenizerSha256,
    'modelBytes': modelBytes,
    'tokenizerBytes': tokenizerBytes,
    'architecture': architecture,
    'embeddingDimension': embeddingDimension,
    'license': license,
    'language': language,
    'vectorStorage': vectorStorage,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Rejects a loaded ONNX model whose actual output does not match this pack.
  void validateEmbeddingDimension(int actualDimension) {
    validateExpectedEmbeddingDimension(
      expectedDimension: embeddingDimension,
      actualDimension: actualDimension,
    );
  }

  static void validateExpectedEmbeddingDimension({
    required int expectedDimension,
    required int actualDimension,
  }) {
    if (actualDimension != expectedDimension) {
      throw RagModelPackException(
        RagModelPackErrorCode.embeddingDimensionMismatch,
        'Model Pack expected $expectedDimension dimensions but the ONNX model returned $actualDimension.',
      );
    }
  }

  void _validate() {
    if (schemaVersion != supportedSchemaVersion) {
      throw const RagModelPackException(
        RagModelPackErrorCode.unsupportedSchema,
        'Only Model Pack schemaVersion 1 is supported.',
      );
    }
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(revision)) {
      throw const RagModelPackException(
        RagModelPackErrorCode.invalidRevision,
        'revision must be an immutable 40-character git SHA.',
      );
    }
    for (final path in [modelAsset, tokenizerAsset]) {
      if (path.isEmpty || path.startsWith('/') || path.contains('..')) {
        throw const RagModelPackException(
          RagModelPackErrorCode.invalidAssetPath,
          'Model-pack asset paths must be relative, non-empty asset paths.',
        );
      }
    }
    for (final hash in [modelSha256, tokenizerSha256]) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        throw const RagModelPackException(
          RagModelPackErrorCode.invalidHash,
          'Model-pack SHA-256 values must be lowercase 64-character hex.',
        );
      }
    }
    if (modelBytes <= 0 || tokenizerBytes <= 0 || embeddingDimension <= 0) {
      throw const RagModelPackException(
        RagModelPackErrorCode.invalidLength,
        'Model-pack lengths and embedding dimension must be positive.',
      );
    }
    if (architecture != 'arm64') {
      throw const RagModelPackException(
        RagModelPackErrorCode.unsupportedArchitecture,
        'Model Pack v1 supports only the arm64 preset.',
      );
    }
    final vectorStorage = _declaredVectorStorage;
    if (vectorStorage != null && vectorStorage != q8_0) {
      throw const RagModelPackException(
        RagModelPackErrorCode.unsupportedVectorStorage,
        'Model Pack v1 is fixed to Q8_0 vector storage.',
      );
    }
  }
}

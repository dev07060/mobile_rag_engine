/// Keeps a file copied from a bundled asset in step with that asset.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show FlutterError, debugPrint;
import 'package:flutter/services.dart';

/// Copies [assetPath] to [filePath] unless the existing copy already holds the
/// same bytes.
///
/// The legacy `modelAsset`/`tokenizerAsset` flow copies into fixed names
/// (`tokenizer.json`, the model's basename), so "the file exists" says nothing
/// about which asset it came from: swapping the tokenizer, or shipping an app
/// update that changes a same-name model, used to leave the stale copy in use.
///
/// A sidecar `<filePath>.asset-stamp` records the asset path, length and
/// SHA-256 of the bytes that were copied. The copy is rewritten when the stamp
/// is missing (copies made before stamps existed), names another asset, or
/// disagrees with the asset's length, the copy's length or the asset's hash.
/// Writes go through a temporary file and a rename, then the stamp, so an
/// interrupted copy is never stamped.
///
/// When the asset is not in the bundle (`rootBundle.load` throws a
/// [FlutterError]) but a non-empty file already exists at [filePath], that
/// file is used as it is, as up to 0.22.3: apps that leave the model out of
/// their release bundle and download it to this path themselves keep working.
/// The engine logs that it did so. The embedding fingerprint's model-content
/// hash still locks the database if the model file is a different model; a
/// tokenizer file is not covered by the fingerprint. Without the asset and
/// without a non-empty file, the error is rethrown.
///
/// Returns whether the file was (re)written.
Future<bool> syncAssetToFile(
  String assetPath,
  String filePath, {
  Future<ByteData> Function(String key)? loadAsset,
}) async {
  final file = File(filePath);
  final ByteData data;
  try {
    data = await (loadAsset ?? rootBundle.load)(assetPath);
  } on FlutterError {
    final length = await _lengthOrNull(file);
    if (length == null || length == 0) rethrow;
    debugPrint(
      '[mobile_rag_engine] "$assetPath" is not in the app bundle; using the '
      'existing file at $filePath ($length bytes) as it is.',
    );
    return false;
  }
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final stampFile = File('$filePath$assetStampSuffix');

  // A model-sized SHA-256 takes long enough to drop frames on the UI isolate.
  // The hash is needed either way: to compare, or to stamp a fresh copy.
  final hash = await Isolate.run(() => sha256.convert(bytes).toString());
  final stamp = await _readStamp(stampFile);
  if (stamp != null &&
      stamp.asset == assetPath &&
      stamp.length == bytes.lengthInBytes &&
      stamp.sha256 == hash &&
      await _lengthOrNull(file) == bytes.lengthInBytes) {
    return false;
  }

  await _write(file, stampFile, assetPath, bytes, hash);
  return true;
}

/// Suffix of the sidecar that records which asset bytes a copy holds.
const assetStampSuffix = '.asset-stamp';

class _AssetStamp {
  const _AssetStamp(this.asset, this.length, this.sha256);

  final String asset;
  final int length;
  final String sha256;
}

Future<_AssetStamp?> _readStamp(File stampFile) async {
  try {
    final json = jsonDecode(await stampFile.readAsString());
    if (json is! Map<String, dynamic>) return null;
    final asset = json['asset'];
    final length = json['length'];
    final hash = json['sha256'];
    if (asset is! String || length is! int || hash is! String) return null;
    return _AssetStamp(asset, length, hash);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

Future<int?> _lengthOrNull(File file) async {
  try {
    return await file.length();
  } on FileSystemException {
    return null;
  }
}

Future<void> _write(
  File file,
  File stampFile,
  String assetPath,
  Uint8List bytes,
  String hash,
) async {
  if (await stampFile.exists()) {
    await stampFile.delete();
  }
  await _writeAtomically(file, bytes);
  await _writeAtomically(
    stampFile,
    utf8.encode(
      jsonEncode({
        'asset': assetPath,
        'length': bytes.lengthInBytes,
        'sha256': hash,
      }),
    ),
  );
}

Future<void> _writeAtomically(File file, List<int> data) async {
  final temporary = File(
    '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
  );
  await temporary.writeAsBytes(data, flush: true);
  await temporary.rename(file.path);
}

/// Helpers for computing and validating the on-device embedding fingerprint.
///
/// The fingerprint identifies which `(model, dim, quant)` combination
/// produced the embeddings persisted on disk. It is opaque to consumers and
/// only compared as a single string against the value the engine binary
/// produces on each boot.
library;

/// Explicit host selection for the variance map used by VABQ.
///
/// [none] is deliberately the default: an embedding dimension or model asset
/// filename is not a reliable model identity and must never enable VABQ.
enum VabqProfile {
  none,
  allMiniLmL6V2,
  allMpnetBaseV2,
  bgeBaseEnV15,
  bgeM3,
}

/// Stable host-to-Rust wire value for [VabqProfile].
String vabqProfileWireName(VabqProfile profile) => switch (profile) {
      VabqProfile.none => 'none',
      VabqProfile.allMiniLmL6V2 => 'allMiniLmL6V2',
      VabqProfile.allMpnetBaseV2 => 'allMpnetBaseV2',
      VabqProfile.bgeBaseEnV15 => 'bgeBaseEnV15',
      VabqProfile.bgeM3 => 'bgeM3',
    };

/// Quantization axis persisted inside an embedding fingerprint.
///
/// Profile changes deliberately take the same re-embedding-lock path as model
/// or dimension changes.
String embeddingQuantizationFingerprintAxis(VabqProfile profile) =>
    'f32+vabq:${vabqProfileWireName(profile)}';

/// Wire format produced by [computeEmbeddingFingerprint].
///
/// `{modelBasename}|{dim}|{quant}`
///
/// Example: `my-model.onnx|384|f32+vabq:allMiniLmL6V2`.
///
/// The basename is taken from `modelPath` rather than its bytes so a host
/// app that replaces the file in-place forces a mismatch (same path, new
/// bytes ⇒ same basename ⇒ same fingerprint is not what we want; in that
/// situation the host MUST also rename the file to a new basename). We rely
/// on the dim component to catch the most common case of swapping models
/// with different output sizes, even if the basename is reused.
String computeEmbeddingFingerprint({
  required String modelBasename,
  required int dim,
  required String quant,
}) {
  if (modelBasename.isEmpty) {
    throw ArgumentError.value(
      modelBasename,
      'modelBasename',
      'must be non-empty',
    );
  }
  if (dim <= 0) {
    throw ArgumentError.value(dim, 'dim', 'must be positive');
  }
  if (quant.isEmpty) {
    throw ArgumentError.value(quant, 'quant', 'must be non-empty');
  }
  return '$modelBasename|$dim|$quant';
}

/// Extract just the file name component from `modelPath`.
///
/// Tolerates both `/` and `\` separators so the fingerprint stays stable
/// across the platforms mobile_rag_engine ships on.
String embeddingModelBasename(String modelPath) {
  if (modelPath.isEmpty) return modelPath;
  final lastSlash = modelPath.lastIndexOf('/');
  final lastBackslash = modelPath.lastIndexOf('\\');
  final cut = lastSlash > lastBackslash ? lastSlash : lastBackslash;
  return cut >= 0 ? modelPath.substring(cut + 1) : modelPath;
}

/// Must exactly match `EMBEDDING_CLEAR_CONFIRMATION` in
/// `rust_builder/rust/src/api/migration_meta.rs`. Duplicated here because the
/// Rust `pub const &str` is not surfaced through flutter_rust_bridge bindings.
const String kEmbeddingClearConfirmationToken =
    'I_UNDERSTAND_THIS_DELETES_ALL_ON_DEVICE_EMBEDDINGS';

/// Snapshot of an active embedding fingerprint mismatch.
///
/// While `MobileRag.instance.embeddingFingerprintLock` is non-null, every
/// search and ingest API throws `RagError.embeddingFingerprintMismatch`.
/// Resolve by calling `reembedAll(progress:)` (preserves data) or
/// `clearAndRestart(confirm:)` (discards embeddings after explicit consent).
class RagEmbeddingFingerprintLock {
  /// Fingerprint persisted on disk when the lock was opened.
  final String stored;

  /// Fingerprint produced by the currently loaded embedding model.
  final String current;

  /// Number of chunks still tagged with a non-current fingerprint at the
  /// moment the lock was opened. Use `MobileRag.instance.reembedRemaining()`
  /// for an up-to-date count during a long-running reembed.
  final int remainingChunks;

  /// True when a previous reembed-to-`current` attempt left
  /// `embedding_fingerprint_pending` set, so the new run can pick up where
  /// the previous one left off without a fresh user prompt.
  final bool resumeInProgress;

  const RagEmbeddingFingerprintLock({
    required this.stored,
    required this.current,
    required this.remainingChunks,
    required this.resumeInProgress,
  });

  @override
  String toString() =>
      'RagEmbeddingFingerprintLock(stored: $stored, current: $current, '
      'remaining: $remainingChunks, resume: $resumeInProgress)';
}

/// Typed acknowledgment that the caller understands `clearAndRestart` deletes
/// every on-device embedding BLOB. Required as an explicit parameter so the
/// destructive choice is visible at every call site.
class ClearAndRestartConfirmation {
  const ClearAndRestartConfirmation._();

  /// Sentinel value the caller must pass to opt into deletion.
  ///
  /// The name is verbose by design — typing it out is the consent.
  static const ClearAndRestartConfirmation
      iUnderstandThisDeletesAllOnDeviceEmbeddings =
      ClearAndRestartConfirmation._();
}

/// Progress event emitted during `reembedAll(progress:)`.
class RagReembedProgress {
  /// Chunks successfully re-embedded in the current run.
  final int done;

  /// Snapshot of the total work captured when the run began. May be slightly
  /// lower than `done` if new chunks were ingested mid-run on a prior boot
  /// before the engine became locked.
  final int total;

  const RagReembedProgress({required this.done, required this.total});

  /// Fraction in `[0, 1]`. Clamped to 1 when `total == 0` so UI bindings
  /// don't blow up on an empty corpus.
  double get fraction =>
      total == 0 ? 1.0 : (done / total).clamp(0.0, 1.0).toDouble();

  @override
  String toString() => 'RagReembedProgress($done/$total)';
}

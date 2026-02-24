/// Internal soft-validation helpers for runtime stability.
library;

import 'package:flutter/foundation.dart';

import 'defaults.dart';

class NormalizedHybridWeights {
  final double vectorWeight;
  final double bm25Weight;

  const NormalizedHybridWeights({
    required this.vectorWeight,
    required this.bm25Weight,
  });
}

int normalizeMaxChunkChars(int value, {String context = 'runtime'}) {
  if (value >= kMinChunkChars) return value;
  debugPrint(
    '[Validation][$context] maxChunkChars=$value is below minimum '
    '$kMinChunkChars. Using $kMinChunkChars.',
  );
  return kMinChunkChars;
}

int normalizeOverlapChars(int value, {String context = 'runtime'}) {
  if (value >= 0) return value;
  debugPrint(
    '[Validation][$context] overlapChars=$value is negative. Using 0.',
  );
  return 0;
}

void warnThreadConfigConflict({
  required Object? threadLevel,
  required int? embeddingIntraOpNumThreads,
  String context = 'runtime',
}) {
  if (threadLevel != null && embeddingIntraOpNumThreads != null) {
    debugPrint(
      '[Validation][$context] Both threadLevel and '
      'embeddingIntraOpNumThreads are set. threadLevel takes precedence.',
    );
  }
}

NormalizedHybridWeights normalizeHybridWeights({
  required double vectorWeight,
  required double bm25Weight,
  String context = 'runtime',
}) {
  double normalizedVector = vectorWeight;
  double normalizedBm25 = bm25Weight;
  bool changed = false;

  if (!normalizedVector.isFinite) {
    normalizedVector = kDefaultVectorWeight;
    changed = true;
  } else {
    final clamped = normalizedVector.clamp(0.0, 1.0).toDouble();
    if (clamped != normalizedVector) {
      normalizedVector = clamped;
      changed = true;
    }
  }

  if (!normalizedBm25.isFinite) {
    normalizedBm25 = kDefaultBm25Weight;
    changed = true;
  } else {
    final clamped = normalizedBm25.clamp(0.0, 1.0).toDouble();
    if (clamped != normalizedBm25) {
      normalizedBm25 = clamped;
      changed = true;
    }
  }

  if (normalizedVector == 0.0 && normalizedBm25 == 0.0) {
    normalizedVector = kDefaultVectorWeight;
    normalizedBm25 = kDefaultBm25Weight;
    changed = true;
  }

  if (changed) {
    debugPrint(
      '[Validation][$context] Normalized hybrid weights '
      '(vector=$vectorWeight, bm25=$bm25Weight) -> '
      '(vector=$normalizedVector, bm25=$normalizedBm25).',
    );
  }

  return NormalizedHybridWeights(
    vectorWeight: normalizedVector,
    bm25Weight: normalizedBm25,
  );
}

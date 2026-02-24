library;

/// Tracks and validates embedding dimensions for a single active ONNX session.
class EmbeddingDimensionState {
  int? _baselineDimension;

  int? get baselineDimension => _baselineDimension;

  void reset() {
    _baselineDimension = null;
  }

  void validateAndRemember(int dimension) {
    if (dimension <= 0) {
      throw StateError(
        'Invalid embedding dimension: got $dimension. '
        'Embedding output must be a positive length vector.',
      );
    }

    final expected = _baselineDimension;
    if (expected == null) {
      _baselineDimension = dimension;
      return;
    }

    if (expected != dimension) {
      throw StateError(
        'Embedding dimension mismatch: expected $expected, got $dimension. '
        'Model replacement may require re-embedding all stored vectors. '
        'Use clear/rebuild flow or regenerateAllEmbeddings() to restore consistency.',
      );
    }
  }
}

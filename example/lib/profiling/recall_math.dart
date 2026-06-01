import 'dart:math' as math;
import 'dart:typed_data';

/// Decode a raw native-endian f32 blob (the `chunks.embedding` column)
/// into a Float32List. Mirrors Rust `decode_f32_embedding` (vector_math.rs):
/// returns null if the byte length is not a multiple of 4.
Float32List? decodeF32Blob(Uint8List bytes) {
  if (bytes.lengthInBytes % 4 != 0) return null;
  final copy = Uint8List.fromList(bytes);
  return copy.buffer.asFloat32List(0, copy.lengthInBytes ~/ 4);
}

/// Cosine similarity of two equal-length vectors. Returns 0.0 if either vector
/// has zero magnitude so recall calculation never receives NaN.
double cosineSimilarity(List<double> a, List<double> b) {
  assert(
    a.length == b.length,
    'vector length mismatch: ${a.length} vs ${b.length}',
  );
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    dot += x * y;
    normA += x * x;
    normB += y * y;
  }
  if (normA == 0.0 || normB == 0.0) return 0.0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}

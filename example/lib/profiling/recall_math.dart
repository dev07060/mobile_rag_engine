import 'dart:typed_data';

/// Decode a raw native-endian f32 blob (the `chunks.embedding` column)
/// into a Float32List. Mirrors Rust `decode_f32_embedding` (vector_math.rs):
/// returns null if the byte length is not a multiple of 4.
Float32List? decodeF32Blob(Uint8List bytes) {
  if (bytes.lengthInBytes % 4 != 0) return null;
  final copy = Uint8List.fromList(bytes);
  return copy.buffer.asFloat32List(0, copy.lengthInBytes ~/ 4);
}

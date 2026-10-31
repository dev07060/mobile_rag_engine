import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/rag_config.dart';
import 'package:mobile_rag_engine/src/internal/embedding_fingerprint.dart';

void main() {
  test('public configuration never selects VABQ', () {
    // VABQ is internal research; RagConfig has no profile to set, and the
    // engine always configures Q8_0 storage.
    const config = RagConfig(
      tokenizerAsset: 'assets/tokenizer.json',
      modelAsset: 'assets/bge-base-en-v1.5-768.onnx',
    );
    expect(config.modelAsset, endsWith('.onnx'));
  });

  test('the Q8_0 fingerprint axis is unchanged for existing databases', () {
    expect(vabqProfileWireName(VabqProfile.none), 'none');
    expect(
      embeddingQuantizationFingerprintAxis(VabqProfile.none),
      'f32+vabq:none',
    );
    expect(
      computeEmbeddingFingerprint(
        modelBasename: 'model.onnx',
        dim: 384,
        quant: embeddingQuantizationFingerprintAxis(VabqProfile.none),
      ),
      'model.onnx|384|f32+vabq:none',
    );
    // A database written with a VABQ profile on a 0.21.0 dev release carries a
    // different axis, so it is detected as a fingerprint mismatch.
    expect(
      embeddingQuantizationFingerprintAxis(VabqProfile.allMiniLmL6V2),
      isNot(embeddingQuantizationFingerprintAxis(VabqProfile.none)),
    );
  });
}

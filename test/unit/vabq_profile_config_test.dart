import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart' as public_api;
import 'package:mobile_rag_engine/services/rag_config.dart';
import 'package:mobile_rag_engine/src/internal/embedding_fingerprint.dart';

void main() {
  test('public configuration defaults to Q8_0 without inferring VABQ', () {
    const defaultConfig = RagConfig(
      tokenizerAsset: 'assets/tokenizer.json',
      modelAsset: 'assets/bge-base-en-v1.5-768.onnx',
    );
    final assetConfig = RagConfig.fromAssets(
      tokenizerAsset: 'assets/tokenizer.json',
      modelAsset: 'assets/all-mpnet-base-v2-768.onnx',
    );
    const configured = RagConfig(
      tokenizerAsset: 'assets/tokenizer.json',
      modelAsset: 'assets/model.onnx',
      vabqProfile: VabqProfile.allMiniLmL6V2,
    );

    expect(defaultConfig.vabqProfile, VabqProfile.none);
    expect(assetConfig.vabqProfile, VabqProfile.none);
    expect(configured.vabqProfile, VabqProfile.allMiniLmL6V2);
    expect(vabqProfileWireName(defaultConfig.vabqProfile), 'none');
    expect(vabqProfileWireName(assetConfig.vabqProfile), 'none');
    expect(
      embeddingQuantizationFingerprintAxis(VabqProfile.none),
      'f32+vabq:none',
    );
    expect(
      embeddingQuantizationFingerprintAxis(VabqProfile.allMiniLmL6V2),
      'f32+vabq:allMiniLmL6V2',
    );
    expect(vabqProfileWireName(VabqProfile.bgeBaseEnV15), 'bgeBaseEnV15');
    expect(public_api.VabqProfile.bgeBaseEnV15, VabqProfile.bgeBaseEnV15);
    expect(
      embeddingQuantizationFingerprintAxis(VabqProfile.bgeBaseEnV15),
      'f32+vabq:bgeBaseEnV15',
    );
    expect(
      computeEmbeddingFingerprint(
        modelBasename: 'model.onnx',
        dim: 768,
        quant: embeddingQuantizationFingerprintAxis(VabqProfile.bgeBaseEnV15),
      ),
      'model.onnx|768|f32+vabq:bgeBaseEnV15',
    );
  });
}

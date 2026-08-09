import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/rag_config.dart';
import 'package:mobile_rag_engine_example/profiling/vabq_measurement_config.dart';

void main() {
  test('maps an explicit production VABQ profile into the run manifest', () {
    final config = VabqMeasurementConfig.fromWire(
      profileWire: 'allMpnetBaseV2',
      docsPerCollection: 500,
    );

    expect(config.vabqProfile, VabqProfile.allMpnetBaseV2);
    expect(config.quantizationLabel, 'vabq:allMpnetBaseV2');
    expect(config.toJson()['vabq_profile'], 'allMpnetBaseV2');
    expect(config.toJson()['chunks_total'], 1000);
  });

  test('maps BGE-base profile ID 4 into the run manifest', () {
    final config = VabqMeasurementConfig.fromWire(
      profileWire: 'bgeBaseEnV15',
      docsPerCollection: 500,
    );

    expect(config.vabqProfile, VabqProfile.bgeBaseEnV15);
    expect(config.profileWire, 'bgeBaseEnV15');
    expect(config.quantizationLabel, 'vabq:bgeBaseEnV15');
  });

  test('keeps Q8_0 as the explicit none profile', () {
    final config = VabqMeasurementConfig.fromWire(
      profileWire: 'none',
      docsPerCollection: 500,
    );

    expect(config.vabqProfile, VabqProfile.none);
    expect(config.quantizationLabel, 'q8_0');
  });

  test('rejects unknown profile text instead of silently selecting VABQ', () {
    expect(
      () => VabqMeasurementConfig.fromWire(
        profileWire: 'model.onnx',
        docsPerCollection: 500,
      ),
      throwsArgumentError,
    );
  });
}

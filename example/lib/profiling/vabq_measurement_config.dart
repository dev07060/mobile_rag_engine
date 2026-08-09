import 'package:mobile_rag_engine/services/rag_config.dart';

/// Explicit quantization condition for one isolated Phase 1 measurement run.
///
/// The profile comes only from the operator's `--dart-define=VABQ_PROFILE=…`
/// value. It deliberately does not inspect the ONNX asset name or infer a
/// profile from its embedding dimension; [MobileRag.initialize] verifies the
/// selected profile against the actual probe embedding before any ingest.
class VabqMeasurementConfig {
  final VabqProfile vabqProfile;
  final int docsPerCollection;

  const VabqMeasurementConfig._({
    required this.vabqProfile,
    required this.docsPerCollection,
  });

  factory VabqMeasurementConfig.fromWire({
    required String profileWire,
    required int docsPerCollection,
  }) {
    if (docsPerCollection <= 0) {
      throw ArgumentError.value(
        docsPerCollection,
        'docsPerCollection',
        'must be positive',
      );
    }

    final profile = switch (profileWire) {
      'none' => VabqProfile.none,
      'allMiniLmL6V2' => VabqProfile.allMiniLmL6V2,
      'allMpnetBaseV2' => VabqProfile.allMpnetBaseV2,
      'bgeBaseEnV15' => VabqProfile.bgeBaseEnV15,
      'bgeM3' => VabqProfile.bgeM3,
      _ => throw ArgumentError.value(
        profileWire,
        'profileWire',
        'must be none, allMiniLmL6V2, allMpnetBaseV2, bgeBaseEnV15, or bgeM3',
      ),
    };

    return VabqMeasurementConfig._(
      vabqProfile: profile,
      docsPerCollection: docsPerCollection,
    );
  }

  String get profileWire => switch (vabqProfile) {
    VabqProfile.none => 'none',
    VabqProfile.allMiniLmL6V2 => 'allMiniLmL6V2',
    VabqProfile.allMpnetBaseV2 => 'allMpnetBaseV2',
    VabqProfile.bgeBaseEnV15 => 'bgeBaseEnV15',
    VabqProfile.bgeM3 => 'bgeM3',
  };

  String get quantizationLabel =>
      vabqProfile == VabqProfile.none ? 'q8_0' : 'vabq:$profileWire';

  Map<String, Object> toJson() => {
    'quantization_label': quantizationLabel,
    'vabq_profile': profileWire,
    'docs_per_collection': docsPerCollection,
    'chunks_total': docsPerCollection * 2,
  };
}

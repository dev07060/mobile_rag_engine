import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mobile_rag_engine_example/profiling/query_fixture.dart';

// On-device RAG query profiler — P2 smoke entrypoint.
//
// Validates the device pipeline: engine init (real ONNX) + A/B fixture seed.
// Runs fine in debug:
//   flutter test integration_test/query_profile_test.dart -d <device-id>
//
// The P3/P4 MEASUREMENT lives in query_profile_measure_test.dart and must run
// under `flutter drive --profile` (profile build => shipped vector_faer/
// vector_quant_i8 backend; flutter test hard-pins debug = fallback backend).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const docsPerCollection = 40;

  // Non-UI integration test: use test() (not testWidgets) so the widget-tester
  // end-of-test semantics-handle verification — irrelevant here — doesn't fire.
  test('profiler smoke: engine init + A/B fixture builds', () async {
    await MobileRag.initialize(
      tokenizerAsset: 'assets/tokenizer.json',
      modelAsset: 'assets/model.onnx',
      databaseName: 'profile.sqlite',
      deferIndexWarmup: true,
    );

    final ids = await QueryFixture.seed(docsPerCollection: docsPerCollection);

    expect(ids[QueryFixture.collectionA]!.length, docsPerCollection);
    expect(ids[QueryFixture.collectionB]!.length, docsPerCollection);
  });
}

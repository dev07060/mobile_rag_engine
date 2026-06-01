// Driver entrypoint for `flutter drive` (profile/release integration runs).
//
// `flutter test` cannot build integration tests in profile mode (it hard-pins
// BuildMode.debug), so the on-device query-profiler MEASUREMENT runs — which
// require the shipped `vector_faer,vector_quant_i8` backend (only compiled in
// profile/release) — must go through `flutter drive`:
//
//   cd example && flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/query_profile_measure_test.dart \
//     --profile -d <device-id>
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();

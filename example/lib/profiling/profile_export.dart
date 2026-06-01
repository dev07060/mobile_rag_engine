// On-device RAG query profiler — P4 (LOC-69) baseline export.
//
// Writes the profiling report to the app documents directory as JSON + CSV and
// emits one structured PROFILE log line per run for live console/logcat capture.
// The printed PROFILE_EXPORT_DIR is the on-device sandbox path (not reachable
// from the host shell) — pull the files off-device for the baseline:
//   iOS (PHYSICAL device — the baseline target):
//     - Xcode > Window > Devices & Simulators > select device > Installed Apps >
//       select the example app > '...' > Download Container… → open the
//       .xcappdata bundle; files are under AppData/Documents/query_profile_<ts>.*
//     - or: xcrun devicectl device copy from --device <UDID>
//       --domain-type appDataContainer --domain-identifier <bundle-id>
//       --source Documents/query_profile_<ts>.json --destination ./
//     - or: surface via the Files app / share sheet for an ad-hoc pull.
//   iOS (Simulator ONLY): xcrun simctl get_app_container booted <bundle-id> data
//       → then Documents/.
//   Android: adb shell run-as <app-id> cat files/query_profile_<ts>.json
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'query_profile_report.dart';

class ProfileExport {
  /// Writes `<docs>/query_profile_<tsTag>.json` and `.csv`, prints one
  /// `PROFILE <json>` log line per run, and returns the documents dir path
  /// (logged so the operator knows where to pull from).
  static Future<String> write(
    QueryProfileReport report, {
    required String tsTag,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final base = '${dir.path}/query_profile_$tsTag';

    await File('$base.json').writeAsString(report.toJsonString(), flush: true);
    await File('$base.csv').writeAsString(report.toCsv(), flush: true);

    for (final r in report.runs) {
      // ignore: avoid_print
      print('PROFILE ${r.toJson()}');
    }
    return dir.path;
  }
}

/// Platform-appropriate root directory for engine-owned files.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Directory that holds the database, index files, and copied model assets.
///
/// On Windows the documents directory is the user's visible (and often
/// OneDrive-synced) Documents folder, which is the wrong home for a SQLite
/// database and memory-mapped index files, so app-private support storage
/// (`%APPDATA%\<company>\<app>`) is used instead. Other platforms keep the
/// documents directory so existing installs find their data where they left it.
Future<Directory> ragStorageDirectory() {
  if (Platform.isWindows) {
    return getApplicationSupportDirectory();
  }
  return getApplicationDocumentsDirectory();
}

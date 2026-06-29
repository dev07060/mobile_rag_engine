import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'frb_generated.dart';

bool shouldLoadRustFromCurrentProcess({String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  return os == 'ios' || os == 'macos';
}

Future<void> initRustLibForPlatform() async {
  if (RustLib.instance.initialized) return;

  if (shouldLoadRustFromCurrentProcess()) {
    await RustLib.init(
      externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
    );
  } else {
    await RustLib.init();
  }
}

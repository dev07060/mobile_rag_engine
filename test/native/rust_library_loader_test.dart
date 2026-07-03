import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/rust/rust_library_loader.dart';

void main() {
  test('Darwin platforms use current-process Rust symbols', () {
    expect(shouldLoadRustFromCurrentProcess(operatingSystem: 'ios'), isTrue);
    expect(shouldLoadRustFromCurrentProcess(operatingSystem: 'macos'), isTrue);
  });

  test('non-Darwin platforms use the default dynamic loader', () {
    expect(
        shouldLoadRustFromCurrentProcess(operatingSystem: 'android'), isFalse);
    expect(shouldLoadRustFromCurrentProcess(operatingSystem: 'linux'), isFalse);
    expect(
        shouldLoadRustFromCurrentProcess(operatingSystem: 'windows'), isFalse);
  });
}

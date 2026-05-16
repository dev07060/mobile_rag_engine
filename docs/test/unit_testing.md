# Unit Testing Guide

This guide explains how to write unit tests for applications that use `mobile_rag_engine`.

## The Challenge: Native Dependencies

`mobile_rag_engine` relies on Rust binaries and the ONNX Runtime for its core functionality. In a standard Dart unit test environment (`flutter test`), these native libraries are often unavailable or cannot be initialized, leading to `RustLibraryException` or `MissingPluginException`.

To solve this, the package provides a **Mock Injection Mechanism** that allows you to test your app's logic without loading the native engine.

## Prerequisites

We recommend using [mocktail](https://pub.dev/packages/mocktail) for creating mocks, as it provides a simple, type-safe API.

Add it to your `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.0
```

## Basic Setup

The core method for testing is `MobileRag.setMockInstance(mock)`. This injects your mock implementation into the `MobileRag` singleton, bypassing the native initialization check.

### 1. Create a Mock Class

```dart
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mocktail/mocktail.dart';

class MockMobileRag extends Mock implements MobileRag {}
```

### 2. Inject the Mock

Use `setUp` and `tearDown` to ensure a clean state for every test.

```dart
void main() {
  late MockMobileRag mockRag;

  setUp(() {
    mockRag = MockMobileRag();
    // Inject the mock
    MobileRag.setMockInstance(mockRag);
  });

  tearDown(() {
    // Clear the singleton
    MobileRag.setMockInstance(null);
  });
  
  // ... tests ...
}
```

## Testing Scenarios

> **Type note:** ID-bearing fields such as `chunkId`, `sourceId`, and the counters on `SourceStats` are typed as `PlatformInt64` in the generated FFI. On the supported platforms (iOS / Android / macOS) this is an `int` alias, so the `int` literals in the snippets below compile as-is. If you ever target the web, switch to `BigInt`-backed literals.

### Scenario 1: Mocking Search Results

When testing UI code that displays search results, you don't need the real engine to run a query. You just need to return a predefined `RagSearchResult`.

```dart
test('SearchScreen displays results correctly', () async {
  // 1. Arrange
  final mockContext = AssembledContext(
    text: "Flutter is a UI toolkit.", 
    estimatedTokens: 5,
    includedChunks: [],
    remainingBudget: 1000,
  );
  
  // Mock the search method
  when(() => mockRag.search(any(), tokenBudget: any(named: 'tokenBudget')))
      .thenAnswer((_) async => RagSearchResult(
            chunks: [
              ChunkSearchResult(
                chunkId: 1, 
                sourceId: 1, 
                content: "Flutter is...", 
                chunkIndex: 0, 
                chunkType: 'text', 
                similarity: 0.9, 
                metadata: null
              )
            ],
            context: mockContext,
          ));

  // 2. Act
  // Calling the singleton now routes to your mock
  final result = await MobileRag.instance.search(
    'What is Flutter?',
    tokenBudget: 1000,
  );

  // 3. Assert
  expect(result.context.text, equals("Flutter is a UI toolkit."));
  verify(() => mockRag.search(any(), tokenBudget: any(named: 'tokenBudget')))
      .called(1);
});
```

### Scenario 2: Mocking Document Ingestion

You can simulate successful or failed document additions without parsing actual files.

```dart
test('Add document success flow', () async {
  when(() => mockRag.addDocument(any(), filePath: any(named: 'filePath')))
      .thenAnswer((_) async => SourceAddResult(
            sourceId: 1, 
            isDuplicate: false, 
            chunkCount: 5, 
            message: 'Success'
          ));

  await MobileRag.instance.addDocument('Content', filePath: 'doc.pdf');
  
  verify(() => mockRag.addDocument('Content', filePath: 'doc.pdf')).called(1);
});
```

### Scenario 3: Error Handling

Test how your app reacts when the engine fails (e.g., database error).

```dart
test('Handles engine errors gracefully', () async {
  // Simulate a state error (e.g., DB locked)
  when(() => mockRag.search(any()))
      .thenThrow(StateError("Database locked"));

  // Expect your logic to catch it
  expect(
    () => MobileRag.instance.search('query'),
    throwsStateError,
  );
});
```

## Testing `RagEngine` Directly

If your app uses `RagEngine` instances directly (instead of the `MobileRag` singleton), you can mock that too.

```dart
class MockRagEngine extends Mock implements RagEngine {}

test('Direct engine usage', () async {
  final mockEngine = MockRagEngine();
  
  // If you inject this into your classes, you can mock methods similarly:
  when(() => mockEngine.getStats()).thenAnswer(
    (_) async => SourceStats(sourceCount: 10, chunkCount: 500)
  );
  
  final stats = await mockEngine.getStats();
  expect(stats.chunkCount, 500);
});
```

## Integration Testing

If you need to test the **real** engine performance or accuracy:
1.  Run tests on a physical device or emulator (not the host machine).
2.  Use `integration_test` package.
3.  Ensure `assets/` are included in the test build.

Mocking is strictly for **Unit Tests** where the native environment is unavailable.

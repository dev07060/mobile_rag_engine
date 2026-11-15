// Fake embedding workers for EmbeddingService.startWorkerForTest. They speak
// the same protocol as the ONNX worker: `embed` is answered with a
// TransferableTypedData of a Float32List, `dispose` with null.
import 'dart:isolate';
import 'dart:typed_data';

/// Dimension of the vectors the fake workers return.
const fakeEmbeddingDimension = 384;

/// Deterministic, non-zero vector for [text].
Float32List fakeEmbedding(String text) {
  final vector = Float32List(fakeEmbeddingDimension);
  var hash = 17;
  for (final unit in text.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  for (var i = 0; i < vector.length; i++) {
    hash = (hash * 1103515245 + 12345) & 0x3fffffff;
    vector[i] = (hash % 2001 - 1000) / 1000.0;
  }
  vector[0] += 2.0;
  return vector;
}

Future<void> _serve(
  SendPort main, {
  Duration? delay,
  bool answerEmbed = true,
}) async {
  final port = ReceivePort();
  main.send(port.sendPort);
  await for (final message in port) {
    final request = message as Map;
    final reply = request['replyPort'] as SendPort;
    switch (request['cmd']) {
      case 'embed':
        if (!answerEmbed) break;
        if (delay != null) await Future<void>.delayed(delay);
        reply.send(
          TransferableTypedData.fromList([
            fakeEmbedding(request['text'] as String),
          ]),
        );
      case 'dispose':
        reply.send(null);
        port.close();
    }
  }
}

/// Answers every request at once.
void answeringWorker(SendPort main) => _serve(main);

/// Answers each embed after 20 ms, like a slow model.
void slowWorker(SendPort main) =>
    _serve(main, delay: const Duration(milliseconds: 20));

/// Never answers `embed`, like a worker that is stuck or already gone.
void silentWorker(SendPort main) => _serve(main, answerEmbed: false);

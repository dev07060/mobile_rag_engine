// lib/services/embedding_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:mobile_rag_engine/src/internal/embedding_dimension_state.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;

/// Dart-based embedding service backed by a dedicated background isolate.
///
/// All ONNX inference runs on a long-lived worker isolate so that the main
/// isolate (UI thread) is never blocked. The public API is unchanged:
///
/// ```dart
/// await EmbeddingService.init(modelPath: '/path/to/model.onnx');
/// final embedding = await EmbeddingService.embed('Hello world');
/// await EmbeddingService.disposeAsync();
/// ```
class EmbeddingService {
  // ── Worker isolate state ──────────────────────────────────────────────
  static Isolate? _workerIsolate;
  static SendPort? _workerSendPort;
  static final EmbeddingDimensionState _dimensionState =
      EmbeddingDimensionState();

  /// Debug mode flag — forwarded to the worker on each embed call.
  static bool debugMode = false;

  // ── Public API (unchanged signatures) ─────────────────────────────────

  /// Initialize ONNX model on a background worker isolate.
  ///
  /// Provide either [modelBytes] (loads from memory) or [modelPath] (loads
  /// from file). [modelPath] is recommended for memory optimization.
  ///
  /// [intraOpNumThreads] configures ONNX intra-op parallelism. If omitted,
  /// the ONNX default is used.
  ///
  /// The [options] parameter is retained for backward compatibility but is
  /// **ignored** — `OrtSessionOptions` cannot be transferred across isolate
  /// boundaries. Use [intraOpNumThreads] instead.
  static Future<void> init({
    Uint8List? modelBytes,
    String? modelPath,
    OrtSessionOptions? options,
    int? intraOpNumThreads,
  }) async {
    if (options != null && intraOpNumThreads == null) {
      debugPrint(
        '[EmbeddingService] Warning: OrtSessionOptions cannot be transferred to '
        'the background worker isolate. Use intraOpNumThreads instead.',
      );
    }

    // Tear down any previous worker.
    await _shutdownWorker();

    // Spawn a fresh worker isolate.
    final bootstrapPort = ReceivePort();
    _workerIsolate = await Isolate.spawn(
      _workerEntryPoint,
      bootstrapPort.sendPort,
    );

    // First message from the worker is its own SendPort.
    _workerSendPort = await bootstrapPort.first as SendPort;
    bootstrapPort.close();

    // Send the init command and wait for acknowledgement.
    final replyPort = ReceivePort();
    _workerSendPort!.send({
      'cmd': 'init',
      'modelPath': modelPath,
      'modelBytes': modelBytes,
      'intraOpNumThreads': intraOpNumThreads,
      'replyPort': replyPort.sendPort,
    });

    final result = await replyPort.first;
    replyPort.close();

    if (result is Map && result['error'] != null) {
      await _shutdownWorker();
      throw Exception(result['error']);
    }
  }

  /// Convert text to an embedding vector.
  ///
  /// The inference runs entirely on the background worker isolate so this
  /// call never blocks the UI thread. The returned [Float32List] is
  /// transferred across the isolate boundary without copying via
  /// [TransferableTypedData]; downstream FFI consumers (`rag_engine_flutter`)
  /// also expect `Float32List`, so no further conversion is performed.
  static Future<Float32List> embed(String text) async {
    final sendPort = _workerSendPort;
    if (sendPort == null) {
      throw Exception("EmbeddingService not initialized. Call init() first.");
    }

    final replyPort = ReceivePort();
    sendPort.send({
      'cmd': 'embed',
      'text': text,
      'debugMode': debugMode,
      'replyPort': replyPort.sendPort,
    });

    final result = await replyPort.first;
    replyPort.close();

    if (result is Map && result['error'] != null) {
      throw Exception(result['error']);
    }

    final embedding = (result as TransferableTypedData)
        .materialize()
        .asFloat32List();
    _dimensionState.validateAndRemember(embedding.length);
    return embedding;
  }

  /// Batch embed multiple texts (sequential processing).
  ///
  /// ONNX session doesn't support concurrent access, so processing is
  /// sequential. Each embed call is dispatched to the worker isolate.
  ///
  /// [texts]: List of texts to embed
  /// [onProgress]: Progress callback (completed count, total count)
  static Future<List<Float32List>> embedBatch(
    List<String> texts, {
    int concurrency = 1,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_workerSendPort == null) {
      throw Exception("EmbeddingService not initialized. Call init() first.");
    }

    if (texts.isEmpty) return <Float32List>[];

    final results = <Float32List>[];
    for (var i = 0; i < texts.length; i++) {
      final embedding = await embed(texts[i]);
      results.add(embedding);
      onProgress?.call(i + 1, texts.length);
    }
    return results;
  }

  /// Release resources deterministically.
  static Future<void> disposeAsync() async {
    await _shutdownWorker();
    _dimensionState.reset();
  }

  /// Backward compatible, non-blocking dispose.
  ///
  /// For deterministic shutdown, prefer `await disposeAsync()`.
  static void dispose() {
    unawaited(disposeAsync());
  }

  // ── Private helpers ───────────────────────────────────────────────────

  static Future<void> _shutdownWorker() async {
    final sendPort = _workerSendPort;
    if (sendPort != null) {
      final replyPort = ReceivePort();
      sendPort.send({'cmd': 'dispose', 'replyPort': replyPort.sendPort});
      await replyPort.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      replyPort.close();
    }

    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Worker Isolate — all ONNX work happens here, never on the UI thread.
// ═══════════════════════════════════════════════════════════════════════════

/// Top-level entry point for the worker isolate.
Future<void> _workerEntryPoint(SendPort mainSendPort) async {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSession? session;
  Set<String> requiredInputNames = {};

  await for (final message in receivePort) {
    final msg = message as Map<String, dynamic>;
    final cmd = msg['cmd'] as String;
    final replyPort = msg['replyPort'] as SendPort;

    switch (cmd) {
      case 'init':
        try {
          // Initialize Rust FFI (required for tokenizer)
          if (Platform.isMacOS) {
            await RustLib.init(
              externalLibrary: frb.ExternalLibrary.process(
                iKnowHowToUseIt: true,
              ),
            );
          } else {
            await RustLib.init();
          }

          // Initialize ONNX Runtime
          OrtEnv.instance.init();

          final sessionOptions = OrtSessionOptions();
          final threads = msg['intraOpNumThreads'] as int?;
          if (threads != null) {
            try {
              sessionOptions.setIntraOpNumThreads(threads);
            } catch (_) {
              // Best-effort; fall back to ONNX default.
            }
          }

          final modelPath = msg['modelPath'] as String?;
          final modelBytes = msg['modelBytes'] as Uint8List?;

          if (modelPath != null) {
            session = OrtSession.fromFile(File(modelPath), sessionOptions);
          } else if (modelBytes != null) {
            session = OrtSession.fromBuffer(modelBytes, sessionOptions);
          } else {
            replyPort.send({
              'error': 'Either modelBytes or modelPath must be provided',
            });
            continue;
          }

          requiredInputNames = session.inputNames.toSet();
          replyPort.send({'ok': true});
        } catch (e) {
          replyPort.send({'error': e.toString()});
        }

      case 'embed':
        try {
          if (session == null) {
            replyPort.send({'error': 'Not initialized'});
            continue;
          }

          final text = msg['text'] as String;
          final debug = msg['debugMode'] as bool? ?? false;

          // 1. Tokenize with Rust tokenizer
          final tokenIds = tokenize(text: text);
          final seqLen = tokenIds.length;
          final attentionMask = List<int>.filled(seqLen, 1);

          if (debug) {
            debugPrint('[DEBUG] Text: "$text"');
            debugPrint(
              '[DEBUG] Token IDs: $tokenIds (length: ${tokenIds.length})',
            );
          }

          // 2. Create ONNX input tensors
          final inputIdsData = Int64List.fromList(
            tokenIds.map((e) => e.toInt()).toList(),
          );
          final attentionMaskData = Int64List.fromList(
            attentionMask.map((e) => e.toInt()).toList(),
          );
          final shape = [1, seqLen];

          final inputIdsTensor = OrtValueTensor.createTensorWithDataList(
            inputIdsData,
            shape,
          );
          final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(
            attentionMaskData,
            shape,
          );
          OrtValueTensor? tokenTypeIdsTensor;

          final inputs = <String, OrtValue>{
            'input_ids': inputIdsTensor,
            'attention_mask': attentionMaskTensor,
          };

          if (requiredInputNames.contains('token_type_ids')) {
            final tokenTypeIdsData = Int64List.fromList(
              List<int>.filled(seqLen, 0),
            );
            tokenTypeIdsTensor = OrtValueTensor.createTensorWithDataList(
              tokenTypeIdsData,
              shape,
            );
            inputs['token_type_ids'] = tokenTypeIdsTensor;
          }

          // 3. Run inference
          final runOptions = OrtRunOptions();
          List<OrtValue?>? outputs;
          try {
            outputs = await session.runAsync(runOptions, inputs);
          } catch (e) {
            // Wrap input-signature errors with helpful context.
            final message = e.toString();
            if (message.contains('Missing Input') ||
                message.contains('Invalid Feed Input Name')) {
              final sortedNames = requiredInputNames.toList()..sort();
              replyPort.send({
                'error':
                    'ONNX input signature mismatch: $message\n'
                    'Model input names: ${sortedNames.join(', ')}\n'
                    'mobile_rag_engine sends: input_ids, attention_mask, '
                    'optional token_type_ids.',
              });
              continue;
            }
            rethrow;
          } finally {
            inputIdsTensor.release();
            attentionMaskTensor.release();
            tokenTypeIdsTensor?.release();
            runOptions.release();
          }

          // 4. Extract results and apply mean pooling.
          // Accumulate in f64 for precision, narrow to f32 once at the end,
          // and transfer the Float32List across the isolate boundary without
          // copying via TransferableTypedData.
          try {
            final outputTensor = outputs?[0];
            if (outputTensor == null) {
              replyPort.send({'error': 'ONNX inference returned null output'});
              continue;
            }

            final outputData = outputTensor.value as List;
            Float32List embedding;

            if (outputData.isNotEmpty && outputData[0] is List) {
              final batchData = outputData[0] as List;
              if (batchData.isNotEmpty && batchData[0] is List) {
                // 3D output: [batch, seq_len, hidden] → mean pooling
                final hiddenSize = (batchData[0] as List).length;
                final accumulator = Float64List(hiddenSize);

                int count = 0;
                for (int t = 0; t < batchData.length; t++) {
                  if (t < attentionMask.length && attentionMask[t] == 1) {
                    final tokenEmb = batchData[t] as List;
                    for (int h = 0; h < hiddenSize; h++) {
                      accumulator[h] += (tokenEmb[h] as num).toDouble();
                    }
                    count++;
                  }
                }

                embedding = Float32List(hiddenSize);
                if (count > 0) {
                  for (int h = 0; h < hiddenSize; h++) {
                    embedding[h] = accumulator[h] / count;
                  }
                }

                if (debug) {
                  debugPrint(
                    '[DEBUG] Embedding (first 5): ${embedding.take(5).toList()}',
                  );
                }
              } else {
                // 2D output: [batch, hidden]
                embedding = Float32List(batchData.length);
                for (int i = 0; i < batchData.length; i++) {
                  embedding[i] = (batchData[i] as num).toDouble();
                }
              }
            } else {
              // 1D output: [hidden]
              embedding = Float32List(outputData.length);
              for (int i = 0; i < outputData.length; i++) {
                embedding[i] = (outputData[i] as num).toDouble();
              }
            }

            replyPort.send(TransferableTypedData.fromList([embedding]));
          } finally {
            for (final output in outputs ?? <OrtValue?>[]) {
              output?.release();
            }
          }
        } catch (e) {
          replyPort.send({'error': e.toString()});
        }

      case 'dispose':
        try {
          session?.release();
          session = null;
          requiredInputNames = {};
          OrtEnv.instance.release();
        } catch (_) {
          // Best-effort cleanup.
        }
        replyPort.send({'ok': true});
        receivePort.close();
        return; // Exit the worker isolate.
    }
  }
}

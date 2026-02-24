// lib/services/embedding_service.dart
import 'dart:io';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart';
import 'package:flutter/foundation.dart';

/// Dart-based embedding service
/// Rust tokenizer + Flutter ONNX Runtime combination
class EmbeddingService {
  static OrtSession? _session;
  static Set<String> _requiredInputNames = <String>{};

  /// Debug mode flag
  static bool debugMode = false;

  /// Initialize ONNX model
  ///
  /// Provide either [modelBytes] (loads from memory) or [modelPath] (loads from file).
  /// [modelPath] is recommended for memory optimization.
  static Future<void> init({
    Uint8List? modelBytes,
    String? modelPath,
    OrtSessionOptions? options,
  }) async {
    OrtEnv.instance.init();
    final sessionOptions = options ?? OrtSessionOptions();

    if (modelPath != null) {
      // Load from file (Memory efficient)
      // Note: Assuming 'fromFile' exists based on standard ONNX Runtime API patterns.
      // If the specific binding uses a different name (e.g. create path), we'll catch it.
      // The web search indicated session creation from file is supported.
      try {
        _session = OrtSession.fromFile(File(modelPath), sessionOptions);
        if (debugMode) {
          debugPrint('[EmbeddingService] Loaded model from file: $modelPath');
        }
      } catch (e) {
        // Fallback or rethrow?
        // If fromFile is not found, we might need to check if binding exposes naming differently.
        // But for now let's assume standard API.
        rethrow;
      }
    } else if (modelBytes != null) {
      // Legacy: Load from memory (Double buffering)
      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      if (debugMode) {
        debugPrint('[EmbeddingService] Loaded model from memory buffer');
      }
    } else {
      throw ArgumentError('Either modelBytes or modelPath must be provided');
    }

    _refreshRequiredInputNames();
  }

  /// Convert text to 384-dimensional embedding
  static Future<List<double>> embed(String text) async {
    if (_session == null) {
      throw Exception("EmbeddingService not initialized. Call init() first.");
    }

    // 1. Tokenize with Rust tokenizer
    final tokenIds = tokenize(text: text);

    if (debugMode) {
      debugPrint('[DEBUG] Text: "$text"');
      debugPrint('[DEBUG] Token IDs: $tokenIds (length: ${tokenIds.length})');
    }

    // 2. Generate attention_mask
    final seqLen = tokenIds.length;
    final attentionMask = List<int>.filled(seqLen, 1);

    // 3. Create ONNX input tensors
    final inputIdsData = Int64List.fromList(
      tokenIds.map((e) => e.toInt()).toList(),
    );
    final attentionMaskData = Int64List.fromList(
      attentionMask.map((e) => e.toInt()).toList(),
    );
    // BGE-m3 / many modern embedding models do not use token_type_ids
    // Passing it to a model that doesn't expect it causes an ONNX runtime error.

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

    if (_requiresInput('token_type_ids')) {
      final tokenTypeIdsData = Int64List.fromList(List<int>.filled(seqLen, 0));
      tokenTypeIdsTensor = OrtValueTensor.createTensorWithDataList(
        tokenTypeIdsData,
        shape,
      );
      inputs['token_type_ids'] = tokenTypeIdsTensor;
    }

    // 4. Run inference
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session!.runAsync(runOptions, inputs);
    } catch (e, st) {
      final wrapped = _buildInputSignatureException(e);
      if (wrapped != null) {
        Error.throwWithStackTrace(wrapped, st);
      }
      rethrow;
    } finally {
      inputIdsTensor.release();
      attentionMaskTensor.release();
      tokenTypeIdsTensor?.release();
      runOptions.release();
    }

    // 5. Extract results and apply mean pooling
    try {
      final outputTensor = outputs?[0];
      if (outputTensor == null) {
        throw Exception("ONNX inference returned null output");
      }

      final outputData = outputTensor.value as List;

      if (debugMode) {
        debugPrint('[DEBUG] Output shape: ${_getShape(outputData)}');
      }

      // [1, seq_len, 384] -> mean pooling -> [384]
      List<double> embedding;
      if (outputData.isNotEmpty && outputData[0] is List) {
        // 3D output: [batch, seq_len, hidden]
        final batchData = outputData[0] as List;
        if (batchData.isNotEmpty && batchData[0] is List) {
          final hiddenSize = (batchData[0] as List).length;
          embedding = List<double>.filled(hiddenSize, 0.0);

          // Apply mean pooling over all tokens (with attention mask)
          // Includes CLS and SEP - sentence-transformers default behavior
          int count = 0;
          for (int t = 0; t < batchData.length; t++) {
            // Only include tokens with attention_mask == 1
            if (t < attentionMask.length && attentionMask[t] == 1) {
              final tokenEmb = batchData[t] as List;
              for (int h = 0; h < hiddenSize; h++) {
                embedding[h] += (tokenEmb[h] as num).toDouble();
              }
              count++;
            }
          }

          if (count > 0) {
            for (int h = 0; h < hiddenSize; h++) {
              embedding[h] /= count;
            }
          }

          if (debugMode) {
            debugPrint(
              '[DEBUG] Embedding (first 5): ${embedding.take(5).toList()}',
            );
          }
        } else {
          // 2D output: [batch, hidden]
          embedding = (batchData).map((e) => (e as num).toDouble()).toList();
        }
      } else {
        // 1D output: [hidden]
        embedding = outputData.map((e) => (e as num).toDouble()).toList();
      }

      return embedding;
    } finally {
      for (final output in outputs ?? <OrtValue?>[]) {
        output?.release();
      }
    }
  }

  /// Batch embed multiple texts (sequential processing)
  ///
  /// ONNX session doesn't support concurrent access, so processing is sequential
  ///
  /// [texts]: List of texts to embed
  /// [onProgress]: Progress callback (completed count, total count)
  static Future<List<List<double>>> embedBatch(
    List<String> texts, {
    int concurrency = 1, // Sequential due to ONNX session limitation
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_session == null) {
      throw Exception("EmbeddingService not initialized. Call init() first.");
    }

    if (texts.isEmpty) return [];

    final results = <List<double>>[];

    // Sequential processing (ONNX session is not thread-safe)
    for (var i = 0; i < texts.length; i++) {
      final embedding = await embed(texts[i]);
      results.add(embedding);
      onProgress?.call(i + 1, texts.length);
    }

    return results;
  }

  /// Release resources
  static void dispose() {
    _session?.release();
    _requiredInputNames = <String>{};
    OrtEnv.instance.release();
  }

  static void _refreshRequiredInputNames() {
    _requiredInputNames = _session?.inputNames.toSet() ?? <String>{};
    if (debugMode) {
      final sortedInputNames = _requiredInputNames.toList()..sort();
      debugPrint('[EmbeddingService] Model input names: $sortedInputNames');
    }
  }

  static bool _requiresInput(String inputName) {
    return _requiredInputNames.contains(inputName);
  }

  static Exception? _buildInputSignatureException(Object error) {
    final message = error.toString();
    final hasInputSignatureError =
        message.contains('Missing Input') ||
        message.contains('Invalid Feed Input Name');
    if (!hasInputSignatureError) {
      return null;
    }

    final sortedInputNames = _requiredInputNames.toList()..sort();
    final availableInputs = sortedInputNames.isEmpty
        ? '(unavailable)'
        : sortedInputNames.join(', ');

    return Exception(
      'ONNX input signature mismatch: $message\n'
      'Model input names: $availableInputs\n'
      'mobile_rag_engine sends: input_ids, attention_mask, optional token_type_ids.\n'
      'Models requiring additional mandatory inputs (e.g. position_ids) are not yet supported.',
    );
  }

  /// Get array shape as string
  static String _getShape(dynamic data) {
    if (data is! List) return 'scalar';
    if (data.isEmpty) return '[0]';
    if (data[0] is! List) return '[${data.length}]';
    if (data[0].isEmpty) return '[${data.length}, 0]';
    if (data[0][0] is! List) return '[${data.length}, ${data[0].length}]';
    return '[${data.length}, ${data[0].length}, ${data[0][0].length}]';
  }
}

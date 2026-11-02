// Shared by both phases of the upgrade harness. It must compile against the
// last published release and the PR head, so it uses only dart:io, Flutter
// and path_provider, never mobile_rag_engine.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Which scenario this process runs, from `--dart-define=H1_SCENARIO=...`.
const scenario = String.fromEnvironment('H1_SCENARIO');

/// MiniLM pack written by `dart run mobile_rag_engine:setup`.
const miniLmPack = 'assets/mobile_rag/model-pack.json';
const miniLmModel = 'assets/mobile_rag/model.onnx';
const miniLmTokenizer = 'assets/mobile_rag/tokenizer.json';

/// KoEn-E5-Tiny: another 384-dim model whose file is also `model.onnx`.
const koEnPack = 'assets/h1/koen/model-pack.json';
const koEnModel = 'assets/h1/koen/model.onnx';
const koEnTokenizer = 'assets/h1/koen/tokenizer.json';

String databaseName(String id) => 'h1_$id.sqlite';

/// The engine keeps its files in the documents directory on macOS.
Future<Directory> documentsDirectory() => getApplicationDocumentsDirectory();

/// Where S2 keeps a model the app downloaded itself (a prepared path).
Future<Directory> preparedDirectory() async =>
    Directory('${(await documentsDirectory()).path}/h1_prepared');

/// Written by phase A, read by phase B to prove the data container survived.
Future<File> phaseAMarker(String id) async =>
    File('${(await documentsDirectory()).path}/h1_phase_a_$id.json');

Future<void> copyAsset(String asset, File target) async {
  final data = await rootBundle.load(asset);
  await target.parent.create(recursive: true);
  await target.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
}

/// One result line for run.sh: `H1_CHECK <id> PASS|FAIL <detail>`.
bool report(String id, bool pass, String detail) {
  final line = detail.replaceAll(RegExp(r'\s+'), ' ');
  print('H1_CHECK $id ${pass ? 'PASS' : 'FAIL'} $line');
  return pass;
}

/// Short English passages, each longer than a fifth of the contract tool's
/// token budget, so five retrieved chunks overflow it.
const corpus = <String, String>{
  'flutter.txt':
      'Flutter is an open source UI toolkit from Google for building natively '
      'compiled applications for mobile, web and desktop from a single '
      'codebase. Widgets describe what the view should look like given its '
      'current configuration and state, and the framework rebuilds them when '
      'the state changes. Hot reload injects updated source files into the '
      'running Dart virtual machine so changes appear within a second.',
  'dart.txt':
      'Dart is a client-optimized programming language for fast apps on any '
      'platform. It compiles ahead of time to native machine code for '
      'release builds and runs on a virtual machine with just-in-time '
      'compilation during development. Sound null safety means a variable '
      'cannot contain null unless its type says it can, and isolates run '
      'code concurrently without shared memory.',
  'sqlite.txt':
      'SQLite is a small, fast, self-contained SQL database engine that '
      'stores a whole database in a single file on disk. It is the most '
      'widely deployed database in the world and ships inside every mobile '
      'phone. Write-ahead logging lets readers continue while a writer '
      'commits, and the full-text search extension builds inverted indexes '
      'for keyword queries.',
  'onnx.txt':
      'ONNX Runtime is a cross-platform inference engine for machine learning '
      'models stored in the Open Neural Network Exchange format. Quantized '
      'models store weights as eight-bit integers, which shrinks the file and '
      'speeds up inference on mobile processors. Sessions can limit the number '
      'of intra-op threads so inference does not take every CPU core.',
  'hnsw.txt':
      'Hierarchical navigable small world graphs are an approximate nearest '
      'neighbor index. Each vector links to a few close neighbors on several '
      'layers, and a search walks from a coarse layer down to the finest one. '
      'Recall depends on the ef search parameter, and inserting a vector only '
      'touches its neighborhood instead of rebuilding the whole graph.',
  'bm25.txt':
      'BM25 is a ranking function for keyword search. It scores a document by '
      'how often the query terms appear in it, discounted by how common each '
      'term is across the collection and normalized by document length. '
      'Hybrid search combines BM25 with vector similarity, for example with '
      'reciprocal rank fusion, which adds one over sixty plus the rank.',
  'tokenizer.txt':
      'A tokenizer splits text into the subword units a language model reads. '
      'WordPiece and byte pair encoding build a vocabulary from frequent '
      'character sequences, so rare words become several tokens. Embedding '
      'models truncate input after a fixed number of tokens, which is why long '
      'documents are split into chunks before they are embedded.',
  'rag.txt':
      'Retrieval augmented generation answers a question by first searching a '
      'document collection and then giving the most relevant passages to a '
      'language model as context. Citing each passage by an identifier lets '
      'the answer point back to its sources, and a token budget keeps the '
      'context small enough for the model and cheap to send.',
};

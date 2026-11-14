// Which embedding model the example app runs with (docs/milestones.md E1).
//
// Pick it at build time:
//   flutter run --dart-define=EXAMPLE_MODEL=koen
// The model files are not in git. See example/README.md for how to install
// each Model Pack into assets/models/<name>/.

import 'package:mobile_rag_engine/mobile_rag_engine.dart';

/// The engine's default hybrid weights (`MobileRag.initialize` defaults).
const engineDefaultVectorWeight = 0.2;
const engineDefaultBm25Weight = 0.8;

class ExampleModel {
  const ExampleModel({
    required this.id,
    required this.label,
    required this.languages,
    required this.dimension,
    this.vectorWeight,
    this.bm25Weight,
  });

  /// Value of `--dart-define=EXAMPLE_MODEL`.
  final String id;
  final String label;
  final String languages;
  final int dimension;

  /// Hybrid weights passed to [MobileRag.initialize]. Null keeps the engine
  /// default (vector 0.2 / BM25 0.8).
  final double? vectorWeight;
  final double? bm25Weight;

  String get manifestAsset => 'assets/models/$id/model-pack.json';

  /// Weights every search uses when it does not pass its own.
  (double, double) get effectiveWeights => (
    vectorWeight ?? engineDefaultVectorWeight,
    bm25Weight ?? engineDefaultBm25Weight,
  );

  String get weightLabel {
    final (v, b) = effectiveWeights;
    final source = vectorWeight == null ? 'engine default' : 'model recipe';
    return 'vector $v / BM25 $b ($source)';
  }

  Future<void> initialize({String databaseName = 'rag_db.sqlite'}) {
    final (v, b) = effectiveWeights;
    return MobileRag.initialize(
      modelPack: RagModelPack.asset(manifestAsset),
      // One database per model: vectors from different models cannot be mixed.
      databaseName: databaseName.replaceFirst('.sqlite', '_$id.sqlite'),
      deferIndexWarmup: true,
      threadLevel: ThreadUseLevel.medium,
      defaultVectorWeight: v,
      defaultBm25Weight: b,
    );
  }
}

const exampleModels = <String, ExampleModel>{
  // Default Model Pack (English). Keeps the engine's default weights.
  'minilm': ExampleModel(
    id: 'minilm',
    label: 'MiniLM (all-MiniLM-L6-v2)',
    languages: 'English',
    dimension: 384,
  ),
  // KoEn-E5-Tiny recipe in docs/guides/model_setup.md: 0.5 / 0.5.
  'koen': ExampleModel(
    id: 'koen',
    label: 'KoEn-E5-Tiny',
    languages: 'Korean, English',
    dimension: 384,
    vectorWeight: 0.5,
    bm25Weight: 0.5,
  ),
};

ExampleModel resolveExampleModel([
  String id = const String.fromEnvironment(
    'EXAMPLE_MODEL',
    defaultValue: 'minilm',
  ),
]) {
  final model = exampleModels[id];
  if (model == null) {
    throw ArgumentError.value(
      id,
      'EXAMPLE_MODEL',
      'expected one of ${exampleModels.keys.join(', ')}',
    );
  }
  return model;
}

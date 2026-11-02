/// Exposes on-device search as an LLM tool without depending on any LLM SDK.
library;

import 'dart:convert';

import '../mobile_rag.dart';

/// Runs one search for [RagSearchTool]: the model's [query] and [topK].
typedef RagToolSearch =
    Future<RagSearchResult> Function(String query, int topK);

/// A search tool an LLM can call, described in a provider-neutral shape.
///
/// [definition] is `{name, description, parameters}`, where `parameters` is a
/// JSON Schema object. It is the shape OpenAI's `function` and Gemini's
/// function declarations take as is; Anthropic expects the same schema under
/// `input_schema`. Pass the model's tool-call arguments to [call] (decoded) or
/// [callJson] (raw string) and send the result back as the tool result.
///
/// ```dart
/// final tool = RagSearchTool.fromMobileRag(MobileRag.instance);
/// // Register tool.definition with your LLM client, then on a tool call:
/// final output = await tool.callJson(toolCall.arguments);
/// ```
class RagSearchTool {
  RagSearchTool({
    required RagToolSearch search,
    Future<List<SourceEntry>> Function()? listSources,
    this.name = defaultName,
    this.description = defaultDescription,
    this.defaultTopK = 5,
    this.maxTopK = 10,
  }) : _search = search,
       _listSources = listSources {
    if (defaultTopK < 1 || defaultTopK > maxTopK) {
      throw ArgumentError.value(
        defaultTopK,
        'defaultTopK',
        'must be between 1 and maxTopK ($maxTopK)',
      );
    }
  }

  /// Searches [rag] with hybrid (vector + keyword) search, keeping the
  /// returned passages within [tokenBudget] engine tokens.
  factory RagSearchTool.fromMobileRag(
    MobileRag rag, {
    String name = defaultName,
    String description = defaultDescription,
    int defaultTopK = 5,
    int maxTopK = 10,
    int tokenBudget = 1500,
  }) => RagSearchTool(
    search: (query, topK) => rag.searchHybridWithContext(
      query,
      topK: topK,
      tokenBudget: tokenBudget,
    ),
    listSources: rag.listSources,
    name: name,
    description: description,
    defaultTopK: defaultTopK,
    maxTopK: maxTopK,
  );

  /// Like [RagSearchTool.fromMobileRag], scoped to one collection.
  factory RagSearchTool.fromCollection(
    CollectionRag collection, {
    String name = defaultName,
    String description = defaultDescription,
    int defaultTopK = 5,
    int maxTopK = 10,
    int tokenBudget = 1500,
  }) => RagSearchTool(
    search: (query, topK) => collection.searchHybridWithContext(
      query,
      topK: topK,
      tokenBudget: tokenBudget,
    ),
    listSources: collection.listSources,
    name: name,
    description: description,
    defaultTopK: defaultTopK,
    maxTopK: maxTopK,
  );

  static const defaultName = 'search_documents';
  static const defaultDescription =
      'Search the documents stored on this device and return the passages '
      'most relevant to the query. Each passage has an id; cite passages by '
      'id when using them in an answer.';

  final RagToolSearch _search;
  final Future<List<SourceEntry>> Function()? _listSources;

  /// Tool name the model calls.
  final String name;

  /// Tells the model when to use the tool.
  final String description;

  /// `top_k` used when the model leaves it out.
  final int defaultTopK;

  /// Largest `top_k` the schema allows; larger requests are clamped to it.
  final int maxTopK;

  /// Provider-neutral tool definition: `{name, description, parameters}`.
  Map<String, Object?> get definition => {
    'name': name,
    'description': description,
    'parameters': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'What to look for, in the language of the documents when known.',
        },
        'top_k': {
          'type': 'integer',
          'description':
              'Number of passages to retrieve (default $defaultTopK).',
          'minimum': 1,
          'maximum': maxTopK,
        },
      },
      'required': ['query'],
    },
  };

  /// Runs the search for decoded tool-call [arguments].
  ///
  /// Returns [RagSearchResult.toLlmJson] with source names filled in. Invalid
  /// arguments return `{"error": ...}` instead of throwing, so the model can
  /// correct its call; engine failures still throw.
  Future<Map<String, Object?>> call(Map<String, Object?> arguments) async {
    final query = arguments['query'];
    if (query is! String || query.trim().isEmpty) {
      return _error('"query" must be a non-empty string.');
    }
    final rawTopK = arguments['top_k'];
    int topK;
    if (rawTopK == null) {
      topK = defaultTopK;
    } else if (rawTopK is num && rawTopK == rawTopK.roundToDouble()) {
      // Some models send integral values as 5.0.
      topK = rawTopK.toInt().clamp(1, maxTopK);
    } else {
      return _error('"top_k" must be an integer between 1 and $maxTopK.');
    }

    final result = await _search(query.trim(), topK);
    return result.toLlmJson(sourceNames: await _sourceNames(result));
  }

  /// Runs the search for raw JSON [arguments] and returns the JSON result.
  ///
  /// An empty string counts as no arguments. Malformed JSON returns an
  /// `{"error": ...}` result like any other invalid call.
  Future<String> callJson(String arguments) async {
    Object? decoded;
    try {
      decoded = arguments.trim().isEmpty ? const {} : jsonDecode(arguments);
    } on FormatException {
      return jsonEncode(_error('Arguments are not valid JSON.'));
    }
    if (decoded is! Map<String, Object?>) {
      return jsonEncode(_error('Arguments must be a JSON object.'));
    }
    return jsonEncode(await call(decoded));
  }

  Future<Map<int, String>> _sourceNames(RagSearchResult result) async {
    final listSources = _listSources;
    if (listSources == null || result.context.includedChunks.isEmpty) {
      return const {};
    }
    return {
      for (final source in await listSources())
        if (source.name case final name? when name.isNotEmpty)
          source.id.toInt(): name,
    };
  }

  static Map<String, Object?> _error(String message) => {'error': message};
}

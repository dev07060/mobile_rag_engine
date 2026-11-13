import 'dart:convert';

class RelevanceSourceManifest {
  final String datasetId;
  final int schemaVersion;
  final List<RelevanceSource> sources;
  final Map<String, RelevanceSource> sourceByKey;

  RelevanceSourceManifest({
    required this.datasetId,
    required this.schemaVersion,
    required this.sources,
  }) : sourceByKey = {for (final source in sources) source.sourceKey: source} {
    if (sourceByKey.length != sources.length) {
      throw StateError('Duplicate source_key found in manifest');
    }
  }

  Set<String> get sourceKeys => sourceByKey.keys.toSet();

  static RelevanceSourceManifest parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Source manifest must be a JSON object');
    }
    return RelevanceSourceManifest.fromJson(decoded);
  }

  factory RelevanceSourceManifest.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    if (rawSources is! List) {
      throw const FormatException('"sources" must be a list');
    }
    return RelevanceSourceManifest(
      datasetId: _requiredString(json, 'dataset_id'),
      schemaVersion: _requiredInt(json, 'schema_version'),
      sources: [
        for (final rawSource in rawSources)
          RelevanceSource.fromJson(_asJsonObject(rawSource, 'source')),
      ],
    );
  }
}

class RelevanceSource {
  final String sourceKey;
  final String filePath;
  final String language;
  final Map<String, dynamic> raw;

  const RelevanceSource({
    required this.sourceKey,
    required this.filePath,
    required this.language,
    required this.raw,
  });

  factory RelevanceSource.fromJson(Map<String, dynamic> json) =>
      RelevanceSource(
        sourceKey: _requiredString(json, 'source_key'),
        filePath: _requiredString(json, 'file_path'),
        language: _optionalString(json, 'language', fallback: 'unknown'),
        raw: Map<String, dynamic>.from(json),
      );
}

class RelevanceEvalset {
  final List<RelevanceEvalItem> items;

  const RelevanceEvalset({required this.items});

  static RelevanceEvalset parseJsonl(String raw) {
    final items = <RelevanceEvalItem>[];
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      final decoded = jsonDecode(line);
      items.add(
        RelevanceEvalItem.fromJson(_asJsonObject(decoded, 'eval item')),
      );
    }
    return RelevanceEvalset(items: items);
  }

  void validateAgainst(RelevanceSourceManifest manifest) {
    final sourceKeys = manifest.sourceKeys;
    final itemIds = <String>{};

    for (final item in items) {
      if (!itemIds.add(item.itemId)) {
        throw StateError('Duplicate item_id found: ${item.itemId}');
      }
      if (!sourceKeys.contains(item.expectedSourceKey)) {
        throw StateError(
          'Unknown expected_source_key in eval item ${item.itemId}: '
          '${item.expectedSourceKey}',
        );
      }
      for (final hardNegativeKey in item.hardNegativeSourceKeys) {
        if (!sourceKeys.contains(hardNegativeKey)) {
          throw StateError(
            'Unknown hard_negative_source_key in eval item ${item.itemId}: '
            '$hardNegativeKey',
          );
        }
      }
    }
  }
}

class RelevanceEvalItem {
  final String datasetId;
  final int schemaVersion;
  final String itemId;
  final String query;
  final String language;
  final String queryType;
  final String expectedSourceKey;
  final List<String> hardNegativeSourceKeys;
  final List<String> tags;
  final String? collectedAt;
  final Map<String, dynamic> raw;

  const RelevanceEvalItem({
    required this.datasetId,
    required this.schemaVersion,
    required this.itemId,
    required this.query,
    required this.language,
    required this.queryType,
    required this.expectedSourceKey,
    required this.hardNegativeSourceKeys,
    required this.tags,
    required this.collectedAt,
    required this.raw,
  });

  String get queryClass {
    for (final tag in tags) {
      if (tag.startsWith('class:') && tag.length > 'class:'.length) {
        return tag.substring('class:'.length);
      }
    }
    return queryType;
  }

  factory RelevanceEvalItem.fromJson(Map<String, dynamic> json) {
    final hardNegativeRaw = json['hard_negative_source_keys'];
    final tagRaw = json['tags'];
    return RelevanceEvalItem(
      datasetId: _requiredString(json, 'dataset_id'),
      schemaVersion: _requiredInt(json, 'schema_version'),
      itemId: _requiredString(json, 'item_id'),
      query: _requiredString(json, 'query'),
      language: _optionalString(json, 'language', fallback: 'unknown'),
      queryType: _optionalString(json, 'query_type', fallback: 'positive'),
      expectedSourceKey: _requiredString(json, 'expected_source_key'),
      hardNegativeSourceKeys: hardNegativeRaw is List
          ? [for (final key in hardNegativeRaw) key.toString()]
          : const [],
      tags: tagRaw is List
          ? [for (final tag in tagRaw) tag.toString()]
          : const [],
      collectedAt: json['collected_at'] as String?,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, Object?> toJson() => {
        'dataset_id': datasetId,
        'schema_version': schemaVersion,
        'item_id': itemId,
        'query': query,
        'language': language,
        'query_type': queryType,
        'query_class': queryClass,
        'expected_source_key': expectedSourceKey,
        'hard_negative_source_keys': hardNegativeSourceKeys,
        'tags': tags,
        if (collectedAt != null) 'collected_at': collectedAt,
      };
}

class ChunkGoldEvalset {
  final List<ChunkGoldItem> items;
  final Map<String, ChunkGoldItem> itemById;

  ChunkGoldEvalset({required this.items})
      : itemById = {for (final item in items) item.itemId: item} {
    if (itemById.length != items.length) {
      throw StateError('Duplicate chunk-gold item_id found');
    }
  }

  static ChunkGoldEvalset parseJsonl(String raw) {
    final items = <ChunkGoldItem>[];
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      final decoded = jsonDecode(line);
      items.add(ChunkGoldItem.fromJson(_asJsonObject(decoded, 'chunk-gold')));
    }
    return ChunkGoldEvalset(items: items);
  }

  void validateAgainst({
    required RelevanceSourceManifest manifest,
    required RelevanceEvalset sourceEvalset,
    required bool requireExactItemIds,
  }) {
    final sourceKeys = manifest.sourceKeys;
    final sourceItemById = {
      for (final item in sourceEvalset.items) item.itemId: item,
    };

    if (sourceItemById.length != sourceEvalset.items.length) {
      throw StateError('Duplicate source evalset item_id found');
    }

    if (requireExactItemIds) {
      final sourceIds = sourceItemById.keys.toSet();
      final goldIds = itemById.keys.toSet();
      final missing = sourceIds.difference(goldIds).toList()..sort();
      final extra = goldIds.difference(sourceIds).toList()..sort();
      if (missing.isNotEmpty || extra.isNotEmpty) {
        throw StateError(
          'Chunk-gold item_id mismatch: missing=$missing extra=$extra',
        );
      }
    }

    for (final item in items) {
      if (!sourceKeys.contains(item.goldSourceKey)) {
        throw StateError(
          'Unknown gold_source_key in chunk-gold item ${item.itemId}: '
          '${item.goldSourceKey}',
        );
      }
      for (final hardNegative in item.hardNegativePassages) {
        if (!sourceKeys.contains(hardNegative.sourceKey)) {
          throw StateError(
            'Unknown hard_negative_passage source_key in chunk-gold item '
            '${item.itemId}: ${hardNegative.sourceKey}',
          );
        }
      }

      final sourceItem = sourceItemById[item.itemId];
      if (sourceItem == null) {
        if (requireExactItemIds) {
          throw StateError('Missing source evalset item for ${item.itemId}');
        }
        continue;
      }
      if (sourceItem.expectedSourceKey != item.goldSourceKey) {
        throw StateError(
          'chunk-gold item ${item.itemId} gold_source_key '
          '${item.goldSourceKey} does not match source-level '
          'expected_source_key ${sourceItem.expectedSourceKey}',
        );
      }
    }
  }
}

class ChunkGoldItem {
  final String datasetId;
  final int schemaVersion;
  final String itemId;
  final String query;
  final String language;
  final String queryType;
  final String goldSourceKey;
  final String? goldChunkId;
  final String goldPassage;
  final int? goldSpanStart;
  final int? goldSpanEnd;
  final List<HardNegativePassage> hardNegativePassages;
  final List<String> tags;
  final String? collectedAt;
  final Map<String, dynamic> raw;

  const ChunkGoldItem({
    required this.datasetId,
    required this.schemaVersion,
    required this.itemId,
    required this.query,
    required this.language,
    required this.queryType,
    required this.goldSourceKey,
    required this.goldChunkId,
    required this.goldPassage,
    required this.goldSpanStart,
    required this.goldSpanEnd,
    required this.hardNegativePassages,
    required this.tags,
    required this.collectedAt,
    required this.raw,
  });

  String get queryClass {
    for (final tag in tags) {
      if (tag.startsWith('class:') && tag.length > 'class:'.length) {
        return tag.substring('class:'.length);
      }
    }
    return queryType;
  }

  factory ChunkGoldItem.fromJson(Map<String, dynamic> json) {
    final hardNegativeRaw = json['hard_negative_passages'];
    final tagRaw = json['tags'];
    return ChunkGoldItem(
      datasetId: _requiredString(json, 'dataset_id'),
      schemaVersion: _requiredInt(json, 'schema_version'),
      itemId: _requiredString(json, 'item_id'),
      query: _requiredString(json, 'query'),
      language: _optionalString(json, 'language', fallback: 'unknown'),
      queryType: _optionalString(json, 'query_type', fallback: 'positive'),
      goldSourceKey: _requiredString(json, 'gold_source_key'),
      goldChunkId: json['gold_chunk_id'] as String?,
      goldPassage: _requiredString(json, 'gold_passage'),
      goldSpanStart: json['gold_span_start'] as int?,
      goldSpanEnd: json['gold_span_end'] as int?,
      hardNegativePassages: hardNegativeRaw is List
          ? [
              for (final rawHardNegative in hardNegativeRaw)
                HardNegativePassage.fromJson(
                  _asJsonObject(rawHardNegative, 'hard-negative passage'),
                ),
            ]
          : const [],
      tags: tagRaw is List
          ? [for (final tag in tagRaw) tag.toString()]
          : const [],
      collectedAt: json['collected_at'] as String?,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, Object?> toJson() => {
        'dataset_id': datasetId,
        'schema_version': schemaVersion,
        'item_id': itemId,
        'query': query,
        'language': language,
        'query_type': queryType,
        'query_class': queryClass,
        'gold_source_key': goldSourceKey,
        if (goldChunkId != null) 'gold_chunk_id': goldChunkId,
        'gold_passage': goldPassage,
        if (goldSpanStart != null) 'gold_span_start': goldSpanStart,
        if (goldSpanEnd != null) 'gold_span_end': goldSpanEnd,
        'hard_negative_passages': [
          for (final passage in hardNegativePassages) passage.toJson(),
        ],
        'tags': tags,
        if (collectedAt != null) 'collected_at': collectedAt,
      };
}

class HardNegativePassage {
  final String sourceKey;
  final String passage;
  final String? reason;
  final Map<String, dynamic> raw;

  const HardNegativePassage({
    required this.sourceKey,
    required this.passage,
    required this.reason,
    required this.raw,
  });

  factory HardNegativePassage.fromJson(Map<String, dynamic> json) =>
      HardNegativePassage(
        sourceKey: _requiredString(json, 'source_key'),
        passage: _requiredString(json, 'passage'),
        reason: json['reason'] as String?,
        raw: Map<String, dynamic>.from(json),
      );

  Map<String, Object?> toJson() => {
        'source_key': sourceKey,
        'passage': passage,
        if (reason != null) 'reason': reason,
      };
}

Map<String, dynamic> _asJsonObject(Object? value, String context) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw FormatException('$context must be a JSON object');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('"$key" must be a non-empty string');
}

String _optionalString(
  Map<String, dynamic> json,
  String key, {
  required String fallback,
}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('"$key" must be a non-empty string when present');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('"$key" must be an integer');
}

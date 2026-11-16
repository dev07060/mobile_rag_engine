/// Answers a question from on-device search with a generation function the
/// app supplies, without depending on any LLM SDK.
library;

import 'llm_tool.dart';

/// Generates the answer for [prompt] with the app's LLM.
typedef RagGenerate = Future<String> Function(String prompt);

/// Builds the prompt sent to the LLM from the [question] and the [passages]
/// found for it.
typedef RagPromptBuilder =
    String Function(String question, List<RagPassage> passages);

/// A passage given to the LLM, with the citation [id] the model uses.
class RagPassage {
  const RagPassage({
    required this.id,
    required this.text,
    this.sourceId,
    this.sourceName,
    this.chunkId,
    this.score,
  });

  /// Builds a passage from one entry of [RagSearchResult.toLlmJson].
  factory RagPassage.fromLlmJson(Map<String, Object?> json) => RagPassage(
    id: json['id'] as String,
    text: json['text'] as String,
    sourceId: json['source_id'] as int?,
    sourceName: json['source_name'] as String?,
    chunkId: json['chunk_id'] as int?,
    score: (json['score'] as num?)?.toDouble(),
  );

  /// Citation label, such as `"1"`, cited in the answer as `[1]`.
  final String id;

  /// Passage text.
  final String text;

  /// Source of the passage, for example for `getSourceDocument`. Null when the
  /// search returned only assembled context.
  final int? sourceId;

  /// The `name` given to `addDocument`, when known.
  final String? sourceName;

  /// Chunk the passage came from.
  final int? chunkId;

  /// Relevance relative to the best passage (1.0).
  final double? score;
}

/// The prompt for one question, built by `prepareAsk`.
///
/// Send [prompt] to the LLM, for example with a streaming SDK, then pass the
/// complete answer to [answer].
class RagAskPrompt {
  const RagAskPrompt({
    required this.question,
    required this.prompt,
    required this.passages,
  });

  final String question;

  /// Prompt for the LLM. Empty when no passages were found.
  final String prompt;

  /// Passages included in [prompt].
  final List<RagPassage> passages;

  /// False when the search found nothing; there is nothing to send.
  bool get hasPassages => passages.isNotEmpty;

  /// Pairs the LLM's [text] with the passages it cites.
  RagAnswer answer(String text) => RagAnswer(
    question: question,
    text: text,
    prompt: prompt,
    passages: passages,
    citations: citedPassages(text, passages),
  );
}

/// An answer from `ask`, with the passages it was based on.
class RagAnswer {
  const RagAnswer({
    required this.question,
    required this.text,
    required this.prompt,
    required this.passages,
    required this.citations,
  });

  final String question;

  /// The LLM's answer. Empty when no passages were found and the LLM was not
  /// called.
  final String text;

  /// Prompt sent to the LLM.
  final String prompt;

  /// Passages given to the LLM.
  final List<RagPassage> passages;

  /// Passages cited in [text], in order of first citation. Citations of ids
  /// that were not given to the LLM are left out.
  final List<RagPassage> citations;

  /// False when the search found nothing and the LLM was not called.
  bool get hasPassages => passages.isNotEmpty;
}

/// Default prompt: instructions, numbered passages, then the question.
String defaultAskPrompt(String question, List<RagPassage> passages) {
  final buffer = StringBuffer()
    ..writeln(
      'Answer the question using only the passages below. Cite the passages '
      'you use by id, like [1] or [1][2]. If the passages do not contain the '
      'answer, say so. Answer in the language of the question.',
    )
    ..writeln();
  for (final passage in passages) {
    buffer.writeln(
      passage.sourceName == null
          ? '[${passage.id}]'
          : '[${passage.id}] ${passage.sourceName}',
    );
    buffer
      ..writeln(passage.text.trim())
      ..writeln();
  }
  buffer.write('Question: ${question.trim()}');
  return buffer.toString();
}

/// Opening and closing brackets read as citations: `[1]`, full-width
/// `［1］`, lenticular `【1】`, and the corner brackets `「1」` and `『1』`
/// that some models use instead of `[1]`. Corner
/// brackets also quote words (`「결전」`), so only digits count, and only ids
/// that were given to the model.
const _brackets = {'[': ']', '［': '］', '【': '】', '「': '」', '『': '』'};

/// One id or a range (`1-3`, `1–3`, `1~3`); ids are separated by `,`, `，`
/// or `、`. Digits may be full-width (`１`).
const _id = r'[0-9０-９]+';
const _range = '$_id(?:\\s*[-–~～〜－]\\s*$_id)?';
const _ids = '$_range(?:\\s*[,，、]\\s*$_range)*';

final _citation = RegExp(
  _brackets.entries
      .map(
        (e) =>
            '${RegExp.escape(e.key)}\\s*($_ids)\\s*${RegExp.escape(e.value)}',
      )
      .join('|'),
);

/// Inline code (`` `items[2]` ``) and fenced code blocks (``` or `~~~`).
final _code = RegExp(
  r'^ {0,3}(`{3,}|~{3,})[^\n]*\n[\s\S]*?(?:^ {0,3}\1[`~]*[ \t]*$|(?![\s\S]))|(`+)[^`\n]*?\2',
  multiLine: true,
);

String _asciiDigits(String s) => String.fromCharCodes(
  s.codeUnits.map((u) => u >= 0xFF10 && u <= 0xFF19 ? u - 0xFF10 + 0x30 : u),
);

/// Passages of [passages] cited in [text] as `[1]`, `[1, 2]`, `[1][2]`,
/// `[1-3]`, `［１］`, `【1】`, `[1、2]` or `「1」`, in order of first citation
/// and without repeats. Brackets inside inline code or fenced code blocks
/// are not citations.
List<RagPassage> citedPassages(String text, List<RagPassage> passages) {
  final byId = {for (final p in passages) p.id: p};
  final cited = <String, RagPassage>{};
  void cite(String id) {
    final passage = byId[id];
    if (passage != null) cited.putIfAbsent(passage.id, () => passage);
  }

  final prose = text.replaceAllMapped(_code, (m) => ' ' * m[0]!.length);
  for (final match in _citation.allMatches(prose)) {
    final ids = match
        .groups([for (var i = 1; i <= match.groupCount; i++) i])
        .firstWhere((g) => g != null)!;
    for (final part in ids.split(RegExp('[,，、]'))) {
      final bounds = _asciiDigits(
        part,
      ).split(RegExp('[-–~～〜－]')).map((b) => int.tryParse(b.trim())).toList();
      if (bounds.any((b) => b == null)) continue;
      if (bounds.length == 1) {
        cite('${bounds.single}');
        continue;
      }
      final (from, to) = (bounds.first!, bounds.last!);
      // Only ids that were given count, so a wide range stays cheap.
      for (final p in passages) {
        final n = int.tryParse(p.id);
        if (n != null && n >= from && n <= to) cite(p.id);
      }
    }
  }
  return cited.values.toList();
}

/// Searches with [tool] (its `defaultTopK` passages) and builds the prompt
/// for [question].
///
/// `MobileRag.prepareAsk` and `CollectionRag.prepareAsk` call this with a new
/// tool each time, so citation ids start at 1 for every question.
Future<RagAskPrompt> prepareAskWith(
  RagSearchTool tool,
  String question, {
  RagPromptBuilder buildPrompt = defaultAskPrompt,
}) async {
  if (question.trim().isEmpty) {
    throw ArgumentError.value(question, 'question', 'must not be empty');
  }
  final json = await tool.call({'query': question});
  if (json['error'] case final String error) throw ArgumentError(error);
  final passages = [
    for (final r in json['results'] as List)
      RagPassage.fromLlmJson(r as Map<String, Object?>),
  ];
  return RagAskPrompt(
    question: question,
    prompt: passages.isEmpty ? '' : buildPrompt(question, passages),
    passages: passages,
  );
}

/// [prepareAskWith], then [generate], then [RagAskPrompt.answer]. [generate]
/// is not called when no passages were found.
Future<RagAnswer> askWith(
  RagSearchTool tool,
  String question, {
  required RagGenerate generate,
  RagPromptBuilder buildPrompt = defaultAskPrompt,
}) async {
  final prepared = await prepareAskWith(
    tool,
    question,
    buildPrompt: buildPrompt,
  );
  if (!prepared.hasPassages) return prepared.answer('');
  return prepared.answer(await generate(prepared.prompt));
}

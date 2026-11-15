// Q4 B13 (docs/milestones.md): `PromptCompressor.compress` counts
// `maxTokens` with the app's token counter when one is given.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/prompt_compressor.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';

ChunkSearchResult _chunk(int id, String content) => ChunkSearchResult(
  chunkId: id,
  sourceId: 1,
  chunkIndex: id,
  content: content,
  chunkType: 'general',
  similarity: 1.0,
);

/// Korean, Japanese, Chinese, NFD Hangul, full-width, emoji and decimals.
final _chunks = [
  _chunk(0, '환불은 구매 후 14일 이내 가능합니다. 금액은 ３,５００원입니다. 버전 3.14 기준입니다.'),
  _chunk(1, '東京は大きい。北京是中国的首都。返金は14日以内です。🚀 2.5倍です。'),
  _chunk(2, '환불 예외는 없습니다! 退款需在14天内。'),
];

/// A stand-in for an LLM tokenizer that counts every code point but spaces.
int _perCodePoint(String text) =>
    text.runes.where((r) => r != 0x20 && r != 0x0A).length;

void main() {
  setUpAll(() async {
    if (!RustLib.instance.initialized) await RustLib.init();
  });

  test('without a counter, maxTokens is 4 characters per token', () async {
    final result = await PromptCompressor.compress(
      chunks: _chunks,
      maxTokens: 10,
    );
    expect(result.text.runes.length, lessThanOrEqualTo(40));
  });

  test('with a counter, the text fits maxTokens by that count and ends at a '
      'sentence end', () async {
    final full = await PromptCompressor.compress(
      chunks: _chunks,
      maxTokens: 100000,
      tokenCounter: _perCodePoint,
    );
    final fullTokens = _perCodePoint(full.text);

    for (final maxTokens in [20, 45, 60, fullTokens - 1]) {
      final result = await PromptCompressor.compress(
        chunks: _chunks,
        maxTokens: maxTokens,
        tokenCounter: _perCodePoint,
      );
      expect(
        _perCodePoint(result.text),
        lessThanOrEqualTo(maxTokens),
        reason: '$maxTokens: ${result.text}',
      );
      expect(result.text, isNotEmpty, reason: '$maxTokens');
      expect(full.text.startsWith(result.text), isTrue, reason: '$maxTokens');
      expect(result.text, matches(RegExp(r'[.!?。！？]$')), reason: '$maxTokens');
      expect(
        result.estimatedTokensSaved,
        _perCodePoint(_chunks.map((c) => c.content).join('\n\n')) -
            _perCodePoint(result.text),
      );
    }

    // 4 characters per token would keep about 4 times as much text here.
    final estimated = await PromptCompressor.compress(
      chunks: _chunks,
      maxTokens: 20,
    );
    expect(_perCodePoint(estimated.text), greaterThan(20));
  });

  test('with a counter and enough budget, nothing is cut', () async {
    final result = await PromptCompressor.compress(
      chunks: _chunks,
      maxTokens: 100000,
      tokenCounter: _perCodePoint,
    );
    expect(result.text, contains('退款需在14天内。'));
    expect(result.text, contains('3.14'));
  });
}

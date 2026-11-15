// Fitting search passages to a token budget counted with the app's LLM
// tokenizer (`promptTokenCounter` on `ask`, `prepareAsk` and
// `RagSearchTool`).
import '../../services/context_builder.dart';
import '../../services/source_rag_service.dart';
import '../rust/api/source_rag.dart' show ChunkSearchResult;

/// Engine budget used when passages are counted with a prompt token counter:
/// large enough that the engine keeps every hit whole, and within Rust `i32`.
const uncappedEngineTokenBudget = 1 << 30;

/// Runs [search] with [tokenBudget] engine tokens, or, when [count] is given,
/// with no engine budget and then keeps the passages, in relevance order,
/// whose texts fit [tokenBudget] tokens counted with [count].
Future<RagSearchResult> searchWithinPromptBudget(
  int tokenBudget,
  int Function(String text)? count,
  Future<RagSearchResult> Function(int engineTokenBudget) search,
) async {
  if (count == null) return search(tokenBudget);
  return fitToPromptTokens(
    await search(uncappedEngineTokenBudget),
    tokenBudget,
    count,
  );
}

/// The passages of [result], in order, until the next one would take the
/// texts over [tokenBudget] tokens counted with [count].
RagSearchResult fitToPromptTokens(
  RagSearchResult result,
  int tokenBudget,
  int Function(String text) count,
) {
  final included = result.context.includedChunks;
  if (included.isEmpty) return result;
  final kept = <ChunkSearchResult>[];
  var used = 0;
  for (final chunk in included) {
    final tokens = count(chunk.content);
    if (used + tokens > tokenBudget) break;
    kept.add(chunk);
    used += tokens;
  }
  return RagSearchResult(
    chunks: result.chunks,
    context: AssembledContext(
      text: kept.map((c) => c.content).join('\n\n'),
      includedChunks: kept,
      estimatedTokens: used,
      remainingBudget: tokenBudget - used,
    ),
  );
}

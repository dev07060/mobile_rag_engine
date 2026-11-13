# Answering Questions with Your LLM

`MobileRag.ask` answers a question from the stored documents. It searches,
builds a prompt with numbered passages, calls a generation function you
supply, and returns the answer with the passages it cites. The package does
not call any LLM itself; you pass your own SDK or HTTP call.

> Requires `mobile_rag_engine` 0.23.0 or later.

## Ask

```dart
final answer = await MobileRag.instance.ask(
  '환불 기간은 얼마나 되나요?',
  generate: (prompt) => myLlm.complete(prompt), // Future<String>
);

print(answer.text); // "구매일로부터 14일 이내입니다 [1]."
for (final passage in answer.citations) {
  print('[${passage.id}] ${passage.sourceName}: ${passage.text}');
}
```

For one collection, call `MobileRag.instance.inCollection('manuals').ask(...)`.

`RagAnswer` has:

| Field | Meaning |
|---|---|
| `text` | The LLM's answer, as returned by `generate`. |
| `passages` | The passages put in the prompt, with citation ids `"1"`, `"2"`, … |
| `citations` | The passages the answer cites, in order of first citation. |
| `prompt` | The prompt sent to `generate`. |
| `hasPassages` | False when no passage was found; see below. |

Each `RagPassage` has `id`, `text`, `sourceId`, `sourceName`, `chunkId` and
`score`. Use `sourceId` with `getSourceDocument` to open the cited document.

## Search and prompt

- **Search:** hybrid (vector + keyword) search for `topK` passages (default 5),
  kept within `tokenBudget` engine tokens (default 1500), the same as
  `RagSearchTool.fromMobileRag`. `vectorWeight` and `bm25Weight` change the
  fusion weights, as in `searchHybrid`; they default to 0.2 and 0.8.
- **Citation ids** start at 1 for every question.
- **Default prompt:** an instruction to answer only from the passages, cite
  them like `[1]`, say when they do not contain the answer, and answer in the
  language of the question; then each passage as `[id] source name` and its
  text; then the question. Five short passages came to about 440 tokens.
- **Your own prompt:** pass `buildPrompt: (question, passages) => ...`. Ask
  the model to cite passage ids in brackets so `citations` can find them.

## Citations

`citations` reads `[1]`, `[1, 2]`, `[1][2]` and the CJK corner brackets `「1」`, `『1』` from the answer. Ids that were
not in the prompt, such as a made-up `[9]`, are left out of `citations`, but
stay in `text`.

## Short documents next to a large one

In hybrid search, a passage reaches the top `topK` either because the vector
index ranks it high or because it matches words of the question. A one-sentence
document stored next to a large one can lose on both counts: it holds few words
to match, and with the default weights (vector 0.2, BM25 0.8) a chunk of the
large document that matches only common words of the question ("how", "is",
"the") scores above a passage that matches none.

Keyword search reduces English words to their stem (Snowball English), so
"How long is the refund period?" finds "Refunds are accepted within 14 days of
purchase." even next to a 1,800-chunk PDF. A question that shares *no* word
with the sentence still can miss it. Stemming is English-only (Korean, Japanese and
Chinese words are matched as before), and like any stemmer it joins some
unrelated words, such as "university" and "universe".

What helps, in order:

1. **Store short documents in their own collection** and ask that collection:
   `MobileRag.instance.inCollection('faq').ask(question)`. The large document's
   chunks are then not in the candidate list at all. This is the reliable
   option.
2. **Raise the vector weight for that question**:
   `ask(question, vectorWeight: 0.5, bm25Weight: 0.5)`. On "How many days do I
   have to return an item?", which shares only "days" with the sentence, the
   defaults put it second among the five passages and 0.5/0.5 put it first.
   Which weights are best depends on the embedding model (on an 80-question
   measurement, raising the vector weight helped two models and hurt a third),
   so measure before changing them everywhere.
3. **Give the short document a few more words** — a title line, or the question
   it answers. One sentence of 8 words has little for either search to work
   with.

## When nothing is found

If no passage fits the token budget, `generate` is not called. The answer has
empty `text` and `hasPassages` is false, so you can show your own message
without paying for an LLM call.

The same happens when the database or collection has no documents yet, for
example right after installing.

## Streaming

`ask` waits for the complete answer. To stream, build the prompt with
`prepareAsk`, stream with your SDK, and pass the complete text to `answer`:

```dart
final prepared = await MobileRag.instance.prepareAsk(question);
if (!prepared.hasPassages) return showNotFound();

final buffer = StringBuffer();
await for (final delta in myLlm.stream(prepared.prompt)) {
  buffer.write(delta);
  updateUi(buffer.toString());
}
final answer = prepared.answer(buffer.toString());
```

The package has no stream type of its own, because SDKs stream in different
shapes (text deltas, accumulated text, events).

## Tool calling instead

`ask` always searches once, with the question as the query. To let the model
decide when and what to search, for example in a multi-turn chat, use
`RagSearchTool`; see the [LLM Tools guide](llm_tools.md).

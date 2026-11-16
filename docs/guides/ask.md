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
  kept within `tokenBudget` engine tokens (default 1500, see
  [Token budget](#token-budget)), the same as
  `RagSearchTool.fromMobileRag`. `vectorWeight` and `bm25Weight` change the
  fusion weights for one call, as in `searchHybrid`. Without them the call uses
  `defaultVectorWeight` / `defaultBm25Weight` from `MobileRag.initialize`
  (0.2 and 0.8 unless you set them; [Model Setup](model_setup.md) lists what
  each weight found with KoEn-E5-Tiny on Korean and English documents).
- **Citation ids** start at 1 for every question.
- **Default prompt:** an instruction to answer only from the passages, cite
  them like `[1]`, say when they do not contain the answer, and answer in the
  language of the question; then each passage as `[id] source name` and its
  text; then the question. Five short passages came to about 440 tokens.
- **Your own prompt:** pass `buildPrompt: (question, passages) => ...`. Ask
  the model to cite passage ids in brackets so `citations` can find them.

## Token budget

`tokenBudget` counts tokens of the embedding model's tokenizer, not your
LLM's. The two can differ several times, most for Korean, Thai and emoji. Counted with the embedding tokenizer through `countTokens`:

| Text | MiniLM (default) | KoEn-E5-Tiny | BGE-m3 |
|---|---|---|---|
| 23 Korean characters | 38 | 10 | 10 |
| 31 Thai characters | 1 | 2 | 7 |
| 10 emoji | 1 | 2 | 11 |
| 49 English characters | 10 | 11 | 11 |

So 1500 engine tokens can be far more or far fewer tokens for your LLM.
Without `promptTokenCounter` this stays so: the default budget is still
counted in engine tokens, and a prompt can be much larger or smaller than
`tokenBudget` suggests. To budget in your LLM's tokens, pass its token count
as `promptTokenCounter`:

```dart
final answer = await MobileRag.instance.ask(
  question,
  generate: myLlm.generate,
  tokenBudget: 1500,
  promptTokenCounter: (text) => myTokenizer.encode(text).length,
);
```

With `promptTokenCounter`, `tokenBudget` counts the passage texts with that
function. The most relevant passages that fit are kept whole, in relevance
order; a passage that does not fit is left out, not cut. The counter is called
once per passage and must be synchronous; if your SDK only counts tokens
asynchronously, count before calling or use an estimate. The budget covers the
passages, not the instructions and question the prompt adds around them.
`prepareAsk`, `CollectionRag.ask` / `prepareAsk` and
`RagSearchTool.fromMobileRag` / `fromCollection` take the same parameter.
`PromptCompressor.compress` takes `tokenCounter` for `maxTokens`, which is
otherwise estimated at 4 characters per token.

## Citations

`citations` reads these forms from the answer:

- `[1]`, `[1, 2]`, `[1][2]`
- full-width `［１］`, lenticular `【1】` and the corner brackets `「1」`,
  `『1』`, which some models write instead of `[1]`
- ids separated by `、` or `，` (`[1、2]`), and ranges (`[1-3]`, `[1–3]`,
  `[1~3]`), which cite every given id in the range

Only digits inside a matching pair of brackets count, so quoted words such as
`「결전」` are not citations, and a reversed range (`[3-1]`) is ignored.
Brackets inside inline code (`` `items[2]` ``) or a fenced code block are not
citations. Ids that were not in the prompt, such as a made-up `[9]`, are left
out of `citations`, but stay in `text`.

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
with the sentence still can miss it. Stemming is English-only (Korean words are
matched as before), and like any stemmer it joins some
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
   so measure before changing them everywhere. To change them for every call,
   pass `defaultVectorWeight` / `defaultBm25Weight` to `MobileRag.initialize`.
3. **Give the short document a few more words** — a title line, or the question
   it answers. One sentence of 8 words has little for either search to work
   with.

## Splitting your own documents

When you write the documents yourself (a help screen, a game guide, an FAQ),
you choose where one ends and the next begins. What to keep in mind:

- **A long section takes several of the five places.** Text is cut into
  chunks of at most `maxChunkChars` (500 by default), and each chunk competes
  on its own. A section that lists many items becomes several chunks, and
  when the question shares a common word with them ("gold", "upgrade"), two
  or three of the five passages can come from that one section.
- **Splitting alone does not move the answer up.** Splitting such a section
  into one document per item changes which chunks fill the places, not the
  rank of a short document that answers the question: the items still share
  the common word.
- **A first line that names the topic in the words people ask with does.**
  "How to earn more gold." at the top of the gold document put it first.
- **One topic per document** keeps each passage about one thing, so the
  passages the model cites, and `RagPassage.sourceName`, point at the right
  place. Pass a `name:` to `addDocument` so the source name is not null.

Example (MiniLM Model Pack, `mobile_rag_engine` 0.23.0, default weights,
`prepareAsk` with its default 5 passages; 6 upgrade-card descriptions that
each mention "gold" and 4 short documents, on an iOS 26.4 simulator,
2026-11-16). Rank of the "Earning gold" document for "How do I earn more
gold?":

| Layout | Rank |
|---|---|
| Card descriptions as one section (679 characters, more than one chunk), short documents as written | 3 (after two chunks of that section) |
| One document per card | 3 (after two cards) |
| One section, short documents with a title line | 1 |
| One document per card, short documents with a title line | 1 |

This is one constructed example, not a measurement. 0.23.0 does not reduce
English words to their stem, so "earn" did not match "Earning"; 0.24.0
and later do. To compare the hybrid weights on documents like these, see the
measurements in [Model Setup](model_setup.md#korean-documents-koen-e5-tiny);
which weight is best differs between models, languages and document sets.

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

## Example: Apple Foundation Models on iOS

On iOS 26 and later, the on-device model of Apple's Foundation Models
framework can be the `generate` function. It has no Dart SDK, so call it
through a method channel. The model is not always there (older iOS, a device
without Apple Intelligence, Apple Intelligence turned off, the model still
downloading), and a call can fail on its safety guardrails or when the prompt
is longer than its context window. In each case, show the passages search
found instead of an answer.

`ios/Runner/AppDelegate.swift`:

```swift
import Flutter
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let registrar = self.registrar(forPlugin: "OnDeviceLlm")!
    let channel = FlutterMethodChannel(
      name: "app/on_device_llm", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(OnDeviceLlm.isAvailable)
      case "generate":
        guard let prompt = call.arguments as? String else {
          result(FlutterError(code: "bad_arguments", message: nil, details: nil))
          return
        }
        Task {
          do {
            result(try await OnDeviceLlm.generate(prompt))
          } catch {
            result(FlutterError(
              code: OnDeviceLlm.errorCode(error), message: "\(error)", details: nil))
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

enum OnDeviceLlm {
  static var isAvailable: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *),
      case .available = SystemLanguageModel.default.availability
    {
      return true
    }
    #endif
    return false
  }

  static func generate(_ prompt: String) async throws -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let session = LanguageModelSession()
      return try await session.respond(to: prompt).content
    }
    #endif
    throw NSError(domain: "OnDeviceLlm", code: 1)
  }

  static func errorCode(_ error: Error) -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *),
      let error = error as? LanguageModelSession.GenerationError
    {
      switch error {
      case .guardrailViolation: return "guardrail"
      case .exceededContextWindowSize: return "context_too_long"
      default: return "generation_failed"
      }
    }
    #endif
    return "unavailable"
  }
}
```

Dart:

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

class OnDeviceLlm {
  static const _channel = MethodChannel('app/on_device_llm');

  static Future<bool> isAvailable() async =>
      Platform.isIOS &&
      (await _channel.invokeMethod<bool>('isAvailable') ?? false);

  static Future<String> generate(String prompt) async =>
      await _channel.invokeMethod<String>('generate', prompt) ?? '';
}

/// What the screen shows: an answer, or the passages search found.
sealed class GuideReply {}

class Answered extends GuideReply {
  Answered(this.answer);
  final RagAnswer answer;
}

class PassagesOnly extends GuideReply {
  PassagesOnly(this.passages, {this.reason});
  final List<RagPassage> passages;
  final String? reason;
}

Future<GuideReply> askGuide(String question) async {
  final prepared = await MobileRag.instance.prepareAsk(question);
  if (!prepared.hasPassages) return PassagesOnly(const []);
  if (!await OnDeviceLlm.isAvailable()) {
    return PassagesOnly(prepared.passages, reason: 'unavailable');
  }
  try {
    return Answered(prepared.answer(await OnDeviceLlm.generate(prepared.prompt)));
  } on PlatformException catch (e) {
    // guardrail, context_too_long, generation_failed: show what search found.
    return PassagesOnly(prepared.passages, reason: e.code);
  }
}
```

Notes:

- `prepareAsk` searches before the model is asked, so the passages are ready
  for the fallback without a second search. `askGuide` calls `isAvailable`
  each time because availability can change while the app runs (for example
  when the model finishes downloading).
- The context window of the on-device model is small. If you see
  `context_too_long`, lower `tokenBudget` or `topK`; see
  [Token budget](#token-budget) for why engine tokens and the model's tokens
  differ.
- **Test generation on a device.** In the iOS Simulator, availability follows
  the Mac, not a phone: on one Mac it reported the model as available and
  generation still failed; on another (iOS 26.4 simulator) it reported it as
  unavailable, so the example showed the passages.

## Tool calling instead

`ask` always searches once, with the question as the query. To let the model
decide when and what to search, for example in a multi-turn chat, use
`RagSearchTool`; see the [LLM Tools guide](llm_tools.md).

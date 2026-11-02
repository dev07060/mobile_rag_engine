# Search as an LLM Tool

`mobile_rag_engine` does not call any LLM. It gives you search results in a
shape any LLM client can use: a JSON result with citation ids, and a search
tool definition the model can call. You keep your own LLM SDK or HTTP client.

> Requires the release after `mobile_rag_engine` 0.22.3.

## Results as JSON

`RagSearchResult.toLlmJson()` turns a search result into plain JSON:

```dart
final result = await MobileRag.instance.searchHybridWithContext(
  '환불 기간',
  tokenBudget: 1500,
);
final json = result.toLlmJson(sourceNames: {7: 'refund.md'});
```

```json
{
  "results": [
    {
      "id": "1",
      "source_id": 7,
      "source_name": "refund.md",
      "chunk_id": 31,
      "chunk_index": 1,
      "score": 1.0,
      "text": "환불은 구매일로부터 14일 이내에 ..."
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `results` | The passages that fit the token budget, in context order. Each passage text appears once. |
| `id` | Citation label for the model (`"1"`, `"2"`, …). Labels start at `firstId` (default 1). |
| `source_id`, `chunk_id` | Map a citation back to the document, for example with `getSourceDocument(sourceId)`. |
| `source_name` | The `name` given to `addDocument`, when known. Left out otherwise. |
| `chunk_index` | Position of the chunk within its source. |
| `score` | Relevance relative to the best passage in this result, which scores 1.0. Rounded to three decimals. Compare scores only within one result. |
| `text` | The passage text. |

Chunk metadata and the engine's assembled `context.text` (the same passages
wrapped in `<document>` blocks) are not included, to keep tool results small.

Hybrid search ranks by reciprocal rank fusion, so its raw similarity is tiny
(about 0.016 at best) and says nothing on its own. `score` is therefore
relative. With vector-only search, the absolute cosine similarity is still on
`ChunkSearchResult.similarity`.

A result from `SearchHydrationMode.contextOnly` has no passage list. It becomes
one passage with only `id` and `text` (the assembled context).

## Search as a tool

`RagSearchTool` lets the model decide when to search:

```dart
final tool = RagSearchTool.fromMobileRag(MobileRag.instance);
// For one collection: RagSearchTool.fromCollection('manuals')
```

`tool.definition` is provider-neutral:

```json
{
  "name": "search_documents",
  "description": "Search the documents stored on this device ...",
  "parameters": {
    "type": "object",
    "properties": {
      "query": {"type": "string", "description": "..."},
      "top_k": {"type": "integer", "minimum": 1, "maximum": 10, "description": "..."}
    },
    "required": ["query"]
  }
}
```

When the model calls the tool, pass its arguments to `tool.callJson(String)`
(arguments as a JSON string) or `tool.call(Map)` (already decoded). Then send
the output back as the tool result.

- **Search:** hybrid (vector + keyword) search, with passages kept within
  `tokenBudget` engine tokens (default 1500).
- **Citation ids:** keep counting across calls on one tool. If the first
  search returns passages 1–3, the next starts at 4, so ids never collide
  within a conversation. Create a new tool for each conversation.
- **Source names:** filled in from `listSources()` on each call that finds
  passages. Names are not cached, because a removed source's id can be reused.
- **Re-initializing:** the tool keeps working after `MobileRag.dispose()` and
  a new `MobileRag.initialize()`. `fromCollection` looks the collection up on
  `MobileRag.instance` for every call.
- **`top_k`:** defaults to `defaultTopK` (5). Values above `maxTopK` are clamped
  to it.
- **Invalid arguments:** a missing query or malformed JSON returns
  `{"error": "..."}` instead of throwing, so the model can fix its call. Engine
  errors still throw.

The name, description, `defaultTopK`, `maxTopK` and `tokenBudget` can be set on
the factory. The main `RagSearchTool(search: ...)` constructor takes any search
function, for example with your own filters.

## Provider formats

The examples below show the request and response JSON, not a specific SDK.
Field names follow each provider's API at the time of writing.

### OpenAI (Chat Completions)

```dart
final tools = [
  {'type': 'function', 'function': tool.definition},
];
// For each tool call in the assistant message:
final output = await tool.callJson(toolCall['function']['arguments']);
messages.add({
  'role': 'tool',
  'tool_call_id': toolCall['id'],
  'content': output,
});
```

### Anthropic (Messages)

Anthropic takes the schema as `input_schema` and sends decoded arguments:

```dart
final d = tool.definition;
final tools = [
  {
    'name': d['name'],
    'description': d['description'],
    'input_schema': d['parameters'],
  },
];
// For each content block with type "tool_use":
final output = jsonEncode(await tool.call(block['input']));
messages.add({
  'role': 'user',
  'content': [
    {'type': 'tool_result', 'tool_use_id': block['id'], 'content': output},
  ],
});
```

### Gemini

Gemini takes the definition inside `functionDeclarations`, and expects the
function response as an object:

```dart
final tools = [
  {
    'functionDeclarations': [tool.definition],
  },
];
// For each part with a functionCall:
final output = await tool.call(part['functionCall']['args']);
contents.add({
  'role': 'user',
  'parts': [
    {
      'functionResponse': {'name': tool.name, 'response': output},
    },
  ],
});
```

## Without tool calling

For models without tool calling, search first and put the JSON in the prompt.
Ask the model to cite passage ids:

```dart
final result = await MobileRag.instance.searchHybridWithContext(question);
final prompt = '''
Answer using only the passages below. Cite passage ids like [1].

${jsonEncode(result.toLlmJson()['results'])}

Question: $question''';
```

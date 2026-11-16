# Markdown Structure-Aware Chunker

The `mobile_rag_engine` provides a highly specialized **Markdown Chunker** designed specifically for RAG (Retrieval-Augmented Generation) applications. Unlike simple text splitters that blindly cut text at fixed character limits, this chunker understands the *structure* of Markdown documents to preserve semantic context.

## Key Features

### 1. Structure Preservation
The chunker respects the logical boundaries of Markdown elements. It ensures that semantic units are kept intact whenever possible.

*   **Code Blocks (`code`)**: Splits code blocks at line boundaries; a single line longer than the embedding model's token limit is split inside the line. If a code block exceeds the chunk size, it is split by lines, and metadata is added to link the parts (see below).
*   **Tables (`table`)**: Splits tables between rows (a row longer than the token limit is split inside the row). If a table is too large, it is split by rows while keeping each stored chunk as a raw source-backed slice.
*   **Headers**: Headers build "breadcrumbs" for context (see Header Path Inheritance). A section whose chunk has two lines or fewer gets the type `header`.

### 2. Header Path Inheritance (Context Awareness)
One of the biggest challenges in RAG is losing context when a document is sliced. For example, a chunk containing just "Run `npm install`" is useless without knowing it belongs to the "Installation > Linux" section.

The Markdown Chunker stores the **Header Path** as structured metadata on each chunk and the engine injects that path into embedding/context assembly when needed.

**Example:**
```markdown
# Agent System
## Installation
### Windows
Run `installer.exe`...
```

The resulting chunk keeps:
- `content`: `Run installer.exe...`
- `headerPath`: `Agent System > Installation > Windows`

When the engine builds embedding text or final context, it renders:
`Header Path: Agent System > Installation > Windows`

This keeps stored chunk content clean while still giving the LLM the section context it needs.

### 3. Smart Code Block Linking
When a code block is too massive to fit into a single chunk (e.g., a 2000-line config file), it must be split. Standard splitters leave these orphan chunks disconnected.

Our chunker adds **Linking Metadata** to split code blocks:
*   `batch_id`: A unique UUID shared by all chunks from the original code block.
*   `batch_index`: The sequence number (0, 1, 2...).
*   `batch_total`: The total number of chunks.

These fields are on the chunks `TextChunker.markdown` returns. They are not stored by `addDocument`, so search results do not carry them; to get the rest of a code block from a search hit, use `adjacentChunks`.

### 4. Smart Table Splitting
Large tables are still split on row boundaries so the engine never cuts through the middle of a row.

To preserve raw source offsets, the engine keeps each stored table chunk as a direct slice of the original markdown. That means the first chunk contains the table header row from the source, while later chunks continue with subsequent rows instead of receiving a synthetic repeated header row.

**Original:**
| Name | Age | Role |
|---|---|---|
| Alice | 30 | Dev |
... (50 rows) ...

**Split Chunk 2:**
| Bob | 25 | Design |
...

If you need extra table context for later chunks, treat it as a retrieval/rendering concern rather than assuming the stored chunk content has a duplicated header row.

## Usage

### Automatic (Recommended)
When you add a Markdown file through `MobileRag`, the chunker is automatically applied if the file path extension is `.md` or `.markdown` (case-insensitive). Only CommonMark headings (1 to 6 `#` followed by a space) start a section, so hashtags such as `#travel` are plain text.

```dart
await MobileRag.instance.addDocumentFromFile(
  '/path/to/guide.md',
  name: 'guide.md',
);
```

### Manual Usage
You can use the chunker directly if you are building a custom pipeline or processing text from memory.

```dart
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

final markdownText = """
# My Guide
... content ...
""";

// Chunk the markdown
final chunks = await TextChunker.markdown(
  markdownText,
  maxChars: 512, // Target chunk size
);

for (final chunk in chunks) {
  print('Type: ${chunk.chunkType}'); // text, code or code:<lang>, table, header
  print('Path: ${chunk.headerPath}'); // My Guide > ...
  print('Content: ${chunk.content}');
  
  // Access linked code block metadata
  if (chunk.batchId != null) {
     print('Part ${chunk.batchIndex} of ${chunk.batchTotal}');
  }
}
```

## Contract Notes

- Raw markdown chunk `content` is preserved as extracted text. Header path is **not** automatically prepended to stored content.
- `headerPath` is carried separately and injected into embedding/context rendering paths.
- Split table chunks preserve row boundaries, but later chunks do **not** receive a synthetic repeated header row.
- `tokenBudget` applies to the assembled `context.text`, not the full prompt wrapper that `formatPrompt()` adds later.

## Comparisons
<p align="center">
<img src="../../assets/readme-sources/comparing_markdown_structure.png" width="768" /> 
</p>

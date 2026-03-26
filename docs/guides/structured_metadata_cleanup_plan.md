# Structured Metadata Cleanup Plan

This note documents the current compatibility contract and the intended shape
of the next breaking cleanup for chunk metadata and token-count naming.

## Current Compatibility Contract

- Markdown contextual metadata is encoded as `chunkType|headerPath`.
- `renderContextText()` decodes that string and injects `Header Path: ...`
  during embedding/context assembly.
- Stored chunk content remains raw source text.
- `AssembledContext.estimatedTokens` already contains an exact engine-tokenizer
  count for `context.text`, but the field name is preserved for backward
  compatibility.

## Planned Breaking Cleanup

- Split `chunkType` and contextual path into separate fields.
  - Keep `chunkType` for the raw structural type only.
  - Add `contextualPath` or `headerPath` as a dedicated field.
- Stop requiring downstream code to parse `chunkType|headerPath`.
- Rename `estimatedTokens` to `exactTokens` once the public API can break.

## Migration Notes

- This cleanup should be treated as a schema/API change, not a silent internal
  refactor.
- A compatibility layer is required if the runtime keeps serving old chunk rows
  or serialized search results during the transition.
- Until that breaking release happens, the current encoded-string contract
  remains the source of truth.

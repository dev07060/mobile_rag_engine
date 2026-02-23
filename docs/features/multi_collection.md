# Multi-Collection (v1)

Mobile RAG Engine supports collection-scoped workflows so you can separate data domains (for example `business`, `travel`, `personal`) without splitting databases.

## Why Use Collections

- Isolate ingest/search/rebuild by category.
- Avoid rebuilding the whole corpus for small targeted updates.
- Keep a single integration path while preserving logical boundaries.

## Core API

```dart
final business = MobileRag.instance.inCollection('business');
final travel = MobileRag.instance.inCollection('travel');
```

Each `CollectionRag` scope keeps operations within that collection:

- `addDocument(...)`
- `search(...)`
- `searchHybrid(...)`
- `searchHybridWithContext(...)`
- `listSources()`
- `removeSource(...)`
- `rebuildIndex(...)`
- `getStats()`

## Quick Example

```dart
final business = MobileRag.instance.inCollection('business');
final travel = MobileRag.instance.inCollection('travel');

await business.addDocument('Q1 roadmap and forecast...');
await travel.addDocument('Kyoto itinerary and hotel notes...');

if (!travel.isIndexReady) {
  await travel.warmupFuture;
}

final hits = await travel.searchHybrid('hotel near station', topK: 5);
print('travel hits: ${hits.length}');
```

## Collection Behavior

- Existing calls without `inCollection(...)` use the default collection: `__default__`.
- Collection IDs are normalized (`trim`), and empty IDs resolve to `__default__`.
- Source IDs are collection-scoped in practice: use `listSources()` from the same collection scope before applying `sourceIds` filters.

## Operational Notes

- Index warmup/readiness is available per collection via `isIndexReady` and `warmupFuture`.
- Rebuilds can be forced per collection (`collection.rebuildIndex()`), but routine flows usually rely on normal auto-index lifecycle.

/// Internal defaults for configuration and search behavior.
library;

const int kDefaultMaxChunkChars = 500;
const int kDefaultOverlapChars = 30;
const int kMinChunkChars = 100;

const double kDefaultVectorWeight = 0.2;
const double kDefaultBm25Weight = 0.8;

/// Micro-batch ingestion size for memory-safe document processing.
/// Controls how many chunks are embedded and saved to DB per batch.
const int kIngestionBatchSize = 32;

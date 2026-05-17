use flutter_rust_bridge::frb;
use thiserror::Error;

/// Structured error type passed to Dart via FFI.
#[frb(dart_metadata=("freezed"))] // Generated as a sealed class in Dart.
#[derive(Error, Debug)]
pub enum RagError {
    /// Database related error (potential for retry).
    #[error("Database error: {0}")]
    DatabaseError(String),

    /// I/O error (file missing, permission issues, etc.).
    #[error("IO error: {0}")]
    IoError(String),

    /// Failed to load embedding model.
    #[error("Failed to load model: {0}")]
    ModelLoadError(String),

    /// User input error (invalid query, etc.).
    #[error("Invalid input: {0}")]
    InvalidInput(String),

    /// Search handle became stale because collection data changed.
    #[error("Stale search handle: {0}")]
    StaleSearchHandle(String),

    /// Search metadata creation raced with a concurrent collection mutation.
    #[error("Concurrent mutation: {0}")]
    ConcurrentMutation(String),

    /// Internal system error (HNSW, Logic, etc.).
    #[error("Internal error: {0}")]
    InternalError(String),

    /// A persisted `migration_meta` axis is newer than this build can read.
    /// Field order: (axis_key, stored_version, supported_version).
    /// Downgrade is unsupported; the user must upgrade the engine binary.
    #[error("Unsupported migration axis '{0}': stored version {1} is newer than build's supported version {2}. Downgrade is not supported.")]
    UnsupportedMigrationVersion(String, i64, i64),

    /// The currently loaded embedding model produced a fingerprint that does
    /// not match the one persisted on disk. Search and ingest must remain
    /// locked until the host app explicitly drives either reembed-all or
    /// clear-and-restart. Field order: (stored, current, remaining_chunks).
    #[error("Embedding fingerprint mismatch: stored='{0}', current='{1}', remaining_chunks={2}. Call reembedAll() to reuse stored documents or clearAndRestart() to discard them.")]
    EmbeddingFingerprintMismatch(String, String, i64),

    /// Unknown error.
    #[error("Unknown error: {0}")]
    Unknown(String),
}

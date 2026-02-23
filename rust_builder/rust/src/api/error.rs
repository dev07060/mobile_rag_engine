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

    /// Internal system error (HNSW, Logic, etc.).
    #[error("Internal error: {0}")]
    InternalError(String),

    /// Unknown error.
    #[error("Unknown error: {0}")]
    Unknown(String),
}

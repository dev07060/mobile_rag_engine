// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Stateful ingestion session that keeps chunk content resident in Rust
// between chunking and DB commit, so the chunk body never round-trips
// across the Dart↔Rust FFI boundary as a String. Only embedding_text
// (Rust→Dart) and embedding vectors (Dart→Rust) traverse FFI per chunk.

use crate::api::error::RagError;
use crate::api::ingest_metrics::{
    LegacyCountingGuard, SESSION_COMMIT_EMBEDDINGS_IN, SESSION_EMBEDDING_TEXT_OUT,
    SESSION_PREPARE_CONTENT_IN,
};
use crate::api::semantic_chunker::{markdown_chunk, semantic_chunk_with_overlap};
use crate::api::source_rag::{
    add_chunks, add_source_in_collection, claim_source_for_ingestion, clear_source_chunks,
    get_source_chunk_count, get_source_status, update_source_status, ChunkData,
};
use crate::frb_generated::RustAutoOpaqueMoi as RustAutoOpaque;
use flutter_rust_bridge::frb;
use log::{debug, info};
use std::collections::{HashMap, VecDeque};

/// Chunking strategy selector for `prepare_source_ingestion`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IngestStrategy {
    Recursive,
    Markdown,
}

/// Outcome of the source-row stage inside `prepare_source_ingestion`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreparedSourceState {
    /// New source row created and claimed; chunks staged, ready to drain.
    CreatedReady,
    /// Existing failed/empty-completed source: stale chunks cleared, re-claimed, restaged.
    ResumeReady,
    /// Existing completed source with chunks already on disk; nothing to do.
    DuplicateSkip,
    /// Existing source in `pending` or `processing` — owned by another worker.
    DuplicateInProgress,
}

/// Returned per-chunk by `IngestSession::take_embedding_batch`.
#[derive(Debug, Clone)]
pub struct EmbeddingRequest {
    pub chunk_index: i32,
    pub embedding_text: String,
}

/// Returned per-chunk by Dart and consumed by `IngestSession::commit_embeddings`.
#[derive(Debug, Clone)]
pub struct ChunkEmbedding {
    pub chunk_index: i32,
    pub embedding: Vec<f32>,
}

/// Result of `prepare_source_ingestion`.
///
/// `session` is `Some` exactly when `state` is `CreatedReady` or `ResumeReady`,
/// signalling Dart to drain embeddings and call `finalize` / `abort` on it.
pub struct PreparedIngestion {
    pub source_id: i64,
    pub state: PreparedSourceState,
    pub total_chunks: i32,
    /// UTF-8 byte length of the decoded text body after parsing / decoding.
    ///
    /// For `from_file`, this may be non-zero even though
    /// `SESSION_PREPARE_CONTENT_IN` remains zero: the former describes the
    /// extracted text body, while the latter counts text bytes that crossed FFI.
    pub body_byte_length: i32,
    /// Text length using Dart `String.length` semantics (UTF-16 code units).
    pub body_char_length: i32,
    pub message: String,
    pub session: Option<RustAutoOpaque<IngestSession>>,
}

#[derive(Debug)]
struct StagedChunk {
    chunk_index: i32,
    content: String,
    chunk_type: String,
    start_pos: i32,
    end_pos: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SessionState {
    Draining,
    Completed,
    Aborted,
}

/// In-Rust ingestion handle. Chunk content lives here until `commit_embeddings`
/// hands it directly to `add_chunks` — never crossing the FFI boundary.
#[frb(opaque)]
#[derive(Debug)]
pub struct IngestSession {
    source_id: i64,
    total: i32,
    committed_count: i32,
    pending: VecDeque<StagedChunk>,
    in_flight: Vec<StagedChunk>,
    state: SessionState,
}

impl IngestSession {
    fn ensure_active(&self) -> Result<(), RagError> {
        match self.state {
            SessionState::Draining => Ok(()),
            SessionState::Completed => Err(RagError::InvalidInput(
                "ingest session already finalized".to_string(),
            )),
            SessionState::Aborted => Err(RagError::InvalidInput(
                "ingest session was aborted".to_string(),
            )),
        }
    }
}

#[frb]
impl IngestSession {
    pub fn source_id(&self) -> i64 {
        self.source_id
    }

    pub fn total(&self) -> i32 {
        self.total
    }

    pub fn committed_count(&self) -> i32 {
        self.committed_count
    }

    pub fn pending_dispatch_count(&self) -> i32 {
        self.pending.len() as i32
    }

    pub fn in_flight_count(&self) -> i32 {
        self.in_flight.len() as i32
    }

    /// Drain up to `batch_size` chunks from the pending queue. Each chunk's
    /// `embedding_text` is computed from its stored content+chunk_type and
    /// shipped to Dart for ONNX embedding. The corresponding `StagedChunk`
    /// moves to the in-flight slot, awaiting a matching `commit_embeddings`.
    ///
    /// Errors if a previous batch is still in flight (single-batch discipline).
    pub fn take_embedding_batch(
        &mut self,
        batch_size: i32,
    ) -> Result<Vec<EmbeddingRequest>, RagError> {
        self.ensure_active()?;
        if !self.in_flight.is_empty() {
            return Err(RagError::InvalidInput(
                "previous embedding batch must be committed before requesting a new one"
                    .to_string(),
            ));
        }

        let take = batch_size.max(0) as usize;
        if take == 0 || self.pending.is_empty() {
            return Ok(Vec::new());
        }

        let to_dispatch = take.min(self.pending.len());
        let mut out = Vec::with_capacity(to_dispatch);
        let mut outbound_bytes: u64 = 0;
        for _ in 0..to_dispatch {
            let staged = self
                .pending
                .pop_front()
                .expect("pending must have items at this point");
            let embedding_text = render_context_text(&staged.content, &staged.chunk_type);
            outbound_bytes += embedding_text.len() as u64;
            out.push(EmbeddingRequest {
                chunk_index: staged.chunk_index,
                embedding_text,
            });
            self.in_flight.push(staged);
        }
        if outbound_bytes > 0 {
            SESSION_EMBEDDING_TEXT_OUT.record(outbound_bytes);
        }

        debug!(
            "[IngestSession] dispatched {} embedding requests (source {})",
            out.len(),
            self.source_id
        );
        Ok(out)
    }

    /// Flush the current in-flight batch to the chunks table using the
    /// provided embeddings. Returns the number of chunks written.
    ///
    /// Validation is performed *before* draining in_flight so a malformed
    /// embedding payload does not lose chunk content.
    pub fn commit_embeddings(&mut self, embeddings: Vec<ChunkEmbedding>) -> Result<i32, RagError> {
        self.ensure_active()?;
        // 4 bytes per f32 dim; gives the embedding vector traffic for the
        // Dart→Rust direction (separate from the text-body counters).
        let vector_bytes: u64 = embeddings
            .iter()
            .map(|e| (e.embedding.len() as u64) * 4)
            .sum();
        if vector_bytes > 0 {
            SESSION_COMMIT_EMBEDDINGS_IN.record(vector_bytes);
        }
        if self.in_flight.is_empty() {
            return Err(RagError::InvalidInput(
                "no in-flight batch to commit; call take_embedding_batch first".to_string(),
            ));
        }
        if embeddings.len() != self.in_flight.len() {
            return Err(RagError::InvalidInput(format!(
                "embedding count mismatch: expected {}, got {}",
                self.in_flight.len(),
                embeddings.len()
            )));
        }

        let mut by_index: HashMap<i32, Vec<f32>> = HashMap::with_capacity(embeddings.len());
        for ChunkEmbedding {
            chunk_index,
            embedding,
        } in embeddings
        {
            if by_index.insert(chunk_index, embedding).is_some() {
                return Err(RagError::InvalidInput(format!(
                    "duplicate embedding for chunk_index {}",
                    chunk_index
                )));
            }
        }

        for staged in &self.in_flight {
            if !by_index.contains_key(&staged.chunk_index) {
                return Err(RagError::InvalidInput(format!(
                    "missing embedding for chunk_index {}",
                    staged.chunk_index
                )));
            }
        }

        // Validation done: safe to drain.
        let mut to_commit = Vec::with_capacity(self.in_flight.len());
        for staged in self.in_flight.drain(..) {
            let embedding = by_index
                .remove(&staged.chunk_index)
                .expect("presence checked above");
            to_commit.push(ChunkData {
                chunk_index: staged.chunk_index,
                content: staged.content,
                start_pos: staged.start_pos,
                end_pos: staged.end_pos,
                chunk_type: staged.chunk_type,
                embedding,
            });
        }

        // Suppress legacy counters for the internal add_chunks delegation.
        let _legacy_guard = LegacyCountingGuard::enter();
        let saved = add_chunks(self.source_id, to_commit)?;
        drop(_legacy_guard);
        self.committed_count += saved;
        debug!(
            "[IngestSession] committed batch of {} (total committed {} / {})",
            saved, self.committed_count, self.total
        );
        Ok(saved)
    }

    /// Mark the source `completed`. Errors if any chunks are still pending or in flight.
    pub fn finalize(&mut self) -> Result<(), RagError> {
        self.ensure_active()?;
        if !self.in_flight.is_empty() {
            return Err(RagError::InvalidInput(format!(
                "cannot finalize: {} chunks still in flight",
                self.in_flight.len()
            )));
        }
        if !self.pending.is_empty() {
            return Err(RagError::InvalidInput(format!(
                "cannot finalize: {} chunks still pending dispatch",
                self.pending.len()
            )));
        }
        update_source_status(self.source_id, "completed".to_string())?;
        self.state = SessionState::Completed;
        info!(
            "[IngestSession] finalized source {} with {} chunks",
            self.source_id, self.committed_count
        );
        Ok(())
    }

    /// Roll back: clear any DB chunks that were already committed, mark the
    /// source `failed`, and drop staged content. Idempotent after the first
    /// call; no-op once the session is finalized.
    pub fn abort(&mut self) -> Result<(), RagError> {
        if !matches!(self.state, SessionState::Draining) {
            return Ok(());
        }
        // Best-effort cleanup; even if clear_source_chunks fails we still try
        // to mark the row failed.
        let cleared = clear_source_chunks(self.source_id);
        let status_update = update_source_status(self.source_id, "failed".to_string());
        self.pending.clear();
        self.in_flight.clear();
        self.state = SessionState::Aborted;
        info!(
            "[IngestSession] aborted source {} (cleared_chunks={:?}, status_update={:?})",
            self.source_id,
            cleared.as_ref().ok(),
            status_update.as_ref().ok(),
        );
        cleared?;
        status_update?;
        Ok(())
    }

    /// Explicit drop to release the Rust handle from Dart.
    pub fn dispose(self) {}
}

/// Combined entrypoint: insert/find source row, claim it, run the chunker, and
/// return an `IngestSession` carrying the chunked content. Dart drives the
/// per-batch embedding loop on the returned session.
pub fn prepare_source_ingestion(
    collection_id: String,
    content: String,
    metadata: Option<String>,
    name: Option<String>,
    strategy: IngestStrategy,
    max_chars: i32,
    overlap_chars: i32,
) -> Result<PreparedIngestion, RagError> {
    // Record the FFI byte traffic from Dart→Rust before delegating to the inner
    // helper. `content.len()` matches the encoded UTF-8 byte length for ASCII
    // and ≤ the actual Dart String memory cost for any input.
    SESSION_PREPARE_CONTENT_IN.record(content.len() as u64);
    prepare_source_ingestion_inner(
        collection_id,
        content,
        metadata,
        name,
        strategy,
        max_chars,
        overlap_chars,
    )
}

/// UTF-8 bytes variant: skips the Dart `String` materialization step. The
/// caller hands raw bytes (typically a `Uint8List` from a file/network read);
/// the Rust side performs UTF-8 decoding once. Identical staging behavior to
/// `prepare_source_ingestion` once the bytes are decoded.
pub fn prepare_source_ingestion_from_utf8(
    collection_id: String,
    content_bytes: Vec<u8>,
    metadata: Option<String>,
    name: Option<String>,
    strategy: IngestStrategy,
    max_chars: i32,
    overlap_chars: i32,
) -> Result<PreparedIngestion, RagError> {
    // `content_bytes.len()` equals the actual Dart→Rust FFI byte traffic on
    // this entrypoint — bytes flow straight into Rust without intermediate
    // String creation in Dart.
    SESSION_PREPARE_CONTENT_IN.record(content_bytes.len() as u64);
    let content = String::from_utf8(content_bytes)
        .map_err(|e| RagError::InvalidInput(format!("UTF-8 decode failed: {}", e)))?;
    prepare_source_ingestion_inner(
        collection_id,
        content,
        metadata,
        name,
        strategy,
        max_chars,
        overlap_chars,
    )
}

/// File-path variant: Rust reads the file and never round-trips its body
/// through Dart. Only the path string crosses FFI (Dart→Rust). When
/// `strategy_hint` is `None`, the chunking strategy is inferred from the
/// extension (`.md` / `.markdown` → Markdown, otherwise Recursive). Text-like
/// extensions (`.txt`, `.md`, `.markdown`) are decoded as UTF-8; everything
/// else falls through to `document_parser::extract_text_from_document` (PDF /
/// DOCX magic-byte routing).
pub fn prepare_source_ingestion_from_file(
    collection_id: String,
    file_path: String,
    metadata: Option<String>,
    name: Option<String>,
    strategy_hint: Option<IngestStrategy>,
    max_chars: i32,
    overlap_chars: i32,
) -> Result<PreparedIngestion, RagError> {
    let bytes = std::fs::read(&file_path)
        .map_err(|e| RagError::IoError(format!("Failed to read file '{}': {}", file_path, e)))?;

    let extension = std::path::Path::new(&file_path)
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.to_ascii_lowercase());
    let is_text_like = matches!(extension.as_deref(), Some("txt" | "md" | "markdown"));

    let content = if is_text_like {
        String::from_utf8(bytes).map_err(|e| {
            RagError::InvalidInput(format!("UTF-8 decode failed for '{}': {}", file_path, e))
        })?
    } else {
        crate::api::document_parser::extract_text_from_document(bytes).map_err(|e| {
            RagError::InvalidInput(format!(
                "Document extraction failed for '{}': {}",
                file_path, e
            ))
        })?
    };

    let strategy = strategy_hint.unwrap_or_else(|| {
        if matches!(extension.as_deref(), Some("md" | "markdown")) {
            IngestStrategy::Markdown
        } else {
            IngestStrategy::Recursive
        }
    });

    // Body bytes did NOT cross FFI on this path — only the path string did.
    // Honest counter reflects "Dart→Rust body bytes" rather than internal
    // Rust I/O, so SESSION_PREPARE_CONTENT_IN stays unrecorded here.
    prepare_source_ingestion_inner(
        collection_id,
        content,
        metadata,
        name,
        strategy,
        max_chars,
        overlap_chars,
    )
}

/// Shared body for all three `prepare_source_ingestion*` entrypoints.
/// Wrappers above are responsible for counter recording and decoding inputs
/// down to a `String` body; this function owns the source-row + claim +
/// chunker + staging pipeline.
fn prepare_source_ingestion_inner(
    collection_id: String,
    content: String,
    metadata: Option<String>,
    name: Option<String>,
    strategy: IngestStrategy,
    max_chars: i32,
    overlap_chars: i32,
) -> Result<PreparedIngestion, RagError> {
    let body_byte_length = saturating_i32(content.len());
    // Dart's String.length reports UTF-16 code units. Mirror that so callers
    // can preserve existing "extracted text length" UI without materializing
    // the body in Dart on file-path ingest.
    let body_char_length = saturating_i32(content.encode_utf16().count());

    // The guard suppresses legacy counter increments for the nested calls
    // (add_source_in_collection, semantic_chunk_with_overlap, markdown_chunk)
    // so a session-path run does not double-charge legacy counters.
    let _legacy_guard = LegacyCountingGuard::enter();

    let add_result = add_source_in_collection(collection_id, content.clone(), metadata, name)?;
    let source_id = add_result.source_id;

    // Mirror source_rag_service.dart::addSourceWithChunking exact order:
    // try to claim first, fall back to status-based duplicate decision only
    // when the row is not claimable (i.e. status is 'completed' or 'processing').
    //
    // This preserves the pre-IngestSession behavior where a 'pending' duplicate
    // (left behind by a process that crashed between INSERT and CLAIM) auto-
    // resumes on the next attempt rather than being skipped as in-progress.
    let mut claimed = claim_source_for_ingestion(source_id)?;
    let mut resumed_via_reset = false;

    if !claimed {
        let status = get_source_status(source_id)?;
        let chunk_count = get_source_chunk_count(source_id)?;
        match decide_duplicate_decision(status.as_deref(), chunk_count) {
            DuplicateDecision::SkipCompleted => {
                update_source_status(source_id, "completed".to_string())?;
                return Ok(PreparedIngestion {
                    source_id,
                    state: PreparedSourceState::DuplicateSkip,
                    total_chunks: 0,
                    body_byte_length,
                    body_char_length,
                    message: add_result.message,
                    session: None,
                });
            }
            DuplicateDecision::AlreadyInProgress => {
                return Ok(PreparedIngestion {
                    source_id,
                    state: PreparedSourceState::DuplicateInProgress,
                    total_chunks: 0,
                    body_byte_length,
                    body_char_length,
                    message: "Source ingestion already in progress".to_string(),
                    session: None,
                });
            }
            DuplicateDecision::ResetAndResume => {
                clear_source_chunks(source_id)?;
                claimed = claim_source_for_ingestion(source_id)?;
                if !claimed {
                    return Ok(PreparedIngestion {
                        source_id,
                        state: PreparedSourceState::DuplicateInProgress,
                        total_chunks: 0,
                        body_byte_length,
                        body_char_length,
                        message: "Source ingestion already in progress".to_string(),
                        session: None,
                    });
                }
                resumed_via_reset = true;
            }
        }
    }

    // Defensive clear: when a duplicate row's claim succeeded on first try
    // (status was 'pending' or 'failed'), the previous incarnation may have
    // left partial chunks on disk before strict rollback existed.
    let is_resume = add_result.is_duplicate;
    if is_resume && !resumed_via_reset {
        let stale_count = get_source_chunk_count(source_id)?;
        if stale_count > 0 {
            clear_source_chunks(source_id)?;
        }
    }

    debug_assert!(claimed, "source must be claimed before staging chunks");

    let staged: Vec<StagedChunk> = match strategy {
        IngestStrategy::Recursive => semantic_chunk_with_overlap(content, max_chars, overlap_chars)
            .into_iter()
            .map(|c| StagedChunk {
                chunk_index: c.index,
                content: c.content,
                chunk_type: c.chunk_type,
                start_pos: c.start_pos,
                end_pos: c.end_pos,
            })
            .collect(),
        IngestStrategy::Markdown => markdown_chunk(content, max_chars)
            .into_iter()
            .map(|c| StagedChunk {
                chunk_index: c.index,
                chunk_type: encode_structured_chunk_type(&c.chunk_type, &c.header_path),
                content: c.content,
                start_pos: c.start_pos,
                end_pos: c.end_pos,
            })
            .collect(),
    };

    let total = staged.len() as i32;
    let pending: VecDeque<StagedChunk> = staged.into();
    let state = if is_resume {
        PreparedSourceState::ResumeReady
    } else {
        PreparedSourceState::CreatedReady
    };

    info!(
        "[prepare_source_ingestion] source={} state={:?} total_chunks={}",
        source_id, state, total
    );

    Ok(PreparedIngestion {
        source_id,
        state,
        total_chunks: total,
        body_byte_length,
        body_char_length,
        message: add_result.message,
        session: Some(RustAutoOpaque::new(IngestSession {
            source_id,
            total,
            committed_count: 0,
            pending,
            in_flight: Vec::new(),
            state: SessionState::Draining,
        })),
    })
}

fn saturating_i32(value: usize) -> i32 {
    i32::try_from(value).unwrap_or(i32::MAX)
}

// ---------------------------------------------------------------------------
// Local mirrors of private helpers in source_rag.rs.
//
// `render_context_text` and `decode_structured_chunk_type` are private in
// source_rag.rs. We replicate them here so this module can be added without
// touching source_rag.rs (which is gated by the contributor guideline).
//
// Keep BYTE-FOR-BYTE IN SYNC with:
//   - source_rag::render_context_text
//   - source_rag::decode_structured_chunk_type
//   - source_rag_service.dart::_encodeStructuredChunkType
// ---------------------------------------------------------------------------

fn decode_structured_chunk_type(chunk_type: &str) -> (&str, Option<&str>) {
    let Some(separator) = chunk_type.find('|') else {
        return (chunk_type, None);
    };
    let raw_type = &chunk_type[..separator];
    let header_path = chunk_type[separator + 1..].trim();
    (
        raw_type,
        if header_path.is_empty() {
            None
        } else {
            Some(header_path)
        },
    )
}

fn render_context_text(content: &str, chunk_type: &str) -> String {
    let (_, header_path) = decode_structured_chunk_type(chunk_type);
    match header_path {
        Some(path) => format!("Header Path: {path}\n{content}"),
        None => content.to_string(),
    }
}

fn encode_structured_chunk_type(chunk_type: &str, header_path: &str) -> String {
    let trimmed = header_path.trim();
    if trimmed.is_empty() {
        chunk_type.to_string()
    } else {
        format!("{}|{}", chunk_type, trimmed)
    }
}

enum DuplicateDecision {
    SkipCompleted,
    AlreadyInProgress,
    ResetAndResume,
}

// Mirrors source_rag_service.dart::decideDuplicateSourceIngestion so behavior
// matches the existing pipeline exactly.
fn decide_duplicate_decision(status: Option<&str>, chunk_count: i32) -> DuplicateDecision {
    let normalized = status.unwrap_or("completed");
    match normalized {
        "completed" => {
            if chunk_count > 0 {
                DuplicateDecision::SkipCompleted
            } else {
                DuplicateDecision::ResetAndResume
            }
        }
        "pending" | "processing" => DuplicateDecision::AlreadyInProgress,
        "failed" => DuplicateDecision::ResetAndResume,
        _ => {
            if chunk_count > 0 {
                DuplicateDecision::SkipCompleted
            } else {
                DuplicateDecision::ResetAndResume
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::bm25_search::bm25_clear_index;
    use crate::api::db_pool::{close_db_pool, init_db_pool};
    use crate::api::hnsw_index::clear_hnsw_index;
    use crate::api::source_rag::init_source_db;
    use std::path::PathBuf;
    use std::sync::{Mutex, OnceLock};

    fn test_guard() -> std::sync::MutexGuard<'static, ()> {
        static TEST_MUTEX: OnceLock<Mutex<()>> = OnceLock::new();
        TEST_MUTEX
            .get_or_init(|| Mutex::new(()))
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn setup_test_db(name: &str) -> PathBuf {
        let db_path = std::env::temp_dir().join(name);
        let _ = std::fs::remove_file(&db_path);
        init_db_pool(db_path.to_str().unwrap().to_string(), 4).unwrap();
        init_source_db().unwrap();
        clear_hnsw_index();
        bm25_clear_index();
        db_path
    }

    fn teardown_test_db(db_path: PathBuf) {
        clear_hnsw_index();
        bm25_clear_index();
        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    fn fake_embedding(dim: usize, seed: f32) -> Vec<f32> {
        (0..dim).map(|i| seed + i as f32 * 0.001).collect()
    }

    fn drain_session_with_fake_embeddings(session: &mut IngestSession) -> i32 {
        let mut saved = 0;
        loop {
            let batch = session.take_embedding_batch(4).unwrap();
            if batch.is_empty() {
                break;
            }
            let embeddings: Vec<ChunkEmbedding> = batch
                .into_iter()
                .map(|req| ChunkEmbedding {
                    chunk_index: req.chunk_index,
                    embedding: fake_embedding(4, req.chunk_index as f32),
                })
                .collect();
            saved += session.commit_embeddings(embeddings).unwrap();
        }
        saved
    }

    #[test]
    fn test_saturating_i32_caps_overflow() {
        assert_eq!(saturating_i32(i32::MAX as usize), i32::MAX);
        assert_eq!(saturating_i32(i32::MAX as usize + 1), i32::MAX);
        assert_eq!(saturating_i32(usize::MAX), i32::MAX);
    }

    #[test]
    fn test_prepare_new_source_creates_ready_session() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_prepare_new.db");

        let content = "Paragraph one.\n\nParagraph two.\n\nParagraph three.".to_string();
        let prepared = prepare_source_ingestion(
            "__default__".to_string(),
            content,
            None,
            Some("doc.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();

        assert_eq!(prepared.state, PreparedSourceState::CreatedReady);
        assert!(prepared.total_chunks >= 1);
        assert!(prepared.session.is_some());

        let session_opaque = prepared.session.unwrap();
        let mut session = session_opaque.blocking_write();
        assert_eq!(session.total(), prepared.total_chunks);
        let saved = drain_session_with_fake_embeddings(&mut session);
        assert_eq!(saved, prepared.total_chunks);
        session.finalize().unwrap();
        assert_eq!(
            get_source_status(prepared.source_id).unwrap(),
            Some("completed".to_string())
        );
        assert_eq!(
            get_source_chunk_count(prepared.source_id).unwrap(),
            prepared.total_chunks
        );

        teardown_test_db(db_path);
    }

    #[test]
    fn test_prepare_duplicate_completed_returns_skip() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_prepare_dup_completed.db");

        let content = "Reusable document body.".to_string();
        let expected_body_byte_length = content.len() as i32;
        let expected_body_char_length = content.encode_utf16().count() as i32;
        // First ingest, finalize completed.
        let first = prepare_source_ingestion(
            "__default__".to_string(),
            content.clone(),
            None,
            Some("dup.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();
        let session_opaque = first.session.unwrap();
        {
            let mut session = session_opaque.blocking_write();
            drain_session_with_fake_embeddings(&mut session);
            session.finalize().unwrap();
        }

        // Second prepare for same content → DuplicateSkip.
        let second = prepare_source_ingestion(
            "__default__".to_string(),
            content,
            None,
            Some("dup.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();
        assert_eq!(second.state, PreparedSourceState::DuplicateSkip);
        assert!(second.session.is_none());
        assert_eq!(second.source_id, first.source_id);
        assert_eq!(second.body_byte_length, expected_body_byte_length);
        assert_eq!(second.body_char_length, expected_body_char_length);

        teardown_test_db(db_path);
    }

    #[test]
    fn test_abort_clears_partial_chunks_and_marks_failed() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_abort.db");

        // Build a multi-paragraph body that the chunker (min chunk floor of 100
        // chars) will split into >= 2 chunks at max_chars=120.
        let paragraph = "alpha bravo charlie delta echo foxtrot golf hotel india juliet";
        let content = (0..6)
            .map(|i| format!("Paragraph {i}: {paragraph}."))
            .collect::<Vec<_>>()
            .join("\n\n");
        let prepared = prepare_source_ingestion(
            "__default__".to_string(),
            content,
            None,
            Some("abort.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();
        assert_eq!(prepared.state, PreparedSourceState::CreatedReady);
        assert!(
            prepared.total_chunks >= 2,
            "expected >= 2 chunks, got {}",
            prepared.total_chunks
        );

        let session_opaque = prepared.session.unwrap();
        {
            let mut session = session_opaque.blocking_write();
            // Commit only the first batch, then abort.
            let batch = session.take_embedding_batch(1).unwrap();
            assert_eq!(batch.len(), 1);
            let embeddings: Vec<ChunkEmbedding> = batch
                .into_iter()
                .map(|req| ChunkEmbedding {
                    chunk_index: req.chunk_index,
                    embedding: fake_embedding(4, req.chunk_index as f32),
                })
                .collect();
            session.commit_embeddings(embeddings).unwrap();
            assert_eq!(session.committed_count(), 1);

            session.abort().unwrap();
        }

        assert_eq!(
            get_source_status(prepared.source_id).unwrap(),
            Some("failed".to_string())
        );
        assert_eq!(get_source_chunk_count(prepared.source_id).unwrap(), 0);

        teardown_test_db(db_path);
    }

    #[test]
    fn test_prepare_pending_duplicate_resumes() {
        // Regression: a source row left in `pending` status by a process that
        // crashed between INSERT and CLAIM must auto-resume on the next
        // attempt — not be reported as DuplicateInProgress. This matches the
        // pre-IngestSession behavior in source_rag_service.dart where claim
        // was attempted before consulting decideDuplicateSourceIngestion.
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_pending_dup_resume.db");

        let content = "Pending-duplicate body alpha bravo charlie delta echo.".to_string();
        let first = prepare_source_ingestion(
            "__default__".to_string(),
            content.clone(),
            None,
            Some("pending-dup.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();
        assert_eq!(first.state, PreparedSourceState::CreatedReady);
        let source_id = first.source_id;
        // Drop the session without finalize/abort to simulate a crash before
        // any chunks were written, then rewind status to `pending` so the next
        // prepare sees the duplicate-pending edge case.
        drop(first.session);
        update_source_status(source_id, "pending".to_string()).unwrap();

        let second = prepare_source_ingestion(
            "__default__".to_string(),
            content,
            None,
            Some("pending-dup.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();
        assert_eq!(
            second.state,
            PreparedSourceState::ResumeReady,
            "pending duplicate must auto-resume, not stick as DuplicateInProgress",
        );
        assert!(second.session.is_some());
        assert_eq!(second.source_id, source_id);
        // After resume, source status should now be `processing`.
        assert_eq!(
            get_source_status(source_id).unwrap(),
            Some("processing".to_string())
        );

        teardown_test_db(db_path);
    }

    #[test]
    fn test_failed_source_resumes_after_abort() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_resume_after_abort.db");

        let content = "Resume me. After failure.".to_string();
        // First attempt: prepare then abort.
        let first = prepare_source_ingestion(
            "__default__".to_string(),
            content.clone(),
            None,
            Some("resume.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();
        let session_opaque = first.session.unwrap();
        {
            let mut session = session_opaque.blocking_write();
            session.abort().unwrap();
        }
        assert_eq!(
            get_source_status(first.source_id).unwrap(),
            Some("failed".to_string())
        );

        // Second prepare: duplicate row found with status=failed → ResumeReady.
        let second = prepare_source_ingestion(
            "__default__".to_string(),
            content,
            None,
            Some("resume.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();
        assert_eq!(second.state, PreparedSourceState::ResumeReady);
        assert!(second.session.is_some());
        assert_eq!(second.source_id, first.source_id);

        let session_opaque = second.session.unwrap();
        {
            let mut session = session_opaque.blocking_write();
            drain_session_with_fake_embeddings(&mut session);
            session.finalize().unwrap();
        }
        assert_eq!(
            get_source_status(second.source_id).unwrap(),
            Some("completed".to_string())
        );

        teardown_test_db(db_path);
    }

    #[test]
    fn test_commit_rejects_mismatched_count() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_commit_mismatch.db");

        let content = "Sentence one. Sentence two.".to_string();
        let prepared = prepare_source_ingestion(
            "__default__".to_string(),
            content,
            None,
            None,
            IngestStrategy::Recursive,
            20,
            0,
        )
        .unwrap();
        let session_opaque = prepared.session.unwrap();
        let mut session = session_opaque.blocking_write();

        let batch = session.take_embedding_batch(2).unwrap();
        let mut embeddings: Vec<ChunkEmbedding> = batch
            .into_iter()
            .map(|req| ChunkEmbedding {
                chunk_index: req.chunk_index,
                embedding: fake_embedding(4, req.chunk_index as f32),
            })
            .collect();
        // Drop the last embedding → count mismatch.
        embeddings.pop();
        let err = session.commit_embeddings(embeddings).unwrap_err();
        match err {
            RagError::InvalidInput(msg) => assert!(msg.contains("count mismatch"), "msg={}", msg),
            other => panic!("expected InvalidInput, got {:?}", other),
        }
        // No chunks should have been written.
        assert_eq!(get_source_chunk_count(prepared.source_id).unwrap(), 0);

        drop(session);
        teardown_test_db(db_path);
    }

    #[test]
    fn test_take_rejects_back_to_back_without_commit() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_take_twice.db");

        let content = "Sentence one. Sentence two. Sentence three.".to_string();
        let prepared = prepare_source_ingestion(
            "__default__".to_string(),
            content,
            None,
            None,
            IngestStrategy::Recursive,
            20,
            0,
        )
        .unwrap();
        let session_opaque = prepared.session.unwrap();
        let mut session = session_opaque.blocking_write();

        let first_batch = session.take_embedding_batch(1).unwrap();
        assert_eq!(first_batch.len(), 1);
        let err = session.take_embedding_batch(1).unwrap_err();
        match err {
            RagError::InvalidInput(msg) => {
                assert!(msg.contains("previous embedding batch"), "msg={}", msg)
            }
            other => panic!("expected InvalidInput, got {:?}", other),
        }

        drop(session);
        teardown_test_db(db_path);
    }

    #[test]
    fn test_finalize_requires_full_commit() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_finalize_guard.db");

        let content = "Sentence one. Sentence two.".to_string();
        let prepared = prepare_source_ingestion(
            "__default__".to_string(),
            content,
            None,
            None,
            IngestStrategy::Recursive,
            20,
            0,
        )
        .unwrap();
        let session_opaque = prepared.session.unwrap();
        let mut session = session_opaque.blocking_write();

        let err = session.finalize().unwrap_err();
        match err {
            RagError::InvalidInput(msg) => assert!(msg.contains("pending"), "msg={}", msg),
            other => panic!("expected InvalidInput, got {:?}", other),
        }

        drop(session);
        teardown_test_db(db_path);
    }

    #[test]
    fn test_markdown_strategy_encodes_header_path() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_markdown_headers.db");

        let content = "# Top\n\nIntro paragraph.\n\n## Sub\n\nDetail paragraph.\n".to_string();
        let prepared = prepare_source_ingestion(
            "__default__".to_string(),
            content,
            None,
            Some("doc.md".to_string()),
            IngestStrategy::Markdown,
            200,
            0,
        )
        .unwrap();
        assert_eq!(prepared.state, PreparedSourceState::CreatedReady);

        let session_opaque = prepared.session.unwrap();
        let mut session = session_opaque.blocking_write();
        // Pull one batch and confirm embedding_text inherits "Header Path: ..." prefix.
        let batch = session.take_embedding_batch(prepared.total_chunks).unwrap();
        let has_header_path = batch
            .iter()
            .any(|req| req.embedding_text.starts_with("Header Path: "));
        assert!(
            has_header_path,
            "expected at least one chunk's embedding_text to carry a Header Path prefix"
        );

        // Commit and finalize so teardown leaves a clean state.
        let embeddings: Vec<ChunkEmbedding> = batch
            .into_iter()
            .map(|req| ChunkEmbedding {
                chunk_index: req.chunk_index,
                embedding: fake_embedding(4, req.chunk_index as f32),
            })
            .collect();
        session.commit_embeddings(embeddings).unwrap();
        session.finalize().unwrap();

        drop(session);
        teardown_test_db(db_path);
    }

    #[test]
    fn test_prepare_from_utf8_matches_string_path() {
        // Validates that `prepare_source_ingestion_from_utf8` produces an
        // equivalent CreatedReady session for valid UTF-8 input.
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_prepare_from_utf8_ok.db");

        let content = "Bytes path body. 한글 포함.".to_string();
        let expected_body_byte_length = content.len() as i32;
        let expected_body_char_length = content.encode_utf16().count() as i32;
        let prepared = prepare_source_ingestion_from_utf8(
            "__default__".to_string(),
            content.into_bytes(),
            None,
            Some("utf8.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();

        assert_eq!(prepared.state, PreparedSourceState::CreatedReady);
        assert!(prepared.total_chunks >= 1);
        assert_eq!(prepared.body_byte_length, expected_body_byte_length);
        assert_eq!(prepared.body_char_length, expected_body_char_length);
        let session_opaque = prepared.session.unwrap();
        let mut session = session_opaque.blocking_write();
        let saved = drain_session_with_fake_embeddings(&mut session);
        assert_eq!(saved, prepared.total_chunks);
        session.finalize().unwrap();

        drop(session);
        teardown_test_db(db_path);
    }

    #[test]
    fn test_prepare_from_utf8_rejects_invalid_bytes() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_prepare_from_utf8_invalid.db");

        // 0xFF is not valid UTF-8 in any position.
        let invalid = vec![0x48, 0x65, 0x6C, 0xFF, 0x6F];
        let result = prepare_source_ingestion_from_utf8(
            "__default__".to_string(),
            invalid,
            None,
            Some("bad.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        );
        match result {
            Err(RagError::InvalidInput(msg)) => {
                assert!(msg.contains("UTF-8 decode failed"), "msg={}", msg)
            }
            Err(other) => panic!("expected InvalidInput, got {:?}", other),
            Ok(_) => panic!("expected error for invalid UTF-8 bytes"),
        }

        teardown_test_db(db_path);
    }

    #[test]
    fn test_prepare_from_utf8_empty_input_creates_zero_chunks() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_prepare_from_utf8_empty.db");

        let prepared = prepare_source_ingestion_from_utf8(
            "__default__".to_string(),
            Vec::new(),
            None,
            Some("empty.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();
        // Empty body: chunker yields nothing, finalize on a zero-chunk session
        // is allowed (matches semantic_chunk_with_overlap on empty input).
        assert!(matches!(
            prepared.state,
            PreparedSourceState::CreatedReady | PreparedSourceState::ResumeReady,
        ));
        assert_eq!(prepared.total_chunks, 0);
        assert_eq!(prepared.body_byte_length, 0);
        assert_eq!(prepared.body_char_length, 0);
        let session_opaque = prepared.session.unwrap();
        let mut session = session_opaque.blocking_write();
        session.finalize().unwrap();
        drop(session);

        teardown_test_db(db_path);
    }

    #[test]
    fn test_prepare_from_file_reads_txt_and_md_with_auto_strategy() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_prepare_from_file_textlike.db");

        let tmp = std::env::temp_dir();
        let txt_path = tmp.join("ingest_session_from_file_plain.txt");
        let md_path = tmp.join("ingest_session_from_file_doc.md");
        std::fs::write(&txt_path, "Plain text body for ingest from file test.").unwrap();
        std::fs::write(
            &md_path,
            "# Header One\n\nMarkdown intro paragraph.\n\n## Sub\n\nDetail body.\n",
        )
        .unwrap();

        // .txt → Recursive (no header_path encoding expected).
        let txt_prepared = prepare_source_ingestion_from_file(
            "__default__".to_string(),
            txt_path.to_string_lossy().into_owned(),
            None,
            Some("plain.txt".to_string()),
            None, // auto-detect
            200,
            0,
        )
        .unwrap();
        assert_eq!(txt_prepared.state, PreparedSourceState::CreatedReady);
        assert!(txt_prepared.total_chunks >= 1);
        let txt_session_opaque = txt_prepared.session.unwrap();
        {
            let mut session = txt_session_opaque.blocking_write();
            drain_session_with_fake_embeddings(&mut session);
            session.finalize().unwrap();
        }

        // .md → Markdown (at least one chunk should carry "Header Path: ").
        let md_prepared = prepare_source_ingestion_from_file(
            "__default__".to_string(),
            md_path.to_string_lossy().into_owned(),
            None,
            Some("doc.md".to_string()),
            None, // auto-detect → Markdown
            200,
            0,
        )
        .unwrap();
        assert_eq!(md_prepared.state, PreparedSourceState::CreatedReady);
        let md_session_opaque = md_prepared.session.unwrap();
        {
            let mut session = md_session_opaque.blocking_write();
            let batch = session
                .take_embedding_batch(md_prepared.total_chunks)
                .unwrap();
            let has_header_path = batch
                .iter()
                .any(|req| req.embedding_text.starts_with("Header Path: "));
            assert!(
                has_header_path,
                "markdown auto-strategy must propagate header path through embedding_text",
            );
            let embeddings: Vec<ChunkEmbedding> = batch
                .into_iter()
                .map(|req| ChunkEmbedding {
                    chunk_index: req.chunk_index,
                    embedding: fake_embedding(4, req.chunk_index as f32),
                })
                .collect();
            session.commit_embeddings(embeddings).unwrap();
            session.finalize().unwrap();
        }

        let _ = std::fs::remove_file(txt_path);
        let _ = std::fs::remove_file(md_path);
        teardown_test_db(db_path);
    }

    #[test]
    fn test_prepare_from_file_missing_path_returns_io_error() {
        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_prepare_from_file_missing.db");

        let missing = std::env::temp_dir()
            .join("definitely_does_not_exist_ingest_session.txt")
            .to_string_lossy()
            .into_owned();
        let result = prepare_source_ingestion_from_file(
            "__default__".to_string(),
            missing,
            None,
            None,
            None,
            120,
            0,
        );
        match result {
            Err(RagError::IoError(msg)) => {
                assert!(msg.contains("Failed to read file"), "msg={}", msg)
            }
            Err(other) => panic!("expected IoError, got {:?}", other),
            Ok(_) => panic!("expected error for missing file"),
        }

        teardown_test_db(db_path);
    }

    #[test]
    fn test_prepare_from_file_does_not_record_session_prepare_content() {
        // Regression guard: from_file must not record the body bytes into
        // SESSION_PREPARE_CONTENT_IN, because the body never crossed FFI.
        use crate::api::ingest_metrics::{ingest_traffic_stats, reset_ingest_traffic_stats};

        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_prepare_from_file_counter.db");

        let tmp = std::env::temp_dir();
        let txt_path = tmp.join("ingest_session_from_file_counter.txt");
        let body = "This is a sufficiently long body of text to cross a kilobyte ".repeat(64);
        std::fs::write(&txt_path, &body).unwrap();

        reset_ingest_traffic_stats();
        let prepared = prepare_source_ingestion_from_file(
            "__default__".to_string(),
            txt_path.to_string_lossy().into_owned(),
            None,
            Some("counter.txt".to_string()),
            None,
            500,
            0,
        )
        .unwrap();
        let stats = ingest_traffic_stats();
        assert_eq!(
            stats.session_prepare_content_in_bytes, 0,
            "from_file must not credit body bytes to SESSION_PREPARE_CONTENT_IN",
        );
        assert_eq!(stats.session_prepare_content_in_calls, 0);

        // Clean up the session so teardown is deterministic.
        if let Some(session_opaque) = prepared.session {
            let mut session = session_opaque.blocking_write();
            drain_session_with_fake_embeddings(&mut session);
            session.finalize().unwrap();
        }

        let _ = std::fs::remove_file(txt_path);
        teardown_test_db(db_path);
    }

    #[test]
    fn test_prepare_from_utf8_records_bytes_len_into_counter() {
        // Regression guard: from_utf8 must credit its byte payload to
        // SESSION_PREPARE_CONTENT_IN (and exactly once).
        use crate::api::ingest_metrics::{ingest_traffic_stats, reset_ingest_traffic_stats};

        let _guard = test_guard();
        let db_path = setup_test_db("test_ingest_prepare_from_utf8_counter.db");

        let body = "Counter check body.".to_string();
        let expected = body.len() as u64;

        reset_ingest_traffic_stats();
        let prepared = prepare_source_ingestion_from_utf8(
            "__default__".to_string(),
            body.into_bytes(),
            None,
            Some("counter-utf8.txt".to_string()),
            IngestStrategy::Recursive,
            120,
            0,
        )
        .unwrap();
        let stats = ingest_traffic_stats();
        assert_eq!(stats.session_prepare_content_in_bytes, expected);
        assert_eq!(stats.session_prepare_content_in_calls, 1);

        if let Some(session_opaque) = prepared.session {
            let mut session = session_opaque.blocking_write();
            drain_session_with_fake_embeddings(&mut session);
            session.finalize().unwrap();
        }

        teardown_test_db(db_path);
    }
}

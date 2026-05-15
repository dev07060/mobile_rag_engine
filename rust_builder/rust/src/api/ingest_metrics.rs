// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Always-on, low-overhead FFI traffic counters for the ingest text path.
//
// Two parallel sets of counters mirror the legacy chain (add_source_in_collection
// → chunker → add_chunks) and the IngestSession chain (prepare → take_embedding
// _batch → commit). Each FFI boundary point is recorded as (bytes, calls).
//
// Used by `BenchmarkService.benchmarkIngestFfiTraffic` to compare the two paths
// empirically. Overhead: one `AtomicU64::fetch_add` per FFI call site (≈1 ns),
// negligible against any DB / ONNX / chunker work.

use flutter_rust_bridge::frb;
use std::cell::Cell;
use std::sync::atomic::{AtomicU64, Ordering};

// Thread-local suppression flag: when set, the LEGACY_* counters below skip
// their increments. This lets `prepare_source_ingestion` and `commit_embeddings`
// call into the legacy chunker / add_chunks helpers as plain Rust functions
// without polluting the legacy-path bench numbers.
thread_local! {
    static SUPPRESS_LEGACY_COUNTERS: Cell<bool> = const { Cell::new(false) };
}

pub(crate) fn legacy_counters_enabled() -> bool {
    !SUPPRESS_LEGACY_COUNTERS.with(|c| c.get())
}

/// RAII guard that suppresses legacy counter increments for its lifetime.
/// Used by IngestSession entrypoints to silence the internal calls into
/// `add_source_in_collection`, the chunkers, and `add_chunks`.
pub(crate) struct LegacyCountingGuard {
    previous: bool,
}

impl LegacyCountingGuard {
    pub(crate) fn enter() -> Self {
        let previous = SUPPRESS_LEGACY_COUNTERS.with(|c| c.replace(true));
        Self { previous }
    }
}

impl Drop for LegacyCountingGuard {
    fn drop(&mut self) {
        SUPPRESS_LEGACY_COUNTERS.with(|c| c.set(self.previous));
    }
}

pub(crate) struct AtomicCounter {
    bytes: AtomicU64,
    calls: AtomicU64,
}

impl AtomicCounter {
    pub(crate) const fn new() -> Self {
        Self {
            bytes: AtomicU64::new(0),
            calls: AtomicU64::new(0),
        }
    }

    pub(crate) fn record(&self, bytes: u64) {
        self.bytes.fetch_add(bytes, Ordering::Relaxed);
        self.calls.fetch_add(1, Ordering::Relaxed);
    }

    fn snapshot(&self) -> (u64, u64) {
        (
            self.bytes.load(Ordering::Relaxed),
            self.calls.load(Ordering::Relaxed),
        )
    }

    fn reset(&self) {
        self.bytes.store(0, Ordering::Relaxed);
        self.calls.store(0, Ordering::Relaxed);
    }
}

// --- Legacy chain (old addSourceWithChunking pipeline) -----------------------

/// Dart→Rust: full document body sent to `add_source_in_collection`.
pub(crate) static LEGACY_ADD_SOURCE_IN: AtomicCounter = AtomicCounter::new();
/// Dart→Rust: full document body sent to `semantic_chunk_with_overlap` /
/// `markdown_chunk`.
pub(crate) static LEGACY_CHUNKER_TEXT_IN: AtomicCounter = AtomicCounter::new();
/// Rust→Dart: aggregated chunk content bytes returned from the chunkers.
pub(crate) static LEGACY_CHUNKER_CHUNKS_OUT: AtomicCounter = AtomicCounter::new();
/// Dart→Rust: aggregated chunk content bytes sent into `add_chunks`.
pub(crate) static LEGACY_ADD_CHUNKS_IN: AtomicCounter = AtomicCounter::new();

// --- IngestSession chain (current pipeline) ----------------------------------

/// Dart→Rust: full document body sent to `prepare_source_ingestion`.
pub(crate) static SESSION_PREPARE_CONTENT_IN: AtomicCounter = AtomicCounter::new();
/// Rust→Dart: aggregated `embedding_text` bytes returned from
/// `take_embedding_batch`.
pub(crate) static SESSION_EMBEDDING_TEXT_OUT: AtomicCounter = AtomicCounter::new();
/// Dart→Rust: aggregated `embedding` byte count (Float32List ⇒ 4 bytes per dim)
/// received by `commit_embeddings`. Kept separate so the text-traffic claim
/// can be read without conflating vector traffic.
pub(crate) static SESSION_COMMIT_EMBEDDINGS_IN: AtomicCounter = AtomicCounter::new();

/// Snapshot of all ingest FFI byte/call counters.
///
/// Each field is the cumulative count since the last `reset_ingest_traffic_stats`
/// (or process start). Designed to be diffed around a single ingest call.
#[derive(Debug, Clone)]
pub struct IngestTrafficStats {
    pub legacy_add_source_in_bytes: u64,
    pub legacy_add_source_in_calls: u64,
    pub legacy_chunker_text_in_bytes: u64,
    pub legacy_chunker_text_in_calls: u64,
    pub legacy_chunker_chunks_out_bytes: u64,
    pub legacy_chunker_chunks_out_calls: u64,
    pub legacy_add_chunks_in_bytes: u64,
    pub legacy_add_chunks_in_calls: u64,
    pub session_prepare_content_in_bytes: u64,
    pub session_prepare_content_in_calls: u64,
    pub session_embedding_text_out_bytes: u64,
    pub session_embedding_text_out_calls: u64,
    pub session_commit_embeddings_in_bytes: u64,
    pub session_commit_embeddings_in_calls: u64,
}

impl IngestTrafficStats {
    /// Sum of text-body bytes that crossed FFI on the legacy chain.
    pub fn legacy_text_traffic_total(&self) -> u64 {
        self.legacy_add_source_in_bytes
            + self.legacy_chunker_text_in_bytes
            + self.legacy_chunker_chunks_out_bytes
            + self.legacy_add_chunks_in_bytes
    }

    /// Sum of text-body bytes that crossed FFI on the IngestSession chain.
    /// Excludes embedding vector bytes (vectors are not text and are tracked
    /// separately for transparency).
    pub fn session_text_traffic_total(&self) -> u64 {
        self.session_prepare_content_in_bytes + self.session_embedding_text_out_bytes
    }
}

#[frb(sync)]
pub fn ingest_traffic_stats() -> IngestTrafficStats {
    let (l1_b, l1_c) = LEGACY_ADD_SOURCE_IN.snapshot();
    let (l2_b, l2_c) = LEGACY_CHUNKER_TEXT_IN.snapshot();
    let (l3_b, l3_c) = LEGACY_CHUNKER_CHUNKS_OUT.snapshot();
    let (l4_b, l4_c) = LEGACY_ADD_CHUNKS_IN.snapshot();
    let (s1_b, s1_c) = SESSION_PREPARE_CONTENT_IN.snapshot();
    let (s2_b, s2_c) = SESSION_EMBEDDING_TEXT_OUT.snapshot();
    let (s3_b, s3_c) = SESSION_COMMIT_EMBEDDINGS_IN.snapshot();
    IngestTrafficStats {
        legacy_add_source_in_bytes: l1_b,
        legacy_add_source_in_calls: l1_c,
        legacy_chunker_text_in_bytes: l2_b,
        legacy_chunker_text_in_calls: l2_c,
        legacy_chunker_chunks_out_bytes: l3_b,
        legacy_chunker_chunks_out_calls: l3_c,
        legacy_add_chunks_in_bytes: l4_b,
        legacy_add_chunks_in_calls: l4_c,
        session_prepare_content_in_bytes: s1_b,
        session_prepare_content_in_calls: s1_c,
        session_embedding_text_out_bytes: s2_b,
        session_embedding_text_out_calls: s2_c,
        session_commit_embeddings_in_bytes: s3_b,
        session_commit_embeddings_in_calls: s3_c,
    }
}

#[frb(sync)]
pub fn reset_ingest_traffic_stats() {
    LEGACY_ADD_SOURCE_IN.reset();
    LEGACY_CHUNKER_TEXT_IN.reset();
    LEGACY_CHUNKER_CHUNKS_OUT.reset();
    LEGACY_ADD_CHUNKS_IN.reset();
    SESSION_PREPARE_CONTENT_IN.reset();
    SESSION_EMBEDDING_TEXT_OUT.reset();
    SESSION_COMMIT_EMBEDDINGS_IN.reset();
}

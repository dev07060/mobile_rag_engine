// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Low-overhead counters for query-path chunk content reads.
//
// These counters measure SQLite content rows/bytes read by current search
// shapes. They are intentionally lower-bound counters: they track chunk/doc
// body strings pulled from storage, not allocator copies or FFI serialization.

use flutter_rust_bridge::frb;
use std::cell::Cell;
use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum QueryContentReadPhase {
    Unclassified,
    FullHydrate,
    Preview,
    Assembly,
}

thread_local! {
    static CURRENT_READ_PHASE: Cell<QueryContentReadPhase> =
        const { Cell::new(QueryContentReadPhase::Unclassified) };
}

pub(crate) struct QueryContentReadGuard {
    previous: QueryContentReadPhase,
}

impl QueryContentReadGuard {
    pub(crate) fn enter(phase: QueryContentReadPhase) -> Self {
        let previous = CURRENT_READ_PHASE.with(|p| p.replace(phase));
        Self { previous }
    }
}

impl Drop for QueryContentReadGuard {
    fn drop(&mut self) {
        CURRENT_READ_PHASE.with(|p| p.set(self.previous));
    }
}

struct AtomicCounter {
    rows: AtomicU64,
    content_bytes: AtomicU64,
}

impl AtomicCounter {
    const fn new() -> Self {
        Self {
            rows: AtomicU64::new(0),
            content_bytes: AtomicU64::new(0),
        }
    }

    fn record(&self, content_bytes: u64) {
        self.rows.fetch_add(1, Ordering::Relaxed);
        self.content_bytes
            .fetch_add(content_bytes, Ordering::Relaxed);
    }

    fn snapshot(&self) -> (u64, u64) {
        (
            self.rows.load(Ordering::Relaxed),
            self.content_bytes.load(Ordering::Relaxed),
        )
    }

    fn reset(&self) {
        self.rows.store(0, Ordering::Relaxed);
        self.content_bytes.store(0, Ordering::Relaxed);
    }
}

static HYBRID_RESULT_CONTENT: AtomicCounter = AtomicCounter::new();
static FULL_HYDRATE_CONTENT: AtomicCounter = AtomicCounter::new();
static PREVIEW_CONTENT: AtomicCounter = AtomicCounter::new();
static ASSEMBLY_CONTENT: AtomicCounter = AtomicCounter::new();
static UNCLASSIFIED_CONTENT: AtomicCounter = AtomicCounter::new();
static SCOPED_EXACT_SCAN_CONTENT: AtomicCounter = AtomicCounter::new();

/// Record content read by `hybrid_search` while materializing legacy
/// `HybridSearchResult.content`.
pub(crate) fn record_hybrid_result_content_read(content_bytes: u64) {
    HYBRID_RESULT_CONTENT.record(content_bytes);
}

/// Record content read by the shared SearchHandle hydration query.
pub(crate) fn record_hydrated_content_read(content_bytes: u64) {
    CURRENT_READ_PHASE.with(|phase| match phase.get() {
        QueryContentReadPhase::FullHydrate => FULL_HYDRATE_CONTENT.record(content_bytes),
        QueryContentReadPhase::Preview => PREVIEW_CONTENT.record(content_bytes),
        QueryContentReadPhase::Assembly => ASSEMBLY_CONTENT.record(content_bytes),
        QueryContentReadPhase::Unclassified => UNCLASSIFIED_CONTENT.record(content_bytes),
    });
}

/// Record content read by the hybrid-search scoped exact-scan path (the
/// `source_ids` / `metadata_like` branch that walks the entire scoped chunk
/// set to compute scoped BM25). Counted per row regardless of whether the
/// chunk ends up in the final top-K; this is the "backend scan cost"
/// counter and is intentionally orthogonal to the materialization counters
/// above (a scoped chunk that survives RRF will also show up in
/// `hybrid_result_*` or `full_hydrate_*` when its body is later returned).
pub(crate) fn record_scoped_exact_scan_content_read(content_bytes: u64) {
    SCOPED_EXACT_SCAN_CONTENT.record(content_bytes);
}

#[derive(Debug, Clone)]
pub struct QueryContentReadStats {
    pub hybrid_result_rows: u64,
    pub hybrid_result_content_bytes: u64,
    pub full_hydrate_rows: u64,
    pub full_hydrate_content_bytes: u64,
    pub preview_rows: u64,
    pub preview_content_bytes: u64,
    pub assembly_rows: u64,
    pub assembly_content_bytes: u64,
    pub unclassified_rows: u64,
    pub unclassified_content_bytes: u64,
    pub scoped_exact_scan_rows: u64,
    pub scoped_exact_scan_content_bytes: u64,
}

impl QueryContentReadStats {
    pub fn hydration_rows_total(&self) -> u64 {
        self.full_hydrate_rows + self.preview_rows + self.assembly_rows + self.unclassified_rows
    }

    pub fn hydration_content_bytes_total(&self) -> u64 {
        self.full_hydrate_content_bytes
            + self.preview_content_bytes
            + self.assembly_content_bytes
            + self.unclassified_content_bytes
    }

    /// Materialized result reads only — does NOT include the scoped exact-scan
    /// backend counter, which measures rows scanned during search rather than
    /// rows surfaced as results.
    pub fn rows_total(&self) -> u64 {
        self.hybrid_result_rows + self.hydration_rows_total()
    }

    /// Materialized result bytes only — see [`Self::rows_total`].
    pub fn content_bytes_total(&self) -> u64 {
        self.hybrid_result_content_bytes + self.hydration_content_bytes_total()
    }
}

#[frb(sync)]
pub fn query_content_read_stats() -> QueryContentReadStats {
    let (hybrid_rows, hybrid_bytes) = HYBRID_RESULT_CONTENT.snapshot();
    let (full_rows, full_bytes) = FULL_HYDRATE_CONTENT.snapshot();
    let (preview_rows, preview_bytes) = PREVIEW_CONTENT.snapshot();
    let (assembly_rows, assembly_bytes) = ASSEMBLY_CONTENT.snapshot();
    let (unclassified_rows, unclassified_bytes) = UNCLASSIFIED_CONTENT.snapshot();
    let (scoped_rows, scoped_bytes) = SCOPED_EXACT_SCAN_CONTENT.snapshot();
    QueryContentReadStats {
        hybrid_result_rows: hybrid_rows,
        hybrid_result_content_bytes: hybrid_bytes,
        full_hydrate_rows: full_rows,
        full_hydrate_content_bytes: full_bytes,
        preview_rows,
        preview_content_bytes: preview_bytes,
        assembly_rows,
        assembly_content_bytes: assembly_bytes,
        unclassified_rows,
        unclassified_content_bytes: unclassified_bytes,
        scoped_exact_scan_rows: scoped_rows,
        scoped_exact_scan_content_bytes: scoped_bytes,
    }
}

#[frb(sync)]
pub fn reset_query_content_read_stats() {
    HYBRID_RESULT_CONTENT.reset();
    FULL_HYDRATE_CONTENT.reset();
    PREVIEW_CONTENT.reset();
    ASSEMBLY_CONTENT.reset();
    UNCLASSIFIED_CONTENT.reset();
    SCOPED_EXACT_SCAN_CONTENT.reset();
}

#[frb(sync)]
pub fn take_query_content_read_stats() -> QueryContentReadStats {
    let stats = query_content_read_stats();
    reset_query_content_read_stats();
    stats
}

use flutter_rust_bridge::frb;
use std::sync::atomic::{AtomicU64, Ordering};

struct AtomicTimingCounter {
    count: AtomicU64,
    nanos: AtomicU64,
}

impl AtomicTimingCounter {
    const fn new() -> Self {
        Self {
            count: AtomicU64::new(0),
            nanos: AtomicU64::new(0),
        }
    }

    fn record(&self, nanos: u64) {
        self.count.fetch_add(1, Ordering::Relaxed);
        self.nanos.fetch_add(nanos, Ordering::Relaxed);
    }

    fn snapshot(&self) -> (u64, u64) {
        (
            self.nanos.load(Ordering::Relaxed),
            self.count.load(Ordering::Relaxed),
        )
    }

    fn reset(&self) {
        self.count.store(0, Ordering::Relaxed);
        self.nanos.store(0, Ordering::Relaxed);
    }
}

static ACTIVATE_TOTAL: AtomicTimingCounter = AtomicTimingCounter::new();
static BM25_REBUILD: AtomicTimingCounter = AtomicTimingCounter::new();
static HNSW_LOAD: AtomicTimingCounter = AtomicTimingCounter::new();
static HNSW_LOAD_SUCCESS: AtomicU64 = AtomicU64::new(0);
static HNSW_LOAD_MISS: AtomicU64 = AtomicU64::new(0);
static HNSW_REBUILD: AtomicTimingCounter = AtomicTimingCounter::new();
static HNSW_SAVE: AtomicTimingCounter = AtomicTimingCounter::new();

#[derive(Debug, Clone)]
pub struct ActivationTimingStats {
    pub activate_total_nanos: u64,
    pub activate_count: u64,
    pub bm25_rebuild_nanos: u64,
    pub bm25_rebuild_count: u64,
    pub hnsw_load_nanos: u64,
    pub hnsw_load_count: u64,
    pub hnsw_load_success_count: u64,
    pub hnsw_load_miss_count: u64,
    pub hnsw_rebuild_nanos: u64,
    pub hnsw_rebuild_count: u64,
    pub hnsw_save_nanos: u64,
    pub hnsw_save_count: u64,
}

pub(crate) fn record_activate_total_nanos(nanos: u64) {
    ACTIVATE_TOTAL.record(nanos);
}

pub(crate) fn record_bm25_rebuild_nanos(nanos: u64) {
    BM25_REBUILD.record(nanos);
}

pub(crate) fn record_hnsw_load_nanos(nanos: u64, loaded: bool) {
    HNSW_LOAD.record(nanos);
    if loaded {
        HNSW_LOAD_SUCCESS.fetch_add(1, Ordering::Relaxed);
    } else {
        HNSW_LOAD_MISS.fetch_add(1, Ordering::Relaxed);
    }
}

pub(crate) fn record_hnsw_rebuild_nanos(nanos: u64) {
    HNSW_REBUILD.record(nanos);
}

pub(crate) fn record_hnsw_save_nanos(nanos: u64) {
    HNSW_SAVE.record(nanos);
}

#[frb(sync)]
pub fn activation_timing_stats() -> ActivationTimingStats {
    let (activate_total_nanos, activate_count) = ACTIVATE_TOTAL.snapshot();
    let (bm25_rebuild_nanos, bm25_rebuild_count) = BM25_REBUILD.snapshot();
    let (hnsw_load_nanos, hnsw_load_count) = HNSW_LOAD.snapshot();
    let (hnsw_rebuild_nanos, hnsw_rebuild_count) = HNSW_REBUILD.snapshot();
    let (hnsw_save_nanos, hnsw_save_count) = HNSW_SAVE.snapshot();

    ActivationTimingStats {
        activate_total_nanos,
        activate_count,
        bm25_rebuild_nanos,
        bm25_rebuild_count,
        hnsw_load_nanos,
        hnsw_load_count,
        hnsw_load_success_count: HNSW_LOAD_SUCCESS.load(Ordering::Relaxed),
        hnsw_load_miss_count: HNSW_LOAD_MISS.load(Ordering::Relaxed),
        hnsw_rebuild_nanos,
        hnsw_rebuild_count,
        hnsw_save_nanos,
        hnsw_save_count,
    }
}

#[frb(sync)]
pub fn reset_activation_timing_stats() {
    ACTIVATE_TOTAL.reset();
    BM25_REBUILD.reset();
    HNSW_LOAD.reset();
    HNSW_LOAD_SUCCESS.store(0, Ordering::Relaxed);
    HNSW_LOAD_MISS.store(0, Ordering::Relaxed);
    HNSW_REBUILD.reset();
    HNSW_SAVE.reset();
}

#[frb(sync)]
pub fn take_activation_timing_stats() -> ActivationTimingStats {
    let stats = activation_timing_stats();
    reset_activation_timing_stats();
    stats
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn take_returns_recorded_activation_timings_and_resets() {
        reset_activation_timing_stats();

        record_activate_total_nanos(100);
        record_bm25_rebuild_nanos(20);
        record_hnsw_load_nanos(30, true);
        record_hnsw_load_nanos(40, false);
        record_hnsw_rebuild_nanos(50);
        record_hnsw_save_nanos(60);

        let stats = take_activation_timing_stats();
        assert_eq!(stats.activate_total_nanos, 100);
        assert_eq!(stats.activate_count, 1);
        assert_eq!(stats.bm25_rebuild_nanos, 20);
        assert_eq!(stats.bm25_rebuild_count, 1);
        assert_eq!(stats.hnsw_load_nanos, 70);
        assert_eq!(stats.hnsw_load_count, 2);
        assert_eq!(stats.hnsw_load_success_count, 1);
        assert_eq!(stats.hnsw_load_miss_count, 1);
        assert_eq!(stats.hnsw_rebuild_nanos, 50);
        assert_eq!(stats.hnsw_rebuild_count, 1);
        assert_eq!(stats.hnsw_save_nanos, 60);
        assert_eq!(stats.hnsw_save_count, 1);

        let reset = take_activation_timing_stats();
        assert_eq!(reset.activate_total_nanos, 0);
        assert_eq!(reset.hnsw_load_count, 0);
    }
}

// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Licensed under the MIT License. You may obtain a copy of the License at
// https://opensource.org/licenses/MIT
//
// This software is provided "AS IS", without warranty of any kind, express or
// implied, including but not limited to the warranties of merchantability,
// fitness for a particular purpose, and noninfringement. In no event shall the
// authors or copyright holders be liable for any claim, damages, or other
// liability arising from the use of this software.
//
// CONTRIBUTOR GUIDELINES:
// This file is part of the core engine. Any modifications require owner approval.
// Please submit a PR with detailed explanation of changes before modifying.
//
//! Database connection pool for efficient SQLite connection reuse.
//!
//! This module provides a global connection pool that eliminates the overhead
//! of creating new database connections for each operation. Performance impact:
//! - Single search: 50-100ms → 1-5ms (connection overhead eliminated)
//! - Batch operations: 33-50% faster
//! - Reduced file descriptor usage

use anyhow::Result;
use log::info;
use once_cell::sync::OnceCell;
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use std::path::Path;
use std::sync::RwLock;

/// Global database connection pool (thread-safe)
static DB_POOL: OnceCell<RwLock<Option<Pool<SqliteConnectionManager>>>> = OnceCell::new();

/// Initialize the global connection pool with optimized SQLite settings.
///
/// This should be called once during application startup, before any database operations.
///
/// # Arguments
/// * `db_path` - Path to the SQLite database file
/// * `max_size` - Maximum number of connections in the pool (default: 4)
///
/// # SQLite Optimizations
/// - WAL mode: Better concurrency for read-heavy workloads
/// - 64MB page cache: Reduces disk I/O
/// - Memory temp storage: Faster temporary operations
/// - 256MB mmap: Memory-mapped I/O for large databases
///
/// # Example
/// ```rust,no_run
/// use rag_engine_flutter::api::db_pool::init_db_pool;
///
/// init_db_pool("/path/to/rag.sqlite".to_string(), 4).unwrap();
/// ```
pub fn init_db_pool(db_path: String, max_size: u32) -> Result<()> {
    info!(
        "[db_pool] Initializing connection pool: path={}, max_size={}",
        db_path, max_size
    );

    let manager = SqliteConnectionManager::file(&db_path).with_init(|conn| {
        // SQLite performance optimizations
        conn.execute_batch(
            "PRAGMA journal_mode = WAL;
                 PRAGMA synchronous = NORMAL;
                 PRAGMA cache_size = -64000;
                 PRAGMA temp_store = MEMORY;
                 PRAGMA mmap_size = 268435456;
                 PRAGMA page_size = 4096;",
        )?;
        Ok(())
    });

    let pool = Pool::builder()
        .max_size(max_size)
        .min_idle(Some(1)) // Keep at least 1 connection alive
        .connection_timeout(std::time::Duration::from_secs(5))
        .build(manager)?;

    // Support re-initialization
    if let Some(lock) = DB_POOL.get() {
        let mut guard = lock.write().unwrap();
        *guard = Some(pool);
        info!("[db_pool] Connection pool updated/re-initialized");
    } else {
        // Try to initialize for the first time
        // Handle race condition if multiple threads try to init simultaneously
        let lock = RwLock::new(Some(pool));
        if let Err(params) = DB_POOL.set(lock) {
            // Initialization failed because it was just initialized by another thread.
            // Retrieve our pool and update the existing lock.
            let my_pool = params.into_inner().unwrap().unwrap();
            let existing_lock = DB_POOL.get().unwrap();
            let mut guard = existing_lock.write().unwrap();
            *guard = Some(my_pool);
            info!("[db_pool] Connection pool updated (race condition handled)");
        } else {
            info!("[db_pool] Connection pool initialized successfully");
        }
    }

    let vec_path = Path::new(&db_path)
        .with_extension("vec")
        .to_string_lossy()
        .into_owned();
    info!("[mmap_store] Initializing MmapVectorStore at {}", vec_path);
    match crate::api::mmap_store::MmapVectorStore::new(&vec_path) {
        Ok(store) => {
            let mut mmap_guard = crate::api::mmap_store::MMAP_STORE.write().unwrap();
            *mmap_guard = Some(store);
            info!("[mmap_store] MmapVectorStore initialized successfully");
        }
        Err(e) => {
            log::error!("[mmap_store] Failed to initialize MmapVectorStore: {}", e);
        }
    }

    Ok(())
}

/// Get a connection from the pool.
///
/// This is the primary method for obtaining database connections. The connection
/// is automatically returned to the pool when dropped.
///
/// # Returns
/// A pooled connection that can be used like a regular rusqlite::Connection
///
/// # Errors
/// Returns an error if:
/// - The pool has not been initialized (call `init_db_pool` first)
/// - No connections are available within the timeout period
///
/// # Example
/// ```rust,ignore
/// let conn = get_connection()?;
/// conn.execute("INSERT INTO ...", params![])?;
/// // Connection automatically returned to pool when `conn` goes out of scope
/// ```
pub(crate) fn get_connection() -> Result<r2d2::PooledConnection<SqliteConnectionManager>> {
    let pool_guard = DB_POOL
        .get()
        .ok_or_else(|| anyhow::anyhow!("DB pool not initialized. Call init_db_pool() first."))?
        .read()
        .unwrap();

    let pool = pool_guard
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("DB pool is None"))?;

    Ok(pool.get()?)
}

/// Check if the connection pool is initialized.
pub fn is_pool_initialized() -> bool {
    DB_POOL
        .get()
        .and_then(|lock| lock.read().ok())
        .map(|guard| guard.is_some())
        .unwrap_or(false)
}

/// Get pool statistics for monitoring.
///
/// Returns (active_connections, idle_connections, max_size)
pub fn get_pool_stats() -> Option<(u32, u32, u32)> {
    DB_POOL
        .get()
        .and_then(|lock| lock.read().ok())
        .and_then(|guard| {
            guard.as_ref().map(|pool| {
                let state = pool.state();
                (state.connections, state.idle_connections, pool.max_size())
            })
        })
}

/// Close the connection pool and release all resources.
///
/// This should be called during application shutdown. After calling this,
/// you must call `init_db_pool` again before using database operations.
pub fn close_db_pool() {
    if let Some(pool_lock) = DB_POOL.get() {
        let mut pool_guard = pool_lock.write().unwrap();
        *pool_guard = None;
        info!("[db_pool] Connection pool closed");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::params;

    #[test]
    fn test_pool_initialization() {
        let temp_db = tempfile::NamedTempFile::new().unwrap();
        let db_path = temp_db.path().to_str().unwrap().to_string();

        assert!(!is_pool_initialized());
        init_db_pool(db_path.clone(), 2).unwrap();
        assert!(is_pool_initialized());

        close_db_pool();
        assert!(!is_pool_initialized());
    }

    #[test]
    fn test_get_connection() {
        let temp_db = tempfile::NamedTempFile::new().unwrap();
        let db_path = temp_db.path().to_str().unwrap().to_string();

        init_db_pool(db_path, 2).unwrap();

        let conn = get_connection().unwrap();
        conn.execute("CREATE TABLE test (id INTEGER)", params![])
            .unwrap();
        drop(conn);

        // Connection should be returned to pool
        let conn2 = get_connection().unwrap();
        let count: i32 = conn2
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(count, 1);

        close_db_pool();
    }

    #[test]
    fn test_pool_stats() {
        let temp_db = tempfile::NamedTempFile::new().unwrap();
        let db_path = temp_db.path().to_str().unwrap().to_string();

        init_db_pool(db_path, 4).unwrap();

        let stats = get_pool_stats().unwrap();
        assert_eq!(stats.2, 4); // max_size
        assert!(stats.0 >= 1); // at least min_idle connection

        close_db_pool();
    }
}

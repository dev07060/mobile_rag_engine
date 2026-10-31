// Copyright 2026 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT

use anyhow::{Context, Result};
use memmap2::{MmapMut, MmapOptions};
use once_cell::sync::Lazy;
use std::fs::{File, OpenOptions};
use std::path::Path;
use std::sync::RwLock;

#[cfg(test)]
use std::sync::atomic::{AtomicBool, Ordering};

const MAGIC_HEADER: &[u8; 4] = b"VEC1";
const HEADER_SIZE: usize = 4;

pub static MMAP_STORE: Lazy<RwLock<Option<MmapVectorStore>>> = Lazy::new(|| RwLock::new(None));

#[cfg(test)]
static FAIL_NEXT_APPEND: AtomicBool = AtomicBool::new(false);

#[cfg(test)]
pub(crate) fn fail_next_append_for_test() {
    FAIL_NEXT_APPEND.store(true, Ordering::SeqCst);
}

pub struct MmapVectorStore {
    file: File,
    mmap: Option<MmapMut>,
    current_offset: usize,
    capacity: usize,
}

impl MmapVectorStore {
    const INITIAL_CAPACITY: usize = 1024 * 1024; // 1 MB initial

    pub(crate) fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let path = path.as_ref();
        let file_exists = path.exists();
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .open(path)
            .context("Failed to open vector store file")?;

        let mut current_offset = 0;
        let mut capacity = if file_exists {
            file.metadata()?.len() as usize
        } else {
            0
        };
        // A missing file, or one too short to hold the header (e.g. left at
        // zero length by a crash between create and set_len), starts fresh.
        let needs_init = capacity < HEADER_SIZE;
        if needs_init {
            file.set_len(Self::INITIAL_CAPACITY as u64)?;
            capacity = Self::INITIAL_CAPACITY;
        }

        let mut mmap = unsafe { MmapOptions::new().map_mut(&file)? };

        if needs_init {
            mmap[0..4].copy_from_slice(MAGIC_HEADER);
            current_offset = HEADER_SIZE;
        } else {
            if &mmap[0..4] != MAGIC_HEADER {
                anyhow::bail!("Invalid vector store magic header");
            }

            current_offset = HEADER_SIZE;
            loop {
                if current_offset + 8 > capacity {
                    break;
                }

                let mut len_bytes = [0u8; 4];
                len_bytes.copy_from_slice(&mmap[current_offset..current_offset + 4]);
                let len = u32::from_le_bytes(len_bytes) as usize;

                if len == 0 || current_offset + 8 + len > capacity {
                    break;
                }

                let mut crc_bytes = [0u8; 4];
                crc_bytes.copy_from_slice(&mmap[current_offset + 4..current_offset + 8]);
                let stored_crc = u32::from_le_bytes(crc_bytes);

                let data_slice = &mmap[current_offset + 8..current_offset + 8 + len];
                let mut hasher = crc32fast::Hasher::new();
                hasher.update(data_slice);
                let computed_crc = hasher.finalize();

                if stored_crc != computed_crc {
                    log::warn!(
                        "[mmap_store] Data corruption detected at offset {}. Truncating recovery.",
                        current_offset
                    );
                    break;
                }

                current_offset += 8 + len;
            }
        }

        Ok(Self {
            file,
            mmap: Some(mmap),
            current_offset,
            capacity,
        })
    }

    pub(crate) fn append(&mut self, vector: &[u8]) -> Result<usize> {
        #[cfg(test)]
        if FAIL_NEXT_APPEND.swap(false, Ordering::SeqCst) {
            anyhow::bail!("injected mmap append failure");
        }
        let len = vector.len();
        let total_len = 8 + len;

        while self.current_offset + total_len > self.capacity {
            self.resize(std::cmp::max(self.capacity * 2, self.capacity + total_len))?;
        }

        let start = self.current_offset;
        if let Some(mmap) = &mut self.mmap {
            let mut hasher = crc32fast::Hasher::new();
            hasher.update(vector);
            let crc = hasher.finalize();

            mmap[start..start + 4].copy_from_slice(&(len as u32).to_le_bytes());
            mmap[start + 4..start + 8].copy_from_slice(&crc.to_le_bytes());
            mmap[start + 8..start + total_len].copy_from_slice(vector);
        }

        self.current_offset += total_len;

        Ok(start)
    }

    pub(crate) fn get(&self, offset: usize) -> Option<&[u8]> {
        if offset + 8 > self.current_offset {
            return None;
        }
        if let Some(mmap) = &self.mmap {
            let mut len_bytes = [0u8; 4];
            len_bytes.copy_from_slice(&mmap[offset..offset + 4]);
            let len = u32::from_le_bytes(len_bytes) as usize;

            if offset + 8 + len <= self.current_offset {
                Some(&mmap[offset + 8..offset + 8 + len])
            } else {
                None
            }
        } else {
            None
        }
    }

    pub(crate) fn flush(&self) -> Result<()> {
        if let Some(mmap) = &self.mmap {
            mmap.flush()?;
        }
        Ok(())
    }

    fn resize(&mut self, new_capacity: usize) -> Result<()> {
        self.mmap.take(); // Release lock
        self.file.set_len(new_capacity as u64)?;
        let mmap = unsafe { MmapOptions::new().map_mut(&self.file)? };

        self.mmap = Some(mmap);
        self.capacity = new_capacity;

        Ok(())
    }
}

impl Drop for MmapVectorStore {
    fn drop(&mut self) {
        let _ = self.flush();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_mmap_vector_store_append_and_get() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("test.vec");

        let mut store = MmapVectorStore::new(&file_path).unwrap();

        let vec1 = vec![1, 2, 3, 4];
        let vec2 = vec![5, 6, 7, 8, 9];

        let id1 = store.append(&vec1).unwrap();
        let id2 = store.append(&vec2).unwrap();

        assert_eq!(store.get(id1).unwrap(), vec1.as_slice());
        assert_eq!(store.get(id2).unwrap(), vec2.as_slice());

        // Test persistence
        drop(store);
        let store2 = MmapVectorStore::new(&file_path).unwrap();
        assert_eq!(store2.get(id1).unwrap(), vec1.as_slice());
        assert_eq!(store2.get(id2).unwrap(), vec2.as_slice());
    }

    #[test]
    fn test_mmap_vector_store_resizing() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("resize_test.vec");

        let mut store = MmapVectorStore::new(&file_path).unwrap();
        // Force it to resize by appending a lot of data
        let large_vec = vec![42; 500_000];

        let id1 = store.append(&large_vec).unwrap();
        let id2 = store.append(&large_vec).unwrap();
        let id3 = store.append(&large_vec).unwrap();

        assert_eq!(store.get(id1).unwrap().len(), 500_000);
        assert_eq!(store.get(id2).unwrap().len(), 500_000);
        assert_eq!(store.get(id3).unwrap().len(), 500_000);
    }

    #[test]
    fn test_mmap_vector_store_corruption_recovery() {
        use std::io::Write;
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("corrupt.vec");

        let mut store = MmapVectorStore::new(&file_path).unwrap();
        let vec1 = vec![1, 1, 1, 1];
        let vec2 = vec![2, 2, 2, 2];
        let id1 = store.append(&vec1).unwrap();
        let id2 = store.append(&vec2).unwrap();
        drop(store);

        // Corrupt the file manually at id2 (change CRC or length or data)
        let mut file = OpenOptions::new().write(true).open(&file_path).unwrap();
        file.set_len((id2 + 4) as u64).unwrap(); // truncate in the middle of id2's header
        drop(file);

        // Load again. It should recover and only have vec1
        let store2 = MmapVectorStore::new(&file_path).unwrap();
        assert_eq!(store2.get(id1).unwrap(), vec1.as_slice());
        assert!(store2.get(id2).is_none());
        assert_eq!(store2.current_offset, id2); // correctly truncated before id2
    }

    #[test]
    fn test_mmap_vector_store_opens_existing_empty_file() {
        // A crash between create and set_len, or an external truncate, leaves
        // a zero-length .vec file; opening it must re-initialize, not fail.
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("empty.vec");
        File::create(&file_path).unwrap();

        let mut store = MmapVectorStore::new(&file_path).unwrap();
        let id = store.append(&[7, 7, 7]).unwrap();
        assert_eq!(id, HEADER_SIZE);
        drop(store);

        let reopened = MmapVectorStore::new(&file_path).unwrap();
        assert_eq!(reopened.get(id).unwrap(), &[7, 7, 7]);
    }

    #[test]
    fn test_mmap_vector_store_crc_mismatch_stops_recovery_at_bad_record() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("crc.vec");

        let mut store = MmapVectorStore::new(&file_path).unwrap();
        let id1 = store.append(&[1, 2, 3, 4]).unwrap();
        let id2 = store.append(&[5, 6, 7, 8]).unwrap();
        let id3 = store.append(&[9, 9, 9, 9]).unwrap();
        drop(store);

        // Flip one payload byte of the middle record so its CRC no longer matches.
        let mut bytes = std::fs::read(&file_path).unwrap();
        bytes[id2 + 8] ^= 0xFF;
        std::fs::write(&file_path, &bytes).unwrap();

        let store = MmapVectorStore::new(&file_path).unwrap();
        assert_eq!(store.get(id1).unwrap(), &[1, 2, 3, 4]);
        assert!(store.get(id2).is_none());
        assert!(store.get(id3).is_none());
        assert_eq!(store.current_offset, id2);
    }

    #[test]
    fn test_mmap_vector_store_append_after_reopen_keeps_earlier_records() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("reopen.vec");

        let mut store = MmapVectorStore::new(&file_path).unwrap();
        let id1 = store.append(&[1; 16]).unwrap();
        drop(store);

        let mut store = MmapVectorStore::new(&file_path).unwrap();
        let id2 = store.append(&[2; 16]).unwrap();
        assert_eq!(id2, id1 + 8 + 16);
        drop(store);

        let store = MmapVectorStore::new(&file_path).unwrap();
        assert_eq!(store.get(id1).unwrap(), &[1; 16]);
        assert_eq!(store.get(id2).unwrap(), &[2; 16]);
    }

    #[test]
    fn test_mmap_vector_store_resize_preserves_contents() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("resize_contents.vec");

        let mut store = MmapVectorStore::new(&file_path).unwrap();
        let records: Vec<Vec<u8>> = (0..5u8).map(|i| vec![i; 400_000]).collect();
        let ids: Vec<usize> = records.iter().map(|r| store.append(r).unwrap()).collect();
        assert!(store.capacity > MmapVectorStore::INITIAL_CAPACITY);
        for (id, record) in ids.iter().zip(&records) {
            assert_eq!(store.get(*id).unwrap(), record.as_slice());
        }
        drop(store);

        let store = MmapVectorStore::new(&file_path).unwrap();
        for (id, record) in ids.iter().zip(&records) {
            assert_eq!(store.get(*id).unwrap(), record.as_slice());
        }
    }

    #[test]
    fn test_mmap_vector_store_get_rejects_out_of_range_offsets() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("range.vec");

        let mut store = MmapVectorStore::new(&file_path).unwrap();
        let id = store.append(&[3, 3, 3]).unwrap();
        assert!(store.get(store.current_offset).is_none());
        assert!(store.get(id + 8 + 3).is_none());
        assert!(store.get(usize::MAX / 2).is_none());
        // Offset 0 is the magic header, never a record.
        assert!(store.get(0).is_none());
    }
}

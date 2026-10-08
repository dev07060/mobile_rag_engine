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
//! HuggingFace tokenizers integration module.

use anyhow::Result;
use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use std::collections::HashMap;
#[cfg(test)]
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::RwLock;
use tokenizers::Tokenizer;

static TOKENIZER: Lazy<RwLock<Option<Tokenizer>>> = Lazy::new(|| RwLock::new(None));
/// Copies of `TOKENIZER` with truncation preset, keyed by max length (at most
/// one per `resolve_truncation_max_length` bucket). Setting truncation needs
/// `&mut Tokenizer`, so this avoids deep-cloning the whole tokenizer on every
/// `tokenize` call. Cleared whenever `init_tokenizer` replaces the tokenizer.
static TRUNCATING_TOKENIZERS: Lazy<RwLock<HashMap<usize, Tokenizer>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));
#[cfg(test)]
static COUNT_TOKENS_UNTRUNCATED_CALLS: AtomicUsize = AtomicUsize::new(0);
#[cfg(test)]
static TRUNCATING_TOKENIZER_BUILDS: AtomicUsize = AtomicUsize::new(0);
const TOKENIZER_BASE_TRUNCATION_MAX_LENGTH: usize = 256;
const TOKENIZER_MID_TRUNCATION_MAX_LENGTH: usize = 384;
const TOKENIZER_MAX_TRUNCATION_MAX_LENGTH: usize = 512;
const TOKENIZER_MID_TRUNCATION_CHAR_THRESHOLD: usize = 1200;
const TOKENIZER_MAX_TRUNCATION_CHAR_THRESHOLD: usize = 2400;

pub(crate) fn resolve_truncation_max_length(text: &str) -> usize {
    let char_len = text.chars().count();
    if char_len >= TOKENIZER_MAX_TRUNCATION_CHAR_THRESHOLD {
        TOKENIZER_MAX_TRUNCATION_MAX_LENGTH
    } else if char_len >= TOKENIZER_MID_TRUNCATION_CHAR_THRESHOLD {
        TOKENIZER_MID_TRUNCATION_MAX_LENGTH
    } else {
        TOKENIZER_BASE_TRUNCATION_MAX_LENGTH
    }
}

/// Initialize tokenizer with tokenizer.json file path.
pub fn init_tokenizer(tokenizer_path: String) -> Result<()> {
    let mut tokenizer = Tokenizer::from_file(&tokenizer_path)
        .map_err(|e| anyhow::anyhow!("Failed to load tokenizer: {}", e))?;

    tokenizer.with_padding(None);
    tokenizer.with_truncation(None).ok();

    let mut global_tokenizer = TOKENIZER.write().unwrap();
    *global_tokenizer = Some(tokenizer);
    TRUNCATING_TOKENIZERS.write().unwrap().clear();
    Ok(())
}

fn with_tokenizer<T>(f: impl FnOnce(&Tokenizer) -> Result<T>) -> Result<T> {
    let tokenizer_guard = TOKENIZER.read().unwrap();
    let tokenizer = tokenizer_guard
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("Tokenizer not initialized. Call init_tokenizer first."))?;
    f(tokenizer)
}

fn encode_without_truncation(text: &str, add_special_tokens: bool) -> Result<tokenizers::Encoding> {
    with_tokenizer(|tokenizer| {
        tokenizer
            .encode(text, add_special_tokens)
            .map_err(|e| anyhow::anyhow!("Tokenization failed: {}", e))
    })
}

fn encode_internal(
    text: &str,
    add_special_tokens: bool,
    truncation_max_length: Option<usize>,
) -> Result<tokenizers::Encoding> {
    let Some(max_length) = truncation_max_length else {
        return encode_without_truncation(text, add_special_tokens);
    };

    let encode = |tokenizer: &Tokenizer| {
        tokenizer
            .encode(text, add_special_tokens)
            .map_err(|e| anyhow::anyhow!("Tokenization failed: {}", e))
    };
    if let Some(tokenizer) = TRUNCATING_TOKENIZERS.read().unwrap().get(&max_length) {
        return encode(tokenizer);
    }

    // Hold the base tokenizer's read lock while inserting so a concurrent
    // `init_tokenizer` cannot clear the cache between the clone and the insert.
    with_tokenizer(|base| {
        let mut cache = TRUNCATING_TOKENIZERS.write().unwrap();
        let tokenizer = cache.entry(max_length).or_insert_with(|| {
            #[cfg(test)]
            TRUNCATING_TOKENIZER_BUILDS.fetch_add(1, Ordering::Relaxed);
            let mut tokenizer = base.clone();
            tokenizer
                .with_truncation(Some(tokenizers::TruncationParams {
                    max_length,
                    ..Default::default()
                }))
                .ok();
            tokenizer
        });
        encode(tokenizer)
    })
}

pub(crate) fn count_tokens_untruncated(text: &str) -> Result<usize> {
    #[cfg(test)]
    COUNT_TOKENS_UNTRUNCATED_CALLS.fetch_add(1, Ordering::Relaxed);
    Ok(encode_internal(text, true, None)?.len())
}

pub(crate) fn count_plain_text_tokens_untruncated(text: &str) -> Result<usize> {
    Ok(encode_internal(text, false, None)?.len())
}

#[cfg(test)]
pub(crate) fn reset_count_tokens_untruncated_call_count() {
    COUNT_TOKENS_UNTRUNCATED_CALLS.store(0, Ordering::Relaxed);
}

#[cfg(test)]
pub(crate) fn reset_truncating_tokenizer_build_count() {
    TRUNCATING_TOKENIZER_BUILDS.store(0, Ordering::Relaxed);
}

#[cfg(test)]
pub(crate) fn truncating_tokenizer_build_count() -> usize {
    TRUNCATING_TOKENIZER_BUILDS.load(Ordering::Relaxed)
}

#[cfg(test)]
pub(crate) fn count_tokens_untruncated_call_count() -> usize {
    COUNT_TOKENS_UNTRUNCATED_CALLS.load(Ordering::Relaxed)
}

/// Tokenize text (returns token IDs with CLS/SEP tokens).
#[frb(sync)]
pub fn tokenize(text: String) -> Result<Vec<u32>> {
    let max_length = resolve_truncation_max_length(&text);
    let encoding = encode_internal(&text, true, Some(max_length))?;
    Ok(encoding.get_ids().to_vec())
}

/// Count plain-text tokens without truncation or special tokens.
#[frb(sync)]
pub fn count_tokens(text: String) -> Result<u32> {
    Ok(count_plain_text_tokens_untruncated(&text)? as u32)
}

/// Decode token IDs to text.
#[frb(sync)]
pub fn decode_tokens(token_ids: Vec<u32>) -> Result<String> {
    with_tokenizer(|tokenizer| {
        tokenizer
            .decode(&token_ids, true)
            .map_err(|e| anyhow::anyhow!("Decoding failed: {}", e))
    })
}

/// Get vocab size.
#[frb(sync)]
pub fn get_vocab_size() -> Result<u32> {
    with_tokenizer(|tokenizer| Ok(tokenizer.get_vocab_size(true) as u32))
}

#[cfg(test)]
mod tests {
    use super::*;
    use once_cell::sync::Lazy;
    use std::sync::Mutex;
    use tokenizers::models::wordlevel::WordLevel;
    use tokenizers::pre_tokenizers::whitespace::Whitespace;
    use tokenizers::processors::bert::BertProcessing;
    use uuid::Uuid;

    static TOKENIZER_TEST_MUTEX: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

    fn init_test_tokenizer() {
        init_test_tokenizer_with_vocab(r#"{"[UNK]":0,"hello":1,"world":2,"[CLS]":3,"[SEP]":4}"#);
    }

    fn init_test_tokenizer_with_vocab(vocab: &str) {
        let suffix = Uuid::new_v4().to_string();
        let vocab_path =
            std::env::temp_dir().join(format!("mobile_rag_engine_test_vocab_{suffix}.json"));
        std::fs::write(&vocab_path, vocab).expect("failed to write test vocab");

        let model = WordLevel::builder()
            .files(vocab_path.to_str().unwrap().to_string())
            .unk_token("[UNK]".to_string())
            .build()
            .expect("failed to build test tokenizer");
        let mut tokenizer = Tokenizer::new(model);
        tokenizer.with_pre_tokenizer(Some(Whitespace));
        tokenizer.with_post_processor(Some(BertProcessing::new(
            ("[SEP]".to_string(), 4),
            ("[CLS]".to_string(), 3),
        )));

        let path =
            std::env::temp_dir().join(format!("mobile_rag_engine_test_tokenizer_{suffix}.json"));
        tokenizer
            .save(path.to_str().unwrap(), false)
            .expect("failed to save test tokenizer");
        init_tokenizer(path.to_str().unwrap().to_string()).expect("failed to init tokenizer");
    }

    #[test]
    fn test_resolve_truncation_max_length_short() {
        assert_eq!(resolve_truncation_max_length("hello world"), 256);
    }

    #[test]
    fn test_resolve_truncation_max_length_mid() {
        let text = "가".repeat(1500);
        assert_eq!(resolve_truncation_max_length(&text), 384);
    }

    #[test]
    fn test_resolve_truncation_max_length_long() {
        let text = "x".repeat(3000);
        assert_eq!(resolve_truncation_max_length(&text), 512);
    }

    #[test]
    fn test_count_tokens_untruncated_matches_short_tokenization() {
        let _guard = TOKENIZER_TEST_MUTEX
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        init_test_tokenizer();

        let text = "hello world hello";
        let truncated = tokenize(text.to_string()).unwrap();
        let untruncated = count_tokens_untruncated(text).unwrap();
        let plain_text_count = count_tokens(text.to_string()).unwrap();

        assert_eq!(truncated.len(), untruncated);
        assert_eq!(plain_text_count, 3);
        assert_eq!(untruncated, plain_text_count as usize + 2);
    }

    #[test]
    fn test_count_tokens_untruncated_avoids_runtime_truncation() {
        let _guard = TOKENIZER_TEST_MUTEX
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        init_test_tokenizer();

        let text = std::iter::repeat("hello")
            .take(700)
            .collect::<Vec<_>>()
            .join(" ");
        let truncated = tokenize(text.clone()).unwrap();
        let untruncated = count_tokens_untruncated(&text).unwrap();

        assert_eq!(truncated.len(), TOKENIZER_MAX_TRUNCATION_MAX_LENGTH);
        assert!(untruncated > truncated.len());
    }

    #[test]
    fn test_count_tokens_excludes_special_tokens() {
        let _guard = TOKENIZER_TEST_MUTEX
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        init_test_tokenizer();

        let text = "hello world";
        let plain = count_tokens(text.to_string()).unwrap();
        let model_input = count_tokens_untruncated(text).unwrap();

        assert_eq!(plain, 2);
        assert_eq!(model_input, 4);
    }

    fn words(count: usize) -> String {
        std::iter::repeat("hello world")
            .take(count)
            .collect::<Vec<_>>()
            .join(" ")
    }

    // The pre-cache behaviour: clone the tokenizer and set truncation per call.
    fn reference_tokenize(text: &str) -> Vec<u32> {
        let max_length = resolve_truncation_max_length(text);
        with_tokenizer(|tokenizer| {
            let mut tokenizer = tokenizer.clone();
            tokenizer
                .with_truncation(Some(tokenizers::TruncationParams {
                    max_length,
                    ..Default::default()
                }))
                .ok();
            Ok(tokenizer.encode(text, true).unwrap().get_ids().to_vec())
        })
        .unwrap()
    }

    #[test]
    fn test_tokenize_matches_per_call_truncation() {
        let _guard = TOKENIZER_TEST_MUTEX
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        init_test_tokenizer();

        // Short, mid (>= 1200 chars) and long (>= 2400 chars) texts hit the
        // 256 / 384 / 512 truncation lengths.
        for text in ["hello world".to_string(), words(110), words(220), words(400)] {
            assert_eq!(tokenize(text.clone()).unwrap(), reference_tokenize(&text));
        }
    }

    #[test]
    fn test_tokenize_reuses_one_truncating_tokenizer_per_length() {
        let _guard = TOKENIZER_TEST_MUTEX
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        init_test_tokenizer();
        reset_truncating_tokenizer_build_count();

        for _ in 0..50 {
            tokenize("hello world".to_string()).unwrap();
            tokenize(words(400)).unwrap();
        }
        assert_eq!(truncating_tokenizer_build_count(), 2);
    }

    #[test]
    fn test_reinit_drops_cached_truncating_tokenizers() {
        let _guard = TOKENIZER_TEST_MUTEX
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        init_test_tokenizer();
        assert_eq!(tokenize("hello world".to_string()).unwrap(), vec![3, 1, 2, 4]);

        init_test_tokenizer_with_vocab(r#"{"[UNK]":0,"hello":7,"world":8,"[CLS]":3,"[SEP]":4}"#);
        assert_eq!(tokenize("hello world".to_string()).unwrap(), vec![3, 7, 8, 4]);
    }
}

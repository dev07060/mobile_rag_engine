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
//! Lightweight text compression for prompt optimization.

use std::collections::HashSet;

#[derive(Debug, Clone)]
pub struct CompressionOptions {
    pub remove_stopwords: bool,
    pub remove_duplicates: bool,
    pub language: String,
    pub level: i32,
}

impl Default for CompressionOptions {
    fn default() -> Self {
        Self {
            remove_stopwords: true,
            remove_duplicates: true,
            language: "en".to_string(),
            level: 1,
        }
    }
}

#[derive(Debug, Clone)]
pub struct CompressedText {
    pub text: String,
    pub original_chars: i32,
    pub compressed_chars: i32,
    pub ratio: f64,
    pub sentences_removed: i32,
    pub chars_saved_stopwords: i32,
    pub chars_saved_truncation: i32,
}

/// Split text into sentences.
pub fn split_sentences(text: String) -> Vec<String> {
    if text.is_empty() {
        return vec![];
    }

    let mut sentences = Vec::new();
    let mut current = String::new();

    for ch in text.chars() {
        current.push(ch);
        if ch == '.' || ch == '?' || ch == '!' || ch == '。' {
            let trimmed = current.trim().to_string();
            if !trimmed.is_empty() && trimmed.len() > 1 {
                sentences.push(trimmed);
            }
            current = String::new();
        }
    }

    let trimmed = current.trim().to_string();
    if !trimmed.is_empty() {
        sentences.push(trimmed);
    }

    sentences
}

/// Calculate hash for sentence deduplication (FNV-1a).
pub fn sentence_hash(sentence: String) -> u64 {
    let normalized: String = sentence
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in normalized.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

/// Compress text with deduplication and truncation.
pub fn compress_text(text: String, max_chars: i32, options: CompressionOptions) -> CompressedText {
    let original_chars = text.chars().count() as i32;

    if text.is_empty() {
        return CompressedText {
            text: String::new(),
            original_chars: 0,
            compressed_chars: 0,
            ratio: 1.0,
            sentences_removed: 0,
            chars_saved_stopwords: 0,
            chars_saved_truncation: 0,
        };
    }

    let sentences = split_sentences(text);
    let original_sentence_count = sentences.len();

    let mut unique_sentences = Vec::new();
    let mut seen_hashes = HashSet::new();

    if options.remove_duplicates {
        for sentence in sentences {
            let hash = sentence_hash(sentence.clone());
            if !seen_hashes.contains(&hash) {
                seen_hashes.insert(hash);
                unique_sentences.push(sentence);
            }
        }
    } else {
        unique_sentences = sentences;
    }

    let mut result = unique_sentences.join(" ");
    let chars_before_truncation = result.chars().count() as i32;

    if max_chars > 0 && result.chars().count() > max_chars as usize {
        result = result.chars().take(max_chars as usize).collect();
        if let Some(pos) = result.rfind(|c| c == '.' || c == '?' || c == '!' || c == '。') {
            result = result[..=pos].to_string();
        }
    }

    let chars_saved_truncation = chars_before_truncation - result.chars().count() as i32;
    let compressed_chars = result.chars().count() as i32;
    let sentences_removed = (original_sentence_count - unique_sentences.len()) as i32;

    CompressedText {
        text: result,
        original_chars,
        compressed_chars,
        ratio: if original_chars > 0 {
            compressed_chars as f64 / original_chars as f64
        } else {
            1.0
        },
        sentences_removed,
        chars_saved_stopwords: 0,
        chars_saved_truncation,
    }
}

/// Quick compress with default options.
pub fn compress_text_simple(text: String, level: i32) -> String {
    compress_text(
        text,
        0,
        CompressionOptions {
            level,
            ..Default::default()
        },
    )
    .text
}

/// Check if text needs compression based on token estimate.
pub fn should_compress(text: String, token_threshold: i32) -> bool {
    text.chars().count() / 4 > token_threshold as usize
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_sentences() {
        let sentences = split_sentences("Hello. World!".to_string());
        assert_eq!(sentences.len(), 2);
    }

    #[test]
    fn test_sentence_hash_identical() {
        let hash1 = sentence_hash("Hello World".to_string());
        let hash2 = sentence_hash("hello world".to_string());
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_compress_text_removes_duplicates() {
        let text = "First. Second. First.".to_string();
        let options = CompressionOptions {
            remove_duplicates: true,
            remove_stopwords: false,
            level: 1,
            ..Default::default()
        };
        let result = compress_text(text, 0, options);
        assert_eq!(result.sentences_removed, 1);
    }
}

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
//! Semantic text chunking with paragraph-first strategy for multilingual support.

use text_splitter::TextSplitter;

/// Chunk type classification.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ChunkType {
    Definition,
    Example,
    List,
    Procedure,
    Comparison,
    General,
}

impl ChunkType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ChunkType::Definition => "definition",
            ChunkType::Example => "example",
            ChunkType::List => "list",
            ChunkType::Procedure => "procedure",
            ChunkType::Comparison => "comparison",
            ChunkType::General => "general",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "definition" => ChunkType::Definition,
            "example" => ChunkType::Example,
            "list" => ChunkType::List,
            "procedure" => ChunkType::Procedure,
            "comparison" => ChunkType::Comparison,
            _ => ChunkType::General,
        }
    }
}

/// Classify chunk by rule-based pattern matching.
#[flutter_rust_bridge::frb(sync)]
pub fn classify_chunk(text: &str) -> ChunkType {
    let text_lower = text.to_lowercase();

    // List detection
    let bullet_count = text
        .lines()
        .filter(|l| {
            let trimmed = l.trim();
            trimmed.starts_with("•")
                || trimmed.starts_with("●")
                || trimmed.starts_with("-")
                || trimmed.starts_with("*")
                || trimmed.starts_with("①")
                || trimmed.starts_with("②")
                || trimmed.starts_with("③")
                || trimmed.starts_with("④")
                || (trimmed.len() > 2
                    && trimmed.chars().next().map_or(false, |c| c.is_numeric())
                    && (trimmed.chars().nth(1) == Some('.') || trimmed.chars().nth(1) == Some(')')))
        })
        .count();
    if bullet_count >= 3 {
        return ChunkType::List;
    }

    // Definition patterns
    let definition_patterns = [
        "is defined as",
        "refers to",
        "means that",
        "is a type of",
        "can be defined as",
        "is known as",
    ];
    for pattern in definition_patterns {
        if text_lower.contains(pattern) {
            return ChunkType::Definition;
        }
    }

    // Example patterns
    let example_patterns = ["for example", "e.g.", "for instance", "such as", "example:"];
    for pattern in example_patterns {
        if text_lower.contains(pattern) {
            return ChunkType::Example;
        }
    }

    // Procedure patterns
    let procedure_patterns = [
        "step 1",
        "step 2",
        "first,",
        "then,",
        "finally,",
        "how to",
        "procedure",
        "instructions",
    ];
    let procedure_matches = procedure_patterns
        .iter()
        .filter(|p| text_lower.contains(*p))
        .count();
    if procedure_matches >= 2 {
        return ChunkType::Procedure;
    }

    // Comparison patterns
    let comparison_patterns = [
        "vs",
        "versus",
        "compared to",
        "in contrast",
        "on the other hand",
        "differs from",
        "difference between",
    ];
    for pattern in comparison_patterns {
        if text_lower.contains(pattern) {
            return ChunkType::Comparison;
        }
    }

    ChunkType::General
}

/// Semantic chunk result.
#[derive(Debug, Clone)]
pub struct SemanticChunk {
    pub index: i32,
    pub content: String,
    pub start_pos: i32,
    pub end_pos: i32,
    pub chunk_type: String,
}

/// Split text into semantic chunks using paragraph-first strategy.
#[flutter_rust_bridge::frb(sync)]
pub fn semantic_chunk(text: String, max_chars: i32) -> Vec<SemanticChunk> {
    if text.is_empty() {
        return vec![];
    }

    let max_chars_usize = max_chars.max(100) as usize;
    let mut chunks = Vec::new();
    let mut current_pos = 0i32;
    let mut chunk_index = 0i32;

    let paragraphs: Vec<&str> = text.split("\n\n").collect();

    for para in paragraphs {
        let para_trimmed = para.trim();
        if para_trimmed.is_empty() {
            continue;
        }

        if para_trimmed.len() <= max_chars_usize {
            let chunk_type = classify_chunk(para_trimmed);
            chunks.push(SemanticChunk {
                index: chunk_index,
                content: para_trimmed.to_string(),
                start_pos: current_pos,
                end_pos: current_pos + para_trimmed.len() as i32,
                chunk_type: chunk_type.as_str().to_string(),
            });
            chunk_index += 1;
            current_pos += para_trimmed.len() as i32 + 1;
        } else {
            let lines: Vec<&str> = para_trimmed.split('\n').collect();
            let mut line_buffer = String::new();

            for line in lines {
                let line_trimmed = line.trim();
                if line_trimmed.is_empty() {
                    continue;
                }

                let is_article_start = is_article_title(line_trimmed);
                let would_be_len = if line_buffer.is_empty() {
                    line_trimmed.len()
                } else {
                    line_buffer.len() + 1 + line_trimmed.len()
                };

                if would_be_len <= max_chars_usize && !is_article_start {
                    if !line_buffer.is_empty() {
                        line_buffer.push('\n');
                    }
                    line_buffer.push_str(line_trimmed);
                } else {
                    if !line_buffer.is_empty() {
                        let chunk_type = classify_chunk(&line_buffer);
                        chunks.push(SemanticChunk {
                            index: chunk_index,
                            content: line_buffer.clone(),
                            start_pos: current_pos,
                            end_pos: current_pos + line_buffer.len() as i32,
                            chunk_type: chunk_type.as_str().to_string(),
                        });
                        chunk_index += 1;
                        current_pos += line_buffer.len() as i32 + 1;
                        line_buffer.clear();
                    }

                    if line_trimmed.len() <= max_chars_usize {
                        line_buffer.push_str(line_trimmed);
                    } else {
                        let splitter = TextSplitter::new(max_chars_usize);
                        for sub_chunk in splitter.chunks(line_trimmed) {
                            let sub_chunk_trimmed = sub_chunk.trim();
                            if !sub_chunk_trimmed.is_empty() {
                                let chunk_type = classify_chunk(sub_chunk_trimmed);
                                chunks.push(SemanticChunk {
                                    index: chunk_index,
                                    content: sub_chunk_trimmed.to_string(),
                                    start_pos: current_pos,
                                    end_pos: current_pos + sub_chunk_trimmed.len() as i32,
                                    chunk_type: chunk_type.as_str().to_string(),
                                });
                                chunk_index += 1;
                                current_pos += sub_chunk_trimmed.len() as i32;
                            }
                        }
                    }
                }
            }

            if !line_buffer.is_empty() {
                let chunk_type = classify_chunk(&line_buffer);
                chunks.push(SemanticChunk {
                    index: chunk_index,
                    content: line_buffer.clone(),
                    start_pos: current_pos,
                    end_pos: current_pos + line_buffer.len() as i32,
                    chunk_type: chunk_type.as_str().to_string(),
                });
                chunk_index += 1;
                current_pos += line_buffer.len() as i32 + 2;
            }
        }
    }

    chunks
}

#[allow(dead_code)]
fn is_article_title(_line: &str) -> bool {
    false
}

fn tail_chars(text: &str, count: usize) -> String {
    if count == 0 || text.is_empty() {
        return String::new();
    }
    let total_chars = text.chars().count();
    if total_chars <= count {
        return text.to_string();
    }
    text.chars().skip(total_chars - count).collect()
}

/// Split text with overlap (API compatibility wrapper).
#[flutter_rust_bridge::frb(sync)]
pub fn semantic_chunk_with_overlap(
    text: String,
    max_chars: i32,
    overlap_chars: i32,
) -> Vec<SemanticChunk> {
    let base_chunks = semantic_chunk(text, max_chars);
    let overlap = overlap_chars.max(0) as usize;

    if overlap == 0 || base_chunks.len() <= 1 {
        return base_chunks;
    }

    let mut overlapped = Vec::with_capacity(base_chunks.len());

    for (i, base_chunk) in base_chunks.iter().enumerate() {
        let mut chunk = base_chunk.clone();
        if i > 0 {
            let prefix = tail_chars(&base_chunks[i - 1].content, overlap);
            if !prefix.is_empty() && !chunk.content.starts_with(&prefix) {
                chunk.start_pos = (chunk.start_pos - prefix.len() as i32).max(0);
                chunk.content = format!("{}\n{}", prefix, chunk.content);
                chunk.end_pos = chunk.start_pos + chunk.content.len() as i32;
            }
        }
        overlapped.push(chunk);
    }

    overlapped
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_semantic_chunk_basic() {
        let text = "This is the first sentence. This is the second sentence.";
        let chunks = semantic_chunk(text.to_string(), 50);
        assert!(!chunks.is_empty());
    }

    #[test]
    fn test_empty_text() {
        let chunks = semantic_chunk("".to_string(), 100);
        assert!(chunks.is_empty());
    }

    #[test]
    fn test_classify_chunk_definition() {
        assert_eq!(
            classify_chunk("A blockchain is defined as a distributed ledger."),
            ChunkType::Definition
        );
    }

    #[test]
    fn test_classify_chunk_list() {
        let list_text = "Features:\n• Item1\n• Item2\n• Item3";
        assert_eq!(classify_chunk(list_text), ChunkType::List);
    }

    #[test]
    fn test_chunk_type_string_conversion() {
        assert_eq!(ChunkType::Definition.as_str(), "definition");
        assert_eq!(ChunkType::from_str("definition"), ChunkType::Definition);
        assert_eq!(ChunkType::from_str("unknown"), ChunkType::General);
    }

    #[test]
    fn test_semantic_chunk_with_overlap_applies_prefix() {
        let text = "First chunk content here.\n\nSecond chunk starts here.";
        let chunks = semantic_chunk_with_overlap(text.to_string(), 500, 5);
        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0].content, "First chunk content here.");
        assert!(chunks[1].content.starts_with("here."));
        assert!(chunks[1].content.contains("Second chunk starts here."));
    }

    #[test]
    fn test_semantic_chunk_with_overlap_zero_overlap_is_noop() {
        let text = "First paragraph.\n\nSecond paragraph.";
        let plain = semantic_chunk(text.to_string(), 500);
        let overlapped = semantic_chunk_with_overlap(text.to_string(), 500, 0);
        assert_eq!(plain.len(), overlapped.len());
        assert_eq!(plain[0].content, overlapped[0].content);
        assert_eq!(plain[1].content, overlapped[1].content);
    }
}

// =============================================================================
// Structure-Aware Chunking (Markdown)
// =============================================================================

/// Structured chunk with header path for context inheritance.
#[derive(Debug, Clone)]
pub struct StructuredChunk {
    pub index: i32,
    pub content: String,
    pub header_path: String, // e.g., "# Installation > ## Windows"
    pub chunk_type: String,  // "text", "code", "table", "header"
    pub start_pos: i32,
    pub end_pos: i32,
    pub batch_id: Option<String>,
    pub batch_index: Option<i32>,
    pub batch_total: Option<i32>,
}

/// Chunking strategy for structure-aware chunking.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ChunkingStrategy {
    Recursive, // Default paragraph-based
    Markdown,  // Header-based with structure preservation
}

/// Markdown chunk with structure preservation and metadata inheritance.
///
/// - Splits by Markdown headers (#, ##, ###)
/// - Preserves code blocks (```) as single units
/// - Preserves tables (|---|) as single units
/// - Inherits header path as metadata
#[flutter_rust_bridge::frb(sync)]
pub fn markdown_chunk(text: String, max_chars: i32) -> Vec<StructuredChunk> {
    if text.is_empty() {
        return vec![];
    }

    let max_chars_usize = max_chars.max(100) as usize;
    let mut chunks = Vec::new();
    let mut current_pos = 0i32;
    let mut chunk_index = 0i32;

    // Track header hierarchy for breadcrumbs
    let mut header_stack: Vec<(i32, String)> = vec![]; // (level, header_text)

    // First, identify and protect structural blocks
    let protected = protect_structural_blocks(&text);

    // Split by headers
    let sections = split_by_headers(&protected.text);

    for section in sections {
        // Update header stack based on section header
        if let Some((level, header_text)) = &section.header {
            // Pop headers of same or lower level
            while !header_stack.is_empty() && header_stack.last().unwrap().0 >= *level {
                header_stack.pop();
            }
            header_stack.push((*level, header_text.clone()));
        }

        // Build header path
        let header_path = header_stack
            .iter()
            .map(|(_, h)| h.as_str())
            .collect::<Vec<_>>()
            .join(" > ");

        let content = section.content.trim();
        if content.is_empty() {
            continue;
        }

        // Determine chunk type (includes language for code blocks)
        let chunk_type = if section.is_code_block {
            match &section.code_language {
                Some(lang) if !lang.is_empty() => format!("code:{}", lang),
                _ => "code".to_string(),
            }
        } else if section.is_table {
            "table".to_string()
        } else if section.header.is_some() && content.lines().count() <= 2 {
            "header".to_string()
        } else {
            "text".to_string()
        };

        // Check if content needs recursive splitting
        if content.len() <= max_chars_usize {
            chunks.push(StructuredChunk {
                index: chunk_index,
                content: content.to_string(),
                header_path: header_path.clone(),
                chunk_type: chunk_type.to_string(),
                start_pos: current_pos,
                end_pos: current_pos + content.len() as i32,
                batch_id: None,
                batch_index: None,
                batch_total: None,
            });
            chunk_index += 1;
            current_pos += content.len() as i32 + 1;
        } else {
            // Structure-aware splitting for large sections
            let sub_chunks = if section.is_table {
                split_table_preserving_headers(content, max_chars_usize)
            } else if section.is_code_block {
                split_by_lines(content, max_chars_usize)
            } else {
                recursive_split(content, max_chars_usize)
            };

            // Generate batch linking metadata for code blocks
            let batch_id: Option<String> = if section.is_code_block && sub_chunks.len() > 1 {
                Some(uuid::Uuid::new_v4().to_string())
            } else {
                None
            };
            let total_chunks = sub_chunks.len();

            for (i, sub) in sub_chunks.iter().enumerate() {
                // Propagate original chunk type for structured content
                let sub_type = if section.is_code_block || section.is_table {
                    chunk_type.clone()
                } else {
                    "text".to_string()
                };

                chunks.push(StructuredChunk {
                    index: chunk_index,
                    content: sub.clone(),
                    header_path: header_path.clone(),
                    chunk_type: sub_type,
                    start_pos: current_pos,
                    end_pos: current_pos + sub.len() as i32,
                    batch_id: batch_id.clone(),
                    batch_index: batch_id.as_ref().map(|_| i as i32),
                    batch_total: batch_id.as_ref().map(|_| total_chunks as i32),
                });
                chunk_index += 1;
                current_pos += sub.len() as i32 + 1;
            }
        }
    }

    chunks
}

// =============================================================================
// Helper structures and functions
// =============================================================================

struct ProtectedText {
    text: String,
}

struct Section {
    header: Option<(i32, String)>, // (level, header_text)
    content: String,
    is_code_block: bool,
    is_table: bool,
    code_language: Option<String>, // e.g., "rust", "bash", "yaml"
}

/// Protect code blocks and tables from being split.
fn protect_structural_blocks(text: &str) -> ProtectedText {
    // For now, we'll handle structural blocks in split_by_headers
    // This function is a placeholder for more complex protection logic
    ProtectedText {
        text: text.to_string(),
    }
}

/// Split text by markdown headers while preserving code blocks and tables.
fn split_by_headers(text: &str) -> Vec<Section> {
    let mut sections: Vec<Section> = vec![];
    let mut current_content = String::new();
    let mut current_header: Option<(i32, String)> = None;
    let mut in_code_block = false;
    let mut code_block_content = String::new();
    let mut in_table = false;
    let mut table_content = String::new();

    for line in text.lines() {
        // Check for code block start/end
        if line.trim().starts_with("```") {
            if in_code_block {
                // End of code block
                code_block_content.push_str(line);
                code_block_content.push('\n');
                // Extract language from first line (e.g., ```bash -> bash)
                let lang = code_block_content.lines().next().and_then(|first_line| {
                    let trimmed = first_line.trim().trim_start_matches('`');
                    if trimmed.is_empty() {
                        None
                    } else {
                        Some(trimmed.to_string())
                    }
                });
                sections.push(Section {
                    header: None,
                    content: code_block_content.clone(),
                    is_code_block: true,
                    is_table: false,
                    code_language: lang,
                });
                code_block_content.clear();
                in_code_block = false;
            } else {
                // Start of code block - save current content first
                if !current_content.trim().is_empty() {
                    sections.push(Section {
                        header: current_header.take(),
                        content: current_content.clone(),
                        is_code_block: false,
                        is_table: false,
                        code_language: None,
                    });
                    current_content.clear();
                }
                in_code_block = true;
                code_block_content.push_str(line);
                code_block_content.push('\n');
            }
            continue;
        }

        if in_code_block {
            code_block_content.push_str(line);
            code_block_content.push('\n');
            continue;
        }

        // Check for table (lines starting with |)
        let is_table_line = line.trim().starts_with('|') && line.trim().ends_with('|');
        if is_table_line {
            if !in_table {
                // Save current content first
                if !current_content.trim().is_empty() {
                    sections.push(Section {
                        header: current_header.take(),
                        content: current_content.clone(),
                        is_code_block: false,
                        is_table: false,
                        code_language: None,
                    });
                    current_content.clear();
                }
                in_table = true;
            }
            table_content.push_str(line);
            table_content.push('\n');
            continue;
        } else if in_table {
            // End of table
            sections.push(Section {
                header: None,
                content: table_content.clone(),
                is_code_block: false,
                is_table: true,
                code_language: None,
            });
            table_content.clear();
            in_table = false;
        }

        // Check for header
        if line.starts_with('#') {
            // Save current content first
            if !current_content.trim().is_empty() {
                sections.push(Section {
                    header: current_header.take(),
                    content: current_content.clone(),
                    is_code_block: false,
                    is_table: false,
                    code_language: None,
                });
                current_content.clear();
            }

            // Parse header level
            let level = line.chars().take_while(|c| *c == '#').count() as i32;
            let header_text = line.trim_start_matches('#').trim().to_string();
            current_header = Some((level, header_text));
            current_content.push_str(line);
            current_content.push('\n');
        } else {
            current_content.push_str(line);
            current_content.push('\n');
        }
    }

    // Don't forget remaining content
    if in_table && !table_content.trim().is_empty() {
        sections.push(Section {
            header: None,
            content: table_content,
            is_code_block: false,
            is_table: true,
            code_language: None,
        });
    }
    if !current_content.trim().is_empty() {
        sections.push(Section {
            header: current_header,
            content: current_content,
            is_code_block: false,
            is_table: false,
            code_language: None,
        });
    }

    sections
}

/// Split text line-by-line, trying to fill chunks up to max_chars.
/// Preserves structure by not breaking lines (unless a single line is too long).
fn split_by_lines(text: &str, max_chars: usize) -> Vec<String> {
    let mut chunks = Vec::new();
    let mut buffer = String::new();

    for line in text.lines() {
        // If buffer + line fits, add it
        // +1 for newline
        let needed = if buffer.is_empty() {
            line.len()
        } else {
            buffer.len() + 1 + line.len()
        };

        if needed <= max_chars {
            if !buffer.is_empty() {
                buffer.push('\n');
            }
            buffer.push_str(line);
        } else {
            // Buffer full, flush it
            if !buffer.is_empty() {
                chunks.push(buffer.clone());
                buffer.clear();
            }

            // Handle current line
            if line.len() <= max_chars {
                buffer.push_str(line);
            } else {
                // Line itself is too long, must split it
                // Fallback to text splitter for this line
                let splitter = TextSplitter::new(max_chars);
                for sub in splitter.chunks(line) {
                    let sub_trimmed = sub.trim();
                    if !sub_trimmed.is_empty() {
                        chunks.push(sub_trimmed.to_string());
                    }
                }
            }
        }
    }

    if !buffer.is_empty() {
        chunks.push(buffer);
    }

    chunks
}

/// Split table while preserving headers for each chunk.
fn split_table_preserving_headers(table_content: &str, max_chars: usize) -> Vec<String> {
    let lines: Vec<&str> = table_content.lines().collect();
    if lines.len() < 3 {
        // Need at least header + separator + 1 row
        return split_by_lines(table_content, max_chars);
    }

    let header_rows = format!("{}\n{}", lines[0], lines[1]);
    let mut chunks = Vec::new();
    let mut current_chunk = header_rows.clone();

    for line in &lines[2..] {
        if current_chunk.len() + 1 + line.len() <= max_chars {
            current_chunk.push('\n');
            current_chunk.push_str(line);
        } else {
            // Flush current
            chunks.push(current_chunk);

            // Start new with header
            current_chunk = header_rows.clone();

            // Check if line fits in new chunk
            if current_chunk.len() + 1 + line.len() <= max_chars {
                current_chunk.push('\n');
                current_chunk.push_str(line);
            } else {
                // Line too huge even with fresh header.
                // Force add it contextually
                current_chunk.push('\n');
                current_chunk.push_str(line);
            }
        }
    }

    if !current_chunk.is_empty() && current_chunk != header_rows {
        chunks.push(current_chunk);
    }

    chunks
}

/// Recursively split large text into smaller chunks.
fn recursive_split(text: &str, max_chars: usize) -> Vec<String> {
    if text.len() <= max_chars {
        return vec![text.to_string()];
    }

    let mut chunks = Vec::new();

    // Try splitting by paragraphs first
    let paragraphs: Vec<&str> = text.split("\n\n").collect();
    if paragraphs.len() > 1 {
        let mut buffer = String::new();
        for para in paragraphs {
            if buffer.len() + para.len() + 2 <= max_chars {
                if !buffer.is_empty() {
                    buffer.push_str("\n\n");
                }
                buffer.push_str(para);
            } else {
                if !buffer.is_empty() {
                    chunks.push(buffer.clone());
                    buffer.clear();
                }
                if para.len() <= max_chars {
                    buffer.push_str(para);
                } else {
                    // Paragraph too large, split by sentences
                    chunks.extend(split_by_sentences(para, max_chars));
                }
            }
        }
        if !buffer.is_empty() {
            chunks.push(buffer);
        }
    } else {
        // Single paragraph, split by sentences
        chunks.extend(split_by_sentences(text, max_chars));
    }

    chunks
}

/// Split text by sentences.
fn split_by_sentences(text: &str, max_chars: usize) -> Vec<String> {
    let mut chunks = Vec::new();
    let mut buffer = String::new();

    // Simple sentence splitting by . ! ?
    for part in text.split_inclusive(|c| c == '.' || c == '!' || c == '?') {
        if buffer.len() + part.len() <= max_chars {
            buffer.push_str(part);
        } else {
            if !buffer.is_empty() {
                chunks.push(buffer.trim().to_string());
                buffer.clear();
            }
            if part.len() <= max_chars {
                buffer.push_str(part);
            } else {
                // Sentence too large, just split by chars
                let splitter = TextSplitter::new(max_chars);
                for sub in splitter.chunks(part) {
                    chunks.push(sub.trim().to_string());
                }
            }
        }
    }

    if !buffer.is_empty() {
        chunks.push(buffer.trim().to_string());
    }

    chunks.into_iter().filter(|s| !s.is_empty()).collect()
}

#[cfg(test)]
mod markdown_tests {
    use super::*;

    #[test]
    fn test_markdown_chunk_basic() {
        let text = "# Title\n\nSome content here.\n\n## Subtitle\n\nMore content.";
        let chunks = markdown_chunk(text.to_string(), 500);
        assert!(!chunks.is_empty());
        // Check header path inheritance
        let last_chunk = chunks.last().unwrap();
        assert!(last_chunk.header_path.contains("Title"));
    }

    #[test]
    fn test_code_block_preservation() {
        let text = "# Code Example\n\n```rust\nfn main() {\n    println!(\"Hello\");\n}\n```\n\nText after code.";
        let chunks = markdown_chunk(text.to_string(), 500);
        // Find code chunk (chunk_type is "code" or "code:language")
        let code_chunk = chunks.iter().find(|c| c.chunk_type.starts_with("code"));
        assert!(code_chunk.is_some());
        let chunk = code_chunk.unwrap();
        assert!(chunk.content.contains("fn main()"));
        // Verify language detection
        assert!(chunk.chunk_type == "code:rust" || chunk.chunk_type == "code");
    }

    #[test]
    fn test_table_preservation() {
        let text = "# Data\n\n| Name | Value |\n|------|-------|\n| A | 1 |\n| B | 2 |\n\nEnd.";
        let chunks = markdown_chunk(text.to_string(), 500);
        // Find table chunk
        let table_chunk = chunks.iter().find(|c| c.chunk_type == "table");
        assert!(table_chunk.is_some());
        assert!(table_chunk.unwrap().content.contains("|------|"));
    }

    #[test]
    fn test_header_path_inheritance() {
        let text =
            "# Main\n\nIntro.\n\n## Section A\n\nContent A.\n\n### Subsection\n\nDeep content.";
        let chunks = markdown_chunk(text.to_string(), 500);
        // Find deepest chunk
        let deep_chunk = chunks.iter().find(|c| c.content.contains("Deep content"));
        assert!(deep_chunk.is_some());
        assert!(deep_chunk.unwrap().header_path.contains("Main"));
        assert!(deep_chunk.unwrap().header_path.contains("Section A"));
        assert!(deep_chunk.unwrap().header_path.contains("Subsection"));
    }

    #[test]
    fn test_large_code_block_splitting() {
        // Create code block larger than max_chars (100 minimum enforced)
        // We need content > 100 chars.
        // 6 lines of ~20 chars = 120 chars.
        let code_body = "let a = 10000000000;\nlet b = 20000000000;\nlet c = 30000000000;\nlet d = 40000000000;\nlet e = 50000000000;\nlet f = 60000000000;";
        let text = format!("```rust\n{}\n```", code_body);

        // max_chars=100 (clamped internally if we pass less, but we pass 100 to be explicit)
        let chunks = markdown_chunk(text, 100);

        assert!(chunks.len() >= 2);
        for chunk in &chunks {
            assert!(chunk.chunk_type == "code:rust");
            // Verify no split mid-line (simple check: no partial variable names if lines are atomic)
            assert!(!chunk.content.contains("let a = 10000000000;let"));
        }
    }

    #[test]
    fn test_large_table_splitting() {
        // Table needs to be > 100 chars.
        // Header: | Col1 | Col2 |\n|---|---| (25 chars)
        // Rows: | Val1 | Val2 | (15 chars)
        // Need > 100 total. 25 + 15*6 = 115.
        let header = "| Col1 | Col2 |\n|---|---|";
        let row = "| Val1 | Val2 |";
        let text = format!(
            "{}\n{}\n{}\n{}\n{}\n{}\n{}",
            header, row, row, row, row, row, row
        );

        let chunks = markdown_chunk(text, 100);

        for (i, chunk) in chunks.iter().enumerate() {
            assert_eq!(chunk.chunk_type, "table");
            // EVERY chunk must start with header
            assert!(
                chunk.content.starts_with("| Col1 | Col2 |"),
                "Chunk {} missing header",
                i
            );
            assert!(
                chunk.content.contains("|---|---|"),
                "Chunk {} missing separator",
                i
            );
        }
    }

    #[test]
    fn test_code_block_linking() {
        // Need > 100 chars to force split (min_chars clamped to 100)
        let code_body = "let a = 10000000000;\nlet b = 20000000000;\nlet c = 30000000000;\nlet d = 40000000000;\nlet e = 50000000000;\nlet f = 60000000000;";
        let text = format!("```\n{}\n```", code_body);
        // Force split with max_chars=100
        let chunks = markdown_chunk(text, 100);

        assert!(chunks.len() >= 2);

        // Check first chunk has linking info
        let first_chunk = &chunks[0];
        assert!(first_chunk.batch_id.is_some());
        assert!(first_chunk.batch_index.is_some());
        assert!(first_chunk.batch_total.is_some());

        let batch_id = first_chunk.batch_id.as_ref().unwrap();
        let total = first_chunk.batch_total.unwrap();

        // Check all chunks share batch_id and have correct total
        for (i, chunk) in chunks.iter().enumerate() {
            assert_eq!(chunk.batch_id.as_ref().unwrap(), batch_id);
            assert_eq!(chunk.batch_total.unwrap(), total);
            assert_eq!(chunk.batch_index.unwrap(), i as i32);
        }
    }
}

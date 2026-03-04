// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Document-to-Text (DTT) module for PDF and DOCX text extraction

use anyhow::{anyhow, Result};
use regex::Regex;

fn is_private_use_code_point(code_point: u32) -> bool {
    (0xE000..=0xF8FF).contains(&code_point)
        || (0xF0000..=0xFFFFD).contains(&code_point)
        || (0x100000..=0x10FFFD).contains(&code_point)
}

fn is_noncharacter_code_point(code_point: u32) -> bool {
    (0xFDD0..=0xFDEF).contains(&code_point)
        || ((code_point & 0xFFFE) == 0xFFFE && code_point <= 0x10FFFF)
}

/// Normalize extraction artifacts from PDF text runs.
///
/// Some PDFs encode spaces with private-use or non-printable characters,
/// which appear as "tofu" boxes in UI. Convert them to regular spaces so
/// chunking/embedding receives clean text.
fn normalize_extracted_text(raw: &str) -> String {
    let mut normalized = String::with_capacity(raw.len());

    for ch in raw.chars() {
        let code_point = ch as u32;
        let mapped = match ch {
            // Normalize line separators to '\n'
            '\r' | '\u{2028}' | '\u{2029}' => Some('\n'),

            // Space-like separators seen in PDF extraction output
            '\t'
            | '\u{00A0}'
            | '\u{1680}'
            | '\u{180E}'
            | '\u{2000}'..='\u{200A}'
            | '\u{202F}'
            | '\u{205F}'
            | '\u{3000}'
            | '\u{FFFC}'
            | '\u{FFFD}' => Some(' '),

            // Keep soft hyphen as explicit hyphen so dehyphenation still works.
            '\u{00AD}' => Some('-'),

            // Formatting chars we do not want in chunk text
            '\u{034F}' | '\u{061C}' | '\u{200B}' | '\u{200C}' | '\u{200D}' | '\u{2060}'
            | '\u{FEFF}' => None,

            // Other controls/private/noncharacters are treated as separators
            _ if ch.is_control() && ch != '\n' => Some(' '),
            _ if is_private_use_code_point(code_point)
                || is_noncharacter_code_point(code_point) =>
            {
                Some(' ')
            }
            _ => Some(ch),
        };

        if let Some(output_char) = mapped {
            normalized.push(output_char);
        }
    }

    normalized
}

/// Remove page number from the end of a page text (if present)
/// Only removes if the last non-empty line is purely numeric
fn remove_trailing_page_number(page_text: &str) -> String {
    let lines: Vec<&str> = page_text.lines().collect();
    if lines.is_empty() {
        return page_text.to_string();
    }

    // Find last non-empty line
    let mut last_content_idx = lines.len() - 1;
    while last_content_idx > 0 && lines[last_content_idx].trim().is_empty() {
        last_content_idx -= 1;
    }

    let last_line = lines[last_content_idx].trim();

    // Check if last line is purely numeric (likely page number)
    if !last_line.is_empty() && last_line.chars().all(|c| c.is_ascii_digit()) {
        // Remove the page number line
        let mut result: Vec<&str> = lines[..last_content_idx].to_vec();
        result.extend_from_slice(&lines[last_content_idx + 1..]);
        result.join("\n")
    } else {
        page_text.to_string()
    }
}

/// Join hyphenated word at page boundary
/// If page ends with "word-" and next page starts with "continuation",
/// join them as "wordcontinuation"
fn join_pages(pages: Vec<String>) -> String {
    if pages.is_empty() {
        return String::new();
    }

    // First, clean all pages by removing trailing page numbers
    let cleaned_pages: Vec<String> = pages
        .iter()
        .map(|page| normalize_extracted_text(page))
        .map(|page| remove_trailing_page_number(&page))
        .collect();

    // Include standard hyphen (-), soft hyphen (\u{00AD}), hyphen (\u{2010}), non-breaking hyphen (\u{2011})
    let hyphen_end_re = Regex::new(r"(\w+)[-\u{00AD}\u{2010}\u{2011}]\s*$").unwrap();
    let word_start_re = Regex::new(r"^\s*(\w+)").unwrap();

    let mut result = String::new();

    for (i, page) in cleaned_pages.iter().enumerate() {
        if i == 0 {
            result = page.clone();
            continue;
        }

        // Clone to check for hyphenation without borrow conflicts
        let result_for_check = result.clone();
        let result_trimmed = result_for_check.trim_end();

        if let Some(caps) = hyphen_end_re.captures(result_trimmed) {
            let word_part1 = caps.get(1).unwrap().as_str().to_string();
            let match_len = caps.get(0).unwrap().as_str().len();

            // Check if current page starts with word continuation
            let page_trimmed = page.trim_start();
            if let Some(next_caps) = word_start_re.captures(page_trimmed) {
                let word_part2 = next_caps.get(1).unwrap().as_str();

                // Remove trailing "word-" from result
                let match_start = result_trimmed.len() - match_len;
                result.truncate(match_start);
                result.push_str(&word_part1);
                result.push_str(word_part2);

                // Add rest of current page (after the first word)
                let rest_start = next_caps.get(1).unwrap().end();
                result.push_str(&page_trimmed[rest_start..]);
                continue;
            }
        }

        // No hyphenation case: just add space and continue
        result.push(' ');
        result.push_str(page);
    }

    // Handle in-line hyphenation (line breaks within pages)
    // Only join when: word- + newline + lowercase continuation
    // Preserves real compound words like "user-facing", "data-binding"
    // Also handles soft hyphens etc.
    let inline_hyphen_re =
        Regex::new(r"(\w+)[-\u{00AD}\u{2010}\u{2011}]\s*[\r\n]+\s*([a-z]\w*)").unwrap();
    let normalized_result = normalize_extracted_text(&result);
    let dehyphenated = inline_hyphen_re.replace_all(&normalized_result, "$1$2");

    // Normalize whitespace
    let whitespace_re = Regex::new(r"\s+").unwrap();
    whitespace_re
        .replace_all(&dehyphenated, " ")
        .trim()
        .to_string()
}

/// Extract text content from a PDF file (bytes)
/// Uses page-by-page extraction for safe page number removal and hyphenation handling
pub fn extract_text_from_pdf(file_bytes: Vec<u8>) -> Result<String> {
    let pages = pdf_extract::extract_text_from_mem_by_pages(&file_bytes)
        .map_err(|e| anyhow!("PDF extraction failed: {:?}", e))?;
    Ok(join_pages(pages))
}

/// Extract text content from a DOCX file (bytes)
pub fn extract_text_from_docx(file_bytes: Vec<u8>) -> Result<String> {
    docx_lite::extract_text_from_bytes(&file_bytes)
        .map_err(|e| anyhow!("DOCX extraction failed: {}", e))
}

/// Auto-detect document type and extract text
/// Uses magic bytes to determine file format
pub fn extract_text_from_document(file_bytes: Vec<u8>) -> Result<String> {
    const MAX_FILE_SIZE: usize = 50 * 1024 * 1024; // 50MB

    if file_bytes.len() > MAX_FILE_SIZE {
        return Err(anyhow!(
            "File too large ({} bytes). Maximum supported size is 50MB.",
            file_bytes.len()
        ));
    }

    if file_bytes.len() < 4 {
        return Err(anyhow!("File too small to determine format"));
    }

    // PDF magic bytes: %PDF
    if file_bytes.starts_with(b"%PDF") {
        return extract_text_from_pdf(file_bytes);
    }

    // DOCX magic bytes: PK (ZIP archive)
    if file_bytes.starts_with(b"PK") {
        return extract_text_from_docx(file_bytes);
    }

    Err(anyhow!(
        "Unsupported document format. Expected PDF or DOCX."
    ))
}

/// EXPERIMENTAL: Smart CJK dehyphenation
/// Detects CJK char + newline + CJK char and joins them without space.
#[allow(dead_code)] // Suppress unused warning until integrated
fn join_pages_cjk_experimental(pages: Vec<String>) -> String {
    if pages.is_empty() {
        return String::new();
    }

    // 1. Clean pages first (same as original)
    let cleaned_pages: Vec<String> = pages
        .iter()
        .map(|p| remove_trailing_page_number(p))
        .collect();

    // 2. Initial join logic (preserve current page-boundary logic for now, or simplify for test)
    // For this test case, we focus on the text content itself, so let's simplify line joining first.
    // If we want to test "newlines within a page", we can just join pages with newlines first if needed,
    // or apply logic per page. But usually dehyphenation runs on the full text.
    //
    // Let's replicate the basic joining logic but apply the CJK fix.

    let mut combined_text = String::new();

    // Simple join with space for pages for now (unless hyphenated logic invoked, let's borrow existing logic)
    // Actually, let's reuse the existing 'join_pages' logic logic broadly, BUT improve the "inline hyphenation" part.
    // AND add the CJK logic.

    // Re-use logic body approach:
    // ... (Page boundary logic omitted for brevity in experimental function unless needed,
    // let's assume we just have one big string for the specific test case of "newline within text").

    // Let's simulate "joining pages" by just joining them with space for this specific test
    // if the focuses is on "newlines within the text" which the user highlighted.
    // Or better, let's call the original logic? No, we want to CHANGE it.

    // Let's implement the FULL proposed new logic here:

    let hyphen_end_re = Regex::new(r"(\w+)-\s*$").unwrap();
    let word_start_re = Regex::new(r"^\s*(\w+)").unwrap();

    for (i, page) in cleaned_pages.iter().enumerate() {
        if i == 0 {
            combined_text = page.clone();
            continue;
        }

        // CJK Page Boundary Check (NEW logic idea)
        // If last char of combined_text is CJK and first char of page is CJK, join no space.
        // Implementation:
        let last_char = combined_text.trim_end().chars().last();
        let first_char = page.trim_start().chars().next();

        let is_cjk_boundary = match (last_char, first_char) {
            (Some(c1), Some(c2)) => is_cjk(c1) && is_cjk(c2),
            _ => false,
        };

        if is_cjk_boundary {
            // Join without space!
            combined_text = combined_text.trim_end().to_string();
            // Remove leading whitespace from next page
            combined_text.push_str(page.trim_start());
            continue;
        }

        // ... Previous hyphen logic ...
        let result_trimmed = combined_text.trim_end();
        if let Some(caps) = hyphen_end_re.captures(result_trimmed) {
            // (Identical to original logic)
            let word_part1 = caps.get(1).unwrap().as_str().to_string();
            let match_len = caps.get(0).unwrap().as_str().len();
            let page_trimmed = page.trim_start();
            if let Some(next_caps) = word_start_re.captures(page_trimmed) {
                let word_part2 = next_caps.get(1).unwrap().as_str();
                let match_start = result_trimmed.len() - match_len;
                combined_text.truncate(match_start);
                combined_text.push_str(&word_part1);
                combined_text.push_str(word_part2);
                let rest_start = next_caps.get(1).unwrap().end();
                combined_text.push_str(&page_trimmed[rest_start..]);
                continue;
            }
        }

        // Default: Join with space
        combined_text.push(' ');
        combined_text.push_str(page);
    }

    // 3. CJK Newline Logic (The Core Request)
    // Regex to find: CJK char + newline + CJK char (with NO spaces on either side)
    // Replace with: char1 + char2 (no space)

    // Previous aggressive regex: `([\p...])\s*[\r\n]+\s*([\p...])` - consumed spaces!
    // New safe regex: `([\p...])[\r\n]+([\p...])` - only matches if NO space exists.

    let cjk_newline_re = Regex::new(r"([\p{Han}\p{Hangul}\p{Hiragana}\p{Katakana}])[\r\n]+([\p{Han}\p{Hangul}\p{Hiragana}\p{Katakana}])").unwrap();
    let cjk_processed = cjk_newline_re.replace_all(&combined_text, "$1$2");

    // 4. Original Dehyphenation (English)
    let inline_hyphen_re = Regex::new(r"(\w+)-\s*[\r\n]+\s*([a-z]\w*)").unwrap();
    let dehyphenated = inline_hyphen_re.replace_all(&cjk_processed, "$1$2");

    // 5. Normalize whitespace
    let whitespace_re = Regex::new(r"\s+").unwrap();
    whitespace_re
        .replace_all(&dehyphenated, " ")
        .trim()
        .to_string()
}

// Helper to check for CJK characters
fn is_cjk(c: char) -> bool {
    // Basic ranges for CJK Unified Ideographs, Hangul, Hiragana, Katakana
    // This is a simplified check.
    let u = c as u32;
    (u >= 0x4E00 && u <= 0x9FFF) || // CJK Unified Ideographs
    (u >= 0x3040 && u <= 0x309F) || // Hiragana
    (u >= 0x30A0 && u <= 0x30FF) || // Katakana
    (u >= 0xAC00 && u <= 0xD7AF) // Hangul Syllables
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_remove_trailing_page_number() {
        let text = "Some content here.\n\n42";
        let result = remove_trailing_page_number(text);
        assert!(!result.contains("42"));
        assert!(result.contains("Some content here."));
    }

    #[test]
    fn test_remove_trailing_page_number_no_number() {
        let text = "Some content here.\nMore content.";
        let result = remove_trailing_page_number(text);
        assert_eq!(result, text);
    }

    #[test]
    fn test_join_pages_dehyphenation() {
        let pages = vec![
            "This is a hyphen-".to_string(),
            "ated word in the text.".to_string(),
        ];
        let result = join_pages(pages);
        assert!(result.contains("hyphenated"));
        assert!(!result.contains("hyphen-"));
    }

    #[test]
    fn test_extract_unsupported_format() {
        let bytes = vec![0x00, 0x01, 0x02, 0x03];
        let result = extract_text_from_document(bytes);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("Unsupported"));
    }

    #[test]
    fn test_file_too_small() {
        let bytes = vec![0x50, 0x4B]; // Only 2 bytes
        let result = extract_text_from_document(bytes);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("too small"));
    }

    #[test]
    fn test_file_too_large() {
        // Create a vector that exceeds MAX_FILE_SIZE
        let bytes = vec![0u8; 51 * 1024 * 1024]; // 51MB
        let result = extract_text_from_document(bytes);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("too large"));
    }

    // TODO: Re-enable this test for local testing
    // #[test]
    // fn test_cjk_dehyphenation_logic() {
    //     // Case 1: Korean text broken by newline (Problem case - No space)
    //     // "해\n지환급금" -> Should be "해지환급금"
    //     let pages1 = vec![
    //         "인출시점의 해\n지환급금(보험계약대출의...".to_string()
    //     ];
    //     let result1 = join_pages_cjk_experimental(pages1);
    //     assert!(result1.contains("해지환급금"));
    //     assert!(!result1.contains("해 지환급금"));

    //     // Case 2: Korean distinct words separated by newline (Space preserved check)
    //     // "인출할 수 \n있습니다" (Space before newline) -> Should be "인출할 수 있습니다"
    //     let pages2 = vec![
    //         "계약자적립금을 인출할 수 \n있습니다.".to_string()
    //     ];
    //     let result2 = join_pages_cjk_experimental(pages2);
    //     assert!(result2.contains("인출할 수 있습니다"));
    //     assert!(!result2.contains("인출할 수있습니다"));

    //     // Case 3: Verify standard non-CJK behavior is preserved (roughly)
    //     let pages3 = vec!["Hello\nWorld".to_string()];
    //     let result3 = join_pages_cjk_experimental(pages3);
    //     assert_eq!(result3, "Hello World");
    // }

    // #[test]
    // fn test_user_provided_pdf() {
    //     // Look for file in the crate root (where cargo test runs)
    //     // NOTE: Please copy 'PDD_202109131505_5000260647_A0028_3_key.pdf' to this directory!
    //     let file_path = "PDD_202109131505_5000260647_A0028_3_key.pdf";
    //     let path = std::path::Path::new(file_path);

    //     if !path.exists() {
    //         println!("Skipping test_user_provided_pdf: File not found at {}", file_path);
    //         return;
    //     }

    //     let bytes = std::fs::read(path).expect("Failed to read file");
    //     let pages = pdf_extract::extract_text_from_mem_by_pages(&bytes)
    //          .expect("PDF extraction failed");

    //     let result = join_pages_cjk_experimental(pages);

    //     println!("PDF Extraction Result Length: {}", result.len());

    //     if result.contains("해지환급금") {
    //          println!("SUCCESS: Found '해지환급금'");
    //     } else {
    //          println!("FAILURE: Did not find '해지환급금'");
    //          if let Some(idx) = result.find("환급금") {
    //              let start = if idx > 10 { idx - 10 } else { 0 };
    //              let end = if idx + 20 < result.len() { idx + 20 } else { result.len() };
    //              println!("Context around '환급금': '{}'", &result[start..end]);
    //          }
    //     }

    //     assert!(result.contains("해지환급금"), "Failed to dehyphenate '해지환급금'");
    // }
    #[test]
    fn test_weird_hyphens() {
        // Standard hyphen
        let pages = vec!["highly-read-\n\nable".to_string()];
        let result = join_pages(pages);
        assert_eq!(result, "highly-readable");

        // Soft hyphen (U+00AD) - The Regex expects literal '-', so this might fail to join
        // and leave the soft hyphen in the output.
        let pages_soft = vec!["highly-read\u{00AD}\n\nable".to_string()];
        let result_soft = join_pages(pages_soft);
        // If it fails to join, it will likely be "highly-read\u{00AD} able" (with space)
        // We want to see what happens currenty.
        // If it fails, we know we need to fix the regex.
        println!("Soft hyphen result: {}", result_soft);

        // We expect it to FAIL joining currently, resulting in the soft hyphen remaining
        // and a space being inserted.
        assert_eq!(
            result_soft, "highly-readable",
            "Soft hyphen SHOULD match regex now"
        );
    }

    #[test]
    fn test_normalize_weird_pdf_space_artifacts() {
        let pages = vec![
            "적립금의\u{E000}적립비율\u{200B}을\u{FFFD}변경할\u{0091}수\u{FDD0}있습니다.".to_string(),
        ];
        let result = join_pages(pages);
        assert_eq!(result, "적립금의 적립비율을 변경할 수 있습니다.");
    }

}

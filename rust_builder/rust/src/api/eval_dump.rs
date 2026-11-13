// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Test-only dumps for the search evaluation (docs/milestones.md F1).
// Nothing here is compiled into the library: the module is `#[cfg(test)]`
// and every test is `#[ignore]`, so `cargo test` skips them unless asked.
//
// Run:
//   F1_DUMP_IN=in.jsonl F1_DUMP_OUT=out.jsonl \
//     cargo test --lib eval_dump::dump_bm25_tokens -- --ignored --test-threads=1
//
// Input lines: {"id": "...", "text": "..."}. Output lines: {"id": "...",
// "tokens": [...]} using the engine's own `tokenize_for_bm25`, so overlap
// counts follow whatever the engine does (stemming, Hangul bigrams).

use std::io::{BufRead, Write};

use super::bm25_search::tokenize_for_bm25;

#[test]
#[ignore]
fn dump_bm25_tokens() {
    let input = std::env::var("F1_DUMP_IN").expect("F1_DUMP_IN");
    let output = std::env::var("F1_DUMP_OUT").expect("F1_DUMP_OUT");
    let reader = std::io::BufReader::new(std::fs::File::open(&input).expect("open input"));
    let mut writer = std::io::BufWriter::new(std::fs::File::create(&output).expect("create output"));
    let mut count = 0usize;
    for line in reader.lines() {
        let line = line.expect("read line");
        if line.trim().is_empty() {
            continue;
        }
        let row: serde_json::Value = serde_json::from_str(&line).expect("json line");
        let id = row["id"].as_str().expect("id").to_string();
        let text = row["text"].as_str().expect("text");
        let tokens = tokenize_for_bm25(text);
        let out = serde_json::json!({ "id": id, "tokens": tokens });
        writeln!(writer, "{out}").expect("write");
        count += 1;
    }
    writer.flush().expect("flush");
    println!("F1_DUMP_BM25_TOKENS rows={count} out={output}");
}

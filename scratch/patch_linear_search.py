import sys
import re

def main():
    with open("rust_builder/rust/src/api/source_rag.rs", "r") as f:
        content = f.read()

    # Step 1: Update the SELECT queries in search_chunks_linear_in_collection
    query_pattern = r'conn\s*\.prepare\(\s*"SELECT c\.id, c\.source_id, c\.chunk_index, c\.content, COALESCE\(c\.chunk_type, \'general\'\), c\.embedding, c\.embedding_i8, s\.metadata\s*FROM chunks c\s*JOIN sources s ON c\.source_id = s\.id\s*WHERE c\.collection_id = \?1\s*AND COALESCE\(s\.status, \'completed\'\) = \'completed\'",\s*\)\s*\{\s*Ok\(stmt\) => stmt,\s*Err\(_\) => conn\s*\.prepare\(\s*"SELECT c\.id, c\.source_id, c\.chunk_index, c\.content, COALESCE\(c\.chunk_type, \'general\'\), c\.embedding, NULL AS embedding_i8, s\.metadata\s*FROM chunks c\s*JOIN sources s ON c\.source_id = s\.id\s*WHERE c\.collection_id = \?1\s*AND COALESCE\(s\.status, \'completed\'\) = \'completed\'",\s*\)'

    new_query = '''conn.prepare(
        "SELECT c.id, c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), c.embedding, c.embedding_i8, s.metadata, c.mmap_id
         FROM chunks c
         JOIN sources s ON c.source_id = s.id
         WHERE c.collection_id = ?1
           AND COALESCE(s.status, 'completed') = 'completed'",
    ) {
        Ok(stmt) => stmt,
        Err(_) => conn
            .prepare(
                "SELECT c.id, c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), c.embedding, NULL AS embedding_i8, s.metadata, c.mmap_id
                 FROM chunks c
                 JOIN sources s ON c.source_id = s.id
                 WHERE c.collection_id = ?1
                   AND COALESCE(s.status, 'completed') = 'completed'",
            )'''
    content = re.sub(query_pattern, new_query, content, flags=re.MULTILINE)

    # Step 2: Update the query_map
    query_map_pattern = r'row\.get\(7\)\?,\s*\)\)\s*\}\)'
    new_query_map = r'row.get(7)?,\n                row.get::<_, Option<i64>>(8).unwrap_or(None),\n            ))\n        })'
    content = re.sub(query_map_pattern, new_query_map, content)

    # Step 3: Update the for row in rows tuple destructuring
    for_loop_pattern = r'let \(\s*id,\s*source_id,\s*chunk_index,\s*content,\s*chunk_type,\s*embedding_blob,\s*embedding_i8_blob,\s*metadata,\s*\):\s*\(\s*i64,\s*i64,\s*i32,\s*String,\s*String,\s*Vec<u8>,\s*Option<Vec<u8>>,\s*Option<String>,\s*\)\s*=\s*row\.map_err\(\|e\| RagError::DatabaseError\(e\.to_string\(\)\)\)\?;'
    new_for_loop = '''let (
            id,
            source_id,
            chunk_index,
            content,
            chunk_type,
            embedding_blob,
            mut embedding_i8_blob,
            metadata,
            mmap_id,
        ): (
            i64,
            i64,
            i32,
            String,
            String,
            Vec<u8>,
            Option<Vec<u8>>,
            Option<String>,
            Option<i64>,
        ) = row.map_err(|e| RagError::DatabaseError(e.to_string()))?;

        if let Some(mid) = mmap_id {
            if mid > 0 && embedding_i8_blob.as_ref().map_or(true, |b| b.is_empty()) {
                let store = crate::api::mmap_store::MMAP_STORE.read().unwrap();
                if let Some(s) = store.as_ref() {
                    if let Some(data) = s.get(mid as usize) {
                        embedding_i8_blob = Some(data.to_vec());
                    }
                }
            }
        }'''
    content = re.sub(for_loop_pattern, new_for_loop, content)

    # Step 4: Add !qblob.is_empty() to the condition
    condition_pattern = r'\} else if \(qblob\.len\(\) == query_i8\.len\(\) \|\| qblob\.len\(\) % 36 == 0\) && query_i8_norm > 0\.0 \{'
    new_condition = r'} else if !qblob.is_empty() && (qblob.len() == query_i8.len() || qblob.len() % 36 == 0) && query_i8_norm > 0.0 {'
    content = re.sub(condition_pattern, new_condition, content)

    with open("rust_builder/rust/src/api/source_rag.rs", "w") as f:
        f.write(content)

    print("Patched linear search")

if __name__ == "__main__":
    main()

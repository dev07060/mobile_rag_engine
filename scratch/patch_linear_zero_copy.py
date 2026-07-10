import sys
import re

def main():
    with open("rust_builder/rust/src/api/source_rag.rs", "r") as f:
        content = f.read()

    # Step 1: Replace the logic from `if let Some(mid) = mmap_id {` down to `let similarity = ...`
    pattern = r'if let Some\(mid\) = mmap_id \{.*?let similarity = if let Some\(qblob\) = embedding_i8_blob\.as_deref\(\) \{'

    new_code = '''#[cfg(feature = "vector_quant_i8")]
        let mut sim_opt = None;

        #[cfg(feature = "vector_quant_i8")]
        if let Some(mid) = mmap_id {
            if mid > 0 && embedding_i8_blob.as_ref().map_or(true, |b| b.is_empty()) {
                let store = crate::api::mmap_store::MMAP_STORE.read().unwrap();
                if let Some(s) = store.as_ref() {
                    if let Some(data) = s.get(mid as usize) {
                        let qblob = data;
                        if !qblob.is_empty() && qblob[0] == 0x02 {
                            sim_opt = Some(cosine_similarity_vabq(&query_vabq, qblob) as f64);
                        } else if qblob.len() >= query_i8.len() + 4 && query_i8_norm > 0.0 {
                            sim_opt = Some(crate::api::vector_quant::cosine_with_query_norm_i8_blob(&query_i8, query_i8_norm, &qblob[4..]) as f64);
                        } else if !qblob.is_empty() && (qblob.len() == query_i8.len() || qblob.len() % 36 == 0) && query_i8_norm > 0.0 {
                            sim_opt = Some(cosine_similarity_q8(&query_q8, qblob, &query_i8, query_i8_norm) as f64);
                        }
                    }
                }
            }
        }

        #[cfg(not(feature = "vector_quant_i8"))]
        let _ = &embedding_i8_blob;
        #[cfg(not(feature = "vector_quant_i8"))]
        let _ = &mmap_id;

        #[cfg(feature = "vector_quant_i8")]
        let similarity = if let Some(sim) = sim_opt {
            sim
        } else if let Some(qblob) = embedding_i8_blob.as_deref() {'''

    content = re.sub(pattern, new_code, content, flags=re.DOTALL)

    with open("rust_builder/rust/src/api/source_rag.rs", "w") as f:
        f.write(content)

if __name__ == "__main__":
    main()

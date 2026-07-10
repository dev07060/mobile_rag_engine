import re
import subprocess

# Restore from git
subprocess.run(["git", "checkout", "rust_builder/rust/src/api/custom_hnsw.rs"])

with open("rust_builder/rust/src/api/custom_hnsw.rs", "r") as f:
    content = f.read()

# 1. Add vector_quant usage
if "use crate::api::vector_quant::" not in content:
    content = content.replace("use std::io::Cursor;", "use std::io::Cursor;\nuse crate::api::vector_quant::{QueryVABQ, cosine_similarity_vabq, quantize_f32_to_vabq};")

# HnswBuilder remains Vec<f32> entirely!
# So Node struct, search_layer, insert all stay F32.

# 2. save_to_file logic: Quantize on the fly
content = content.replace("let dim = if self.nodes.is_empty() { 0 } else { self.nodes[0].vector.len() };",
                          "let f32_dim = if self.nodes.is_empty() { 0 } else { self.nodes[0].vector.len() };\n            let blob_len = if f32_dim > 0 { quantize_f32_to_vabq(&self.nodes[0].vector).0.len() } else { 0 };")
content = content.replace("writer.write_u32::<LittleEndian>(dim as u32)?;",
                          "writer.write_u32::<LittleEndian>(blob_len as u32)?;")
content = content.replace("let mut node_size = 8 + 1 + dim * 4;",
                          "let mut node_size = 8 + 1 + blob_len;")

write_vabq_code = """
                    let (vabq_blob, _scale) = quantize_f32_to_vabq(&node.vector);
                    writer.write_all(&vabq_blob)?;
"""
content = content.replace("for &v in &node.vector {\n                        writer.write_f32::<LittleEndian>(v)?;\n                    }",
                          write_vabq_code.strip())

# 3. MmapHnswSearcher
content = content.replace("dim: u32,", "blob_len: u32,")
content = content.replace("let dim = cursor.read_u32::<LittleEndian>()?;", "let blob_len = cursor.read_u32::<LittleEndian>()?;")
content = content.replace("dim,", "blob_len,")
content = content.replace("fn get_node_vector(&self, offset: usize) -> &[f32] {",
                          "fn get_node_vector(&self, offset: usize) -> &[u8] {")
content = content.replace("let bytes = &self.mmap[vec_offset..vec_offset + (self.dim as usize) * 4];",
                          "let bytes = &self.mmap[vec_offset..vec_offset + (self.blob_len as usize)];")
content = content.replace("unsafe { std::slice::from_raw_parts(bytes.as_ptr() as *const f32, self.dim as usize) }",
                          "bytes")

# search signature
content = content.replace("pub fn search(&self, query: &[f32], ef: usize) -> Vec<(i64, f32)> {",
                          "pub fn search(&self, query_vabq: &QueryVABQ, ef: usize) -> Vec<(i64, f32)> {")
content = content.replace("crate::api::custom_hnsw::cosine_distance(query, vec)",
                          "cosine_similarity_vabq(query_vabq, vec)")
content = content.replace("cursor.set_position(cursor.position() + self.dim as u64 * 4); // skip vector",
                          "cursor.set_position(cursor.position() + self.blob_len as u64); // skip vector")

with open("rust_builder/rust/src/api/custom_hnsw.rs", "w") as f:
    f.write(content)
print("done")

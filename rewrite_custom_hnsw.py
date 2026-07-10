import re

with open("rust_builder/rust/src/api/custom_hnsw.rs", "r") as f:
    content = f.read()

# 1. Add vector_quant usage
if "use crate::api::vector_quant::" not in content:
    content = content.replace("use std::io::Cursor;", "use std::io::Cursor;\nuse crate::api::vector_quant::{QueryVABQ, cosine_similarity_vabq};")

# 2. Node struct: Vec<f32> -> Vec<u8>
content = content.replace("pub vector: Vec<f32>", "pub vector: Vec<u8>")

# 3. search_layer signature
content = content.replace("fn search_layer(&self, query: &[f32], entry_points: &[usize], ef: usize, lc: usize) -> Vec<DistNode>",
                          "fn search_layer(&self, query: &QueryVABQ, entry_points: &[usize], ef: usize, lc: usize) -> Vec<DistNode>")

# 4. cosine_distance -> cosine_similarity_vabq in search_layer
content = content.replace("let dist = cosine_distance(query, &self.nodes[ep].vector);",
                          "let dist = cosine_similarity_vabq(query, &self.nodes[ep].vector);")
content = content.replace("let d = cosine_distance(query, &self.nodes[neighbor].vector);",
                          "let d = cosine_similarity_vabq(query, &self.nodes[neighbor].vector);")

# 5. HnswBuilder::insert signature
content = content.replace("pub fn insert(&mut self, id: i64, vector: Vec<f32>)",
                          "pub fn insert(&mut self, id: i64, vector: Vec<u8>, query_vabq: &QueryVABQ)")

# 6. insert inner calls (replace &vector with query_vabq)
content = content.replace("let mut curr_dist = cosine_distance(&vector, &self.nodes[curr_ep].vector);",
                          "let mut curr_dist = cosine_similarity_vabq(query_vabq, &self.nodes[curr_ep].vector);")
content = content.replace("let d = cosine_distance(&vector, &self.nodes[neighbor].vector);",
                          "let d = cosine_similarity_vabq(query_vabq, &self.nodes[neighbor].vector);")
content = content.replace("let neighbors = self.search_layer(&vector, &eps, self.ef_construction, lc);",
                          "let neighbors = self.search_layer(query_vabq, &eps, self.ef_construction, lc);")

# 7. Build method
content = content.replace("pub fn build(&mut self, data: &[(i64, Vec<f32>)]) {",
                          "pub fn build(&mut self, data: &[(i64, Vec<u8>, QueryVABQ)]) {\n")
content = content.replace("self.insert(id, vec.clone());",
                          "self.insert(id, vec.clone(), qv);")
content = content.replace("for (id, vec) in data {",
                          "for (id, vec, qv) in data {")

# 8. save_to_file logic
content = content.replace("let dim = if self.nodes.is_empty() { 0 } else { self.nodes[0].vector.len() };",
                          "let blob_len = if self.nodes.is_empty() { 0 } else { self.nodes[0].vector.len() };")
content = content.replace("writer.write_u32::<LittleEndian>(dim as u32)?;",
                          "writer.write_u32::<LittleEndian>(blob_len as u32)?;")
content = content.replace("let mut node_size = 8 + 1 + dim * 4;",
                          "let mut node_size = 8 + 1 + blob_len;")

# Write vector directly as bytes
content = content.replace("for &v in &node.vector {\n                        writer.write_f32::<LittleEndian>(v)?;\n                    }",
                          "writer.write_all(&node.vector)?;")

# 9. MmapHnswSearcher
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

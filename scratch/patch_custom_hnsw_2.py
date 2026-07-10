import sys

def main():
    with open("rust_builder/rust/src/api/custom_hnsw.rs", "r") as f:
        content = f.read()

    # Define a helper macro or function for vector distance
    helper_code = '''
#[cfg(feature = "vector_quant_i8")]
fn node_distance(a: VectorQuery, b: &VectorData) -> f32 {
    1.0 - (crate::api::vector_quant::cosine_similarity_vabq(a, b) as f32).max(-1.0).min(1.0)
}
#[cfg(not(feature = "vector_quant_i8"))]
fn node_distance(a: VectorQuery, b: &VectorData) -> f32 {
    cosine_distance(a, b)
}

#[cfg(feature = "vector_quant_i8")]
fn node_distance_raw(a: &VectorData, b: &VectorData) -> f32 {
    let q_vabq = crate::api::vector_quant::QueryVABQ::from_vabq_blob(a).unwrap_or_else(|| crate::api::vector_quant::QueryVABQ::new(&[]));
    1.0 - (crate::api::vector_quant::cosine_similarity_vabq(&q_vabq, b) as f32).max(-1.0).min(1.0)
}
#[cfg(not(feature = "vector_quant_i8"))]
fn node_distance_raw(a: &VectorData, b: &VectorData) -> f32 {
    cosine_distance(a, b)
}
'''
    content = content.replace("fn cosine_distance(a: &[f32], b: &[f32]) -> f32 {", helper_code + "\nfn cosine_distance(a: &[f32], b: &[f32]) -> f32 {")

    # Replace `cosine_distance(query, &self.nodes[neighbor].vector)` with `node_distance(query, &self.nodes[neighbor].vector)`

    # In search_layer:
    #                 #[cfg(feature = "vector_quant_i8")]
    #                 let dist = 1.0 - (crate::api::vector_quant::cosine_similarity_vabq(query, &self.nodes[ep].vector) as f32).max(-1.0).min(1.0);
    #                 #[cfg(not(feature = "vector_quant_i8"))]
    #                 let dist = cosine_distance(query, &self.nodes[ep].vector);

    content = content.replace('''                #[cfg(feature = "vector_quant_i8")]
                let dist = 1.0 - (crate::api::vector_quant::cosine_similarity_vabq(query, &self.nodes[ep].vector) as f32).max(-1.0).min(1.0);
                #[cfg(not(feature = "vector_quant_i8"))]
                let dist = cosine_distance(query, &self.nodes[ep].vector);''', '''                let dist = node_distance(query, &self.nodes[ep].vector);''')

    # Fix error in line 132:
    content = content.replace('''let d = cosine_distance(query, &self.nodes[neighbor].vector);''', '''let d = node_distance(query, &self.nodes[neighbor].vector);''')

    # Fix HnswBuilder::search
    # It starts with:
    #     pub fn search(&self, query_f32: &[f32], ef: usize) -> Vec<(i64, f32)> {
    content = content.replace('''pub fn search(&self, query: &[f32], ef: usize) -> Vec<(i64, f32)> {''', '''pub fn search(&self, query_f32: &[f32], ef: usize) -> Vec<(i64, f32)> {
        #[cfg(feature = "vector_quant_i8")]
        let q_vabq = QueryVABQ::new(query_f32);

        #[cfg(feature = "vector_quant_i8")]
        let query = &q_vabq;
        #[cfg(not(feature = "vector_quant_i8"))]
        let query = query_f32;
''')

    # In HnswBuilder::search:
    # let mut curr_dist = cosine_distance(&vector, &self.nodes[curr_ep].vector);
    content = content.replace('''let mut curr_dist = cosine_distance(&vector, &self.nodes[curr_ep].vector);''', '''let mut curr_dist = node_distance(query, &self.nodes[curr_ep].vector);''')
    content = content.replace('''let d = cosine_distance(&vector, &self.nodes[neighbor].vector);''', '''let d = node_distance(query, &self.nodes[neighbor].vector);''')

    # And search_layer calls in `search`:
    content = content.replace('''let neighbors = self.search_layer(&vector, &eps, self.ef_construction, lc);''', '''let neighbors = self.search_layer(query, &eps, self.ef_construction, lc);''')
    content = content.replace('''let neighbors = self.search_layer(&vector, &eps, ef, 0);''', '''let neighbors = self.search_layer(query, &eps, ef, 0);''')

    # Fix `connect_node` line 236:
    # dist: cosine_distance(&self.nodes[n_idx].vector, &self.nodes[idx].vector),
    content = content.replace('''dist: cosine_distance(&self.nodes[n_idx].vector, &self.nodes[idx].vector)''', '''dist: node_distance_raw(&self.nodes[n_idx].vector, &self.nodes[idx].vector)''')

    # Fix `save_to_disk` line 272 and 297 where it failed:
    content = content.replace('''let f32_dim = if self.nodes.is_empty() { 0 } else {
            #[cfg(feature = "vector_quant_i8")]
            { self.nodes[0].vector.len() }
            #[cfg(not(feature = "vector_quant_i8"))]
            { quantize_f32_to_vabq(&self.nodes[0].vector).0.len() }
        };
    let blob_len = if f32_dim > 0 { quantize_f32_to_vabq(&self.nodes[0].vector).0.len() } else { 0 };''', '''let blob_len = if self.nodes.is_empty() { 0 } else {
            #[cfg(feature = "vector_quant_i8")]
            { self.nodes[0].vector.len() }
            #[cfg(not(feature = "vector_quant_i8"))]
            { quantize_f32_to_vabq(&self.nodes[0].vector).0.len() }
        } as u32;''')

    content = content.replace('''let blob_len = if f32_dim > 0 { quantize_f32_to_vabq(&self.nodes[0].vector).0.len() } else { 0 };''', '''''')

    # Line 297:
    content = content.replace('''let (vabq_blob, _scale) = quantize_f32_to_vabq(&node.vector);''', '''let (vabq_blob, _scale) = quantize_f32_to_vabq(&node.vector);''') # Wait, I already fixed this in previous script

    with open("rust_builder/rust/src/api/custom_hnsw.rs", "w") as f:
        f.write(content)

if __name__ == "__main__":
    main()

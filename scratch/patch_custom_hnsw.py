import sys

def main():
    with open("rust_builder/rust/src/api/custom_hnsw.rs", "r") as f:
        content = f.read()

    # 1. Define VectorData type at the top
    top_replacement = '''use std::io::Cursor;
use crate::api::vector_quant::{QueryVABQ, cosine_similarity_vabq, quantize_f32_to_vabq};

#[cfg(feature = "vector_quant_i8")]
pub type VectorData = Vec<u8>;
#[cfg(not(feature = "vector_quant_i8"))]
pub type VectorData = Vec<f32>;

#[cfg(feature = "vector_quant_i8")]
pub type VectorQuery<'a> = &'a QueryVABQ;
#[cfg(not(feature = "vector_quant_i8"))]
pub type VectorQuery<'a> = &'a [f32];

fn cosine_distance(a: &[f32], b: &[f32]) -> f32 {'''
    content = content.replace('''use std::io::Cursor;
use crate::api::vector_quant::{QueryVABQ, cosine_similarity_vabq, quantize_f32_to_vabq};

fn cosine_distance(a: &[f32], b: &[f32]) -> f32 {''', top_replacement)

    # 2. Change Node
    content = content.replace('''pub struct Node {
    pub id: i64,
    pub vector: Vec<f32>,
    pub max_layer: usize,
    pub connections: Vec<Vec<usize>>,
}''', '''pub struct Node {
    pub id: i64,
    pub vector: VectorData,
    pub max_layer: usize,
    pub connections: Vec<Vec<usize>>,
}''')

    # 3. Change search_layer signature and body
    content = content.replace('''fn search_layer(&self, query: &[f32], entry_points: &[usize], ef: usize, lc: usize) -> Vec<DistNode> {''', '''fn search_layer(&self, query: VectorQuery, entry_points: &[usize], ef: usize, lc: usize) -> Vec<DistNode> {''')

    # In search_layer, the distance calc:
    #                 let dist = cosine_distance(query, &self.nodes[ep].vector);
    dist_replacement = '''                #[cfg(feature = "vector_quant_i8")]
                let dist = 1.0 - (crate::api::vector_quant::cosine_similarity_vabq(query, &self.nodes[ep].vector) as f32).max(-1.0).min(1.0);
                #[cfg(not(feature = "vector_quant_i8"))]
                let dist = cosine_distance(query, &self.nodes[ep].vector);'''
    content = content.replace('''                let dist = cosine_distance(query, &self.nodes[ep].vector);''', dist_replacement)

    # 4. Change insert signature
    #     pub fn insert(&mut self, id: i64, vector: Vec<f32>) {
    insert_replacement = '''    pub fn insert(&mut self, id: i64, vector_f32: Vec<f32>) {
        #[cfg(feature = "vector_quant_i8")]
        let (vector, _) = quantize_f32_to_vabq(&vector_f32);
        #[cfg(not(feature = "vector_quant_i8"))]
        let vector = vector_f32;
'''
    content = content.replace('''    pub fn insert(&mut self, id: i64, vector: Vec<f32>) {''', insert_replacement)

    # In insert:
    #             let mut ep = vec![self.entry_point.unwrap()];
    #             for lc in (curr_node.max_layer + 1..=self.max_layer).rev() {
    #                 ep = self.search_layer(&vector, &ep, 1, lc)

    ep_search_replacement = '''                #[cfg(feature = "vector_quant_i8")]
                let q_vabq = QueryVABQ::new(&vector_f32);

                #[cfg(feature = "vector_quant_i8")]
                let q_ref = &q_vabq;
                #[cfg(not(feature = "vector_quant_i8"))]
                let q_ref = &vector;

                for lc in (curr_node.max_layer + 1..=self.max_layer).rev() {
                    ep = self.search_layer(q_ref, &ep, 1, lc)'''

    content = content.replace('''                for lc in (curr_node.max_layer + 1..=self.max_layer).rev() {
                    ep = self.search_layer(&vector, &ep, 1, lc)''', ep_search_replacement)

    ep_search_replacement2 = '''                for lc in (0..=curr_node.max_layer).rev() {
                    let mut neighbors = self.search_layer(q_ref, &ep, self.ef_construction, lc);'''

    content = content.replace('''                for lc in (0..=curr_node.max_layer).rev() {
                    let mut neighbors = self.search_layer(&vector, &ep, self.ef_construction, lc);''', ep_search_replacement2)

    # 5. Change save_to_disk
    #             let (vabq_blob, _scale) = quantize_f32_to_vabq(&node.vector);
    #             writer.write_all(&vabq_blob)?;

    save_replacement = '''            #[cfg(feature = "vector_quant_i8")]
            writer.write_all(&node.vector)?;
            #[cfg(not(feature = "vector_quant_i8"))]
            {
                let (vabq_blob, _scale) = quantize_f32_to_vabq(&node.vector);
                writer.write_all(&vabq_blob)?;
            }'''

    content = content.replace('''            let (vabq_blob, _scale) = quantize_f32_to_vabq(&node.vector);
            writer.write_all(&vabq_blob)?;''', save_replacement)

    #     let f32_dim = if self.nodes.is_empty() { 0 } else { self.nodes[0].vector.len() };
    f32_dim_replacement = '''    let blob_len = if self.nodes.is_empty() { 0 } else {
            #[cfg(feature = "vector_quant_i8")]
            { self.nodes[0].vector.len() }
            #[cfg(not(feature = "vector_quant_i8"))]
            { quantize_f32_to_vabq(&self.nodes[0].vector).0.len() }
        };'''
    content = content.replace('''    let f32_dim = if self.nodes.is_empty() { 0 } else { self.nodes[0].vector.len() };
    let blob_len = if f32_dim > 0 { quantize_f32_to_vabq(&self.nodes[0].vector).0.len() } else { 0 };''', f32_dim_replacement)

    with open("rust_builder/rust/src/api/custom_hnsw.rs", "w") as f:
        f.write(content)

if __name__ == "__main__":
    main()

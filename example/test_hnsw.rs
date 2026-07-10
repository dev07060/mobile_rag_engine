use hnsw_rs::prelude::*;
use hnsw_rs::hnswio::*;
fn main() {
    let hnsw = Hnsw::new(16, 100, 16, 200, DistCosine);
    hnsw.insert((&vec![1.0_f32, 2.0, 3.0], 1));
    hnsw.file_dump(".", "my_index").unwrap();
}

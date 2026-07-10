import sys

def main():
    with open("rust_builder/rust/src/api/custom_hnsw.rs", "r") as f:
        content = f.read()

    search_func = '''
    pub fn search(&self, query: &[f32], ef: usize) -> Vec<(i64, f32)> {
        if self.nodes.is_empty() || self.entry_point.is_none() {
            return Vec::new();
        }

        let mut curr_ep = self.entry_point.unwrap();
        let curr_max_layer = self.max_layer;

        // Phase 1: greedy search down to layer + 1
        for lc in (1..=curr_max_layer).rev() {
            let mut curr_dist = cosine_distance(query, &self.nodes[curr_ep].vector);
            let mut changed = true;
            while changed {
                changed = false;
                for &neighbor in &self.nodes[curr_ep].connections[lc] {
                    let d = cosine_distance(query, &self.nodes[neighbor].vector);
                    if d < curr_dist {
                        curr_dist = d;
                        curr_ep = neighbor;
                        changed = true;
                    }
                }
            }
        }

        // Phase 2: search layer 0 with ef
        let eps = vec![curr_ep];
        let mut neighbors = self.search_layer(query, &eps, ef, 0);

        neighbors.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());

        neighbors
            .into_iter()
            .map(|n| (self.nodes[n.index].id, n.dist))
            .collect()
    }
'''
    # Insert it before `pub fn save_to_disk`
    target = "    pub fn save_to_disk(&self, file_path: &str) -> Result<()> {"
    content = content.replace(target, search_func + "\n" + target)

    with open("rust_builder/rust/src/api/custom_hnsw.rs", "w") as f:
        f.write(content)

if __name__ == "__main__":
    main()

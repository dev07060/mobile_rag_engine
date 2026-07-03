use flutter_rust_bridge::frb;

#[derive(Debug, Clone)]
pub struct NativeRuntimeInfo {
    pub native_allocator: String,
    pub rust_features: String,
}

#[frb(sync)]
pub fn native_runtime_info() -> NativeRuntimeInfo {
    NativeRuntimeInfo {
        native_allocator: native_allocator_label().to_string(),
        rust_features: rust_features_label(),
    }
}

fn native_allocator_label() -> &'static str {
    if cfg!(feature = "allocator_mimalloc") {
        "mimalloc"
    } else {
        "system"
    }
}

fn rust_features_label() -> String {
    let mut features = Vec::new();
    if cfg!(feature = "vector_faer") {
        features.push("vector_faer");
    }
    if cfg!(feature = "vector_quant_i8") {
        features.push("vector_quant_i8");
    }
    if cfg!(feature = "allocator_mimalloc") {
        features.push("allocator_mimalloc");
    }
    if cfg!(feature = "hnsw_streaming_rebuild") {
        features.push("hnsw_streaming_rebuild");
    }

    if features.is_empty() {
        "default".to_string()
    } else {
        features.join(",")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allocator_label_matches_compile_time_feature() {
        let expected = if cfg!(feature = "allocator_mimalloc") {
            "mimalloc"
        } else {
            "system"
        };

        assert_eq!(native_runtime_info().native_allocator, expected);
    }

    #[test]
    fn rust_features_label_lists_enabled_allocator_feature() {
        let info = native_runtime_info();

        if cfg!(feature = "allocator_mimalloc") {
            assert!(info.rust_features.contains("allocator_mimalloc"));
        } else {
            assert!(!info.rust_features.contains("allocator_mimalloc"));
        }
    }

    #[test]
    fn rust_features_label_lists_enabled_hnsw_streaming_feature() {
        let info = native_runtime_info();

        if cfg!(feature = "hnsw_streaming_rebuild") {
            assert!(info.rust_features.contains("hnsw_streaming_rebuild"));
        } else {
            assert!(!info.rust_features.contains("hnsw_streaming_rebuild"));
        }
    }
}

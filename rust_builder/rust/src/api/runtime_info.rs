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
        rust_features: rust_features_label().to_string(),
    }
}

fn native_allocator_label() -> &'static str {
    if cfg!(feature = "allocator_mimalloc") {
        "mimalloc"
    } else {
        "system"
    }
}

fn rust_features_label() -> &'static str {
    match (
        cfg!(feature = "vector_faer"),
        cfg!(feature = "vector_quant_i8"),
        cfg!(feature = "allocator_mimalloc"),
    ) {
        (true, true, true) => "vector_faer,vector_quant_i8,allocator_mimalloc",
        (true, true, false) => "vector_faer,vector_quant_i8",
        (true, false, true) => "vector_faer,allocator_mimalloc",
        (true, false, false) => "vector_faer",
        (false, true, true) => "vector_quant_i8,allocator_mimalloc",
        (false, true, false) => "vector_quant_i8",
        (false, false, true) => "allocator_mimalloc",
        (false, false, false) => "default",
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
}

import sys
import re

def main():
    with open("rust_builder/rust/src/api/vector_quant.rs", "r") as f:
        content = f.read()

    # Replace the signature and dimension deduction
    new_func = """
/// Decodes a packed quantization blob (VABQ or Q8_0) back into a full-precision f32 vector.
/// Used during HNSW index rebuilds when the original f32 embedding is discarded to save space.
pub fn decode_packed_blob_to_f32(blob: &[u8]) -> Option<Vec<f32>> {
    if blob.is_empty() {
        return None;
    }

    // Check for VABQ format
    if blob[0] == 0x02 {
        let (expected_dim, d_high, _d_low, num_blocks_h, num_blocks_l, pi_array) = match blob.len() {
            397 => (384, 288, 96, 288 / 16, 96 / 64, &PI_ALL_MINILM_L6_V2 as &[usize]),
            785 => (768, 512, 256, 512 / 16, 256 / 64, &PI_ALL_MPNET_BASE_V2 as &[usize]),
            1105 => (1024, 768, 256, 768 / 16, 256 / 64, &PI_BGE_M3_1024 as &[usize]),
            _ => return None,
        };

        let mut permuted = vec![0.0f32; expected_dim];
        let mut blob_idx = 1;

        // Decode high-variance (INT8, b=16)
        for block_idx in 0..num_blocks_h {
            let scale = f32::from_le_bytes([
                blob[blob_idx], blob[blob_idx + 1], blob[blob_idx + 2], blob[blob_idx + 3]
            ]);
            blob_idx += 4;

            let start = block_idx * 16; // VABQ_BH
            for i in 0..16 {
                let q = blob[blob_idx] as i8 as f32;
                blob_idx += 1;
                permuted[start + i] = q * scale;
            }
        }

        // Decode low-variance (INT4, b=64)
        for block_idx in 0..num_blocks_l {
            let scale = f32::from_le_bytes([
                blob[blob_idx], blob[blob_idx + 1], blob[blob_idx + 2], blob[blob_idx + 3]
            ]);
            blob_idx += 4;

            let start = d_high + block_idx * 64; // VABQ_BL
            for i in (0..64).step_by(2) {
                let packed = blob[blob_idx];
                blob_idx += 1;

                // Sign extension for 4-bit two's complement
                let v0 = (packed & 0x0F) as i8;
                let v0 = if v0 > 7 { v0 - 16 } else { v0 } as f32;

                let v1 = (packed >> 4) as i8;
                let v1 = if v1 > 7 { v1 - 16 } else { v1 } as f32;

                permuted[start + i] = v0 * scale;
                permuted[start + i + 1] = v1 * scale;
            }
        }

        // Inverse permutation
        let mut original = vec![0.0f32; expected_dim];
        for i in 0..expected_dim {
            original[pi_array[i]] = permuted[i];
        }

        return Some(original);
    }

    // Q8_0 format (block size 32 -> 36 bytes per block)
    let block_size = 32;
    let bytes_per_block = 36;
    let expected_dim = match blob.len() {
        432 => 384,
        864 => 768,
        1152 => 1024,
        _ => return None,
    };

    let mut decoded = vec![0.0f32; expected_dim];
    let num_blocks = expected_dim / block_size;
    let mut blob_idx = 0;

    for block_idx in 0..num_blocks {
        let scale = f32::from_le_bytes([
            blob[blob_idx], blob[blob_idx + 1], blob[blob_idx + 2], blob[blob_idx + 3]
        ]);
        blob_idx += 4;

        let start = block_idx * block_size;
        for i in 0..block_size {
            let q = blob[blob_idx] as i8 as f32;
            blob_idx += 1;
            decoded[start + i] = q * scale;
        }
    }
    return Some(decoded);
}
"""
    # Use regex to replace the function definition
    pattern = r"/// Decodes a packed quantization blob(.*?)None\n\}"
    content = re.sub(pattern, new_func.strip(), content, flags=re.DOTALL)

    with open("rust_builder/rust/src/api/vector_quant.rs", "w") as f:
        f.write(content)

    print("Replaced decode_packed_blob_to_f32.")

if __name__ == "__main__":
    main()

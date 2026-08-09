// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Scalar quantization utilities for f32 <-> i8 conversion.

use crate::api::error::RagError;
use once_cell::sync::Lazy;
use std::sync::RwLock;

#[inline]
pub(crate) fn quantize_f32_to_i8(input: &[f32]) -> (Vec<i8>, f32) {
    if input.is_empty() {
        return (Vec::new(), 1.0);
    }

    let max_abs = input
        .iter()
        .fold(0.0f32, |acc, v| if v.abs() > acc { v.abs() } else { acc });
    if max_abs == 0.0 {
        return (vec![0; input.len()], 1.0);
    }

    let scale = max_abs / 127.0;
    let inv_scale = 1.0 / scale;
    let quantized = input
        .iter()
        .map(|v| (v * inv_scale).round().clamp(-127.0, 127.0) as i8)
        .collect();

    (quantized, scale)
}

#[allow(dead_code)]
#[inline]
pub(crate) fn dequantize_i8_to_f32(input: &[i8], scale: f32) -> Vec<f32> {
    if input.is_empty() {
        return Vec::new();
    }
    input.iter().map(|v| (*v as f32) * scale).collect()
}

#[cfg(any(test, feature = "bench"))]
#[inline]
pub(crate) fn i8_blob_from_slice(input: &[i8]) -> Vec<u8> {
    input.iter().map(|v| *v as u8).collect()
}

/// Quantize an `f32` embedding directly into the SQLite `BLOB`
/// representation, skipping the intermediate `Vec<i8>` that
/// [`quantize_f32_to_i8`] plus a byte conversion would otherwise produce.
/// Returns the quantized bytes together with the scale used to dequantize
/// them later. Behaviour is bit-for-bit equivalent to the older two-step path.
#[cfg(feature = "vector_quant_i8")]
#[inline]
pub(crate) fn quantize_f32_to_u8_blob(input: &[f32]) -> (Vec<u8>, f32) {
    if input.is_empty() {
        return (Vec::new(), 1.0);
    }
    // Packed block-wise quantization format (Q8_0 style):
    // 36 bytes per block of 32: 4-byte f32 scale (little-endian) + 32-byte i8 values.
    let (quantized, scales) = quantize_f32_to_i8_blockwise(input);
    let mut packed = Vec::with_capacity(scales.len() * 4 + quantized.len());

    for block_idx in 0..scales.len() {
        let scale_bytes = scales[block_idx].to_le_bytes();
        packed.extend_from_slice(&scale_bytes);

        let start = block_idx * BLOCK_SIZE;
        let end = (start + BLOCK_SIZE).min(quantized.len());
        for i in start..end {
            packed.push(quantized[i] as u8);
        }
    }
    // Return the packed blob and a dummy scale of 1.0
    (packed, 1.0)
}

#[cfg(not(feature = "vector_quant_i8"))]
#[inline]
pub(crate) fn quantize_f32_to_u8_blob(input: &[f32]) -> (Vec<u8>, f32) {
    if input.is_empty() {
        return (Vec::new(), 1.0);
    }

    let max_abs = input
        .iter()
        .fold(0.0f32, |acc, v| if v.abs() > acc { v.abs() } else { acc });
    if max_abs == 0.0 {
        return (vec![0u8; input.len()], 1.0);
    }

    let scale = max_abs / 127.0;
    let inv_scale = 1.0 / scale;
    let blob = input
        .iter()
        .map(|v| (v * inv_scale).round().clamp(-127.0, 127.0) as i8 as u8)
        .collect();

    (blob, scale)
}

#[allow(dead_code)]
#[inline]
pub(crate) fn i8_vec_from_blob(blob: &[u8]) -> Vec<i8> {
    blob.iter().map(|v| *v as i8).collect()
}

#[inline]
pub(crate) fn dot_i8_i32(a: &[i8], b: &[i8]) -> i32 {
    if a.len() != b.len() || a.is_empty() {
        return 0;
    }
    a.iter()
        .zip(b.iter())
        .map(|(x, y)| (*x as i32) * (*y as i32))
        .sum()
}

#[inline]
pub(crate) fn l2_norm_i8(v: &[i8]) -> f32 {
    if v.is_empty() {
        return 0.0;
    }
    let sq_sum: i32 = v.iter().map(|x| (*x as i32) * (*x as i32)).sum();
    (sq_sum as f32).sqrt()
}

#[inline]
pub(crate) fn cosine_with_query_norm_i8(query: &[i8], query_norm: f32, target: &[i8]) -> f32 {
    if query.len() != target.len() || query.is_empty() || query_norm == 0.0 {
        return 0.0;
    }
    let target_norm = l2_norm_i8(target);
    if target_norm == 0.0 {
        return 0.0;
    }
    (dot_i8_i32(query, target) as f32) / (query_norm * target_norm)
}

#[inline]
pub(crate) fn cosine_with_query_norm_i8_blob(
    query: &[i8],
    query_norm: f32,
    target_blob: &[u8],
) -> f32 {
    if query.len() > target_blob.len() || query.is_empty() || query_norm == 0.0 {
        return 0.0;
    }

    let mut dot: i32 = 0;
    let mut target_sq_sum: i32 = 0;
    for (&q, &raw_target) in query.iter().zip(target_blob.iter()) {
        let target = raw_target as i8;
        let target_i32 = target as i32;
        dot += (q as i32) * target_i32;
        target_sq_sum += target_i32 * target_i32;
    }

    if target_sq_sum == 0 {
        return 0.0;
    }
    (dot as f32) / (query_norm * (target_sq_sum as f32).sqrt())
}

const BLOCK_SIZE: usize = 32;

/// Quantizes an f32 slice into block-wise i8 elements with independent scales (Q8_0 style).
/// Returns the quantized bytes and a list of scales for each block.
pub(crate) fn quantize_f32_to_i8_blockwise(input: &[f32]) -> (Vec<i8>, Vec<f32>) {
    if input.is_empty() {
        return (Vec::new(), Vec::new());
    }

    let num_blocks = (input.len() + BLOCK_SIZE - 1) / BLOCK_SIZE;
    let mut quantized = Vec::with_capacity(input.len());
    let mut scales = Vec::with_capacity(num_blocks);

    for block_idx in 0..num_blocks {
        let start = block_idx * BLOCK_SIZE;
        let end = (start + BLOCK_SIZE).min(input.len());
        let slice = &input[start..end];

        let max_abs = slice.iter().fold(0.0f32, |acc, &v| acc.max(v.abs()));

        if max_abs == 0.0 {
            quantized.extend(vec![0; slice.len()]);
            scales.push(1.0);
        } else {
            let scale = max_abs / 127.0;
            let inv_scale = 1.0 / scale;
            for &v in slice {
                quantized.push((v * inv_scale).round().clamp(-127.0, 127.0) as i8);
            }
            scales.push(scale);
        }
    }

    (quantized, scales)
}

/// Dequantizes block-wise i8 slice back into f32.
#[allow(dead_code)]
pub(crate) fn dequantize_i8_to_f32_blockwise(input: &[i8], scales: &[f32]) -> Vec<f32> {
    if input.is_empty() || scales.is_empty() {
        return Vec::new();
    }

    let mut output = Vec::with_capacity(input.len());
    for (block_idx, scale) in scales.iter().enumerate() {
        let start = block_idx * BLOCK_SIZE;
        let end = (start + BLOCK_SIZE).min(input.len());
        if start >= input.len() {
            break;
        }
        for i in start..end {
            output.push((input[i] as f32) * scale);
        }
    }
    output
}

#[derive(Clone, Debug)]
#[flutter_rust_bridge::frb(ignore)]
pub struct QueryQ8 {
    pub blocks: Vec<i8>,
    pub scales: Vec<f32>,
    pub norm: f32,
}

impl QueryQ8 {
    pub fn new(query_f32: &[f32]) -> Self {
        if query_f32.is_empty() {
            return Self {
                blocks: Vec::new(),
                scales: Vec::new(),
                norm: 0.0,
            };
        }

        let (blocks, scales) = quantize_f32_to_i8_blockwise(query_f32);

        let mut sq_sum: f32 = 0.0;
        let num_blocks = scales.len();
        for block_idx in 0..num_blocks {
            let scale = scales[block_idx];
            let start = block_idx * BLOCK_SIZE;
            let end = (start + BLOCK_SIZE).min(blocks.len());
            let mut block_sum = 0i32;
            for i in start..end {
                let v = blocks[i];
                block_sum += (v as i32) * (v as i32);
            }
            sq_sum += (block_sum as f32) * scale * scale;
        }

        Self {
            blocks,
            scales,
            norm: sq_sum.sqrt(),
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub fn cosine_similarity_q8(
    query_q8: &QueryQ8,
    target_blob: &[u8],
    legacy_query_i8: &[i8],
    legacy_query_norm: f32,
) -> f32 {
    // ── Fast path: legacy uniform blob (len == n_dims) ────────────────────────
    // The blob is a flat array of i8 values cast to u8, one per dimension.
    if target_blob.len() == legacy_query_i8.len() {
        return cosine_with_query_norm_i8_blob(legacy_query_i8, legacy_query_norm, target_blob);
    }

    // ── Block-wise Q8_0 path ──────────────────────────────────────────────────
    // Each block is 36 bytes: [f32 scale (4 bytes LE)] + [32x i8 as u8].
    const BLOCK_BYTES: usize = 36;
    const VALS_PER_BLOCK: usize = 32;

    if target_blob.len() % BLOCK_BYTES != 0 || query_q8.blocks.is_empty() {
        return 0.0;
    }

    let num_blocks = target_blob.len() / BLOCK_BYTES;
    // Only iterate over blocks present in both query and target
    let n_blocks = num_blocks.min(query_q8.scales.len());

    let mut dot_weighted: f32 = 0.0;
    let mut target_sq_sum: f32 = 0.0;

    for block_idx in 0..n_blocks {
        let blob_off = block_idx * BLOCK_BYTES;
        let q_off = block_idx * BLOCK_SIZE;

        // Read target scale directly from the blob bytes (no intermediate buffer)
        let target_scale = f32::from_le_bytes([
            target_blob[blob_off],
            target_blob[blob_off + 1],
            target_blob[blob_off + 2],
            target_blob[blob_off + 3],
        ]);
        let query_scale = query_q8.scales[block_idx]; // safe: block_idx < n_blocks <= scales.len()

        // Determine actual block length (handles last partial block in query)
        let q_end = (q_off + VALS_PER_BLOCK).min(query_q8.blocks.len());
        let block_len = q_end - q_off;

        // Inner dot product: slice-based iteration — no per-element bounds checks,
        // LLVM can auto-vectorize with ARM NEON / x86 AVX2
        let q_slice = &query_q8.blocks[q_off..q_end];
        let t_slice = &target_blob[blob_off + 4..blob_off + 4 + block_len];

        let mut block_dot = 0i32;
        let mut block_target_sq = 0i32;

        for (&q_byte, &t_byte) in q_slice.iter().zip(t_slice.iter()) {
            let q = q_byte as i32;
            let t = t_byte as i8 as i32;
            block_dot += q * t;
            block_target_sq += t * t;
        }

        dot_weighted += (block_dot as f32) * query_scale * target_scale;
        target_sq_sum += (block_target_sq as f32) * target_scale * target_scale;
    }

    let query_norm = query_q8.norm;
    let target_norm = target_sq_sum.sqrt();

    if query_norm == 0.0 || target_norm == 0.0 {
        return 0.0;
    }

    dot_weighted / (query_norm * target_norm)
}

pub(crate) const PI_ALL_MINILM_L6_V2: [usize; 384] = [
    231, 382, 69, 149, 141, 176, 180, 212, 234, 366, 250, 381, 32, 146, 55, 208, 156, 361, 11, 24,
    98, 292, 296, 118, 92, 327, 380, 139, 316, 246, 115, 64, 240, 102, 119, 53, 79, 20, 6, 216,
    309, 241, 221, 251, 142, 270, 294, 274, 260, 88, 16, 245, 116, 189, 67, 259, 304, 272, 218,
    144, 266, 271, 236, 282, 60, 126, 211, 34, 230, 197, 192, 73, 170, 31, 364, 97, 378, 81, 138,
    152, 299, 201, 330, 206, 318, 129, 311, 222, 94, 252, 280, 255, 50, 90, 337, 68, 257, 75, 204,
    238, 356, 340, 21, 191, 325, 91, 227, 4, 308, 207, 359, 247, 131, 107, 7, 172, 38, 19, 215,
    196, 137, 181, 332, 261, 232, 80, 193, 310, 329, 210, 49, 143, 101, 35, 347, 354, 300, 295, 0,
    72, 320, 70, 188, 103, 132, 277, 352, 226, 276, 334, 244, 287, 263, 313, 125, 349, 17, 1, 369,
    194, 307, 136, 153, 297, 220, 164, 279, 202, 291, 174, 233, 289, 83, 288, 326, 281, 87, 317,
    186, 14, 77, 168, 163, 51, 254, 200, 298, 36, 224, 112, 301, 122, 114, 124, 267, 160, 367, 243,
    342, 106, 322, 355, 2, 162, 370, 339, 242, 52, 183, 104, 290, 96, 228, 284, 237, 198, 167, 239,
    148, 324, 56, 375, 8, 82, 37, 331, 265, 18, 158, 217, 286, 48, 47, 159, 377, 76, 213, 225, 343,
    275, 59, 41, 78, 283, 305, 173, 205, 209, 177, 269, 25, 264, 321, 113, 336, 323, 66, 374, 145,
    121, 45, 285, 10, 195, 314, 258, 110, 161, 190, 84, 185, 30, 128, 175, 44, 273, 379, 302, 140,
    278, 65, 46, 27, 178, 373, 360, 13, 235, 346, 350, 362, 15, 154, 303, 123, 22, 253, 57, 187,
    133, 155, 344, 42, 135, 5, 108, 219, 348, 105, 29, 120, 12, 93, 333, 262, 229, 74, 328, 147,
    171, 58, 315, 293, 89, 54, 353, 372, 71, 256, 248, 383, 117, 357, 40, 335, 9, 151, 358, 182,
    371, 365, 306, 130, 86, 376, 26, 345, 100, 3, 268, 165, 214, 109, 95, 351, 85, 166, 43, 134,
    62, 199, 179, 312, 368, 203, 33, 341, 61, 39, 184, 111, 169, 23, 150, 28, 249, 63, 363, 99,
    338, 157, 319, 223, 127,
];

pub(crate) const PI_ALL_MPNET_BASE_V2: [usize; 768] = [
    513, 237, 267, 184, 622, 362, 13, 176, 457, 401, 97, 55, 456, 287, 613, 650, 445, 346, 698,
    692, 763, 197, 477, 673, 496, 736, 634, 289, 498, 438, 239, 559, 41, 90, 483, 465, 57, 256,
    709, 296, 221, 391, 466, 100, 641, 51, 515, 40, 493, 730, 616, 80, 579, 732, 675, 435, 64, 343,
    635, 138, 85, 629, 66, 754, 337, 125, 434, 552, 478, 370, 166, 530, 147, 481, 208, 704, 206,
    542, 467, 313, 222, 107, 683, 406, 15, 175, 614, 203, 276, 516, 8, 405, 58, 451, 1, 255, 54,
    532, 47, 299, 720, 360, 135, 348, 45, 452, 210, 734, 589, 334, 669, 630, 647, 684, 70, 611, 18,
    120, 241, 246, 748, 75, 331, 411, 453, 258, 388, 99, 410, 181, 424, 651, 168, 156, 236, 537,
    536, 719, 375, 224, 177, 605, 596, 378, 355, 752, 499, 39, 677, 392, 59, 288, 381, 6, 433, 179,
    549, 11, 192, 317, 685, 24, 414, 305, 357, 436, 235, 402, 444, 328, 437, 186, 409, 503, 705,
    319, 624, 234, 162, 591, 102, 625, 656, 350, 129, 105, 495, 426, 309, 448, 714, 48, 202, 623,
    728, 152, 260, 364, 396, 535, 722, 67, 30, 584, 760, 225, 244, 470, 114, 610, 173, 737, 33,
    329, 393, 750, 178, 662, 609, 245, 10, 377, 0, 363, 441, 259, 459, 417, 539, 159, 316, 187,
    659, 447, 726, 619, 449, 717, 77, 551, 454, 335, 94, 52, 643, 419, 297, 307, 576, 474, 561,
    524, 344, 703, 517, 497, 29, 560, 372, 636, 627, 706, 150, 266, 578, 281, 464, 606, 104, 554,
    38, 109, 687, 116, 286, 325, 88, 300, 106, 81, 170, 165, 359, 124, 631, 358, 171, 462, 264,
    427, 252, 697, 356, 581, 290, 293, 308, 431, 351, 113, 144, 628, 183, 110, 718, 142, 218, 678,
    571, 180, 494, 638, 598, 84, 738, 512, 228, 158, 384, 215, 682, 557, 658, 333, 716, 646, 525,
    332, 3, 510, 547, 108, 442, 460, 154, 758, 415, 140, 169, 528, 347, 583, 404, 694, 480, 544,
    710, 545, 395, 725, 690, 617, 217, 580, 489, 403, 597, 652, 389, 73, 91, 248, 49, 420, 741, 14,
    219, 766, 601, 640, 592, 306, 201, 157, 724, 664, 301, 408, 676, 523, 695, 277, 570, 600, 141,
    268, 593, 326, 118, 753, 476, 422, 657, 349, 423, 112, 430, 507, 338, 212, 387, 505, 739, 92,
    126, 689, 341, 4, 174, 486, 61, 500, 28, 199, 691, 209, 582, 31, 285, 744, 475, 708, 89, 746,
    368, 240, 68, 439, 122, 74, 529, 491, 133, 699, 17, 304, 361, 663, 60, 385, 26, 759, 421, 440,
    257, 164, 65, 649, 594, 27, 321, 702, 345, 655, 115, 701, 310, 137, 531, 98, 429, 729, 490,
    679, 564, 446, 294, 271, 151, 632, 365, 514, 755, 620, 83, 573, 32, 412, 418, 136, 543, 205,
    587, 12, 254, 302, 615, 443, 9, 44, 367, 42, 275, 533, 540, 25, 742, 432, 119, 667, 637, 671,
    680, 182, 711, 312, 653, 626, 369, 562, 139, 469, 721, 250, 198, 553, 35, 509, 123, 46, 747,
    696, 200, 595, 93, 572, 707, 342, 36, 407, 20, 450, 761, 63, 145, 298, 733, 96, 670, 196, 238,
    272, 128, 69, 280, 23, 117, 765, 79, 323, 366, 425, 263, 668, 163, 757, 314, 504, 78, 132, 371,
    506, 167, 604, 633, 7, 204, 185, 674, 233, 541, 482, 556, 550, 261, 382, 322, 398, 278, 327,
    397, 16, 546, 740, 585, 700, 735, 538, 253, 295, 693, 291, 727, 511, 315, 194, 575, 71, 193,
    479, 318, 548, 62, 247, 324, 22, 320, 518, 618, 522, 745, 76, 226, 161, 612, 262, 681, 519,
    473, 621, 468, 749, 134, 21, 567, 713, 242, 191, 380, 265, 282, 661, 131, 101, 566, 211, 214,
    229, 195, 603, 189, 599, 751, 143, 645, 463, 534, 190, 586, 121, 373, 270, 563, 577, 485, 220,
    336, 558, 767, 458, 249, 379, 283, 666, 386, 146, 72, 111, 243, 383, 155, 103, 207, 339, 352,
    127, 764, 5, 574, 330, 712, 400, 428, 502, 394, 149, 251, 565, 172, 160, 413, 374, 608, 521,
    232, 87, 274, 43, 53, 660, 56, 484, 130, 488, 569, 227, 230, 492, 37, 279, 95, 487, 213, 390,
    19, 340, 455, 648, 216, 153, 665, 731, 82, 353, 311, 639, 292, 527, 188, 590, 86, 269, 354,
    501, 723, 602, 399, 508, 607, 223, 762, 644, 284, 715, 376, 654, 303, 148, 642, 526, 416, 231,
    472, 471, 743, 273, 588, 520, 2, 686, 672, 50, 461, 568, 34, 688, 555, 756,
];

/// BAAI/bge-base-en-v1.5 variance order calibrated from the pinned runtime
/// model over the fixed 10,000-passage MS MARCO corpus. Provenance is checked
/// in at research/vabq/calibration/bge-base-en-v1.5.json.
pub(crate) const PI_BGE_BASE_EN_V15: [usize; 768] = [
    504, 704, 645, 28, 629, 391, 551, 376, 633, 603, 396, 231, 153, 596, 588, 544, 582, 62, 198,
    679, 328, 43, 724, 312, 732, 304, 563, 46, 8, 67, 761, 280, 608, 338, 168, 71, 320, 703, 239,
    339, 169, 41, 658, 178, 246, 750, 313, 485, 458, 606, 562, 434, 507, 483, 686, 3, 203, 609,
    227, 171, 445, 605, 379, 81, 275, 390, 543, 40, 94, 753, 764, 269, 11, 150, 653, 143, 370, 748,
    163, 429, 495, 496, 623, 175, 322, 38, 302, 701, 446, 121, 182, 337, 282, 646, 723, 624, 260,
    447, 659, 155, 100, 579, 580, 252, 690, 327, 404, 133, 599, 166, 357, 669, 539, 0, 691, 359,
    295, 408, 97, 219, 243, 200, 403, 228, 516, 738, 119, 284, 268, 683, 515, 115, 325, 759, 743,
    272, 426, 202, 555, 677, 139, 616, 110, 229, 524, 437, 311, 489, 611, 710, 573, 714, 365, 590,
    52, 469, 18, 273, 620, 621, 33, 210, 368, 211, 695, 508, 60, 296, 498, 717, 442, 335, 183, 742,
    428, 79, 173, 204, 509, 372, 195, 744, 660, 267, 69, 293, 688, 561, 655, 538, 197, 253, 587,
    418, 441, 635, 144, 517, 410, 333, 642, 189, 574, 147, 554, 148, 720, 765, 450, 356, 45, 305,
    697, 80, 68, 251, 454, 354, 540, 383, 135, 146, 362, 558, 698, 258, 481, 344, 728, 536, 676,
    628, 715, 547, 31, 668, 88, 585, 619, 99, 331, 125, 600, 72, 256, 630, 351, 692, 30, 350, 19,
    111, 345, 533, 436, 138, 318, 745, 584, 348, 425, 48, 634, 707, 570, 58, 675, 453, 188, 374,
    650, 9, 384, 465, 729, 480, 56, 127, 735, 746, 722, 279, 7, 317, 104, 631, 95, 330, 248, 82,
    192, 559, 289, 641, 684, 196, 747, 578, 537, 651, 632, 708, 487, 151, 347, 137, 247, 564, 366,
    388, 737, 525, 276, 721, 575, 594, 187, 319, 288, 259, 78, 709, 505, 225, 157, 756, 755, 406,
    520, 571, 324, 44, 493, 181, 432, 667, 167, 23, 230, 486, 589, 307, 306, 378, 663, 209, 134,
    326, 377, 92, 639, 521, 409, 414, 238, 316, 170, 477, 158, 299, 270, 315, 241, 607, 98, 321,
    117, 459, 444, 534, 63, 21, 474, 577, 208, 116, 300, 236, 430, 711, 387, 102, 61, 329, 522,
    479, 114, 440, 647, 439, 622, 17, 699, 39, 762, 556, 142, 752, 47, 610, 375, 541, 309, 394,
    478, 689, 438, 399, 678, 35, 207, 617, 392, 367, 503, 464, 424, 352, 294, 546, 682, 112, 518,
    358, 16, 685, 595, 371, 468, 514, 550, 364, 32, 395, 93, 568, 287, 37, 257, 398, 490, 264, 176,
    59, 433, 159, 586, 531, 560, 706, 733, 149, 693, 29, 15, 180, 42, 523, 361, 286, 51, 500, 75,
    741, 716, 6, 165, 113, 220, 191, 497, 511, 193, 736, 455, 613, 420, 222, 549, 527, 602, 719,
    240, 665, 473, 553, 726, 205, 22, 548, 291, 763, 310, 385, 340, 283, 1, 462, 423, 604, 297,
    417, 739, 499, 130, 212, 542, 680, 766, 381, 162, 731, 156, 393, 74, 767, 50, 145, 526, 386,
    638, 734, 274, 552, 199, 626, 673, 760, 237, 407, 657, 401, 467, 576, 77, 184, 254, 592, 266,
    194, 656, 154, 70, 435, 261, 449, 614, 397, 124, 545, 694, 107, 529, 120, 223, 301, 513, 702,
    566, 265, 654, 103, 123, 185, 363, 214, 118, 749, 510, 140, 234, 353, 413, 24, 89, 402, 457,
    532, 174, 54, 644, 712, 84, 652, 640, 373, 49, 177, 96, 618, 360, 87, 10, 4, 421, 382, 494,
    405, 713, 535, 126, 346, 488, 245, 2, 232, 681, 460, 250, 206, 105, 290, 452, 164, 625, 255,
    389, 179, 567, 242, 226, 73, 109, 85, 90, 666, 491, 25, 443, 108, 662, 332, 217, 530, 591, 122,
    216, 466, 64, 451, 674, 101, 201, 565, 292, 233, 598, 476, 160, 65, 627, 343, 637, 380, 308,
    581, 597, 461, 431, 419, 448, 730, 569, 612, 740, 472, 36, 281, 427, 244, 572, 314, 422, 400,
    57, 13, 141, 53, 615, 501, 224, 519, 751, 14, 528, 186, 700, 342, 55, 754, 601, 132, 369, 583,
    758, 271, 213, 636, 66, 76, 131, 696, 334, 336, 502, 323, 482, 661, 471, 218, 20, 262, 649,
    190, 664, 671, 725, 512, 672, 355, 492, 643, 86, 172, 34, 221, 152, 415, 285, 456, 83, 506, 91,
    470, 475, 687, 757, 341, 557, 12, 727, 718, 303, 593, 263, 412, 161, 235, 136, 416, 129, 278,
    298, 215, 27, 463, 26, 249, 349, 5, 106, 648, 277, 411, 484, 705, 128, 670,
];

pub(crate) const PI_BGE_M3_1024: [usize; 1024] = [
    532, 727, 162, 598, 387, 518, 389, 32, 527, 306, 453, 568, 451, 544, 972, 664, 322, 327, 741,
    122, 911, 290, 890, 87, 307, 662, 851, 651, 980, 428, 223, 353, 863, 683, 43, 604, 569, 660,
    844, 346, 496, 241, 549, 415, 507, 885, 76, 355, 84, 628, 522, 505, 744, 586, 806, 358, 392,
    275, 671, 632, 311, 565, 79, 56, 697, 720, 699, 802, 106, 637, 319, 469, 791, 975, 347, 338,
    933, 582, 236, 665, 663, 229, 587, 679, 742, 650, 448, 499, 186, 728, 211, 916, 294, 759, 388,
    446, 401, 100, 227, 512, 433, 509, 873, 964, 420, 1016, 31, 298, 858, 571, 640, 385, 160, 410,
    157, 176, 928, 581, 163, 267, 765, 572, 589, 1023, 472, 743, 541, 206, 799, 525, 261, 690, 624,
    465, 574, 576, 655, 957, 213, 618, 18, 210, 941, 377, 1018, 627, 1020, 456, 384, 413, 150, 807,
    203, 753, 868, 513, 653, 562, 390, 792, 874, 811, 915, 832, 161, 833, 726, 939, 291, 712, 463,
    667, 408, 829, 167, 894, 281, 238, 142, 520, 209, 489, 748, 631, 286, 482, 535, 600, 595, 977,
    965, 825, 666, 486, 995, 16, 731, 491, 242, 207, 583, 145, 838, 283, 478, 936, 397, 721, 564,
    757, 585, 937, 26, 713, 967, 7, 945, 295, 659, 137, 901, 117, 278, 342, 424, 202, 194, 473,
    592, 864, 902, 323, 78, 28, 737, 534, 614, 813, 561, 611, 321, 553, 940, 247, 771, 1003, 225,
    289, 668, 953, 908, 1022, 815, 50, 280, 1002, 85, 34, 754, 899, 41, 48, 371, 178, 485, 925,
    886, 790, 396, 494, 767, 818, 550, 147, 672, 723, 333, 492, 240, 363, 860, 141, 770, 6, 926, 5,
    703, 52, 193, 309, 905, 443, 393, 212, 287, 706, 531, 215, 626, 693, 511, 435, 986, 810, 700,
    836, 1004, 320, 29, 136, 824, 429, 155, 156, 955, 171, 1011, 994, 230, 104, 101, 930, 153, 234,
    633, 602, 158, 300, 949, 445, 918, 830, 897, 368, 621, 245, 719, 54, 220, 533, 982, 423, 437,
    762, 214, 794, 1006, 120, 514, 875, 950, 0, 464, 694, 419, 559, 715, 725, 849, 641, 898, 814,
    909, 118, 364, 536, 552, 853, 479, 62, 881, 958, 305, 1010, 996, 407, 722, 524, 462, 315, 471,
    710, 809, 796, 246, 228, 149, 37, 58, 687, 997, 61, 49, 22, 988, 181, 449, 12, 382, 356, 81,
    450, 252, 786, 931, 861, 82, 603, 249, 328, 745, 369, 629, 361, 962, 128, 606, 480, 495, 529,
    1019, 349, 551, 253, 269, 243, 707, 417, 880, 121, 613, 1008, 24, 334, 920, 526, 35, 192, 224,
    927, 774, 777, 560, 20, 548, 543, 126, 180, 426, 422, 590, 554, 65, 475, 828, 86, 1000, 612,
    734, 154, 578, 430, 440, 454, 846, 999, 134, 226, 758, 555, 855, 856, 64, 1009, 990, 557, 490,
    779, 362, 324, 906, 625, 198, 159, 642, 803, 125, 146, 217, 823, 608, 152, 303, 72, 636, 285,
    264, 92, 934, 195, 199, 645, 944, 274, 165, 318, 350, 461, 519, 232, 357, 452, 504, 656, 89,
    254, 425, 826, 673, 617, 865, 3, 14, 804, 105, 943, 317, 669, 394, 921, 169, 111, 609, 820,
    935, 172, 768, 250, 30, 987, 708, 896, 760, 10, 335, 108, 200, 985, 989, 441, 457, 634, 862,
    90, 196, 130, 493, 817, 537, 502, 597, 326, 59, 772, 183, 296, 434, 570, 55, 53, 77, 644, 222,
    877, 354, 458, 380, 610, 325, 189, 102, 219, 304, 974, 620, 538, 97, 775, 23, 979, 698, 127,
    409, 182, 736, 831, 724, 966, 332, 904, 857, 96, 373, 605, 704, 951, 848, 239, 1013, 71, 547,
    969, 968, 510, 112, 948, 21, 1017, 835, 39, 674, 900, 266, 431, 798, 204, 436, 992, 580, 763,
    481, 360, 718, 345, 500, 455, 970, 208, 272, 981, 961, 124, 98, 91, 781, 173, 566, 483, 929,
    144, 670, 402, 131, 88, 442, 787, 216, 959, 459, 879, 840, 75, 268, 682, 33, 913, 567, 730, 63,
    516, 635, 789, 185, 847, 15, 218, 1012, 850, 563, 191, 870, 403, 221, 444, 675, 998, 95, 912,
    907, 262, 412, 747, 277, 271, 197, 432, 258, 1014, 270, 414, 370, 596, 379, 139, 843, 508, 201,
    661, 892, 375, 57, 51, 852, 421, 498, 113, 755, 506, 696, 764, 166, 331, 170, 279, 717, 501,
    837, 418, 878, 797, 17, 133, 83, 343, 60, 716, 299, 488, 689, 132, 993, 676, 740, 284, 265,
    237, 983, 476, 615, 378, 971, 705, 883, 695, 867, 647, 1005, 140, 164, 129, 839, 639, 273, 910,
    135, 702, 474, 638, 468, 919, 889, 44, 94, 231, 756, 503, 776, 340, 973, 66, 288, 40, 80, 138,
    709, 107, 484, 467, 681, 359, 115, 151, 1015, 822, 1001, 622, 584, 795, 282, 116, 882, 8, 841,
    406, 711, 313, 749, 348, 540, 954, 932, 652, 174, 466, 187, 341, 366, 314, 11, 735, 1021, 310,
    523, 714, 36, 691, 783, 876, 411, 938, 891, 19, 330, 259, 293, 99, 685, 556, 405, 1007, 539,
    184, 732, 677, 601, 984, 630, 701, 337, 235, 751, 439, 367, 680, 336, 607, 872, 750, 942, 658,
    834, 103, 400, 922, 372, 515, 70, 2, 521, 884, 376, 487, 93, 73, 788, 1, 692, 819, 383, 888,
    733, 528, 761, 276, 593, 805, 69, 312, 251, 46, 42, 344, 374, 416, 74, 67, 785, 869, 854, 643,
    924, 752, 591, 352, 773, 801, 248, 766, 110, 893, 27, 558, 594, 244, 546, 143, 646, 148, 914,
    45, 404, 190, 845, 438, 339, 119, 123, 577, 9, 398, 260, 887, 778, 391, 588, 895, 963, 477,
    739, 619, 365, 784, 205, 729, 746, 769, 255, 648, 859, 678, 256, 782, 530, 946, 233, 842, 599,
    399, 302, 460, 738, 168, 649, 947, 25, 688, 542, 866, 657, 13, 978, 4, 386, 654, 575, 684, 351,
    991, 114, 497, 800, 827, 470, 38, 816, 179, 976, 960, 956, 623, 381, 793, 808, 686, 923, 316,
    952, 917, 395, 579, 545, 812, 188, 427, 109, 257, 292, 821, 47, 447, 780, 871, 68, 177, 175,
    263, 301, 308, 903, 297, 573, 517, 329, 616,
];

pub(crate) const VABQ_BH: usize = 16;
pub(crate) const VABQ_BL: usize = 64;
const VABQ_TAG: u8 = 0x02;
const VABQ_FORMAT_VERSION: u8 = 0x01;
const VABQ_HEADER_LEN: usize = 5;

/// Variance profiles whose permutations were calibrated for a supported
/// embedding model family. The profile id is persisted in every new VABQ blob
/// so a reader never silently applies the wrong permutation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum VabqProfile {
    AllMiniLmL6V2 = 1,
    AllMpnetBaseV2 = 2,
    BgeM3 = 3,
    BgeBaseEnV15 = 4,
}

impl VabqProfile {
    fn from_host_name(value: &str) -> Option<Self> {
        match value {
            "allMiniLmL6V2" => Some(Self::AllMiniLmL6V2),
            "allMpnetBaseV2" => Some(Self::AllMpnetBaseV2),
            "bgeM3" => Some(Self::BgeM3),
            "bgeBaseEnV15" => Some(Self::BgeBaseEnV15),
            _ => None,
        }
    }
    pub(crate) fn for_dimension(dimension: usize) -> Option<Self> {
        match dimension {
            384 => Some(Self::AllMiniLmL6V2),
            768 => Some(Self::AllMpnetBaseV2),
            1024 => Some(Self::BgeM3),
            _ => None,
        }
    }

    fn from_wire(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::AllMiniLmL6V2),
            2 => Some(Self::AllMpnetBaseV2),
            3 => Some(Self::BgeM3),
            4 => Some(Self::BgeBaseEnV15),
            _ => None,
        }
    }

    fn dimension(self) -> usize {
        match self {
            Self::AllMiniLmL6V2 => 384,
            Self::AllMpnetBaseV2 => 768,
            Self::BgeM3 => 1024,
            Self::BgeBaseEnV15 => 768,
        }
    }

    fn layout(self) -> (&'static [usize], usize, usize) {
        match self {
            Self::AllMiniLmL6V2 => (&PI_ALL_MINILM_L6_V2, 288, 96),
            Self::AllMpnetBaseV2 => (&PI_ALL_MPNET_BASE_V2, 512, 256),
            Self::BgeM3 => (&PI_BGE_M3_1024, 768, 256),
            Self::BgeBaseEnV15 => (&PI_BGE_BASE_EN_V15, 512, 256),
        }
    }
}

/// Process-wide profile selected explicitly by the host at initialization.
/// `None` deliberately means Q8_0; dimensions never select a VABQ profile.
static ACTIVE_VABQ_PROFILE: Lazy<RwLock<Option<VabqProfile>>> = Lazy::new(|| RwLock::new(None));

fn active_vabq_profile() -> Option<VabqProfile> {
    *ACTIVE_VABQ_PROFILE
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Configure the VABQ profile chosen by the Dart host after probing the
/// embedding model's output dimension. Unknown names and dimension/profile
/// mismatches are rejected before any data can be written.
pub(crate) fn configure_active_vabq_profile(
    profile: Option<String>,
    embedding_dimension: i32,
) -> Result<(), RagError> {
    let selected =
        match profile {
            None => None,
            Some(name) if name == "none" => None,
            Some(name) => Some(VabqProfile::from_host_name(&name).ok_or_else(|| {
                RagError::InvalidInput(format!("Unsupported VABQ profile '{name}'"))
            })?),
        };

    if let Some(selected) = selected {
        let expected = selected.dimension() as i32;
        if embedding_dimension != expected {
            return Err(RagError::InvalidInput(format!(
                "VABQ profile requires embedding dimension {expected}, got {embedding_dimension}"
            )));
        }
    }

    *ACTIVE_VABQ_PROFILE
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = selected;
    Ok(())
}

struct VabqBlobLayout {
    dimension: usize,
    d_high: usize,
    stored_d_low: usize,
    num_blocks_h: usize,
    num_blocks_l: usize,
    profile: VabqProfile,
    payload_offset: usize,
}

fn vabq_blob_layout(blob: &[u8]) -> Option<VabqBlobLayout> {
    let legacy_layout = |profile: VabqProfile, stored_d_low, num_blocks_l| VabqBlobLayout {
        dimension: profile.dimension(),
        d_high: profile.layout().1,
        stored_d_low,
        num_blocks_h: profile.layout().1 / VABQ_BH,
        num_blocks_l,
        profile,
        payload_offset: 1,
    };

    match blob.len() {
        // Before the self-describing header, readers infer the profile from
        // the serialized size. 397 is the original truncated 384-dim layout;
        // 417 is the fixed-tail pre-header layout produced during migration.
        397 if blob.first() == Some(&VABQ_TAG) => {
            Some(legacy_layout(VabqProfile::AllMiniLmL6V2, 64, 1))
        }
        417 if blob.first() == Some(&VABQ_TAG) => {
            Some(legacy_layout(VabqProfile::AllMiniLmL6V2, 96, 2))
        }
        785 if blob.first() == Some(&VABQ_TAG) => {
            Some(legacy_layout(VabqProfile::AllMpnetBaseV2, 256, 4))
        }
        1105 if blob.first() == Some(&VABQ_TAG) => Some(legacy_layout(VabqProfile::BgeM3, 256, 4)),
        421 | 789 | 1109 if blob.len() >= VABQ_HEADER_LEN => {
            if blob[0] != VABQ_TAG || blob[1] != VABQ_FORMAT_VERSION {
                return None;
            }
            let dimension = u16::from_le_bytes([blob[2], blob[3]]) as usize;
            let profile = VabqProfile::from_wire(blob[4])?;
            if profile.dimension() != dimension {
                return None;
            }
            let (_pi, d_high, d_low) = profile.layout();
            let expected_len = VABQ_HEADER_LEN
                + (d_high / VABQ_BH) * (4 + VABQ_BH)
                + ((d_low + VABQ_BL - 1) / VABQ_BL) * 4
                + (d_low + 1) / 2;
            if blob.len() != expected_len {
                return None;
            }
            Some(VabqBlobLayout {
                dimension,
                d_high,
                stored_d_low: d_low,
                num_blocks_h: d_high / VABQ_BH,
                num_blocks_l: (d_low + VABQ_BL - 1) / VABQ_BL,
                profile,
                payload_offset: VABQ_HEADER_LEN,
            })
        }
        _ => None,
    }
}

fn has_versioned_vabq_envelope(blob: &[u8]) -> bool {
    matches!(blob.len(), 421 | 789 | 1109)
        && blob.get(0) == Some(&VABQ_TAG)
        && blob.get(1) == Some(&VABQ_FORMAT_VERSION)
}

/// Returns the dimension encoded by a structurally valid Q8_0 payload.
/// A Q8_0 block is `[f32 scale LE][32 i8 values]`; the final block may be
/// partial but still includes its four-byte scale. This is intentionally based
/// on exact block layout, not on the payload's first byte.
fn q8_0_blob_dimension(blob: &[u8]) -> Option<usize> {
    const Q8_BLOCK_SIZE: usize = 32;
    const Q8_BYTES_PER_BLOCK: usize = 36;

    let full_blocks = blob.len() / Q8_BYTES_PER_BLOCK;
    let tail_len = blob.len() % Q8_BYTES_PER_BLOCK;
    match tail_len {
        0 if full_blocks > 0 => Some(full_blocks * Q8_BLOCK_SIZE),
        5..=35 => Some(full_blocks * Q8_BLOCK_SIZE + tail_len - 4),
        _ => None,
    }
}

// Pack to VABQ
#[flutter_rust_bridge::frb(ignore)]
pub fn quantize_f32_to_vabq(input: &[f32]) -> (Vec<u8>, f32) {
    let Some(profile) = VabqProfile::for_dimension(input.len()) else {
        return quantize_f32_to_u8_blob(input);
    };
    quantize_f32_to_vabq_for_profile(input, profile)
}

fn quantize_f32_to_vabq_for_profile(input: &[f32], profile: VabqProfile) -> (Vec<u8>, f32) {
    if input.is_empty() {
        return (Vec::new(), 1.0);
    }
    let n_dims = input.len();
    debug_assert_eq!(n_dims, profile.dimension());
    let (pi_array, d_high, _d_low) = profile.layout();

    // 1. Permute
    let mut permuted = vec![0.0f32; n_dims];
    for i in 0..n_dims {
        permuted[i] = input[pi_array[i]];
    }

    // 2. High variance (INT8, b=16)
    let high_var = &permuted[..d_high];
    let num_blocks_h = d_high / VABQ_BH;
    let mut high_q = Vec::with_capacity(d_high);
    let mut high_scales = Vec::with_capacity(num_blocks_h);

    for block_idx in 0..num_blocks_h {
        let start = block_idx * VABQ_BH;
        let end = start + VABQ_BH;
        let slice = &high_var[start..end];

        let max_abs = slice.iter().fold(0.0f32, |acc, &v| acc.max(v.abs()));
        if max_abs == 0.0 {
            high_q.extend(vec![0; VABQ_BH]);
            high_scales.push(1.0);
        } else {
            let scale = max_abs / 127.0;
            let inv_scale = 1.0 / scale;
            for &v in slice {
                high_q.push((v * inv_scale).round().clamp(-127.0, 127.0) as i8);
            }
            high_scales.push(scale);
        }
    }

    // 3. Low variance (INT4, b=64)
    let d_low = n_dims - d_high;
    let low_var = &permuted[d_high..];
    let num_blocks_l = (d_low + VABQ_BL - 1) / VABQ_BL;
    let mut low_q_packed = Vec::with_capacity(d_low / 2);
    let mut low_scales = Vec::with_capacity(num_blocks_l);

    for block_idx in 0..num_blocks_l {
        let start = block_idx * VABQ_BL;
        let end = (start + VABQ_BL).min(d_low);
        let slice = &low_var[start..end];
        let packed_len = (slice.len() + 1) / 2;

        let max_abs = slice.iter().fold(0.0f32, |acc, &v| acc.max(v.abs()));
        if max_abs == 0.0 {
            low_q_packed.extend(vec![0; packed_len]);
            low_scales.push(1.0);
        } else {
            let scale = max_abs / 7.0; // INT4 range: -7 to 7
            let inv_scale = 1.0 / scale;
            for i in (0..slice.len()).step_by(2) {
                let v0 = (slice[i] * inv_scale).round().clamp(-7.0, 7.0) as i8;
                let v1 = if i + 1 < slice.len() {
                    (slice[i + 1] * inv_scale).round().clamp(-7.0, 7.0) as i8
                } else {
                    0
                };
                // pack into 1 byte. v0 in lower 4 bits, v1 in upper 4 bits
                let packed = ((v0 & 0x0F) as u8) | (((v1 & 0x0F) as u8) << 4);
                low_q_packed.push(packed);
            }
            low_scales.push(scale);
        }
    }

    // 4. Pack together
    // Format: Tag, format version, dimension, profile id, then High Scales +
    // Values and Low Scales + Values. The self-describing header prevents a
    // reader from silently using a variance profile selected only by length.
    let mut blob = Vec::new();
    blob.extend_from_slice(&[
        VABQ_TAG,
        VABQ_FORMAT_VERSION,
        n_dims as u8,
        (n_dims >> 8) as u8,
        profile as u8,
    ]);

    // High section
    for block_idx in 0..num_blocks_h {
        blob.extend_from_slice(&high_scales[block_idx].to_le_bytes());
        let start = block_idx * VABQ_BH;
        let end = start + VABQ_BH;
        for i in start..end {
            blob.push(high_q[i] as u8);
        }
    }

    // Low section
    let mut packed_idx = 0;
    for block_idx in 0..num_blocks_l {
        blob.extend_from_slice(&low_scales[block_idx].to_le_bytes());
        let block_start = block_idx * VABQ_BL;
        let packed_len = ((d_low - block_start).min(VABQ_BL) + 1) / 2;
        for i in packed_idx..packed_idx + packed_len {
            blob.push(low_q_packed[i]);
        }
        packed_idx += packed_len;
    }

    (blob, 1.0)
}

/// Production storage dispatch. VABQ is available only after an explicit host
/// configuration; otherwise this returns the existing Q8_0 representation.
pub(crate) fn quantize_f32_for_active_profile(input: &[f32]) -> Result<(Vec<u8>, f32), RagError> {
    match active_vabq_profile() {
        None => Ok(quantize_f32_to_u8_blob(input)),
        Some(profile) if input.len() == profile.dimension() => {
            Ok(quantize_f32_to_vabq_for_profile(input, profile))
        }
        Some(profile) => Err(RagError::InvalidInput(format!(
            "Active VABQ profile requires embedding dimension {}, got {}",
            profile.dimension(),
            input.len()
        ))),
    }
}

// Struct to hold pre-computed query info
#[flutter_rust_bridge::frb(ignore)]
pub struct QueryVABQ {
    pub high_q: Vec<i8>,
    pub high_scales: Vec<f32>,
    pub low_q: Vec<i8>,
    pub low_scales: Vec<f32>,
    pub query_norm: f32,
    pub d_high: usize,
    pub d_low: usize,
    profile: Option<VabqProfile>,
}

impl QueryVABQ {
    pub fn new(query_f32: &[f32]) -> Self {
        let n_dims = query_f32.len();
        let profile = match VabqProfile::for_dimension(n_dims) {
            Some(profile) => profile,
            None => {
                return Self {
                    high_q: Vec::new(),
                    high_scales: Vec::new(),
                    low_q: Vec::new(),
                    low_scales: Vec::new(),
                    query_norm: 0.0,
                    d_high: 0,
                    d_low: 0,
                    profile: None,
                };
            }
        };
        Self::for_profile(query_f32, profile)
    }

    fn for_profile(query_f32: &[f32], profile: VabqProfile) -> Self {
        let n_dims = query_f32.len();
        debug_assert_eq!(n_dims, profile.dimension());
        let (pi_array, d_high, d_low) = profile.layout();

        let mut permuted = vec![0.0f32; n_dims];
        for i in 0..n_dims {
            permuted[i] = query_f32[pi_array[i]];
        }

        let high_var = &permuted[..d_high];
        let num_blocks_h = d_high / VABQ_BH;
        let mut high_q = Vec::with_capacity(d_high);
        let mut high_scales = Vec::with_capacity(num_blocks_h);

        for block_idx in 0..num_blocks_h {
            let start = block_idx * VABQ_BH;
            let slice = &high_var[start..start + VABQ_BH];
            let max_abs = slice.iter().fold(0.0f32, |acc, &v| acc.max(v.abs()));
            if max_abs == 0.0 {
                high_q.extend(vec![0; VABQ_BH]);
                high_scales.push(1.0);
            } else {
                let scale = max_abs / 127.0;
                let inv_scale = 1.0 / scale;
                for &v in slice {
                    high_q.push((v * inv_scale).round().clamp(-127.0, 127.0) as i8);
                }
                high_scales.push(scale);
            }
        }

        let low_var = &permuted[d_high..];
        let num_blocks_l = (d_low + VABQ_BL - 1) / VABQ_BL;
        let mut low_q = Vec::with_capacity(d_low);
        let mut low_scales = Vec::with_capacity(num_blocks_l);

        for block_idx in 0..num_blocks_l {
            let start = block_idx * VABQ_BL;
            let end = (start + VABQ_BL).min(d_low);
            let slice = &low_var[start..end];
            let max_abs = slice.iter().fold(0.0f32, |acc, &v| acc.max(v.abs()));
            if max_abs == 0.0 {
                low_q.extend(vec![0; slice.len()]);
                low_scales.push(1.0);
            } else {
                let scale_8 = max_abs / 127.0;
                let inv_scale_8 = 1.0 / scale_8;
                for &v in slice {
                    low_q.push((v * inv_scale_8).round().clamp(-127.0, 127.0) as i8);
                }
                low_scales.push(scale_8);
            }
        }

        // Norm calculation requires multiplying by scale squared.
        let mut f32_sq_sum_h = 0.0;
        for block_idx in 0..num_blocks_h {
            let start = block_idx * VABQ_BH;
            let mut block_sq = 0;
            for i in start..start + VABQ_BH {
                let q = high_q[i] as i32;
                block_sq += q * q;
            }
            f32_sq_sum_h += (block_sq as f32) * high_scales[block_idx] * high_scales[block_idx];
        }

        let mut f32_sq_sum_l = 0.0;
        for block_idx in 0..num_blocks_l {
            let start = block_idx * VABQ_BL;
            let mut block_sq = 0;
            let end = (start + VABQ_BL).min(d_low);
            for i in start..end {
                let q = low_q[i] as i32;
                block_sq += q * q;
            }
            f32_sq_sum_l += (block_sq as f32) * low_scales[block_idx] * low_scales[block_idx];
        }

        let query_norm = (f32_sq_sum_h + f32_sq_sum_l).sqrt();

        Self {
            high_q,
            high_scales,
            low_q,
            low_scales,
            query_norm,
            d_high,
            d_low,
            profile: Some(profile),
        }
    }
}

/// Builds a VABQ query only when the host selected a profile whose dimension
/// matches the query. The low-level `QueryVABQ::new` remains for migration and
/// codec tests; production call sites must use this gate.
pub(crate) fn active_vabq_query(query_f32: &[f32]) -> Option<QueryVABQ> {
    let profile = active_vabq_profile()?;
    (query_f32.len() == profile.dimension()).then(|| QueryVABQ::for_profile(query_f32, profile))
}

/// Scores a recognized VABQ blob only when the active host profile, query,
/// and blob header agree. `Ok(None)` means the blob is not VABQ and callers
/// may dispatch it to Q8_0; an incompatible VABQ blob is a fail-closed error.
pub(crate) fn score_vabq_blob_for_active_profile(
    query_f32: &[f32],
    blob: &[u8],
) -> Result<Option<f32>, RagError> {
    let Some(layout) = vabq_blob_layout(blob) else {
        if has_versioned_vabq_envelope(blob) {
            return Err(RagError::InvalidInput(
                "Malformed VABQ header or layout".to_string(),
            ));
        }
        return Ok(None);
    };
    let active = active_vabq_profile().ok_or_else(|| {
        RagError::InvalidInput(
            "Encountered a VABQ blob while the host selected VabqProfile.none".to_string(),
        )
    })?;
    if active != layout.profile {
        return Err(RagError::InvalidInput(format!(
            "Active VABQ profile {:?} does not match blob profile {:?}",
            active, layout.profile
        )));
    }
    if query_f32.len() != active.dimension() {
        return Err(RagError::InvalidInput(format!(
            "Active VABQ profile requires query dimension {}, got {}",
            active.dimension(),
            query_f32.len()
        )));
    }
    let query = QueryVABQ::for_profile(query_f32, active);
    Ok(Some(cosine_similarity_vabq(&query, blob)))
}

/// Shared persistence dispatcher for VABQ and Q8_0 blobs. VABQ is attempted
/// first using the explicit active-profile contract; a recognized but
/// incompatible VABQ blob returns an error instead of being misread as Q8_0.
pub(crate) fn score_persisted_quantized_blob(
    query_f32: &[f32],
    blob: &[u8],
) -> Result<Option<f32>, RagError> {
    if let Some(score) = score_vabq_blob_for_active_profile(query_f32, blob)? {
        return Ok(Some(score));
    }
    if active_vabq_profile().is_some() {
        return Err(RagError::InvalidInput(
            "Expected a VABQ blob for the active VABQ profile".to_string(),
        ));
    }

    let (query_i8, _) = quantize_f32_to_i8(query_f32);
    let query_i8_norm = l2_norm_i8(&query_i8);
    if query_i8_norm <= 0.0 || blob.is_empty() {
        return Ok(None);
    }

    // Q8_0 must be checked before the old flat-i8-with-scale fallback. A
    // 768-d Q8_0 record is 864 bytes, which used to satisfy `>= dim + 4` and
    // therefore scored from a shifted slice. Its first scale byte may also be
    // 0x02, the VABQ tag, so neither tag nor length-prefix heuristics are safe.
    if q8_0_blob_dimension(blob) == Some(query_f32.len()) {
        return Ok(Some(cosine_similarity_q8(
            &QueryQ8::new(query_f32),
            blob,
            &query_i8,
            query_i8_norm,
        )));
    }
    if blob.len() == query_i8.len() + 4 {
        return Ok(Some(cosine_with_query_norm_i8_blob(
            &query_i8,
            query_i8_norm,
            &blob[4..],
        )));
    }
    if blob.len() == query_i8.len() {
        return Ok(Some(cosine_similarity_q8(
            &QueryQ8::new(query_f32),
            blob,
            &query_i8,
            query_i8_norm,
        )));
    }
    Ok(None)
}

/// Query representation matching the host-selected persistence format.
pub(crate) enum ActiveQuantizedQuery {
    Vabq(QueryVABQ),
    Q8 {
        query: QueryQ8,
        legacy_query_i8: Vec<i8>,
        legacy_query_norm: f32,
    },
}

pub(crate) fn active_quantized_query(query_f32: &[f32]) -> Result<ActiveQuantizedQuery, RagError> {
    match active_vabq_profile() {
        Some(profile) => {
            if query_f32.len() != profile.dimension() {
                return Err(RagError::InvalidInput(format!(
                    "Active VABQ profile requires query dimension {}, got {}",
                    profile.dimension(),
                    query_f32.len()
                )));
            }
            Ok(ActiveQuantizedQuery::Vabq(QueryVABQ::for_profile(
                query_f32, profile,
            )))
        }
        None => {
            let (legacy_query_i8, _) = quantize_f32_to_i8(query_f32);
            let legacy_query_norm = l2_norm_i8(&legacy_query_i8);
            Ok(ActiveQuantizedQuery::Q8 {
                query: QueryQ8::new(query_f32),
                legacy_query_i8,
                legacy_query_norm,
            })
        }
    }
}

pub(crate) fn cosine_similarity_active_quantized(
    query: &ActiveQuantizedQuery,
    blob: &[u8],
) -> Result<f32, RagError> {
    match query {
        ActiveQuantizedQuery::Vabq(query_vabq) => {
            score_vabq_blob_for_active_profile_from_query(query_vabq, blob)
        }
        ActiveQuantizedQuery::Q8 {
            query,
            legacy_query_i8,
            legacy_query_norm,
        } => {
            if vabq_blob_layout(blob).is_some() {
                return Err(RagError::InvalidInput(
                    "Encountered a VABQ blob while the host selected VabqProfile.none".to_string(),
                ));
            }
            Ok(cosine_similarity_q8(
                query,
                blob,
                legacy_query_i8,
                *legacy_query_norm,
            ))
        }
    }
}

fn score_vabq_blob_for_active_profile_from_query(
    query: &QueryVABQ,
    blob: &[u8],
) -> Result<f32, RagError> {
    let layout = vabq_blob_layout(blob).ok_or_else(|| {
        RagError::InvalidInput("Expected a VABQ blob for the active VABQ profile".to_string())
    })?;
    let active = active_vabq_profile().ok_or_else(|| {
        RagError::InvalidInput(
            "Encountered a VABQ blob while the host selected VabqProfile.none".to_string(),
        )
    })?;
    if active != layout.profile || query.profile != Some(active) {
        return Err(RagError::InvalidInput(
            "Active VABQ profile, query profile, and blob header must match".to_string(),
        ));
    }
    Ok(cosine_similarity_vabq(query, blob))
}

#[flutter_rust_bridge::frb(ignore)]
pub fn cosine_similarity_vabq(query: &QueryVABQ, target_blob: &[u8]) -> f32 {
    if target_blob.is_empty() || target_blob[0] != VABQ_TAG {
        return 0.0;
    }

    let Some(layout) = vabq_blob_layout(target_blob) else {
        return 0.0;
    };
    if query.profile != Some(layout.profile) {
        return 0.0;
    }

    let mut blob_idx = layout.payload_offset;
    let mut dot_f32 = 0.0;
    let mut target_sq_f32 = 0.0;

    // High section
    for block_idx in 0..layout.num_blocks_h {
        let scale_bytes: [u8; 4] = [
            target_blob[blob_idx],
            target_blob[blob_idx + 1],
            target_blob[blob_idx + 2],
            target_blob[blob_idx + 3],
        ];
        blob_idx += 4;
        let scale_t = f32::from_le_bytes(scale_bytes);
        let scale_q = query.high_scales[block_idx];

        let q_block = &query.high_q[block_idx * VABQ_BH..(block_idx + 1) * VABQ_BH];

        let mut dot_i32 = 0;
        let mut target_sq_i32 = 0;

        for i in 0..VABQ_BH {
            let t = target_blob[blob_idx] as i8 as i32;
            blob_idx += 1;
            let q = q_block[i] as i32;
            dot_i32 += q * t;
            target_sq_i32 += t * t;
        }

        dot_f32 += (dot_i32 as f32) * scale_q * scale_t;
        target_sq_f32 += (target_sq_i32 as f32) * scale_t * scale_t;
    }

    // Low section
    for block_idx in 0..layout.num_blocks_l {
        let scale_bytes: [u8; 4] = [
            target_blob[blob_idx],
            target_blob[blob_idx + 1],
            target_blob[blob_idx + 2],
            target_blob[blob_idx + 3],
        ];
        blob_idx += 4;
        let scale_t = f32::from_le_bytes(scale_bytes);
        let scale_q = query.low_scales[block_idx];

        let block_start = block_idx * VABQ_BL;
        let block_len = (layout.stored_d_low - block_start).min(VABQ_BL);
        let q_block = &query.low_q[block_start..block_start + block_len];

        let mut dot_i32 = 0;
        let mut target_sq_i32 = 0;

        for i in (0..block_len).step_by(2) {
            let packed = target_blob[blob_idx];
            blob_idx += 1;

            // Sign extend 4-bit to 8-bit
            let mut t0 = (packed & 0x0F) as i8;
            if t0 & 0x08 != 0 {
                t0 |= 0xF0_u8 as i8;
            } // negative

            let mut t1 = (packed >> 4) as i8;
            if t1 & 0x08 != 0 {
                t1 |= 0xF0_u8 as i8;
            } // negative

            let q0 = q_block[i] as i32;
            let q1 = q_block.get(i + 1).copied().unwrap_or_default() as i32;

            let t0_i32 = t0 as i32;
            let t1_i32 = t1 as i32;

            dot_i32 += q0 * t0_i32 + q1 * t1_i32;
            target_sq_i32 += t0_i32 * t0_i32;
            if i + 1 < block_len {
                target_sq_i32 += t1_i32 * t1_i32;
            }
        }

        dot_f32 += (dot_i32 as f32) * scale_q * scale_t;
        target_sq_f32 += (target_sq_i32 as f32) * scale_t * scale_t;
    }

    if target_sq_f32 == 0.0 || query.query_norm == 0.0 {
        return 0.0;
    }

    dot_f32 / (query.query_norm * target_sq_f32.sqrt())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::vector_math::{cosine_with_query_norm_f32, l2_norm_f32};
    use base64::Engine;
    use serde::Deserialize;
    use sha2::{Digest, Sha256};
    use std::sync::{Mutex, OnceLock};

    #[derive(Deserialize)]
    struct CanonicalVabqFixture {
        format_version: u8,
        generator: String,
        cases: Vec<CanonicalVabqCase>,
    }

    #[derive(Deserialize)]
    struct CanonicalVabqCase {
        profile: String,
        dimension: usize,
        seed: u32,
        header_hex: String,
        packed_base64: String,
        decoded_f32_le_sha256: String,
        self_cosine: f32,
    }

    fn canonical_fixture_vector(dimension: usize, seed: u32) -> Vec<f32> {
        let mut state = seed;
        (0..dimension)
            .map(|index| {
                state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                let centered = (((state % 2_001) as f64 - 1_000.0) / 1_000.0) as f32;
                let offset = (((index % 13) as f64 - 6.0) / 97.0) as f32;
                centered + offset
            })
            .collect()
    }

    fn canonical_profile(name: &str) -> VabqProfile {
        VabqProfile::from_host_name(name).expect("fixture profile must be supported")
    }

    fn canonical_hex(bytes: &[u8]) -> String {
        bytes.iter().map(|byte| format!("{byte:02x}")).collect()
    }

    #[test]
    fn rust_codec_matches_canonical_v1_packed_fixture() {
        let fixture: CanonicalVabqFixture = serde_json::from_str(include_str!(
            "../../../../test/fixtures/vabq/canonical-v1.json"
        ))
        .expect("canonical fixture must be valid JSON");
        assert_eq!(fixture.format_version, VABQ_FORMAT_VERSION);
        assert_eq!(fixture.generator, "lcg-v1");

        for case in fixture.cases {
            let profile = canonical_profile(&case.profile);
            assert_eq!(case.dimension, profile.dimension());
            let vector = canonical_fixture_vector(case.dimension, case.seed);
            let (blob, _) = quantize_f32_to_vabq_for_profile(&vector, profile);
            assert_eq!(canonical_hex(&blob[..VABQ_HEADER_LEN]), case.header_hex);
            let expected = base64::engine::general_purpose::STANDARD
                .decode(&case.packed_base64)
                .expect("fixture packed bytes must be base64");
            if blob != expected {
                let first_difference = blob
                    .iter()
                    .zip(expected.iter())
                    .position(|(left, right)| left != right)
                    .expect("equal-length blobs must have a differing byte");
                let block = (first_difference - VABQ_HEADER_LEN) / (4 + VABQ_BH);
                let scale_offset = VABQ_HEADER_LEN + block * (4 + VABQ_BH);
                let rust_scale =
                    f32::from_le_bytes(blob[scale_offset..scale_offset + 4].try_into().unwrap());
                let fixture_scale = f32::from_le_bytes(
                    expected[scale_offset..scale_offset + 4].try_into().unwrap(),
                );
                let (permutation, _, _) = profile.layout();
                let start = block * VABQ_BH;
                let (max_index, max_value) = (start..start + VABQ_BH)
                    .map(|index| (index, vector[permutation[index]]))
                    .max_by(|(_, left), (_, right)| left.abs().partial_cmp(&right.abs()).unwrap())
                    .unwrap();
                panic!(
                    "Rust packed bytes diverged for {} at byte {}: rust={:#04x}, fixture={:#04x}, high_block={}, rust_scale={:?}, fixture_scale={:?}, max_permuted_index={}, max_value={:?}, bits={:#x}",
                    case.profile,
                    first_difference,
                    blob[first_difference],
                    expected[first_difference],
                    block,
                    rust_scale,
                    fixture_scale,
                    max_index,
                    max_value,
                    max_value.to_bits(),
                );
            }
            let decoded = decode_packed_blob_to_f32(&blob).expect("v1 blob must decode");
            let decoded_bytes: Vec<u8> = decoded
                .iter()
                .flat_map(|value| value.to_le_bytes())
                .collect();
            assert_eq!(
                format!("{:x}", Sha256::digest(decoded_bytes)),
                case.decoded_f32_le_sha256,
                "Rust decoded values diverged for {}",
                case.profile
            );
            configure_active_vabq_profile(Some(case.profile.clone()), case.dimension as i32)
                .expect("fixture profile must configure");
            let cosine = score_vabq_blob_for_active_profile(&vector, &blob)
                .expect("active profile score must succeed")
                .expect("v1 blob must score");
            assert!(
                (cosine - case.self_cosine).abs() <= 0.000_000_1,
                "Rust cosine diverged for {}: expected {}, got {}",
                case.profile,
                case.self_cosine,
                cosine
            );
        }
        configure_active_vabq_profile(None, 0).expect("reset active profile");
    }

    fn active_profile_test_guard() -> std::sync::MutexGuard<'static, ()> {
        static GUARD: OnceLock<Mutex<()>> = OnceLock::new();
        GUARD
            .get_or_init(|| Mutex::new(()))
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    #[test]
    fn active_profile_requires_explicit_host_selection_and_valid_dimension() {
        let _guard = active_profile_test_guard();
        let vector = vec![0.25f32; 384];

        configure_active_vabq_profile(None, 384).unwrap();
        let (q8_blob, _) = quantize_f32_for_active_profile(&vector).unwrap();
        assert!(vabq_blob_layout(&q8_blob).is_none());
        assert!(active_vabq_query(&vector).is_none());

        configure_active_vabq_profile(Some("allMiniLmL6V2".to_string()), 384).unwrap();
        let (vabq_blob, _) = quantize_f32_for_active_profile(&vector).unwrap();
        assert_eq!(
            vabq_blob_layout(&vabq_blob).unwrap().profile,
            VabqProfile::AllMiniLmL6V2
        );
        assert!(active_vabq_query(&vector).is_some());
        assert!(score_vabq_blob_for_active_profile(&vector, &vabq_blob)
            .unwrap()
            .is_some());

        let mismatch =
            configure_active_vabq_profile(Some("allMiniLmL6V2".to_string()), 768).unwrap_err();
        assert!(mismatch
            .to_string()
            .contains("requires embedding dimension 384"));
        configure_active_vabq_profile(None, 0).unwrap();
        assert!(score_vabq_blob_for_active_profile(&vector, &vabq_blob).is_err());
    }

    #[test]
    fn bge_base_profile_is_explicit_id_4_and_never_falls_back_to_q8() {
        let _guard = active_profile_test_guard();
        let vector: Vec<f32> = (0..768)
            .map(|index| (index as f32 - 384.0) / 384.0)
            .collect();

        configure_active_vabq_profile(Some("bgeBaseEnV15".to_string()), 768).unwrap();
        let (blob, _) = quantize_f32_for_active_profile(&vector).unwrap();
        assert_eq!(&blob[..5], &[VABQ_TAG, VABQ_FORMAT_VERSION, 0x00, 0x03, 4]);
        assert_eq!(blob.len(), 789);
        assert_ne!(blob.len(), 864, "BGE VABQ must not be a 768-d Q8_0 blob");

        let layout = vabq_blob_layout(&blob).expect("BGE blob must have a VABQ layout");
        assert_eq!(layout.profile as u8, 4);
        assert_eq!(layout.d_high, 512);
        assert_eq!(layout.stored_d_low, 256);
        assert!(score_persisted_quantized_blob(&vector, &blob)
            .unwrap()
            .is_some());

        let wrong_dimension = quantize_f32_for_active_profile(&vector[..384]).unwrap_err();
        assert!(wrong_dimension
            .to_string()
            .contains("requires embedding dimension 768"));

        let mut wrong_profile = blob.clone();
        wrong_profile[4] = VabqProfile::AllMpnetBaseV2 as u8;
        assert!(score_persisted_quantized_blob(&vector, &wrong_profile).is_err());

        configure_active_vabq_profile(None, 0).unwrap();
        let (fallback_blob, _) = quantize_f32_for_active_profile(&vector).unwrap();
        #[cfg(feature = "vector_quant_i8")]
        assert_eq!(fallback_blob.len(), 864);
        #[cfg(not(feature = "vector_quant_i8"))]
        assert_eq!(fallback_blob.len(), vector.len());
        configure_active_vabq_profile(Some("bgeBaseEnV15".to_string()), 768).unwrap();
        let fallback_error = score_persisted_quantized_blob(&vector, &fallback_blob).unwrap_err();
        assert!(fallback_error
            .to_string()
            .contains("Expected a VABQ blob for the active VABQ profile"));
        configure_active_vabq_profile(None, 0).unwrap();
    }

    #[test]
    fn quantize_dequantize_roundtrip_reasonable_error() {
        let input = vec![0.1f32, -0.25, 0.5, 1.0, -1.2, 2.3];
        let (q, scale) = quantize_f32_to_i8(&input);
        let restored = dequantize_i8_to_f32(&q, scale);
        assert_eq!(restored.len(), input.len());

        let max_abs_err = input
            .iter()
            .zip(restored.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0f32, f32::max);
        assert!(max_abs_err < 0.05);
    }

    #[test]
    fn i8_cosine_matches_directionality() {
        let a = vec![1.0f32, 2.0, 3.0, -1.0];
        let b = vec![1.1f32, 1.9, 2.8, -0.8];
        let c = vec![-1.0f32, -2.0, -3.0, 1.0];

        let (qa, _) = quantize_f32_to_i8(&a);
        let (qb, _) = quantize_f32_to_i8(&b);
        let (qc, _) = quantize_f32_to_i8(&c);

        let sim_ab = cosine_with_query_norm_i8(&qa, l2_norm_i8(&qa), &qb);
        let sim_ac = cosine_with_query_norm_i8(&qa, l2_norm_i8(&qa), &qc);

        assert!(sim_ab > 0.9);
        assert!(sim_ac < -0.9);
    }

    #[test]
    fn i8_blob_cosine_matches_slice_cosine() {
        let a = vec![1.0f32, 2.0, 3.0, -1.0];
        let b = vec![1.1f32, 1.9, 2.8, -0.8];
        let (qa, _) = quantize_f32_to_i8(&a);
        let (qb, _) = quantize_f32_to_i8(&b);
        let blob = i8_blob_from_slice(&qb);

        let from_slice = cosine_with_query_norm_i8(&qa, l2_norm_i8(&qa), &qb);
        let from_blob = cosine_with_query_norm_i8_blob(&qa, l2_norm_i8(&qa), &blob);
        assert!((from_slice - from_blob).abs() < 1e-6);
    }

    #[test]
    fn quantize_f32_to_u8_blob_matches_two_step_pipeline() {
        // The direct blob path skips an intermediate Vec<i8>; the
        // resulting bytes and scale must be bit-for-bit identical to
        // the manual two-step process.
        let inputs: &[&[f32]] = &[
            &[],
            &[0.0],
            &[0.1, -0.25, 0.5, 1.0, -1.2, 2.3],
            &[-3.4, 0.0, 3.4, -1.7, 1.7],
        ];

        #[cfg(not(feature = "vector_quant_i8"))]
        for input in inputs {
            let (direct_blob, direct_scale) = quantize_f32_to_u8_blob(input);
            let (i8_vec, two_step_scale) = quantize_f32_to_i8(input);
            let two_step_blob = i8_blob_from_slice(&i8_vec);
            assert_eq!(direct_scale, two_step_scale);
            assert_eq!(direct_blob, two_step_blob);
        }

        #[cfg(feature = "vector_quant_i8")]
        for input in inputs {
            let (direct_blob, direct_scale) = quantize_f32_to_u8_blob(input);
            assert_eq!(direct_scale, 1.0);
            if input.is_empty() {
                assert!(direct_blob.is_empty());
                continue;
            }
            let (quantized, scales) = quantize_f32_to_i8_blockwise(input);
            let mut two_step_blob = Vec::new();
            for block_idx in 0..scales.len() {
                two_step_blob.extend_from_slice(&scales[block_idx].to_le_bytes());
                let start = block_idx * BLOCK_SIZE;
                let end = (start + BLOCK_SIZE).min(quantized.len());
                for i in start..end {
                    two_step_blob.push(quantized[i] as u8);
                }
            }
            assert_eq!(direct_blob, two_step_blob);
        }
    }

    // --- PR6 shared test helpers (deterministic, no rand dep) ---

    // Same generator as benches/vector_math.rs: reproducible run-to-run.
    fn pseudo_vec(dim: usize, seed: u32) -> Vec<f32> {
        (0..dim)
            .map(|i| {
                let x = (i as u32)
                    .wrapping_mul(2_654_435_761)
                    .wrapping_add(seed.wrapping_mul(40_503));
                ((x % 1000) as f32 / 1000.0) - 0.5
            })
            .collect()
    }

    // Independent f64 reference cosine of two i8 vectors. Different accumulation
    // width (i64) and float precision (f64) than the i32->f32 kernel, so a match
    // proves the kernel math, not just that it agrees with itself.
    fn ref_cosine_i8_f64(q: &[i8], t: &[i8]) -> f64 {
        if q.len() != t.len() || q.is_empty() {
            return 0.0;
        }
        let mut dot: i64 = 0;
        let mut qsq: i64 = 0;
        let mut tsq: i64 = 0;
        for (&a, &b) in q.iter().zip(t.iter()) {
            dot += (a as i64) * (b as i64);
            qsq += (a as i64) * (a as i64);
            tsq += (b as i64) * (b as i64);
        }
        if qsq == 0 || tsq == 0 {
            return 0.0;
        }
        (dot as f64) / ((qsq as f64).sqrt() * (tsq as f64).sqrt())
    }

    #[test]
    fn i8_blob_cosine_matches_independent_reference() {
        // Integer dot/sq are exact; only the final f32 sqrt+div can drift.
        const EPS: f64 = 1e-4;
        for &dim in &[1usize, 2, 3, 16, 384, 768, 1024, 1536] {
            let q = pseudo_vec(dim, 7);
            let t = pseudo_vec(dim, 9);
            let (qi, _) = quantize_f32_to_i8(&q);
            let (ti, _) = quantize_f32_to_i8(&t);
            let blob = i8_blob_from_slice(&ti);
            let qn = l2_norm_i8(&qi);

            let kernel = cosine_with_query_norm_i8_blob(&qi, qn, &blob) as f64;
            let reference = ref_cosine_i8_f64(&qi, &ti);
            assert!(
                (kernel - reference).abs() < EPS,
                "i8 cosine dim={dim}: kernel={kernel} ref={reference}"
            );
        }
    }

    // --- PR6 Task 2 helpers ---

    fn normalize(v: &mut [f32]) {
        let n = v.iter().map(|x| x * x).sum::<f32>().sqrt();
        if n > 0.0 {
            for x in v.iter_mut() {
                *x /= n;
            }
        }
    }

    fn det_unit(dim: usize, seed: u32) -> Vec<f32> {
        let mut v = pseudo_vec(dim, seed);
        normalize(&mut v);
        v
    }

    // Clustered corpus: vector i belongs to cluster (i % clusters); a weighted
    // blend of that cluster's center and per-vector noise, normalized.
    fn clustered_corpus(
        n: usize,
        dim: usize,
        clusters: usize,
        weight: f32,
        seed0: u32,
    ) -> Vec<Vec<f32>> {
        let centers: Vec<Vec<f32>> = (0..clusters)
            .map(|c| det_unit(dim, 1_000 + c as u32))
            .collect();
        (0..n)
            .map(|i| {
                let c = i % clusters;
                let noise = pseudo_vec(dim, seed0 + i as u32);
                let mut v: Vec<f32> = centers[c]
                    .iter()
                    .zip(noise.iter())
                    .map(|(&ce, &no)| weight * ce + (1.0 - weight) * no)
                    .collect();
                normalize(&mut v);
                v
            })
            .collect()
    }

    // Total order: score descending, then index ascending. total_cmp gives a
    // provably total order (NaN-safe), so sort output is platform-deterministic.
    fn order_desc_f64(a: &(usize, f64), b: &(usize, f64)) -> std::cmp::Ordering {
        b.1.total_cmp(&a.1).then(a.0.cmp(&b.0))
    }
    fn order_desc_f32(a: &(usize, f32), b: &(usize, f32)) -> std::cmp::Ordering {
        b.1.total_cmp(&a.1).then(a.0.cmp(&b.0))
    }

    // True cosine of the ORIGINAL f32 vectors, accumulated in f64 (boundary gap
    // >> x86/ARM ULP jitter); also the reference for cosine fidelity.
    fn cosine_f64_true(q: &[f32], t: &[f32]) -> f64 {
        let mut dot = 0.0f64;
        let mut qsq = 0.0f64;
        let mut tsq = 0.0f64;
        for (a, b) in q.iter().zip(t.iter()) {
            let (a, b) = (*a as f64, *b as f64);
            dot += a * b;
            qsq += a * a;
            tsq += b * b;
        }
        if qsq == 0.0 || tsq == 0.0 {
            0.0
        } else {
            dot / (qsq.sqrt() * tsq.sqrt())
        }
    }

    #[test]
    fn i8_topk_recall_matches_f32_within_floor() {
        const N: usize = 2000;
        const Q: usize = 32;
        const DIM: usize = 768;
        const K: usize = 10;
        const CLUSTERS: usize = 16;
        const WEIGHT: f32 = 0.85;
        // Locked from measured baseline recall@10 = 0.996875 (deterministic:
        // f64 GT + integer-exact i8 => bit-identical across x86/ARM). FLOOR =
        // floor(0.9969 - 0.02) = 0.98, margin ~0.017 (~5 hits of 320).
        const MIN_RECALL: f32 = 0.98;
        const _: () = assert!(MIN_RECALL >= 0.9, "MIN_RECALL must be a real floor");

        let corpus = clustered_corpus(N, DIM, CLUSTERS, WEIGHT, 5_000);
        let queries = clustered_corpus(Q, DIM, CLUSTERS, WEIGHT, 9_000);
        let corpus_blob: Vec<Vec<u8>> = corpus
            .iter()
            .map(|v| i8_blob_from_slice(&quantize_f32_to_i8(v).0))
            .collect();

        let mut recall_sum = 0.0f32;
        for query in &queries {
            let mut gt_scores: Vec<(usize, f64)> = corpus
                .iter()
                .enumerate()
                .map(|(i, c)| (i, cosine_f64_true(query, c)))
                .collect();
            gt_scores.sort_by(order_desc_f64);
            let gt: std::collections::HashSet<usize> =
                gt_scores.iter().take(K).map(|(i, _)| *i).collect();

            let (qi, _) = quantize_f32_to_i8(query);
            let qn_i8 = l2_norm_i8(&qi);
            let mut i8_scores: Vec<(usize, f32)> = corpus_blob
                .iter()
                .enumerate()
                .map(|(i, blob)| (i, cosine_with_query_norm_i8_blob(&qi, qn_i8, blob)))
                .collect();
            i8_scores.sort_by(order_desc_f32);
            let got: std::collections::HashSet<usize> =
                i8_scores.iter().take(K).map(|(i, _)| *i).collect();

            recall_sum += gt.intersection(&got).count() as f32 / K as f32;
        }
        let recall = recall_sum / Q as f32;
        println!("PR6 recall@{K} (N={N} Q={Q} dim={DIM} clusters={CLUSTERS}) = {recall}");
        assert!(
            recall >= MIN_RECALL,
            "i8 recall@{K} regressed: {recall} < {MIN_RECALL}"
        );
    }

    #[test]
    fn i8_cosine_fidelity_vs_true_f32() {
        const N: usize = 2000;
        const Q: usize = 32;
        const DIM: usize = 768;
        const CLUSTERS: usize = 16;
        const WEIGHT: f32 = 0.85;
        // Locked from measured max error 0.00121 (deterministic). 0.005 ~= 4x the
        // baseline: sensitive to a lossier future quantizer yet never flaky.
        const MAX_COS_ERR: f64 = 0.005;
        const _: () = assert!(MAX_COS_ERR < 0.1, "MAX_COS_ERR must be a real bound");

        let corpus = clustered_corpus(N, DIM, CLUSTERS, WEIGHT, 5_000);
        let queries = clustered_corpus(Q, DIM, CLUSTERS, WEIGHT, 9_000);
        let corpus_blob: Vec<Vec<u8>> = corpus
            .iter()
            .map(|v| i8_blob_from_slice(&quantize_f32_to_i8(v).0))
            .collect();

        let mut max_err = 0.0f64;
        for query in &queries {
            let (qi, _) = quantize_f32_to_i8(query);
            let qn_i8 = l2_norm_i8(&qi);
            for (c, blob) in corpus.iter().zip(corpus_blob.iter()) {
                let i8c = cosine_with_query_norm_i8_blob(&qi, qn_i8, blob) as f64;
                let truec = cosine_f64_true(query, c);
                let e = (i8c - truec).abs();
                if e > max_err {
                    max_err = e;
                }
            }
        }
        println!("PR6 max|cosine_i8 - cosine_f32_true| (N={N} Q={Q} dim={DIM}) = {max_err}");
        assert!(
            max_err <= MAX_COS_ERR,
            "i8 cosine fidelity regressed: max err {max_err} > {MAX_COS_ERR}"
        );
    }

    #[test]
    fn blockwise_quantize_dequantize_roundtrip() {
        // Create an input vector with some outliers in a specific block
        let mut input = vec![0.0f32; 100];
        // Block 0: small values
        for i in 0..32 {
            input[i] = 0.05 * (i as f32 / 32.0);
        }
        // Block 1: huge values (outliers)
        for i in 32..64 {
            input[i] = 10.0 * (i as f32 / 64.0);
        }
        // Block 2: mid values
        for i in 64..96 {
            input[i] = 1.0 * (i as f32 / 96.0);
        }

        let (q, scales) = quantize_f32_to_i8_blockwise(&input);
        assert_eq!(q.len(), input.len());
        assert_eq!(scales.len(), 4); // 100 elements / 32 block size = 4 blocks

        let restored = dequantize_i8_to_f32_blockwise(&q, &scales);
        assert_eq!(restored.len(), input.len());

        // Check that quantization error in block 0 is small despite the large outlier in block 1
        for i in 0..32 {
            let err = (input[i] - restored[i]).abs();
            // With block-wise, block 0 scale is around 0.05/127 ~ 0.0004. Error should be very small.
            assert!(
                err < 0.001,
                "Block 0 index {}: original={}, restored={}, err={}",
                i,
                input[i],
                restored[i],
                err
            );
        }

        // Verify with global quantization, the error in block 0 would be much larger
        let (global_q, global_scale) = quantize_f32_to_i8(&input);
        let global_restored = dequantize_i8_to_f32(&global_q, global_scale);
        let mut global_max_err_block0 = 0.0f32;
        for i in 0..32 {
            global_max_err_block0 =
                global_max_err_block0.max((input[i] - global_restored[i]).abs());
        }
        // Global scale is around 10.0/127 ~ 0.08. Maximum quantization error can be up to 0.04.
        println!(
            "Block-wise block 0 max error: {}",
            (0..32)
                .map(|i| (input[i] - restored[i]).abs())
                .fold(0.0f32, f32::max)
        );
        println!("Global block 0 max error: {}", global_max_err_block0);
        assert!(global_max_err_block0 > 0.01);
    }

    #[test]
    fn test_blockwise_cosine_similarity() {
        // Create two 768-dim vectors with different patterns and outliers
        let mut a = vec![0.0f32; 768];
        let mut b = vec![0.0f32; 768];
        for i in 0..768 {
            a[i] = 0.1 * (i as f32).sin();
            b[i] = 0.15 * (i as f32).cos();
        }
        // Introduce massive outliers in block 5
        for i in 160..192 {
            a[i] *= 25.0;
            b[i] *= 20.0;
        }

        let true_cos = cosine_with_query_norm_f32(&a, l2_norm_f32(&a), &b);

        let query_q8 = QueryQ8::new(&a);
        let (packed_blob_b, _) = quantize_f32_to_u8_blob(&b);

        // For legacy comparison fallback
        let (legacy_q_a, _) = quantize_f32_to_i8(&a);
        let legacy_norm_a = l2_norm_i8(&legacy_q_a);

        let approx_cos =
            cosine_similarity_q8(&query_q8, &packed_blob_b, &legacy_q_a, legacy_norm_a);

        println!("True f32 cosine: {}", true_cos);
        println!("Block-wise approx cosine: {}", approx_cos);

        let err = (true_cos - approx_cos).abs();
        assert!(
            err < 0.005,
            "Block-wise cosine error too large: {} (true={}, approx={})",
            err,
            true_cos,
            approx_cos
        );
    }

    #[test]
    fn test_vabq_quantization_and_similarity() {
        use crate::api::vector_math::cosine_with_query_norm_f32;
        use crate::api::vector_math::l2_norm_f32;
        use crate::api::vector_quant::{cosine_similarity_vabq, quantize_f32_to_vabq, QueryVABQ};
        use rand::Rng;

        let mut rng = rand::thread_rng();

        for &dim in &[384, 768, 1024] {
            let mut a = vec![0.0f32; dim];
            let mut b = vec![0.0f32; dim];

            for i in 0..dim {
                a[i] = rng.gen_range(-1.0..1.0);
                b[i] = rng.gen_range(-1.0..1.0) + a[i] * 0.5; // correlated
            }

            let true_cos = cosine_with_query_norm_f32(&a, l2_norm_f32(&a), &b);

            let query_vabq = QueryVABQ::new(&a);
            let (packed_blob_b, _) = quantize_f32_to_vabq(&b);

            let approx_cos = cosine_similarity_vabq(&query_vabq, &packed_blob_b);

            println!("Dim {}: True f32 cosine: {}", dim, true_cos);
            println!("Dim {}: VABQ approx cosine: {}", dim, approx_cos);

            let err = (true_cos - approx_cos).abs();
            assert!(
                err < 0.05,
                "VABQ cosine error too large for dim {}: {} (true={}, approx={})",
                dim,
                err,
                true_cos,
                approx_cos
            );
        }
    }

    #[cfg(feature = "vector_quant_i8")]
    #[test]
    fn q8_fallback_blob_restores_nonstandard_dimension() {
        let input = vec![1.0, -0.5, 0.25, 0.0];
        let (blob, _) = quantize_f32_to_vabq(&input);

        let restored =
            decode_packed_blob_to_f32(&blob).expect("Q8 fallback blobs must remain rebuildable");

        assert_eq!(restored.len(), input.len());
    }

    #[test]
    fn vabq_384_roundtrip_preserves_low_variance_tail_dimensions() {
        let mut input = vec![0.0f32; 384];
        for permuted_index in 352..384 {
            input[PI_ALL_MINILM_L6_V2[permuted_index]] = 0.5;
        }

        let (blob, _) = quantize_f32_to_vabq(&input);
        let restored = decode_packed_blob_to_f32(&blob).unwrap();

        for permuted_index in 352..384 {
            assert!(
                restored[PI_ALL_MINILM_L6_V2[permuted_index]].abs() > 0.1,
                "tail dimension at permuted index {permuted_index} was not preserved"
            );
        }
    }

    #[test]
    fn supported_vabq_dimensions_use_versioned_full_length_formats() {
        for (dimension, expected_len, expected_profile) in
            [(384, 421, 1), (768, 789, 2), (1024, 1109, 3)]
        {
            let input = vec![0.25f32; dimension];
            let (blob, _) = quantize_f32_to_vabq(&input);

            assert_eq!(&blob[..2], &[0x02, 0x01]);
            assert_eq!(u16::from_le_bytes([blob[2], blob[3]]) as usize, dimension);
            assert_eq!(blob[4], expected_profile);
            assert_eq!(blob.len(), expected_len);
            assert_eq!(decode_packed_blob_to_f32(&blob).unwrap().len(), dimension);
        }
    }

    #[test]
    fn vabq_similarity_rejects_mismatched_profile_header() {
        let query = vec![0.25f32; 384];
        let (mut blob, _) = quantize_f32_to_vabq(&query);
        blob[4] = 2;

        assert_eq!(cosine_similarity_vabq(&QueryVABQ::new(&query), &blob), 0.0);
        assert!(decode_packed_blob_to_f32(&blob).is_none());
    }

    #[test]
    fn malformed_versioned_vabq_header_fails_closed_without_q8_fallback() {
        let mut blob = vec![0u8; 789];
        blob[..5].copy_from_slice(&[VABQ_TAG, VABQ_FORMAT_VERSION, 0x00, 0x03, 0xff]);
        let query = vec![0.25f32; 768];

        assert!(decode_packed_blob_to_f32(&blob).is_none());
        assert!(score_persisted_quantized_blob(&query, &blob).is_err());
    }

    #[test]
    fn legacy_vabq_blobs_have_explicit_read_and_rebuild_behavior() {
        let _guard = active_profile_test_guard();
        configure_active_vabq_profile(Some("allMiniLmL6V2".to_string()), 384).unwrap();
        let mut input = vec![0.0f32; 384];
        for permuted_index in 352..384 {
            input[PI_ALL_MINILM_L6_V2[permuted_index]] = 0.5;
        }
        let (versioned, _) = quantize_f32_to_vabq_for_profile(&input, VabqProfile::AllMiniLmL6V2);
        let mut legacy_full = vec![VABQ_TAG];
        legacy_full.extend_from_slice(&versioned[VABQ_HEADER_LEN..]);
        assert_eq!(legacy_full.len(), 417);
        assert_eq!(
            decode_packed_blob_to_f32(&legacy_full).unwrap().len(),
            input.len()
        );
        assert!(score_vabq_blob_for_active_profile(&input, &legacy_full)
            .unwrap()
            .is_some());

        let legacy_truncated = &legacy_full[..397];
        let restored = decode_packed_blob_to_f32(legacy_truncated).unwrap();
        for permuted_index in 352..384 {
            assert_eq!(restored[PI_ALL_MINILM_L6_V2[permuted_index]], 0.0);
        }

        for (profile, dimension, expected_len) in [
            (VabqProfile::AllMpnetBaseV2, 768, 785),
            (VabqProfile::BgeM3, 1024, 1105),
        ] {
            let input = vec![0.25f32; dimension];
            let (versioned, _) = quantize_f32_to_vabq_for_profile(&input, profile);
            let mut legacy = vec![VABQ_TAG];
            legacy.extend_from_slice(&versioned[VABQ_HEADER_LEN..]);
            assert_eq!(legacy.len(), expected_len);
            assert_eq!(decode_packed_blob_to_f32(&legacy).unwrap().len(), dimension);
        }
        configure_active_vabq_profile(None, 0).unwrap();
    }

    #[cfg(feature = "vector_quant_i8")]
    fn q8_0_768_tag_collision_fixture() -> Vec<u8> {
        let mut blob = Vec::with_capacity(24 * 36);
        for block_idx in 0..24 {
            // A valid little-endian f32 scale whose first byte is VABQ_TAG.
            // The remaining blocks use an ordinary finite scale so this is a
            // deterministic, structurally valid 768-d Q8_0 payload.
            let scale = if block_idx == 0 {
                f32::from_bits(0x3f80_0002)
            } else {
                0.5
            };
            blob.extend_from_slice(&scale.to_le_bytes());
            for lane in 0..BLOCK_SIZE {
                blob.push(((block_idx * BLOCK_SIZE + lane) as i8).wrapping_sub(96) as u8);
            }
        }
        assert_eq!(blob.len(), 864);
        assert_eq!(blob[0], VABQ_TAG);
        blob
    }

    #[cfg(feature = "vector_quant_i8")]
    #[test]
    fn q8_0_768_tag_collision_decodes_as_q8_not_vabq() {
        let blob = q8_0_768_tag_collision_fixture();

        let decoded = decode_packed_blob_to_f32(&blob)
            .expect("a valid Q8_0 blob must not be rejected because its first scale byte is 0x02");

        assert_eq!(decoded.len(), 768);
        assert!(decoded.iter().all(|value| value.is_finite()));
    }

    #[cfg(feature = "vector_quant_i8")]
    #[test]
    fn q8_0_768_tag_collision_scores_with_q8_dispatch() {
        let blob = q8_0_768_tag_collision_fixture();
        let query: Vec<f32> = (0..768)
            .map(|index| (index as f32 - 384.0) / 384.0)
            .collect();
        let (query_i8, _) = quantize_f32_to_i8(&query);
        let query_i8_norm = l2_norm_i8(&query_i8);
        let expected = cosine_similarity_q8(&QueryQ8::new(&query), &blob, &query_i8, query_i8_norm);

        let actual = score_persisted_quantized_blob(&query, &blob)
            .expect("Q8_0 dispatch must not return a VABQ error")
            .expect("Q8_0 dispatch must score a valid blob");

        assert!(
            (actual - expected).abs() < 1e-6,
            "actual={actual}, expected={expected}"
        );
    }
}

/// Decodes a packed quantization blob (VABQ or Q8_0) back into a full-precision f32 vector.
/// Used during HNSW index rebuilds when the original f32 embedding is discarded to save space.
pub(crate) fn decode_packed_blob_to_f32(blob: &[u8]) -> Option<Vec<f32>> {
    if blob.is_empty() {
        return None;
    }

    // VABQ is selected only after its complete layout validates. A Q8_0
    // scale's low byte is unconstrained and may equal VABQ_TAG (0x02).
    if let Some(layout) = vabq_blob_layout(blob) {
        let (pi_array, _profile_d_high, _profile_d_low) = layout.profile.layout();

        let mut permuted = vec![0.0f32; layout.dimension];
        let mut blob_idx = layout.payload_offset;

        // Decode high-variance (INT8, b=16)
        for block_idx in 0..layout.num_blocks_h {
            let scale = f32::from_le_bytes([
                blob[blob_idx],
                blob[blob_idx + 1],
                blob[blob_idx + 2],
                blob[blob_idx + 3],
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
        for block_idx in 0..layout.num_blocks_l {
            let scale = f32::from_le_bytes([
                blob[blob_idx],
                blob[blob_idx + 1],
                blob[blob_idx + 2],
                blob[blob_idx + 3],
            ]);
            blob_idx += 4;

            let block_start = block_idx * VABQ_BL;
            let block_len = (layout.stored_d_low - block_start).min(VABQ_BL);
            let start = layout.d_high + block_start;
            for i in (0..block_len).step_by(2) {
                let packed = blob[blob_idx];
                blob_idx += 1;

                // Sign extension for 4-bit two's complement
                let v0 = (packed & 0x0F) as i8;
                let v0 = if v0 > 7 { v0 - 16 } else { v0 } as f32;

                let v1 = (packed >> 4) as i8;
                let v1 = if v1 > 7 { v1 - 16 } else { v1 } as f32;

                permuted[start + i] = v0 * scale;
                if i + 1 < block_len {
                    permuted[start + i + 1] = v1 * scale;
                }
            }
        }

        // Inverse permutation
        let mut original = vec![0.0f32; layout.dimension];
        for i in 0..layout.dimension {
            original[pi_array[i]] = permuted[i];
        }

        return Some(original);
    }

    if has_versioned_vabq_envelope(blob) {
        return None;
    }

    // Q8_0 format (block size 32 -> 36 bytes per block)
    let block_size = 32;
    let expected_dim = q8_0_blob_dimension(blob)?;
    let num_blocks = (expected_dim + block_size - 1) / block_size;

    let mut decoded = vec![0.0f32; expected_dim];
    let mut blob_idx = 0;

    for block_idx in 0..num_blocks {
        let scale = f32::from_le_bytes([
            blob[blob_idx],
            blob[blob_idx + 1],
            blob[blob_idx + 2],
            blob[blob_idx + 3],
        ]);
        blob_idx += 4;

        let start = block_idx * block_size;
        let values_in_block = (expected_dim - start).min(block_size);
        for i in 0..values_in_block {
            let q = blob[blob_idx] as i8 as f32;
            blob_idx += 1;
            decoded[start + i] = q * scale;
        }
    }
    return Some(decoded);
}

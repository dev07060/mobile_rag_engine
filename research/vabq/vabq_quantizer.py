"""
VABQ Quantizer (Step 2)
-----------------------
Core implementation of all four quantization baselines and the proposed VABQ algorithm.

Baselines:
  1. Uniform Quantization     - single global scale, 8-bit
  2. Standard Q8_0            - fixed 32-dim blocks, 8-bit
  3. Product Quantization (PQ)- codebook-based sub-space compression
  4. VABQ (Proposed)          - variance-aware dual-precision (INT8 + INT4) adaptive blocks

Each quantizer exposes:
  - quantize(vectors: np.ndarray) -> bytes  (database storage representation)
  - dequantize(data: bytes, n_vecs: int, n_dims: int) -> np.ndarray  (f32 reconstruction)
  - bytes_per_vector: int  (storage cost)
  - cosine_similarity_batch(query_f32, db_quantized_list) -> np.ndarray of scores
"""

from __future__ import annotations

import json
import struct
import time
from abc import ABC, abstractmethod
from typing import List, Tuple

import numpy as np
from sklearn.cluster import MiniBatchKMeans


# ─────────────────────────────────────────────────────────────────────────────
# Base class
# ─────────────────────────────────────────────────────────────────────────────

class VectorQuantizer(ABC):
    """Abstract base class for all quantizers."""

    @property
    @abstractmethod
    def name(self) -> str:
        ...

    @property
    @abstractmethod
    def bytes_per_vector(self) -> int:
        ...

    @abstractmethod
    def fit(self, train_vectors: np.ndarray) -> None:
        """Train any parameters (e.g. PQ codebooks) on training data."""
        ...

    @abstractmethod
    def quantize(self, vectors: np.ndarray) -> np.ndarray:
        """Compress vectors. Returns an object array of bytes blobs."""
        ...

    @abstractmethod
    def cosine_similarity(self, query_f32: np.ndarray, db_vectors: np.ndarray) -> np.ndarray:
        """
        Compute approximate cosine similarity between a single query (f32)
        and a batch of quantized vectors (returned from quantize()).
        Returns: 1D array of shape (n_db,)
        """
        ...


# ─────────────────────────────────────────────────────────────────────────────
# 1. Uniform Quantization (Legacy)
# ─────────────────────────────────────────────────────────────────────────────

class UniformQuantizer(VectorQuantizer):
    """
    Legacy 8-bit scalar quantization with a single global min/max scale factor.
    One (global_min, global_scale) pair per database, stored once.
    Each vector: 1 byte per dimension → n_dims bytes per vector.
    """

    def __init__(self, n_dims: int):
        self.n_dims = n_dims
        self._global_min: float = 0.0
        self._global_scale: float = 1.0

    @property
    def name(self) -> str:
        return "Uniform Q8 (Legacy)"

    @property
    def bytes_per_vector(self) -> int:
        return self.n_dims  # 1 byte per dim (INT8)

    def fit(self, train_vectors: np.ndarray) -> None:
        self._global_min = float(train_vectors.min())
        global_max = float(train_vectors.max())
        self._global_scale = (global_max - self._global_min) / 255.0

    def quantize(self, vectors: np.ndarray) -> np.ndarray:
        """Returns array of shape (n, n_dims) dtype=uint8."""
        clamped = np.clip(vectors, self._global_min, self._global_min + 255 * self._global_scale)
        quantized = ((clamped - self._global_min) / self._global_scale).astype(np.uint8)
        return quantized

    def _dequantize(self, q: np.ndarray) -> np.ndarray:
        return q.astype(np.float32) * self._global_scale + self._global_min

    def cosine_similarity(self, query_f32: np.ndarray, db_quantized: np.ndarray) -> np.ndarray:
        """db_quantized: (n_db, n_dims) uint8"""
        db_f32 = self._dequantize(db_quantized)
        norms_db = np.linalg.norm(db_f32, axis=1, keepdims=True)
        norms_db = np.where(norms_db == 0, 1e-9, norms_db)
        db_normed = db_f32 / norms_db

        q_norm = np.linalg.norm(query_f32)
        q_normed = query_f32 / (q_norm + 1e-9)
        return db_normed @ q_normed


# ─────────────────────────────────────────────────────────────────────────────
# 2. Standard Q8_0 (32-dim fixed blocks, 8-bit)
# ─────────────────────────────────────────────────────────────────────────────

class Q8_0Quantizer(VectorQuantizer):
    """
    Block-wise 8-bit scalar quantization with fixed 32-dimension blocks.
    Matches the implementation used in mobile_rag_engine v0.20.0.

    Storage per vector:
        n_blocks = ceil(n_dims / block_size)
        bytes = n_dims * 1 (INT8) + n_blocks * 4 (float32 scale per block)
    """

    def __init__(self, n_dims: int, block_size: int = 32):
        self.n_dims = n_dims
        self.block_size = block_size
        self.n_blocks = (n_dims + block_size - 1) // block_size

    @property
    def name(self) -> str:
        return f"Q8_0 (block={self.block_size})"

    @property
    def bytes_per_vector(self) -> int:
        return self.n_dims + self.n_blocks * 4  # INT8 elements + float32 scales

    def fit(self, train_vectors: np.ndarray) -> None:
        pass  # No training needed

    def _pad(self, vectors: np.ndarray) -> np.ndarray:
        """Pad to multiple of block_size."""
        rem = vectors.shape[1] % self.block_size
        if rem != 0:
            pad = self.block_size - rem
            vectors = np.pad(vectors, ((0, 0), (0, pad)), mode="constant")
        return vectors

    def quantize(self, vectors: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """
        Returns:
            q_int8: (n, n_padded_dims) int8 array
            scales: (n, n_blocks) float32 array
        """
        n = vectors.shape[0]
        v_pad = self._pad(vectors)
        n_padded = v_pad.shape[1]
        n_blocks_actual = n_padded // self.block_size

        v_blocks = v_pad.reshape(n, n_blocks_actual, self.block_size)
        amax = np.max(np.abs(v_blocks), axis=2, keepdims=True)  # (n, n_blocks, 1)
        scales = amax[:, :, 0].astype(np.float32)  # (n, n_blocks)
        safe_amax = np.where(amax == 0, 1e-9, amax)
        v_normed = v_blocks / safe_amax  # normalized to [-1, 1]
        q_int8 = np.clip(np.round(v_normed * 127), -127, 127).astype(np.int8)

        return q_int8.reshape(n, n_padded), scales

    def cosine_similarity(self, query_f32: np.ndarray, db_quantized) -> np.ndarray:
        """db_quantized: (q_int8, scales) tuples returned from quantize()"""
        q_int8, scales = db_quantized

        n = q_int8.shape[0]
        n_padded = q_int8.shape[1]
        n_blocks_actual = n_padded // self.block_size

        v_blocks = q_int8.reshape(n, n_blocks_actual, self.block_size).astype(np.float32)
        scale_expanded = scales[:, :, np.newaxis]  # (n, n_blocks, 1)
        db_f32 = (v_blocks * scale_expanded / 127.0).reshape(n, n_padded)
        db_f32 = db_f32[:, :self.n_dims]

        norms_db = np.linalg.norm(db_f32, axis=1, keepdims=True)
        norms_db = np.where(norms_db == 0, 1e-9, norms_db)
        db_normed = db_f32 / norms_db

        q_norm = np.linalg.norm(query_f32)
        q_normed = query_f32 / (q_norm + 1e-9)
        return db_normed @ q_normed


# ─────────────────────────────────────────────────────────────────────────────
# 3. Product Quantization (PQ)
# ─────────────────────────────────────────────────────────────────────────────

class ProductQuantizer(VectorQuantizer):
    """
    Standard Product Quantization (PQ) with M sub-spaces and K=256 codewords.
    Storage per vector: M bytes (1 byte per sub-space code).
    Codebook: M * 256 * (n_dims/M) float32 values.
    """

    def __init__(self, n_dims: int, M: int = 16, K: int = 256):
        self.n_dims = n_dims
        self.M = M  # number of sub-spaces
        self.K = K  # number of codewords per sub-space
        self.sub_dim = n_dims // M
        assert n_dims % M == 0, f"n_dims ({n_dims}) must be divisible by M ({M})"
        self.codebooks: np.ndarray | None = None  # (M, K, sub_dim)

    @property
    def name(self) -> str:
        return f"PQ (M={self.M}, K={self.K})"

    @property
    def bytes_per_vector(self) -> int:
        return self.M  # 1 byte per sub-space

    def fit(self, train_vectors: np.ndarray) -> None:
        """Fit K-means codebooks per sub-space."""
        n_dims = train_vectors.shape[1]
        assert n_dims == self.n_dims

        self.codebooks = np.zeros((self.M, self.K, self.sub_dim), dtype=np.float32)
        print(f"  Fitting PQ codebooks (M={self.M}, K={self.K}, sub_dim={self.sub_dim})...")
        for m in range(self.M):
            sub = train_vectors[:, m * self.sub_dim: (m + 1) * self.sub_dim].astype(np.float32)
            km = MiniBatchKMeans(n_clusters=self.K, random_state=42, batch_size=4096, n_init=3)
            km.fit(sub)
            self.codebooks[m] = km.cluster_centers_.astype(np.float32)
            if (m + 1) % 4 == 0 or m == self.M - 1:
                print(f"    Sub-space {m+1}/{self.M} trained.")

    def quantize(self, vectors: np.ndarray) -> np.ndarray:
        """Returns codes: (n, M) uint8"""
        assert self.codebooks is not None, "Call fit() first."
        n = vectors.shape[0]
        codes = np.zeros((n, self.M), dtype=np.uint8)
        for m in range(self.M):
            sub = vectors[:, m * self.sub_dim: (m + 1) * self.sub_dim].astype(np.float32)
            dists = np.sum(
                (sub[:, np.newaxis, :] - self.codebooks[m][np.newaxis, :, :]) ** 2, axis=2
            )
            codes[:, m] = np.argmin(dists, axis=1).astype(np.uint8)
        return codes

    def _decode(self, codes: np.ndarray) -> np.ndarray:
        """Decode (n, M) codes back to (n, n_dims) float32."""
        n = codes.shape[0]
        decoded = np.zeros((n, self.n_dims), dtype=np.float32)
        for m in range(self.M):
            decoded[:, m * self.sub_dim: (m + 1) * self.sub_dim] = self.codebooks[m][codes[:, m]]
        return decoded

    def cosine_similarity(self, query_f32: np.ndarray, db_codes: np.ndarray) -> np.ndarray:
        """db_codes: (n_db, M) uint8 from quantize()."""
        db_f32 = self._decode(db_codes)
        norms_db = np.linalg.norm(db_f32, axis=1, keepdims=True)
        norms_db = np.where(norms_db == 0, 1e-9, norms_db)
        db_normed = db_f32 / norms_db

        q_norm = np.linalg.norm(query_f32)
        q_normed = query_f32 / (q_norm + 1e-9)
        return db_normed @ q_normed


# ─────────────────────────────────────────────────────────────────────────────
# 4. VABQ (Proposed) - Variance-aware Adaptive Block Quantization
# ─────────────────────────────────────────────────────────────────────────────

class VABQQuantizer(VectorQuantizer):
    """
    Variance-aware Adaptive Block Quantization (VABQ).

    Algorithm:
    1. Dimensions are reordered by descending variance (high-variance first)
       using a pre-computed offline variance map.
    2. The first N_high dimensions (covering ~75% of total variance) are
       quantized to INT8 with small block size (16 dims → fine-grained scale).
    3. The remaining N_low dimensions are quantized to INT4 with large block
       size (64 dims → aggressive compression).

    Storage per vector:
        high_seg: N_high bytes (INT8) + ceil(N_high/16) * 4 bytes (scales)
        low_seg:  N_low / 2 bytes (INT4 packed) + ceil(N_low/64) * 4 bytes (scales)
        + 4 bytes header (N_high as uint16 + block sizes)
    """

    def __init__(
        self,
        n_dims: int,
        sorted_indices: List[int],
        n_high_ratio: float = 0.75,
        high_block_size: int = 16,
        low_block_size: int = 64,
    ):
        self.n_dims = n_dims
        self.sorted_indices = np.array(sorted_indices, dtype=np.int32)
        self.inverse_indices = np.argsort(self.sorted_indices)  # for reconstruction

        # Determine split point (how many dims go into the HIGH-variance segment)
        self.n_high = self._find_n_high_from_ratio(sorted_indices, n_high_ratio)
        self.n_low = n_dims - self.n_high
        self.high_block_size = high_block_size
        self.low_block_size = low_block_size

        self.n_high_blocks = (self.n_high + high_block_size - 1) // high_block_size
        self.n_low_blocks = (self.n_low + low_block_size - 1) // low_block_size

        print(f"[VABQ] n_dims={n_dims}, n_high={self.n_high} (INT8/b{high_block_size}), "
              f"n_low={self.n_low} (INT4/b{low_block_size})")
        print(f"[VABQ] bytes_per_vector={self.bytes_per_vector}")

    def _find_n_high_from_ratio(self, sorted_indices: List[int], ratio: float) -> int:
        """
        This is called with sorted_indices already sorted by variance descending.
        We use ratio of dimension count directly since we don't have variances here.
        The caller should pass the actual variance-based n_high or use a simple ratio.
        """
        return int(len(sorted_indices) * ratio)

    @classmethod
    def from_variance_map(
        cls,
        variance_map_path: str,
        n_high_ratio: float = 0.75,
        high_block_size: int = 16,
        low_block_size: int = 64,
    ) -> "VABQQuantizer":
        """Load sorted dimension indices from a profiler-generated JSON file."""
        with open(variance_map_path) as f:
            vm = json.load(f)
        return cls(
            n_dims=vm["n_dims"],
            sorted_indices=vm["sorted_indices"],
            n_high_ratio=n_high_ratio,
            high_block_size=high_block_size,
            low_block_size=low_block_size,
        )

    @classmethod
    def from_runtime_variance(
        cls,
        vectors: np.ndarray,
        n_high_ratio: float = 0.75,
        high_block_size: int = 16,
        low_block_size: int = 64,
    ) -> "VABQQuantizer":
        """Compute variance from a set of vectors at runtime (for simulation)."""
        variances = np.var(vectors, axis=0)
        sorted_indices = np.argsort(variances)[::-1].tolist()
        n_dims = vectors.shape[1]
        return cls(
            n_dims=n_dims,
            sorted_indices=sorted_indices,
            n_high_ratio=n_high_ratio,
            high_block_size=high_block_size,
            low_block_size=low_block_size,
        )

    @property
    def name(self) -> str:
        return f"VABQ (h={self.n_high}×INT8/b{self.high_block_size}, l={self.n_low}×INT4/b{self.low_block_size})"

    @property
    def bytes_per_vector(self) -> int:
        high_bytes = self.n_high + self.n_high_blocks * 4  # INT8 dims + float32 scales
        low_bytes = (self.n_low + 1) // 2 + self.n_low_blocks * 4  # INT4 packed + float32 scales
        return high_bytes + low_bytes

    def fit(self, train_vectors: np.ndarray) -> None:
        pass  # No codebook training; variance map is pre-computed

    def _quantize_int8_blocks(self, segment: np.ndarray, block_size: int):
        """Quantize a (n, n_seg) array to INT8 with per-block scales."""
        n, n_seg = segment.shape
        n_blocks = (n_seg + block_size - 1) // block_size
        pad = n_blocks * block_size - n_seg
        if pad > 0:
            segment = np.pad(segment, ((0, 0), (0, pad)), mode="constant")

        blocks = segment.reshape(n, n_blocks, block_size)
        amax = np.max(np.abs(blocks), axis=2, keepdims=True)
        scales = amax[:, :, 0].astype(np.float32)
        safe_amax = np.where(amax == 0, 1e-9, amax)
        normed = blocks / safe_amax
        q = np.clip(np.round(normed * 127), -127, 127).astype(np.int8)
        return q.reshape(n, n_blocks * block_size)[:, :n_seg], scales

    def _quantize_int4_blocks(self, segment: np.ndarray, block_size: int):
        """
        Quantize a (n, n_seg) array to INT4 (values in [-8, 7]).
        Two INT4 values are packed per byte.
        Returns:
            packed: (n, ceil(n_seg/2)) uint8 array
            scales: (n, n_blocks) float32 array
        """
        n, n_seg = segment.shape
        n_blocks = (n_seg + block_size - 1) // block_size
        pad = n_blocks * block_size - n_seg
        if pad > 0:
            segment = np.pad(segment, ((0, 0), (0, pad)), mode="constant")

        blocks = segment.reshape(n, n_blocks, block_size)
        amax = np.max(np.abs(blocks), axis=2, keepdims=True)
        scales = amax[:, :, 0].astype(np.float32)
        safe_amax = np.where(amax == 0, 1e-9, amax)
        normed = blocks / safe_amax  # [-1, 1]
        q = np.clip(np.round(normed * 7), -8, 7).astype(np.int8)

        flat = q.reshape(n, n_blocks * block_size)[:, :n_seg + (n_seg % 2)]
        # Pad to even number if needed
        if flat.shape[1] % 2 != 0:
            flat = np.pad(flat, ((0, 0), (0, 1)), mode="constant")

        # Pack two INT4 into one byte
        low = (flat[:, ::2] & 0x0F).astype(np.uint8)
        high = ((flat[:, 1::2] & 0x0F) << 4).astype(np.uint8)
        packed = (low | high).astype(np.uint8)

        return packed, scales

    def quantize(self, vectors: np.ndarray):
        """
        Returns a tuple:
            (high_q, high_scales, low_packed, low_scales)
        """
        # 1. Reorder dimensions by variance (high-variance first)
        v_reordered = vectors[:, self.sorted_indices]

        # 2. Split into high and low variance segments
        high_seg = v_reordered[:, :self.n_high]
        low_seg = v_reordered[:, self.n_high:]

        # 3. Quantize each segment
        high_q, high_scales = self._quantize_int8_blocks(high_seg, self.high_block_size)
        low_packed, low_scales = self._quantize_int4_blocks(low_seg, self.low_block_size)

        return (high_q, high_scales, low_packed, low_scales)

    def _dequantize_int8(self, q: np.ndarray, scales: np.ndarray, n_seg: int, block_size: int) -> np.ndarray:
        """Reconstruct float32 from INT8 quantized blocks."""
        n = q.shape[0]
        n_blocks = scales.shape[1]
        pad_len = n_blocks * block_size
        q_pad = np.pad(q, ((0, 0), (0, pad_len - q.shape[1])), mode="constant") if q.shape[1] < pad_len else q
        blocks = q_pad.reshape(n, n_blocks, block_size).astype(np.float32)
        blocks = blocks * scales[:, :, np.newaxis] / 127.0
        return blocks.reshape(n, pad_len)[:, :n_seg]

    def _dequantize_int4(self, packed: np.ndarray, scales: np.ndarray, n_seg: int, block_size: int) -> np.ndarray:
        """Reconstruct float32 from INT4 packed bytes."""
        n = packed.shape[0]
        # Unpack
        low = (packed & 0x0F).astype(np.int8)
        high = ((packed >> 4) & 0x0F).astype(np.int8)
        # Sign-extend 4-bit to 8-bit
        low = np.where(low > 7, low - 16, low)
        high = np.where(high > 7, high - 16, high)

        flat = np.empty((n, packed.shape[1] * 2), dtype=np.int8)
        flat[:, ::2] = low
        flat[:, 1::2] = high
        flat = flat[:, :n_seg]

        n_blocks = scales.shape[1]
        pad_len = n_blocks * block_size
        if flat.shape[1] < pad_len:
            flat = np.pad(flat, ((0, 0), (0, pad_len - flat.shape[1])), mode="constant")
        blocks = flat.reshape(n, n_blocks, block_size).astype(np.float32)
        blocks = blocks * scales[:, :, np.newaxis] / 7.0
        return blocks.reshape(n, pad_len)[:, :n_seg]

    def cosine_similarity(self, query_f32: np.ndarray, db_quantized) -> np.ndarray:
        """
        db_quantized: tuple returned by quantize()
        query_f32: (n_dims,) float32 query vector
        """
        high_q, high_scales, low_packed, low_scales = db_quantized

        # Dequantize
        high_f32 = self._dequantize_int8(high_q, high_scales, self.n_high, self.high_block_size)
        low_f32 = self._dequantize_int4(low_packed, low_scales, self.n_low, self.low_block_size)

        # Reassemble in sorted dimension order
        db_reordered = np.concatenate([high_f32, low_f32], axis=1)  # (n, n_dims) in sorted order

        # Restore original dimension order
        db_f32 = db_reordered[:, self.inverse_indices]

        norms_db = np.linalg.norm(db_f32, axis=1, keepdims=True)
        norms_db = np.where(norms_db == 0, 1e-9, norms_db)
        db_normed = db_f32 / norms_db

        q_reordered = query_f32[self.sorted_indices]
        q_norm = np.linalg.norm(query_f32)
        q_normed = query_f32 / (q_norm + 1e-9)

        return db_normed @ q_normed


# ─────────────────────────────────────────────────────────────────────────────
# Helper: Build VABQ with a simple ratio split (no JSON required)
# ─────────────────────────────────────────────────────────────────────────────

def build_vabq_from_train_data(
    train_vectors: np.ndarray,
    n_high_ratio: float = 0.75,
    high_block_size: int = 16,
    low_block_size: int = 64,
) -> VABQQuantizer:
    """
    Convenience function for simulation: computes variance inline
    from the training set and returns a fitted VABQ quantizer.
    """
    return VABQQuantizer.from_runtime_variance(
        vectors=train_vectors,
        n_high_ratio=n_high_ratio,
        high_block_size=high_block_size,
        low_block_size=low_block_size,
    )

"""Production VABQ v1 binary codec used only for contract verification.

This is intentionally separate from the research evaluator. It follows the
on-device packed format exactly: fixed Rust permutations, f32 little-endian
scales, INT8 high blocks, low-nibble-first signed INT4 blocks, and the v1
header. The fixture test treats Rust's checked-in expected bytes as canonical.
"""

from __future__ import annotations

import math
import re
import struct
from pathlib import Path

TAG = 0x02
VERSION = 0x01
HIGH_BLOCK = 16
LOW_BLOCK = 64

PROFILES = {
    "allMiniLmL6V2": (1, 384, 288, "PI_ALL_MINILM_L6_V2"),
    "allMpnetBaseV2": (2, 768, 512, "PI_ALL_MPNET_BASE_V2"),
    "bgeM3": (3, 1024, 768, "PI_BGE_M3_1024"),
    "bgeBaseEnV15": (4, 768, 512, "PI_BGE_BASE_EN_V15"),
}


def f32(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", value))[0]


def round_away_from_zero(value: float) -> int:
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def fixed_permutation(profile: str) -> list[int]:
    _, dimension, _, constant = PROFILES[profile]
    source = (repository_root() / "rust_builder/rust/src/api/vector_quant.rs").read_text()
    match = re.search(
        rf"(?:pub(?:\(crate\))? )?const {constant}: \[usize; {dimension}\] = \[(.*?)\];",
        source,
        flags=re.DOTALL,
    )
    if match is None:
        raise ValueError(f"could not load Rust permutation {constant}")
    permutation = [int(value) for value in re.findall(r"\d+", match.group(1))]
    if len(permutation) != dimension or sorted(permutation) != list(range(dimension)):
        raise ValueError(f"invalid Rust permutation {constant}")
    return permutation


def deterministic_vector(dimension: int, seed: int) -> list[float]:
    """Portable LCG vector generator shared by canonical fixture producers."""
    state = seed & 0xFFFFFFFF
    values: list[float] = []
    for index in range(dimension):
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        centered = f32((state % 2001 - 1000) / 1000.0)
        offset = f32(((index % 13) - 6) / 97.0)
        values.append(f32(centered + offset))
    return values


def _quantize(values: list[float], divisor: float) -> tuple[list[int], float]:
    max_abs = max((abs(value) for value in values), default=0.0)
    if max_abs == 0.0:
        return [0] * len(values), 1.0
    scale = f32(max_abs / divisor)
    inverse = f32(1.0 / scale)
    quantized = [
        max(-int(divisor), min(int(divisor), round_away_from_zero(f32(value * inverse))))
        for value in values
    ]
    return quantized, scale


def encode(vector: list[float], profile: str) -> bytes:
    profile_id, dimension, high_dim, _ = PROFILES[profile]
    if len(vector) != dimension:
        raise ValueError(f"{profile} requires {dimension} dimensions")
    permutation = fixed_permutation(profile)
    permuted = [f32(vector[index]) for index in permutation]
    result = bytearray([TAG, VERSION])
    result.extend(struct.pack("<H", dimension))
    result.append(profile_id)

    for start in range(0, high_dim, HIGH_BLOCK):
        quantized, scale = _quantize(permuted[start : start + HIGH_BLOCK], 127.0)
        result.extend(struct.pack("<f", scale))
        result.extend(value & 0xFF for value in quantized)

    for start in range(high_dim, dimension, LOW_BLOCK):
        quantized, scale = _quantize(permuted[start : start + LOW_BLOCK], 7.0)
        result.extend(struct.pack("<f", scale))
        for index in range(0, len(quantized), 2):
            low = quantized[index] & 0x0F
            high = quantized[index + 1] & 0x0F if index + 1 < len(quantized) else 0
            result.append(low | (high << 4))
    return bytes(result)


def decode(blob: bytes) -> list[float]:
    if len(blob) < 5 or blob[0] != TAG or blob[1] != VERSION:
        raise ValueError("not a VABQ v1 blob")
    dimension = struct.unpack("<H", blob[2:4])[0]
    profile = next((name for name, (pid, dim, _, _) in PROFILES.items() if pid == blob[4] and dim == dimension), None)
    if profile is None:
        raise ValueError("invalid VABQ profile header")
    _, _, high_dim, _ = PROFILES[profile]
    permutation = fixed_permutation(profile)
    permuted = [0.0] * dimension
    cursor = 5
    for start in range(0, high_dim, HIGH_BLOCK):
        scale = struct.unpack("<f", blob[cursor : cursor + 4])[0]
        cursor += 4
        for offset in range(HIGH_BLOCK):
            value = struct.unpack("b", blob[cursor : cursor + 1])[0]
            cursor += 1
            permuted[start + offset] = f32(value * scale)
    for start in range(high_dim, dimension, LOW_BLOCK):
        scale = struct.unpack("<f", blob[cursor : cursor + 4])[0]
        cursor += 4
        block_len = min(LOW_BLOCK, dimension - start)
        for offset in range(0, block_len, 2):
            packed = blob[cursor]
            cursor += 1
            low = packed & 0x0F
            high = (packed >> 4) & 0x0F
            if low > 7:
                low -= 16
            if high > 7:
                high -= 16
            permuted[start + offset] = f32(low * scale)
            if offset + 1 < block_len:
                permuted[start + offset + 1] = f32(high * scale)
    if cursor != len(blob):
        raise ValueError("VABQ payload length mismatch")
    original = [0.0] * dimension
    for index, original_index in enumerate(permutation):
        original[original_index] = permuted[index]
    return original


def self_cosine(vector: list[float], profile: str) -> float:
    """Mirror Rust's VABQ query kernel for a vector scored against itself."""
    blob = encode(vector, profile)
    _, dimension, high_dim, _ = PROFILES[profile]
    permutation = fixed_permutation(profile)
    permuted = [vector[index] for index in permutation]
    query_high: list[tuple[list[int], float]] = [
        _quantize(permuted[start : start + HIGH_BLOCK], 127.0)
        for start in range(0, high_dim, HIGH_BLOCK)
    ]
    query_low: list[tuple[list[int], float]] = [
        _quantize(permuted[start : start + LOW_BLOCK], 127.0)
        for start in range(high_dim, dimension, LOW_BLOCK)
    ]
    cursor = 5
    dot = 0.0
    target_sq = 0.0
    query_sq = 0.0
    for quantized, query_scale in query_high:
        target_scale = struct.unpack("<f", blob[cursor : cursor + 4])[0]
        cursor += 4
        target = [struct.unpack("b", blob[cursor + index : cursor + index + 1])[0] for index in range(HIGH_BLOCK)]
        cursor += HIGH_BLOCK
        dot = f32(dot + f32(sum(a * b for a, b in zip(quantized, target)) * query_scale * target_scale))
        target_sq = f32(target_sq + f32(sum(value * value for value in target) * target_scale * target_scale))
        query_sq = f32(query_sq + f32(sum(value * value for value in quantized) * query_scale * query_scale))
    for quantized, query_scale in query_low:
        target_scale = struct.unpack("<f", blob[cursor : cursor + 4])[0]
        cursor += 4
        target: list[int] = []
        for _ in range(0, len(quantized), 2):
            packed = blob[cursor]
            cursor += 1
            low = packed & 0x0F
            high = (packed >> 4) & 0x0F
            target.append(low - 16 if low > 7 else low)
            if len(target) < len(quantized):
                target.append(high - 16 if high > 7 else high)
        dot = f32(dot + f32(sum(a * b for a, b in zip(quantized, target)) * query_scale * target_scale))
        target_sq = f32(target_sq + f32(sum(value * value for value in target) * target_scale * target_scale))
        query_sq = f32(query_sq + f32(sum(value * value for value in quantized) * query_scale * query_scale))
    return f32(dot / f32(math.sqrt(query_sq) * math.sqrt(target_sq))) if query_sq and target_sq else 0.0

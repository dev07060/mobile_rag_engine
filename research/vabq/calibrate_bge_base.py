"""Calibrate the production BGE-base-en-v1.5 VABQ permutation.

The tokenizer truncation thresholds and attention-mask mean pooling mirror
mobile_rag_engine's Rust tokenizer and Dart EmbeddingService runtime path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

MODEL_SHA256 = "4e8fae771f7050180b28e694455d7f6f5aaaabeaba9fdf8be1bc364eb53ea83b"
TOKENIZER_SHA256 = "be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037"
DIMENSION = 768


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def truncation_length(text: str) -> int:
    if len(text) >= 2400:
        return 512
    if len(text) >= 1200:
        return 384
    return 256


def encoded_ids(tokenizer: Tokenizer, text: str) -> list[int]:
    tokenizer.enable_truncation(max_length=truncation_length(text))
    return tokenizer.encode(text, add_special_tokens=True).ids


def update_variance(
    embeddings: np.ndarray,
    count: int,
    mean: np.ndarray,
    m2: np.ndarray,
) -> int:
    for embedding in embeddings:
        count += 1
        delta = embedding.astype(np.float64) - mean
        mean += delta / count
        m2 += delta * (embedding.astype(np.float64) - mean)
    return count


def calibrate(args: argparse.Namespace) -> dict[str, object]:
    model = Path(args.model)
    tokenizer_path = Path(args.tokenizer)
    corpus = Path(args.corpus)
    if sha256(model) != MODEL_SHA256:
        raise ValueError("runtime model SHA-256 does not match the pinned BGE-base contract")
    if sha256(tokenizer_path) != TOKENIZER_SHA256:
        raise ValueError("tokenizer SHA-256 does not match the pinned BGE-base contract")

    tokenizer = Tokenizer.from_file(str(tokenizer_path))
    tokenizer.no_padding()
    session = ort.InferenceSession(
        str(model),
        providers=["CPUExecutionProvider"],
    )
    input_names = {item.name for item in session.get_inputs()}
    if not {"input_ids", "attention_mask"}.issubset(input_names):
        raise ValueError(f"unsupported ONNX inputs: {sorted(input_names)}")

    count = 0
    mean = np.zeros(DIMENSION, dtype=np.float64)
    m2 = np.zeros(DIMENSION, dtype=np.float64)
    pending: list[list[int]] = []

    def flush() -> None:
        nonlocal count
        if not pending:
            return
        width = max(len(ids) for ids in pending)
        input_ids = np.zeros((len(pending), width), dtype=np.int64)
        attention_mask = np.zeros_like(input_ids)
        for row, ids in enumerate(pending):
            input_ids[row, : len(ids)] = ids
            attention_mask[row, : len(ids)] = 1
        inputs = {
            "input_ids": input_ids,
            "attention_mask": attention_mask,
        }
        if "token_type_ids" in input_names:
            inputs["token_type_ids"] = np.zeros_like(input_ids)
        output = session.run(None, inputs)[0]
        if output.ndim == 3:
            embeddings = (output * attention_mask[..., None]).sum(axis=1)
            embeddings /= attention_mask.sum(axis=1, keepdims=True)
        elif output.ndim == 2:
            embeddings = output
        else:
            raise ValueError(f"unsupported ONNX output shape: {output.shape}")
        if embeddings.shape[1] != DIMENSION:
            raise ValueError(f"expected {DIMENSION} dimensions, got {embeddings.shape[1]}")
        count = update_variance(embeddings.astype(np.float32), count, mean, m2)
        pending.clear()

    with corpus.open(encoding="utf-8") as source:
        for line in source:
            text = str(json.loads(line).get("text", "")).strip()
            if not text:
                continue
            pending.append(encoded_ids(tokenizer, text))
            if len(pending) == args.batch_size:
                flush()
    flush()
    if count < 2:
        raise ValueError("calibration requires at least two non-empty passages")

    variances = m2 / count
    permutation = sorted(range(DIMENSION), key=lambda index: (-variances[index], index))
    return {
        "profile": "bgeBaseEnV15",
        "model_family": "BAAI/bge-base-en-v1.5",
        "model_sha256": MODEL_SHA256,
        "tokenizer_sha256": TOKENIZER_SHA256,
        "corpus_sha256": sha256(corpus),
        "corpus_format": "MS MARCO JSONL {id,text}",
        "sample_count": count,
        "dimension": DIMENSION,
        "high_dimension": 512,
        "low_dimension": 256,
        "variance_estimator": "population Welford f64 over runtime f32 embeddings",
        "embedding_pipeline": "BertModel output with attention-mask mean pooling",
        "tokenizer_truncation": "chars <1200:256, <2400:384, otherwise:512",
        "permutation": permutation,
        "variances": [float(variances[index]) for index in permutation],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--tokenizer", required=True)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--batch-size", type=int, default=16)
    args = parser.parse_args()
    artifact = calibrate(args)
    Path(args.output).write_text(json.dumps(artifact, indent=2) + "\n")
    print(f"wrote {args.output} with {artifact['sample_count']} samples")


if __name__ == "__main__":
    main()

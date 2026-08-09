"""Byte-for-byte checks for the source-controlled VABQ v1 fixture."""

import base64
import hashlib
import json
import struct
import unittest
from pathlib import Path

from production_format import PROFILES, decode, deterministic_vector, encode, self_cosine


FIXTURE = Path(__file__).resolve().parents[2] / "test/fixtures/vabq/canonical-v1.json"


class ProductionFormatFixtureTest(unittest.TestCase):
    def test_bge_base_profile_is_append_only_and_not_mpnet_alias(self):
        bge = PROFILES["bgeBaseEnV15"]
        mpnet = PROFILES["allMpnetBaseV2"]
        self.assertEqual(bge[:3], (4, 768, 512))
        self.assertNotEqual(bge[3], mpnet[3])

    def test_python_codec_matches_canonical_v1_bytes_and_decode(self):
        fixture = json.loads(FIXTURE.read_text())
        self.assertEqual(fixture["format_version"], 1)
        self.assertEqual(fixture["generator"], "lcg-v1")
        self.assertEqual({case["profile"] for case in fixture["cases"]}, set(PROFILES))

        for case in fixture["cases"]:
            with self.subTest(profile=case["profile"]):
                vector = deterministic_vector(case["dimension"], case["seed"])
                blob = encode(vector, case["profile"])
                self.assertEqual(blob[:5].hex(), case["header_hex"])
                self.assertEqual(base64.b64encode(blob).decode(), case["packed_base64"])
                decoded = decode(blob)
                decoded_bytes = struct.pack(f"<{len(decoded)}f", *decoded)
                self.assertEqual(
                    hashlib.sha256(decoded_bytes).hexdigest(),
                    case["decoded_f32_le_sha256"],
                )
                self.assertAlmostEqual(
                    self_cosine(vector, case["profile"]),
                    case["self_cosine"],
                    places=6,
                )


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""
The local model's thirteen tools do not move by a byte unless somebody means
them to.

Routing accuracy was MEASURED against exactly what the local model is shown
(research/ai-assist/), and "adding a tool is a routing change" (CLAUDE.md).
Until #209 the only guard on that was a count of tools and a digest quoted,
truncated, in documentation/10 — made by a hasher that was not in the
repository. This pins the FULL digest of `contracts/assist-cases.json` ->
`toolSchemas.local`, using the committed hasher
(`research/ai-assist/toolhash.py`), so a description, schema or tool that
reaches the local surface fails a gate on both platforms.

The chain it closes: the mac suite checks that `--write-contracts` output
equals the committed contract (AssistContractTests), and this checks the
committed contract's local half against the recorded number. Changing the
local surface ON PURPOSE means re-measuring routing and then updating
LOCAL_DIGEST below, in the same commit as the measurement.

The MCP digest is NOT pinned: it moves whenever an MCP-only tool is added
(#209 added three), and is recorded in documentation/10 where that happens.
"""
import importlib.util
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
HASHER = REPOSITORY / "research" / "ai-assist" / "toolhash.py"

# The local 13, unchanged since it was recorded (documentation/10: 46b96562…2cd96cb6).
LOCAL_COUNT = 13
LOCAL_DIGEST = "46b965622213567d49aae523c70f9bcd2c9fd3d1c21279e167d0da2b2cd96cb6"


def load_hasher():
    specification = importlib.util.spec_from_file_location("toolhash", HASHER)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


class LocalSurfaceDigestTests(unittest.TestCase):

    def test_the_hasher_is_in_the_repository(self):
        self.assertTrue(HASHER.is_file(), f"{HASHER} is missing — it is what the docs' digests are made with")

    def test_the_local_surface_is_the_one_routing_was_measured_against(self):
        count, digest = load_hasher().surfaces()["local"]
        self.assertEqual(count, LOCAL_COUNT)
        self.assertEqual(
            digest, LOCAL_DIGEST,
            "What the LOCAL model is shown has changed. That is a routing change: re-measure "
            "(research/ai-assist/) before updating LOCAL_DIGEST, and say so in documentation/10.",
        )

    def test_the_recipe_is_the_one_documented(self):
        # A guard on the guard: the digest of a known list, so a hasher that
        # quietly changed its recipe cannot keep the pin above green by
        # accident.
        self.assertEqual(
            load_hasher().digest([{"b": 1, "a": "é"}]),
            __import__("hashlib").sha256('[{"a": "é", "b": 1}]'.encode("utf-8")).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()

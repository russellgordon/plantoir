#!/usr/bin/env python3
"""
Unit tests for contracts.py — the scripts' reader for the Plantoir contract.

Pure stdlib, no Docker and no network. What these pin is not the contract's
CONTENT (the apps' suites do that) but the property that makes reading it safe
to build a rule on: a missing or malformed contract RAISES rather than quietly
falling back, because a build using a rule nobody can see is the exact failure
the shared contract exists to prevent.

Run with:

    python3 scripts/test_contracts.py
"""
import json
import tempfile
import unittest
from pathlib import Path

import contracts
import toolchain_paths


class ContractLoadingTests(unittest.TestCase):

    def setUp(self):
        self._original = toolchain_paths.CONTRACTS_DIR
        self._temp = tempfile.TemporaryDirectory()
        toolchain_paths.CONTRACTS_DIR = Path(self._temp.name)
        contracts.reset_cache()

    def tearDown(self):
        toolchain_paths.CONTRACTS_DIR = self._original
        contracts.reset_cache()
        self._temp.cleanup()

    def _write(self, name: str, payload) -> None:
        path = Path(self._temp.name) / name
        path.write_text(json.dumps(payload), encoding="utf-8")

    def test_suffix_is_optional(self):
        """load('x') and load('x.json') are the same file, read once."""
        self._write("sample.json", {"a": 1})
        self.assertEqual(contracts.load("sample"), {"a": 1})
        self.assertEqual(contracts.load("sample.json"), {"a": 1})

    def test_a_missing_file_raises(self):
        """The point of the module: no silent fallback to a built-in default."""
        with self.assertRaises(contracts.ContractMissing):
            contracts.load("not-here")

    def test_malformed_json_raises(self):
        (Path(self._temp.name) / "broken.json").write_text("{oh dear", encoding="utf-8")
        with self.assertRaises(contracts.ContractMissing):
            contracts.load("broken")

    def test_optional_returns_none_instead_of_raising(self):
        self.assertIsNone(contracts.load("not-here", optional=True))
        (Path(self._temp.name) / "broken.json").write_text("{oh dear", encoding="utf-8")
        self.assertIsNone(contracts.load("broken", optional=True))

    def test_section_walks_nested_keys(self):
        self._write("nested.json", {"outer": {"inner": {"cases": [1, 2]}}})
        self.assertEqual(contracts.section("nested", "outer", "inner", "cases"), [1, 2])

    def test_section_names_the_key_it_could_not_find(self):
        """A wrong shape must fail where it happened, not travel as a None."""
        self._write("nested.json", {"outer": {}})
        with self.assertRaises(contracts.ContractMissing) as caught:
            contracts.section("nested", "outer", "missing")
        self.assertIn("outer.missing", str(caught.exception))

    def test_section_optional_returns_none_for_a_missing_key(self):
        self._write("nested.json", {"outer": {}})
        self.assertIsNone(contracts.section("nested", "outer", "missing", optional=True))

    def test_walking_into_a_non_dict_raises_rather_than_crashing(self):
        self._write("nested.json", {"outer": [1, 2, 3]})
        with self.assertRaises(contracts.ContractMissing):
            contracts.section("nested", "outer", "inner")


class RealContractDirectoryTests(unittest.TestCase):
    """
    The repository's own contracts/ must be readable by this loader — the
    check that the files the apps generate are the files the scripts can
    consume. Skipped when the directory is not present (an installed
    container has it at /opt/contracts; a bare checkout of scripts/ alone
    would not).
    """

    def setUp(self):
        contracts.reset_cache()
        self._original = toolchain_paths.CONTRACTS_DIR
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if not repo_contracts.is_dir():
            self.skipTest("no contracts/ directory beside scripts/")
        toolchain_paths.CONTRACTS_DIR = repo_contracts

    def tearDown(self):
        toolchain_paths.CONTRACTS_DIR = self._original
        contracts.reset_cache()

    def test_every_contract_file_parses(self):
        found = sorted(contracts.contracts_dir().glob("*.json"))
        self.assertTrue(found, "contracts/ has no .json files")
        for path in found:
            with self.subTest(contract=path.name):
                self.assertIsInstance(contracts.load(path.name), (dict, list))


if __name__ == "__main__":
    unittest.main(verbosity=2)

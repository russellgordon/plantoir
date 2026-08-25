#!/usr/bin/env python3
"""
Unit tests for excluded_items preflight handling and index.md sentinel notes.

Tests preflight discovery skipping, un-hide suppression, sentinel note
application/removal, and sentinel stripping without requiring Docker.
"""
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import contracts
import toolchain_paths

# Ensure scripts dir is on sys.path
scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import build_site


class PreflightExclusionTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.base = Path(self.temp_dir.name)
        self.course_dir = self.base / "ICS3U"
        self.course_dir.mkdir(parents=True)
        self.section_dir = self.course_dir / "section1"
        self.section_dir.mkdir(parents=True)
        self.config_path = self.course_dir / "course_config.json"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_contract_section_exists(self):
        """specialNames.excludedFolderIndexNote exists in shared-rules.json"""
        cfg = contracts.section("shared-rules", "specialNames", "excludedFolderIndexNote")
        self.assertIn("sentinelStart", cfg)
        self.assertIn("sentinelEnd", cfg)
        self.assertIn("noteBody", cfg)
        self.assertTrue(cfg["sentinelStart"].startswith("<!--"))
        self.assertTrue(cfg["sentinelEnd"].endswith("-->"))

    def test_sentinel_apply_and_remove(self):
        """Sentinel notes are applied idempotently and removed cleanly."""
        start, end, body = build_site._get_excluded_note_config()
        index_file = self.course_dir / "Tasks" / "index.md"
        index_file.parent.mkdir(parents=True)
        
        # 1. Never creates a missing file
        missing_file = self.course_dir / "NoExist" / "index.md"
        build_site._apply_sentinel_note(missing_file, start, end, body)
        self.assertFalse(missing_file.exists())

        # 2. Inserts after frontmatter
        initial_content = "---\ntitle: Tasks\n---\n# Tasks Content\nSome text."
        index_file.write_text(initial_content, encoding="utf-8")
        build_site._apply_sentinel_note(index_file, start, end, body)

        applied = index_file.read_text(encoding="utf-8")
        self.assertIn(start, applied)
        self.assertIn(end, applied)
        self.assertIn("title: Tasks", applied)
        self.assertIn("# Tasks Content", applied)

        # 3. Idempotent: applying again leaves content unchanged
        mtime_before = index_file.stat().st_mtime_ns
        build_site._apply_sentinel_note(index_file, start, end, body)
        self.assertEqual(index_file.read_text(encoding="utf-8"), applied)

        # 4. Remove cleans the note and sentinels
        build_site._remove_sentinel_note(index_file, start, end)
        removed = index_file.read_text(encoding="utf-8")
        self.assertNotIn(start, removed)
        self.assertNotIn(end, removed)
        self.assertIn("title: Tasks", removed)
        self.assertIn("# Tasks Content", removed)

    def test_strip_sentinels(self):
        """_strip_sentinels removes sentinel block from text."""
        start, end, _ = build_site._get_excluded_note_config()
        text = f"Intro\n{start}\n> [!NOTE]\n> Excluded\n{end}\n\nBody content"
        stripped = build_site._strip_sentinels(text, start, end)
        self.assertNotIn(start, stripped)
        self.assertNotIn("Excluded", stripped)
        self.assertIn("Intro", stripped)
        self.assertIn("Body content", stripped)

    def test_preflight_skips_excluded_items_and_prints_skip_lines(self):
        """Preflight does not add excluded items, does not un-hide them, and prints skip notices."""
        # Create folders and files on disk
        (self.course_dir / "ExcludedSharedFolder").mkdir(parents=True)
        (self.course_dir / "ExcludedSharedFolder" / "index.md").write_text("# Excluded Shared", encoding="utf-8")
        (self.course_dir / "NormalSharedFolder").mkdir(parents=True)
        (self.course_dir / "ExcludedSharedFile.md").write_text("# Excluded File", encoding="utf-8")
        (self.course_dir / "NormalSharedFile.md").write_text("# Normal File", encoding="utf-8")

        (self.section_dir / "ExcludedSectionFolder").mkdir(parents=True)
        (self.section_dir / "ExcludedSectionFolder" / "index.md").write_text("# Excluded Sec", encoding="utf-8")
        (self.section_dir / "NormalSectionFolder").mkdir(parents=True)

        config_data = {
            "course_code": "ICS3U",
            "shared_folders": [],
            "shared_files": [],
            "per_section_folders": [],
            "per_section_files": [],
            "hidden": ["ExcludedSharedFolder"],
            "expandable": [],
            "excluded_items": {
                "shared": ["ExcludedSharedFolder", "ExcludedSharedFile.md"],
                "per_section": ["ExcludedSectionFolder"]
            }
        }
        self.config_path.write_text(json.dumps(config_data, indent=2), encoding="utf-8")

        output = io.StringIO()
        with patch("sys.stdout", output):
            updated_cfg = build_site.preflight_update_course_config(
                self.course_dir, self.section_dir, self.config_path
            )
        stdout = output.getvalue()

        # Check skip notices were printed
        self.assertIn("🚫 Skipping excluded shared folder: ExcludedSharedFolder", stdout)
        self.assertIn("🚫 Skipping excluded shared file: ExcludedSharedFile.md", stdout)
        self.assertIn("🚫 Skipping excluded per-section folder: ExcludedSectionFolder", stdout)

        # Check excluded items were NOT added
        self.assertNotIn("ExcludedSharedFolder", updated_cfg["shared_folders"])
        self.assertNotIn("ExcludedSharedFile.md", updated_cfg["shared_files"])
        self.assertNotIn("ExcludedSectionFolder", updated_cfg["per_section_folders"])

        # Check normal items WERE added
        self.assertIn("NormalSharedFolder", updated_cfg["shared_folders"])
        self.assertIn("NormalSharedFile.md", updated_cfg["shared_files"])
        self.assertIn("NormalSectionFolder", updated_cfg["per_section_folders"])

        # Check hidden status: ExcludedSharedFolder must NOT be un-hidden
        self.assertIn("ExcludedSharedFolder", updated_cfg["hidden"])

        # Check sentinel note was written to existing index.md in ExcludedSharedFolder
        start, end, _ = build_site._get_excluded_note_config()
        excluded_index = self.course_dir / "ExcludedSharedFolder" / "index.md"
        self.assertIn(start, excluded_index.read_text(encoding="utf-8"))

        # Check sentinel note was written to existing index.md in ExcludedSectionFolder
        sec_excluded_index = self.section_dir / "ExcludedSectionFolder" / "index.md"
        self.assertIn(start, sec_excluded_index.read_text(encoding="utf-8"))

    def test_name_in_both_copy_list_and_excluded_items_is_dropped(self):
        """excluded_items is authoritative: a name still in a copy list is dropped and written back."""
        (self.course_dir / "Tasks").mkdir(parents=True)
        (self.section_dir / "Drafts").mkdir(parents=True)
        config_data = {
            "course_code": "ICS3U",
            "shared_folders": ["Concepts", "Tasks"],
            "shared_files": ["Notes.md"],
            "per_section_folders": ["Drafts"],
            "per_section_files": [],
            "hidden": [],
            "expandable": [],
            "excluded_items": {"shared": ["Tasks", "Notes.md"], "per_section": ["Drafts"]},
        }
        self.config_path.write_text(json.dumps(config_data, indent=2), encoding="utf-8")

        output = io.StringIO()
        with patch("sys.stdout", output):
            updated_cfg = build_site.preflight_update_course_config(
                self.course_dir, self.section_dir, self.config_path
            )
        stdout = output.getvalue()

        self.assertIn("🚫 Dropped excluded shared folder from the copy list: Tasks", stdout)
        self.assertIn("🚫 Dropped excluded shared file from the copy list: Notes.md", stdout)
        self.assertIn("🚫 Dropped excluded per-section folder from the copy list: Drafts", stdout)
        self.assertEqual(updated_cfg["shared_folders"], ["Concepts"])
        self.assertEqual(updated_cfg["shared_files"], [])
        self.assertEqual(updated_cfg["per_section_folders"], [])
        # Written back, not just returned
        on_disk = json.loads(self.config_path.read_text(encoding="utf-8"))
        self.assertEqual(on_disk["shared_folders"], ["Concepts"])
        self.assertEqual(on_disk["excluded_items"], config_data["excluded_items"])

    def test_preflights_own_backup_is_never_discovered(self):
        """The write-back's backup file must not become a shared file on the next build."""
        (self.course_dir / "course_config.backup.json").write_text("{}", encoding="utf-8")
        (self.course_dir / "course_config.json.tmp").write_text("{}", encoding="utf-8")
        (self.course_dir / "Real Notes.md").write_text("# real", encoding="utf-8")
        _, files = build_site.discover_shared_items(self.course_dir)
        self.assertEqual(files, ["Real Notes.md"])

    def test_reincluding_item_removes_sentinel_note(self):
        """When an excluded item is removed from excluded_items, preflight cleans the sentinel note."""
        folder = self.course_dir / "ReincludedFolder"
        folder.mkdir(parents=True)
        index_file = folder / "index.md"
        start, end, body = build_site._get_excluded_note_config()
        index_file.write_text(f"{start}\n{body}\n{end}\n\n# Reincluded\nText", encoding="utf-8")

        config_data = {
            "course_code": "ICS3U",
            "shared_folders": ["ReincludedFolder"],
            "shared_files": [],
            "per_section_folders": [],
            "per_section_files": [],
            "hidden": [],
            "expandable": ["ReincludedFolder"]
        }
        self.config_path.write_text(json.dumps(config_data, indent=2), encoding="utf-8")

        build_site.preflight_update_course_config(
            self.course_dir, self.section_dir, self.config_path
        )

        cleaned_text = index_file.read_text(encoding="utf-8")
        self.assertNotIn(start, cleaned_text)
        self.assertNotIn(end, cleaned_text)
        self.assertIn("# Reincluded", cleaned_text)


if __name__ == "__main__":
    unittest.main()

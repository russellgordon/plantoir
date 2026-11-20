#!/usr/bin/env python3
"""
An upgraded work folder's dependency mirror gains the Visual C++ runtime
copies beside its native modules (GitHub #1006, after #965).

On Windows a section's work folder holds `node_modules` as a hardlink MIRROR
of the runtime's `runtime\\quartz\\node_modules`, made when the section is
first built and not remade after. Since #965 the runtime carries
`vcruntime140.dll` beside the two native modules that import it (`contracts/toolchain.json` ->
`windowsNodeVcRuntime` -> `besideModules`), so a fresh mirror has them; a
section first built under 1.9.3 kept a mirror without them, and there the
modules found the copy beside `node.exe` only through PATH, behind any older
copy in System32. Every build now brings the named files into an existing
mirror, file by file, without remaking the mirror.

Pinned here, each measured failing before the change:

  * a mirror laid out as 1.9.3 left it gains each copy, as a hardlink to the
    runtime's file, through the build's own dependency step;
  * nothing else in the mirror is touched, and a second build adds nothing;
  * a copy the mirror holds that is not the runtime's file (an older one
    left by an earlier upgrade) is replaced by the runtime's, even at the
    same size;
  * a copy that already holds the runtime's bytes under its own inode (made
    where a hardlink was refused) is left alone, not copied again on every
    build (#1010: files are compared by size and SHA-256, not by inode);
  * a runtime without the copies, or a mirror without the module's folder,
    is left as it is and the build goes on;
  * off Windows (the Mac, the container) the step does nothing at all.

Pure stdlib, temporary folders, no network. Runs in verify.sh and in
Windows' PythonToolchainTests:

    python3 scripts/test_mirror_module_libraries.py
"""
import contextlib
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import contracts
import toolchain_paths
import build_site

REPOSITORY_CONTRACTS = scripts_dir.parent / "contracts"
LIGHTNINGCSS = ("lightningcss-win32-x64-msvc", "lightningcss.win32-x64-msvc.node")
TYPST = ("@myriaddreamin/typst-ts-node-compiler-win32-x64-msvc", "typst-ts-node-compiler.win32-x64-msvc.node")
LIBRARY = "vcruntime140.dll"


def same_file(first: Path, second: Path) -> bool:
    first_stat = first.stat()
    second_stat = second.stat()
    return first_stat.st_ino == second_stat.st_ino and first_stat.st_dev == second_stat.st_dev


class AnUpgradedMirrorGainsTheModuleCopies(unittest.TestCase):

    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name)
        self.runtime = self.root / "runtime"
        self.runtime_modules = self.runtime / "quartz" / "node_modules"
        for folder, module in (LIGHTNINGCSS, TYPST):
            module_folder = self.runtime_modules / folder
            module_folder.mkdir(parents=True)
            (module_folder / module).write_bytes(b"MZ module " + module.encode())
            (module_folder / "package.json").write_text("{}")
        (self.runtime_modules / "katex").mkdir()
        (self.runtime_modules / "katex" / "katex.js").write_text("// katex")
        self.output_dir = self.root / "work" / "EXC2O" / "section1"
        self.output_dir.mkdir(parents=True)
        self.mirror = self.output_dir / "node_modules"
        # The mirror as 1.9.3 made it: the runtime before the copies existed.
        toolchain_paths.hardlink_mirror(self.runtime_modules, self.mirror)
        # Then the upgrade: the installer adds the copies to the runtime only.
        for folder, _ in (LIGHTNINGCSS, TYPST):
            (self.runtime_modules / folder / LIBRARY).write_bytes(b"MZ vcruntime 14.51")
        self._original_quartz = toolchain_paths.QUARTZ_DIR
        self._original_contracts = toolchain_paths.CONTRACTS_DIR
        toolchain_paths.QUARTZ_DIR = self.runtime / "quartz"
        toolchain_paths.CONTRACTS_DIR = REPOSITORY_CONTRACTS
        contracts.reset_cache()

    def tearDown(self):
        toolchain_paths.QUARTZ_DIR = self._original_quartz
        toolchain_paths.CONTRACTS_DIR = self._original_contracts
        contracts.reset_cache()
        self._temporary.cleanup()

    def build_dependencies(self, on_windows: bool) -> str:
        said = io.StringIO()
        with mock.patch.object(toolchain_paths, "on_windows", return_value=on_windows):
            with contextlib.redirect_stdout(said):
                build_site.ensure_node_dependencies(self.output_dir, force_npm_install=False)
        return said.getvalue()

    def test_the_contract_names_the_two_module_folders_under_the_scaffold(self):
        folders = toolchain_paths.module_library_places()
        self.assertEqual([LIGHTNINGCSS[0], TYPST[0]], [relative for relative, _ in folders])
        for _, names in folders:
            self.assertEqual([LIBRARY], names)

    def test_a_mirror_as_1_9_3_left_it_gains_the_copies(self):
        for folder, _ in (LIGHTNINGCSS, TYPST):
            self.assertFalse((self.mirror / folder / LIBRARY).exists(), "the fixture's mirror already has the copy")
        said = self.build_dependencies(on_windows=True)
        for folder, _ in (LIGHTNINGCSS, TYPST):
            copy = self.mirror / folder / LIBRARY
            self.assertTrue(copy.is_file(), f"{copy} was not added to the mirror")
            self.assertTrue(same_file(copy, self.runtime_modules / folder / LIBRARY),
                            f"{copy} is not a hardlink to the runtime's file")
        self.assertIn("Added 2 library file(s)", said)

    def test_nothing_else_in_the_mirror_is_touched_and_a_second_build_adds_nothing(self):
        katex = self.mirror / "katex" / "katex.js"
        module = self.mirror / LIGHTNINGCSS[0] / LIGHTNINGCSS[1]
        self.build_dependencies(on_windows=True)
        self.assertTrue(same_file(katex, self.runtime_modules / "katex" / "katex.js"))
        self.assertTrue(same_file(module, self.runtime_modules / LIGHTNINGCSS[0] / LIGHTNINGCSS[1]))
        added_again = toolchain_paths.bring_module_libraries_into_mirror(self.mirror)
        self.assertEqual([], added_again)

    def test_an_older_copy_in_the_mirror_is_replaced_by_the_runtimes(self):
        stale = self.mirror / TYPST[0] / LIBRARY
        stale.write_bytes(b"MZ vcruntime 14.29")
        self.build_dependencies(on_windows=True)
        self.assertTrue(same_file(stale, self.runtime_modules / TYPST[0] / LIBRARY))
        self.assertEqual(b"MZ vcruntime 14.51", stale.read_bytes())

    def test_a_copy_made_where_a_link_was_refused_is_not_copied_again(self):
        # #1010: os.link can be refused (another volume, a file system without
        # hardlinks), and then the step COPIES. That copy holds the runtime's
        # bytes under its own inode, and comparing inodes replaced it, and
        # said "Added 2", on every build. Compared by content, it is left.
        for folder, _ in (LIGHTNINGCSS, TYPST):
            copy = self.mirror / folder / LIBRARY
            copy.write_bytes((self.runtime_modules / folder / LIBRARY).read_bytes())
            self.assertFalse(same_file(copy, self.runtime_modules / folder / LIBRARY))
        before = {}
        for folder, _ in (LIGHTNINGCSS, TYPST):
            before[folder] = (self.mirror / folder / LIBRARY).stat().st_ino
        said = self.build_dependencies(on_windows=True)
        self.assertNotIn("library file(s)", said)
        self.assertEqual([], toolchain_paths.bring_module_libraries_into_mirror(self.mirror, windows=True))
        for folder, _ in (LIGHTNINGCSS, TYPST):
            self.assertEqual(before[folder], (self.mirror / folder / LIBRARY).stat().st_ino,
                             f"{folder}/{LIBRARY} was replaced although it already held the runtime's bytes")

    def test_a_copy_of_the_same_size_with_other_bytes_is_replaced(self):
        stale = self.mirror / TYPST[0] / LIBRARY
        stale.write_bytes(b"MZ vcruntime 14.29")
        self.assertEqual(stale.stat().st_size, (self.runtime_modules / TYPST[0] / LIBRARY).stat().st_size)
        added = toolchain_paths.bring_module_libraries_into_mirror(self.mirror, windows=True)
        self.assertIn(TYPST[0] + "/" + LIBRARY, added)
        self.assertEqual(b"MZ vcruntime 14.51", stale.read_bytes())

    def test_a_runtime_without_the_copies_leaves_the_mirror_as_it_is(self):
        for folder, _ in (LIGHTNINGCSS, TYPST):
            (self.runtime_modules / folder / LIBRARY).unlink()
        self.build_dependencies(on_windows=True)
        for folder, _ in (LIGHTNINGCSS, TYPST):
            self.assertFalse((self.mirror / folder / LIBRARY).exists())

    def test_a_mirror_without_the_modules_folder_is_not_given_one(self):
        missing = self.mirror / TYPST[0]
        for entry in missing.iterdir():
            entry.unlink()
        missing.rmdir()
        added = toolchain_paths.bring_module_libraries_into_mirror(self.mirror, windows=True)
        self.assertEqual([LIGHTNINGCSS[0] + "/" + LIBRARY], added)
        self.assertFalse(missing.exists())

    def test_off_windows_the_step_does_nothing(self):
        self.build_dependencies(on_windows=False)
        for folder, _ in (LIGHTNINGCSS, TYPST):
            self.assertFalse((self.mirror / folder / LIBRARY).exists())
        self.assertEqual([], toolchain_paths.bring_module_libraries_into_mirror(self.mirror, windows=False))

    def test_a_missing_contract_never_stops_the_build(self):
        toolchain_paths.CONTRACTS_DIR = self.root / "no-contracts-here"
        contracts.reset_cache()
        said = self.build_dependencies(on_windows=True)
        self.assertIn("Skipping npm install", said)
        for folder, _ in (LIGHTNINGCSS, TYPST):
            self.assertFalse((self.mirror / folder / LIBRARY).exists())


if __name__ == "__main__":
    unittest.main()

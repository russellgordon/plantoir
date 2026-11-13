#!/usr/bin/env python3
"""
Compiled Python never renames the website builder's image (GitHub #747).

The 1.9.1 app bundle carried `support/swift/__pycache__/*.pyc`. A test run by
hand in the checkout writes `__pycache__` beside the scripts, Xcode copies a
folder reference whole, and the launchers hash every file in the build
context to name the image (`teaching-quartz:src-<hash>`). One stray `.pyc`
gave the same recipe a new image name, and every Mac built the image again
for nothing. Measured, with what was rejected, in
documentation/03-launcher-scripts.md -> "Compiled Python is not part of the
recipe (#747)".

Pinned here, each part measured failing on the code before the fix:

  * the mac build phase (`mac-app/BuildScripts/write_toolchain_hashes.py`)
    removes every `__pycache__` folder and `.pyc` file from the bundle's copy
    of the recipe folders before it fingerprints them, and lists none;
  * `toolchain_hash` is the same text in setup.sh, preview.sh and deploy.sh,
    and gives the same hash for a context with bytecode planted in it;
  * on a context with no bytecode it gives exactly the hash the function
    gave before #747, so the change renames no teacher's image by itself;
  * the release check and verify.sh look in every recipe folder.

The launcher half needs a bash that can reach a scratch folder, and shasum,
and skips without them (Windows' PythonToolchainTests runs this file).
Pure stdlib, no Docker, no network. Run with:

    python3 scripts/test_toolchain_bytecode.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
BUILD_PHASE = REPOSITORY_ROOT / "mac-app" / "BuildScripts" / "write_toolchain_hashes.py"
LAUNCHERS = ["setup.sh", "preview.sh", "deploy.sh"]

# toolchain_hash as it was in all three launchers before #747, kept as text so
# the continuity test can run it beside today's.
TOOLCHAIN_HASH_BEFORE_747 = r"""toolchain_hash() {
  local context="$1"
  (cd "$context" && find . \
      \( -path './.git' -o -path './courses' -o -path './mac-app' \
         -o -name node_modules -o -name '.merged_output' \
         -o -name '.verify-export.*' \) -prune \
      -o -type f -not -name '.DS_Store' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256 \
    | shasum -a 256 | cut -c1-8)
}
"""


def recipe_folders():
    with open(REPOSITORY_ROOT / "contracts" / "toolchain.json", encoding="utf-8") as handle:
        return json.load(handle)["recipeFolders"]["folders"]


def _bash_with_shasum_can_reach_a_scratch_folder():
    """A Windows `bash` from WSL cannot open a Windows temporary path, and a
    Git Bash may have no shasum: these must skip there, not fail."""
    if shutil.which("bash") is None:
        return False
    try:
        with tempfile.TemporaryDirectory() as tmp:
            probe = subprocess.run(
                ["bash", "-c", 'cd "$1" && command -v shasum >/dev/null && printf reachable', "_", str(tmp)],
                capture_output=True, timeout=60,
            )
            return probe.stdout.decode("utf-8", "replace").strip() == "reachable"
    except (OSError, subprocess.SubprocessError):
        return False


HAS_BASH = _bash_with_shasum_can_reach_a_scratch_folder()


def the_function_in(launcher):
    lines = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8").splitlines(keepends=True)
    taken = []
    inside = False
    for line in lines:
        if line.startswith("toolchain_hash() {"):
            inside = True
        if inside:
            taken.append(line)
            if line.rstrip("\n") == "}":
                break
    if not taken:
        raise AssertionError(f"{launcher} has no toolchain_hash function")
    return "".join(taken)


def hash_with(function_text, context):
    script = function_text + '\ntoolchain_hash "$1"\n'
    result = subprocess.run(["bash", "-c", script, "_", str(context)],
                            capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        raise AssertionError(f"toolchain_hash failed: {result.stderr}")
    return result.stdout.strip()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_a_clean_context(root):
    """A small build context shaped like a working folder's .toolchain/."""
    write(root / "Dockerfile", "FROM scratch\n")
    write(root / "preview.sh", "#!/bin/bash\n")
    write(root / "scripts" / "build_site.py", "print('built')\n")
    write(root / "scripts" / "social_card.py", "print('card')\n")
    write(root / "support" / "swift" / "runner.py", "print('swift')\n")
    write(root / "contracts" / "toolchain.json", "{}\n")
    write(root / "patches" / "build.ts", "export {}\n")


def plant_bytecode(root):
    (root / "scripts" / "__pycache__").mkdir(parents=True, exist_ok=True)
    (root / "scripts" / "__pycache__" / "build_site.cpython-314.pyc").write_bytes(b"\x00\x01")
    (root / "support" / "swift" / "__pycache__").mkdir(parents=True, exist_ok=True)
    (root / "support" / "swift" / "__pycache__" / "runner.cpython-311.pyc").write_bytes(b"\x00\x02")
    (root / "stray.pyc").write_bytes(b"\x00\x03")
    (root / "contracts" / "loose.pyc").write_bytes(b"\x00\x04")
    (root / "patches" / "old.pyo").write_bytes(b"\x00\x05")


class TheBuildPhaseStripsBytecode(unittest.TestCase):

    def setUp(self):
        self.resources = Path(tempfile.mkdtemp(prefix="plantoir-747-bundle-"))
        self.addCleanup(shutil.rmtree, self.resources, True)
        make_a_clean_context(self.resources)

    def run_the_phase(self):
        return subprocess.run([sys.executable, "-I", str(BUILD_PHASE), str(self.resources)],
                              capture_output=True, text=True, timeout=120)

    def manifest_paths(self):
        paths = []
        text = (self.resources / "toolchain.hashes").read_text(encoding="utf-8")
        for line in text.splitlines():
            paths.append(line.split("\t")[0])
        return paths

    def test_the_build_phase_strips_bytecode_from_the_bundle(self):
        plant_bytecode(self.resources)
        result = self.run_the_phase()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.resources / "scripts" / "__pycache__").exists())
        self.assertFalse((self.resources / "support" / "swift" / "__pycache__").exists())
        self.assertFalse((self.resources / "contracts" / "loose.pyc").exists())
        self.assertFalse((self.resources / "patches" / "old.pyo").exists())
        for path in self.manifest_paths():
            self.assertNotIn("__pycache__", path)
            self.assertFalse(path.endswith(".pyc"), path)
            self.assertFalse(path.endswith(".pyo"), path)
        self.assertIn("removed 4 compiled Python files", result.stdout)

    def test_the_recipe_itself_is_kept_and_listed(self):
        plant_bytecode(self.resources)
        self.assertEqual(self.run_the_phase().returncode, 0)
        paths = self.manifest_paths()
        for kept in ["Dockerfile", "preview.sh", "scripts/build_site.py", "scripts/social_card.py",
                     "support/swift/runner.py", "contracts/toolchain.json", "patches/build.ts"]:
            self.assertIn(kept, paths)
        self.assertEqual(len(paths), 7)

    def test_a_clean_bundle_says_nothing_was_removed(self):
        result = self.run_the_phase()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("removed", result.stdout)

    def test_a_recipe_folder_that_is_a_link_is_refused_and_nothing_outside_is_removed(self):
        # Measured before the fix: the phase followed a linked scripts/ and
        # deleted the caches at the link's target, outside the bundle.
        outside = Path(tempfile.mkdtemp(prefix="plantoir-747-outside-"))
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / "__pycache__").mkdir()
        (outside / "__pycache__" / "x.pyc").write_bytes(b"\x00")
        (outside / "y.pyc").write_bytes(b"\x00")
        shutil.rmtree(self.resources / "scripts")
        os.symlink(outside, self.resources / "scripts")
        result = self.run_the_phase()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is a link", result.stderr)
        self.assertTrue((outside / "__pycache__" / "x.pyc").exists())
        self.assertTrue((outside / "y.pyc").exists())

    def test_a_linked_folder_further_down_is_not_followed(self):
        outside = Path(tempfile.mkdtemp(prefix="plantoir-747-outside-"))
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / "__pycache__").mkdir()
        (outside / "__pycache__" / "x.pyc").write_bytes(b"\x00")
        os.symlink(outside, self.resources / "support" / "linked")
        self.assertEqual(self.run_the_phase().returncode, 0)
        self.assertTrue((outside / "__pycache__" / "x.pyc").exists())

    def test_a_file_at_the_top_of_the_bundle_is_not_its_business(self):
        # Only the four recipe folders are the phase's to change. A .pyc at the
        # Resources root is never mirrored, so it is left where it is.
        (self.resources / "stray.pyc").write_bytes(b"\x00")
        self.assertEqual(self.run_the_phase().returncode, 0)
        self.assertTrue((self.resources / "stray.pyc").exists())


@unittest.skipUnless(HAS_BASH, "needs a bash with shasum that can reach a scratch folder")
class TheLaunchersSkipBytecode(unittest.TestCase):

    def setUp(self):
        self.context = Path(tempfile.mkdtemp(prefix="plantoir-747-context-"))
        self.addCleanup(shutil.rmtree, self.context, True)
        make_a_clean_context(self.context)

    def test_the_three_launchers_hash_alike(self):
        texts = []
        for launcher in LAUNCHERS:
            texts.append(the_function_in(launcher))
        self.assertEqual(texts[0], texts[1], "setup.sh and preview.sh have different toolchain_hash functions")
        self.assertEqual(texts[0], texts[2], "setup.sh and deploy.sh have different toolchain_hash functions")
        clean = hash_with(texts[0], self.context)
        plant_bytecode(self.context)
        self.assertEqual(hash_with(texts[0], self.context), clean,
                         "a planted __pycache__ or .pyc changed the image tag")

    def test_the_swift_image_tag_skips_bytecode_too(self):
        # preview.sh and verify.sh hash support/swift alone for the Swift image.
        function_text = the_function_in("preview.sh")
        swift = self.context / "support" / "swift"
        clean = hash_with(function_text, swift)
        plant_bytecode(self.context)
        self.assertEqual(hash_with(function_text, swift), clean)

    def test_a_clean_context_hashes_as_it_did(self):
        # Continuity, not a must-fail: the prune renames no teacher's image.
        today = hash_with(the_function_in("preview.sh"), self.context)
        before = hash_with(TOOLCHAIN_HASH_BEFORE_747, self.context)
        self.assertEqual(today, before)

    def test_verify_sh_uses_the_launchers_own_function(self):
        # verify.sh's Swift gate tag is the launcher's function, read out of
        # preview.sh, never a copy that could drift from it.
        text = (REPOSITORY_ROOT / "verify.sh").read_text(encoding="utf-8")
        self.assertIn("eval \"$(sed -n '/^toolchain_hash() {/,/^}/p' preview.sh)\"", text)
        self.assertNotIn("\ntoolchain_hash() {", text)


class EveryCheckLooksInEveryRecipeFolder(unittest.TestCase):

    def test_the_release_check_and_verify_name_every_recipe_folder(self):
        release_check = (REPOSITORY_ROOT / "mac-app" / "release" / "check-no-bytecode.sh").read_text(encoding="utf-8")
        verify = (REPOSITORY_ROOT / "verify.sh").read_text(encoding="utf-8")
        expected = "find " + " ".join(recipe_folders()) + " "
        self.assertIn(expected, release_check,
                      "check-no-bytecode.sh does not look in contracts/toolchain.json -> recipeFolders")
        bytecode_check = verify[verify.index("# Nothing may have left bytecode behind."):]
        self.assertIn(expected, bytecode_check,
                      "verify.sh's bytecode check does not look in contracts/toolchain.json -> recipeFolders")

if __name__ == "__main__":
    unittest.main(verbosity=2)

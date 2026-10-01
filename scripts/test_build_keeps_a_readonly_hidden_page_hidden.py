#!/usr/bin/env python3
"""
A page the teacher HID stays hidden when its file is READ-ONLY (#241).

The build copies every page into its own tree with `shutil.copy2`, which
carries the read-only bit (on Windows the attribute; on the mac the mode), and
then rewrites the COPY's frontmatter - which is where `draft: true` becomes
`publish: false`. If that rewrite fails, the copy keeps `draft: true` with no
`publish` key, and the site publishes anything that does not say
`publish: false`: the page the teacher hid is PUBLISHED.

Reachable on Windows today. The native build runs as the teacher, not as
root, in a build tree on the host, so a read-only page anywhere in a course -
left by OneDrive, a zip from another tool, or the older read-only attribute
some tools set - arrives read-only. (A reference course is locked with access
entries rather than this bit precisely because the bit travels; this test is
the belt to that design's braces.) On the mac the build writes in the
container as root, where the rewrite succeeds whatever the mode; this test
still runs there and holds the same line.

So `process_frontmatter` makes the build's own copy writable before it writes.
Only ever the BUILD's copy: the teacher's page is never touched by this.

`build_site` imports `frontmatter`, which lives only inside the container on
the mac; verify.sh runs this in the image. Windows' `PythonToolchainTests`
discovers it.
"""
import os
import shutil
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

import build_site


def _make_read_only(path: Path) -> None:
    os.chmod(path, stat.S_IREAD)


class AReadOnlyHiddenPageStaysHidden(unittest.TestCase):

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-readonly-page-"))

    def tearDown(self):
        for folder, _, files in os.walk(self.root):
            for name in files:
                try:
                    os.chmod(Path(folder) / name, stat.S_IREAD | stat.S_IWRITE)
                except OSError:
                    pass
        shutil.rmtree(self.root, ignore_errors=True)

    def _copied_into_the_build(self, text: str) -> Path:
        """A teacher's page, read-only, copied the way the build copies it."""
        teacher = self.root / "course" / "Concepts" / "Loops.md"
        teacher.parent.mkdir(parents=True)
        teacher.write_text(text, encoding="utf-8")
        _make_read_only(teacher)
        built = self.root / "build" / "content" / "Concepts" / "Loops.md"
        built.parent.mkdir(parents=True)
        shutil.copy2(teacher, built)
        self.assertFalse(os.access(built, os.W_OK), "copy2 should carry the read-only bit - else this test proves nothing")
        return built

    def test_a_draft_page_is_rewritten_hidden(self):
        built = self._copied_into_the_build("---\ntitle: Loops\ndraft: true\n---\n# Loops\n")
        build_site.process_frontmatter(built, 1)
        text = built.read_text(encoding="utf-8")
        self.assertIn("publish: false", text)
        self.assertNotIn("draft:", text)

    def test_a_page_hidden_in_this_section_only_is_rewritten_hidden(self):
        built = self._copied_into_the_build("---\ntitle: Loops\ndraftSection1: true\n---\n# Loops\n")
        build_site.process_frontmatter(built, 1)
        self.assertIn("publish: false", built.read_text(encoding="utf-8"))

    def test_the_teachers_own_page_is_left_exactly_as_it_was(self):
        teacher_text = "---\ndraft: true\n---\n# Loops\n"
        built = self._copied_into_the_build(teacher_text)
        build_site.process_frontmatter(built, 1)
        teacher = self.root / "course" / "Concepts" / "Loops.md"
        self.assertEqual(teacher_text, teacher.read_text(encoding="utf-8"))
        self.assertFalse(os.access(teacher, os.W_OK))


if __name__ == "__main__":
    unittest.main()

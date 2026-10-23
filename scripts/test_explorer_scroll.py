#!/usr/bin/env python3
"""
The sidebar scrolls only itself when a page opens (#611).

Quartz v4.5.0's explorer brought the current page's entry into view with
scrollIntoView, which scrolls EVERY scrollable ancestor: the sidebar is sticky
and as tall as the window, so a long page jumped 300-600 px down as it opened,
and a closed folder's hidden list slid toward a row nobody could see.
`patch_explorer_scroll_in_sidebar_only` replaces that one line, on every
build, with a scroll of the sidebar's own list.

This runs the patch against the real patches/explorer.inline.ts (the file
every section's scaffold starts from), after the expand-on-navigate patch
that runs before it on every build. What a browser does with the result is
measured off the built site by browser-checks/picture_heights.mjs and
browser-checks/sidebar_page_marker.mjs, run by verify.sh.

Stdlib only (build_site imports python-frontmatter only if it is there), so
Windows' PythonToolchainTests discovers and runs it too. Files are read as
UTF-8 explicitly.

Run with:

    python3 scripts/test_explorer_scroll.py
"""
import shutil
import tempfile
import unittest
from pathlib import Path

import build_site

REPOSITORY = Path(__file__).resolve().parent.parent
EXPLORER_INLINE = REPOSITORY / "patches" / "explorer.inline.ts"


def read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def the_restore_block(text):
    """The lines from reading the saved sidebar position to the end of the
    block that brings the current page's entry into view."""
    start = text.index('const scrollTop = sessionStorage.getItem("explorerScrollTop")')
    end = text.index("const explorerButtons", start)
    return text[start:end]


class SidebarScrollTests(unittest.TestCase):

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="explorer-scroll-"))
        self.inline = self.folder / "explorer.inline.ts"
        shutil.copyfile(EXPLORER_INLINE, self.inline)
        self.lines = []

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def patch(self):
        return build_site.patch_explorer_scroll_in_sidebar_only(self.inline, printer=self.lines.append)

    def test_the_real_file_still_has_quartzs_line_once(self):
        # If patches/ ever changes this line, the build patch stops applying:
        # this says so here rather than as a warning nobody reads.
        self.assertEqual(read_text(EXPLORER_INLINE).count(build_site._SIDEBAR_SCROLL_OLD), 1)

    def test_scrollintoview_is_replaced_by_a_scroll_of_the_sidebars_own_list(self):
        build_site.patch_explorer_inline_expand_on_navigate(self.inline)
        self.assertTrue(self.patch())
        text = read_text(self.inline)
        block = the_restore_block(text)
        self.assertNotIn("scrollIntoView", block)
        self.assertEqual(text.count(build_site.SIDEBAR_SCROLL_MARKER), 1)
        self.assertIn("explorerUl.scrollTop +=", block)
        # The entry is skipped inside a closed folder, and left alone when it
        # is already in view.
        self.assertIn('folder.classList.contains("open")', block)
        self.assertIn("if (!alreadyInView)", block)
        # A saved position still wins, untouched: that is how the sidebar
        # keeps its place from page to page in a tab.
        self.assertIn("explorerUl.scrollTop = parseInt(scrollTop)", block)

    def test_the_result_is_still_balanced(self):
        self.patch()
        before = the_restore_block(read_text(EXPLORER_INLINE))
        after = the_restore_block(read_text(self.inline))
        for opening, closing in (("{", "}"), ("(", ")")):
            self.assertEqual(before.count(opening) - before.count(closing),
                             after.count(opening) - after.count(closing), opening + closing)

    def test_a_second_run_changes_nothing(self):
        self.assertTrue(self.patch())
        once = read_text(self.inline)
        self.assertFalse(self.patch())
        self.assertEqual(read_text(self.inline), once)
        self.assertEqual(len(self.lines), 1)

    def test_a_file_of_another_shape_is_said_once_and_left_alone(self):
        reshaped = read_text(EXPLORER_INLINE).replace(
            build_site._SIDEBAR_SCROLL_OLD, 'activeElement.scrollIntoView({ block: "center" })')
        self.inline.write_text(reshaped, encoding="utf-8")
        self.assertFalse(self.patch())
        self.assertEqual(read_text(self.inline), reshaped)
        self.assertEqual(len(self.lines), 1)
        self.assertIn("changed shape", self.lines[0])

    def test_a_missing_file_is_said_and_the_build_carries_on(self):
        self.inline.unlink()
        self.assertFalse(self.patch())
        self.assertEqual(len(self.lines), 1)

    def test_it_runs_on_every_build_after_expand_on_navigate(self):
        # In the ALWAYS section, so a section staged before the fix heals on
        # its next preview without a full rebuild.
        source = read_text(REPOSITORY / "scripts" / "build_site.py")
        staged_only = source.index("if full_rebuild or not output_dir.exists():")
        always = source.index("# ALWAYS: Fix Netlify static import target", staged_only)
        expand = source.index("    patch_explorer_inline_expand_on_navigate(explorer_inline)\n", always)
        scroll = source.index("    patch_explorer_scroll_in_sidebar_only(explorer_inline)\n", always)
        self.assertLess(expand, scroll)


if __name__ == "__main__":
    unittest.main()

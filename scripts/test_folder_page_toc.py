#!/usr/bin/env python3
"""
Issue #520: a folder page shows its table of contents.

Quartz v4.5.0 renders every `folder/index.md` — a curriculum folder's index
among them — with `defaultListPageLayout`, whose right column is `[]`: the
table of contents was computed and placed nowhere, so `enableToc: true` and
five headings showed nothing (measured on the #520 plan: the Ontario and AP CSP
curriculum indexes, toc 0, while an expectation page with two headings showed
one). The build now puts the content layout's own
`Component.DesktopOnly(Component.TableOfContents())` in the list layout's
right column — `build_site._wire_list_page_toc`, run by
`wire_quartz_additions` on every build.

Driven through `wire_quartz_additions` itself, over a folder holding only a
`quartz.layout.ts` shaped as v4.5.0 ships it (the other wires meet a missing
file, warn and carry on), so forgetting to add the wire to that list fails
here, not only in verify.sh. The key is `contracts/file-formats.json` ->
`pageOptIns.keys` (`enableToc`); what a built page shows is verify.sh 6h's.

Pure Python, temporary folders, no Docker: verify.sh runs it on the mac host
and Windows' PythonToolchainTests discovers it.
"""
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import build_site  # noqa: E402
import contracts  # noqa: E402
import toolchain_paths  # noqa: E402

TOC = "Component.DesktopOnly(Component.TableOfContents())"

# The two layouts as Quartz v4.5.0 ships them in the website builder's image
# (/opt/quartz/quartz.layout.ts), with the Explorer's filter shortened.
LAYOUT_AS_SHIPPED = """import { PageLayout, SharedLayout } from "./quartz/cfg"
import * as Component from "./quartz/components"

export const sharedPageComponents: SharedLayout = {
  head: Component.Head(),
  header: [],
  afterBody: [],
  footer: Component.Footer({
    links: {},
  }),
}

export const defaultContentPageLayout: PageLayout = {
  beforeBody: [
    Component.Breadcrumbs(),
    Component.ArticleTitle(),
    Component.ContentMeta(),
    Component.TagList(),
  ],
  left: [
    Component.PageTitle(),
    Component.MobileOnly(Component.Spacer()),
    Component.Explorer({
    folderClickBehavior: "link",
  }),
  ],
  right: [
    Component.Graph(),
    Component.DesktopOnly(Component.TableOfContents()),
    Component.Backlinks(),
  ],
}

export const defaultListPageLayout: PageLayout = {
  beforeBody: [Component.Breadcrumbs(), Component.ArticleTitle(), Component.ContentMeta()],
  left: [
    Component.PageTitle(),
    Component.MobileOnly(Component.Spacer()),
    Component.Explorer({
    folderClickBehavior: "link",
  }),
  ],
  right: [],
}
"""


def layout_block(text: str, name: str) -> str:
    start = text.index(f"export const {name}")
    end = text.find("export const", start + 1)
    if end < 0:
        end = len(text)
    return text[start:end]


def right_column(block: str) -> str:
    """`right: [ ... ]`, to its matching bracket."""
    start = block.index("right: [")
    depth = 0
    position = start + len("right: ")
    while position < len(block):
        character = block[position]
        if character == "[":
            depth += 1
        elif character == "]":
            depth -= 1
            if depth == 0:
                return block[start:position + 1]
        position += 1
    raise AssertionError("the right column never closes")


class FolderPagesGetTheTableOfContents(unittest.TestCase):

    def wire(self, folder: Path) -> str:
        with redirect_stdout(io.StringIO()):
            build_site.wire_quartz_additions(folder)
        return (folder / "quartz.layout.ts").read_text(encoding="utf-8")

    def test_the_list_layout_gets_it_once_and_the_content_layout_keeps_its_own(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            (folder / "quartz.layout.ts").write_text(LAYOUT_AS_SHIPPED, encoding="utf-8")
            content_right_before = right_column(layout_block(LAYOUT_AS_SHIPPED, "defaultContentPageLayout"))

            once = self.wire(folder)
            twice = self.wire(folder)

            self.assertEqual(once, twice, "a second build must change nothing")
            list_block = layout_block(once, "defaultListPageLayout")
            self.assertEqual(right_column(list_block), f"right: [{TOC}]")
            self.assertEqual(list_block.count("TableOfContents"), 1)
            content_block = layout_block(once, "defaultContentPageLayout")
            self.assertEqual(right_column(content_block), content_right_before)
            self.assertEqual(content_block.count("TableOfContents"), 1)
            self.assertEqual(layout_block(once, "sharedPageComponents").count("TableOfContents"), 0)

    def test_a_layout_of_another_shape_is_left_alone_with_a_warning(self):
        changed = LAYOUT_AS_SHIPPED.replace("  right: [],\n}\n", "  right: [Component.Graph()],\n}\n")
        self.assertNotEqual(changed, LAYOUT_AS_SHIPPED)
        with tempfile.TemporaryDirectory() as temp:
            layout = Path(temp) / "quartz.layout.ts"
            layout.write_text(changed, encoding="utf-8")
            output = io.StringIO()
            with redirect_stdout(output):
                build_site._wire_list_page_toc(layout)
            self.assertEqual(layout.read_text(encoding="utf-8"), changed)
            self.assertIn("Could not add the table of contents to folder pages", output.getvalue())

    def test_a_list_layout_that_already_has_one_is_left_alone(self):
        already = LAYOUT_AS_SHIPPED.replace(
            "  right: [],\n}\n", "  right: [\n    Component.TableOfContents(),\n  ],\n}\n")
        with tempfile.TemporaryDirectory() as temp:
            layout = Path(temp) / "quartz.layout.ts"
            layout.write_text(already, encoding="utf-8")
            with redirect_stdout(io.StringIO()):
                build_site._wire_list_page_toc(layout)
            self.assertEqual(layout.read_text(encoding="utf-8"), already)


class TheKeyIsListed(unittest.TestCase):

    def test_enable_toc_is_with_the_other_page_keys(self):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        entries = contracts.section("file-formats", "pageOptIns", "keys")
        found = None
        for entry in entries:
            if entry["key"] == "enableToc":
                found = entry
        self.assertIsNotNone(found, "pageOptIns.keys has no enableToc")
        self.assertEqual(found["type"], "boolean")


if __name__ == "__main__":
    unittest.main()

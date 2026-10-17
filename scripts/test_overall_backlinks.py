#!/usr/bin/env python3
"""
"When did we do this?" on an overall expectation's page (#505).

Classes connect to SPECIFIC expectations (B1.3), so the panel on an overall
expectation's page (B1) used to be empty. The build now writes, into the
backlinks component, which specific expectations each overall page gathers
(`overall_backlink_children`, behind CQ4T-OVERALL-ANCHOR), and the component
runs ONE filter over the site's pages with targets = [slug, ...children].

The cases are `contracts/shared-rules.json` -> `curriculumRules.overallBacklinks`.
Each is laid out as a real course folder, the build's own functions write the
real support/Backlinks.tsx (a copy), and the lines they wrote are read back:
the map must be the case's `children`, and the component's filter — modelled
here over the case's pages, in the case's (Quartz's) order, with the
structural set the build wrote beside it — must give the case's `backlinks`.
verify.sh 6k checks the real thing in a built site.

Pure Python, temporary folders, no Docker: verify.sh runs it on the mac host
and Windows' PythonToolchainTests discovers it.
"""
import io
import json
import re
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

REPOSITORY = Path(__file__).resolve().parent.parent
COMPONENT = REPOSITORY / "support" / "Backlinks.tsx"


def use_the_repository_contracts():
    repo_contracts = REPOSITORY / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def overall_backlink_cases() -> list:
    use_the_repository_contracts()
    return contracts.section("shared-rules", "curriculumRules", "overallBacklinks", "cases")


def lay_out_course(root: Path, case: dict) -> None:
    for name in case["curriculumPages"]:
        page = root / (name + ".md")
        page.parent.mkdir(parents=True, exist_ok=True)
        page.write_text(f"---\ntitle: {page.stem}\n---\nA curriculum page.\n", encoding="utf-8")


def write_the_component(root: Path, case: dict) -> str:
    """The real component, rewritten by the build's own two functions, as
    `build_section_site` calls them."""
    component = root / "Backlinks.tsx"
    component.write_text(COMPONENT.read_text(encoding="utf-8"), encoding="utf-8")
    content_root = root / "content"
    plan = build_site.plan_coverage_maps(content_root, case["folders"])
    with redirect_stdout(io.StringIO()):
        build_site.set_backlinks_structural_pages(component, content_root, plan)
        build_site.set_backlinks_overall_children(component, content_root, plan)
    return component.read_text(encoding="utf-8")


def read_structural(component_text: str) -> set:
    match = re.search(r"const structural = new Set<string>\(\[(.*)\]\)\n", component_text)
    names = json.loads("[" + match.group(1) + "]")
    result = set()
    for name in names:
        result.add(name)
    return result


def read_overall_children(component_text: str) -> dict:
    match = re.search(r"const overallChildren = new Map<string, string\[\]>\(\[(.*)\]\)\n",
                      component_text)
    pairs = json.loads("[" + match.group(1) + "]")
    children = {}
    for overall_slug, specific_slugs in pairs:
        children[overall_slug] = specific_slugs
    return children


def backlinks_of(slug: str, site_pages: list, structural: set, children: dict) -> list:
    """What the component lists on `slug`: one pass over the site's pages, in
    their order; a page is listed when it links ANY target and is not
    structural (in a curriculum folder, or a coverage map)."""
    targets = [slug]
    for specific_slug in children.get(slug, []):
        targets.append(specific_slug)
    listed = []
    for page in site_pages:
        page_slug = page["slug"]
        folder = page_slug.split("/")[0]
        if page_slug in structural or folder in structural:
            continue
        links_a_target = False
        for target in targets:
            if target in page["links"]:
                links_a_target = True
        if links_a_target:
            listed.append(page_slug)
    return listed


class OverallBacklinksTests(unittest.TestCase):

    def test_the_component_carries_the_anchor_and_one_filter_over_the_targets(self):
        text = COMPONENT.read_text(encoding="utf-8")
        self.assertIn("// CQ4T-OVERALL-ANCHOR: do not remove; build_site.py rewrites this line\n"
                      "    const overallChildren = new Map<string, string[]>([])\n", text)
        self.assertIn("const targets = [slug, ...(overallChildren.get(slug) ?? [])]", text)
        self.assertEqual(text.count("allFiles.filter("), 1)
        self.assertIn("(file) => linksAnyTarget(file.links) && !isStructural(simplifySlug(file.slug!)),",
                      text)

    def test_contract_cases(self):
        cases = overall_backlink_cases()
        self.assertGreaterEqual(len(cases), 4)
        for case in cases:
            with self.subTest(case["name"]):
                with tempfile.TemporaryDirectory() as temp:
                    root = Path(temp)
                    lay_out_course(root / "content", case)
                    content_root = root / "content"
                    plan = build_site.plan_coverage_maps(content_root, case["folders"])
                    self.assertEqual(build_site.overall_backlink_children(content_root, plan),
                                     case["children"])
                    text = write_the_component(root, case)
                    children = read_overall_children(text)
                    self.assertEqual(children, case["children"])
                    structural = read_structural(text)
                    for slug, expected in case["backlinks"].items():
                        self.assertEqual(
                            backlinks_of(slug, case["sitePages"], structural, children),
                            expected, slug)

    def test_rewriting_twice_leaves_one_line(self):
        case = overall_backlink_cases()[0]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lay_out_course(root / "content", case)
            first = write_the_component(root, case)
            component = root / "Backlinks.tsx"
            plan = build_site.plan_coverage_maps(root / "content", case["folders"])
            with redirect_stdout(io.StringIO()):
                build_site.set_backlinks_overall_children(component, root / "content", plan)
            second = component.read_text(encoding="utf-8")
            self.assertEqual(first, second)
            self.assertEqual(second.count("const overallChildren ="), 1)

    def test_no_curriculum_folder_writes_an_empty_map(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "content").mkdir()
            component = root / "Backlinks.tsx"
            component.write_text(COMPONENT.read_text(encoding="utf-8"), encoding="utf-8")
            with redirect_stdout(io.StringIO()):
                build_site.set_backlinks_overall_children(component, root / "content", [])
            self.assertEqual(read_overall_children(component.read_text(encoding="utf-8")), {})

    def test_a_page_called_like_a_built_in_object_key_is_a_plain_slug(self):
        """The map is a JavaScript Map, so `get("constructor")` is undefined
        rather than Object.prototype.constructor (a function, which would
        break the spread)."""
        text = COMPONENT.read_text(encoding="utf-8")
        self.assertNotIn("overallChildren[", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)

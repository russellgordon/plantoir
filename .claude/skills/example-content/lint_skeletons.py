"""Check the generated skeletons before they ship.

A skeleton is installed for every Ontario course code that has no example
content, so a mistake here is a mistake in about 1,900 courses. The checks
are deliberately blunt: every link resolves, every page is titled, every
sentinel is where the installer expects it, and no template token survived
into the output.

    python3 .claude/skills/example-content/lint_skeletons.py [family ...]
"""

import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKELETONS = ROOT / "support" / "skeletons"

LINK = re.compile(r"!?\[\[([^\]|#]+?)(?:\\?\|[^\]]*)?(?:#[^\]|]*)?\]\]")
CLASS_SENTINEL = re.compile(r"created: __CREATED_CLASS_(\d+)__")


def frontmatter(text: str) -> dict:
    """The frontmatter as a flat dict of strings — enough for these checks."""
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end < 0:
        return {}
    fields = {}
    for line in text[4:end].split("\n"):
        match = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
        if match:
            fields[match.group(1)] = match.group(2)
    return fields


def check(family: str) -> list:
    root = SKELETONS / family
    problems = []
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    curriculum = manifest.get("curriculum_folder")

    pages = {}
    for path in sorted(root.rglob("*.md")):
        pages[path.stem] = path
    # Folder landings are addressed as `Folder/index`, so record those too.
    addressable = set(pages)
    for path in root.rglob("index.md"):
        addressable.add(f"{path.parent.name}/index")

    class_ordinals = []
    for path in sorted(root.rglob("*.md")):
        relative = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        fields = frontmatter(text)
        is_curriculum = curriculum and f"/{curriculum}/" in f"/{relative}"

        # Windows cannot create these characters in a filename, and Git for
        # Windows refuses to check such a path out — which stops the whole
        # repository fast-forwarding on that machine.
        #
        # A skeleton page slips past every other check here: this linter
        # requires `title` to MATCH the filename, so "Why Bother?.md" titled
        # "Why Bother?" is internally consistent, correct-looking, and
        # unusable on half the machines this ships to. That matching rule is
        # a GENERATOR-consistency choice, not a technical one — Obsidian and
        # Quartz are happy for the two to differ, which is what `title` is
        # for, and the payloads rely on exactly that (see SKILL.md). A shape
        # wanting a question mark can therefore either keep it in the prose,
        # or split the two the way the payloads do; what it may never do is
        # put one of these characters in the filename.
        for forbidden in '<>:"|?*':
            if forbidden in path.name:
                problems.append(
                    f"{relative}: filename contains {forbidden!r}, which "
                    f"Windows cannot create")
                break

        if not fields:
            problems.append(f"{relative}: no frontmatter")
            continue
        title = fields.get("title")
        if path.name != "index.md" and title != path.stem:
            # One sanctioned exception: filenames fold combining accents to
            # ASCII (Finder decomposes them to NFD inside a DMG and wikilinks
            # break — see write() in generate_skeletons.py), so a title with
            # an é may sit in a file named with an e, PROVIDED the accented
            # name is kept as an alias so old wikilinks still resolve.
            folded = "".join(
                ch for ch in unicodedata.normalize("NFD", title or "")
                if not unicodedata.combining(ch))
            alias_kept = f'- "{title}"' in text
            if not (folded == path.stem and alias_kept):
                problems.append(f"{relative}: title is {title!r}, filename says {path.stem!r}")
        if path.name == "index.md" and not title:
            problems.append(f"{relative}: a folder landing needs a title, or it shows as 'index'")

        if is_curriculum:
            if "created:" in text:
                problems.append(f"{relative}: curriculum pages carry no created: line")
        elif "created:" not in text:
            problems.append(f"{relative}: no created: line, so the installer cannot date it")
        elif "created: __CREATED" not in text:
            problems.append(f"{relative}: created: without a sentinel")

        match = CLASS_SENTINEL.search(text)
        if match:
            class_ordinals.append(int(match.group(1)))

        if "%" in text:
            leftover = re.findall(r"%[A-Z_]{3,}%", text)
            if leftover:
                problems.append(f"{relative}: template token(s) left in the page: {sorted(set(leftover))}")

        prose = re.sub(r"```[\s\S]*?```", "", text)
        prose = re.sub(r"`[^`\n]*`", "", prose)
        for link in LINK.finditer(prose):
            target = link.group(1).strip().rstrip("\\")
            if "/" in target:
                # A path link has to resolve as a path: every folder has an
                # index, so matching on the stem alone would accept a link
                # to a folder that does not exist.
                if target in addressable:
                    continue
            elif target in addressable:
                continue
            problems.append(f"{relative}: links to {target!r}, which does not exist here")

    if sorted(class_ordinals) != list(range(1, 13)):
        problems.append(f"class pages carry ordinals {sorted(class_ordinals)}, expected 1–12")

    key_links = root / "per_section" / "Key Links.md"
    if not key_links.exists():
        problems.append("per_section/Key Links.md is missing")
    else:
        bullets = [line.strip() for line in key_links.read_text(encoding="utf-8").splitlines()
                   if line.startswith("- ")]
        if not bullets or bullets[-1] != "- [[Scavenger Hunt]]":
            problems.append("per_section/Key Links.md: Scavenger Hunt must be the LAST entry")
        if f"- [[{curriculum}/index|Curriculum Expectations]]" not in bullets:
            problems.append("per_section/Key Links.md: missing the Curriculum Expectations link")

    landing = root / "per_section" / "index.md"
    if landing.exists() and "![[Unit 1, Day 1]]" not in landing.read_text(encoding="utf-8"):
        problems.append("per_section/index.md: Most Recent Class transcludes nothing")

    # The sidebar rule: the curriculum folder is never visible, every other
    # shared folder carries a chevron, and All Classes stays a plain link.
    # Which folders count for marks — the ring on a cell in the Curriculum
    # Coverage map, and Ontario's ask that every overall expectation be
    # evaluated at least once. Declared rather than inferred at install time,
    # because inference is a substring ("task") while the build matches a
    # pooled name EXACTLY: a family whose folder is "Thinking Tasks" would
    # silently stop counting under a pool of ["Tasks"].
    graded = manifest.get("graded_folders")
    if graded is None:
        problems.append(
            "manifest: no graded_folders. Say which folders hold work that "
            "counts for marks, even if the answer is []"
        )
    else:
        known = set(manifest.get("shared_folders", [])) \
            | set(manifest.get("per_section_folders", []))
        for name in graded:
            if name not in known:
                problems.append(
                    f"manifest: graded folder {name!r} is not one of this "
                    "course's folders, so nothing will ever count for marks in it"
                )
        if not graded:
            problems.append(
                "manifest: graded_folders is empty, so no expectation can ever "
                "be shown as evaluated. Deliberate? Say so in a comment field; "
                "otherwise name the folder your assessed work lives in"
            )

    hidden = manifest.get("hidden", [])
    expandable = manifest.get("expandable", [])
    if curriculum not in hidden:
        problems.append(f"manifest: {curriculum!r} must be hidden from the sidebar")
    if curriculum in expandable:
        problems.append(f"manifest: {curriculum!r} is hidden, so it cannot be expandable")
    for name in manifest.get("shared_folders", []):
        if name == curriculum or name in hidden:
            continue
        if name not in expandable:
            problems.append(f"manifest: shared folder {name!r} has no chevron")
    for name in manifest.get("per_section_folders", []):
        if name in expandable:
            problems.append(f"manifest: {name!r} is a per-section folder and stays a plain link")

    for name in manifest.get("shared_folders", []):
        if not (root / "shared" / name).is_dir():
            problems.append(f"manifest lists shared folder {name!r}, which was never written")
    for name in manifest.get("shared_files", []):
        if not (root / "shared" / name).exists():
            problems.append(f"manifest lists shared file {name!r}, which was never written")
    for name in manifest.get("per_section_files", []):
        if not (root / "per_section" / name).exists():
            problems.append(f"manifest lists per-section file {name!r}, which was never written")

    return problems


def main():
    families = sys.argv[1:] or sorted(p.name for p in SKELETONS.iterdir() if p.is_dir())
    total = 0
    for family in families:
        problems = check(family)
        total += len(problems)
        if problems:
            print(f"\n{family}: {len(problems)} problem(s)")
            for line in problems[:12]:
                print(f"   {line}")
            if len(problems) > 12:
                print(f"   … and {len(problems) - 12} more")
    print(f"\n{len(families)} skeletons checked; "
          + ("clean" if not total else f"{total} problem(s)"))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())

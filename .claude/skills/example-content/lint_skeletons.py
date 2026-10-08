"""Check the generated skeletons before they ship.

A skeleton is installed for every Ontario course code whose teacher is not
taking example content — the ~1,900 codes that have no payload, and the 38
that have one the teacher declined — so a mistake here is a mistake in
about 1,900 courses. The checks
are deliberately blunt: every link resolves, every page is titled, every
sentinel is where the installer expects it, no template token — %PERCENT% or
{brace} — survived into the output, the subject never lands in front of a
noun it does not fit ("a this course course", #328), and the class website is
never called "the published website" (#443). That last rule also reads the
Example Course (`support/example_course/`, EXC2O), whose template pages carry
the same sentences and which no other linter reads — and so does
`lint_payload.py`'s heading-mark rule (#444): the template's sentence must
say "Every `##` (level 2) and `###` (level 3) heading", marks and all. Both
run when no family is named.

    python3 .claude/skills/example-content/lint_skeletons.py [family ...]
"""

import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# Where a page's code is: the toolchain's own definition (#313). A link shown
# inside code is an example of the syntax, not a link that has to resolve.
sys.path.insert(0, str(ROOT / "scripts"))
import markdown_code  # noqa: E402
SKELETONS = ROOT / "support" / "skeletons"
EXAMPLE_COURSE = ROOT / "support" / "example_course"

LINK = re.compile(r"!?\[\[([^\]|#]+?)(?:\\?\|[^\]]*)?(?:#[^\]|]*)?\]\]")
CLASS_SENTINEL = re.compile(r"created: __CREATED_CLASS_(\d+)__")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_skeletons import article_for  # noqa: E402 — one rule for "a"/"an", shared with the generator
# The heading-mark rule (#444) has ONE home, lint_payload.py, which runs it on
# every payload page; it is borrowed here only to read the Example Course.
from lint_payload import heading_marks_missing  # noqa: E402
from lint_payload import check_the_checks as heading_mark_rule_misbehaves  # noqa: E402

# A {brace} placeholder is never filled — the generator's tokens are
# %PERCENT% ones, because the pages carry LaTeX and YAML in earnest — so one
# that reaches a page ships as written. Every Concepts page said "{subject}"
# and three Fieldwork pages "{room}" until #328. A brace opened straight after
# a letter, a backslash, `^`, `_`, `$` or another brace is LaTeX (`\frac{a}{b}`,
# `x^{2}`, `\begin{aligned}`) and is left alone; so is anything inside `$…$`
# or `$$…$$` (math_removed), and a brace after a LaTeX command and a space
# (`\mathrm {kg}`), which is checked on the text before the match.
BRACE_PLACEHOLDER = re.compile(r"(?<![\\\w}^_$])\{[A-Za-z_][A-Za-z0-9_ ]*\}")
LATEX_COMMAND_BEFORE = re.compile(r"\\[A-Za-z]+\s*$")

# The subject dropped in front of a noun where it does not fit: "a this
# course course", "A this course class", "a the language course", "a English
# course" — all shipped until #328. `%SUBJECT%` belongs after a preposition;
# in front of a noun the generator has %A_SUBJECT_COURSE% and
# %A_SUBJECT_CLASS_START%.
THIS_COURSE_BEFORE_A_NOUN = re.compile(r"\bthis course (course|class)\b", re.IGNORECASE)
LOWER_ARTICLE_BEFORE_THIS_OR_THE = re.compile(r"\ba (this|the)\b")
# "a"/"an" is checked against article_for, the generator's own rule. A
# capital "A" or "An" counts only where it cannot be a letter used as a name
# — "Plan A or B", "Option A is" — so it is skipped straight after a word.
ARTICLE_LOWER = re.compile(r"\b(a|an) ([A-Za-z][A-Za-z-]*)")
ARTICLE_UPPER = re.compile(r"(?<![A-Za-z,] )\b(A|An) ([A-Za-z][A-Za-z-]*)")
UPPER_START_OF_THIS_OR_THE = re.compile(r"(?<![A-Za-z,] )\bA (this|the)\b")

# The site students see is never "the published page / website / site" (#443,
# decided by Russell 2026-10-04): DEPLOY is what puts a site online, and
# PUBLISH only marks a page so a deploy includes it. A sentence about the
# website says "your class website"; a sentence about marking a page
# ("publish: true", "the newest published page", "never published") is
# right and stays — which is why the rule names the SITE, and a page only
# straight after "the" or "your". `[\s>]` lets the phrase wrap inside a callout.
SITE_CALLED_PUBLISHED = re.compile(
    r"\bpublished[\s>]+(?:web\s*)?sites?\b|\b(?:the|your)[\s>]+published[\s>]+pages?\b",
    re.IGNORECASE,
)

# Shapes the checks must accept and refuse, run before every lint so a
# widened rule cannot start biting real prose (or stop catching the #328
# shapes) unnoticed. A failure here is a broken LINTER, not a broken page.
MUST_BE_ACCEPTED = [
    "Plan A or B is fine.",
    "Option A is the default.",
    "Start with a one-page summary.",
    "a European exchange",
    "a unit test, a university, a useful habit",
    "an hour, an honest answer",
    "an English course, an arts class, an economics course",
    "a language course, a French course, a history course",
    "The mass is $\\mathrm {kg}$ and $ {n} $ is the count.",
    "Units: \\mathrm {kg} per \\text {m}.",
    "$$\\begin{aligned} x &= \\frac{a}{b} \\\\ y^{2} \\end{aligned}$$",
    "written for this course. This class asks people to try things.",
    "It starts at Unit 4, Day 21 because that is the newest PUBLISHED page in All Classes.",
    "it stays strictly on your computer and is never published or uploaded anywhere.",
    "on the right side of the page on your class website.",
    "A shared page can be published to one section and held back from another.",
]
MUST_BE_REFUSED = [
    "When an idea in {subject} needs explaining",
    "Work done outside the {room}.",
    "a placeholder written for a this course course.",
    "A this course class asks people to try things.",
    "written for a the language course.",
    "written for a English course.",
    "An economics class? A economics class asks.",
    "a urban studies course",
    "an unit",
    "an one-page summary",
    "the table of contents on the right side of the published page.",
    "a clickable link on the right side of your published\n> website!",
    "How it looks to your students on the published website:",
    "never exists on the published site!",
]


def math_removed(text: str) -> str:
    """The text with `$$…$$` and `$…$` spans taken out — LaTeX braces live there."""
    text = re.sub(r"\$\$[\s\S]*?\$\$", "", text)
    return re.sub(r"\$[^$\n]*\$", "", text)


def prose_problems(prose: str) -> list:
    """What is wrong with this prose (code already removed): unfilled
    placeholders and a subject or article that does not fit the next word."""
    problems = []
    text = math_removed(prose)
    unfilled = []
    for match in BRACE_PLACEHOLDER.finditer(text):
        line_start = text.rfind("\n", 0, match.start()) + 1
        if LATEX_COMMAND_BEFORE.search(text[line_start:match.start()]):
            continue
        unfilled.append(match.group(0))
    if unfilled:
        problems.append(f"unfilled placeholder(s) left in the page: {sorted(set(unfilled))}")
    misfit = THIS_COURSE_BEFORE_A_NOUN.search(text)
    if misfit:
        problems.append(f'the subject "this course" in front of a noun: {misfit.group(0)!r}')
    for pattern in (LOWER_ARTICLE_BEFORE_THIS_OR_THE, UPPER_START_OF_THIS_OR_THE):
        misfit = pattern.search(text)
        if misfit:
            problems.append(f'"a" in front of "this" or "the": {misfit.group(0)!r}')
    for pattern in (ARTICLE_LOWER, ARTICLE_UPPER):
        for match in pattern.finditer(text):
            article, word = match.group(1), match.group(2)
            if word.lower() in ("this", "the"):
                continue
            if article.lower() != article_for(word):
                problems.append(f'"{article}" in front of {word!r}: {match.group(0)!r}')
                break
    published = SITE_CALLED_PUBLISHED.search(text)
    if published:
        problems.append(
            f'the class website called "published" (#443 — say "your class website"): '
            f"{published.group(0)!r}"
        )
    return problems


def check_the_checks() -> list:
    """The linter's own rules against the shapes they must accept and refuse."""
    failures = []
    for sentence in MUST_BE_ACCEPTED:
        found = prose_problems(sentence)
        if found:
            failures.append(f"refused a sentence it must accept: {sentence!r} -> {found}")
    for sentence in MUST_BE_REFUSED:
        if not prose_problems(sentence):
            failures.append(f"accepted a sentence it must refuse: {sentence!r}")
    for failure in heading_mark_rule_misbehaves():
        failures.append(f"heading-mark rule (#444): {failure}")
    return failures


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

        # The prose the wording checks read: the page with its code blanked
        # out by the toolchain's own definition of code (#313), so an example
        # of syntax is never read as a sentence.
        prose_characters = list(text)
        for start, end in markdown_code.code_ranges(text):
            for position in range(start, end):
                if prose_characters[position] != "\n":
                    prose_characters[position] = " "
        prose = "".join(prose_characters)

        for problem in prose_problems(prose):
            problems.append(f"{relative}: {problem}")
        for link in markdown_code.matches_outside_code(LINK, text):
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


def example_course_problems() -> list:
    """The #443 phrase rule and the #444 heading-mark rule over the Example
    Course (EXC2O).

    Only those TWO rules: EXC2O is hand-written course content, not a
    skeleton, so the skeleton-shape checks (sentinels, manifests, every link)
    do not apply to it. It copies the skeleton template sentences, though,
    and was missed once because nothing read it (review of #443,
    2026-10-07). The heading-mark rule is read on the RAW page, as
    lint_payload.py reads it: with the backticked marks removed, the right
    sentence looks exactly like the broken one.
    """
    problems = []
    for page in sorted(EXAMPLE_COURSE.rglob("*.md")):
        text = page.read_text(encoding="utf-8")
        where = page.relative_to(EXAMPLE_COURSE)
        published = SITE_CALLED_PUBLISHED.search(text)
        if published:
            problems.append(
                f'{where}: the class website called "published" (#443 — say '
                f'"your class website"): {published.group(0)!r}'
            )
        for number in heading_marks_missing(text):
            problems.append(
                f"{where}:{number}: the heading sentence names a level with no mark "
                f"before it (\"Every  (level 2)\") — write Every `##` (level 2) and "
                f"`###` (level 3) (#444)"
            )
    return problems


def main():
    broken = check_the_checks()
    if broken:
        print("lint_skeletons.py's own checks are wrong — fix the linter before trusting it:")
        for line in broken:
            print(f"   {line}")
        return 2
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
    if not sys.argv[1:]:
        problems = example_course_problems()
        total += len(problems)
        if problems:
            print(f"\nexample_course: {len(problems)} problem(s)")
            for line in problems[:12]:
                print(f"   {line}")
    checked = f"{len(families)} skeletons"
    if not sys.argv[1:]:
        checked += " and the Example Course"
    print(f"\n{checked} checked; "
          + ("clean" if not total else f"{total} problem(s)"))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())

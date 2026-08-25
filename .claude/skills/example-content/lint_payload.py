"""Lint an example-content payload before shipping it.

Usage:  python3 .claude/skills/example-content/lint_payload.py ADA1O

Checks every rule the installer and the site build depend on. Exit code 0
means clean; 1 means problems were printed.
"""

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]

# An Ontario credit is 110 hours of scheduled time. A semestered day school
# runs 75-minute periods, so a full credit is about 86 periods plus a
# three-hour final evaluation — the tolerance either side is one week of
# classes, because timetables really do differ.
#
# HALF CREDITS are real courses, not exceptions: Career Studies and Civics
# are 55 hours each and are commonly timetabled back to back in one
# semester. A payload declares what it is in its manifest rather than
# having the linter guess from the page count, so the arithmetic below
# scales instead of special-casing.
FULL_CREDIT_HOURS = 110
PERIOD_MINUTES = 75
DEFAULT_FINAL_EVALUATION_HOURS = 3
# One week of classes either side of the target, scaled to the credit.
HOURS_TOLERANCE = 6
MINIMUM_REVIEW_CLASSES = 3


def lint(course_code: str) -> int:
    root = REPO_ROOT / "support" / "example_content" / course_code
    if not root.is_dir():
        print(f"no payload at {root}")
        return 1

    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    pages = sorted(root.rglob("*.md"))
    page_names = {page.stem for page in pages} | {"index"}

    # Folder-qualified targets such as [[Curriculum/index]]. These need the
    # whole path checked: matching only the last segment lets a link to a
    # missing Curriculum/index pass because some other folder has an index.
    qualified_names = set()
    for page in pages:
        parts = page.relative_to(root).parts
        for depth in range(1, len(parts)):
            qualified_names.add("/".join(parts[depth - 1:])[:-len(".md")])
    curriculum_folder = manifest.get("curriculum_folder")

    problems = []

    # Which folders count for marks — the ring on a cell in the Curriculum
    # Coverage map. Declared rather than inferred at install time, because
    # inference is a substring ("task") while the build matches a pooled name
    # EXACTLY: a payload whose folder was "Thinking Tasks" would silently stop
    # counting under a pool of ["Tasks"].
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
                "be shown as evaluated — name the folder the assessed work lives in"
            )
    # Obsidian comments, paired exactly the way the vendored Quartz pairs
    # them (`commentRegex = /%%[\s\S]*?%%/g` in ofm.ts): non-greedy, so
    # `%%curriculum-start%%` consumes its own delimiters and the
    # transclusions between the markers are NOT inside a comment.
    comment_pattern = re.compile(r"%%(.*?)%%", re.S)
    missing_triangulation = []
    bulky_pies = []
    link_pattern = re.compile(r"!?\[\[([^\]|#]+?)(?:\\?\|[^\]]*)?(?:#[^\]|]*)?\]\]")
    class_sentinel = re.compile(r"created: __CREATED_CLASS_(\d+)__")

    class_ordinals = []
    linked_from_classes = set()
    page_links = {}
    class_pages = set()

    for page in pages:
        text = page.read_text(encoding="utf-8")
        rel = str(page.relative_to(root))
        is_curriculum = curriculum_folder and rel.startswith(f"shared/{curriculum_folder}/")

        # A filename Windows cannot create is a course Windows teachers
        # cannot have. Git for Windows refuses to check such a path out at
        # all, so the whole repository stops fast-forwarding there — which
        # is how 57 pages across 13 payloads went unnoticed for three days
        # while the Windows clone silently stayed on an August commit.
        # The question mark belongs in the page's TITLE, where students
        # read it, and in the link's display half: a discussion page is
        # named "Who Decides.md" with title "Who Decides?" and is linked
        # as [[Who Decides|Who Decides?]].
        for forbidden in '<>:"|?*':
            if forbidden in page.name:
                problems.append(
                    f"{rel}: filename contains {forbidden!r}, which Windows "
                    f"cannot create — put it in the title and alias the links")
                break

        # Sentinels: every created: line carries one (curriculum pages
        # normally have no created: at all).
        if "created:" in text and "created: __CREATED" not in text and not is_curriculum:
            problems.append(f"{rel}: created: without a sentinel")

        # A payload cannot know how many sections the teacher will choose,
        # so per-section keys are the INSTALLER's job — it splits a shared
        # page's created/publish into createdSectionN/publishForSectionN for each
        # section. Writing them here would fix the course at one section.
        head = text.split("\n---", 1)[0] if text.startswith("---\n") else ""
        if re.search(r"^(created|draft)Section\d+:|^publishForSection\d+:", head, re.M):
            problems.append(f"{rel}: per-section keys are written by the installer, not the payload")

        # Visibility is `publish:` — a teacher says a page is published or it
        # is not. `draft:` is the older spelling with the OPPOSITE polarity,
        # so a page that keeps it does not merely look inconsistent: anyone
        # copying that page as a model inverts the flag by accident.
        if re.search(r"^draft:", head, re.M):
            problems.append(
                f"{rel}: uses draft: — visibility is publish:, and the "
                f"polarity is inverted (draft: true is publish: false)"
            )

        # A checklist on the site cannot be ticked — nothing is saved and
        # clicking does nothing. A page that says otherwise lies about the
        # software to the student reading it.
        lowered = text.lower()
        for phrase in ("click to check", "clicking checks", "check them off",
                       "tick them off", "tick these off", "checkboxes are clickable",
                       "clickable checklist", "click each box", "tick each box"):
            at = lowered.find(phrase)
            while at >= 0:
                # Ticking a printed copy is honest and worth saying, so the
                # sentence around the phrase decides.
                sentence = lowered[max(0, at - 120):at + 160]
                if not any(word in sentence for word in
                           ("paper", "notebook", "printed", "print it", "your own copy")):
                    problems.append(f"{rel}: says a checklist can be ticked — it is read-only")
                    break
                at = lowered.find(phrase, at + 1)

        # Mermaid prints each pie percentage at its slice's mid-angle with
        # no collision avoidance, and rounds to whole numbers.
        for block in re.findall(r"```mermaid\n(.*?)```", text, re.S):
            if not block.lstrip().startswith("pie"):
                continue
            values = [float(match.group(1)) for match
                      in re.finditer(r'^\s*"[^"]*"\s*:\s*([0-9.]+)\s*$', block, re.M)]
            total = sum(values)
            if total <= 0:
                continue
            shares = [value / total * 100 for value in values]
            vanishing = [share for share in shares if share < 0.5]
            crowded = [share for share in shares if share < 3]
            if vanishing:
                problems.append(f"{rel}: a pie slice rounds to 0% — combine it into a larger one")
            elif len(crowded) > 1:
                problems.append(f"{rel}: two pie slices under 3% will print their labels on top of each other")
            # A pie carries the SHAPE of an answer, never an inventory. The
            # mark page's pie is the seventy and the thirty and nothing
            # else: per-item weights are a professional judgement that
            # shifts with the class and the year, so printing them as
            # slices presents a judgement as arithmetic. Six payloads had
            # drifted to four- and five-slice weighting pies before this
            # check existed, because the rule lived only in prose.
            if page.stem == "How Marks Work" and len(values) != 2:
                problems.append(
                    f"{rel}: the mark page's pie has {len(values)} slices — it "
                    f"must be exactly two, the 70/30 split, with the tasks "
                    f"making up each part named in prose beneath it")
            elif len(values) > 4:
                bulky_pies.append((rel, len(values)))

        # The whole link graph, so reachability can be checked below.
        outside_fences = re.sub(r"```[\s\S]*?```", "", text)
        page_links[page.stem] = {
            link.group(1).strip().rstrip("\\").split("/")[-1]
            for link in link_pattern.finditer(outside_fences)
        }

        # A wikilink split by the 80-column wrap still parses, but the
        # target it builds contains a newline and so matches no page. The
        # prose reads correctly, which is exactly why this survives review;
        # the per-line scan below cannot see it at all.
        for match in re.finditer(r"!?\[\[[^\[\]]*\n[^\[\]]*\]\]", outside_fences):
            wrapped = " ".join(match.group(0).split())
            problems.append(f"{rel}: wikilink split across lines: {wrapped}")

        class_match = class_sentinel.search(text)
        if class_match:
            class_ordinals.append(int(class_match.group(1)))
            class_pages.add(page.stem)
            for link in link_pattern.finditer(text):
                linked_from_classes.add(link.group(1).strip().split("/")[-1])
            # A class page is a schedule, not a destination. Expectations
            # belong on the pages the agenda links to — the investigation,
            # the exercise set, the task — because those are what a
            # student is actually doing when the expectation is met.
            if "%%curriculum-start%%" in text:
                problems.append(
                    f"{rel}: class pages carry no curriculum connection — "
                    f"move those codes to the pages its agenda links to"
                )

        if text.count("%%curriculum-start%%") != text.count("%%curriculum-end%%"):
            problems.append(f"{rel}: unbalanced curriculum markers")

        # A link inside a `%%` comment is invisible to every reader and
        # visible to both gates: this script and build_site.py read the raw
        # markdown without stripping comments, so a hidden `![[A1.2]]`
        # counts as curriculum coverage no student page provides, and a
        # hidden `[[Page]]` satisfies the two-hop reachability check for a
        # page nothing on the site reaches. Comments hold plain text.
        for comment in comment_pattern.finditer(text):
            body = comment.group(1)
            if body.strip().startswith("curriculum-"):
                continue
            for hidden in link_pattern.finditer(body):
                problems.append(
                    f"{rel}: link inside a %% comment: "
                    f"[[{hidden.group(1).strip()}]] — it is stripped before "
                    f"anyone can follow it, but still counts for coverage "
                    f"and reachability. Write the name as plain text"
                )

        # Observation and conversation are the two evidence sources a real
        # course loses first, so every task carries a hidden prompt saying
        # where in THAT task they are available. This is a note rather than
        # a failure: no payload written before the rule existed has one.
        rel_posix = rel.replace("\\", "/")
        if "/Tasks/" in rel_posix and page.stem not in ("index", "_DUPLICATE ME"):
            if not any("triangulation" in c.group(1).lower()
                       for c in comment_pattern.finditer(text)):
                missing_triangulation.append(rel)

        in_fence = False
        for line in text.split("\n"):
            stripped = line.strip()
            if stripped.startswith("```") or stripped.startswith("````"):
                in_fence = not in_fence
                continue
            if in_fence or "`" in line:
                continue
            for match in link_pattern.finditer(line):
                target = match.group(1).strip().rstrip("\\")
                if "/" in target:
                    known = target in qualified_names
                else:
                    known = target in page_names
                if not known:
                    problems.append(f"{rel}: unknown link [[{target}]]")
            if stripped.startswith("|") and re.search(r"\[\[[^\]]*[^\\]\|[^\]]*\]\]", line):
                problems.append(f"{rel}: unescaped pipe in table: {stripped[:60]}")

    # Folder index pages must be titled after their folder — a literal
    # "title: index" shows "index" as the page name on the built site.
    for page in pages:
        if page.stem != "index" or page.parent == root:
            continue
        folder_name = page.parent.name
        if folder_name in ("shared", "per_section"):
            continue
        text = page.read_text(encoding="utf-8")
        title_match = re.search(r"^title: (.+)$", text, re.MULTILINE)
        if not title_match or title_match.group(1).strip() != folder_name:
            found = title_match.group(1).strip() if title_match else "(none)"
            problems.append(
                f"{page.relative_to(root)}: index title should be "
                f"'{folder_name}', found '{found}'"
            )

    # Expectation pages hold ONLY the verbatim expectation: frontmatter,
    # the ^text-anchored wording, nothing after — no callouts or notes.
    if curriculum_folder:
        for page in (root / "shared" / curriculum_folder).glob("*.md"):
            if page.stem in ("index", "About These Expectations", "Mathematical Process Expectations"):
                continue
            text = page.read_text(encoding="utf-8")
            if "^text" in text and text.split("^text", 1)[1].strip():
                problems.append(f"shared/{curriculum_folder}/{page.name}: content after the ^text anchor — expectation pages carry the verbatim wording only")

    # Exercises answer callouts carry no repeated "(click to expand)"
    # hint — the Exercises index opens with the how-to message instead.
    exercises_dir = root / "shared" / "Exercises"
    if exercises_dir.is_dir():
        for page in exercises_dir.glob("*.md"):
            if page.name != "index.md" and "click to expand" in page.read_text(encoding="utf-8"):
                problems.append(f"shared/Exercises/{page.name}: '(click to expand)' hint — the index teaches the pattern instead")
        index_text = (exercises_dir / "index.md").read_text(encoding="utf-8") if (exercises_dir / "index.md").exists() else ""
        if "How to use these pages" not in index_text:
            problems.append("shared/Exercises/index.md: missing the 'How to use these pages' opening message")

    # Key Links must offer the Curriculum Expectations link (inside
    # curriculum markers, so declining the curriculum removes it cleanly).
    key_links = root / "per_section" / "Key Links.md"
    if curriculum_folder and key_links.exists():
        key_links_text = key_links.read_text(encoding="utf-8")
        expected_link = f"[[{curriculum_folder}/index|Curriculum Expectations]]"
        if expected_link not in key_links_text:
            problems.append(f"per_section/Key Links.md: missing {expected_link}")
        elif "%%curriculum-start%%" not in key_links_text.split(expected_link)[0]:
            problems.append("per_section/Key Links.md: Curriculum Expectations link is not inside curriculum markers")

    # Key Links is the course's orientation panel, not an index of its
    # content. It holds the things that set the tone — how the class runs,
    # how marks work, where to get help, the learning goals, the site
    # tour, and the curriculum — and NOTHING a student reaches by
    # following the schedule. A task or a concept page listed here
    # competes with the class pages that are supposed to lead students to
    # it, and dates it the moment the unit ends.
    if key_links.exists():
        bullets = []
        for line in key_links.read_text(encoding="utf-8").splitlines():
            if line.startswith("- "):
                bullets.append(line.strip())

        # Which folder does each linked page live in?
        folder_of = {}
        for page in pages:
            relative = page.relative_to(root).as_posix()
            parts = relative.split("/")
            if len(parts) >= 3:                       # shared/<Folder>/<page>.md
                folder_of[page.stem] = parts[1]
        content_folders = {
            f for f in folder_of.values()
            if f not in {"Setup", "Style", "Tutorials", curriculum_folder}
        }
        for bullet in bullets:
            match = re.search(r"\[\[([^\]|#]+)", bullet)
            if not match:
                continue
            raw = match.group(1).strip()
            # A link written with a folder says which folder it means;
            # every folder has an index.md, so the stem alone cannot.
            if "/" in raw:
                folder = raw.split("/")[0]
                target = raw
            else:
                target = raw
                folder = folder_of.get(target)
            if folder in content_folders:
                problems.append(
                    f"per_section/Key Links.md: links to {target} in {folder}/ — "
                    f"Key Links is for course-level orientation only, never "
                    f"tasks, lessons, or content pages"
                )

        tour = "- [[What This Site Can Do]]"
        hunt = "- [[Scavenger Hunt]]"
        if tour not in bullets:
            problems.append(f"per_section/Key Links.md: missing {tour}")
        if hunt not in bullets:
            problems.append(f"per_section/Key Links.md: missing {hunt}")

        # The curriculum links close the list: the expectations, then the
        # coverage map that the build inserts directly beneath them, followed
        # by the Scavenger Hunt orientation link.
        if curriculum_folder:
            expected_link = f"- [[{curriculum_folder}/index|Curriculum Expectations]]"
            if expected_link in bullets:
                if bullets[-1] != hunt:
                    problems.append(
                        "per_section/Key Links.md: Scavenger Hunt must be the LAST entry"
                    )
                if len(bullets) >= 2 and bullets[-2] != expected_link:
                    problems.append(
                        "per_section/Key Links.md: Curriculum Expectations must come "
                        "immediately before Scavenger Hunt"
                    )
                if len(bullets) >= 3 and bullets[-3] != tour:
                    problems.append(
                        "per_section/Key Links.md: What This Site Can Do must come "
                        "immediately before the curriculum links"
                    )
        elif bullets:
            if bullets[-1] != hunt:
                problems.append(
                    "per_section/Key Links.md: Scavenger Hunt must be the LAST entry"
                )
            if len(bullets) >= 2 and bullets[-2] != tour:
                problems.append(
                    "per_section/Key Links.md: What This Site Can Do must come "
                    "immediately before Scavenger Hunt"
                )

    # The section landing page's "Most Recent Class" must transclude the
    # newest PUBLISHED class page — the point of that heading.
    landing = root / "per_section" / "index.md"
    if landing.exists() and class_ordinals:
        newest_published = None
        for page in (root / "per_section").rglob("*.md"):
            text = page.read_text(encoding="utf-8")
            match = class_sentinel.search(text)
            if match and "publish: false" not in text:
                ordinal = int(match.group(1))
                if newest_published is None or ordinal > newest_published[0]:
                    newest_published = (ordinal, page.stem)
        if newest_published and f"![[{newest_published[1]}]]" not in landing.read_text(encoding="utf-8"):
            problems.append(
                f"per_section/index.md: Most Recent Class should transclude "
                f"the newest published class, ![[{newest_published[1]}]]"
            )

    # Class ordinals: consecutive from 1, no gaps or repeats.
    class_ordinals.sort()
    if class_ordinals != list(range(1, len(class_ordinals) + 1)):
        problems.append(f"class ordinals are not 1..N without gaps: {class_ordinals}")

    # Manifest completeness: every named folder/file exists in the payload
    # and every payload folder is named — the manifest is the WHOLE
    # structure, so nothing may be missing and nothing may ship empty.
    for folder in manifest.get("shared_folders", []):
        folder_path = root / "shared" / folder
        if not folder_path.is_dir() or not list(folder_path.glob("*.md")):
            problems.append(f"manifest folder empty or missing: shared/{folder}")
    for name in manifest.get("shared_files", []):
        if not (root / "shared" / name).exists():
            problems.append(f"manifest shared file missing: {name}")
    for folder in manifest.get("per_section_folders", []):
        folder_path = root / "per_section" / folder
        if not folder_path.is_dir() or not list(folder_path.glob("*.md")):
            problems.append(f"manifest folder empty or missing: per_section/{folder}")

    # Teaching-order dates only work when content pages are linked from
    # class pages. Warn (not fail) for shared pages never linked by any
    # class — they will carry the Unit 1, Day 1 date.
    unlinked = []
    for page in pages:
        rel = str(page.relative_to(root))
        if not rel.startswith("shared/") or page.stem == "index":
            continue
        if page.stem == "_DUPLICATE ME":
            continue
        if curriculum_folder and rel.startswith(f"shared/{curriculum_folder}/"):
            continue
        if page.stem not in linked_from_classes:
            unlinked.append(rel)

    # Outside Key Links, no page stands on its own: every page must be
    # reachable from a class page directly, or through one page a class
    # page links to. Key Links is the sidebar's index of last resort, so
    # a page reachable only through it is still an orphan.
    first_hop = set()
    for stem in class_pages:
        first_hop |= page_links.get(stem, set())
    second_hop = set()
    for stem in first_hop:
        second_hop |= page_links.get(stem, set())
    reachable = class_pages | first_hop | second_hop
    exempt = {"index", "Key Links", "Private Notes", "Scratch Page", "_DUPLICATE ME", "Scavenger Hunt"}
    for page in pages:
        rel = str(page.relative_to(root))
        if page.stem in exempt or page.stem in reachable:
            continue
        if curriculum_folder and rel.startswith(f"shared/{curriculum_folder}/"):
            continue
        problems.append(
            f"{rel}: nothing reaches this page — link it from a class page, "
            f"or from a page a class page links to (Key Links does not count)"
        )

    # ---- Curriculum coverage, and the hours the arc actually accounts for.
    #
    # The built site draws a Curriculum Coverage heat map from exactly these
    # numbers, so a payload can be checked here without building anything.
    # A red cell on a shipped example course teaches the wrong lesson: it
    # says a course may leave an expectation untaught.
    if curriculum_folder:
        curriculum_dir = root / "shared" / curriculum_folder
        specific = set()
        overall = set()
        for page in curriculum_dir.glob("*.md"):
            if re.fullmatch(r"[A-Z]\d+\.\d+", page.stem):
                specific.add(page.stem)
            elif re.match(r"^[A-Z]\d+\.\s", page.stem):
                overall.add(page.stem.split(".")[0])

        addressed_by = {code: set() for code in specific}
        assessed_by = {code: set() for code in specific}
        for page in pages:
            rel = str(page.relative_to(root))
            if curriculum_folder and rel.startswith(f"shared/{curriculum_folder}/"):
                continue
            text = page.read_text(encoding="utf-8")
            if "publish: false" in text:
                continue          # not on the site, so it addresses nothing
            is_assessed = "/Tasks/" in rel.replace("\\", "/")
            # The same pattern build_site.py counts with, block anchor and
            # all: SNC1W transcludes as `![[A1.2#^text]]`, which the site
            # counts and an anchor-blind regex here would silently miss.
            for match in re.finditer(r"!\[\[([^\]|#]+?)(?:\\?\|[^\]]*)?(?:#[^\]|]*)?\]\]", text):
                code = match.group(1).strip().split("/")[-1]
                if code in addressed_by:
                    addressed_by[code].add(rel)
                    if is_assessed:
                        assessed_by[code].add(rel)

        uncovered = sorted(code for code in specific if not addressed_by[code])
        thin = sorted(code for code in specific if len(addressed_by[code]) == 1)
        if uncovered:
            problems.append(
                f"{len(uncovered)} expectation(s) addressed by NO published page — "
                f"every specific expectation must be transcluded at least once: "
                f"{' '.join(uncovered)}"
            )
        for overall_code in sorted(overall):
            related = [code for code in specific if code.startswith(overall_code + ".")]
            if related and not any(assessed_by[code] for code in related):
                problems.append(
                    f"overall expectation {overall_code} is never reached by assessed work — "
                    f"a page in Tasks must transclude one of its specific expectations"
                )

    # ---- Hours: an Ontario credit is 110 hours of scheduled time (half credit is 55).
    # In British Columbia, a standard senior secondary course is 4 credits (110–120 hours).
    #
    # One class page is one period. The final evaluation is not a class
    # page, so its hours are added separately; several review periods
    # belong inside the arc, before it. Both the credit value and the
    # length of the final evaluation are declared in the manifest, so a
    # half credit is a stated property of the payload rather than a
    # tolerance stretched until it fits.
    jurisdiction = manifest.get("jurisdiction", "ON").upper()
    credit_value = float(manifest.get("credit_value", 4.0 if jurisdiction == "BC" else 1.0))
    final_hours = float(manifest.get("final_evaluation_hours",
                                     DEFAULT_FINAL_EVALUATION_HOURS))
    credit_multiplier = (credit_value / 4.0) if jurisdiction == "BC" else credit_value
    credit_hours = FULL_CREDIT_HOURS * credit_multiplier
    tolerance = HOURS_TOLERANCE * credit_multiplier
    review_needed = max(2, round(MINIMUM_REVIEW_CLASSES * credit_multiplier))
    if class_ordinals:
        hours = len(class_ordinals) * PERIOD_MINUTES / 60 + final_hours
        if not credit_hours - tolerance <= hours <= credit_hours + tolerance:
            problems.append(
                f"the arc accounts for {hours:.1f} hours "
                f"({len(class_ordinals)} periods x {PERIOD_MINUTES} min + "
                f"{final_hours:g} h final evaluation) — this payload declares "
                f"{credit_value:g} credit, which is {credit_hours:g} hours, so the arc "
                f"needs about "
                f"{round((credit_hours - final_hours) * 60 / PERIOD_MINUTES)} class pages"
            )
        review = [page for page in pages if "\n  - review\n" in page.read_text(encoding="utf-8")]
        if len(review) < review_needed:
            problems.append(
                f"{len(review)} review class(es) — a course ends with at least "
                f"{review_needed}, tagged `review`, before the final evaluation"
            )
        final = [page for page in pages
                 if "\n  - final-evaluation\n" in page.read_text(encoding="utf-8")]
        if not final:
            problems.append(
                "no final evaluation — the last thing in the course is a page in Tasks "
                "tagged `final-evaluation`, carrying the exam or culminating task"
            )

    print(f"{len(pages)} pages checked; {len(class_ordinals)} class pages")
    if curriculum_folder and specific:
        covered = len(specific) - len(uncovered)
        print(f"coverage: {covered}/{len(specific)} expectations addressed; "
              f"{len(thin)} addressed exactly once")
        if thin:
            print(f"note     addressed only once (aim for two or more): {' '.join(thin)}")
    for problem in problems:
        print(f"PROBLEM  {problem}")
    for rel in unlinked:
        print(f"note     no class links {rel} (it will carry the Unit 1, Day 1 date)")
    for rel in missing_triangulation:
        print(f"note     no triangulation prompt {rel} (a hidden %% block "
              f"naming where to observe and what to ask)")
    for rel, count in bulky_pies:
        print(f"note     {rel} has a {count}-slice pie — past about four a pie "
              f"is an inventory rather than a shape; fine for a real "
              f"composition, wrong for a weighting")
    print("clean" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(lint(sys.argv[1]))

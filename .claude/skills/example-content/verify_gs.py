"""Mechanical conformance checks the linter cannot make."""
import re, sys, pathlib, subprocess

def check(code):
    root = pathlib.Path("support/example_content")/code
    cls = root/"per_section/All Classes"
    # A missing payload must FAIL, not report "pass" on an empty set — a
    # silent green here is the exact failure this script exists to catch.
    if not cls.is_dir() or not (root/"shared/Tasks").is_dir():
        print(f"=== {code}: PAYLOAD NOT FOUND at {root.resolve()} — wrong cwd?")
        return 1
    days = {p.stem for p in cls.glob("Unit *.md")}
    tasks = [p for p in (root/"shared/Tasks").glob("*.md")
             if p.stem not in ("index", "_DUPLICATE ME")]
    comment = re.compile(r"%%(.*?)%%", re.S)
    link = re.compile(r"!?\[\[")
    problems, notes = [], []

    # every task has a triangulation block
    for t in tasks:
        txt = t.read_text(encoding="utf-8")
        blocks = [c.group(1) for c in comment.finditer(txt)
                  if not c.group(1).strip().startswith("curriculum-")]
        if not any("triangulation" in b.lower() for b in blocks):
            problems.append(f"{t.name}: no triangulation block")

    # hidden links + day references that name a class page which does not exist
    for p in root.rglob("*.md"):
        txt = p.read_text(encoding="utf-8")
        for c in comment.finditer(txt):
            body = c.group(1)
            if body.strip().startswith("curriculum-"):
                continue
            if link.search(body):
                problems.append(f"{p.name}: link inside a %% comment")
            for m in re.finditer(r"Unit (\d+),?\s+Day (\d+)", body):
                ref = f"Unit {m.group(1)}, Day {m.group(2)}"
                if ref not in days:
                    problems.append(f"{p.name}: block names {ref!r}, which is not a class page")

    # Simulate what the site actually publishes: Quartz strips %%...%% with a
    # NON-GREEDY regex, so a stray %% inside a block closes it early and spills
    # the rest onto the page. Rather than guess at pairing, strip the way the
    # build does and then look for teacher-only text that survived.
    # Match only shapes unique to a triangulation block. Bare "Triangulation"
    # is a real maths/geography word — MPM2D uses it for GPS and surveying in
    # student prose — and a check that cries wolf stops being read.
    LEAK = ("the evidence you will not have unless",
            "\nOBSERVE — ", "\nTALK — ", "\n  Going well:", "\n  Stuck:",
            "The product evidence is")
    for p2 in root.rglob("*.md"):
        txt = p2.read_text(encoding="utf-8")
        if "publish: false" in txt.split("---")[1] if txt.startswith("---") and len(txt.split("---")) > 2 else False:
            continue
        stripped = re.sub(r"%%.*?%%", "", txt, flags=re.S)
        for phrase in LEAK:
            if phrase in stripped:
                problems.append(f"{p2.name}: {phrase!r} SURVIVES comment-stripping — teacher text would publish")
                break

    # class ordinals contiguous
    ords = sorted(int(m.group(1)) for p in cls.glob("Unit *.md")
                  if (m := re.search(r"__CREATED_CLASS_(\d+)__", p.read_text(encoding="utf-8"))))
    if ords != list(range(1, len(ords)+1)):
        problems.append(f"class ordinals not 1..N: {ords[:5]}…")

    # agenda numbering
    for p in cls.glob("*.md"):
        m = re.search(r"## Agenda\n(.*?)(\n## |\Z)", p.read_text(encoding="utf-8"), re.S)
        if not m: continue
        n = [int(x) for x in re.findall(r"^(\d+)\.", m.group(1), re.M)]
        if n != list(range(1, len(n)+1)):
            problems.append(f"{p.stem}: agenda numbering {n}")

    lint = subprocess.run([sys.executable, ".claude/skills/example-content/lint_payload.py", code],
                          capture_output=True, text=True).stdout.strip().split("\n")
    print(f"=== {code}: {len(tasks)} tasks, {len(days)} class pages")
    print("    lint:", lint[-1], "|", [l for l in lint if l.startswith("coverage")][:1])
    for x in problems: print("    PROBLEM", x)
    if not problems: print("    mechanical checks: pass")
    return len(problems)

sys.exit(sum(check(c) for c in sys.argv[1:]))

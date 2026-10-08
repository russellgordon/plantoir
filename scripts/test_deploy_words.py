#!/usr/bin/env python3
"""DEPLOY puts a site online; PUBLISH only marks a page (#443, v1.4.4).

Russell's rule of 2026-10-03: every sentence a teacher reads uses each word
only in its own sense. v1.4.4 moved every sentence that said "publish" for a
deploy. This guard keeps them moved: it scans the TEXT the mac app, the
launchers, the shared Python and (since #441) the Windows app show, for
phrases that can only mean a deploy and say "publish".

EXACT ON PURPOSE, and so narrow. Each phrase below is one that was found
saying publish for a deploy and was changed; none of them can mean marking a
page. A guard on the bare word would be wrong in both directions — "Publish
Unit 2, Day 3" is the assistant's own shelf, and "publish them and deploy" is
the right sentence — so it would either fail on correct text or be loosened
until it catches nothing.

WHAT IT CANNOT SEE, said so nobody relies on it for more:
  - a NEW sentence that says publish for a deploy in words not listed here;
  - text built from pieces across lines (a phrase split over `+ "...` joins
    is only caught when the phrase sits on one line, which is how every
    phrase below is written today);
  - the Windows app's tests (Plantoir.Tests, Plantoir.UiTests), which type
    fixtures rather than show text, and anything under bin/ or obj/ (build
    output, including copies of deploy.ps1);
  - the website and course content (other bundles);
  - code comments (C# `//` and `///` lines, XAML `<!-- -->`, PowerShell and
    shell `#` lines) and the activity trail's event KEYS on both apps, which
    are not text a teacher reads (the keys are frozen: activityTrail.note).
    Known edges of that reading, none of which bites today: PowerShell `<# #>`
    and C# `/* */` block comments ARE read (a false failure at worst, never a
    miss); C# strings that span lines (verbatim and raw literals) are NOT read; and a
    `// "quoted"` remark after code on the same line is read as a string.

Runs everywhere `scripts/test_*.py` runs: verify.sh, and Windows'
PythonToolchainTests. It reads BOTH apps' sources on both machines — every
clone carries mac-app/ and windows-app/ — so since #441 (Windows v1.4.4) a
mac session's verify.sh fails on a Windows sentence that says publish for a
deploy, and Windows' suite on a mac one. That coupling is the point: the
words rule is one product's, and documentation/07-deployment.md says so.
"""
import os
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Each meant a deploy and said publish until v1.4.4.
DEPLOY_PHRASES_THAT_SAID_PUBLISH = [
    "set to publish on its own",
    "set to publish on their own",
    "scheduled publish",
    "Scheduled publishing",
    "published on its own",
    "Nothing was published.",
    "nothing to publish",
    "Nothing to publish",
    "publishing folder",
    "publishing destination",
    "Publish this section once",
    "publishes to:",
    "a publish or preview",
    "Also publish to",
    "Deploying publishes",
    "Publish the curriculum coverage map",
    "previewed or published",
    "is being published",
    "is publishing this course",
    "still publishing",
    "First-time publishing",
    "Future publishes",
    "When publishing online",
    "the publishing is coming",
    "your publishing working",
    "allowed to publish",
    "cannot publish anything",
    "no website to publish",
    "Publishing is what puts",
    "Publish each section",
    "try to publish",
    "publishing it will still",
    "until you publish.",
    "before you publish.",
    "can publish these pages",
    "can publish it.",
    # Added with the Windows scan (#441): deploy.ps1's and the Windows app's
    # own lines that had no mac twin to be caught by.
    "rebuild this site for publishing",
    "Next publish will ask",
    "Unknown publishing target",
    "whichever service you publish to",
    "publish set to happen on its own",
    "publish was set to happen on its own",
    "missing publishing token",
    "Keep publishing this section",
    "next publish makes",
    "pages as published to",
]

# Where a string literal is a line on the activity trail's event KEY, frozen.
EVENT_KEY = re.compile(r'^\s*case \w+ = "')
# The same on Windows: ActivityTrail.cs maps each Event to its key.
CSHARP_EVENT_KEY = re.compile(r'^\s*Event\.\w+ => "')

# The Windows app's product sources: the three projects a teacher's copy is
# built from. Listed rather than walked from windows-app/, which also holds
# build output (Vendor/runtime, dist/).
WINDOWS_PROJECTS = ("Plantoir", "Plantoir.Core", "Plantoir.Mcp")


def swift_literals(path: pathlib.Path):
    """(line number, text) for each line of Swift that is not a comment, with
    only what is inside string literals kept."""
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if path.name == "ActivityTrail.swift" and EVENT_KEY.match(line):
            continue
        literals = re.findall(r'"((?:[^"\\]|\\.)*)"', line)
        if literals:
            yield number, " ".join(literals)


def csharp_literals(path: pathlib.Path):
    """(line number, text) for each line of C# that is not a comment, with
    only what is inside string literals kept."""
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.strip().startswith("//"):
            continue
        if path.name == "ActivityTrail.cs" and CSHARP_EVENT_KEY.match(line):
            continue
        literals = re.findall(r'"((?:[^"\\]|\\.)*)"', line)
        if literals:
            yield number, " ".join(literals)


def xaml_text(path: pathlib.Path):
    """A XAML file's lines with every <!-- --> comment blanked out (they run
    across lines), so a comment is never read as text a teacher sees."""
    text = re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"),
                  path.read_text(encoding="utf-8"), flags=re.DOTALL)
    for number, line in enumerate(text.splitlines(), start=1):
        yield number, line


def windows_sources():
    """Every .cs and .xaml file in the Windows app's product projects, with
    bin/ and obj/ pruned before they are walked (on a machine that has built
    the app they hold about 150,000 files)."""
    found = []
    for project in WINDOWS_PROJECTS:
        for folder, folders, files in os.walk(ROOT / "windows-app" / project):
            folders[:] = sorted(d for d in folders if d not in ("bin", "obj"))
            for name in sorted(files):
                if name.endswith((".cs", ".xaml")):
                    found.append(pathlib.Path(folder) / name)
    return found


def python_literals(path: pathlib.Path):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.strip().startswith("#"):
            continue
        literals = re.findall(r'"((?:[^"\\]|\\.)*)"', line) + re.findall(r"'((?:[^'\\]|\\.)*)'", line)
        if literals:
            yield number, " ".join(literals)


def shell_text(path: pathlib.Path):
    """A launcher's lines that are not comments: echoes, prompts, heredocs."""
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.strip().startswith("#"):
            continue
        yield number, line


def offending(lines, where: str):
    found = []
    for number, text in lines:
        for phrase in DEPLOY_PHRASES_THAT_SAID_PUBLISH:
            if phrase in text:
                found.append("%s:%d says %r" % (where, number, phrase))
    return found


class TeacherTextSaysDeployForADeploy(unittest.TestCase):

    def test_the_mac_app_says_deploy(self):
        found = []
        for path in sorted((ROOT / "mac-app" / "QuartzTeachers").rglob("*.swift")):
            found += offending(swift_literals(path), str(path.relative_to(ROOT)))
        self.assertEqual(found, [], "a sentence says publish for a deploy (#443)")

    def test_the_windows_app_says_deploy(self):
        sources = windows_sources()
        # A walk that found nothing would pass forever.
        self.assertTrue(any(p.suffix == ".cs" for p in sources), "no C# found under windows-app/")
        self.assertTrue(any(p.suffix == ".xaml" for p in sources), "no XAML found under windows-app/")
        found = []
        for path in sources:
            lines = csharp_literals(path) if path.suffix == ".cs" else xaml_text(path)
            found += offending(lines, path.relative_to(ROOT).as_posix())
        self.assertEqual(found, [], "a Windows sentence says publish for a deploy (#441)")

    def test_the_launchers_say_deploy(self):
        found = []
        for name in ("deploy.sh", "preview.sh", "setup.sh", "deploy.ps1", "preview.ps1", "setup.ps1"):
            found += offending(shell_text(ROOT / name), name)
        self.assertEqual(found, [], "a launcher line says publish for a deploy (#443)")

    def test_the_shared_python_says_deploy(self):
        found = []
        for path in sorted((ROOT / "scripts").glob("*.py")):
            if path.name.startswith("test_"):
                continue
            found += offending(python_literals(path), str(path.relative_to(ROOT)))
        self.assertEqual(found, [], "a script's message says publish for a deploy (#443)")

    def test_the_guard_can_see_what_it_guards(self):
        """A guard that matches nothing passes forever. Each kind of source is
        read through the same function the tests use, on a line written the
        old way."""
        self.assertTrue(offending([(1, 'echo " Nothing was published."')], "x"))
        self.assertTrue(offending([(1, "Also publish to, for redundancy")], "x"))
        self.assertFalse(offending([(1, "Publish Unit 2, Day 3")], "x"))
        self.assertFalse(offending([(1, "until you publish them and deploy.")], "x"))

    def test_the_windows_readers_see_text_and_skip_comments(self):
        """The C# and XAML readers, on files written the old way: a literal is
        caught, a comment and a frozen event key are not."""
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            cs = pathlib.Path(folder) / "ActivityTrail.cs"
            cs.write_text('\n'.join([
                '    // the scheduled publish notification, in a comment',
                '        Event.ScheduledPublishNotification => "scheduled publish notification",',
                '        ? "Your scheduled publish went out"',
            ]), encoding="utf-8")
            hits = offending(csharp_literals(cs), "x")
            self.assertEqual(len(hits), 1, hits)
            self.assertTrue(hits[0].startswith("x:3 "), hits)

            xaml = pathlib.Path(folder) / "View.xaml"
            xaml.write_text('\n'.join([
                '<!-- How last night\'s scheduled publish',
                '     turned out -->',
                '<TextBlock Text="First-time publishing" />',
            ]), encoding="utf-8")
            hits = offending(xaml_text(xaml), "x")
            self.assertEqual(len(hits), 1, hits)
            self.assertTrue(hits[0].startswith("x:3 "), hits)


if __name__ == "__main__":
    unittest.main()

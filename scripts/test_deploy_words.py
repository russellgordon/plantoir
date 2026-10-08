#!/usr/bin/env python3
"""DEPLOY puts a site online; PUBLISH only marks a page (#443, v1.4.4).

Russell's rule of 2026-10-03: every sentence a teacher reads uses each word
only in its own sense. v1.4.4 moved every sentence that said "publish" for a
deploy. This guard keeps them moved: it scans the TEXT the mac app, the
launchers and the shared Python show, for phrases that can only mean a deploy
and say "publish".

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
  - Windows (windows-app/, deploy.ps1, preview.ps1): their half is #441, and
    scanning it here would make Windows' own suite red on text it has not
    moved yet;
  - the website and course content (other bundles);
  - code comments and the activity trail's event KEYS, which are not text a
    teacher reads (the keys are frozen: activityTrail.note).

Runs everywhere `scripts/test_*.py` runs: verify.sh, and Windows'
PythonToolchainTests, where it reads only these mac and launcher files.
"""
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
]

# Where a string literal is a line on the activity trail's event KEY, frozen.
EVENT_KEY = re.compile(r'^\s*case \w+ = "')


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

    def test_the_launchers_say_deploy(self):
        found = []
        for name in ("deploy.sh", "preview.sh", "setup.sh"):
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


if __name__ == "__main__":
    unittest.main()

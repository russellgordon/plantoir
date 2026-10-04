#!/usr/bin/env python3
"""
The launchers never name the machinery to a teacher (CLAUDE.md rule 1,
GitHub #382). Everything setup.sh, preview.sh and deploy.sh print reaches the
app's console, where a teacher reads it — so a line that says "container",
"Docker" or "image" there is a line about the plumbing, and "website builder"
is the product's word for all of it.

This is the WHOLE-FILE scan that #228 and #263 left for later: they pinned the
first-run block (AppRulesContractTests.testTheFirstRunLinesNameNoMachinery),
and this reads every other line.

**What counts as teacher-facing** — the rule, stated once:

  - every `echo` and `printf`, wherever it sits on its line (after `then`,
    `else`, `do`, `;`, `&&`, `||` or a `case` arm's `pattern)` as well as at
    the start), and every `read -p` prompt;
  - every line of a `cat <<'MSG'` message (the Netlify and Cloudflare
    instructions);
  - the text a teacher sees, not the code that makes it: `$( … )`,
    `${ … }` and `$NAME` are removed first, so `${CONTAINER_NAME}` or
    `$(_colima_cpus)` is not the word.

**What is not**, and why each is safe to leave out:

  - comments, and anything that is not one of the above (commands, `docker`
    calls, awk programs) — a teacher never reads them;
  - `--help` text (`cat <<EOF` in setup.sh, `cat <<USAGE` in deploy.sh), which
    the app never asks for, and whose flags (`--context`, `--image`) are
    about the machinery on purpose;
  - `echo "PLANTOIR_…` lines: machine-readable lines the app reads and keeps
    out of the console, whose fields name the programs on purpose (#312);
  - a line that ends `# never shown to a teacher: <why>`. That is the one
    way a PRINTING line keeps a word, it must say why, and it is meant for
    lines the app cannot show: a function's answer captured by `$( … )` (the
    helper-path `case` arms among them), text piped into a command, and the
    lines reached only with `--image` or `--context`, which the app never
    passes. 38 lines carry it today (2026-09-30). Everything else a launcher
    holds keeps its words because it is not printed at all (the list above);
    what this scan still cannot see is text printed some other way — `cat`
    of a file, a `python3 -` heredoc's own print, a command's own output —
    which is why those are not where teacher text is written. It is NOT for a line a teacher can read: rewording those was the
    point of #382. REJECTED: an allow-list kept here, which freezes the list
    rather than emptying it, and which a reader of the launcher never sees.

Pure stdlib, runs on Windows too (it only reads the files). Run with:

    python3 scripts/test_launcher_words.py
"""

import re
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
LAUNCHERS = ("setup.sh", "preview.sh", "deploy.sh")

# The same list as the first-run test on the mac, less "script", plus
# "live-reload" (#407): deploy.sh used to tell a teacher a preview "bakes in a
# live-reload script", and now says it "adds live updating", the words
# deploy.ps1 took first (#296). "script" alone stays allowed: it is the web's
# word, and a line a teacher reads may still need it.
FORBIDDEN_WORDS = (
    "live-reload",
    "toolchain", "toolchains",
    "docker", "container", "containers",
    "colima", "lima", "buildx", "buildkit",
    "virtual machine", "disk image", "image", "images",
    # Russell, v1.4.1: "workspace" meant nothing to him; the launchers say
    # "website builder" (#378, #382).
    "workspace", "workspaces",
)

EXEMPTION = "# never shown to a teacher:"

# `cat <<WORD` bodies a teacher reads, and those that are --help text.
SHOWN_HEREDOCS = ("MSG",)
HELP_HEREDOCS = ("EOF", "USAGE")

PRINTING = re.compile(r"(?:^\s*|[;&|]\s*|\)\s*|\bthen\s+|\belse\s+|\bdo\s+)(echo|printf)\b(.*)$")
READ_PROMPT = re.compile(r"\bread\b[^\"']*-[a-z]*p\s*(\"[^\"]*\"|'[^']*')")
HEREDOC_START = re.compile(r"\bcat\b[^<]*<<-?\s*['\"]?([A-Za-z_]+)['\"]?")


def without_substitutions(text):
    """The text as printed, less what the shell puts in: `$( … )` (nested
    ones too), `${ … }` and `$NAME`."""
    previous = None
    while previous != text:
        previous = text
        text = re.sub(r"\$\([^()]*\)", "", text)
    text = re.sub(r"\$\{[^}]*\}", "", text)
    text = re.sub(r"\$[A-Za-z_][A-Za-z0-9_]*", "", text)
    return text


def teacher_lines(text):
    """(line number, the text a teacher reads) for every teacher-facing line,
    and (line number, why) for every exemption."""
    shown = []
    exemptions = []
    inside = None
    for number, line in enumerate(text.split("\n"), start=1):
        if inside is not None:
            if line.strip() == inside:
                inside = None
            elif inside in SHOWN_HEREDOCS:
                shown.append((number, line))
            continue
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        heredoc = HEREDOC_START.search(line)
        if heredoc and heredoc.group(1) in SHOWN_HEREDOCS + HELP_HEREDOCS:
            inside = heredoc.group(1)
            continue
        if EXEMPTION in line:
            why = line.split(EXEMPTION, 1)[1].strip()
            exemptions.append((number, why))
            continue
        printed = PRINTING.search(line)
        if printed:
            said = printed.group(2).strip()
            if said.startswith('"PLANTOIR_'):
                continue
            shown.append((number, without_substitutions(said)))
        prompt = READ_PROMPT.search(line)
        if prompt:
            shown.append((number, without_substitutions(prompt.group(1))))
    return shown, exemptions


def machinery_in(line):
    found = []
    for word in FORBIDDEN_WORDS:
        if re.search(r"\b" + re.escape(word) + r"\b", line, re.IGNORECASE):
            found.append(word)
    return found


def printed_lines(text):
    """Just the text of every teacher-facing line, less its substitutions."""
    shown, _ = teacher_lines(text)
    return [line for _, line in shown]


# Which launchers each of the app's progress bars reads. A publish that builds
# first runs preview.sh and then deploy.sh under one bar.
LAUNCHERS_BEHIND_EACH_BAR = {
    "courseCreation": ("setup.sh",),
    "exampleCourse": ("setup.sh",),
    "preview": ("preview.sh",),
    "deploy": ("deploy.sh",),
    "deployToCloudflare": ("deploy.sh",),
    "deployToFolder": ("deploy.sh",),
    "buildAndDeploy": ("preview.sh", "deploy.sh"),
    "buildAndDeployToCloudflare": ("preview.sh", "deploy.sh"),
    "buildAndDeployToFolder": ("preview.sh", "deploy.sh"),
}


class EveryLauncherMarkerIsPrintedWhereItIsWatched(unittest.TestCase):
    """A marker a bar watches for must be PRINTED by a launcher that bar
    reads — on a line a teacher sees, not in a comment. The mac's
    AppRulesContractTests asks only whether ANY launcher prints it, which is
    how the example course came to watch setup.sh for "Starting container if
    needed", a line only preview.sh ever printed: step 3 of that bar could
    never be reached (found and fixed with #382). Read from the contract's
    generated `milestones`, so a renamed marker is checked where it is used."""

    def test_each_bar_can_reach_its_launcher_steps(self):
        import json
        rules = json.loads((REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8"))
        origins = rules["markerOrigins"]["origins"]
        printed = {}
        for launcher in LAUNCHERS:
            printed[launcher] = printed_lines((REPOSITORY_ROOT / launcher).read_text(encoding="utf-8"))
        bars = [name for name in rules["milestones"] if name != "note"]
        self.assertEqual(sorted(bars), sorted(LAUNCHERS_BEHIND_EACH_BAR),
                         "a bar was added or renamed: say which launchers it reads")
        for bar in bars:
            for step in rules["milestones"][bar]:
                marker = step["marker"]
                if origins.get(marker) != "launcher":
                    continue
                with self.subTest(bar=bar, marker=marker):
                    found = False
                    for launcher in LAUNCHERS_BEHIND_EACH_BAR[bar]:
                        for line in printed[launcher]:
                            if marker in line:
                                found = True
                    self.assertTrue(found, f"the {bar} bar watches for {marker!r}, and "
                                           f"no echo in {' or '.join(LAUNCHERS_BEHIND_EACH_BAR[bar])} prints it")


class TheLaunchersNameNoMachinery(unittest.TestCase):

    def test_no_line_a_teacher_reads_names_the_machinery(self):
        for launcher in LAUNCHERS:
            text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            shown, _ = teacher_lines(text)
            for number, line in shown:
                with self.subTest(launcher=launcher, line=number):
                    self.assertEqual(
                        machinery_in(line), [],
                        f"{launcher}:{number} names the machinery to a teacher: {line!r}. "
                        "Say 'website builder' instead (CLAUDE.md rule 1, #382).")

    def test_every_exemption_says_why(self):
        for launcher in LAUNCHERS:
            text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            _, exemptions = teacher_lines(text)
            for number, why in exemptions:
                with self.subTest(launcher=launcher, line=number):
                    self.assertGreaterEqual(len(why.split()), 3,
                                            f"{launcher}:{number} is exempted without saying why")

    def test_the_scan_is_reading_something(self):
        """A reader that lost its way would pass everything."""
        for launcher in LAUNCHERS:
            text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            shown, _ = teacher_lines(text)
            self.assertGreater(len(shown), 100, f"only {len(shown)} lines read in {launcher}")
            joined = "\n".join(line for _, line in shown)
            self.assertIn("website builder", joined)
        deploy = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        shown, _ = teacher_lines(deploy)
        self.assertIn("Connect to Netlify.", [line for _, line in shown],
                      "the MSG heredocs a teacher reads are no longer being read")

    def test_the_reader_finds_what_it_must(self):
        """The rule, on lines made up to test it."""
        sample = "\n".join([
            'echo "🚀 Starting container if needed..."',
            'if true; then echo "Docker context: $X"; fi',
            'foo || echo "no image"',
            '  *) echo "a container in a case arm" ;;',
            'read -rp "Paste the container id: " answer',
            'echo "✅ ${CONTAINER_NAME} $(_colima_cpus) $IMAGE_ID"',
            '# echo "a container in a comment"',
            'echo "PLANTOIR_HELPERS_INSTALLED: colima=1"',
            'echo "./.toolchain"  # never shown to a teacher: captured by the caller',
            "cat <<'MSG'",
            "The container is in a message.",
            "MSG",
            "cat <<EOF",
            "  --context NAME  Use a specific Docker context.",
            "EOF",
        ])
        shown, exemptions = teacher_lines(sample)
        flagged = [number for number, line in shown if machinery_in(line)]
        self.assertEqual(flagged, [1, 2, 3, 4, 5, 11])
        self.assertEqual([number for number, _ in exemptions], [9])


if __name__ == "__main__":
    unittest.main(verbosity=1)

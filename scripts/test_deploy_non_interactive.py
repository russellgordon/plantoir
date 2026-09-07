#!/usr/bin/env python3
"""
`--non-interactive`: a publish that nobody is there to answer questions for.

Found on Windows 2026-09-06 by `verify-deploy.ps1`, whose Netlify leg hung
until its own 900-second timeout: the site saved in `.netlify_sites/` no
longer existed on Netlify, so the deploy fell through to creating a fresh
one and asked what to call it. A person answers that in two seconds; a
scheduled publish has nobody. Both branches of the old behaviour were seen
for real, and both are bad:

* **With a terminal on standard input**, `input()` waits forever — two
  measured runs sat at one prompt for 45 minutes. The teacher's site is
  simply not updated in the morning, with nothing to say why.
* **Without one**, `sys.stdin.isatty()` is false and the DEFAULT is taken
  silently, so the website is published at an address nobody chose.

So the rule this pins is: with the flag set, a question becomes a REFUSAL
that names the question, and nothing takes a default it was not given.

Pure stdlib, no Docker and no network. Run with:

    python3 scripts/test_deploy_non_interactive.py

verify.sh runs this early, before the (slow) Docker build.
"""

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

import deploy


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent


class NonInteractiveRefusesEveryQuestion(unittest.TestCase):
    """Every question `deploy.py` can ask, with the flag set."""

    def setUp(self):
        self.previous = deploy.NON_INTERACTIVE
        deploy.NON_INTERACTIVE = True

    def tearDown(self):
        deploy.NON_INTERACTIVE = self.previous

    def test_a_prompt_refuses_rather_than_taking_its_default(self):
        """The backstop, and the failure it replaces.

        This is the one that used to publish to an address nobody chose:
        `prompt()` returned `default or ""` whenever standard input was not
        a terminal, so the site was created at the suggested address with
        no sign that a question had been skipped.
        """
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as stopped:
                deploy.prompt("Enter Netlify site name", default="ics3u-s1-2026-gordon")
        self.assertEqual(stopped.exception.code, 1)

    def test_a_prompt_with_no_default_refuses_too(self):
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as stopped:
                deploy.prompt("Choose a different Netlify site name")
        self.assertEqual(stopped.exception.code, 1)

    def test_the_refusal_names_the_question_it_could_not_ask(self):
        """A refusal nobody can act on is barely better than a hang.

        The question is quoted verbatim, so whoever reads the log in the
        morning knows what would have been asked.
        """
        said = io.StringIO()
        with contextlib.redirect_stdout(said):
            with self.assertRaises(SystemExit):
                deploy.prompt("Enter Netlify site name", default="ics3u-s1-2026-gordon")
        printed = said.getvalue()
        self.assertIn(
            "Enter Netlify site name", printed,
            "The refusal must say which question it could not ask",
        )
        self.assertIn(
            "nobody is at this computer", printed,
            "The refusal must say why it stopped",
        )

    def test_the_surname_question_refuses(self):
        """Reached only when a NEW website is being named.

        The surname is looked for under `GLOBAL_SECRETS_ROOT`, which is a
        path inside the container — so it is pointed at an empty folder
        here rather than left to the host's, where "no surname saved"
        would be true by accident rather than by arrangement.
        """
        with tempfile.TemporaryDirectory() as tmp:
            with unittest.mock.patch.object(deploy, "GLOBAL_SECRETS_ROOT", Path(tmp)):
                with contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaises(SystemExit) as stopped:
                        deploy.get_or_prompt_teacher_last_name()
                self.assertEqual(stopped.exception.code, 1)


class WithSomebodyThereNothingChanges(unittest.TestCase):
    """The flag is opt-in, and the ordinary publish must be untouched.

    Pressing Deploy in the app runs this same code through a
    pseudo-terminal, so a question comes back to the app and becomes a
    dialog the teacher answers. That is the feature, not a fault.
    """

    def test_a_prompt_still_takes_its_default_when_the_flag_is_off(self):
        self.assertFalse(deploy.NON_INTERACTIVE)
        # Standard input is replaced rather than merely assumed to be a
        # pipe. `prompt()` branches on `isatty()`, so run from a terminal
        # this test would call `input()` and WAIT — and verify.sh insists
        # on a terminal, which means the gate for a hang would itself hang,
        # with its output redirected to a log so nothing said why.
        with unittest.mock.patch.object(sys, "stdin", io.StringIO()):
            self.assertEqual(
                deploy.prompt("Enter Netlify site name", default="ics3u-s1-2026-gordon"),
                "ics3u-s1-2026-gordon",
            )


class TheFlagIsWiredAllTheWayThrough(unittest.TestCase):
    """It has to survive three hops, and a break in any one is silent."""

    def test_the_python_accepts_the_flag(self):
        result = subprocess.run(
            [sys.executable, str(REPOSITORY_ROOT / "scripts" / "deploy.py"), "--help"],
            capture_output=True, text=True, timeout=60,
        )
        self.assertIn("--non-interactive", result.stdout)

    def test_the_launcher_accepts_the_flag_and_does_not_call_it_unknown(self):
        """`deploy.sh` exiting with "Unknown option" is a publish that never started.

        A COPY is run, in an empty folder, because the launcher's second
        line is `cd "$(dirname "$0")"` — running the repository's own copy
        would ignore `cwd` entirely and carry on into the real working
        folder. From an empty folder it stops at the missing recipe, long
        before anything needs Docker, but only AFTER parsing the flags,
        which is what this is really asking about.
        """
        with tempfile.TemporaryDirectory() as tmp:
            launcher = Path(tmp) / "deploy.sh"
            launcher.write_bytes((REPOSITORY_ROOT / "deploy.sh").read_bytes())
            result = subprocess.run(
                ["bash", str(launcher), "ICS3U", "1", "--non-interactive"],
                capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL,
            )
            self.assertNotIn("Unknown option", result.stdout + result.stderr)
            self.assertIn(
                "missing the toolchain's build recipe", result.stdout + result.stderr,
                "The flags were parsed and it reached the first real step",
            )

    def test_the_launcher_hands_the_flag_to_the_python(self):
        """The container command builds its options as a string, so this
        cannot be checked by running it without Docker."""
        launcher = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        self.assertIn('opts="$opts --non-interactive"', launcher)
        self.assertIn('-e NON_INTERACTIVE=', launcher)

    def test_the_launcher_asks_for_no_terminal_when_nobody_is_here(self):
        """Belt and braces: with no terminal on standard input, the branch
        of `input()` that WAITS cannot be reached at all."""
        launcher = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        self.assertIn('if [[ "$NON_INTERACTIVE" == "true" ]]; then\n  _EXEC_TTY="-i"', launcher)


class TheContractAndTheCodeAgree(unittest.TestCase):
    """The refusal points are contract data so Windows copies them rather
    than inventing a second, differently-shaped list."""

    def test_the_contract_lists_the_flag_and_what_it_refuses(self):
        rules = json.loads(
            (REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8")
        )
        flags = rules["launcherFlags"]
        named = [entry["flag"] for entry in flags["deployExtras"]]
        self.assertIn("--non-interactive", named)

        refusals = flags["nonInteractive"]["refusals"]
        self.assertTrue(refusals, "The list of what it refuses is the point")
        for refusal in refusals:
            for key in ("where", "question", "reachedWhen", "refuse"):
                self.assertIn(key, refusal)

    def test_the_scheduled_deploy_is_what_passes_it(self):
        """A case in `deployArguments` carries it, so both apps build the
        same command line for a scheduled publish."""
        rules = json.loads(
            (REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8")
        )
        unattended = [
            case for case in rules["deployArguments"]["cases"] if case.get("unattended")
        ]
        self.assertTrue(unattended, "Nothing pins what a scheduled deploy passes")
        for case in unattended:
            self.assertIn("--non-interactive", case["expectArguments"])
        for case in rules["deployArguments"]["cases"]:
            if not case.get("unattended"):
                self.assertNotIn(
                    "--non-interactive", case["expectArguments"],
                    "Only a scheduled deploy says nobody is here",
                )


if __name__ == "__main__":
    unittest.main()

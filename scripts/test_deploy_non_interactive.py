#!/usr/bin/env python3
"""
Regression test for `deploy.py --non-interactive`.

A publish a teacher sets to happen on its own runs at half six in the morning
with the app closed, so every question deploy.py can ask is a question NOBODY
will answer. Until this flag existed there were two ways that ended, and BOTH
have been seen:

  * stdin IS a terminal -> `input()` blocks, forever. Measured: two harness
    runs left a powershell.exe and its python.exe child waiting at the
    site-name prompt for 45 minutes. The teacher's site is simply not updated
    in the morning, and nothing says why.
  * stdin is NOT a terminal -> `prompt()` returns its DEFAULT silently, and a
    Netlify name conflict auto-suffixes. The site is published to an address
    nobody chose, and on a machine with no saved surname the address has no
    surname in it either.

Under the flag, every question REFUSES instead: it says which question it could
not ask, says what to do about it, and exits `NEEDS_AN_ANSWER` (3) — a code
that means that and nothing else, so a caller can tell it from an ordinary
failure. GitHub issue #92.

**What is pinned here is the REFUSAL, not the prose.** The sentences are free
to change; what must not change is that no question is asked, no default is
taken, and the exit code is 3.

Pure stdlib, no Docker, no network, no credentials. Run with:

    python3 scripts/test_deploy_non_interactive.py
"""
# Merged 2026-09-09 from two branches that implemented this flag independently:
# issue/92-non-interactive-deploy (Windows, whose SHAPE won -- exit 3, the
# top-level Cloudflare guard, the teacher-facing readout) and
# issue/deploy-non-interactive (the mac, whose CONTRACT won -- the seven named
# refusal points in app-rules.json and the deployArguments cases). The four
# tests appended at the end came from the mac's file; they pin the launcher
# plumbing and the contract, which the Windows file did not cover.
#
# One mac test was deliberately NOT carried over:
# test_the_launcher_asks_for_no_terminal_when_nobody_is_here asserted that
# deploy.sh forces `-i` under the flag, as belt and braces so the branch of
# input() that WAITS could not be reached at all. The Windows shape decides the
# terminal with `[[ -t 0 ]]` instead and relies on every question refusing
# first, which is sound -- refuse_to_ask() runs before input() at every site,
# and prompt() refuses as a catch-all. The belt is redundant rather than
# missing, and forcing `-i` would also change the MCP path.

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent


def _a_bash_that_can_run_deploy_sh():
    """A `bash` that can actually run this repository's launcher, or None.

    THIS IS NOT PEDANTRY, and it cost a test run to find. Since 2026-09-07 the
    Windows app runs every `scripts/test_*.py` inside `dotnet test`
    (`PythonToolchainTests`), so this file is a gate on BOTH platforms. It is
    also the only shared test that shells out to `bash`, and on Windows the
    plain name is a trap twice over:

      * `bash` on PATH is `C:\\Windows\\System32\\bash.exe`, the WSL LAUNCHER
        rather than a shell. On a machine whose WSL wants updating it prints
        "Windows Subsystem for Linux must be updated to the latest version to
        proceed" — in UTF-16, so the failure arrives as a wall of NUL bytes —
        and the test fails for a reason that has nothing to do with publishing.
      * Even where WSL WORKS it is the wrong shell here. The launcher copy is
        written to a Windows temporary folder and handed over as
        `C:\\Users\\...\\deploy.sh`, a path no Linux filesystem can open.

    So a Windows-hosted `bash` is accepted only if it is NOT the System32 one:
    in practice Git for Windows, which every clone of this repository already
    has because git itself ships it. Verified by RUNNING it rather than by
    trusting the path, since a `.exe` that exists and cannot start is exactly
    the case above.

    Returns None when there is no such shell, and the caller skips — visibly,
    with the reason — rather than failing. A skip that says why is honest; a
    failure that says "WSL must be updated" sends the next person looking for a
    bug in the launcher.
    """
    candidates = []
    if os.name == "nt":
        for base in (os.environ.get("ProgramFiles", r"C:\Program Files"),
                     os.environ.get("ProgramW6432", r"C:\Program Files"),
                     os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")):
            candidates.append(Path(base) / "Git" / "bin" / "bash.exe")
            candidates.append(Path(base) / "Git" / "usr" / "bin" / "bash.exe")

    on_path = shutil.which("bash")
    if on_path:
        candidates.append(Path(on_path))

    system_root = Path(os.environ.get("SystemRoot", r"C:\Windows")).resolve()
    for candidate in candidates:
        try:
            resolved = candidate.resolve()
            if not resolved.exists():
                continue
            # The WSL launcher, rejected by WHERE it lives rather than by what
            # it says, because what it says depends on the machine's WSL state.
            if os.name == "nt" and system_root in resolved.parents:
                continue
            # 7 rather than 0: a stub that fails to start also exits non-zero,
            # and a shell that ran nothing would exit 0.
            if subprocess.run([str(resolved), "-c", "exit 7"],
                              capture_output=True, timeout=60).returncode == 7:
                return str(resolved)
        except (OSError, subprocess.SubprocessError):
            continue
    return None
from contextlib import redirect_stdout

import deploy


class RefusingRatherThanAsking(unittest.TestCase):

    def setUp(self):
        # Module-level state, so it is put back whatever happens — otherwise a
        # failure here would leave every later test in this process refusing.
        self._before = deploy.NON_INTERACTIVE
        deploy.NON_INTERACTIVE = True

    def tearDown(self):
        deploy.NON_INTERACTIVE = self._before

    def _refusal(self, call):
        """Run something that must refuse, and hand back what it printed."""
        said = io.StringIO()
        with redirect_stdout(said):
            with self.assertRaises(SystemExit) as stopped:
                call()
        self.assertEqual(
            deploy.NEEDS_AN_ANSWER, stopped.exception.code,
            "The exit code is the whole mechanism: the scheduled wrapper reads "
            "it to tell a teacher their publish needs one answer. Any other "
            "code reads as an ordinary failure.")
        return said.getvalue()

    def test_the_exit_code_is_distinct_from_an_ordinary_failure(self):
        # Every other exit in deploy.py is 1. If this ever becomes 1, a caller
        # can no longer tell "nobody was there to answer" from "the upload
        # failed", and the teacher gets the wrong sentence in the morning.
        self.assertEqual(3, deploy.NEEDS_AN_ANSWER)
        self.assertNotEqual(1, deploy.NEEDS_AN_ANSWER)

    def test_a_question_with_a_default_refuses_rather_than_taking_it(self):
        """
        The dangerous half. Without the flag and without a terminal this
        returns "ics3u-s1-2026" and the site is created at that address —
        published, live, and named by nobody.
        """
        said = self._refusal(
            lambda: deploy.prompt("Enter Netlify site name", default="ics3u-s1-2026"))
        self.assertIn("Enter Netlify site name", said,
                      "The refusal has to name the question it could not ask.")
        self.assertNotIn("ics3u-s1-2026", said,
                         "Naming the default invites somebody to think it was used.")

    def test_a_question_with_no_default_refuses_too(self):
        said = self._refusal(lambda: deploy.prompt("Choose a different Netlify site name"))
        self.assertIn("Choose a different Netlify site name", said)

    def test_the_surname_question_refuses(self):
        """
        Asked only when a NEW site is being named — which is exactly the
        situation a scheduled run must not be in.
        """
        # No saved profile is needed: the point is that it never reaches the
        # terminal, whatever is on disk. If a surname IS already saved the
        # function returns it and asks nothing, which is the ordinary case and
        # is not what this pins.
        if deploy.load_teacher_last_name():
            self.skipTest("a surname is already saved on this machine, so nothing is asked")
        said = self._refusal(deploy.get_or_prompt_teacher_last_name)
        self.assertIn("last name", said.lower())

    def test_it_says_nothing_was_published(self):
        """
        The sentence a teacher most needs, because the alternative reading of a
        stopped publish is "it half happened".
        """
        said = self._refusal(lambda: deploy.prompt("Enter Netlify site name", default="x"))
        self.assertIn("Nothing was published", said)

    def test_it_says_what_to_do_about_it(self):
        said = self._refusal(lambda: deploy.prompt("Enter Netlify site name", default="x"))
        self.assertIn("Plantoir", said,
                      "A refusal that does not say where to answer the question leaves the "
                      "teacher with a publish that will fail again tomorrow night.")


class AskingNormallyWhenSomebodyIsThere(unittest.TestCase):
    """
    The other half, and the one a regression would be worst in: with the flag
    ABSENT nothing changes at all. A teacher at a keyboard must get every
    prompt they got before.
    """

    def test_without_the_flag_a_non_terminal_still_takes_the_default(self):
        before = deploy.NON_INTERACTIVE
        before_stdin = sys.stdin
        deploy.NON_INTERACTIVE = False
        # stdin is REPLACED rather than tested, because this file is also run
        # by hand from a terminal — where the real stdin is a tty and this call
        # would block on input() for ever, hanging the suite. A StringIO is not
        # a terminal, which takes the same branch a scheduled run takes.
        sys.stdin = io.StringIO("")
        try:
            self.assertEqual("ics3u-s1-2026",
                             deploy.prompt("Enter Netlify site name", default="ics3u-s1-2026"))
        finally:
            sys.stdin = before_stdin
            deploy.NON_INTERACTIVE = before

    def test_the_flag_is_off_unless_it_is_asked_for(self):
        # Read from the module as imported, not after setUp has touched it.
        self.assertFalse(
            deploy.NON_INTERACTIVE,
            "Refusing by default would break every teacher publishing by hand.")


class TheFlagIsAccepted(unittest.TestCase):

    def test_the_argument_parser_takes_it(self):
        # Guards the plumbing rather than the behaviour: a flag the parser
        # rejects makes the launcher's child exit 2 with an argparse message,
        # which reads as a broken toolchain rather than as a missing answer.
        source = (deploy.__file__ or "")
        self.assertTrue(source.endswith("deploy.py"))
        with open(source, encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn('"--non-interactive"', text)
        self.assertIn("non_interactive", text,
                      "argparse turns --non-interactive into args.non_interactive; "
                      "main() has to read that name.")



    def test_the_launcher_accepts_the_flag_and_does_not_call_it_unknown(self):
        """`deploy.sh` exiting with "Unknown option" is a publish that never started.

        A COPY is run, in an empty folder, because the launcher's second
        line is `cd "$(dirname "$0")"` — running the repository's own copy
        would ignore `cwd` entirely and carry on into the real working
        folder. From an empty folder it stops at the missing recipe, long
        before anything needs Docker, but only AFTER parsing the flags,
        which is what this is really asking about.
        """
        shell = _a_bash_that_can_run_deploy_sh()
        if shell is None:
            self.skipTest(
                "no bash on this machine that can run a launcher from a native path "
                "(on Windows the `bash` on PATH is the WSL launcher, not a shell). "
                "The mac runs this for real; every other test in this file still runs here."
            )

        with tempfile.TemporaryDirectory() as tmp:
            launcher = Path(tmp) / "deploy.sh"
            launcher.write_bytes((REPOSITORY_ROOT / "deploy.sh").read_bytes())
            # encoding= rather than text=, because text= decodes with the
            # machine's LOCALE encoding: on a Windows box that is cp1252, and
            # deploy.sh's own sentences carry em-dashes and curly quotes, so the
            # read threw UnicodeDecodeError in a subprocess reader thread and
            # the test failed with "unsupported operand type(s) for +: 'NoneType'
            # and 'str'" — which names neither the launcher nor the encoding.
            # errors="replace" for the same reason: this test reads the output
            # for two SENTENCES, and a stray byte must not be able to stop it.
            result = subprocess.run(
                [shell, str(launcher), "ICS3U", "1", "--non-interactive"],
                capture_output=True, timeout=120, stdin=subprocess.DEVNULL,
                encoding="utf-8", errors="replace",
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

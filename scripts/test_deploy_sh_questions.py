#!/usr/bin/env python3
"""
Drives the REAL `deploy.sh` to every question it can ask, and back out again.

`scripts/test_deploy_non_interactive.py` next door tests `deploy.py` and reads
`deploy.sh` as TEXT. This file RUNS the launcher. The distinction is the whole
reason it exists: `deploy.sh` gained `--non-interactive` on a Windows machine
with no bash and no Docker, was syntax-checked and reasoned through, and had
never been executed when GitHub issue #129 asked the mac to run it. Running it
found two things reading could not (below), so "it was reviewed carefully" is
not a substitute for starting the script and watching what it says.

**No Docker, no network, no credentials, and nothing of the teacher's is
touched.** Three things make that true, and each is load-bearing:

  * `--image <tag>` skips resolving the build recipe, so the script gets past
    its Docker setup without one. Every question below is asked BEFORE the
    first `docker` call, so the run never needs a container.
  * `USER` is set to an account name that does not exist, so the Keychain
    lookups (`/usr/bin/security ... -a "$USER"`) find nothing and the
    questions fire. Nothing is written: under the flag the script exits
    before `set_..._keychain` is reached, and where a test runs WITHOUT the
    flag the Keychain writers are stubbed out.
  * A COPY of the launcher runs, in a scratch folder, because `deploy.sh`'s
    second line is `cd "$(dirname "$0")"` — the repository's own copy would
    ignore `cwd` and walk into the real working folder.

WHAT THE RUN FOUND, both in `prompt_for_cf_account` and both invisible to a
reader (issue #129, 2026-09-09):

  1. Its six-step "where to find your Account ID" instructions and its "that
     doesn't look like an Account ID" error went to STDOUT, and it is called
     as `CF_ACCOUNT="$(prompt_for_cf_account)"` — a subshell that captures
     stdout. Driven through a pseudo-terminal, a teacher was asked to paste a
     code with no hint where it lives, and saw NOTHING AT ALL when they got it
     wrong. Same trap that issue #92 fixed for the refusal; these two were
     left behind because nobody had run the script this far.
  2. Worse, and only visible once (1) was understood: on the SUCCESS path the
     captured value was the instructions AND the ID — 115 bytes where 32 were
     meant. That blob went to `set_cf_account_keychain`, so it was remembered
     and every later run skipped the question and reused it, and to wrangler
     as `CLOUDFLARE_ACCOUNT_ID`. First-time Cloudflare publishing from the
     command line did not work, and stayed broken until the Keychain entry was
     cleared by hand.

Both are fixed by writing to stderr, which is where `read -rp` already puts
its own prompt. `test_the_account_question_returns_the_id_and_nothing_else`
pins it by running the real function out of the real file, so it cannot rot.

Pure stdlib. Run with:

    python3 scripts/test_deploy_sh_questions.py
"""

import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent

# A user name no account has, so every Keychain lookup comes back empty and the
# questions are reached. Never written to: see the module docstring.
NOBODY = "plantoir-no-such-user-129"

# `deploy.sh` exits 1 with "This script targets macOS" before any credential
# question, so those tests have nothing to drive anywhere else. The course-code
# guard comes first and runs wherever bash does.
ON_A_MAC = sys.platform == "darwin"
HAS_BASH = shutil.which("bash") is not None

# What `assert_can_ask` prints, and the exit code it means. Pinned in
# contracts/app-rules.json -> launcherFlags.nonInteractive; the SENTENCES are
# free to change, so only the parts a caller depends on are asserted here.
NEEDS_AN_ANSWER = 3
REFUSAL_HEADLINE = "nobody is here to answer"


def a_working_folder(tmp: str, course: str = "ICS3U", section: int = 1) -> Path:
    """A scratch folder holding just enough for `deploy.sh` to reach its
    questions: the launcher itself, and a built site to publish."""
    folder = Path(tmp)
    shutil.copy2(REPOSITORY_ROOT / "deploy.sh", folder / "deploy.sh")
    built = folder / "courses" / course / ".merged_output" / f"section{section}" / "public"
    built.mkdir(parents=True)
    (built / "index.html").write_text("<html>a built site</html>", encoding="utf-8")
    return folder


def run_launcher(folder: Path, arguments: list, answer: str = "",
                 launcher: str = "deploy.sh") -> subprocess.CompletedProcess:
    """Runs the copied launcher with a hollowed-out environment.

    `answer` is fed on stdin. Note that bash only DISPLAYS a `read -rp` prompt
    when stdin is a terminal, so a test that wants to see the question itself
    has to look at what the script echoes afterwards (or use a terminal); the
    answer is still read from a pipe eitherway.
    """
    import os
    environment = dict(os.environ, USER=NOBODY)
    return subprocess.run(
        ["bash", str(folder / launcher)] + arguments,
        capture_output=True, text=True, timeout=180, cwd=str(folder),
        input=answer, env=environment,
    )


def with_credentials_stubbed(folder: Path) -> str:
    """Writes a second copy of the launcher whose Keychain and Cloudflare
    lookups are stubbed, and returns its name.

    Needed for ONE question — the Cloudflare Account ID — which is reached
    only when a token is already saved and no account could be discovered.
    Getting there for real would mean putting a token in the teacher's
    Keychain and calling Cloudflare. The five stubbed functions are the
    credential and network lookups ONLY; `assert_can_ask`, the call site and
    `prompt_for_cf_account` — everything under test — are untouched, and the
    marker is asserted so a rename fails the test rather than skipping it.
    """
    marker = "# -------------------- Cloudflare token and account ---------------------\n"
    text = (folder / "deploy.sh").read_text(encoding="utf-8")
    if text.count(marker) != 1:
        raise AssertionError(
            "deploy.sh no longer carries the Cloudflare section marker this test "
            "inserts its stubs before, so it cannot reach the Account ID question."
        )
    stubs = (
        "get_cf_token_keychain() { printf '%s' 'stub-token-never-leaves-this-test'; }\n"
        "validate_cf_token() { return 0; }\n"
        "discover_cf_account() { printf '%s' ''; }\n"
        "get_cf_account_keychain() { printf '%s' ''; }\n"
        "set_cf_account_keychain() { :; }\n"
    )
    (folder / "deploy_stubbed.sh").write_text(text.replace(marker, stubs + marker),
                                              encoding="utf-8")
    return "deploy_stubbed.sh"


@unittest.skipUnless(HAS_BASH, "no bash on this machine, so deploy.sh cannot be run")
class EveryQuestionRefusesUnderTheFlag(unittest.TestCase):
    """With `--non-interactive`, every question exits 3 and says which one."""

    def assert_refused(self, result: subprocess.CompletedProcess, question: str):
        everything = result.stdout + result.stderr
        self.assertEqual(
            NEEDS_AN_ANSWER, result.returncode,
            f"Refusing {question!r} must exit {NEEDS_AN_ANSWER}, so a scheduled "
            f"publish can tell it from an ordinary failure. Got {result.returncode}.\n"
            f"{everything[-2000:]}",
        )
        self.assertIn(REFUSAL_HEADLINE, everything,
                      "The refusal has to be SAID, not only exited")
        self.assertIn(question, everything,
                      "The refusal names the question it could not ask")
        self.assertIn("Nothing was published.", everything)

    def test_the_course_code_question_refuses(self):
        """The 'Open' course-code guard — the one that asks BEFORE the flag
        loop runs, which is why deploy.sh pre-scans its arguments for the flag
        and deploy.ps1 does not need to."""
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            # ICS30 ends in a zero, so the guard offers ICS3O and asks.
            result = run_launcher(folder, ["ICS30", "1", "--image", "unused:tag",
                                           "--non-interactive"])
            self.assert_refused(result, "Fix course code to 'ICS3O'?")

    @unittest.skipUnless(ON_A_MAC, "deploy.sh stops at 'This script targets macOS' first")
    def test_the_netlify_token_question_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            result = run_launcher(folder, ["ICS3U", "1", "--image", "unused:tag",
                                           "--non-interactive"])
            self.assert_refused(result, "Paste Netlify token")

    @unittest.skipUnless(ON_A_MAC, "deploy.sh stops at 'This script targets macOS' first")
    def test_the_cloudflare_token_question_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            result = run_launcher(folder, ["ICS3U", "1", "--image", "unused:tag",
                                           "--target", "cloudflare", "--non-interactive"])
            self.assert_refused(result, "Paste Cloudflare token")

    @unittest.skipUnless(ON_A_MAC, "deploy.sh stops at 'This script targets macOS' first")
    def test_the_cloudflare_account_question_refuses_ON_THE_SCREEN(self):
        """The one that was wrong, and the reason the guard sits at the call
        site rather than inside the function.

        A refusal printed inside `prompt_for_cf_account` would land in
        `$CF_ACCOUNT` and its `exit 3` would end only the subshell, leaving
        `|| exit 1` to report an ordinary failure — nothing on screen, wrong
        code, and a scheduled publish that records the wrong reason. So this
        asserts the refusal is VISIBLE, not merely that the run stopped.
        """
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            stubbed = with_credentials_stubbed(folder)
            result = run_launcher(folder, ["ICS3U", "1", "--image", "unused:tag",
                                           "--target", "cloudflare", "--non-interactive"],
                                  launcher=stubbed)
            self.assert_refused(result, "Paste Cloudflare Account ID")


@unittest.skipUnless(HAS_BASH, "no bash on this machine, so deploy.sh cannot be run")
class WithoutTheFlagNothingChanged(unittest.TestCase):
    """The important half. A teacher at a keyboard must be asked exactly what
    they were asked before, and their answer must be taken."""

    def ask_the_course_code_question(self, answer: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            return run_launcher(folder, ["ICS30", "1", "--image", "unused:tag"],
                                answer=answer + "\n")

    def test_answering_yes_corrects_the_course_code(self):
        result = self.ask_the_course_code_question("y")
        self.assertIn("Using corrected course code: ICS3O", result.stdout + result.stderr)

    def test_answering_no_keeps_what_was_typed(self):
        result = self.ask_the_course_code_question("n")
        self.assertIn("Continuing with: ICS30", result.stdout + result.stderr)

    def test_an_empty_answer_still_takes_the_default(self):
        """`${_ans:-Y}` — pressing return means yes, as it always did. Pinned
        because the flag's whole point is that this is what must NOT happen
        when nobody is there, so the two behaviours are asserted together."""
        result = self.ask_the_course_code_question("")
        self.assertIn("Using corrected course code: ICS3O", result.stdout + result.stderr)

    def test_no_ordinary_failure_ever_exits_three(self):
        """Exit 3 means "a question went unasked" and nothing else, so a
        wrapper can act on it. These runs all fail for ordinary reasons."""
        for answer in ("y", "n", ""):
            with self.subTest(answer=answer):
                result = self.ask_the_course_code_question(answer)
                self.assertNotEqual(NEEDS_AN_ANSWER, result.returncode)
                self.assertEqual(1, result.returncode)


@unittest.skipUnless(HAS_BASH, "no bash on this machine")
class TheAccountQuestionSaysWhatItMeansTo(unittest.TestCase):
    """`prompt_for_cf_account`'s stdout is its RETURN VALUE, and everything it
    says to the teacher goes to stderr.

    Run against the function lifted out of the real `deploy.sh`, so it cannot
    drift from the file. Both halves of the bug issue #129 found are here.
    """

    def the_real_function(self) -> str:
        """The function's own text, taken from deploy.sh rather than copied."""
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        match = re.search(r"^prompt_for_cf_account\(\) \{\n.*?^\}\n", text,
                          re.DOTALL | re.MULTILINE)
        self.assertIsNotNone(
            match, "prompt_for_cf_account is not in deploy.sh in the shape this "
                   "test lifts it out with, so nothing below tested anything.")
        return match.group(0)

    def call_it(self, typed: str):
        """Calls it exactly as deploy.sh does — captured — and returns what
        the caller would get and what the teacher would see."""
        script = self.the_real_function() + (
            '\nCF_ACCOUNT="$(prompt_for_cf_account)" || true\n'
            'printf "CAPTURED:%s:END" "$CF_ACCOUNT" >&2\n'
        )
        result = subprocess.run(["bash", "-c", script], input=typed + "\n",
                                capture_output=True, text=True, timeout=60)
        captured = re.search(r"CAPTURED:(.*):END", result.stderr, re.DOTALL)
        self.assertIsNotNone(captured, result.stderr)
        seen_by_the_teacher = result.stderr[:captured.start()]
        return captured.group(1), seen_by_the_teacher

    def test_a_good_id_is_captured_and_nothing_else_is(self):
        """The failure this closes: the caller got the instructions AND the
        id — 115 bytes where 32 were meant — which was then remembered in the
        Keychain and handed to wrangler as CLOUDFLARE_ACCOUNT_ID."""
        identifier = "0123456789abcdef0123456789abcdef"
        captured, _ = self.call_it(identifier)
        self.assertEqual(identifier, captured,
                         "Everything this function writes to stdout is its return "
                         "value, because the call site captures it.")

    def test_the_instructions_reach_the_teacher(self):
        _, seen = self.call_it("0123456789abcdef0123456789abcdef")
        self.assertIn("dash.cloudflare.com", seen,
                      "A teacher asked to paste an Account ID is told where to find it")

    def test_a_bad_id_is_explained_rather_than_swallowed(self):
        captured, seen = self.call_it("not-an-account-id")
        self.assertEqual("", captured, "A refused id returns nothing to the caller")
        self.assertIn("look like an Account ID", seen,
                      "Before this was fixed the teacher saw nothing at all and the "
                      "script exited 1 in silence.")


if __name__ == "__main__":
    unittest.main(verbosity=2)

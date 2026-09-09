#!/usr/bin/env python3
"""
Drives the REAL `preview.sh` to the one question it can ask, and back out again.

The twin next door, `scripts/test_deploy_sh_questions.py`, does this for
`deploy.sh`, and its own meta-test says in as many words that a preview-only
question "belongs to a preview test". This is that file.

**Why it exists at all.** `preview.sh` took `--non-interactive` on 2026-09-09
(GitHub issue #124), and until this file nothing had ever STARTED it under the
flag. That is exactly the state `deploy.sh` was in when issue #129 asked the mac
to run it: reviewed, syntax-checked, reasoned through, never executed — and
running it found two defects reading had missed. The contract's own reasoning
for the flag is a claim about what an unattended `preview.sh` DOES, and a claim
nobody has measured is a claim that can be wrong; the Windows side found theirs
was wrong for PowerShell on the same day, which is what makes this worth
running rather than reading.

**No Docker, no network, no credentials, and nothing of the teacher's is
touched.** Three things make that true:

  * `--image <tag>` skips resolving the build recipe, so the script never
    hashes a build context or asks for a container. Every question and every
    validation these tests reach is asked long before the first `docker` call.
  * The course-code guard fires BEFORE the course preflight, so no course
    folder has to exist for the question to be asked. The runs that get past
    the guard stop at "course_config.json not found", which is an ordinary
    exit 1 and touches nothing.
  * A COPY of the launcher runs, in a scratch folder, because `preview.sh`
    line 21 is `cd "$(dirname "$0")"` — the repository's own copy would ignore
    `cwd` and walk into the real working folder.

**The harness is imported from the deploy twin rather than copied.** Its
`run_launcher` already takes the launcher's name, and its bash probe, its
byte-encoded stdin and the reasons for both are written down there at length.
Copying them would mean two places to fix when a bash on some future machine
reads a pipe differently — and the byte-encoding one was a real measured bug,
not a style choice.

Pure stdlib. Run with:

    python3 scripts/test_preview_sh_questions.py
"""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

# Imported by bare name, which resolves because `verify.sh` runs these from
# `scripts/` and Windows' PythonToolchainTests sets the same working directory.
from test_deploy_sh_questions import (
    HAS_BASH,
    NEEDS_AN_ANSWER,
    ON_A_MAC,
    REFUSAL_HEADLINE,
    REPOSITORY_ROOT,
    run_launcher,
)

# A code ending in a digit zero, which is what the 'Open' guard is looking for.
# ICS3O is what it offers instead.
CODE_THAT_IS_ASKED_ABOUT = "ICS30"
WHAT_THE_GUARD_OFFERS = "ICS3O"


def a_working_folder(tmp: str) -> Path:
    """A scratch folder holding just the launcher.

    Nothing else is needed: the guard this file drives is asked before
    `preview.sh` looks for a course, a section folder or a container.
    """
    folder = Path(tmp)
    shutil.copy2(REPOSITORY_ROOT / "preview.sh", folder / "preview.sh")
    return folder


def run_preview(folder: Path, arguments: list, answer: str = ""):
    return run_launcher(folder, arguments, answer=answer, launcher="preview.sh")


@unittest.skipUnless(HAS_BASH, "no bash here that can reach a scratch folder")
class TheQuestionRefusesUnderTheFlag(unittest.TestCase):
    """With `--non-interactive`, the question exits 3 and says which one.

    Exit 3 is the load-bearing part. The mac's scheduled wrapper reads the
    build leg's exit code and writes `buildNeededAnAnswer` for 3 and
    `didNotFinish` for anything else (`ScheduledDeploy.oneShotCommand`), so a
    refusal that exited 1 would tell the teacher their overnight publish had
    failed rather than that it had asked them something.
    """

    def assert_refused(self, result: subprocess.CompletedProcess, question: str):
        everything = result.stdout + result.stderr
        self.assertEqual(
            NEEDS_AN_ANSWER, result.returncode,
            f"Refusing {question!r} must exit {NEEDS_AN_ANSWER}, so the scheduled "
            f"wrapper can tell it from an ordinary failure. Got {result.returncode}.\n"
            f"{everything[-2000:]}",
        )
        self.assertIn(REFUSAL_HEADLINE, everything,
                      "The refusal has to be SAID, not only exited")
        self.assertIn(question, everything,
                      "The refusal names the question it could not ask")
        self.assertIn("Nothing was built.", everything,
                      "preview.sh builds; it publishes nothing, and says so")

    def test_the_course_code_question_refuses(self):
        """The 'Open' course-code guard — `preview.sh`'s only question.

        It is asked BEFORE the flag loop runs, which is why `preview.sh`
        pre-scans its arguments for the flag rather than relying on the parser
        to have seen it.
        """
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            result = run_preview(folder, [CODE_THAT_IS_ASKED_ABOUT, "1",
                                          "--image", "unused:tag", "--non-interactive"])
            self.assert_refused(result, f"Fix course code to '{WHAT_THE_GUARD_OFFERS}'?")

    def test_the_command_the_scheduled_wrapper_writes_refuses(self):
        """The shape that actually runs at half six, argument for argument.

        `ScheduledDeploy.oneShotCommand` writes `preview.sh <CODE> <N>
        --build-only --non-interactive` into the launchd wrapper — the flag
        LAST, after another flag. Driven as its own case because the parser bug
        the flag's `case` arm carries a comment about (a second `shift` eating
        the following argument) was latent for exactly this reason: the wrapper
        happens to put the flag at the end, so the ONE caller that matters
        would not have shown it.
        """
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            result = run_preview(folder, [CODE_THAT_IS_ASKED_ABOUT, "1",
                                          "--image", "unused:tag",
                                          "--build-only", "--non-interactive"])
            self.assert_refused(result, f"Fix course code to '{WHAT_THE_GUARD_OFFERS}'?")

    def test_nothing_was_built_is_true_and_not_merely_said(self):
        """The refusal claims nothing was built. This checks the folder.

        Cheap, and it is the half a sentence cannot promise: the guard runs
        before the preflight, so a refusal that had somehow got as far as
        laying down an output tree would still have printed the same words.
        """
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            run_preview(folder, [CODE_THAT_IS_ASKED_ABOUT, "1",
                                 "--image", "unused:tag", "--non-interactive"])
            left_behind = sorted(entry.name for entry in folder.iterdir())
            self.assertEqual(
                ["preview.sh"], left_behind,
                "A refused build left something behind. Nothing may be created "
                f"before the question is answered; found {left_behind}.",
            )


@unittest.skipUnless(HAS_BASH, "no bash here that can reach a scratch folder")
class TheFlagDoesNotEatWhatFollowsIt(unittest.TestCase):
    """The parser arm for `--non-interactive` must not shift.

    The loop shifts once at the bottom for every case, so a `shift` inside the
    arm consumes the NEXT argument. It was written that way once: `preview.sh
    <CODE> <N> --non-interactive --build-only` lost `--build-only`, and an
    unattended run would then have started a SERVER — taking a port and
    holding it — where a build was meant. Latent only because the wrapper puts
    the flag last, which is why the comment in the launcher is not enough on
    its own.

    Driven through `--port`, whose validation refuses a value outside
    8081-8084 and so PROVES the argument after the flag was still parsed.
    `--build-only` cannot show it: proving a build rather than a server would
    need a container, and this file needs none.
    """

    def run_with(self, *flags) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            # A course code the guard does NOT ask about, so the run reaches
            # the parser and the validations rather than stopping at the
            # question.
            return run_preview(folder, ["ICS3U", "1", "--image", "unused:tag", *flags])

    def test_the_argument_after_the_flag_is_still_parsed(self):
        result = self.run_with("--non-interactive", "--port", "9999")
        everything = result.stdout + result.stderr
        self.assertIn(
            "--port must be between 8081 and 8084", everything,
            "The value after --non-interactive never reached the port "
            "validation, so the flag's parser arm is eating the argument that "
            "follows it.\n" + everything[-2000:],
        )

    def test_the_flag_is_not_reported_as_an_unknown_option(self):
        """The pre-scan sees the flag; the PARSER still has to accept it.

        Without an arm of its own it would fall to `*)`, which prints
        "Unknown option" and exits 1 — so a scheduled build would stop before
        it began, having refused nothing. Asserted by getting PAST the parser:
        the run reaches the course preflight, which is the next thing that
        speaks.
        """
        result = self.run_with("--non-interactive")
        everything = result.stdout + result.stderr
        self.assertNotIn("Unknown option", everything)
        self.assertIn("course_config.json not found", everything,
                      "The run never reached the preflight, so it did not get "
                      "past the parser at all.\n" + everything[-2000:])


@unittest.skipUnless(HAS_BASH, "no bash here that can reach a scratch folder")
@unittest.skipUnless(ON_A_MAC, "preview.sh is the mac's launcher; a foreign bash "
                               "reads a pipe in ways this machine cannot check")
class WithoutTheFlagNothingChanged(unittest.TestCase):
    """A teacher at a keyboard is asked what they were always asked.

    And the empty-answer case is more than symmetry: it is the MEASUREMENT the
    contract's reasoning rests on. `launcherFlags.nonInteractive.refusals` says
    that unattended, without the flag, `preview.sh` takes the [Y/n] default and
    builds a DIFFERENT course — which a deploy then publishes successfully
    against the wrong course. That is the whole justification for giving a
    script that publishes nothing a publishing flag, and the Windows side found
    the equivalent claim about PowerShell was FALSE when they measured it. So
    it is checked here rather than believed.

    Gated to macOS for the reason the deploy twin gives: what these assert is
    how the mac launcher reads an answer, and a red suite must not arrive on
    the other platform as a surprise (CLAUDE.md rule 4).
    """

    def ask_the_course_code_question(self, answer: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_working_folder(tmp)
            return run_preview(folder, [CODE_THAT_IS_ASKED_ABOUT, "1",
                                        "--image", "unused:tag"],
                               answer=answer + "\n")

    def test_an_empty_answer_takes_the_default_and_retargets_the_build(self):
        result = self.ask_the_course_code_question("")
        everything = result.stdout + result.stderr
        self.assertIn(f"Using corrected course code: {WHAT_THE_GUARD_OFFERS}", everything)

    def test_answering_yes_corrects_the_course_code(self):
        result = self.ask_the_course_code_question("y")
        self.assertIn(f"Using corrected course code: {WHAT_THE_GUARD_OFFERS}",
                      result.stdout + result.stderr)

    def test_answering_no_keeps_what_was_typed(self):
        result = self.ask_the_course_code_question("n")
        self.assertIn(f"Continuing with: {CODE_THAT_IS_ASKED_ABOUT}",
                      result.stdout + result.stderr)

    def test_no_ordinary_failure_ever_exits_three(self):
        """Exit 3 means "a question went unanswered" and nothing else, so the
        wrapper can act on it. These runs all fail for an ordinary reason —
        the corrected course has no `course_config.json` in a scratch folder."""
        for answer in ("y", "n", ""):
            with self.subTest(answer=answer):
                result = self.ask_the_course_code_question(answer)
                self.assertEqual(1, result.returncode)


# Deliberately NOT gated on bash: this one reads JSON and preview.sh as text.
class EveryQuestionTheContractNamesIsDrivenHere(unittest.TestCase):
    """What preview.sh asks and what this file drives are the same list.

    The mirror of the deploy twin's own completeness test, and the reason both
    exist: without it the file quietly stops being "every question it can ask"
    the day a second one is added — the tests still pass, and the new question
    is the one nobody has ever seen refused.
    """

    DRIVEN_ABOVE = {
        "Fix course code to '<CODE>'? [Y/n]": "test_the_course_code_question_refuses",
    }

    def test_the_questions_driven_are_the_ones_the_contract_names(self):
        rules = json.loads(
            (REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8")
        )
        refusals = rules["launcherFlags"]["nonInteractive"]["refusals"]
        launcher_text = (REPOSITORY_ROOT / "preview.sh").read_text(encoding="utf-8")

        named = set()
        for refusal in refusals:
            if refusal.get("where") != "launcher":
                continue          # deploy.py's own questions; tested next door.
            if refusal["question"].startswith("(not a question)"):
                continue          # a rule about a saved credential, not a prompt.
            # The contract spells a question out with its explanation after an
            # em dash; the part before it is the question itself, and the
            # course-code guard carries a placeholder because the code varies.
            question = refusal["question"].split(" — ")[0].strip()
            probe = question.split("<")[0].strip() or question
            # Asking the launcher itself which questions are ITS questions is
            # what keeps this honest as the register grows: `where: "launcher"`
            # does not say which launcher, and an entry can be for a launcher
            # that does not exist on this platform at all (`preview.ps1` asks a
            # question `preview.sh` does not). Either way the text is simply
            # not in this file, so it belongs to a test somewhere else.
            if probe not in launcher_text:
                continue
            named.add(question)

        self.assertTrue(named, "Nothing in the contract was matched to preview.sh at "
                               "all, which means this comparison is vacuous.")
        self.assertEqual(
            set(self.DRIVEN_ABOVE), named,
            "The questions this file drives and the ones the contract says "
            "--non-interactive must refuse in preview.sh have come apart. "
            "Either a question was added and nothing here starts the script to "
            "check it, or one was renamed. Both end the same way: a question "
            "nobody has ever seen refused.",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

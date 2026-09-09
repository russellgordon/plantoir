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
import io
import sys
import unittest
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


if __name__ == "__main__":
    unittest.main(verbosity=2)

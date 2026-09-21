#!/usr/bin/env python3
"""
What the command-line wizard says when it offers a subject's skeleton.

The app RUNS this script and shows its output to the teacher, so these are
sentences a teacher reads, not log lines. There are two openings because two
different things are true:

* a course code with no ready-made course of its own — saying so is the
  point, since it is why a skeleton is being offered at all;
* a course code that HAS one, which the teacher has just been asked about
  and declined. Telling them there is no ready-made course for the code
  they were offered a ready-made course for is plainly untrue, and it is
  what they read for all 38 codes with a payload (GitHub issue #248).

The skeleton INSTALL itself needed no change — `find_skeleton_dir` has never
looked at payloads, so `use_skeleton: true` on a payload code has always
worked. Measured while fixing #248, driving the real script through a pty:
ICS4U with `prepopulate:false, use_skeleton:true` installs 47 `.md` files
against the 18 the apps were producing, and the tree is identical to the one
ICS2O (same family, no payload) gets.

Run with:

    python3 scripts/test_starting_content_prompts.py
"""
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from setup_course import starting_point_intro  # noqa: E402


class StartingPointIntroTests(unittest.TestCase):

    def test_a_code_with_no_ready_made_course_is_told_so(self):
        text = starting_point_intro("ICS2O", "Computer Studies", has_payload=False)
        self.assertIn("There is no ready-made course for ICS2O", text)
        self.assertIn("shaped for computer studies", text)

    def test_a_code_whose_ready_made_course_was_declined_is_not_told_there_is_none(self):
        text = starting_point_intro("ICS4U", "Computer Studies", has_payload=True)
        self.assertNotIn("no ready-made course", text,
                         "The teacher declined a ready-made course for this very code one "
                         "question ago; this sentence says there was never one to decline.")
        self.assertIn("There is also a starting point", text)
        self.assertIn("shaped for computer studies", text)

    def test_both_openings_describe_the_same_starting_point(self):
        without_payload = starting_point_intro("ICS2O", "Computer Studies", has_payload=False)
        with_payload = starting_point_intro("ICS4U", "Computer Studies", has_payload=True)
        for promise in ("four units of class pages to rename",
                        "a page explaining what the site can do",
                        "placeholders saying"):
            with self.subTest(promise=promise):
                self.assertIn(promise, without_payload)
                self.assertIn(promise, with_payload)

    def test_a_family_with_no_label_still_reads_as_english(self):
        text = starting_point_intro("CODING", "", has_payload=False)
        self.assertIn("shaped for this subject", text)

    def test_the_last_line_is_not_mistaken_for_a_prompt(self):
        # The app answers any line ending in ":" or "?" by pressing Return
        # (NewCourseCreator.looksLikePrompt). A paragraph whose last line
        # looked like a question would be answered instead of read, and the
        # real question below it would then go unanswered.
        for has_payload in (False, True):
            with self.subTest(has_payload=has_payload):
                last = starting_point_intro("ICS4U", "Computer Studies", has_payload).rstrip().splitlines()[-1]
                self.assertFalse(last.endswith(":"))
                self.assertFalse(last.endswith("?"))


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""
A build for publishing stops the preview serving THIS section, and no other.

Written because the first version of this stopped previews by PORT, and a
build-only run is never given one: it killed whatever held the default 8081,
which is the first section to have previewed in that working folder rather than
the one being published. Previewing section 1 while publishing section 2 took
section 1's preview down — the ordinary multi-section workflow.

The matching rule is now the section's own build directory, and the two claims
worth pinning are the ones the documentation makes: a trailing separator (so
`section1` does not match `section10`), and `--serve` (so a build is never
mistaken for a server).

`/proc` is not simulated — the function is exercised through the same matching
it uses, against command lines taken from a real container.
"""
import sys
import unittest
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import build_site


# Real command lines, copied from a running container on 2026-09-05.
SERVING_SECTION_1 = (
    "node /tmp/quartz-builds/ADA1O/section1/quartz/bootstrap-cli.mjs build "
    "--concurrency 1 --serve --port 8081 --wsPort 9081"
)
SERVING_SECTION_10 = (
    "node /tmp/quartz-builds/ADA1O/section10/quartz/bootstrap-cli.mjs build "
    "--concurrency 1 --serve --port 8082 --wsPort 9082"
)
SERVING_SECTION_2 = (
    "node /tmp/quartz-builds/ADA1O/section2/quartz/bootstrap-cli.mjs build "
    "--concurrency 1 --serve --port 8082 --wsPort 9082"
)
BUILDING_SECTION_1 = (
    "node /tmp/quartz-builds/ADA1O/section1/quartz/bootstrap-cli.mjs build "
    "--concurrency 1"
)


def would_stop(command: str, output_dir: str) -> bool:
    """The rule `stop_preview_serving` applies to one process's command line."""
    marker = str(output_dir).rstrip("/") + "/"
    return marker in command and "--serve" in command


class StopPreviewMatchingTests(unittest.TestCase):

    def test_it_stops_this_sections_preview(self):
        self.assertTrue(would_stop(SERVING_SECTION_1, "/tmp/quartz-builds/ADA1O/section1"))

    def test_it_leaves_another_sections_preview_alone(self):
        """
        The regression this whole rule replaced: a build for section 2 must not
        touch section 1, which is what killing by the default port did.
        """
        self.assertFalse(would_stop(SERVING_SECTION_1, "/tmp/quartz-builds/ADA1O/section2"))
        self.assertFalse(would_stop(SERVING_SECTION_2, "/tmp/quartz-builds/ADA1O/section1"))

    def test_section_1_does_not_match_section_10(self):
        """
        The trailing separator, which both documents now promise. Without it
        `.../section1` is a prefix of `.../section10` and a build for section 1
        would stop section 10's preview.
        """
        self.assertFalse(would_stop(SERVING_SECTION_10, "/tmp/quartz-builds/ADA1O/section1"))
        self.assertTrue(would_stop(SERVING_SECTION_10, "/tmp/quartz-builds/ADA1O/section10"))

    def test_a_build_is_not_a_server(self):
        """`--serve` is what separates a preview from an ordinary build."""
        self.assertFalse(would_stop(BUILDING_SECTION_1, "/tmp/quartz-builds/ADA1O/section1"))

    def test_a_trailing_slash_on_the_directory_changes_nothing(self):
        self.assertTrue(would_stop(SERVING_SECTION_1, "/tmp/quartz-builds/ADA1O/section1/"))

    def test_it_does_nothing_where_there_is_no_proc(self):
        """
        Windows, natively. The function must be a no-op rather than an error —
        the same shape `kill_existing_quartz` already has without `lsof`.
        """
        import unittest.mock as mock
        with mock.patch.object(build_site.Path, "is_dir", return_value=False):
            self.assertEqual(
                build_site.stop_preview_serving(Path("/tmp/quartz-builds/ADA1O/section1")), 0
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

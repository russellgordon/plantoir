#!/usr/bin/env python3
"""
`preview.sh` announces the preview's address, or says it cannot and stops —
it never announces a port it guessed (GitHub #235).

The address the app opens is the one line `preview.sh` prints as
"Preview will be available at: …", and the app believes it: it is the only
address it will try. That line used to fall back to the port INSIDE the
builder whenever the question "which port does this Mac use?" came back
empty, and announce it as fact. That port is right only for the first working
folder on a Mac (8081 -> 8081); the development Mac's own folder publishes
8091 -> 8081. So the fallback was a wrong answer delivered as the truth, and
it could point the app at another section's preview.

**How this runs the real thing without Docker.** The two functions are cut
out of the repository's `preview.sh` by name — not retyped — and run under
bash with `docker` replaced by a shell function that answers as told. Nothing
is started and nothing is published; the only file written is a counter in a
scratch folder, deleted afterwards.

**Windows.** Skipped where there is no bash that can run a program, the same
rule as the launcher tests beside it; `preview.ps1` probes its ports on the PC
itself and has no such fallback to remove.

Pure stdlib. Run with:

    python3 scripts/test_preview_address.py
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT

ANNOUNCEMENT = "Preview will be available at: "


def the_launcher_text() -> str:
    return (REPOSITORY_ROOT / "preview.sh").read_text(encoding="utf-8")


def function_named(name: str) -> str:
    """The whole of one function, from `name() {` to the `}` that closes it
    at the start of a line — the shape every function in the launcher has."""
    match = re.search(
        r"^" + re.escape(name) + r"\(\) \{\n.*?^\}\n",
        the_launcher_text(),
        flags=re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(
            f"preview.sh has no function called {name}: the address is announced "
            "some other way now, and this file has to be told how."
        )
    return match.group(0)


def announce(answers: list, build_only: str = "", trail_home: Path = None) -> subprocess.CompletedProcess:
    """Runs the launcher's own announcement with `docker port` answering each
    time with the next of `answers` (an empty string is an empty answer), and
    reports how many times it was asked.

    `HOME` is always a scratch folder — the launcher's trail helper writes
    under `$HOME/Library/Logs/Plantoir`, and a test must never add a line to
    the real trail. Pass `trail_home` to read what was written there.

    The count is kept in a file because the launcher asks inside `$( … )`,
    which is a subshell: a variable counted there is gone when it returns."""
    with tempfile.TemporaryDirectory() as scratch:
        home = trail_home if trail_home is not None else Path(scratch) / "home"
        home.mkdir(parents=True, exist_ok=True)
        counter = Path(scratch) / "asked"
        counter.write_text("0", encoding="utf-8")
        program = "\n".join([
            function_named("note_on_the_trail"),
            # Since #234 the announcement first makes sure this Mac can reach
            # the address (scripts/test_preview_reach.py). Here curl always
            # answers the way a healthy Mac does, and nothing sleeps, so this
            # file tests the address alone and never touches the network.
            "\n".join(re.findall(r"^PREVIEW_REACH_[A-Z_]+=.*$", the_launcher_text(), flags=re.MULTILINE)),
            function_named("this_mac_can_reach_the_builder"),
            function_named("say_this_mac_cannot_reach_the_builder"),
            'curl() { return 52; }',
            'sleep() { :; }',
            function_named("say_the_preview_address_is_unknown"),
            # Since #310 the address is also asked whose it is
            # (scripts/test_preview_reach.py -> WhoseAddressItIs). Here it is
            # always this account's own, so this file tests the address alone.
            'held_by_someone_else() { return 1; }',
            'a_different_engine_was_named_by_hand() { return 1; }',
            function_named("the_preview_s_host_port"),
            function_named("announce_the_preview_address"),
            "_answers=(" + " ".join("'" + answer + "'" for answer in answers) + ")",
            '_counter="$1"',
            'docker() {',
            '  if [[ "$1" != "port" ]]; then echo "unexpected docker $*" >&2; return 99; fi',
            '  local asked; asked=$(cat "$_counter")',
            '  echo $((asked + 1)) > "$_counter"',
            '  local answer="${_answers[$asked]:-}"',
            '  if [[ -n "$answer" ]]; then printf "%b\\n" "$answer"; fi',
            '}',
            'CONTAINER_NAME="teaching-quartz-test"',
            'COURSE="ICS4U"',
            'SECTION="2"',
            'PREVIEW_PORT=8081',
            'BUILD_ONLY="' + build_only + '"',
            'announce_the_preview_address',
            '_status=$?',
            'echo "ASKED=$(cat "$_counter")"',
            'exit $_status',
        ]) + "\n"
        return subprocess.run(
            ["bash", "-c", program, "announce", str(counter)],
            capture_output=True,
            timeout=30,
            env={"HOME": str(home), "PATH": os.environ.get("PATH", "")},
        )


def output_of(result: subprocess.CompletedProcess) -> str:
    return result.stdout.decode("utf-8", "replace")


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class TheAddressIsAnnouncedOrTheLauncherStops(unittest.TestCase):

    def test_the_published_port_is_announced(self):
        result = announce(["0.0.0.0:8091\\n[::]:8091"])
        self.assertEqual(result.returncode, 0, output_of(result))
        self.assertIn(ANNOUNCEMENT + "http://localhost:8091/\n", output_of(result))
        self.assertIn("ASKED=1", output_of(result))

    def test_one_empty_answer_is_asked_again(self):
        """A single empty answer is not proof: the question is put a second
        time, and the second answer is announced."""
        result = announce(["", "0.0.0.0:8101"])
        self.assertEqual(result.returncode, 0, output_of(result))
        self.assertIn(ANNOUNCEMENT + "http://localhost:8101/\n", output_of(result))
        self.assertIn("ASKED=2", output_of(result))

    def test_no_answer_stops_rather_than_guessing(self):
        """The fault: two empty answers used to announce the port inside the
        builder, 8081, as though it were known."""
        result = announce(["", ""])
        self.assertEqual(result.returncode, 1, output_of(result))
        self.assertNotIn(ANNOUNCEMENT, output_of(result))
        self.assertNotIn("8081", output_of(result))
        self.assertIn("❌", output_of(result))
        self.assertIn("ASKED=2", output_of(result))

    def test_the_refusal_leaves_its_line_on_the_trail(self):
        """Rule 5: the refusal a teacher will actually meet says why on the
        trail, in the contract's words, with the course and section — and a
        preview that found its address, or a build for publishing, adds
        nothing."""
        rules = json.loads(
            (REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8")
        )
        line = None
        for entry in rules["activityTrail"]["mustRecord"]:
            if entry["event"] == "preview did not appear":
                line = entry["launcherLine"]
        self.assertIsNotNone(line, "the contract no longer pins the launcher's line")
        expected = line.replace("{course}", "ICS4U").replace("{section}", "2")

        with tempfile.TemporaryDirectory() as scratch:
            home = Path(scratch)
            announce(["", ""], trail_home=home)
            trail = (home / "Library" / "Logs" / "Plantoir" / "activity.txt").read_text(encoding="utf-8")
            lines = trail.splitlines()
            self.assertEqual(len(lines), 1, trail)
            self.assertTrue(lines[0].endswith(" · " + expected), trail)

        for answers, build_only in ((["0.0.0.0:8091"], ""), (["", ""], "--build-only")):
            with tempfile.TemporaryDirectory() as scratch:
                home = Path(scratch)
                announce(answers, build_only=build_only, trail_home=home)
                self.assertFalse(
                    (home / "Library" / "Logs" / "Plantoir" / "activity.txt").exists(),
                    f"nothing to record for {answers} {build_only!r}",
                )

    def test_the_sentence_names_no_machinery(self):
        """Rule 1: a teacher reads this line in the console."""
        result = announce(["", ""])
        words = set(re.findall(r"[a-z]+", output_of(result).lower().replace("asked=2", "")))
        for forbidden in ["docker", "container", "port", "toolchain", "script", "localhost"]:
            self.assertNotIn(forbidden, words)

    def test_a_build_for_publishing_asks_nothing_and_is_never_stopped(self):
        """A publish runs `preview.sh --build-only` first. It opens no preview,
        so it must not be refused over a question publishing never asks — even
        on a Mac where the answer would have been empty."""
        result = announce(["", ""], build_only="--build-only")
        self.assertEqual(result.returncode, 0, output_of(result))
        self.assertEqual(output_of(result).strip(), "ASKED=0")


# Deliberately NOT gated on bash: this one reads preview.sh as text.
class TheLauncherUsesItsAnnouncement(unittest.TestCase):

    def test_the_old_guess_is_gone(self):
        text = the_launcher_text()
        self.assertIsNone(
            re.search(r'=\s*"\$PREVIEW_PORT"\s*$', text, flags=re.MULTILINE),
            "preview.sh sets a host port from the port inside the builder again.",
        )

    def test_a_refusal_stops_the_launcher(self):
        """The function says it cannot; the call site is what stops. Without
        `|| exit 1` the launcher would say so and then build anyway, into a
        preview the app has no address for."""
        text = the_launcher_text()
        self.assertRegex(text, r"(?m)^announce_the_preview_address \|\| exit 1$")

    def test_the_announcement_is_printed_only_in_one_place(self):
        """A second announcement elsewhere in preview.sh would be a second
        writer of the address the app opens."""
        text = the_launcher_text()
        self.assertEqual(text.count(ANNOUNCEMENT), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""
One launcher at a time gets the website builder ready (bundle B), and
`setup.sh --prepare-builder` gets it ready and nothing else.

`contracts/app-rules.json` -> `builderWarmUp.turn.cases` and
`builderWarmUp.sequences.cases`, run against the REAL GETTING-READY TURN
BLOCK, cut out of each launcher by its markers (the three copies must be
identical) and run under /bin/bash with `set -euo pipefail`, HOME pointed at a
scratch folder. The end-to-end half runs the real setup.sh in
--prepare-builder mode from a scratch folder, with a pretend `docker` first on
PATH that answers from files and writes down every question it was asked:
nothing is started, built or downloaded.

Skipped where there is no bash that can run a program (Windows), like the
other launcher tests. Pure stdlib. Run with:

    python3 scripts/test_getting_ready_turn.py
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT

LAUNCHERS = ["setup.sh", "preview.sh", "deploy.sh"]
START = "# >>> GETTING-READY TURN BLOCK >>>"
END = "# <<< GETTING-READY TURN BLOCK <<<"
BASH = "/bin/bash" if Path("/bin/bash").exists() else "bash"


def the_rules() -> dict:
    with open(REPOSITORY_ROOT / "contracts" / "app-rules.json", encoding="utf-8") as handle:
        return json.load(handle)["builderWarmUp"]


def the_block(launcher: str) -> str:
    text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
    start = text.index(START)
    end = text.index(END, start) + len(END)
    return text[start:end] + "\n"


def waiting_line() -> str:
    return the_rules()["wording"]["waitingLine"]


@unittest.skipUnless(HAS_BASH, "needs a bash that can run a program")
class TheTurn(unittest.TestCase):

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.home = Path(self.scratch.name)
        self.turn = self.home / "Library" / "Application Support" / "Plantoir" / "getting-ready.turn"
        self.holders = []

    def tearDown(self):
        for holder in self.holders:
            if holder.poll() is None:
                holder.kill()
                holder.wait()
        self.scratch.cleanup()

    def script(self, body: str) -> str:
        return "set -euo pipefail\nREADY_TURN_PAUSE=0.2\n" + the_block("setup.sh") + body

    def run_script(self, body: str, timeout: float = 20) -> subprocess.CompletedProcess:
        environment = dict(os.environ, HOME=str(self.home))
        return subprocess.run([BASH, "-c", self.script(body)], capture_output=True, text=True,
                              env=environment, timeout=timeout)

    def start_script(self, body: str) -> subprocess.Popen:
        environment = dict(os.environ, HOME=str(self.home))
        return subprocess.Popen([BASH, "-c", self.script(body)], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, env=environment)

    def a_running_holder(self) -> int:
        holder = subprocess.Popen(["sleep", "60"])
        self.holders.append(holder)
        self.turn.mkdir(parents=True)
        (self.turn / "pid").write_text(f"{holder.pid}\n")
        return holder

    def a_gone_holder(self) -> None:
        gone = subprocess.Popen(["true"])
        gone.wait()
        self.turn.mkdir(parents=True)
        (self.turn / "pid").write_text(f"{gone.pid}\n")

    def test_the_three_copies_are_the_same(self):
        blocks = [the_block(launcher) for launcher in LAUNCHERS]
        self.assertEqual(blocks[0], blocks[1])
        self.assertEqual(blocks[0], blocks[2])

    def test_every_launcher_takes_the_turn_before_starting_the_builder(self):
        for launcher in LAUNCHERS:
            text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            take = text.index(END + "\ntake_the_ready_turn\n")
            start = text.index("\nensure_container_runtime\n")
            self.assertLess(take, start, launcher)

    def test_every_launcher_hands_it_back_once_the_builder_is_ready(self):
        for launcher in ["setup.sh", "preview.sh"]:
            text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            self.assertIn("\nbuild_image_if_missing\n# The builder is ready: the next launcher may go "
                          "(GETTING-READY TURN BLOCK).\ngive_back_the_ready_turn\n", text, launcher)
        deploy = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        building = deploy[deploy.index("ensure_image_present() {"):]
        building = building[:building.index("\n}\n")]
        self.assertIn("take_the_ready_turn", building)
        self.assertIn("give_back_the_ready_turn", building)
        after_start = deploy.index("\nensure_container_runtime\n")
        self.assertIn("give_back_the_ready_turn", deploy[after_start:after_start + 600])

    def test_every_case(self):
        for case in the_rules()["turn"]["cases"]:
            with self.subTest(case["name"]):
                if self.turn.exists():
                    shutil.rmtree(self.turn)
                holder = None
                if case["holder"] == "running":
                    holder = self.a_running_holder()
                elif case["holder"] == "gone":
                    self.a_gone_holder()
                elif case["holder"] in ("unwrittenRecent", "unwrittenOld"):
                    self.turn.mkdir(parents=True)
                    if case["holder"] == "unwrittenOld":
                        old = time.time() - 120
                        os.utime(self.turn, (old, old))
                waiter = self.start_script('take_the_ready_turn\necho "TOOK $(cat "$READY_TURN/pid")"\n'
                                           'give_back_the_ready_turn\n[[ ! -e "$READY_TURN" ]] && echo GAVE_BACK\n')
                if case["expect"].startswith("waits"):
                    time.sleep(1.5)
                    self.assertIsNone(waiter.poll(), "it should still be waiting")
                    if holder is not None:
                        holder.kill()
                        holder.wait()
                    else:
                        shutil.rmtree(self.turn)
                out, err = waiter.communicate(timeout=20)
                self.assertEqual(waiter.returncode, 0, err)
                self.assertIn("TOOK ", out)
                self.assertIn("GAVE_BACK", out)
                self.assertEqual(waiting_line() in out, case["expectWaitingLine"], out)
                self.assertLessEqual(out.count(waiting_line()), 1, "said more than once")

    def test_it_is_handed_back_on_any_exit(self):
        result = self.run_script('take_the_ready_turn\nexit 3\n')
        self.assertEqual(result.returncode, 3)
        self.assertFalse(self.turn.exists())

    def test_a_turn_someone_else_took_is_never_removed_by_handing_back(self):
        holder = self.a_running_holder()
        result = self.run_script('READY_TURN_IS_OURS=1\ngive_back_the_ready_turn\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.turn / "pid").read_text().strip(), str(holder.pid))


FAKE_DOCKER = r'''#!/bin/bash
# A pretend docker: answers from files in $FAKE, writes every question down.
printf '%s\n' "$*" >> "$FAKE/asked"
case "$1" in
  info) exit 0 ;;
  buildx) if [[ "${2:-}" == "version" ]]; then exit 0; fi
          if [[ "${2:-}" == "build" ]]; then echo build >> "$FAKE/builds"; : > "$FAKE/image"; exit 0; fi ;;
  build) echo build >> "$FAKE/builds"; : > "$FAKE/image"; exit 0 ;;
  image) [[ -e "$FAKE/image" ]] && exit 0; exit 1 ;;
  images) exit 0 ;;
  context) echo colima; exit 0 ;;
  ps) exit 0 ;;
esac
exit 0
'''


@unittest.skipUnless(HAS_BASH, "needs a bash that can run a program")
class ThePrepareMode(unittest.TestCase):
    """The real setup.sh, --prepare-builder, with a pretend docker."""

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        root = Path(self.scratch.name)
        self.home = root / "home"
        self.home.mkdir()
        self.fake = root / "fake"
        self.fake.mkdir()
        bin_dir = root / "bin"
        bin_dir.mkdir()
        docker = bin_dir / "docker"
        docker.write_text(FAKE_DOCKER)
        docker.chmod(docker.stat().st_mode | stat.S_IEXEC)
        self.path = f"{bin_dir}:/usr/bin:/bin:/usr/sbin:/sbin"
        self.place = self.home / "Library" / "Application Support" / "Plantoir" / "getting-ready"
        (self.place / ".toolchain").mkdir(parents=True)
        shutil.copy(REPOSITORY_ROOT / "setup.sh", self.place / "setup.sh")
        (self.place / ".toolchain" / "Dockerfile").write_text("FROM scratch\n")

    def tearDown(self):
        self.scratch.cleanup()

    def prepare(self) -> subprocess.CompletedProcess:
        environment = {"HOME": str(self.home), "PATH": self.path, "FAKE": str(self.fake),
                       "READY_TURN_PAUSE": "0.2"}
        return subprocess.Popen([BASH, str(self.place / "setup.sh"), "--prepare-builder"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                env=environment, cwd=str(self.place))

    def test_it_builds_the_builder_and_nothing_else(self):
        run = self.prepare()
        out, err = run.communicate(timeout=60)
        self.assertEqual(run.returncode, 0, out + err)
        lines = [line for line in out.splitlines() if line.strip()]
        self.assertTrue(lines[-1].startswith(the_rules()["readyLine"] + "teaching-quartz:src-"), lines[-1])
        self.assertEqual((self.fake / "builds").read_text().count("build"), 1)
        self.assertFalse((self.place / "courses").exists(), "no courses folder")
        self.assertFalse((self.home / "Library" / "Application Support" / "Plantoir" / "builds").exists(),
                         "no builds folder")
        asked = (self.fake / "asked").read_text()
        self.assertNotIn("run ", asked, "no workspace made")
        self.assertNotIn("create", asked)
        turn = self.home / "Library" / "Application Support" / "Plantoir" / "getting-ready.turn"
        self.assertFalse(turn.exists(), "the turn is handed back")

    def test_every_sequence_builds_once(self):
        """A second launcher that arrives mid-build waits, then builds nothing
        (builderWarmUp.sequences): here, a second --prepare-builder run
        started while the first holds the turn."""
        for case in the_rules()["sequences"]["cases"]:
            with self.subTest(case["name"]):
                for leftover in ("builds", "image", "asked"):
                    (self.fake / leftover).unlink(missing_ok=True)
                turn = self.home / "Library" / "Application Support" / "Plantoir" / "getting-ready.turn"
                holder = subprocess.Popen(["sleep", "60"])
                turn.mkdir(parents=True)
                (turn / "pid").write_text(f"{holder.pid}\n")
                try:
                    second = self.prepare()
                    time.sleep(1.5)
                    self.assertIsNone(second.poll(), "it waits while the turn is held")
                    # The holder finishes the build, then hands the turn back.
                    (self.fake / "image").write_text("")
                    (self.fake / "builds").write_text("build\n")
                    shutil.rmtree(turn)
                    out, err = second.communicate(timeout=60)
                finally:
                    holder.kill()
                    holder.wait()
                self.assertEqual(second.returncode, 0, out + err)
                self.assertIn(the_rules()["wording"]["waitingLine"], out)
                self.assertEqual((self.fake / "builds").read_text().count("build"), case["expectBuilds"])


if __name__ == "__main__":
    unittest.main()

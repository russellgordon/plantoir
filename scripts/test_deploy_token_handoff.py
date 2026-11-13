#!/usr/bin/env python3
"""
The deploy token reaches the website builder through a file only that deploy
knows the name of (GitHub #835, fix F1).

Until #835 `deploy.sh` piped the token into ONE fixed path inside the website
builder, `/tmp/deploy_pat`, and the next `docker exec` read it and removed it.
A working folder has one builder, so two deploys started together (two
courses today, two sections once #835 narrows the hold) wrote and read the
same file: in a stand-in of those two steps run in a real builder on
2026-11-13, 29 of 60 deploys read the OTHER deploy's token and 6 read none.

Now each deploy makes a fresh 0700 folder with `mktemp -d` and a 0600 file in
it, hands only the file's NAME to the reading step, and that step deletes the
folder before anything else. An exit before the reading step is reached
deletes it from the EXIT trap.

This file runs the REAL block (`# >>> TOKEN HAND-OFF BLOCK >>>` in
deploy.sh) with `docker exec` standing in as a local `sh`, so the folder is
made in this Mac's /tmp the way it is made in the builder's: two deploys at a
time, many times; the permissions; every way out; and a search of every
argument list, the console and the trail for the token. No credential is
used: the tokens are made-up strings.

Pure stdlib, no Docker, no network. Mac only (the block is bash). Listed in
verify.sh's step 0. Run with:

    python3 scripts/test_deploy_token_handoff.py
"""

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
BLOCK_START = "# >>> TOKEN HAND-OFF BLOCK >>>"
BLOCK_END = "# <<< TOKEN HAND-OFF BLOCK <<<"
ON_A_MAC = sys.platform == "darwin"
PAIRS = 30


def the_block() -> str:
    text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
    if text.count(BLOCK_START) != 1 or text.count(BLOCK_END) != 1:
        raise AssertionError("deploy.sh no longer carries the token hand-off block's markers")
    start = text.index(BLOCK_START)
    return text[start:text.index(BLOCK_END, start)]


# `docker exec [-i] [-e NAME=value]... CONTAINER sh -c|-lc SCRIPT [ARGS]`, run
# here as a local sh. Every argument list it is given is written down, so the
# test can search them for the token.
FAKE_DOCKER = r'''
docker() {
  printf '%s\n' "docker $*" >> "$ARGV_LOG"
  [ "$1" = "exec" ] || return 99
  shift
  local envs=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -i|-it|-t) shift ;;
      -e) envs+=("$2"); shift 2 ;;
      *) break ;;
    esac
  done
  shift            # the container's name
  shift            # sh
  shift            # -c or -lc
  env ${envs[@]+"${envs[@]}"} sh -c "$@"
}
give_back_the_ready_turn() { :; }
CONTAINER_NAME="teaching-quartz-0000abcd"
PLANS_MODE="${PLANS_MODE:-false}"
'''


def a_deploy(block: str, ending: str) -> str:
    """One deploy's hand-off and reading step, then `ending`."""
    return "\n".join([
        "set -euo pipefail",
        FAKE_DOCKER,
        block,
        # Wait for the go-ahead, so two deploys start at the same moment.
        'while [ ! -e "$GO" ]; do :; done',
        'hand_the_token_to_the_builder "$TOKEN_FOR_THIS_TEST"',
        'printf %s "$DEPLOY_PAT_FILE" > "$WHERE"',
        ending,
    ])


READ_IT = ('docker exec -i -e PAT_FILE="${DEPLOY_PAT_FILE}" -e OUT="$OUT" "$CONTAINER_NAME" '
           'sh -lc "$TAKE_THE_TOKEN"\'printf %s "$tok" > "$OUT"\'')


@unittest.skipUnless(ON_A_MAC and shutil.which("bash"), "deploy.sh runs only on a Mac")
class EachDeployGetsItsOwnToken(unittest.TestCase):

    def setUp(self):
        self.scratch = Path(tempfile.mkdtemp(prefix="plantoir-token-handoff-"))
        self.argv_log = self.scratch / "argv.log"
        self.trail = self.scratch / "trail"
        self.trail.mkdir()
        self.block = the_block()

    def tearDown(self):
        # Anything a failing run left behind, removed by its exact name.
        for where in self.scratch.glob("where-*"):
            left = where.read_text(encoding="utf-8").strip()
            if left.startswith("/tmp/deploy_pat.") and left.endswith("/pat"):
                shutil.rmtree(os.path.dirname(left), ignore_errors=True)
        shutil.rmtree(self.scratch, ignore_errors=True)

    def start(self, name: str, token: str, ending: str, extra=None) -> subprocess.Popen:
        environment = dict(os.environ,
                           ARGV_LOG=str(self.argv_log),
                           GO=str(self.scratch / "go"),
                           WHERE=str(self.scratch / f"where-{name}"),
                           OUT=str(self.scratch / f"out-{name}"),
                           TOKEN_FOR_THIS_TEST=token,
                           PLANTOIR_TRAIL_DIR=str(self.trail))
        environment.update(extra or {})
        return subprocess.Popen(["bash", "-c", a_deploy(self.block, ending)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)

    def where(self, name: str) -> str:
        path = self.scratch / f"where-{name}"
        return path.read_text(encoding="utf-8") if path.exists() else ""

    def got(self, name: str) -> str:
        path = self.scratch / f"out-{name}"
        return path.read_text(encoding="utf-8") if path.exists() else ""

    def finish(self, process: subprocess.Popen) -> tuple:
        out, err = process.communicate(timeout=60)
        return process.returncode, out.decode("utf-8", "replace") + err.decode("utf-8", "replace")

    def test_two_deploys_started_together_each_read_their_own(self):
        wrong: int = 0
        empty: int = 0
        consoles: list = []
        tokens: list = []
        for trial in range(PAIRS):
            go = self.scratch / "go"
            if go.exists():
                go.unlink()
            token_a = f"made-up-token-A-{trial}-q8Zr"
            token_b = f"made-up-token-B-{trial}-x3Lm"
            tokens += [token_a, token_b]
            first = self.start(f"a{trial}", token_a, READ_IT)
            second = self.start(f"b{trial}", token_b, READ_IT)
            time.sleep(0.05)
            go.write_text("go", encoding="utf-8")
            for name, token, process in ((f"a{trial}", token_a, first), (f"b{trial}", token_b, second)):
                code, console = self.finish(process)
                consoles.append(console)
                self.assertEqual(code, 0, console)
                got = self.got(name)
                if got == "":
                    empty += 1
                elif got != token:
                    wrong += 1
                left = self.where(name)
                self.assertTrue(left.startswith("/tmp/deploy_pat.") and left.endswith("/pat"), left)
                self.assertFalse(os.path.exists(os.path.dirname(left)),
                                 "the reading step leaves no hand-off folder behind")
        self.assertEqual((wrong, empty), (0, 0),
                         f"of {2 * PAIRS} deploys {wrong} read the other's token and {empty} read none")
        self.assert_never_shown(tokens, consoles)

    def assert_never_shown(self, tokens: list, consoles: list):
        argv = self.argv_log.read_text(encoding="utf-8") if self.argv_log.exists() else ""
        trail = ""
        for path in self.trail.rglob("*"):
            if path.is_file():
                trail += path.read_text(encoding="utf-8", errors="replace")
        for token in tokens:
            self.assertNotIn(token, argv, "a token reached an argument list")
            self.assertNotIn(token, trail, "a token reached the trail")
            for console in consoles:
                self.assertNotIn(token, console, "a token reached the console")

    def test_the_folder_is_0700_and_the_file_0600(self):
        looked = 'stat -f "%Lp" "$(dirname "$DEPLOY_PAT_FILE")" "$DEPLOY_PAT_FILE" > "$OUT.modes"\n' + READ_IT
        process = self.start("modes", "made-up-token-modes", looked)
        (self.scratch / "go").write_text("go", encoding="utf-8")
        code, console = self.finish(process)
        self.assertEqual(code, 0, console)
        modes = (self.scratch / "out-modes.modes").read_text(encoding="utf-8").split()
        self.assertEqual(modes, ["700", "600"])
        self.assertEqual(self.got("modes"), "made-up-token-modes")

    def test_an_exit_before_the_reading_step_leaves_nothing(self):
        process = self.start("early", "made-up-token-early", "exit 1")
        (self.scratch / "go").write_text("go", encoding="utf-8")
        code, console = self.finish(process)
        self.assertEqual(code, 1, "the trap keeps the deploy's own exit status")
        left = self.where("early")
        self.assertTrue(left.startswith("/tmp/deploy_pat."), left)
        self.assertFalse(os.path.exists(os.path.dirname(left)))
        self.assert_never_shown(["made-up-token-early"], [console])

    def test_the_trap_never_changes_how_the_run_ended(self):
        # Under `set -e` a failing command in the EXIT trap becomes the run's
        # exit status: a finished deploy read as failed (found by
        # test_deploy_sh_plans.py, whose launcher has no getting-ready turn).
        ending = "unset -f give_back_the_ready_turn\n" + READ_IT + "\ndocker() { return 1; }\nexit 0"
        process = self.start("trap", "made-up-token-trap", ending)
        (self.scratch / "go").write_text("go", encoding="utf-8")
        code, console = self.finish(process)
        self.assertEqual(code, 0, console)
        self.assertEqual(self.got("trap"), "made-up-token-trap")

    def test_a_deploy_stopped_before_the_reading_step_leaves_nothing(self):
        for stopped_by in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            with self.subTest(stopped_by.name):
                name = f"stopped-{stopped_by.name}"
                process = self.start(name, "made-up-token-stopped", "sleep 30 >/dev/null 2>&1 & wait")
                (self.scratch / "go").write_text("go", encoding="utf-8")
                deadline = time.time() + 20
                while self.where(name) == "" and time.time() < deadline:
                    time.sleep(0.05)
                left = self.where(name)
                self.assertTrue(os.path.exists(left), "the hand-off was made")
                process.send_signal(stopped_by)
                self.finish(process)
                self.assertFalse(os.path.exists(os.path.dirname(left)),
                                 f"{stopped_by.name} left the hand-off folder behind")
                (self.scratch / "go").unlink()

    def test_the_reading_step_removes_only_a_hand_off_folder(self):
        keep = self.scratch / "keep" / "pat"
        keep.parent.mkdir()
        keep.write_text("not a hand-off", encoding="utf-8")
        process = self.start("refused", "made-up-token-refused",
                             'DEPLOY_PAT_FILE="' + str(keep) + '"\n' + READ_IT)
        (self.scratch / "go").write_text("go", encoding="utf-8")
        code, console = self.finish(process)
        self.assertEqual(code, 1, console)
        self.assertTrue(keep.exists(), "a name this block did not make is never removed")
        self.assertIn("could not hand the sign-in to the website builder", console)

    def test_a_hand_off_that_fails_stops_the_deploy_in_words(self):
        broken = self.scratch / "bin"
        broken.mkdir()
        (broken / "mktemp").write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        (broken / "mktemp").chmod(0o755)
        for plans, words in (("false", "so nothing was deployed."), ("true", "so nothing was shared.")):
            with self.subTest(plans=plans):
                process = self.start(f"broken-{plans}", "made-up-token-broken", READ_IT,
                                     {"PATH": str(broken) + ":" + os.environ.get("PATH", ""),
                                      "PLANS_MODE": plans})
                (self.scratch / "go").write_text("go", encoding="utf-8")
                code, console = self.finish(process)
                self.assertEqual(code, 1, console)
                self.assertIn(words, console)
                self.assertEqual(self.got(f"broken-{plans}"), "")
                (self.scratch / "go").unlink()


# The same trial in a REAL website builder, when asked for: the builder's own
# sh, mktemp and /tmp, which the class above stands in for. Opt-in because it
# needs Docker and an image; give the image's tag in
# PLANTOIR_TOKEN_HANDOFF_IMAGE (any teaching-quartz:src-* this Mac has). A
# container of its own is started for the run and removed after it.
REAL_IMAGE = os.environ.get("PLANTOIR_TOKEN_HANDOFF_IMAGE", "")


@unittest.skipUnless(REAL_IMAGE and ON_A_MAC and shutil.which("docker"),
                     "set PLANTOIR_TOKEN_HANDOFF_IMAGE to run it in a real website builder")
class EachDeployGetsItsOwnTokenInARealBuilder(unittest.TestCase):

    def setUp(self):
        self.scratch = Path(tempfile.mkdtemp(prefix="plantoir-token-handoff-real-"))
        self.container = f"plantoir-token-handoff-{os.getpid()}"
        subprocess.run(["docker", "run", "-d", "--rm", "--name", self.container, "--entrypoint", "tail",
                        REAL_IMAGE, "-f", "/dev/null"], check=True, capture_output=True, timeout=120)

    def tearDown(self):
        subprocess.run(["docker", "rm", "-f", self.container], capture_output=True, timeout=60)
        shutil.rmtree(self.scratch, ignore_errors=True)

    def test_two_deploys_started_together_each_read_their_own(self):
        block = the_block()
        program = "\n".join([
            "set -euo pipefail",
            "give_back_the_ready_turn() { :; }",
            f'CONTAINER_NAME="{self.container}"; PLANS_MODE=false',
            block,
            'while [ ! -e "$GO" ]; do :; done',
            'hand_the_token_to_the_builder "$TOKEN_FOR_THIS_TEST"',
            'printf %s "$DEPLOY_PAT_FILE" > "$WHERE"',
            'docker exec -i -e PAT_FILE="${DEPLOY_PAT_FILE}" "$CONTAINER_NAME" '
            'sh -lc "$TAKE_THE_TOKEN"\'printf %s "$tok"\' > "$OUT"',
        ])
        wrong: int = 0
        empty: int = 0
        for trial in range(PAIRS):
            go = self.scratch / "go"
            if go.exists():
                go.unlink()
            runs = []
            for side in ("a", "b"):
                token = f"made-up-token-{side}-{trial}-r7Kp"
                environment = dict(os.environ, GO=str(go), TOKEN_FOR_THIS_TEST=token,
                                   WHERE=str(self.scratch / f"where-{side}{trial}"),
                                   OUT=str(self.scratch / f"out-{side}{trial}"))
                runs.append((side, token, subprocess.Popen(["bash", "-c", program], env=environment,
                                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)))
            time.sleep(0.05)
            go.write_text("go", encoding="utf-8")
            for side, token, process in runs:
                out, err = process.communicate(timeout=120)
                self.assertEqual(process.returncode, 0, err.decode("utf-8", "replace"))
                self.assertNotIn(token, out.decode("utf-8", "replace") + err.decode("utf-8", "replace"))
                got = (self.scratch / f"out-{side}{trial}").read_text(encoding="utf-8")
                if got == "":
                    empty += 1
                elif got != token:
                    wrong += 1
        left = subprocess.run(["docker", "exec", self.container, "sh", "-c", "ls -d /tmp/deploy_pat* 2>/dev/null || true"],
                              capture_output=True, timeout=60).stdout.decode("utf-8").strip()
        self.assertEqual(left, "", "a hand-off folder was left in the builder")
        self.assertEqual((wrong, empty), (0, 0),
                         f"of {2 * PAIRS} deploys {wrong} read the other's token and {empty} read none")


class TheCallSitesUseTheBlock(unittest.TestCase):
    """Read as text, so it runs everywhere (Windows' PythonToolchainTests
    included): no fixed token path is left, and both readers take the file's
    name through PAT_FILE and start with the block's reading step."""

    def test_no_fixed_token_path_is_written_or_read(self):
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        for old in ("cat > /tmp/deploy_pat'", "cat /tmp/deploy_pat", "rm -f /tmp/deploy_pat"):
            self.assertNotIn(old, text)

    def test_both_readers_start_with_the_reading_step(self):
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        self.assertEqual(text.count('sh -lc "$TAKE_THE_TOKEN"\''), 2, "the plan share and the deploy")
        self.assertEqual(text.count('-e PAT_FILE="${DEPLOY_PAT_FILE}"'), 2)
        self.assertEqual(text.count('hand_the_token_to_the_builder "$'), 2, "Cloudflare and Netlify")

    def test_the_token_is_never_handed_over_as_an_argument(self):
        block = the_block()
        self.assertIn('printf %s "$1" | docker exec -i', block)
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        for leak in ('-e TOKEN=', '-e CF_TOKEN=', '-e NETLIFY_AUTH_TOKEN=', '-e CLOUDFLARE_API_TOKEN='):
            self.assertNotIn(leak, text)


if __name__ == "__main__":
    unittest.main()

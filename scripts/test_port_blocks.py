#!/usr/bin/env python3
"""
Every launcher finds this folder's preview ports the same way: walking upward
through forty blocks, skipping any block something on the Mac is listening on
or another working folder's workspace holds — and when there is no room, it
says so truthfully (GitHub #280).

The rule is data: `contracts/app-rules.json` -> `previewPorts` (the walk's
cases, the ceiling, the words a clash is recognised by, and the sentence).
This file runs that data against the REAL code.

**How this runs the real thing without Docker.** The PREVIEW PORT BLOCK and
the CONTAINER MOUNT BLOCK are cut out of each launcher by their markers, and
each launcher's own `run_container_with_mount` by name — not retyped — and run
under `/bin/bash` (3.2 on a Mac, the one a teacher's launchers run under) with
`set -euo pipefail`. `lsof` and `docker` are small pretend programs put first
on PATH, answering from files in a scratch folder and writing down every
question they were asked. Nothing is started, nothing is published, and the
trail written is a scratch folder's.

**Windows.** The parts that need bash are skipped where there is no bash that
can run a program, the same rule as the launcher tests beside this one. The
`build_site.py` half runs everywhere: its walk is the one Windows' native
preview uses.

Pure stdlib. Run with:

    python3 scripts/test_port_blocks.py
"""

import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT

LAUNCHERS = ["setup.sh", "preview.sh", "deploy.sh"]
BLOCK_START = "# >>> PREVIEW PORT BLOCK >>>"
BLOCK_END = "# <<< PREVIEW PORT BLOCK <<<"
MOUNT_START = "# >>> CONTAINER MOUNT BLOCK >>>"
MOUNT_END = "# <<< CONTAINER MOUNT BLOCK <<<"
CONTAINER = "teaching-quartz-0000abcd"

# Bash 3.2 is what /bin/bash is on every Mac, and what the launchers' shebangs
# reach. A test run under a newer bash would pass code 3.2 cannot run.
BASH = "/bin/bash" if Path("/bin/bash").exists() else "bash"


def the_rules() -> dict:
    return json.loads((REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8"))["previewPorts"]


def the_trail_line() -> str:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    for entry in rules["activityTrail"]["mustRecord"]:
        if entry["event"] == "preview did not appear":
            return entry["launcherLineWhenEveryAddressIsTaken"]
    raise AssertionError("the contract no longer has a 'preview did not appear' event")


def launcher_text(launcher: str) -> str:
    return (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")


def between(text: str, start: str, end: str) -> str:
    begin = text.find(start)
    finish = text.find(end)
    if begin < 0 or finish < 0:
        raise AssertionError(f"markers {start!r} … {end!r} are missing")
    return text[begin:finish + len(end)] + "\n"


def function_named(text: str, name: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}\n", text, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        raise AssertionError(f"no function called {name}")
    return match.group(0)


def block_ports(base: int) -> list:
    ports = []
    for offset in range(4):
        ports.append(base + offset)
        ports.append(base + 1000 + offset)
    return ports


# ---- The pretend programs ---------------------------------------------
# Written in bash so they run wherever the launchers' code runs. Each answers
# from a file in $FAKE and appends what it was asked to $FAKE/calls.
FAKE_LSOF = r"""#!/bin/bash
echo "lsof $*" >> "$FAKE/calls"
if [ -f "$FAKE/lsof_fails" ]; then
  echo "lsof: something went wrong" >&2
  exit 1
fi
cat "$FAKE/listening" 2>/dev/null
exit 0
"""

FAKE_DOCKER = r"""#!/bin/bash
echo "docker $*" >> "$FAKE/calls"
case "$1" in
  ps)
    if [ "${2:-}" = "-a" ]; then cat "$FAKE/workspaces" 2>/dev/null; else cat "$FAKE/running" 2>/dev/null; fi
    exit 0 ;;
  inspect)
    shift 3
    for name in "$@"; do
      if [ -f "$FAKE/ports_$name" ]; then printf '%s \n' "$(cat "$FAKE/ports_$name")"; fi
    done
    exit 0 ;;
  run)
    n=$(cat "$FAKE/runs" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE/runs"
    answer=$(sed -n "${n}p" "$FAKE/run_answers" 2>/dev/null)
    if [ -z "$answer" ] || [ "$answer" = "ok" ]; then echo "0123456789abcdef"; exit 0; fi
    echo "$answer" >&2
    exit 125 ;;
  rm)
    if [ -f "$FAKE/rm_refuses" ]; then echo "Error: container is running" >&2; exit 1; fi
    exit 0 ;;
  start)
    answer=$(cat "$FAKE/start_answer" 2>/dev/null)
    if [ -z "$answer" ] || [ "$answer" = "ok" ]; then echo "$2"; exit 0; fi
    echo "$answer" >&2
    exit 1 ;;
esac
echo "unexpected docker $*" >&2
exit 99
"""


class PretendMac:
    """A scratch folder holding the pretend programs and what they answer."""

    def __init__(self, scratch: Path, with_lsof: bool = True):
        self.scratch = scratch
        self.fake = scratch / "fake"
        self.bin = scratch / "bin"
        self.home = scratch / "home"
        self.courses = scratch / "work" / "courses"
        for folder in (self.fake, self.bin, self.home, self.courses):
            folder.mkdir(parents=True, exist_ok=True)
        programs = {"docker": FAKE_DOCKER}
        if with_lsof:
            programs["lsof"] = FAKE_LSOF
        for name, body in programs.items():
            path = self.bin / name
            path.write_text(body, encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def listening(self, ports: list) -> None:
        # The three shapes lsof really writes, plus the process and file lines
        # that come between them.
        lines = ["p1105", "f15"]
        shapes = ["n*:{}", "n127.0.0.1:{}", "n[::1]:{}"]
        index = 0
        for port in ports:
            lines.append(shapes[index % 3].format(port))
            index += 1
        (self.fake / "listening").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def workspaces(self, holding: dict, running: list = None) -> None:
        """holding: {name: [ports]} — every workspace, stopped ones included."""
        (self.fake / "workspaces").write_text("".join(name + "\n" for name in holding), encoding="utf-8")
        for name, ports in holding.items():
            (self.fake / ("ports_" + name)).write_text(" ".join(str(p) for p in ports), encoding="utf-8")
        (self.fake / "running").write_text("".join(name + "\n" for name in (running or [])), encoding="utf-8")

    def run_answers(self, answers: list) -> None:
        (self.fake / "run_answers").write_text("\n".join(answers) + "\n", encoding="utf-8")

    def calls(self) -> list:
        path = self.fake / "calls"
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []

    def trail(self) -> list:
        path = self.home / "Library" / "Logs" / "Plantoir" / "activity.txt"
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []

    def run(self, launcher: str, action: str) -> subprocess.CompletedProcess:
        text = launcher_text(launcher)
        place = ""
        for line in text.splitlines():
            if line.startswith("WORKSPACE_TRAIL_PLACE="):
                place = line
        program = "\n".join([
            "set -euo pipefail",
            'COURSE="ICS4U"; SECTION="2"; COURSE_CODE="ICS4U"; SECTION_NUM="2"',
            'CONTAINER_NAME="' + CONTAINER + '"',
            'HOST_COURSES="' + str(self.courses) + '"',
            'BUILD_ROOT="' + str(self.scratch / "builds") + '"',
            'IMAGE="teaching-quartz:src-test"',
            function_named(text, "note_on_the_trail"),
            between(text, MOUNT_START, MOUNT_END),
            between(text, BLOCK_START, BLOCK_END),
            place,
            "ensure_build_root() { :; }",
            "retire_legacy_container() { :; }",
            "ensure_image_present() { :; }",
            function_named(text, "run_container_with_mount"),
            action,
        ]) + "\n"
        environment = {
            "HOME": str(self.home),
            "FAKE": str(self.fake),
            # /usr/sbin (where the real lsof lives) is deliberately absent.
            "PATH": str(self.bin) + ":/usr/bin:/bin",
        }
        return subprocess.run([BASH, "-c", program], capture_output=True, timeout=60, env=environment)


def output_of(result: subprocess.CompletedProcess) -> str:
    return result.stdout.decode("utf-8", "replace") + result.stderr.decode("utf-8", "replace")


def published_bases(calls: list) -> list:
    bases = []
    for call in calls:
        if call.startswith("docker run "):
            match = re.search(r"-p (\d+)-(\d+):8081-8084 -p (\d+)-(\d+):9081-9084", call)
            if match is None:
                raise AssertionError("a workspace was made without the eight addresses: " + call)
            bases.append(int(match.group(1)))
    return bases


def stopped_workspaces_of(case: dict) -> dict:
    """The case's stoppedBlocks, as stopped workspaces of other folders."""
    holding = {}
    for base in case.get("stoppedBlocks", []):
        holding[f"teaching-quartz-5{base:07x}"] = block_ports(base)
    return holding


def busy_ports_of(case: dict) -> list:
    ports = []
    for base in case.get("busyBlocks", []):
        ports.extend(block_ports(base))
    ports.extend(case.get("busyPorts", []))
    return ports


# ======================================================================
# Text: the three launchers carry one rule, and use it.
# ======================================================================
class TheThreeLaunchersCarryOneWalk(unittest.TestCase):

    def test_the_block_is_the_same_in_all_three(self):
        first = between(launcher_text("setup.sh"), BLOCK_START, BLOCK_END)
        for launcher in ["preview.sh", "deploy.sh"]:
            self.assertEqual(first, between(launcher_text(launcher), BLOCK_START, BLOCK_END),
                             f"{launcher}'s PREVIEW PORT BLOCK has drifted from setup.sh's")

    def test_every_workspace_is_made_by_the_block(self):
        """The same two folders and the same eight addresses in all three:
        each launcher's own function hands the making to the shared one and
        makes nothing itself."""
        for launcher in LAUNCHERS:
            body = function_named(launcher_text(launcher), "run_container_with_mount")
            self.assertIn("\n  create_the_workspace_on_free_ports\n}", body, launcher)
            self.assertNotIn("docker run", body, launcher)
            self.assertEqual(launcher_text(launcher).count("docker run -dit"), 1,
                             f"{launcher} makes a workspace somewhere other than the block")

    def test_a_stopped_workspace_is_started_by_the_block(self):
        for launcher in LAUNCHERS:
            text = launcher_text(launcher)
            outside = text.replace(between(text, BLOCK_START, BLOCK_END), "")
            self.assertNotRegex(outside, r'docker start "\$CONTAINER_NAME"',
                                f"{launcher} starts its workspace without the block's port check")
            self.assertIn("start_the_existing_workspace\n", outside, launcher)

    def test_nothing_in_the_block_is_removed_by_force(self):
        """-f is what would kill a workspace another launcher made a moment
        ago under the same name, mid-publish."""
        block = between(launcher_text("setup.sh"), BLOCK_START, BLOCK_END)
        self.assertNotRegex(block, r"docker rm -f")

    def test_the_numbers_are_the_contracts(self):
        rules = the_rules()
        block = between(launcher_text("setup.sh"), BLOCK_START, BLOCK_END)
        self.assertIn(f"\nFIRST_HOST_BLOCK={rules['firstHostBlock'][0]}\n", block)
        self.assertIn(f"\nHOST_BLOCK_STEP={rules['hostBlockStep']}\n", block)
        self.assertIn(f"\nHOST_BLOCK_COUNT={rules['hostBlockCount']}\n", block)

    def test_every_clash_wording_is_recognised(self):
        block = between(launcher_text("setup.sh"), BLOCK_START, BLOCK_END)
        recogniser = function_named(block, "it_was_a_port_clash")
        for words in the_rules()["hostBlockClash"]["words"]:
            self.assertIn(f'*"{words}"*', recogniser)

    def test_preview_and_publish_file_the_refusal_under_their_section(self):
        self.assertIn('\nWORKSPACE_TRAIL_PLACE="${COURSE}/${SECTION}"\n', launcher_text("preview.sh"))
        self.assertIn('\nWORKSPACE_TRAIL_PLACE="${COURSE_CODE}/${SECTION_NUM}"\n', launcher_text("deploy.sh"))
        self.assertNotIn("WORKSPACE_TRAIL_PLACE=", launcher_text("setup.sh"))

    def test_the_console_lines_are_the_contracts(self):
        """previewPorts.hostBlockClash.says…: named by key, never retyped."""
        block = between(launcher_text("setup.sh"), BLOCK_START, BLOCK_END)
        clash = the_rules()["hostBlockClash"]
        lines = [clash["saysWhenCreationClashes"], clash["saysWhenAStartIsRefused"]]
        lines.extend(clash["saysWhenAStoppedWorkspaceIsRemade"])
        for line in lines:
            self.assertIn(f'echo "{line}"', block)

    def test_the_sentence_names_no_machinery(self):
        """Rule 1, and the old sentence's fault: it said "ports"."""
        for line in the_rules()["whenNoBlockIsFree"]["sentence"]:
            words = set(re.findall(r"[a-z]+", line.lower()))
            for forbidden in ["docker", "container", "port", "ports", "toolchain", "script", "localhost", "lsof"]:
                self.assertNotIn(forbidden, words, line)


# ======================================================================
# Behaviour: the real code, against a pretend Mac.
# ======================================================================
@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class TheWalk(unittest.TestCase):

    def walk(self, launcher: str, listening: list = None, holding: dict = None, with_lsof: bool = True,
             lsof_fails: bool = False) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            mac = PretendMac(Path(scratch), with_lsof=with_lsof)
            mac.listening(listening or [])
            mac.workspaces(holding or {})
            if lsof_fails:
                (mac.fake / "lsof_fails").write_text("", encoding="utf-8")
            result = mac.run(launcher, "run_container_with_mount")
            return result, published_bases(mac.calls()), mac.trail(), mac.calls()

    def test_the_contract_cases_with_other_apps_listening(self):
        for case in the_rules()["hostBlockCases"]:
            for launcher in LAUNCHERS:
                with self.subTest(case=case["name"], launcher=launcher):
                    result, bases, _, _ = self.walk(launcher, listening=busy_ports_of(case),
                                                    holding=stopped_workspaces_of(case))
                    if case["expect"] is None:
                        self.assertEqual(result.returncode, 1, output_of(result))
                        self.assertEqual(bases, [], "a workspace was made with nowhere free")
                    else:
                        self.assertEqual(result.returncode, 0, output_of(result))
                        self.assertEqual(bases, [case["expect"]], output_of(result))

    def test_the_contract_cases_with_other_workspaces_holding_the_blocks(self):
        """The same cases with the busy blocks held by other working folders'
        RUNNING workspaces that the listing does not show (lsof blind to
        them, as it is to a root-owned forwarder) — so it is the workspace
        count alone that skips them. stoppedBlocks are stopped workspaces, as
        in every case."""
        for case in the_rules()["hostBlockCases"]:
            holding = stopped_workspaces_of(case)
            running = []
            for base in case.get("busyBlocks", []):
                name = f"teaching-quartz-{base:08x}"
                holding[name] = block_ports(base)
                running.append(name)
            for launcher in LAUNCHERS:
                with self.subTest(case=case["name"], launcher=launcher):
                    with tempfile.TemporaryDirectory() as scratch:
                        mac = PretendMac(Path(scratch))
                        mac.listening(case.get("busyPorts", []))
                        mac.workspaces(holding, running)
                        result = mac.run(launcher, "run_container_with_mount")
                        bases = published_bases(mac.calls())
                    if case["expect"] is None:
                        self.assertEqual(result.returncode, 1, output_of(result))
                        self.assertEqual(bases, [])
                    else:
                        self.assertEqual(result.returncode, 0, output_of(result))
                        self.assertEqual(bases, [case["expect"]], output_of(result))

    def test_a_block_held_only_by_a_stopped_workspace_is_skipped(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, bases, _, _ = self.walk(
                    launcher, holding={"teaching-quartz-deadbeef": block_ports(8081)})
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(bases, [8091])

    def test_this_folders_own_workspace_is_not_counted_against_it(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, bases, _, _ = self.walk(launcher, holding={CONTAINER: block_ports(8081)})
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(bases, [8081])

    def test_one_listing_is_asked_for_not_one_per_port(self):
        """0.12 s against 9.8 s for forty blocks, measured."""
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                _, bases, _, calls = self.walk(launcher, listening=busy_ports_of({"busyBlocks": [8081, 8091, 8101]}))
                self.assertEqual(bases, [8111])
                asked = [call for call in calls if call.startswith("lsof ")]
                self.assertEqual(asked, ["lsof -nP -iTCP -sTCP:LISTEN -Fn"])
                inspected = [call for call in calls if call.startswith("docker inspect")]
                self.assertLessEqual(len(inspected), 1)

    def test_no_lsof_at_all_takes_the_first_block(self):
        """Unchanged from the old probe, and pinned so nobody changes it
        quietly: a listing that cannot be read counts as nothing listening."""
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, bases, _, _ = self.walk(launcher, with_lsof=False)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(bases, [8081])
                result, bases, _, _ = self.walk(launcher, lsof_fails=True)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(bases, [8081])

    def test_with_no_lsof_the_other_workspaces_are_still_skipped(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, bases, _, _ = self.walk(
                    launcher, with_lsof=False, holding={"teaching-quartz-deadbeef": block_ports(8081)})
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(bases, [8091])

    def test_when_every_block_is_taken_the_sentence_is_said_and_written_down(self):
        rules = the_rules()["whenNoBlockIsFree"]
        every_block = busy_ports_of({"busyBlocks": list(range(8081, 8481, 10))})
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, bases, trail, _ = self.walk(launcher, listening=every_block)
                self.assertEqual(result.returncode, rules["exitCode"], output_of(result))
                self.assertEqual(bases, [], "docker run was called with nowhere free")
                lines = result.stdout.decode("utf-8").splitlines()
                said = []
                started = False
                for line in lines:
                    if line.startswith("❌"):
                        started = True
                    if started:
                        said.append(line.replace("❌", "").strip())
                self.assertEqual(said, rules["sentence"], output_of(result))
                place = "setup" if launcher == "setup.sh" else "ICS4U/2"
                expected = the_trail_line().replace("{course}/{section}", place)
                self.assertEqual(len(trail), 1, trail)
                self.assertTrue(trail[0].endswith(" · " + expected), trail)

    def test_a_walk_that_finds_a_high_block_writes_nothing_on_the_trail(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                _, bases, trail, _ = self.walk(launcher, listening=busy_ports_of({"busyBlocks": [8081, 8091]}))
                self.assertEqual(bases, [8101])
                self.assertEqual(trail, [])


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class AClashAtTheMomentOfMaking(unittest.TestCase):

    def make(self, launcher: str, answers: list) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            mac = PretendMac(Path(scratch))
            mac.listening([])
            mac.workspaces({})
            mac.run_answers(answers)
            result = mac.run(launcher, "run_container_with_mount")
            return result, mac.calls()

    def test_each_clash_wording_walks_on_to_the_next_block(self):
        wordings = {
            "port is already allocated": "Error response from daemon: driver failed programming external connectivity on endpoint x: Bind for 0.0.0.0:8081 failed: port is already allocated",
            "Ports are not available": "Error response from daemon: Ports are not available: exposing port TCP 0.0.0.0:8081 -> 0.0.0.0:0: listen tcp 0.0.0.0:8081: bind: address already in use",
            "address already in use": "Error response from daemon: failed to set up container networking: listen tcp4 0.0.0.0:8081: bind: address already in use",
        }
        self.assertEqual(sorted(wordings), sorted(the_rules()["hostBlockClash"]["words"]))
        for words, refusal in wordings.items():
            for launcher in LAUNCHERS:
                with self.subTest(words=words, launcher=launcher):
                    result, calls = self.make(launcher, [refusal, "ok"])
                    self.assertEqual(result.returncode, 0, output_of(result))
                    self.assertEqual(published_bases(calls), [8081, 8091])
                    first_run = calls.index(next(c for c in calls if c.startswith("docker run ")))
                    between_runs = calls[first_run + 1:]
                    removed = [c for c in between_runs if c.startswith("docker rm")]
                    self.assertEqual(removed, ["docker rm " + CONTAINER], "the half-made one, without force")

    def test_any_other_refusal_is_not_retried(self):
        refusal = "Error response from daemon: invalid mount config for type \"bind\": bind source path does not exist: /Volumes/X"
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.make(launcher, [refusal, "ok"])
                self.assertEqual(result.returncode, 1, output_of(result))
                self.assertEqual(published_bases(calls), [8081])
                self.assertEqual([c for c in calls if c.startswith("docker rm")], [])
                # The engine's words stay on screen: the app's failure
                # explanations are matched against them.
                self.assertIn("bind source path does not exist", output_of(result))
                self.assertIn("inside your home folder", output_of(result))

    def test_clashes_all_the_way_up_end_at_the_ceiling(self):
        clash = "Bind for 0.0.0.0:1 failed: port is already allocated"
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.make(launcher, [clash] * 45)
                self.assertEqual(result.returncode, 1, output_of(result))
                self.assertEqual(published_bases(calls), list(range(8081, 8481, 10)))
                self.assertIn(the_rules()["whenNoBlockIsFree"]["sentence"][0], output_of(result))


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class AStoppedWorkspaceThatCannotStart(unittest.TestCase):

    def start(self, launcher: str, answer: str, rm_refuses: bool = False, running: list = None) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            mac = PretendMac(Path(scratch))
            mac.listening(block_ports(8081))
            mac.workspaces({CONTAINER: block_ports(8081)}, running)
            (mac.fake / "start_answer").write_text(answer, encoding="utf-8")
            if rm_refuses:
                (mac.fake / "rm_refuses").write_text("", encoding="utf-8")
            result = mac.run(launcher, 'start_the_existing_workspace; echo "CARRIED ON"')
            return result, mac.calls()

    def test_a_start_that_works_changes_nothing(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.start(launcher, "ok")
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertIn("CARRIED ON", output_of(result))
                self.assertEqual([c for c in calls if c.startswith("docker rm") or c.startswith("docker run")], [])

    def test_a_block_taken_while_it_was_stopped_is_made_again_on_free_ports(self):
        refusal = "Error response from daemon: driver failed programming external connectivity on endpoint teaching-quartz-0000abcd: Bind for 0.0.0.0:8081 failed: port is already allocated"
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.start(launcher, refusal)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertIn("CARRIED ON", output_of(result))
                self.assertIn("slower", output_of(result), "the console must say what it costs")
                self.assertEqual([c for c in calls if c.startswith("docker rm")], ["docker rm " + CONTAINER])
                self.assertEqual(published_bases(calls), [8091])

    def test_any_other_refusal_stops_with_the_engines_words(self):
        """setup.sh and deploy.sh used to end here under `set -e` with only
        the engine's words; preview.sh carried on past it."""
        refusal = "Error response from daemon: something else entirely"
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.start(launcher, refusal)
                self.assertEqual(result.returncode, 1, output_of(result))
                self.assertNotIn("CARRIED ON", output_of(result))
                self.assertIn("something else entirely", output_of(result))
                self.assertEqual([c for c in calls if c.startswith("docker rm") or c.startswith("docker run")], [])

    def test_a_workspace_another_launcher_already_started_is_used_as_it_is(self):
        refusal = "Bind for 0.0.0.0:8081 failed: port is already allocated"
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.start(launcher, refusal, rm_refuses=True, running=[CONTAINER])
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertIn("CARRIED ON", output_of(result))
                self.assertEqual(published_bases(calls), [])


# ======================================================================
# build_site.py's own walk, which Windows' native preview runs moments
# before it binds. No bash needed: this half runs everywhere.
# ======================================================================
class TheBuildersOwnWalk(unittest.TestCase):

    def setUp(self):
        sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))
        import build_site
        self.build_site = build_site

    def test_forty_blocks_like_the_launchers(self):
        self.assertEqual(self.build_site.PREVIEW_HOST_BLOCK_COUNT, the_rules()["hostBlockCount"])
        self.assertEqual(self.build_site.PREVIEW_HOST_BLOCK_STEP, the_rules()["hostBlockStep"])

    def test_the_contract_cases_made_of_whole_blocks(self):
        """Only the cases made of WHOLE blocks: a native preview binds one
        site port and its websocket, not a block of four, so a single busy
        port elsewhere in a block does not move it (next test)."""
        for case in the_rules()["hostBlockCases"]:
            if case.get("busyPorts") or case.get("stoppedBlocks"):
                continue
            busy = set(busy_ports_of(case))

            def is_free(port: int) -> bool:
                return port not in busy

            with self.subTest(case=case["name"]):
                expected = case["expect"] if case["expect"] is not None else 8081
                self.assertEqual(self.build_site.first_free_preview_port(8081, is_free), expected)

    def test_it_needs_only_its_own_port_and_websocket(self):
        busy = {8083, 9082}

        def is_free(port: int) -> bool:
            return port not in busy

        self.assertEqual(self.build_site.first_free_preview_port(8081, is_free), 8081)
        busy.add(9081)
        self.assertEqual(self.build_site.first_free_preview_port(8081, is_free), 8091)

    def test_the_ceiling_is_counted_from_the_port_asked_for(self):
        """The port asked for can be any of 8081-8084; forty blocks from 8083
        end at 8473, not at 8471."""
        busy = set()
        for base in range(8083, 8473, 10):
            busy.add(base)

        def is_free(port: int) -> bool:
            return port not in busy

        self.assertEqual(self.build_site.first_free_preview_port(8083, is_free), 8473)
        busy.add(8473)
        self.assertEqual(self.build_site.first_free_preview_port(8083, is_free), 8083)


if __name__ == "__main__":
    unittest.main(verbosity=2)

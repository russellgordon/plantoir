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
`set -euo pipefail`. `lsof`, `netstat` and `docker` are small pretend programs
put first on PATH, answering from files in a scratch folder and writing down
every question they were asked. One test (`TheRealListings`) runs the two
listing functions against THIS Mac's real `netstat` and `lsof`, because every
other test here would pass against a parse that the real kernel's output
defeats (GitHub #310). Nothing is started, nothing is published, and the
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

# The kernel's list, as `netstat -an -p tcp` prints it: a heading, then one
# row per socket. $FAKE/kernel holds the rows; the heading's last word is
# "(state)", so it never reads as LISTEN.
FAKE_NETSTAT = r"""#!/bin/bash
echo "netstat $*" >> "$FAKE/calls"
if [ -f "$FAKE/netstat_fails" ]; then
  echo "netstat: sysctl: net.inet.tcp.pcblist_n: Operation not permitted" >&2
  exit 1
fi
echo "Active Internet connections (including servers)"
echo "Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)"
cat "$FAKE/kernel" 2>/dev/null
exit 0
"""

FAKE_DOCKER = r"""#!/bin/bash
echo "docker $*" >> "$FAKE/calls"
case "$1" in
  context)
    cat "$FAKE/context" 2>/dev/null || echo "colima"
    exit 0 ;;
  port)
    if [ -f "$FAKE/remade" ]; then echo "0.0.0.0:$(cat "$FAKE/port_after")"; else echo "0.0.0.0:$(cat "$FAKE/port" 2>/dev/null || echo 8081)"; fi
    exit 0 ;;
  ps)
    if [ "${2:-}" = "-a" ]; then cat "$FAKE/workspaces" 2>/dev/null; else cat "$FAKE/running" 2>/dev/null; fi
    exit 0 ;;
  inspect)
    template="${3:-}"
    case "$template" in
      "{{.Id}}")
        # $FAKE/ids holds "name id" for every workspace that exists.
        line=$(awk -v x="$4" '$1 == x || $2 == x { print $2; exit }' "$FAKE/ids" 2>/dev/null)
        if [ -z "$line" ]; then echo "Error: No such object: $4" >&2; exit 1; fi
        echo "$line"; exit 0 ;;
      "{{.State.Running}} {{.State.Pid}}")
        line=$(awk -v x="$4" '$1 == x || $2 == x { print $2; exit }' "$FAKE/ids" 2>/dev/null)
        if [ -z "$line" ]; then echo "Error: No such object: $4" >&2; exit 1; fi
        cat "$FAKE/state" 2>/dev/null || echo "true 100"
        exit 0 ;;
    esac
    shift 3
    for name in "$@"; do
      if [ -f "$FAKE/ports_$name" ]; then printf '%s \n' "$(cat "$FAKE/ports_$name")"; fi
    done
    exit 0 ;;
  top)
    # The Nth look answers from $FAKE/top_N; the last one given repeats.
    n=$(cat "$FAKE/tops" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE/tops"
    if [ -f "$FAKE/top_fails" ]; then echo "Error: container is not running" >&2; exit 1; fi
    while [ "$n" -gt 1 ] && [ ! -f "$FAKE/top_$n" ]; do n=$((n - 1)); done
    echo "UID PID PPID C STIME TTY TIME CMD"
    cat "$FAKE/top_$n" 2>/dev/null
    exit 0 ;;
  stop)
    exit 0 ;;
  run)
    touch "$FAKE/remade"
    n=$(cat "$FAKE/runs" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE/runs"
    answer=$(sed -n "${n}p" "$FAKE/run_answers" 2>/dev/null)
    if [ -z "$answer" ] || [ "$answer" = "ok" ]; then echo "0123456789abcdef"; exit 0; fi
    echo "$answer" >&2
    exit 125 ;;
  rm)
    if [ -f "$FAKE/rm_refuses" ]; then echo "Error: container is running" >&2; exit 1; fi
    if [ -f "$FAKE/rm_gone" ]; then
      # Another launcher removed it a moment before this one could.
      awk -v x="$2" '$1 != x && $2 != x' "$FAKE/ids" > "$FAKE/ids.next" 2>/dev/null; mv "$FAKE/ids.next" "$FAKE/ids"
      echo "Error response from daemon: No such container: $2" >&2; exit 1
    fi
    if [ -f "$FAKE/ids" ]; then
      awk -v x="$2" '$1 != x && $2 != x' "$FAKE/ids" > "$FAKE/ids.next"; mv "$FAKE/ids.next" "$FAKE/ids"
    fi
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


# The Mac's process table, as `ps -Ao pid=,ppid=,args=` prints it: whatever
# $FAKE/ps holds, and — so that a run leaving ITSELF out is tested for real —
# a line for the program that asked, with the words it was run with.
FAKE_PS = r"""#!/bin/bash
echo "ps $*" >> "$FAKE/calls"
if [ -f "$FAKE/ps_fails" ]; then exit 1; fi
if [ -f "$FAKE/ps_self" ]; then
  echo "$PPID $(/bin/ps -o ppid= -p "$PPID" | tr -d ' ') $(cat "$FAKE/ps_self")"
fi
cat "$FAKE/ps" 2>/dev/null
exit 0
"""

# Returns at once and writes down how long it was asked for, so a ten-minute
# wait runs in a moment and can be counted.
FAKE_SLEEP = r"""#!/bin/bash
echo "sleep $*" >> "$FAKE/calls"
exit 0
"""

# A connection to a forwarded port with nothing served inside yet: an empty
# reply, curl's exit 52 (#234's healthy answer).
FAKE_CURL = r"""#!/bin/bash
echo "curl $*" >> "$FAKE/calls"
exit 52
"""


class PretendMac:
    """A scratch folder holding the pretend programs and what they answer."""

    def __init__(self, scratch: Path, with_lsof: bool = True, with_netstat: bool = True):
        self.scratch = scratch
        self.fake = scratch / "fake"
        self.bin = scratch / "bin"
        self.home = scratch / "home"
        self.courses = scratch / "work" / "courses"
        for folder in (self.fake, self.bin, self.home, self.courses):
            folder.mkdir(parents=True, exist_ok=True)
        programs = {"docker": FAKE_DOCKER, "ps": FAKE_PS, "sleep": FAKE_SLEEP, "curl": FAKE_CURL}
        if with_lsof:
            programs["lsof"] = FAKE_LSOF
        if with_netstat:
            programs["netstat"] = FAKE_NETSTAT
        for name, body in programs.items():
            path = self.bin / name
            path.write_text(body, encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IEXEC)
        self.own_ports = []
        self.others_ports = []
        self.other_rows = []

    def listening(self, ports: list) -> None:
        """Listening in THIS account: both lists show them."""
        self.own_ports = list(ports)
        # The three shapes lsof really writes, plus the process and file lines
        # that come between them.
        lines = ["p1105", "f15"]
        shapes = ["n*:{}", "n127.0.0.1:{}", "n[::1]:{}"]
        index = 0
        for port in ports:
            lines.append(shapes[index % 3].format(port))
            index += 1
        (self.fake / "listening").write_text("\n".join(lines) + "\n", encoding="utf-8")
        self.write_the_kernels_list()

    def listening_in_another_account(self, ports: list) -> None:
        """Listening in another account, or as root: only the kernel's list."""
        self.others_ports = list(ports)
        self.write_the_kernels_list()

    def not_listening(self, rows: list) -> None:
        """Sockets on these ports in a state other than LISTEN."""
        self.other_rows = list(rows)
        self.write_the_kernels_list()

    def write_the_kernels_list(self) -> None:
        # The shapes netstat really writes: tcp4 and tcp6 and tcp46, a
        # wildcard, a specific IPv4 address, ::1, and a long IPv6 address cut
        # short with its port kept (measured on macOS 26).
        shapes = [
            "tcp4       0      0  *.{}                 *.*                    LISTEN",
            "tcp4       0      0  127.0.0.1.{}         *.*                    LISTEN",
            "tcp6       0      0  ::1.{}               *.*                    LISTEN",
            "tcp46      0      0  *.{}                 *.*                    LISTEN",
            "tcp6       0      0  fd35:5143:77cb:4.{}  *.*                    LISTEN",
        ]
        lines = ["tcp4       0      0  192.168.1.20.51234     17.253.144.10.443      ESTABLISHED"]
        index = 0
        for port in self.own_ports + self.others_ports:
            lines.append(shapes[index % len(shapes)].format(port))
            index += 1
        for row in self.other_rows:
            lines.append(f"tcp4       0      0  127.0.0.1.{row['port']}         127.0.0.1.52011        {row['state']}")
        (self.fake / "kernel").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def flag(self, name: str, text: str = "") -> None:
        (self.fake / name).write_text(text, encoding="utf-8")

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

    def run(self, launcher: str, action: str, serving: bool = False,
            docker_host: str = None, colima_home: str = None) -> subprocess.CompletedProcess:
        """`serving` sets WORKSPACE_WILL_SERVE the way preview.sh does for a
        preview (never for setup.sh, deploy.sh or a build for publishing)."""
        text = launcher_text(launcher)
        place = ""
        for line in text.splitlines():
            if line.startswith("WORKSPACE_TRAIL_PLACE="):
                place = line
        program = "\n".join([
            "set -euo pipefail",
            'WORKSPACE_WILL_SERVE="' + ("yes" if serving else "") + '"',
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
            "ensure_image_present() { :; }",
            function_named(text, "run_container_with_mount"),
            action,
        ]) + "\n"
        environment = {
            "HOME": str(self.home),
            "FAKE": str(self.fake),
            # /usr/sbin (where the real lsof and netstat live) is deliberately
            # absent, so neither real program can leak in.
            "PATH": str(self.bin) + ":/usr/bin:/bin",
        }
        if docker_host is not None:
            environment["DOCKER_HOST"] = docker_host
        if colima_home is not None:
            environment["COLIMA_HOME"] = colima_home
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


def this_accounts_ports_of(case: dict) -> list:
    """busyBlocks and busyPorts: listening in THIS account."""
    ports = []
    for base in case.get("busyBlocks", []):
        ports.extend(block_ports(base))
    ports.extend(case.get("busyPorts", []))
    return ports


def another_accounts_ports_of(case: dict) -> list:
    """anotherAccountBlocks and anotherAccountPorts: only the kernel's list."""
    ports = []
    for base in case.get("anotherAccountBlocks", []):
        ports.extend(block_ports(base))
    ports.extend(case.get("anotherAccountPorts", []))
    return ports


def busy_ports_of(case: dict) -> list:
    """Every port the case says something is LISTENING on, in any account:
    a port is busy whoever holds it (the native walk's reading)."""
    return this_accounts_ports_of(case) + another_accounts_ports_of(case)


def lay_out_the_listings(mac: "PretendMac", case: dict, own_ports: list) -> None:
    """The case's listening fields, onto a pretend Mac's two lists."""
    mac.listening(own_ports)
    mac.listening_in_another_account(another_accounts_ports_of(case))
    mac.not_listening(case.get("notListening", []))
    if case.get("kernelListFails"):
        mac.flag("netstat_fails")
    if case.get("accountListFails"):
        mac.flag("lsof_fails")


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

    def test_each_listing_fails_open_on_its_own(self):
        """Each half carries its own `|| true`, so one list failing never
        takes the other's answer with it. (Behaviourally the lsof half's is
        what a failing netstat hides behind too, so the text is pinned.)"""
        block = between(launcher_text("setup.sh"), BLOCK_START, BLOCK_END)
        every = function_named(block, "ports_listening_in_every_account")
        this = function_named(block, "ports_listening_in_this_account")
        self.assertIn("{ netstat -an -p tcp 2>/dev/null || true; }", every)
        self.assertIn("{ lsof -nP -iTCP -sTCP:LISTEN -Fn 2>/dev/null || true; }", this)
        both = function_named(block, "listening_ports_on_this_mac")
        self.assertIn("\n  ports_listening_in_every_account\n  ports_listening_in_this_account\n", both)

    def test_only_a_serving_run_looks_before_a_start(self):
        """(B) is switched on by a variable only preview.sh sets, so the block
        stays the same text in all three launchers (#280) while setup.sh and
        deploy.sh keep their warm builder."""
        self.assertIn('\nWORKSPACE_WILL_SERVE=""\nif [[ -z "$BUILD_ONLY" ]]; then\n  WORKSPACE_WILL_SERVE="yes"\nfi\n',
                      launcher_text("preview.sh"))
        for launcher in ["setup.sh", "deploy.sh"]:
            text = launcher_text(launcher)
            outside = text.replace(between(text, BLOCK_START, BLOCK_END), "")
            self.assertNotIn("WORKSPACE_WILL_SERVE", outside, launcher)

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
             lsof_fails: bool = False, case: dict = None, with_netstat: bool = True,
             netstat_fails: bool = False, elsewhere: list = None) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            mac = PretendMac(Path(scratch), with_lsof=with_lsof, with_netstat=with_netstat)
            lay_out_the_listings(mac, case or {}, listening or [])
            if elsewhere:
                mac.listening_in_another_account(elsewhere)
            mac.workspaces(holding or {})
            if lsof_fails:
                mac.flag("lsof_fails")
            if netstat_fails:
                mac.flag("netstat_fails")
            result = mac.run(launcher, "run_container_with_mount")
            return result, published_bases(mac.calls()), mac.trail(), mac.calls()

    def test_the_contract_cases_with_other_apps_listening(self):
        for case in the_rules()["hostBlockCases"]:
            for launcher in LAUNCHERS:
                with self.subTest(case=case["name"], launcher=launcher):
                    result, bases, _, _ = self.walk(launcher, listening=this_accounts_ports_of(case),
                                                    holding=stopped_workspaces_of(case), case=case)
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
                        lay_out_the_listings(mac, case, case.get("busyPorts", []))
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
        """ONE of each list, for all forty blocks: 0.01 s and 0.12 s, against
        9.8 s for the old one-question-per-port probe (measured)."""
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                _, bases, _, calls = self.walk(launcher, listening=busy_ports_of({"busyBlocks": [8081, 8091]}),
                                               elsewhere=block_ports(8101))
                self.assertEqual(bases, [8111])
                asked = [call for call in calls if call.startswith("lsof ") or call.startswith("netstat ")]
                self.assertEqual(sorted(asked), ["lsof -nP -iTCP -sTCP:LISTEN -Fn", "netstat -an -p tcp"])
                inspected = [call for call in calls if call.startswith("docker inspect")]
                self.assertLessEqual(len(inspected), 1)

    def test_no_listing_at_all_takes_the_first_block(self):
        """Unchanged from the old probe, and pinned so nobody changes it
        quietly: when NEITHER list can be read, nothing counts as listening."""
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, bases, _, _ = self.walk(launcher, with_lsof=False, with_netstat=False)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(bases, [8081])
                result, bases, _, _ = self.walk(launcher, lsof_fails=True, netstat_fails=True)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(bases, [8081])

    def test_each_list_still_counts_when_the_other_is_missing(self):
        """No netstat: this account's list alone, as before #310. No lsof: the
        kernel's list, which holds this account's listeners too."""
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, bases, _, _ = self.walk(launcher, listening=block_ports(8081), with_netstat=False)
                self.assertEqual((result.returncode, bases), (0, [8091]), output_of(result))
                result, bases, _, _ = self.walk(launcher, listening=block_ports(8081), with_lsof=False)
                self.assertEqual((result.returncode, bases), (0, [8091]), output_of(result))

    def test_another_accounts_listener_is_stepped_past(self):
        """#310: seen only in the kernel's list, and the only thing that moves
        the walk here. Every shape netstat writes: the port after the LAST
        dot, whatever the address (a long IPv6 one cut short included)."""
        for launcher in LAUNCHERS:
            for port in [8081, 9084]:
                # Rows in front of it (screen sharing's 5900) put the port in
                # each of the five shapes the pretend kernel writes in turn.
                for shape in range(5):
                    with self.subTest(launcher=launcher, port=port, shape=shape):
                        result, bases, _, _ = self.walk(launcher, elsewhere=[5900] * shape + [port])
                        self.assertEqual((result.returncode, bases), (0, [8091]), output_of(result))

    def test_with_no_lsof_the_other_workspaces_are_still_skipped(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, bases, _, _ = self.walk(
                    launcher, with_lsof=False, with_netstat=False,
                    holding={"teaching-quartz-deadbeef": block_ports(8081)})
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


# Another working folder's RUNNING workspace, holding the first block — the
# shape a Docker port refusal comes from. Its ports are NOT in the listening
# lists: nothing here is meant to be "another account holds them", so the
# look before a start (#310) finds nothing and the refusal path is what is
# tested. (Until #310 this fixture listed the block as listening, which
# could not matter while nothing looked before starting.)
OTHER_FOLDER = "teaching-quartz-deadbeef"


def the_launchers_serving_or_not() -> list:
    """Every launcher as it runs for real, plus preview.sh serving: the look
    before a start must leave these paths exactly as they were."""
    return [(launcher, False) for launcher in LAUNCHERS] + [("preview.sh", True)]


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class AStoppedWorkspaceThatCannotStart(unittest.TestCase):

    def start(self, launcher: str, answer: str, rm_refuses: bool = False, running: list = None,
              serving: bool = False) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            mac = PretendMac(Path(scratch))
            mac.listening([])
            mac.workspaces({CONTAINER: block_ports(8081), OTHER_FOLDER: block_ports(8081)},
                           [OTHER_FOLDER] + (running or []))
            (mac.fake / "start_answer").write_text(answer, encoding="utf-8")
            if rm_refuses:
                (mac.fake / "rm_refuses").write_text("", encoding="utf-8")
            result = mac.run(launcher, 'start_the_existing_workspace; echo "CARRIED ON"', serving=serving)
            return result, mac.calls()

    def test_a_start_that_works_changes_nothing(self):
        for launcher, serving in the_launchers_serving_or_not():
            with self.subTest(launcher=launcher, serving=serving):
                result, calls = self.start(launcher, "ok", serving=serving)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertIn("CARRIED ON", output_of(result))
                self.assertEqual([c for c in calls if c.startswith("docker rm") or c.startswith("docker run")], [])

    def test_a_block_taken_while_it_was_stopped_is_made_again_on_free_ports(self):
        refusal = "Error response from daemon: driver failed programming external connectivity on endpoint teaching-quartz-0000abcd: Bind for 0.0.0.0:8081 failed: port is already allocated"
        for launcher, serving in the_launchers_serving_or_not():
            with self.subTest(launcher=launcher, serving=serving):
                result, calls = self.start(launcher, refusal, serving=serving)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertIn("CARRIED ON", output_of(result))
                self.assertIn("slower", output_of(result), "the console must say what it costs")
                self.assertEqual([c for c in calls if c.startswith("docker rm")], ["docker rm " + CONTAINER])
                self.assertEqual(published_bases(calls), [8091])
                self.assertNotIn(address_held_prefix(), output_of(result),
                                 "a Docker refusal is not another account's address")

    def test_any_other_refusal_stops_with_the_engines_words(self):
        """setup.sh and deploy.sh used to end here under `set -e` with only
        the engine's words; preview.sh carried on past it."""
        refusal = "Error response from daemon: something else entirely"
        for launcher, serving in the_launchers_serving_or_not():
            with self.subTest(launcher=launcher, serving=serving):
                result, calls = self.start(launcher, refusal, serving=serving)
                self.assertEqual(result.returncode, 1, output_of(result))
                self.assertNotIn("CARRIED ON", output_of(result))
                self.assertIn("something else entirely", output_of(result))
                self.assertEqual([c for c in calls if c.startswith("docker rm") or c.startswith("docker run")], [])

    def test_a_workspace_another_launcher_already_started_is_used_as_it_is(self):
        refusal = "Bind for 0.0.0.0:8081 failed: port is already allocated"
        for launcher, serving in the_launchers_serving_or_not():
            with self.subTest(launcher=launcher, serving=serving):
                result, calls = self.start(launcher, refusal, rm_refuses=True, running=[CONTAINER],
                                           serving=serving)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertIn("CARRIED ON", output_of(result))
                self.assertEqual(published_bases(calls), [])


# ======================================================================
# GitHub #310 (B): before a PREVIEW starts a stopped workspace under Colima,
# its own ports are looked at. Colima does not refuse a start onto a port
# another account holds — it exits 0 and the forward silently fails.
# ======================================================================
def address_held_entry() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    for entry in rules["activityTrail"]["mustRecord"]:
        if entry["event"] == "preview address held by another account":
            return entry
    raise AssertionError("the contract no longer has a 'preview address held by another account' event")


def address_held_prefix() -> str:
    return address_held_entry()["marker"]["prefix"]


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class TheLookBeforeAStart(unittest.TestCase):

    def start(self, launcher: str = "preview.sh", serving: bool = True, elsewhere: list = None,
              own: list = None, context: str = "colima", running: list = None, docker_host: str = None,
              rm_refuses: bool = False, colima_home: str = None) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            mac = PretendMac(Path(scratch))
            mac.listening(own or [])
            mac.listening_in_another_account(elsewhere if elsewhere is not None else [8081])
            mac.workspaces({CONTAINER: block_ports(8081)}, running)
            mac.flag("context", context + "\n")
            if rm_refuses:
                mac.flag("rm_refuses")
            result = mac.run(launcher, 'start_the_existing_workspace; echo "CARRIED ON"',
                             serving=serving, docker_host=docker_host, colima_home=colima_home)
            return result, mac.calls()

    def said(self, result) -> list:
        return result.stdout.decode("utf-8").splitlines()

    def assert_remade_before_starting(self, result, calls, port: int = 8081) -> None:
        self.assertEqual(result.returncode, 0, output_of(result))
        self.assertIn("CARRIED ON", output_of(result))
        self.assertEqual(engine_calls(calls, "start"), [], "started onto somebody else's address: " + output_of(result))
        self.assertEqual(engine_calls(calls, "rm"), ["docker rm " + CONTAINER])
        self.assertEqual(published_bases(calls), [8091])
        said = self.said(result)
        for line in the_rules()["hostBlockClash"]["saysWhenAStoppedWorkspaceIsRemade"]:
            self.assertIn(line, said)
        self.assertIn(f"{address_held_prefix()} before-start {port} ICS4U/2", said)

    def test_another_accounts_listener_on_its_address_remakes_it_before_it_starts(self):
        """The #204 rehearsal's second half: the start would have 'worked'."""
        result, calls = self.start()
        self.assert_remade_before_starting(result, calls)

    def test_any_of_its_eight_ports_counts(self):
        result, calls = self.start(elsewhere=[9084])
        self.assert_remade_before_starting(result, calls, port=9084)

    def test_this_accounts_own_program_counts_too(self):
        """A stopped workspace listens on nothing itself, so any listener is
        somebody else's — including a program of this account's."""
        result, calls = self.start(elsewhere=[], own=[8082])
        self.assert_remade_before_starting(result, calls, port=8082)

    def test_a_colima_profile_counts_as_colima(self):
        result, calls = self.start(context="colima-work")
        self.assert_remade_before_starting(result, calls)

    def test_docker_host_into_colima_counts_as_colima(self):
        result, calls = self.start(context="default", docker_host="unix:///Users/t/.colima/default/docker.sock")
        self.assert_remade_before_starting(result, calls)

    def test_docker_host_into_colima_home_counts_as_colima(self):
        """A Colima kept somewhere else keeps its socket under COLIMA_HOME."""
        result, calls = self.start(context="default", docker_host="unix:///opt/colima-dev/default/docker.sock",
                                   colima_home="/opt/colima-dev")
        self.assert_remade_before_starting(result, calls)
        result, calls = self.start(context="default", docker_host="unix:///opt/other/docker.sock",
                                   colima_home="/opt/colima-dev")
        self.assertEqual(engine_calls(calls, "start"), ["docker start " + CONTAINER], output_of(result))

    def test_nothing_on_its_addresses_starts_it_as_before(self):
        result, calls = self.start(elsewhere=[8085, 9085])
        self.assertEqual(result.returncode, 0, output_of(result))
        self.assertEqual(engine_calls(calls, "start"), ["docker start " + CONTAINER])
        self.assertEqual(engine_calls(calls, "rm") + engine_calls(calls, "run"), [])
        self.assertNotIn(address_held_prefix(), output_of(result))

    def test_one_another_launcher_started_a_moment_ago_is_used_as_it_is(self):
        """The listener is then its own forward: no remake, nothing said."""
        result, calls = self.start(running=[CONTAINER])
        self.assertEqual(result.returncode, 0, output_of(result))
        self.assertEqual(engine_calls(calls, "start") + engine_calls(calls, "rm") + engine_calls(calls, "run"), [])
        self.assertNotIn("♻️", output_of(result))
        self.assertNotIn(address_held_prefix(), output_of(result))

    def test_another_engine_is_not_looked_at(self):
        """Docker Desktop refuses a start onto a held port itself, and an
        engine nobody measured must not pay a remake on a guess."""
        for context, docker_host in [("desktop-linux", None), ("default", "tcp://192.168.64.2:2375")]:
            with self.subTest(context=context, docker_host=docker_host):
                result, calls = self.start(context=context, docker_host=docker_host)
                self.assertEqual(engine_calls(calls, "start"), ["docker start " + CONTAINER], output_of(result))
                self.assertEqual([c for c in calls if c.startswith("netstat") or c.startswith("lsof")], [])
                self.assertNotIn(address_held_prefix(), output_of(result))

    def test_a_run_that_does_not_serve_never_looks(self):
        """setup.sh, deploy.sh and a build for publishing keep their warm
        builder: a squatted forward costs them nothing."""
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.start(launcher=launcher, serving=False)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(engine_calls(calls, "start"), ["docker start " + CONTAINER])
                self.assertEqual([c for c in calls if c.startswith("netstat") or c.startswith("lsof")
                                  or c.startswith("docker context")], [])

    def test_a_remove_that_is_refused_stops_with_the_sentence_and_no_engine_words(self):
        """There was no start, so there are no engine's words to print."""
        result, calls = self.start(rm_refuses=True)
        self.assertEqual(result.returncode, 1, output_of(result))
        self.assertNotIn("CARRIED ON", output_of(result))
        self.assertEqual(engine_calls(calls, "start") + engine_calls(calls, "run"), [])
        self.assertEqual(self.said(result)[-1], the_rules()["hostBlockClash"]["saysWhenAStartIsRefused"])
        self.assertNotIn(address_held_prefix(), output_of(result),
                         "the trail must never say it was set up again when it was not")

    def test_a_remove_refused_because_it_is_running_now_claims_no_rebuild(self):
        """Another launcher started it between the look and the remove: it is
        used as it is, and nothing says it was set up again."""
        with tempfile.TemporaryDirectory() as scratch:
            mac = PretendMac(Path(scratch))
            mac.listening([])
            mac.listening_in_another_account([8081])
            mac.workspaces({CONTAINER: block_ports(8081)}, [])
            mac.flag("rm_refuses")
            # Not running at the look; running by the time the remove fails.
            (mac.bin / "docker").write_text(FAKE_DOCKER.replace(
                'if [ "${2:-}" = "-a" ]; then cat "$FAKE/workspaces" 2>/dev/null; else cat "$FAKE/running" 2>/dev/null; fi',
                'if [ "${2:-}" = "-a" ]; then cat "$FAKE/workspaces" 2>/dev/null; '
                'elif grep -q "^docker rm" "$FAKE/calls"; then echo ' + CONTAINER + '; '
                'else cat "$FAKE/running" 2>/dev/null; fi'), encoding="utf-8")
            result = mac.run("preview.sh", 'start_the_existing_workspace; echo "CARRIED ON"', serving=True)
            calls = mac.calls()
        self.assertEqual(result.returncode, 0, output_of(result))
        self.assertIn("CARRIED ON", output_of(result))
        self.assertEqual(engine_calls(calls, "run") + engine_calls(calls, "start"), [])
        self.assertNotIn(address_held_prefix(), output_of(result))

    def test_the_marker_is_the_contracts(self):
        block = between(launcher_text("setup.sh"), BLOCK_START, BLOCK_END)
        self.assertIn(f'echo "{address_held_prefix()} $1 $2 ${{WORKSPACE_TRAIL_PLACE:-setup}}"', block)
        self.assertIn("tell_the_app_the_address_was_held before-start", block)


# ======================================================================
# GitHub #94: a workspace is remade only once nothing is running in it.
# The rule is contracts/app-rules.json -> previewPorts.whenTheWorkspaceIsInUse.
# ======================================================================
def in_use_rules() -> dict:
    return the_rules()["whenTheWorkspaceIsInUse"]


def in_use_trail_entry() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    for entry in rules["activityTrail"]["mustRecord"]:
        if entry["event"] == "workspace was in use":
            return entry
    raise AssertionError("the contract no longer has a 'workspace was in use' event")


OLD_ID = "0ld0000000000000000000000000000000000000000000000000000000000000"
THE_OPEN_PREVIEW = "python3 -u /opt/scripts/build_site.py --host-os mac --course=ICS4U --section=1 --port 8081"
A_PUBLISH = "python3 /opt/scripts/deploy.py --host-os mac --course ICS4U --section 2"
ITS_LAUNCHER = "/bin/bash /Users/t/Work/preview.sh ICS4U 1"

# What each word of a sequence looks like from outside: the workspace's
# processes (pid, parent, command), its first process always first.
LOOKS = {
    "nothing": [[100, 1, "tail -f /dev/null"]],
    "other work": [[100, 1, "tail -f /dev/null"], [410, 1, A_PUBLISH]],
    "a preview": [[100, 1, "tail -f /dev/null"], [210, 1, THE_OPEN_PREVIEW]],
}


def place_of(launcher: str) -> str:
    return "setup" if launcher == "setup.sh" else "ICS4U/2"


class AWorkspaceInUse:
    """A pretend Mac with this folder's workspace in it, and what runs there."""

    def __init__(self, scratch: Path):
        self.mac = PretendMac(scratch)
        self.mac.listening([])
        self.mac.workspaces({})
        self.fake = self.mac.fake

    def exists(self, names: dict) -> None:
        (self.fake / "ids").write_text("".join(f"{name} {ident}\n" for name, ident in names.items()), encoding="utf-8")

    def stopped(self) -> None:
        (self.fake / "state").write_text("false 0\n", encoding="utf-8")

    def looks(self, answers: list) -> None:
        number = 1
        for processes in answers:
            lines = []
            for pid, parent, command in processes:
                lines.append(f"root {pid} {parent} 0 16:56 ? 00:00:00 {command}")
            (self.fake / f"top_{number}").write_text("\n".join(lines) + "\n", encoding="utf-8")
            number += 1

    def launchers(self, lines: list) -> None:
        text = ""
        pid = 7001
        for line in lines:
            text += f"{pid} 1 {line}\n"
            pid += 1
        (self.fake / "ps").write_text(text, encoding="utf-8")

    def flag(self, name: str, text: str = "") -> None:
        (self.fake / name).write_text(text, encoding="utf-8")

    def run(self, launcher: str, action: str) -> tuple:
        result = self.mac.run(launcher, action)
        return result, self.mac.calls()


def engine_calls(calls: list, verb: str) -> list:
    found = []
    for call in calls:
        if call.startswith("docker " + verb + " "):
            found.append(call)
    return found


def sleeps(calls: list) -> list:
    found = []
    for call in calls:
        if call.startswith("sleep "):
            found.append(call)
    return found


class TheLookBeforeARemakeIsWritten(unittest.TestCase):

    def block(self) -> str:
        return between(launcher_text("setup.sh"), BLOCK_START, BLOCK_END)

    def test_nothing_outside_the_block_stops_or_removes_a_workspace(self):
        """Every remake goes through remake_the_workspace, which looks first.
        Before #94: setup.sh 8, preview.sh 5, deploy.sh 7, and one -f of the
        old shared workspace in each."""
        pattern = re.compile(r"docker\s+(container\s+)?(stop|rm|kill)\b[^\n]*(CONTAINER_NAME|teaching-quartz\b)")
        for launcher in LAUNCHERS:
            text = launcher_text(launcher)
            outside = text.replace(between(text, BLOCK_START, BLOCK_END), "")
            with self.subTest(launcher=launcher):
                self.assertEqual(pattern.findall(outside), [],
                                 f"{launcher} removes a workspace without looking at what runs in it")
                self.assertNotIn("retire_legacy_container() {", outside,
                                 "the old shared workspace is retired by the block's look, not a copy of its own")

    def test_every_remake_reason_calls_the_block(self):
        # preview.sh's sixth is #310's: an announced address that turned
        # out to be another account's.
        expected = {"setup.sh": 8, "preview.sh": 6, "deploy.sh": 7}
        for launcher, count in expected.items():
            text = launcher_text(launcher)
            outside = text.replace(between(text, BLOCK_START, BLOCK_END), "")
            with self.subTest(launcher=launcher):
                self.assertEqual(len(re.findall(r"^\s*remake_the_workspace$", outside, flags=re.MULTILINE)), count)

    def test_the_numbers_are_the_contracts(self):
        waiting = in_use_rules()["waiting"]
        block = self.block()
        self.assertIn(f"\nWORKSPACE_LOOK_EVERY_SECONDS={waiting['lookEverySeconds']}\n", block)
        self.assertIn(f"\nWORKSPACE_PREVIEW_SECONDS={waiting['previewSeconds']}\n", block)
        self.assertIn(f"\nWORKSPACE_WORK_SECONDS={waiting['workSeconds']}\n", block)

    def test_the_sentences_are_the_contracts(self):
        sentences = in_use_rules()["sentences"]
        block = self.block()
        self.assertIn(f'echo "{sentences["whileWaiting"]}"', block)
        for line in sentences["whenAPreviewIsOpen"]:
            written = line.replace("{course} section {section}", "$WORKSPACE_OPEN_PREVIEW")
            self.assertIn(f'echo "{written}"', block)
        for line in sentences["whenWorkDidNotFinish"]:
            self.assertIn(f'echo "{line}"', block)

    def test_the_marker_is_the_contracts(self):
        prefix = in_use_trail_entry()["marker"]["prefix"]
        self.assertIn(f'echo "{prefix} $1 $2 ', self.block())

    def test_the_sentences_name_no_machinery(self):
        sentences = in_use_rules()["sentences"]
        lines = [sentences["whileWaiting"]] + sentences["whenAPreviewIsOpen"] + sentences["whenWorkDidNotFinish"]
        for line in lines:
            words = set(re.findall(r"[a-z]+", line.lower()))
            for forbidden in ["docker", "container", "port", "ports", "toolchain", "script", "localhost", "process"]:
                self.assertNotIn(forbidden, words, line)


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class WhatCountsAsRunning(unittest.TestCase):

    def look(self, launcher: str, case: dict, setup=None) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            pretend = AWorkspaceInUse(Path(scratch))
            if case["running"] != "gone":
                pretend.exists({CONTAINER: OLD_ID})
            if case["running"] is False:
                pretend.stopped()
            if case["top"] == "fails":
                pretend.flag("top_fails")
            elif isinstance(case["top"], list):
                pretend.looks([case["top"]])
            pretend.launchers(case.get("launchers", []))
            if setup is not None:
                setup(pretend)
            result, calls = pretend.run(
                launcher,
                'look_inside_the_workspace "' + OLD_ID + '"; '
                'echo "LOOKED=$WORKSPACE_IS_RUNNING|$WORKSPACE_OPEN_PREVIEW_PLACE"')
            return result, calls

    def answer(self, result: subprocess.CompletedProcess) -> str:
        for line in result.stdout.decode("utf-8").splitlines():
            if line.startswith("LOOKED="):
                return line[len("LOOKED="):]
        raise AssertionError("the look did not finish: " + output_of(result))

    def test_every_contract_case(self):
        for case in in_use_rules()["whatCountsAsRunning"]["cases"]:
            for launcher in LAUNCHERS:
                with self.subTest(case=case["name"], launcher=launcher):
                    result, calls = self.look(launcher, case)
                    self.assertEqual(result.returncode, 0, output_of(result))
                    self.assertEqual(self.answer(result), case["expect"] + "|" + case.get("preview", ""))
                    if case["top"] == "not asked":
                        self.assertEqual(engine_calls(calls, "top"), [],
                                         "a stopped or missing workspace cannot be asked what runs in it")

    def test_this_run_is_not_the_preview_s_launcher(self):
        """A second run of the same section — or this run wrapped in a login
        shell — carries the same words as the preview's launcher. With the
        preview's own launcher gone, only this run is left: an orphan."""
        case = {"running": True, "top": LOOKS["a preview"], "launchers": []}

        def as_the_same_section(pretend: AWorkspaceInUse) -> None:
            pretend.flag("ps_self", "/bin/bash ./preview.sh ICS4U 1")

        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, _ = self.look(launcher, case, as_the_same_section)
                self.assertEqual(self.answer(result), "nothing|", output_of(result))

    def test_a_process_table_that_cannot_be_read_keeps_the_preview_open(self):
        case = {"running": True, "top": LOOKS["a preview"], "launchers": []}

        def unreadable(pretend: AWorkspaceInUse) -> None:
            pretend.flag("ps_fails")

        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, _ = self.look(launcher, case, unreadable)
                self.assertEqual(self.answer(result), "a preview|ICS4U/1", output_of(result))


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class TheRemake(unittest.TestCase):

    def remake(self, launcher: str, looks: list, setup=None) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            pretend = AWorkspaceInUse(Path(scratch))
            pretend.exists({CONTAINER: OLD_ID})
            answers = []
            for word in looks:
                answers.append(LOOKS[word])
            pretend.looks(answers)
            pretend.launchers([ITS_LAUNCHER])
            if setup is not None:
                setup(pretend)
            result, calls = pretend.run(launcher, 'remake_the_workspace; echo "CARRIED ON"')
            return result, calls

    def said(self, result: subprocess.CompletedProcess) -> list:
        return result.stdout.decode("utf-8").splitlines()

    def assert_nothing_was_touched(self, calls: list, result) -> None:
        for verb in ["stop", "rm", "run"]:
            self.assertEqual(engine_calls(calls, verb), [], f"docker {verb} was called: " + output_of(result))

    def test_every_contract_sequence(self):
        rules = in_use_rules()
        sentences = rules["sentences"]
        prefix = in_use_trail_entry()["marker"]["prefix"]
        for case in rules["sequences"]["cases"]:
            for launcher in LAUNCHERS:
                with self.subTest(case=case["name"], launcher=launcher):
                    result, calls = self.remake(launcher, case["looks"])
                    said = self.said(result)
                    waited = case["waited"]
                    self.assertEqual(len(sleeps(calls)), waited // rules["waiting"]["lookEverySeconds"], calls)
                    self.assertEqual(said.count(sentences["whileWaiting"]), 1 if waited else 0, said)
                    markers = [line for line in said if line.startswith(prefix)]
                    if case["expect"] == "remade":
                        self.assertEqual(result.returncode, 0, output_of(result))
                        self.assertIn("CARRIED ON", said)
                        self.assertEqual(engine_calls(calls, "stop"), ["docker stop " + OLD_ID])
                        self.assertEqual(engine_calls(calls, "rm"), ["docker rm " + OLD_ID])
                        self.assertEqual(len(engine_calls(calls, "run")), 1)
                        if waited:
                            self.assertEqual(markers, [f"{prefix} waited {waited} {place_of(launcher)}"])
                        else:
                            self.assertEqual(markers, [])
                    elif case["expect"] == "refused: a preview":
                        self.assertEqual(result.returncode, sentences["exitCode"], output_of(result))
                        self.assert_nothing_was_touched(calls, result)
                        for line in sentences["whenAPreviewIsOpen"]:
                            self.assertIn(line.replace("{course}", "ICS4U").replace("{section}", "1"), said)
                        self.assertEqual(markers, [f"{prefix} preview {waited} {place_of(launcher)} ICS4U/1"])
                    else:
                        self.assertEqual(result.returncode, sentences["exitCode"], output_of(result))
                        self.assert_nothing_was_touched(calls, result)
                        for line in sentences["whenWorkDidNotFinish"]:
                            self.assertIn(line, said)
                        self.assertEqual(markers, [f"{prefix} work {waited} {place_of(launcher)}"])

    def test_a_stopped_workspace_is_remade_without_asking_what_runs_in_it(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.remake(launcher, ["a preview"], lambda pretend: pretend.stopped())
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(engine_calls(calls, "top"), [])
                self.assertEqual(engine_calls(calls, "rm"), ["docker rm " + OLD_ID])

    def test_no_workspace_at_all_is_simply_made(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.remake(launcher, ["nothing"], lambda pretend: pretend.exists({}))
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(engine_calls(calls, "top") + engine_calls(calls, "rm"), [])
                self.assertEqual(len(engine_calls(calls, "run")), 1)

    def test_one_already_removed_by_another_launcher_is_no_failure(self):
        """The id is gone: another launcher removed it first. Its new
        workspace is found at the making, given two seconds, and used."""
        conflict = 'docker: Error response from daemon: Conflict. The container name "/teaching-quartz-0000abcd" is already in use by container "abc". You have to remove (or rename) that container to be able to reuse that name.'

        def raced(pretend: AWorkspaceInUse) -> None:
            pretend.flag("rm_gone")
            pretend.mac.run_answers([conflict])
            pretend.mac.workspaces({}, running=[CONTAINER])

        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.remake(launcher, ["nothing"], raced)
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertIn("CARRIED ON", output_of(result))
                self.assertEqual(len(engine_calls(calls, "run")), 1, "the other launcher's workspace is used as it is")
                self.assertEqual(sleeps(calls), ["sleep 2"])

    def test_a_second_name_conflict_stops_with_the_sentence(self):
        conflict = 'Conflict. The container name "/teaching-quartz-0000abcd" is already in use by container "abc".'

        def taken(pretend: AWorkspaceInUse) -> None:
            pretend.mac.run_answers([conflict, conflict])

        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.remake(launcher, ["nothing"], taken)
                self.assertEqual(result.returncode, 1, output_of(result))
                self.assertEqual(len(engine_calls(calls, "run")), 2)
                self.assertIn(the_rules()["hostBlockClash"]["saysWhenAStartIsRefused"], self.said(result))
                self.assertNotIn("inside your home folder", output_of(result),
                                 "a name taken a moment ago is not a folder in the wrong place")

    def test_a_remove_that_keeps_failing_is_tried_once_more_then_stops(self):
        def stuck(pretend: AWorkspaceInUse) -> None:
            pretend.flag("rm_refuses")

        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.remake(launcher, ["nothing"], stuck)
                self.assertEqual(result.returncode, 1, output_of(result))
                self.assertEqual(engine_calls(calls, "rm"), ["docker rm " + OLD_ID] * 2)
                self.assertEqual(sleeps(calls), ["sleep 2"])
                self.assertEqual(engine_calls(calls, "run"), [])
                self.assertIn(the_rules()["hostBlockClash"]["saysWhenAStartIsRefused"], self.said(result))

    def test_nothing_is_stopped_or_removed_by_name_or_by_force(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                _, calls = self.remake(launcher, ["other work", "nothing"])
                for call in engine_calls(calls, "stop") + engine_calls(calls, "rm"):
                    self.assertNotIn(CONTAINER, call)
                    self.assertNotIn(" -f", call)


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class TheOldSharedWorkspace(unittest.TestCase):
    """Moved into the block by #94, and run from it here — no stand-in."""

    def retire(self, launcher: str, look: list) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            pretend = AWorkspaceInUse(Path(scratch))
            pretend.exists({"teaching-quartz": "1e9ac7"})
            pretend.looks([look])
            pretend.launchers([ITS_LAUNCHER])
            return pretend.run(launcher, 'retire_legacy_container; echo "CARRIED ON"')

    def test_an_idle_one_is_removed_by_its_id(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                result, calls = self.retire(launcher, LOOKS["nothing"])
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertEqual(engine_calls(calls, "rm"), ["docker rm 1e9ac7"])

    def test_a_busy_one_is_left_alone_silently(self):
        for look in ["other work", "a preview"]:
            for launcher in LAUNCHERS:
                with self.subTest(look=look, launcher=launcher):
                    result, calls = self.retire(launcher, LOOKS[look])
                    self.assertEqual(result.returncode, 0, output_of(result))
                    self.assertIn("CARRIED ON", output_of(result))
                    self.assertEqual(engine_calls(calls, "stop") + engine_calls(calls, "rm"), [])
                    self.assertNotIn("Retiring", output_of(result))

    def test_making_a_workspace_retires_it_through_the_block(self):
        """run_container_with_mount calls the REAL retire, not a stand-in."""
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                with tempfile.TemporaryDirectory() as scratch:
                    pretend = AWorkspaceInUse(Path(scratch))
                    pretend.exists({"teaching-quartz": "1e9ac7"})
                    pretend.looks([LOOKS["nothing"]])
                    result, calls = pretend.run(launcher, "run_container_with_mount")
                self.assertEqual(result.returncode, 0, output_of(result))
                self.assertIn("docker rm 1e9ac7", calls)


# ======================================================================
# GitHub #310 (C) through the REAL remake: preview.sh's announcement, with
# the real block behind it, when the address is another account's. The
# contract's own cases (whenAnotherAccountHasTheAddress.cases) run in
# test_preview_reach.py with the remake stubbed; these two need it real.
# ======================================================================
def preview_announcement_functions() -> str:
    text = launcher_text("preview.sh")
    parts = re.findall(r"^PREVIEW_REACH_[A-Z_]+=.*$", text, flags=re.MULTILINE)
    for name in ["this_mac_can_reach_the_builder", "say_this_mac_cannot_reach_the_builder",
                 "say_the_preview_address_is_unknown", "held_by_someone_else",
                 "say_another_account_has_this_preview_s_address", "the_preview_s_host_port",
                 "announce_the_preview_address"]:
        parts.append(function_named(text, name))
    return "\n".join(parts)


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class TheLookBeforeTheAnnouncement(unittest.TestCase):

    def announce(self, looks: list, launchers: list) -> tuple:
        with tempfile.TemporaryDirectory() as scratch:
            pretend = AWorkspaceInUse(Path(scratch))
            pretend.exists({CONTAINER: OLD_ID})
            answers = []
            for word in looks:
                answers.append(LOOKS[word])
            pretend.looks(answers)
            pretend.launchers(launchers)
            # This account's own list holds limactl's listener only; the
            # kernel's has another account's on 8081, the announced address.
            pretend.mac.listening([53])
            pretend.mac.listening_in_another_account([8081])
            pretend.flag("port", "8081")
            pretend.flag("port_after", "8091")
            action = "\n".join([
                preview_announcement_functions(),
                'PREVIEW_PORT=8081; BUILD_ONLY=""; THIS_RUN_STARTED_THE_BUILDER=""',
                'announce_the_preview_address || { echo "STOPPED"; exit 1; }',
                'echo "CARRIED ON"',
            ])
            return pretend.run("preview.sh", action)

    def test_an_open_preview_from_the_folder_refuses_the_remake_with_94s_words(self):
        """The plan's tenth case, moved here from the contract: the remake
        is #94's, so an open preview of another section is not ended for it."""
        result, calls = self.announce(["a preview"], [ITS_LAUNCHER])
        said = result.stdout.decode("utf-8").splitlines()
        self.assertEqual(result.returncode, in_use_rules()["sentences"]["exitCode"], output_of(result))
        for line in in_use_rules()["sentences"]["whenAPreviewIsOpen"]:
            self.assertIn(line.replace("{course}", "ICS4U").replace("{section}", "1"), said)
        prefix = in_use_trail_entry()["marker"]["prefix"]
        self.assertIn(f"{prefix} preview 20 ICS4U/2 ICS4U/1", said)
        # #94 refused, so nothing was set up again: its own line is the
        # trail's, and no line may claim a rebuild that did not happen.
        self.assertNotIn(address_held_prefix(), output_of(result))
        self.assertEqual(engine_calls(calls, "rm") + engine_calls(calls, "run"), [])
        self.assertNotIn("Preview will be available at", output_of(result))

    def test_an_idle_workspace_is_remade_and_the_new_address_announced(self):
        result, calls = self.announce(["nothing"], [])
        said = result.stdout.decode("utf-8").splitlines()
        self.assertEqual(result.returncode, 0, output_of(result))
        self.assertIn("CARRIED ON", said)
        self.assertEqual(engine_calls(calls, "rm"), ["docker rm " + OLD_ID])
        self.assertEqual(published_bases(calls), [8091], "the walk steps past the kernel's 8081")
        self.assertIn("🌐 Preview will be available at: http://localhost:8091/", said)
        self.assertEqual([line for line in said if line.startswith(address_held_prefix())],
                         [f"{address_held_prefix()} remade 8081 ICS4U/2"])


# ======================================================================
# The REAL listings on this Mac. Every other test here fakes both programs,
# so all of them would pass against an awk the real kernel's output
# defeats — and that failure falls back to lsof alone, silently
# reproducing #310. So the netstat half is checked ON ITS OWN.
# ======================================================================
@unittest.skipUnless(sys.platform == "darwin" and Path("/usr/sbin/netstat").exists()
                     and Path("/usr/sbin/lsof").exists(), "needs a Mac's netstat and lsof")
class TheRealListings(unittest.TestCase):

    def ports_from(self, function: str) -> set:
        block = between(launcher_text("setup.sh"), BLOCK_START, BLOCK_END)
        program = "set -euo pipefail\n" + function_named(block, function) + function + "\n"
        result = subprocess.run([BASH, "-c", program], capture_output=True, timeout=60,
                                env={"PATH": "/usr/sbin:/usr/bin:/bin", "HOME": os.environ.get("HOME", "/tmp")})
        self.assertEqual(result.returncode, 0, output_of(result))
        found = set()
        for line in result.stdout.decode("utf-8").splitlines():
            self.assertRegex(line, r"^[0-9]+$")
            found.add(int(line))
        return found

    def test_the_kernels_list_holds_every_port_this_accounts_list_holds(self):
        """Non-empty whenever lsof's is, and a superset of it: netstat sees
        this account too. Under Colima this account always owns listeners
        (limactl's), so on the development Mac this is never vacuous."""
        # The kernel's list is read before AND after this account's, so a
        # listener that comes or goes between the reads (other sessions make
        # and remove workspaces all the time here) is in one of them.
        before = self.ports_from("ports_listening_in_every_account")
        this_account = self.ports_from("ports_listening_in_this_account")
        after = self.ports_from("ports_listening_in_every_account")
        self.assertTrue(before and after or not this_account,
                        "netstat's half read NOTHING on this macOS: the walk is back to lsof alone")
        everyone = before | after
        if this_account:
            self.assertTrue(everyone, "netstat's half read NOTHING on this macOS: the walk is back to lsof alone")
        self.assertEqual(this_account - everyone, set(),
                         f"netstat's half missed ports lsof lists (macOS {os.uname().release})")


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
            if (case.get("busyPorts") or case.get("anotherAccountPorts") or case.get("stoppedBlocks")
                    or case.get("notListening")):
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

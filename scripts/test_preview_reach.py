#!/usr/bin/env python3
"""
`preview.sh` makes sure this Mac can reach the builder BEFORE it builds, and
stops in seconds when it cannot (GitHub #234).

The fault, met on 2026-09-19 (#225): a Mac whose builder had stopped handing
new addresses through to it built a preview for about two minutes, and the app
then waited 45 seconds more before saying this Mac could not reach it. Nothing
about the build was wrong, so all of that was waiting for an answer that was
knowable before the build began. `preview.sh` now asks — a connection to the
address it is about to announce — and only a REFUSED connection, on every try,
stops it. Everything else goes ahead, because #225's check after the build is
still there behind it.

The numbers and the cases are the contract's
(`contracts/app-rules.json` -> `previewPorts.whenThisMacCannotReachTheBuilder`),
and this file runs every case against the launcher.

**How this runs the real thing without Docker or a network.** The functions are
cut out of the repository's `preview.sh` by name — not retyped — and run under
bash with `docker`, `curl` and `sleep` replaced by shell functions that answer
as told and write down how they were called. Nothing is started, nothing is
connected to, and nothing waits: the only files written are in a scratch
folder, deleted afterwards. `HOME` is always that scratch folder, so the
launcher's trail helper can never add a line to the real trail.

**Whose address it is (GitHub #310).** After the reach check, under Colima,
`preview.sh` also asks whether the address is this account's own: another
account on the same Mac can hold it, and then the reach check is answered by
THEIR forwarder and the teacher is shown their site. Every case of
`previewPorts.whenAnotherAccountHasTheAddress` runs here too, with `netstat`,
`lsof`, `docker` and `remake_the_workspace` replaced by shell functions that
answer look by look — so the real `netstat` and `lsof` on this PATH can never
leak in. The remake itself is real in `test_port_blocks.py`.

**Windows.** The bash half is skipped where there is no bash that can run a
program, the same rule as the launcher tests beside it; the text half runs
everywhere. `preview.ps1` serves on the PC itself — there is no forward to
lose — so Windows has nothing to mirror.

Pure stdlib. Run with:

    python3 scripts/test_preview_reach.py
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT

ANNOUNCEMENT = "Preview will be available at: "
HOST_PORT = "8091"
INSIDE_PORT = "8081"

# Rule 1: a teacher reads these lines in the console.
MACHINERY_WORDS = ["docker", "container", "port", "toolchain", "script", "localhost",
                   "colima", "curl", "forward", "vm"]


def the_launcher_text() -> str:
    return (REPOSITORY_ROOT / "preview.sh").read_text(encoding="utf-8")


def the_rule() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8"))
    return rules["previewPorts"]["whenThisMacCannotReachTheBuilder"]


def the_ownership_rule() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8"))
    return rules["previewPorts"]["whenAnotherAccountHasTheAddress"]


def the_address_held_entry() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    for entry in rules["activityTrail"]["mustRecord"]:
        if entry["event"] == "preview address held by another account":
            return entry
    raise AssertionError("the contract no longer has the 'preview address held by another account' event")


def the_trail_line() -> str:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    for entry in rules["activityTrail"]["mustRecord"]:
        if entry["event"] == "preview did not appear":
            return entry["launcherLineWhenThisMacCannotReachTheBuilder"]
    raise AssertionError("the contract no longer has the 'preview did not appear' event")


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
            f"preview.sh has no function called {name}: the reach check is done "
            "some other way now, and this file has to be told how."
        )
    return match.group(0)


def the_reach_settings() -> str:
    """The launcher's own `PREVIEW_REACH_…=` lines, cut out as they are."""
    lines = re.findall(r"^PREVIEW_REACH_[A-Z_]+=.*$", the_launcher_text(), flags=re.MULTILINE)
    if not lines:
        raise AssertionError("preview.sh no longer sets PREVIEW_REACH_… at the top level")
    return "\n".join(lines)


def the_setting(name: str) -> str:
    match = re.search(r"^" + name + r"=(\S+)$", the_launcher_text(), flags=re.MULTILINE)
    if match is None:
        raise AssertionError(f"preview.sh no longer sets {name}")
    return match.group(1)


class Run:
    """What one run of the announcement did."""

    def __init__(self, result: subprocess.CompletedProcess, curl_calls: list, sleeps: list, trail: str,
                 calls: list):
        self.returncode = result.returncode
        self.output = result.stdout.decode("utf-8", "replace")
        self.errors = result.stderr.decode("utf-8", "replace")
        self.curl_calls = curl_calls
        self.sleeps = sleeps
        self.trail = trail
        self.calls = calls

    def asked(self, program: str) -> int:
        count = 0
        for call in self.calls:
            if call.split(" ")[0] == program:
                count += 1
        return count

    def markers(self) -> list:
        prefix = the_address_held_entry()["marker"]["prefix"]
        found = []
        for line in self.output.splitlines():
            if line.startswith(prefix):
                found.append(line)
        return found

    def describe(self) -> str:
        return (f"exit {self.returncode}\n--- output\n{self.output}\n--- errors\n{self.errors}"
                f"\n--- curl calls {len(self.curl_calls)}, sleeps {self.sleeps}, calls {self.calls}")


# This account's own listener besides the preview's: limactl's, which under
# Colima is always there (measured), so a working lsof is never empty.
LIMACTL_PORT = "53"


def look_bodies(looks: list) -> tuple:
    """The shell `case` arms answering each ownership look: netstat's rows
    and lsof's, for the port the workspace publishes at that moment."""
    kernel_arms = []
    own_arms = []
    number = 1
    for look in looks:
        kernel = look["kernel"]
        if kernel == "fails":
            kernel_arms.append(f'    {number}) echo "netstat: something went wrong" >&2; return 1 ;;')
        else:
            rows = ['echo "tcp4 0 0 *.' + LIMACTL_PORT + ' *.* LISTEN"']
            for _ in range(int(kernel)):
                rows.append('echo "tcp4 0 0 *.$(_port_now) *.* LISTEN"')
            kernel_arms.append(f"    {number}) " + "; ".join(rows) + " ;;")
        own = look["own"]
        if own == "missing":
            own_arms.append(f'    {number}) echo "lsof: command not found" >&2; return 127 ;;')
        elif own == "empty":
            own_arms.append(f"    {number}) return 0 ;;")
        else:
            rows = ['echo "p90"', 'echo "n*:' + LIMACTL_PORT + '"']
            for _ in range(int(own)):
                rows.append('echo "n*:$(_port_now)"')
            own_arms.append(f"    {number}) " + "; ".join(rows) + " ;;")
        number += 1
    return kernel_arms, own_arms


HEALTHY = [{"kernel": 1, "own": 1}]


def announce(refused_first: int, then_curl_exits, started_this_run: bool = False,
             build_only: bool = False, stub_curl: bool = True, extra_bash: str = "",
             looks: list = None, context: str = "colima", docker_host: str = None,
             port_after_remake=None) -> Run:
    """Runs the launcher's own announcement. `docker port` answers with the
    published port; `curl` exits 7 (connection refused) `refused_first` times
    and then `then_curl_exits` for ever (None: 7 for ever). With
    `stub_curl=False` there is no curl at all on the PATH.

    `looks` answers the ownership looks (#310) one by one, in the contract's
    shape; a look nobody expected fails the run. `remake_the_workspace` is a
    stub that records itself and makes `docker port` answer
    `port_after_remake` from then on."""
    if looks is None:
        looks = HEALTHY * 3
    with tempfile.TemporaryDirectory() as scratch:
        scratch_path = Path(scratch)
        home = scratch_path / "home"
        home.mkdir()
        curl_log = scratch_path / "curl-calls"
        sleep_log = scratch_path / "sleeps"
        calls_log = scratch_path / "calls"
        look_file = scratch_path / "look"
        remade_file = scratch_path / "remade"
        for log in (curl_log, sleep_log, calls_log):
            log.write_text("", encoding="utf-8")
        look_file.write_text("0", encoding="utf-8")
        kernel_arms, own_arms = look_bodies(looks)
        after = HOST_PORT if port_after_remake is None else str(port_after_remake)

        then_code = 7 if then_curl_exits is None else int(then_curl_exits)
        program_lines = [
            function_named("note_on_the_trail"),
            the_reach_settings(),
            function_named("this_mac_can_reach_the_builder"),
            function_named("say_this_mac_cannot_reach_the_builder"),
            function_named("say_the_preview_address_is_unknown"),
            function_named("ports_listening_in_every_account"),
            function_named("ports_listening_in_this_account"),
            function_named("the_engine_forwards_from_this_account"),
            function_named("a_different_engine_was_named_by_hand"),
            function_named("tell_the_app_the_address_was_held"),
            function_named("say_this_folder_is_set_up_again_on_free_addresses"),
            function_named("held_by_someone_else"),
            function_named("say_another_account_has_this_preview_s_address"),
            function_named("the_preview_s_host_port"),
            function_named("announce_the_preview_address"),
            '_curl_log="$1"',
            '_sleep_log="$2"',
            '_calls="$3"',
            '_look="$4"',
            '_remade="$5"',
            '_port_now() { if [ -f "$_remade" ]; then echo "' + after + '"; else echo "' + HOST_PORT + '"; fi; }',
            'docker() {',
            '  echo "docker $*" >> "$_calls"',
            '  case "$1" in',
            '    port) echo "0.0.0.0:$(_port_now)" ;;',
            '    context) echo "' + context + '" ;;',
            '    *) echo "unexpected docker $*" >&2; return 99 ;;',
            '  esac',
            '}',
            'netstat() {',
            '  echo "netstat $*" >> "$_calls"',
            '  local n; n=$(( $(cat "$_look") + 1 )); echo "$n" > "$_look"',
            '  echo "Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)"',
            '  case "$n" in',
        ] + kernel_arms + [
            '    *) echo "a look nobody expected" >&2; exit 98 ;;',
            '  esac',
            '}',
            'lsof() {',
            '  echo "lsof $*" >> "$_calls"',
            '  local n; n=$(cat "$_look")',
            '  case "$n" in',
        ] + own_arms + [
            '    *) echo "a look nobody expected" >&2; exit 98 ;;',
            '  esac',
            '}',
            'remake_the_workspace() { echo "remake_the_workspace" >> "$_calls"; : > "$_remade"; }',
            'sleep() { printf "%s\\n" "$*" >> "$_sleep_log"; }',
        ]
        if stub_curl:
            program_lines += [
                'curl() {',
                '  local asked; asked=$(wc -l < "$_curl_log" | tr -d " ")',
                '  local joined="" argument',
                '  for argument in "$@"; do joined="${joined}${argument}"$\'\\t\'; done',
                '  printf "%s\\n" "$joined" >> "$_curl_log"',
                '  if [ "$asked" -lt ' + str(int(refused_first)) + ' ]; then return 7; fi',
                '  return ' + str(then_code),
                '}',
            ]
        program_lines += [
            extra_bash,
            'CONTAINER_NAME="teaching-quartz-test"',
            'COURSE="ICS4U"',
            'SECTION="2"',
            # The launcher's own line, so the marker is filed where a real run files it.
            re.search(r'^WORKSPACE_TRAIL_PLACE=.*$', the_launcher_text(), flags=re.MULTILINE).group(0),
            'PREVIEW_PORT=' + INSIDE_PORT,
            'BUILD_ONLY="' + ("--build-only" if build_only else "") + '"',
            'THIS_RUN_STARTED_THE_BUILDER="' + ("1" if started_this_run else "") + '"',
            'announce_the_preview_address',
        ]
        program = "\n".join(program_lines) + "\n"

        path = os.environ.get("PATH", "")
        if not stub_curl:
            # A PATH with the few programs the functions use, and no curl.
            tools = scratch_path / "bin"
            tools.mkdir()
            for tool in ["date", "mkdir", "head", "sed", "cat", "wc", "tr", "grep", "awk"]:
                found = shutil.which(tool)
                if found:
                    (tools / tool).symlink_to(found)
            path = str(tools)

        bash = shutil.which("bash") or "/bin/bash"
        environment = {"HOME": str(home), "PATH": path}
        if docker_host is not None:
            environment["DOCKER_HOST"] = docker_host
        result = subprocess.run(
            [bash, "-c", program, "announce", str(curl_log), str(sleep_log), str(calls_log),
             str(look_file), str(remade_file)],
            capture_output=True,
            timeout=60,
            env=environment,
        )
        curl_calls = []
        for line in curl_log.read_text(encoding="utf-8").splitlines():
            curl_calls.append(line.split("\t")[:-1])
        sleeps = sleep_log.read_text(encoding="utf-8").splitlines()
        trail_file = home / "Library" / "Logs" / "Plantoir" / "activity.txt"
        trail = trail_file.read_text(encoding="utf-8") if trail_file.exists() else ""
        calls = calls_log.read_text(encoding="utf-8").splitlines()
        return Run(result, curl_calls, sleeps, trail, calls)


def tries_line(tries: int) -> str:
    return the_rule()["reachedAfterRetrying"].replace("{tries}", str(tries))


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class EveryContractCaseHolds(unittest.TestCase):

    def test_every_case(self):
        rule = the_rule()
        pause = the_setting("PREVIEW_REACH_PAUSE_SECONDS")
        self.assertGreaterEqual(len(rule["cases"]), 10)
        for case in rule["cases"]:
            with self.subTest(case=case["why"]):
                run = announce(case["refusedFirst"], case["thenCurlExits"],
                               started_this_run=case["thisRunStartedTheBuilder"],
                               build_only=case.get("buildOnly", False))
                self.assertEqual(len(run.curl_calls), case["probes"], run.describe())
                self.assertEqual(len(run.sleeps), case["pauses"], run.describe())
                for slept in run.sleeps:
                    self.assertEqual(slept, pause, run.describe())
                if case["outcome"] == "announces":
                    self.assertEqual(run.returncode, 0, run.describe())
                    self.assertIn(ANNOUNCEMENT + "http://localhost:" + HOST_PORT + "/\n", run.output)
                    self.assertEqual(run.trail, "", run.describe())
                elif case["outcome"] == "refuses":
                    self.assertEqual(run.returncode, rule["exitCode"], run.describe())
                    self.assertNotIn(ANNOUNCEMENT, run.output)
                    self.assertNotEqual(run.trail, "", run.describe())
                elif case["outcome"] == "asksNothing":
                    self.assertEqual(run.returncode, 0, run.describe())
                    self.assertEqual(run.output, "", run.describe())
                    self.assertEqual(run.trail, "", run.describe())
                else:
                    self.fail("unknown outcome " + case["outcome"])
                if "saysTries" in case:
                    self.assertIn(tries_line(case["saysTries"]) + "\n", run.output)
                else:
                    self.assertNotIn(tries_line(2).split("2")[0], run.output, run.describe())


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class TheRefusal(unittest.TestCase):

    def test_it_says_the_contract_sentence_word_for_word_and_builds_nothing(self):
        run = announce(1000, None)
        self.assertEqual(run.returncode, 1, run.describe())
        for line in the_rule()["sentence"]:
            self.assertIn(line, run.output)
        self.assertNotIn(ANNOUNCEMENT, run.output)

    def test_it_leaves_exactly_one_line_on_the_trail(self):
        expected = the_trail_line().replace("{course}", "ICS4U").replace("{section}", "2")
        run = announce(1000, None)
        lines = run.trail.splitlines()
        self.assertEqual(len(lines), 1, run.trail)
        self.assertTrue(lines[0].endswith(" · " + expected), run.trail)

    def test_the_bound_is_twenty_tries_and_sixty_after_starting_the_builder(self):
        """The one number a teacher on a broken Mac waits for, and the longer
        one for the run that started the builder's virtual machine."""
        run = announce(1000, None)
        self.assertEqual(len(run.curl_calls), the_rule()["attempts"])
        run = announce(1000, None, started_this_run=True)
        self.assertEqual(len(run.curl_calls), the_rule()["attemptsWhenThisRunStartedTheBuilder"])

    def test_the_words_name_no_machinery(self):
        run = announce(1000, None)
        words = set(re.findall(r"[a-z]+", run.output.lower()))
        for forbidden in MACHINERY_WORDS:
            self.assertNotIn(forbidden, words)
        run = announce(3, 52)
        words = set(re.findall(r"[a-z]+", run.output.lower().split("preview will be available")[0]))
        for forbidden in MACHINERY_WORDS:
            self.assertNotIn(forbidden, words)


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class ItFailsOpen(unittest.TestCase):

    def test_every_answer_but_a_refused_connection_goes_ahead(self):
        """Only curl's exit 7 means nothing is there. Any other answer — an
        error curl has a number for, or one it does not — is not proof, and
        must not stop a preview that would have worked before #234."""
        failures = []
        for code in range(0, 256):
            if code == 7:
                continue
            run = announce(0, code)
            if run.returncode != 0 or ANNOUNCEMENT not in run.output or len(run.curl_calls) != 1:
                failures.append(code)
        self.assertEqual(failures, [])

    def test_a_mac_with_no_curl_at_all_goes_ahead(self):
        run = announce(0, None, stub_curl=False)
        self.assertEqual(run.returncode, 0, run.describe())
        self.assertIn(ANNOUNCEMENT, run.output)
        self.assertEqual(run.sleeps, [])


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class TheQuestionIsPutTheRightWay(unittest.TestCase):

    def test_curl_is_asked_about_the_announced_port_on_this_mac_with_no_proxy(self):
        run = announce(0, 52)
        self.assertEqual(len(run.curl_calls), 1, run.describe())
        arguments = run.curl_calls[0]
        # -q must be FIRST, or curl has already read the teacher's ~/.curlrc.
        self.assertEqual(arguments[0], "-q")
        self.assertIn("--noproxy", arguments)
        self.assertEqual(arguments[arguments.index("--noproxy") + 1], "*")
        self.assertIn("--max-time", arguments)
        self.assertIn("http://127.0.0.1:" + HOST_PORT + "/", arguments)
        for argument in arguments:
            self.assertNotIn(":" + INSIDE_PORT, argument)


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class WhoseAddressItIs(unittest.TestCase):
    """previewPorts.whenAnotherAccountHasTheAddress, every case (#310)."""

    def run_case(self, case: dict) -> Run:
        reach = case["reach"]
        refused_first = 1000 if reach == 7 else 0
        then = None if reach == 7 else reach
        return announce(refused_first, then, build_only=case.get("buildOnly", False),
                        looks=case["looks"] or [], context=case["context"],
                        docker_host=case.get("dockerHost"), port_after_remake=case.get("portAfterRemake"))

    def test_every_case(self):
        rule = the_ownership_rule()
        prefix = the_address_held_entry()["marker"]["prefix"]
        self.assertGreaterEqual(len(rule["cases"]), 12)
        for case in rule["cases"]:
            with self.subTest(case=case["why"]):
                run = self.run_case(case)
                self.assertEqual(run.asked("remake_the_workspace"), case["remakes"], run.describe())
                self.assertLessEqual(run.asked("remake_the_workspace"), rule["remakesAtMost"])
                if case["netstatAsked"]:
                    self.assertEqual(run.asked("netstat"), len(case["looks"]), run.describe())
                else:
                    self.assertEqual(run.asked("netstat") + run.asked("lsof"), 0, run.describe())
                expected_markers = []
                port = HOST_PORT
                for outcome in case["markers"]:
                    if outcome == "refused":
                        port = str(case["portAfterRemake"])
                    expected_markers.append(f"{prefix} {outcome} {port} ICS4U/2")
                self.assertEqual(run.markers(), expected_markers, run.describe())
                outcome = case["outcome"]
                if outcome == "announces":
                    self.assertEqual(run.returncode, 0, run.describe())
                    self.assertIn(f"{ANNOUNCEMENT}http://localhost:{case['announces']}/\n", run.output)
                    self.assertEqual(run.output.count(ANNOUNCEMENT), 1, run.describe())
                elif outcome == "refuses":
                    self.assertEqual(run.returncode, rule["exitCode"], run.describe())
                    self.assertNotIn(ANNOUNCEMENT, run.output)
                    for line in rule["sentence"]:
                        self.assertIn(line, run.output)
                elif outcome == "reachRefuses":
                    self.assertEqual(run.returncode, the_rule()["exitCode"], run.describe())
                    self.assertNotIn(ANNOUNCEMENT, run.output)
                    for line in the_rule()["sentence"]:
                        self.assertIn(line, run.output)
                elif outcome == "asksNothing":
                    self.assertEqual(run.returncode, 0, run.describe())
                    self.assertEqual(run.output, "", run.describe())
                    self.assertEqual(run.calls, [], run.describe())
                else:
                    self.fail("unknown outcome " + outcome)
                if case["remakes"]:
                    for line in the_hostblock_remade_lines():
                        self.assertIn(line, run.output)

    def test_the_ownership_look_comes_after_the_reach_check(self):
        body = function_named("announce_the_preview_address")
        reach = body.find('this_mac_can_reach_the_builder "$host_port"')
        owner = body.find('held_by_someone_else "$host_port"')
        self.assertGreater(reach, 0)
        self.assertGreater(owner, reach)
        self.assertLess(owner, body.find(ANNOUNCEMENT))

    def test_the_sentence_names_no_machinery(self):
        rule = the_ownership_rule()
        entry = the_address_held_entry()
        lines = list(rule["sentence"])
        for key in ["lineWhenRemadeBeforeStarting", "lineWhenRemade", "lineWhenRefused", "lineWhenUnchecked"]:
            lines.append(entry[key])
        for line in lines:
            words = set(re.findall(r"[a-z]+", line.lower()))
            for forbidden in MACHINERY_WORDS + ["lsof", "netstat", "ssh", "uid", "root"]:
                self.assertNotIn(forbidden, words, line)

    def test_the_launcher_prints_the_contract_words(self):
        text = the_launcher_text()
        for line in the_ownership_rule()["sentence"]:
            self.assertIn(line, text)
        for outcome in ["remade", "refused", "unchecked"]:
            self.assertIn(f"tell_the_app_the_address_was_held {outcome} \"$host_port\"", text)


def the_hostblock_remade_lines() -> list:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8"))
    return rules["previewPorts"]["hostBlockClash"]["saysWhenAStoppedWorkspaceIsRemade"]


# Deliberately NOT gated on bash: these read the files as text.
class TheLauncherAndTheContractAgree(unittest.TestCase):

    def test_the_numbers_are_the_contracts(self):
        rule = the_rule()
        self.assertEqual(int(the_setting("PREVIEW_REACH_ATTEMPTS")), rule["attempts"])
        self.assertEqual(int(the_setting("PREVIEW_REACH_ATTEMPTS_WHEN_THIS_RUN_STARTED_THE_BUILDER")),
                         rule["attemptsWhenThisRunStartedTheBuilder"])
        self.assertEqual(float(the_setting("PREVIEW_REACH_PAUSE_SECONDS")), rule["pauseSeconds"])

    def test_the_sentences_name_no_machinery(self):
        rule = the_rule()
        text = " ".join(rule["sentence"]) + " " + rule["reachedAfterRetrying"] + " " + the_trail_line()
        words = set(re.findall(r"[a-z]+", text.lower()))
        for forbidden in MACHINERY_WORDS:
            self.assertNotIn(forbidden, words)

    def test_the_launcher_prints_the_contract_words(self):
        text = the_launcher_text()
        for line in the_rule()["sentence"]:
            self.assertIn(line, text)
        self.assertIn(the_rule()["reachedAfterRetrying"].replace("{tries}", "${attempt}"), text)
        self.assertIn(the_trail_line().replace("{course}", "${COURSE}").replace("{section}", "${SECTION}"), text)

    def test_the_check_comes_before_the_announcement(self):
        body = function_named("announce_the_preview_address")
        check = body.find('this_mac_can_reach_the_builder "$host_port"')
        announcement = body.find(ANNOUNCEMENT)
        self.assertGreater(check, 0, "announce_the_preview_address no longer asks")
        self.assertLess(check, announcement)

    def test_a_run_that_starts_the_builder_says_so(self):
        """The longer bound depends on this flag being set on every path that
        starts the builder's virtual machine, and on none that finds it running."""
        body = function_named("ensure_container_runtime")
        flag = body.find("THIS_RUN_STARTED_THE_BUILDER=1")
        self.assertGreater(flag, 0, "ensure_container_runtime no longer sets the flag")
        self.assertGreater(flag, body.find("return 0"), "the flag is set on the fast path")
        self.assertLess(flag, body.find("colima start"), "the flag is set after a start")
        # The flag is set identically in all three launchers, so their copies
        # of the first-run code stay the same text (#263 checks that). Only
        # preview.sh reads it.
        for launcher in ["setup.sh", "preview.sh", "deploy.sh"]:
            text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            self.assertRegex(text, r'(?m)^THIS_RUN_STARTED_THE_BUILDER=""\nensure_container_runtime$', launcher)
            self.assertIn("  THIS_RUN_STARTED_THE_BUILDER=1\n", text, launcher)


if __name__ == "__main__":
    unittest.main(verbosity=2)

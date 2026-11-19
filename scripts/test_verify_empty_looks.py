#!/usr/bin/env python3
"""
An empty answer does not end a `verify.sh` run (GitHub #972).

`verify.sh` runs under `set -euo pipefail`. A command substitution whose
pipeline starts with `lsof`, `grep`, `find` or `docker port` takes that
command's exit 1 when it has nothing to report, and set -e then ends the run
on the spot: no FAIL line, no summary. That is how the #684 retry loop died
on its first look on the second Mac, where the port forward comes up a
moment late, and the loop never looked a second time.

**How this runs the real thing.** Each line is cut out of the repository's
`verify.sh` by the name it assigns, not retyped, and run under `/bin/bash`
with `set -euo pipefail`. `lsof`, `docker`, `grep` and `find` are stand-ins
on PATH that print nothing and exit 1, which is what each does with nothing
to report; `sleep` is a stand-in that returns at once and counts the waits.

**Windows.** Skipped where there is no bash that can run a program;
`verify.sh` is a mac gate and Windows has nothing to mirror.

Pure stdlib. Run with:

    python3 scripts/test_verify_empty_looks.py
"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT

BASH = "/bin/bash" if Path("/bin/bash").exists() else "bash"

# The lines whose pipeline may find nothing by design, each followed in
# verify.sh by a check that says what an empty answer means.
ASSIGNMENTS_THAT_MAY_FIND_NOTHING = [
    "_site_port",
    "_ws_port",
    "RENDERED_DONE",
    "RENDERED_NOT_RUN",
    "RED_DONE",
    "SWIFT_READY_FIRST",
    "COLON_BUILT_PAGES",
    "COLON_PUBLISHED_PAGES",
]

# A stand-in that prints nothing and exits 1, as each of these does when it
# has nothing to report.
FINDS_NOTHING = "#!/bin/sh\nexit 1\n"

# lsof's stand-in counts its looks, and from look ANSWER_FROM on it answers
# the way lsof does when the forward is up: a header, then one line per
# listener. ANSWER_FROM of 0 means it never answers.
LSOF = """#!/bin/sh
count_file="$STAND_INS/lsof_looks"
looks=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))
echo "$looks" > "$count_file"
if [ "$ANSWER_FROM" -gt 0 ] && [ "$looks" -ge "$ANSWER_FROM" ]; then
  echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
  echo "ssh 1 me 3u IPv4 0 0t0 TCP 127.0.0.1:8081 (LISTEN)"
  exit 0
fi
exit 1
"""

SLEEP = """#!/bin/sh
echo waited >> "$STAND_INS/sleeps"
"""


def verify_text() -> str:
    return (REPOSITORY_ROOT / "verify.sh").read_text(encoding="utf-8")


def the_assignment(name: str) -> str:
    """The one line of verify.sh that assigns `name` from a command substitution."""
    found = []
    for line in verify_text().splitlines():
        if line.strip().startswith(name + '="$('):
            found.append(line.strip())
    if len(found) != 1:
        raise AssertionError(f"verify.sh has {len(found)} lines assigning {name}, expected one")
    return found[0]


def the_retry_loop() -> str:
    """The #684 port check's retry loop, from its empty start to its `done`."""
    text = verify_text()
    start = text.find('  _listening=""\n')
    if start < 0:
        raise AssertionError("verify.sh has no _listening retry loop")
    end = text.find("\n  done\n", start)
    if end < 0:
        raise AssertionError("verify.sh's _listening retry loop has no done")
    return text[start:end + len("\n  done\n")]


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class AnEmptyAnswerIsNotTheEnd(unittest.TestCase):

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.stand_ins = Path(self.scratch.name)
        for name in ("docker", "grep", "find"):
            self.write_stand_in(name, FINDS_NOTHING)
        self.write_stand_in("lsof", LSOF)
        self.write_stand_in("sleep", SLEEP)

    def tearDown(self):
        self.scratch.cleanup()

    def write_stand_in(self, name: str, body: str) -> None:
        path = self.stand_ins / name
        path.write_text(body, encoding="utf-8")
        path.chmod(0o755)

    def run_under_pipefail(self, lines: str, answer_from: int = 0) -> subprocess.CompletedProcess:
        program = "set -euo pipefail\nCONTAINER_NAME=nobody\n" + lines + '\necho "REACHED [${_listening:-}]"\n'
        environment = {
            "PATH": f"{self.stand_ins}:/usr/bin:/bin",
            "STAND_INS": str(self.stand_ins),
            "ANSWER_FROM": str(answer_from),
        }
        return subprocess.run([BASH, "-c", program], env=environment, capture_output=True,
                              text=True, timeout=30, cwd=self.scratch.name)

    def looks(self) -> int:
        count_file = self.stand_ins / "lsof_looks"
        if not count_file.exists():
            return 0
        return int(count_file.read_text(encoding="utf-8").strip())

    def test_each_assignment_survives_finding_nothing(self):
        for name in ASSIGNMENTS_THAT_MAY_FIND_NOTHING:
            with self.subTest(name=name):
                result = self.run_under_pipefail(the_assignment(name))
                self.assertEqual(result.returncode, 0, f"{name}: {result.stdout}{result.stderr}")
                self.assertIn("REACHED", result.stdout)

    def test_the_retry_loop_looks_ten_times_when_nothing_listens(self):
        result = self.run_under_pipefail("_site_port=8081\n_ws_port=9081\n" + the_retry_loop())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("REACHED []", result.stdout)
        self.assertEqual(self.looks(), 10, "the loop did not look ten times")

    def test_the_retry_loop_waits_for_a_late_forward(self):
        result = self.run_under_pipefail("_site_port=8081\n_ws_port=9081\n" + the_retry_loop(), answer_from=3)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("REACHED [127.0.0.1:8081 ]", result.stdout)
        self.assertEqual(self.looks(), 3, "the loop did not stop at the look that answered")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""
What a teacher is told when a publishing token is refused, or could not be
checked — and that a saved token is cleared only when the service SAYS no.

Two pieces of work share this file because they share two launcher lines and
one rule about lifting them:

  * GitHub #695. A token pasted for Cloudflare that Cloudflare refuses makes
    both launchers print two lines and exit 1, and until #695 the window said
    only "Something went wrong". `contracts/app-rules.json` ->
    `failureExplanations.cases` now LIFTS those lines into the sentence the
    teacher reads. The sentence is the launchers' own, joined, not a second
    wording of it — so the first half of this file pins the launchers' lines
    to the contract's `expect`, in BOTH launchers, the way
    `test_reference_course.py` pins the "cannot tell" refusal. Change the words
    in a launcher and this fails until the contract moves with them.

  * GitHub #716. `deploy.sh` checked a SAVED token with the same yes/no probe
    the paste check uses, which throws curl's errors away, so an offline Mac
    (a captive portal, school Wi-Fi that dropped for a moment, a deploy set
    for half six on a laptop that had not joined the network yet) heard "no",
    deleted a good token — and for Cloudflare its account too — and asked for
    another, which a deploy set for later cannot even answer. It now clears
    the token only on HTTP 400, 401 or 403 whose body is the service's own
    answer (not a web filter's block page), keeps it otherwise, and stops
    with two lines of its own that the contract lifts the same way. The
    second half of this file RUNS the real launcher's credential section with
    `curl` replaced by a stub that answers with a chosen status, and reads
    what was cleared.

`deploy.ps1`'s half of #716 is Windows' #705 (1.9.3): it prints the same
"could not reach" lines, which the drift check below pins to the contract,
and its three-word rule runs against `contracts/app-rules.json` ->
`savedTokenCheck.cases` in `windows-app/test_launcher_rules.ps1`. Since #771
the last class here runs the same cases through deploy.sh's
`token_check_answer`, and pins its addresses and patterns to the contract's.

Both launchers are read with encoding="utf-8" (deploy.sh's ❌ and em dashes
would not survive a Windows code page) and line by line with the ending
stripped, because a Windows checkout may hold deploy.ps1 with CRLF. This file
is discovered by Windows' `PythonToolchainTests` and listed in verify.sh's
step 0 on the mac.

Pure stdlib, no Docker, no network, no credentials, and nothing is written to
the Keychain: every credential reader and writer the run reaches is stubbed,
and the run is stopped before the website builder. Run with:

    python3 scripts/test_deploy_token_refusal.py
"""

import atexit
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

# Every launcher run here keeps its trail in a folder of its own (#737, #738):
# a run refused by a deploy elsewhere on this Mac must never write the
# teacher's real activity log. Set on this process, so every launcher run
# below inherits it, whichever way its environment is built.
_TRAIL_FOLDER = tempfile.mkdtemp(prefix="plantoir-test-trail-")
os.environ["PLANTOIR_TRAIL_DIR"] = _TRAIL_FOLDER
atexit.register(shutil.rmtree, _TRAIL_FOLDER, True)

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))

import contracts  # noqa: E402
import test_deploy_non_interactive as launcher_harness  # noqa: E402

# The words that find each pair of lines. They are the launchers' own, and the
# Swift explainer matches on the same ones (FailureExplainer.tokenRefusedMarker
# and .savedTokenUnheardMarker).
REFUSED_MARKER = "Cloudflare did not accept that token"
UNHEARD_MARKER = "to check the saved token, so this section was not deployed there"

# deploy.sh exits with "This script targets macOS" before any credential
# question, so the half of this file that RUNS it has nothing to drive
# anywhere else.
ON_A_MAC = sys.platform == "darwin"


def _launcher_lines(name: str) -> list:
    text = (REPOSITORY_ROOT / name).read_text(encoding="utf-8")
    lines = []
    for line in text.split("\n"):
        lines.append(line.rstrip("\r"))
    return lines


def _printed(line: str):
    """The string an `echo "…"` or `Write-Host "…"` line prints, or None."""
    match = re.match(r'^\s*(?:echo|Write-Host)\s+"(.*)"\s*$', line)
    if match is None:
        return None
    return match.group(1)


def _as_one_sentence(first: str, second: str) -> str:
    """Two printed lines as the teacher reads them: the cross and the indent
    taken off, joined with a space."""
    lifted = first
    while lifted and not (lifted[0].isascii() and lifted[0].isalnum()):
        lifted = lifted[1:]
    return lifted.strip() + " " + second.strip()


def _sentences_printed_after(lines: list, marker: str) -> list:
    """Every pair of printed lines whose first carries `marker`, as the one
    sentence each pair makes."""
    sentences = []
    for index, line in enumerate(lines):
        first = _printed(line)
        if first is None or marker not in first:
            continue
        second = _printed(lines[index + 1]) if index + 1 < len(lines) else None
        if second is None:
            raise AssertionError(
                f"the line after {first!r} is not a printed line, so the launcher no "
                "longer says this sentence in the two lines the contract joins"
            )
        sentences.append(_as_one_sentence(first, second))
    return sentences


def _expects_for(marker: str) -> list:
    expects = []
    for case in contracts.section("app-rules", "failureExplanations", "cases"):
        if marker in case["output"]:
            expects.append(case["expect"])
    return expects


class TheLaunchersSayWhatTheContractLifts(unittest.TestCase):

    def test_the_contract_carries_both_shapes_of_the_refusal(self):
        cases = []
        for case in contracts.section("app-rules", "failureExplanations", "cases"):
            if REFUSED_MARKER in case["output"]:
                cases.append(case)
        self.assertEqual(len(cases), 2, "one case in deploy.sh's shape and one in deploy.ps1's")
        crossed = 0
        for case in cases:
            if "❌ " + REFUSED_MARKER in case["output"]:
                crossed += 1
        self.assertEqual(crossed, 1, "exactly one case carries the bash launcher's cross")

    def test_deploy_sh_says_the_refusal_word_for_word(self):
        said = _sentences_printed_after(_launcher_lines("deploy.sh"), REFUSED_MARKER)
        self.assertEqual(len(said), 1, "deploy.sh refuses a pasted Cloudflare token in one place")
        for expect in _expects_for(REFUSED_MARKER):
            self.assertEqual(said[0], expect)

    def test_deploy_ps1_says_the_refusal_word_for_word(self):
        said = _sentences_printed_after(_launcher_lines("deploy.ps1"), REFUSED_MARKER)
        self.assertEqual(len(said), 1, "deploy.ps1 refuses a pasted Cloudflare token in one place")
        for expect in _expects_for(REFUSED_MARKER):
            self.assertEqual(said[0], expect)

    def test_deploy_sh_says_both_could_not_reach_sentences_word_for_word(self):
        said = _sentences_printed_after(_launcher_lines("deploy.sh"), UNHEARD_MARKER)
        expects = _expects_for(UNHEARD_MARKER)
        self.assertEqual(len(expects), 2, "one case for Cloudflare and one for Netlify")
        self.assertEqual(sorted(said), sorted(expects))

    def test_deploy_ps1_if_it_says_them_says_them_word_for_word(self):
        """Windows' #705 added them (1.9.3); each one must be a contract sentence."""
        said = _sentences_printed_after(_launcher_lines("deploy.ps1"), UNHEARD_MARKER)
        expects = _expects_for(UNHEARD_MARKER)
        for sentence in said:
            self.assertIn(sentence, expects)


def _a_stubbed_working_folder(tmp: str) -> Path:
    """A scratch folder holding a copy of deploy.sh whose credential readers,
    writers and `curl` are stubbed, and which stops before the website
    builder.

    A COPY, because the launcher's second line is `cd "$(dirname "$0")"`. The
    stubs go in front of the Cloudflare section's marker, so everything the
    test is about — `token_check_answer`, the saved-token checks and what they
    clear — is the real code, and the markers are asserted so a rename fails
    the test rather than skipping it.
    """
    folder = Path(tmp)
    built = folder / "courses" / "ICS3U" / ".merged_output" / "section1" / "public"
    built.mkdir(parents=True)
    (built / "index.html").write_text("<html>a built site</html>", encoding="utf-8")
    # Built by the image the runs here name (#746), so no deploy builds again.
    (built.parent / ".built-with-toolchain").write_text("unused:tag\n", encoding="utf-8")

    text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
    credentials = "# -------------------- Cloudflare token and account ---------------------\n"
    builder = "# ==================== Container runtime (Colima) ====================\n"
    for marker in (credentials, builder):
        if text.count(marker) != 1:
            raise AssertionError(f"deploy.sh no longer carries the marker {marker.strip()!r}")

    stubs = (
        # The status curl is made to answer with comes from the environment,
        # and 000 is what curl writes when nothing answered, exiting 28 the way
        # a timeout does.
        "curl() {\n"
        "  printf '%s\\n%s' \"${FAKE_BODY:-}\" \"${FAKE_STATUS:-000}\"\n"
        "  [[ \"${FAKE_STATUS:-000}\" != 000 ]] || return 28\n"
        "}\n"
        "get_cf_token_keychain() { printf '%s' 'stub-token-never-leaves-this-test'; }\n"
        "set_cf_token_keychain() { :; }\n"
        "delete_cf_token_keychain() { echo 'CLEARED-THE-CLOUDFLARE-TOKEN'; }\n"
        "discover_cf_account() { printf '%s' '0123456789abcdef0123456789abcdef'; }\n"
        "get_cf_account_keychain() { printf '%s' ''; }\n"
        "set_cf_account_keychain() { :; }\n"
        "delete_cf_account_keychain() { echo 'CLEARED-THE-CLOUDFLARE-ACCOUNT'; }\n"
        "get_token_keychain() { printf '%s' 'stub-token-never-leaves-this-test'; }\n"
        "set_token_keychain() { :; }\n"
        "delete_token_keychain() { echo 'CLEARED-THE-NETLIFY-TOKEN'; }\n"
    )
    stop = "echo 'REACHED-THE-WEBSITE-BUILDER'\nexit 0\n"
    text = text.replace(credentials, stubs + credentials).replace(builder, stop + builder)
    (folder / "deploy.sh").write_text(text, encoding="utf-8")
    return folder


@unittest.skipUnless(ON_A_MAC and shutil.which("bash"), "deploy.sh runs only on a Mac")
class ASavedTokenIsClearedOnlyWhenTheServiceSaysNo(unittest.TestCase):

    def run_with(self, target: str, status: str, body: str = ""):
        with tempfile.TemporaryDirectory() as tmp:
            folder = _a_stubbed_working_folder(tmp)
            environment = dict(os.environ, FAKE_STATUS=status, FAKE_BODY=body)
            result = subprocess.run(
                ["bash", str(folder / "deploy.sh"), "ICS3U", "1", "--image", "unused:tag",
                 "--target", target, "--non-interactive"],
                capture_output=True, timeout=180, cwd=str(folder),
                stdin=subprocess.DEVNULL, env=environment,
            )
            return (result.returncode,
                    result.stdout.decode("utf-8", "replace") + result.stderr.decode("utf-8", "replace"))

    def assert_cleared(self, target: str, status: str, body: str = ""):
        code, said = self.run_with(target, status, body)
        if target == "cloudflare":
            self.assertIn("CLEARED-THE-CLOUDFLARE-TOKEN", said, f"HTTP {status} is a refusal")
            self.assertIn("CLEARED-THE-CLOUDFLARE-ACCOUNT", said)
        else:
            self.assertIn("CLEARED-THE-NETLIFY-TOKEN", said, f"HTTP {status} is a refusal")
        self.assertIn("no longer works, so it has been cleared", said)
        self.assertNotIn(UNHEARD_MARKER, said)
        # Cleared, it goes on to ask for a new one, which under the flag is a
        # refusal (exit 3), never the website builder.
        self.assertEqual(code, 3, said)

    def assert_kept(self, target: str, status: str, body: str = ""):
        code, said = self.run_with(target, status, body)
        self.assertNotIn("CLEARED-THE", said, f"HTTP {status} says nothing about the token")
        self.assertNotIn("no longer works", said)
        self.assertIn(UNHEARD_MARKER, said)
        self.assertNotIn("REACHED-THE-WEBSITE-BUILDER", said)
        self.assertEqual(code, 1, said)

    def assert_used(self, target: str, status: str, body: str = ""):
        code, said = self.run_with(target, status, body)
        self.assertNotIn("CLEARED-THE", said)
        self.assertNotIn(UNHEARD_MARKER, said)
        self.assertIn("REACHED-THE-WEBSITE-BUILDER", said)
        self.assertEqual(code, 0, said)

    def test_cloudflare_refusals_clear_the_token_and_its_account(self):
        refused = '{"success":false,"errors":[{"code":1000,"message":"Invalid API Token"}]}'
        for status in ("400", "401", "403"):
            with self.subTest(status=status):
                self.assert_cleared("cloudflare", status, refused)

    def test_cloudflare_unheard_keeps_the_token_and_stops(self):
        for status in ("000", "429", "500", "503", "302"):
            with self.subTest(status=status):
                self.assert_kept("cloudflare", status, "<html>a captive portal</html>")

    def test_cloudflare_an_answer_that_does_not_say_yes_keeps_it_too(self):
        self.assert_kept("cloudflare", "200", "<html>a captive portal</html>")

    def test_cloudflare_a_refusal_that_is_not_cloudflares_keeps_it(self):
        """A school web filter's block page, or a firewall's challenge in front
        of the API, comes back as a 403 that never asked Cloudflare."""
        for status in ("401", "403"):
            with self.subTest(status=status):
                self.assert_kept("cloudflare", status, "<html>Blocked by the school's web filter</html>")

    def test_cloudflare_an_accepted_token_is_used(self):
        self.assert_used("cloudflare", "200",
                         '{"result":{"status":"active"},"success":true,"errors":[]}')

    def test_netlify_refusals_clear_the_token(self):
        for status in ("401", "403"):
            with self.subTest(status=status):
                self.assert_cleared("netlify", status, '{"code":%s,"message":"Access Denied"}' % status)

    def test_netlify_unheard_keeps_the_token_and_stops(self):
        for status in ("000", "502", "503"):
            with self.subTest(status=status):
                self.assert_kept("netlify", status)

    def test_netlify_a_refusal_that_is_not_netlifys_keeps_it(self):
        for status in ("401", "403"):
            with self.subTest(status=status):
                self.assert_kept("netlify", status, "<html>Blocked by the school's web filter</html>")

    def test_netlify_an_answer_that_is_not_the_account_keeps_it(self):
        self.assert_kept("netlify", "200", "<html>a captive portal</html>")

    def test_netlify_an_accepted_token_is_used(self):
        self.assert_used("netlify", "200", '{"id":"someone"}')


def _cut_from_deploy_sh(name: str) -> str:
    """The text deploy.sh carries between `# BEGIN name` and `# END name`."""
    text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
    begin = f"# BEGIN {name}\n"
    end = f"# END {name}\n"
    if text.count(begin) != 1 or text.count(end) != 1:
        raise AssertionError(f"deploy.sh no longer carries {name} between its markers")
    return text[text.index(begin) + len(begin):text.index(end)]


# Each service's four values, as deploy.sh names them.
THE_LAUNCHERS_NAMES = {
    "cloudflare": {
        "url": "CLOUDFLARE_TOKEN_CHECK_URL",
        "acceptedWhenTheBodyMatches": "CLOUDFLARE_TOKEN_ACCEPTED",
        "refusedWhenTheBodyMatches": "CLOUDFLARE_TOKEN_REFUSED",
    },
    "netlify": {
        "url": "NETLIFY_TOKEN_CHECK_URL",
        "acceptedWhenTheBodyMatches": "NETLIFY_TOKEN_ACCEPTED",
        "refusedWhenTheBodyMatches": "NETLIFY_TOKEN_REFUSED",
    },
}

# The token each call site passes, after the URL.
THE_LAUNCHERS_TOKENS = {"cloudflare": "CF_TOKEN", "netlify": "TOKEN"}


class TheSavedTokenRuleIsTheContracts(unittest.TestCase):
    """GitHub #771: deploy.sh runs `contracts/app-rules.json` ->
    `savedTokenCheck`, the cases Windows proposed (#705) and deploy.ps1 runs.

    The function and the six values are CUT from deploy.sh and run in a bash
    of their own, with `curl` replaced by a stub that answers with the case's
    status and body. Function-level rather than a whole launcher per case:
    the class above already runs the call sites end to end, and 25 launcher
    runs would cost minutes.
    """

    def setUp(self):
        # Not the `bash` on PATH: on Windows that is the WSL launcher (see
        # test_deploy_non_interactive). Git Bash runs these there.
        self.shell = launcher_harness._a_bash_that_can_run_deploy_sh()
        if self.shell is None:
            self.skipTest("no bash on this machine that can run deploy.sh's definitions")

    def _bash(self, script: str, *arguments, environment=None):
        result = subprocess.run(
            self.shell + ["-c", script, "_", *arguments],
            capture_output=True, timeout=60, env=environment,
        )
        return result.returncode, result.stdout.decode("utf-8", "replace")

    def test_the_launchers_addresses_and_patterns_are_the_contracts(self):
        """MUST-FAIL before #771, whose patterns were written [[:space:]]:
        right in grep, and read by .NET as a set of letters."""
        services = contracts.section("app-rules", "savedTokenCheck", "services")
        self.assertEqual(sorted(services), sorted(THE_LAUNCHERS_NAMES))
        rules = _cut_from_deploy_sh("saved_token_check_rules")
        for service, names in THE_LAUNCHERS_NAMES.items():
            for key, variable in names.items():
                with self.subTest(service=service, key=key):
                    # NUL-ended, so a trailing TAB or space would show.
                    code, said = self._bash(rules + f'\nprintf "%s\\0" "${variable}"\n')
                    self.assertEqual(code, 0, said)
                    self.assertEqual(said, services[service][key] + "\0")

    def test_each_saved_token_check_passes_its_services_values(self):
        """The values above are what the two checks hand token_check_answer,
        not six names that nothing reads."""
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        calls = []
        for line in text.split("\n"):
            if "token_check_answer " in line and "#" not in line.split("token_check_answer")[0]:
                calls.append(line.strip())
        self.assertEqual(len(calls), 2, calls)
        for service, names in THE_LAUNCHERS_NAMES.items():
            with self.subTest(service=service):
                expected = (
                    f'token_check_answer "${names["url"]}" "${THE_LAUNCHERS_TOKENS[service]}" '
                    f'"${names["acceptedWhenTheBodyMatches"]}" "${names["refusedWhenTheBodyMatches"]}")'
                )
                found = False
                for call in calls:
                    if expected in call:
                        found = True
                self.assertTrue(found, f"no call passes {expected}; the calls are {calls}")

    def test_every_case_is_answered_as_the_contract_says(self):
        rule = contracts.section("app-rules", "savedTokenCheck")
        self.assertEqual(sorted(rule["refusalStatuses"]), [400, 401, 403])
        script = (
            _cut_from_deploy_sh("saved_token_check_rules")
            + _cut_from_deploy_sh("token_check_answer")
            # The stub the class above uses: 000 when nothing answered, with
            # the exit code a timeout gives.
            + "curl() {\n"
            "  printf '%s\\n%s' \"${FAKE_BODY:-}\" \"${FAKE_STATUS:-000}\"\n"
            "  [[ \"${FAKE_STATUS:-000}\" != 000 ]] || return 28\n"
            "}\n"
            'case "$1" in\n'
            '  cloudflare) token_check_answer "$CLOUDFLARE_TOKEN_CHECK_URL" a-token '
            '"$CLOUDFLARE_TOKEN_ACCEPTED" "$CLOUDFLARE_TOKEN_REFUSED" ;;\n'
            '  netlify) token_check_answer "$NETLIFY_TOKEN_CHECK_URL" a-token '
            '"$NETLIFY_TOKEN_ACCEPTED" "$NETLIFY_TOKEN_REFUSED" ;;\n'
            "esac\n"
        )
        self.assertTrue(rule["cases"], "the contract carries no cases to run")
        for case in rule["cases"]:
            with self.subTest(case=case["name"]):
                status = "000" if case["status"] == 0 else str(case["status"])
                environment = dict(os.environ, FAKE_STATUS=status, FAKE_BODY=case["body"])
                code, said = self._bash(script, case["service"], environment=environment)
                self.assertEqual(code, 0, said)
                self.assertEqual(said.strip(), case["expect"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

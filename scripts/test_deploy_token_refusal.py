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
    the token only on HTTP 400, 401 or 403, keeps it otherwise, and stops
    with two lines of its own that the contract lifts the same way. The
    second half of this file RUNS the real launcher's credential section with
    `curl` replaced by a stub that answers with a chosen status, and reads
    what was cleared.

`deploy.ps1`'s half of #716 is Windows' issue #705: until it lands that
launcher prints no "could not reach" lines, and the drift check below asks
only that IF it carries them they say what the contract says.

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

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))

import contracts  # noqa: E402

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
        """Windows' #705 is what adds them; until then there is nothing to pin."""
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

    def test_cloudflare_an_accepted_token_is_used(self):
        self.assert_used("cloudflare", "200",
                         '{"result":{"status":"active"},"success":true,"errors":[]}')

    def test_netlify_refusals_clear_the_token(self):
        for status in ("401", "403"):
            with self.subTest(status=status):
                self.assert_cleared("netlify", status, '{"code":401,"message":"Unauthorized"}')

    def test_netlify_unheard_keeps_the_token_and_stops(self):
        for status in ("000", "502", "503"):
            with self.subTest(status=status):
                self.assert_kept("netlify", status)

    def test_netlify_an_accepted_token_is_used(self):
        self.assert_used("netlify", "200", '{"id":"someone"}')


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""
The teacher's deploy tokens, looked after from Plantoir ▸ Settings ▸ Deploying
and checked before they are saved (GitHub #696).

Runs `contracts/shared-rules.json` -> `deployTokens` through the REAL
`deploy.sh`:

  * `paste.cases` through `tidy_pasted_token`, `endDate.reading.cases`
    through the end-date reading and `deployTimeRefusals.lines` through
    `say_token_not_saved`, each CUT from between its markers and run in a bash
    of its own (as test_deploy_token_refusal.py cuts token_check_answer);
  * `check.cases` and `reachability.cases` through `deploy.sh --token ...`
    itself, and `reachability.deployCases` through a whole deploy, in a
    scratch working folder whose copy of the launcher has its token store
    and `curl` stubbed.

The stubs go in front of the launcher's `# >>> TOKEN MODE DISPATCH >>>`
marker, after every real definition, so the code under test is the real code.
The token store is three files in the scratch folder; `curl` answers from a
table of routes the case names (`deployTokens.check.routes`), refuses any
token but the one the case pasted, and logs every address it was asked for.
Nothing is written to the Keychain, nothing reaches the network, and every
token here is invented.

The Windows half (deploy.ps1's `--token` mode and its paste rule) is
Windows' to write: this Mac has no PowerShell, so these cases run through
deploy.sh only, and the `windows` issue for #696 asks for the same cases
through deploy.ps1.

Pure stdlib. Run with:

    python3 scripts/test_deploy_tokens.py
"""

import atexit
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

_TRAIL_FOLDER = tempfile.mkdtemp(prefix="plantoir-test-trail-")
os.environ["PLANTOIR_TRAIL_DIR"] = _TRAIL_FOLDER
atexit.register(shutil.rmtree, _TRAIL_FOLDER, True)

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))
os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))

import contracts  # noqa: E402
import test_deploy_non_interactive as launcher_harness  # noqa: E402

ON_A_MAC = sys.platform == "darwin"
GOOD_TOKEN = "good-token"
DISPATCH = "# >>> TOKEN MODE DISPATCH >>>\n"
CREDENTIALS = "# -------------------- Cloudflare token and account ---------------------\n"
BUILDER = "# ==================== Container runtime (Colima) ====================\n"


def _section(*path):
    return contracts.section("shared-rules", "deployTokens", *path)


def _cut_from_deploy_sh(name: str) -> str:
    text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
    begin = f"# BEGIN {name}\n"
    end = f"# END {name}\n"
    if text.count(begin) != 1 or text.count(end) != 1:
        raise AssertionError(f"deploy.sh no longer carries {name} between its markers")
    return text[text.index(begin) + len(begin):text.index(end)]


# `curl` and the token store, stubbed. Bash, written into the launcher copy.
STUBS = r'''
get_token_keychain() { cat "$FAKE_DIR/store-netlify" 2>/dev/null || true; }
set_token_keychain() { printf '%s' "$1" > "$FAKE_DIR/store-netlify"; }
delete_token_keychain() { rm -f "$FAKE_DIR/store-netlify"; }
get_cf_token_keychain() { cat "$FAKE_DIR/store-cloudflare" 2>/dev/null || true; }
set_cf_token_keychain() { printf '%s' "$1" > "$FAKE_DIR/store-cloudflare"; }
delete_cf_token_keychain() { rm -f "$FAKE_DIR/store-cloudflare"; }
get_cf_account_keychain() { cat "$FAKE_DIR/store-cloudflare-account" 2>/dev/null || true; }
set_cf_account_keychain() { printf '%s' "$1" > "$FAKE_DIR/store-cloudflare-account"; }
delete_cf_account_keychain() { rm -f "$FAKE_DIR/store-cloudflare-account"; }
discover_cf_account() { :; }
prune_legacy_netlify_entry() { :; }
curl() {
  local url="" token="" fail="false" write="false" previous=""
  for argument in "$@"; do
    if [[ "$previous" == "-H" && "$argument" == "Authorization: Bearer "* ]]; then
      token="${argument#Authorization: Bearer }"
    fi
    case "$argument" in
      -f|-fsS) fail="true" ;;
      -w) write="true" ;;
      http*) url="$argument" ;;
    esac
    previous="$argument"
  done
  local route="" service=""
  case "$url" in
    */api/v1/user) route="netlifyUser"; service="netlify" ;;
    */api/v1/sites/*) route="netlifySite:${url##*/sites/}"; service="netlify" ;;
    */user/tokens/verify) route="cloudflareVerify"; service="cloudflare" ;;
    */pages/projects) route="cloudflareAccountProjects"; service="cloudflare" ;;
    */pages/projects/*) route="cloudflareProject:${url##*/pages/projects/}"; service="cloudflare" ;;
    *) route="unknown" ;;
  esac
  printf '%s\n' "$route" >> "$FAKE_DIR/requests"
  local status body
  if [[ "$token" != "$FAKE_GOOD_TOKEN" ]]; then
    status=401
    if [[ "$service" == "netlify" ]]; then body='{"code":401,"message":"Access Denied"}'; else body='{"success":false,"errors":[{"code":1000,"message":"Invalid API Token"}]}'; fi
  elif [[ -f "$FAKE_DIR/routes/$route.status" ]]; then
    status="$(cat "$FAKE_DIR/routes/$route.status")"
    body="$(cat "$FAKE_DIR/routes/$route.body")"
  else
    status=0
    body=""
  fi
  if [[ "$status" == "0" ]]; then
    [[ "$write" == "true" ]] && printf '\n000'
    return 28
  fi
  if [[ "$fail" == "true" && "$status" -ge 400 ]]; then
    return 22
  fi
  if [[ "$write" == "true" ]]; then printf '%s\n%s' "$body" "$status"; else printf '%s' "$body"; fi
  return 0
}
'''


class AWorkingFolder:
    """A scratch working folder holding a stubbed copy of deploy.sh."""

    def __init__(self, tmp: str, stop_before_the_builder: bool = False):
        self.folder = Path(tmp)
        self.fake = self.folder / "fake"
        (self.fake / "routes").mkdir(parents=True)
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        # In front of the dispatch, after every real definition. A whole
        # deploy (TheDeploysOwnPaste) needs them only before the deploy's own
        # token handling, which is where a launcher without the --token mode
        # takes them, so the must-fail proof can run those cases on it.
        anchor = DISPATCH if DISPATCH in text else CREDENTIALS
        if text.count(anchor) != 1:
            raise AssertionError("deploy.sh no longer carries the marker the stubs go in front of")
        text = text.replace(anchor, STUBS + anchor)
        if stop_before_the_builder:
            if text.count(BUILDER) != 1:
                raise AssertionError("deploy.sh no longer carries the website builder's marker")
            text = text.replace(BUILDER, "echo 'REACHED-THE-WEBSITE-BUILDER'\nexit 0\n" + BUILDER)
        (self.folder / "deploy.sh").write_text(text, encoding="utf-8")

    def answer(self, answers: dict):
        for route, given in answers.items():
            (self.fake / "routes" / f"{route}.status").write_text(str(given["status"]), encoding="utf-8")
            (self.fake / "routes" / f"{route}.body").write_text(given["body"], encoding="utf-8")

    def marker(self, service: str, place: str, value: str):
        course, section = place.split("/")
        folder = ".netlify_sites" if service == "netlify" else ".cloudflare_sites"
        key = "id" if service == "netlify" else "name"
        path = self.folder / "courses" / course / folder / f"section{section}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        # As deploy.py writes it: indent=2, with a nested id further in.
        content = {key: value, "published_deploy": {"id": "a-deploy-not-the-site"}}
        path.write_text(json.dumps(content, indent=2), encoding="utf-8")

    def store(self, name: str):
        path = self.fake / f"store-{name}"
        return path.read_text(encoding="utf-8") if path.exists() else None

    def save(self, name: str, value: str):
        (self.fake / f"store-{name}").write_text(value, encoding="utf-8")

    def requests(self) -> list:
        path = self.fake / "requests"
        if not path.exists():
            return []
        return path.read_text(encoding="utf-8").split()

    def run(self, arguments: list, pasted: str = ""):
        environment = dict(os.environ, FAKE_DIR=str(self.fake), FAKE_GOOD_TOKEN=GOOD_TOKEN)
        result = subprocess.run(
            ["bash", str(self.folder / "deploy.sh")] + arguments,
            input=pasted.encode("utf-8"), capture_output=True, timeout=180,
            cwd=str(self.folder), env=environment,
        )
        return (result.returncode, result.stdout.decode("utf-8", "replace"),
                result.stderr.decode("utf-8", "replace"))


class ThePasteRule(unittest.TestCase):

    def setUp(self):
        self.shell = launcher_harness._a_bash_that_can_run_deploy_sh()
        if self.shell is None:
            self.skipTest("no bash on this machine that can run deploy.sh's definitions")

    def test_every_paste_case(self):
        rule = _cut_from_deploy_sh("token_paste_rule")
        script = rule + '\nif tidy_pasted_token "$1"; then printf "token\\0%s" "$TIDIED_TOKEN"; else printf "problem\\0%s" "$TOKEN_PASTE_PROBLEM"; fi\n'
        cases = _section("paste", "cases")
        self.assertGreaterEqual(len(cases), 15)
        for case in cases:
            with self.subTest(case=case["name"]):
                result = subprocess.run(self.shell + ["-c", script, "_", case["pasted"]],
                                        capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                kind, value = result.stdout.decode("utf-8").split("\0")
                self.assertEqual({kind: value}, case["expect"])


class TheEndDateReading(unittest.TestCase):

    def setUp(self):
        self.shell = launcher_harness._a_bash_that_can_run_deploy_sh()
        if self.shell is None:
            self.skipTest("no bash on this machine that can run deploy.sh's definitions")

    def test_every_reading_case(self):
        reading = _cut_from_deploy_sh("token_end_reading")
        script = reading + '\nprintf "%s\\0%s" "$(cloudflare_token_status_word "$1")" "$(cloudflare_token_end "$1")"\n'
        for case in _section("endDate", "reading", "cases"):
            with self.subTest(case=case["name"]):
                result = subprocess.run(self.shell + ["-c", script, "_", case["body"]],
                                        capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                status, ends = result.stdout.decode("utf-8").split("\0")
                self.assertEqual({"status": status, "endsOn": ends or None}, case["expect"])


class TheDeployTimeRefusals(unittest.TestCase):

    def setUp(self):
        self.shell = launcher_harness._a_bash_that_can_run_deploy_sh()
        if self.shell is None:
            self.skipTest("no bash on this machine that can run deploy.sh's definitions")

    def test_every_refusal_is_the_contracts_two_lines(self):
        lines = _section("deployTimeRefusals", "lines")
        function = _cut_from_deploy_sh("token_not_saved_lines")
        for key, (first, second) in lines.items():
            for service in ("Netlify", "Cloudflare"):
                with self.subTest(key=key, service=service):
                    result = subprocess.run(
                        self.shell + ["-c", function + '\nsay_token_not_saved "$1" "$2"\n', "_", key, service],
                        capture_output=True, timeout=30)
                    said = result.stdout.decode("utf-8")
                    expected = ("❌ " + first.replace("{service}", service) + "\n"
                                + "   " + second.replace("{service}", service) + "\n")
                    self.assertEqual(said, expected)
                    self.assertIn("saved as your token", first)

    def test_every_paste_problem_and_reach_answer_has_two_lines(self):
        lines = _section("deployTimeRefusals", "lines")
        for problem in ("tokenEmpty", "tokenHasSpaces", "tokenNotPlainText"):
            self.assertIn(problem, lines)
            self.assertIn(problem, _section("answerShape", "problems"))


def _expected_answer(word_problem_ends: str) -> tuple:
    answer, problem, ends = word_problem_ends.split(" ")
    return (answer, None if problem == "-" else problem, None if ends == "-" else ends)


@unittest.skipUnless(ON_A_MAC and shutil.which("bash"), "deploy.sh's token store is the mac's")
class TheTokenMode(unittest.TestCase):

    def test_every_check_case_through_status(self):
        cases = _section("check", "cases")
        self.assertGreaterEqual(len(cases), 12)
        for case in cases:
            with self.subTest(case=case["name"]), tempfile.TemporaryDirectory() as tmp:
                folder = AWorkingFolder(tmp)
                folder.answer(case["answers"])
                folder.save(case["service"], GOOD_TOKEN)
                arguments = ["--token", "status", "--target", case["service"]]
                if case.get("account"):
                    arguments += ["--account", case["account"]]
                code, out, err = folder.run(arguments)
                self.assertEqual(code, 0, out + err)
                said = json.loads(out)
                answer, problem, ends = _expected_answer(case["expect"])
                self.assertEqual((said["answer"], said["problem"], said["endsOn"]), (answer, problem, ends))
                self.assertTrue(said["saved"])
                self.assertEqual(folder.store(case["service"]), GOOD_TOKEN, "status never clears a token")

    def test_every_reachability_case(self):
        for case in _section("reachability", "cases"):
            with self.subTest(case=case["name"]), tempfile.TemporaryDirectory() as tmp:
                folder = AWorkingFolder(tmp)
                folder.answer(case["answers"])
                for marker in case["markers"]:
                    folder.marker(case["service"], marker["place"], marker["value"])
                if case.get("saved"):
                    folder.save(case["service"], GOOD_TOKEN)
                if case["service"] == "cloudflare":
                    folder.save("cloudflare-account", "0123456789abcdef0123456789abcdef")
                arguments = ["--token", case["action"], "--target", case["service"]]
                if case.get("account"):
                    arguments += ["--account", case["account"]]
                if case.get("useAnyway"):
                    arguments.append("--use-anyway")
                pasted = case.get("pasted", GOOD_TOKEN) + "\n" if case["action"] == "save" else ""
                code, out, err = folder.run(arguments, pasted=pasted)
                self.assertEqual(code, 0, out + err)
                self.assertEqual(len(out.strip().split("\n")), 1, "one line of JSON and nothing else")
                self.assertEqual(json.loads(out), case["expect"])
                if "stored" in case:
                    self.assertEqual(folder.store(case["service"]) is not None, case["stored"])
                if case.get("accountKept"):
                    self.assertIsNotNone(folder.store("cloudflare-account"))
                if "requests" in case:
                    self.assertEqual(len(folder.requests()), case["requests"], folder.requests())
                self.assertNotIn(GOOD_TOKEN, out + err, "the token is never printed")

    def test_a_refused_check_asks_about_no_site(self):
        """MUST-FAIL before #696: there was no --token mode at all."""
        with tempfile.TemporaryDirectory() as tmp:
            folder = AWorkingFolder(tmp)
            folder.answer({"netlifyUser": {"status": 200, "body": '{"id":"5f1e"}'}})
            folder.marker("netlify", "ICS3U/1", "site-one")
            code, out, err = folder.run(["--token", "save", "--target", "netlify"], pasted="wrong-token\n")
            self.assertEqual(json.loads(out)["answer"], "refused", out + err)
            self.assertEqual(folder.requests(), ["netlifyUser"])

    def test_the_mode_refuses_what_it_does_not_know(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = AWorkingFolder(tmp)
            for arguments in (["--token", "status"], ["--token", "status", "--target", "github"],
                              ["--token", "--target", "netlify"], ["--token", "keep", "--target", "netlify"]):
                with self.subTest(arguments=arguments):
                    code, out, err = folder.run(arguments)
                    self.assertEqual(code, 1, out + err)
                    self.assertTrue(out.startswith("❌"), out)


@unittest.skipUnless(ON_A_MAC and shutil.which("bash"), "deploy.sh's token store is the mac's")
class TheDeploysOwnPaste(unittest.TestCase):
    """Review MUST 1: the deploy's own paste is checked against the section's
    website before it is saved. MUST-FAIL before #696: the first and third
    cases saved the token and went on to the website builder."""

    def _a_built_section(self, folder: AWorkingFolder, place: str):
        course, section = place.split("/")
        built = folder.folder / "courses" / course / ".merged_output" / f"section{section}" / "public"
        built.mkdir(parents=True)
        (built / "index.html").write_text("<html>a built site</html>", encoding="utf-8")
        (built.parent / ".built-with-toolchain").write_text("unused:tag\n", encoding="utf-8")

    def test_every_deploy_case(self):
        lines = _section("deployTimeRefusals", "lines")
        for case in _section("reachability", "deployCases"):
            with self.subTest(case=case["name"]), tempfile.TemporaryDirectory() as tmp:
                folder = AWorkingFolder(tmp, stop_before_the_builder=True)
                folder.answer(case["answers"])
                # The marker first: written after the build, it would make the
                # course look changed since it was built (#768).
                if case.get("marker"):
                    folder.marker(case["service"], case["section"], case["marker"])
                self._a_built_section(folder, case["section"])
                course, section = case["section"].split("/")
                arguments = [course, section, "--image", "unused:tag", "--target", case["service"]]
                if case.get("account"):
                    arguments += ["--account", case["account"]]
                code, out, err = folder.run(arguments, pasted=case.get("pasted", GOOD_TOKEN) + "\n")
                said = out + err
                expect = case["expect"]
                self.assertEqual(code, expect["exit"], said)
                self.assertEqual(folder.store(case["service"]) is not None, expect["stored"], said)
                if expect["refusal"] is None:
                    self.assertIn("REACHED-THE-WEBSITE-BUILDER", said)
                    self.assertNotIn("saved as your token", said)
                else:
                    service = "Netlify" if case["service"] == "netlify" else "Cloudflare"
                    first = lines[expect["refusal"]][0].replace("{service}", service)
                    self.assertIn("❌ " + first, said)
                    self.assertNotIn("REACHED-THE-WEBSITE-BUILDER", said)
                self.assertNotIn(GOOD_TOKEN + "\n", said.replace(" ", ""))

    def test_a_cloudflare_deploy_says_the_tokens_end_date(self):
        marker_rule = _section("endDate", "marker")
        with tempfile.TemporaryDirectory() as tmp:
            folder = AWorkingFolder(tmp, stop_before_the_builder=True)
            folder.answer({"cloudflareVerify": {"status": 200, "body": '{"result":{"status":"active","expires_on":"2027-07-01T00:00:00Z"},"success":true}'}})
            self._a_built_section(folder, "MPM2D/3")
            folder.save("cloudflare", GOOD_TOKEN)
            code, out, err = folder.run(["MPM2D", "3", "--image", "unused:tag", "--target", "cloudflare",
                                         "--account", "0123456789abcdef0123456789abcdef", "--non-interactive"])
            self.assertEqual(code, 0, out + err)
            self.assertIn(marker_rule["prefix"] + " cloudflare 2027-07-01T00:00:00Z\n", out)
            self.assertEqual(marker_rule["cases"][0]["line"], marker_rule["prefix"] + " cloudflare 2027-07-01T00:00:00Z")

    def test_a_cloudflare_deploy_that_cannot_ask_says_no_date(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = AWorkingFolder(tmp, stop_before_the_builder=True)
            folder.answer({"cloudflareVerify": {"status": 200, "body": '{"result":{"status":"active"},"success":true}'}})
            self._a_built_section(folder, "MPM2D/3")
            folder.save("cloudflare", GOOD_TOKEN)
            code, out, err = folder.run(["MPM2D", "3", "--image", "unused:tag", "--target", "cloudflare",
                                         "--account", "0123456789abcdef0123456789abcdef", "--non-interactive"])
            self.assertEqual(code, 0, out + err)
            self.assertIn("PLANTOIR_TOKEN_ENDS: cloudflare none\n", out)


if __name__ == "__main__":
    unittest.main()

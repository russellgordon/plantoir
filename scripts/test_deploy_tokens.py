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
from test_deploy_sh_questions import no_request_was_made, the_network_refused  # noqa: E402

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
  local url="" token="" fail="false" write="false" previous="" header=""
  # Every argument, for the test that the token is never among them.
  printf '%s\n' "$*" >> "$FAKE_DIR/arguments"
  for argument in "$@"; do
    if [[ "$previous" == "-H" && "$argument" == "Authorization: Bearer "* ]]; then
      token="${argument#Authorization: Bearer }"
    fi
    # The header on standard input (`-H @-`), as http_answer hands it over.
    if [[ "$previous" == "-H" && "$argument" == "@-" ]]; then
      IFS= read -r header || true
      token="${header#Authorization: Bearer }"
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

    def released_marker(self, service: str, place: str, value: str, stamp: str):
        """Last year's marker, as DeployCommand.releasedMarkerName names it."""
        course, section = place.split("/")
        folder = ".netlify_sites" if service == "netlify" else ".cloudflare_sites"
        key = "id" if service == "netlify" else "name"
        path = self.folder / "courses" / course / folder / f"section{section}.previous-{stamp}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({key: value}, indent=2), encoding="utf-8")

    def legacy_marker(self, place: str, value: str):
        """The old Netlify place inside the built site, which deploy.py still reads."""
        course, section = place.split("/")
        path = self.folder / "courses" / course / ".merged_output" / f"section{section}" / ".netlify_site.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"id": value}, indent=2), encoding="utf-8")

    def plan_marker(self, course: str, year: int, value):
        """A course's shared unit plans (unit_plan_site.marker_name). With no
        value, the shape the app writes before the share's question is
        answered (PlanSharing.writeChoices: the teacher's choices only,
        pretty-printed with sorted keys, which puts a space before each
        colon; the fix review's N1)."""
        path = self.folder / "courses" / course / ".cloudflare_sites" / f"plans-{year}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        if value is None:
            choices = json.dumps({"documents": {"Unit 1/plan.md": "shared"}}, indent=2, sort_keys=True)
            path.write_text(choices.replace('": ', '" : ').replace("/", "\\/"), encoding="utf-8")
            return
        path.write_text(json.dumps({"name": value, "year": year}, indent=2), encoding="utf-8")

    def unreadable_marker(self, service: str, place: str):
        course, section = place.split("/")
        folder = ".netlify_sites" if service == "netlify" else ".cloudflare_sites"
        path = self.folder / "courses" / course / folder / f"section{section}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("not json {", encoding="utf-8")

    def arguments_given_to_curl(self) -> str:
        path = self.fake / "arguments"
        return path.read_text(encoding="utf-8") if path.exists() else ""

    def requests(self) -> list:
        path = self.fake / "requests"
        if not path.exists():
            return []
        return path.read_text(encoding="utf-8").split()

    def run(self, arguments: list, pasted: str = ""):
        # Under the network guard as well as the curl stub (the fix review's
        # M-a): a request the stub did not answer fails the run.
        environment = the_network_refused(
            self.folder, dict(os.environ, FAKE_DIR=str(self.fake), FAKE_GOOD_TOKEN=GOOD_TOKEN))
        result = subprocess.run(
            ["bash", str(self.folder / "deploy.sh")] + arguments,
            input=pasted.encode("utf-8"), capture_output=True, timeout=180,
            cwd=str(self.folder), env=environment,
        )
        no_request_was_made(self.folder)
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
                    settings_path = _section("placeholders", "deployingSettings", "mac")
                    expected = ("❌ " + _filled(first, service, settings_path) + "\n"
                                + "   " + _filled(second, service, settings_path) + "\n")
                    self.assertEqual(said, expected)
                    self.assertIn("saved as your token", first)

    def test_every_paste_problem_and_reach_answer_has_two_lines(self):
        lines = _section("deployTimeRefusals", "lines")
        for problem in ("tokenEmpty", "tokenHasSpaces", "tokenNotPlainText"):
            self.assertIn(problem, lines)
            self.assertIn(problem, _section("answerShape", "problems"))


def _filled(line: str, service: str, settings_path: str) -> str:
    return line.replace("{service}", service).replace("{deployingSettings}", settings_path)


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
                for marker in case.get("releasedMarkers", []):
                    folder.released_marker(case["service"], marker["place"], marker["value"], marker["stamp"])
                for marker in case.get("legacyMarkers", []):
                    folder.legacy_marker(marker["place"], marker["value"])
                for marker in case.get("planMarkers", []):
                    folder.plan_marker(marker["course"], marker["year"], marker.get("value"))
                for marker in case.get("unreadableMarkers", []):
                    folder.unreadable_marker(case["service"], marker["place"])
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
                self.assertNotIn(GOOD_TOKEN, folder.arguments_given_to_curl(),
                                 "the token is never on a request's command line")

    def test_the_token_is_never_on_a_requests_command_line(self):
        """Review W3. MUST-FAIL on ee9007303, whose http_answer passed the
        header as an argument, where `ps` shows it while the request runs."""
        with tempfile.TemporaryDirectory() as tmp:
            folder = AWorkingFolder(tmp)
            folder.answer({
                "cloudflareVerify": {"status": 200, "body": '{"result":{"status":"active"},"success":true}'},
                "cloudflareAccountProjects": {"status": 200, "body": '{"result":[],"success":true}'},
                "cloudflareProject:mpm2d-s3-2026": {"status": 200, "body": '{"success":true}'},
            })
            folder.marker("cloudflare", "MPM2D/3", "mpm2d-s3-2026")
            code, out, err = folder.run(["--token", "save", "--target", "cloudflare",
                                         "--account", "0123456789abcdef0123456789abcdef"],
                                        pasted=GOOD_TOKEN + "\n")
            self.assertEqual(json.loads(out)["saved"], True, out + err)
            self.assertEqual(len(folder.requests()), 3, folder.requests())
            self.assertNotIn(GOOD_TOKEN, folder.arguments_given_to_curl())

    def test_the_contract_carries_the_cases_the_review_asked_for(self):
        """Reviews W1 and I2: a released marker beside a live one, an
        unreadable marker, the old Netlify place, unit plans, and an Account
        ID that is not whole. Each runs in test_every_reachability_case."""
        cases = _section("reachability", "cases")
        for field in ("releasedMarkers", "unreadableMarkers", "legacyMarkers", "planMarkers"):
            found = False
            for case in cases:
                if case.get(field):
                    found = True
            self.assertTrue(found, f"no reachability case carries {field}")
        problems = []
        for case in cases:
            problems.append(case["expect"]["problem"])
        self.assertIn("accountNotValid", problems)

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
                course, section = case["section"].split("/")
                if case.get("marker") and case.get("legacyMarker"):
                    folder.legacy_marker(case["section"], case["marker"])
                elif case.get("marker"):
                    folder.marker(case["service"], case["section"], case["marker"])
                if case.get("planMarker"):
                    folder.plan_marker(course, case["planMarker"]["year"], case["planMarker"].get("value"))
                if case.get("plans"):
                    # A share of unit plans needs the course, not a built section.
                    (folder.folder / "courses" / course / "course_config.json").write_text(
                        json.dumps({"course_code": course}), encoding="utf-8")
                    arguments = [course, "--plans", "--image", "unused:tag", "--target", case["service"]]
                else:
                    self._a_built_section(folder, case["section"])
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
                self.assertNotIn(GOOD_TOKEN, folder.arguments_given_to_curl(),
                                 "the token is never on a request's command line")

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

    def test_a_cloudflare_token_with_no_end_date_says_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = AWorkingFolder(tmp, stop_before_the_builder=True)
            folder.answer({"cloudflareVerify": {"status": 200, "body": '{"result":{"status":"active"},"success":true}'}})
            self._a_built_section(folder, "MPM2D/3")
            folder.save("cloudflare", GOOD_TOKEN)
            code, out, err = folder.run(["MPM2D", "3", "--image", "unused:tag", "--target", "cloudflare",
                                         "--account", "0123456789abcdef0123456789abcdef", "--non-interactive"])
            self.assertEqual(code, 0, out + err)
            self.assertIn("PLANTOIR_TOKEN_ENDS: cloudflare none\n", out)

    def test_a_cloudflare_deploy_asks_cloudflare_about_its_token_once(self):
        """Review M4. MUST-FAIL on ee9007303, which asked the token check a
        second time for the end date."""
        with tempfile.TemporaryDirectory() as tmp:
            folder = AWorkingFolder(tmp, stop_before_the_builder=True)
            folder.answer({"cloudflareVerify": {"status": 200, "body": '{"result":{"status":"active","expires_on":"2027-07-01T00:00:00Z"},"success":true}'}})
            self._a_built_section(folder, "MPM2D/3")
            folder.save("cloudflare", GOOD_TOKEN)
            code, out, err = folder.run(["MPM2D", "3", "--image", "unused:tag", "--target", "cloudflare",
                                         "--account", "0123456789abcdef0123456789abcdef", "--non-interactive"])
            self.assertEqual(code, 0, out + err)
            self.assertEqual(folder.requests(), ["cloudflareVerify"])
            self.assertIn("PLANTOIR_TOKEN_ENDS: cloudflare 2027-07-01T00:00:00Z\n", out)

    def test_a_pasted_cloudflare_token_says_its_end_date_with_one_request(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = AWorkingFolder(tmp, stop_before_the_builder=True)
            folder.answer({"cloudflareVerify": {"status": 200, "body": '{"result":{"status":"active","expires_on":"2027-07-01T00:00:00Z"},"success":true}'}})
            self._a_built_section(folder, "MPM2D/3")
            code, out, err = folder.run(["MPM2D", "3", "--image", "unused:tag", "--target", "cloudflare",
                                         "--account", "0123456789abcdef0123456789abcdef"],
                                        pasted=GOOD_TOKEN + "\n")
            self.assertEqual(code, 0, out + err)
            self.assertEqual(folder.requests(), ["cloudflareVerify"])
            self.assertIn("PLANTOIR_TOKEN_ENDS: cloudflare 2027-07-01T00:00:00Z\n", out)
            self.assertEqual(folder.store("cloudflare"), GOOD_TOKEN)



# The store tool, standing in front of the real one for TheKeychainSave: it
# writes down its own arguments, refuses unless the throwaway keychain the
# test made is there (a keychain path that does not exist is not an error to
# `security`, which then writes to the login keychain instead: measured
# 2026-11-13), and hands each command it reads on to the real `security -i`
# with that keychain named at the end of the line.
STORE_TOOL_IN_FRONT = r"""#!/bin/bash
printf '%s\n' "$*" >> "$STORE_ARGUMENTS"
[[ -f "$THROWAWAY_KEYCHAIN" && "$THROWAWAY_KEYCHAIN" == *.keychain-db ]] || exit 99
while IFS= read -r line; do
  printf '%s "%s"\n' "$line" "$THROWAWAY_KEYCHAIN"
done | /usr/bin/security "$@"
"""


@unittest.skipUnless(ON_A_MAC and os.path.exists("/usr/bin/security"), "the Keychain is the mac's")
class TheKeychainSave(unittest.TestCase):
    """The fix review's N2 on #696: `--token save` handed the token to
    `security add-generic-password -w <token>`, where `ps` shows it.
    MUST-FAIL on c4655ba2d (keychain_save is not there to cut; and its
    set_token_keychain put the token in the store tool's arguments).

    Everything here goes to a keychain this test makes in a temporary folder
    and deletes by its path; the login keychain is never named, and every
    token is invented."""

    TOKENS = ("plain-Token_123.abc", "with space", 'dq"inside', "back\\slash", "end\\",
              "sq'inside", "dollar$HOME", "semi;colon", "#hash", "tab\tin", '"', 'a\\"b')

    def setUp(self):
        self.shell = launcher_harness._a_bash_that_can_run_deploy_sh()
        if self.shell is None:
            self.skipTest("no bash on this machine that can run deploy.sh's definitions")
        self.scratch = Path(tempfile.mkdtemp(prefix="plantoir-keychain-save-"))
        self.keychain = self.scratch / "throwaway.keychain-db"
        made = subprocess.run(["/usr/bin/security", "create-keychain", "-p", "invented-for-a-test",
                               str(self.keychain)], capture_output=True, timeout=30)
        if made.returncode != 0 or not self.keychain.exists():
            shutil.rmtree(self.scratch, ignore_errors=True)
            self.skipTest("this Mac would not make a throwaway keychain: "
                          + made.stderr.decode("utf-8", "replace"))
        self.tool = self.scratch / "security-in-front"
        self.tool.write_text(STORE_TOOL_IN_FRONT, encoding="utf-8")
        self.tool.chmod(0o755)
        self.arguments = self.scratch / "store-arguments"

    def tearDown(self):
        subprocess.run(["/usr/bin/security", "delete-keychain", str(self.keychain)],
                       capture_output=True, timeout=30)
        shutil.rmtree(self.scratch, ignore_errors=True)

    def _saved(self, service: str, account: str):
        found = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", service, "-a", account,
                                "-w", str(self.keychain)], capture_output=True, timeout=30)
        if found.returncode != 0:
            return None
        shown = found.stdout.decode("utf-8", "replace").rstrip("\n")
        return shown

    def _same(self, shown, token: str) -> bool:
        # `security -w` shows a value holding a TAB as its bytes in hex.
        if shown == token:
            return True
        try:
            return bytes.fromhex(shown) == token.encode("utf-8")
        except (TypeError, ValueError):
            return False

    def test_each_token_is_saved_byte_for_byte_and_on_no_command_line(self):
        function = _cut_from_deploy_sh("keychain_save")
        self.assertEqual(function.count("/usr/bin/security -i"), 1)
        script = function.replace("/usr/bin/security -i", '"$STORE_TOOL" -i') + \
            '\nkeychain_save_secret "$1" "$2" "$(cat "$3")"\n'
        environment = dict(os.environ, STORE_TOOL=str(self.tool), STORE_ARGUMENTS=str(self.arguments),
                           THROWAWAY_KEYCHAIN=str(self.keychain))
        for number, token in enumerate(self.TOKENS):
            with self.subTest(token=token):
                service = f"plantoir-test-service-{number}"
                held = self.scratch / f"token-{number}"
                held.write_text(token, encoding="utf-8")
                result = subprocess.run(self.shell + ["-c", script, "_", service, "invented-account", str(held)],
                                        env=environment, capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(self._same(self._saved(service, "invented-account"), token))
        handed = self.arguments.read_text(encoding="utf-8").splitlines()
        self.assertEqual(handed, ["-i"] * len(self.TOKENS), "the store tool's arguments are only -i")

    def test_a_secret_with_a_line_break_is_refused_and_nothing_is_saved(self):
        function = _cut_from_deploy_sh("keychain_save")
        script = function.replace("/usr/bin/security -i", '"$STORE_TOOL" -i') + \
            '\nkeychain_save_secret "$1" "$2" "$3"\n'
        environment = dict(os.environ, STORE_TOOL=str(self.tool), STORE_ARGUMENTS=str(self.arguments),
                           THROWAWAY_KEYCHAIN=str(self.keychain))
        result = subprocess.run(self.shell + ["-c", script, "_", "plantoir-test-broken", "invented-account",
                                              "first\nadd-generic-password -s other -a other -w other"],
                                env=environment, capture_output=True, timeout=60)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.arguments.exists(), "the store tool was never started")
        self.assertIsNone(self._saved("other", "other"))

    def test_both_token_stores_save_through_it(self):
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        for name, service in (("set_token_keychain", "KEYCHAIN_SERVICE"), ("set_cf_token_keychain", "CF_KEYCHAIN_SERVICE")):
            begin = text.index(f"\n{name}() {{\n") + 1
            body = text[begin:text.index("\n}\n", begin)]
            with self.subTest(store=name):
                self.assertIn(f'keychain_save_secret "${service}" "$USER" "$1"', body)
                self.assertNotIn("-w \"$1\"", body)


if __name__ == "__main__":
    unittest.main()

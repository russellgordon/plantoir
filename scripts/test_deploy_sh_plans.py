#!/usr/bin/env python3
"""
`deploy.sh <CODE> --plans …` (#709), the REAL launcher, with the Keychain,
Cloudflare and the website builder stubbed. Nothing is sent anywhere, nothing
is written to the teacher's Keychain, and no container is started.

What is proved:
  * plans mode goes to Cloudflare and nowhere else: it never reads the
    course's saved destinations (#668), and --to-folder and --target netlify
    are refused with the contract's sentences;
  * a plan flag without --plans is refused;
  * the username and password are asked for only by a protected share with
    none saved, are refused under --non-interactive, and their prompts name
    no other credential;
  * protection is sticky: a marker that last asked for it makes a share with
    no flag a protected one;
  * the username and password reach the website builder on stdin only:
    never in the arguments of any docker call;
  * the plans guard refuses while `deploy.sh C --plans` runs in this folder,
    and is not refused by `deploy.sh C 1`, nor the other way round.

The plan's own stubs are inserted at the markers named below; a marker that
moves fails the test rather than skipping it. Run with:

    python3 scripts/test_deploy_sh_plans.py
"""
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_deploy_sh_questions import HAS_BASH, NOBODY, ON_A_MAC, REPOSITORY_ROOT  # noqa: E402
from test_preview_while_deploying import FAKE_PS_FOR_THE_REAL_LAUNCHER, PretendMac  # noqa: E402

SHARE = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))["unitPlanning"]["share"]
PROMPTS = json.loads((REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8"))["credentialPrompts"]["cases"]

USERNAME = "colleague709"
PASSWORD = "Kettle-Sunflower 42"

CF_MARKER = "# -------------------- Cloudflare token and account ---------------------\n"
PLAN_MARKER = 'if [[ "$PLANS_MODE" == "true" ]]; then\n  if [[ -z "$PLAN_YEAR" ]]; then'
CONTAINER_START = "# ==================== Container runtime (Colima) ====================\n"
CONTAINER_END = 'if [[ "$PLANS_MODE" == "true" ]]; then\n  if [[ "$PLAN_STOP" == "true" ]]; then\n    echo "🚀 Stopping'

CF_STUBS = r'''
get_cf_token_keychain() { echo "fake-cloudflare-token-709"; }
token_check_answer() { echo accepted; }
discover_cf_account() { printf '%s' "0123456789abcdef0123456789abcdef"; }
set_cf_account_keychain() { :; }
delete_cf_account_keychain() { :; }
delete_cf_token_keychain() { :; }
'''

PLAN_STUBS = r'''
get_plan_credential_keychain() { if [[ -f "$STUB/plan_item" ]]; then cat "$STUB/plan_item"; fi; }
set_plan_credential_keychain() { printf '%s' "$1" > "$STUB/plan_item_set"; }
delete_plan_credential_keychain() { : > "$STUB/plan_item_deleted"; }
'''

DOCKER_STUB = r'''
CONTAINER_NAME="teaching-quartz-test"
docker() {
  printf 'ARGS %s\n' "$*" >> "$STUB/docker.log"
  case " $* " in
    *" -i "*) cat >> "$STUB/docker.stdin"; printf '\n--\n' >> "$STUB/docker.stdin" ;;
  esac
  return "${DOCKER_RC:-0}"
}
'''


def the_school_year() -> int:
    today = dt.date.today()
    return today.year if today.month >= 8 else today.year - 1


def stubbed_launcher(folder: Path) -> None:
    text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
    for marker in (CF_MARKER, PLAN_MARKER, CONTAINER_START, CONTAINER_END):
        if text.count(marker) != 1:
            raise AssertionError(f"deploy.sh no longer carries {marker!r} once")
    text = text.replace(CF_MARKER, CF_STUBS + CF_MARKER)
    text = text.replace(PLAN_MARKER, PLAN_STUBS + PLAN_MARKER)
    start = text.index(CONTAINER_START)
    end = text.index(CONTAINER_END)
    text = text[:start] + DOCKER_STUB + text[end:]
    (folder / "deploy.sh").write_text(text, encoding="utf-8")


def a_folder(tmp: str, config: dict | None = None) -> Path:
    folder = Path(tmp)
    stubbed_launcher(folder)
    course = folder / "courses" / "SNC2D"
    (course / ".internal" / "planning").mkdir(parents=True)
    (course / "course_config.json").write_text(json.dumps(config or {"course_code": "SNC2D"}), encoding="utf-8")
    (folder / "stub").mkdir()
    return folder


def run(folder: Path, arguments: list, answer: str = "", extra_env: dict | None = None):
    environment = dict(os.environ, USER=NOBODY, STUB=str(folder / "stub"))
    environment.update(extra_env or {})
    done = subprocess.run(["bash", str(folder / "deploy.sh"), "SNC2D", "--plans", "--image", "unused:tag"] + arguments,
                          capture_output=True, timeout=180, cwd=str(folder), input=answer.encode("utf-8"),
                          env=environment)
    return done.returncode, done.stdout.decode("utf-8", "replace") + done.stderr.decode("utf-8", "replace")


def docker_args(folder: Path) -> str:
    log = folder / "stub" / "docker.log"
    return log.read_text(encoding="utf-8") if log.exists() else ""


def docker_stdin(folder: Path) -> str:
    log = folder / "stub" / "docker.stdin"
    return log.read_text(encoding="utf-8") if log.exists() else ""


@unittest.skipUnless(HAS_BASH and ON_A_MAC, "deploy.sh's credential path runs on a Mac")
class PlansModeTests(unittest.TestCase):

    def test_plans_go_to_cloudflare_and_never_read_the_saved_destinations(self):
        config = {"course_code": "SNC2D", "deploy_target": "local_folder", "deploy_folder_path": "/tmp/x",
                  "additional_deploy_targets": [{"type": "netlify"}]}
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp, config)
            status, out = run(folder, [])
            self.assertEqual(status, 0, out)
            self.assertNotIn("🎯", out)
            self.assertNotIn("Netlify token", out)
            self.assertIn("share_plan.py", docker_args(folder))
            self.assertNotIn("deploy.py", docker_args(folder))

    def test_to_a_folder_and_netlify_are_refused_with_the_contracts_sentences(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            status, out = run(folder, ["--to-folder", "out"])
            self.assertEqual(status, 1)
            self.assertIn("❌ " + SHARE["refusals"]["notToAFolder"], out)
            status, out = run(folder, ["--target", "netlify"])
            self.assertEqual(status, 1)
            self.assertIn("❌ " + SHARE["refusals"]["netlifyNever"], out)
            self.assertEqual(docker_args(folder), "")
            status, out = run(folder, ["--target", "cloudflare"])
            self.assertEqual(status, 0, out)

    def test_a_plan_flag_without_plans_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            for flag in ("--protect", "--remove-password", "--change-password", "--include-answer-keys", "--stop-sharing"):
                with self.subTest(flag=flag):
                    done = subprocess.run(["bash", str(folder / "deploy.sh"), "SNC2D", "1", flag, "--image", "x"],
                                          capture_output=True, text=True, cwd=str(folder), timeout=60,
                                          env=dict(os.environ, USER=NOBODY, STUB=str(folder / "stub")))
                    self.assertEqual(done.returncode, 1)
                    self.assertIn(f"❌ {flag} is for sharing unit plans: use it with --plans.", done.stdout)

    def test_protect_and_remove_password_together_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            status, out = run(folder, ["--protect", "--remove-password"])
            self.assertEqual(status, 1)
            self.assertEqual(docker_args(folder), "")

    def test_an_open_share_asks_for_no_password(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            status, out = run(folder, ["--non-interactive"])
            self.assertEqual(status, 0, out)
            self.assertNotIn("username", out.lower())
            self.assertNotIn("--protect", docker_args(folder))
            self.assertIn(f"--year {the_school_year()}", docker_args(folder))
            self.assertNotIn("plan_cred", docker_args(folder))

    def test_a_protected_share_with_nothing_saved_refuses_under_non_interactive(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            status, out = run(folder, ["--protect", "--non-interactive"])
            self.assertEqual(status, 3, out)
            self.assertIn("Choose a username for these unit plans", out)
            self.assertEqual(docker_args(folder), "")

    def test_the_two_questions_save_the_answer_and_hand_it_over_on_stdin_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            answer = "bad name!\n" + USERNAME + "\nshort\n" + PASSWORD + "\n"
            status, out = run(folder, ["--protect"], answer)
            self.assertEqual(status, 0, out)
            self.assertEqual((folder / "stub" / "plan_item_set").read_text(), f"{USERNAME}:{PASSWORD}")
            arguments = docker_args(folder)
            self.assertNotIn(PASSWORD, arguments)
            self.assertNotIn(USERNAME, arguments)
            self.assertIn("cat > /tmp/plan_cred", arguments)
            self.assertIn("--protect", arguments)
            self.assertIn(f"{USERNAME}:{PASSWORD}\n--", docker_stdin(folder))
            self.assertNotIn(PASSWORD, out)

    def test_a_saved_credential_is_used_without_asking(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            (folder / "stub" / "plan_item").write_text(f"{USERNAME}:{PASSWORD}")
            status, out = run(folder, ["--protect", "--non-interactive"])
            self.assertEqual(status, 0, out)
            self.assertIn(f"{USERNAME}:{PASSWORD}", docker_stdin(folder))
            self.assertFalse((folder / "stub" / "plan_item_set").exists())

    def test_change_password_asks_again_even_with_one_saved(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            (folder / "stub" / "plan_item").write_text("old:OldPassword1")
            status, out = run(folder, ["--protect", "--change-password"], f"{USERNAME}\n{PASSWORD}\n")
            self.assertEqual(status, 0, out)
            self.assertEqual((folder / "stub" / "plan_item_set").read_text(), f"{USERNAME}:{PASSWORD}")

    def test_protection_is_sticky_through_the_years_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            markers = folder / "courses" / "SNC2D" / ".cloudflare_sites"
            markers.mkdir()
            (markers / f"plans-{the_school_year()}.json").write_text(
                json.dumps({"name": "x", "asked": "protected", "protected": True}, indent=2))
            (folder / "stub" / "plan_item").write_text(f"{USERNAME}:{PASSWORD}")
            status, out = run(folder, ["--non-interactive"])
            self.assertEqual(status, 0, out)
            self.assertIn("--protect", docker_args(folder))
            status, out = run(folder, ["--remove-password", "--non-interactive"])
            self.assertEqual(status, 0, out)
            self.assertTrue((folder / "stub" / "plan_item_deleted").exists())

    def test_remove_password_keeps_the_keychain_item_when_the_share_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            status, out = run(folder, ["--remove-password", "--non-interactive"], extra_env={"DOCKER_RC": "1"})
            self.assertEqual(status, 1, out)
            self.assertFalse((folder / "stub" / "plan_item_deleted").exists())

    def test_stop_sharing_deletes_the_item_only_when_no_year_is_left(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            markers = folder / "courses" / "SNC2D" / ".cloudflare_sites"
            markers.mkdir()
            (markers / "plans-2025.json").write_text("{}")
            status, out = run(folder, ["--stop-sharing", "--year", "2026", "--non-interactive"])
            self.assertEqual(status, 0, out)
            self.assertIn("--stop", docker_args(folder))
            self.assertFalse((folder / "stub" / "plan_item_deleted").exists())
            (markers / "plans-2025.json").unlink()
            (markers / "plans-2024.previous-20260901T120000Z.json").write_text("{}")
            status, out = run(folder, ["--stop-sharing", "--year", "2025", "--non-interactive"])
            self.assertEqual(status, 0, out)
            self.assertTrue((folder / "stub" / "plan_item_deleted").exists())

    def test_include_answer_keys_reaches_share_plan(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            status, out = run(folder, ["--include-answer-keys", "--non-interactive"])
            self.assertEqual(status, 0, out)
            self.assertIn("--include-answer-keys", docker_args(folder))

    def test_a_bad_year_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_folder(tmp)
            status, out = run(folder, ["--year", "26"])
            self.assertEqual(status, 1)


class PromptWordsTests(unittest.TestCase):

    def plan_prompts(self) -> list:
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        start = text.index("ask_for_the_plan_credential() {")
        body = text[start:text.index("\n}\n", start)]
        import re
        return re.findall(r'read -rs?p "([^"]+)"', body)

    def test_the_prompts_name_no_other_credential(self):
        prompts = self.plan_prompts()
        self.assertEqual(len(prompts), 4)
        for prompt in prompts:
            for word in ("netlify", "cloudflare", "token", "last name", "website name", "account id"):
                self.assertNotIn(word, prompt.lower())

    def test_every_prompt_is_a_credential_prompt_case(self):
        listed = set()
        for case in PROMPTS:
            listed.add(case["prompt"].strip())
        for prompt in self.plan_prompts():
            self.assertIn(prompt.strip(), listed)


@unittest.skipUnless(HAS_BASH and sys.platform == "darwin" and Path("/bin/ps").exists(),
                     "needs a Mac: the pretend ps walks the real table with /bin/ps -o")
class PlansGuardTests(unittest.TestCase):
    """The real deploy.sh from its first line to just after a guard's call."""

    PLANS_CALL = 'refuse_while_these_plans_share "$COURSE_CODE"\nfi\n'
    SECTION_CALL = 'refuse_while_this_section_deploys "$COURSE_CODE" "$SECTION_NUM" deploy\nfi\n'

    def run_prefix(self, call: str, arguments: list, running: str):
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        self.assertEqual(text.count(call), 1)
        prefix = text[:text.index(call) + len(call)] + "echo REACHED\nexit 0\n"
        with tempfile.TemporaryDirectory() as tmp:
            mac = PretendMac(Path(tmp))
            (mac.bin / "ps").write_text(FAKE_PS_FOR_THE_REAL_LAUNCHER, encoding="utf-8")
            (mac.here / "deploy.sh").write_text(prefix, encoding="utf-8")
            (mac.here / "courses" / "SNC2D").mkdir(parents=True)
            (mac.here / "courses" / "SNC2D" / "course_config.json").write_text('{"deploy_target": "cloudflare_pages"}')
            mac.lay_out({"processes": [[801, 1, running]], "cwd": {"801": "here"}})
            environment = {"HOME": str(mac.home), "FAKE": str(mac.fake), "PATH": f"{mac.bin}:/usr/bin:/bin",
                           "PLANTOIR_TRAIL_DIR": str(mac.scratch / "trail")}
            return subprocess.run(["/bin/bash", "./deploy.sh"] + arguments, cwd=mac.here, env=environment,
                                  capture_output=True, text=True, timeout=60)

    def test_a_share_refuses_while_the_plans_are_being_shared(self):
        done = self.run_prefix(self.PLANS_CALL, ["SNC2D", "--plans"], "/bin/bash ./deploy.sh SNC2D --plans --protect")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("❌ " + SHARE["refusals"]["stillSharing"], done.stdout)
        self.assertNotIn("REACHED", done.stdout)

    def test_a_share_is_not_refused_by_a_sections_deploy(self):
        done = self.run_prefix(self.PLANS_CALL, ["SNC2D", "--plans"], "/bin/bash ./deploy.sh SNC2D 1")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("REACHED", done.stdout)

    def test_a_sections_deploy_is_not_refused_by_a_share(self):
        done = self.run_prefix(self.SECTION_CALL, ["SNC2D", "1"], "/bin/bash ./deploy.sh SNC2D --plans")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("REACHED", done.stdout)

    def test_a_share_runs_the_section_guard_with_no_place(self):
        done = self.run_prefix(self.SECTION_CALL, ["SNC2D", "--plans"], "/bin/bash ./deploy.sh SNC2D 1")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("REACHED", done.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=1)

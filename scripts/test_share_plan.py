#!/usr/bin/env python3
"""
`scripts/share_plan.py` (#709) against a stand-in Cloudflare: no network, no
account, no credential. The stand-in keeps projects and deployments as
Cloudflare does (measured 2026-11-12, documentation/07-deployment.md ->
"Sharing a unit plan (#709)"): every deploy is a deployment of its own, the
canonical one cannot be deleted, an older one keeps answering at its own
address until it is deleted, and the main address answers the canonical one.

What is proved, in the order the worst faults come:
  * nothing is called protected until the address has asked for the password
    (`notProtectedYet` otherwise), and every older deployment is deleted;
  * protection is sticky: a share with no flag keeps the last one asked for;
  * an open share leaves answer keys out;
  * the username and password are in no output, no marker, no staged file
    but the hash, and the file they came in is gone afterwards, even when the
    upload fails;
  * fail closed is set on every share and read back;
  * the address comes from Cloudflare's subdomain, never from the name.

Stdlib only. Run with:

    python3 scripts/test_share_plan.py
"""
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY / "contracts"))
os.environ.setdefault("PLANTOIR_SUPPORT_DIR", str(REPOSITORY / "support"))
sys.path.insert(0, str(REPOSITORY / "scripts"))

import share_plan  # noqa: E402
import unit_plan_site  # noqa: E402

TEMPLATE = REPOSITORY / "support" / "agent_guidance" / "skills" / "plantoir-unit-planning" / "template"
USERNAME = "colleague709"
PASSWORD = "Sunflower-Kettle-42"
TOKEN = "fake-token-never-real-709"
ACCOUNT = "fakeaccount709"


class FakeCloudflare:
    """Projects and deployments, answered the way Cloudflare answered."""

    def __init__(self):
        self.projects = {}
        self.calls = []
        self.subdomain_extra = ""
        self.taken = set()
        self.patch_fails = False
        self.patch_ignored = False
        self.delete_deployment_fails = False
        self.delete_project_fails = False
        self.staged = []
        self.counter = 0

    def api(self, method, path, token, payload=None):
        assert token == TOKEN
        self.calls.append((method, path, payload))
        parts = path.split("?", 1)[0].split("/")
        # /accounts/{a}/pages/projects[/name[/deployments[/id]]]
        if len(parts) == 5 and method == "POST":
            name = payload["name"]
            if name in self.taken or name in self.projects:
                raise RuntimeError("Cloudflare API error 409: A project with this name already exists.")
            configs = {"production": {"fail_open": True}, "preview": {"fail_open": True}}
            for environment, values in (payload.get("deployment_configs") or {}).items():
                configs[environment].update(values)
            self.projects[name] = {"name": name, "subdomain": name + self.subdomain_extra + ".pages.dev",
                                   "deployment_configs": configs, "deployments": [], "canonical": None}
            return self.view(name)
        name = parts[5]
        if name not in self.projects:
            raise RuntimeError("Cloudflare API error 404: Project not found.")
        project = self.projects[name]
        if len(parts) == 6:
            if method == "GET":
                return self.view(name)
            if method == "PATCH":
                if self.patch_fails:
                    raise RuntimeError("Cloudflare API error 400: Request body is incorrect.")
                if not self.patch_ignored:
                    for environment, values in payload["deployment_configs"].items():
                        project["deployment_configs"][environment].update(values)
                return self.view(name)
            if method == "DELETE":
                if self.delete_project_fails:
                    raise RuntimeError("Cloudflare API error 400: too many deployments")
                del self.projects[name]
                return {}
        if len(parts) == 7 and method == "GET":
            listed = []
            for deployment in project["deployments"]:
                listed.append({"id": deployment["id"], "uses_functions": deployment["worker"]})
            return listed
        if len(parts) == 8 and method == "DELETE":
            deployment_id = parts[7]
            if deployment_id == project["canonical"]:
                raise RuntimeError("Cloudflare API error 400: You cannot delete the active production deployment.")
            if self.delete_deployment_fails:
                raise RuntimeError("Cloudflare API error 500: internal")
            kept = []
            for deployment in project["deployments"]:
                if deployment["id"] != deployment_id:
                    kept.append(deployment)
            project["deployments"] = kept
            return {}
        raise AssertionError(f"unexpected call {method} {path}")

    def view(self, name):
        project = self.projects[name]
        canonical = None
        for deployment in project["deployments"]:
            if deployment["id"] == project["canonical"]:
                canonical = {"id": deployment["id"], "uses_functions": deployment["worker"]}
        return {"name": name, "subdomain": project["subdomain"],
                "deployment_configs": json.loads(json.dumps(project["deployment_configs"])),
                "canonical_deployment": canonical}

    def deploy(self, public, name, token, account):
        assert token == TOKEN and account == ACCOUNT
        assert name in self.projects, "deployed before the project existed"
        files = {}
        for path in sorted(Path(public).rglob("*")):
            if path.is_file():
                files[path.relative_to(public).as_posix()] = path.read_bytes()
        self.staged.append({"files": files, "cwd": os.getcwd(), "public": str(public)})
        self.counter += 1
        worker = files.get("_worker.js", b"")
        deployment = {"id": f"dep{self.counter}", "protected": b"const PROTECTED = true;" in worker,
                      "worker": bool(worker)}
        self.projects[name]["deployments"].append(deployment)
        self.projects[name]["canonical"] = deployment["id"]

    def fetch(self, url, credential=None):
        for project in self.projects.values():
            base = f"https://{project['subdomain']}/"
            if url.startswith(base):
                for deployment in project["deployments"]:
                    if deployment["id"] == project["canonical"]:
                        if deployment["protected"]:
                            right = unit_plan_site.credential_b64(USERNAME, PASSWORD)
                            if credential != right:
                                return 401, {"www-authenticate": 'Basic realm="x"'}
                        if url != base:
                            if deployment["worker"]:
                                return 404, {"cache-control": "no-store"}
                            return 404, {}
                        return 200, {}
        return None, {}


class Clock:
    def __init__(self):
        self.seconds = 0.0

    def now(self):
        return self.seconds

    def sleep(self, seconds):
        self.seconds += seconds


class ShareTestCase(unittest.TestCase):

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="plantoir-share-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.courses = self.tmp / "courses"
        self.course_dir = self.courses / "SNC2D"
        shutil.copytree(TEMPLATE, self.course_dir / ".internal" / "planning")
        (self.course_dir / "course_config.json").write_text('{"course_code": "SNC2D"}', encoding="utf-8")
        pdfs = self.course_dir / ".internal" / "planning" / "unit" / "pdfs"
        pdfs.mkdir(parents=True, exist_ok=True)
        (pdfs / "Quiz 1 - Solutions.pdf").write_bytes(b"%PDF-1.4 invented key")
        (pdfs / "Quiz 1.pdf").write_bytes(b"%PDF-1.4 invented quiz")
        self.cloudflare = FakeCloudflare()
        self.clock = Clock()
        self.cred_file = self.tmp / "plan_cred"
        patches = {
            "cloudflare_api": self.cloudflare.api,
            "deploy_to_cloudflare": self.cloudflare.deploy,
            "fetch_address": self.cloudflare.fetch,
            "now": self.clock.now,
            "sleep": self.clock.sleep,
            "CRED_FILE": self.cred_file,
        }
        for name, value in patches.items():
            original = getattr(share_plan, name)
            setattr(share_plan, name, value)
            self.addCleanup(setattr, share_plan, name, original)
        original_remake = share_plan.deploy.cloudflare_api
        share_plan.deploy.cloudflare_api = self.cloudflare.api
        self.addCleanup(setattr, share_plan.deploy, "cloudflare_api", original_remake)
        original_courses = share_plan.toolchain_paths.COURSES_DIR
        share_plan.toolchain_paths.COURSES_DIR = self.courses
        self.addCleanup(setattr, share_plan.toolchain_paths, "COURSES_DIR", original_courses)
        original_surname = share_plan.deploy.get_or_prompt_teacher_last_name
        share_plan.deploy.get_or_prompt_teacher_last_name = lambda: "gordon"
        self.addCleanup(setattr, share_plan.deploy, "get_or_prompt_teacher_last_name", original_surname)
        os.environ["CLOUDFLARE_API_TOKEN"] = TOKEN
        os.environ["CLOUDFLARE_ACCOUNT_ID"] = ACCOUNT
        self.addCleanup(os.environ.pop, "CLOUDFLARE_API_TOKEN", None)
        self.addCleanup(os.environ.pop, "CLOUDFLARE_ACCOUNT_ID", None)
        self.outputs = []

    def give_credential(self):
        self.cred_file.write_text(f"{USERNAME}:{PASSWORD}", encoding="utf-8")

    def run_share(self, *flags):
        arguments = ["--host-os", "mac", "--course", "SNC2D", "--year", "2026"] + list(flags)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = share_plan.main(arguments)
        text = out.getvalue()
        self.outputs.append(text)
        return status, text

    def marker(self):
        path = self.course_dir / ".cloudflare_sites" / "plans-2026.json"
        if not path.exists():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def assert_no_secret_anywhere(self):
        secrets = [PASSWORD, unit_plan_site.credential_b64(USERNAME, PASSWORD), TOKEN]
        for text in self.outputs:
            for secret in secrets:
                self.assertNotIn(secret, text)
        marker_text = json.dumps(self.marker() or {})
        for secret in secrets + [USERNAME, ACCOUNT]:
            self.assertNotIn(secret, marker_text)
        for staged in self.cloudflare.staged:
            for relative, data in staged["files"].items():
                for secret in (PASSWORD, USERNAME, unit_plan_site.credential_b64(USERNAME, PASSWORD)):
                    self.assertNotIn(secret.encode("utf-8"), data, relative)
        for _, _, payload in self.cloudflare.calls:
            for secret in (PASSWORD, USERNAME):
                self.assertNotIn(secret, json.dumps(payload or {}))
        self.assertFalse(self.cred_file.exists(), "the credential file was left behind")


class OpenShareTests(ShareTestCase):

    def test_an_open_share_proves_the_address_and_says_so(self):
        status, text = self.run_share()
        self.assertEqual(status, 0, text)
        marker = self.marker()
        self.assertFalse(marker["protected"])
        self.assertEqual(marker["asked"], "open")
        self.assertEqual(marker["answerKeys"], "out")
        self.assertEqual(marker["answerKeysLeftOut"], 1)
        self.assertIn("PLANTOIR_PLAN_SHARED: SNC2D 2026 https://", text)
        self.assertIn("protected:no failClosed:yes answerKeys:out units:1 oldCopies:0", text)
        files = self.cloudflare.staged[-1]["files"]
        self.assertIn("_headers", files)
        self.assertIn(b"const PROTECTED = false;", files["_worker.js"])
        self.assertNotIn(b'"unit/pdfs/Quiz 1 - Solutions.pdf"', files["_worker.js"])
        self.assertIn(b'"unit/pdfs/Quiz 1.pdf"', files["_worker.js"])
        self.assertNotIn("unit/pdfs/Quiz 1 - Solutions.pdf", files)
        self.assertIn("unit/pdfs/Quiz 1.pdf", files)
        self.assertIn("404.html", files)
        self.assert_no_secret_anywhere()

    def test_include_answer_keys_keeps_them_in_an_open_share(self):
        status, text = self.run_share("--include-answer-keys")
        self.assertEqual(status, 0, text)
        self.assertIn("unit/pdfs/Quiz 1 - Solutions.pdf", self.cloudflare.staged[-1]["files"])
        self.assertEqual(self.marker()["answerKeys"], "in")

    def test_a_new_project_is_named_for_the_year_with_a_suffix_and_made_fail_closed(self):
        self.run_share()
        name = self.marker()["name"]
        self.assertRegex(name, r"^snc2d-plans-2026-27-gordon-[a-z0-9]{8}$")
        post = None
        for method, path, payload in self.cloudflare.calls:
            if method == "POST":
                post = payload
        self.assertEqual(post["deployment_configs"]["production"]["fail_open"], False)
        self.assertEqual(post["deployment_configs"]["preview"]["fail_open"], False)

    def test_the_address_is_cloudflares_subdomain_not_the_name(self):
        self.cloudflare.subdomain_extra = "-7xq"
        status, text = self.run_share()
        self.assertEqual(status, 0, text)
        marker = self.marker()
        self.assertEqual(marker["address"], f"https://{marker['name']}-7xq.pages.dev/")
        self.assertIn(marker["address"], text)

    def test_a_name_taken_in_the_account_gets_a_new_suffix(self):
        taken = []
        original = unit_plan_site.new_suffix
        answers = iter(["aaaaaaaa", "bbbbbbbb"])
        unit_plan_site.new_suffix = lambda: next(answers)
        self.addCleanup(setattr, unit_plan_site, "new_suffix", original)
        self.cloudflare.taken.add("snc2d-plans-2026-27-gordon-aaaaaaaa")
        status, text = self.run_share()
        self.assertEqual(status, 0, text)
        self.assertEqual(self.marker()["name"], "snc2d-plans-2026-27-gordon-bbbbbbbb")
        self.assertEqual(taken, [])

    def test_wrangler_runs_beside_the_staged_folder_and_the_folder_is_gone_afterwards(self):
        self.run_share()
        staged = self.cloudflare.staged[-1]
        self.assertEqual(Path(staged["public"]).parent.resolve(), Path(staged["cwd"]).resolve())
        self.assertFalse(Path(staged["public"]).exists())


class ProtectedShareTests(ShareTestCase):

    def test_a_protected_share_asks_for_the_password_and_keeps_the_answer_keys(self):
        self.give_credential()
        status, text = self.run_share("--protect")
        self.assertEqual(status, 0, text)
        marker = self.marker()
        self.assertTrue(marker["protected"])
        self.assertEqual(marker["answerKeys"], "in")
        files = self.cloudflare.staged[-1]["files"]
        self.assertIn(b"const PROTECTED = true;", files["_worker.js"])
        self.assertNotIn("_headers", files)
        self.assertIn("unit/pdfs/Quiz 1 - Solutions.pdf", files)
        self.assertIn("protected:yes", text)
        self.assert_no_secret_anywhere()

    def test_a_protected_share_with_no_password_given_is_refused_and_never_falls_back_to_open(self):
        status, text = self.run_share("--protect")
        self.assertEqual(status, 1)
        self.assertIn("PLANTOIR_PLAN_REFUSED: SNC2D noPassword", text)
        self.assertEqual(self.cloudflare.staged, [])
        self.assertEqual(self.cloudflare.calls, [])

    def test_protection_is_sticky_and_only_remove_password_opens_it(self):
        self.give_credential()
        self.run_share("--protect")
        self.give_credential()
        status, text = self.run_share()
        self.assertEqual(status, 0, text)
        self.assertIn(b"const PROTECTED = true;", self.cloudflare.staged[-1]["files"]["_worker.js"])
        self.assertTrue(self.marker()["protected"])
        status, text = self.run_share("--remove-password")
        self.assertEqual(status, 0, text)
        self.assertIn(b"const PROTECTED = false;", self.cloudflare.staged[-1]["files"]["_worker.js"])
        self.assertFalse(self.marker()["protected"])
        self.assertEqual(self.marker()["subdomain"], self.cloudflare.view(self.marker()["name"])["subdomain"])
        self.assert_no_secret_anywhere()

    def test_a_sticky_share_with_no_password_handed_over_is_refused(self):
        self.give_credential()
        self.run_share("--protect")
        status, text = self.run_share()
        self.assertEqual(status, 1)
        self.assertIn("noPassword", text)

    def test_a_protected_share_the_address_does_not_prove_is_not_called_protected(self):
        self.give_credential()

        def always_open(url, credential=None):
            return 200, {}

        share_plan.fetch_address = always_open
        status, text = self.run_share("--protect")
        self.assertEqual(status, 1)
        self.assertIn("PLANTOIR_PLAN_REFUSED: SNC2D notProtectedYet", text)
        self.assertNotIn("PLANTOIR_PLAN_SHARED", text)
        marker = self.marker()
        self.assertFalse(marker["protected"])
        self.assertEqual(marker["asked"], "protected")
        self.assertGreaterEqual(self.clock.seconds, share_plan.PROOF_SECONDS)

    def test_a_changed_password_is_proved_by_the_new_password_not_the_old_deployments_401(self):
        self.give_credential()
        self.run_share("--protect")
        answers = {"calls": 0}
        fake_fetch = self.cloudflare.fetch

        def the_old_deployment_for_a_moment(url, credential=None):
            # The main address still answers the old deployment, which also
            # says 401 without a password, for the first few fetches.
            answers["calls"] += 1
            if answers["calls"] <= 3:
                if credential is None:
                    return 401, {"www-authenticate": 'Basic realm="x"'}
                return 401, {"www-authenticate": 'Basic realm="x"'}
            return fake_fetch(url, credential)

        share_plan.fetch_address = the_old_deployment_for_a_moment
        self.give_credential()
        status, text = self.run_share("--protect")
        self.assertEqual(status, 0, text)
        self.assertIn("protected:yes", text)

    def test_every_older_deployment_is_deleted_and_the_current_one_kept(self):
        self.run_share()
        self.give_credential()
        self.run_share("--protect")
        name = self.marker()["name"]
        deployments = self.cloudflare.projects[name]["deployments"]
        self.assertEqual(len(deployments), 1)
        self.assertEqual(deployments[0]["id"], self.cloudflare.projects[name]["canonical"])
        self.assertTrue(deployments[0]["protected"])
        self.assertEqual(self.marker()["oldCopies"], 0)

    def test_an_older_deployment_that_cannot_be_deleted_is_said_and_counted(self):
        self.run_share()
        self.cloudflare.delete_deployment_fails = True
        self.give_credential()
        status, text = self.run_share("--protect")
        self.assertEqual(status, 0, text)
        self.assertIn(share_plan.share_words()["refusals"]["oldCopyStillThere"], text)
        self.assertIn("oldCopies:1", text)
        self.assertEqual(self.marker()["oldCopies"], 1)

    def test_the_credential_and_the_staged_folder_go_even_when_the_upload_fails(self):
        self.give_credential()
        seen = []

        def failing(public, name, token, account):
            seen.append(public)
            raise RuntimeError("Cloudflare's deploy tool exited with code 1")

        share_plan.deploy_to_cloudflare = failing
        status, text = self.run_share("--protect")
        self.assertEqual(status, 1)
        self.assertFalse(self.cred_file.exists())
        self.assertFalse(Path(seen[0]).exists())
        self.assertNotIn(PASSWORD, text)


class EdgeCacheTests(ShareTestCase):

    def test_an_open_share_without_the_worker_in_front_is_not_called_shared(self):
        def no_worker(url, credential=None):
            return (200, {}) if url.endswith("/") else (404, {})

        share_plan.fetch_address = no_worker
        status, text = self.run_share()
        self.assertEqual(status, 1)
        self.assertIn("notAnsweringYet", text)
        self.assertNotIn("PLANTOIR_PLAN_SHARED", text)


class FailClosedTests(ShareTestCase):

    def test_fail_closed_is_set_and_read_back_on_every_share(self):
        self.run_share()
        self.run_share()
        patches = 0
        for method, path, payload in self.cloudflare.calls:
            if method == "PATCH":
                patches += 1
                self.assertEqual(payload, {"deployment_configs": share_plan.fail_closed_configs()})
        self.assertEqual(patches, 2)
        self.assertTrue(self.marker()["failClosed"])

    def test_a_refused_patch_records_fail_open_and_shares_anyway(self):
        self.cloudflare.patch_fails = True
        self.cloudflare.api  # the creating POST still carries it; make the project fail open
        status, text = self.run_share()
        self.assertEqual(status, 0, text)
        self.assertFalse(self.marker()["failClosed"])
        self.assertIn("failClosed:no", text)

    def test_a_read_back_that_disagrees_records_fail_open(self):
        self.run_share()
        name = self.marker()["name"]
        self.cloudflare.projects[name]["deployment_configs"]["preview"]["fail_open"] = True
        self.cloudflare.patch_ignored = True
        status, text = self.run_share()
        self.assertEqual(status, 0, text)
        self.assertFalse(self.marker()["failClosed"])


class CheckFirstTests(ShareTestCase):

    def test_a_plan_with_problems_is_refused_before_anything_is_sent(self):
        (self.course_dir / ".internal" / "planning" / "robots.txt").unlink()
        status, text = self.run_share()
        self.assertEqual(status, 1)
        self.assertIn("PLANTOIR_PLAN_REFUSED: SNC2D checkFound 1", text)
        self.assertEqual(self.cloudflare.calls, [])
        self.assertEqual(self.cloudflare.staged, [])

    def test_a_reference_course_is_refused(self):
        (self.course_dir / "course_config.json").write_text(
            '{"course_code": "SNC2D", "kept_for_reference": true}', encoding="utf-8")
        status, text = self.run_share()
        self.assertEqual(status, 1)
        self.assertIn("PLANTOIR_PLAN_REFUSED: SNC2D referenceCourse", text)
        self.assertEqual(self.cloudflare.calls, [])


class StopTests(ShareTestCase):

    def test_stop_deletes_the_project_and_the_marker(self):
        self.run_share()
        name = self.marker()["name"]
        status, text = self.run_share("--stop")
        self.assertEqual(status, 0, text)
        self.assertNotIn(name, self.cloudflare.projects)
        self.assertIsNone(self.marker())
        self.assertRegex(text, r"PLANTOIR_PLAN_STOPPED: SNC2D 2026 https://\S+ deleted")

    def test_stop_with_nothing_shared_is_already_gone(self):
        status, text = self.run_share("--stop")
        self.assertEqual(status, 0)
        self.assertIn("PLANTOIR_PLAN_STOPPED: SNC2D 2026 none alreadyGone", text)

    def test_stop_of_a_project_deleted_elsewhere_is_already_gone(self):
        self.run_share()
        del self.cloudflare.projects[self.marker()["name"]]
        status, text = self.run_share("--stop")
        self.assertEqual(status, 0)
        self.assertIn(" alreadyGone", text)
        self.assertIsNone(self.marker())

    def test_a_stop_that_fails_keeps_the_marker(self):
        self.run_share()
        self.cloudflare.delete_project_fails = True
        status, text = self.run_share("--stop")
        self.assertEqual(status, 1)
        self.assertIn(" failed", text)
        self.assertIsNotNone(self.marker())
        self.assertIn(share_plan.share_words()["words"]["stopFailed"], text)


class MarkerTests(ShareTestCase):

    def test_the_marker_holds_the_contracts_keys_and_no_account_id(self):
        self.give_credential()
        self.run_share("--protect")
        marker = self.marker()
        self.assertEqual(sorted(marker), sorted(share_plan.share_words()["markerFile"]["keys"]))
        self.assertNotIn("account_id", marker)
        self.assertNotIn("id", marker)
        mode = (self.course_dir / ".cloudflare_sites" / "plans-2026.json").stat().st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def test_every_mode_case(self):
        for case in share_plan.share_words()["modeCases"]["cases"]:
            with self.subTest(case=case):
                marker = None if case["marker"] is None else {"asked": "protected" if case["marker"] else "open"}
                protected = share_plan.decide_protected(marker, case["flag"] == "--protect",
                                                        case["flag"] == "--remove-password")
                self.assertEqual(protected, case["protected"])


if __name__ == "__main__":
    unittest.main(verbosity=1)

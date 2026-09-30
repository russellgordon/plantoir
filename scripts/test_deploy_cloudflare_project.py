#!/usr/bin/env python3
"""
Publishing to Cloudflare Pages must never leave wrangler a question to ask.

deploy.py hands the upload to wrangler, Cloudflare's own CLI, and always runs
it with CI set — its documented "no questions" switch — because a publish can
come from anywhere: a teacher's Deploy button (a pseudo-terminal), a scheduled
deploy from launchd (no terminal at all), the assistant's windowless deploy
(--non-interactive) and verify-deploy.sh. Under CI, a question wrangler would
have asked is an ERROR instead: "This command cannot be run in a
non-interactive context", exit 1.

So everything that would make wrangler ask must be settled before it runs:

  * the flags that answer its questions (project, branch, dirty tree) are
    passed, and CI is set, whatever the caller's environment;
  * the project must EXIST. A section's saved project whose Cloudflare project
    was deleted in the dashboard made wrangler ask "create it?", and every
    publish of that section failed. Found 2026-09-30, when verify-deploy.sh
    went red on every Cloudflare leg after its test project had been deleted
    by hand; it was 53/0/0 the run before. deploy.py now checks the saved name
    and, on a 404, makes the project again under the same name.

Pure stdlib, no Docker, no network, no credentials. Run with:

    python3 scripts/test_deploy_cloudflare_project.py
"""
import io
import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

import deploy


class FakeCloudflare:
    """Stands in for cloudflare_api: a set of projects that exist, and a log."""

    def __init__(self, existing: set, get_failure: str | None = None):
        self.existing = set(existing)
        self.get_failure = get_failure
        self.calls: list = []

    def __call__(self, method, path, token, payload=None):
        self.calls.append((method, path, payload))
        if method == "GET":
            if self.get_failure is not None:
                raise RuntimeError(self.get_failure)
            name = path.rsplit("/", 1)[-1]
            if name in self.existing:
                return {"name": name, "id": "old-id", "subdomain": f"{name}.pages.dev"}
            raise RuntimeError("Cloudflare API error 404: Project not found. The specified project name does not match any of your existing projects.")
        if method == "POST":
            name = payload["name"]
            self.existing.add(name)
            # A recreated project can come back on a different address.
            return {"name": name, "id": "new-id", "subdomain": f"{name}-7x2.pages.dev"}
        raise AssertionError(f"unexpected {method} {path}")

    def posted(self) -> list:
        result = []
        for method, _path, payload in self.calls:
            if method == "POST":
                result.append(payload)
        return result


class WranglerIsInvokedSoItCannotAsk(unittest.TestCase):

    def run_deploy_to_cloudflare(self, environment: dict) -> tuple:
        seen: dict = {}

        def fake_run(command, env=None, **kwargs):
            seen["command"] = command
            seen["env"] = env
            seen["kwargs"] = kwargs
            return subprocess.CompletedProcess(command, 0)

        with mock.patch.dict("os.environ", environment, clear=True), \
             mock.patch.object(deploy.subprocess, "run", fake_run):
            deploy.deploy_to_cloudflare(Path("/tmp/site/public"), "ada1o-s1", "a-token", "an-account")
        return seen["command"], seen["env"]

    def test_ci_is_set_whatever_the_caller_had(self):
        # A terminal-less caller, a caller with a terminal, and a caller that
        # itself said CI=false: wrangler gets CI=1 every time.
        for environment in ({}, {"TERM": "xterm-256color"}, {"CI": "false"}):
            _command, env = self.run_deploy_to_cloudflare(environment)
            self.assertEqual(env.get("CI"), "1", f"CI not forced for caller environment {environment}")

    def test_every_question_wrangler_could_ask_is_answered_by_a_flag(self):
        command, env = self.run_deploy_to_cloudflare({})
        self.assertEqual(command[1:3], ["pages", "deploy"])
        self.assertIn("--project-name=ada1o-s1", command)
        self.assertIn("--branch=main", command)
        self.assertIn("--commit-dirty=true", command)
        self.assertEqual(env.get("CLOUDFLARE_ACCOUNT_ID"), "an-account",
                         "without the account wrangler asks which one to use")
        self.assertEqual(env.get("CLOUDFLARE_API_TOKEN"), "a-token")


class APublishWhoseSavedProjectWasDeleted(unittest.TestCase):

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.course_dir = Path(self.temporary.name) / "ADA1O"
        self.public_dir = Path(self.temporary.name) / "section1" / "public"
        self.public_dir.mkdir(parents=True)
        (self.public_dir / "index.html").write_text("<html></html>", encoding="utf-8")
        deploy.save_cloudflare_marker(self.course_dir, "1", {
            "name": "ada1o-s1-2026-testing", "id": "old-id",
            "subdomain": "ada1o-s1-2026-testing.pages.dev", "account_id": "an-account",
        })
        self.uploaded_to: list = []

    def tearDown(self):
        self.temporary.cleanup()

    def publish(self, fake: FakeCloudflare, non_interactive: bool = False) -> str:
        def fake_upload(public_dir, project_name, token, account_id):
            self.uploaded_to.append(project_name)

        output = io.StringIO()
        environment = {"CLOUDFLARE_API_TOKEN": "a-token", "CLOUDFLARE_ACCOUNT_ID": "an-account"}
        with mock.patch.dict("os.environ", environment, clear=True), \
             mock.patch.object(deploy, "cloudflare_api", fake), \
             mock.patch.object(deploy, "deploy_to_cloudflare", fake_upload), \
             mock.patch.object(deploy, "ensure_base_url_and_rebuild", lambda *arguments: None), \
             mock.patch.object(deploy, "NON_INTERACTIVE", non_interactive), \
             redirect_stdout(output):
            deploy.publish_to_cloudflare(self.public_dir, self.course_dir, "ADA1O", "1", "Gordon")
        return output.getvalue()

    def saved_marker(self) -> dict:
        return json.loads(deploy._cf_marker_path(self.course_dir, "1").read_text(encoding="utf-8"))

    def test_a_deleted_project_is_made_again_under_the_same_name(self):
        fake = FakeCloudflare(existing=set())
        output = self.publish(fake)
        self.assertEqual(fake.posted(), [{"name": "ada1o-s1-2026-testing", "production_branch": "main"}])
        self.assertEqual(self.uploaded_to, ["ada1o-s1-2026-testing"],
                         "the upload must go to the project that now exists")
        marker = self.saved_marker()
        self.assertEqual(marker["id"], "new-id")
        self.assertEqual(marker["subdomain"], "ada1o-s1-2026-testing-7x2.pages.dev")
        self.assertIn("https://ada1o-s1-2026-testing-7x2.pages.dev", output,
                      "the address given must be the recreated project's, which can differ")

    def test_remaking_it_asks_nothing_so_a_windowless_publish_does_it_too(self):
        fake = FakeCloudflare(existing=set())
        self.publish(fake, non_interactive=True)
        self.assertEqual(len(fake.posted()), 1)
        self.assertEqual(self.uploaded_to, ["ada1o-s1-2026-testing"])

    def test_a_project_that_exists_is_left_alone(self):
        fake = FakeCloudflare(existing={"ada1o-s1-2026-testing"})
        self.publish(fake)
        self.assertEqual(fake.posted(), [])
        self.assertEqual(self.saved_marker()["id"], "old-id")
        self.assertEqual(self.uploaded_to, ["ada1o-s1-2026-testing"])

    def test_a_check_that_fails_for_another_reason_does_not_stop_the_publish(self):
        fake = FakeCloudflare(existing=set(), get_failure="Cloudflare API error 503: try again")
        self.publish(fake)
        self.assertEqual(fake.posted(), [], "only a 404 means the project is gone")
        self.assertEqual(self.uploaded_to, ["ada1o-s1-2026-testing"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

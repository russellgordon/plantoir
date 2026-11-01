#!/usr/bin/env python3
"""deploy.sh deploys where the course's settings say when no destination is typed (#668).

Russell, 2026-11-01: a deploy typed at the command line goes where the
course's own `deploy_target` says, as the app's Deploy button does, so a
course made for Cloudflare Pages - every new course since #668 - is not
quietly deployed to Netlify. `--target` and `--to-folder` still decide when
they are typed. `additional_deploy_targets` are deployed one leg each, by
running the launcher again with that leg's flag, the app's own shape.

Each case runs a COPY of deploy.sh in an empty folder holding only the
course's settings: it reads the destination, says it, and then stops at the
missing recipe for the website builder, long before anything needs Docker,
the network or a credential. The line it says is what is read here.

Listed in verify.sh; Windows' PythonToolchainTests discovers it, and skips it
there when no bash can run the launcher (see test_deploy_non_interactive).

    python3 scripts/test_deploy_sh_destination.py
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import test_deploy_non_interactive as launcher_harness  # noqa: E402

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
STOPPED_BEFORE_THE_BUILDER = "missing the recipe for its website builder"


class DeployShReadsTheSavedDestination(unittest.TestCase):

    def setUp(self):
        self.shell = launcher_harness._a_bash_that_can_run_deploy_sh()
        if self.shell is None:
            self.skipTest("no bash on this machine that can run a launcher from a native path")
        probe = subprocess.run(
            self.shell + ["-c", "command -v python3 || command -v python"],
            capture_output=True, timeout=60, encoding="utf-8", errors="replace",
        )
        if probe.returncode != 0 or not probe.stdout.strip():
            self.skipTest("the bash that runs the launcher has no python to read the settings with")

    def run_deploy(self, settings, *flags, every_leg_reads_stdin=False, path=None):
        """Runs a copy of deploy.sh for ICS3U section 1; returns its output and exit code.

        `every_leg_reads_stdin` plants `cat >/dev/null` just before the recipe
        check in the copy, standing in for what a real leg does there and
        after: `docker exec -i` forwards stdin to the container, and a token
        prompt waits on it (#668 review H1). `path` replaces PATH for the run.
        """
        with tempfile.TemporaryDirectory() as folder:
            launcher = Path(folder) / "deploy.sh"
            text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
            if every_leg_reads_stdin:
                marker = "# Resolve IMAGE (same rules as setup.sh and preview.sh)\n"
                self.assertEqual(text.count(marker), 1, "the place the probe is planted has moved")
                text = text.replace(marker, "cat >/dev/null\n" + marker)
            launcher.write_bytes(text.encode("utf-8"))
            course = Path(folder) / "courses" / "ICS3U"
            course.mkdir(parents=True)
            if isinstance(settings, str):
                (course / "course_config.json").write_text(settings, encoding="utf-8")
            else:
                (course / "course_config.json").write_text(json.dumps(settings), encoding="utf-8")
            environment = dict(os.environ)
            if path is not None:
                environment["PATH"] = path
            result = subprocess.run(
                self.shell + [str(launcher), "ICS3U", "1", "--non-interactive", *flags],
                capture_output=True, timeout=180, stdin=subprocess.DEVNULL,
                encoding="utf-8", errors="replace", env=environment,
            )
            return result.stdout + result.stderr, result.returncode

    def test_a_cloudflare_course_with_no_target_deploys_to_cloudflare(self):
        said, _ = self.run_deploy({"course_code": "ICS3U", "deploy_target": "cloudflare_pages"})
        self.assertIn("Deploying to Cloudflare Pages, as ICS3U's settings say.", said)
        self.assertIn(STOPPED_BEFORE_THE_BUILDER, said, "it stopped before reaching the builder")

    def test_a_typed_target_still_wins(self):
        said, _ = self.run_deploy(
            {"course_code": "ICS3U", "deploy_target": "cloudflare_pages"}, "--target", "netlify"
        )
        self.assertNotIn("Cloudflare", said, "--target netlify lost to the course's settings")
        self.assertNotIn("as ICS3U's settings say", said)
        self.assertIn(STOPPED_BEFORE_THE_BUILDER, said)

    def test_a_course_that_names_no_destination_deploys_to_netlify_as_before(self):
        said, _ = self.run_deploy({"course_code": "ICS3U"})
        self.assertIn("Deploying to Netlify, as ICS3U's settings say.", said)
        self.assertNotIn("Cloudflare", said)

    def test_a_folder_course_deploys_to_its_folder_and_a_folder_with_none_refuses(self):
        said, code = self.run_deploy({"course_code": "ICS3U", "deploy_target": "local_folder"})
        self.assertNotEqual(code, 0)
        self.assertIn("no folder is chosen in its settings", said)
        self.assertIn("Nothing was deployed.", said)

    def test_every_destination_is_a_leg_of_its_own(self):
        said, code = self.run_deploy({
            "course_code": "ICS3U",
            "deploy_target": "netlify",
            "additional_deploy_targets": [{"type": "cloudflare_pages"}],
        })
        self.assertIn("Deploying ICS3U section 1 to Netlify, as its settings say.", said)
        self.assertIn("Deploying ICS3U section 1 to Cloudflare Pages, as its settings say.", said)
        self.assertEqual(said.count(STOPPED_BEFORE_THE_BUILDER), 2,
                         "each destination should run as its own leg, and every leg go on after one fails")
        self.assertNotEqual(code, 0, "a run whose legs failed must not end in success")

    def test_a_leg_that_reads_stdin_does_not_swallow_the_other_legs(self):
        """MUST-FAIL on the first version, whose list of legs WAS the loop's
        stdin: the first leg's `docker exec -i` (here, `cat`) read it to the
        end, and the other legs never ran."""
        said, code = self.run_deploy({
            "course_code": "ICS3U",
            "deploy_target": "netlify",
            "additional_deploy_targets": [{"type": "cloudflare_pages"}],
        }, every_leg_reads_stdin=True)
        self.assertIn("Deploying ICS3U section 1 to Cloudflare Pages, as its settings say.", said,
                      "the first leg swallowed the list of legs")
        self.assertEqual(said.count(STOPPED_BEFORE_THE_BUILDER), 2)
        self.assertNotEqual(code, 0)

    @unittest.skipUnless(sys.platform == "darwin", "plutil is the Mac's reader")
    def test_a_mac_with_no_python_still_reads_the_destination(self):
        """The rule the reference-course check keeps (#668 review M1): a
        command-line deploy needs no host python3, which a Mac without the
        Command Line Tools does not have."""
        with tempfile.TemporaryDirectory() as tools:
            for folder in ("/usr/bin", "/bin", "/usr/sbin", "/sbin"):
                for entry in os.listdir(folder):
                    if entry.startswith("python") or (Path(tools) / entry).exists():
                        continue
                    os.symlink(os.path.join(folder, entry), os.path.join(tools, entry))
            said, _ = self.run_deploy({
                "course_code": "ICS3U",
                "deploy_target": "cloudflare_pages",
                "additional_deploy_targets": [{"type": "netlify"}],
            }, path=tools)
        self.assertNotIn("could not read where", said, "the launcher needed a Python to read the settings")
        self.assertIn("Deploying ICS3U section 1 to Cloudflare Pages, as its settings say.", said)
        self.assertIn("Deploying ICS3U section 1 to Netlify, as its settings say.", said)

    def test_settings_that_cannot_be_read_refuse_rather_than_fall_back_to_netlify(self):
        said, code = self.run_deploy('{"course_code": "ICS3U", "deploy_target": ')
        self.assertNotEqual(code, 0)
        self.assertIn("could not read where ICS3U deploys", said)
        self.assertNotIn(STOPPED_BEFORE_THE_BUILDER, said)


if __name__ == "__main__":
    unittest.main()

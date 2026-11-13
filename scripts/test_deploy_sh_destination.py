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

The last class runs `contracts/app-rules.json` -> `savedDestinations` (#771):
every case through the reader functions cut from deploy.sh, with each
reader, and every sentence pinned to the line the launcher prints.

Listed in verify.sh; Windows' PythonToolchainTests discovers it, and skips it
there when no bash can run the launcher (see test_deploy_non_interactive).

    python3 scripts/test_deploy_sh_destination.py
"""

import atexit
import shutil
import json
import os
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

sys.path.insert(0, str(Path(__file__).resolve().parent))

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
# Set before anything first imports toolchain_paths (contracts does, and
# test_deploy_non_interactive reaches it through deploy.py), which reads it
# once, at import.
os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))

import contracts  # noqa: E402
import test_deploy_non_interactive as launcher_harness  # noqa: E402

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


THE_DESTINATION_BLOCK_BEGINS = "# ---- Where this course deploys, when no destination was typed (#668) ----\n"
THE_DESTINATION_BLOCK_ENDS = "# >>> DEPLOY WHILE ITS SECTION DEPLOYS GUARD >>>"

# What each placeholder in savedDestinations.sentences is in deploy.sh's
# printed lines.
THE_LAUNCHERS_PLACEHOLDERS = {
    "{course}": "${COURSE_CODE}",
    "{section}": "${SECTION_NUM}",
    "{where}": '$(destination_words "$_kind")',
    "{refusal}": "${_leg_output}",
    "{kind}": "${kind}",
}

# The launcher's own reading loop, run on the cut-out functions: a settings
# file that cannot be read, or reads as nothing, is unreadable (the
# couldNotRead refusal); otherwise each line is a leg, written
# LEG <kind> <flags joined by US> or REFUSED <kind> <refusal>.
LEGS_SCRIPT = r'''
if ! saved="$(the_saved_destinations "$1" 2>/dev/null)" || [[ -z "$saved" ]]; then
  echo UNREADABLE
  exit 0
fi
while IFS=$'\t' read -r kind path; do
  [[ -n "$kind" ]] || continue
  if output="$(flags_for_the_saved_destination "$kind" "$path")"; then
    printf 'LEG\t%s\t%s\n' "$kind" "$(printf '%s' "$output" | tr '\n' '\037')"
  else
    printf 'REFUSED\t%s\t%s\n' "$kind" "$output"
  fi
done <<< "$saved"
'''


def _the_launchers_text() -> str:
    return (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")


def _cut_from_deploy_sh(name: str) -> str:
    text = _the_launchers_text()
    begin = f"# BEGIN {name}\n"
    end = f"# END {name}\n"
    if text.count(begin) != 1 or text.count(end) != 1:
        raise AssertionError(f"deploy.sh no longer carries {name} between its markers")
    return text[text.index(begin) + len(begin):text.index(end)]


def _printed(line: str):
    """What an `echo "…"` line prints, with the cross or target and the
    indent taken off the front as a teacher's window lifts them, or None."""
    stripped = line.strip()
    if not (stripped.startswith('echo "') and stripped.endswith('"')):
        return None
    said = stripped[len('echo "'):-1]
    while said and not (said[0].isascii() and (said[0].isalnum() or said[0] in "${")):
        said = said[1:]
    return said


def _the_destination_blocks_printed_lines() -> list:
    text = _the_launchers_text()
    if text.count(THE_DESTINATION_BLOCK_BEGINS) != 1 or text.count(THE_DESTINATION_BLOCK_ENDS) != 1:
        raise AssertionError("deploy.sh's #668 destination block has lost its first or last line")
    block = text[text.index(THE_DESTINATION_BLOCK_BEGINS):text.index(THE_DESTINATION_BLOCK_ENDS)]
    printed = []
    for line in block.split("\n"):
        said = _printed(line)
        if said:
            printed.append(said)
    return printed


def _as_the_launcher_writes_it(sentence: str) -> str:
    written = sentence
    for placeholder, variable in THE_LAUNCHERS_PLACEHOLDERS.items():
        written = written.replace(placeholder, variable)
    return written


class TheSavedDestinationsAreTheContracts(unittest.TestCase):
    """GitHub #771: deploy.sh runs `contracts/app-rules.json` ->
    `savedDestinations`, the cases Windows proposed (#739) and deploy.ps1 runs.

    The block's functions are CUT from deploy.sh and run with the launcher's
    own reading loop, once with plutil (the Mac's reader) and once with only
    a Python to read with (every other bash). The whole-launcher tests above
    cover the loop that runs the legs.
    """

    def setUp(self):
        self.shell = launcher_harness._a_bash_that_can_run_deploy_sh()
        if self.shell is None:
            self.skipTest("no bash on this machine that can run deploy.sh's definitions")
        if not shutil.which("plutil"):
            # The class above's rule: off a Mac the Python reader is the only
            # one, and a bash that has no Python cannot read the settings.
            probe = subprocess.run(
                self.shell + ["-c", "command -v python3 || command -v python"],
                capture_output=True, timeout=60, encoding="utf-8", errors="replace",
            )
            if probe.returncode != 0 or not probe.stdout.strip():
                self.skipTest("the bash that runs the launcher has no python to read the settings with")
        self.rule = contracts.section("app-rules", "savedDestinations")

    def _legs(self, case, path=None) -> list:
        with tempfile.TemporaryDirectory() as folder:
            settings = Path(folder) / "course_config.json"
            if "settingsText" in case:
                settings.write_text(case["settingsText"], encoding="utf-8")
            else:
                settings.write_text(json.dumps(case["settings"]), encoding="utf-8")
            environment = dict(os.environ)
            if path is not None:
                environment["PATH"] = path
            script = (f"COURSE_CODE={self.rule['course']}\n"
                      + _cut_from_deploy_sh("saved_destinations") + LEGS_SCRIPT)
            result = subprocess.run(
                self.shell + ["-c", script, "_", str(settings)],
                capture_output=True, timeout=60, encoding="utf-8", errors="replace",
                env=environment,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout.rstrip("\n").split("\n")

    def _expected(self, case) -> list:
        if case.get("expectUnreadable"):
            return ["UNREADABLE"]
        expected = []
        for leg in case["expectLegs"]:
            if "flags" in leg:
                expected.append("LEG\t" + leg["kind"] + "\t" + "\x1f".join(leg["flags"]))
            else:
                expected.append("REFUSED\t" + leg["kind"] + "\t" + leg["refusal"])
        return expected

    # The one case Windows' Python cannot run through Git Bash, by name (step 0
    # of v2.0.0, 2026-11-13). Measured with `od -c` on Windows 11 Pro 26200:
    # the heredoc reader, run by Windows' own Python, prints its lines with
    # CRLF ("local_folder\t\r\n"), so bash reads an empty path as "\r", which
    # is not empty, and the leg gets --to-folder instead of the refusal.
    # No teacher runs deploy.sh on Windows (deploy.ps1 is that platform's
    # launcher, and its own reader passes this case in test_launcher_rules.ps1);
    # the Mac and Linux Pythons print "\n", so the case still runs there.
    _CRLF_FROM_WINDOWS_PYTHON = "an additional folder with no folder is a refused leg, and the others still run"

    def _run_every_case(self, path=None):
        self.assertTrue(self.rule["cases"], "the contract carries no cases to run")
        for case in self.rule["cases"]:
            with self.subTest(case=case["name"]):
                if os.name == "nt" and case["name"] == self._CRLF_FROM_WINDOWS_PYTHON:
                    self.skipTest("Windows' Python prints the reader's lines with CRLF, so under Git Bash "
                                  "an empty path reaches deploy.sh as a path of \\r; deploy.sh is the Mac's "
                                  "launcher and deploy.ps1 passes this case")
                self.assertEqual(self._legs(case, path), self._expected(case))

    @unittest.skipUnless(shutil.which("plutil"), "plutil is the Mac's reader")
    def test_every_case_through_plutil(self):
        """MUST-FAIL before #771: settings of ["netlify"] converted cleanly,
        every -extract on them failed, and the course deployed to Netlify."""
        self._run_every_case()

    def test_every_case_through_python(self):
        """The reader every bash but a Mac's uses, so on a Mac PATH is cut to
        a Python and `tr` and plutil is not found."""
        if not shutil.which("plutil"):
            self._run_every_case()
            return
        python = shutil.which("python3")
        if python is None:
            self.skipTest("no python3 to read the settings with")
        with tempfile.TemporaryDirectory() as tools:
            os.symlink(python, os.path.join(tools, "python3"))
            os.symlink(shutil.which("tr"), os.path.join(tools, "tr"))
            self._run_every_case(path=tools)

    def test_one_destination_deploys_with_the_flags_the_contract_checks(self):
        """With ONE saved destination the launcher does not run a leg with
        the flags; it sets TARGET or TO_FOLDER through
        the_one_saved_destination. Every leg the contract accepts, set that
        way, must be what its flags say (#771 review M1)."""
        text = _the_launchers_text()
        block = _cut_from_deploy_sh("saved_destinations")
        self.assertEqual(text.count('the_one_saved_destination "$_kind" "$_path"'), 1,
                         "the one-destination run no longer sets its destination through the block's function")
        script = (block + '\nTARGET=unset\nTO_FOLDER=\n'
                  'the_one_saved_destination "$1" "$2"\nprintf "%s\\t%s" "$TARGET" "$TO_FOLDER"\n')
        checked = 0
        for case in self.rule["cases"]:
            for leg in case.get("expectLegs", []):
                if "flags" not in leg:
                    continue
                flag, value = leg["flags"]
                path = value if flag == "--to-folder" else ""
                expected = (value, "") if flag == "--target" else ("unset", value)
                with self.subTest(case=case["name"], kind=leg["kind"]):
                    result = subprocess.run(
                        self.shell + ["-c", script, "_", leg["kind"], path],
                        capture_output=True, timeout=60, encoding="utf-8", errors="replace",
                    )
                    self.assertEqual(tuple(result.stdout.split("\t")), expected)
                checked += 1
        self.assertTrue(checked, "the contract carries no accepted leg to check")

    def test_the_sentences_are_the_contracts(self):
        """Every sentence in savedDestinations.sentences is a line the block
        prints, and the block prints nothing else a teacher reads."""
        printed = _the_destination_blocks_printed_lines()
        sentences = self.rule["sentences"]
        expected = []
        for key, sentence in sentences.items():
            if key == "where":
                continue
            if isinstance(sentence, list):
                written = []
                for line in sentence:
                    written.append(_as_the_launcher_writes_it(line))
                with self.subTest(sentence=key):
                    found = False
                    for index in range(len(printed) - len(written) + 1):
                        if printed[index:index + len(written)] == written:
                            found = True
                    self.assertTrue(found, f"deploy.sh does not print {written} in a row")
                expected.extend(written)
            else:
                written = _as_the_launcher_writes_it(sentence)
                with self.subTest(sentence=key):
                    self.assertIn(written, printed)
                expected.append(written)
        for line in printed:
            with self.subTest(printed=line):
                self.assertIn(line, expected, "the block prints a sentence the contract does not carry")

    def test_where_is_the_contracts(self):
        """sentences.where, and a kind it does not list reads as Netlify's word."""
        where = self.rule["sentences"]["where"]
        script = _cut_from_deploy_sh("saved_destinations") + '\ndestination_words "$1"\n'
        kinds = dict(where)
        kinds["github_pages"] = where["netlify"]
        for kind, words in kinds.items():
            with self.subTest(kind=kind):
                result = subprocess.run(
                    self.shell + ["-c", script, "_", kind],
                    capture_output=True, timeout=60, encoding="utf-8", errors="replace",
                )
                self.assertEqual(result.stdout.strip(), words)


if __name__ == "__main__":
    unittest.main()

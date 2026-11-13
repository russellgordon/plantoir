#!/usr/bin/env python3
"""
The shared rules for sharing a course's unit plans (#709), with no network:
`scripts/unit_plan_site.py` against every case in contracts/shared-rules.json
-> unitPlanning.share (checkCases, stageCases, answerKeys, names, schoolYear,
workerCases).

The worker cases run the REAL `_worker.js` under node, with a stand-in ASSETS,
so what is proved is the program Cloudflare runs, not a description of it.
They skip only when there is no node (Windows' runtime carries one).

Stdlib only. Run with:

    python3 scripts/test_unit_plan_site.py
"""
import base64
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY / "contracts"))
os.environ.setdefault("PLANTOIR_SUPPORT_DIR", str(REPOSITORY / "support"))
sys.path.insert(0, str(REPOSITORY / "scripts"))

import unit_plan_site  # noqa: E402

TEMPLATE = REPOSITORY / "support" / "agent_guidance" / "skills" / "plantoir-unit-planning" / "template"
NODE = shutil.which("node")
WORKER_USER = "colleague"
WORKER_PASSWORD = "correct horse 7"


def share():
    return unit_plan_site.share_rules()


def a_planning_folder(tmp: Path) -> Path:
    folder = tmp / "planning"
    shutil.copytree(TEMPLATE, folder)
    return folder


def apply_change(folder: Path, change: dict) -> None:
    for relative in change.get("remove", []):
        target = folder / relative
        if target.is_dir():
            shutil.rmtree(target)
        else:
            target.unlink()
    for old, new in change.get("rename", {}).items():
        (folder / old).rename(folder / new)
    for old, new in change.get("copy", {}).items():
        shutil.copytree(folder / old, folder / new)
    for relative, text in change.get("write", {}).items():
        target = folder / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(text.encode("utf-8"))
    for relative, text in change.get("append", {}).items():
        target = folder / relative
        page = target.read_text(encoding="utf-8")
        target.write_text(page.replace("</body>", text + "\n</body>"), encoding="utf-8")
    for relative, pair in change.get("replace", {}).items():
        target = folder / relative
        page = target.read_text(encoding="utf-8")
        if pair[0] not in page:
            raise AssertionError(f"{relative} no longer holds {pair[0]!r}")
        target.write_text(page.replace(pair[0], pair[1]), encoding="utf-8")


def kinds_of(problems) -> list:
    kinds = []
    for problem in problems:
        if problem.kind not in kinds:
            kinds.append(problem.kind)
    return kinds


class CheckTests(unittest.TestCase):

    def test_every_check_case(self):
        for case in share()["checkCases"]["cases"]:
            with self.subTest(case=case["name"]), tempfile.TemporaryDirectory() as tmp:
                folder = a_planning_folder(Path(tmp))
                apply_change(folder, case["change"])
                problems = unit_plan_site.check(folder, unit_plan_site.bundled_assets_dir())
                lines = []
                for problem in problems:
                    lines.append(f"{problem.kind} {problem.line()}")
                self.assertEqual(kinds_of(problems), case["expect"], "\n".join(lines))

    def test_the_kinds_are_the_contracts_and_in_its_order(self):
        order = share()["checkKinds"]
        self.assertEqual(len(order), len(set(order)))
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_planning_folder(Path(tmp))
            apply_change(folder, {"remove": ["robots.txt"], "rename": {"unit": "Unit-1"}})
            kinds = kinds_of(unit_plan_site.check(folder))
            positions = []
            for kind in kinds:
                positions.append(order.index(kind))
            self.assertEqual(positions, sorted(positions))

    def test_a_missing_planning_folder_is_no_plans(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(kinds_of(unit_plan_site.check(Path(tmp) / "absent")), ["noPlans"])

    def test_a_file_over_25_megabytes_is_too_large(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_planning_folder(Path(tmp))
            big = folder / "unit" / "pdfs" / "Huge.pdf"
            big.parent.mkdir(parents=True, exist_ok=True)
            with open(big, "wb") as handle:
                handle.truncate(unit_plan_site.MAX_FILE_BYTES + 1)
            self.assertIn("tooLarge", kinds_of(unit_plan_site.check(folder)))


class StageTests(unittest.TestCase):

    def test_every_stage_case(self):
        for case in share()["stageCases"]["cases"]:
            with self.subTest(case=case["name"]), tempfile.TemporaryDirectory() as tmp:
                folder = a_planning_folder(Path(tmp))
                for relative in case["add"]:
                    target = folder / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(b"%PDF-1.4 invented" if relative.endswith(".pdf") else b"x")
                out = Path(tmp) / "staged"
                staged = unit_plan_site.stage(folder, out, unit_plan_site.bundled_assets_dir(),
                                              case["includeAnswerKeys"])
                for relative in case["notCopied"]:
                    self.assertFalse((out / relative).exists(), f"{relative} was staged")
                for relative in case["copied"]:
                    if relative in case["notCopied"]:
                        continue
                    self.assertTrue((out / relative).is_file(), f"{relative} was not staged")
                self.assertEqual(staged.answer_keys_left_out, case["answerKeysLeftOut"])

    def test_the_404_page_says_the_contracts_words_and_asks_to_be_left_alone(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_planning_folder(Path(tmp))
            (folder / "404.html").write_text("<p>a teacher's own</p>", encoding="utf-8")
            out = Path(tmp) / "staged"
            unit_plan_site.stage(folder, out, unit_plan_site.bundled_assets_dir(), False)
            page = (out / "404.html").read_text(encoding="utf-8")
            self.assertIn(share()["words"]["notSharedHere"], page)
            self.assertIn('<meta name="robots" content="noindex, nofollow">', page)
            self.assertNotIn("a teacher's own", page)

    def test_the_apps_assets_replace_the_plans_own(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_planning_folder(Path(tmp))
            (folder / "assets" / "plan.css").write_text("/* edited by hand */", encoding="utf-8")
            (folder / "assets" / "extra.css").write_text("/* added */", encoding="utf-8")
            out = Path(tmp) / "staged"
            unit_plan_site.stage(folder, out, unit_plan_site.bundled_assets_dir(), False)
            self.assertEqual((out / "assets" / "plan.css").read_bytes(),
                             (TEMPLATE / "assets" / "plan.css").read_bytes())
            self.assertFalse((out / "assets" / "extra.css").exists())

    def test_a_link_is_never_followed(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_planning_folder(Path(tmp))
            secret = Path(tmp) / "elsewhere.txt"
            secret.write_text("not for sharing", encoding="utf-8")
            os.symlink(secret, folder / "unit" / "linked.txt")
            out = Path(tmp) / "staged"
            unit_plan_site.stage(folder, out, unit_plan_site.bundled_assets_dir(), False)
            self.assertFalse((out / "unit" / "linked.txt").exists())

    def test_the_units_are_counted(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = a_planning_folder(Path(tmp))
            shutil.copytree(folder / "unit", folder / "unit-2")
            staged = unit_plan_site.stage(folder, Path(tmp) / "staged", None, False)
            self.assertEqual(staged.units, 2)


class AnswerKeyTests(unittest.TestCase):

    def test_every_answer_key_case(self):
        for case in share()["answerKeys"]["cases"]:
            with self.subTest(name=case["name"]):
                self.assertEqual(unit_plan_site.is_answer_key(case["name"]), case["answerKey"])


class NameAndYearTests(unittest.TestCase):

    def test_every_name_case(self):
        for case in share()["names"]["cases"]:
            with self.subTest(code=case["code"], surname=case["surname"]):
                name = unit_plan_site.project_name(case["code"], case["year"], case["surname"], case["suffix"])
                self.assertEqual(name, case["name"])
                self.assertLessEqual(len(name), share()["names"]["maxLength"])
                self.assertTrue(name.endswith("-" + case["suffix"]), "the suffix was cut")

    def test_every_school_year_case(self):
        for case in share()["schoolYear"]["cases"]:
            with self.subTest(day=case["day"]):
                year = unit_plan_site.school_year(dt.date.fromisoformat(case["day"]))
                self.assertEqual(year, case["year"])
                self.assertEqual(unit_plan_site.year_label(year), case["label"])

    def test_a_new_suffix_is_its_length_from_its_letters(self):
        seen = set()
        for _ in range(20):
            suffix = unit_plan_site.new_suffix()
            self.assertEqual(len(suffix), share()["names"]["suffixLength"])
            self.assertRegex(suffix, r"^[a-z0-9]+$")
            seen.add(suffix)
        self.assertGreater(len(seen), 15)

    def test_the_open_headers_are_the_contracts(self):
        self.assertEqual(unit_plan_site.open_headers(), share()["openHeaders"])


WORKER_HARNESS = r"""
import worker from "./worker.mjs";
const cases = JSON.parse(process.argv[2]);
const auths = JSON.parse(process.argv[3]);
const env = { ASSETS: { fetch: async (request) => new Response("asset " + new URL(request.url).pathname, { status: 200, headers: { "Content-Type": "text/plain" } }) } };
const out = [];
for (const c of cases) {
  const headers = {};
  if (auths[c.auth]) headers["Authorization"] = auths[c.auth];
  const answer = await worker.fetch(new Request("https://plans.example" + c.path, { headers }), env);
  out.push({ status: answer.status, challenge: answer.headers.get("WWW-Authenticate"), robots: answer.headers.get("X-Robots-Tag"), cache: answer.headers.get("Cache-Control"), body: await answer.text() });
}
console.log(JSON.stringify(out));
"""

SHARED_FILES = ["index.html", "unit/index.html", "unit/correlation.html", "unit/pdfs/Quiz 1, Solutions.pdf",
                "robots.txt", "404.html"]


@unittest.skipIf(NODE is None, "node is not installed here")
class WorkerTests(unittest.TestCase):

    def run_worker(self, source: str, cases: list, auths: dict) -> list:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "worker.mjs").write_text(source, encoding="utf-8")
            (Path(tmp) / "harness.mjs").write_text(WORKER_HARNESS, encoding="utf-8")
            done = subprocess.run([NODE, str(Path(tmp) / "harness.mjs"), json.dumps(cases), json.dumps(auths)],
                                  capture_output=True, text=True, timeout=60, cwd=tmp)
            self.assertEqual(done.returncode, 0, done.stderr)
            return json.loads(done.stdout.strip().splitlines()[-1])

    def auths(self) -> dict:
        right = unit_plan_site.credential_b64(WORKER_USER, WORKER_PASSWORD)
        wrong = unit_plan_site.credential_b64(WORKER_USER, "correct horse 8")
        return {"none": "", "wrong": "Basic " + wrong, "right": "Basic " + right}

    def test_every_worker_case(self):
        credential = unit_plan_site.credential_b64(WORKER_USER, WORKER_PASSWORD)
        sources = {
            "protected": unit_plan_site.worker_js(credential, unit_plan_site.realm_for("SNC2D"), SHARED_FILES),
            "open": unit_plan_site.worker_js(None, unit_plan_site.realm_for("SNC2D"), SHARED_FILES),
        }
        for mode, source in sources.items():
            cases = []
            for case in share()["workerCases"]["cases"]:
                if case["mode"] == mode:
                    cases.append(case)
            # The right password twice: the second answer is the remembered one.
            results = self.run_worker(source, cases + cases[2:3], self.auths())
            for case, result in zip(cases, results):
                with self.subTest(mode=mode, path=case["path"], auth=case["auth"]):
                    self.assertEqual(result["status"], case["status"])
                    if case["basicChallenge"]:
                        self.assertEqual(result["challenge"], 'Basic realm="SNC2D unit plans", charset="UTF-8"')
                    else:
                        self.assertIsNone(result["challenge"])
                    self.assertEqual(result["robots"], "noindex, nofollow")
                    self.assertIn("no-store", result["cache"])
                    if case["status"] == 200:
                        self.assertTrue(result["body"].startswith("asset "))
                    if case["status"] == 404:
                        self.assertEqual(result["body"], "asset /404.html")
            self.assertEqual(results[-1]["status"], cases[2]["status"])

    def test_the_password_is_not_in_the_worker_and_two_shares_have_two_salts(self):
        credential = unit_plan_site.credential_b64(WORKER_USER, WORKER_PASSWORD)
        first = unit_plan_site.worker_js(credential, "X unit plans", SHARED_FILES)
        second = unit_plan_site.worker_js(credential, "X unit plans", SHARED_FILES)
        for source in (first, second):
            self.assertNotIn(WORKER_PASSWORD, source)
            self.assertNotIn(credential, source)
            self.assertNotIn(WORKER_USER, source)
        self.assertNotEqual(first, second)

    def test_the_worker_never_lists_itself(self):
        source = unit_plan_site.worker_js(None, "X unit plans", SHARED_FILES + ["_worker.js", "_headers"])
        self.assertNotIn('"_worker.js"', source)
        self.assertNotIn('"_headers"', source)

    def test_a_realm_cannot_end_the_header(self):
        self.assertEqual(unit_plan_site.realm_for('AB"C\\D'), "ABCD unit plans")


if __name__ == "__main__":
    unittest.main(verbosity=1)

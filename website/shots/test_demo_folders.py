#!/usr/bin/env python3
"""
A clone can make both demo working folders from the repository alone (#445).

plantoir.app's pictures are taken in two working folders: the demo folder
(ENG2D, MCV4U, SCH3U — the hero, the app windows and the class sites) and the
marketing folder (ICS3U, ICS4U, a reference copy, the College Board pages —
the v1.4.0 scenes). ``marketing/folders.json`` describes both as rules; this
test lays each course out the way the app's new-course panel does (the real
installer, ``setup_course.install_example_content``, imported from scripts/),
applies every file step and rule, and checks what each SCENE needs — not
byte-identity with the kept folders, which follow the payloads as they change.

It runs twice, with the clock in September 2026 and in September 2027, so a
date written down as a date (a second semester starting "2027-02-01", a
reference year "2025–26", a front page "dated January 15") turns it red.

Three parts are skipped by default, each saying why:
- the College Board pages' WORDS: never in this repository; the test uses a
  stand-in page per code the correlations name;
- the front pages THROUGH THE APP: needs a built app; set
  PLANTOIR_DEMO_FOLDERS_APP to its binary (Plantoir.app/Contents/MacOS/Plantoir);
- the comparison with the KEPT folders on Russell's Mac: opt-in only,
  PLANTOIR_DEMO_FOLDERS_COMPARE=1. It reads them, copies their source pages
  into a temporary folder, and writes nothing to them.

Stdlib only; the same file runs on macOS (verify.sh) and Windows
(capture_windows.py runs it first).

    python3 website/shots/test_demo_folders.py
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys
import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path

# No .pyc files: scripts/ is copied into the app bundle and hashed into the
# image tag, so bytecode left there by a test run would hand teachers a rebuild
# (verify.sh sets PYTHONDONTWRITEBYTECODE for the same reason).
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO / "scripts"))

import demo_folders  # noqa: E402
import marketing_folder  # noqa: E402
import setup_course  # noqa: E402

SPEC = demo_folders.load_spec()
PAYLOADS = REPO / "support" / "example_content"
UI_TESTS = REPO / "mac-app" / "Tests" / "QuartzTeachersUITests" / "MarketingScreenshotTests.swift"
CURRICULUM_BLOCK = re.compile(r"^##\s+Curriculum connection\s*$", re.MULTILINE)


# ---------- Laying a folder out the way the app does ----------

def make_course(folder: Path, code: str, sections: list[int], clock: datetime) -> Path:
    """One course from its ready-made content, as the new-course panel makes
    it: the configuration it writes, then the installer with the clock as
    "now". Not a copy of a kept folder — the payload in this checkout."""
    payload = PAYLOADS / code
    manifest = setup_course.load_example_content_manifest(payload)
    course_dir = folder / "courses" / code
    course_dir.mkdir(parents=True, exist_ok=True)
    schemes: dict[str, str] = {}
    for section in sections:
        schemes[f"section{section}"] = "quartz-standard"
    config = {
        "course_code": code,
        "section_numbers": sections,
        "num_sections": len(sections),
        "shared_folders": list(manifest.get("shared_folders", [])),
        "shared_files": list(manifest.get("shared_files", [])),
        "per_section_folders": list(manifest.get("per_section_folders", [])),
        "per_section_files": list(manifest.get("per_section_files", [])),
        "hidden": list(manifest.get("hidden", [])) + ["Media"],
        "class_folder": "All Classes",
        "curriculum_folder": "Curriculum",
        "curriculum_folders": ["Curriculum"],
        "color_schemes": schemes,
        "deploy_target": "netlify",
        "deploy_folder_path": "",
    }
    (course_dir / "course_config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    now = clock.strftime("%Y-%m-%dT%H:%M:%S.000%z")
    setup_course.install_example_content(
        course_dir, payload, manifest, sections, now, True,
        config["shared_folders"], config["shared_files"],
        config["per_section_folders"], config["per_section_files"],
        reference=clock, course_code=code,
    )
    return course_dir


def stand_in_college_board_pages() -> dict[str, str]:
    """One page per code the correlations name. The College Board's words are
    never in this repository (folders.json → marketing.collegeBoardPages)."""
    pages: dict[str, str] = {}
    for course in marketing_folder.CSP_COURSES:
        for row in marketing_folder.load_correlation(course["correlation"]):
            for code in row["codes"]:
                pages[code] = f"---\ntitle: {code}\n---\nstand-in: the College Board's words are not in this repository\n"
    return pages


def make_demo_folder(root: Path, clock: datetime) -> Path:
    folder = root / "Teaching"
    for course in demo_folders.demo_courses(SPEC):
        make_course(folder, course["code"], course["sections"], clock)
    return folder


def make_marketing_folder(root: Path, clock: datetime) -> tuple[Path, marketing_folder.Report]:
    folder = root / "Plantoir Marketing"
    marketing_folder.mark_as_ours(folder)
    for course in demo_folders.marketing_courses(SPEC):
        make_course(folder, course["code"], course["sections"], clock)
    report = marketing_folder.apply_file_steps(folder, stand_in_college_board_pages())
    return folder, report


def curriculum_block(text: str) -> str:
    match = CURRICULUM_BLOCK.search(text)
    if match is None:
        return ""
    rest = text[match.end():]
    following = re.search(r"^#{1,6}\s", rest, re.MULTILINE)
    return rest[:following.start()] if following else rest


def find_page(course_dir: Path, title: str) -> Path | None:
    for page in course_dir.rglob(f"{title}.md"):
        return page
    return None


# ---------- The scenes' needs, at one clock ----------

class SceneNeeds:
    """Mixed into one TestCase per clock year."""

    CLOCK: datetime

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory()
        root = Path(cls.temporary.name)
        cls.demo = make_demo_folder(root, cls.CLOCK)
        cls.demo_report = marketing_folder.Report()
        cls.demo_left = demo_folders.apply_demo_state(cls.demo, None, cls.demo_report, SPEC)
        cls.marketing, cls.marketing_report = make_marketing_folder(root, cls.CLOCK)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def school_year(self) -> int:
        return demo_folders.school_year_of(self.CLOCK.date())

    # courses scene, and the provisioning tests' lists
    def test_courses_and_sections_are_the_specs(self):
        for kind, folder, courses in [("demo", self.demo, demo_folders.demo_courses(SPEC)),
                                      ("marketing", self.marketing, demo_folders.marketing_courses(SPEC))]:
            for course in courses:
                config = demo_folders.read_config(folder / "courses" / course["code"])
                self.assertIsNotNone(config, f"{kind}: {course['code']} should be made")
                for section in course["sections"]:
                    self.assertTrue((folder / "courses" / course["code"] / f"section{section}" / "index.md").is_file(),
                                    f"{kind}: {course['code']} section {section} should have a front page")

    # new-course scene
    def test_the_new_course_is_ready_made_and_not_in_the_folder(self):
        offered = SPEC["marketing"]["scenes"]["newCourse"]["code"]
        self.assertTrue((PAYLOADS / offered / "manifest.json").is_file(), f"{offered} should have ready-made content")
        self.assertFalse((self.marketing / "courses" / offered).exists(), f"{offered} should not be in the folder")

    # reference scene
    def test_the_page_to_borrow_is_in_one_course_and_not_the_other(self):
        title = SPEC["marketing"]["scenes"]["pageToBorrow"]
        codes = [course["code"] for course in demo_folders.marketing_courses(SPEC)]
        curriculum_course = SPEC["marketing"]["curriculumCourse"]
        for code in codes:
            found = find_page(self.marketing / "courses" / code, title)
            if code == curriculum_course:
                self.assertIsNotNone(found, f"{title} should be in {code}")
            else:
                self.assertIsNone(found, f"{title} should not be in {code}, or Copy a Page has nothing to copy")

    # reference scene and Keep a Copy: the year is READ from the copy
    def test_the_reference_year_is_read_from_the_copy(self):
        self.assertEqual(demo_folders.reference_school_year(self.marketing, self.CLOCK.date(), SPEC),
                         self.school_year() - 1, "a folder without a copy files a new one under last year")
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            copy = folder / "courses" / "ICS3U-2025"
            copy.mkdir(parents=True)
            (copy / "course_config.json").write_text(json.dumps({
                "course_code": SPEC["marketing"]["referenceCopy"]["of"],
                "kept_for_reference": True, "reference_school_year": 2025}), encoding="utf-8")
            self.assertEqual(demo_folders.reference_school_year(folder, self.CLOCK.date(), SPEC), 2025,
                             "a kept copy stays filed where it was filed, whatever the clock says")
        self.assertEqual(demo_folders.year_title(2025), "2025–26")
        self.assertEqual(demo_folders.year_title(2099), "2099–00")

    # start-of-year scene
    def test_section_two_starts_in_the_week_of_february_1(self):
        course_dir = self.marketing / "courses" / SPEC["marketing"]["curriculumCourse"]
        section = SPEC["marketing"]["secondSemester"]["section"]
        second = demo_folders.class_pages(course_dir, section)
        first = demo_folders.class_pages(course_dir, 1)
        self.assertTrue(second and first)
        starts = demo_folders.day_in_school_year(self.school_year(), SPEC["marketing"]["secondSemester"]["startsInTheWeekOf"])
        week = starts - timedelta(days=starts.weekday())
        self.assertGreaterEqual(second[0].day, week, f"section {section} should start in the week of {starts}")
        self.assertLess(second[0].day, week + timedelta(days=7), f"section {section} should start in the week of {starts}")
        self.assertGreater(second[0].day, first[-1].day, "section 2 should start after section 1's last class")

    # both-curricula and two-maps scenes
    def test_one_curriculum_block_embeds_both_curricula(self):
        both = SPEC["marketing"]["scenes"]["bothCurricula"]
        page = find_page(self.marketing / "courses" / SPEC["marketing"]["curriculumCourse"], both["page"])
        self.assertIsNotNone(page)
        block = curriculum_block(page.read_text(encoding="utf-8"))
        self.assertIn(f"![[{both['ontario']}]]", block)
        self.assertIn(f"![[{both['collegeBoard']}]]", block)

    # how-i-teach scene
    def test_how_i_teach_is_in_the_curriculum_course(self):
        course_dir = self.marketing / "courses" / SPEC["marketing"]["curriculumCourse"]
        self.assertTrue((course_dir / marketing_folder.HOW_I_TEACH_NAME).is_file())

    # curriculum-settings scene: the folder is there and hidden, and the
    # declaration is left for the scene to make through Course Settings
    def test_the_college_board_folder_is_there_hidden_and_declared_only_where_the_spec_says(self):
        name = SPEC["marketing"]["collegeBoardPages"]["folder"]
        for course in demo_folders.marketing_courses(SPEC):
            course_dir = self.marketing / "courses" / course["code"]
            config = demo_folders.read_config(course_dir) or {}
            self.assertTrue((course_dir / name).is_dir(), f"{course['code']} should hold {name}")
            self.assertIn(name, config.get("hidden", []))
            declared = name in (config.get("curriculum_folders") or [])
            self.assertEqual(declared, course["declaresCollegeBoardHere"],
                             f"{course['code']}: declared {declared}, folders.json says {course['declaresCollegeBoardHere']}")

    def test_every_course_deploys_to_a_folder_inside_the_kept_folder(self):
        for course in demo_folders.marketing_courses(SPEC):
            config = demo_folders.read_config(self.marketing / "courses" / course["code"]) or {}
            self.assertEqual(config.get("deploy_target"), "local_folder")
            self.assertEqual(config.get("deploy_folder_path"), str(self.marketing / course["publishTo"]))

    def test_a_second_run_of_the_file_steps_changes_nothing(self):
        self.assertEqual(self.marketing_report.named_and_skipped, [], self.marketing_report.named_and_skipped)
        again = marketing_folder.apply_file_steps(self.marketing, stand_in_college_board_pages())
        self.assertEqual(again.made, 0, again.lines)

    # the hero and the colour figures
    def test_every_demo_section_wears_its_colour(self):
        self.assertEqual(demo_folders.colour_problems(self.demo, SPEC), [])
        again = marketing_folder.Report()
        demo_folders.apply_colours(self.demo, again, SPEC)
        self.assertEqual(again.made, 0, "a second run changes nothing")

    def test_the_demo_folder_names_its_sites_and_its_teacher(self):
        for course in demo_folders.demo_courses(SPEC):
            marker = json.loads((self.demo / "courses" / course["code"] / ".netlify_sites" / "section1.json")
                                .read_text(encoding="utf-8"))
            self.assertEqual(marker["name"], course["site"])
        profile = json.loads((self.demo / "courses" / ".internal" / "profile.json").read_text(encoding="utf-8"))
        self.assertEqual(profile["teacher_last_name"], SPEC["teacherLastName"])

    # the hero and the class sites: what the app is asked to do
    def test_each_front_page_is_asked_for_the_latest_class_on_or_before_january_15(self):
        limit = demo_folders.day_in_school_year(self.school_year(), SPEC["demo"]["frontPage"]["latestClassOnOrBefore"])
        for course in demo_folders.demo_courses(SPEC):
            course_dir = self.demo / "courses" / course["code"]
            for section in course["sections"]:
                plan = demo_folders.front_page_plan(course_dir, section, SPEC)
                label = f"{course['code']} section {section}"
                self.assertIsNotNone(plan.shown, f"{label} has no class on or before {limit}")
                self.assertLessEqual(plan.shown.day, limit, label)
                self.assertGreater(plan.shown.day, limit - timedelta(days=7), f"{label}: not the LATEST class before {limit}")
                self.assertTrue(plan.after, f"{label} should have classes after {limit} to hold back")
                self.assertGreater(plan.after[0].day, limit, label)
                requests = demo_folders.door_requests(plan)
                unpublish = [arguments for tool, arguments in requests if tool == "unpublish_pages"]
                self.assertEqual(unpublish, [{"course": course["code"], "section": section,
                                              "onOrAfter": plan.after[0].day.isoformat()}],
                                 f"{label}: every class after {plan.shown.title} is to be unpublished, from the next one on")
                self.assertTrue(any(page.published for page in plan.after),
                                f"{label}: the payload holds nothing back after {limit}, so the request is not exercised")

    def test_without_the_app_the_front_pages_are_named_as_left(self):
        self.assertTrue(self.demo_left, "the front pages need the app; a run without it must say so")
        for line in self.demo_left:
            self.assertIn("needs the app", line)

    @unittest.skipUnless(os.environ.get("PLANTOIR_DEMO_FOLDERS_APP"),
                         "the front pages are set THROUGH THE APP: set PLANTOIR_DEMO_FOLDERS_APP to a built "
                         "Plantoir.app/Contents/MacOS/Plantoir to run them")
    def test_the_app_puts_each_front_page_where_the_spec_says(self):
        app = Path(os.environ["PLANTOIR_DEMO_FOLDERS_APP"])
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary) / "Teaching"
            shutil.copytree(self.demo, folder)
            state = Path(temporary) / "state"
            state.mkdir()
            door = demo_folders.mac_server(app, folder, state)
            report = marketing_folder.Report()
            left = demo_folders.apply_demo_state(folder, door, report, SPEC)
            self.assertEqual(left, [])
            self.assertEqual(demo_folders.demo_state_problems(folder, SPEC), [])
            again = marketing_folder.Report()
            self.assertEqual(demo_folders.apply_demo_state(folder, door, again, SPEC), [])
            self.assertEqual(again.made, 0, again.lines)

    @unittest.skip("the College Board pages' WORDS are not in this repository (folders.json → "
                   "marketing.collegeBoardPages: hand-copied by Russell; ruling Q3, #445). This test "
                   "uses a stand-in page per code; test_marketing_folder.test_extraction reads the real "
                   "document when it is on this Mac")
    def test_the_college_board_pages_words(self):
        pass


class AtSeptember2026(SceneNeeds, unittest.TestCase):
    CLOCK = datetime(2026, 9, 27, 7, 0).astimezone()


class AtSeptember2027(SceneNeeds, unittest.TestCase):
    # 2028-01-15 is a Saturday: no class is dated on it.
    CLOCK = datetime(2027, 9, 27, 7, 0).astimezone()


# ---------- One home for the courses ----------

class OneHome(unittest.TestCase):
    """folders.json is the one place the courses, sections, sites and the
    reference year are written; these catch a copy creeping back."""

    def test_the_ui_tests_write_no_school_year(self):
        code = []
        for line in UI_TESTS.read_text(encoding="utf-8").split("\n"):
            if line.strip().startswith("//"):
                continue
            code.append(line)
        years = re.findall(r'"[^"\n]*\b20\d\d–\d\d\b[^"\n]*"', "\n".join(code))
        self.assertEqual(years, [], "a school year is read from the folder, never written in the tests")

    def test_the_ui_tests_list_no_courses_of_their_own(self):
        text = UI_TESTS.read_text(encoding="utf-8")
        self.assertIn("MarketingFolderSpec", text)
        for course in demo_folders.demo_courses(SPEC) + demo_folders.marketing_courses(SPEC):
            self.assertNotIn(f'("{course["code"]}", "', text, f"{course['code']}'s sections belong in folders.json")

    def test_the_site_names_are_written_only_in_folders_json(self):
        for course in demo_folders.demo_courses(SPEC):
            for script in sorted(HERE.glob("*.py")):
                if script.name == Path(__file__).name:
                    continue
                self.assertNotIn(course["site"], script.read_text(encoding="utf-8"),
                                 f"{script.name} names {course['site']}; read it from folders.json")

    def test_no_fixed_second_semester(self):
        source = (HERE / "marketing_folder.py").read_text(encoding="utf-8")
        self.assertIsNone(re.search(r"SECOND_SEMESTER_STARTS\s*=\s*date\(", source))

    def test_the_windows_capturer_lists_no_courses_of_its_own(self):
        # #459: app_scenes_windows.py once carried "ENG2D:1, 2;MCV4U:1, 2;…"
        # (sections folders.json does not have) and a fixed "ICS3U:2025".
        source = (HERE / "app_scenes_windows.py").read_text(encoding="utf-8")
        for name in ("DEMO_COURSES", "MARKETING_COURSES", "MARKETING_REFERENCE"):
            self.assertNotIn(name, source, f"{name} belongs in folders.json")
        for course in demo_folders.demo_courses(SPEC) + demo_folders.marketing_courses(SPEC):
            literal = re.search(r'"[^"\n]*\b' + course["code"] + r'\s*:[^"\n]*"', source)
            self.assertIsNone(literal, f"app_scenes_windows.py writes {course['code']}'s sections or year: "
                                       f"{literal.group(0) if literal else ''}")


# ---------- What Windows' provision scene is given (#459) ----------

class TheWindowsProvisionArguments(unittest.TestCase):
    """The strings `Plantoir.exe --stage-scene provision` takes, built from
    folders.json (MarketingScene.CourseList / ReferenceCopyOf parse them)."""

    @staticmethod
    def parse_courses(text: str) -> list[tuple[str, list[int]]]:
        # MarketingScene.CourseList: `;` between courses, `CODE:sections`.
        parsed: list[tuple[str, list[int]]] = []
        for entry in text.split(";"):
            code, sections = entry.split(":", 1)
            numbers: list[int] = []
            for part in sections.split(","):
                numbers.append(int(part.strip()))
            parsed.append((code.strip(), numbers))
        return parsed

    def test_the_provision_argument_is_the_specs(self):
        for courses in (demo_folders.demo_courses(SPEC), demo_folders.marketing_courses(SPEC)):
            expected: list[tuple[str, list[int]]] = []
            for course in courses:
                expected.append((course["code"], list(course["sections"])))
            self.assertEqual(self.parse_courses(demo_folders.provision_courses_argument(courses)), expected)
        self.assertEqual(demo_folders.provision_courses_argument(
            [{"code": "ENG2D", "sections": [1, 2]}, {"code": "MCV4U", "sections": [1]}]), "ENG2D:1, 2;MCV4U:1")

    def test_a_new_reference_copy_is_filed_the_year_before_the_clock(self):
        of = SPEC["marketing"]["referenceCopy"]["of"]
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.assertEqual(demo_folders.reference_copy_argument(folder, date(2026, 9, 15), SPEC), f"{of}:2025")
            self.assertEqual(demo_folders.reference_copy_argument(folder, date(2026, 10, 8), SPEC), f"{of}:2025")
            self.assertEqual(demo_folders.reference_copy_argument(folder, date(2027, 9, 15), SPEC), f"{of}:2026")

    def test_a_kept_copys_own_year_wins_at_any_clock(self):
        of = SPEC["marketing"]["referenceCopy"]["of"]
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            copy = folder / "courses" / f"{of}-2025"
            copy.mkdir(parents=True)
            (copy / "course_config.json").write_text(json.dumps(
                {"course_code": of, "kept_for_reference": True, "reference_school_year": 2025}), encoding="utf-8")
            for today in (date(2026, 9, 15), date(2027, 9, 15), date(2030, 1, 4)):
                self.assertEqual(demo_folders.reference_copy_argument(folder, today, SPEC), f"{of}:2025")


def _windows_scenes():
    """app_scenes_windows, when this machine can import it (Windows, with
    Pillow, which capture_windows.py needs anyway); None elsewhere."""
    if sys.platform != "win32":
        return None
    try:
        import app_scenes_windows
    except ImportError:
        return None
    return app_scenes_windows


@unittest.skipUnless(_windows_scenes(), "app_scenes_windows.py imports Windows' own modules")
class TheWindowsCapturersFolders(unittest.TestCase):
    """How the Windows capturer judges and prepares its folders, against
    temporary stand-ins for ~/Teaching, ~/School Web Space and
    ~/Desktop/Teaching. No app is run."""

    def setUp(self) -> None:
        self.scenes = _windows_scenes()
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.saved = {name: getattr(self.scenes, name) for name in ("DEMO", "MARKETING", "SHOWN", "COURSES_SET_ASIDE")}
        self.scenes.DEMO = root / "Teaching"
        self.scenes.MARKETING = root / "School Web Space"
        self.scenes.SHOWN = root / "Desktop" / "Teaching"
        self.scenes.COURSES_SET_ASIDE = self.scenes.SHOWN / ".courses set aside for the pictures"

    def tearDown(self) -> None:
        for name, value in self.saved.items():
            setattr(self.scenes, name, value)
        self.tmp.cleanup()

    @staticmethod
    def course(folder: Path, code: str, config: dict) -> Path:
        course_dir = folder / "courses" / code
        course_dir.mkdir(parents=True, exist_ok=True)
        (course_dir / "course_config.json").write_text(json.dumps(config), encoding="utf-8")
        return course_dir

    def make_demo(self, sections_of=lambda course: course["sections"]) -> None:
        demo = self.scenes.DEMO
        demo.mkdir(parents=True)
        (demo / "preview.ps1").write_text("#" * 4000, encoding="utf-8")
        for course in demo_folders.demo_courses(SPEC):
            self.course(demo, course["code"], {"course_code": course["code"], "section_numbers": sections_of(course)})

    def test_a_demo_folder_with_the_specs_sections_is_whole(self):
        self.make_demo()
        self.assertTrue(self.scenes.demo_is_whole())

    def test_a_demo_folder_with_other_sections_is_made_again(self):
        # The folder the old constants made: every course with sections 1 and 2.
        self.make_demo(lambda course: [1, 2])
        self.assertNotEqual([c["sections"] for c in demo_folders.demo_courses(SPEC)],
                            [[1, 2]] * len(demo_folders.demo_courses(SPEC)),
                            "folders.json gives every demo course two sections; this test proves nothing")
        self.assertFalse(self.scenes.demo_is_whole())

    def test_a_kept_destination_is_left_alone_and_nothing_is_made_beside_it(self):
        marketing = self.scenes.MARKETING
        kept: dict[str, Path] = {}
        for course in demo_folders.marketing_courses(SPEC):
            kept[course["code"]] = marketing / "Websites" / course["code"]
            self.course(marketing, course["code"], {"course_code": course["code"], "deploy_target": "local_folder",
                                                     "deploy_folder_path": str(kept[course["code"]])})
        import marketing_folder
        self.scenes.give_marketing_courses_their_destinations(marketing_folder.Report())
        for course in demo_folders.marketing_courses(SPEC):
            config = demo_folders.read_config(marketing / "courses" / course["code"])
            self.assertEqual(config["deploy_folder_path"], str(kept[course["code"]]))
            self.assertFalse((marketing / course["publishTo"]).exists(),
                             f"{course['publishTo']} was made inside a folder that deploys elsewhere")
        self.assertEqual(sorted(self.scenes.publish_folders(marketing)), sorted(kept.values()))

    def test_a_fresh_course_is_given_folders_jsons_destination(self):
        marketing = self.scenes.MARKETING
        for course in demo_folders.marketing_courses(SPEC):
            self.course(marketing, course["code"], {"course_code": course["code"], "deploy_target": "netlify"})
        import marketing_folder
        self.scenes.give_marketing_courses_their_destinations(marketing_folder.Report())
        expected: list[Path] = []
        for course in demo_folders.marketing_courses(SPEC):
            expected.append(marketing / course["publishTo"])
            self.assertTrue((marketing / course["publishTo"]).is_dir())
        self.assertEqual(sorted(self.scenes.publish_folders(marketing)), sorted(expected))

    def test_the_shown_folder_gets_the_destinations_and_loses_only_what_it_was_given(self):
        marketing, shown = self.scenes.MARKETING, self.scenes.SHOWN
        self.course(marketing, "ICS3U", {"deploy_target": "local_folder",
                                         "deploy_folder_path": str(marketing / "Websites")})
        self.course(marketing, "ICS4U", {"deploy_target": "local_folder",
                                         "deploy_folder_path": str(marketing / "Websites" / "ICS4U")})
        theirs = shown / "Notes"
        theirs.mkdir(parents=True)
        self.course(shown, "THEIRS", {"deploy_target": "local_folder", "deploy_folder_path": str(theirs)})
        with self.scenes.ShownAsTeaching(marketing):
            self.assertTrue((shown / "Websites" / "ICS4U").is_dir())
        self.assertFalse((shown / "Websites").exists())
        self.assertTrue(theirs.is_dir())
        self.assertTrue((shown / "courses" / "THEIRS").is_dir())
        self.assertEqual(json.loads((marketing / "courses" / "ICS4U" / "course_config.json")
                                    .read_text(encoding="utf-8"))["deploy_folder_path"],
                         str(marketing / "Websites" / "ICS4U"))


# ---------- The door's own behaviour, with a stand-in server ----------

class TheDoor(unittest.TestCase):
    """ask_the_app stops a server that goes quiet, says what it said on
    stderr, and sends every section's requests through ONE process."""

    def server(self, body: str) -> list[str]:
        script = Path(self.temporary.name) / "server.py"
        script.write_text(body, encoding="utf-8")
        return [sys.executable, str(script)]

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_a_quiet_server_is_stopped_and_its_stderr_is_shown(self):
        quiet = self.server("import sys, time\nsys.stderr.write('building the site\\n'); sys.stderr.flush()\n"
                            "time.sleep(60)\n")
        started = datetime.now()
        with self.assertRaises(demo_folders.DoorRefused) as raised:
            demo_folders.ask_the_app(quiet, [("unpublish_pages", {})], timeout_seconds=2)
        self.assertLess((datetime.now() - started).total_seconds(), 30)
        self.assertIn("building the site", str(raised.exception))

    def test_every_request_goes_through_one_process_with_the_extra_arguments(self):
        log = Path(self.temporary.name) / "calls.jsonl"
        echo = self.server(
            "import json, os, sys\n"
            f"log = open({str(log)!r}, 'a')\n"
            "for line in sys.stdin:\n"
            "    message = json.loads(line)\n"
            "    if 'id' not in message: continue\n"
            "    log.write(json.dumps({'pid': os.getpid(), 'message': message}) + '\\n'); log.flush()\n"
            "    print(json.dumps({'jsonrpc': '2.0', 'id': message['id'], 'result': {'content': [{'type': 'text', 'text': 'ok'}]}}), flush=True)\n")
        with tempfile.TemporaryDirectory() as temporary:
            folder = make_demo_folder(Path(temporary), AtSeptember2026.CLOCK)
            demo_folders.apply_demo_state(folder, echo, marketing_folder.Report(), SPEC, extra_arguments={"preview": False})
        calls = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()]
        processes = {call["pid"] for call in calls}
        tools = [call["message"] for call in calls if call["message"].get("method") == "tools/call"]
        self.assertEqual(len(processes), 1, "one server for every section, so each course is backed up once")
        sections = sum(len(course["sections"]) for course in demo_folders.demo_courses(SPEC))
        self.assertEqual(len(tools), sections)
        for call in tools:
            self.assertIs(call["params"]["arguments"]["preview"], False)


# ---------- The kept folders, opt-in ----------

@unittest.skipUnless(os.environ.get("PLANTOIR_DEMO_FOLDERS_COMPARE") == "1",
                     "the comparison with the KEPT folders reads Russell's own folders: opt-in only, "
                     "PLANTOIR_DEMO_FOLDERS_COMPARE=1, never in verify.sh")
class KeptFolders(unittest.TestCase):
    """Every rule holds on the kept folders as they are: nothing this piece
    adds would change either of them. Read-only — the marketing folder is
    COPIED (source pages only) before its file steps run."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.kept = demo_folders.find_kept_folders()

    def test_the_demo_folder_already_matches(self):
        folder = self.kept.get("demo")
        if folder is None:
            self.skipTest("no kept demo folder on this Mac")
        self.assertEqual(demo_folders.demo_state_problems(folder, SPEC), [])

    def test_the_marketing_folders_file_steps_are_already_there(self):
        folder = self.kept.get("marketing")
        if folder is None:
            self.skipTest("no kept marketing folder on this Mac")
        with tempfile.TemporaryDirectory() as temporary:
            copy = Path(temporary) / "Plantoir Marketing"
            demo_folders.copy_sources(folder, copy)
            # The scenes rewrite each destination to the path the pictures show
            # (~/Desktop/Teaching/...); point the copy's at itself.
            for course in demo_folders.marketing_courses(SPEC):
                config_path = copy / "courses" / course["code"] / "course_config.json"
                config = json.loads(config_path.read_text(encoding="utf-8"))
                config["deploy_folder_path"] = str(copy / course["publishTo"])
                config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
            name = SPEC["marketing"]["collegeBoardPages"]["folder"]
            pages: dict[str, str] = {}
            for page in sorted((copy / "courses" / SPEC["marketing"]["curriculumCourse"] / name).glob("*.md")):
                pages[page.stem] = page.read_text(encoding="utf-8")
            report = marketing_folder.apply_file_steps(copy, pages)
            self.assertEqual(report.made, 0, report.lines)
            self.assertEqual(report.left_as_changed, 0, report.lines)
            copies = demo_folders.reference_copies(copy, SPEC["marketing"]["referenceCopy"]["of"])
            self.assertTrue(copies, "the kept folder has a reference copy")
            kept_year = demo_folders.read_config(copies[0])["reference_school_year"]
            self.assertEqual(demo_folders.reference_school_year(copy, date(2027, 9, 27), SPEC), kept_year)


if __name__ == "__main__":
    unittest.main(verbosity=2)

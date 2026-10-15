"""What the print pictures are taken of, shared by both capture harnesses.

The `print-page` and `print-handout` shots (shots.json, scene `print-set`)
photograph a PREVIEW of the MPM2D example course, built in a working folder of
their own: the published demo sites carry no printable page, and a preview is
what a teacher presses Print on. capture.py makes that folder on the Mac
(`--print-set`) and capture_windows.py on Windows (`--print-set`); both write
the course from this one configuration, answered the way each app's New Course
panel answers setup's questions, so nothing in the folder is hand-made and the
two platforms photograph the same course.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent

PRINT_COURSE_CONFIG = {
    "class_folder": "All Classes",
    "color_schemes": {"section1": "quartz-standard"},
    "course_code": "MPM2D",
    "course_name": "Principles of Mathematics, Grade 10, Academic",
    "custom_short_name": "",
    "deploy_folder_path": "",
    "deploy_target": "netlify",
    "emojis": {"sections": {"section1": "📐"}},
    "expandOnFolderClick": False,
    "fonts": {
        "default": {"body": "Helvetica, Arial", "code": "IBM Plex Mono", "header": "Helvetica, Arial"},
        "sections": {"section1": {"body": "Helvetica, Arial", "code": "IBM Plex Mono", "header": "Helvetica, Arial"}},
    },
    "footer_html": "",
    "include_coverage_notes": False,
    "include_curriculum_coverage": True,
    "include_curriculum_pages": True,
    "locale": "en-CA",
    "num_sections": 1,
    "prepopulate_example_content": True,
    "section_numbers": [1],
    "show_grade_in_title": {"sections": {"section1": False}},
    "show_reading_time": True,
    "show_section_marker": {"sections": {"section1": True}},
    "unit_word": "Unit",
    "use_lcs_terminology": False,
    "use_skeleton": False,
}

PRINT_CODE = PRINT_COURSE_CONFIG["course_code"]


def course_config() -> dict:
    """The course_config.json setup is handed: the settings above plus the
    payload's own structure (its manifest is the course's ENTIRE structure)."""
    manifest = json.loads((REPO / "support" / "example_content" / PRINT_CODE / "manifest.json")
                          .read_text(encoding="utf-8"))
    config = dict(PRINT_COURSE_CONFIG)
    for key in ("shared_folders", "shared_files", "per_section_folders", "per_section_files", "hidden", "expandable"):
        config[key] = manifest[key]
    return config


def write_course_config(course: Path) -> None:
    course.mkdir(parents=True, exist_ok=True)
    (course / "course_config.json").write_text(json.dumps(course_config(), indent=2, ensure_ascii=False) + "\n",
                                               encoding="utf-8")

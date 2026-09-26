#!/usr/bin/env python3
"""The v1.4.0 scenes: what each picture needs set up, and how it is checked.

Every image a v1.4.0 section of plantoir.app shows is made by ONE scene here,
in the kept marketing folder (``~/Plantoir Marketing``, ``marketing_folder.py``),
so a plain ``capture.py --scenes`` regenerates all of them from a clean state at
any later release, and ``capture.py --only <scene>`` re-takes one.

A scene is either a UI test (``MarketingScenes`` in
``mac-app/Tests/QuartzTeachersUITests/MarketingScreenshotTests.swift``, which
sets the app's state and photographs it) or a step run from here (the
notification banner, Obsidian). Each lists:

- the identifiers it drives in the app, so ``--dry-run`` can say, without
  launching anything, whether this tree's app has them yet — and which issue
  brings the ones it does not;
- the contract wording it reads (never retyped: CLAUDE.md, "name it instead");
- the words its finished picture must show (``shots.json -> expectText``),
  read back with Vision (``ocr.swift``). That is the check that catches "the
  right window, the wrong state", which is what every failure in the
  marketing-screenshots skill's list was, and which no exit code reports.

Standard library only (the image steps use Pillow through composite.py).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
WEBSITE = REPO / "website"
APP_SOURCE = REPO / "mac-app" / "QuartzTeachers"
UI_TESTS = REPO / "mac-app" / "Tests" / "QuartzTeachersUITests" / "MarketingScreenshotTests.swift"
CONTRACTS = REPO / "contracts"
OCR_HELPER = HERE / "ocr.swift"
WINDOW_HELPER = HERE / "windowid.swift"

SCENE_CLASS = "QuartzTeachersUITests/MarketingScenes"
PROVISIONING_CLASS = "QuartzTeachersUITests/MarketingFolderProvisioning"


@dataclass
class Scene:
    name: str
    produces: list[str]
    kind: str                                   # "ui-test", "notification" or "obsidian"
    test: str | None = None
    identifiers: list[str] = field(default_factory=list)
    # Identifiers another piece of work brings, with the issue that does.
    identifiers_pending: dict[str, str] = field(default_factory=dict)
    wording: list[tuple[str, str]] = field(default_factory=list)   # (contract file, dotted path)
    what_it_sets_up: str = ""


SCENES: list[Scene] = [
    Scene(
        name="courses", produces=["courses"], kind="ui-test", test="testCourses",
        identifiers=["courseNameField", "referenceYear-"],
        what_it_sets_up="ICS3U selected (its settings form), ICS4U beside it, and last year's ICS3U "
                        "unfolded under Reference Courses, 2025–26.",
    ),
    Scene(
        name="new-course", produces=["new-course"], kind="ui-test", test="testNewCourse",
        identifiers=["addCourseButton", "wizardCourseCodeField", "wizardSectionNumbersField", "wizardCloseButton"],
        what_it_sets_up="The New Course panel for TEJ3M (a ready-made code not in the folder), sections 1, 2; "
                        "cancelled, so nothing is made.",
    ),
    Scene(
        name="schedule-sheet", produces=["schedule-sheet"], kind="ui-test", test="testScheduleSheet",
        identifiers=["scheduleDeploy-", "scheduleDeployTitle", "scheduleDeployPlan", "scheduleDeployCancelButton"],
        what_it_sets_up="ICS3U section 1 → Schedule Deploy…, the plan line showing; cancelled, so nothing is "
                        "scheduled by the UI test (the real schedule is the notification-banner scene's).",
    ),
    Scene(
        name="notification-banner", produces=["notification-banner"], kind="notification",
        wording=[("shared-rules.json", "scheduledPublishStopped.sentences.succeeded")],
        what_it_sets_up="A REAL scheduled publish of ICS3U section 1 to the kept folder's School Web Space, "
                        "asked for through `Plantoir --mcp-stdio` (outside the UI-test isolation, which "
                        "would hide the run's record); the banner is photographed the moment it appears.",
    ),
    Scene(
        name="reference", produces=["reference"], kind="ui-test", test="testReferenceAndCopyAPage",
        identifiers=["referenceYear-", "copyAPage-", "copyPageDestinationCourse", "copyPageChecklist",
                     "copyPageRefusal"],
        what_it_sets_up="Reference Courses › 2025–26 unfolded; Copy a Page from the reference ICS3U, "
                        "\"The Unplugged Algorithm\" into ICS4U, with its linked pages listed; cancelled.",
    ),
    Scene(
        name="start-of-year", produces=["start-of-year"], kind="ui-test", test="testGetReadyForTheStartOfTheYear",
        identifiers_pending={"startOfYear-": "#96", "startOfYearSheet": "#96", "startOfYearGo": "#96"},
        what_it_sets_up="ICS3U section 2 → Get Ready for the Start of the Year…, the plan listed with its "
                        "reasons; cancelled, so nothing is put into draft.",
    ),
    Scene(
        name="curriculum-settings", produces=["curriculum-settings"], kind="ui-test",
        test="testDeclareSecondCurriculum",
        identifiers=["courseNameField"],
        identifiers_pending={"curriculumFolderToggle-": "#128"},
        what_it_sets_up="ICS3U's Course Settings with College Board Curriculum ticked beside Curriculum, and "
                        "saved — the declaration every later build needs, made through the app on purpose.",
    ),
    Scene(
        name="two-maps", produces=["map-ontario", "map-college-board"], kind="ui-test",
        test="testTwoMapsAndBothCurricula",
        identifiers=["previewButton", "stopPreviewButton"],
        what_it_sets_up="ICS3U section 1 previewed in the app; each coverage map opened through the site's "
                        "own search, after the preview's console has named BOTH maps.",
    ),
    Scene(
        name="both-curricula", produces=["both-curricula"], kind="ui-test",
        test="testTwoMapsAndBothCurricula",
        identifiers=["previewButton"],
        what_it_sets_up="The same preview, on The Unplugged Algorithm, scrolled to its curriculum "
                        "connection: an Ontario expectation and an AP learning objective together.",
    ),
    Scene(
        name="how-i-teach", produces=["how-i-teach"], kind="obsidian",
        what_it_sets_up="Obsidian open on ICS3U/How I Teach.md; Obsidian's list of vaults backed up first "
                        "and put back after, then compared.",
    ),
    Scene(
        name="club", produces=["club"], kind="ui-test", test="testClubWizard",
        identifiers=["addCourseButton", "wizardCourseCodeField", "clubToggle", "clubFrontPageHeadingField",
                     "wizardCloseButton"],
        what_it_sets_up="The New Course panel for CODING with \"This is a club\" ticked; cancelled.",
    ),
]

# Assembled from parts after both appearances have been photographed.
COMPOSITES: dict[str, dict] = {
    "schedule": {"of": ["schedule-sheet", "notification-banner"], "arrange": "banner"},
    "two-maps": {"of": ["map-ontario", "map-college-board"], "arrange": "pair"},
}


def scene_named(name: str) -> Scene | None:
    for scene in SCENES:
        if scene.name == name:
            return scene
    return None


def scenes_for(names: list[str]) -> list[Scene]:
    """The scenes to run for `--only a,b`, accepting a composite's name for its parts."""
    chosen: list[Scene] = []
    for name in names:
        if name in COMPOSITES:
            for part in COMPOSITES[name]["of"]:
                for scene in SCENES:
                    if part in scene.produces and scene not in chosen:
                        chosen.append(scene)
            continue
        scene = scene_named(name)
        if scene is None:
            raise SystemExit(f"No scene is called {name!r}. The scenes are: "
                             + ", ".join(scene.name for scene in SCENES))
        if scene not in chosen:
            chosen.append(scene)
    return chosen


# ---------- What a picture must say ----------

def load_shots() -> dict:
    return json.loads((WEBSITE / "shots.json").read_text(encoding="utf-8"))


def expected_text(image_name: str, shots: dict | None = None) -> list[str]:
    """The words the picture named `image_name` (a shot id or a part) must show."""
    shots = shots or load_shots()
    for shot in shots["shots"]:
        if shot["id"] == image_name:
            if "retake" in shot:
                return list(shot["retake"].get("expectText", []))
            return list(shot.get("expectText", []))
        for part_name, part in shot.get("parts", {}).items():
            if part_name == image_name:
                return list(part.get("expectText", []))
    return []


def recognised_text(image: Path) -> str:
    result = subprocess.run(["swift", str(OCR_HELPER), str(image)], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"text recognition failed on {image.name}: {result.stderr.strip()}")
    return result.stdout


def missing_words(image: Path, expected: list[str]) -> list[str]:
    """Which of the expected words Vision did NOT find on the image.

    Compared without case and without spaces, since Vision splits and joins
    words by how far apart they are drawn ("ICS3U Section 1" can come back as
    "ICS3U" and "Section 1" on one line or two).
    """
    seen = re.sub(r"\s+", "", recognised_text(image)).lower()
    missing: list[str] = []
    for word in expected:
        if re.sub(r"\s+", "", word).lower() not in seen:
            missing.append(word)
    return missing


# ---------- Contract wording ----------

def contract_value(file_name: str, dotted: str):
    data = json.loads((CONTRACTS / file_name).read_text(encoding="utf-8"))
    for key in dotted.split("."):
        if not isinstance(data, dict) or key not in data:
            return None
        data = data[key]
    return data


def fixed_parts(sentence: str) -> list[str]:
    """A contract sentence's words between its placeholders — what a picture
    of it will show whatever the placeholders become."""
    pieces: list[str] = []
    for piece in re.split(r"\{[a-zA-Z]+\}", sentence):
        piece = piece.strip(" .,")
        if len(piece) >= 6:
            pieces.append(piece)
    return pieces


# ---------- The app, read without running it ----------

def app_identifiers() -> set[str]:
    """Every accessibility identifier the app's views set, with an
    interpolated one recorded up to its first `\\(`."""
    found: set[str] = set()
    # Every string literal on the call's line, so a chosen identifier —
    # `isRunning ? "stopPreviewButton" : "previewButton"` — counts both ways.
    call = re.compile(r'accessibilityIdentifier\((.*)\)')
    literal = re.compile(r'"((?:[^"\\]|\\.)*)"')
    for path in APP_SOURCE.rglob("*.swift"):
        for match in call.finditer(path.read_text(encoding="utf-8", errors="replace")):
            for text in literal.findall(match.group(1)):
                found.add(text.split("\\(")[0])
    return found


def ui_test_methods() -> set[str]:
    text = UI_TESTS.read_text(encoding="utf-8")
    return set(re.findall(r"func (test\w+)\(\)", text))


# ---------- The dry run ----------

@dataclass
class DryRunLine:
    scene: str
    state: str          # "ready", "waits", "broken"
    detail: str


def dry_run(marketing_folder: Path, ced_pdf: Path | None) -> int:
    """Prove each scene's set-up is reachable, launching nothing.

    - The folder's FILE steps are run for real against the ICS3U payload laid
      out in a throwaway folder (never the kept one): College Board pages from
      the document when it is on this Mac, every correlation embed, How I
      Teach, the publish destination — and run twice, to prove the second run
      changes nothing.
    - Each scene's UI test exists, each identifier it drives is in this tree's
      app (or is named as waiting for the issue that brings it), and each piece
      of contract wording it reads resolves.
    - Text recognition works, on an image already on the site.

    Exit 0 when every scene is ready or waiting on a named issue; 1 when
    something is broken with no explanation.
    """
    sys.path.insert(0, str(HERE))
    import marketing_folder
    import college_board

    lines: list[DryRunLine] = []
    print("\n▶︎ Dry run: nothing is launched, and the kept folder is not touched")

    # 1. The folder's file steps, in a throwaway copy.
    with tempfile.TemporaryDirectory() as temporary:
        scratch = Path(temporary) / "Plantoir Marketing"
        marketing_folder.stage_from_payload(scratch, REPO / "support")
        pages: dict[str, str] | None = None
        if ced_pdf is not None:
            extraction = college_board.build_pages(
                ced_pdf, overrides=marketing_folder.DEFAULT_FOLDER / ".sources" / college_board.OVERRIDES_NAME)
            pages = dict(extraction.pages)
            for code, draft in extraction.needs_a_person.items():
                pages[code] = draft
            state = "ready" if not extraction.problems else "broken"
            detail = (f"{len(extraction.pages)} pages from the document, {len(extraction.needs_a_person)} "
                      f"drafted for a person ({', '.join(sorted(extraction.needs_a_person))}), "
                      f"{len(extraction.problems)} problem(s)")
            lines.append(DryRunLine("College Board pages", state, detail))
        else:
            lines.append(DryRunLine("College Board pages", "waits",
                                    "the Course and Exam Description is not on this Mac yet; --provision fetches it"))
        first = marketing_folder.apply_file_steps(scratch, pages)
        second = marketing_folder.apply_file_steps(scratch, pages)
        state = "ready" if second.made == 0 and not first.named_and_skipped else "broken"
        lines.append(DryRunLine("marketing folder file steps", state,
                                f"first run: {marketing_folder.summary(first)}; second run made {second.made}"))

    # 2. Each scene.
    methods = ui_test_methods()
    identifiers = app_identifiers()
    for scene in SCENES:
        problems: list[str] = []
        waits: list[str] = []
        if scene.test and scene.test not in methods:
            problems.append(f"no UI test {scene.test}")
        for identifier in scene.identifiers:
            if identifier not in identifiers:
                problems.append(f"the app has no '{identifier}'")
        for identifier, issue in scene.identifiers_pending.items():
            if identifier not in identifiers:
                waits.append(f"'{identifier}' arrives with {issue}")
        for file_name, dotted in scene.wording:
            if contract_value(file_name, dotted) is None:
                problems.append(f"contracts/{file_name} has no {dotted}")
        for image in scene.produces:
            if not expected_text(image):
                problems.append(f"shots.json lists no expectText for {image}")
        if problems:
            lines.append(DryRunLine(scene.name, "broken", "; ".join(problems)))
        elif waits:
            lines.append(DryRunLine(scene.name, "waits", "; ".join(waits)))
        else:
            lines.append(DryRunLine(scene.name, "ready", scene.what_it_sets_up))

    # 3. The read-back itself.
    sample = REPO / "site" / "img" / "courses-light.png"
    if sample.exists():
        try:
            missing = missing_words(sample, ["Courses & Clubs"])
            lines.append(DryRunLine("text recognition", "ready" if not missing else "broken",
                                    f"read {sample.name}" + (f"; missed {missing}" if missing else "")))
        except RuntimeError as error:
            lines.append(DryRunLine("text recognition", "broken", str(error)))

    symbols = {"ready": "✅", "waits": "🕓", "broken": "✗"}
    for line in lines:
        print(f"   {symbols[line.state]} {line.scene}: {line.detail}")
    broken = [line for line in lines if line.state == "broken"]
    print(f"\n   {len(lines) - len(broken)} of {len(lines)} ready or waiting on a named issue; "
          f"{len(broken)} broken.")
    return 1 if broken else 0


# ---------- The notification scene ----------

def folder_identifier(working_folder: Path) -> str:
    """`BuildOutputLocation.folderIdentifier`: the first 8 hex digits of the
    SHA-256 of the folder's canonical path and a newline — the path
    `/bin/pwd -P` prints, which is the one the launchers hash too."""
    import hashlib
    canonical = subprocess.run(["/bin/pwd", "-P"], cwd=working_folder, capture_output=True,
                               text=True, check=True).stdout.strip()
    return hashlib.sha256((canonical + "\n").encode("utf-8")).hexdigest()[:8]


def scheduled_record(working_folder: Path, course: str, section: int) -> Path:
    """Where a scheduled run of that section in that folder says how it went
    (`ScheduledPublishOutcome.recordURL`)."""
    return (Path.home() / "Library" / "Application Support" / "Plantoir" / "scheduled" / "stopped"
            / f"{course}-section{section}.{folder_identifier(working_folder)}.txt")


def banner_windows() -> dict[int, tuple[int, int, int, int]]:
    """Notification Center's on-screen windows, by number. The owner's name has
    been both spellings across macOS releases; both are asked."""
    found: dict[int, tuple[int, int, int, int]] = {}
    for owner in ("Notification Center", "NotificationCenter"):
        result = subprocess.run(["swift", str(WINDOW_HELPER), "--list", owner], capture_output=True, text=True)
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 5:
                found[int(parts[0])] = (int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]))
    return found


def ask_over_mcp(app_binary: Path, working_folder: Path, tool: str, arguments: dict) -> dict:
    """One tool call through the app's own MCP server, the way an outside
    assistant makes it. Newline-delimited JSON-RPC over stdio."""
    process = subprocess.Popen(
        [str(app_binary), "--mcp-stdio", str(working_folder)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    assert process.stdin is not None and process.stdout is not None

    def send(message: dict) -> None:
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()

    def answer(identifier: int) -> dict:
        deadline = time.time() + 60
        while time.time() < deadline:
            line = process.stdout.readline()
            if not line:
                break
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if message.get("id") == identifier:
                return message
        raise RuntimeError(f"the app's MCP server did not answer request {identifier}")

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                         "clientInfo": {"name": "plantoir-marketing-capture", "version": "1"}}})
        answer(1)
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": tool, "arguments": arguments}})
        return answer(2)
    finally:
        # Close stdin and wait: a stray server holds files open (CLAUDE.md,
        # "Leave no plantoir-mcp running" — the same courtesy on the mac).
        process.stdin.close()
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()


def capture_notification(app_binary: Path, working_folder: Path, destination: Path,
                         course: str = "ICS3U", section: int = 1, timeout_seconds: int = 360) -> list[str]:
    """Schedule a real publish, and photograph the banner that reports it.

    Returns the problems found; an empty list means the banner was captured
    AFTER the run's record said "succeeded". Why it is done this way and not
    inside a UI test: a UI-tested app reads scheduled records from a temporary
    folder (`BuildOutputLocation.isRunningTests`), so it can never see a real
    run's record — photographing a record written into that folder would be a
    picture of a publish that did not happen.
    """
    problems: list[str] = []
    record = scheduled_record(working_folder, course, section)
    if record.exists():
        record.unlink()
    when = (datetime.now() + timedelta(minutes=3)).replace(second=0, microsecond=0)
    reply = ask_over_mcp(app_binary, working_folder, "schedule_deploy",
                         {"course": course, "section": section, "when": when.strftime("%Y-%m-%d %H:%M")})
    if "error" in reply or reply.get("result", {}).get("isError"):
        return [f"the schedule was refused: {json.dumps(reply)[:400]}"]
    print(f"   Scheduled {course} section {section} for {when:%H:%M}; waiting for it to run…")

    before = set(banner_windows())
    deadline = time.time() + timeout_seconds
    captured = False
    record_seen_at: float | None = None
    while time.time() < deadline:
        if record_seen_at is None and record.exists():
            first_line = record.read_text(encoding="utf-8").split("\n")[0].strip()
            record_seen_at = time.time()
            if first_line != "succeeded":
                problems.append(f"the scheduled run did not succeed: its record says {first_line!r}")
                break
        for number, bounds in banner_windows().items():
            if number in before or bounds[2] < 200 or bounds[3] < 40:
                continue
            if record_seen_at is None:
                # A banner before the record is somebody else's notification.
                before.add(number)
                continue
            subprocess.run(["screencapture", "-x", "-o", "-l", str(number), str(destination)], check=True)
            captured = True
            break
        if captured:
            break
        time.sleep(0.1)
    if not captured and not problems:
        problems.append("no banner appeared after the run's record — are Plantoir's notifications allowed, "
                        "and is Focus off?")
    if captured:
        sentence = contract_value("shared-rules.json", "scheduledPublishStopped.sentences.succeeded") or ""
        wanted = [f"{course} Section {section}"] + fixed_parts(sentence)[:1]
        missing = missing_words(destination, wanted)
        if missing:
            problems.append(f"the banner does not say {missing} — another notification, or the wrong run")
    return problems


def cancel_leftover_schedule(app_binary: Path, working_folder: Path, course: str = "ICS3U", section: int = 1) -> None:
    """Cleanup the capture owes: a schedule it set that has not run yet."""
    try:
        ask_over_mcp(app_binary, working_folder, "cancel_scheduled_deploy",
                     {"course": course, "section": section})
    except RuntimeError:
        pass


# ---------- Obsidian's list of vaults, borrowed and put back ----------

OBSIDIAN_REGISTRY = Path.home() / "Library" / "Application Support" / "obsidian" / "obsidian.json"


class ObsidianRegistryKept:
    """Opening a note by path registers its folder as a vault. The registry is
    copied first and put back after, then compared (CLAUDE.md rule 9)."""

    def __enter__(self) -> "ObsidianRegistryKept":
        self.saved: bytes | None = OBSIDIAN_REGISTRY.read_bytes() if OBSIDIAN_REGISTRY.exists() else None
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> bool:
        if self.saved is not None:
            OBSIDIAN_REGISTRY.write_bytes(self.saved)
            if OBSIDIAN_REGISTRY.read_bytes() != self.saved:
                print("   ✗ Obsidian's list of vaults did not go back as it was.", file=sys.stderr)
            else:
                print("   Put Obsidian's list of vaults back as it was.")
        return False


def main() -> int:
    for scene in SCENES:
        print(f"{scene.name:22} {', '.join(scene.produces):32} {scene.what_it_sets_up}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

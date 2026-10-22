"""The Code and Quizzes pages' figures, photographed on Windows:
`capture_windows.py --code` / `--quizzes` (#590, #574).

The Windows twins of capture.py's `capture_code_set` and `capture_quiz_set`:
every `preview-page` shot whose `capture.scene` is `code` or `quizzes`, except
the two Swift ones (`NOT_ON_WINDOWS`: Swift stays read-only on Windows,
Russell's ruling on #570, so code-swift and code-swift-live stay owed).

Each is a page of a NATIVE preview (print_set_windows.Preview, the bundled
runtime) of the folder its `capture.workspace` names:

- `marketing` is app_scenes_windows.MARKETING, ~/School Web Space: ICS3U and
  ICS4U, the folder the Windows app-window scenes use;
- `demo` is app_scenes_windows.DEMO, ~/Teaching: ENG2D, MCV4U and SCH3U.

Before anything is written, each folder is checked (`refuse_marketing`,
`refuse_demo`) and its courses are zipped into its own courses/_backups, so
everything the run changes can be put back. Then it is given what the
figures need, by the same steps the Mac runs: the marketing ICS3U's runnable
pages brought up to date from the ready-made course and Check Your Loops
planted (`marketing_folder.apply_code_steps`, or `add_code_pages` for the
quizzes alone); the demo folder's three quiz pages planted
(`demo_folders.apply_planted_pages`). The launchers and the recipe come from
the tree's COMMITTED files (`git archive HEAD`, as the Mac's #562 fix N5), so
an uncommitted edit never rides into a folder's `.toolchain/`.

Each page is opened in an Edge `--app` window at the print page's framing
(1280 x 860 DIPs, `fit=True`), scrolled to the top, put into its figure's
state by `website/shots/prepare/<id>.js` -- the SAME scripts the Mac's
webwindow.swift runs, each the body of an async function taking `timeoutMs`
and returning "ready" or the reason it is not -- and photographed whole by
windowshot, in light and then dark. Anything but "ready" refuses the
picture; so does a quiz taller than the window (the scripts say so
themselves). `expectText` is read back with Windows' own OCR (`must_show`).

A REAL run (pictures into site/img) needs the window drawn at exactly 2x
(#557: a 4K screen at 200%): it refuses any other fitted scale, and any
picture that is not 2560 x 1720. `--dry-run` takes every picture at whatever
scale this screen gives, into a scratch folder only, and writes nothing to
site/img: the proof that every prepare script reaches "ready" here.

Nothing here promotes a shot. `windows: true` and WINDOWS_PICTURE_OWED change
in the release commit, by `capture_windows.py --promote` (which checks the
pictures first) and by hand; site.json's availability flags are the
release's, never this file's.
"""

from __future__ import annotations

import io
import json
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
WEBSITE = REPO / "website"
IMAGE_DIR = REPO / "site" / "img"

sys.path.insert(0, str(HERE))
import print_set_windows  # noqa: E402
from print_set_windows import SCRATCH, PAGE_SIZE_DIP  # noqa: E402

PARTS = SCRATCH / "parts-preview-windows"
DRY_PARTS = SCRATCH / "parts-preview-windows-dry-run"
# What a real run took, and at what scale: `--promote` reads it, so a shot is
# never marked as having a Windows picture that was not taken at 2x.
LEDGER = SCRATCH / "preview-pages-windows.json"
PREPARE_DIR = HERE / "prepare"
PREPARE_TIMEOUT_MS = 120000

SCENES = ("code", "quizzes")
# Swift stays read-only on Windows (#570, Russell's ruling): its two figures
# stay owed, and no pass here ever takes them.
NOT_ON_WINDOWS = ("code-swift", "code-swift-live")

# #557: a Windows window capture is never scaled, and stands beside the Mac's
# 2x capture, so it is taken at exactly 2x: 1280 x 860 DIPs is 2560 x 1720.
WANTED_SCALE = 2.0
SCALE_TOLERANCE = 0.01
WANTED_PIXELS = (round(PAGE_SIZE_DIP[0] * WANTED_SCALE), round(PAGE_SIZE_DIP[1] * WANTED_SCALE))


def announce(message: str) -> None:
    print(f"\n▶︎ {message}", flush=True)


def preview_page_shots(scene: str, only: list[str] | None = None) -> list[dict]:
    """The `preview-page` shots of `scene` that Windows takes, in shots.json
    order; with `only`, just those ids (every one must be such a shot)."""
    manifest = json.loads((WEBSITE / "shots.json").read_text(encoding="utf-8"))
    wanted: list[dict] = []
    for shot in manifest["shots"]:
        capture = shot.get("capture", {})
        if capture.get("kind") != "preview-page" or capture.get("scene") != scene:
            continue
        if shot["id"] in NOT_ON_WINDOWS:
            continue
        if only is not None and shot["id"] not in only:
            continue
        wanted.append(shot)
    return wanted


def windows_preview_ids() -> list[str]:
    ids: list[str] = []
    for scene in SCENES:
        for shot in preview_page_shots(scene):
            if shot["id"] not in ids:
                ids.append(shot["id"])
    return ids


def folders() -> dict[str, Path]:
    from app_scenes_windows import DEMO, MARKETING
    return {"marketing": MARKETING, "demo": DEMO}


# ---------- The guards ----------

def plantoir_is_running() -> bool:
    """A running Plantoir mirrors ITS bundled recipe into a folder it touches,
    and would put the launchers this run wrote back to its own."""
    listed = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Plantoir.exe", "/NH"],
                            capture_output=True, text=True)
    return "Plantoir.exe" in listed.stdout


def refuse_marketing(folder: Path) -> None:
    """Only the Windows marketing folder, and only while it holds nothing but
    ICS3U, ICS4U and reference copies of them.

    The Mac's guard (`marketing_folder.refuse_foreign_courses`) also wants
    the `.plantoir-marketing-folder` marker its own set-up writes. The Windows
    folder has none (measured 2026-10-22): it is made by the APP's New Course
    panel (app_scenes_windows.provision), and its courses were copied in from
    the Mac's (#460). Writing a marker now would only make the folder pass a
    test it was never made by. So the place is checked instead -- the one
    folder the Windows scenes keep, by its resolved path -- and the same
    allow-list the Mac's guard uses (`marketing_folder.foreign_courses`)."""
    import marketing_folder
    from app_scenes_windows import MARKETING
    if folder.resolve() != MARKETING.resolve():
        raise SystemExit(f"{folder} is not the Windows marketing folder ({MARKETING}). Nothing was changed.")
    foreign = marketing_folder.foreign_courses(folder)
    if foreign:
        raise SystemExit(f"{folder} holds courses the marketing set-up did not make ({', '.join(foreign)}). "
                         "Nothing was changed.")
    if marketing_folder.read_config(folder / "courses" / marketing_folder.RUNNABLE_COURSE) is None:
        raise SystemExit(f"{folder} has no {marketing_folder.RUNNABLE_COURSE}: make it first "
                         "(capture_windows.py --app makes the marketing folder).")


def refuse_demo(folder: Path) -> None:
    import demo_folders
    from app_scenes_windows import DEMO
    if folder.resolve() != DEMO.resolve():
        raise SystemExit(f"{folder} is not the Windows demo folder ({DEMO}). Nothing was changed.")
    if demo_folders.identify(folder) != "demo":
        raise SystemExit(f"{folder} does not hold the demo courses (ENG2D, MCV4U, SCH3U) and nothing else. "
                         "Nothing was changed.")


# ---------- Backing up, then planting ----------

def course_codes(folder: Path) -> list[str]:
    """The course folders a run may write into: every course with a
    configuration, reference copies apart (nothing here writes to them)."""
    import demo_folders
    codes: list[str] = []
    for entry in sorted((folder / "courses").iterdir()):
        config = demo_folders.read_config(entry)
        if config is None or config.get("kept_for_reference") is True:
            continue
        codes.append(entry.name)
    return codes


def back_up(folder: Path, codes: list[str]) -> list[Path]:
    """Each course zipped into the folder's own courses/_backups/<CODE>/, by
    the name a teacher's own backup has (contracts/course-management.json →
    zipNames: `<CODE>_backup_<YYYY-MM-DD_HHMMSS>.zip`), laid out as the
    apps' backups are (`<CODE>/...`), so the Backups list shows it and can
    put the course back. The built site is not in it: it is made again."""
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    made: list[Path] = []
    for code in codes:
        course = folder / "courses" / code
        destination = folder / "courses" / "_backups" / code / f"{code}_backup_{stamp}.zip"
        destination.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(course.rglob("*")):
                relative = path.relative_to(course)
                if relative.parts and relative.parts[0] == ".merged_output":
                    continue
                if path.is_file() and not path.is_symlink():
                    archive.write(path, (Path(code) / relative).as_posix())
        made.append(destination)
        print(f"   backed up {code} to {destination}")
    return made


def page_label(capture: dict) -> str:
    """`ICS3U/Warm-Ups/Spot the Bug.md`: the page a shot shows, as the steps'
    report names it (a preview's path is the file name with dashes)."""
    return f"{capture['course']}/{capture['path'].strip('/').replace('-', ' ')}.md"


def refuse_changed_pages(report, shots: list[dict]) -> None:
    """A page a figure shows that somebody changed is left as they changed it,
    so the figure would not be of the committed page (the Mac's rule)."""
    for shot in shots:
        label = page_label(shot["capture"])
        for line in report.lines:
            if line in (f"left as you changed it: {label}", f"left as you changed it: {label} runnable"):
                raise SystemExit(f"{label} was changed by hand, so {shot['id']} would not be of the committed "
                                 "page. Put it back from the backup this run made, or delete it to have it "
                                 "planted again.")


def plant(workspace: str, folder: Path, scenes: list[str], shots: list[dict]) -> list[str]:
    """What the figures need, by the Mac's own steps. Returns the report's
    lines, so the run can say exactly what it rewrote and planted."""
    import demo_folders
    import marketing_folder
    report = marketing_folder.Report()
    if workspace == "marketing":
        if "code" in scenes:
            marketing_folder.apply_code_steps(folder, report)   # runnable pages, then CODE_PAGES
        else:
            marketing_folder.add_code_pages(folder, report)
        if report.named_and_skipped:
            raise SystemExit("The marketing folder is missing what the figures need: "
                             + "; ".join(report.named_and_skipped))
    else:
        demo_folders.apply_planted_pages(folder, report)
        problems = demo_folders.demo_state_problems(folder)
        if problems:
            raise SystemExit(f"{folder} does not match marketing/folders.json: " + "; ".join(problems)
                             + ". Run capture_windows.py --provision-demo first.")
    refuse_changed_pages(report, shots)
    print(f"   {marketing_folder.summary(report)}")
    changed: list[str] = []
    for line in report.lines:
        if line.startswith("made: "):
            changed.append(line[len("made: "):])
            print(f"   {line}")
    return changed


def committed_recipe() -> Path:
    """The tree's files exactly as committed (`git archive HEAD`), never the
    working tree: an uncommitted edit or an untracked __pycache__ must not
    ride into a folder's .toolchain/ (the Mac's #562 review, N5)."""
    destination = SCRATCH / "committed-recipe"
    shutil.rmtree(destination, ignore_errors=True)
    destination.mkdir(parents=True)
    archive = subprocess.run(["git", "-C", str(REPO), "archive", "--format=tar", "HEAD"],
                             capture_output=True, check=True)
    with tarfile.open(fileobj=io.BytesIO(archive.stdout)) as tar:
        tar.extractall(destination, filter="data")
    return destination


# ---------- The pictures ----------

def run_prepare(script: Path):
    """The prepare script, run in the page after it is scrolled to the top:
    the body of an async function taking `timeoutMs`, as webwindow.swift
    runs it, awaited over the DevTools protocol. Anything but "ready" stops
    the run before the shutter."""
    body = script.read_text(encoding="utf-8")
    expression = f"(async (timeoutMs) => {{\n{body}\n}})({PREPARE_TIMEOUT_MS})"

    def prepare_page(page) -> None:
        print_set_windows.at_the_top(page)
        said = page.evaluate(expression)
        if said != "ready":
            raise SystemExit(f"{script.name}: {said}. Nothing past this point was taken.")
        print(f"   {script.name}: ready")
        time.sleep(0.5)
    return prepare_page


def refuse_the_wrong_scale(dry_run: bool) -> float:
    from hero_windows import fitted_scale, make_dpi_aware
    make_dpi_aware()
    scale = fitted_scale(PAGE_SIZE_DIP)
    if dry_run:
        print(f"   A dry run, at {scale:.3f}x: the pictures go to {DRY_PARTS}, nothing to site/img.")
    elif abs(scale - WANTED_SCALE) >= SCALE_TOLERANCE:
        raise SystemExit(f"The page window would be drawn at {scale:.3f}x, not {WANTED_SCALE:.0f}x (#557): run "
                         "this on a 4K screen at 200%, or pass --dry-run to prove the pages without pictures "
                         "for the site.")
    return scale


def read_ledger() -> dict:
    try:
        return json.loads(LEDGER.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def record(shot_id: str, theme: str, scale: float, picture: Path) -> None:
    from PIL import Image
    with Image.open(picture) as opened:
        size = opened.size
    ledger = read_ledger()
    ledger.setdefault(shot_id, {})[theme] = {"scale": round(scale, 4), "width": size[0], "height": size[1],
                                             "taken": datetime.now().isoformat(timespec="seconds")}
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    LEDGER.write_text(json.dumps(ledger, indent=2) + "\n", encoding="utf-8")


def photograph_course(folder: Path, code: str, shots: list[dict], scale: float, dry_run: bool) -> list[str]:
    """One preview of `code`, every shot of it in light then dark."""
    from hero_windows import capture_page, read_theme, write_theme
    from images import prepare
    parts = DRY_PARTS if dry_run else PARTS
    parts.mkdir(parents=True, exist_ok=True)
    print_set_windows.PARTS.mkdir(parents=True, exist_ok=True)   # must_show reads a larger copy there
    taken: list[str] = []
    with print_set_windows.Preview(folder, code) as preview:
        if print_set_windows.desktop_is_locked():
            raise SystemExit("The desktop is locked, so no window can be photographed. Unlock it and run again.")
        was_apps, was_system = read_theme()
        try:
            for shot in shots:
                capture = shot["capture"]
                url = preview.address + capture["path"]
                script = PREPARE_DIR / capture["prepare"]
                for theme in ("light", "dark"):
                    write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)
                    announce(f"{shot['id']}, {theme}")
                    part = parts / f"{shot['id']}-windows-{theme}.png"
                    capture_page(url, "", part, size_dip=PAGE_SIZE_DIP, prepare_page=run_prepare(script), fit=True)
                    print_set_windows.must_show(part, shot)
                    if dry_run:
                        taken.append(f"{shot['id']}-{theme}")
                        continue
                    from PIL import Image
                    with Image.open(part) as opened:
                        size = opened.size
                    if size != WANTED_PIXELS:
                        raise SystemExit(f"{part.name} is {size[0]} x {size[1]}, not {WANTED_PIXELS[0]} x "
                                         f"{WANTED_PIXELS[1]} (#557). Nothing past this point was taken.")
                    destination = IMAGE_DIR / part.name
                    shutil.copyfile(part, destination)
                    prepare(destination)   # never scaled: 2x, like the mac's (#557)
                    record(shot["id"], theme, scale, destination)
                    taken.append(f"{shot['id']}-{theme}")
                    print(f"   saved {destination.name} + WebP")
        finally:
            write_theme(was_apps, was_system)
            print("   Windows colour mode put back")
    return taken


def capture_preview_pages(selection: dict[str, list[str] | None], dry_run: bool = False) -> list[str]:
    """The Windows `preview-page` shots each scene of `selection` names
    (`{"code": None}` is all of them, `{"quizzes": ["quiz-math"]}` one),
    folder by folder and course by course, each course previewed once.
    Returns the pictures taken, as `<id>-light` / `<id>-dark`."""
    shots: list[dict] = []
    for scene, only in selection.items():
        chosen = preview_page_shots(scene, only)
        if only is not None:
            unknown = [identifier for identifier in only if identifier not in [shot["id"] for shot in chosen]]
            if unknown:
                raise SystemExit(f"Not a Windows {scene} figure: {', '.join(unknown)}"
                                 + (" (Swift stays read-only on Windows, #570)"
                                    if set(unknown) & set(NOT_ON_WINDOWS) else ""))
        for shot in chosen:
            if shot not in shots:
                shots.append(shot)
    if not shots:
        return []
    if plantoir_is_running():
        raise SystemExit("Plantoir is running: it would put its own launchers back into the folders this run "
                         "writes. Quit it first.")
    scale = refuse_the_wrong_scale(dry_run)
    places = folders()
    workspaces: list[str] = []
    for shot in shots:
        if shot["capture"]["workspace"] not in workspaces:
            workspaces.append(shot["capture"]["workspace"])
    # Every folder is checked before ANY is written to.
    for workspace in workspaces:
        (refuse_marketing if workspace == "marketing" else refuse_demo)(places[workspace])
    recipe = committed_recipe()
    taken: list[str] = []
    try:
        for workspace in workspaces:
            folder = places[workspace]
            mine = [shot for shot in shots if shot["capture"]["workspace"] == workspace]
            announce(f"Photographing {', '.join(shot['id'] for shot in mine)} in {folder}")
            back_up(folder, course_codes(folder))
            plant(workspace, folder, [shot["capture"]["scene"] for shot in mine], mine)
            print_set_windows.mirror_toolchain(folder, source=recipe)
            courses: list[str] = []
            for shot in mine:
                if shot["capture"]["course"] not in courses:
                    courses.append(shot["capture"]["course"])
            for code in courses:
                taken.extend(photograph_course(folder, code, [s for s in mine if s["capture"]["course"] == code],
                                               scale, dry_run))
    finally:
        shutil.rmtree(recipe, ignore_errors=True)
    announce(f"Took {len(taken)} picture(s){' (a dry run: none for the site)' if dry_run else ''}")
    if not dry_run:
        print("   Not promoted: once Russell has looked at them, `capture_windows.py --promote "
              + ",".join(sorted({entry.rsplit('-', 1)[0] for entry in taken})) + "` marks them windows: true.")
    return taken


# ---------- Promotion ----------

def promotion_problems(identifier: str) -> list[str]:
    """Why `identifier` may not be marked `windows: true` yet: both pictures,
    PNG and WebP, in site/img, 2560 x 1720, and taken at 2x by a real run."""
    from PIL import Image
    if identifier not in windows_preview_ids():
        return [f"{identifier} is not a Windows preview-page figure"]
    problems: list[str] = []
    ledger = read_ledger().get(identifier, {})
    for theme in ("light", "dark"):
        png = IMAGE_DIR / f"{identifier}-windows-{theme}.png"
        if not png.exists() or not png.with_suffix(".webp").exists():
            problems.append(f"{png.stem}: the PNG or its WebP twin is not in site/img")
            continue
        with Image.open(png) as opened:
            if opened.size != WANTED_PIXELS:
                problems.append(f"{png.name} is {opened.size[0]} x {opened.size[1]}, not "
                                f"{WANTED_PIXELS[0]} x {WANTED_PIXELS[1]}")
        taken = ledger.get(theme)
        if taken is None:
            problems.append(f"{png.name} was not taken by a real run on this machine ({LEDGER} has no record)")
        elif abs(float(taken["scale"]) - WANTED_SCALE) >= SCALE_TOLERANCE:
            problems.append(f"{png.name} was taken at {taken['scale']}x, not {WANTED_SCALE:.0f}x")
    return problems


def promote(identifiers: list[str]) -> int:
    """`windows: true` for each shot whose pictures pass `promotion_problems`
    (print_set_windows.promote writes it, and says WINDOWS_PICTURE_OWED must
    lose the shot in the same commit -- by hand, so the release commit is
    where both change). site.json's availability flags are not touched."""
    ready: list[str] = []
    refused = False
    for identifier in identifiers:
        problems = promotion_problems(identifier)
        if problems:
            refused = True
            for problem in problems:
                print(f"   not promoted, {identifier}: {problem}", file=sys.stderr)
        else:
            ready.append(identifier)
    if ready:
        print_set_windows.promote(ready)
    return 1 if refused else 0

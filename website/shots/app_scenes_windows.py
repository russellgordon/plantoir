#!/usr/bin/env python3
"""The Windows app's pictures on plantoir.app, each a REAL window photographed whole (#380, #370).

    python website/shots/capture_windows.py --app [scene,scene]

For each scene, in Windows' light and then dark colour mode, Plantoir.exe is
started with ``--stage-scene <scene>`` (MarketingShotCapturer.cs): it opens
the window the scene is about, drives it to the state the caption describes
through the app's own code, and says so in a ready file. The window is then
photographed by ``windowshot`` -- Windows.Graphics.Capture on that one
window, its own corners and alpha, nothing cropped, masked or drawn -- and
the process is ended. A scene that cannot reach its state says why and is
NOT photographed.

Two working folders, both made by the app itself (the ``provision`` scene:
the New Course panel for each course, Keep a Copy for Reference's code for
last year's ICS3U). Which courses, which sections, which school year the
reference copy is filed under and where each marketing course deploys are
all read from ``marketing/folders.json``, the file the mac reads (#445,
#459); nothing here lists a course of its own:

- DEMO, ``~/Teaching`` -- folders.json's ``demo.courses`` (ENG2D, MCV4U and
  SCH3U), the courses the hero, the preview, the progress and the assistant
  pictures show. Disposable: it is deleted and made again whenever it is
  missing a course or a course has other sections than folders.json's (the
  app's provision scene leaves a course that is already there as it is).
  Then, every run, the demo STATE is applied (``capture_windows.provision_demo``:
  the colour schemes, the teacher's name, the stand-in site markers and the
  front pages, through ``plantoir-mcp.exe``); a section already right costs
  nothing.
- MARKETING, ``~/School Web Space`` -- ``marketing.courses`` (ICS3U, ICS4U)
  and the reference copy, the v1.4.0 scenes' folder. Kept. A course with no
  folder destination yet is given folders.json's ``publishTo``; one already
  pointed somewhere keeps it.

Every picture's path bar shows ``~/Desktop/Teaching``, as the mac's do: each
folder's courses are put there for its scenes (``ShownAsTeaching``), so
nothing like a "marketing" folder is ever in frame (Russell, 2026-10-04).

Every run starts the app with ``--state-dir`` pointing at a temporary
folder, so no setting, window list or trail line of a teacher's is touched.
Launched through ShellExecute (PowerShell's Start-Process), never with
redirected output: a creator whose stdio are pipes leaks them into the
launchers the app starts, and course creation then hangs (DrivenApp.cs says
how that was measured).

What it borrows and puts back: the Windows colour mode; every process it
started (the app, its tools, a preview it built) is ended, and any lease
file they left is deleted.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
IMAGE_DIR = REPO / "site" / "img"
sys.path.insert(0, str(HERE))

from images import prepare, WIDEST_WINDOW_PIXELS  # noqa: E402
import demo_folders  # noqa: E402
import hero_windows as desk  # noqa: E402

DEMO = Path.home() / "Teaching"
MARKETING = Path.home() / "School Web Space"
# Every picture shows ONE teacher's folder, ~/Desktop/Teaching, as the mac's
# do (its capture.py, MarketingFolderShownAsTeaching; Russell 2026-10-04: no
# picture may show "Plantoir Marketing"). Each folder's courses are put there
# for its scenes, with whatever is there set aside, and both are put back.
SHOWN = Path.home() / "Desktop" / "Teaching"
COURSES_SET_ASIDE = SHOWN / ".courses set aside for the pictures"


def publish_folders(folder: Path) -> list[Path]:
    """Every folder destination the courses in `folder` are set to deploy
    to, read from their own course_config.json — the kept folder's
    (`Websites`, `Websites\\ICS4U`) and a fresh one's (folders.json's
    `publishTo`) alike. A sheet that offers to deploy to a folder that does
    not exist warns about it instead, so these are made before a scene."""
    import marketing_folder
    found: list[Path] = []
    courses = folder / "courses"
    if not courses.is_dir():
        return found
    for course_dir in sorted(courses.iterdir()):
        config = demo_folders.read_config(course_dir) or {}
        path = str(config.get("deploy_folder_path", ""))
        if config.get("deploy_target") == marketing_folder.FOLDER_DESTINATION and path:
            found.append(Path(path))
    return found


def make_publish_folders(folder: Path, made: list[Path] | None = None) -> list[Path]:
    """Make the folder destinations of `folder`'s courses — only those
    INSIDE `folder`, so a config still naming some other place (say a
    Desktop path left by a run that died) never gets folders made there.
    Returns the top-level folders under `folder` that did not exist before,
    so a caller that made them for a while can take them away again. Pass
    `made` to have them recorded AS they are made, so a failure part-way
    still leaves the caller knowing what to take away."""
    if made is None:
        made = []
    for destination in publish_folders(folder):
        try:
            top = folder / destination.relative_to(folder).parts[0]
        except (ValueError, IndexError):
            continue
        if not top.exists() and top not in made:
            made.append(top)
        destination.mkdir(parents=True, exist_ok=True)
    return made


class ShownAsTeaching:
    """`folder`'s courses at SHOWN for the scenes, SHOWN's own courses set
    aside beside them, both put back, and every course's absolute paths
    rewritten there and back.

    The COURSES are swapped, not the folder: renaming ~/Desktop/Teaching
    itself was refused ("Access is denied") while a File Explorer window had
    it open — which on a teacher's or a developer's machine is the ordinary
    case. A working folder is its launchers and its `courses`, and the app
    refreshes the launchers itself, so the window shows exactly the folder
    the scene needs, at SHOWN's path."""

    def __init__(self, folder: Path) -> None:
        self.folder = folder

    @staticmethod
    def rewrite(courses: Path, old: Path, new: Path) -> None:
        for config in courses.glob("*/course_config.json"):
            try:
                text = config.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as problem:
                # One unreadable config must not stop the others, nor the
                # courses being put back: it is named and left as it is.
                print(f"   {config.parent.name}'s course_config.json could not be read ({problem}); left as it is")
                continue
            escaped_old, escaped_new = json.dumps(str(old))[1:-1], json.dumps(str(new))[1:-1]
            if escaped_old in text:
                try:
                    config.write_text(text.replace(escaped_old, escaped_new), encoding="utf-8")
                except PermissionError:
                    pass   # a reference course is locked, and deploys nowhere

    def __enter__(self) -> Path:
        if COURSES_SET_ASIDE.exists():
            raise SystemExit(f"{COURSES_SET_ASIDE} is still there from an earlier run: put it back first.")
        self.made_here: list[Path] = []
        if (SHOWN / "courses").exists():
            (SHOWN / "courses").rename(COURSES_SET_ASIDE)
        try:
            (self.folder / "courses").rename(SHOWN / "courses")
        except BaseException:
            if COURSES_SET_ASIDE.exists():
                COURSES_SET_ASIDE.rename(SHOWN / "courses")
            raise
        try:
            self.rewrite(SHOWN / "courses", self.folder, SHOWN)
            # Where these courses deploy while they are shown here
            # (`Websites` for the kept folder, `School Web Space` for one made
            # from folders.json): made for the scenes, and only what was not
            # there already is taken away again on the way out.
            make_publish_folders(SHOWN, self.made_here)
        except BaseException:
            # The courses are already here: a failure past this point must
            # put them back, or they are stranded on the Desktop with their
            # paths rewritten and the next run refuses (`with` never calls
            # __exit__ for an __enter__ that raised).
            self.__exit__()
            raise
        print(f"   {self.folder.name}'s courses are at {SHOWN} for their pictures")
        return SHOWN

    def __exit__(self, *_) -> bool:
        try:
            for top in self.made_here:
                shutil.rmtree(top, ignore_errors=True)
            self.rewrite(SHOWN / "courses", SHOWN, self.folder)
        finally:
            # The courses go back whatever happened above: courses left on
            # the Desktop are the one outcome this class exists to prevent.
            (SHOWN / "courses").rename(self.folder / "courses")
            if COURSES_SET_ASIDE.exists():
                COURSES_SET_ASIDE.rename(SHOWN / "courses")
        print(f"   {self.folder.name}'s courses and {SHOWN}'s own put back")
        return False


# id in shots.json -> (scene, folder). One picture per scene and appearance.
SCENES: dict[str, tuple[str, Path]] = {
    "courses": ("courses", MARKETING),
    "new-course": ("new-course", MARKETING),
    "club": ("club", MARKETING),
    "reference": ("reference", MARKETING),
    "start-of-year": ("start-of-year", MARKETING),
    "curriculum-settings": ("curriculum-settings", MARKETING),
    "both-curricula": ("both-curricula", MARKETING),
    "map-ontario": ("map-ontario", MARKETING),
    "map-college-board": ("map-college-board", MARKETING),
    # The Schedule a deploy sheet in its window, alone: Windows' notification
    # is no window Windows.Graphics.Capture can be given (EnumWindows, UI
    # Automation and FindWindowEx found none while a real one showed), so the
    # Windows picture is the sheet, with words of its own (shots.json
    # `windowsAlt`) — Russell's ruling of 2026-10-04.
    "schedule": ("schedule-sheet", MARKETING),
    "progress": ("progress", DEMO),
    "preview": ("preview", DEMO),
    "assistant": ("assistant", DEMO),
}

# This session's own MCP server, which a capture must never end.
NEVER_STOP_PIDS: set[int] = {13052}


def start_app(exe: Path, arguments: list[str]) -> int:
    """Start Plantoir through ShellExecute and hand back its process id."""
    # Windows PowerShell 5.1 joins -ArgumentList with spaces and quotes
    # nothing, so "School Web Space" arrived as "School" (measured on the
    # first run). Each argument carries its own double quotes.
    quoted = ", ".join("'\"" + argument.replace("'", "''") + "\"'" for argument in arguments)
    script = (f"$p = Start-Process -FilePath '{exe}' -ArgumentList @({quoted}) -PassThru; "
              "Write-Output $p.Id")
    found = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True)
    return int(found.stdout.strip().splitlines()[-1])


def end_everything_naming(folder: Path, app_pid: int | None) -> None:
    """End the app, and anything still naming the folder: its tools, a build
    or a preview server it started. Then the lease files they left."""
    if app_pid is not None:
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(app_pid)], capture_output=True)
    keep = ",".join(str(pid) for pid in NEVER_STOP_PIDS) or "0"
    query = (
        "$keep = @(" + keep + "); "
        "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and "
        "$_.CommandLine.Contains('" + str(folder).replace("'", "''") + "') -and "
        "$keep -notcontains $_.ProcessId -and $_.ProcessId -ne $PID } | "
        "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", query], capture_output=True, text=True)
    time.sleep(1.0)
    activity = folder / "courses" / ".internal" / "activity"
    if activity.is_dir():
        for lease in activity.glob("*.lease"):
            try:
                lease.unlink()
            except OSError:
                pass


# The section each preview-building scene serves, so its preview is ended
# with the launcher's own stop afterwards: a preview's server runs from the
# builds folder and does not name the working folder, so ending "anything
# naming the folder" left it holding the port, and the next scene's preview
# met it (measured: map-college-board refused after map-ontario).
SERVES: dict[str, tuple[str, int]] = {
    "progress": ("ENG2D", 2), "preview": ("ENG2D", 1),
    "map-ontario": ("ICS3U", 1), "map-college-board": ("ICS3U", 1), "both-curricula": ("ICS3U", 1),
}


def stop_preview(exe: Path, folder: Path, code: str, section: int) -> None:
    import os
    runtime = exe.parent / "runtime"
    environment = dict(os.environ)
    if (runtime / "manifest.json").exists():
        environment["PLANTOIR_RUNTIME"] = str(runtime)
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(folder / "preview.ps1"), code, str(section), "--stop"],
                   cwd=folder, env=environment, capture_output=True, text=True, timeout=180)


def stage(exe: Path, scene: str, theme: str, folder: Path, extra: list[str] | None = None,
          patience: float = 120.0) -> tuple[int, str, Path]:
    """Start the app on one scene; wait for its ready file. (pid, outcome, state dir)."""
    state = Path(tempfile.mkdtemp(prefix="plantoir-scene-"))
    ready = state / "ready.txt"
    arguments = ["--state-dir", str(state), "--stage-scene", scene, "--theme", theme,
                 "--folder", str(folder), "--ready-file", str(ready)] + (extra or [])
    pid = start_app(exe, arguments)
    deadline = time.time() + patience
    while time.time() < deadline:
        if ready.exists():
            time.sleep(0.3)
            return pid, ready.read_text(encoding="utf-8").strip(), state
        time.sleep(1.0)
    return pid, "refused: no answer from the app in time", state


def provision(exe: Path, folder: Path, courses: str, reference: str | None = None) -> None:
    """The folder made by the app: set up, its courses through New Course."""
    extra = ["--courses", courses]
    if reference:
        extra += ["--reference-copy", reference]
    desk.announce(f"Setting up {folder} through the app")
    pid, outcome, state = stage(exe, "provision", "light", folder, extra, patience=40 * 60)
    end_everything_naming(folder, pid)
    shutil.rmtree(state, ignore_errors=True)
    if outcome != "staged":
        raise SystemExit(f"{folder} could not be set up: {outcome}")


def demo_is_whole() -> bool:
    # Real launchers, not the one-line stand-ins the old capture wrote: a
    # preview has to be BUILT in this folder.
    launcher = DEMO / "preview.ps1"
    if not launcher.exists() or launcher.stat().st_size < 2000:
        return False
    # Every course folders.json names, with exactly its sections: the
    # provision scene leaves a course that is already there as it is, so a
    # folder made when the demo had other sections would keep them forever.
    for course in demo_folders.demo_courses():
        config = demo_folders.read_config(DEMO / "courses" / course["code"])
        if config is None or list(config.get("section_numbers") or []) != list(course["sections"]):
            return False
    return True


def give_marketing_courses_their_destinations(report) -> None:
    """folders.json's `publishTo` for a marketing course with no folder
    destination yet; a course already pointed at a folder keeps it (the kept
    folder's ICS3U deploys to `Websites`, its ICS4U to `Websites\\ICS4U`).
    `marketing_folder.publish_to_folder` would leave those alone too, but it
    makes folders.json's folder first, which would put an empty
    `School Web Space` inside the kept folder on every run."""
    import marketing_folder
    for course in demo_folders.marketing_courses():
        course_dir = MARKETING / "courses" / course["code"]
        config = demo_folders.read_config(course_dir)
        if config is None:
            continue
        if config.get("deploy_target") == marketing_folder.FOLDER_DESTINATION and config.get("deploy_folder_path"):
            report.skip(f"{course['code']} publishes to {config['deploy_folder_path']}; left as it is")
            continue
        marketing_folder.publish_to_folder(course_dir, MARKETING / course["publishTo"], report)


def ensure_folders(exe: Path, folders: set[Path]) -> None:
    from datetime import date
    if DEMO in folders:
        if not demo_is_whole():
            shutil.rmtree(DEMO, ignore_errors=True)
            provision(exe, DEMO, demo_folders.provision_courses_argument(demo_folders.demo_courses()))
        # The demo STATE: colours, the teacher's name, site markers and the
        # front pages, through plantoir-mcp.exe. A folder in the wrong state
        # is never photographed.
        import capture_windows
        if capture_windows.provision_demo(DEMO, exe) != 0:
            raise SystemExit(f"{DEMO} does not match marketing/folders.json yet (see 'still to do' above)")
    if MARKETING in folders:
        provision(exe, MARKETING, demo_folders.provision_courses_argument(demo_folders.marketing_courses()),
                  demo_folders.reference_copy_argument(MARKETING, date.today()))
        import marketing_folder
        report = marketing_folder.Report()
        give_marketing_courses_their_destinations(report)
        # Where each course deploys: a sheet that offers to deploy to a folder
        # that does not exist warns about it instead, and the first
        # schedule-sheet picture showed exactly that warning.
        make_publish_folders(MARKETING)
        marketing_folder.add_how_i_teach(MARKETING / "courses" / marketing_folder.CURRICULUM_COURSE, report)
        print(f"   {marketing_folder.summary(report)}")


def bring_forward(hwnd: int) -> None:
    """In front and active, at the size the app gave itself."""
    import ctypes.wintypes as wintypes
    rect = wintypes.RECT()
    desk.user32.GetWindowRect(hwnd, desk.ctypes.byref(rect))
    desk.place(hwnd, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top)


def builds_folder_of(folder: Path) -> Path | None:
    """The app's builds folder for a working folder, found by the marker it
    writes there (`working-folder.txt`)."""
    import os
    root = Path(os.environ["LOCALAPPDATA"]) / "Plantoir" / "builds"
    for marker in root.glob("*/working-folder.txt"):
        try:
            if Path(marker.read_text(encoding="utf-8").strip()) == folder:
                return marker.parent
        except OSError:
            continue
    return None


def photograph_scene(exe: Path, identifier: str, theme: str, parts: Path) -> Path:
    """One scene, in its folder already moved to SHOWN (ShownAsTeaching)."""
    scene, _ = SCENES[identifier]
    folder = SHOWN
    if scene == "schedule-sheet":
        # Where the courses deploy while they are shown here (each course's
        # own destination, made by ShownAsTeaching; again here in case a
        # scene before this one took it away): a sheet that offers to deploy
        # to a folder that does not exist says so instead.
        make_publish_folders(SHOWN)
    if scene == "progress":
        # The progress picture is a build caught part-way, and the build is
        # then ended; a scaffold ended part-way refuses the next build ("the
        # Explorer's hide filter could not be established" — the dark pass of
        # the first full run). So the section's build starts from nothing.
        builds = builds_folder_of(folder)
        if builds is not None:
            shutil.rmtree(builds / "work" / SERVES[scene][0] / f"section{SERVES[scene][1]}", ignore_errors=True)
    desk.announce(f"{identifier}, {theme}")
    patience = 25 * 60 if scene in ("preview", "map-ontario", "map-college-board", "both-curricula") else 180
    pid, outcome, state = stage(exe, scene, theme, folder, patience=patience)
    try:
        if outcome != "staged":
            raise SystemExit(f"{identifier} ({theme}) was not photographed: {outcome}")
        windows = desk.windows_of_process(pid)
        if len(windows) != 1:
            raise SystemExit(f"{identifier}: expected one window, found {len(windows)}")
        bring_forward(windows[0])
        time.sleep(1.0)
        return desk.photograph(windows[0], parts / f"{identifier}-windows-{theme}.png")
    finally:
        end_everything_naming(folder, pid)
        if scene in SERVES:
            stop_preview(exe, folder, *SERVES[scene])
        shutil.rmtree(state, ignore_errors=True)


# Parts of a figure, not pictures of their own: the two coverage maps side by
# side make `two-maps`, the way the mac's figure is made (the maps placed,
# never cut or redrawn).
PARTS_ONLY = ("map-ontario", "map-college-board")


def assemble(parts: Path, theme: str) -> None:
    from composite import side_by_side
    maps = [parts / f"map-ontario-windows-{theme}.png", parts / f"map-college-board-windows-{theme}.png"]
    if all(path.exists() for path in maps):
        side_by_side(maps, IMAGE_DIR / f"two-maps-windows-{theme}.png")
        print(f"   saved two-maps-windows-{theme}.png + WebP")


def capture_app_scenes(exe: Path, only: list[str] | None = None, parts: Path | None = None) -> None:
    desk.make_dpi_aware()
    parts = parts or desk.SCRATCH / "parts-app-windows"
    parts.mkdir(parents=True, exist_ok=True)
    chosen = [identifier for identifier in SCENES if not only or identifier in only]
    ensure_folders(exe, {SCENES[identifier][1] for identifier in chosen})
    was_apps, was_system = desk.read_theme()
    try:
        for source in (MARKETING, DEMO):
            group = [identifier for identifier in chosen if SCENES[identifier][1] == source]
            if not group:
                continue
            with ShownAsTeaching(source):
                for theme in ("light", "dark"):
                    desk.write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)
                    for identifier in group:
                        part = photograph_scene(exe, identifier, theme, parts)
                        if identifier in PARTS_ONLY:
                            continue
                        destination = IMAGE_DIR / part.name
                        shutil.copyfile(part, destination)
                        prepare(destination, WIDEST_WINDOW_PIXELS)
                        print(f"   saved {destination.name} + WebP")
                    assemble(parts, theme)
    finally:
        desk.write_theme(was_apps, was_system)
        print("   Windows colour mode put back")
    if not only or "how-i-teach" in only:
        capture_how_i_teach(parts)


# ---- How I Teach, in Obsidian ---------------------------------------------

def capture_how_i_teach(parts: Path | None = None) -> None:
    """Obsidian open on ICS3U's How I Teach page, in the marketing folder.

    The course folder is the vault, as the app's own "Open in Obsidian" makes
    it. Obsidian's list of vaults is read first and put back after; an
    Obsidian already running is closed first, so the window photographed is
    the one launched here (#428 item 6). Light and dark follow Windows and the
    vault's own theme, which is set for each pass.
    """
    import urllib.parse
    desk.make_dpi_aware()
    parts = parts or desk.SCRATCH / "parts-app-windows"
    parts.mkdir(parents=True, exist_ok=True)
    vault = MARKETING / "courses" / "ICS3U"
    if not (vault / "How I Teach.md").exists():
        raise SystemExit(f"{vault} has no How I Teach page")
    desk.stop("Obsidian.exe")
    original = desk.OBSIDIAN_CONFIG.read_text(encoding="utf-8") if desk.OBSIDIAN_CONFIG.exists() else None
    settings = vault / ".obsidian"
    had_settings = settings.exists()
    # workspace.json too: Obsidian reopens the vault on the page it last
    # showed, whatever the address asks for (measured: "index"), so it is set
    # aside for the run and put back after.
    kept = {name: (settings / name).read_bytes() for name in ("appearance.json", "app.json", "workspace.json")
            if (settings / name).exists()}
    was_apps, was_system = desk.read_theme()
    try:
        registry = json.loads(original) if original else {}
        vaults = registry.setdefault("vaults", {})
        for entry in vaults.values():
            entry["open"] = False
        vaults[desk.vault_identifier(vault)] = {"path": str(vault), "ts": int(time.time() * 1000), "open": True}
        desk.OBSIDIAN_CONFIG.parent.mkdir(parents=True, exist_ok=True)
        desk.OBSIDIAN_CONFIG.write_text(json.dumps(registry), encoding="utf-8")
        for theme in ("light", "dark"):
            desk.write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)
            settings.mkdir(exist_ok=True)
            (settings / "appearance.json").write_text(json.dumps({"theme": "obsidian" if theme == "dark" else "moonstone"}),
                                                      encoding="utf-8")
            (settings / "app.json").write_text(json.dumps({"livePreview": True, "defaultViewMode": "source",
                                                           "propertiesInDocument": "hidden",
                                                           "readableLineLength": True}), encoding="utf-8")
            (settings / "workspace.json").unlink(missing_ok=True)
            desk.announce(f"how-i-teach, {theme}")
            # By PATH, never by vault name: this PC knows several vaults
            # called ICS3U, and asking by name opened another one (whose
            # "How I Teach" did not exist) on the first runs.
            address = "obsidian://open?path=" + urllib.parse.quote(str(vault / "How I Teach.md"))
            process = subprocess.Popen([str(desk.OBSIDIAN_EXE), address])
            try:
                hwnd = desk.wait_for_window(lambda: desk.window_titled("Obsidian", pid=process.pid), seconds=45)
                time.sleep(3.5)
                scale = desk.scale_factor()
                desk.place(hwnd, 20, 20, round(1280 * scale), round(800 * scale))
                time.sleep(1.5)
                if not desk.window_title(hwnd).startswith("How I Teach - ICS3U"):
                    raise SystemExit(f"Obsidian is showing {desk.window_title(hwnd)!r}, not How I Teach")
                part = desk.photograph(hwnd, parts / f"how-i-teach-windows-{theme}.png")
            finally:
                desk.stop("Obsidian.exe")
            destination = IMAGE_DIR / part.name
            shutil.copyfile(part, destination)
            prepare(destination, WIDEST_WINDOW_PIXELS)
            print(f"   saved {destination.name} + WebP")
    finally:
        desk.write_theme(was_apps, was_system)
        if original is None:
            desk.OBSIDIAN_CONFIG.unlink(missing_ok=True)
        else:
            desk.OBSIDIAN_CONFIG.write_text(original, encoding="utf-8")
        if not had_settings:
            shutil.rmtree(settings, ignore_errors=True)
        else:
            for name in ("appearance.json", "app.json", "workspace.json"):
                if name in kept:
                    (settings / name).write_bytes(kept[name])
                else:
                    (settings / name).unlink(missing_ok=True)
        print("   colour mode, Obsidian's list of vaults and the vault's settings put back")


# ---- The schedule: the sheet, and Windows' own notification of a real run --

MCP_SERVER = REPO / "windows-app" / "Plantoir.Mcp" / "bin" / "Debug" / "net9.0" / "win-x64" / "plantoir-mcp.exe"


def ask_over_mcp(exe: Path, tool: str, arguments: dict) -> dict:
    """One tool call to Plantoir's own tools, the way the app's assistant
    makes it (McpClient.Start): newline-delimited JSON-RPC over stdio, with
    PLANTOIR_APP_PATH naming the Plantoir a scheduled deploy should start."""
    import os
    environment = dict(os.environ, PLANTOIR_APP_PATH=str(exe))
    process = subprocess.Popen([str(MCP_SERVER), "--folder", str(MARKETING), "--course", "ICS3U"],
                               cwd=MARKETING, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, encoding="utf-8", env=environment)

    def send(message: dict) -> None:
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()

    def answer(identifier: int) -> dict:
        deadline = time.time() + 90
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
        raise SystemExit(f"Plantoir's tools did not answer {tool}")

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                         "clientInfo": {"name": "plantoir-marketing-capture", "version": "1"}}})
        answer(1)
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": tool, "arguments": arguments}})
        return answer(2)
    finally:
        # Closed and waited for: a stray server holds Plantoir.Core.dll open.
        process.stdin.close()
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()


def notification_windows() -> dict[int, str]:
    """Every visible window Windows draws a notification in, by handle."""
    found: dict[int, str] = {}
    proc = desk.ctypes.WINFUNCTYPE(desk.ctypes.c_bool, desk.ctypes.c_int, desk.ctypes.POINTER(desk.ctypes.c_int))

    def callback(hwnd, _lparam):
        if desk.user32.IsWindowVisible(hwnd) and "notification" in desk.window_title(hwnd).lower():
            found[hwnd] = desk.window_title(hwnd)
        return True

    desk.user32.EnumWindows(proc(callback), None)
    return found


def capture_notification(exe: Path, theme: str, parts: Path) -> Path:
    """A REAL scheduled deploy of ICS3U Section 1 to its folder destination,
    set through Plantoir's own schedule_deploy three minutes ahead, and the
    notification Windows shows when it has run, photographed whole. The
    schedule is cancelled afterwards whatever happened (cancel_scheduled_deploy
    is safe when nothing is set)."""
    from datetime import datetime, timedelta
    make_publish_folders(MARKETING)
    when = (datetime.now() + timedelta(minutes=3)).replace(second=0, microsecond=0)
    before = set(notification_windows())
    reply = ask_over_mcp(exe, "schedule_deploy", {"course": "ICS3U", "section": 1, "when": when.strftime("%Y-%m-%d %H:%M")})
    if "error" in reply or reply.get("result", {}).get("isError"):
        raise SystemExit(f"the schedule was refused: {json.dumps(reply)[:400]}")
    desk.announce(f"notification, {theme}: ICS3U Section 1 deploys at {when:%H:%M}")
    try:
        deadline = time.time() + 12 * 60
        while time.time() < deadline:
            fresh = [hwnd for hwnd in notification_windows() if hwnd not in before]
            if fresh:
                time.sleep(1.5)   # its slide-in finished
                return desk.photograph(fresh[0], parts / f"notification-banner-windows-{theme}.png")
            time.sleep(0.25)
        raise SystemExit("no notification appeared after the scheduled deploy")
    finally:
        ask_over_mcp(exe, "cancel_scheduled_deploy", {"course": "ICS3U", "section": 1})
        end_everything_naming(MARKETING, None)


def assemble_schedule(parts: Path, theme: str) -> None:
    """The notification over the sheet's window, at its top right — placed
    whole, never cut or drawn (the mac's figure is arranged the same way)."""
    from PIL import Image
    from composite import save_figure
    sheet = parts / f"schedule-sheet-windows-{theme}.png"
    banner = parts / f"notification-banner-windows-{theme}.png"
    if not sheet.exists() or not banner.exists():
        return
    window = Image.open(sheet).convert("RGBA")
    card = Image.open(banner).convert("RGBA")
    rise = round(card.height * 0.45)
    margin = round(window.width * 0.012)
    width = max(window.width, card.width + margin)
    canvas = Image.new("RGBA", (width, window.height + rise), (0, 0, 0, 0))
    canvas.alpha_composite(window, (0, rise))
    canvas.alpha_composite(card, (width - card.width - margin, 0))
    save_figure(canvas, IMAGE_DIR / f"schedule-windows-{theme}.png")
    print(f"   saved schedule-windows-{theme}.png + WebP")


def capture_schedule_notifications(exe: Path, parts: Path | None = None) -> None:
    desk.make_dpi_aware()
    parts = parts or desk.SCRATCH / "parts-app-windows"
    parts.mkdir(parents=True, exist_ok=True)
    was_apps, was_system = desk.read_theme()
    try:
        for theme in ("light", "dark"):
            desk.write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)
            capture_notification(exe, theme, parts)
            assemble_schedule(parts, theme)
    finally:
        desk.write_theme(was_apps, was_system)
        print("   Windows colour mode put back")


def retake(exe: Path, pairs: list[tuple[str, str]], parts: Path | None = None) -> None:
    """Take again only the named pictures, e.g. progress in dark."""
    desk.make_dpi_aware()
    parts = parts or desk.SCRATCH / "parts-app-windows"
    was_apps, was_system = desk.read_theme()
    try:
        for identifier, theme in pairs:
            desk.write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)
            with ShownAsTeaching(SCENES[identifier][1]):
                part = photograph_scene(exe, identifier, theme, parts)
            if identifier not in PARTS_ONLY:
                destination = IMAGE_DIR / part.name
                shutil.copyfile(part, destination)
                prepare(destination, WIDEST_WINDOW_PIXELS)
                print(f"   saved {destination.name} + WebP")
            assemble(parts, theme)
    finally:
        desk.write_theme(was_apps, was_system)
        print("   Windows colour mode put back")


if __name__ == "__main__":
    from capture_windows import find_or_build_plantoir_exe
    if len(sys.argv) > 2 and sys.argv[1] == "--retake":
        retake(find_or_build_plantoir_exe(), [tuple(pair.split(":")) for pair in sys.argv[2].split(",")])
    elif len(sys.argv) > 1 and sys.argv[1] == "--how-i-teach":
        capture_how_i_teach()
    elif len(sys.argv) > 1 and sys.argv[1] == "--schedule":
        capture_schedule_notifications(find_or_build_plantoir_exe())
    else:
        capture_app_scenes(find_or_build_plantoir_exe(), sys.argv[1].split(",") if len(sys.argv) > 1 else None)

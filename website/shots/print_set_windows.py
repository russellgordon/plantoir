"""What printing does, photographed on Windows: `capture_windows.py --print-set`.

The Windows twin of capture.py's `capture_print_set` (v1.7.0, DECISIONS 35),
for the two shots whose `capture.scene` is `print-set` in shots.json:

- `preview-page` (`print-page`): a printable maths page as students see it,
  Print button and all, in Windows' light and dark colour modes, saved as
  `print-page-windows-light.png` / `-dark.png`;
- `handout` (`print-handout`, `static`): the handout that button prints, as
  paper, light only, saved as `print-handout-windows.png`.

Both are of a PREVIEW of the MPM2D example course built in a working folder of
its own (`~/Plantoir Print`, made when absent; print_set.py holds the course,
shared with the Mac). The course is made by the branch's own `setup.ps1` and
the preview built by its own `preview.ps1`, NATIVELY, with the bundled runtime
(`windows-app/Vendor/runtime`, or PLANTOIR_RUNTIME), so the triangle diagram
and Latin Modern come from the engines a teacher's copy carries.

The page is photographed the way every Windows class-site shot is
(`hero_windows.capture_page`): an Edge `--app` window, driven over CDP, taken
whole by windowshot. The handout is printed by the page ITSELF in headless
Edge (`handout_pdf.mjs`, the Mac's printer script, run by the runtime's Node),
and the PDF is shown in an Edge `--app` window and taken the same way, so both
are whole window captures with their own corners. Every picture is then read
back with Windows' own text recognition (`windowshot --ocr`) and must show
`shots.json -> expectText`, as the Mac's must show it to Vision.

The photographs need a desktop someone could see: Windows.Graphics.Capture
sends no frame for a window on a locked or disconnected session (measured
2026-10-15: "the window sent no frame in 3 seconds"). Everything before the
shutter -- the course, the preview, the handout's PDF -- runs without one, and
the run says so and stops at the first photograph when the desktop is locked.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
WEBSITE = REPO / "website"
IMAGE_DIR = REPO / "site" / "img"
SCRATCH = Path(os.environ.get("TEMP", "C:/temp")) / "plantoir-marketing-shots"
PARTS = SCRATCH / "parts-print-windows"

sys.path.insert(0, str(HERE))
import print_set  # noqa: E402
from print_set import PRINT_CODE  # noqa: E402

PRINT_FOLDER = Path.home() / "Plantoir Print"
RUNTIME = REPO / "windows-app" / "Vendor" / "runtime"

# The launchers a Windows working folder holds (ToolchainMirror.Launchers),
# and the recipe's root files beside its folders in `.toolchain/`
# (ToolchainMirror.RecipeRootFiles; the FOLDERS come from the contract).
LAUNCHERS = ["setup.ps1", "preview.ps1", "deploy.ps1", "setup.bat", "preview.bat", "deploy.bat"]
RECIPE_ROOT_FILES = ["Dockerfile", "setup.sh", "preview.sh", "deploy.sh", *LAUNCHERS]

# The mac's page window is 1280 x 860 points and its handout window 680 x 880
# (capture.py): the same sizes in DIPs here, so the two platforms' pictures
# frame the same page.
PAGE_SIZE_DIP = (1280, 860)
HANDOUT_SIZE_DIP = (680, 880)


def announce(message: str) -> None:
    print(f"\n▶︎ {message}", flush=True)


def runtime() -> Path:
    named = os.environ.get("PLANTOIR_RUNTIME", "")
    found = Path(named) if named else RUNTIME
    if not (found / "manifest.json").exists():
        raise SystemExit(f"No bundled runtime at {found}: run windows-app/Vendor/fetch-runtime.ps1, "
                         "or set PLANTOIR_RUNTIME.")
    return found


def launcher_environment() -> dict:
    environment = dict(os.environ)
    environment["PLANTOIR_RUNTIME"] = str(runtime())
    return environment


def shots_of_kind(kind: str) -> list[dict]:
    """The print set's shots of `kind`: scene `print-set` only. Other
    `preview-page` shots are pages of other previews — the Code page's
    figures (#562, scene `code`) are ICS3U's and ICS4U's, the Quizzes
    page's (#587, scene `quizzes`) the demo courses' too, which MPM2D's
    preview would answer with a 404. Windows takes those with
    `capture_windows.py --code` / `--quizzes` (preview_pages_windows.py)."""
    manifest = json.loads((WEBSITE / "shots.json").read_text(encoding="utf-8"))
    wanted = []
    for shot in manifest["shots"]:
        capture = shot.get("capture", {})
        if capture.get("kind") == kind and capture.get("scene") == "print-set":
            wanted.append(shot)
    return wanted


def recipe_folders() -> list[str]:
    contract = json.loads((REPO / "contracts" / "toolchain.json").read_text(encoding="utf-8"))
    return list(contract["recipeFolders"]["folders"])


def mirror_toolchain(folder: Path, source: Path = REPO) -> None:
    """What the app does to a folder it touches: the launchers at the top,
    the recipe in `.toolchain/`, both from THIS tree (or `source`, the
    tree's committed files, for the preview pictures), so the pictures are
    of the branch being released and not of whatever app is installed."""
    (folder / "courses").mkdir(parents=True, exist_ok=True)
    for name in LAUNCHERS:
        shutil.copy2(source / name, folder / name)
    toolchain = folder / ".toolchain"
    toolchain.mkdir(parents=True, exist_ok=True)
    for name in RECIPE_ROOT_FILES:
        if (source / name).exists():
            shutil.copy2(source / name, toolchain / name)
    for name in recipe_folders():
        shutil.rmtree(toolchain / name, ignore_errors=True)
        shutil.copytree(source / name, toolchain / name)
    print(f"   Mirrored the launchers and the build recipe into {folder}")


def powershell(script: str, *arguments: str) -> list[str]:
    return ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, *arguments]


def provision(folder: Path) -> None:
    """Make MPM2D from its example content, unless it is there: setup.ps1,
    answered the way the app's New Course panel answers it -- Return at every
    question, the course code where it is asked for. A payload page changed
    since reaches the folder only when it is made again: delete the folder."""
    mirror_toolchain(folder)
    course = folder / "courses" / PRINT_CODE
    if (course / "course_config.json").exists() and (course / "Exercises").is_dir():
        print(f"   {PRINT_CODE} is already there.")
        return
    print_set.write_course_config(course)
    print(f"   Making {PRINT_CODE} from its example content…")
    # Through PtyDriver, the ConPTY host the app's own launcher runs use
    # (documentation/12-windows-app.md): the colour-scheme picker reads keys
    # from the CONSOLE (msvcrt), so a pipe answers every question but that one
    # and the run waits for ever (measured 2026-10-15). `q` there keeps the
    # scheme course_config.json already names.
    driver = pty_driver()
    log = SCRATCH / "print-set-setup.log"
    SCRATCH.mkdir(parents=True, exist_ok=True)
    rules = [f"Enter the course code=>{PRINT_CODE}", "Press 'q' to keep previous choice=>{Q}", r"[:?\])]$=>{ENTER}"]
    command = [str(driver), "--cwd", str(folder), "--raw-log", str(log), "--settle", "800", "--timeout", "1200"]
    for rule in rules:
        command += ["--rule", rule]
    command += ["--", *powershell("setup.ps1")]
    # PtyDriver captures nothing when its own output is redirected
    # (verify-deploy.ps1 says why), so it gets a hidden console of its own.
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    result = subprocess.run(command, cwd=folder, env=launcher_environment(), startupinfo=startup,
                            creationflags=subprocess.CREATE_NEW_CONSOLE, timeout=1500)
    said = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
    if result.returncode != 0 or not (course / "Exercises").is_dir():
        print(said[-3000:], file=sys.stderr)
        raise SystemExit(f"setup.ps1 did not make {PRINT_CODE} in {folder}.")
    print(f"   Made {PRINT_CODE} ({said.count('# reply :')} question(s) answered).")


def pty_driver() -> Path:
    """windows-app/PtyDriver, built when it is missing (verify-deploy.ps1 builds
    it the same way)."""
    project = REPO / "windows-app" / "PtyDriver" / "PtyDriver.csproj"
    exe = REPO / "windows-app" / "PtyDriver" / "bin" / "Debug" / "net9.0" / "PtyDriver.exe"
    if not exe.exists():
        print("   building PtyDriver")
        built = subprocess.run(["dotnet", "build", str(project), "-c", "Debug", "--nologo"], capture_output=True, text=True)
        if built.returncode != 0 or not exe.exists():
            raise SystemExit("PtyDriver did not build:\n" + built.stdout[-2000:])
    return exe


class Preview:
    """`preview.ps1 <code> <section> --non-interactive` (MPM2D 1 for the
    print set), stopped with the launcher's own `--stop` whatever happens."""

    def __init__(self, folder: Path, code: str = PRINT_CODE, section: int = 1):
        self.folder = folder
        self.code = code
        self.section = str(section)
        self.process: subprocess.Popen | None = None
        self.address = ""
        self.lines: list[str] = []

    def __enter__(self) -> "Preview":
        announce(f"Building and serving the preview of {self.code}")
        self.process = subprocess.Popen(powershell("preview.ps1", self.code, self.section, "--non-interactive"),
                                        cwd=self.folder, env=launcher_environment(),
                                        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        started = False
        for line in self.process.stdout:
            self.lines.append(line)
            if "Preview will be available at:" in line:
                self.address = line.split("at:", 1)[1].strip().rstrip("/")
            if "Started a Quartz server" in line:
                started = True
                break
        if not (started and self.address):
            print("".join(self.lines[-40:]), file=sys.stderr)
            raise SystemExit(f"The preview of {self.code} did not start.")
        # Keep reading, so a full pipe never stalls the server.
        threading.Thread(target=lambda: [None for _ in self.process.stdout], daemon=True).start()
        print(f"   The preview is at {self.address}")
        return self

    def __exit__(self, *_) -> None:
        subprocess.run(powershell("preview.ps1", self.code, self.section, "--stop"), cwd=self.folder,
                       env=launcher_environment(), capture_output=True)
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
        print("   The preview is stopped.")


def node_command() -> list[str]:
    """The runtime's Node. handout_pdf.mjs speaks to the browser with Node's
    own WebSocket, global from Node 22; the runtime carries Node 20 (Quartz
    v4.5.0's known-good line), where the same class is behind a flag."""
    node = runtime() / "node" / "node.exe"
    version = subprocess.run([str(node), "--version"], capture_output=True, text=True).stdout.strip()
    major = int(version.lstrip("v").split(".")[0]) if version else 0
    return [str(node), *(["--experimental-websocket"] if major < 22 else [])]


def print_handout(address: str, shot: dict) -> Path:
    """The handout, printed by the page itself in headless Edge (no window,
    so a locked desktop does not matter here)."""
    from hero_windows import EDGE_EXE
    capture = shot["capture"]
    SCRATCH.mkdir(parents=True, exist_ok=True)
    pdf = SCRATCH / f"{shot['id']}-windows.pdf"
    if pdf.exists():
        pdf.unlink()
    result = subprocess.run([*node_command(), str(HERE / "handout_pdf.mjs"), str(EDGE_EXE), address + capture["path"],
                             str(pdf), capture.get("mode", "questionsOnly"), capture.get("paper", "portrait")],
                            capture_output=True, text=True, encoding="utf-8", errors="replace")
    print(f"   {result.stdout.strip()}")
    if result.returncode != 0 or not pdf.exists():
        print(result.stderr[-1500:], file=sys.stderr)
        raise SystemExit(f"The handout of {capture['path']} was not printed.")
    return pdf


def recognised_text(picture: Path) -> str:
    from hero_windows import windowshot_exe
    result = subprocess.run([str(windowshot_exe()), "--ocr", str(picture)], capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise SystemExit(f"Text recognition failed on {picture.name}: {result.stderr.strip()}")
    return result.stdout


def must_show(picture: Path, shot: dict) -> None:
    """`expectText`, read back off the picture by Windows' own OCR, compared
    without case or spaces (as scenes.missing_words compares Vision's)."""
    seen = "".join(recognised_text(picture).split()).lower()
    missing = [word for word in shot.get("expectText", []) if "".join(word.split()).lower() not in seen]
    if missing:
        # Read again from a copy three times the size, for READING only (the
        # picture is not changed): Windows' recogniser misses lettering about
        # 10 px high, which is what the handout's footer is when the page
        # must fit a 1080-pixel screen (measured 2026-10-15: "Page 1 of 1"
        # not read at all at 1x, "Page I (f I" at 2x, exact at 3x).
        from PIL import Image
        larger = PARTS / f"reading-{picture.name}"
        with Image.open(picture) as opened:
            opened.convert("RGB").resize((opened.width * 3, opened.height * 3), Image.BICUBIC).save(larger)
        try:
            seen += "".join(recognised_text(larger).split()).lower()
        finally:
            larger.unlink(missing_ok=True)
        missing = [word for word in missing if "".join(word.split()).lower() not in seen]
    if missing:
        raise SystemExit(f"{picture.name} does not show {', '.join(missing)}. Nothing past this point was taken.")
    print(f"   {picture.name} shows {', '.join(shot.get('expectText', []))}")


def desktop_is_locked() -> bool:
    """True when nobody could see a window: the input desktop is not the
    user's (Winlogon, on a locked PC) or the session is disconnected."""
    import ctypes
    user32 = ctypes.windll.user32
    desktop = user32.OpenInputDesktop(0, False, 0x0100)  # DESKTOP_SWITCHDESKTOP
    if not desktop:
        return True
    try:
        return not user32.SwitchDesktop(desktop)
    finally:
        user32.CloseDesktop(desktop)


def photograph_pdf(pdf: Path, destination: Path) -> Path:
    """The PDF in an Edge `--app` window with the viewer's toolbar off: the
    page on the viewer's own background, as the Mac's handout window shows it."""
    from hero_windows import (device_scale_flags, edge_window, fitted_scale, launch_edge, photograph,
                              place_visible, stop_matching, work_area, EDGE_PROFILE)
    left, top, _, _ = work_area()
    scale = fitted_scale(HANDOUT_SIZE_DIP)
    width, height = round(HANDOUT_SIZE_DIP[0] * scale), round(HANDOUT_SIZE_DIP[1] * scale)
    x, y = left + 20, top + 20
    # `view=Fit`, the whole page: FitH filled the width and left the footer
    # (Page 1 of 1, which expectText asks for) below the window's edge
    # (measured 2026-10-15, the first unlocked run).
    process = launch_edge([f"--app={pdf.resolve().as_uri()}#toolbar=0&view=Fit"], x, y, width, height,
                          flags=device_scale_flags(scale))
    try:
        hwnd = edge_window(process, "")
        place_visible(hwnd, x, y, width, height)   # the frame seen, not the border round it (#544)
        time.sleep(4.0)   # the viewer draws the page after the window appears
        place_visible(hwnd, x, y, width, height)
        return photograph(hwnd, destination)
    finally:
        stop_matching("msedge.exe", str(EDGE_PROFILE))


def promote(identifiers: list[str]) -> None:
    """A shot whose Windows pictures were all taken and read back is marked
    `windows: true`, so build.py offers them (the Mac's `promote` does the
    same for `awaiting_capture`)."""
    path = WEBSITE / "shots.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    changed = []
    for shot in manifest["shots"]:
        if shot["id"] in identifiers and shot.get("windows") is not True:
            shot["windows"] = True
            changed.append(shot["id"])
    if changed:
        path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"   shots.json — windows: true for {', '.join(changed)}")
        print("   Take them off WINDOWS_PICTURE_OWED in website/test_build_data.py, which pins them false "
              "until now.")


def at_the_top(page) -> None:
    """The page from its top, where the title and the Print button are.
    Quartz scrolls a page about 300 px down on load to bring its place in
    the sidebar into view (measured here 2026-10-15, as on the Mac, whose
    capture scrolls back the same way), which leaves the button above the
    window."""
    page.evaluate("window.scrollTo(0, 0); document.activeElement && document.activeElement.blur()")
    time.sleep(0.5)
    page.evaluate("window.scrollTo(0, 0)")


def capture_print_set(folder: Path = PRINT_FOLDER) -> None:
    from hero_windows import capture_page, make_dpi_aware, read_theme, write_theme
    from images import prepare
    page_shots = shots_of_kind("preview-page")
    handout_shots = shots_of_kind("handout")
    announce(f"Photographing what printing does, in {folder}")
    make_dpi_aware()
    PARTS.mkdir(parents=True, exist_ok=True)
    provision(folder)
    taken: list[str] = []
    with Preview(folder) as preview:
        handouts = {shot["id"]: print_handout(preview.address, shot) for shot in handout_shots}
        if desktop_is_locked():
            raise SystemExit("The desktop is locked, so no window can be photographed: the course, the preview "
                             "and the handout's PDF are done, the pictures are not. Unlock it and run again.")
        was_apps, was_system = read_theme()
        try:
            for shot in page_shots:
                url = preview.address + shot["capture"]["path"]
                for theme in ("light", "dark"):
                    write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)
                    announce(f"{shot['id']}, {theme}")
                    part = PARTS / f"{shot['id']}-windows-{theme}.png"
                    capture_page(url, "", part, size_dip=PAGE_SIZE_DIP, prepare_page=at_the_top, fit=True)
                    must_show(part, shot)
                    destination = IMAGE_DIR / part.name
                    shutil.copyfile(part, destination)
                    prepare(destination)   # never scaled: 2x, like the mac's (#544)
                    print(f"   saved {destination.name} + WebP")
                taken.append(shot["id"])
            write_theme(1, 1)   # paper is light
            for shot in handout_shots:
                announce(f"{shot['id']}, the handout as paper")
                part = PARTS / f"{shot['id']}-windows.png"
                photograph_pdf(handouts[shot["id"]], part)
                must_show(part, shot)
                destination = IMAGE_DIR / part.name
                shutil.copyfile(part, destination)
                prepare(destination)   # never scaled: 2x, like the mac's (#544)
                print(f"   saved {destination.name} + WebP")
                taken.append(shot["id"])
        finally:
            write_theme(was_apps, was_system)
            print("   Windows colour mode put back")
    promote(taken)

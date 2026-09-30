#!/usr/bin/env python3
"""Take every screenshot plantoir.app uses, without anyone touching a mouse.

Run it from the top of the repository::

    python3 website/shots/capture.py            # everything
    python3 website/shots/capture.py --app      # just the app windows
    python3 website/shots/capture.py --sites    # just the class websites

    # The v1.4.0 scenes, in the kept marketing folder (~/Plantoir Marketing):
    python3 website/shots/capture.py --provision          # make or reuse the folder
    python3 website/shots/capture.py --scenes             # all eleven scenes
    python3 website/shots/capture.py --only reference     # one scene (or several, a,b)
    python3 website/shots/capture.py --dry-run            # prove every scene can be set up

See website/README.md, "Regenerating every image", and scenes.py.

What it does, in order:

1. **Provisions a demo working folder** (``~/Desktop/Teaching`` by default,
   ``--provision-demo``) by driving the app's own new-course panel for ENG2D,
   MCV4U and SCH3U -- three subjects chosen so the class sites between them
   show prose, typeset mathematics and chemistry. Skipped when the courses are
   already there. (Until v1.4.0 this step only wrote launchers and site
   markers and never ran the course-making test, although this docstring said
   it did; it runs it now.)
2. **Builds and publishes** each of those sections, so the address bar in a
   screenshot reads like a real class site rather than like localhost.
3. **Photographs the app** by running the marketing UI tests, once with the
   Mac in light appearance and once in dark.
4. **Photographs the class sites** in Safari, and on an iPhone in the
   Simulator, again in both appearances.
5. **Rebuilds the site** so the new images are in the pages.

Everything it borrows, it puts back: the Mac's appearance, the app's
remembered window size, the frontmost application, and any Safari window it
opened. It also holds off sleep while it runs, so a capture started at night
survives the displays going dark -- though the Mac itself must stay awake and
unlocked.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from appearance import Appearance          # noqa: E402
from images import (  # noqa: E402
    prepare,
    WIDEST_PHONE_PIXELS,
    WIDEST_WINDOW_PIXELS,
)
from composite import fan, side_by_side, diagonal_hero, FIGURE_WIDTH    # noqa: E402
from corners import corner_problems, images_the_pages_show  # noqa: E402
from safari import SafariWindow, verify_appearance, verify_address_bar  # noqa: E402
import scenes as scene_book  # noqa: E402

REPO = Path(__file__).resolve().parent.parent.parent
WEBSITE = REPO / "website"
IMAGE_DIR = REPO / "site" / "img"
SCRATCH = Path(os.environ.get("TMPDIR", "/tmp")) / "plantoir-marketing-shots"

MAC_APP = REPO / "mac-app"
APP_BUNDLE_DEFAULTS_DOMAIN = "ca.russellgordon.Plantoir"

# The Debug build wears the "BETA" ribbon icon so Russell can tell it from the
# released app in his Dock (mac-app/project.yml). The screenshots are taken
# from a Debug build and the notification banner shows the app icon, so every
# build this script starts names the plain icon instead. The side effect is
# that the Dock's Debug bundle is ribbonless after a capture run until the
# next ordinary build. A notification-only run starts NO build (with
# --skip-preflight), so the banner scene reads the bundle's own icon name
# first — see bundle_icon_name() — rather than trusting which path built it.
PLAIN_APP_ICON = "ASSETCATALOG_COMPILER_APPICON_NAME=Plantoir"

# ~/Desktop/Teaching, not ~/Teaching: the plain ~/Teaching folder on this
# Mac now holds REAL courses (ADA1O, MCR3U), and a default pointing there
# would provision demo courses into a teacher's actual working folder.
DEFAULT_WORKSPACE = Path.home() / "Desktop" / "Teaching"

# The kept marketing folder the v1.4.0 scenes are taken in (marketing_folder.py).
MARKETING_FOLDER = Path.home() / "Plantoir Marketing"

# The courses the marketing shots are taken from, and the Netlify site each is
# published to. The naming scheme is per-SECTION — <code>-s<n>-2026-gordon —
# matching the sites Russell redeployed on 2026-08-19; the browser and phone
# shots use each course's section 1. The authoritative record is the working
# folder itself: courses/<CODE>/.netlify_sites/section<n>.json.
DEMO_COURSES = [
    {"code": "ENG2D", "site": "eng2d-s1-2026-gordon"},
    {"code": "MCV4U", "site": "mcv4u-s1-2026-gordon"},
    {"code": "SCH3U", "site": "sch3u-s1-2026-gordon"},
]

# The simulator used for the phone shot, and the RocketSim helper that draws
# the device around it. "iPhone 17 Pro" because the plain iPhone 17 simulator
# no longer exists on this Mac (device lists change with Xcode updates), and
# simulator_udid() exits when the name matches nothing.
SIMULATOR_DEVICE = "iPhone 17 Pro"
ROCKETSIM = Path("/Applications/RocketSim.app/Contents/Helpers/rocketsim")

# Window frames the app remembers between launches. The UI tests override them
# for the duration of a capture; these are saved and put back afterwards so a
# capture run does not resize the windows somebody was working in.
REMEMBERED_FRAME_KEYS = [
    "NSWindow Frame SwiftUI.ModifiedContent<QuartzTeachers.WindowRootView, "
    "SwiftUI._FlexFrameLayout>-1-AppWindow-1",
    # The assistant keeps its own frame under its own key rather than an
    # autosave name — SwiftUI owns the autosave name for that window and
    # overwrites anything put there.
    "AssistantWindowFrame-ENG2D-1",
]

# Where the assistant window should sit for its portrait. Written into the
# app's own preference before the run and put back afterwards, because a
# launch argument does not reliably win against a value the app applies by
# hand after the window is shown.
ASSISTANT_FRAME = "{{500, 60}, {560, 760}}"

# The assistant photograph is of the "Shall I go ahead?" card — but that card
# only appears when plan mode is on, and plan mode follows a Settings toggle
# the developer's own Mac may have turned OFF. With it off the assistant
# CARRIES OUT the request instead: the capture then shows "Unpublished 1
# page.", and the demo course really has a page hidden in it afterwards. So
# the setting is staged on for the run and put back, exactly like the window
# frames. (The Windows capture harness has the same dependency if it ever
# photographs an approval card — its app keeps an equivalent setting.)
ASSISTANT_ASKS_KEY = "assistantAsksBeforeChanging"

# ---------- Running things ----------

def announce(message: str) -> None:
    print(f"\n▶︎ {message}", flush=True)


def run(command: list[str], **keywords) -> subprocess.CompletedProcess:
    print(f"   $ {' '.join(str(part) for part in command)}", flush=True)
    return subprocess.run(command, **keywords)


def stay_awake() -> subprocess.Popen:
    """Hold off sleep -- including display sleep, which is what triggers the
    screen lock that would otherwise break a capture running overnight."""
    return subprocess.Popen(["caffeinate", "-disu", "-w", str(os.getpid())])


# ---------- The app's remembered window sizes ----------

def read_defaults(key: str) -> str | None:
    result = subprocess.run(
        ["defaults", "read", APP_BUNDLE_DEFAULTS_DOMAIN, key],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.rstrip("\n")


def write_defaults(key: str, value: str | None) -> None:
    if value is None:
        subprocess.run(
            ["defaults", "delete", APP_BUNDLE_DEFAULTS_DOMAIN, key],
            capture_output=True,
        )
        return
    # -string is not optional. A frame is written "{{500, 40}, {560, 940}}",
    # and to `defaults` those braces are old-style plist syntax: it tries to
    # parse the value as a DICTIONARY, fails with "Could not parse", writes
    # nothing, and exits without anybody noticing. The assistant window then
    # opened at its default size in every capture, which is why it kept coming
    # back too wide to hold the conversation.
    result = subprocess.run(
        ["defaults", "write", APP_BUNDLE_DEFAULTS_DOMAIN, key, "-string", value],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"   Could not set {key}: {result.stderr.strip()}", file=sys.stderr)


class RememberedWindowFrames:
    """Puts back whatever window sizes and settings the app had before the capture."""

    def __enter__(self) -> "RememberedWindowFrames":
        self.saved: dict[str, str | None] = {}
        for key in REMEMBERED_FRAME_KEYS + [ASSISTANT_ASKS_KEY]:
            self.saved[key] = read_defaults(key)
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> bool:
        for key, value in self.saved.items():
            write_defaults(key, value)
        return False

    def stage_assistant_frame(self) -> None:
        """Put the assistant window where its portrait wants it, and check.

        The app applies this frame by hand when the window appears, so a value
        that never landed shows up only as a badly proportioned screenshot half
        an hour later. Reading it back costs nothing.
        """
        write_defaults("AssistantWindowFrame-ENG2D-1", ASSISTANT_FRAME)
        written = read_defaults("AssistantWindowFrame-ENG2D-1")
        if written != ASSISTANT_FRAME:
            print(f"   The assistant window frame did not take: wanted {ASSISTANT_FRAME}, "
                  f"got {written!r}", file=sys.stderr)
        else:
            print(f"   Assistant window staged at {ASSISTANT_FRAME}")

        main_key = (
            "NSWindow Frame SwiftUI.ModifiedContent<QuartzTeachers.WindowRootView, "
            "SwiftUI._FlexFrameLayout>-1-AppWindow-1"
        )
        write_defaults(main_key, "40 60 1280 800 0 0 1512 982")

        # Plan mode on, whatever this Mac's own setting is, so the assistant
        # answers with the card the photograph is of. -bool, not -string: the
        # app reads it as a boolean.
        subprocess.run(
            ["defaults", "write", APP_BUNDLE_DEFAULTS_DOMAIN,
             ASSISTANT_ASKS_KEY, "-bool", "true"],
            capture_output=True,
        )
        print("   Plan mode staged on, so the assistant asks before changing anything.")


# ---------- The UI tests ----------

def run_ui_test(test_identifier: str, workspace: Path, label: str,
                allow_failure: bool = False) -> Path:
    """Run one marketing UI test and return its result bundle.

    With ``allow_failure`` the bundle is returned even when a test failed. The
    captures are independent of one another, and a run where the assistant was
    slow to start should still deliver the five shots that did work rather
    than throwing them away with the sixth.
    """
    bundle = SCRATCH / f"{label}.xcresult"
    if bundle.exists():
        shutil.rmtree(bundle)
    bundle.parent.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    # xcodebuild does not hand its own environment to the test runner. A
    # variable named TEST_RUNNER_<NAME> arrives there as <NAME>, which is the
    # documented way in; the unprefixed one is set too, for a test run started
    # by hand from Xcode.
    environment["MARKETING_WORKSPACE"] = str(workspace)
    environment["TEST_RUNNER_MARKETING_WORKSPACE"] = str(workspace)

    # Several identifiers may arrive comma-separated, so a re-shoot of three
    # wrong captures costs one run rather than three preflights and six
    # appearance flips.
    only_flags: list[str] = []
    for identifier in test_identifier.split(","):
        only_flags.append("-only-testing:" + identifier)

    result = run(
        [
            "xcodebuild",
            "-project", str(MAC_APP / "Plantoir.xcodeproj"),
            "-scheme", "Plantoir",
            "-configuration", "Debug",
            PLAIN_APP_ICON,
            "test",
            *only_flags,
            "-resultBundlePath", str(bundle),
        ],
        cwd=MAC_APP,
        env=environment,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        failures = [line for line in result.stdout.splitlines() if " error: " in line]
        for line in failures[:10]:
            print(f"   ✗ {line.strip()}", file=sys.stderr)
        if not failures:
            print("\n".join(result.stdout.splitlines()[-30:]), file=sys.stderr)
        if not allow_failure:
            raise SystemExit(f"The UI test {test_identifier} failed.")
        print(f"   Some captures failed; keeping the ones that worked.", file=sys.stderr)
    return bundle


def export_attachments(bundle: Path, suffix: str, parts: set[str] | None = None,
                       staging: Path | None = None) -> list[str]:
    """Copy a result bundle's screenshots into site/img/<name>-<suffix>.png.

    A name in ``parts`` is a piece of a composite, not a picture a page shows,
    so it goes to the scratch parts folder instead; so does a name starting
    "demo-" (the demo folder's old window shots, kept only as parts). With
    ``staging``, EVERYTHING goes there, to be checked before it is promoted.
    """
    exported = SCRATCH / f"{bundle.stem}-attachments"
    if exported.exists():
        shutil.rmtree(exported)
    run(
        ["xcrun", "xcresulttool", "export", "attachments",
         "--path", str(bundle), "--output-path", str(exported)],
        capture_output=True, check=True,
    )

    manifest_path = exported / "manifest.json"
    if not manifest_path.exists():
        return []

    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    saved: list[str] = []
    with manifest_path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    for entry in manifest:
        for attachment in entry.get("attachments", []):
            readable = attachment.get("suggestedHumanReadableName", "")
            shot_name = readable.split("_")[0]
            if not shot_name or not readable.endswith(".png"):
                continue
            source = exported / attachment["exportedFileName"]
            destination = IMAGE_DIR / f"{shot_name}-{suffix}.png"
            if (parts and shot_name in parts) or shot_name.startswith("demo-"):
                PARTS.mkdir(parents=True, exist_ok=True)
                destination = PARTS / f"{shot_name}-{suffix}.png"
            if staging is not None:
                staging.mkdir(parents=True, exist_ok=True)
                destination = staging / f"{shot_name}-{suffix}.png"
            shutil.copy2(source, destination)
            # No corner masking: the attachment came from `screencapture -l`,
            # which hands back the real curve with the corners already
            # transparent. See the note at the top of images.py.
            if staging is None and destination.parent == IMAGE_DIR:
                prepare(destination, WIDEST_WINDOW_PIXELS)
            saved.append(destination.name)
    return saved


# ---------- Provisioning and publishing ----------

def app_bundle_resources() -> Path:
    """The Resources folder of the Debug build the UI tests run against.

    That is the build of THIS checkout's project, found by the WorkspacePath
    DerivedData records for it. It used to be whichever Plantoir-* folder
    sorted last, and on a Mac with several clones that was a two-day-old
    bundle from another one — launchers and a build recipe the app under
    test did not carry.
    """
    import plistlib
    project = (MAC_APP / "Plantoir.xcodeproj").resolve()
    for derived in sorted((Path.home() / "Library/Developer/Xcode/DerivedData").glob("Plantoir-*")):
        try:
            with (derived / "info.plist").open("rb") as handle:
                recorded = plistlib.load(handle).get("WorkspacePath", "")
        except (OSError, plistlib.InvalidFileException):
            continue
        if not recorded or Path(recorded).resolve() != project:
            continue
        resources = derived / "Build/Products/Debug/Plantoir.app/Contents/Resources"
        if resources.is_dir():
            return resources
    raise SystemExit(
        f"No built Plantoir.app found for {project}. Build it first:\n"
        "  cd mac-app && xcodebuild -project Plantoir.xcodeproj -scheme Plantoir "
        "-configuration Debug build"
    )


def _recipe_folders() -> list:
    """
    The toolchain recipe's folders, from the contract rather than a fourth copy.

    Raises rather than guessing: a wrong answer here stages a demo workspace
    whose Dockerfile COPYs a folder that is not present, which fails the build
    outright and cannot produce preview.sh's friendly "missing the build recipe"
    message, because the Dockerfile IS there.
    """
    import json
    for parent in Path(__file__).resolve().parents:
        candidate = parent / "contracts" / "toolchain.json"
        if candidate.is_file():
            data = json.loads(candidate.read_text(encoding="utf-8"))
            folders = data.get("recipeFolders", {}).get("folders")
            if folders:
                return list(folders)
            break
    raise RuntimeError(
        "Cannot read contracts/toolchain.json -> recipeFolders, which is the "
        "one home for the toolchain recipe's folder list."
    )


def mirror_toolchain(workspace: Path) -> None:
    """Put the app's build recipe into the demo folder's `.toolchain/`.

    The app does this itself whenever it touches a working folder — except
    under a UI test, where it deliberately leaves the folder alone so test
    fixtures can keep their stub launchers. The demo folder is a real folder
    being driven by a UI test, so it falls in the gap: without this, creating
    a course fails with "this folder is missing the toolchain's build recipe",
    and the test then waits half an hour for a course that will never appear.

    The FOLDER list is not held here: it is read from
    `contracts/toolchain.json` -> recipeFolders, the same data
    `WorkspaceModel.refreshToolchain` and Windows' `ToolchainMirror` are pinned
    against. This used to be a fourth hand-maintained copy, with a comment
    telling the next person to keep it in step, and it was the one that did
    not — a `.toolchain/` holding the new Dockerfile without the folder that
    Dockerfile COPYs is not stale, it is UNBUILDABLE.
    """
    resources = app_bundle_resources()
    toolchain = workspace / ".toolchain"
    toolchain.mkdir(parents=True, exist_ok=True)

    root_files = [
        "Dockerfile",
        "setup.sh", "preview.sh", "deploy.sh",
        "setup.bat", "preview.bat", "deploy.bat",
        "setup.ps1", "preview.ps1", "deploy.ps1",
    ]
    for name in root_files:
        source = resources / name
        if source.exists():
            shutil.copy2(source, toolchain / name)

    for folder in _recipe_folders():
        source = resources / folder
        if not source.exists():
            # Skipping is what made the ORIGINAL failure possible: the
            # Dockerfile is copied unconditionally above, so a recipe folder
            # missing here stages a workspace whose Dockerfile COPYs something
            # that is not there — an unbuildable folder, not a stale one, and
            # preview.sh cannot say so because the Dockerfile IS present.
            # app_bundle_resources() takes the NEWEST DerivedData bundle, so
            # this fires when the app was last built before the folder existed.
            raise RuntimeError(
                f"The app bundle has no '{folder}' folder, which "
                f"contracts/toolchain.json lists as part of the toolchain "
                f"recipe. Rebuild the mac app before capturing: staging a "
                f".toolchain/ without it produces a workspace that cannot "
                f"build at all."
            )
        subprocess.run(
            ["rsync", "-a", "--delete", f"{source}/", str(toolchain / folder) + "/"],
            check=True,
        )
    print(f"   Mirrored the build recipe into {toolchain}")


def workspace_has_course(workspace: Path, code: str) -> bool:
    return (workspace / "courses" / code / "course_config.json").exists()


def ensure_launchers(workspace: Path) -> None:
    """A brand-new folder needs the three launchers before anything else —
    and a `courses/` folder. The app reads a folder with launchers and no
    `courses/` as a problem ("There are no courses in this folder yet") and
    keeps the folder picker up, so the new-course button a provisioning test
    clicks is never shown; that is how the first marketing set-up failed."""
    (workspace / "courses").mkdir(parents=True, exist_ok=True)
    resources = app_bundle_resources()
    for name in ["setup.sh", "preview.sh", "deploy.sh"]:
        destination = workspace / name
        source = resources / name
        if source.exists():
            shutil.copy2(source, destination)
            destination.chmod(0o755)


def provision(workspace: Path) -> None:
    """The demo folder (hero and class-site shots): launchers, the build
    recipe, the three courses THROUGH THE APP, and the live sites' markers.

    Idempotent: a course already there is not made again (the UI test skips
    it), and a marker already there is not rewritten.
    """
    announce(f"Provisioning the demo courses in {workspace}")
    workspace.mkdir(parents=True, exist_ok=True)
    ensure_launchers(workspace)
    mirror_toolchain(workspace)

    missing: list[str] = []
    for course in DEMO_COURSES:
        if not workspace_has_course(workspace, course["code"]):
            missing.append(course["code"])
    if missing:
        print(f"   Making {', '.join(missing)} through the app's own new-course panel…")
        run_ui_test("QuartzTeachersUITests/DemoWorkspaceProvisioning/testCreateDemoCourses",
                    workspace, "provision-demo")
    else:
        print("   ENG2D, MCV4U and SCH3U are already there.")

    for course in DEMO_COURSES:
        marker_dir = workspace / "courses" / course["code"] / ".netlify_sites"
        marker_dir.mkdir(parents=True, exist_ok=True)
        marker_path = marker_dir / "section1.json"
        if not marker_path.exists():
            marker_path.write_text(json.dumps({
                "id": f"demo-{course['code'].lower()}-s1",
                "name": course["site"],
                "url": f"https://{course['site']}.netlify.app"
            }, indent=2), encoding="utf-8")


def build_section(workspace: Path, code: str) -> None:
    """Build a section's site, which is what publishing needs.

    ``--build-only`` writes the pages without then serving them, so this can
    wait for the command to finish rather than watching for files to appear.
    """
    built = workspace / "courses" / code / ".merged_output" / "section1" / "public" / "index.html"
    if built.exists():
        print(f"   {code} is already built.")
        return

    print(f"   Building {code} — the first one also builds the site builder…")
    result = subprocess.run(
        ["./preview.sh", code, "1", "--build-only"],
        cwd=workspace,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=3600,
    )
    if result.returncode != 0 or not built.exists():
        print("\n".join(result.stdout.splitlines()[-30:]), file=sys.stderr)
        raise SystemExit(f"{code} did not build; nothing to publish.")


def remember_teacher_name(workspace: Path, last_name: str = "gordon") -> None:
    """Answer the one question a first publish asks about the teacher.

    Publishing asks for a last name once per working folder, to suggest a site
    name from it. Writing the answer straight into the profile it would save
    means the only thing left on the prompt queue is the site name — and a
    queue of answers that can slip by one is a queue that names a site after
    the wrong prompt.
    """
    profile = workspace / "courses" / ".internal" / "profile.json"
    if profile.exists():
        return
    profile.parent.mkdir(parents=True, exist_ok=True)
    profile.write_text(json.dumps({"teacher_last_name": last_name}, indent=2), encoding="utf-8")
    profile.chmod(0o600)


def publish_section(workspace: Path, code: str, site_name: str) -> None:
    print(f"   Publishing {code} to {site_name}.netlify.app…")
    answers = f"{site_name}\n\n\n\n"
    result = subprocess.run(
        ["./deploy.sh", code, "1"],
        cwd=workspace,
        input=answers,
        capture_output=True,
        text=True,
    )
    print("\n".join(result.stdout.splitlines()[-15:]))
    if result.returncode != 0:
        raise SystemExit(f"Publishing {code} failed.")


def publish_demo_sites(workspace: Path) -> None:
    announce("Building and publishing the demo class sites")
    mirror_toolchain(workspace)
    remember_teacher_name(workspace)
    for course in DEMO_COURSES:
        build_section(workspace, course["code"])
        publish_section(workspace, course["code"], course["site"])


# ---------- Capturing ----------

def clear_built_site(workspace: Path, code: str, section: int) -> None:
    """Throw away one section's built pages, so previewing it really builds.

    The progress capture needs a build that takes long enough to photograph.
    Quartz serves the PREVIOUS build the moment the container is up, so a
    section that has been previewed before comes back almost at once — the
    first two attempts at this photographed the finished site and filed it as
    progress. Deleting the output is what makes the picture honest.
    """
    built = workspace / "courses" / code / ".merged_output" / f"section{section}"
    if built.exists():
        shutil.rmtree(built)
        print(f"   Cleared the built pages for {code} section {section}, so its preview really builds.")


def kill_orphaned_model_servers() -> None:
    """Sweep up assistant model servers whose app has been killed.

    The app spawns the assistant's engine as a child process, and a UI test
    run ends by KILLING the app — so the engine outlives every capture that
    opened the assistant. Each orphan holds gigabytes of memory and a share
    of the GPU, and four of them once slowed the machine enough that
    keystroke synthesis timed out mid-test, which reads as a flaky test
    rather than as a loaded machine. Swept before and after the capture:
    at both moments no app instance is (or is about to stay) running, so
    every engine from the app bundle is an orphan by definition.
    """
    # Only engines from THIS checkout's build, and only orphans (parent 1).
    # The sweep used to `pkill -f Resources/llama/llama-server`, which on a
    # Mac where other sessions run UI tests from their own clones killed
    # THEIR engines too (2026-09-27: one from ~/plantoir-r mid-run).
    try:
        ours = str(app_bundle_resources() / "llama" / "llama-server")
    except SystemExit:
        return
    listing = subprocess.run(["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True).stdout
    for line in listing.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) < 3:
            continue
        pid, ppid, command = parts
        if ppid == "1" and command.startswith(ours):
            subprocess.run(["kill", pid], capture_output=True)


class KeyboardNavigationOff:
    """Keyboard navigation off for the run, put back afterwards.

    With it on (System Settings › Keyboard › Keyboard navigation, the global
    `AppleKeyboardUIMode` 2), every sheet opens with a focus ring round its
    first control — the start-of-year plan's first list, in the 2026-09-27
    capture. Most teachers have it off, so the pictures should too. Passing
    `-AppleKeyboardUIMode 0` to the app under test was tried first and did
    not take: AppKit reads it from the global domain. So the global value is
    borrowed and restored exactly — including its absence (CLAUDE.md rule 9).
    """

    def __enter__(self) -> "KeyboardNavigationOff":
        read = subprocess.run(["defaults", "read", "-g", "AppleKeyboardUIMode"], capture_output=True, text=True)
        self.saved: str | None = read.stdout.strip() if read.returncode == 0 else None
        # A run ended by SIGTERM or SIGHUP (a closed terminal, a killed
        # shell) would skip __exit__: Python has no handler for either, so
        # turn both into SystemExit and the `with` unwinds as for Ctrl-C.
        import signal
        self.previous_handlers: dict = {}
        for number in (signal.SIGTERM, signal.SIGHUP):
            self.previous_handlers[number] = signal.signal(number, KeyboardNavigationOff.exit_on_signal)
        if self.saved not in (None, "0"):
            subprocess.run(["defaults", "write", "-g", "AppleKeyboardUIMode", "-int", "0"], capture_output=True)
            print(f"   Keyboard navigation off for the run (was {self.saved}; put back afterwards — if this run "
                  f"is killed hard, restore it with: defaults write -g AppleKeyboardUIMode -int {self.saved}).")
        return self

    @staticmethod
    def exit_on_signal(number, frame) -> None:
        raise SystemExit(128 + number)

    def __exit__(self, exc_type, exc_value, traceback) -> bool:
        import signal
        for number, handler in self.previous_handlers.items():
            signal.signal(number, handler)
        if self.saved is None:
            subprocess.run(["defaults", "delete", "-g", "AppleKeyboardUIMode"], capture_output=True)
        elif self.saved != "0":
            subprocess.run(["defaults", "write", "-g", "AppleKeyboardUIMode", "-int", self.saved], capture_output=True)
            print(f"   Keyboard navigation put back ({self.saved}).")
        return False


class BackupsSetAside:
    """Keep the teacher's course backups out of frame, without touching them.

    Backups accumulate whenever the assistant changes a section, and each
    adds a row to the sidebar's Backups group — so the same capture taken a
    week apart would differ by whatever work happened in between, and a
    backup named after a course once made every query for that course
    ambiguous mid-test ("Multiple matching elements found"). The `_backups`
    folder is renamed aside for the run and put back whole afterwards;
    nothing inside it is read, altered, or deleted.
    """

    def __init__(self, workspace: Path) -> None:
        self.backups: Path = workspace / "courses" / "_backups"
        self.aside: Path = workspace / "courses" / "_backups.set-aside-for-capture"

    def __enter__(self) -> "BackupsSetAside":
        if self.backups.exists() and not self.aside.exists():
            self.backups.rename(self.aside)
            print("   Set the course backups aside, so the sidebar photographs the same every run.")
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> bool:
        if self.aside.exists():
            if self.backups.exists():
                # Something recreated _backups mid-run; fold the set-aside
                # contents back in rather than losing either side.
                for course_dir in self.aside.iterdir():
                    target = self.backups / course_dir.name
                    if target.exists():
                        for item in course_dir.iterdir():
                            shutil.move(str(item), str(target / item.name))
                        course_dir.rmdir()
                    else:
                        shutil.move(str(course_dir), str(target))
                self.aside.rmdir()
            else:
                self.aside.rename(self.backups)
            print("   Put the course backups back.")
        return False


def capture_app(workspace: Path, only: str | None = None) -> None:
    """Photograph the app, once per appearance.

    ``only`` names a single test to run — `test6Assistant`, say — so a shot
    that needs another attempt does not cost a re-run of the five that were
    already right.
    """
    announce("Photographing the app")
    kill_orphaned_model_servers()
    remember_teacher_name(workspace)
    target = "QuartzTeachersUITests/MarketingScreenshots"
    if only:
        target = ",".join(f"{target}/{name}" for name in only.split(","))
    with RememberedWindowFrames() as frames, BackupsSetAside(workspace):
        frames.stage_assistant_frame()
        for dark in (False, True):
            # Section 2 ONLY, and per appearance: the progress capture
            # previews section 2, and clearing its output is what makes a
            # real build happen — clearing it only once left the second
            # pass photographing the first pass's finished build as
            # "progress". Section 1 is deliberately NOT cleared: the
            # preview capture photographs the FINISHED site, which the
            # existing build shows identically and minutes sooner — a
            # fresh section 1 build per appearance was most of a run's
            # dead time. (The container is left running for the same
            # reason: a warm section 2 rebuild still holds the progress
            # view up for several seconds, and the 20 Hz poll in the test
            # needs only one of them.)
            clear_built_site(workspace, "ENG2D", 2)
            suffix = "dark" if dark else "light"
            print(f"   {suffix} appearance")
            with Appearance(dark=dark):
                time.sleep(2)
                bundle = run_ui_test(
                    target,
                    workspace,
                    f"app-{suffix}",
                    allow_failure=True,
                )
            saved = export_attachments(bundle, suffix)
            print(f"   saved {len(saved)} image(s): {', '.join(saved)}")
    kill_orphaned_model_servers()


def site_address(code: str) -> str:
    for course in DEMO_COURSES:
        if course["code"] == code:
            return f"https://{course['site']}.netlify.app"
    raise SystemExit(f"No demo site is configured for {code}.")


# Captures that exist only to be assembled into the two static figures. They
# are not referred to by any page, so they live outside site/img/.
PARTS = SCRATCH / "parts"


def capture_parts(suffix: str) -> None:
    """Photograph the three course home pages, for the two colour figures.

    In a plain window with no browser around it (`webwindow.swift`), not in
    Safari: those figures are about the SITES, and three toolbars read as
    three browsers. The window's own edge is the picture's edge, so its real
    corners are kept — never a Safari capture with the toolbar cut off and
    corners painted back on, which is what this used to be.
    """
    PARTS.mkdir(parents=True, exist_ok=True)
    helper = Path(__file__).resolve().parent / "webwindow.swift"
    for course in DEMO_COURSES:
        destination = PARTS / f"home-{course['code'].lower()}-{suffix}.png"
        result = subprocess.run(
            ["swift", str(helper), site_address(course["code"]) + "/", "1280", "860",
             str(destination), "3.5"],
            capture_output=True, text=True,
        )
        if result.returncode != 0 or not destination.exists():
            raise SystemExit(f"Could not photograph {course['code']}'s home page: {result.stderr.strip()}")
        verify_appearance(destination, suffix == "dark", course["code"])
        print(f"   part {destination.name}")


def capture_obsidian(workspace: Path, suffix: str) -> None:
    """Capture Obsidian showing the ENG2D course note."""
    PARTS.mkdir(parents=True, exist_ok=True)
    note_path = workspace / "courses" / "ENG2D" / "section2" / "index.md"
    if not note_path.exists():
        note_path = workspace / "ENG2D" / "section2" / "index.md"

    run(["open", f"obsidian://open?path={note_path}"], capture_output=True)
    time.sleep(2.5)

    script = """
    tell application "Obsidian" to activate
    delay 0.4
    tell application "System Events"
      tell process "Obsidian"
        set position of window 1 to {60, 60}
        set size of window 1 to {1280, 800}
      end tell
    end tell
    """
    subprocess.run(["osascript", "-e", script], capture_output=True)
    time.sleep(1.5)

    helper = Path(__file__).resolve().parent / "windowid.swift"
    # Bounds match the position and size set just above — so a second
    # Obsidian window somewhere else can never be the one photographed.
    result = subprocess.run(
        ["swift", str(helper), "Obsidian", "60", "60", "1280", "800"],
        capture_output=True, text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        print("   Could not find Obsidian window to capture.", file=sys.stderr)
        return

    window_id = result.stdout.strip()
    destination = PARTS / f"obsidian-{suffix}.png"
    subprocess.run(["screencapture", "-x", "-o", "-l", window_id, str(destination)], check=True)
    print(f"   part {destination.name}")

    subprocess.run(["osascript", "-e", 'tell application "iTerm" to activate'], capture_output=True)


def build_hero_figures() -> None:
    """Assemble the diagonal hero composite images for light and dark appearances."""
    announce("Assembling the hero figures")
    for suffix in ("light", "dark"):
        obsidian = PARTS / f"obsidian-{suffix}.png"
        plantoir = IMAGE_DIR / f"hero-plantoir-{suffix}.png"
        safari = IMAGE_DIR / f"site-eng2d-{suffix}.png"

        if not obsidian.exists():
            print(f"   Missing Obsidian capture for {suffix} ({obsidian.name})", file=sys.stderr)
            continue
        if not plantoir.exists():
            print(f"   Missing Plantoir capture for {suffix} ({plantoir.name})", file=sys.stderr)
            continue
        if not safari.exists():
            print(f"   Missing Safari capture for {suffix} ({safari.name})", file=sys.stderr)
            continue

        dest = IMAGE_DIR / f"hero-{suffix}.png"
        diagonal_hero(obsidian, plantoir, safari, dest, stagger_ratio=0.20, figure_width=FIGURE_WIDTH)
        print(f"   saved {dest.name}")


def build_static_figures() -> None:
    """Assemble the figures whose subject is composite or colour."""
    build_colour_figures()
    build_hero_figures()


def build_colour_figures() -> None:
    """The fanned colour schemes and the light/dark pair, from whole captures."""
    announce("Assembling the colour figures")
    fanned = [PARTS / f"home-{course['code'].lower()}-light.png" for course in DEMO_COURSES]
    missing = [path.name for path in fanned if not path.exists()]
    if missing:
        print(f"   Missing parts: {', '.join(missing)} — run --sites first.", file=sys.stderr)
    else:
        fan(fanned, IMAGE_DIR / "colour-schemes.png")
        print("   saved colour-schemes.png")

    pair = [PARTS / "home-eng2d-light.png", PARTS / "home-eng2d-dark.png"]
    if all(path.exists() for path in pair):
        side_by_side(pair, IMAGE_DIR / "light-and-dark.png")
        print("   saved light-and-dark.png")
    else:
        print("   Missing the dark half of the light/dark pair.", file=sys.stderr)


def capture_search(window: "SafariWindow", shot: dict, suffix: str) -> None:
    """A class site with its search panel open and a query typed in.

    Quartz binds the search panel to Command-K, which avoids clicking a target
    whose position depends on the window size.
    """
    capture = shot["capture"]
    window.load(site_address(capture["course"]) + capture.get("path", "/"), settle_seconds=3.5)
    window.press("k", using="command down")
    window.press(capture.get("query", "thesis"))
    time.sleep(2.0)
    destination = IMAGE_DIR / f"{shot['id']}-{suffix}.png"
    window.capture(destination)
    verify_appearance(destination, suffix == "dark", shot["id"])
    verify_address_bar(destination, shot["id"])
    prepare(destination, WIDEST_WINDOW_PIXELS)
    print(f"   saved {destination.name}")


def browser_shots() -> list[dict]:
    """The shots taken in a browser, from the manifest the pages read.

    Each names the course and the page to open. Two of them open the course's
    own "What This Site Can Do" page rather than its front page, because that
    is where the typeset mathematics and the chemistry notation are — a course
    home page shows the shape of a site but not what it can carry.
    """
    return shots_of_kind("browser")


def search_shots() -> list[dict]:
    return shots_of_kind("browser-search")


def shots_of_kind(kind: str) -> list[dict]:
    manifest = json.loads((WEBSITE / "shots.json").read_text(encoding="utf-8"))
    wanted: list[dict] = []
    for shot in manifest["shots"]:
        if shot["capture"].get("kind") == kind:
            wanted.append(shot)
    return wanted


def capture_browser_shots(identifiers: list[str]) -> None:
    """Re-take just these class-site shots, in both appearances.

    For a shot that is new or wrong, without re-taking every other picture
    `--sites` makes (the phone, search, Obsidian and the hero among them).
    """
    wanted: list[dict] = []
    for shot in browser_shots():
        if shot["id"] in identifiers:
            wanted.append(shot)
    if len(wanted) != len(identifiers):
        raise SystemExit(f"Not every one of {identifiers} is a class-site shot in shots.json.")
    announce("Photographing " + ", ".join(identifiers))
    for dark in (False, True):
        suffix = "dark" if dark else "light"
        with Appearance(dark=dark):
            time.sleep(2)
            with SafariWindow(1280, 860) as window:
                for shot in wanted:
                    capture = shot["capture"]
                    window.load(site_address(capture["course"]) + capture.get("path", "/"), settle_seconds=3.5)
                    destination = IMAGE_DIR / f"{shot['id']}-{suffix}.png"
                    window.capture(destination)
                    verify_appearance(destination, dark, shot["id"])
                    verify_address_bar(destination, shot["id"])
                    prepare(destination, WIDEST_WINDOW_PIXELS)
                    print(f"   saved {destination.name}")


def capture_colour_figures() -> None:
    """Photograph the three home pages in both appearances and assemble the
    two colour figures from them — nothing else."""
    announce("Photographing the course home pages for the colour figures")
    for dark in (False, True):
        with Appearance(dark=dark):
            time.sleep(2)
            capture_parts("dark" if dark else "light")
    build_colour_figures()


def capture_sites(workspace: Path) -> None:
    announce("Photographing the class websites")
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    shots = browser_shots()
    for dark in (False, True):
        suffix = "dark" if dark else "light"
        print(f"   {suffix} appearance")
        with Appearance(dark=dark):
            time.sleep(2)
            capture_obsidian(workspace, suffix)
            with SafariWindow(1280, 860) as window:
                for shot in shots:
                    capture = shot["capture"]
                    url = site_address(capture["course"]) + capture.get("path", "/")
                    window.load(url, settle_seconds=3.5)
                    destination = IMAGE_DIR / f"{shot['id']}-{suffix}.png"
                    window.capture(destination)
                    # Before the resize, while the page is still full size.
                    verify_appearance(destination, dark, shot["id"])
                    verify_address_bar(destination, shot["id"])
                    prepare(destination, WIDEST_WINDOW_PIXELS)
                    print(f"   saved {destination.name}")

                for shot in search_shots():
                    capture_search(window, shot, suffix)

            capture_parts(suffix)
        capture_phone(dark=dark)


def simulator_udid(device_name: str) -> str:
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True, text=True, check=True,
    )
    catalogue = json.loads(result.stdout)["devices"]
    newest = ""
    for runtime in sorted(catalogue.keys()):
        for device in catalogue[runtime]:
            if device["name"] == device_name:
                newest = device["udid"]
    if not newest:
        raise SystemExit(f"No simulator named {device_name} is available.")
    return newest


def forget_site_theme(udid: str, url: str) -> None:
    """Remove the light/dark choice a class site saved in the simulator's
    Mobile Safari, so the page follows the phone's own appearance.

    Quartz keeps it as the localStorage key `theme`. WebKit stores each
    origin's localStorage in an SQLite file beside a small `origin` file
    naming the host, under the Safari app's data container. The simulator's
    Safari is terminated first, since a running WebKit holds the file and
    would write its copy back. Only the `theme` key of that one site is
    removed; nothing else in the simulator is touched.
    """
    host = url.split("//", 1)[-1].split("/", 1)[0]
    run(["xcrun", "simctl", "terminate", udid, "com.apple.mobilesafari"], capture_output=True)
    time.sleep(1)
    devices = Path.home() / "Library" / "Developer" / "CoreSimulator" / "Devices" / udid / "data"
    applications = devices / "Containers" / "Data" / "Application"
    for origin in applications.glob("*/Library/WebKit/com.apple.mobilesafari/WebsiteData/Default/*/*/origin"):
        if host.encode() not in origin.read_bytes():
            continue
        database = origin.parent / "LocalStorage" / "localstorage.sqlite3"
        if not database.exists():
            continue
        connection = sqlite3.connect(str(database))
        try:
            connection.execute("DELETE FROM ItemTable WHERE key = 'theme'")
            connection.commit()
        finally:
            connection.close()
        print(f"   Took away {host}'s saved light/dark choice in the simulator's Safari.")


def capture_phone(dark: bool) -> None:
    """One iPhone screenshot of a class site, inside a device."""
    suffix = "dark" if dark else "light"
    udid = simulator_udid(SIMULATOR_DEVICE)
    was_booted = simulator_is_booted(udid)

    if not was_booted:
        run(["xcrun", "simctl", "boot", udid], capture_output=True)
        time.sleep(20)
    run(["open", "-g", "-a", "Simulator"], capture_output=True)
    time.sleep(4)

    run(["xcrun", "simctl", "ui", udid, "appearance", "dark" if dark else "light"],
        capture_output=True)
    run(["xcrun", "simctl", "status_bar", udid, "override",
         "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
         "--dataNetwork", "wifi", "--wifiBars", "3", "--cellularBars", "4"],
        capture_output=True)

    url = site_address("ENG2D") + "/"
    # The site remembers a light/dark choice in Mobile Safari's own storage,
    # which outranks the simulator's appearance: the committed "light" phone
    # shot had been dark all along (median luminance 18, measured
    # 2026-09-27). Tapping the site's own switch through RocketSim by its
    # label ("Light mode") was tried and did nothing. So the saved choice is
    # taken away instead, with the simulator's Safari closed, and the site
    # follows the phone. The shot is still checked below and named if wrong.
    forget_site_theme(udid, url)
    run(["xcrun", "simctl", "openurl", udid, url], capture_output=True)
    time.sleep(9)
    dismiss_safari_onboarding(udid)

    destination = IMAGE_DIR / f"site-phone-{suffix}.png"
    with destination.open("wb") as handle:
        result = subprocess.run(
            # --udid, not the focused simulator. Without it RocketSim
            # photographs whichever simulator is in front — which, on a Mac
            # with another one already booted, was somebody else's home
            # screen rather than the class site.
            [str(ROCKETSIM), "screenshot", "--udid", udid,
             "--background", "transparent", "--bezel", "device"],
            stdout=handle, stderr=subprocess.PIPE, text=False,
        )
    if result.returncode != 0:
        print(f"   RocketSim could not draw the device: {result.stderr.decode()[:300]}",
              file=sys.stderr)
        # A plain simulator screenshot is better than no phone shot at all.
        run(["xcrun", "simctl", "io", udid, "screenshot", str(destination)],
            capture_output=True)
    prepare(destination, WIDEST_PHONE_PIXELS)
    from safari import page_is_dark
    if page_is_dark(destination) != dark:
        print(f"   ✗ {destination.name} came out {'light' if dark else 'dark'}: the site has the other "
              "theme saved in the simulator's Safari. Open it there, tap the site's light/dark switch "
              "until it follows the phone, and re-take with --phone. Do not commit this one.",
              file=sys.stderr)
    print(f"   saved {destination.name}")

    if not was_booted:
        run(["xcrun", "simctl", "shutdown", udid], capture_output=True)


def simulator_is_booted(udid: str) -> bool:
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "--json"],
        capture_output=True, text=True, check=True,
    )
    catalogue = json.loads(result.stdout)["devices"]
    for devices in catalogue.values():
        for device in devices:
            if device["udid"] == udid:
                return device["state"] == "Booted"
    return False


def dismiss_safari_onboarding(udid: str) -> None:
    """Close the first-run popover Mobile Safari shows over the page."""
    if not ROCKETSIM.exists():
        return
    # With a timeout: when there is no popover (every run after the first),
    # the tap waits for a "Close" that never comes. It hung a phone run for
    # over ten minutes on 2026-09-27.
    try:
        subprocess.run(
            [str(ROCKETSIM), "interact", "tap", "--udid", udid, "--label", "Close"],
            capture_output=True, timeout=20,
        )
    except subprocess.TimeoutExpired:
        pass
    time.sleep(1.5)


# ---------- Putting the site back together ----------

def rebuild_site() -> None:
    announce("Rebuilding the site")
    run([sys.executable, str(WEBSITE / "build.py")], cwd=REPO)


def preflight_permissions() -> None:
    """Trip both permission dialogs immediately, so a human can grant them
    and walk away instead of finding one part way through an hour-long run.

    Each dialog blocks whatever triggers it until a human answers, and macOS
    only asks once it is actually needed -- Safari's the first time this
    process sends it an AppleEvent, XCTest's the first time xcodebuild enables
    UI automation. Left alone, that means the Safari prompt appears minutes
    into a --sites run and the XCTest one minutes into --app, which is the
    opposite of "grant it and leave".

    The XCTest half is tripped with the fixture-based smoke test rather than
    anything from MarketingScreenshots: it launches against a disposable
    workspace built into the test bundle, needs no demo folder, no network,
    and no already-published sites, and normally finishes in well under a
    minute. Any UI test would trigger the SAME dialog -- xcodebuild asks
    before the test's own logic runs -- so this one is chosen for speed, not
    for anything it captures.

    The two halves run in PARALLEL, slow one first. The XCTest dialog cannot
    appear until xcodebuild has built and launched the test runner -- most of
    a minute -- so run in sequence, it surfaced long after the person who
    granted the Safari prompt had walked away. Started in the background
    before Safari is poked, that build runs while the first dialog is being
    answered, and both prompts land as early as each mechanically can.
    """
    announce("Requesting permissions up front (Safari control, then UI automation)")
    print("   If a system dialog appears for either one, approve it now --")
    print("   the second can take up to a minute to surface. Both granted and")
    print("   remembered, the rest of the run needs nobody at the keyboard.")

    smoke_command: list[str] = [
        "xcodebuild", "-project", str(MAC_APP / "Plantoir.xcodeproj"),
        "-scheme", "Plantoir", "-configuration", "Debug", PLAIN_APP_ICON, "test",
        "-only-testing:QuartzTeachersUITests/QuartzTeachersUITests/testSidebarShowsExampleCourse",
    ]
    print(f"   $ {' '.join(smoke_command)}  (in the background)")
    smoke = subprocess.Popen(
        smoke_command, cwd=MAC_APP,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

    try:
        # `get version`, NOT `activate`. Any Apple Event to Safari raises the
        # same "wants access to control Safari" dialog, and this one does not
        # bring Safari forward — `activate` fronted whatever the teacher had
        # open, in whatever profile, in the middle of a capture run.
        subprocess.run(
            ["osascript", "-e", 'tell application "Safari" to get version'],
            capture_output=True, text=True, timeout=60,
        )
    except subprocess.TimeoutExpired:
        print("   Safari did not respond within a minute -- the dialog may still be waiting.")

    try:
        returncode: int = smoke.wait(timeout=300)
    except subprocess.TimeoutExpired:
        smoke.kill()
        smoke.wait()
        returncode = -1
    if returncode != 0:
        print("   The preflight test did not pass -- if a permission dialog is still on screen, "
              "answer it and re-run.", file=sys.stderr)
    else:
        print("   Both permissions are in place.")


# ---------- The v1.4.0 scenes, in the kept marketing folder ----------

def ced_on_this_mac(folder: Path) -> Path | None:
    """The Course and Exam Description, if it is already on this Mac."""
    codes = json.loads((Path(__file__).resolve().parent / "marketing" / "csp-codes.json").read_text(encoding="utf-8"))
    candidates: list[Path] = []
    if os.environ.get("PLANTOIR_CED_PDF"):
        candidates.append(Path(os.environ["PLANTOIR_CED_PDF"]))
    candidates.append(folder / ".sources" / codes["source"]["fileName"])
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def provision_marketing(folder: Path) -> int:
    """Make the kept marketing folder when it is absent; reuse it when present.

    In order, each step saying "made" or "already there":
    the launchers and build recipe; ICS3U (1, 2) and ICS4U (1) through the
    app; the College Board pages from the public document (fetched once into
    .sources/, hash-checked), into both courses; each course's correlation
    embeds and folder destination, ICS4U's declared second curriculum and
    How I Teach (marketing_folder.py); and a reference copy of ICS3U for
    2025–26, through the app. Declaring ICS3U's second curriculum is NOT
    here: the curriculum-settings scene does it through Course Settings,
    because that is the picture.
    """
    import marketing_folder
    import college_board

    announce(f"Setting up the marketing folder, {folder}")
    marketing_folder.refuse_foreign_courses(folder)
    marketing_folder.mark_as_ours(folder)
    ensure_launchers(folder)
    mirror_toolchain(folder)

    missing: list[str] = []
    for course in marketing_folder.COURSES:
        if not workspace_has_course(folder, course["code"]):
            missing.append(course["code"])
    if missing:
        print(f"   Making {', '.join(missing)} through the app's new-course panel, from the ready-made content…")
        run_ui_test(f"{scene_book.PROVISIONING_CLASS}/testCreateMarketingCourses", folder, "provision-marketing")
    else:
        print("   ICS3U and ICS4U are already there.")

    sources = folder / ".sources"
    try:
        pdf = college_board.fetch_ced(sources)
    except college_board.SourceChanged as changed:
        print(f"   ✗ {changed}", file=sys.stderr)
        return 1
    extraction = college_board.build_pages(pdf, overrides=sources / college_board.OVERRIDES_NAME)
    for problem in extraction.problems:
        print(f"   ✗ {problem}", file=sys.stderr)
    if extraction.problems:
        print("   The College Board pages were not written: the document's copies disagree somewhere above. "
              "Read those, then record a ruling in marketing/csp-codes.json -> whereCopiesDiffer.", file=sys.stderr)
        return 1
    if extraction.needs_a_person:
        drafts = sources / college_board.DRAFTS_NAME
        drafts.mkdir(parents=True, exist_ok=True)
        for code, draft in extraction.needs_a_person.items():
            path = drafts / f"{code}.md"
            if not path.exists():
                path.write_text(draft, encoding="utf-8")
        print(f"   {len(extraction.needs_a_person)} learning objectives quote drawn code and need a person: "
              f"{', '.join(sorted(extraction.needs_a_person))}.\n"
              f"   Drafts are in {drafts}; set each out from the document and save it in "
              f"{sources / college_board.OVERRIDES_NAME}, then run --provision again.")

    report = marketing_folder.apply_file_steps(folder, extraction.pages)
    print(f"   {marketing_folder.summary(report)}")

    if not any(True for _ in reference_copies_of(folder, "ICS3U")):
        print("   Keeping a copy of ICS3U for reference (2025–26), through the app…")
        run_ui_test(f"{scene_book.PROVISIONING_CLASS}/testKeepACopyForReference", folder, "provision-reference")
    else:
        print("   A reference copy of ICS3U is already there.")
    return 1 if extraction.needs_a_person else 0


def reference_copies_of(folder: Path, code: str):
    courses = folder / "courses"
    if not courses.is_dir():
        return
    for entry in courses.iterdir():
        config_path = entry / "course_config.json"
        if not config_path.is_file():
            continue
        try:
            config = json.loads(config_path.read_text(encoding="utf-8"))
        except ValueError:
            continue
        if config.get("kept_for_reference") is True and config.get("course_code") == code:
            yield entry


def capture_note_in_obsidian(note: Path, destination: Path) -> bool:
    """Obsidian showing one note, photographed as its own window."""
    from urllib.parse import quote
    # Percent-encoded: the folder and the note both have spaces in their names.
    run(["open", f"obsidian://open?path={quote(str(note), safe='/')}"], capture_output=True)
    time.sleep(2.5)
    script = """
    tell application "Obsidian" to activate
    delay 0.4
    tell application "System Events"
      tell process "Obsidian"
        set position of window 1 to {60, 60}
        set size of window 1 to {1280, 800}
      end tell
    end tell
    """
    subprocess.run(["osascript", "-e", script], capture_output=True)
    time.sleep(1.5)
    helper = Path(__file__).resolve().parent / "windowid.swift"
    result = subprocess.run(["swift", str(helper), "Obsidian", "60", "60", "1280", "800"],
                            capture_output=True, text=True)
    if result.returncode != 0 or not result.stdout.strip():
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["screencapture", "-x", "-o", "-l", result.stdout.strip(), str(destination)], check=True)
    subprocess.run(["osascript", "-e", 'tell application "iTerm" to activate'], capture_output=True)
    return True


def image_path(name: str, suffix: str) -> Path:
    """Where a scene's picture lands: a composite's part in the scratch parts
    folder, anything a page shows in site/img/."""
    for composite in scene_book.COMPOSITES.values():
        if name in composite["of"]:
            return PARTS / f"{name}-{suffix}.png"
    return IMAGE_DIR / f"{name}-{suffix}.png"


def bundle_icon_name(app_binary: Path) -> str:
    """The icon the built bundle names in its Info.plist, or "" if unreadable."""
    import plistlib
    info = app_binary.parent.parent / "Info.plist"
    try:
        with info.open("rb") as handle:
            return str(plistlib.load(handle).get("CFBundleIconName", ""))
    except (OSError, plistlib.InvalidFileException):
        return ""


def plain_icon_problem(app_binary: Path) -> str | None:
    """Make sure the bundle the banner comes from wears the plain icon.

    The notification banner shows the app icon, and the Debug build wears
    the Beta ribbon (#372) unless it was built with PLAIN_APP_ICON. A UI-test
    scene or the preflight builds it plain; a notification-only run with
    --skip-preflight builds nothing, and would photograph whatever the last
    ordinary Debug build left. So the BUNDLE is asked, and rebuilt plain when
    it says otherwise. Returns a sentence naming the problem, or None.
    """
    if bundle_icon_name(app_binary) == "Plantoir":
        return None
    print("   The Debug build wears the Beta icon; rebuilding it with the plain one for the banner.")
    result = run(
        [
            "xcodebuild",
            "-project", str(MAC_APP / "Plantoir.xcodeproj"),
            "-scheme", "Plantoir",
            "-configuration", "Debug",
            PLAIN_APP_ICON,
            "build",
        ],
        cwd=MAC_APP,
        capture_output=True,
        text=True,
    )
    named = bundle_icon_name(app_binary)
    if result.returncode != 0 or named != "Plantoir":
        return (f"the Debug build wears the Beta icon ({named or 'no icon name'}) and rebuilding it with "
                f"the plain one did not take, so the banner would show the ribbon; build with "
                f"{PLAIN_APP_ICON} and re-take with --only notification-banner")
    return None


def run_scenes(folder: Path, chosen: list) -> int:
    """Photograph the chosen scenes in both appearances, then check them.

    A scene FAILS, and is named, when a picture it should make is missing or
    does not show the words shots.json expects of it. The exit code says so:
    "judge it by the count, never the exit code" (the skill) is the exit code
    now.
    """
    import marketing_folder
    announce(f"Photographing {len(chosen)} scene(s) in {folder}")
    if not (folder / "courses" / marketing_folder.CURRICULUM_COURSE / "course_config.json").exists():
        print("   The marketing folder is not set up yet — run capture.py --provision first.", file=sys.stderr)
        return 1
    app_binary = app_bundle_resources().parent / "MacOS" / "Plantoir"
    parts: set[str] = set()
    for composite in scene_book.COMPOSITES.values():
        parts.update(composite["of"])

    tests: list[str] = []
    for scene in chosen:
        if scene.kind == "ui-test" and scene.test not in tests:
            tests.append(scene.test)

    failures: list[str] = []
    passed: list[str] = []          # "<name>-<suffix>", checked and promoted
    icon_problem: str | None = None
    for scene in chosen:
        if scene.kind == "notification":
            icon_problem = plain_icon_problem(app_binary)
            if icon_problem is not None:
                failures.append(f"{scene.name}: {icon_problem}")
            break
    staging: Path = SCRATCH / "scenes-staged"
    if staging.exists():
        shutil.rmtree(staging)
    kill_orphaned_model_servers()
    try:
        with RememberedWindowFrames(), BackupsSetAside(folder), KeyboardNavigationOff():
            for dark in (False, True):
                suffix = "dark" if dark else "light"
                print(f"   {suffix} appearance")
                with Appearance(dark=dark):
                    time.sleep(2)
                    if tests:
                        target = ",".join(f"{scene_book.SCENE_CLASS}/{test}" for test in tests)
                        bundle = run_ui_test(target, folder, f"scenes-{suffix}", allow_failure=True)
                        saved = export_attachments(bundle, suffix, staging=staging)
                        print(f"   staged {len(saved)} image(s): {', '.join(saved)}")
                    for scene in chosen:
                        if scene.kind == "notification":
                            if icon_problem is not None:
                                continue
                            destination = staging / f"notification-banner-{suffix}.png"
                            staging.mkdir(parents=True, exist_ok=True)
                            for problem in scene_book.capture_notification(app_binary, folder, destination):
                                failures.append(f"{scene.name} ({suffix}): {problem}")
                        elif scene.kind == "obsidian":
                            note = folder / "courses" / marketing_folder.CURRICULUM_COURSE / marketing_folder.HOW_I_TEACH_NAME
                            with scene_book.ObsidianRegistryKept() as registry:
                                if not registry.register(note.parent):
                                    failures.append(f"{scene.name} ({suffix}): Obsidian is open, and opening a "
                                                    "note in it would need its list of vaults changed under it; "
                                                    "quit Obsidian (it is not the capture's to quit) and re-take "
                                                    "with --only how-i-teach")
                                elif not capture_note_in_obsidian(note, staging / f"how-i-teach-{suffix}.png"):
                                    failures.append(f"{scene.name} ({suffix}): Obsidian's window was not found")
                    # Checked in STAGING, and only what passes is promoted —
                    # to site/img, or to the parts folder for a composite. A
                    # wrong picture never replaces a right one.
                    for scene in chosen:
                        for name in scene.produces:
                            picture = staging / f"{name}-{suffix}.png"
                            if not picture.exists():
                                failures.append(f"{scene.name} ({suffix}): {picture.name} was not made")
                                continue
                            drawn = corner_problems(picture)
                            if drawn:
                                failures.append(f"{scene.name} ({suffix}): {picture.name} is not a whole window "
                                                f"capture with its own corners — {drawn[0]}")
                                continue
                            missing = scene_book.missing_words(picture, scene_book.expected_text(name))
                            if missing:
                                failures.append(f"{scene.name} ({suffix}): {picture.name} does not show {missing} "
                                                f"(kept for a look in {staging})")
                                continue
                            final = image_path(name, suffix)
                            final.parent.mkdir(parents=True, exist_ok=True)
                            shutil.copy2(picture, final)
                            if final.parent == IMAGE_DIR:
                                prepare(final, WIDEST_WINDOW_PIXELS)
                            passed.append(f"{name}-{suffix}")
    finally:
        kill_orphaned_model_servers()
        for scene in chosen:
            if scene.kind == "notification":
                scene_book.cancel_leftover_schedule(app_binary, folder)
                record = scene_book.scheduled_record(folder, "ICS3U", 1)
                if record.exists():
                    record.unlink()
                print("   Cleared the scheduled run's record for this folder. The delivered notification stays "
                      "in Notification Center: a script cannot withdraw another app's notification.")

    compose_scene_figures(passed)
    promote_captured_shots(passed)
    for failure in failures:
        print(f"   ✗ {failure}", file=sys.stderr)
    if failures:
        print(f"\n   {len(failures)} scene check(s) failed. Nothing above counts as done until each is re-taken.",
              file=sys.stderr)
        return 1
    print("   Every scene made every picture it owes, and each says what its caption says.")
    return 0


def compose_scene_figures(passed: list[str]) -> None:
    """Assemble each composite whose parts ALL passed this run, per appearance."""
    from composite import pair_of_windows, banner_over_window
    for name, composite in scene_book.COMPOSITES.items():
        for suffix in ("light", "dark"):
            if not all(f"{part}-{suffix}" in passed for part in composite["of"]):
                continue
            sources = [PARTS / f"{part}-{suffix}.png" for part in composite["of"]]
            destination = IMAGE_DIR / f"{name}-{suffix}.png"
            if composite["arrange"] == "banner":
                banner_over_window(sources[0], sources[1], destination)
            else:
                pair_of_windows(sources, destination)
            prepare(destination, WIDEST_WINDOW_PIXELS)
            drawn = corner_problems(destination)
            if drawn:
                print(f"   ✗ {destination.name}: {drawn[0]}", file=sys.stderr)
                continue
            passed.append(f"{name}-{suffix}")
            print(f"   saved {destination.name}")


def pictures_with_drawn_corners() -> list[str]:
    """Every picture the pages show whose corners are not a real window's.

    Run before a picture is called finished: the same check as
    `test_native_corners.py`. A drawn, cropped or square corner is refused,
    never fixed up — the capture that made it is what is wrong.
    """
    problems: list[str] = []
    for picture in images_the_pages_show(WEBSITE, IMAGE_DIR):
        problems.extend(corner_problems(picture))
    return problems


def refuse_drawn_corners(only_ids: list[str] | None = None) -> int:
    """Name every picture with a square or drawn corner, and exit non-zero.

    Pictures written straight to site/img (the class sites, the figures) are
    already there when this runs: a failure here means "do not commit them",
    and the exit code says so. Scene pictures are checked earlier, in
    staging, and a failing one never reaches site/img.
    """
    problems: list[str] = []
    for problem in pictures_with_drawn_corners():
        if only_ids is None or any(problem.startswith(f"{identifier}-") for identifier in only_ids):
            problems.append(problem)
    for problem in problems:
        print(f"   ✗ {problem}", file=sys.stderr)
    if problems:
        print(f"\n   {len(problems)} corner(s) on the site's pictures are not a real window's. "
              "Re-take them; do not commit them.", file=sys.stderr)
        return 1
    print("   Every picture the pages show has its window's own corners.")
    return 0


def promote_captured_shots(passed: list[str]) -> None:
    """Bring shots.json up to date with pictures that now exist.

    Only pictures whose corners are a real window's are promoted: a shot
    with a drawn or square corner stays as it was, and is named.

    A shot taken in BOTH appearances this run loses `awaiting_capture`, and a
    retaken one has its new words (`retake` → alt, caption, expectText, test)
    promoted in the same change as its picture, so the words never describe a
    picture that is not there. Written back in the file's own shape.
    """
    path = WEBSITE / "shots.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    changed: list[str] = []
    for shot in manifest["shots"]:
        identifier = shot["id"]
        if f"{identifier}-light" not in passed or f"{identifier}-dark" not in passed:
            continue
        drawn: list[str] = []
        for suffix in ("light", "dark"):
            picture = IMAGE_DIR / f"{identifier}-{suffix}.png"
            if picture.exists():
                drawn.extend(corner_problems(picture))
        if drawn:
            print(f"   ✗ {identifier} not promoted: {drawn[0]}", file=sys.stderr)
            continue
        if shot.pop("awaiting_capture", None):
            changed.append(f"{identifier}: taken")
        issue = shot.pop("waiting_on", None)
        if issue:
            changed.append(f"{identifier}: no longer waiting on {issue} — close it when every shot it names is taken")
        retake = shot.pop("retake", None)
        if retake:
            for key in ("alt", "caption", "expectText"):
                if key in retake:
                    shot[key] = retake[key]
            if "test" in retake:
                shot.setdefault("capture", {})["test"] = retake["test"]
            changed.append(f"{identifier}: its new alt text and caption promoted")
    if changed:
        path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        for line in changed:
            print(f"   shots.json — {line}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture every screenshot plantoir.app uses.")
    parser.add_argument("--workspace", default=str(DEFAULT_WORKSPACE),
                        help="the demo working folder (must be inside your home folder)")
    parser.add_argument("--provision", action="store_true",
                        help="make or reuse the kept marketing folder (ICS3U, ICS4U, the College Board "
                             "pages and both courses' correlations) for the v1.4.0 scenes")
    parser.add_argument("--provision-demo", action="store_true",
                        help="only create the demo courses (ENG2D, MCV4U, SCH3U) in the demo folder")
    parser.add_argument("--scenes", action="store_true", help="photograph every v1.4.0 scene")
    parser.add_argument("--dry-run", action="store_true",
                        help="prove each scene's set-up is reachable, launching nothing and changing nothing")
    parser.add_argument("--marketing-folder", default=str(MARKETING_FOLDER),
                        help="the kept marketing folder (must be inside your home folder)")
    parser.add_argument("--publish", action="store_true", help="only build and publish the demo sites")
    parser.add_argument("--app", action="store_true", help="only photograph the app")
    parser.add_argument("--only", default=None,
                        help="run just these, comma-separated: scene names (reference, two-maps, … — "
                             "see scenes.py) or, with --app, test names (test4Progress,test6Assistant)")
    parser.add_argument("--sites", action="store_true", help="only photograph the class websites")
    parser.add_argument("--phone", action="store_true",
                        help="only photograph the class site on the phone, both appearances")
    parser.add_argument("--skip-preflight", action="store_true",
                        help="skip the permission preflight — for back-to-back runs, when both "
                             "grants were exercised minutes ago and macOS still remembers them")
    parser.add_argument("--figures", action="store_true",
                        help="only reassemble the static figures from parts already captured")
    parser.add_argument("--colour-figures", action="store_true",
                        help="only re-take the three home pages and rebuild colour-schemes and light-and-dark")
    parser.add_argument("--browser-shots", default=None,
                        help="only re-take these class-site shots, comma-separated ids from shots.json")
    parser.add_argument("--hero", action="store_true",
                        help="only reassemble the hero composite from parts already captured")
    arguments = parser.parse_args()

    workspace = Path(arguments.workspace).expanduser()
    if Path.home() not in workspace.parents:
        raise SystemExit("The demo folder has to be inside your home folder, or the site builder sees it as empty.")

    marketing = Path(arguments.marketing_folder).expanduser()
    if Path.home() not in marketing.parents:
        raise SystemExit("The marketing folder has to be inside your home folder, or the site builder sees it as empty.")

    if arguments.dry_run:
        return scene_book.dry_run(marketing, ced_on_this_mac(marketing))

    only_scenes: list = []
    if arguments.only and not arguments.app:
        only_scenes = scene_book.scenes_for(arguments.only.split(","))
    if arguments.provision or arguments.scenes or only_scenes:
        SCRATCH.mkdir(parents=True, exist_ok=True)
        keeping_awake = stay_awake()
        try:
            if not arguments.skip_preflight:
                preflight_permissions()
            result = 0
            if arguments.provision:
                result = provision_marketing(marketing)
            if result == 0 and (arguments.scenes or only_scenes):
                result = run_scenes(marketing, only_scenes or list(scene_book.SCENES))
                rebuild_site()
                announce("Checking every picture's corners")
                if refuse_drawn_corners() != 0:
                    result = 1
        finally:
            keeping_awake.terminate()
        return result

    if arguments.colour_figures or arguments.browser_shots:
        keeping_awake = stay_awake()
        try:
            if not arguments.skip_preflight:
                preflight_permissions()
            if arguments.browser_shots:
                capture_browser_shots(arguments.browser_shots.split(","))
            if arguments.colour_figures:
                capture_colour_figures()
        finally:
            keeping_awake.terminate()
        rebuild_site()
        announce("Checking every picture's corners")
        return refuse_drawn_corners()

    if arguments.hero:
        build_hero_figures()
        rebuild_site()
        return refuse_drawn_corners(["hero"])

    if arguments.phone:
        # No preflight: the phone shot is simctl and RocketSim end to end —
        # no Safari control, no UI automation — so neither permission dialog
        # can appear, and the smoke test would only cost a minute.
        announce("Photographing the class site on the phone")
        IMAGE_DIR.mkdir(parents=True, exist_ok=True)
        keeping_awake = stay_awake()
        try:
            for dark in (False, True):
                capture_phone(dark=dark)
        finally:
            keeping_awake.terminate()
        rebuild_site()
        return 0

    everything = not (arguments.provision_demo or arguments.publish or arguments.app
                      or arguments.sites or arguments.figures)
    SCRATCH.mkdir(parents=True, exist_ok=True)

    keeping_awake = stay_awake()
    try:
        if arguments.skip_preflight:
            print("   Skipping the permission preflight, as asked. If a capture "
                  "stalls on a system dialog, re-run without --skip-preflight.")
        else:
            preflight_permissions()
        if everything or arguments.provision_demo:
            provision(workspace)
        if everything or arguments.publish:
            publish_demo_sites(workspace)
        if everything or arguments.app:
            capture_app(workspace, only=arguments.only)
        if everything or arguments.sites:
            capture_sites(workspace)
            build_static_figures()
        if arguments.figures and not (everything or arguments.sites):
            build_static_figures()
        if everything or arguments.app or arguments.sites or arguments.figures:
            rebuild_site()
    finally:
        keeping_awake.terminate()

    announce("Checking every picture's corners")
    if refuse_drawn_corners() != 0:
        return 1
    announce("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

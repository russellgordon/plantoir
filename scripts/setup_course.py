import os
import json
import subprocess
from pathlib import Path

# The embeddable Python used by the native Windows runtime replaces
# sys.path wholesale (python311._pth), so the script's own folder must
# be added by hand before sibling imports. Harmless everywhere else.
import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
import toolchain_paths
import re
import sys
# The wizard's single-keypress reader. termios/tty are POSIX-only; running
# natively on Windows the same keys arrive through msvcrt instead, and the
# import must not sink the whole module (everything non-interactive in here
# is imported by the build machinery too).
try:
    import tty
    import termios
except ImportError:
    tty = None
    termios = None
    import msvcrt
from datetime import datetime, timezone, timedelta
import textwrap
import zipfile  # NEW: for backups
import argparse  # NEW: for --no-backup flag
import shutil   # NEW: needed for copying example course
import random   # NEW: for generating alternate example course code
import string   # NEW: for generating alternate example course code


# ---- Host OS signaling (injected) -------------------------------------------
_HOST_OS = "unknown"  # set from --host-os at runtime

def _is_windows(host_os: str) -> bool:
    return (host_os or "").lower() == "windows"

def _cmd_example(script_base: str, course, section, host_os: str) -> str:
    """
    Returns OS-appropriate example command for preview/deploy.
    script_base: 'preview' or 'deploy'
    """
    if _is_windows(host_os):
        # Windows example: .\preview.bat ICS3U 1
        return f".\\{script_base}.bat {course} {section}"
    else:
        # mac/Linux example: ./preview.sh ICS3U 1
        return f"./{script_base}.sh {course} {section}"
# ----------------------------------------------------------------------------

# The factory defaults are deliberately school-neutral. One switch brings
# back LCS's own set-up — its terms (Grove Time, SIC) and the College Board
# folder its AP courses use. These four lists are the whole difference.
DEFAULT_SHARED_FOLDERS = [
    "Concepts", "Discussions", "Examples", "Exercises", "Media",
    "Ontario Curriculum", "Portfolios",
    "Recaps", "Setup", "Style", "Tasks", "Tutorials"
]

LCS_SHARED_FOLDERS = [
    "Concepts", "Discussions", "Examples", "Exercises", "Media",
    "Ontario Curriculum", "College Board Curriculum", "Portfolios",
    "Recaps", "Setup", "Style", "Tasks", "Tutorials"
]

DEFAULT_SHARED_FILES = [
    "Extra Help.md", "Learning Goals.md"
]

LCS_SHARED_FILES = [
    "SIC Drop-In Sessions.md", "Grove Time.md", "Learning Goals.md"
]

DEFAULT_PER_SECTION_FOLDERS = ["All Classes"]

DEFAULT_PER_SECTION_FILES = [
    "Private Notes.md", "Scratch Page.md", "Key Links.md"
]

# Pages that exist for the teacher's own eyes: they ship as drafts so they
# are never published, and stay that way unless the teacher flips them.
UNPUBLISHED_PER_SECTION_FILES = {"Private Notes.md", "Scratch Page.md"}

# Two jurisdictions, both resolved through toolchain_paths rather than by
# hard-coded prefix: a native Windows run has no /opt, and SUPPORT_DIR is
# what already knows where the bundled support/ tree landed. Order matters
# only in that the first file holding the code wins, and no code appears in
# both.
COURSE_LOOKUP_PATHS = [
    toolchain_paths.SUPPORT_DIR / "ontario_secondary_courses.json",
    toolchain_paths.SUPPORT_DIR / "british_columbia_secondary_courses.json",
]

# ---------- NEW: Backup exclusion set ---------------------------------------
BACKUP_DEFAULT_EXCLUDES = {
    "node_modules",
    ".git",
    ".quartz-cache",
    ".cache",
    "dist",
    "build",
    "out",
    ".DS_Store",
    "__pycache__",
    ".merged_output",  # constructed output – exclude from backups
}

def _iter_nonempty(p: Path) -> bool:
    """Return True if directory exists and has at least one entry."""
    if not p.exists() or not p.is_dir():
        return False
    try:
        next(p.iterdir())
        return True
    except StopIteration:
        return False

def backup_existing_course_dir(course_dir: Path, backup_root: Path, excludes: set[str] | None = None) -> Path | None:
    """
    If course_dir exists and is non-empty, create a zip backup at:
      backup_root / course_dir.name / YYYY-MM-DD_HHMMSS.zip
    Skips folders/files listed in `excludes` (merged_output, caches, etc.).
    Returns the created zip path, or None if nothing was backed up.
    """
    excludes = (excludes or set()) | BACKUP_DEFAULT_EXCLUDES

    if not _iter_nonempty(course_dir):
        return None

    backup_base = backup_root / course_dir.name
    backup_base.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d_%H%M%S")
    zip_path = backup_base / f"{ts}.zip"

    print(f"🛟 Backing up existing course folder: {course_dir}")
    print(f"    → Excluding: {', '.join(sorted(excludes)) or '(none)'}")
    print(f"    → Writing:   {zip_path}")

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(course_dir):
            # Prune excluded directories in-place
            dirs[:] = [d for d in dirs if d not in excludes]
            rel_root = os.path.relpath(root, course_dir)
            if rel_root == ".":
                rel_root = ""
            for name in files:
                if name in excludes:
                    continue
                src = Path(root) / name
                rel = Path(rel_root) / name
                try:
                    if src.is_file():
                        zf.write(src, rel.as_posix())
                except FileNotFoundError:
                    # Ignore broken symlinks / races
                    pass

    print("✅ Backup complete.\n")
    return zip_path

# ---------- Colour scheme support (added) -----------------------------------

CANDIDATE_COLOUR_JSON_PATHS = [
    Path("support/colour_schemes.json"),
    toolchain_paths.SUPPORT_DIR / "colour_schemes.json",
    Path(__file__).resolve().parent.parent / "support" / "colour_schemes.json",
    Path(__file__).resolve().parent / "support" / "colour_schemes.json",
]

def load_colour_schemes():
    for p in CANDIDATE_COLOUR_JSON_PATHS:
        if p.exists():
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
            # Accept either list or {"schemes":[...]}
            if isinstance(data, dict) and "schemes" in data:
                data = data["schemes"]
            return data
    print("⚠️  colour_schemes.json not found. Skipping scheme selection.")
    return []

def hex_to_rgb(s):
    s = s.strip()
    if s.startswith("#") and len(s) == 7:
        return int(s[1:3], 16), int(s[3:5], 16), int(s[5:7], 16)
    if s.startswith("#") and len(s) == 4:
        r = int(s[1]*2, 16)
        g = int(s[2]*2, 16)
        b = int(s[3]*2, 16)
        return r, g, b
    if s.lower().startswith("rgba"):
        try:
            nums = s[s.find("(")+1:s.find(")")].split(",")
            r, g, b = [int(float(x.strip())) for x in nums[:3]]
            return r, g, b
        except Exception:
            pass
    return (128, 128, 128)

def bg_rgb(r, g, b): 
    return f"\x1b[48;2;{r};{g};{b}m"

RESET = "\033[0m"
BOLD  = "\x1b[1m"

def block(color_hex, width=10):
    r, g, b = hex_to_rgb(color_hex)
    return f"{bg_rgb(r,g,b)}{' ' * width}{RESET}"

def clear_screen():
    sys.stdout.write("\x1b[2J\x1b[H")
    sys.stdout.flush()

def getch():
    """Read single keypress (supports arrow left/right) without Enter."""
    if termios is None:
        # Windows console: a locally-typed arrow arrives as a two-character
        # sequence with a \x00 or \xe0 prefix ('M' right, 'K' left). Under
        # ConPTY (the app driving the wizard), the same key can arrive as
        # the raw VT sequence ESC [ C / ESC [ D instead - handle both, and
        # only call a lone ESC an ESC when nothing follows it.
        ch1 = msvcrt.getwch()
        if ch1 in ("\x00", "\xe0"):
            ch2 = msvcrt.getwch()
            if ch2 == "M":
                return "RIGHT"
            if ch2 == "K":
                return "LEFT"
            return "ESC"
        if ch1 == "\x1b":
            if msvcrt.kbhit():
                ch2 = msvcrt.getwch()
                if ch2 == "[" and msvcrt.kbhit():
                    ch3 = msvcrt.getwch()
                    if ch3 == "C":
                        return "RIGHT"
                    if ch3 == "D":
                        return "LEFT"
            return "ESC"
        if ch1 in ("\r", "\n"):
            return "ENTER"
        return ch1
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch1 = sys.stdin.read(1)
        if ch1 == '\x1b':  # escape
            ch2 = sys.stdin.read(1)
            if ch2 == '[':
                ch3 = sys.stdin.read(1)
                if ch3 == 'C': return 'RIGHT'
                if ch3 == 'D': return 'LEFT'
            return 'ESC'
        if ch1 in ('\r', '\n'):
            return 'ENTER'
        return ch1
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

def render_scheme_preview_for_section(scheme, idx, total, section_number):
    name = scheme.get("name", scheme.get("id", f"Scheme {idx+1}"))
    colors = scheme.get("colors", {})
    lm = colors.get("lightMode", {})
    dm = colors.get("darkMode", {})

    clear_screen()
    print(f"{BOLD}Colour Scheme for Section {section_number}{RESET}")
    print(f"{BOLD}({idx+1}/{total}) {name}{RESET}\n")

    keys = ["light", "lightgray", "gray", "darkgray", "dark", "secondary", "tertiary", "textHighlight"]

    def column(mode_dict, title):
        print(f"{BOLD}{title}:{RESET}")
        for k in keys:
            sw = block(mode_dict.get(k, "#888888"))
            # Plain text key name with a simple color block beside it
            print(f"  {k:<13} {sw}")
        print()

    column(lm, "Light Mode")
    column(dm, "Dark Mode")

    print("Use ← / → (or 'p' / 'n') to browse, Enter to select. Press 'q' to keep previous choice.")

def interactive_pick_scheme_for_section(schemes, section_number, default_id=None):
    if not schemes:
        return default_id
    start = 0
    if default_id:
        for i, s in enumerate(schemes):
            if s.get("id") == default_id:
                start = i
                break

    i = start
    total = len(schemes)
    while True:
        render_scheme_preview_for_section(schemes[i], i, total, section_number)
        key = getch()
        if key in ('RIGHT', 'n'):
            i = (i + 1) % total
        elif key in ('LEFT', 'p'):
            i = (i - 1 + total) % total
        elif key in ('q', 'Q', 'ESC'):
            return default_id
        elif key == 'ENTER':
            return schemes[i].get("id")

# ---------- Original helpers (preserved) ------------------------------------

def prompt_with_default(prompt_text, default_value):
    response = input(f"{prompt_text} [Default: {default_value}]: ").strip()
    return response if response else default_value

def prompt_select_multiple(prompt_text, options, default_selection=None):
    BLUE = "\033[34m"
    RESET_LOCAL = "\033[0m"

    # Highlight "HIDE" or "EXPANDABLE" in blue if present in prompt_text
    prompt_text = prompt_text.replace("HIDE", f"{BLUE}HIDE{RESET_LOCAL}")
    prompt_text = prompt_text.replace("EXPANDABLE", f"{BLUE}EXPANDABLE{RESET_LOCAL}")

    print(f"\n{prompt_text}")
    for idx, option in enumerate(options):
        if default_selection and option in default_selection:
            print(f"{BLUE}{idx + 1}. {option}{RESET_LOCAL}")
        else:
            print(f"{idx + 1}. {option}")

    if default_selection:
        default_indices = [str(options.index(item) + 1) for item in default_selection if item in options]
        print(f"Enter comma-separated numbers (e.g., 1,3,5) or leave blank to accept default: {','.join(default_indices)}")
    else:
        print("Enter comma-separated numbers (e.g., 1,3,5) or leave blank for none:")

    selection = input("> ").strip()
    if not selection and default_selection is not None:
        return default_selection
    if not selection:
        return []

    try:
        indices = [int(i) - 1 for i in selection.split(",")]
        return [options[i] for i in indices if 0 <= i < len(options)]
    except Exception:
        print("Invalid input. Please try again.")
        return prompt_select_multiple(prompt_text, options, default_selection)

def prompt_type_list(prompt_text, default_list=None, add_md_extension=False, forbidden_names=None):
    """
    Prompt the user for a comma-separated list of items.
    - If forbidden_names is provided, any matches are removed and a warning is printed.
    - If add_md_extension is True, ensure items end with .md.
    """
    forbidden_names = set((forbidden_names or []))
    print(f"\n{prompt_text}")
    if default_list:
        for item in default_list:
            print(f" - {item}")
    print("Enter comma-separated names or leave blank to accept default:")
    entry = input("> ").strip()
    if not entry:
        # Remove forbidden names from defaults silently but warn if they were present
        defaults = default_list if default_list else []
        filtered = [x for x in defaults if x not in forbidden_names]
        removed = [x for x in defaults if x in forbidden_names]
        if removed:
            print(f"ℹ️  Skipping reserved name(s): {', '.join(removed)}")
        return filtered

    raw = [name.strip() for name in entry.split(",") if name.strip()]
    # Remove forbidden names from provided list and warn
    cleaned = []
    removed = []
    for name in raw:
        if name in forbidden_names:
            removed.append(name)
            continue
        cleaned.append(name + ".md" if add_md_extension and not name.endswith(".md") else name)

    if removed:
        print(f"⚠️  The following name(s) are reserved and will be skipped: {', '.join(removed)}. A course-level 'Media' folder is created automatically for storing images/videos and is hidden from the site sidebar.")

    return cleaned

def get_course_name_from_json(course_code):
    course_info = None
    for path in COURSE_LOOKUP_PATHS:
        if not path.exists():
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                course_data = json.load(f)
            info = course_data.get(course_code.upper())
            if info:
                course_info = info
                break
        except Exception:
            continue

    if not course_info:
        return None

    try:
        print(f"\n🔎 Found course info for {course_code}:")
        formal = course_info["formal_name"]
        short = course_info["short_name"]

        # The SHORT name is offered first, because it is the one a teacher
        # usually keeps. The formal name is the ministry's string, correct
        # and rarely wanted on a website — offering it first only means it
        # gets deleted. Same order as the app's New Course wizard.
        if input(f"Use short name \"{short}\"? (y/n): ").strip().lower() == "y":
            return short
        if input(f"Use formal name \"{formal}\"? (y/n): ").strip().lower() == "y":
            return formal
        return input("Enter a custom course name: ").strip()
    except Exception:
        return None

# ---------- New helpers: stateful footer prompt -----------------------------

def capture_multiline() -> str:
    """Capture multi-line input until a single line 'EOF' is entered."""
    print("\nPaste your footer HTML below.")
    print("When finished, type a single line: EOF")
    lines = []
    while True:
        try:
            line = input()
        except EOFError:
            break
        if line.strip() == "EOF":
            break
        lines.append(line)
    return "\n".join(lines).strip()

def prompt_footer_html_stateful(saved_config: dict) -> str:
    current = (saved_config.get("footer_html") or "").strip()
    if current:
        preview = current
        print(f"\n🦶 A custom footer is already set (blank lines added above and below for clarity within this series of prompts):\n\n{preview}\n")
        choice = input("Press ENTER to keep it, 'e' to edit, or 'c' to clear: ").strip().lower()
        if choice == "":
            print("✅ Keeping existing footer.")
            return current
        if choice == "c":
            print("🧹 Footer cleared.")
            return ""
        if choice != "e":
            print("↪️ Unrecognized choice; keeping existing footer.")
            return current

        # Edit path
        print("\nEnter the full HTML content you want to display in the footer (example shown):")
        print('The resources on this site by Russell Gordon are licensed under '
              '<a href="http://creativecommons.org/licenses/by/4.0/?ref=chooser-v1" '
              'target="_blank" rel="license noopener noreferrer" style="display:inline-block;">'
              'CC BY 4.0</a> unless otherwise noted.')
        new_html = capture_multiline()
        if not new_html:
            print("↪️ No changes entered; keeping existing footer.")
            return current
        print("✅ Footer updated.")
        return new_html

    # No footer set yet — original y/n flow
    yn = input("\nWould you like to add custom footer HTML? (y/n) [Default: n]: ").strip().lower()
    if yn == "y":
        print("\nEnter the full HTML content you want to display in the footer (example shown):")
        print('The resources on this site by Russell Gordon are licensed under '
              '<a href="http://creativecommons.org/licenses/by/4.0/?ref=chooser-v1" '
              'target="_blank" rel="license noopener noreferrer" style="display:inline-block;">'
              'CC BY 4.0</a> unless otherwise noted.')
        return capture_multiline()
    return ""

# ---------- New helper: yes/no boolean with default -------------------------

def prompt_curriculum_coverage(curriculum_included: bool, saved_config: dict) -> bool:
    """
    Offer the Curriculum Coverage heat map.

    The map reads the site's own links to the curriculum pages, so it can
    only exist when those pages do: with the curriculum declined there is
    nothing to colour, and the question is not asked. The reverse is not
    true — a teacher can keep the curriculum pages and still not want a
    coverage map, which is why this is its own question rather than a
    consequence of the previous one.

    Defaults to ON when the curriculum is present.
    """
    if not curriculum_included:
        return False
    print("\n🗺️  A Curriculum Coverage page can be added: a heat map of every")
    print("expectation, coloured by how many pages address it, rebuilt every time")
    print("the site is built. It starts red in September and greens as the year")
    print("goes on. It is linked from Key Links, and stays out of the sidebar.")
    return prompt_yes_no_default(
        "Include the Curriculum Coverage page?",
        bool(saved_config.get("include_curriculum_coverage", True))
    )


def prompt_coverage_notes(coverage_included: bool, saved_config: dict) -> bool:
    """
    Offer the coverage page's two explanatory sections.

    "What counts" and "Reading it honestly" explain what the map counts and
    how to read a wall of red in September. They are written for a teacher
    meeting the map for the first time — a department that has already had
    that conversation, or a teacher publishing the map to students, may want
    the page to be the map and nothing else.

    They cannot exist without the map, so declining the map answers this
    question too. Defaults to ON.
    """
    if not coverage_included:
        return False
    print("\n📝 The coverage page ends with two short sections: what counts as")
    print("addressing an expectation, and how to read the map honestly — red in")
    print("September is normal, red in May is not. They can be left off, leaving")
    print("the map, the legend, and the summary table.")
    return prompt_yes_no_default(
        "Include those explanatory sections on the coverage page?",
        bool(saved_config.get("include_coverage_notes", True))
    )


def prompt_yes_no_default(prompt_text: str, default: bool) -> bool:
    """
    Ask a yes/no question with a boolean default.
    Example prompt: 'Show page read time estimates to students?'
    Displays [Default: y] or [Default: n] accordingly.
    """
    default_label = "y" if default else "n"
    resp = input(f"\n{prompt_text} (y/n) [Default: {default_label}]: ").strip().lower()
    if resp == "":
        return default
    if resp in ("y", "yes"):
        return True
    if resp in ("n", "no"):
        return False
    print("↪️ Unrecognized input; keeping default.")
    return default

# ---------- New helper: Explorer expansion behaviour (stateful) -------------

def prompt_explorer_expansion_behavior(saved_config: dict) -> bool:
    """
    Returns True if folder should expand when name OR chevron is clicked.
    Returns False if folder should expand ONLY when chevron is clicked.
    Default: False (expand only on chevron).
    """
    last = saved_config.get("expandOnFolderClick")
    default = bool(last) if last is not None else False  # default to chevron-only
    default_idx = 1 if default else 2

    print("\n🧭 Explorer item expansion behaviour")
    print("When clicking folders in the sidebar, choose what should happen:")
    print(f"  1. Expand when chevron or name is clicked{'  ← default' if default_idx == 1 else ''}")
    print(f"  2. Expand only when chevron is clicked{'  ← default' if default_idx == 2 else ''}")

    choice = input(f"Select 1-2 [Default: {default_idx}]: ").strip()
    if choice == "":
        return default
    if choice == "1":
        return True
    if choice == "2":
        return False

    print("↪️ Unrecognized input; keeping default.")
    return default

# ---------- New: Font selection helpers -------------------------------------

FONT_PAIRINGS = [
    # (Header, Body)
    ("Playfair Display", "Source Sans 3"),
    ("Source Serif 4", "Inter"),
    ("Montserrat", "Lora"),
    ("Raleway", "Roboto"),
    ("Poppins", "Merriweather"),
    ("Archivo", "Noto Sans"),
]

CODE_FONTS = [
    "JetBrains Mono",
    "Fira Code",
    "IBM Plex Mono",
    "Source Code Pro",
    "Inconsolata",
    "Ubuntu Mono",
]

# --- snip (all your existing imports and code stay the same) ---

# ---------- NEW: Locale selection (restricted list, saved to config) --------
# Note: 'definition.ts' is not an actual locale file, so it is intentionally excluded.
_LOCALE_FILES = [
    "nb-NO.ts",
    "ar-SA.ts",
    "ca-ES.ts",
    "cs-CZ.ts",
    "de-DE.ts",
    "en-GB.ts",
    "en-US.ts",
    "es-ES.ts",
    "fa-IR.ts",
    "fi-FI.ts",
    "fr-FR.ts",
    "hu-HU.ts",
    "it-IT.ts",
    "ja-JP.ts",
    "ko-KR.ts",
    "lt-LT.ts",
    "nl-NL.ts",
    "pl-PL.ts",
    "pt-BR.ts",
    "ro-RO.ts",
    "ru-RU.ts",
    "th-TH.ts",
    "tr-TR.ts",
    "uk-UA.ts",
    "vi-VN.ts",
    "zh-CN.ts",
    "zh-TW.ts",
]
LOCALE_CODES = [f[:-3] for f in _LOCALE_FILES]  # strip '.ts' → 'en-US', etc.

# --- ADD: Human-friendly labels for the supported locale codes ---------------
# (Mapped only for the LOCALE_CODES above to avoid any behavioral changes.)
LOCALE_LABELS = {
    "nb-NO": "Norwegian Bokmål (Norway)",
    "ar-SA": "Arabic (Saudi Arabia)",
    "ca-ES": "Catalan (Spain)",
    "cs-CZ": "Czech (Czechia)",
    "de-DE": "German (Germany)",
    "en-GB": "English (United Kingdom)",
    "en-US": "English (United States)",
    "es-ES": "Spanish (Spain)",
    "fa-IR": "Persian (Iran)",
    "fi-FI": "Finnish (Finland)",
    "fr-FR": "French (France)",
    "hu-HU": "Hungarian (Hungary)",
    "it-IT": "Italian (Italy)",
    "ja-JP": "Japanese (Japan)",
    "ko-KR": "Korean (South Korea)",
    "lt-LT": "Lithuanian (Lithuania)",
    "nl-NL": "Dutch (Netherlands)",
    "pl-PL": "Polish (Poland)",
    "pt-BR": "Portuguese (Brazil)",
    "ro-RO": "Romanian (Romania)",
    "ru-RU": "Russian (Russia)",
    "th-TH": "Thai (Thailand)",
    "tr-TR": "Turkish (Türkiye)",
    "uk-UA": "Ukrainian (Ukraine)",
    "vi-VN": "Vietnamese (Vietnam)",
    "zh-CN": "Chinese, Simplified (China)",
    "zh-TW": "Chinese, Traditional (Taiwan)",
}

# Optional nice-to-have flag icons for the country/region part
LOCALE_FLAGS = {
    "NO": "🇳🇴",
    "SA": "🇸🇦",
    "ES": "🇪🇸",
    "CZ": "🇨🇿",
    "DE": "🇩🇪",
    "GB": "🇬🇧",
    "US": "🇺🇸",
    "IR": "🇮🇷",
    "FI": "🇫🇮",
    "FR": "🇫🇷",
    "HU": "🇭🇺",
    "IT": "🇮🇹",
    "JP": "🇯🇵",
    "KR": "🇰🇷",
    "LT": "🇱🇹",
    "NL": "🇳🇱",
    "PL": "🇵🇱",
    "BR": "🇧🇷",
    "RO": "🇷🇴",
    "RU": "🇷🇺",
    "TH": "🇹🇭",
    "TR": "🇹🇷",
    "UA": "🇺🇦",
    "VN": "🇻🇳",
    "CN": "🇨🇳",
    "TW": "🇹🇼",
}

def _print_locale_menu(default_code: str | None):
    print("\n🌐 Quartz Locale")
    print("Choose the language/region for Quartz UI (dates, labels, etc.).")
    for i, code in enumerate(LOCALE_CODES, start=1):
        label = LOCALE_LABELS.get(code, "")
        # Pull region part (after '-') for flag lookup, if present
        parts = code.split("-")
        flag = LOCALE_FLAGS.get(parts[1], "") if len(parts) == 2 else ""
        marker = "  ← default" if default_code == code else ""
        # Show: "  1. fr-FR — French (France) 🇫🇷"
        if label:
            print(f"  {i:>2}. {code} — {label} {flag}{marker}")
        else:
            print(f"  {i:>2}. {code}{marker}")

def prompt_quartz_locale(saved_config: dict) -> str:
    """
    Prompt for a locale code restricted to LOCALE_CODES.
    Returns the selected code (e.g., 'en-US'). Default is saved_config['locale'] or 'en-US'.
    """
    saved = (saved_config.get("locale") or "").strip()
    default_code = saved if saved in LOCALE_CODES else ("en-US" if "en-US" in LOCALE_CODES else LOCALE_CODES[0])
    _print_locale_menu(default_code)
    prompt_label = f"Select 1-{len(LOCALE_CODES)} or type a code [Default: {default_code}]: "

    while True:
        choice = input(prompt_label).strip()
        if choice == "":
            return default_code
        if choice.isdigit():
            n = int(choice)
            if 1 <= n <= len(LOCALE_CODES):
                return LOCALE_CODES[n - 1]
        # Allow typing the code directly
        if choice in LOCALE_CODES:
            return choice
        print("Please choose a valid number or locale code from the list.")

def _print_font_pair_menu(default_idx: int | None = None):
    print("\n🅰️  Choose a header/body font pairing (Google Fonts):")
    for i, (hdr, body) in enumerate(FONT_PAIRINGS, start=1):
        marker = "  ← default" if default_idx == i else ""
        print(f"  {i}. {hdr}  —  {body}{marker}")
    marker7 = "  ← default" if default_idx == 7 else ""
    marker8 = "  ← default" if default_idx == 8 else ""
    print(f"  7. System fonts (Helvetica, Arial){marker7}")
    print(f"  8. Enter a custom pair (e.g., 'DM Sans, Inter'){marker8}")

def _print_code_font_menu(default_idx: int | None = None):
    print("\n👨‍💻 Choose a code font (monospaced, Google Fonts):")
    for i, name in enumerate(CODE_FONTS, start=1):
        marker = "  ← default" if default_idx == i else ""
        print(f"  {i}. {name}{marker}")
    marker7 = "  ← default" if default_idx == 7 else ""
    print(f"  7. Enter a custom code font (e.g., 'Cascadia Code'){marker7}")

def prompt_font_pairing(previous_default: dict | None) -> tuple[str, str]:
    """
    Returns (header, body). If a previous default exists, it becomes the real default:
      - If it matches one of the 1–6 pairings, that index is default.
      - If it's Helvetica/Arial, option 7 is default.
      - Otherwise, option 8 (custom) is default, pressing ENTER keeps the prior values.
    """
    # Compute which option should be the default based on previous_default
    def find_pair_index(h: str, b: str) -> int | None:
        for i, (hdr, body) in enumerate(FONT_PAIRINGS, start=1):
            if hdr == h and body == b:
                return i
        return None

    prev_header = (previous_default or {}).get("header")
    prev_body   = (previous_default or {}).get("body")

    default_idx: int
    if prev_header and prev_body:
        if prev_header.strip() == "Helvetica, Arial" and prev_body.strip() == "Helvetica, Arial":
            default_idx = 7
        else:
            idx = find_pair_index(prev_header.strip(), prev_body.strip())
            default_idx = idx if idx is not None else 8
    else:
        default_idx = 7  # first run: show system default as recommended pairing

    _print_font_pair_menu(default_idx=default_idx)
    if previous_default:
        print(f"\nLast used fonts: header='{prev_header}', body='{prev_body}'")

    prompt_label = f"Select 1-8 [Default: {default_idx}]: "
    while True:
        choice = input(prompt_label).strip()
        if choice == "":
            # User accepts the default
            if 1 <= default_idx <= 6:
                return FONT_PAIRINGS[default_idx - 1]
            if default_idx == 7:
                return "Helvetica, Arial", "Helvetica, Arial"
            # default_idx == 8 → keep the previous custom values if available
            if prev_header and prev_body:
                return prev_header, prev_body
            # fallback if somehow no previous custom
            return "Schibsted Grotesk", "Source Sans Pro"

        if choice in [str(i) for i in range(1, 9)]:
            n = int(choice)
            if 1 <= n <= 6:
                hdr, body = FONT_PAIRINGS[n - 1]
                print(f"✅ Selected: Header '{hdr}' with Body '{body}'")
                return hdr, body
            if n == 7:
                print("Using system-safe fonts. (Quartz will use CSS fallbacks.)")
                return "Helvetica, Arial", "Helvetica, Arial"
            if n == 8:
                # Let the user easily keep prior custom values via defaults
                hdr = prompt_with_default("Enter header font family", prev_header or "Schibsted Grotesk")
                body = prompt_with_default("Enter body font family",   prev_body   or "Source Sans Pro")
                print(f"✅ Selected: Header '{hdr}' with Body '{body}'")
                return hdr, body

        print("Please choose a number between 1 and 8.")

def prompt_code_font(previous_default: str | None) -> str:
    # Determine default index from previous_default
    if previous_default and previous_default in CODE_FONTS:
        default_idx = CODE_FONTS.index(previous_default) + 1
    elif previous_default:
        default_idx = 7  # custom previously used
    else:
        default_idx = 3  # IBM Plex Mono

    _print_code_font_menu(default_idx=default_idx)
    if previous_default:
        print(f"\nLast used code font: '{previous_default}'")

    prompt_label = f"Select 1-7 [Default: {default_idx}]: "
    while True:
        choice = input(prompt_label).strip()
        if choice == "":
            # Accept default
            if 1 <= default_idx <= 6:
                return CODE_FONTS[default_idx - 1]
            if default_idx == 7:
                return previous_default or "IBM Plex Mono"
            # Fallback
            return "IBM Plex Mono"

        if choice in [str(i) for i in range(1, 8)]:
            n = int(choice)
            if 1 <= n <= 6:
                print(f"✅ Selected code font: '{CODE_FONTS[n - 1]}'")
                return CODE_FONTS[n - 1]
            if n == 7:
                custom = prompt_with_default("Enter code font family", previous_default or "IBM Plex Mono")
                print(f"✅ Selected code font: '{custom}'")
                return custom

        print("Please choose a number between 1 and 7.")

def select_fonts_for_sections(section_numbers: list[int], saved_config: dict) -> dict:
    """
    Prompts for per-section font choices, suggesting consistency across sections.
    Returns a dict like:
    {
      "default": {"header": "...", "body": "...", "code": "..."},
      "sections": {"section3": {...}, "section4": {...}}
    }
    """
    print("\n🔤 Typography")
    print("You'll now choose fonts. We strongly recommend keeping font choices consistent across sections.\n")

    prev = (saved_config.get("fonts") or {}).get("default") or {}
    header, body = prompt_font_pairing(prev)
    code_font = prompt_code_font(prev.get("code") if prev else None)

    fonts = {
        "default": {"header": header, "body": body, "code": code_font},
        "sections": {}
    }

    prev_sections = ((saved_config.get("fonts") or {}).get("sections") or {})

    for sec in section_numbers:
        section_key = f"section{sec}"
        prior = prev_sections.get(section_key, {})
        print(f"\nSection {sec}:")
        print(f"Press ENTER to use default → header='{header}', body='{body}', code='{code_font}'")
        if prior:
            print(f"(Last time you used: header='{prior.get('header')}', body='{prior.get('body')}', code='{prior.get('code')}')")

        use_default = input("Keep defaults for this section? (y/ENTER to keep, 'n' to customize): ").strip().lower()
        if use_default in ("", "y", "yes"):
            fonts["sections"][section_key] = {"header": header, "body": body, "code": code_font}
        else:
            sh, sb = prompt_font_pairing(prior or fonts["default"])
            sc = prompt_code_font((prior or fonts["default"]).get("code"))
            fonts["sections"][section_key] = {"header": sh, "body": sb, "code": sc}

    return fonts
    
# ---------- Header emoji selection helpers (per-section only) ----------------

PRESET_HEADER_EMOJIS = [
    "📚", "🎓", "🏫", "✏️", "📝", "📐",
    "📊", "🧪", "🔬", "🔭", "🧬", "🖥️",
]

def _looks_like_single_emoji(s: str) -> bool:
    """
    Heuristic to accept a single emoji (optionally with variation selectors/skin tone).
    Rejects spaces/alphanumerics; allows one primary symbol plus modifiers.
    Note: complex ZWJ sequences (e.g., family emojis) are intentionally rejected.
    """
    s = (s or "").strip()
    if not s or any(ch.isspace() for ch in s):
        return False
    for ch in s:
        if ch.isalnum():
            return False
    SKIN_TONES = {0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF}
    ZWJ = 0x200D
    VARIATION_SELECTORS = {0xFE0E, 0xFE0F}
    base_count = 0
    for ch in s:
        cp = ord(ch)
        if cp in VARIATION_SELECTORS or cp == ZWJ or cp in SKIN_TONES:
            continue
        base_count += 1
        if base_count > 1:
            return False
    return base_count == 1

def prompt_single_emoji(prompt_text: str, default_emoji: str) -> str:
    """Prompt for one emoji with a menu of presets or custom entry; stateful default supported."""
    print(f"\n{prompt_text}")
    print("Choose one of the presets, or enter your own single emoji.")
    for i, emo in enumerate(PRESET_HEADER_EMOJIS, start=1):
        print(f"  {i:>2}. {emo}")
    print("  13. Enter a custom emoji")
    choice = input(f"Select 1-13 [Default: {default_emoji}]: ").strip()

    if choice == "":
        return default_emoji
    if choice.isdigit():
        n = int(choice)
        if 1 <= n <= 12:
            return PRESET_HEADER_EMOJIS[n - 1]
        if n == 13:
            custom = input("Enter a single emoji: ").strip()
            if _looks_like_single_emoji(custom):
                return custom
            print("⚠️ That doesn't look like a single emoji. Keeping default.")
            return default_emoji
    if _looks_like_single_emoji(choice):
        return choice
    print("⚠️ Invalid selection. Keeping default.")
    return default_emoji

def select_header_emojis_for_sections(section_numbers: list[int], saved_config: dict) -> dict:
    """
    Returns:
    {
      "sections": { "section1": "📚", "section3": "🔬", ... }
    }
    (No course-level default is stored.)
    """
    print("\n🔣 Section Header Emojis")
    print("Pick a single emoji for each section. (e.g., 📚)")
    print("Tip: Press ENTER to keep the shown default from a previous run.\n")

    prev_emojis = (saved_config.get("emojis") or {})
    # Back-compat: if an older config had a course-level default, we only use it as a suggestion
    prev_default = prev_emojis.get("default")
    prev_sections = prev_emojis.get("sections") if isinstance(prev_emojis.get("sections"), dict) else {}

    result_sections = {}
    for sec in section_numbers:
        section_key = f"section{sec}"
        prior_for_section = prev_sections.get(section_key)
        suggested = prior_for_section or prev_default or PRESET_HEADER_EMOJIS[0]
        chosen = prompt_single_emoji(
            f"Choose header emoji for Section {sec}:", suggested
        )
        result_sections[section_key] = chosen

    return {"sections": result_sections}

# ---------- NEW: Per-section SECTION MARKER visibility ----------------------

def select_section_marker_visibility_for_sections(section_numbers: list[int], saved_config: dict) -> dict:
    """
    Ask for each section whether the title should include the section marker (e.g., 'S1').
    Default: True (show marker). Saves per-section booleans.
    Returns:
    {
      "sections": { "section1": true, "section3": false, ... }
    }
    """
    print("\n🔖 Section Title Marker")
    print("Decide whether to show the section indicator (e.g., 'S1') in the site title for each section.")
    prev_map = {}
    raw_prev = (saved_config.get("show_section_marker") or {})
    if isinstance(raw_prev, dict):
        prev_map = raw_prev.get("sections") or {}
        if not isinstance(prev_map, dict):
            prev_map = {}

    result = {}
    for sec in section_numbers:
        key = f"section{sec}"
        prev_val = prev_map.get(key, True)
        # Coerce previous to bool if it was stored as a string in older configs
        if isinstance(prev_val, str):
            prev_val_bool = prev_val.strip().lower() in ("1", "true", "yes", "y")
        else:
            prev_val_bool = bool(prev_val)
        choice = prompt_yes_no_default(
            f"Show section marker in the site title for Section {sec}? (example: 'S{sec}')",
            prev_val_bool
        )
        result[key] = bool(choice)

    return {"sections": result}

# ---------- Hardened Explorer patch helpers ---------------------------------

EXPLORER_BLOCK = """Component.Explorer({
    folderClickBehavior: "link",
    filterFn: (node) => {
      // CQ4T-OMIT-ANCHOR: do not remove this line; build script overwrites this Set
      const omit = new Set<string>([""]);
      if (node.isFolder) {
        return !omit.has(node.fileSegmentHint);
      } else {
        return !omit.has(node.data.title);
      }
    },
  })"""

def _patch_explorer_with_anchor(layout_src: str) -> tuple[str, bool]:
    """
    Replace the Explorer component (simple or configured) with our anchored version.
    Returns (new_src, changed).
    """
    changed = False

    # 1) Replace the simplest call: Component.Explorer()
    new_src, n1 = re.subn(r'Component\.Explorer\(\s*\)', EXPLORER_BLOCK, layout_src)
    if n1 > 0:
        return new_src, True

    # 2) Replace any configured Explorer: Component.Explorer({ ... })
    new_src, n2 = re.subn(r'Component\.Explorer\(\s*\{[\s\S]*?\}\s*\)', EXPLORER_BLOCK, new_src)
    if n2 > 0:
        return new_src, True

    # 3) If there's an Explorer somewhere *without* our anchor but our regex failed, try a lighter touch:
    #    Ensure an omit Set line with anchor exists inside any existing filterFn.
    def ensure_anchor_in_filterfn(m: re.Match) -> str:
        block = m.group(0)
        if "CQ4T-OMIT-ANCHOR" in block:
            return block  # already anchored

        # Try to insert our omit line after the opening brace of filterFn
        block2, n = re.subn(
            r'(filterFn\s*:\s*\(\s*node\s*\)\s*=>\s*\{\s*)',
            r'\1\n      // CQ4T-OMIT-ANCHOR: do not remove this line; build script overwrites this Set\n'
            r'      const omit = new Set<string>([""]);\n',
            block,
            count=1
        )
        return block2 if n > 0 else block

    new_src2, n3 = re.subn(r'Component\.Explorer\(\s*\{[\s\S]*?\}\s*\)', ensure_anchor_in_filterfn, layout_src)
    if n3 > 0 and new_src2 != layout_src:
        return new_src2, True

    return layout_src, changed

def _scaffold_is_bundled_runtime() -> bool:
    """
    True when the Quartz scaffold is the app's bundled native runtime — a
    folder shared by every working folder and pre-baked with these patches
    by fetch-runtime.ps1. The wizard must never write there: a write races
    concurrent builds, and an installed copy may not be writable at all.
    """
    runtime = os.environ.get("PLANTOIR_RUNTIME", "").strip()
    if not runtime:
        return False
    try:
        toolchain_paths.QUARTZ_DIR.resolve().relative_to(Path(runtime).resolve())
        return True
    except (ValueError, OSError):
        return False




def ensure_quartz_explorer_anchor():
    """Idempotently ensure quartz.layout.ts includes the omit anchor block."""
    if _scaffold_is_bundled_runtime():
        print("ℹ️ The bundled website builder already carries the Explorer anchor (no change).")
        return
    quartz_layout_path = toolchain_paths.QUARTZ_DIR / "quartz.layout.ts"
    if quartz_layout_path.exists():
        with open(quartz_layout_path, "r", encoding="utf-8") as f:
            content = f.read()

        new_content, changed = _patch_explorer_with_anchor(content)

        if changed:
            result = toolchain_paths.write_file(quartz_layout_path, new_content.encode("utf-8"))
            if result.returncode == 0:
                print(f"✅ Ensured Explorer has omit anchor in {quartz_layout_path}")
            else:
                print(f"❌ Failed to write updated layout. Error:\n{result.stderr.decode()}")
        else:
            if "CQ4T-OMIT-ANCHOR" in content:
                print("ℹ️ Explorer already contains omit anchor (no change).")
            else:
                print("⚠️ Could not locate Component.Explorer() to patch. You may need to update quartz.layout.ts manually.")
    else:
        print(f"⚠️ quartz.layout.ts not found at: {quartz_layout_path}")

# ---------- NEW: OverflowList stable ID patch (idempotent) -------------------

def ensure_quartz_overflowlist_static_id():
    if _scaffold_is_bundled_runtime():
        print("ℹ️ The bundled website builder already carries the stable OverflowList id (no change).")
        return
    """
    Idempotently ensure OverflowList uses a stable, non-random id to avoid noisy diffs:
      const id = randomIdNonSecure()   →   const id = "j8p48f"
    Targets: /opt/quartz/quartz/components/OverflowList.tsx
    """
    tsx_path = toolchain_paths.QUARTZ_DIR / "quartz" / "components" / "OverflowList.tsx"
    if not tsx_path.exists():
        print(f"⚠️ OverflowList.tsx not found at: {tsx_path}")
        return

    try:
        with open(tsx_path, "r", encoding="utf-8") as f:
            src = f.read()
    except Exception as e:
        print(f"❌ Failed to read {tsx_path}: {e}")
        return

    # Already patched?
    if re.search(r'const\s+id\s*=\s*["\']j8p48f["\']', src):
        print("ℹ️ OverflowList already uses a stable id (no change).")
        return

    # Replace only the first occurrence; be tolerant of an optional namespace (e.g., utils.randomIdNonSecure())
    pattern = r'const\s+id\s*=\s*(?:\w+\.)?randomIdNonSecure\s*\(\s*\)'
    new_src, n = re.subn(pattern, 'const id = "j8p48f"', src, count=1)

    if n == 0:
        print("⚠️ Could not find 'const id = randomIdNonSecure()' in OverflowList.tsx; no changes made.")
        return

    result = toolchain_paths.write_file(tsx_path, new_src.encode("utf-8"))
    if result.returncode == 0:
        print(f"✅ Patched OverflowList to use a stable id in {tsx_path}")
    else:
        print(f"❌ Failed to write updated OverflowList.tsx. Error:\n{result.stderr.decode()}")

# ---------- NEW: Example Course installer -----------------------------------

EXAMPLE_COURSE_CODE = "EXC2O"

CANDIDATE_EXAMPLE_SOURCE_PATHS = [
    Path("support/example_course") / EXAMPLE_COURSE_CODE,
    toolchain_paths.SUPPORT_DIR / "example_course" / EXAMPLE_COURSE_CODE,
    Path(__file__).resolve().parent.parent / "support" / "example_course" / EXAMPLE_COURSE_CODE,
    Path(__file__).resolve().parent / "support" / "example_course" / EXAMPLE_COURSE_CODE,
]

def _find_example_source_dir() -> Path | None:
    for p in CANDIDATE_EXAMPLE_SOURCE_PATHS:
        if p.exists() and p.is_dir():
            return p
    return None

def _generate_alt_example_code(dest_root: Path) -> str:
    """
    Generate a 5-char alternative course code ending with '2O' that does not collide.
    Uses three random uppercase letters for the prefix.
    """
    letters = string.ascii_uppercase
    for _ in range(100):
        prefix = "".join(random.choice(letters) for _ in range(3))
        candidate = f"{prefix}2O"
        if not (dest_root / candidate).exists():
            return candidate
    # Fallback deterministic slug if somehow everything collides
    i = 1
    while (dest_root / f"EX{i:02d}2O").exists():
        i += 1
    return f"EX{i:02d}2O"

def _copy_example_course(src: Path, dest: Path, dest_code: str) -> bool:
    """
    Copy the example course, then make its configuration agree with the folder
    it now lives in. Without the rewrite, a course installed under an alternate
    code still calls itself EXC2O everywhere the config is read.
    """
    try:
        shutil.copytree(src, dest, dirs_exist_ok=False)
    except FileExistsError:
        print(f"⚠️ Destination {dest} already exists; skipping copy.")
        return False
    except Exception as e:
        print(f"❌ Failed to install Example Course: {e}")
        return False

    # The interactive wizard seeds .obsidian into every course it builds;
    # the example course must arrive equally ready to open as a vault.
    try:
        copy_obsidian_defaults(dest)
    except Exception as e:
        print(f"⚠️  Unable to install Obsidian defaults: {e}")

    config_path = dest / "course_config.json"
    if config_path.exists() and dest_code != EXAMPLE_COURSE_CODE:
        try:
            with open(config_path, "r", encoding="utf-8") as handle:
                config = json.load(handle)
            config["course_code"] = dest_code
            with open(config_path, "w", encoding="utf-8") as handle:
                json.dump(config, handle, indent=2)
                handle.write("\n")
            print(f"✅ Course code in course_config.json set to {dest_code}")
        except Exception as e:
            print(f"⚠️ Could not update course_config.json with the new code: {e}")

    print(f"✅ Example Course installed to: {dest}")
    return True


def install_example_course_noninteractive(courses_root: Path) -> bool:
    """
    Install the example course without asking anything. Used when the app
    offers the example course to a teacher who has never made one.
    """
    source = _find_example_source_dir()
    if not source:
        print("❌ Could not find the example course content.")
        return False

    dest_code = EXAMPLE_COURSE_CODE
    dest = courses_root / dest_code
    if dest.exists():
        dest_code = _generate_alt_example_code(courses_root)
        dest = courses_root / dest_code
        print(f"ℹ️ A course named {EXAMPLE_COURSE_CODE} already exists. Using {dest_code} instead.")

    if not _copy_example_course(source, dest, dest_code):
        return False

    ensure_quartz_explorer_anchor()
    ensure_quartz_overflowlist_static_id()
    # The app reads this line to learn which course was created.
    print(f"EXAMPLE_COURSE_CODE={dest_code}")
    return True


def maybe_install_example_course(courses_root: Path) -> bool:
    """
    Offer to install the Example Course (EXC2O) for new users.
    Copies support/example_course/EXC2O → /teaching/courses/EXC2O (or alt code if taken).
    If installed, ensure the Quartz Explorer omit anchor is present, show hint, and exit.
    Returns True if installed, False otherwise.
    """
    print("\n📦 Optional: Install an Example Course")
    print("The 'EXC2O' course (stands for 'Example Course') demonstrates how content is organized in Obsidian and how Quartz renders it into a site.")
    print("Recommended if you're NEW to this workflow — you can remove it later.")
    install = prompt_yes_no_default("Install the Example Course now?", default=False)
    if not install:
        return False

    src = _find_example_source_dir()
    if not src:
        print("⚠️ Could not find example course content at expected locations. Skipping installation.")
        return False

    dest_code = EXAMPLE_COURSE_CODE
    dest = courses_root / dest_code
    if dest.exists():
        # Generate an alternate code preserving '2O' as the final two characters
        alt = _generate_alt_example_code(courses_root)
        print(f"ℹ️ A course named '{dest_code}' already exists. Using alternate code: {alt}")
        dest_code = alt
        dest = courses_root / dest_code

    if not _copy_example_course(src, dest, dest_code):
        return False

    # Ensure Quartz patches so hidden items + stable IDs work in preview
    ensure_quartz_explorer_anchor()
    ensure_quartz_overflowlist_static_id()

    # Print final hint and exit early (as requested)
    print(f"✅ Example Course installed: {dest_code}")
    print("ℹ️ To preview this site, run:")
    print("   " + _cmd_example("preview", dest_code, 1, _HOST_OS))
    print("   (Then open http://localhost:8081 in your browser.)")
    sys.exit(0)
    return True  # not reached

# ---------- Per-course-code example content ---------------------------------
#
# Unlike the standalone Example Course (EXC2O) above, which is copied whole
# under its own code, example CONTENT is poured into a course the teacher is
# creating under their real course code. Each payload lives at
# support/example_content/<CODE>/ and is shaped like this:
#
#   <CODE>/
#     manifest.json      — which folders/files the payload provides, plus
#                          which of them to hide or make expandable, and the
#                          name of the curriculum folder (if any)
#     shared/            — copied into the course root
#     per_section/       — copied into every sectionN/ folder
#
# Two rules keep the install safe to re-run: nothing ever overwrites a file
# that already exists, and only items the teacher kept in the structure
# lists are installed.

EXAMPLE_CONTENT_ROOTS = [
    Path("support/example_content"),
    toolchain_paths.SUPPORT_DIR / "example_content",
    Path(__file__).resolve().parent.parent / "support" / "example_content",
]

# Replaced with the course's real creation timestamp at install time, so
# payload pages need no hardcoded dates.
EXAMPLE_CONTENT_CREATED_SENTINEL = "__CREATED__"

# Class pages instead carry `__CREATED_CLASS_K__`, where K is the class's
# position in the course (1 = the first class of the year). The installer
# turns these into REAL, DISTINCT dates spread across the semester, because
# the All Classes listing sorts by date — with identical dates the most
# recent class cannot float to the top.
EXAMPLE_CONTENT_CLASS_SENTINEL = re.compile(r"__CREATED_CLASS_(\d+)__")


# How many school days pass between one class page and the next. A payload
# sets this in its manifest as `class_weekday_step`: 1 for a course that
# meets every school day — the shape of a 110-hour semestered credit, about
# 86 periods from September to January — and 2 for one that meets every
# other day. Payloads that say nothing keep the every-other-day spacing
# their arcs were written for.
DEFAULT_CLASS_WEEKDAY_STEP = 2


def is_school_day(date) -> bool:
    """
    Weekends and the two fixed holidays a September-to-January course runs
    into: the winter break, and Thanksgiving Monday. A daily arc of about
    86 periods crosses both, and a class page dated December 25 would be
    the first thing a teacher noticed. PA days and board-specific closures
    are NOT modelled — they differ by board, and a date that is a day or
    two out reads as a timetable difference rather than an error.
    """
    if date.weekday() >= 5:
        return False
    if (date.month, date.day) >= (12, 22) or (date.month, date.day) <= (1, 2):
        return False
    if date.month == 10 and date.weekday() == 0 and 8 <= date.day <= 14:
        return False                          # Thanksgiving Monday
    return True


def semester_class_timestamp(class_ordinal: int, reference,
                             weekday_step: int = DEFAULT_CLASS_WEEKDAY_STEP,
                             start_school_day: int = 1) -> str:
    """
    The `created:` timestamp for the K-th class of the semester: at 07:00,
    `weekday_step` school days apart, anchored at September 8 of the current
    school year (the year whose September has most recently begun, or is
    about to). Matches the semestered September-to-January shape of the
    example content, and the 07:00 convention real courses here use.

    `start_school_day` moves the anchor later, counted in school days. It
    exists for HALF CREDITS, which are commonly timetabled back to back:
    Career Studies runs from September and Civics picks up the same period
    when it ends. The second course declares where it starts rather than
    both courses claiming September, which would date two different
    courses onto the same mornings.

    The walk is done on a NAIVE date, and the offset attached only at the
    end. A semester crosses the change off daylight time in November, so
    borrowing the offset that happened to be in force when setup ran would
    stamp every class after it an hour out.
    """
    year = reference.year if reference.month >= 8 else reference.year - 1
    date = datetime(year, 9, 8, 7, 0, 0)
    while not is_school_day(date):
        date += timedelta(days=1)
    remaining_steps = ((class_ordinal - 1) * max(1, weekday_step)
                       + max(0, start_school_day - 1))
    while remaining_steps > 0:
        date += timedelta(days=1)
        if is_school_day(date):
            remaining_steps -= 1
    return date.astimezone().strftime("%Y-%m-%dT%H:%M:%S.000%z")


def replacing_class_sentinels(text: str, reference,
                              weekday_step: int = DEFAULT_CLASS_WEEKDAY_STEP,
                              start_school_day: int = 1) -> str:
    def replace(match):
        return semester_class_timestamp(int(match.group(1)), reference,
                                        weekday_step, start_school_day)
    return EXAMPLE_CONTENT_CLASS_SENTINEL.sub(replace, text)


def first_use_dates(payload_dir: Path, reference,
                    weekday_step: int = DEFAULT_CLASS_WEEKDAY_STEP,
                    start_school_day: int = 1) -> dict:
    """
    Page name -> the date of the FIRST class that links to it. A concept
    taught on Unit 3, Day 5 should carry Unit 3, Day 5's date — that is
    what lets each category page (Conventions, Discussions, ...) list its
    pages in the order the course actually met them, which has meaning
    for students. Pages no class links to are absent from the map and
    inherit the first class date (Unit 1, Day 1) or the install-time date.
    """
    per_section_root = payload_dir / "per_section"
    class_pages = []
    class_date_by_stem = {}
    if per_section_root.is_dir():
        for page in per_section_root.rglob("*.md"):
            with open(page, "r", encoding="utf-8") as handle:
                text = handle.read()
            match = EXAMPLE_CONTENT_CLASS_SENTINEL.search(text)
            if match:
                ordinal = int(match.group(1))
                class_pages.append((ordinal, text))
                class_date = semester_class_timestamp(ordinal, reference, weekday_step,
                                                      start_school_day)
                class_date_by_stem[page.stem] = class_date
    class_pages.sort()

    link_target_pattern = re.compile(r"!?\[\[([^\]#|]+)")
    dates = {}
    for ordinal, text in class_pages:
        class_date = semester_class_timestamp(ordinal, reference, weekday_step,
                                              start_school_day)
        for match in link_target_pattern.finditer(text):
            target = match.group(1).strip().split("/")[-1]
            if target and target != "index" and target not in dates:
                dates[target] = class_date

    # The section landing page (index.md) carries the date of the class it
    # transcludes (e.g. Unit 4, Day 20 or Unit 1, Day 1).
    index_file = per_section_root / "index.md"
    if index_file.is_file():
        with open(index_file, "r", encoding="utf-8") as handle:
            index_text = handle.read()
        for match in link_target_pattern.finditer(index_text):
            target = match.group(1).strip().split("/")[-1]
            if target in class_date_by_stem:
                dates["index"] = class_date_by_stem[target]
                break

    return dates

# Content that only makes sense alongside the curriculum pages sits between
# these markers (Obsidian comments, so they are invisible on the site even
# if something goes wrong). With curriculum pages excluded, the whole block
# goes; with them included, only the marker lines go.
CURRICULUM_BLOCK_START = "%%curriculum-start%%"
CURRICULUM_BLOCK_END = "%%curriculum-end%%"


def find_example_content_dir(course_code: str) -> Path | None:
    """The payload folder for this course code, or None when there is none."""
    for root in EXAMPLE_CONTENT_ROOTS:
        candidate = root / course_code
        if candidate.is_dir() and (candidate / "manifest.json").exists():
            return candidate
    return None


def load_example_content_manifest(payload_dir: Path) -> dict:
    with open(payload_dir / "manifest.json", "r", encoding="utf-8") as handle:
        return json.load(handle)


SKELETON_ROOTS = [
    Path("support/skeletons"),
    toolchain_paths.SUPPORT_DIR / "skeletons",
    Path(__file__).resolve().parent.parent / "support" / "skeletons",
]


def find_skeleton_dir(course_code: str) -> Path | None:
    """
    The starting skeleton for this course code.

    A couple of dozen course codes have real example content, and the list
    grows; every other Ontario
    code gets a skeleton shaped for its SUBJECT — a drama course opens with
    Conventions and Warm-Ups, a chemistry course with Investigations and
    Safety in the Lab. The mapping is by three-letter prefix (ADA, SCH,
    MCV…), falling back to the generic skeleton for club and custom codes.
    """
    prefix = (course_code or "")[:3].upper()
    for root in SKELETON_ROOTS:
        families_file = root / "families.json"
        if not families_file.exists():
            continue
        try:
            with open(families_file, "r", encoding="utf-8") as handle:
                families = json.load(handle)
        except Exception:
            continue
        name = families.get("prefixes", {}).get(prefix) or families.get("default")
        if not name:
            continue
        candidate = root / name
        if candidate.is_dir() and (candidate / "manifest.json").exists():
            return candidate
    return None


def curriculum_page_names(payload_dir: Path, manifest: dict) -> set:
    """The page names (file stems) of every curriculum page in the payload."""
    folder_name = manifest.get("curriculum_folder")
    if not folder_name:
        return set()
    curriculum_dir = payload_dir / "shared" / folder_name
    names = set()
    if curriculum_dir.is_dir():
        for page in curriculum_dir.rglob("*.md"):
            if page.stem != "index":
                names.add(page.stem)
    return names


def strip_curriculum_blocks(text: str, keep_content: bool) -> str:
    """
    With keep_content True, only the marker lines are removed. With it
    False, everything between the markers goes too.
    """
    result_lines = []
    inside_block = False
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped == CURRICULUM_BLOCK_START:
            inside_block = True
            continue
        if stripped == CURRICULUM_BLOCK_END:
            inside_block = False
            continue
        if inside_block and not keep_content:
            continue
        result_lines.append(line)
    return "\n".join(result_lines)


def unlink_curriculum_references(text: str, page_names: set) -> str:
    """
    With the curriculum pages absent, links to them must not dangle. A
    transclusion line (`![[A1.1]]`) disappears entirely; an inline link
    becomes its visible words (`[[A1.1|the expectation]]` -> the words,
    `[[A1.1]]` -> A1.1).
    """
    if not page_names:
        return text

    def replace_link(match):
        is_transclusion = match.group(1) == "!"
        target = match.group(2).strip()
        alias = match.group(4)
        if target not in page_names:
            return match.group(0)
        if is_transclusion:
            return ""
        if alias is not None:
            return alias
        return target

    link_pattern = re.compile(r"(!?)\[\[([^\]#|]+)(#[^\]|]*)?(?:\|([^\]]*))?\]\]")

    result_lines = []
    for line in text.split("\n"):
        replaced = link_pattern.sub(replace_link, line)
        # A line that held only a transclusion (possibly inside a callout)
        # would otherwise linger as an empty shell.
        if replaced != line and replaced.strip() in ("", ">"):
            continue
        result_lines.append(replaced)
    return "\n".join(result_lines)


def per_section_frontmatter(text: str, section_numbers: list) -> str:
    """
    Give a course-level page one `created`/`publish` pair PER SECTION.

    A page at the course root is shared by every section, but the sections
    are not in step: one class may have covered the material a day later,
    or not yet at all. Quartz reads `createdSectionN` / `publishForSectionN`
    at build time (see `process_frontmatter` in build_site.py) and resolves
    them to the plain keys for the section being built, so splitting them
    here is what lets a teacher publish a page to one section and hold it
    back from another.

    Visibility is read from either key and always written as
    `publishForSectionN`. `draft:` is the older spelling with the opposite
    polarity, so it is inverted on the way through; a page carrying only
    `draft:` that came out unsplit would silently share one publish state
    across every section, which is the bug this function exists to prevent.

    Only the frontmatter block is touched — a `draft: true` shown inside a
    fenced code block on a tutorial page is documentation, not metadata.
    """
    if not section_numbers or not text.startswith("---\n"):
        return text
    end = text.find("\n---", 4)
    if end < 0:
        return text
    head = text[4:end]
    rest = text[end:]

    values = {}
    for line in head.split("\n"):
        match = re.match(r"^(created|draft|publish):[ \t]*(.*)$", line)
        if match:
            values.setdefault(match.group(1), match.group(2))
    if not values:
        return text

    if "publish" in values:
        publish = values["publish"]
    elif "draft" in values:
        publish = "false" if values["draft"].strip().lower() == "true" else "true"
    else:
        publish = None

    # Written section by section, so a teacher scanning the top of a page
    # reads each section's pair together.
    block = []
    for number in section_numbers:
        if "created" in values:
            block.append(f"createdSection{number}: {values['created']}")
        if publish is not None:
            block.append(f"publishForSection{number}: {publish}")

    out = []
    for line in head.split("\n"):
        if re.match(r"^(created|draft|publish):", line):
            if block:
                out.extend(block)
                block = []
            continue
        out.append(line)
    return "---\n" + "\n".join(out) + rest


def install_payload_file(source: Path, destination: Path, now_str: str,
                         include_curriculum: bool, page_names: set,
                         section_number: int | None = None,
                         reference=None,
                         first_use_date: str | None = None,
                         shared_sections: list | None = None,
                         course_code: str | None = None,
                         course_name: str | None = None,
                         weekday_step: int = DEFAULT_CLASS_WEEKDAY_STEP,
                         start_school_day: int = 1) -> bool:
    """
    One file from payload to course. Markdown is adjusted on the way
    through; everything else is copied as-is. Existing files are never
    touched. Returns True when a file was written.
    """
    if destination.exists():
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.suffix.lower() != ".md":
        shutil.copy2(source, destination)
        return True
    with open(source, "r", encoding="utf-8") as handle:
        text = handle.read()
    if reference is not None:
        text = replacing_class_sentinels(text, reference, weekday_step,
                                         start_school_day)
    if first_use_date is not None:
        text = text.replace(
            f"created: {EXAMPLE_CONTENT_CREATED_SENTINEL}",
            f"created: {first_use_date}"
        )
    text = text.replace(EXAMPLE_CONTENT_CREATED_SENTINEL, now_str)
    if section_number is not None:
        text = text.replace("__SECTION_NUMBER__", str(section_number))
    if course_code:
        text = text.replace("__COURSE_CODE__", course_code)
    if course_name:
        text = text.replace("__COURSE_NAME__", course_name)
    text = strip_curriculum_blocks(text, keep_content=include_curriculum)
    if not include_curriculum:
        text = unlink_curriculum_references(text, page_names)
    if shared_sections:
        text = per_section_frontmatter(text, shared_sections)
    with open(destination, "w", encoding="utf-8") as handle:
        handle.write(text)
    return True


def install_example_content(course_path: Path, payload_dir: Path, manifest: dict,
                            section_numbers: list, now_str: str,
                            include_curriculum: bool,
                            shared_folders: list, shared_files: list,
                            per_section_folders: list, per_section_files: list,
                            reference=None,
                            course_code: str | None = None,
                            course_name: str | None = None) -> int:
    """
    Pour the payload into the course. Only top-level items the teacher kept
    in the structure lists are installed; the curriculum folder also needs
    its own flag. Returns the number of files written.
    """
    page_names = curriculum_page_names(payload_dir, manifest)
    curriculum_folder = manifest.get("curriculum_folder")
    weekday_step = int(manifest.get("class_weekday_step", DEFAULT_CLASS_WEEKDAY_STEP))
    # Which school day the course's first class lands on. 1 for anything
    # starting in September; a later number for the second half credit in
    # a pair, which begins when the first one finishes.
    start_school_day = int(manifest.get("class_start_school_day", 1))
    class_use_dates = (first_use_dates(payload_dir, reference, weekday_step,
                                       start_school_day)
                       if reference is not None else {})
    first_class_date = (semester_class_timestamp(1, reference, weekday_step,
                                                start_school_day)
                        if reference is not None else None)
    written = 0

    def top_level_allowed(entry: Path, allowed_folders: list, allowed_files: list) -> bool:
        if entry.name == curriculum_folder:
            return include_curriculum and entry.name in allowed_folders
        if entry.is_dir():
            return entry.name in allowed_folders
        # A payload's index.md is the landing page of the folder it sits
        # in (e.g. the section's own front page) — always welcome.
        if entry.name == "index.md":
            return True
        return entry.name in allowed_files

    shared_root = payload_dir / "shared"
    if shared_root.is_dir():
        for entry in sorted(shared_root.iterdir()):
            if not top_level_allowed(entry, shared_folders, shared_files):
                continue
            sources = entry.rglob("*") if entry.is_dir() else [entry]
            for source in sources:
                if source.is_dir():
                    continue
                destination = course_path / source.relative_to(shared_root)
                if install_payload_file(source, destination, now_str,
                                        include_curriculum, page_names,
                                        first_use_date=class_use_dates.get(source.stem) or first_class_date,
                                        shared_sections=section_numbers,
                                        course_code=course_code,
                                        course_name=course_name):
                    written += 1

    per_section_root = payload_dir / "per_section"
    if per_section_root.is_dir():
        for sec in section_numbers:
            section_path = course_path / f"section{sec}"
            for entry in sorted(per_section_root.iterdir()):
                if not top_level_allowed(entry, per_section_folders, per_section_files):
                    continue
                sources = entry.rglob("*") if entry.is_dir() else [entry]
                for source in sources:
                    if source.is_dir():
                        continue
                    destination = section_path / source.relative_to(per_section_root)
                    if install_payload_file(source, destination, now_str,
                                            include_curriculum, page_names,
                                            section_number=sec,
                                            reference=reference,
                                            first_use_date=class_use_dates.get(source.stem) or first_class_date,
                                            course_code=course_code,
                                            course_name=course_name,
                                            weekday_step=weekday_step,
                                            start_school_day=start_school_day):
                        written += 1

    return written


# ---------- NEW: Timetable section numbers prompt ---------------------------

def prompt_section_numbers(num_sections: int, saved_config: dict) -> list[int]:
    """
    Ask the teacher to enter the timetable section numbers (e.g., 1,3,4).
    Enforces uniqueness and exact count == num_sections.
    """
    prev = saved_config.get("section_numbers")
    if isinstance(prev, list) and prev:
        default_list = [int(x) for x in prev]
    else:
        default_list = list(range(1, num_sections + 1))
    default_str = ",".join(str(x) for x in default_list)

    print(f"\nYou indicated you teach {num_sections} section(s).")
    print("Enter the timetable section numbers for YOUR sections (e.g., 1,3,4).")
    entry = input(f"> [Default: {default_str}]: ").strip()

    if not entry:
        return default_list

    try:
        parts = [p.strip() for p in entry.split(",") if p.strip() != ""]
        nums = [int(p) for p in parts]
    except ValueError:
        print("Invalid input. Please enter comma-separated integers like 1,3,4.")
        return prompt_section_numbers(num_sections, saved_config)

    if len(nums) != num_sections:
        print(f"Please provide exactly {num_sections} unique numbers.")
        return prompt_section_numbers(num_sections, saved_config)
    if len(set(nums)) != len(nums):
        print("Duplicate numbers detected. Please enter unique section numbers.")
        return prompt_section_numbers(num_sections, saved_config)
    if any(n <= 0 for n in nums):
        print("Section numbers must be positive integers.")
        return prompt_section_numbers(num_sections, saved_config)

    return sorted(nums)

# ---------- NEW: Obsidian defaults copier -----------------------------------

CANDIDATE_OBSIDIAN_DEFAULTS_PATHS = [
    Path("support/obsidian_defaults") / ".obsidian",
    toolchain_paths.SUPPORT_DIR / "obsidian_defaults" / ".obsidian",
    Path(__file__).resolve().parent.parent / "support" / "obsidian_defaults" / ".obsidian",
    Path(__file__).resolve().parent / "support" / "obsidian_defaults" / ".obsidian",
]

def _find_obsidian_defaults_dir() -> Path | None:
    for p in CANDIDATE_OBSIDIAN_DEFAULTS_PATHS:
        if p.exists() and p.is_dir():
            return p
    return None

def copy_obsidian_defaults(course_dir: Path) -> None:
    """
    Copy support/obsidian_defaults/.obsidian into the given course_dir.
    - If course_dir/.obsidian already exists, merge without overwriting existing files.
    - If not found, print a warning and continue silently.
    """
    src = _find_obsidian_defaults_dir()
    if not src:
        print("⚠️  Obsidian defaults not found (support/obsidian_defaults/.obsidian). Skipping.")
        return

    dest = course_dir / ".obsidian"
    copied_count = 0
    skipped_count = 0

    dest.mkdir(parents=True, exist_ok=True)

    for root, dirs, files in os.walk(src):
        rel_root = Path(root).relative_to(src)
        target_root = dest / rel_root
        target_root.mkdir(parents=True, exist_ok=True)
        for fname in files:
            sfile = Path(root) / fname
            dfile = target_root / fname
            if dfile.exists():
                skipped_count += 1
                continue  # do not clobber teacher's existing settings
            try:
                shutil.copy2(sfile, dfile)
                copied_count += 1
            except Exception as e:
                print(f"⚠️  Could not copy '{sfile}' → '{dfile}': {e}")

    if copied_count > 0:
        print(f"✅ Obsidian defaults installed to {dest} ({copied_count} new file(s); {skipped_count} skipped).")
    else:
        print(f"ℹ️  Obsidian defaults already present at {dest} (no changes).")

# ---------- Main setup flow (baseline preserved + backups + defaults) -------

def setup_course(no_backup: bool = False):
    print("📚 Welcome to the Course Setup Script!\n")

    base_path = toolchain_paths.COURSES_DIR

    # --- NEW: Offer to install the Example Course (EXC2O) -------------------
    try:
        maybe_install_example_course(base_path)
    except SystemExit:
        # early exit is expected after example install
        return
    except Exception as e:
        print(f"⚠️ Example Course installation step encountered an error and will be skipped: {e}")

    default_code = "ICS3U"
    course_code = prompt_with_default("Enter the course code (e.g. ICS3U)", default_code).upper()
    course_path = base_path / course_code

    # --- NEW: Automatic backup BEFORE any mutations -------------------------
    try:
        if course_path.exists() and not no_backup:
            backup_root = base_path / "_backups"
            backup_existing_course_dir(course_path, backup_root)
    except Exception as e:
        print(f"⚠️ Backup warning: {e}")
        print("   Proceeding without backup due to the error above.")

    # Ensure the course directory exists (original behavior)
    course_path.mkdir(parents=True, exist_ok=True)

    # --- NEW: Always ensure a course-level Media folder & announce purpose ---
    media_path = course_path / "Media"
    media_path.mkdir(parents=True, exist_ok=True)
    # Drop a .gitkeep so it appears in version control even when empty
    try:
        (media_path / ".gitkeep").touch(exist_ok=True)
    except Exception:
        pass
    print("\n🗂️  'Media' folder")
    print("A course-level folder named 'Media' has been ensured at:")
    print(f"   {media_path}")
    print("Use it to store larger binary assets (images, short videos, PDFs).")
    print("It is automatically hidden from the site's Explorer and shared across all sections.")
    print("Note: You do not need to add 'Media' to any folder lists below—it's created for you.\n")

    # --- NEW: Copy Obsidian defaults into the new/existing course folder ----
    # This seeds sensible defaults (e.g., attachments saved to 'Media').
    try:
        copy_obsidian_defaults(course_path)
    except Exception as e:
        print(f"⚠️  Unable to install Obsidian defaults: {e}")

    config_path = course_path / "course_config.json"
    saved_config = {}
    if config_path.exists():
        with open(config_path, "r", encoding="utf-8") as f:
            saved_config = json.load(f)

    if saved_config.get("course_name"):
        course_name = prompt_with_default("Enter the course name you wish to use", saved_config["course_name"])
    else:
        looked_up_name = get_course_name_from_json(course_code) or "Course Website"
        course_name = prompt_with_default("Enter the course name you wish to use", looked_up_name)

    
    # ---------- NEW: Optional custom short label for clubs (no grade) -------
    # If the 4th character of the course code is not a digit, treat as no grade
    custom_short_name = saved_config.get("custom_short_name", "")
    grade_char_for_prompt = course_code[3] if len(course_code) >= 4 else ""
    if not grade_char_for_prompt.isdigit():
        print("\n🔤 Optional: Set a short label (≤12 chars) to appear beside the emoji (replaces course code).")
        suggested_short = (saved_config.get("custom_short_name") 
                           or (course_name.split()[0][:12] if course_name else "") 
                           or course_code[:12])
        # Use existing helper to allow default suggestion
        user_input = prompt_with_default("Short label (≤12 chars, or leave blank to keep course code)", suggested_short)
        user_input = (user_input or "").strip()
        # Enforce 12 characters max
        while len(user_input) > 12:
            print("⚠️  Please keep this label to 12 characters or fewer.")
            user_input = input("Short label (≤12 chars, or Enter to skip): ").strip()
        custom_short_name = user_input
    else:
        # Preserve previously saved value if present
        custom_short_name = saved_config.get("custom_short_name", "")
# ---------- NEW: Prompt for Quartz locale (restricted list) --------------
    locale_code = prompt_quartz_locale(saved_config)

    # Count first (kept for compatibility / UX), then timetable section numbers
    num_sections = int(prompt_with_default("How many sections are you teaching of this course?", saved_config.get("num_sections", 2)))
    section_numbers = prompt_section_numbers(num_sections, saved_config)
    # Normalize num_sections to entered list length
    num_sections = len(section_numbers)

    # ---- Per-section colour scheme selection (interactive) ----
    schemes = load_colour_schemes()
    previous_map = saved_config.get("color_schemes", {})
    color_schemes_map = {}
    if schemes:
        print("\n🎨 Choose a colour scheme for each section.\n")
        for sec in section_numbers:
            section_key = f"section{sec}"
            default_scheme_id = previous_map.get(section_key)
            chosen_id = interactive_pick_scheme_for_section(
                schemes, section_number=sec, default_id=default_scheme_id
            )
            # If user cancels, keep previous; else pick current or fallback to first
            if not chosen_id:
                chosen_id = default_scheme_id or (schemes[0].get("id") if schemes else None)
            color_schemes_map[section_key] = chosen_id
        clear_screen()

    # ---- Typography selection (after colours) ----
    fonts_config = select_fonts_for_sections(section_numbers, saved_config)
    
    # ---- Per-section header emoji selection (stateful) ----
    emojis_config = select_header_emojis_for_sections(section_numbers, saved_config)

    # ---- NEW: Per-section section marker visibility (stateful) --------------
    section_marker_config = select_section_marker_visibility_for_sections(section_numbers, saved_config)

    # ---------- Example content for this course code ------------------------
    # When ready-made content exists for this exact course code, offer to
    # pour it in. The curriculum pages get their own question: some
    # teachers want the Ministry's expectations linkable from every lesson,
    # others do not want them on the site at all.
    example_payload = find_example_content_dir(course_code)
    example_manifest = None
    prepopulate_example = bool(saved_config.get("prepopulate_example_content", False))
    include_curriculum = bool(saved_config.get("include_curriculum_pages", False))
    include_curriculum_coverage = bool(saved_config.get("include_curriculum_coverage", True))
    include_coverage_notes = bool(saved_config.get("include_coverage_notes", True))
    coverage_asked = False
    if example_payload:
        manifest = load_example_content_manifest(example_payload)
        print(f"\n📖 Ready-made example content is available for {course_code}.")
        print("It fills the course with working pages — lessons, tasks, and")
        print("reference pages — written for this course, that you can keep,")
        print("edit, or delete as you build your own site.")
        prepopulate_example = prompt_yes_no_default(
            "Pre-populate this course with example content?",
            bool(saved_config.get("prepopulate_example_content", True))
        )
        if prepopulate_example and manifest.get("curriculum_folder"):
            print(f"\n🏛️  The example content includes the official Ontario curriculum")
            print(f"for {course_code} — every expectation as its own page, so your")
            print("lessons and tasks can link to exactly the expectations they address.")
            include_curriculum = prompt_yes_no_default(
                "Include the Ontario curriculum pages?",
                bool(saved_config.get("include_curriculum_pages", True))
            )
            include_curriculum_coverage = prompt_curriculum_coverage(
                include_curriculum, saved_config)
            include_coverage_notes = prompt_coverage_notes(
                include_curriculum_coverage, saved_config)
            coverage_asked = True
        elif not prepopulate_example:
            include_curriculum = False
        if prepopulate_example:
            example_manifest = manifest

    # ---------- A starting skeleton for every other course code ------------
    # No ready-made course exists for this code, but the SHAPE of one does:
    # folders that suit the subject, a semester of class pages to rename, a
    # site tour, and placeholder pages that say what belongs in them.
    skeleton_payload = None
    skeleton_manifest = None
    use_skeleton = False
    if not example_manifest:
        candidate = find_skeleton_dir(course_code)
        if candidate:
            skeleton_manifest = load_example_content_manifest(candidate)
            label = skeleton_manifest.get("label", "this subject")
            print(f"\n🧱 There is no ready-made course for {course_code}, but there is a")
            print(f"starting point shaped for {label.lower()}: folders that suit the")
            print("subject, four units of class pages to rename, a page explaining what")
            print("the site can do, and placeholders saying what belongs where.")
            use_skeleton = prompt_yes_no_default(
                "Start this course from that skeleton?",
                bool(saved_config.get("use_skeleton", True))
            )
            if use_skeleton:
                skeleton_payload = candidate
                if skeleton_manifest.get("curriculum_folder"):
                    print("\n🏛️  The skeleton includes an empty Curriculum folder, ready for")
                    print(f"the expectations for {course_code} when you add them.")
                    include_curriculum = prompt_yes_no_default(
                        "Include the Curriculum pages?",
                        bool(saved_config.get("include_curriculum_pages", True))
                    )
                    include_curriculum_coverage = prompt_curriculum_coverage(
                        include_curriculum, saved_config)
                    include_coverage_notes = prompt_coverage_notes(
                        include_curriculum_coverage, saved_config)
                    coverage_asked = True
            else:
                skeleton_manifest = None

    # ---------- Structure: from the example content, or from prompts --------
    if example_manifest:
        # The example content decides the structure WHOLE: which folders and
        # files exist, which stay hidden, which expand. No structure
        # questions are asked — pages were written for exactly this layout,
        # and empty leftover folders would only dilute it. (Everything
        # cosmetic — fonts, colours, emoji, footer — is still the
        # teacher's, above and below.)
        curriculum_folder = example_manifest.get("curriculum_folder")
        # The example content names its own files, so the terminology
        # switch has nothing to decide here; the choice is only carried.
        use_lcs_terminology = bool(saved_config.get("use_lcs_terminology", False))
        shared_folders = [x for x in example_manifest.get("shared_folders", []) if x != "Media"]
        shared_files = list(example_manifest.get("shared_files", []))
        per_section_folders = list(example_manifest.get("per_section_folders", []))
        per_section_files = list(example_manifest.get("per_section_files", []))
        hidden_items = list(example_manifest.get("hidden", []))
        expandable_items = list(example_manifest.get("expandable", []))
        if not include_curriculum and curriculum_folder:
            shared_folders = [x for x in shared_folders if x != curriculum_folder]
            hidden_items = [x for x in hidden_items if x != curriculum_folder]
            expandable_items = [x for x in expandable_items if x != curriculum_folder]
        print("\n🗂️  The example content chooses this course's folders and files:")
        print(f"   Shared folders: {', '.join(shared_folders)}")
        print(f"   Shared files: {', '.join(shared_files) or '—'}")
        print(f"   Per-section folders: {', '.join(per_section_folders) or '—'}")
        print(f"   Per-section files: {', '.join(per_section_files) or '—'}")
    else:
        # ---------- Terminology for the factory defaults ---------------------
        # The factory defaults are school-neutral; one switch brings back
        # LCS's own set-up. Saved lists always win over either factory set —
        # the switch only decides what a fresh course is offered.
        use_lcs_terminology = prompt_yes_no_default(
            "Use LCS-specific terminology (e.g. “Grove Time” instead of “Extra Help”)?",
            bool(saved_config.get("use_lcs_terminology", False))
        )
        factory_shared_folders = LCS_SHARED_FOLDERS if use_lcs_terminology else DEFAULT_SHARED_FOLDERS
        factory_shared_files = LCS_SHARED_FILES if use_lcs_terminology else DEFAULT_SHARED_FILES

        # A skeleton knows which folders its own pages were written for, so
        # it offers those instead of the school-neutral factory list. The
        # teacher still sees them and can add or drop any of them. Its
        # shared files come along too: the skeleton's pages transclude
        # Help Sessions, so dropping it would leave an empty transclusion.
        factory_per_section_folders = DEFAULT_PER_SECTION_FOLDERS
        factory_per_section_files = DEFAULT_PER_SECTION_FILES
        if skeleton_manifest:
            factory_shared_folders = list(skeleton_manifest.get("shared_folders", factory_shared_folders))
            skeleton_files = list(skeleton_manifest.get("shared_files", []))
            if use_lcs_terminology:
                for name in LCS_SHARED_FILES:
                    if name not in skeleton_files:
                        skeleton_files.append(name)
            factory_shared_files = skeleton_files
            factory_per_section_folders = list(skeleton_manifest.get("per_section_folders", factory_per_section_folders))
            factory_per_section_files = list(skeleton_manifest.get("per_section_files", factory_per_section_files))

        # ---------- Original prompts (unchanged except for Media handling) ----------
        # Remove 'Media' from defaults so it never appears in the selection prompt
        shared_default_candidates = saved_config.get("shared_folders", factory_shared_folders)
        shared_default_filtered = [x for x in (shared_default_candidates or []) if x != "Media"]

        shared_folders = prompt_type_list(
            "Enter folder names to be shared across all sections – defaults are:",
            shared_default_filtered,
            forbidden_names=["Media"]  # prevent user from adding 'Media'
        )
        shared_files = prompt_type_list(
            "Enter Markdown file names to be shared across all sections – defaults are:",
            saved_config.get("shared_files", factory_shared_files),
            add_md_extension=True
        )
        per_section_folders = prompt_type_list(
            "Enter folder names to be duplicated per section – defaults are:",
            saved_config.get("per_section_folders", factory_per_section_folders),
            forbidden_names=["Media"]  # prevent user from adding 'Media'
        )
        per_section_files = prompt_type_list(
            "Enter Markdown file names to be duplicated per section – defaults are:",
            saved_config.get("per_section_files", factory_per_section_files),
            add_md_extension=True
        )

        all_selected = shared_folders + shared_files + per_section_folders + per_section_files

        if use_lcs_terminology:
            factory_hidden = [
                "Media", "Ontario Curriculum", "College Board Curriculum",
                "SIC Drop-In Sessions.md", "Grove Time.md", "Learning Goals.md",
                "Private Notes.md", "Scratch Page.md", "Key Links.md"
            ]
        else:
            factory_hidden = [
                "Media", "Ontario Curriculum",
                "Extra Help.md", "Learning Goals.md",
                "Private Notes.md", "Scratch Page.md", "Key Links.md"
            ]
        if skeleton_manifest:
            factory_hidden = ["Media"] + list(skeleton_manifest.get("hidden", []))
        default_hidden = factory_hidden if not saved_config else saved_config.get("hidden", [])

        # IMPORTANT: 'Media' will NOT appear in this prompt because it's not in all_selected,
        # but we still want it hidden in config. We'll enforce that after the prompt.
        hidden_items = prompt_select_multiple("Select folders/files to HIDE from the sidebar:", all_selected, default_hidden)
        visible_items = [item for item in all_selected if item not in hidden_items]

        # Every visible shared folder gets a chevron, including one the
        # teacher added at the prompt above — the curriculum folder and the
        # per-section All Classes are the deliberate exceptions.
        factory_expandable = [
            name for name in shared_folders if name not in hidden_items
        ] if skeleton_manifest else [
            "Concepts", "Discussions", "Examples", "Exercises", "Portfolios",
            "Recaps", "Setup", "Style", "Tasks", "Tutorials"
        ]
        default_expandable = factory_expandable if not saved_config else saved_config.get("expandable", [])

        expandable_items = prompt_select_multiple("Select folders/files that should be EXPANDABLE:", visible_items, default_expandable)

    # ---------- Explorer expansion behaviour (stateful, applies to all sections) ----------
    expand_on_click = prompt_explorer_expansion_behavior(saved_config)

    # ---------- Stateful footer prompt ----------
    footer_html = prompt_footer_html_stateful(saved_config)

    # ---------- Show reading-time estimates (stateful) ----------
    show_reading_time_default = bool(saved_config.get("show_reading_time", False))
    show_reading_time = prompt_yes_no_default(
        "Show page read time estimates to students?",
        show_reading_time_default
    )

    # ---------- Curriculum coverage map -------------------------------------
    # Normally asked in the Starting Content section, beside the curriculum
    # question it depends on. This is the fallback for a course whose
    # Curriculum folder came from neither example content nor a skeleton —
    # a teacher who built the structure themselves.
    curriculum_folder_chosen = any("curriculum" in name.lower() for name in shared_folders)
    if not curriculum_folder_chosen:
        include_curriculum_coverage = False
    elif not coverage_asked:
        include_curriculum_coverage = prompt_curriculum_coverage(True, saved_config)
        include_coverage_notes = prompt_coverage_notes(
            include_curriculum_coverage, saved_config)
    if not include_curriculum_coverage:
        include_coverage_notes = False

    # Ensure 'Media' is always in hidden list even though it wasn't prompted
    if "Media" not in hidden_items:
        hidden_items.append("Media")

    # ---------- Save configuration (now includes section_numbers) ----------
    config = {
        "course_code": course_code,
        "course_name": course_name,
        "custom_short_name": custom_short_name,
        "locale": locale_code,  # NEW: Quartz locale saved for build_site.py
        "emojis": emojis_config,
        "num_sections": num_sections,
        "section_numbers": section_numbers,  # NEW: timetable-based identifiers
        "shared_folders": shared_folders,
        "shared_files": shared_files,
        "per_section_folders": per_section_folders,
        "per_section_files": per_section_files,
        "hidden": hidden_items,
        "expandable": expandable_items,
        # NEW: global Explorer expansion behaviour for this course
        "expandOnFolderClick": expand_on_click,
        "footer_html": footer_html,
        # New flag stored for build_site.py to consume
        "show_reading_time": show_reading_time,
        # New: fonts configuration to be applied by build_site.py per section
        "fonts": fonts_config,
        # NEW: per-section section-marker visibility for site title
        "show_section_marker": section_marker_config,
        # NEW: example-content choices, remembered for future re-runs
        "prepopulate_example_content": prepopulate_example,
        "use_skeleton": use_skeleton,
        "include_curriculum_coverage": include_curriculum_coverage,
        "include_coverage_notes": include_coverage_notes,
        "include_curriculum_pages": include_curriculum,
        # NEW: whether the default file names use LCS's own words
        "use_lcs_terminology": use_lcs_terminology,
    }
    previous_map = saved_config.get("color_schemes", {}) or {}
    if schemes:
        # Use the choices gathered earlier in this run
        config["color_schemes"] = color_schemes_map
    else:
        # No schemes available now; keep whatever was previously saved
        config["color_schemes"] = previous_map

    # Keys this wizard does not own — the desktop apps' publishing choice
    # (deploy_target, deploy_folder_path), and anything a future version
    # adds — must survive a re-run rather than being silently dropped.
    for saved_key, saved_value in saved_config.items():
        if saved_key not in config:
            config[saved_key] = saved_value

    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")  # nice-to-have: trailing newline

    # Get current timestamp in ISO8601 with milliseconds and timezone offset
    tz_offset_str = os.environ.get("HOST_TZ_OFFSET")
    if tz_offset_str and len(tz_offset_str) == 5 and tz_offset_str[1:].isdigit():
        sign = 1 if tz_offset_str[0] == '+' else -1
        hours = int(tz_offset_str[1:3])
        minutes = int(tz_offset_str[3:])
        tzinfo = timezone(sign * timedelta(hours=hours, minutes=minutes))
        now_dt = datetime.now(tzinfo)
    else:
        now_dt = datetime.now().astimezone()
    now_str = now_dt.strftime("%Y-%m-%dT%H:%M:%S.000%z")

    # ---------- Install example content (before scaffolding) ----------------
    # The payload lands first so the scaffold below, which only writes files
    # that do not exist yet, fills in around it rather than over it.
    if example_manifest:
        try:
            files_written = install_example_content(
                course_path, example_payload, example_manifest,
                section_numbers, now_str, include_curriculum,
                shared_folders, shared_files,
                per_section_folders, per_section_files,
                reference=now_dt,
                course_code=course_code,
                course_name=course_name
            )
            if files_written > 0:
                print(f"\n📖 Example content installed: {files_written} pages.")
            else:
                print("\n📖 Example content: nothing to add (every page already exists).")
        except Exception as e:
            print(f"⚠️ Could not install the example content: {e}")

    # ---------- Install the starting skeleton -------------------------------
    # Only the folders and files the teacher kept are poured in; the
    # curriculum folder comes only if they kept that too.
    if skeleton_payload and skeleton_manifest:
        try:
            skeleton_curriculum = skeleton_manifest.get("curriculum_folder")
            files_written = install_example_content(
                course_path, skeleton_payload, skeleton_manifest,
                section_numbers, now_str,
                bool(skeleton_curriculum and skeleton_curriculum in shared_folders),
                shared_folders, shared_files,
                per_section_folders, per_section_files,
                reference=now_dt,
                course_code=course_code,
                course_name=course_name
            )
            if files_written > 0:
                print(f"\n🧱 Starting pages added: {files_written}.")
        except Exception as e:
            print(f"⚠️ Could not add the starting pages: {e}")

    # ---------- Create shared structure (with createdSectionN + publishForSectionN) ----------
    for folder in shared_folders:
        folder_path = toolchain_paths.COURSES_DIR / course_code / folder
        folder_path.mkdir(parents=True, exist_ok=True)
        index_md_path = folder_path / "index.md"
        if not index_md_path.exists():
            with open(index_md_path, "w", encoding="utf-8") as f:
                f.write("---\n")
                f.write(f"title: {folder}\n")
                for sec in section_numbers:
                    f.write(f"createdSection{sec}: {now_str}\n")
                    f.write(f"publishForSection{sec}: true\n")
                f.write("---\n")
                f.write(f"This is the **{folder}** folder. Add Markdown files to this folder to build out your site. Optionally, you can remove this `index.md` file and Quartz will then show only a listing of files that exist in this folder instead.\n")
    
    for file in shared_files:
        file_path = toolchain_paths.COURSES_DIR / course_code / file
        if not file_path.exists():
            with open(file_path, "w", encoding="utf-8") as f:
                f.write("---\n")
                f.write(f"title: {file.replace('.md', '')}\n")
                for sec in section_numbers:
                    f.write(f"createdSection{sec}: {now_str}\n")
                    f.write(f"publishForSection{sec}: true\n")
                f.write("---\n")
                f.write(f"This is the shared file **{file}**.\n")
    
    # ---------- Create per-section structure (with created + publish) ----------
    # Determine grade level from 4th character of course code
    grade_map = {
        "1": "Grade 9",
        "2": "Grade 10",
        "3": "Grade 11",
        "4": "Grade 12"
    }
    grade_char = course_code[3] if len(course_code) >= 4 else ""
    # If the 4th character isn't numeric (e.g., club code like "CODING"),
    # omit the grade prefix entirely; otherwise fall back to existing mapping
    # (including "Grade ?" for unknown digits).
    if grade_char.isdigit():
        grade_label = grade_map.get(grade_char, "Grade ?")
    else:
        grade_label = ""

    for sec in section_numbers:
        section_name = f"section{sec}"
        section_path = toolchain_paths.COURSES_DIR / course_code / section_name
        section_path.mkdir(exist_ok=True)
    
        index_md_path = section_path / "index.md"
        if not index_md_path.exists():
            with open(index_md_path, "w", encoding="utf-8") as f:
                f.write("---\n")
                # The built site recomputes this title from the settings on
                # every build; this is only a starting value, and it follows
                # the same literal rule: the switch alone decides.
                raw_show_grade = saved_config.get("show_grade_in_title", True)
                if isinstance(raw_show_grade, dict):
                    show_grade = bool((raw_show_grade.get("sections") or {}).get(f"section{sec}", True))
                else:
                    show_grade = bool(raw_show_grade)
                title_prefix = f"{grade_label} " if (grade_label and show_grade) else ""
                f.write(f"title: {title_prefix}{course_name}, Section {sec}\n")
                f.write(f"created: {now_str}\n")
                f.write("publish: true\n")
                f.write("---\n")
    
        for folder in DEFAULT_PER_SECTION_FOLDERS if not DEFAULT_PER_SECTION_FOLDERS else []:
            # (kept for compatibility; actual per_section_folders handled below)
            pass

        for folder in per_section_folders:
            folder_path = section_path / folder
            folder_path.mkdir(parents=True, exist_ok=True)
            index_md = folder_path / "index.md"
            if not index_md.exists():
                with open(index_md, "w", encoding="utf-8") as f:
                    f.write("---\n")
                    f.write(f"title: {folder}\n")
                    f.write(f"created: {now_str}\n")
                    f.write("publish: true\n")
                    f.write("---\n")
                    f.write(f"This is the **{folder}** folder. Add Markdown files to this folder to build out your site.\n")
    
        for file in per_section_files:
            file_path = section_path / file
            if not file_path.exists():
                is_unpublished = file in UNPUBLISHED_PER_SECTION_FILES
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write("---\n")
                    f.write(f"title: {file.replace('.md', '')}\n")
                    f.write(f"created: {now_str}\n")
                    f.write(f"publish: {'false' if is_unpublished else 'true'}\n")
                    f.write("---\n")
                    if is_unpublished:
                        f.write(f"This is the per-section file **{file}**. It is marked `publish: false`, so it stays out of the built site — a private place for your own notes.\n")
                    else:
                        f.write(f"This is the per-section file **{file}**.\n")

    # ---------- Patch Quartz Explorer + OverflowList (idempotent) ------------
    ensure_quartz_explorer_anchor()
    ensure_quartz_overflowlist_static_id()

    print(f"\n✅ Course '{course_code}' set up successfully at: {course_path}")
    print("\n\nWebsite previews")
    print("----------------")
    for sec in section_numbers:
    	print(f"\n🔎 You can preview {course_code}, section {sec} by running this command:\n{_cmd_example('preview', course_code, sec, _HOST_OS)}\n")
    print("\nWebsite deploys")
    print("----------------")
    for sec in section_numbers:
    	print(f"\n🚀 You can deploy {course_code}, section {sec} by running this command:\n{_cmd_example('deploy', course_code, sec, _HOST_OS)}\n")

def parse_args():
    parser = argparse.ArgumentParser(description="Course setup with automatic backups")
    parser.add_argument("--no-backup", action="store_true", help="Skip creating a backup of the existing course folder.")
    parser.add_argument("--host-os", choices=["windows","mac","linux","unknown"], default="unknown", help="Host operating system (passed by setup.sh/setup.ps1).")
    parser.add_argument("--install-example", action="store_true", help="Install the example course without prompting, then exit.")
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_args()
    # Set module-level host OS for OS-aware examples
    _HOST_OS = getattr(args, "host_os", "unknown")
    if args.install_example:
        installed = install_example_course_noninteractive(toolchain_paths.COURSES_DIR)
        sys.exit(0 if installed else 1)
    setup_course(no_backup=args.no_backup)
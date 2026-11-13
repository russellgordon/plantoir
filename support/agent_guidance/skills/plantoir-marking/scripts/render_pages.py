#!/usr/bin/env python3
"""Render pages of a boxed paper or a sheet as pictures, into the assessment's Work folder and nowhere else.

Part of the plantoir-marking skill (#750, 750d, after the second trial: an assistant rendered every boxed
paper into /tmp, outside the marking folder, where a name written in one page's body sat in a folder anyone on
the computer could read). A STARTING POINT, like the others: copy it into the marking folder's Scripts/ folder,
adapt it if you must, run --self-test, and only then use it.

    python3 -B render_pages.py "<marking folder>/<Assessment>/Redacted/Section 1/Student A.pdf" --into "<marking folder>/<Assessment>/Work" [--dpi 80] [--first 1] [--last 2]
    python3 -B render_pages.py --self-test

It writes "<Work>/<the PDF's name>/page-N.png" and prints the paths of the pictures it wrote, which hold no
name of a student (the PDF is named by identifier). It refuses a folder that is not called Work, one inside a
Plantoir working folder, and one inside the system's temporary folders. Needs Poppler's pdftoppm.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# MARK: - What you may change for this teacher
#   the resolution, the page range, the picture format and the wording of the lines it prints.
DPI = 80

# MARK: - What must not change
#   write only into a folder called Work, never inside a Plantoir working folder or a temporary folder of the
#   system; never print a file name that is not an identifier or a page number; never a traceback.
WORK = "Work"


class Refusal(Exception):
    """A reason to stop, worded for the teacher."""


def temporary_folders():
    found = []
    for folder in (tempfile.gettempdir(), os.environ.get("TMPDIR", ""), "/tmp", "/private/tmp", "/var/tmp"):
        if folder and os.path.isdir(folder):
            found.append(Path(os.path.realpath(folder)))
    return found


def inside(path, folder):
    path = Path(os.path.realpath(str(path)))
    folder = Path(os.path.realpath(str(folder)))
    return path == folder or folder in path.parents


def inside_a_working_folder(path):
    path = Path(os.path.realpath(str(path)))
    for folder in [path] + list(path.parents):
        if (folder / "courses").is_dir() and (folder / ".toolchain").is_dir():
            return True
    return False


def check_the_folder(into, allow_temporary=False):
    into = Path(into)
    if into.name != WORK:
        raise Refusal(f"pictures go only into the assessment's '{WORK}' folder in the marking folder; nothing was written")
    if inside_a_working_folder(into):
        raise Refusal("that folder is inside the Plantoir working folder; nothing was written")
    if not allow_temporary:
        for folder in temporary_folders():
            if inside(into, folder):
                raise Refusal("that folder is inside the system's temporary folder, which anyone on this computer can "
                              "read; nothing was written")


def render(pdf, into, dpi, first, last, allow_temporary=False):
    check_the_folder(into, allow_temporary)
    if shutil.which("pdftoppm") is None:
        raise Refusal("Poppler is not installed (pdftoppm not found). On a Mac with Homebrew: brew install poppler")
    pdf = Path(pdf)
    if not pdf.is_file():
        raise Refusal("there is no such PDF; nothing was written")
    target = Path(into) / pdf.stem
    target.mkdir(parents=True, exist_ok=True)
    command = ["pdftoppm", "-png", "-r", str(dpi)]
    if first:
        command += ["-f", str(first)]
    if last:
        command += ["-l", str(last)]
    result = subprocess.run(command + [str(pdf), str(target / "page")], capture_output=True)
    if result.returncode != 0:
        raise Refusal("pdftoppm could not read that PDF; nothing more was written")
    written = sorted(target.glob("page-*.png"))
    for path in written:
        print(path)
    return 0


def option(arguments, name, default=None):
    if name in arguments and arguments.index(name) + 1 < len(arguments):
        return arguments[arguments.index(name) + 1]
    return default


def self_test():
    with tempfile.TemporaryDirectory() as root:
        problems = []
        for wrong in (Path(root) / "Elsewhere", Path(root) / "Work"):
            try:
                check_the_folder(wrong)
                problems.append(f"{wrong.name}: not refused")
            except Refusal:
                pass
        try:
            check_the_folder(Path(root) / "Marking" / "Unit Test" / "Work", allow_temporary=True)
        except Refusal:
            problems.append("a Work folder was refused")
    if problems:
        print("self-test FAILED: " + "; ".join(problems))
        return 1
    print("self-test passed: a folder not called Work and a folder in the system's temporary folder are refused, and "
          "a Work folder is taken. This checks the paths the test knows; it is no guarantee about changes it does not reach.")
    return 0


def main(arguments):
    if not arguments or arguments[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if "--self-test" in arguments:
        return self_test()
    if option(arguments, "--into") is None:
        raise Refusal("give --into, the assessment's Work folder")
    return render(arguments[0], option(arguments, "--into"), int(option(arguments, "--dpi", str(DPI))),
                  option(arguments, "--first"), option(arguments, "--last"))


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}")
        sys.exit(1)
    except Exception as error:   # never a traceback
        print(f"Stopped: something unexpected went wrong ({type(error).__name__})")
        sys.exit(1)

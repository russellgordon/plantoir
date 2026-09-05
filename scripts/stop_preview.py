#!/usr/bin/env python3
"""
Which processes belong to a section's preview — the ONE answer.

This question used to be answered three times: `preview.sh --stop` swept
`/proc/<pid>/cwd` inside the container, `preview.ps1 --stop` matched command
lines natively through `Win32_Process`, and `build_site.py` matched command
lines again from inside the container because it cannot call either host
script. `TODO.md` had it as "one rule, three implementations", and by the time
it was picked up they had already drifted apart in three separate ways — one
of them a live bug (see `contracts/shared-rules.json` -> `stopPreview`).

**The three were not three copies of one rule. They were three PARTIAL rules**,
and that is the thing to understand before changing anything here:

- Matching on the working directory catches what a command line cannot: a
  child launched by a RELATIVE path carries no directory to match on, and
  `npm install` (build_site.py) runs exactly that way.
- Matching on the command line catches what a working directory cannot: **the
  Python driver itself.** `build_site.py` never calls `os.chdir` — it passes
  `cwd=` to its CHILDREN — so the driver sits in the container's `/teaching`
  for the whole build. A cwd sweep during any in-process phase (copying the
  scaffold, copying content, social cards, the rsync mirror) therefore found
  NOTHING, said "Stopped 0 process(es)", and left the build running. That was
  the mac's blind spot for as long as `--stop` has existed, and it is also why
  cancelling a deploy did not stop the deploy's build.

So the shared rule is a DISJUNCTION of three evidences, plus a walk down the
process tree to collect the children that carry no evidence of their own. Any
one evidence is enough; the walk then sweeps up the rest.

The rule is code and the CASES are test data — `contracts/shared-rules.json`
-> `stopPreview`, run by `scripts/test_stop_preview.py`. This module does NOT
read the contract at runtime, deliberately: `--stop` must work against a
container built from an older image, and coupling it to a file baked into the
image would give it a second way to fail at the worst moment.

What is deliberately NOT shared, because it is platform mechanics rather than
the rule: how the process list is obtained (`/proc` here, `Win32_Process` on
native Windows) and how a process is ended (ask-then-insist here, since POSIX
has SIGTERM; `Stop-Process -Force` there, since Windows has no equivalent).
"""

import argparse
import json
import os
import signal
import sys
import time
from pathlib import Path


# The two questions this module is ever asked. They differ in WHY they are
# being asked, which is why they are not one mode with a flag.
#
#   everything   — the launcher's `--stop`: the teacher (or the app) has ended
#                  a preview and the container-side work must be reclaimed.
#                  A mid-flight build counts; that is most of the point.
#   servingOnly  — `build_site.py --build-only`: a build for PUBLISHING is
#                  about to start, and the only thing that must go is the
#                  preview SERVER that would otherwise overwrite it a second
#                  later. A build must never be stopped here: the build being
#                  protected is itself a build of this section.
MODE_EVERYTHING = "everything"
MODE_SERVING_ONLY = "servingOnly"
MODES = (MODE_EVERYTHING, MODE_SERVING_ONLY)

# Both separators, always, on both platforms. A command line seen on Windows
# carries backslashes and one seen in the container carries forward slashes,
# but either can appear in either place — a Windows-native run passes POSIX
# spellings around in places, and the container never sees a backslash at all.
# Accepting both costs nothing: a path that ends at the wrong kind of
# separator is still a path that ended at a separator.
SEPARATORS = ("/", "\\")

# What may legally follow the directory when a COMMAND LINE names it: another
# path segment, the end of that argument, or the end of the line. A quote is
# there because Windows quotes an argument containing a space.
#
# End-of-argument counts, and it is worth saying why that is still safe. The
# whole point of the boundary is that `.../section1` must not match
# `.../section10` — and it cannot, because the character after `section1` in
# that string is `0`, which is not a boundary. Allowing the argument to END at
# the directory only adds the case where the directory IS the whole argument,
# which is a real shape (`--directory /tmp/quartz-builds/ADA1O/section1`) and
# was previously missed.
BOUNDARIES = SEPARATORS + (" ", "\t", '"', "'")


def _normalise(text: str) -> str:
    """
    Lower-cased, for every path comparison here.

    Windows filesystems are case-insensitive but case-PRESERVING, so a teacher
    whose folder is on disk as `Ada1o` and whose command line says `ADA1O` is
    an ordinary Windows state rather than an exotic one. The alternative —
    case-sensitive on POSIX, insensitive on Windows — would make a contract
    case's expected answer depend on which platform ran it, and then it is not
    one rule any more. The cost of being insensitive everywhere is that
    `ADA1O` and `ada1o` are treated as the same course, which they are.
    """
    return text.lower()


def _strip_trailing_separator(directory: str) -> str:
    stripped = directory
    while len(stripped) > 1 and stripped[-1] in SEPARATORS:
        stripped = stripped[:-1]
    return stripped


def cwd_is_inside(cwd: str, directory: str) -> bool:
    """
    Evidence (a): the process is SITTING in this section's build directory.

    Catches every child launched with `cwd=output_dir`, including the ones
    whose command line names no directory at all — `npm install`, and the
    esbuild workers it spawns.
    """
    if not cwd:
        return False
    here = _normalise(_strip_trailing_separator(cwd))
    target = _normalise(_strip_trailing_separator(directory))
    if here == target:
        return True
    for separator in SEPARATORS:
        if here.startswith(target + separator):
            return True
    return False


def command_names_directory(command_line: str, directory: str) -> bool:
    """
    Evidence (b): the command line NAMES this section's build directory.

    Catches the serving node, which the launcher runs by absolute path
    precisely so that this works.

    The separator is the whole trick. `.../section1` is a prefix of
    `.../section10`, so a bare substring test stops the wrong preview — which
    is exactly the bug this rule was found to have on one platform. Requiring
    a separator AFTER the directory makes `section1` and `section10` different
    strings again.
    """
    if not command_line:
        return False
    haystack = _normalise(command_line)
    target = _normalise(_strip_trailing_separator(directory))
    start = haystack.find(target)
    while start != -1:
        after = start + len(target)
        if after >= len(haystack) or haystack[after] in BOUNDARIES:
            return True
        start = haystack.find(target, start + 1)
    return False


def _argument_value(command_line: str, name: str) -> str:
    """
    The value of `--name=value` or `--name value`, or "" if it is not there.

    Read as ARGUMENTS rather than as a substring, because `--section=1` is a
    prefix of `--section=10` and the substring form stops the wrong section's
    build — the same prefix bug as above, by a second route. Splitting on
    whitespace is safe for these two flags specifically: a course code and a
    section number never contain a space, whatever the path around them does.
    """
    tokens = command_line.split()
    flag = "--" + name
    for index, token in enumerate(tokens):
        if token.startswith(flag + "="):
            return token[len(flag) + 1:]
        if token == flag and index + 1 < len(tokens):
            return tokens[index + 1]
    return ""


def command_is_the_driver(command_line: str, course: str, section) -> bool:
    """
    Evidence (c): this is `build_site.py` building THIS section.

    The evidence the mac never had. The driver's own working directory is the
    container's, not the section's, and its command line names the course and
    the section rather than the build directory — so neither (a) nor (b) can
    see it, and during every in-process phase of a build it is the only
    process there is to find.
    """
    if not command_line or not course or section in (None, ""):
        return False
    if "build_site.py" not in _normalise(command_line):
        return False
    if _normalise(_argument_value(command_line, "course")) != _normalise(str(course)):
        return False
    return _argument_value(command_line, "section").strip() == str(section).strip()


def is_serving(command_line: str) -> bool:
    """
    A preview SERVER rather than a build.

    `--serve` is what the launcher adds to the Quartz CLI for a preview and
    never adds for a build, so it is the one honest separator between the two.
    """
    return "--serve" in (command_line or "").split()


def process_matches(process: dict, directories, course, section, mode: str) -> bool:
    """
    Does this ONE process belong to the section, for the question being asked?

    `directories` is a list because a section's build directory has more than
    one true spelling: `courses/<CODE>/.merged_output/section<N>` is a symlink
    to the builds folder outside the working folder, and `/proc/<pid>/cwd` is
    the resolved path a process is actually sitting in — never the spelling it
    used to get there. A caller passes every spelling it knows.
    """
    command_line = process.get("commandLine") or ""
    cwd = process.get("cwd") or ""

    if mode == MODE_SERVING_ONLY:
        # Serving only: the directory must be NAMED and the process must be a
        # server. Never the driver, and never on cwd alone — a build of this
        # section sits in this section's directory too, and the caller here IS
        # a build of this section.
        if not is_serving(command_line):
            return False
        for directory in directories:
            if command_names_directory(command_line, directory):
                return True
        return False

    for directory in directories:
        if cwd_is_inside(cwd, directory):
            return True
        if command_names_directory(command_line, directory):
            return True
    return command_is_the_driver(command_line, course, section)


def pids_to_stop(snapshot, directories, course=None, section=None,
                 mode: str = MODE_EVERYTHING, exclude=()) -> list:
    """
    Every pid to stop, given the whole process list.

    A SNAPSHOT rather than one process at a time, because the last part of the
    rule is not a property of any single process: a child spawned with a
    relative path carries no evidence at all, and is only reachable through
    its parent. Windows found this first — `preview.ps1` has walked
    descendants since it was written, and the mac's two copies never did.

    Returns pids in a stable order (the snapshot's), so a caller's output and
    a test's expectation can be compared directly.
    """
    if mode not in MODES:
        raise ValueError(f"Unknown mode {mode!r}; expected one of {MODES}.")

    excluded = set(int(pid) for pid in exclude)
    matched = set()
    for process in snapshot:
        pid = int(process.get("pid"))
        if pid in excluded or pid <= 1:
            continue
        if process_matches(process, directories, course, section, mode):
            matched.add(pid)

    # Descendants, repeatedly: the chain is driver -> npm -> node -> esbuild,
    # so one pass is not enough. Bounded by the snapshot size — every pass
    # either adds a process or stops.
    grew = True
    while grew:
        grew = False
        for process in snapshot:
            pid = int(process.get("pid"))
            if pid in matched or pid in excluded or pid <= 1:
                continue
            parent = process.get("ppid")
            if parent is None:
                continue
            if int(parent) in matched:
                matched.add(pid)
                grew = True

    ordered = []
    for process in snapshot:
        pid = int(process.get("pid"))
        if pid in matched:
            ordered.append(pid)
    return ordered


# --------------------------------------------------------------------------
# Platform mechanics: reading the process list, and ending a process.
# Everything above is the RULE and is shared; everything below is not.
# --------------------------------------------------------------------------

def read_proc_snapshot(proc_root: Path = Path("/proc")) -> list:
    """
    The process list from `/proc`, which exists wherever this runs on the mac
    (inside the container) and on Linux. Natively on Windows there is no
    `/proc` and this returns nothing, so every caller becomes a no-op rather
    than an error — the shape `kill_existing_quartz` already has there without
    `lsof`. Windows reads `Win32_Process` in `preview.ps1` instead.
    """
    if not proc_root.is_dir():
        return []
    snapshot = []
    for entry in sorted(proc_root.iterdir(), key=lambda item: item.name):
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            command_line = (entry / "cmdline").read_bytes().replace(b"\x00", b" ").decode(
                "utf-8", "replace").strip()
        except OSError:
            continue
        try:
            cwd = os.readlink(str(entry / "cwd"))
        except OSError:
            cwd = ""
        try:
            name = (entry / "comm").read_text(encoding="utf-8", errors="replace").strip()
        except OSError:
            name = ""
        parent = None
        try:
            status = (entry / "status").read_text(encoding="utf-8", errors="replace")
            for line in status.splitlines():
                if line.startswith("PPid:"):
                    parent = int(line.split()[1])
                    break
        except (OSError, ValueError, IndexError):
            parent = None
        snapshot.append({
            "pid": pid, "ppid": parent, "name": name,
            "commandLine": command_line, "cwd": cwd,
        })
    return snapshot


def stop_pids(pids, insist_after: float = 1.0) -> int:
    """
    Ask, then insist. SIGTERM lets a node server close its sockets and a
    Python driver run its own cleanup; SIGKILL a second later is for whatever
    ignored it.

    Windows does this differently (`Stop-Process -Force`) because it has no
    SIGTERM to send, and that difference is recorded in the contract rather
    than papered over: the RULE is which processes, not how they end.
    """
    asked = []
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
            asked.append(pid)
        except (ProcessLookupError, PermissionError):
            continue
    if asked:
        time.sleep(insist_after)
    for pid in asked:
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            continue
    return len(asked)


def stop_section(directories, course=None, section=None, mode: str = MODE_EVERYTHING,
                 proc_root: Path = Path("/proc")) -> list:
    """Read the process list, apply the rule, stop what it names."""
    snapshot = read_proc_snapshot(proc_root)
    if not snapshot:
        return []
    pids = pids_to_stop(
        snapshot, directories, course=course, section=section, mode=mode,
        exclude=(os.getpid(),),
    )
    stop_pids(pids)
    return pids


def expand_directories(directories) -> list:
    """
    Every true spelling of the directories given, resolved included.

    `.merged_output/section<N>` is a symlink to the builds folder outside the
    working folder, and a process's `cwd` is the REAL path. Without the
    resolved form the sweep matched nothing at all the moment the built site
    moved, and `--stop` reported success while the build kept running.
    """
    expanded = []
    for directory in directories:
        if not directory:
            continue
        candidate = _strip_trailing_separator(str(directory))
        if candidate not in expanded:
            expanded.append(candidate)
        try:
            resolved = _strip_trailing_separator(os.path.realpath(candidate))
        except OSError:
            continue
        if resolved not in expanded:
            expanded.append(resolved)
    return expanded


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Stop the processes belonging to one section's preview.")
    parser.add_argument("--dir", action="append", default=[], dest="directories",
                        help="A build directory for the section. Repeatable: a section "
                             "has more than one true spelling.")
    parser.add_argument("--course", default=None, help="Course code, for driver evidence.")
    parser.add_argument("--section", default=None, help="Section number, for driver evidence.")
    parser.add_argument("--mode", choices=MODES, default=MODE_EVERYTHING)
    parser.add_argument("--match-stdin", action="store_true",
                        help="Do not touch any process. Read a JSON process list on stdin "
                             "and print the pids the rule names, one per line. This is how "
                             "a platform that cannot read /proc can still use the one rule: "
                             "it enumerates and kills in its own way, and asks here WHICH.")
    args = parser.parse_args()

    if args.match_stdin:
        snapshot = json.load(sys.stdin)
        for pid in pids_to_stop(snapshot, expand_directories(args.directories),
                                course=args.course, section=args.section, mode=args.mode):
            print(pid)
        return 0

    stopped = stop_section(
        expand_directories(args.directories),
        course=args.course, section=args.section, mode=args.mode,
    )
    print(f"✅ Stopped {len(stopped)} process(es).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

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
the rule: how the process list is obtained (`/proc` on Linux and inside the
container, `Win32_Process` via PowerShell on native Windows) and how a process
is ended (ask-then-insist on POSIX, since it has SIGTERM; a single
`TerminateProcess` on Windows, which has no equivalent to ask with).

Both snapshots are read HERE, so every caller of the rule gets the right one
for the platform it is on. That was not true until 2026-09-05: `/proc` was the
only reader, so on native Windows the list came back empty and
`build_site.py`'s own `stop_preview_serving()` stopped nothing — leaving the
overwrite race it exists to close wide open on that platform. See
WINDOWS-HANDOFF.md item 20.
"""

import argparse
import json
import os
import signal
import subprocess
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

# What may legally precede it, for the same reason in the other direction:
# without this, `/x/tmp/quartz-builds/ADA1O/section1/q.mjs` is evidence for
# `/tmp/quartz-builds/ADA1O/section1`, because the target is a SUFFIX of a
# longer absolute path. It needs another absolute path ending in this one to
# bite, which is unlikely — and is exactly the kind of "unlikely" that the
# section1/section10 bug also was.
LEADING_BOUNDARIES = (" ", "\t", '"', "'", "=")


def _is_a_real_directory(target: str) -> bool:
    """
    A target that is empty, or is the root, is not a section's build folder —
    it is a caller that has lost track of what it was asking about.

    Without this, `pids_to_stop(snapshot, [""])` matches EVERY process (an
    empty string is a prefix of everything and `"" + separator` appears in any
    path), so one caller passing a blank sweeps the whole container. That is
    the same failure as the prefix bug one level up, and it belongs here
    rather than in `expand_directories`: the matching functions are the public
    API, and `build_site.py` and the contract runner both call them directly.
    """
    if not target:
        return False
    if target in ("/", "\\"):
        return False
    # `C:\` strips to `c:`, and a drive root sweeps the whole drive — the
    # same failure as `/`, in the spelling the other platform uses. No caller
    # can pass one today; it is refused here because "no caller can" is a fact
    # about today's callers, and this function is the public API.
    if len(target) == 2 and target[1] == ":" and target[0].isalpha():
        return False
    return True


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
    if not _is_a_real_directory(target):
        return False
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
    if not _is_a_real_directory(target):
        return False
    start = haystack.find(target)
    while start != -1:
        after = start + len(target)
        ends_cleanly = after >= len(haystack) or haystack[after] in BOUNDARIES
        starts_cleanly = start == 0 or haystack[start - 1] in LEADING_BOUNDARIES
        if ends_cleanly and starts_cleanly:
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
    (inside the container) and on Linux. Where there is no `/proc` this
    returns nothing rather than raising — the shape `kill_existing_quartz`
    already has without `lsof`.

    POSIX ONLY, and deliberately so even on Windows: `read_snapshot()` is the
    platform dispatcher, and this stays a pure function of `proc_root` so that
    a caller (a test, most of all) can hand it a directory that does not exist
    and get a no-op on every platform.
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


def read_windows_snapshot(timeout: float = 15.0) -> list:
    """
    The process list on native Windows, via `Get-CimInstance Win32_Process`.

    Windows has no `/proc`, and the one field the rule would most like — the
    working directory — is not exposed by `Win32_Process` at all. That costs
    nothing for the question this reader exists to answer: `servingOnly` never
    consults `cwd` (see `process_matches`), because a build of this section
    sits in this section's directory too. The contract records the gap, and
    the cases that genuinely need that evidence say so in `needsEvidence`.

    Five details here are each a way this could silently return nothing, which
    is the failure that matters: a sweep that stops nothing looks exactly like
    a sweep that had nothing to stop.

    * **UTF-8 out of PowerShell, explicitly.** The default is the OEM code
      page, so a teacher whose user folder is named José gets one byte 0x82
      where the accent belongs: either a `UnicodeDecodeError`, or — worse,
      with `errors="replace"` — a path that then never matches the section's
      build directory, so nothing is ever stopped for that teacher and
      nothing errors. Measured on Windows 11 26200 before writing this.
    * **A full path to `powershell.exe`**, from `%SystemRoot%`, falling back
      to the bare name. `CreateProcess` searches `System32` before `PATH`, so
      the bare name works today from every caller, but this runs during a
      publish and a publish should not depend on a `PATH` it did not set.
    * **`-InputObject @(...)`**, because `ConvertTo-Json` given exactly one
      process emits an object rather than an array (PowerShell 5.1 has no
      `-AsArray`), and a machine with exactly one matching process is not the
      machine anyone tests on.
    * **stdin closed, and a timeout.** This runs under ConPTY when the app
      drives it; a child that reads stdin, or a wedged WMI, would otherwise
      hang the publish rather than delay it. On timeout it returns nothing
      and says so — a publish that races is better than a publish that never
      finishes, and the caller then writes no trail line, which is honest.
    * **`CommandLine` is null for system processes**, and becomes `""`.
    """
    if os.name != "nt":
        return []
    query = ("[Console]::OutputEncoding=[Text.UTF8Encoding]::new(); "
             "ConvertTo-Json -Compress -Depth 3 -InputObject @("
             "Get-CimInstance Win32_Process | "
             "Select-Object ProcessId,ParentProcessId,Name,CommandLine)")
    powershell = "powershell.exe"
    system_root = os.environ.get("SystemRoot") or os.environ.get("SYSTEMROOT")
    if system_root:
        full = Path(system_root) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
        if full.exists():
            powershell = str(full)
    try:
        finished = subprocess.run(
            [powershell, "-NoProfile", "-NonInteractive", "-Command", query],
            stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError) as error:
        print(f"WARNING: could not read the list of running processes ({error}); "
              f"nothing was stopped.")
        return []
    if finished.returncode != 0:
        print("WARNING: could not read the list of running processes; nothing was stopped.")
        return []
    try:
        listed = json.loads(finished.stdout.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        print("WARNING: could not read the list of running processes; nothing was stopped.")
        return []

    snapshot = []
    for process in listed:
        pid = process.get("ProcessId")
        if pid is None:
            continue
        snapshot.append({
            "pid": int(pid),
            "ppid": int(process.get("ParentProcessId") or 0),
            "name": process.get("Name") or "",
            "commandLine": process.get("CommandLine") or "",
            # Win32_Process has no working directory to give.
            "cwd": "",
        })
    return snapshot


def read_snapshot(proc_root=None) -> list:
    """
    The process list, from wherever this platform keeps it.

    THE dispatcher: every caller that wants "the processes running right now"
    comes through here, so a platform that reads its list a different way is a
    change in one place rather than a rule that quietly does nothing there.
    Until 2026-09-05 there was no dispatcher, `/proc` was the only reader, and
    that is exactly how native Windows ended up running a rule that always
    answered "nothing".

    `proc_root` is for callers that mean `/proc` specifically — the container,
    and the tests. Passing it explicitly keeps the POSIX reader's purity, so a
    test can hand over a directory that does not exist and get a no-op on any
    platform.
    """
    if proc_root is not None:
        return read_proc_snapshot(proc_root)
    if os.name == "nt":
        return read_windows_snapshot()
    return read_proc_snapshot()


def stop_one(pid: int, signum=None) -> bool:
    """
    End one process, in whatever way this platform has. True if it was asked.

    `signum` is for a caller that has already decided how hard to insist —
    `servingOnly` sends SIGKILL at once rather than asking first, because a
    second spent waiting politely is a second in which the preview's mirror
    can overwrite the build the kill is protecting. It is ignored on Windows,
    which has nothing to ask with, and defaults to SIGTERM where a caller has
    no opinion.

    Windows has no signal to ask with: `os.kill` there is `TerminateProcess`
    whatever signal number it is handed, so this asks once and it is over.
    Its errors are NOT the POSIX ones either — a pid that has already gone
    raises a plain `OSError` (`[WinError 87]`, "the parameter is incorrect"),
    never `ProcessLookupError`, so catching only the POSIX pair would let a
    preview that exited between the snapshot and the kill take a publish down
    with a traceback. Verified on Windows 11 26200.
    """
    try:
        os.kill(pid, signum if signum is not None else signal.SIGTERM)
        return True
    except OSError:
        return False


def stop_pids(pids, insist_after: float = 1.0) -> int:
    """
    Ask, then insist. SIGTERM lets a node server close its sockets and a
    Python driver run its own cleanup; SIGKILL a second later is for whatever
    ignored it.

    Windows does this differently because it has nothing to ask WITH: there is
    no SIGTERM, `os.kill` is `TerminateProcess` whatever it is handed, and so
    the first ask is already final. It therefore skips the wait and the second
    pass entirely — a second spent sleeping between two identical kills is a
    second in which a preview's sync watcher can overwrite the build this was
    called to protect. `signal.SIGKILL` does not even EXIST on Windows, so the
    old second pass would have raised `AttributeError` the moment the snapshot
    there stopped coming back empty. That difference is recorded in the
    contract rather than papered over: the RULE is which processes, not how
    they end.
    """
    asked = []
    for pid in pids:
        if stop_one(pid):
            asked.append(pid)
    if os.name == "nt":
        return len(asked)
    if asked:
        time.sleep(insist_after)
    for pid in asked:
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            continue
    return len(asked)


def stop_section(directories, course=None, section=None, mode: str = MODE_EVERYTHING,
                 proc_root=None) -> list:
    """
    Read the process list, apply the rule, stop what it names.

    `proc_root` defaults to None rather than to `/proc` so that this asks
    `read_snapshot` for the RIGHT list on whatever platform it is running on.
    A caller that means `/proc` specifically still says so, and a test that
    passes a directory which does not exist still gets a no-op everywhere.
    """
    snapshot = read_snapshot(proc_root)
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

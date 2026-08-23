"""Prints the section fingerprint used by the " — Edited" title-bar marker.

Ported from `SectionPublishState.Fingerprint` (Windows, `.cs`) / the mac's
`SectionPublishState.swift` — see WINDOWS-HANDOFF.md, "A scheduled deploy
needs its own path to the same record". Every rule here (which files count,
symlink one-hop resolution, sort order, hash) MUST match those two byte for
byte; this is a wire format, not an implementation detail.

Why this exists as a THIRD copy of the same algorithm, in Python, instead of
being called from C#: a scheduled deploy on Windows runs `schtasks.exe` ->
`powershell.exe` directly, never the app binary, so there is no in-process
C# available at the moment the fingerprint must be taken — right before the
deploy runs, not at the moment the teacher scheduled it (edits made between
scheduling and the overnight run must still show up in the fingerprint, the
same as an interactive deploy). The scheduled task's generated wrapper
script calls this instead, using the app's own bundled Python. Nothing on
the mac calls this file — its launchd agent launches the app binary itself,
so it fingerprints in Swift, in-process, and never needed a Python copy.

Usage:
    python.exe section_fingerprint.py <course_directory> <section_number> [exclude ...]

Excludes are course-relative, forward-slash paths (self-publishing
destinations that land inside the course's own folder) — see
`SectionPublishState.SelfPublishingSubpaths`. Prints the lowercase hex
SHA-256 fingerprint to stdout, and nothing else, on success. Prints nothing
and exits non-zero on failure — a fingerprinting failure must never be
mistaken for an empty-string fingerprint.
"""

import hashlib
import os
import re
import sys

IGNORED_FILE_NAMES = {".DS_Store", "Thumbs.db", "course_config.backup.json"}
IGNORED_FOLDER_NAMES = {"merged_output", "node_modules"}
SECTION_FOLDER_PATTERN = re.compile(r"^section\d+$")


def is_section_folder_name(name):
    """True only for "section" + all-digits — "section3", not "sections" or "section3b"."""
    return SECTION_FOLDER_PATTERN.match(name) is not None


def is_excluded(relative_path, excluded):
    """Case-insensitive on purpose — see SectionPublishState.IsExcluded for why."""
    lowered = relative_path.lower()
    for candidate in excluded:
        if not candidate:
            continue
        candidate_lower = candidate.lower()
        if lowered == candidate_lower or lowered.startswith(candidate_lower + "/"):
            return True
    return False


def counts_toward_fingerprint(relative_path, section_number):
    parts = relative_path.split("/")
    if any(part.startswith(".") for part in parts):
        return False
    file_name = parts[-1]
    if file_name in IGNORED_FILE_NAMES:
        return False
    if file_name.endswith(".tmp"):
        return False
    if any(part in IGNORED_FOLDER_NAMES for part in parts):
        return False
    first_segment = parts[0]
    if is_section_folder_name(first_segment) and first_segment != f"section{section_number}":
        return False
    return True


def folder_counts_toward_fingerprint(relative_path, section_number):
    parts = relative_path.split("/")
    if any(part.startswith(".") for part in parts):
        return False
    if any(part in IGNORED_FOLDER_NAMES for part in parts):
        return False
    first_segment = parts[0]
    if is_section_folder_name(first_segment) and first_segment != f"section{section_number}":
        return False
    return True


def relative_of(root, path):
    return os.path.relpath(path, root).replace("\\", "/")


def append_file_line(lines, relative_path, physical_path):
    st = os.stat(physical_path)
    size = st.st_size
    # Truncated microseconds since the Unix epoch. NTFS timestamps are
    # 100ns units since 1601 (a FILETIME), same resolution as .NET's Ticks,
    # and st_mtime_ns is derived from that FILETIME with no rounding — so
    # floor-dividing by 1000 here is exactly the same truncation as the C#
    # side's `(LastWriteTimeUtc.Ticks - UnixEpoch.Ticks) / 10`.
    microseconds = st.st_mtime_ns // 1000
    lines.append(f"{relative_path}|{size}|{microseconds}")


def walk(course_directory, directory, section_number, excluded, lines, hops_remaining):
    try:
        entries = list(os.scandir(directory))
    except OSError:
        return

    for entry in entries:
        name = entry.name
        if name.startswith("."):
            continue  # hidden entries are skipped wholesale

        relative = relative_of(course_directory, entry.path)
        if is_excluded(relative, excluded):
            continue

        try:
            is_symlink = entry.is_symlink()
        except OSError:
            is_symlink = False

        if is_symlink:
            if hops_remaining <= 0:
                continue  # one hop only
            append_symlink(course_directory, entry.path, relative, section_number, excluded, lines)
            continue

        if entry.is_dir(follow_symlinks=False):
            if not folder_counts_toward_fingerprint(relative, section_number):
                continue
            walk(course_directory, entry.path, section_number, excluded, lines, hops_remaining)
        elif entry.is_file(follow_symlinks=False):
            if not counts_toward_fingerprint(relative, section_number):
                continue
            append_file_line(lines, relative, entry.path)


def append_symlink(course_directory, link_path, link_relative, section_number, excluded, lines):
    """
    Resolves a symlink by hand, ONE hop: a link to a file contributes its
    target's size/date under the LINK's own path; a link to a folder is
    walked (with no further link-following); a broken link contributes
    where it points, so repointing or removing it is visible.
    """
    target = None
    try:
        resolved = os.path.realpath(link_path)
        if os.path.exists(resolved):
            target = resolved
    except OSError:
        target = None

    if target is None:
        try:
            destination = os.readlink(link_path)
        except OSError:
            destination = ""
        lines.append(f"{link_relative}|link|{destination}")
        return

    if os.path.isfile(target):
        if not counts_toward_fingerprint(link_relative, section_number):
            return
        append_file_line(lines, link_relative, target)
        return

    # A link to a folder: walk it under the LINK's own path prefix, not
    # following any further symlink inside it.
    walk_under_prefix(target, target, link_relative, section_number, excluded, lines)


def walk_under_prefix(physical_root, directory, relative_prefix, section_number, excluded, lines):
    try:
        entries = list(os.scandir(directory))
    except OSError:
        return

    for entry in entries:
        name = entry.name
        if name.startswith("."):
            continue

        inner_relative = relative_of(physical_root, entry.path)
        relative = relative_prefix + "/" + inner_relative
        if is_excluded(relative, excluded):
            continue

        try:
            if entry.is_symlink():
                continue  # one hop total — do not follow a link inside a linked folder
        except OSError:
            pass

        if entry.is_dir(follow_symlinks=False):
            if not folder_counts_toward_fingerprint(relative, section_number):
                continue
            walk_under_prefix(physical_root, entry.path, relative_prefix, section_number, excluded, lines)
        elif entry.is_file(follow_symlinks=False):
            if not counts_toward_fingerprint(relative, section_number):
                continue
            append_file_line(lines, relative, entry.path)


def fingerprint(course_directory, section_number, excluded):
    lines = []
    walk(course_directory, course_directory, section_number, excluded, lines, hops_remaining=1)
    lines.sort()  # ordinal — Python's default string sort is by code point, matching StringComparer.Ordinal
    joined = "\n".join(lines)
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: section_fingerprint.py <course_directory> <section_number> [exclude ...]\n")
        return 2
    course_directory = argv[1]
    try:
        section_number = int(argv[2])
    except ValueError:
        sys.stderr.write(f"not a section number: {argv[2]}\n")
        return 2
    excluded = argv[3:]

    print(fingerprint(course_directory, section_number, excluded))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

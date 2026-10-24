#!/usr/bin/env python3
"""Writes the app bundle's `toolchain.hashes` (GitHub #663).

Run by the "Write the toolchain's fingerprints" build phase in project.yml,
AFTER Xcode has copied the resources and before it signs the bundle:

    /usr/bin/python3 -I write_toolchain_hashes.py <bundle Resources folder>

One line per file the working-folder mirror copies
(`WorkspaceModel.copyToolchainFiles`): the ten root files and everything under
`patches/`, `scripts/`, `support/` and `contracts/`. Four tab-separated fields,
the same four as Windows' `Toolchain\\.hashes` (#559):

    relative/path  length  UTC time in .NET ticks  SHA-256 (lower-case hex)

Written FROM THE BUNDLE, after the copy, so the times are the bundle's own
exact times. That is the one way the mac differs from Windows, whose manifest
is written from the build tree: Xcode's folder-reference copy restamps every
file it copies (0 of 12,901 files kept the checkout's time, measured
2026-10-23), so a manifest written from the source tree would describe no file
the app carries.

Incremental: a file whose length and time still match the previous manifest's
line keeps that line's hash without being read, so a build that copied nothing
new costs a walk and a stat per file. The file is written whole (a temporary
file, then a rename) and only when it would change.
"""

import hashlib
import os
import sys

MANIFEST_NAME = "toolchain.hashes"

# Kept in step with `copyToolchainFiles`; ToolchainFingerprintTests checks the
# app's manifest has one line per file the mirror copies.
ROOT_FILES = [
    "Dockerfile",
    "setup.sh", "preview.sh", "deploy.sh",
    "setup.bat", "preview.bat", "deploy.bat",
    "setup.ps1", "preview.ps1", "deploy.ps1",
]
FOLDERS = ["patches", "scripts", "support", "contracts"]

# 1 January 0001 to 1 January 1970, in 100-nanosecond ticks.
TICKS_AT_UNIX_EPOCH = 621355968000000000


def ticks_of(stat_result):
    return TICKS_AT_UNIX_EPOCH + stat_result.st_mtime_ns // 100


def read_previous(path):
    previous = {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 4 and len(parts[3]) == 64:
                    previous[parts[0]] = (parts[1], parts[2], parts[3])
    except OSError:
        pass
    return previous


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1 << 20)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def files_to_describe(resources):
    relatives = []
    for name in ROOT_FILES:
        if os.path.isfile(os.path.join(resources, name)):
            relatives.append(name)
    for folder in FOLDERS:
        top = os.path.join(resources, folder)
        for directory, _subfolders, names in os.walk(top):
            for name in names:
                full = os.path.join(directory, name)
                # Regular files only, as the mirror's enumerator takes them.
                if os.path.isfile(full) and not os.path.islink(full):
                    relatives.append(os.path.relpath(full, resources).replace(os.sep, "/"))
    relatives.sort()
    return relatives


def main():
    if len(sys.argv) != 2:
        print("usage: write_toolchain_hashes.py <bundle Resources folder>", file=sys.stderr)
        return 2
    resources = sys.argv[1]
    if not os.path.isdir(os.path.join(resources, "scripts")):
        print(f"error: {resources} holds no scripts/ folder; the resources were not copied", file=sys.stderr)
        return 1
    manifest = os.path.join(resources, MANIFEST_NAME)
    previous = read_previous(manifest)
    lines = []
    hashed = 0
    for relative in files_to_describe(resources):
        full = os.path.join(resources, relative)
        status = os.stat(full)
        length = str(status.st_size)
        ticks = str(ticks_of(status))
        known = previous.get(relative)
        if known is not None and known[0] == length and known[1] == ticks:
            digest = known[2]
        else:
            digest = sha256_of(full)
            hashed += 1
        lines.append(f"{relative}\t{length}\t{ticks}\t{digest}\n")
    text = "".join(lines)
    try:
        with open(manifest, "r", encoding="utf-8") as handle:
            if handle.read() == text:
                print(f"toolchain.hashes: {len(lines)} files, unchanged")
                return 0
    except OSError:
        pass
    temporary = manifest + f".{os.getpid()}.tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(temporary, manifest)
    print(f"toolchain.hashes: {len(lines)} files, {hashed} hashed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

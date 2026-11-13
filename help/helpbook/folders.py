"""Writing an output folder atomically and quietly.

Each output is built into `<out>.building` and swapped in at the end, so a
deleted page never lingers in the old copy and a failed build leaves the old
one untouched. A picture that has not changed since the last build is hard
linked from the old copy (same size and SHA-256), so it is never rewritten and
an incremental Xcode build does not see it as new.
"""

from __future__ import annotations

import hashlib
import os
import shutil
from pathlib import Path
from typing import Callable

from .problems import HelpError


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk: bytes = handle.read(1 << 16)
            if len(chunk) == 0:
                break
            digest.update(chunk)
    return digest.hexdigest()


def place_picture(source: Path, destination: Path, old_copy: Path) -> None:
    """Hard link the old copy when it is the same picture, else copy."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    if old_copy.exists() and old_copy.stat().st_size == source.stat().st_size:
        if sha256_of(old_copy) == sha256_of(source):
            os.link(str(old_copy), str(destination))
            return
    shutil.copy2(str(source), str(destination))


def remove_tree(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(str(path))
    elif path.exists() or path.is_symlink():
        path.unlink()


def build_atomically(out: Path, write: Callable[[Path], None]) -> None:
    """Calls write(building_folder), then swaps the result in for `out`."""
    building: Path = out.with_name(out.name + ".building")
    retired: Path = out.with_name(out.name + ".old")
    remove_tree(building)
    remove_tree(retired)
    out.parent.mkdir(parents=True, exist_ok=True)
    try:
        building.mkdir()
        write(building)
    except BaseException:
        remove_tree(building)
        raise
    if out.exists() and not out.is_dir():
        remove_tree(building)
        raise HelpError(str(out) + " exists and is not a folder")
    if out.exists():
        os.rename(str(out), str(retired))
    os.rename(str(building), str(out))
    remove_tree(retired)


def folder_size(path: Path) -> int:
    total: int = 0
    for root, _folders, files in os.walk(str(path)):
        for name in files:
            total += os.lstat(os.path.join(root, name)).st_size
    return total


def human_size(size: int) -> str:
    if size >= 1024 * 1024:
        return "{:.1f} MB".format(size / (1024.0 * 1024.0))
    return "{:.0f} KB".format(size / 1024.0)

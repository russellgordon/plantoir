#!/usr/bin/env python3
"""
Reading the Plantoir contract from Python.

`contracts/` has always been the one home for a rule both apps must agree on,
run as data by the macOS and Windows test suites. Until now nothing under
`scripts/` could read it, so a rule that ALSO lives in the Python — and the
rules about which folders carry meaning all do, because `build_site.py` is
what actually decides what ships — existed as a third implementation with no
gate on it. That is the drift the contract exists to prevent, arriving by the
back door.

**Where the files come from.** `toolchain_paths.CONTRACTS_DIR`, which is
`/opt/contracts` in the container and the app's bundled copy when Windows runs
these scripts natively. The container's ONLY bind mount is `courses`, so the
working folder's `.toolchain/` cannot be read from in here and neither can the
app bundle — the contract has to be baked into the image. That is why the
Dockerfile copies it, and why a contract edit changes the image hash and
forces a rebuild: accepted deliberately, because the alternative is a rule the
container cannot see.

**Reading is deliberately strict.** A missing or malformed contract raises
rather than falling back to a built-in default. A silent fallback would mean a
build quietly using a rule nobody could see, which is exactly the failure mode
this module was written to close. Callers that must survive a missing contract
say so explicitly with `optional=True`.
"""

import json
from pathlib import Path

import toolchain_paths


class ContractMissing(Exception):
    """The contract file is not where the toolchain expects it."""


# Parsed files, by name. These are read many times per build (every check
# consults one) and never change while a build runs.
_cache: dict = {}


def contracts_dir() -> Path:
    return Path(toolchain_paths.CONTRACTS_DIR)


def load(name: str, optional: bool = False):
    """
    One contract file, parsed. `name` is the bare file name with or without
    the .json suffix — `load("shared-rules")` and `load("shared-rules.json")`
    are the same file.

    Raises ContractMissing when the file is absent or unreadable, unless
    `optional` is True, in which case the caller gets None and has said in its
    own code that it can carry on without it.
    """
    file_name = name if name.endswith(".json") else name + ".json"
    if file_name in _cache:
        return _cache[file_name]

    path = contracts_dir() / file_name
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        if optional:
            return None
        raise ContractMissing(
            f"Cannot read the contract file '{file_name}' at {path}: {error}. "
            "Inside the container it is baked in by the Dockerfile "
            "(COPY contracts/); running natively it comes from "
            "PLANTOIR_CONTRACTS_DIR."
        ) from error

    try:
        parsed = json.loads(text)
    except ValueError as error:
        if optional:
            return None
        raise ContractMissing(
            f"The contract file '{file_name}' at {path} is not valid JSON: {error}"
        ) from error

    _cache[file_name] = parsed
    return parsed


def section(file_name: str, *keys, optional: bool = False):
    """
    A nested value out of one contract file, by successive keys:

        section("shared-rules", "curriculumRules", "isCurriculumPage")

    Raises ContractMissing naming the key that was not found, rather than
    letting a None travel into the caller and fail somewhere less obvious.
    """
    value = load(file_name, optional=optional)
    if value is None:
        return None
    walked = []
    for key in keys:
        walked.append(key)
        if not isinstance(value, dict) or key not in value:
            if optional:
                return None
            raise ContractMissing(
                f"The contract file '{file_name}' has no "
                f"'{'.'.join(walked)}' — the apps and the scripts disagree "
                "about the shape of the contract."
            )
        value = value[key]
    return value


def reset_cache() -> None:
    """Forget every parsed file. For tests that point CONTRACTS_DIR elsewhere."""
    _cache.clear()

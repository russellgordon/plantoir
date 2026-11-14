"""
The sounds the rendered check's Music page and the page-authoring skill's
music example play (#679), fetched once into the dev cache and planted where
a build keeps what its pages download, so the fixture builds ask GitHub
nothing.

    python3 browser-checks/lib/plant_sounds.py fetch
    python3 browser-checks/lib/plant_sounds.py plant <a working folder's builds folder>
    python3 browser-checks/lib/plant_sounds.py check

The repository never carries a sound file. `fetch` downloads each sound
rendered_rows.json -> soundsFixture names, from the address and commit
contracts/toolchain.json -> pins -> fluidR3Sounds pins, into
`${PLANTOIR_SOUNDS_CACHE:-~/Library/Caches/Plantoir-dev/sounds}/<commit>/`,
refusing any file whose SHA-256 is not the pinned one. `plant` keeps them in
`<builds folder>/.downloaded/sounds/<name>/<version>/` through the build's
own kept_downloads.Store, so each entry is exactly what a build would have
kept. `check` says whether the cache holds a good copy of each.

Exit 0 when it did what it says; 3 (and one line saying why) when the cache
has no good copy, which verify.sh reports as a SKIP by name; 1 otherwise.
Prints no path outside the cache and no name.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent.parent
FIXTURE = json.loads((HERE.parent / "rendered_rows.json").read_text(encoding="utf-8"))["soundsFixture"]


def _scripts():
    scripts = REPOSITORY / "scripts"
    if str(scripts) not in sys.path:
        sys.path.insert(0, str(scripts))
    import toolchain_paths
    toolchain_paths.CONTRACTS_DIR = REPOSITORY / "contracts"
    import contracts
    contracts.reset_cache()
    import kept_downloads
    import music
    return kept_downloads, music


def _pin() -> dict:
    for pin in json.loads((REPOSITORY / "contracts" / "toolchain.json").read_text(encoding="utf-8"))["pins"]:
        if pin["pin"] == "fluidR3Sounds":
            return pin
    raise SystemExit("plant_sounds: contracts/toolchain.json has no fluidR3Sounds pin")


def cache_folder() -> Path:
    root = os.environ.get("PLANTOIR_SOUNDS_CACHE", "").strip()
    base = Path(root) if root else Path.home() / "Library" / "Caches" / "Plantoir-dev" / "sounds"
    return base / _pin()["value"]


def good_copy() -> dict | None:
    pin = _pin()
    found = {}
    for name in FIXTURE["sounds"]:
        wanted = pin["files"][name]
        try:
            data = (cache_folder() / wanted["file"]).read_bytes()
        except OSError:
            return None
        if hashlib.sha256(data).hexdigest() != wanted["sha256"]:
            return None
        found[name] = data
    return found


def fetch() -> int:
    if good_copy() is not None:
        print(f"plant_sounds: the dev cache already holds {', '.join(FIXTURE['sounds'])}")
        return 0
    kept_downloads, music = _scripts()
    pin = _pin()
    fetcher = kept_downloads.Fetcher(music.rules("download", "hosts"))
    folder = cache_folder()
    folder.mkdir(parents=True, exist_ok=True)
    for name in FIXTURE["sounds"]:
        wanted = pin["files"][name]
        try:
            data = fetcher.get(pin["base"].rstrip("/") + "/" + wanted["file"])
        except kept_downloads.DownloadFailed as failed:
            print(f"plant_sounds: {name} could not be downloaded ({failed.reason})")
            return 3
        digest = hashlib.sha256(data).hexdigest()
        if digest != wanted["sha256"]:
            print(f"plant_sounds: {name} is not the pinned file (SHA-256 {digest[:12]}..., pinned {wanted['sha256'][:12]}...); nothing kept")
            return 1
        temporary = folder / (wanted["file"] + ".part")
        temporary.write_bytes(data)
        os.replace(temporary, folder / wanted["file"])
    print(f"plant_sounds: fetched {', '.join(FIXTURE['sounds'])} into the dev cache")
    return 0


def plant(builds: Path) -> int:
    copy = good_copy()
    if copy is None:
        print("plant_sounds: no good copy of the fixture's sounds in the dev cache (run python3 browser-checks/lib/plant_sounds.py fetch)")
        return 3
    kept_downloads, music = _scripts()
    pin = _pin()
    store = kept_downloads.Store(builds / kept_downloads.FOLDER, music.KIND)
    for name, data in copy.items():
        wanted = pin["files"][name]
        entry = store.put(name, pin["version"], {wanted["file"]: data}, about={"planted": True},
                          expected={wanted["file"]: wanted["sha256"]})
        if entry is None:
            print("plant_sounds: a sound could not be planted")
            return 1
    print(f"plant_sounds: planted {', '.join(FIXTURE['sounds'])} where the build keeps its downloads")
    return 0


def main(arguments: list[str]) -> int:
    if arguments == ["fetch"]:
        return fetch()
    if arguments == ["check"]:
        if good_copy() is None:
            print("plant_sounds: no good copy of the fixture's sounds in the dev cache")
            return 3
        print(f"plant_sounds: the dev cache holds {', '.join(FIXTURE['sounds'])}")
        return 0
    if len(arguments) == 2 and arguments[0] == "plant":
        return plant(Path(arguments[1]))
    print("usage: plant_sounds.py fetch | check | plant <builds folder>")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

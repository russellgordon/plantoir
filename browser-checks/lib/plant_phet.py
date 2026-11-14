"""
The PhET simulation the rendered check's Simulation page names (#674),
fetched once into the dev cache and planted where a build keeps what its
pages download, so the fixture build asks PhET nothing.

    python3 browser-checks/lib/plant_phet.py fetch
    python3 browser-checks/lib/plant_phet.py plant <a working folder's builds folder>
    python3 browser-checks/lib/plant_phet.py check

The repository never carries a PhET file: PhET's licence lets a class site
carry a copy with PhET's credit line, and Russell's ruling of 2026-11-13 is
that Plantoir itself carries and redistributes none. `fetch` downloads the
two files rendered_rows.json -> phetFixture pins into
`${PLANTOIR_PHET_CACHE:-~/Library/Caches/Plantoir-dev/phet}/<sim>/<version>/`,
refusing any whose SHA-256 is not the pinned one (the simulation after the
analytics script PhET's servers sometimes add is taken out,
phetFences.download.removedOnTheWay, with the build's own code). `plant`
copies them into `<builds folder>/.downloaded/phet/<sim>/<version>/` through
the build's own kept_downloads.Store, so the entry is exactly what a build
would have kept. `check` says whether the cache holds a good copy.

Exit 0 when it did what it says; 3 (and one line saying why) when the cache
has no good copy, which verify.sh reports as a SKIP by name; 1 otherwise.
Prints no path outside the cache and no name.
"""
from __future__ import annotations

import gzip
import hashlib
import json
import os
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent.parent
FIXTURE = json.loads((HERE.parent / "rendered_rows.json").read_text(encoding="utf-8"))["phetFixture"]


def _scripts():
    scripts = REPOSITORY / "scripts"
    if str(scripts) not in sys.path:
        sys.path.insert(0, str(scripts))
    import toolchain_paths
    toolchain_paths.CONTRACTS_DIR = REPOSITORY / "contracts"
    import contracts
    contracts.reset_cache()
    import kept_downloads
    import phet
    return kept_downloads, phet


def cache_folder() -> Path:
    root = os.environ.get("PLANTOIR_PHET_CACHE", "").strip()
    base = Path(root) if root else Path.home() / "Library" / "Caches" / "Plantoir-dev" / "phet"
    return base / FIXTURE["sim"] / FIXTURE["version"]


def good_copy() -> dict | None:
    folder = cache_folder()
    found = {}
    for name, pin in FIXTURE["files"].items():
        try:
            data = (folder / name).read_bytes()
        except OSError:
            return None
        if hashlib.sha256(data).hexdigest() != pin["sha256"]:
            return None
        found[name] = data
    return found


def fetch() -> int:
    if good_copy() is not None:
        print(f"plant_phet: the dev cache already holds {FIXTURE['sim']} {FIXTURE['version']}")
        return 0
    kept_downloads, phet = _scripts()
    fetcher = kept_downloads.Fetcher(["phet.colorado.edu"])
    folder = cache_folder()
    folder.mkdir(parents=True, exist_ok=True)
    for name, pin in FIXTURE["files"].items():
        try:
            data = fetcher.get(pin["from"])
        except kept_downloads.DownloadFailed as failed:
            print(f"plant_phet: {name} could not be downloaded ({failed.reason})")
            return 3
        if name == "simulation.html":
            data = phet.cleaned(data)
        digest = hashlib.sha256(data).hexdigest()
        if digest != pin["sha256"]:
            print(f"plant_phet: {name} is not the pinned file (SHA-256 {digest[:12]}..., pinned {pin['sha256'][:12]}...); nothing kept")
            return 1
        temporary = folder / (name + ".part")
        temporary.write_bytes(data)
        os.replace(temporary, folder / name)
    print(f"plant_phet: fetched {FIXTURE['sim']} {FIXTURE['version']} into the dev cache")
    return 0


def plant(builds: Path) -> int:
    copy = good_copy()
    if copy is None:
        print(f"plant_phet: no good copy of {FIXTURE['sim']} {FIXTURE['version']} in the dev cache (run python3 browser-checks/lib/plant_phet.py fetch)")
        return 3
    kept_downloads, phet = _scripts()
    store = kept_downloads.Store(builds / kept_downloads.FOLDER, phet.KIND)
    about = {"project": FIXTURE["project"], "languages": sorted(FIXTURE["titles"]), "titles": FIXTURE["titles"],
             "gzippedBytes": len(gzip.compress(copy["simulation.html"], 9)),
             "from": FIXTURE["files"]["simulation.html"]["from"],
             "downloadedOn": time.strftime("%Y-%m-%d", time.gmtime())}
    expected = {name: pin["sha256"] for name, pin in FIXTURE["files"].items()}
    entry = store.put(FIXTURE["sim"], FIXTURE["version"], copy, about=about, expected=expected)
    if entry is None:
        print("plant_phet: the copy could not be planted")
        return 1
    print(f"plant_phet: planted {FIXTURE['sim']} {FIXTURE['version']} where the build keeps its downloads")
    return 0


def main(arguments: list[str]) -> int:
    if arguments == ["fetch"]:
        return fetch()
    if arguments == ["check"]:
        if good_copy() is None:
            print(f"plant_phet: no good copy of {FIXTURE['sim']} {FIXTURE['version']} in the dev cache")
            return 3
        print(f"plant_phet: the dev cache holds {FIXTURE['sim']} {FIXTURE['version']}")
        return 0
    if len(arguments) == 2 and arguments[0] == "plant":
        return plant(Path(arguments[1]))
    print("usage: plant_phet.py fetch | check | plant <builds folder>")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Builds Plantoir Help from help/: checks it, writes the Mac Help book, writes
the web copy, or serves a built web copy. help/README.md explains the format.

    /usr/bin/python3 -I -B help/build_help.py --check
    /usr/bin/python3 -I -B help/build_help.py --mac <out>/Plantoir.help [--app-version 2.0.0]
    /usr/bin/python3 -I -B help/build_help.py --web <out>
    /usr/bin/python3 -I -B help/build_help.py --release-web <out>
    /usr/bin/python3 -I -B help/build_help.py --serve <out>

Every command but --serve runs every check first and exits 1 on any failure;
warnings are printed and never fail a build.
"""

from __future__ import annotations

import sys
from pathlib import Path

# -I takes this script's folder off sys.path, so put it back explicitly. The
# repository is this folder's parent, never the current directory: the Xcode
# build phase runs this script from elsewhere.
HELP_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(HELP_DIR))
# Never leave a __pycache__ in help/ (or in the app bundle's copy), even when
# run without -B.
sys.dont_write_bytecode = True

import argparse  # noqa: E402
from typing import List, Optional, Set  # noqa: E402

from helpbook.checks import run_structural_checks  # noqa: E402
from helpbook.macbook import build_mac  # noqa: E402
from helpbook.problems import HelpError, Problems  # noqa: E402
from helpbook.render import HelpSource, PageRenderer  # noqa: E402
from helpbook.serve import serve  # noqa: E402
from helpbook.web import build_web, web_page_ids  # noqa: E402


def parse_arguments(arguments: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Plantoir Help.")
    commands = parser.add_mutually_exclusive_group(required=True)
    commands.add_argument("--check", action="store_true", help="run every check; write nothing")
    commands.add_argument("--mac", metavar="OUT", help="write the Help book (…/Plantoir.help)")
    commands.add_argument("--web", metavar="OUT", help="write the web copy")
    commands.add_argument("--release-web", metavar="OUT", help="write the web copy, refusing any stub or placeholder")
    commands.add_argument("--serve", metavar="OUT", help="serve a built web copy on 127.0.0.1 and print the address")
    parser.add_argument("--app-version", default="0", help="the app's version, for the book's Info.plist")
    # For the tests: another help folder and repository (fixtures).
    parser.add_argument("--help-dir", default=str(HELP_DIR), help=argparse.SUPPRESS)
    parser.add_argument("--repo", default=None, help=argparse.SUPPRESS)
    parser.add_argument("--today", default=None, help=argparse.SUPPRESS)
    return parser.parse_args(arguments)


def print_findings(problems: Problems) -> None:
    for warning in problems.warnings:
        print("warning: " + warning)
    for failure in problems.failures:
        print("FAILED: " + failure)


def main(arguments: Optional[List[str]] = None) -> int:
    options = parse_arguments(sys.argv[1:] if arguments is None else arguments)
    if options.serve is not None:
        try:
            serve(Path(options.serve).resolve())
        except HelpError as error:
            print("FAILED: " + str(error))
            return 1
        return 0

    help_dir: Path = Path(options.help_dir).resolve()
    repo: Path = Path(options.repo).resolve() if options.repo is not None else help_dir.parent
    problems = Problems()
    try:
        today = None
        if options.today is not None:
            import datetime

            today = datetime.date.fromisoformat(options.today)
        source = HelpSource(repo, help_dir, problems, today)
        run_structural_checks(source)
        all_ids: Set[str] = set()
        for page in source.pages:
            all_ids.add(page.id)
        mac_renderer = PageRenderer(source, "mac", all_ids)
        mac_renderer.render_all()
        web_renderer = PageRenderer(source, "web", web_page_ids(source))
        web_renderer.render_all()
        source.registries.report_unused(problems)
        # What only the web copy may not say stops --web and --release-web, and
        # is a warning elsewhere, so the Xcode build is never failed by it.
        building_the_web: bool = options.web is not None or options.release_web is not None
        for file, line, message in source.web_findings:
            if building_the_web:
                problems.fail(file, line, "on the web copy: " + message)
            else:
                problems.warn(file, line, "on the web copy: " + message)
    except HelpError as error:
        print_findings(problems)
        print("FAILED: " + str(error))
        return 1

    print_findings(problems)
    stubs: int = 0
    for page in source.pages:
        if page.is_stub:
            stubs += 1
    awaiting: int = 0
    for scene_id in source.registries.scenes:
        if source.registries.scenes[scene_id].get("awaiting_capture") is True:
            awaiting += 1
    summary: str = (
        "Help: " + str(len(source.pages) - stubs) + " pages written, " + str(stubs) + " stubs, "
        + str(awaiting) + " scenes awaiting capture, " + str(len(problems.warnings)) + " warnings, "
        + str(len(problems.failures)) + " failures"
    )
    print(summary)
    if problems.has_failures():
        return 1

    try:
        if options.mac is not None:
            print(build_mac(source, mac_renderer, Path(options.mac).resolve(), options.app_version))
        elif options.web is not None:
            print(build_web(source, web_renderer, Path(options.web).resolve(), release=False))
        elif options.release_web is not None:
            print(build_web(source, web_renderer, Path(options.release_web).resolve(), release=True))
    except HelpError as error:
        print("FAILED: " + str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

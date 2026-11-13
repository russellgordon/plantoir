#!/usr/bin/env python3
"""Does a headless Plantoir mode become an application? (#850's fix round.)

    check_headless_modes.py --app <Plantoir.app>

Starts the bundle's binary once in each headless mode that runs while the
teacher works, `--serve-deployed-folder` and `--mcp-stdio`, and asks the
system from outside: is the child known to LaunchServices as an
application (`lsappinfo find pid=<pid>`), and did the frontmost
application change (`lsappinfo front`, before and after)? Then it closes
the child's input and times how long it takes to leave.

It RUNS THE APP BINARY, so run it only when the screen is free. It prints
one line per mode and exits 1 when `--serve-deployed-folder` fails any of
its checks. `--mcp-stdio` is reported, not judged: #850 changes only the
deployed-folder mode.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time


def lsappinfo(*arguments):
    answer = subprocess.run(["lsappinfo", *arguments], capture_output=True, text=True, timeout=10)
    return answer.stdout.strip()


def child_environment():
    """This shell's environment, less anything the loader or XCTest put there."""
    environment = {}
    for key, value in os.environ.items():
        if key.startswith("DYLD_") or key.startswith("XC") or key.startswith("__XPC_"):
            continue
        environment[key] = value
    return environment


def first_line(stream, seconds):
    """The child's first line, or None if none came within `seconds`. Read on
    a thread, so a child that prints nothing cannot hang this script."""
    found = []

    def read():
        found.append(stream.readline())

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    reader.join(seconds)
    if not found:
        return None
    return found[0].strip()


def one_mode(binary, arguments, wait_for_line):
    front_before = lsappinfo("front")
    child = subprocess.Popen(
        [binary, *arguments],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        env=child_environment(),
    )
    line = ""
    if wait_for_line:
        line = first_line(child.stdout, 15)
        if line is None:
            line = "(printed nothing within 15 s)"
    # Sampled every 100 ms for 3 s, so an application that registers late, or
    # takes the front and gives it back, is still seen.
    registered = False
    front_changed = False
    sampling_until = time.time() + 3
    while time.time() < sampling_until:
        if lsappinfo("find", f"pid={child.pid}") != "":
            registered = True
        if lsappinfo("front") != front_before:
            front_changed = True
        time.sleep(0.1)
    started = time.time()
    child.stdin.close()
    try:
        child.wait(timeout=10)
        seconds = round(time.time() - started, 2)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait(timeout=5)
        seconds = None
    return {
        "line": line,
        "isAnApplication": registered,
        "frontChanged": front_changed,
        "secondsToLeave": seconds,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True)
    arguments = parser.parse_args()
    binary = os.path.join(arguments.app, "Contents", "MacOS", "Plantoir")
    if not os.path.isfile(binary):
        print(f"FAILED: no Plantoir at {binary}")
        sys.exit(2)
    scratch = tempfile.mkdtemp()
    try:
        site = os.path.join(scratch, "site")
        os.makedirs(site)
        with open(os.path.join(site, "index.html"), "w") as page:
            page.write("home")
        folder = os.path.join(scratch, "working-folder")
        os.makedirs(os.path.join(folder, "courses"))

        served = one_mode(binary, ["--serve-deployed-folder", site], wait_for_line=True)
        # Its own state folder, read before --mcp-stdio, so the teacher's
        # preferences and trail are not touched.
        state = os.path.join(scratch, "state")
        os.makedirs(state)
        mcp = one_mode(binary, ["--state-dir", state, "--mcp-stdio", folder], wait_for_line=False)
    finally:
        shutil.rmtree(scratch)

    print(f"--serve-deployed-folder: {served}")
    print(f"--mcp-stdio (reported only; if isAnApplication or frontChanged is True, it needs an issue of its own): {mcp}")
    good = (
        served["line"].startswith("DEPLOYED_FOLDER_ADDRESS=")
        and not served["isAnApplication"]
        and not served["frontChanged"]
        and served["secondsToLeave"] is not None
        and served["secondsToLeave"] < 5
        and not served["line"].startswith("(printed nothing")
    )
    sys.exit(0 if good else 1)


if __name__ == "__main__":
    main()

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
import time


def lsappinfo(*arguments):
    answer = subprocess.run(["lsappinfo", *arguments], capture_output=True, text=True)
    return answer.stdout.strip()


def one_mode(binary, arguments, wait_for_line):
    front_before = lsappinfo("front")
    child = subprocess.Popen(
        [binary, *arguments],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    line = ""
    if wait_for_line:
        line = child.stdout.readline().strip()
    else:
        time.sleep(3)
    registered = lsappinfo("find", f"pid={child.pid}")
    front_after = lsappinfo("front")
    started = time.time()
    child.stdin.close()
    try:
        child.wait(timeout=10)
        seconds = time.time() - started
    except subprocess.TimeoutExpired:
        child.kill()
        seconds = None
    return {
        "line": line,
        "isAnApplication": registered != "",
        "frontChanged": front_before != front_after,
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
        mcp = one_mode(binary, ["--mcp-stdio", folder], wait_for_line=False)
    finally:
        shutil.rmtree(scratch)

    print(f"--serve-deployed-folder: {served}")
    print(f"--mcp-stdio (reported only): {mcp}")
    good = (
        served["line"].startswith("DEPLOYED_FOLDER_ADDRESS=")
        and not served["isAnApplication"]
        and not served["frontChanged"]
        and served["secondsToLeave"] is not None
        and served["secondsToLeave"] < 5
    )
    sys.exit(0 if good else 1)


if __name__ == "__main__":
    main()

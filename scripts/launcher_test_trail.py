"""
Every launcher a test runs keeps its trail in a folder of its own (#738).

Importing this module sets PLANTOIR_TRAIL_DIR, for this process and so for
every launcher it starts with an environment built from os.environ, to a
temporary folder that is removed when the run ends. The launchers'
note_on_the_trail writes there (#664) instead of into the teacher's real
~/Library/Logs/Plantoir/activity.txt. That happened on 2026-11-01: reproducing
a flake wrote an estimated 30 to 60 "stopped before it started" lines into the
real log, because the deploy tests ran deploy.sh without the redirect.

A test that hands a launcher a scratch HOME and pops the variable, so its line
lands in that HOME where the test can read it, is unaffected. Every test file
that runs a launcher imports this module; scripts/test_launcher_tests_keep_their_trail.py
holds that rule and proves the redirect on the launchers' real function.

Not a product module: nothing outside the tests imports it, and the image
carries it only where verify.sh mounts it beside a test it runs there.
"""

import atexit
import os
import shutil
import tempfile

FOLDER = tempfile.mkdtemp(prefix="plantoir-test-trail-")
os.environ["PLANTOIR_TRAIL_DIR"] = FOLDER
atexit.register(shutil.rmtree, FOLDER, True)

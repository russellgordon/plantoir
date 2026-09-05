#!/usr/bin/env python3
"""
Regression test for deploy.py's course-directory resolution.

Found 2026-08-22 from a real report: on Windows, scheduling a deploy for a
section that had just been published successfully refused with "has never
been deployed" — the Netlify/Cloudflare site marker (`.netlify_sites/` /
`.cloudflare_sites/`) had been written under the wrong folder entirely, so
it was never found, and every deploy silently created a brand-new site
instead of reusing the one from last time.

Root cause: `main()` used to derive the course directory by climbing two
levels from the built section's own folder — `section_dir.parent.parent`,
assuming the container/mac layout `.../<COURSE>/.merged_output/section#`.
That assumption breaks under Windows' native `PLANTOIR_BUILD_ROOT`, which
`toolchain_paths.merged_output_root()` uses to move the build tree OUT of
the working folder entirely (so builds never churn inside a OneDrive-synced
folder) — and does NOT nest a `.merged_output` level when it does, so the
built section is only ONE level below the build root, not two. Climbing two
levels there landed on the build root's own parent, not the course.

**It now guards the mac as well** (2026-09-05). The mac moved its build
output out of the working folder too, by a different route:
`courses/<CODE>/.merged_output` is a SYMLINK to a builds folder under
Application Support, and `main()` calls `.resolve()` on the built section's
path — so `section_dir.parent.parent` climbs to the builds folder's parent
there too, and the old computation would have written the Netlify/Cloudflare
markers into Application Support and created a brand-new published site on
every deploy. The Windows fix was already in place and already pinned here,
which is why that never happened. The case below still exercises
`PLANTOIR_BUILD_ROOT`, because that is the layout it can build without a
symlink; the rule it protects is the same one.

Pure stdlib, no Docker and no network — this pins the structural mismatch
directly, without needing a real build. Run with:

    python3 scripts/test_deploy_course_dir_resolution.py

verify.sh runs this early, before the (slow) Docker build, since nothing
here needs the image.
"""
import os
import tempfile
import unittest
from pathlib import Path

import toolchain_paths


class CourseDirResolutionTests(unittest.TestCase):

    def test_climbing_two_levels_from_section_dir_breaks_under_a_native_build_root(self):
        """
        Pins the bug directly: with PLANTOIR_BUILD_ROOT set (the native
        Windows layout), the old `section_dir.parent.parent` computation
        does NOT land back on the course directory. If this test ever
        starts failing because the two became equal, `merged_output_root`
        gained a nested layer and the guard comment on `course_dir` in
        `deploy.py`'s `main()` should be revisited — but `course_dir` must
        keep being derived from `COURSES_ROOT / course_code` directly
        either way, never from the built section's own ancestry.
        """
        with tempfile.TemporaryDirectory() as tmp:
            courses_dir = Path(tmp) / "working-folder" / "courses"
            build_root = Path(tmp) / "builds" / "abc123"
            course_dir = courses_dir / "ICD2O"
            course_dir.mkdir(parents=True)
            build_root.mkdir(parents=True)

            old_env = os.environ.get("PLANTOIR_BUILD_ROOT")
            os.environ["PLANTOIR_BUILD_ROOT"] = str(build_root)
            try:
                section_dir = toolchain_paths.merged_output_root(course_dir) / "section1"
                climbed = section_dir.parent.parent
                self.assertNotEqual(
                    climbed, course_dir,
                    "merged_output_root() no longer breaks section_dir.parent.parent under "
                    "PLANTOIR_BUILD_ROOT — see this test's docstring before changing deploy.py "
                    "back to deriving course_dir from section_dir's ancestry."
                )
            finally:
                if old_env is None:
                    os.environ.pop("PLANTOIR_BUILD_ROOT", None)
                else:
                    os.environ["PLANTOIR_BUILD_ROOT"] = old_env

    def test_course_dir_is_correct_under_a_native_build_root(self):
        """The fix: COURSES_ROOT / course code, unaffected by where the build output lives."""
        with tempfile.TemporaryDirectory() as tmp:
            courses_dir = Path(tmp) / "working-folder" / "courses"
            course_dir = courses_dir / "ICD2O"
            course_dir.mkdir(parents=True)

            old_env = os.environ.get("PLANTOIR_COURSES_DIR")
            os.environ["PLANTOIR_COURSES_DIR"] = str(courses_dir)
            try:
                # Mirrors deploy.py main()'s `course_dir = COURSES_ROOT / args.course`
                # — reloaded here so the env var above is picked up, since
                # COURSES_ROOT is captured at import time.
                import importlib
                import toolchain_paths as tp
                importlib.reload(tp)
                resolved = tp.COURSES_DIR / "ICD2O"
                self.assertEqual(resolved, course_dir)
            finally:
                import importlib
                import toolchain_paths as tp
                if old_env is None:
                    os.environ.pop("PLANTOIR_COURSES_DIR", None)
                else:
                    os.environ["PLANTOIR_COURSES_DIR"] = old_env
                importlib.reload(tp)  # restore module state for any test that runs after this one


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""
Unit tests for build_site.py's resolve_section_domain() — specifically the
custom-domain lookup, now keyed by destination TYPE rather than being one
bare string for the whole section.

A course can publish to more than one destination at once (see
CourseConfiguration.additionalDeployTargets on the mac side), but the
baseUrl baked into a single build (sitemap, RSS, social-card absolute
URLs) can only ever be one value — so this reads the PRIMARY destination's
own custom domain, matching what the "Live URL" link on a finished deploy
has always pointed at. An older, single-string shape (written before a
course could have more than one destination) is read as-is.

Pure stdlib, no Docker and no network. Run with:

    python3 scripts/test_build_site_domain_resolution.py

verify.sh runs this early, before the (slow) Docker build, since nothing
here needs the image.
"""
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import build_site


class ResolveSectionDomainTests(unittest.TestCase):

    def test_the_old_bare_string_shape_is_read_as_is(self):
        config = {
            "deploy_target": "netlify",
            "custom_domains": {"sections": {"section1": "ics3u.school.ca"}},
        }
        domain = build_site.resolve_section_domain(Path("."), config, 1)
        self.assertEqual(domain, "ics3u.school.ca")

    def test_the_new_shape_reads_the_primary_destinations_own_domain(self):
        config = {
            "deploy_target": "cloudflare_pages",
            "custom_domains": {
                "sections": {
                    "section1": {
                        "netlify": "ics3u-netlify.school.ca",
                        "cloudflare_pages": "ics3u.school.ca",
                    }
                }
            },
        }
        domain = build_site.resolve_section_domain(Path("."), config, 1)
        self.assertEqual(
            domain, "ics3u.school.ca",
            "The baseUrl must follow the PRIMARY destination, not just whichever key sorts first"
        )

    def test_a_domain_set_only_for_a_non_primary_destination_is_never_used(self):
        # Netlify is primary here; only a Cloudflare Pages domain is set —
        # this course's build must fall through (to a marker file, or to
        # no domain at all) rather than wearing the Cloudflare domain.
        config = {
            "deploy_target": "netlify",
            "custom_domains": {
                "sections": {"section1": {"cloudflare_pages": "ics3u.school.ca"}}
            },
        }
        domain = build_site.resolve_section_domain(Path("."), config, 1)
        self.assertEqual(domain, "")

    def test_a_domain_set_only_for_a_non_primary_destination_still_falls_through_to_a_marker(self):
        config = {
            "deploy_target": "netlify",
            "custom_domains": {
                "sections": {"section1": {"cloudflare_pages": "ics3u.school.ca"}}
            },
        }
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            markers_dir = course_dir / ".netlify_sites"
            markers_dir.mkdir()
            (markers_dir / "section1.json").write_text(
                json.dumps({"name": "ics3u-s1-2026-teacher"}), encoding="utf-8"
            )
            domain = build_site.resolve_section_domain(course_dir, config, 1)
            self.assertEqual(domain, "ics3u-s1-2026-teacher.netlify.app")

    def _both_markers(self, course_dir: Path):
        (course_dir / ".netlify_sites").mkdir()
        (course_dir / ".netlify_sites" / "section1.json").write_text(
            json.dumps({"name": "ics3u-s1-2026-teacher"}), encoding="utf-8")
        (course_dir / ".cloudflare_sites").mkdir()
        (course_dir / ".cloudflare_sites" / "section1.json").write_text(
            json.dumps({"name": "ics3u-s1-2026-teacher", "subdomain": "ics3u-s1-2026-teacher.pages.dev"}),
            encoding="utf-8")

    def test_a_cloudflare_course_with_a_netlify_record_too_is_built_with_its_cloudflare_address(self):
        """#799, measured on Windows: the Netlify marker was read first
        whatever the course deployed to, so a Cloudflare course that had ever
        been deployed to Netlify carried the Netlify address, and deploy.py,
        comparing it with the Cloudflare destination's, rebuilt on every
        Cloudflare deploy."""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            self._both_markers(course_dir)
            domain = build_site.resolve_section_domain(course_dir, {"deploy_target": "cloudflare_pages"}, 1)
            self.assertEqual(domain, "ics3u-s1-2026-teacher.pages.dev")

    def test_a_netlify_course_with_a_cloudflare_record_too_keeps_its_netlify_address(self):
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            self._both_markers(course_dir)
            for config in ({"deploy_target": "netlify"}, {}, {"deploy_target": "local_folder"}):
                with self.subTest(config=config):
                    domain = build_site.resolve_section_domain(course_dir, config, 1)
                    self.assertEqual(domain, "ics3u-s1-2026-teacher.netlify.app")

    def test_a_cloudflare_course_with_only_a_netlify_record_still_has_an_address(self):
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            (course_dir / ".netlify_sites").mkdir()
            (course_dir / ".netlify_sites" / "section1.json").write_text(
                json.dumps({"name": "ics3u-s1-2026-teacher"}), encoding="utf-8")
            domain = build_site.resolve_section_domain(course_dir, {"deploy_target": "cloudflare_pages"}, 1)
            self.assertEqual(domain, "ics3u-s1-2026-teacher.netlify.app")

    def test_a_deploys_own_rebuild_bakes_the_address_it_was_asked_for(self):
        """#799: deploy.py's rebuild for a destination's address sets the
        variable on that build, and it wins over the records and the custom
        domain, so the rebuild comes out with the address it was started for
        (a Cloudflare leg of a course whose primary is Netlify included)."""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            self._both_markers(course_dir)
            config = {"deploy_target": "netlify",
                      "custom_domains": {"sections": {"section1": {"netlify": "ics3u.school.ca"}}}}
            with mock.patch.dict(os.environ, {build_site.DEPLOY_BASE_URL_VARIABLE: "https://ics3u-s1-2026-teacher.pages.dev/"}):
                domain = build_site.resolve_section_domain(course_dir, config, 1)
            self.assertEqual(domain, "ics3u-s1-2026-teacher.pages.dev")
            with mock.patch.dict(os.environ, {build_site.DEPLOY_BASE_URL_VARIABLE: "  "}):
                self.assertEqual(build_site.resolve_section_domain(course_dir, config, 1), "ics3u.school.ca")

    def test_deploy_py_sets_the_same_variable(self):
        """Read from deploy.py's text, not imported: this file imports
        build_site alone (a shared test must not import a sibling the image's
        verify.sh run lacks)."""
        source = (Path(__file__).resolve().parent / "deploy.py").read_text(encoding="utf-8")
        self.assertIn('DEPLOY_BASE_URL_VARIABLE = "%s"' % build_site.DEPLOY_BASE_URL_VARIABLE, source)

    def test_no_custom_domain_at_all_falls_through_cleanly(self):
        config = {"deploy_target": "netlify"}
        domain = build_site.resolve_section_domain(Path("."), config, 1)
        self.assertEqual(domain, "")

    def test_defaults_to_netlify_when_deploy_target_is_missing(self):
        # deploy_target is itself omitted for a course nobody has touched
        # (CourseConfiguration.deployTarget falls back to "netlify" the
        # same way) — the domain lookup must fall back identically.
        config = {
            "custom_domains": {"sections": {"section1": {"netlify": "ics3u.school.ca"}}}
        }
        domain = build_site.resolve_section_domain(Path("."), config, 1)
        self.assertEqual(domain, "ics3u.school.ca")


if __name__ == "__main__":
    unittest.main()

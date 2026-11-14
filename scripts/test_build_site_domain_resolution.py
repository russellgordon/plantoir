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

    def test_a_deploys_own_rebuild_bakes_the_address_deploy_py_chose_for_its_leg(self):
        """#799: deploy.py's rebuild for a destination sets the variable to
        the address it chose for THAT leg: the leg's own custom domain when
        the course records one (deploy.leg_custom_domain, by destination
        type), else the service's host. So the variable is used as given, and
        a build with no variable still follows the primary's custom domain.
        (The third review's H1: until deploy.py chose the leg's custom domain,
        the variable carried the pages.dev host and dropped it.)"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            self._both_markers(course_dir)
            # A Cloudflare course with its own domain: no variable, the
            # preview's build, follows the primary's custom domain...
            config = {"deploy_target": "cloudflare_pages",
                      "custom_domains": {"sections": {"section1": {"cloudflare_pages": "cf.school.ca"}}}}
            self.assertEqual(build_site.resolve_section_domain(course_dir, config, 1), "cf.school.ca")
            # ...and the deploy's rebuild, asked for that domain, keeps it.
            with mock.patch.dict(os.environ, {build_site.DEPLOY_BASE_URL_VARIABLE: "cf.school.ca"}):
                self.assertEqual(build_site.resolve_section_domain(course_dir, config, 1), "cf.school.ca")
            # The Cloudflare leg of a Netlify course with only a NETLIFY
            # domain is built for its own host, never the Netlify domain.
            config = {"deploy_target": "netlify",
                      "custom_domains": {"sections": {"section1": {"netlify": "ics3u.school.ca"}}}}
            with mock.patch.dict(os.environ, {build_site.DEPLOY_BASE_URL_VARIABLE: "https://ics3u-s1-2026-teacher.pages.dev/"}):
                self.assertEqual(build_site.resolve_section_domain(course_dir, config, 1), "ics3u-s1-2026-teacher.pages.dev")
            with mock.patch.dict(os.environ, {build_site.DEPLOY_BASE_URL_VARIABLE: "  "}):
                self.assertEqual(build_site.resolve_section_domain(course_dir, config, 1), "ics3u.school.ca")

    def test_the_variable_is_taken_as_given_whatever_its_shape(self):
        """#799's fourth review, M1: a host-name shape check (the third
        review's L2) resolved a value it refused from the records, which
        follow the PRIMARY, so the second destination of a two-host course
        whose own domain was `cours.école.ca` was built with the primary's
        address. Every non-empty value is now the address, after
        clean_base_url; quartz.config.ts is kept safe by the writer instead
        (#871, test_typescript_strings.py ->
        test_the_base_url_reads_back_and_is_replaced_whole)."""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            self._both_markers(course_dir)
            config = {"deploy_target": "netlify",
                      "custom_domains": {"sections": {"section1": {"netlify": "n.school.ca"}}}}
            for given in ("cours.école.ca", "c.school.ca.", "school.ca/cs", "https://school.ca/cs/",
                          "cf.school.ca", "localhost:8081", "https://Ics3u-S1.pages.dev/", 'a"b\\c\nd'):
                with self.subTest(value=given):
                    with mock.patch.dict(os.environ, {build_site.DEPLOY_BASE_URL_VARIABLE: given}):
                        self.assertEqual(build_site.resolve_section_domain(course_dir, config, 1),
                                         build_site.clean_base_url(given))
            self.assertFalse(hasattr(build_site, "DEPLOY_BASE_URL_SHAPE"))

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

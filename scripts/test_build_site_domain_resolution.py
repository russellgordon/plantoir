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
import tempfile
import unittest
from pathlib import Path

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

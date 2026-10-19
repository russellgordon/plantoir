#!/usr/bin/env python3
"""
build_site.patch_quartz_analytics_off (#594): no site Plantoir builds loads
a page-view counter.

Quartz v4.5.0's own quartz.config.ts ships `analytics: { provider:
"plausible" }`, and Plantoir never set it up, so every Cloudflare, folder and
Preview site sent each student's page view to plausible.io (Netlify's only by
accident: the ad-badge policy blocked the script). Pure stdlib, no Docker:

    python3 scripts/test_quartz_analytics_off.py
"""
import tempfile
import unittest
from pathlib import Path

import build_site

# The head of Quartz v4.5.0's quartz.config.ts as the image carries it
# (/opt/quartz/quartz.config.ts, read 2026-10-19).
QUARTZ_DEFAULT = '''const config: QuartzConfig = {
  configuration: {
    pageTitle: "Quartz 4",
    pageTitleSuffix: "",
    enableSPA: true,
    enablePopovers: true,
    analytics: {
      provider: "plausible",
    },
    locale: "en-US",
    baseUrl: "quartz.jzhao.xyz",
'''


class AnalyticsAreTurnedOffTests(unittest.TestCase):

    def patched(self, text: str) -> str:
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "quartz.config.ts"
            config.write_text(text, encoding="utf-8")
            build_site.patch_quartz_analytics_off(config)
            return config.read_text(encoding="utf-8")

    def test_quartzs_default_plausible_block_becomes_null(self):
        text = self.patched(QUARTZ_DEFAULT)
        self.assertNotIn("plausible", text)
        self.assertIn("    analytics: null,\n    locale: \"en-US\",", text)

    def test_it_is_idempotent(self):
        once = self.patched(QUARTZ_DEFAULT)
        self.assertEqual(self.patched(once), once)

    def test_any_other_provider_is_turned_off_too(self):
        text = self.patched('  analytics: { provider: "goatcounter", websiteId: "x" },\n  locale: "en-US",\n')
        self.assertEqual(text, '  analytics: null,\n  locale: "en-US",\n')

    def test_nothing_else_in_the_config_changes(self):
        text = self.patched(QUARTZ_DEFAULT)
        self.assertEqual(text.replace("analytics: null", ""), QUARTZ_DEFAULT.replace(
            'analytics: {\n      provider: "plausible",\n    }', ""))

    def test_a_missing_config_is_not_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            build_site.patch_quartz_analytics_off(Path(tmp) / "quartz.config.ts")

    def test_the_build_calls_it_in_the_section_every_build_runs(self):
        # After the scaffold-copy block, beside the locale and baseUrl edits,
        # so a workspace copied before #594 is fixed by its next build.
        source = Path(build_site.__file__).read_text(encoding="utf-8")
        scaffold_at = source.index("if full_rebuild or not output_dir.exists():")
        base_url_call_at = source.index("    patch_quartz_base_url(config_path, section_domain)")
        call_at = source.index("    patch_quartz_analytics_off(config_path)")
        self.assertLess(scaffold_at, base_url_call_at)
        self.assertLess(base_url_call_at, call_at)


if __name__ == "__main__":
    unittest.main()

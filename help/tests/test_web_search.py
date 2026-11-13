"""The web copy: the assistant switch, platform runs, the search index and
its search function (run with node), --release-web and --serve."""

from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import json  # noqa: E402
import os  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import time  # noqa: E402
import unittest  # noqa: E402
import urllib.request  # noqa: E402

from helpers import BUILD_HELP, HELP_DIR, Fixture, write_webp  # noqa: E402

NODE = shutil.which("node")

NODE_SEARCH = """
const fs = require("fs");
const vm = require("vm");
const sandbox = { window: {} };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);
const search = require(process.argv[3]);
const results = search.searchHelp(sandbox.window.PLANTOIR_HELP_INDEX, process.argv[4]);
const ids = [];
for (const result of results) { ids.push(result.id); }
console.log(JSON.stringify(ids));
"""


class WebTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()
        self.web = self.fixture.out / "web"

    def tearDown(self) -> None:
        self.fixture.close()

    def build(self, *extra: str) -> str:
        code, output = self.fixture.run("--web", str(self.web), *extra)
        self.assertEqual(code, 0, output)
        return output

    def read(self, name: str) -> str:
        return (self.web / name).read_text(encoding="utf-8")

    def test_the_assistant_section_is_left_out_while_the_switch_is_off(self) -> None:
        output = self.build()
        self.assertIn("web copy: 4 pages", output)
        self.assertFalse((self.web / "helper-page.html").exists())
        self.assertNotIn("helper-page", self.read("assets/search-index.js"))
        self.assertNotIn("zanzibarword", self.read("assets/search-index.js"))
        contents = self.read("index.html")
        self.assertNotIn("helper-page", contents)
        self.assertNotIn("Optional: with an assistant", contents)
        # The {{assistant}} run on an ordinary page is left out with it.
        self.assertNotIn("helper page", self.read("send-section.html"))
        self.assertNotIn('href="helper-page.html"', self.read("send-section.html"))
        self.assertNotIn("assistant", self.read("send-section.html"))

    def test_the_switch_puts_the_assistant_section_back(self) -> None:
        self.fixture.replace("help/facts.json", '"assistantOnTheWeb": false', '"assistantOnTheWeb": true')
        output = self.build()
        self.assertIn("web copy: 5 pages", output)
        self.assertTrue((self.web / "helper-page.html").exists())
        self.assertIn("Optional: with an assistant", self.read("index.html"))
        self.assertIn('href="helper-page.html"', self.read("send-section.html"))
        self.assertIn('<div data-assistant="true">', self.read("send-section.html"))

    def test_every_page_has_the_search_form_and_its_scripts(self) -> None:
        self.build()
        for name in ("index.html", "first-steps.html", "second-look.html"):
            text = self.read(name)
            self.assertIn('<form class="search" role="search" action="index.html" method="get">', text)
            self.assertIn('<html lang="en-CA">', text)
            # Only the contents page loads the index and searches.
            self.assertEqual('<script src="assets/search-index.js"></script>' in text, name == "index.html")
        self.assertIn("<label for=\"help-search\">Search Help</label>", self.read("first-steps.html"))
        self.assertNotIn("Planner's words", self.read("index.html"))
        for name in ("tokens.css", "help.css", "search.js", "search-index.js"):
            self.assertTrue((self.web / "assets" / name).exists(), name)
        self.assertTrue((self.web / "pictures" / "first-steps-2-light.webp").exists())

    def test_platform_runs_are_marked_for_the_site(self) -> None:
        self.build()
        self.assertIn('<div data-platform="mac" data-shared="true">', self.read("first-steps.html"))
        self.fixture.page("second-look", "{{mac}}\nOn a Mac.\n{{/mac}}\n\n{{windows}}\nOn Windows.\n{{/windows}}\n")
        self.build()
        text = self.read("second-look.html")
        self.assertIn('<div data-platform="mac">', text)
        self.assertNotIn('data-shared', text)
        self.assertIn('<div data-platform="windows">', text)
        # The hidden Windows run is not searchable.
        self.assertNotIn("On Windows", self.read("assets/search-index.js"))
        self.assertIn("On a Mac", self.read("assets/search-index.js"))

    def test_the_mac_book_keeps_only_the_mac_run(self) -> None:
        if shutil.which("hiutil") is None:
            self.skipTest("hiutil is not on this machine")
        self.fixture.page("second-look", "{{mac}}\nOn a Mac.\n{{/mac}}\n\n{{windows}}\nOn Windows.\n{{/windows}}\n")
        book = self.fixture.out / "Plantoir.help"
        code, output = self.fixture.run("--mac", str(book))
        self.assertEqual(code, 0, output)
        text = (book / "Contents" / "Resources" / "en.lproj" / "second-look.html").read_text(encoding="utf-8")
        self.assertIn("On a Mac.", text)
        self.assertNotIn("On Windows.", text)
        self.assertNotIn("data-platform", text)

    def test_the_mac_book_keeps_the_assistant_run(self) -> None:
        if shutil.which("hiutil") is None:
            self.skipTest("hiutil is not on this machine")
        book = self.fixture.out / "Plantoir.help"
        code, output = self.fixture.run("--mac", str(book))
        self.assertEqual(code, 0, output)
        text = (book / "Contents" / "Resources" / "en.lproj" / "send-section.html").read_text(encoding="utf-8")
        self.assertIn('<a href="helper-page.html">helper page</a>', text)

    def test_the_search_index_is_javascript_the_search_reads(self) -> None:
        if NODE is None:
            self.skipTest("node is not installed; the search index was not run")
        self.build()
        script = self.fixture.out / "search-test.js"
        script.write_text(NODE_SEARCH, encoding="utf-8")
        index = self.web / "assets" / "search-index.js"
        search = self.web / "assets" / "search.js"

        def search_for(query: str):
            completed = subprocess.run(
                [NODE, str(script), str(index), str(search), query],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout)
            return json.loads(completed.stdout)

        # marmaladeword is in the body of first-steps only: not its title, keywords or description.
        self.assertEqual(search_for("marmaladeword"), ["first-steps"])
        self.assertEqual(search_for("MARMALADEWORD item"), ["first-steps"])
        self.assertEqual(search_for("zanzibarword"), [])
        self.assertEqual(search_for(""), [])
        self.assertEqual(search_for("how do I"), [])
        # The interface words around a page are not searchable as the page's own.
        self.assertEqual(search_for("being written"), [])
        self.assertNotIn("Picture to come", self.read("assets/search-index.js"))
        # Pages need not hold every word; the one holding more ranks first.
        self.assertEqual(search_for("marmaladeword nothingelse"), ["first-steps"])
        # Token text is indexed: a shortcut, a control label, a contract sentence.
        self.assertEqual(search_for("⌘P"), ["first-steps"])
        self.assertEqual(search_for("Coverage tab")[0], "send-section")
        self.assertEqual(search_for("copied into the folder")[0], "first-steps")
        # Stems and a last word typed half way.
        self.assertEqual(search_for("deployed")[0], "send-section")
        self.assertEqual(search_for("deploying"), search_for("deploys"))
        self.assertEqual(search_for("marmaladew"), ["first-steps"])
        self.assertEqual(search_for("how do I deploy my site")[0], "send-section")

    def test_the_assistant_pages_are_found_once_the_switch_is_on(self) -> None:
        if NODE is None:
            self.skipTest("node is not installed; the search index was not run")
        self.fixture.replace("help/facts.json", '"assistantOnTheWeb": false', '"assistantOnTheWeb": true')
        self.build()
        script = self.fixture.out / "search-test.js"
        script.write_text(NODE_SEARCH, encoding="utf-8")
        completed = subprocess.run(
            [NODE, str(script), str(self.web / "assets" / "search-index.js"), str(self.web / "assets" / "search.js"), "GitHub Copilot"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
        )
        self.assertEqual(json.loads(completed.stdout)[0], "helper-page")

    def test_an_assistant_mention_on_an_ordinary_page_stops_the_web_copy(self) -> None:
        self.fixture.page("second-look", "Words.\n\nAsk Claude to revise it.\n")
        code, output = self.fixture.run("--web", str(self.web))
        self.assertNotEqual(code, 0, output)
        self.assertIn("FAILED: help/pages/second-look.md:10: on the web copy: names 'Claude'", output)
        self.assertFalse(self.web.exists())
        # Only a warning for the Mac book and --check, so the Xcode build is never failed by it.
        code, output = self.fixture.run("--check")
        self.assertEqual(code, 0, output)
        self.assertIn("warning: help/pages/second-look.md:10: on the web copy: names 'Claude'", output)
        # Inside an {{assistant}} run it passes, and the Mac book keeps it.
        self.fixture.page("second-look", "Words.\n\n{{assistant}}\nAsk Claude to revise it.\n{{/assistant}}\n")
        self.build()
        self.assertNotIn("Claude", self.read("second-look.html"))

    def test_a_link_to_an_assistant_page_outside_a_run_stops_the_web_copy(self) -> None:
        self.fixture.page("second-look", "Read [this page](page:helper-page).\n")
        code, output = self.fixture.run("--web", str(self.web))
        self.assertNotEqual(code, 0, output)
        self.assertIn("links to the assistant page helper-page outside an {{assistant}} run", output)

    def test_release_web_refuses_stubs_and_placeholders(self) -> None:
        code, output = self.fixture.run("--release-web", str(self.web))
        self.assertNotEqual(code, 0, output)
        self.assertIn("second-look is still a stub", output)
        self.assertIn("scene first-steps-1 is still a placeholder", output)
        self.assertFalse(self.web.exists())
        self.fixture.page("second-look", "Words.\n")
        self.fixture.replace("help/scenes.json", '"awaiting_capture": true', '"awaiting_capture": false')
        write_webp(self.fixture.help_dir / "pictures" / "first-steps-1-light.webp", 800, 600)
        write_webp(self.fixture.help_dir / "pictures" / "first-steps-1-dark.webp", 800, 600)
        code, output = self.fixture.run("--release-web", str(self.web))
        self.assertEqual(code, 0, output)
        self.assertIn('width="400" height="300"', self.read("first-steps.html"))

    def test_serve_prints_an_address_and_serves_the_copy(self) -> None:
        self.build()
        environment = dict(os.environ)
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        server = subprocess.Popen(
            [sys.executable, "-I", "-B", str(BUILD_HELP), "--serve", str(self.web)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True, env=environment,
        )
        try:
            line = server.stdout.readline()
            self.assertTrue(line.startswith("Serving Plantoir Help at http://127.0.0.1:"), line)
            address = line.split(" at ", 1)[1].split(" ", 1)[0]
            for attempt in range(20):
                try:
                    with urllib.request.urlopen(address + "first-steps.html", timeout=5) as response:
                        body = response.read().decode("utf-8")
                    break
                except OSError:
                    time.sleep(0.1)
            self.assertIn("<h1>Take the first steps</h1>", body)
        finally:
            server.terminate()
            server.wait(timeout=10)
            server.stdout.close()


class AssetTests(unittest.TestCase):
    def test_the_tokens_hold_both_palettes(self) -> None:
        text = (HELP_DIR / "assets" / "tokens.css").read_text(encoding="utf-8")
        for value in ("#FCFDFB", "#F1F5EF", "#FFFFFF", "#D9E2D6", "#1E2721", "#566259", "#1F7A3A", "#0F4A27", "#7FB069", "#9CC788", "#d0312d"):
            self.assertIn(value, text)
        self.assertIn("@media (prefers-color-scheme: dark)", text)
        self.assertIn('"Helvetica Neue", Helvetica, Arial, sans-serif', text)
        self.assertNotIn("@import", text)
        self.assertNotIn("url(", text)

    def test_the_layout_never_loads_from_the_web(self) -> None:
        text = (HELP_DIR / "assets" / "help.css").read_text(encoding="utf-8")
        self.assertNotIn("http", text)
        self.assertIn("@media print", text)


if __name__ == "__main__":
    unittest.main()

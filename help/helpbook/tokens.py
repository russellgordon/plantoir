"""Tokens: the names a page uses instead of typing what the app shows.

Each token is resolved at build time against the thing it names, so a menu
item that is renamed, a label that changes or a contract sentence that moves
fails the build instead of leaving Help wrong:

- `{{menu:<id>}}`    help/menu-paths.json; the Mac path must be a path in
                     mac-app/Tests/Goldens/menu-bar.txt, or, for an entry
                     marked "system", a path in help/system-menus.json;
- `{{control:<id>}}` help/controls.json; the label must be a Swift string
                     literal in the named file, the literal of a named
                     `static let`/`var`, or a contract sentence;
- `{{say:<file>#<key path>}}` a sentence from contracts/<file>.json;
- `{{fact:<id>}}`    help/facts.json;
- `{{key:<id>}}`     a shortcut: a menu id's key from the golden, or
                     help/controls.json -> keys;
- `{{count:<name>}}` a number counted from support/ (counts.py).
"""

from __future__ import annotations

import datetime
import html
import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

from . import FACT_AGE_LIMIT_DAYS
from .counts import site_counts
from .problems import HelpError, Problems

MENU_SEPARATOR = " ▸ "
GOLDEN_PATH = Path("mac-app") / "Tests" / "Goldens" / "menu-bar.txt"
SWIFT_SOURCES = Path("mac-app") / "QuartzTeachers"


def read_json(path: Path) -> Any:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except OSError as error:
        raise HelpError("cannot read " + str(path) + ": " + str(error))
    except ValueError as error:
        raise HelpError(str(path) + " is not valid JSON: " + str(error))


# MARK: the menu golden

def parse_menu_golden(text: str) -> Dict[Tuple[str, ...], Optional[str]]:
    """Every path in the golden, mapped to its key equivalent (or None).

    `== <Menu>` opens a menu; two spaces of indent per level; tags after two
    or more spaces: `[⇧⌘N]` a key, `[if …]` a condition, `(alternate)`;
    `----` is a divider; `#` lines and the `menus:` line are comments.
    """
    paths: Dict[Tuple[str, ...], Optional[str]] = {}
    menu: str = ""
    stack: List[str] = []
    for raw in text.split("\n"):
        line: str = raw.rstrip()
        if line.strip() == "" or line.startswith("#") or line.startswith("menus:"):
            continue
        if line.startswith("== "):
            menu = line[3:].strip()
            stack = []
            paths[(menu,)] = None
            continue
        if menu == "":
            continue
        indent: int = len(line) - len(line.lstrip(" "))
        depth: int = indent // 2
        parts: List[str] = re.split(r"\s{2,}", line.strip())
        title: str = parts[0]
        if title == "----":
            continue
        key: Optional[str] = None
        for part in parts[1:]:
            if part.startswith("[if ") or part == "(alternate)":
                continue
            if part.startswith("[") and part.endswith("]"):
                key = part[1:-1]
        while len(stack) >= depth:
            stack.pop()
        stack.append(title)
        paths[tuple([menu] + stack)] = key
    return paths


# MARK: Swift and contract lookups

def swift_literal(label: str) -> str:
    return '"' + label.replace("\\", "\\\\").replace('"', '\\"') + '"'


def unescape_swift(literal: str) -> str:
    return literal.replace('\\"', '"').replace("\\\\", "\\")


def resolve_key_path(document: Any, key_path: str) -> Any:
    """`a.b[2].c` into a JSON document; raises KeyError when it does not resolve."""
    value: Any = document
    for part in re.findall(r"[^.\[\]]+|\[\d+\]", key_path):
        if part.startswith("["):
            index: int = int(part[1:-1])
            if not isinstance(value, list) or index >= len(value):
                raise KeyError(part)
            value = value[index]
        else:
            if not isinstance(value, dict) or part not in value:
                raise KeyError(part)
            value = value[part]
    return value


class Registries:
    """help/'s registries and the repository files the tokens are checked against."""

    def __init__(self, repo: Path, help_dir: Path, today: datetime.date) -> None:
        self.repo = repo
        self.help_dir = help_dir
        self.today = today
        self.menus: Dict[str, Any] = read_json(help_dir / "menu-paths.json").get("entries", {})
        self.system_menus: List[Dict[str, Any]] = read_json(help_dir / "system-menus.json").get("paths", [])
        controls_file = read_json(help_dir / "controls.json")
        self.controls: Dict[str, Any] = controls_file.get("entries", {})
        self.keys: Dict[str, Any] = controls_file.get("keys", {})
        facts_file = read_json(help_dir / "facts.json")
        self.facts: Dict[str, Any] = facts_file.get("facts", {})
        self.assistant_on_the_web: bool = facts_file.get("assistantOnTheWeb", False) is True
        self.scenes: Dict[str, Any] = read_json(help_dir / "scenes.json").get("scenes", {})
        golden_file: Path = repo / GOLDEN_PATH
        try:
            self.golden: Dict[Tuple[str, ...], Optional[str]] = parse_menu_golden(golden_file.read_text(encoding="utf-8"))
        except OSError as error:
            raise HelpError("cannot read the menu golden " + str(golden_file) + ": " + str(error))
        self.counts: Dict[str, str] = site_counts(repo / "support")
        self._contracts: Dict[str, Any] = {}
        self._swift_texts: Optional[List[Tuple[Path, str]]] = None
        self.used: Dict[str, Set[str]] = {"menu": set(), "control": set(), "fact": set(), "key": set(), "scene": set()}

    # MARK: checking the registries themselves

    def menu_path_problem(self, entry: Dict[str, Any]) -> Optional[str]:
        """Why an entry's Mac path is not a real menu path, or None."""
        path_text: Any = entry.get("mac")
        if not isinstance(path_text, str) or path_text.strip() == "":
            return "has no Mac path"
        if entry.get("system") is True:
            for item in self.system_menus:
                if item.get("path") == path_text:
                    return None
            return "is marked system but " + repr(path_text) + " is not in help/system-menus.json"
        parts: Tuple[str, ...] = tuple(path_text.split(MENU_SEPARATOR))
        if parts not in self.golden:
            return repr(path_text) + " is not a path in " + str(GOLDEN_PATH)
        return None

    def menu_key(self, entry: Dict[str, Any]) -> Optional[str]:
        path_text: str = entry.get("mac", "")
        if entry.get("system") is True:
            for item in self.system_menus:
                if item.get("path") == path_text:
                    return item.get("key")
            return None
        return self.golden.get(tuple(path_text.split(MENU_SEPARATOR)))

    def contract_value(self, reference: str) -> Any:
        if "#" not in reference:
            raise KeyError("a say token is <contract file>#<key path>")
        file_name, key_path = reference.split("#", 1)
        if not file_name.endswith(".json"):
            file_name = file_name + ".json"
        if "/" in file_name or "\\" in file_name:
            raise KeyError("names a contract file by its name only")
        if file_name not in self._contracts:
            path: Path = self.repo / "contracts" / file_name
            if not path.exists():
                raise KeyError("there is no contracts/" + file_name)
            self._contracts[file_name] = read_json(path)
        return resolve_key_path(self._contracts[file_name], key_path)

    def swift_texts(self) -> List[Tuple[Path, str]]:
        if self._swift_texts is None:
            texts: List[Tuple[Path, str]] = []
            root: Path = self.repo / SWIFT_SOURCES
            for path in sorted(root.rglob("*.swift")):
                texts.append((path, path.read_text(encoding="utf-8")))
            self._swift_texts = texts
        return self._swift_texts

    def control_problem(self, entry: Dict[str, Any]) -> Optional[str]:
        label: Any = entry.get("label")
        if not isinstance(label, str) or label == "":
            return "has no label"
        mac: Any = entry.get("mac")
        if not isinstance(mac, dict) or len(mac) != 1:
            return "names one Mac source: {\"file\": …}, {\"wording\": \"Type.member\"} or {\"say\": \"file#key\"}"
        if "file" in mac:
            path = self.repo / str(mac["file"])
            if not path.exists():
                return "names " + str(mac["file"]) + ", which does not exist"
            if swift_literal(label) not in path.read_text(encoding="utf-8"):
                return "label " + repr(label) + " is not a string literal in " + str(mac["file"])
            return None
        if "wording" in mac:
            name: str = str(mac["wording"])
            if name.count(".") != 1:
                return "wording is written Type.member"
            type_name, member = name.split(".")
            declares_type = re.compile(r"\b(?:enum|struct|class|extension)\s+" + re.escape(type_name) + r"\b")
            member_literal = re.compile(
                r"\bstatic\s+(?:let|var)\s+" + re.escape(member) + r"\b(?:\s*:\s*[A-Za-z.]+)?\s*=\s*\"((?:[^\"\\]|\\.)*)\""
            )
            for path, text in self.swift_texts():
                if declares_type.search(text) is None:
                    continue
                for found in member_literal.finditer(text):
                    if unescape_swift(found.group(1)) == label:
                        return None
            return "no `static let " + member + "` in " + type_name + " under " + str(SWIFT_SOURCES) + " reads " + repr(label)
        if "say" in mac:
            try:
                value = self.contract_value(str(mac["say"]))
            except KeyError as error:
                return "say " + repr(mac["say"]) + " does not resolve (" + str(error) + ")"
            if value != label:
                return "say " + repr(mac["say"]) + " reads " + repr(value) + ", not " + repr(label)
            return None
        return "names an unknown kind of Mac source"

    def check_registries(self, problems: Problems) -> None:
        for menu_id in sorted(self.menus):
            problem = self.menu_path_problem(self.menus[menu_id])
            if problem is not None:
                problems.fail("help/menu-paths.json", None, menu_id + " " + problem)
        for item in self.system_menus:
            source: str = str(item.get("source", ""))
            if source == "" or not (self.repo / source).exists():
                problems.fail("help/system-menus.json", None, repr(item.get("path")) + " needs a source file that exists")
        for control_id in sorted(self.controls):
            problem = self.control_problem(self.controls[control_id])
            if problem is not None:
                problems.fail("help/controls.json", None, control_id + " " + problem)
        for key_id in sorted(self.keys):
            if not isinstance(self.keys[key_id].get("mac"), str):
                problems.fail("help/controls.json", None, "keys -> " + key_id + " has no Mac shortcut")
        for fact_id in sorted(self.facts):
            fact = self.facts[fact_id]
            if "value" not in fact or "read" not in fact or "source" not in fact:
                problems.fail("help/facts.json", None, fact_id + " carries value, read and source")
                continue
            try:
                read_on = datetime.date.fromisoformat(str(fact["read"]))
            except ValueError:
                problems.fail("help/facts.json", None, fact_id + " read is a date written YYYY-MM-DD")
                continue
            if (self.today - read_on).days > FACT_AGE_LIMIT_DAYS:
                problems.warn(
                    "help/facts.json", None,
                    fact_id + " was read on " + str(read_on) + ", more than " + str(FACT_AGE_LIMIT_DAYS) + " days ago",
                )

    def report_unused(self, problems: Problems) -> None:
        """Unused ids are WARNINGS (plan review H2): an integrator commits the
        registry entries before the pages that use them. F's --release refuses them."""
        families: List[Tuple[str, str, List[str]]] = [
            ("menu", "help/menu-paths.json", sorted(self.menus)),
            ("control", "help/controls.json", sorted(self.controls)),
            ("key", "help/controls.json -> keys", sorted(self.keys)),
            ("fact", "help/facts.json", sorted(self.facts)),
            ("scene", "help/scenes.json", sorted(self.scenes)),
        ]
        for family, file, ids in families:
            for registry_id in ids:
                if registry_id not in self.used[family]:
                    problems.warn(file, None, registry_id + " is used by no page")

    # MARK: rendering inline tokens

    def render_inline(self, token: str, platform: str, file: str, line: int, problems: Problems) -> str:
        """The HTML for one inline token; a failure renders as nothing."""
        if ":" not in token:
            problems.fail(file, line, "unknown token `{{" + token + "}}`")
            return ""
        kind, argument = token.split(":", 1)
        argument = argument.strip()
        if kind == "menu":
            entry = self.menus.get(argument)
            if entry is None:
                problems.fail(file, line, "{{menu:" + argument + "}}: no such id in help/menu-paths.json")
                return ""
            self.used["menu"].add(argument)
            path_text: Any = entry.get(platform)
            if not isinstance(path_text, str):
                problems.fail(file, line, "{{menu:" + argument + "}} has no " + platform + " path yet")
                return ""
            return '<b class="menu">' + html.escape(path_text) + "</b>"
        if kind == "control":
            entry = self.controls.get(argument)
            if entry is None:
                problems.fail(file, line, "{{control:" + argument + "}}: no such id in help/controls.json")
                return ""
            self.used["control"].add(argument)
            label: str = str(entry.get("label", ""))
            if platform == "windows":
                windows_entry: Any = entry.get("windows")
                if not isinstance(windows_entry, dict) or "label" not in windows_entry:
                    problems.fail(file, line, "{{control:" + argument + "}} has no Windows label yet")
                    return ""
                label = str(windows_entry["label"])
            return '<b class="control">' + html.escape(label) + "</b>"
        if kind == "say":
            try:
                value = self.contract_value(argument)
            except KeyError as error:
                problems.fail(file, line, "{{say:" + argument + "}} does not resolve (" + str(error) + ")")
                return ""
            if not isinstance(value, str):
                problems.fail(file, line, "{{say:" + argument + "}} names a " + type(value).__name__ + ", not a sentence")
                return ""
            return '<span class="say">' + html.escape(value) + "</span>"
        if kind == "fact":
            fact = self.facts.get(argument)
            if fact is None:
                problems.fail(file, line, "{{fact:" + argument + "}}: no such id in help/facts.json")
                return ""
            self.used["fact"].add(argument)
            return html.escape(str(fact.get("value", "")))
        if kind == "key":
            shortcut: Optional[str] = None
            if argument in self.menus:
                self.used["menu"].add(argument)
                if platform == "mac":
                    shortcut = self.menu_key(self.menus[argument])
                else:
                    shortcut = self.menus[argument].get("windowsKey")
            elif argument in self.keys:
                self.used["key"].add(argument)
                shortcut = self.keys[argument].get(platform)
            else:
                problems.fail(file, line, "{{key:" + argument + "}}: no menu id or keys entry by that name")
                return ""
            if not isinstance(shortcut, str) or shortcut == "":
                problems.fail(file, line, "{{key:" + argument + "}} has no " + platform + " shortcut")
                return ""
            return "<kbd>" + html.escape(shortcut) + "</kbd>"
        if kind == "count":
            if argument not in self.counts:
                problems.fail(file, line, "{{count:" + argument + "}}: the counts are " + ", ".join(sorted(self.counts)))
                return ""
            return html.escape(self.counts[argument])
        problems.fail(file, line, "unknown token `{{" + token + "}}`")
        return ""

"""Runnable Python in an example-content payload (#455, #561).

Usage:  python3 .claude/skills/example-content/lint_runnable.py ICS3U

Runs under Python 3.9 or later (macOS's own /usr/bin/python3 is 3.9). It is
run BY HAND - alone, or through lint_payload.py in the example-content
skill's Phase 7; no automated gate runs either script.

Two jobs, both read the page the way the site does (the toolchain's own
`scripts/markdown_code.fenced_blocks` and `scripts/page_features.runner_for`):

1. RULES every payload must keep (`lint_payload.py` runs them on every page):
   (1) a runnable block (any language in page_features.RUNNER_LANGUAGES) on a
       page without `codeRunner: true`;
   (2) `codeRunner: true` (or any other codeRunner value) with no run block.
       A ```<language> run block in a language these rules do not judge
       (```swift run, before #493 adds its row) counts as a run block and is
       otherwise left alone - never refused;
   (3) a block that LOOKS runnable but is not - ```Python run, ```py run,
       `run,stdin`, a run block nested after two list markers - or an unknown
       or repeated flag, or more than one `autorun` on a page;
   (4) a run block that does not parse, or uses a name bound nowhere in the
       block (a fragment: NameError the moment it runs). "Nowhere" is
       deliberate: a name bound inside a function and printed outside it -
       a lesson about scope - passes, and so, a known limit, does a name
       used before the line that first binds it;
   (5) a run block that opens a file for reading - `open(...)`,
       `open(file=...)`, `Path(...).read_text()` / `.read_bytes()` - which
       it never writes earlier in the same block, unless the read sits in a
       `try` that catches FileNotFoundError / OSError (each Run starts in a
       fresh, empty folder). A file name may be a literal, a module-level
       constant (`FILE_NAME = "reminders.txt"`) or the same variable the
       write used (a name the user typed);
   plus: an import outside the standard library (or one the site cannot
   run - turtle, tkinter ...), `breakpoint()`, and `sys.stdin` without the
   `stdin` flag, `from sys import stdin` included (the input box appears by
   itself only for `input(`). `notes = Path("w.txt")` then `notes.read_text()`
   is read as a read of w.txt.

2. The JUDGEMENT TABLE for a payload that has one (ICS3U): every Python block
   on every page, top to bottom, is `run`, `readonly`, or plain with the
   reason it stays plain. The payload must match it exactly, so a block
   added, removed or re-flagged later is a decision somebody has to write
   down here, not an accident.

Exit code 0 means clean; 1 means problems were printed; 2 means the rules'
own self-check failed.
"""

import ast
import builtins
import importlib.util
import re
import sys
import sysconfig
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
import markdown_code  # noqa: E402
import page_features  # noqa: E402

# What the site's Python cannot import although it is part of Python
# (support/agent_guidance/skills/plantoir-runnable-code, "Does not work").
CANNOT_IMPORT = {"turtle", "tkinter", "_tkinter", "turtledemo", "idlelib",
                 "curses", "readline", "venv", "ensurepip", "pip"}
# Exceptions that make a missing file a handled case rather than a crash.
CATCHES_A_MISSING_FILE = {"FileNotFoundError", "OSError", "IOError",
                          "EnvironmentError", "Exception", "BaseException"}
# Names every program has without defining them.
ALWAYS_BOUND = set(dir(builtins))

PYTHON_WORDS = {"python", "py", "python3", "py3"}

# Match statements arrived in Python 3.10; on 3.9 there are none to read.
MATCH_CAPTURES = tuple(getattr(ast, name) for name in ("MatchAs", "MatchStar") if hasattr(ast, name))
MATCH_MAPPING = getattr(ast, "MatchMapping", None)


def is_standard_library(module: str) -> bool:
    """Is `module` part of Python itself? sys.stdlib_module_names on 3.10+;
    on 3.9, where the module is found: built in, or under the standard
    library folder and not in site-packages."""
    names = getattr(sys, "stdlib_module_names", None)
    if names is not None:
        return module in names
    if module in sys.builtin_module_names:
        return True
    try:
        spec = importlib.util.find_spec(module)
    except (ImportError, ValueError):
        return False
    if spec is None:
        return False
    origin = spec.origin or ""
    if origin in ("built-in", "frozen"):
        return True
    stdlib = sysconfig.get_paths()["stdlib"]
    return origin.startswith(stdlib) and "site-packages" not in origin


# ---------------------------------------------------------------------------
# Reading a page
# ---------------------------------------------------------------------------

def frontmatter_lines(text: str) -> list:
    """The settings block's lines (between the opening and closing ---)."""
    if not text.startswith("---\n"):
        return []
    end = text.find("\n---", 4)
    if end < 0:
        return []
    return text[4:end].split("\n")


def code_runner_value(text: str):
    """The codeRunner line's value as written, or None when there is none."""
    for line in frontmatter_lines(text):
        match = re.match(r"^codeRunner:(.*)$", line)
        if match:
            return match.group(1).strip()
    return None


def python_blocks(text: str) -> list:
    """Every fenced block whose language word is Python-ish, in order, with
    whether the site makes it runnable (on a page that opts in)."""
    found = []
    for block in markdown_code.fenced_blocks(text):
        words = [word for word in page_features.INFO_SPACE.split(block["info"]) if word]
        if not words or words[0].lower() not in PYTHON_WORDS:
            continue
        runner = None if block["nested"] else page_features.runner_for(block["info"], "", True)
        found.append({
            "line": block["line"],
            "info": block["info"],
            "words": words,
            "body": block["body"],
            "nested": block["nested"],
            "runner": runner,
        })
    return found


def judgement_of(block: dict) -> str:
    """'run', 'readonly' or 'plain', as the site would treat the block."""
    if block["runner"] is None:
        return "plain"
    if "readonly" in block["runner"]["flags"]:
        return "readonly"
    return "run"


# ---------------------------------------------------------------------------
# Rule (3): the info string
# ---------------------------------------------------------------------------

def info_string_problems(block: dict) -> list:
    problems = []
    words = block["words"]
    # A title="..." may hold spaces; what is inside quotes is not a flag.
    unquoted = re.sub(r'"[^"]*"|\'[^\']*\'', "", block["info"])
    tokens = [word for word in page_features.INFO_SPACE.split(unquoted) if word][1:]
    says_run = False
    for token in tokens:
        if token == "run" or re.match(r"^run\W|\Wrun$", token):
            says_run = True
    if not says_run:
        return problems
    if block["runner"] is None:
        if words[0] != "python":
            problems.append(f"```{words[0]} run is not runnable - the language word is "
                            f"exactly `python`, lowercase")
        elif block["nested"]:
            problems.append("a run block opened after two list markers (or a list marker "
                            "and a >) stays plain code - put the fence on its own line")
        else:
            problems.append("`run` must be its own word (not `run,stdin` or `run.py`)")
        return problems
    allowed = set(page_features.RUNNER_LANGUAGES["python"]["flags"]) | {"run"}
    seen = set()
    for token in tokens:
        if "=" in token or token.startswith("{"):
            continue
        if token not in allowed:
            problems.append(f"unknown flag `{token}` - the flags are readonly, stdin and "
                            f"autorun, lowercase")
        elif token in seen:
            problems.append(f"`{token}` written twice")
        seen.add(token)
    return problems


# ---------------------------------------------------------------------------
# Rules (4) and (5) and the imports: the program itself
# ---------------------------------------------------------------------------

def bound_names(tree) -> set:
    """Every name the block binds anywhere: assignment, for, with, def,
    class, parameters, imports, except ... as, match captures, walrus."""
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and not isinstance(node.ctx, ast.Load):
            names.add(node.id)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, ast.arg):
            names.add(node.arg)
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            for alias in node.names:
                names.add(alias.asname or alias.name.split(".")[0])
        elif isinstance(node, ast.ExceptHandler) and node.name:
            names.add(node.name)
        elif MATCH_CAPTURES and isinstance(node, MATCH_CAPTURES) and node.name:
            names.add(node.name)
        elif MATCH_MAPPING is not None and isinstance(node, MATCH_MAPPING) and node.rest:
            names.add(node.rest)
    return names


def module_string_constants(tree) -> dict:
    """NAME -> "text" for each module-level `NAME = "text"` assigned once."""
    seen = {}
    for statement in tree.body:
        if isinstance(statement, ast.Assign) and len(statement.targets) == 1 \
                and isinstance(statement.targets[0], ast.Name):
            name = statement.targets[0].id
            value = statement.value
            if isinstance(value, ast.Constant) and isinstance(value.value, str) and name not in seen:
                seen[name] = value.value
            else:
                seen[name] = None
    constants = {}
    for name, value in seen.items():
        if value is not None:
            constants[name] = value
    return constants


def file_name_of(node, constants):
    """What names the file: its text when it can be known, otherwise the
    expression itself, so `open(name, "w")` then `open(name)` match."""
    if node is None:
        return None
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name) and node.id in constants:
        return constants[node.id]
    return ("expression", ast.dump(node))


def shown_name(name) -> str:
    if isinstance(name, str):
        return name
    return "a file"


def mode_of(call) -> str:
    mode = None
    if len(call.args) >= 2:
        mode = call.args[1]
    for keyword in call.keywords:
        if keyword.arg == "mode":
            mode = keyword.value
    if mode is None:
        return "r"
    if isinstance(mode, ast.Constant) and isinstance(mode.value, str):
        return mode.value
    return "?"


def guarded_against_a_missing_file(node, parents) -> bool:
    """Is `node` inside the body of a try whose handlers catch a missing file?"""
    child = node
    parent = parents.get(id(child))
    while parent is not None:
        if isinstance(parent, ast.Try) and child in parent.body:
            for handler in parent.handlers:
                if handler.type is None:
                    return True
                caught = handler.type.elts if isinstance(handler.type, ast.Tuple) else [handler.type]
                for exception in caught:
                    if isinstance(exception, ast.Name) and exception.id in CATCHES_A_MISSING_FILE:
                        return True
        child = parent
        parent = parents.get(id(child))
    return False


def is_path_call(node) -> bool:
    """Is `node` a call of Path(...) (or pathlib.Path(...)) with an argument?"""
    if not isinstance(node, ast.Call) or not node.args:
        return False
    function = node.func
    return (isinstance(function, ast.Name) and function.id == "Path") \
        or (isinstance(function, ast.Attribute) and function.attr == "Path")


def path_variables(tree, constants) -> dict:
    """NAME -> file for each `NAME = Path(...)` in the block."""
    paths = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name) and is_path_call(node.value):
            paths[node.targets[0].id] = file_name_of(node.value.args[0], constants)
    return paths


def file_accesses(tree, constants) -> list:
    """Every file the block opens, in source order: (call, name, writes)."""
    found = []
    paths = path_variables(tree, constants)
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        function = node.func
        if isinstance(function, ast.Name) and function.id == "open":
            target = node.args[0] if node.args else None
            for keyword in node.keywords:
                if keyword.arg == "file":
                    target = keyword.value
            if target is None:
                continue
            mode = mode_of(node)
            found.append((node, file_name_of(target, constants), any(letter in mode for letter in "wax")))
        elif isinstance(function, ast.Attribute) \
                and function.attr in ("read_text", "read_bytes", "write_text", "write_bytes"):
            name = None
            if is_path_call(function.value):
                name = file_name_of(function.value.args[0], constants)
            elif isinstance(function.value, ast.Name) and function.value.id in paths:
                name = paths[function.value.id]
            if name is not None:
                found.append((node, name, function.attr.startswith("write")))
    found.sort(key=lambda access: (access[0].lineno, access[0].col_offset))
    return found


def reads_sys_stdin(tree) -> bool:
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "sys":
            for alias in node.names:
                if alias.name == "stdin":
                    return True
        if isinstance(node, ast.Attribute) and node.attr == "stdin" \
                and isinstance(node.value, ast.Name) and node.value.id == "sys":
            return True
    return False


def program_problems(source: str, flags=()) -> list:
    """What would go wrong the moment a student presses Run."""
    try:
        tree = ast.parse(source)
    except SyntaxError as error:
        return [f"does not parse on its own (line {error.lineno}: {error.msg}) - "
                f"a fragment belongs in a plain ```python block"]
    problems = []

    bound = bound_names(tree)
    missing = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load) \
                and node.id not in bound and node.id not in ALWAYS_BOUND:
            missing.add(node.id)
    if missing:
        problems.append(f"uses {', '.join(sorted(missing))}, defined nowhere in the block "
                        f"(NameError when it runs) - a fragment belongs in a plain ```python block")

    for node in ast.walk(tree):
        modules = []
        if isinstance(node, ast.Import):
            for alias in node.names:
                modules.append(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            modules.append(node.module.split(".")[0])
        for module in modules:
            if module in CANNOT_IMPORT:
                problems.append(f"imports {module}, which the site's Python cannot run")
            elif not is_standard_library(module):
                problems.append(f"imports {module}, which is not part of Python's standard "
                                f"library (or is another file) - only the standard library runs on the site")
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "breakpoint":
            problems.append("calls breakpoint() - there is no debugger on the site")

    # Rule (5): reads before writes, in source order.
    parents = {}
    for parent in ast.walk(tree):
        for child in ast.iter_child_nodes(parent):
            parents[id(child)] = parent
    constants = module_string_constants(tree)
    written = set()
    for call, name, writes in file_accesses(tree, constants):
        if writes:
            written.add(name)
            continue
        if name in written or guarded_against_a_missing_file(call, parents):
            continue
        problems.append(f"reads {shown_name(name)} without writing it first - each Run starts in an "
                        f"empty folder, so this is FileNotFoundError (catch it, or keep the block plain)")

    if "stdin" not in flags and reads_sys_stdin(tree):
        problems.append("reads sys.stdin without the `stdin` flag - the input box appears by "
                        "itself only for input(); write ```python run stdin")
    return problems


# ---------------------------------------------------------------------------
# One page
# ---------------------------------------------------------------------------

def page_problems(rel: str, text: str) -> list:
    """Rules (1)-(5) on one page."""
    problems = []
    value = code_runner_value(text)
    if value is not None and value != "true":
        problems.append(f"{rel}: codeRunner: {value} - write exactly `codeRunner: true` "
                        f"(the site reads only the word true)")
    opted_in = value == "true"
    blocks = python_blocks(text)
    runnable = 0
    autoruns = 0
    # Run blocks in a language these rules do not judge (```swift run): they
    # count as run blocks for rule (2) and are otherwise left alone.
    for block in markdown_code.fenced_blocks(text):
        words = [word for word in page_features.INFO_SPACE.split(block["info"]) if word]
        if words and words[0].lower() not in PYTHON_WORDS and "run" in words[1:]:
            runnable += 1
            if not opted_in and page_features.runner_for(block["info"], "", True) is not None \
                    and not block["nested"]:
                problems.append(f"{rel}:{block['line']}: a run block on a page without "
                                f"`codeRunner: true` - it shows as ordinary code")
    for block in blocks:
        where = f"{rel}:{block['line']}"
        for problem in info_string_problems(block):
            problems.append(f"{where}: {problem}")
        if block["runner"] is None:
            continue
        runnable += 1
        if "autorun" in block["runner"]["flags"]:
            autoruns += 1
        if not opted_in:
            problems.append(f"{where}: a run block on a page without `codeRunner: true` - "
                            f"it shows as ordinary code")
        for problem in program_problems(block["body"], block["runner"]["flags"]):
            problems.append(f"{where}: {problem}")
    if value is not None and runnable == 0:
        problems.append(f"{rel}: codeRunner is set but no block says ```<language> run - "
                        f"take the line out")
    if autoruns > 1:
        problems.append(f"{rel}: {autoruns} autorun blocks - at most one per page")
    return problems


# ---------------------------------------------------------------------------
# The judgement tables
# ---------------------------------------------------------------------------

# Why a block stays plain. Each Run starts with fresh variables in an empty
# folder, so a block that leans on the text around it cannot run alone.
UNDEFINED = "plain: uses names it never defines"
NO_PARSE = "plain: does not parse alone"
NO_OUTPUT = "plain: shows nothing when run"
DEFINITION = "plain: a definition only, shows nothing"
MISSING_FILE = "plain: reads a file no earlier block can leave behind"
ONE_INPUT = "plain: one input line, shows nothing"
RHETORICAL = "plain: a one-line print shown for its wording"
FIND_THE_FAULT = "plain: a find-the-fault question - running it gives the answer away"

# ICS3U (#561): pages under shared/, every ```python block top to bottom.
# Concepts and Programs are worked examples to read - readonly; everything
# else is the students' to edit. Two runs END IN AN ERROR ON PURPOSE and are
# allow-listed in ENDS_IN_AN_ERROR below.
TABLES = {
    "ICS3U": {
        "Concepts/Boolean Logic": [UNDEFINED, "readonly", "readonly", NO_PARSE],
        "Concepts/Decomposition and Design": [UNDEFINED],
        "Concepts/Files and Persistence": [
            "plain: writes a file, shows nothing", MISSING_FILE,
            "plain: a fragment of a longer program (prints only the no-file message)"],
        "Concepts/Formulas as Algorithms": ["readonly"],
        "Concepts/Functions": [DEFINITION, UNDEFINED, DEFINITION],
        "Concepts/Input and Output": [ONE_INPUT, "readonly", ONE_INPUT, ONE_INPUT,
                                      "readonly", "readonly"],
        "Concepts/Inside the Machine": [UNDEFINED],
        "Concepts/Lists": [NO_OUTPUT, UNDEFINED, UNDEFINED, "readonly", UNDEFINED,
                           "readonly", UNDEFINED],
        "Concepts/Making Decisions": [UNDEFINED, "readonly", UNDEFINED, UNDEFINED],
        "Concepts/Parameters, Returns, and Scope": [DEFINITION, UNDEFINED, "readonly", "readonly"],
        # 3 is the loop that never ends: editable, so students can fix it; the
        # prose says the page stops it for printing too much (measured).
        "Concepts/Repetition": ["readonly", "plain: an input loop that shows nothing",
                                "run", "readonly", "readonly"],
        # Editable, although a Concepts page: the prose asks students to move a
        # line and run it again.
        "Concepts/Testing and Debugging": ["run"],
        "Concepts/Variables and Data Types": [NO_OUTPUT, NO_OUTPUT, NO_OUTPUT, NO_OUTPUT],
        "Concepts/Working with Text": ["readonly", "readonly",
                                       "plain: two lines whose TypeError the page prints beside them"],
        "Discussions/Who Is This For": [RHETORICAL, RHETORICAL],
        "Exercises/Boolean Logic Practice": [UNDEFINED, "run", UNDEFINED, "run", NO_PARSE,
                                             UNDEFINED, UNDEFINED],
        "Exercises/Decisions Practice": [UNDEFINED, "run", NO_PARSE, UNDEFINED, "run", UNDEFINED],
        "Exercises/Files Practice": ["plain: writes a file, shows nothing", MISSING_FILE,
                                     "run", "run", MISSING_FILE, MISSING_FILE],
        "Exercises/Formula Practice": ["run", "run", "run", "run", "run"],
        "Exercises/Functions Practice": ["run", "run", "run", UNDEFINED, "run", "run", "run",
                                         "run", "run"],
        "Exercises/Lists Practice": [NO_OUTPUT, UNDEFINED, "run", "run", UNDEFINED, UNDEFINED],
        "Exercises/Loops Practice": ["run", "run", "run", "run", "run", "run", "run", "run", "run"],
        "Exercises/Text Practice": [FIND_THE_FAULT, "run", "run", "run", "run", "run", "run"],
        "Exercises/Variables and Types Practice": ["run", "run", FIND_THE_FAULT, "run",
                                                   "plain: reads input, shows nothing", "run", "run"],
        "Explorations/The Bad Input Hunt": ["run"],
        "Explorations/The Data Pile": ["run"],
        "Explorations/The Hundred-Line Problem": ["run"],
        "Explorations/The Repeated Chunk": ["run"],
        "Programs/Branching Programs": ["readonly"],
        "Programs/Looping Programs": ["readonly"],
        "Programs/Reading and Writing Files": ["readonly"],
        "Programs/Talking to the User": ["readonly"],
        "Programs/Working with Lists": ["readonly"],
        "Programs/Writing Functions": ["readonly"],
        "Programs/Your First Python Program": ["readonly"],
        "Style/What This Site Can Do": ["run"],
        "Tasks/The Data Digest": ["run"],
        "Tasks/The Helper Script": ["run"],
        "Tasks/The Toolbox": ["plain: a definition that reads a file",
                              "plain: imports another file (toolbox.py)"],
        "Tutorials/Reading an Error Message": ["run"],
        "Tutorials/Reading the Documentation": ["run"],
        "Tutorials/Setting Up Python": ["run"],
        "Tutorials/Starting from a Skeleton": ["run"],
        "Tutorials/Using the Debugger": ["run", "plain: breakpoint(), no debugger on the site", "run"],
        "Tutorials/Ways to Find a Bug": [UNDEFINED],
        "Tutorials/Writing Code Others Can Read": [DEFINITION, DEFINITION,
                                                   "plain: adds to a count it never starts",
                                                   UNDEFINED, DEFINITION, "run",
                                                   "plain: a comment, no code"],
        "Warm-Ups/Predict the Output": ["run"],
        "Warm-Ups/Spot the Bug": ["run"],
        "Warm-Ups/Trace It": ["run"],
    },
}

# Runs that end in an error ON PURPOSE - the error is the lesson. A check
# that presses Run on every block expects "Finished." from all the others.
ENDS_IN_AN_ERROR = {
    "ICS3U": {
        ("Concepts/Parameters, Returns, and Scope", 3): "NameError (the page explains scope with it)",
        ("Exercises/Functions Practice", 3): "NameError (the exercise asks students to predict it)",
        ("Tutorials/Using the Debugger", 3): "ZeroDivisionError (the bug the tutorial hunts)",
    },
}


def table_problems(course_code: str, root: Path) -> list:
    """The payload against its judgement table, if it has one."""
    table = TABLES.get(course_code)
    if table is None:
        return []
    problems = []
    shared = root / "shared"
    seen = set()
    for page in sorted(root.rglob("*.md")):
        text = page.read_text(encoding="utf-8")
        blocks = python_blocks(text)
        if not blocks:
            continue
        try:
            key = str(page.relative_to(shared))[:-len(".md")]
        except ValueError:
            key = str(page.relative_to(root))[:-len(".md")]
        seen.add(key)
        expected = table.get(key)
        if expected is None:
            problems.append(f"table: {key} has {len(blocks)} Python block(s) the table does not list")
            continue
        if len(expected) != len(blocks):
            problems.append(f"table: {key} has {len(blocks)} Python block(s), the table lists {len(expected)}")
            continue
        for number, (block, wanted) in enumerate(zip(blocks, expected), start=1):
            actual = judgement_of(block)
            wanted_kind = "plain" if wanted.startswith("plain") else wanted
            if actual != wanted_kind:
                problems.append(f"table: {key} block {number} (line {block['line']}) is {actual}, "
                                f"the table says {wanted}")
    for key in sorted(set(table) - seen):
        problems.append(f"table: {key} is in the table but has no Python block in the payload")
    return problems


def table_counts(course_code: str, root: Path) -> dict:
    """How many blocks of each kind, and on how many pages, as BUILT from the
    payload (not from the table)."""
    counts = {"run": 0, "readonly": 0, "plain": 0, "input": 0, "pages": 0, "plain_pages": 0}
    pattern = re.compile(page_features.RUNNER_LANGUAGES["python"]["inputPattern"])
    for page in sorted(root.rglob("*.md")):
        blocks = python_blocks(page.read_text(encoding="utf-8"))
        if not blocks:
            continue
        runnable_here = 0
        for block in blocks:
            kind = judgement_of(block)
            counts[kind] += 1
            if kind != "plain":
                runnable_here += 1
                if pattern.search(block["body"]) or "stdin" in block["runner"]["flags"]:
                    counts["input"] += 1
        if runnable_here:
            counts["pages"] += 1
        else:
            counts["plain_pages"] += 1
    return counts


# ---------------------------------------------------------------------------
# Self-check: the rules against shapes they must accept and refuse
# ---------------------------------------------------------------------------

PAGE_MUST_BE_ACCEPTED = [
    "---\npublish: true\n---\nplain\n```python\nprint(x)\n```\n",
    "---\npublish: true\ncodeRunner: true\n---\n```python run\nprint('hi')\n```\n",
    "---\ncodeRunner: true\n---\n```python run readonly\nname = input('Name? ')\nprint(name)\n```\n",
    "---\ncodeRunner: true\n---\n> [!success]- Answer\n> ```python run\n> for n in range(3):\n>     print(n)\n> ```\n",
    "---\ncodeRunner: true\n---\n```python title=\"run me.py\" run\nimport math\nprint(math.pi)\n```\n",
    # A language these rules do not judge is never refused (#493's Swift).
    "---\ncodeRunner: true\n---\n```swift run\nprint(\"hi\")\n```\n",
    # A file named by what the user typed, written then read back.
    "---\ncodeRunner: true\n---\n```python run\nname = input('File? ')\nwith open(name, 'w') as f:\n"
    "    f.write('x')\nwith open(name) as f:\n    print(f.read())\n```\n",
    # sys.stdin with the stdin flag.
    "---\ncodeRunner: true\n---\n```python run stdin\nimport sys\nprint(sys.stdin.readline())\n```\n",
    # Written before it is read, in one run.
    "---\ncodeRunner: true\n---\n```python run\nwith open('a.txt', 'w') as f:\n    f.write('x')\n"
    "with open('a.txt') as f:\n    print(f.read())\n```\n",
    # A read guarded against the missing file, through a constant.
    "---\ncodeRunner: true\n---\n```python run\nFILE_NAME = 'r.txt'\ndef show():\n    try:\n"
    "        with open(FILE_NAME, 'r') as f:\n            print(f.read())\n"
    "    except FileNotFoundError:\n        print('none')\nshow()\n```\n",
    # A name bound inside a function and used outside it: a deliberate NameError.
    "---\ncodeRunner: true\n---\n```python run\ndef f():\n    total = 1\n    return total\nf()\nprint(total)\n```\n",
]
PAGE_MUST_BE_REFUSED = [
    "---\npublish: true\n---\n```python run\nprint('hi')\n```\n",
    "---\ncodeRunner: true\n---\n```python\nprint('hi')\n```\n",
    "---\ncodeRunner: \"true\"\n---\n```python run\nprint('hi')\n```\n",
    "---\ncodeRunner: true\n---\n```Python run\nprint('hi')\n```\n",
    "---\ncodeRunner: true\n---\n```python run,stdin\nprint('hi')\n```\n",
    "---\ncodeRunner: true\n---\n```python run readOnly\nprint('hi')\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nprint(minutes)\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nif x:\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nwith open('w.txt') as f:\n    print(f.read())\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nwith open('w.txt') as f:\n    print(f.read())\n"
    "with open('w.txt', 'w') as f:\n    f.write('x')\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nimport turtle\nturtle.forward(9)\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nfrom toolbox import read_lines\nprint(read_lines('a'))\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nbreakpoint()\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nwith open(file='w.txt') as f:\n    print(f.read())\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nfrom pathlib import Path\nprint(Path('w.txt').read_text())\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nimport sys\nprint(sys.stdin.readline())\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nfrom sys import stdin\nprint(stdin.readline())\n```\n",
    "---\ncodeRunner: true\n---\n```python run\nfrom pathlib import Path\nnotes = Path('w.txt')\nprint(notes.read_text())\n```\n",
    "---\npublish: true\n---\n```python run\nprint(1)\n```\n```swift run\nprint(2)\n```\n",
    "---\ncodeRunner: true\n---\n```python run autorun\nprint(1)\n```\n```python run autorun\nprint(2)\n```\n",
]


def check_the_checks() -> list:
    failures = []
    for page in PAGE_MUST_BE_ACCEPTED:
        found = page_problems("case", page)
        if found:
            failures.append(f"refused a page it must accept: {page!r} -> {found}")
    for page in PAGE_MUST_BE_REFUSED:
        if not page_problems("case", page):
            failures.append(f"accepted a page it must refuse: {page!r}")
    return failures


def main(course_code: str) -> int:
    broken = check_the_checks()
    if broken:
        print("the runnable-code rules misbehave (a broken LINTER, not a broken page):")
        for line in broken:
            print(f"   {line}")
        return 2
    root = REPO_ROOT / "support" / "example_content" / course_code
    if not root.is_dir():
        print(f"no payload at {root}")
        return 1
    problems = []
    for page in sorted(root.rglob("*.md")):
        problems.extend(page_problems(str(page.relative_to(root)), page.read_text(encoding="utf-8")))
    problems.extend(table_problems(course_code, root))
    counts = table_counts(course_code, root)
    print(f"{counts['run'] + counts['readonly']} runnable ({counts['run']} editable, "
          f"{counts['readonly']} readonly; {counts['input']} read input) on {counts['pages']} pages; "
          f"{counts['plain']} plain; {counts['plain_pages']} page(s) with Python and nothing to run")
    if course_code not in TABLES:
        print("note     no judgement table for this payload - the rules alone were checked")
    for problem in problems:
        print(f"PROBLEM  {problem}")
    print("clean" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))

#!/usr/bin/env python3
"""
The self-check quiz rules in the contract, run against what the SITE runs (#563).

NOT named `test_*.py` on purpose, like `check_runner_rules_against_the_site.py`:
it needs the image's Node and esbuild, so it can only run inside the
container, and Windows' `PythonToolchainTests` discovers every
`scripts/test_*.py`. `verify.sh` runs it in the image:

    docker run --rm \
      --mount type=bind,source="$(pwd)/scripts/check_quiz_rules_against_the_site.py",target=/opt/scripts/check_quiz_rules_against_the_site.py,readonly \
      quartz-teacher:dev-test python3 /opt/scripts/check_quiz_rules_against_the_site.py

`support/quartz/plugins/transformers/quizRules.ts` - the ONE file the site's
transformer and the page's script both check answers with - is bundled with
esbuild and every case in `contracts/shared-rules.json` -> `quizCallouts`
is run through it in Node:

* `answers.parse.cases` through parseAnswerLine, and `answers.check.cases`
  through accepts (an empty answer is never accepted);
* `shuffle.cases` through shuffledOrder with the cases' random numbers, and
  1,000 shuffles of 2 to 8 choices with Math.random, each a permutation;
* `recognise.cases`: the verdict of each case's model is not run here (the
  model comes from Quartz's parser, so verify.sh 6k reads every case back
  from a built page), but the transformer's text hook
  (quizRules.nestedTitlesOwnTheirLine) is: a page with no quiz outside fenced code -
  every `untouched` case, the one that only shows quiz syntax in a fence
  among them - comes back byte for byte (review S2), and a page saved with
  CR LF comes back with LF endings and the nested title on a line of its
  own (S1);
* every word the page's script and the transformer ask for
  (`word("...")`, `words.<key>`) is in `words.site`, and no word there goes
  unused.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import toolchain_paths  # noqa: E402

TRANSFORMERS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers"
RULE_TS = TRANSFORMERS / "quizRules.ts"
TRANSFORMER_TS = TRANSFORMERS / "plantoirQuizzes.ts"
SCRIPT_TS = toolchain_paths.SUPPORT_DIR / "quartz" / "components" / "scripts" / "quiz.inline.ts"
NODE_MODULES = toolchain_paths.QUARTZ_DIR / "node_modules"
ESBUILD = NODE_MODULES / "esbuild" / "bin" / "esbuild"

RUNNER = r"""
import { readFileSync } from "fs"
import { accepts, nestedTitlesOwnTheirLine, parseAnswerLine, shuffledOrder } from "RULE_TS"

const rules = JSON.parse(readFileSync(process.argv[2], "utf-8"))
const failures = []
let count = 0
const close = (a, b) => Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(a), Math.abs(b))

for (const c of rules.answers.parse.cases) {
  count += 1
  const got = parseAnswerLine(c.line)
  const want = c.expect
  if ("problem" in want) {
    if (got.problem !== want.problem) failures.push(`parse ${JSON.stringify(c.line)}: ${JSON.stringify(got)}`)
    continue
  }
  if (!("alternatives" in got) || got.alternatives.length !== want.alternatives.length) {
    failures.push(`parse ${JSON.stringify(c.line)}: ${JSON.stringify(got)}`)
    continue
  }
  want.alternatives.forEach((alternative, index) => {
    const mine = got.alternatives[index]
    const same = mine.kind === alternative.kind &&
      (!("value" in alternative) || close(mine.value, alternative.value)) &&
      (!("tolerance" in alternative) || close(mine.tolerance, alternative.tolerance)) &&
      (!("text" in alternative) || mine.text === alternative.text)
    if (!same) failures.push(`parse ${JSON.stringify(c.line)} alternative ${index + 1}: ${JSON.stringify(mine)}`)
  })
}

for (const c of rules.answers.check.cases) {
  count += 1
  const parsed = parseAnswerLine(c.line)
  const got = "alternatives" in parsed && accepts(parsed.alternatives, c.input)
  if (got !== c.accepted) failures.push(`check ${JSON.stringify(c.line)} <- ${JSON.stringify(c.input)}: ${got}`)
}

for (const c of rules.shuffle.cases) {
  count += 1
  let at = 0
  const got = shuffledOrder(c.n, () => c.random[at++])
  if (JSON.stringify(got) !== JSON.stringify(c.order) || at !== c.random.length) {
    failures.push(`shuffle ${JSON.stringify(c)}: ${JSON.stringify(got)} after ${at} numbers`)
  }
}
count += 1
for (let run = 0; run < 1000; run += 1) {
  const n = 2 + (run % 7)
  const order = shuffledOrder(n, Math.random)
  const sorted = order.slice().sort((a, b) => a - b)
  if (JSON.stringify(sorted) !== JSON.stringify(Array.from({ length: n }, (_, index) => index))) {
    failures.push(`shuffle ${n}: ${JSON.stringify(order)} is not a permutation`)
    break
  }
}

for (const c of rules.recognise.cases) {
  count += 1
  const out = nestedTitlesOwnTheirLine(c.markdown)
  if (c.untouched && out !== c.markdown) {
    failures.push(`recognise ${c.name}: a page with no quiz came back changed: ${JSON.stringify(out)}`)
  }
  if (c.markdown.includes("\r")) {
    if (out.includes("\r")) failures.push(`recognise ${c.name}: CR left in the page`)
    if (!out.includes("> > [!answer]- Answer\n> >\n")) failures.push(`recognise ${c.name}: the nested title has no line of its own: ${JSON.stringify(out)}`)
  }
}
console.log(JSON.stringify({ count, failures }))
"""


def run_the_rules_in_node(folder: Path) -> list:
    entry = folder / "runner.mjs"
    entry.write_text(RUNNER.replace("RULE_TS", str(RULE_TS)), encoding="utf-8")
    bundle = folder / "runner.bundle.mjs"
    environment = dict(os.environ, NODE_PATH=str(NODE_MODULES))
    subprocess.run([str(ESBUILD), str(entry), "--bundle", "--format=esm", "--platform=node",
                    f"--outfile={bundle}", "--log-level=warning"], check=True, env=environment)
    rules = folder / "quizCallouts.json"
    rules.write_text(json.dumps(contracts.section("shared-rules", "quizCallouts")), encoding="utf-8")
    output = subprocess.run(["node", str(bundle), str(rules)], check=True, capture_output=True, text=True).stdout
    result = json.loads(output.strip().splitlines()[-1])
    print(f"quizRules.ts: {result['count']} contract cases run in Node")
    return result["failures"]


def check_the_words() -> list:
    """Every word the site asks for is in words.site, and every word there is
    asked for."""
    site = set(contracts.section("shared-rules", "quizCallouts", "words", "site")) - {"note"}
    asked = set()
    for path in (SCRIPT_TS, TRANSFORMER_TS):
        text = path.read_text(encoding="utf-8")
        asked.update(re.findall(r'\bword\("([A-Za-z]+)"', text))
        asked.update(re.findall(r'\bsaid\("([A-Za-z]+)"', text))
        asked.update(re.findall(r'\bwords\.([A-Za-z]+)\b', text))
    asked.discard("site")
    failures = []
    for key in sorted(asked - site):
        failures.append(f"words: the site asks for {key}, which words.site does not have")
    for key in sorted(site - asked):
        failures.append(f"words: words.site.{key} is never shown")
    print(f"words: {len(asked)} asked for by the page's script and the transformer")
    return failures


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        failures = run_the_rules_in_node(Path(name)) + check_the_words()
    for failure in failures:
        print("FAIL " + failure)
    if failures:
        return 1
    print("OK: the self-check quiz rules in the contract hold in the site's own code")
    return 0


if __name__ == "__main__":
    sys.exit(main())

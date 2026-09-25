# Where a frontmatter block ends — fence fuzz, issue #188

**Question.** Does each reader of a page's frontmatter find the SAME block
python-frontmatter finds? The build reads every page with python-frontmatter,
so its block is the one the site obeys; a reader or writer that ends the block
anywhere else reads, or edits, a different block.

**Answer (2026-09-25).** Before #188 both the mac's
`PageVisibilityReader.fenceIndices` and the build's own
`build_site._frontmatter_fences` disagreed with python-frontmatter on
**1,316 of 3,000** generated pages. With #188's rule — the CLOSING fence is
three or more dashes at column 0, trailing spaces and tabs only; the OPENING
fence may be indented, because `frontmatter.parse` strips the whole document
first — both disagree on **0 of 3,000**.

| Reader | Before #188 (`origin/dev` 68214a6c) | After #188 |
|---|---|---|
| Swift, `PageVisibilityReader.fenceIndices` | 1,316 of 3,000 | 0 of 3,000 |
| Python, `build_site._frontmatter_fences` | 1,316 of 3,000 | 0 of 3,000 |

The disagreements were, in order of how often: an INDENTED `---` or `\t---`
inside the block, which the old rule took as the close and python-frontmatter
does not; an indented CLOSE, on which python-frontmatter never closes at all;
often with an indented or `----` opener beside it.

**Rejected, and why it is not in the table.** A symmetric rule ("never
indented", open or close) was measured by the first attempt at this issue
(2026-09-19, on the branch `issue/181-visibility-writers-keep-key-with-value`):
it finds no block behind an indented OPENER, which python-frontmatter does
read, and every writer then prepends a second block and turns the teacher's
own into body text — issue #140's bug.

**What the fuzz does not cover.** Whitespace after the dashes that python's
`\s` matches and the apps' trim does not — a non-breaking space, a FORM FEED,
a vertical tab — so such a line closes the block for the build and not for the
apps; and a byte-order mark. The review of this piece extended the generator
(seed 31337, adding `---\f` among other fences) and got **199 of 3,000**
disagreements, every one a form feed after the dashes; without it, 0 of 2,663,
and Swift against Python 0 of 3,000. Neither is generated here; the first attempt's 1,422-page
corpus of 2026-09-19 carried BOMs, and nothing measured either shape on a
real page. Named in `documentation/08-course-config-reference.md` rather than
coded for.

## Conditions

- Pages: `fuzz_fences.py generate` — seed 188, 3,000 pages, SHA-256 of the
  JSON it prints `44621dc0188c2c26f3c20980df50fff3b4287c6fb793e4a194737c6c520ee85c`.
  Built from 12 fence spellings (open and close chosen independently), 0–3
  lines from 10 bodies (including `  ---`, `\t---`, a block scalar holding a
  `---`), 0–2 blank or space-only lines in front, and CRLF on about one page
  in ten. The corpus is not committed; the seed is.
- The truth: python-frontmatter 1.3.0 / PyYAML 6.0.3 / CPython 3.11.15, inside
  `quartz-teacher:dev-test` — `YAMLHandler.detect` then `.split` on the
  stripped text, which is what `frontmatter.parse` does.
- Swift: Apple Swift 6.3.3, macOS 26.6, Apple M4 Pro; `fence_probe.swift`
  compiled against the app's own sources at each revision.
- Blocks compared with carriage returns removed and outer whitespace stripped,
  which is how python-frontmatter hands its block to YAML; "no block" is
  compared as such.

## Re-running it

From the repository root, with Colima running (the image mounts only paths
under `$HOME`, so the scripts are handed over as a tar stream where needed):

```bash
F=research/frontmatter-fences/fuzz_fences.py
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock
python3 $F generate > /tmp/pages.json
docker run --rm -i -v "$PWD/research/frontmatter-fences:/f:ro" quartz-teacher:dev-test \
  python3 /f/fuzz_fences.py library < /tmp/pages.json > /tmp/library.json

# The build's finder, at this revision:
docker run --rm -i -v "$PWD/research/frontmatter-fences:/f:ro" -v "$PWD/scripts:/w/scripts:ro" \
  -e PYTHONPATH=/w/scripts quartz-teacher:dev-test \
  python3 /f/fuzz_fences.py build < /tmp/pages.json > /tmp/build.json
python3 $F compare /tmp/library.json /tmp/build.json

# The app's finder, at this revision:
M=mac-app/QuartzTeachers/Models
printf 'import Foundation\nfinal class Course { func sectionDirectoryURL(forSection n: Int) -> URL { URL(fileURLWithPath: "/tmp") } }\n' > /tmp/stub.swift
swiftc -parse-as-library -O -o /tmp/fence-probe research/frontmatter-fences/fence_probe.swift /tmp/stub.swift \
  $M/PageVisibilityReader.swift $M/PageFrontmatter.swift $M/Assist/AssistPageVisibility.swift $M/CalendarDay.swift
/tmp/fence-probe < /tmp/pages.json > /tmp/swift.json
python3 $F compare /tmp/library.json /tmp/swift.json
```

For the "before" column, run the same against `git archive origin/dev` of
`scripts/` (piped into the container as a tar stream) and the four Swift files
from `git show 68214a6c:<path>`.

Measured by Claude Opus 5.5 on 2026-09-25 for the branch
`issue/188-182-186-frontmatter-shapes`, reproducing the plan's rig
(`p188/rig/fuzz_fence.py`, same seed and generator) from committed files.

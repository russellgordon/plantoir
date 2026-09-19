# research/

Measurement records. Nothing here runs automatically and nothing here is a
gate — these are the files the code points at when a comment says a decision
was measured rather than reasoned. Two rules keep them useful:

1. **Every results file states its own conditions in its header** — hardware,
   engine build, flags, model, surface, trial count. A number without those is
   not a finding.
2. **Superseded runs are marked, not deleted.** A later run that reversed an
   earlier one is the most valuable thing in here, and it only reads that way
   if both are present.

## `native-control-metrics/` — what a real AppKit control measures

The numbers behind `CourseCodePickerView`, the SwiftUI imitation of an
`NSComboBox` in the macOS wizard. A script renders the REAL control offscreen
and reads it back pixel by pixel, so the imitation is matched against AppKit's
own artwork rather than against screenshots of our own app — which is how the
field once ended up 30pt tall beside a native 24pt one. Cited from
`CourseCodePickerView.swift`.

## `ai-assist/` — the local assistant

Why the assistant is built the way it is: which models were tried, which were
vetoed and for what, and what the flags cost.

**Read these first**

| File | What it settles |
|---|---|
| `HISTORY.md` | The narrative: the feasibility investigation, the build handoff, and the original MCP proposal, merged with a status block saying what has since been overturned. |
| `macos-native-10-trial-comparison.txt` | **The model decision.** Ten models × 29 probes × 10 trials on one identical tool surface. The source of the 3B veto (two unrelated families inverting on the same sentence), and of Qwen3-4B replacing the 7B. Cited from `AssistModelTier.swift`. |
| `reasoning-flag-measurement.txt` | Why thinking must be turned off with **two** flags, and why the fault hid for days: llama.cpp parses the thinking out of the reply, so only the token count and the clock show it. |
| `tools-from-contract.py` | **Start here for a new measurement.** Writes the tool surface the suites take as input, read from `contracts/assist-cases.json` — which is generated from the app, so a run cannot be against a surface that does not ship. `local` (13 tools) is what the on-device model sees; `mcp` (32) is Claude Code's. |
| `thirteen-tool-surface-results.txt` | The **current** shipping surface, 42 probes × 10 trials on both tiers. Also records the description-steer regression: fixing one probe in a tool description broke three others. Its 42-probe harness was never committed, so it cannot be re-run — see the row below. |
| `metal-routing-results.txt` | **Routing on the hardware that ships, after the 2026-08-24 prompt change** (issue #117). Both tiers, three system-prompt forms including the one before the change, the app's own request body, and the mac's OWN shelf — the "promise card" in every other file here is Windows' `ExampleRequests`, not this app's. The answer on the prompt: neutral on the 4B (28 of 29 probes identical either way), and worth 5 trials in 10 on one hide request on the 1.5B. The findings that matter are elsewhere in it, and each is now an issue: `read` on the 4B has gone from 10/10 to 0-1/10 since August (#167), the mac shelf's "Deploy at 6:30 AM" deploys NOW on the small tier (#168 — **closed in code on 2026-09-19**, see `metal-routing-postscript-168.txt` beside it: the sentence is matched in `AssistCardCommand` and no longer reaches the model, so the shelf's split is 16 answered in code and 3 routed. The measurement is unchanged and still true OF THE MODEL), and the app sent no `max_tokens` (#166, since fixed — so **this file's `--app-body` arm is `--app-body --uncapped` today**, and a re-run without that flag is measuring a different body). One more sentence in it went out of date on 2026-09-19: it says the app "rewrites the course and section" before a call runs, and since [#202](https://github.com/russellgordon/plantoir/issues/202) a wrong COURSE is REFUSED rather than rewritten — so its wrong-course counter is now LESS strict than the product rather than more. See `metal-routing-postscript-202.txt` beside it, which also carries the per-file count behind that decision (686 responses, 0 wrong course codes). Checked by three Claude Opus reviews in fresh contexts — of the plan, the results and the corrections — and a final Claude Fable 5.1 pre-merge sweep. Also the file to read before quoting any "malformed tool calls: 0" in this folder. Pre-registered: its thresholds were committed before the first model call. |
| `token-cap-results.txt` | **What the request cap did to routing** (issue #166), and the answer is nothing: 0 of 29 probes and 0 of 19 shelf phrasings differ on either tier, against this morning's uncapped arm AND against a same-afternoon uncapped control — trial for trial, 960 of 960 rows, pre-registered at 08:46 before the first capped request was sent. What DID change is the clock: the runaway that opened #166 went from 5,435 completion tokens and 41–95 s to 512 tokens and 6.0–6.3 s, ten trials of ten. Read it for two other things as well — the equivalence that makes every older `--app-body` number in this folder `--app-body --uncapped` today, and the one shape the cap's headroom argument had not covered, measured at last: sixty `list_pages` relative paths are 975 tokens and would cross 512 at about the thirty-first, but the model asked to publish them answered `"pages": "all"` in 35 tokens, 3 of 3. It cannot show the other half of #166 — whether a cut-off answer is refused — and says so at the top. |
| `shelf-phrasings-results.txt` | **The mac shelf as it stood on 2026-08-16**, word for word, 14 × 10 trials on the 4B — the shelf is 19 cards today and ten of them appear here, including all four that reached the model when this was written — three today, since "Deploy at 6:30 AM" was moved into code on 2026-09-19 (#168) — so it is still the evidence for those four on the larger assistant; `metal-routing-results.txt` measured the current nineteen on the smaller one. Also records a harness fault worth more than the result: measured without `AssistAgent.dateline(on:)`, "Publish the class on Monday" resolved to a date a month away 10/10 and nearly cost a good card. |

**Earlier runs, superseded but kept**

| File | Superseded by |
|---|---|
| `macos-native-results.txt` | The 10-trial comparison — it says so at the end. Three trials per probe, and the 3B veto it reported at 2-of-3 turned out to be 9-of-10. |
| `twenty-tool-surface-results.txt` | `thirteen-tool-surface-results.txt`. Measured the 20-tool surface, which is what the MCP client sees but not what the local model is shown. |
| `trimmed-surface-results.txt`, `shipped-surface-results.txt`, `promise-card-results.txt`, `cache-restore-results.txt` | Windows-side, in-container runs. The prompt-cache save/restore work in the last one is what running the model natively made unnecessary. |

**The harnesses** — `shelf-phrasings-suite.py` (the shelf, with the app's own system prompt AND its dateline), `trimmed-surface-suite.py` (the 29-probe suite the
Windows-comparable numbers come from, and the one to start a new measurement
with),
`teachers-say-suite.py` (**Windows**, 25 probes: what the `TEACHERS SAY:`
clauses on two tools are worth, before and after, with fifteen controls for
the collateral damage a description change has caused before — its
malformed-call counter was corrected on 2026-09-18, so results taken with it
BEFORE that date report "malformed: 0" where they mean "no HTTP errors", and a
re-run counts honestly),
`routing-suite.py`, `adversarial-suite.py` (**cannot be run as committed**: it
does `sys.path.insert(0, "/root")` and then `from suite import TOOLS, SYSTEM`,
and no `suite.py` is in this repository — it was a file on the machine it ran
on. Its probes also expect `set_draft`, a tool that no longer exists. Read it
as a record of what was asked, not as something to re-run), `narrow-tools.py`
(a hand copy of the real narrowing code, so a surface under test is the
shipped one),
`shipped-surface-suite.py` (**historical** — its probes accept `publish_class`
and `hide_class`, tools that no longer exist, so every probe in it now misses
by construction; two files used to point a new measurement at it and were
corrected on 2026-09-18), and two
PowerShell helpers for dumping a live tool list.

`trimmed-surface-suite.py` takes five things that were added for #117 and
#166 and that a later run will want: `--prompt shipped|hyphen|pre-tweak` (the
shipped form is READ out of `AssistAgent.swift` rather than copied, and an
assertion fails the run if the copy has drifted), `--app-body` (exactly what
`AssistModelClient` sends — temperature 0, `tool_choice` auto, and
`max_tokens` read out of `AssistModelClient.swift` the same way, with the run
FAILING if that constant cannot be found rather than quietly falling back to
no cap), `--uncapped` (with `--app-body`: no `max_tokens` at all, which is
the body the mac sent **before** #166 — so every `--app-body` number in this
folder taken before 2026-09-19, `metal-routing-results.txt`'s H arm included,
is reproduced today by `--app-body --uncapped`), `--mac-shelf` (the MAC's own nineteen cards instead of the
default probe set, whose eleven "promise card" entries are WINDOWS'
`ExampleRequests`; the list is checked against
`AssistSupportingViews.swift` on every run and the run FAILS if the two have
drifted, naming both sides), and an interception guard that says which probes
the app answers in code before any model sees them. Defaults are unchanged, so
an old command line still reproduces an old file.

**The 42-probe suite that produced `thirteen-tool-surface-results.txt` was not
committed; its results were — and that has now cost something.** #117 tried to
reproduce it on the same hardware, the same engine build, the same weights,
the same flags and the same tool surface, and several probes came out
differently. Whether the probe text drifted, or the small model is simply that
unstable, cannot now be settled. **Commit the harness beside the results**, or
the file becomes a claim rather than a measurement.

**`narrow-tools.py` was a hand copy that silently went stale, and now is not.**
It was right when committed on 2026-08-14 and wrong from 2026-08-17, when
`AssistAgent.ForTheLocalModel` went from fifteen names to thirteen and the
Python was not followed through — so it kept narrowing to four `plan_` tools
the app no longer shows and missing the two it had gained. Nothing could
catch that: a research script is run by hand, months apart. Since 2026-09-08
`NarrowToolsMirrorTests` in the Windows suite fails when the two lists differ,
which is the only way a file like this stays honest. The three results files
measured inside that 2026-08-14 to 17 window are sound; anything taken through
it AFTER 2026-08-17 is not. **The general lesson, for any harness here:** a
number is only as good as the surface it was taken against, and a hand copy of
a shipping list needs something that runs on every commit to hold it in place.

**To re-run any of it**: start `llama-server` by hand with the flags in the
results file's header, point the suite at it, and compare like for like — the
probe set and the tool surface both have to match, or the numbers mean nothing.
A change to a tool, a tool description, a model, a quant or a context size is a
reason to re-run.

## A source that was NOT kept

`dcp.html` — a 6.4 MB saved copy of Ontario's **Curriculum and Resources**
site, taken 2026-08-14 and used when transcribing the CHC2D expectations and
when working out half credits (Career Studies and Civics are 55 hours each and
taken back to back, which the linter's hard-coded 110 hours and the installer's
fixed September anchor both got wrong).

**Removed 2026-08-16, deliberately.** The ministry updates these documents
whenever it likes, so a copy held here does not preserve a source — it
manufactures a second, stale one, and the next person to transcribe from it
would be quoting a curriculum that has moved. The rule this repository already
had says curriculum text is transcribed **verbatim or not at all**; the
corollary, now written down, is that it is transcribed **from the live site at
the time of writing**, and the payload records what it says rather than the
repository hoarding the page it came from.

If a payload's expectations need checking, go to `dcp.edu.gov.on.ca` and read
what is there now. If it differs from a payload, the payload is what needs
updating.

(The file remains in git history, which is where a removed 6.4 MB file belongs
— recoverable if it is ever genuinely needed, and not in anybody's working
tree.)

## `preview-staleness/`

`FINDINGS.md` — why a preview could show the page as it was before an edit:
what is established, what is assumed, and the hypothesis to test first. It also
carries a platform-independent finding worth knowing before building anything
on a file watcher: **a Colima or WSL2 bind mount does not deliver file events
for host-side writes**, so an in-container watcher never sees the teacher's
edit. Cited from `.claude/skills/mac-app/SKILL.md`.

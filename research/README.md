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
| `tools-from-contract.py` | **Start here for a new measurement.** Writes the tool surface the suites take as input, read from `contracts/assist-cases.json` — which is generated from the app, so a run cannot be against a surface that does not ship. `local` (13 tools) is what the on-device model sees; `mcp` (23) is Claude Code's. |
| `thirteen-tool-surface-results.txt` | The **current** shipping surface, 42 probes × 10 trials on both tiers. Also records the description-steer regression: fixing one probe in a tool description broke three others. |
| `shelf-phrasings-results.txt` | **Every phrasing the assistant window offers**, word for word, 14 × 10 trials — the evidence the shelf is allowed to promise them. Also records a harness fault worth more than the result: measured without `AssistAgent.dateline()`, "Publish the class on Monday" resolved to a date a month away 10/10 and nearly cost a good card. |

**Earlier runs, superseded but kept**

| File | Superseded by |
|---|---|
| `macos-native-results.txt` | The 10-trial comparison — it says so at the end. Three trials per probe, and the 3B veto it reported at 2-of-3 turned out to be 9-of-10. |
| `twenty-tool-surface-results.txt` | `thirteen-tool-surface-results.txt`. Measured the 20-tool surface, which is what the MCP client sees but not what the local model is shown. |
| `trimmed-surface-results.txt`, `shipped-surface-results.txt`, `promise-card-results.txt`, `cache-restore-results.txt` | Windows-side, in-container runs. The prompt-cache save/restore work in the last one is what running the model natively made unnecessary. |

**The harnesses** — `shelf-phrasings-suite.py` (the shelf, with the app's own system prompt AND its dateline), `trimmed-surface-suite.py` (the 29-probe suite the
Windows-comparable numbers come from), `shipped-surface-suite.py`,
`routing-suite.py`, `adversarial-suite.py`, `narrow-tools.py` (the real
narrowing code, so a surface under test is the shipped one), and two
PowerShell helpers for dumping a live tool list. The 42-probe suite that
produced the newest results file was not committed; its results were.

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

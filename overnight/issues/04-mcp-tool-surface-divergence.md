# Windows' MCP server serves 37 tools, the mac 25 — and nothing can notice future drift

Rank: 4 of 18. Potentially the largest item in the file. Read the whole brief
before planning: most of it is NOT an implementation job.
Kind: decide and propose
Gate: unit

## Russell decided this on 2026-09-06, before the batch ran
**Propose only. Build nothing.** He was asked directly whether he wanted parity
attempted and chose the decision document instead. So the refusal below is not
your judgement call to revisit — it is the instruction. Sort the 12, give the
reasoning, and stop. Do NOT implement even a "trivial and uncontroversial" one;
that escape hatch is withdrawn.

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes", first item (search for
"MCP server has drifted"). Found 2026-09-06 by an audit asking whether the
parity list was COMPLETE rather than whether it was correct.

## The verified facts
- `windows-app/Plantoir.Mcp/PlantoirTools.cs` declares **37** tools
  (`[McpServerTool(Name = "...")]`; the 38th `McpServerTool` hit is the
  `[McpServerToolType]` on the class).
- `mac-app/QuartzTeachers/Models/Assist/AssistToolSurface.swift` has 22 in
  `tools` plus 3 in `mcpOnlyTools` = **25** `mcpTools`.
- The difference is exactly 12, all Windows-only, none mac-only:
  `add_classes`, `back_up_course`, `explain_publishing`, `list_courses`,
  `list_recent_changes`, `make_room_for_classes`, `plan_add_classes`,
  `plan_make_room_for_classes`, `plan_sync_page_dates`, `read_timetable`,
  `roll_over_section`, `sync_page_dates`.
- **None of the 12 has any code behind it on the mac** — zero hits for every
  name under `mac-app/QuartzTeachers`.

## The handoff's stated mechanism is WRONG — correct it
It says a subset check hides the gap. It does not:
`windows-app/Plantoir.Tests/ContractTests.cs` →
`AssistCases_Tools_MatchesContract` uses `Assert.Equal` — set equality — for
`local`, `needsApproval` and `mcpOnly`. What is actually true is simpler and
worse: **no test on either platform enumerates the 37 declared tool names
against anything**, and no Windows test reads `toolSchemas` at all. So a tool
added on Windows and put in neither the contract nor the mac passes both suites
silently. Fix this description in `MAC-HANDOFF.md` as part of the work — stale
reasoning is worse than none.

## Why this is not an implementation session
Two reasons, both hard:
1. **Each survivor is a FEATURE, not a schema entry** — a tool definition, a
   runner, an approval gate, and the behaviour behind it. Twelve of those is
   far more than one overnight session.
2. **`toolSchemas` is generated** (`AssistContract.swift`) and overwritten by
   `Plantoir --write-contracts`. You cannot "put the survivors in the contract"
   first; the real order is decide → write Swift → regenerate.

And if any survivor lands in `localTools`, that is a ROUTING change: CLAUDE.md
records that the local model is shown 13 of 22 deliberately, that more choices
is the classic way a router degrades, and that routing is measured by hand
against a local `llama-server` — which cannot happen unattended.

## What done looks like for THIS session
- A written recommendation, in `MAC-HANDOFF.md` under this item, going through
  all 12 and sorting each into: **product** (belongs on the mac, worth
  building), **Windows-shaped** (deliberately not on the mac, with the reason),
  or **already covered** by an existing mac tool under another name. Check
  `TODO.md` first — it already names some of these as the CSV-reschedule
  surface.
- The reasoning for each, because that is the part that travels.
- A note of what Windows owes: an enumeration test over the 37
  `[McpServerTool]` names, which nobody has told them about. Put it in
  `WINDOWS-HANDOFF.md` so they see it.
- **Optionally**, if one survivor is genuinely trivial and uncontroversial,
  implement that one and say why it was safe. Do not implement more.
- Do NOT guess product scope for twelve tools at 3am.

Report `BATCH-RESULT: PROPOSED` unless you actually shipped something.

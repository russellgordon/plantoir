# Brief: write the content for a design-review page of v2.0.0's interface

Russell (the teacher who owns Plantoir) is evaluating the UX and UI of what
v2.0.0 added. Another agent is capturing screenshots; you write the WORDS
AND FACTS the page needs, as one JSON file. You are a READER: edit no
checkout; read `origin/dev` in `<repo>` with
`git show origin/dev:<path>` / `git grep … origin/dev` (the checkout itself
is on `dev` at the same commit and may be read directly, but never changed).
Work at HIGH EFFORT. NO SOUND, nothing that takes the screen, never spawn
agents. S = `<scratch>`.

## Sources (in this order of authority)

1. The contracts: `contracts/shared-rules.json` (`unitPlanning.tab`,
   `unitPlanning.share`, `coverageTab`, `referenceCourses.creating`,
   `.importing.zips`, `.replacing`, `.groups`, `returningToASectionMidDeploy.heldElsewhere`,
   `courseNameCharacters`, `scheduledRunGetsItsFolderReady`,
   `obsidianAddOnsForFigures.openStateCases`), `contracts/app-rules.json`
   (`launcherFlags`, the guard's sentences), `contracts/file-formats.json`
   (`referenceShelf`, `unitPlanShared`): the EXACT sentences a teacher reads
   and each block's `rejected` / `why` entries.
2. `documentation/09-mac-app.md`, `07-deployment.md`, `06` (GeoGebra) for what
   was measured and rejected.
3. The closing comments of the issues, which say what landed and what the
   reviews found: `GH_TOKEN="$(gh auth token --user russellgordon)" gh issue view <n> --repo russellgordon/plantoir --comments`
   for #708, #803, #709, #793, #572, #729, #756, #792, #742, #780, #748, #768.
4. The SwiftUI views themselves, for layout facts (where a control sits, what
   it is called, when it is disabled): `mac-app/QuartzTeachers/Views/`.

## What to write: `S/ui-tour/content.json`

A list of features, each:

```text wrap
{
  "id": "planning-tab",                     // slug
  "title": "…",                             // what a teacher would call it
  "issues": [708, 803],
  "oneLine": "…",                           // what it is, one sentence
  "whereItLives": "…",                      // window, tab, menu path
  "howItWorks": ["step …", "…"],            // the flow a teacher follows, in order, 3 to 8 short steps
  "states": [{"name": "…", "whatTheTeacherSees": "…", "sentence": "the exact sentence from the contract, if one"}],
  "designDecisions": [{"decision": "…", "why": "…", "rejected": "what was considered and not built, and why"}],
  "sentences": [{"key": "contract key", "text": "exact sentence"}],   // the most important 4 to 10 a teacher reads
  "accessibility": "…",                     // what is known: labels, keyboard, VoiceOver; say 'not measured' where true
  "notMeasured": ["…"],                     // what nobody has checked in the real window
  "questionsForRussell": ["…"]              // real UX judgement calls only: things the director ruled while he was away, trade-offs he may see differently
}
```

Features, in this order:
1. The Planning tab (#708, #803): the tab on the course page, the Unit popup, All Plans, Reload, Open in Browser, starting on All Plans when no unit covers today, the plan as plain HTML read from disk.
2. Sharing unit plans (#709): the share bar, the two-lists sheet before an open share, the crawler warning, protect / change / remove password, the console sheet, earlier years' rows, Stop Sharing and its unconfirmed state, the Netlify teacher's sentence, the interrupted-share state.
3. The Coverage tab (#793): per section, made by every build, the refresh that keeps the teacher on the tab, the click that opens Obsidian, every empty and stale state.
4. The reference shelf (#572): three doors and one path, Import for Reference with a zip and on backup rows, Replace with its warning and verified backup, groups (flat; year groups fixed; Start the Groups Again).
5. Deploy while another program works on the course (#729): the greyed button and its sentence; the launcher's refusals.
6. GeoGebra sketches (#756, #792): the opening state inside the sketch's box, no page jump, one announcement, reset.
7. Quiet changes a teacher may notice (#768 a second deploy does not rebuild; #780 names cleaned; #742 the add-ons offer; #748 a scheduled deploy after an update): one short feature entry covering all four.
8. Marking with an assistant: NOT a settled interface. Read `S/trials/RESULTS.md`, `S/plans/marking-hardening-plan-review.md` ("The design I would build") and `S/reviews/750d-impl-review.md`, and describe the PROPOSED teacher-run flow (two files the teacher double-clicks; a Terminal window; the cover with four privacy points; the typed yes) as a proposal awaiting his decision, with its honest limit (nothing stops a determined assistant running the file; it holds because the assistant is never told the folder and never asked), and what is unmeasured (the real double-click).

Rules for the writing: plain declarative sentences a teacher can read; no
machinery words in anything presented as what a teacher sees; EXACT
sentences copied from the contract with their key (never paraphrased, never
invented: if you cannot find the sentence, leave it out); no person's name;
no em dashes; every "rejected" entry true to the source. Where the director
ruled something while Russell was away, say so under `questionsForRussell`:
before an open share the teacher sees both file lists and says yes (#709);
the launcher refuses ANY overlapping build of a section (#729); Import for
Reference takes any zip and backup rows gained "Import for Reference…"
(#572); the wizard offers the reference choice only for codes with
ready-made pages (#572); an unreadable groups arrangement offers Start the
Groups Again (#572); Open in Browser opens only HTML and PDF from the plan
folder (#803).

Validate the JSON parses. Report in under 120 words.

# macOS App — Handoff

> **New here? Read [`MAC-BOOTSTRAP.md`](MAC-BOOTSTRAP.md) first.** It says how
> to take work that arrived from Windows, and how to add a feature on this side
> so it reaches them as data rather than as a surprise. This file is the ledger
> it sends you to.

The ledger of work that originated on the **Windows side** and needs — or
deserves a look from — the **macOS app**. The reverse of
[`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md): read this when syncing the mac
after Windows-side sessions.

**Read it top-down and stop when you like.** Everything still owed is in the
first two sections; everything already dealt with is kept below them, in full,
because the reasoning is the point of the file and deleting a finished entry
throws away why the mac does what it does.

| Section | What is in it |
|---|---|
| [Contract cases waiting on the mac](#contract-cases-waiting-on-the-mac) | Cases proposed from Windows that the mac suite is failing on. Read FIRST when a suite goes red. |
| [Open — what the mac still owes](#open--what-the-mac-still-owes) | Work not yet done here. |
| [For awareness — no mac code needed](#for-awareness--no-mac-code-needed) | Things to KNOW, not to do: shared decisions, frozen names, coordination points. |
| [Done — the ledger](#done--the-ledger) | Finished, marked in place with what landed and where. History, and the reasoning behind decisions the code no longer explains. |

Cross-side rebases rewrite commit hashes, so treat hashes as hints from the
moment of writing — file and test names are the durable pointers.

## How to write an entry

The good entries below already do this; it is written down so the next one
does not have to infer it from twenty examples. An entry carries:

1. **A bold title that says what CHANGED**, then `(source, date, commit)` —
   "Windows", "shared", or "Windows + shared" for work in `scripts/`.
2. **What it fixed, and WHY it was done that way.** The why is the half that
   travels: the mac can read a diff, it cannot read a decision. Include what
   was **rejected**, or it gets proposed again and costs the same afternoon
   twice.
3. **Numbers, with the hardware they came from**, for anything measured. This
   side has no way to find out what a Windows teacher's machine does. "The
   Vulkan build was faster" cannot be acted on; "43 tok/s against 11 on CPU,
   Intel Iris Xe" can.
4. **Where the reference implementation lives** — file and test names, which
   outlast commit hashes across rebases.
5. **Whether the mac is expected to match it, or merely to know.** Those are
   different asks, and the second section of this file exists for the latter.

If a teacher can see the change, it also wants a row in
[`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md) — that log is the record of the
product, not of one platform.

## Contract cases waiting on the mac

**One proposed 2026-09-08, and the mac suite WILL go red for it: a new trail
event, `scheduled publish needed an answer`** — `shared-rules.json` →
`activityTrail.mustRecord`, branch `issue/92-non-interactive-deploy`, GitHub
issue #92. Deliberately NOT scoped with `appliesOn`, because the mac's launchd
wrapper has the identical problem and the identical fix is now available to it.

**What it is for.** A publish set to happen on its own runs at half six with the
app closed, so every question `deploy.py` or a launcher can ask is put to
nobody. Both ways that ended have been SEEN: with a terminal, `input()` blocks
— measured at 45 minutes, a `powershell.exe` and its `python.exe` child still
waiting at the site-name prompt when they were swept up, the teacher's site
simply not updated in the morning and nothing said. Without one, `prompt()`
returns its DEFAULT silently and a Netlify name conflict auto-suffixes, so the
site is published to an address nobody chose.

**What the mac owes, and in what order.**

1. **`deploy.sh` already takes `--non-interactive`** — changed in the same
   commit, since `app-rules.json` → `launcherFlags.deployExtras` is checked
   against BOTH launchers and a flag in one only would have failed the mac for
   a launcher reason rather than as a request. **It has not been run**: this
   machine has no bash-with-Docker, so `verify.sh` is owed from the mac. Four
   `read` sites are guarded (two `read -rp`, and two **`read -rsp`** — a grep
   for `read -rp` finds only two and looks complete), and the flag is forwarded
   into the `docker exec` through a `NON_INTERACTIVE` environment variable.
   `deploy.sh` looks for the flag TWICE, once in a pre-scan before its 'Open'
   course-code guard, which asks a question before the flag loop runs;
   `deploy.ps1` needs no pre-scan because it parses first and asks afterwards.
2. **The launchd wrapper must pass the flag and read exit 3.** Exit **3** means
   "a question went unanswered" and nothing else — every other exit in
   `deploy.py` and in both launchers is 0 or 1, checked rather than assumed.
3. **The event itself**, plus somewhere to say it. Windows writes a per-section
   note under `%LOCALAPPDATA%\Plantoir\scheduled\unanswered\` and reads it in
   `SectionDetailView` beside the folder problems, consume-on-read and
   clear-on-clean-run.

**Two things in the wrapper that look like tidiness and are not**, both found
by writing them: the note is written only by the FIRST destination that stops
(one note per section, several destinations, so overwriting reports the last
thing that went wrong rather than the first), and it is cleared only AFTER
every destination has run — clearing inside the loop meant a course whose
Netlify leg stopped and whose folder leg then succeeded had the note deleted by
the second leg, and the teacher was never told why the first did not go out.

**Rejected, and logged so it is not retried.** (a) A `PLANTOIR_NEEDS_AN_ANSWER:`
marker line on stdout, scanned from a captured log the way `PLANTOIR_HEALTH:`
is. `TranscriptBuilder.CarriesTheHealthMarker` matches only the literal health
marker, so a new one would be RENDERED in the teacher's console — machinery
in front of a teacher, and half-copying a convention: the machine-readable part
without the hiding part. (b) Capturing the deploy legs' output at all, which is
the only reason a marker was wanted: the legs are plain `& launcher` today and
converting them to `Start-Process` inherits four documented traps for a
sentence the app can say better itself, knowing the course, section and
destination already. (c) Redirecting the child's stdin to an empty file, which
would make `isatty()` false by construction — needs the same conversion, and
buys nothing once the flag refuses before any `input()` is reached.

**Not affected:** `ScheduledDeploy.Problem` on both platforms already refuses to
SCHEDULE a section that has never been deployed, for exactly this reason, so the
commonest way in was already closed. What it cannot see is a site DELETED at the
other end after the schedule was set, or a token revoked in between — which
is how a real `verify-deploy.ps1` run hit this and hung until its own 900-second
timeout.

**One proposed 2026-09-08, and nothing goes red for it: the Marks list's title
and caption** — `shared-rules.json` → `gradedFolders.wording`, branch
`issue/marks-wording-contract`. The second Course Settings divergence,
found in the same audit as the tip above — second, not last: see the end of
this entry for what is still unpinned. Four strings pinned by nothing; the
mac's title WINS unchanged, so the mac's only real change is the caption.

> **Title:** Folders whose work counts for marks
>
> **Caption:** Tick the folders holding work that counts for marks. The
> curriculum coverage map shows an expectation as evaluated when a page in one
> of these addresses it. Most courses keep “Tasks”; tick “Tests” or anything
> else you mark.

Russell chose the title (it is also the closer match to `specialFoldersHelp`'s
already-pinned "Work that counts for marks", so it cost this side nothing) and
chose what the map is called. **Three things in the caption are worth the mac
reading before adopting it, because each was argued the other way first.**

**The verbs.** The mac's caption says "**add** “Tests” … and **remove** what
you don't". This control is a tick list — `MembershipToggleListView` on the
mac, `MembershipToggleList` here — with no Add button at all, so it has been
naming two actions the control does not offer, and "remove what you don't"
invites the one thing `lastGradedFolderBlocked` refuses outright. It says
"tick" now. This is the part of the change that is a correction rather than a
preference.

**The map's name.** Both spellings are pinned already: `specialFoldersHelp`
says "the curriculum map", while `specialNames.lastGradedFolderBlocked` — the
flyout raised from THIS list — says "the curriculum coverage map", and the
switch beside it is labelled "Publish the curriculum coverage map". Russell's
call, 2026-09-08: follow the control, so the caption makes three matching names
on one screen. `specialFoldersHelp`'s wording is knowingly left alone; **that
is a recorded mixed state, not drift to tidy up**, and it is written into the
contract's `why` so the next reviewer does not "harmonise" it back. Windows'
capital-C "the Curriculum Coverage map" WAS drift and is gone — that is the
built page's title, not a common noun.

**Where the caption goes.** Below its list, on all four surfaces. The mac
already draws it there; Windows drew it ABOVE, where "a page in one of these"
followed the section header "Marks" and referred to nothing. Windows moved.
**So the mac has no layout change** — but the contract now says the position
out loud (`gradedFolders.wording.rule`), because it is what lets one string
serve all four places instead of a per-surface variant.

**What the mac does:** take the caption into `NewCourseWizardView.swift:937`
and `CourseSettingsView.swift:190` — the title at `:932` / `:185` already
matches — ideally via a constant rather than two literals, and assert both
against `gradedFolders.wording`. **Nothing on the mac is red meanwhile**: no
mac test names this key (`contracts/README.md` — "the mac reads the key but
runs no case list yet"). Reference: `GradedFolderRule.ListTitle` / `.Caption`,
three facts in `GradedFolderContractTests`, and
`CourseSettingsCaptionUiTests` for whether a teacher can see it.

**One trap, met here.** A Windows UI test hard-coded the old title inside an
automation id — `member:{list title}:{name}`, built by
`FormBuilders.MembershipToggleList` — so changing the title moved every marks
checkbox's id, in a suite that gates nothing and would have said nothing. It
now reads the title out of the contract. If the mac keys anything on that
string, look before changing it.

**One imprecision inherited rather than introduced, flagged not fixed:** the
coverage map's own word is "**assessed**", and this sentence says "evaluated".
It says it because `specialFoldersHelp` has said it since that sheet was
written; changing it means changing that row, on both platforms, which is a
separate piece.

**And this is the SECOND divergence in Course Settings, not the last** — an
earlier draft of this entry said "last", which would have told you the audit
was finished. One control above this one, the coverage-notes toggle says
"Explain the map on the page" on the mac and "Include explanations on
Curriculum Coverage page" on Windows — in Course Settings AND in the wizard,
so that is the same divergence twice. Nothing pins any of it.

**The captions beside it are two different problems, and a first draft of this
entry got it wrong in the direction that would have cost you work.** It said
Windows draws two sentences "the mac has no counterpart for". That is true in
Course Settings, where the mac shows no caption at all — and false in the
wizard, where the mac has had its own since it was built
(`NewCourseWizardView.swift:756` and `:766`) and they are markedly better than
this side's, because they say what a teacher will SEE rather than what the
switch does. So the wizard is an ordinary pick-one-of-two and the mac's
probably win; only Course Settings asks whether the mac gains a sentence or
Windows drops two. Eight strings, not four. Nothing is owed today; it is
`WINDOWS-HANDOFF.md` item 44, quoted in full there, so it is not lost.

**One proposed 2026-09-07, and nothing goes red for it: the Course Settings
tip sentence, which item 37 had been waiting on this side to choose** —
`shared-rules.json` → `specialNames.contentStructureTip`, branch
`issue/course-settings-tip-contract`. Russell made the call in a Windows
session; **the decision went the other way from what item 37 assumed** (it said
Windows owed taking the mac's wording verbatim), so the mac has a small change
to make rather than nothing:

> Tip: you can also simply create new folders and files in Obsidian — they’re
> added to your site automatically the next time you preview. The exception is
> anything you remove here: it stays off your site, even if you make it again
> in Obsidian, until you add it back here.

The mac's own sentence in `CourseSettingsView.swift:176` said the exception in
a six-word bracket — "(unless you have removed them here)" — and named no
remedy. **That was rejected as under-weight for the rule it glosses**, which
row 377 made permanent the same day it was written: `excluded_items` is
authoritative, so preflight now DROPS an excluded name it finds back in a copy
list, the exclusion is by NAME and never expires, and this page is the only
thing that can undo it. Windows' longer sentence was adopted with two changes.
"on this page" became **"here"**, because the sibling sentence
`removeLeavesTheFolderOnDisk` — shown at the moment of removal, in this same
view — already says "Add it back here to include it again", and Windows was
using two names for one place in one sentence; "in these lists" was considered
and rejected as marginally more precise but breaking that parallel.

**The third change is the one worth reading even if you disagree about the
rest.** Both apps said "folders". The caption sits under FOUR list editors, two
of which are FILE lists, and the behaviour is identical for files:
`discover_shared_items` / `discover_section_items` append top-level files, and
`build_site.py` skips and drops excluded ones from `shared_files` and
`per_section_files` exactly as it does folders (`documentation/08` —
"**Folder and file** names the teacher removed in Settings"). So a teacher who
removed a file met the same permanent, silent rule with nothing anywhere
warning them, on both platforms. The sentence now says "folders and files" —
"pages" was rejected, because discovery is not limited to `.md` and "files" is
the word the four list labels above the caption already use.

**What the mac does:** move the literal out of `CourseSettingsView.swift:176`
into a `SpecialNames.contentStructureTip` constant, take the sentence above,
and assert it in `testSpecialNamesSentencesMatchContract`. **Nothing on the mac
is red meanwhile** — no mac test pins this key — so this is a request to adopt
the line, not a break. Reference implementation:
`SpecialNames.ContentStructureTip` and the three facts in
`SpecialNamesContractTests` (`TheContentStructureTipMatchesContract`,
`…CoversFilesAsWellAsFolders`, `…IsNotABlockedSentence`). Two traps if you
mirror those: the entry deliberately carries **no `reason` key**, because
Windows' `NoBlockedSentenceInTheContractIsUnusedHere` sweeps every `reason` and
would demand this be one of the seven flyout sentences; and it must stay OUT of
any "longest sentence" assertion, since it is a caption that wraps and is far
longer than the flyout sentence such a test exists to name.

**A fourth test exists and is worth copying in spirit if the mac has anywhere
to put it.** Opting out of the `reason` sweep meant opting out of the only
check that a sentence is actually SHOWN — delete the line that adds the caption
and all 1206 unit tests stay green while it vanishes from the product. So
`CourseSettingsCaptionUiTests` (opt-in `[UiFact]`, gates nothing) reads the
Course Settings form through UI Automation and asserts the contract's sentence
is among the texts a teacher can see. **Measured rather than assumed**: with
the caption line commented out and the app rebuilt, it fails; restored and
rebuilt, it passes. The mac has no equivalent harness, so this is offered as
awareness rather than as a debt.

**One edge worth knowing, in SHARED Python, so it is the mac's too — but it
owes nothing today and is written up elsewhere.** "even if you make it again in
Obsidian" holds for a name remade as it was and not for one remade with
different capitalisation, because exact matching is the deliberate rule
(`gradedFolders.choices.walk.excludedItems`, reasoned in
`GUI-IMPROVEMENTS.md` row 412). The inconsistency worth fixing is narrower:
`_dropping_excluded_items` lowercases both sides while every other consumer
matches exactly. `TODO.md` carries it in full, `WINDOWS-HANDOFF.md` item 42
indexes it, and both warn against the obvious wrong fix.

**One proposed 2026-09-07, and nothing goes red for it: the New Course
wizard's affirmative button reads "Create Course" on both platforms** —
`NewCourseDialog.cs` on Windows, `NewCourseWizardView.swift:520` on the mac —
**and nothing in `contracts/` pins it** (`grep -rn "Create Course" contracts/`
returns nothing). It is the first thing a teacher presses in this app, it is
identical on both sides today, and it would go green on both immediately.
Windows now asserts it in a Windows-only UI test (`NewCourseWizardUiTests`),
which is the weakest place for a shared sentence to live. The contract is
generated on the mac, so where it belongs — `app-rules.json`, or a wizard
block of its own — is that side's call; this is the proposal, not the
implementation. Branch `issue/35-first-run-ui-checks`.

**One proposed 2026-09-07, a SENTENCE, not a rule: `shared-rules.json` →
`specialNames.renameFolder.interruptedRename`** — the line Windows shows
inside the rename sheet when it opens on a rename that stopped after the
folders moved: "Plantoir started renaming “{old}” to “{new}” and did not
finish — the folder has its new name, but this course’s settings still use
the old one. Press Rename to finish." The mac pre-fills the field silently
(`StringListEditorView.renameSheet`); Windows says why, because a filled-in
field with nothing said leaves a teacher wondering. Nothing on the mac goes
red — no test pins this key — so this is a request to adopt the line or say
why not. Branch `issue/13-rename-folder-and-config-writers`.

**One proposed 2026-09-07: `file-formats.json` → `pageVisibility.writingRules[0]`
now says a page in the old `draft:` spelling is MIGRATED to `publishForSection<N>`
and the legacy key removed — the mac keeps the old key inverted, so its suite
fails on this rule until it moves. That failure is the request arriving, not
damage.** Branch `issue/frontmatter-draft-key-divergence`; Russell's decision;
the reasoning and what was rejected are in the rule's own `why`. What the mac
adopts: `AssistPageVisibility.setting(published:…)` writes the NEW key on the
old key's line and drops the legacy one (Windows' `PageFrontmatter.SetDraft`
is the reference, and `FileFormatContractTests.TheOldSpellingIsMigratedToTheNewKey`
the cases); a page carrying both spellings loses the legacy one; and a
legacy page whose value is already right is still migrated, once — the rule's
one deliberate exception to "writing the value it already has changes
nothing", reasoned in `migrationIsTheOneExceptionToRule4`. `GUI-IMPROVEMENTS.md`
row 140's migration paragraph was right all along and needs no correction.

**~~One proposed 2026-09-07: `activityTrail.mustRecord` → `section restored`,
marked `appliesOn: ["windows"]` — and the mac suite goes RED on it anyway,
which is the request arriving, not damage.~~ ✅ DONE 2026-09-07 (mac, branch
`issue/section-restored-trail-event`).** Both halves, as asked. The mac's
`AssistSession.restoreSection()` now notes `.sectionRestored` with the course,
the section and the backup's file name, on the success path only; the sentence
lives in `AssistSectionRestore.trailLine` so a test pins it by name rather than
by a quoted copy. `SharedRulesContractTests.macMustRecord` is the `appliesOn`
filter. It agrees with the Windows twin on every well-formed value and differs
on two malformed ones, both deliberately: anything it cannot READ as a list of
platform names is treated as "belongs to both" rather than excusing the mac —
**and that now includes a well-formed list naming no platform anybody
recognises**, so `["windwos"]`, `["macos"]`, `["Mac"]` or `[]` keep the event
required instead of deleting it from BOTH suites with nothing going red. That
last case is the one worth copying: erring towards "required" turns a typo
into a red suite naming the event, which is a five-minute fix, where erring
the other way makes the requirement vanish and nobody finds out. (On the
wrong-TYPE shape — `"appliesOn": "windows"` — the mac returns "required" while
Windows throws; both end red, so this is a difference in the message, not in
the outcome.) `appliesOn` is now GONE from the case, so it is pinned on both sides
and the `why` no longer describes a state of affairs that has ended.

**One thing this leaves for whoever adds the next platform-only event:** there
is now NO `appliesOn: ["windows"]` entry in the contract, so the mac's filter
has no live case exercising it. `SectionRestoredTrailTests` pins it with
entries of its own for exactly that reason. `GUI-IMPROVEMENTS.md` row 445.
Original text: Branch
`issue/27-assist-conversation-restore`. `SharedRulesContractTests.swift`'s
`testTheTrailRecordsEveryEventTheContractRequires` builds its wanted set from
every `mustRecord` entry with no `appliesOn` filter (the Windows twin honours
it, since the mac's own `built site moved out of the working folder` is
`appliesOn: ["mac"]`), so the mac fails by name until it either adopts the
event or teaches its test the filter. Do both: the filter is what lets either
side propose a platform-only event without reddening the other. The mac's
"Restore Section N…" (`AssistSession.restoreSection`) records nothing on the
trail; Windows' does, because a section whose pages are older than the
conversation that changed them is exactly the thing a teacher asks about next
week, and rule 5 says a feature a teacher can see leaves a line. What is
asked: add `.sectionRestored` to `ActivityTrail.Event` on the mac, note it
from `restoreSection()` with the course, section and the backup's file name,
and drop the `appliesOn` so the event is pinned on both sides. The line
Windows writes: "put the section back to how it was when this conversation
started, from ICS3U_backup_…_assistant-section1.zip".

> **v1.1.0 cut sheet — ✅ Done 2026-08-20.** Released the same day this sheet
> was written: tag `v1.1.0`, release "Plantoir 1.1.0", published
> 2026-08-20T21:20:09Z and marked Latest, not a draft. All three assets are
> attached and they are the artifacts described below — `PlantoirSetup.exe`
> 235,449,648 bytes (224.5 MB) and `Plantoir-win-x64.zip` 398,389,660 bytes
> (379.9 MB), both matching the sizes recorded here. Confirmed against the
> live release 2026-09-06.
>
> **Two things did not go the way this sheet predicted, and they are the part
> worth keeping.** The DMG shipped in the same cut — `Plantoir-macOS.dmg`
> (53,220,868 bytes) is attached to v1.1.0 — so the mac did NOT join a later
> release the way "the macOS DMG does NOT ship in this cut" expected; the gate
> list came green in time. And the draft-then-attach dance was not needed in
> the end. Neither is a fault; both are why a prediction in a handoff gets
> marked done rather than deleted.
>
> **It sat here as an open instruction for seventeen days**, telling any mac
> session that read the top of this file to cut a release that had already
> shipped. That is the failure this section is most prone to, because it is
> read first and abandoned partway: a completed item left unmarked is
> indistinguishable from a pending one. Mark the cut sheet the day the release
> publishes.
>
> <details><summary>The sheet as written, 2026-08-20</summary>
>
> > The verified Windows artifacts live on the Windows machine and will be
> > uploaded FROM there (`gh` is authed there) once the tag exists — so cut the
> > release as a DRAFT, tell Russell, and publish after the assets attach.
> > Hashes for the notes' SHA-256 table:
> > `PlantoirSetup.exe` 224.5 MB
> > `9990bcacade548a35cbd5b11f65dbf79d4a0236eeeee4d4d0e5322204c96527e` ·
> > `Plantoir-win-x64.zip` 379.9 MB
> > `b141c7ac30116c9836334e90472e5a2527fb4e50629c56d4c2f258f437cbb1ba`.
> > Built from commit 8e9faab0, proven by five clean-machine smoke tests
> > (install → course → preview → assistant → deploy, no .NET/WSL/Docker on
> > the machine). The macOS DMG does NOT ship in this cut — see RELEASING.md
> > "Two platforms, one version series": the mac joins v1.1.0 after the gate
> > list below is green.
>
> </details>


**One is outstanding, proposed 2026-09-07: a TWELFTH `linkRewriting` case, for
the branch of the spelling rule that no case reached.** Added while Windows
replaced `Uri.EscapeDataString` (WINDOWS-HANDOFF item 31), in
`contracts/shared-rules.json` →
`specialNames.renameFolder.linkRewriting.cases`:

    given    [q](All%20Tasks/Quiz.md)
    oldName  All Tasks
    newName  Q&A
    expect   [q](Q&A/Quiz.md)

**This should be GREEN on the mac the day you read it** — said plainly so a
passing case is not mistaken for one that needs work. `spelled(_:likeThe:in:)`
already calls `percentEncoded` in both of its branches, and `Q&A` contains
nothing outside `charactersThatSurviveQuartzUndecoded`, so the mac answers
`[q](Q&A/Quiz.md)` today. If it does not, the divergence is real and worth
knowing about.

**Why it is worth a case at all.** `Spelled` has two reasons to escape: the new
name would break a Markdown destination, or the OLD segment arrived
percent-encoded. Not one of the original eleven reaches the second: eight take
the first (their new names carry a space or a bracket), and the other three
escape nothing at all — `Assignments` and `Café` need nothing, and the
wikilink case is not a Markdown link. So the second branch was covered by
nothing. On Windows it still called `Uri.EscapeDataString`, and a fix applied to
the first line alone would have left `Q&A` spelled `Q%26A` with all eleven cases
still green. The case is what makes the second branch visible.

~~**One is outstanding, proposed 2026-09-06: a folder rename breaks Markdown
links when the new name contains a space — on BOTH platforms.**~~
**✅ Done 2026-09-06 (mac).** Implemented here, with the five proposed cases
plus six more, in `contracts/shared-rules.json` →
`specialNames.renameFolder.linkRewriting`. The ledger entry below — **"A folder
rename to a name with a space broke every Markdown link into it"** — carries
the reasoning, INCLUDING the part Windows now owes: the escaping SET was
measured against Quartz and `Uri.EscapeDataString` turned out to be wrong, so
three of the eleven cases failed on Windows — one change fixed all three, on
2026-09-07 (see the awareness entry below). That is the mechanism working
rather than damage; the reasoning is in `WINDOWS-HANDOFF.md`.

The `specialFoldersHelp` pair below went the same way on the same day.

The two cases proposed for v1.1.0 were cleared on 2026-08-20 — one implemented,
three retired — and the reasoning for each is in the ledger below under "The
teacher-made-link case is implemented, and the three setup cases are retired".

The mechanism, in one paragraph. `Plantoir --write-contracts` runs on the mac,
so the Windows side cannot regenerate the derived halves of
[`contracts/`](contracts/README.md) — but the **authored** halves (`scenarios`,
`nearMisses`, `promptHistory`, and the case lists in the other files) survive
regeneration untouched. So a behaviour invented on Windows can be proposed as
a case, and **the mac suite then fails until the mac implements it.** That is
the mechanism working, not a break: verified on purpose by adding a case for
an event the mac has no support for, which failed naming the case and the
missing step rather than passing quietly.

When a case is proposed, add a line here naming it, so whoever meets the red
suite reads it as a request:

> - `contracts/assist-cases.json` → `scenarios` → **"<case name>"**, proposed
>   <date>. What it asks for, and why. Reference: `<Windows file>`.

Remove the line when the mac implements it, and mark the matching entry below
`✅ DONE` — the ledger keeps the history, this section keeps only what is
outstanding. (Striking the line through in place with a pointer to the ledger
entry does the same job and is what the last two mac sessions did; either is
fine. What is not fine is leaving a finished item looking pending, which is
the failure the v1.1.0 cut sheet above sat in for seventeen days.)

~~- `contracts/shared-rules.json` → `specialFoldersHelp` → `cases` →
  **"the curriculum folder is named even when the course never recorded one"**
  and **"a recorded name the course no longer has is not shown"**, both
  proposed 2026-09-06.~~ **✅ Done 2026-09-06 (mac).** Both cases pass here
  now; the mac suite is green on the whole `specialFoldersHelp` block, cases,
  rows, listing grammar and banned vocabulary, deserialised rather than
  retyped. The reasoning — including the two things the plan got wrong on the
  way — is in the ledger entry **"The folders sheet named a curriculum folder
  the course may not have"**.

- `contracts/shared-rules.json` → `gradedFolders` → **`choices`**, a whole new
  authored block with ten cases, proposed 2026-09-06. **The mac suite will not
  go red on its own for this** — nothing over there reads the key yet, which is
  the honest difference between proposing a case in a list a mac test already
  walks and proposing a new list. So this line is the only thing that will tell
  you it is here.

  Nine of the ten cases describe what the mac's own `nestedFolderNames`
  already does, written down so both apps can be tested against one rule
  instead of two implementations that happen to agree. **Two of them need
  something from the mac:**

  - **A SORT.** `"declared folders first, then what is on disk"` and `"the same
    folder name in two places is offered once"` pin an ORDER, and the mac's
    `FileManager.enumerator` returns children in whatever order the filesystem
    gives. Sorting each folder's children case-insensitively before walking
    them is the whole change, and it is worth having for its own sake: the list
    a teacher reads is otherwise in an order nothing promises and which can
    differ between two machines holding the same course.

    **The comparison is ORDINAL, case-insensitive** — `OrdinalIgnoreCase` in
    the C#, and the contract's `walk.order` says so. Worth naming, because the
    natural Swift reach is `localizedStandardCompare` (Finder order), and the
    two disagree the moment a course numbers its folders: ordinal puts
    `Unit 10` before `Unit 2`, Finder order puts `Unit 2` first. A contract
    case now pins it, so the suites disagree rather than the teachers.
    Finder order is arguably the nicer answer for a person reading a list, and
    if anyone wants it, it is a shared change to the contract and both apps —
    not something to reach for on one side because it looked more natural
    there.
  - **`"a folder the teacher removed from the course is not offered back"` is
    a real behaviour difference, and Windows took it deliberately** — see the
    ledger entry below.

  Reference: `windows-app/Plantoir.Core/Models/GradedFolderChoices.cs` and
  `windows-app/Plantoir.Tests/GradedFolderChoicesTests.cs`.

## Open — what the mac still owes

- **Nothing to implement, one thing to switch on: line endings are enforced
  now, and the enforcement reaches this clone only if hooks are enabled.**
  (Windows, 2026-09-08, branch `issue/gitattributes-line-endings`.) A session
  committed four files as CRLF with stray lone CRs — 7,672 insertions for 264
  lines of work, and `git blame` on `WINDOWS-HANDOFF.md` attributing all 6,655
  of its lines to one commit. Review caught it; nothing else would have.

  `.gitattributes` is new and does most of it: `* text=auto` plus an explicit
  `text` on the extensions that matter, so a file carrying a stray CR is
  normalised instead of being mistaken for binary and skipped. **It changes
  nothing anyone has checked out** — no `eol=` directives, so working trees
  keep whatever their platform gives them. Measured before writing it:
  `git ls-files --eol` said 13,091 tracked files were already LF in the index,
  138 binary, and exactly two not LF, both vendored Obsidian theme files, which
  are named one by one as `-text`. A wider `.obsidian/**` exclusion was tried
  first and rejected — it also caught four files that ARE LF, and made
  `git add --renormalize` stage their CRLF, which is the damage this is for.

  **The half `.gitattributes` cannot do, and why the mac has to opt in.** Git
  strips only the CR immediately before a newline, so a file written as
  CR CR LF still reaches the index with one CR per line — the exact shape that
  did the damage. `.githooks/pre-commit` now checks staged blobs for carriage
  returns and says so, without blocking. Hooks are not installed by cloning:
  run `git config core.hooksPath .githooks` on the mac if it has not been run
  there, and check with `git config --get core.hooksPath`. That request was
  already on this list for the publishing warning; it now carries this too.

- **One caption to adopt: the Marks wording is now a contract case, and the
  mac's TITLE won.** (Windows, 2026-09-08, branch
  `issue/marks-wording-contract`.) The title at `CourseSettingsView.swift:185`
  and `NewCourseWizardView.swift:932` already matches, so the change is the
  caption at `:190` / `:937`. **Nothing on the mac is red** — no mac test names
  `gradedFolders.wording` — so this can wait for a convenient session. Read the
  entry in **"Contract cases waiting on the mac"** above first: one of the three
  changes is a correction rather than a preference (the mac's caption says
  "add" and "remove" of a control that only ticks), and one is a deliberate
  mixed state that must not be tidied up.

- **One sentence to adopt: the Course Settings tip is now a contract case, and
  the mac's copy of it is the one that changes.** (Windows, 2026-09-07, branch
  `issue/course-settings-tip-contract`, handoff item 37.) Russell chose
  Windows' wording, widened to say "folders and files" because the caption sits
  under four lists of which two are file lists and both apps had promised only
  the folder half. **Nothing on the mac is red** — no mac test pins the key —
  so this is small and it can wait for a convenient session: move the literal
  at `CourseSettingsView.swift:176` into a `SpecialNames` constant, take the
  contract's `specialNames.contentStructureTip.message`, and assert it in
  `testSpecialNamesSentencesMatchContract`. The full reasoning, the rejected
  alternatives, and two traps in mirroring the Windows tests are in **"Contract
  cases waiting on the mac"** above; this line exists so the work is on the
  list rather than only in prose.

- **Two small things, and a decision you may want to copy: the shared Python
  tests now run on Windows too, and one of them was broken there.** (Windows +
  shared, 2026-09-07, branch `issue/36-publishing-gate`, handoff item 36.)

  **What the mac owes is two lines of housekeeping, not a feature.**

  1. **Run `git config core.hooksPath .githooks` on the mac clone** if it has
     not been run there. A new `.githooks/pre-commit` warns — never blocks —
     when a commit touches the publishing path, naming `./verify-deploy.sh` as
     the only automated check that really publishes. Hooks are not installed by
     cloning, so it reaches this side only by that opt-in; check with
     `git config --get core.hooksPath`.
  2. **Nothing else.** `verify.sh` already runs all fifteen shared
     `scripts/test_*.py` files, so the mac's coverage is unchanged.

  **What changed in shared code**, so the mac is not surprised by the diff:
  `scripts/test_baked_modules.py` read the Dockerfile and the product `.py`
  sources with `read_text()` — no encoding — which takes the LOCALE encoding.
  On macOS that is UTF-8 and it has always passed; on Windows it is cp1252 and
  it dies with `UnicodeDecodeError: 'charmap' codec can't decode byte 0x9d`.
  Now `read_text(encoding="utf-8")` in both places. No behaviour change on the
  mac; it simply stops being luck.

  **The measurement worth having**, because it is about shared files and the
  mac cannot take it: all fifteen `scripts/test_*.py` pass on Windows (156
  tests, ~8 s through `dotnet test`; Lenovo 20QES70500, Intel Core i5-8365U @
  1.60 GHz, 16 GB). Windows had been running **none** of them — `verify.sh` is
  bash and does not run there — so a shared file could be broken from that
  machine with every gate on it green. `PythonToolchainTests` now runs them
  there, discovering `scripts/test_*.py` rather than listing the files, so a
  test file ADDED ON THE MAC starts running on Windows with no Windows change.
  Worth knowing when adding one: if it needs Docker or POSIX it will fail
  there, and the fix is an entry in that class's `NotRunHere` map with a
  reason, not deletion.

  **The two environment variables are load-bearing and cost an hour to learn.**
  The runner sets `PYTHONUTF8=1` and `PYTHONIOENCODING=utf-8`, which is exactly
  what `deploy.ps1:117-118`, `preview.ps1:185-186` and `setup.ps1:158-159`
  already set. Without them, `build_site.py`'s emoji `print` ("📝 Added
  exclusion note to …", `build_site.py:1932`) raises `UnicodeEncodeError` on a
  cp1252 console — and the handler prints an emoji too, raises again, and the
  exception escapes into `preflight_update_course_config`. It reads exactly
  like a real fault in the build and is not one: a teacher never meets it,
  because the launchers set the variables first. **This was nearly written up
  as a product bug**; it is recorded here so the mac does not "fix"
  `build_site.py` for a fault that does not exist.

  **A decision the mac may want to copy, or may reasonably not.** Item 36 asked
  what should run `verify-deploy.ps1`, and the same question is open here for
  `verify-deploy.sh`, which is wired into nothing on this side either. Windows'
  answer: leave it opt-in (it makes real, globally unique sites that nothing
  deletes), warn at commit time, and require a run with **nothing skipped** at
  a release cut — `RELEASING.md` step 2 now names both scripts, so that part
  already binds the mac. A stamp-file design that would have reddened the unit
  suite until the verifier was re-run was rejected on measurements; they are in
  `WINDOWS-HANDOFF.md` item 36, and the headline is that the publishing files
  changed on 16 of 22 active days over 60 days, so the suite would have been
  red three days in four. **The mac is not asked to build anything here** —
  only to know that `RELEASING.md` now expects `./verify-deploy.sh` with
  nothing skipped for a release that changes publishing.

- **One check, five minutes: does `deploy.sh` validate the Netlify token
  before running `deploy.py`?** (Windows, 2026-09-07, branch
  `issue/35-first-run-ui-checks`, handoff item 35.) Windows' `deploy.ps1`
  does — `Test-TokenValid` against `https://api.netlify.com/api/v1/user`
  before the Python starts — and that single fact is what makes the
  new-site dialog un-automatable there: a fake token never reaches the
  site-naming prompt, so it raises "Connect to Netlify" instead. Combined
  with the credential store not being redirected by a test's state
  directory, a test would either stop at the token dialog or **publish a
  real website**, depending on what the machine happened to have saved. So
  Windows made that path a hand-driven check with a written procedure
  (`documentation/12-windows-app.md`) rather than a test.

  **What the mac owes is only the check, not the work**, and it is really
  two questions, because token validation alone does not settle it: (a) does
  `deploy.sh` validate the token before running `deploy.py`, and (b) **can a
  test put a known-bad token into the Keychain for its own run without
  touching the teacher's?** If the answer to (b) is no — and on Windows it
  is no, `deploy.ps1`'s Credential Manager target is hardcoded — then the
  path is un-automatable whatever (a) says, because a machine with a real
  token saved would publish a live site. An earlier version of this entry
  drew the opposite inference from (a) alone; it does not follow. Say what
  you find either way, because "nobody checked" is how both sides discover
  the same thing separately.

- **Two small decisions from Windows item 30, both for the mac to make**
  (Windows, 2026-09-07, branch `issue/30-polish-delete-crumbs-rename`).
  (a) The backup pane's sentence: Windows says "Restoring puts {code} back to
  exactly this moment — the current version is archived first, and the
  backup is kept."; the mac's advertises the delete and omits the
  reassurance. The reassurance is the better half; converge on it from both
  sides at once, or say which wins. (b) The picker's breadcrumbs: a plain
  click walks nowhere, as on the main bar (item 6's decision), though on a
  PICKER walking up the tree is the obvious reading. If that is wanted it is a
  change to `workingFolderPathBar` for both platforms, not one side's
  shortcut. Neither blocks anything; both are wording-and-behaviour choices a
  teacher can see, so they are the mac's call.

- **Turning the skeleton toggle OFF leaves the skeleton's folders in the mac's
  structure editor, and Windows now puts the generic defaults back — decide
  which, and make it a contract case** (Windows, 2026-09-07, branch
  `issue/25-wizard-skeleton-question`). **Small, and it is a teacher-visible
  difference from today.**

  On the mac, `adoptSkeletonStructure()` runs on every code change and
  replaces the four lists (`NewCourseWizardView.swift` line 603, the only
  caller); `startsFromSkeleton` is read only when the configuration is built
  (lines 1285 and 1361), and the lists written are the editor's either way.
  So a teacher who types SNC4M, sees "Concepts, Investigations, Exercises…"
  appear, and turns the toggle off is shown — and gets — the science
  skeleton's folders with none of its pages, while the file says
  `use_skeleton: false`. Russell's decision for Windows (brief
  for item 25, 2026-09-06) was that the editor must show what will actually
  be created, in both directions: OFF restores the factory or LCS defaults,
  ON adopts again. `RestoreGenericStructure` in `NewCourseDialog.cs` does it,
  list by list against a snapshot of what the adoption put there, so a list
  the teacher has edited since — including one the LCS switch rewrote — is
  left exactly as it is, and only the untouched lists go back.

  What is asked: either copy the restore (the Toggle has no `onChange`
  today; add one that, when the toggle goes off, puts the defaults back for
  each list still equal to what `adoptSkeletonStructure()` set, LCS variant
  included), or record that leaving the folders is what the mac means and
  say why. Then a case under a new
  `file-formats.json` → `wizardAnswerKeys` rule, or `shared-rules.json`, so
  the two wizards cannot drift again. Windows follows whichever is chosen.

- **Two sentences in `contracts/shared-rules.json` now say Windows still owes
  the refusal case, and Windows no longer does** (Windows, 2026-09-07, branch
  `issue/33-repair-refused-folder-in-the-way`). **A regeneration and two
  edited strings; nothing behavioural.**

  `siteHealth.repair.reportedOncePerFinding.howToRunACase` ends `("refused" is
  refusedWhenSomethingIsInTheWay, which the mac has and Windows still owes)`,
  and `knownLimit` in the same entry says `Windows has no refusal case yet
  (WINDOWS-HANDOFF.md item 33) … It stops being a Windows limit the day item
  33 lands`. Both were true when written and are false now: Windows answers
  `Refused`, says the contract's sentence, and writes `folder problem not
  repaired` — see the ledger entry below. The contract is generated on the mac
  and never hand-edited, so the correction has to come from
  `SiteHealthContract.swift` (or wherever those two strings are authored) and
  `Plantoir --write-contracts`. Suggested wording: drop the parenthesis from
  `howToRunACase`, and in `knownLimit` say the refusal case escapes the limit
  on BOTH platforms because its sentence names the section folder. Windows'
  suite is not red on the stale text — nothing pins prose — which is exactly
  why it needs saying here rather than being left to be noticed.

  Two source comments say the same stale thing and need no regeneration:
  `mac-app/Tests/QuartzTeachersTests/SiteHealthContractTests.swift` (around
  line 143: "Windows answers `Failed` here today with the generic … so this is
  the sentence they adopt") and `mac-app/QuartzTeachers/Models/SiteHealthRepair.swift`
  (around line 367: "Windows has no blocked case yet, so over there it reads
  namelessly too until `WINDOWS-HANDOFF.md` item 33 lands"). Fix them in the
  same pass, or the contract will be right and the code beside it wrong.

- **The Marks checklist offers a folder the teacher has REMOVED from the
  course** (found on Windows 2026-09-06, branch
  `issue/26-marks-checklist-nested-folders`). **Small, and it only bites
  because the mac walks the disk.**

  `CourseSettingsView.swift`'s `nestedFolderNames` walks the course folder and
  offers what it finds. It does not consult `excluded_items`, so a folder the
  teacher has just taken out of Shared folders — which they were told, in the
  confirmation they had to read, "will take it out of your course's marks
  pool" — is still on disk, and comes straight back into the Marks list on the
  next redraw, unticked. Tick it and `graded_folders` names a folder
  `excluded_items` tells the build to skip: a non-empty pool matching nothing
  the build will publish, so nothing counts for marks while the settings claim
  something does. The mac already keeps this promise on the way OUT —
  `dropFromMarksPool` takes a removed folder out of the pool for exactly that
  reason — and this is the same hole arriving back in through the walk.

  **One thing an earlier draft of this entry said is not true**, and is
  corrected here rather than quietly deleted, because a wrong reason gets
  acted on: such a pool does NOT suppress the `noGradedFolders` finding.
  `_has_graded_folders` in `build_site.py` walks the MERGED tree, so a pool
  matching nothing published answers false and `site_health.py` raises the
  finding exactly as it would for an empty pool. The reason to filter is the
  promise in the dialog, which is reason enough. (Windows' own
  `DropFromMarksPool` comment carried the same wrong clause, inherited from
  GUI-IMPROVEMENTS row 380, and has been corrected in place — that row
  itself is append-only history and is left as it stands.)

  Windows filters it. The rule is in the contract under
  `gradedFolders.choices.walk.excludedItems`: a name in `excluded_items` is
  neither offered nor walked into, matched EXACTLY (case included, the way
  `preflight_update_course_config` matches a Python set), and filtered only at
  the two levels the build's preflight scan actually discovers — the course
  folder's own children against `excluded_items.shared`, a section folder's
  children against `excluded_items.per_section`. Deliberately not at every
  depth: a nested `Portfolios/Tasks` still counts when a top-level `Tasks` has
  been removed, because those are different folders and only one of them was
  removed.

  **Why Windows took a divergence rather than copying and writing it up.**
  Copying would have REGRESSED this side. Before the walk, the Windows
  checklist was literally `SharedFolders.Concat(PerSectionFolders)`, so a
  removed folder left the Marks list in the same gesture; adding the walk
  without the filter would have introduced the reappearing folder here as a
  new bug of the change's own making. Against that, the divergence costs
  nothing a coverage map can see — `CountsForMarks` is untouched, and a
  ticked-but-excluded folder counts nothing on either platform, because the
  build never publishes it. What differs is only which names a teacher is
  OFFERED, and only for folders they have removed.

  Reference: `GradedFolderChoices.Walk` / `Excluded`, and the contract case
  `"a folder the teacher removed from the course is not offered back"`.

- **Two smaller things in the same area, neither of them introduced by
  Windows, both inherited by both apps** (found while porting the walk,
  2026-09-06). Recorded so they are not re-found a third time; neither is
  urgent and neither is Windows-specific.

  - Removing a shared folder drops that NAME from the marks pool, but not the
    graded folders nested inside it. Remove `Portfolios` while the pool holds
    `Tasks` (found at `Portfolios/Tasks`) and the pool keeps naming a folder
    whose parent has left the site.
  - A pool entry whose folder has since been deleted on disk still counts
    toward the "last folder that counts for marks" floor, so the floor can
    refuse a removal on the strength of a folder that is not there.

- **A recommendation rather than a defect: the "Folders Plantoir uses" sheet
  can under-report the marks folders, on both platforms.**
  `SpecialFoldersHelpView.gradedFolderNames` infers from `sharedFolders +
  perSectionFolders`, while `gradedFoldersBinding` infers from
  `gradedFolderChoices` — which includes the walked names. So a course that
  has never been asked can see `Tasks` ticked in the checklist and NOT listed
  in the sheet one section below it, until the first save makes the pool
  explicit. Windows now matches the mac exactly here on purpose
  (`SpecialFoldersHelp.cs` passes the top-level lists explicitly, with a
  comment saying why), because the sheet is handed a configuration with no
  course folder to walk and `specialFoldersHelp`'s own contract cases build
  their config from JSON alone. Fixing it means giving the sheet a directory,
  which changes a shared contract's shape — a decision for both platforms at
  once rather than one taken on the side that noticed.

- **`AppRulesContract.milestones()` leaves the example-course task out of the

- **`AppRulesContract.milestones()` leaves the example-course task out of the
  readout, so two shared markers were classified by nobody** (found 2026-09-06,
  branch `issue/29-windows-contract-case-lists`). **A one-line fix, and the
  smallest item here.**

  `mac-app/QuartzTeachers/Models/Assist/AppRulesContract.swift` writes eight
  milestone lists into `app-rules.json`; `TaskMilestones.swift` has nine.
  `exampleCourse` is the missing one, and it carries `"Example Course installed
  to"` and `"EXAMPLE_COURSE_CODE="` — both printed by `setup_course.py`, both
  shared, and both invisible to `testEveryMarkerIsClassified`, which walks the
  readout rather than the code it is a readout of.

  ```swift
  ("exampleCourse", TaskMilestones.exampleCourse),
  ```

  Add it to the `lists` array and run `Plantoir --write-contracts contracts`.
  **Windows is already ready for that**: the two markers were added to
  `markerOrigins.origins` on 2026-09-06 (see the awareness entry below), and
  `MilestoneContractTests`' parity map already answers `exampleCourse`, so the
  regeneration lands green rather than failing the Windows suite by name. The
  shared steps agree in order on both sides — checked by hand before writing
  this.

  **Worth taking the general lesson, not just the line.** A readout cannot fail
  when the code it reads changes — `contracts/README.md` says exactly that
  about the generated halves — and this is that rule biting the readout's own
  COMPLETENESS rather than its contents. A test that walks
  `TaskMilestones.allLists` and asserts every list appears in the readout would
  have caught it, and is worth more than the one-line fix.

- **The generator should emit the tool-schema DEPARTURES beside the schemas,
  because the only record of them is a Swift comment** (found 2026-09-06 by
  wiring `toolSchemas` into the Windows gate, branch
  `issue/29-windows-contract-case-lists`). **Small, and it removes a copy
  rather than adding one.** Reference:
  `AssistSurfaceContractTests.AssertOnlyTheDeparturesWeHaveAgreed`.

  `AssistToolSurface.swift` names "two deliberate departures from the Windows
  schema": lists of page names reach the mac as ONE semicolon-separated string,
  because that client's schema has no arrays and a comma-separated list would
  cut "Unit 2, Day 3" in half; and the mac has no `preview` flag, because every
  change rebuilds there. Both are good decisions with their reasons written
  down — and written down **only in that doc comment**.

  So when the Windows suite started running `toolSchemas`, four parameters came
  up as type mismatches (`publish_pages.pages` and its three relatives: array
  here, string there) with nothing in the contract to say they were meant. The
  Windows test now carries the list, which makes it the SECOND home for a fact
  the contract cannot hold — `toolSchemas` is a generated key, so the departure
  cannot be written beside the schemas it applies to by hand.

  **What is asked:** have `Plantoir --write-contracts` emit the departures into
  the generated `toolSchemas` block — tool, parameter, each side's type, and
  the reason — from the same place the doc comment states them. The Windows
  test then reads them and deletes its copy. Until then the copy is asserted as
  an exact set, so a NEW departure fails on this side and a resolved one fails
  too, which is the best a second home can do.

  **Not proposed: making the two agree.** The mac's shape is forced by its
  client and the semicolon choice is reasoned; changing either app's schema is
  a routing change needing the suite re-run, and that is not what this branch
  is for.

- ~~**The two apps write a teacher's visibility flag DIFFERENTLY, and the
  contract only describes one of them**~~ ✅ Decided 2026-09-07: migration
  wins, the contract now says so, and the case is at the top of this file
  waiting on the mac. The two documentation files are corrected to the rule.
  The original entry follows. (found 2026-09-06 by wiring
  `pageVisibility.writingRules` into the Windows gate, branch
  `issue/29-windows-contract-case-lists`). **What is owed is a decision, and it
  is not this branch's to take** — both behaviours are deliberate and were
  written down as such, in different places, by different sessions.

  `contracts/file-formats.json` → `pageVisibility.writingRules[0]` says: *"A
  page written in the old spelling KEEPS it, inverted — publishing a `draft:`
  page writes `draft: false`, not `publish: true`,"* because *"rewriting the
  key would change a page they did not ask to have changed, and a course half
  in each spelling is harder to reason about than one consistently old."*

  **The mac does exactly that.** `AssistPageVisibility.setting(published:…)`
  asks `keyInUse` which spelling the page has, and writes that one, inverting
  the value when it is the old key.

  **Windows does the opposite, on purpose.** `PageFrontmatter.SetDraft` writes
  `publishForSection<N>` into the position where `draftSection<N>` sat and
  removes the old key. `GUI-IMPROVEMENTS.md` row 140 describes that as the
  intent — *"writes the new key in the old key's position so a migrated page
  shows a one-line diff rather than reordered frontmatter"* — with *"no flag
  day: legacy courses build exactly as before, and a page migrates the first
  time something edits it,"* which works because `build_site.py` and
  `patches/publish.ts` read both spellings.

  **Why it matters rather than being a tidy-up.** These are a teacher's own
  files, and a course does not stay on one machine: a page edited on Windows
  comes back to the mac migrated, and the mac then keeps the NEW key, so the
  file quietly converts the first time a Windows machine touches it. Nothing is
  broken by that — both spellings build identically (`build_site.py` and
  `patches/publish.ts` read both, and neither `SectionAdder` widens or narrows
  it) — but the contract asserts a property of the teacher's file that is not
  true of the product as shipped, and one of the two has to give.

  **`documentation/` has already taken a side, and it is not the contract's.**
  Found by grepping for the behaviour rather than trusting memory of where it
  is described, which is what rule 11 asks for and what my first pass here did
  not do:

  - `documentation/04-course-setup.md` — *"Plantoir rewrites a page's key only
    when something edits that page."*
  - `documentation/08-course-config-reference.md` — *"rewritten to `publish` the
    first time anything edits the page."*

  So the split is not contract-versus-row-140. It is **the contract and the mac
  code** on one side, and **row 140, both documentation files and the Windows
  code** on the other — and the documentation is false for the mac TODAY,
  whichever way this goes. If the contract wins, those two files change too.

  **Two smaller differences the decision should cover**, both found while
  writing the test:
  - Where a page carries BOTH spellings, Windows deletes the leftover legacy
    key; the mac leaves it.
  - Windows rewrites a legacy page whose value is already correct, purely to
    migrate the key — so `writingRules`' fourth rule, *"writing the value it
    already has changes nothing"*, holds here only for the new spelling. That
    rule exists because a no-op write still moves the modification time and the
    next build then believes the content changed. The publish path filters
    already-correct pages out before it gets there, but the unpublish path does
    not.

  **What the mac owes:** pick one, and say which.
  - *If the contract wins*, Windows changes `SetDraft` to keep the old key
    inverted, and row 140's migration paragraph gets a correction. The test is
    written and waiting:
    `FileFormatContractTests.TheOldSpellingIsKeptRatherThanMigrated`, currently
    `[Fact(Skip = …)]`. Un-skipping it is the whole change on this side.
  - *If migration wins*, `writingRules[0]` is rewritten to say so and the mac
    adopts it, which is the larger change of the two — it is the mac's
    behaviour that would move.

  **Not decided here**, deliberately: the branch this was found on wires
  contract lists into the Windows suite and changes no product behaviour, and
  guessing at a rule about teachers' files in a test-wiring commit is how a
  divergence becomes two divergences.

- **Windows' MCP server has drifted a dozen tools ahead of the mac's, and
  nothing was going to tell either side** (found 2026-09-06 by an audit asking
  whether the parity list was COMPLETE, not whether it was correct).
  `plantoir-mcp.exe` declares **37** tools; the mac's `AssistToolSurface`
  serves **32** (22 plus ten MCP-only, seven of them built on 2026-09-08 out
  of this very list). So the same question asked of Claude
  Code gets a different toolbox depending on the machine.

  **✅ ALL SIX BUILT 2026-09-08.** Russell asked for the whole product bucket
  ("build all six tools"), and each one is done with its own tests and write-up:
  `list_courses` (row 452), the `add_classes` pair (449), the
  `make_room_for_classes` pair (450), and `explain_publishing` with
  `back_up_course` (451). **What is left of the twelve-tool gap is what this
  sorting said should be left**: `read_timetable` and `list_recent_changes`,
  which are Windows-shaped by design, `sync_page_dates`, which needs a
  teacher's problem first, and the `plan_` twins that travel with their writes.
  The mac's MCP surface is 32 (22 shared plus ten MCP-only).

  **The shape Russell set for all six**, which is the part worth carrying
  forward: an MCP tool for Claude Code, plus a card phrasing so the app can
  reach it, with the phrasing offering everything the tool does. MCP-only
  constrains which client the MODEL is shown a tool on; it says nothing about
  what a teacher can ask for. A fixed phrasing is matched in code and never
  reaches a model, so it costs the router nothing.

  **✅ Sorted 2026-09-06** on `issue/mcp-tool-surface-divergence` — the twelve
  are gone through one at a time below, with the reasoning. **What is still
  owed is Russell's yes, and then the building.** Nothing was implemented:
  he was asked directly whether he wanted parity attempted and chose the
  decision document instead, so this entry stays OPEN on purpose rather than
  being marked done — the sorting is finished, the product is not.

  **Two of the four things this entry handed Windows were already done when it
  merged, 2026-09-07.** The sorting ran on a branch cut before
  `issue/29-windows-contract-case-lists` reached `dev`, so it could not see
  `AssistSurfaceContractTests` — which enumerates `PlantoirTools` by reflection
  and records `re_date_classes`' extra arguments as agreed departures. The
  paragraphs below are corrected in place rather than deleted, because the
  reasoning that was rejected on the way is still worth having. What is left
  for Windows is the rollover decision and the seventeen phrasings; what is
  left for the MAC is Russell's yes on the sorting, the one `check_section`
  phrasing, and the generator change Windows asked for in this same file.

  The twelve, verified by set difference rather than read off a list: exactly
  twelve Windows-only, **zero mac-only**, and **zero hits for any of the twelve
  names anywhere under `mac-app/QuartzTeachers` or `contracts/`** — true when
  it was measured on 2026-09-06, and SEVEN of them have since been built here —
  all six tools this entry sorted as the mac's, on 2026-09-08 — so the
  difference is five today —
  `add_classes`, `back_up_course`, `explain_publishing`, `list_courses`,
  `list_recent_changes`, `make_room_for_classes`, `plan_add_classes`,
  `plan_make_room_for_classes`, `plan_sync_page_dates`, `read_timetable`,
  `roll_over_section`, `sync_page_dates`.

  ### Why nothing caught it — the mechanism above was WRONG, twice

  This entry used to say Windows' `AssistCases_Tools_MatchesContract` "only
  checks that the CONTRACT's lists are a subset of what it serves". It does
  not. `Plantoir.Tests/ContractTests.cs:497-510` uses `Assert.Equal` on
  `HashSet`s, which is **set equality**, in both directions. Two things are
  actually true, and both are worse than a subset check:

  1. **That test pins a different class.** It compares the contract against
     `AssistAgent.ForTheLocalModel` and `AssistAgent.DeploysToStudents` — the
     IN-APP assistant — while the 37 live in `Plantoir.Mcp.PlantoirTools`. The
     `mcpOnly` third of it compares the contract against a **hardcoded
     three-name list written inline in the test**, never against
     `PlantoirTools` at all.
  2. **Nothing on either platform enumerated the 37 — true when this was
     written, and Windows fixed it hours later.** The audit ran on a branch cut
     before `issue/29-windows-contract-case-lists` reached `dev`, and reported
     `grep toolSchemas windows-app/Plantoir.Tests` → 0 hits. Windows' new
     `AssistSurfaceContractTests` reads `PlantoirTools` by REFLECTION, pins the
     twelve extras by name in both directions, and reads `toolSchemas` for both
     surfaces including argument names and types. What remains true is the
     first half: `AssistCases_Tools_MatchesContract` still pins `AssistAgent`,
     and no MAC test knows `PlantoirTools.cs` exists — nor should one, see
     below.

  **The fix this entry PRESCRIBED was also wrong, and is the reason to read
  the next paragraph before acting.** It said to "put the survivors in
  `assist-cases.json` → `toolSchemas` so the gap becomes a test failure".
  `toolSchemas` is GENERATED — `AssistContract.generatedCaseKeys` is
  `["cardPhrasings", "tools", "toolSchemas"]`, overwritten wholesale by
  `Plantoir --write-contracts` — so nothing can be hand-added to it, and
  nothing on Windows reads it anyway. The real order is decide → write Swift →
  regenerate.

  ### The drift detector that would make this stick — BUILT, on the other side

  **Windows built it, and their shape is better than the one proposed here.**
  `AssistSurfaceContractTests.TheExtraToolsThisServerOffersAreTheOnesWeKnowAbout`
  reflects over `PlantoirTools` and holds the twelve extras as a NAMED list —
  their own comment says why named rather than counted: "a count stays at
  twelve when one tool is added and another adopted into the contract, and it
  cannot tell the reader WHICH". It fails on an unrecorded addition AND on a
  listed name the contract has since adopted.

  Rejected on the way: **a mac test that reads
  `windows-app/Plantoir.Mcp/PlantoirTools.cs` and regexes out the
  `[McpServerTool(Name = "…")]` names.** It is feasible —
  `AssistContractTests.readContract` already finds the repository root from
  `#filePath`, so a mac test can read anything in the tree — and it was the
  first design. Two things killed it. An attribute reformatted across two
  lines makes the regex find FEWER names, and fewer names all of which are
  accounted for is a **false green**: the one failure mode a drift detector
  must not have. And it couples the mac gate to Windows source rather than to
  data, which is not how anything else here crosses the gap.

  **WITHDRAWN — what this entry was going to propose instead.** An AUTHORED
  `assist-cases.json` key, `mcpToolNames`, listing every name the MCP surface
  is agreed to carry; Windows asserting its 37 against it, the mac asserting
  its 25 plus a recorded "not served here, and why" list against the same one.
  Authored keys do survive `--write-contracts`, so it would have worked. It is
  not needed: reflection on the Windows side gets the complete list from the
  compiler, with no new contract key and no second home for the list to drift
  in. Recorded because it was reasoned about, and because the general lesson
  outlived it — **enumerate a platform's surface ON that platform, and cross
  the gap with the RESULT** — which is also why no mac test should learn to
  read `PlantoirTools.cs`.

  What is still NOT in any contract is the sorting below, and that stays
  deliberate: its "and why" half is an unapproved product decision, and
  committing it would make that decision the acceptance list both suites run.
  Windows' list carries the twelve names with no verdict attached, which is
  exactly the right amount to pin before Russell has chosen.

  ### The twelve, sorted

  Four buckets rather than three. The brief asked for product / Windows-shaped
  / already-covered-under-another-name, and a fourth was needed because
  `sync_page_dates` turned out to need a teacher's problem before it needs a
  decision, which is a different answer from either "build it" or "never".

  **"Already covered under another name" is NOT empty, though the first draft
  of this entry said it was.** `add_next_class` is the one-page case of
  `add_classes` AND — through a `duplicate` key on the same call — the
  one-class case of `make_room_for_classes`; both ENGINES are already called
  from `AssistToolRunner`. So two of the six in the product bucket are
  widenings of something that ships, not new features, and that is the single
  most useful correction in this entry.

  **Do not read "widening" as "add a bigger number", which is how this was
  first written.** `duplicate` is on NO published schema — `AssistToolSurface`
  declares `course` and `section` for `add_next_class` and nothing else, and
  `contracts/assist-cases.json` carries `duplicate` only under `cardPhrasings`.
  The sole supplier is the hardcoded card sentence at
  `AssistCardCommand.swift:85`, so no local model and no MCP client can reach
  that path at all. `ClassInsertionPlanner` is wired up; the ROUTE to it is one
  typed sentence. What the mac needs is a schema argument, and for
  `make_room_for_classes` an MCP route that does not exist yet — still far less
  than an engine, but more than a count.

  **PRODUCT — belongs on the mac. In this order.**

  1. **`list_courses`** — ✅ **BUILT 2026-09-08** (`GUI-IMPROVEMENTS.md` row
     452). MCP-only as judged here, plus two phrasings matched in code — "what
     courses do I have?" and "list my courses" — so a teacher can ask without
     the model being shown a tool. The reasoning that came out of building it,
     and which applies to the rest of this list: MCP-only constrains which
     client the MODEL sees a tool on, and says nothing about what the app can
     do. The original entry follows.

     MCP-only, and the cheapest real gain of the twelve.
     `Plantoir --mcp-stdio <working-folder>` is scoped to a WORKING FOLDER,
     which routinely holds several courses. The server answers only
     `initialize`, `tools/list` and `tools/call` — no `resources/list`, no
     `instructions` — and every other tool takes `course` as a required
     argument. The LOCAL model learns the course from
     `AssistAgent.systemPrompt(course:section:)`; a Claude Code session has no
     such thing. It is not that the information is unreachable — that client
     has file tools and can read `courses/` itself — but that nothing on the
     tool surface offers it, so the first thing it does is guess or read raw
     folders. MCP-only means the local list is untouched, so this is **not a
     routing change** and needs no hand measurement.

     **Consider the cheaper answer first, which Windows already has and the mac
     does not:** `plantoir-mcp --course <CODE>` (`Plantoir.Mcp/Program.cs:21`)
     locks a session to one course, and their own comment says why — "a lock is
     a stronger guarantee than an instruction in a prompt the model might drift
     from". The mac's `--mcp-stdio` takes a folder and nothing else. A
     `--course` argument costs no tool slot and no routing at all, and answers
     the common case (a teacher opening an assistant from one course's menu).
     The two are complements, not alternatives: the lock answers "which course
     is this about", `list_courses` answers "which courses are there".

  2. **`roll_over_section`** — ✅ **DECIDED 2026-09-08: ASK.** A rollover asks
     the teacher whether this should be a new website or the same one as last
     year; and it does NOT hide pages that were visible last year, because
     re-dating moves dates and hiding is a separate act. The sentence has to be
     written in `contracts/` first, the mac has no `ReleaseSite` to call at
     all, and the card phrasing must move on both platforms or the decision
     changes nothing a teacher meets. Reasoning in `TODO.md`. The original
     entry, which is what the decision was taken against, follows.

     The one that is a DEFECT before it is a feature,
     and it is a defect **on both platforms**: "roll this section over to a new
     year" is matched in code on each and routed to `re_date_classes`, which
     cuts the section loose from its published site on neither, so the first
     publish afterwards overwrites last year's website. Written up in full,
     with three options, in `TODO.md` → "A rolled-over section publishes over
     last year's website". It is a product decision rather than a missing
     tool, which is why it is there and not here.

  3. **`plan_add_classes` / `add_classes`** — ✅ **BUILT 2026-09-08**
     (`GUI-IMPROVEMENTS.md` row 453). Smaller even than this entry says: the
     capability already shipped behind the "add five more days to Unit 4"
     phrasing, so only the published door was missing. The original entry
     follows.

     Smaller than it looks, and the
     first draft of this entry got it wrong in a way worth recording.
     `PlaceholderClassPlanner` (340 lines) lays down a unit's worth of class
     pages on the days the section actually meets, skipping days already taken
     — and it is **already wired to the assistant**: `add_next_class` calls
     `PlaceholderClassPlanner.apply` (`AssistToolRunner.swift:2310`) with a
     count of one. So this is not "build a feature", nor even "wrap an engine";
     it is **let the existing arm take a count**, plus a unit and a first day,
     under a name of its own. Today "add seven days to the next unit" has no
     assistant route on the mac; "add the next class" has had one all along.

     (Neither planner has a GUI sheet. An earlier draft of this entry said both
     did — checked and false: nothing under `mac-app/QuartzTeachers/Views/`
     mentions either one. They are reachable only through the assistant, which
     makes the assistant surface the ONLY way a teacher gets at them and raises
     the value of (3) and (4) rather than lowering it.)

  4. **`plan_make_room_for_classes` / `make_room_for_classes`** — ✅ **BUILT
     2026-09-08** (`GUI-IMPROVEMENTS.md` row 454), MCP-only as this entry asked,
     plus a parsed card phrasing. **One thing this entry got wrong, worth
     correcting rather than deleting:** it said what was missing is "a count
     above one, and the ability to name an arbitrary insertion point".
     `ClassInsertionPlanner.plan` has taken `unit`, `atDay` and `count` from the
     start — nothing was missing but a way to SAY them. The original entry
     follows.

     And this one
     is **already covered under another name, for the one-class case**.
     `ClassInsertionPlanner` (574 lines, its own contract in
     `contracts/class-planning.json`) is what runs when a teacher says
     "duplicate Unit 3, Day 2 as my next class" and the next day is already
     taken: `duplicateClassRequested` calls
     `ClassInsertionPlanner.plan(… count: 1)` and `.apply`
     (`AssistToolRunner.swift:2139, 1994`), renaming the later days, re-dating
     them onto real class days and rewriting every wikilink that pointed at a
     renamed page. All of the dangerous machinery already runs on the mac
     today. What is missing is a count above one, and the ability to name an
     arbitrary insertion point rather than "the day after the page I named".

     Ranked below (3) anyway, because widening it is where the danger is: the
     file's own comment calls this "the most dangerous thing here, because it
     renames pages the teacher's links point at", and the current route reaches
     it only through a sentence naming one specific page. If it is built,
     **MCP-only** — a person is reading every step there. Never the local list.

  5. **`back_up_course`** — ✅ **BUILT 2026-09-08** (`GUI-IMPROVEMENTS.md` row
     455). The original entry follows.

     MCP-only, and mechanically the smallest of all: it
     wraps `CourseArchiver.backUpCourse`, which exists. A LOCAL tool would be
     redundant, because `AssistToolRunner.backUpOnceForThisConversation`
     already saves a copy before the assistant's first write. Windows' own
     description says why the tool exists anyway, and the reason survives the
     redundancy: *"Do this before any bulk editing of a course's files —
     **including edits you make directly rather than through these tools**"*.
     That is a Claude Code session about to edit Markdown with its OWN Write
     tool, which the automatic backup does not cover — `AssistMCPServer.serve`
     builds one `AssistToolRunner` for the process, so the automatic copy fires
     once per server session and only ahead of a tool write.

  6. **`explain_publishing`** — ✅ **BUILT 2026-09-08** (`GUI-IMPROVEMENTS.md`
     row 451), as a TOOL rather than the cheaper `instructions` field this entry
     suggested trying first: a paragraph sent at startup is read once by a
     session that may not need it, while a tool is there at the moment the
     question arises and can say "already explained" the second time. The
     original entry follows.

     MCP-only. The publish-versus-deploy distinction
     reaches the local model through `AssistAgent.systemPrompt`, whose own
     comment says the paragraph "is not padding … saying plainly that they are
     different is what stops 'publish tomorrow's class' turning into a live
     site". The mac's MCP server sends no `instructions` in its `initialize`
     result and has no such tool, so a Claude Code session driving it **never
     learns the two are different acts**. **Try the cheaper answer first:** the
     MCP `initialize` result carries an `instructions` field. One paragraph,
     said once, costs no tool slot and no routing. The tool's extra trick —
     only explaining once per section, then saying so — is worth having only if
     the `instructions` field turns out not to be read.

  **WINDOWS-SHAPED — deliberately not the mac's, with the reason.**

  7. **`read_timetable`** — it takes a school spreadsheet by PATH or by link.
     The mac deliberately puts that reading behind the schedule SHEET:
     `SectionScheduleSource` (902 lines) turns a file, a shared-sheet link or a
     paste into calendar days, and its own comment states the rule — *"The
     reading happens here, in Swift, and never in the assistant's model."*
     `SectionTimetable` then remembers the answer inside the course folder so
     nothing asks twice, and the assistant reads it back with
     `read_remembered_timetable`. There is no file-path argument anywhere on
     the mac's tool surface today, and adding one is a bigger decision than a
     tool. Windows needs the file because its MCP server drives a whole
     rollover from Claude Code; the mac's answer is "the teacher fills the
     schedule sheet once, and everything reads it from there". **Reconsider
     only if (2) is ever built as an end-to-end rollover over MCP.**

  8. **`list_recent_changes`** — answers a question neither mac client has to
     ask. Windows' own description says the history "is only kept while this
     conversation is open"; the mac's `AssistChangeHistory` is the same, and
     the local assistant SHOWS each change in the conversation it just had,
     while a Claude Code session has its own transcript of every call it made.

  **NEEDS A TEACHER'S PROBLEM BEFORE IT NEEDS A DECISION.**

  9. **`plan_sync_page_dates` / `sync_page_dates`** — the only pair of the
     twelve with **no mac engine at all** (zero hits for anything sync-dates
     shaped). It fixes "the class is in June but the concept page it links to
     is dated in November", one class at a time. Two things make it a question
     rather than a task. The mac's answer today is `re_date_classes`, which
     moves each class's linked pages with it across the whole section — a
     bigger hammer, but not obviously the wrong one. And **nothing on the mac
     reports the problem this fixes**: Windows' re-date plan surfaces date
     drift under "Worth looking at:" because `AssistWorkspace.ProblemsAfter`
     runs `DateAudit.Run`, and the mac's `SectionReDatePlanner` has no
     equivalent — `DateAudit` has zero hits under `mac-app/`. So on the mac
     this would be a fix for a problem nothing surfaces. **If it is wanted,
     the audit is the half to build first**, and it is useful with or without
     the fix.

  **BUNDLED, not separate decisions** — `plan_add_classes`,
  `plan_make_room_for_classes` and `plan_sync_page_dates` travel with their
  writes. The mac's convention (`AssistPlanMode`, pinned by
  `AssistPlanModeTests`) is that every write has a plan twin, so a `plan_` name
  is never its own call.

  ### One more divergence, found on the way and not in the original audit

  **`re_date_classes` exists on both sides with the same NAME and different
  PARAMETERS.** Windows takes `timetable, block, pages, meetings, firstDay,
  startYear` on top of `course` and `section` (`PlantoirTools.cs:938-951`); the
  mac takes `course` and `section` alone and reads the remembered timetable. `toolSchemas` is generated from the mac,
  so the contract records the mac's shape and nothing on either side compares
  Windows' actual parameters to it. **This is worse than a missing tool**: a
  missing tool is at least visible as missing, while a shared name with two
  shapes lets a client written against the contract send arguments one server
  silently ignores. **Answered on the Windows side while this was being
  written:** `AssistSurfaceContractTests.AssertOnlyTheDeparturesWeHaveAgreed`
  lists all six of the extra arguments as agreed departures, asserted as an
  exact set, so a seventh fails and a resolved one that stays listed fails too.
  What the mac still owes is the generator change Windows asked for in this
  same file — emit the departures beside the schemas, so their test can read
  them instead of holding a second copy.

  ### The `TEACHERS SAY:` phrasings have drifted five ways, mostly OURS

  Checked clause by clause, every `TEACHERS SAY:` list in `toolSchemas.mcp`
  against every `[Description]` in `PlantoirTools.cs`. **Five of the 25 shared
  tools differ, and four of the five are tools where Windows has no
  `TEACHERS SAY:` clause at all** — seventeen phrasings the mac shows the model
  and Windows shows it nowhere, in the MCP server or the in-app assistant:

  | Tool | Difference |
  |---|---|
  | `check_section` | Windows has four phrasings, the mac three. Windows added "what would students see in this section right now?" on 2026-08-17, two days after the mac wrote its three, and it never came back here. |
  | `add_next_class` | The mac has six phrasings. Windows has **no `TEACHERS SAY:` clause at all**. |
  | `plan_add_next_class` | The mac has three. Windows has none. |
  | `read_remembered_timetable` | The mac has four. Windows has none. |
  | `remember_timetable` | The mac has four. Windows has none. |

  This matters more than a documentation difference, and the reason is written
  into `AssistToolSurface` itself: the phrasings *"are what took routing from
  69% to 91%"*, so they are measured artifacts and a missing one is a routing
  change nobody chose. The rule for copying a Windows description is to keep
  the clause WHOLE, and `check_section` is the one place the mac did not.

  **Nothing is fixed here on either side**, because adding a phrasing IS a
  routing change and routing is measured by hand against a local
  `llama-server`, which an unattended session cannot do. The mac owes itself
  one phrasing; Windows owes itself seventeen, and item 41 tells them so.
  (An earlier draft of this entry claimed the `check_section` case was the only
  difference of the 25 — that was a script that only looked in one direction,
  and it is exactly the failure this whole entry is about.)

  Reference: `windows-app/Plantoir.Mcp/PlantoirTools.cs` (the 37, each an
  `[McpServerTool]`), `mac-app/QuartzTeachers/Models/Assist/AssistToolSurface.swift`.

  Stale counts corrected on the way past, both saying 23 where the surface is
  25: `documentation/09-mac-app.md` and `WINDOWS-HANDOFF.md`'s "compare against
  the contract" section. (This entry previously claimed the two stale counts
  were `CLAUDE.md` and `documentation/10-local-ai-assistant.md`; those two are
  right, and the two above were missed.) `AssistToolSurface.swift`'s own header
  said "twenty tools", "seven of the twenty" and "six `plan_` twins" against a
  measured 22, 9 and 7 — corrected, since stale counts in that file are exactly
  how the previous miscount happened.

- **A section rolled over to a new year publishes over LAST year's website, on
  both platforms** — found 2026-09-06 while sorting the entry above. It is a
  DECISION for Russell rather than a fix, and because it was found on the mac
  rather than handed over from Windows, the write-up and the three options live
  in **`TODO.md`** ("A rolled-over section publishes over last year's website").
  Listed here only so the sorting above does not point at nothing: item (2) of
  the product bucket is this. Windows' half is item 41 in `WINDOWS-HANDOFF.md`.

- **The folder-problem front end landed on Windows, and it found two defects in
  the mac's own repair** (Windows, 2026-09-06, branch
  `issue/windows-folder-problems-front-end`, `GUI-IMPROVEMENTS.md` row 420).
  Windows implemented `WINDOWS-HANDOFF.md` item 21 — the findings dialog, the
  Fix button, the two repairs, the outcome report and "Preview Again". Mostly a
  **know**; the two below are genuine **do**s for this side, both found by
  porting the mac's code line by line and asking what each branch answers.

  1. ~~**A DIRECTORY named `index.md` is reported to the teacher as ALREADY PUT
     RIGHT.**~~ — ✅ **Done 2026-09-07**, branch
     `issue/repair-index-md-directory`, `GUI-IMPROVEMENTS.md` row 426.
     `SiteHealthRepair.restoreIndex` asked `FileManager.fileExists(atPath:)`,
     which is TRUE for a directory, so it returned `.alreadyFine` — "That is
     already put right. Nothing needed changing." — about a section that still
     had no front page, so the build still produced no site and the publish
     still refused; the one dialog written to end silence said the problem was
     dealt with. `restoreMedia`, the function directly above it, got this
     right, with the
     `isDirectory:` form and a comment saying why. You were right, and the fix
     is yours as much as ours.

     **The mac took the better sentence you invited it to propose, so this
     comes back to you as work.** Windows returned `Failed`, which is the
     honest answer of the two that existed; the mac now REFUSES with a
     sentence of its own, touching nothing —
     `contracts/shared-rules.json` → `siteHealth.repair.refusedWhenSomethingIsInTheWay`,
     `expect: "refused"`. So `SiteHealthRepair.Result` needs a FOURTH answer on
     your side and
     `ADirectorySittingWhereTheFrontPageBelongsIsAFailureNotAnAlreadyFine`
     needs updating. The refusal also records a new trail event, `folder
     problem not repaired`, which `activityTrail.mustRecord` pins by equality
     — **your suite is red until you add it**, and that is the mechanism
     working. Both are written up as `WINDOWS-HANDOFF.md` item 33, with the
     rejected alternative (move the folder aside and write a proper front page
     — no: it relocates a folder that may hold their pages, without asking,
     and neither app can see inside it) and the reason the event is named for
     the outcome rather than for its cause.

  2. ~~**`repair(_:in:)` returns `[String: Result]`, keyed by check NAME, so two
     findings with the same name collapse.**~~ — ✅ **Done 2026-09-07**, branch
     `issue/repair-results-keyed-by-name`, `GUI-IMPROVEMENTS.md` row 427.
     Two sections each missing a front
     page are both repaired — the loop runs — but only the LAST result is
     reported. Section 1 restored and section 2 already fine therefore reads as
     "That is already put right", with `canRebuild: false` and no preview
     offered, for a repair that really did put a page back. **Unreachable from
     the app today** (a section view owns one runner, and
     `announce_or_stay_quiet` is called once per section), which is why it is
     listed second — but it is one line to make impossible and a paragraph to
     explain if left. Windows returns one entry per FINDING and de-duplicates
     the NAMES when building the sentence, so "Put the front page and the front
     page back." cannot occur either. Reference: `SiteHealthRepair.Repair`,
     test `TwoSectionsMissingAFrontPageDoNotCollapseIntoOneAnswer`.

     **The mac now returns `[Attempt]` — the same shape, arrived at second.**
     You were right on both counts, and this one you had already fixed, so the
     mac copied rather than invented. What came back the other way is the RULE
     as data: `contracts/shared-rules.json` →
     `siteHealth.repair.reportedOncePerFinding` carries two cases, a
     `howToRunACase` note, and the `expectResults` vocabulary, so the behaviour
     can be checked against one source instead of proved twice in parallel.
     **Nothing of yours goes red** — no list pins it by equality — so
     deserialising those two cases in place of
     `TwoSectionsMissingAFrontPageDoNotCollapseIntoOneAnswer` is a should, not a
     must; it is written up as `WINDOWS-HANDOFF.md` item 34. One stale comment
     is left for you rather than edited from this side: the `<remarks>` on
     `SiteHealthRepair.cs:241-250` still call the per-finding list "a deliberate
     divergence from the mac, whose dictionary is keyed by name", and it is no
     longer a divergence.

  **Two places Windows is deliberately BROADER than the mac, and the mac may
  want to match — a know rather than a do, but the second one is visible.**
  The mac hides the marker line by `hasPrefix` after trimming
  (`SiteHealthFinding.isMarkerLine`), so a marker glued to the tail of another
  line — which happens when a preceding partial line lacked its newline — is
  shown to the teacher as raw JSON. Windows hides on `Contains`. And the mac
  filters only at push, so a half-arrived payload RENDERS in the console until
  its newline turns up; Windows hides the line under construction too, because
  a pseudo console hands over whatever bytes are ready and that wait is a
  whole 150 ms flush. Both are rule 1 leaks on the mac, both are small, and
  neither is worth a release on its own.

  **What Windows rejected, so it is not re-proposed.** Showing the dialog when
  the runner FINISHES: `preview.ps1` does not exit while it is serving, so that
  is Stop-Preview time, hours later — and a section with no `index.md` 404s
  every request, so the server wait never completes either. Both were tried on
  the mac and written down (`SectionDetailView.swift:400-409`); Windows
  attaches to the runner's `HealthFindings` notification instead. Also
  rejected: showing on the FIRST finding to arrive. `site_health.py` prints its
  findings in one burst, so they land in one flush and the C# runner announces
  them one after another on the same stack — showing at once would put up a
  dialog naming one problem and then a second naming both. Windows posts the
  presentation to the dispatcher, so the whole flush is collected first.
  **The mac does not have this problem in practice**, and an earlier draft of
  this paragraph said flatly that it did: SwiftUI's `onChange(of:)` observes
  state at the next render, so two synchronous appends read as one change 0→2.
  `GUI-IMPROVEMENTS.md` row 366 is the evidence — a real run with two findings,
  watched, showing one dialog titled "2 things need your attention". Corrected
  here rather than quietly dropped, because a handoff that sends the other side
  after a non-defect costs them the same afternoon a real one would.

  **What is worth knowing is the shape underneath it**, which is not free:
  the mac keeps no record of which findings it has already SHOWN, so it is
  relying on the burst arriving in one flush. If a PTY read ever split it,
  `showHealthFindings` would hold `[F, G]` behind the dialog already showing
  `[F]` and F would be shown twice. One `contains` check would close it, and
  the same split is the thing Windows' own line buffering exists for — so this
  is a "reasoned from the code, not observed", said plainly.

  **The assistant surface had the same leak, and the mac should check its
  own.** `LauncherRunner.Capture` on Windows passed every output line straight
  to the progress reporter and into the 12-line tail the assistant reports
  back — so the raw `PLANTOIR_HEALTH:` JSON reached a teacher through the
  assistant, on a surface nobody had looked at. Fixed by lifting findings out
  of the output before it is narrated, and the sentences now follow the answer
  through the mac's own `SiteHealthFinding.appending` shape. **Worth checking
  on the mac**: `AssistSiteWork` calls `SiteHealthFinding.appending(to:from:)`
  with a `ScriptRunner`, whose transcript already drops the marker at push —
  but the mac's progress reporting is a different path from its transcript,
  and if anything there narrates raw lines the same leak is present. Windows
  also records `FolderProblemFound` from the MCP process, which the mac does
  not appear to: it matters more here than in the GUI, because a headless
  server leaves no console behind for the teacher to have seen.

  **The overnight run is covered too, and Windows solved it differently from
  the mac — this one is worth reading.** It was nearly shipped as a gap: on
  `dev` the Windows Task Scheduler wrapper had no build step at all, so no
  health check ran overnight and there was nothing to capture. Pointing the
  new machinery at it would have produced code that looked finished and
  reported nothing for ever. Once the branch carrying that build step was
  merged in, the capture was built.

  **The difference from the mac is the part to consider adopting.** The mac
  reads its findings out of the scheduled run's LOG FILE, and had to record
  the log's SIZE before the run because launchd opens it with `O_APPEND` and
  nothing truncates it — without the offset, last week's markers are re-found
  every night, the record is rewritten with stale findings for ever, and the
  "nothing wrong this time" branch becomes unreachable the moment one problem
  has ever been logged. Windows captures the build's output to a GUID-named
  file PER RUN and deletes it immediately afterwards, so that class of bug
  cannot arise: there is no accumulating log to take an offset into. If the
  mac ever revisits `recordFolderProblems`, a per-run capture removes the
  offset dance rather than making it more careful.

  Four decisions behind it, none obvious from the diff:

  - **The scan runs BEFORE the build-failure guard.** Since 2026-09-01 a
    section with no `index.md` exits non-zero from `--build-only`, and that is
    exactly the run whose findings the teacher most needs in the morning. A
    scan after the guard would say nothing about the one failure that explains
    itself. The exit code is saved into a variable the instant the build
    returns, because everything between it and the guard runs commands of its
    own.
  - **No JSON is parsed in PowerShell.** The wrapper copies matching lines
    verbatim with `Select-String -SimpleMatch`; the app parses them with the
    same parser a live build uses, so there is no second implementation to
    keep in step.
  - **A capture that cannot be set up still publishes.** Losing the findings
    is a pity; losing the publish is not acceptable, so the build falls back
    to running plainly.
  - **The record's filename comes from ONE function** used by both the
    generated wrapper and the reader. A mismatch there fails in the quietest
    way available — written faithfully every night, read never.

  **Run at the real thing, three times, because generated shell has no runner
  behind it** (Windows 11 Pro 26200, Windows PowerShell 5.1.26100, native
  runtime, course ICD2O section 1). The wrapper's capture block was extracted
  verbatim and executed against the real `preview.ps1`:

  1. `Media` renamed aside → build exited **0**, the record was written, and it
     held the real `mediaFolderMissing` marker line.
  2. `Media` AND `section1/index.md` aside → build exited **1**, and the record
     still held BOTH markers, `sectionIndexMissing` included. That is the case
     the whole ordering exists for: the finding that explains the failure is
     the one a scan placed after the guard would have thrown away.
  3. Both restored → build exited **0**, no markers, and the stale record from
     run 2 was **deleted**.

  Four things that could each only have failed at 6 a.m. were settled by
  running it: `Out-File -LiteralPath` does exist in 5.1; `$LASTEXITCODE` does
  carry the launcher's own code out through `*>&1 | Out-File`; `Set-Content
  -Encoding utf8` writes a UTF-8 **BOM** (`EF BB BF`) in 5.1, and
  `File.ReadAllLines` — the API the reader uses — strips it, verified by
  reading the real record back and checking the first character is `P` and not
  `U+FEFF`.

  **And it writes a trail line the mac does not.** Each finding read out of
  the record is noted as `folder problem found`, dated to when the RUN wrote
  the record rather than to the morning somebody opened the app. Nothing else
  records an overnight finding at all: the run happened with the app closed
  and the console it printed to is gone. **Proposed back to the mac** — the
  mac's `takeFolderProblems` returns findings to the view and notes nothing,
  so an overnight problem there is invisible to a problem report. Small, and
  `ActivityTrail.note` already takes a `moment`.

  **One divergence that is deliberate and visible, so decide rather than
  inherit it.** Windows forgets what it has shown when a new BUILD starts, so a
  problem that is still there is reported again by the next preview and again
  by the publish. The mac gets the same behaviour for free — its runner clears
  its findings on each run and `onChange` fires afresh — so this is parity
  rather than divergence; what is written down here is the REASON, because the
  first Windows cut kept a per-view "already shown" set and it silently ate the
  case that matters most. Preview reports a missing Media folder, the teacher
  presses OK and publishes anyway, and the publish's identical finding is the
  one carrying the sentence about what students can see. Suppressing it as
  "already shown" loses precisely the sentence the occasion exists for.
  "Show it once" means once per build, not once per view.

  **Run against the real toolchain, not only against fixtures** (Windows 11 Pro
  26200, native runtime, working folder `scheduled deploy test`, course ICD2O
  section 1). With `Media` renamed aside, `preview.ps1 ICD2O 1 --build-only`
  exited 0 and printed exactly one `PLANTOIR_HEALTH:` line — the real one, with
  real line endings — beside its `⚠️` sentence. With `Media` restored, the same
  build printed zero. That second half is the one worth having: a healthy
  course reporting nothing is what stops this feature from becoming a thing
  teachers dismiss by habit, and it is not something a fixture can prove.

  **A measurement, and the way it was WRONG, which is the more useful half.**
  Windows PowerShell 5.1.26100, Windows 11 Pro 26200. `$LASTEXITCODE` does
  survive a capture pipeline — an inner script exiting 7 yields 7 in the
  caller through `2>&1 | Tee-Object`, `$v = & script 2>&1`, and
  `*>&1 | Out-File`. That measurement was taken and believed, and it was
  measuring the wrong thing: the callee had no
  `$ErrorActionPreference = 'Stop'`, and every launcher here sets it on line
  2. Under `Stop`, merging a native command's stderr into the pipeline turns
  the first stderr LINE into a **terminating** `NativeCommandError` that
  propagates out of the callee and kills its caller — measured: the piped
  callee died at its first stderr line and took the caller with it, where the
  same callee run plainly finished and returned 5. So an overnight deploy
  would have published nothing and said nothing the first time npm wrote to
  stderr. Caught by an adversarial review of the finished code, not by the
  measurement, and this repo already lists it as a platform lesson.

  **If the mac ever captures a launcher's output for the same purpose, the
  shape to copy is a CHILD PROCESS with OS-level redirection**, not a shell
  pipeline — on Windows that is `Start-Process
  -RedirectStandardOutput/-RedirectStandardError`, whose `ExitCode` also
  removes any dependence on a shell variable surviving. And its arguments go
  as ONE STRING: an argument array is joined with spaces and quoted not at
  all, so a working folder whose name contains a space is split at it. The
  first fixture used a space-free temp path and passed; the real folder is
  called "scheduled deploy test".

  Reference: `windows-app/Plantoir.Core/Models/SiteHealthRepair.cs`,
  `windows-app/Plantoir/Views/FolderProblemsDialog.cs`,
  `windows-app/Plantoir/Views/SectionDetailView.xaml.cs` (the "Folder problems"
  section), `windows-app/Plantoir.Core/Scripting/TranscriptBuilder.cs`;
  tests `SiteHealthRepairTests.cs`, `TranscriptHealthFilterTests.cs`.

- **Windows now has the exclusions AND the protection model, and three things
  come back to the mac** (Windows, 2026-08-25, branch
  `issue/windows-special-folders-parity`, `GUI-IMPROVEMENTS.md` row 385).
  Windows implemented handoff items 11 and 12: `excluded_items`,
  `graded_folders` and `curriculum_folder` in `CourseConfiguration.cs`, the
  `ItemProtection` model in the list editors and the marks checklist, a Marks
  section in Course Settings (which this app never had), and the wizard's marks
  control. Mostly a **know, not a do** — but three items below are genuine
  questions for this side.

  **The one finding worth the mac's attention: the two pieces could not be
  shipped separately, and an adversarial review is what caught it.** Item 11
  (exclusions) and item 12 (protection) read as independent pieces of work, and
  Windows implemented item 11 first. That was wrong, and quietly so. Before
  `excluded_items` existed, a Windows teacher who removed `All Classes` got it
  back at the next preview, because `preflight_update_course_config`
  rediscovers folders — the missing protection model was survivable. The moment
  the app writes `excluded_items`, row 377 makes that key AUTHORITATIVE, the
  folder never comes back, and the next-class button and the schedule write
  into a folder that no longer publishes. Same for the resolved curriculum
  folder (the map silently stops building) and a section's `index.md` (the
  section cannot be published at all). **Item 11 without item 12 turns a
  recoverable gap into an unrecoverable one**, and nothing in either item says
  so. Worth a line in `WINDOWS-HANDOFF.md` if anyone ever ports these
  separately again.

  **1. The Course Settings tip sentence is contract-pinned on NEITHER
  platform, and now the two apps word the same rule differently.** Row 375 says
  the mac "amended Course Settings tip callout to except removed names". That
  is a sentence a teacher READS, so by CLAUDE.md rule 2 it belongs in
  `contracts/`; `grep -rn "added to your site automatically" contracts/`
  returns nothing. Windows therefore wrote its own — "…The exception is
  anything you remove here: it stays off your site, even if you make it again
  in Obsidian, until you add it back on this page." **No case has been
  proposed**, deliberately: proposing one would redden the mac suite over
  wording the mac already ships, and choosing WHICH sentence becomes the
  contract is the mac's call. If the mac agrees it belongs there, add it under
  `specialNames` and Windows will take the mac's wording verbatim.

  **✅ Resolved 2026-09-07 — but not the way this paragraph expected, so read
  the top of this file rather than the sentence above.** Russell made the call
  in a Windows session and chose Windows' substance, widened to cover FILES as
  well as folders, which neither app's wording did. The case is now
  `specialNames.contentStructureTip` and the mac has a small adoption to make;
  the sentence, the reasoning, the two rejected alternatives and the two traps
  in mirroring the tests are in **"Contract cases waiting on the mac"** at the
  top of this file. The paragraph above stands as written because it is the
  honest record of what was true until today — but its last sentence is now
  wrong in both directions: a case HAS been proposed, and it is not the mac's
  wording Windows took.

  **2. `reconciledGradedFolders` on the MAC does not match the Python, and
  that is a finding rather than a question.** This entry originally asked which
  way the mac resolves a case collision. The answer, checked since: it resolves
  it neither way — `NewCourseWizardView.reconciledGradedFolders` is an exact
  `validChoices.contains(folder)` filter with no case-insensitive lookup at
  all, so a declared `tasks` against an actual `Tasks` is DROPPED. Both
  `setup_course.py:graded_folders_for` (via `actual_lookup`) and Windows's
  `GradedFolderRule.Reconciled` map it to the actual folder instead. So the mac
  silently narrows a pool the build would have kept. Windows also had a bug
  here — `Dictionary.TryAdd` keeps the FIRST match where the Python's dict
  comprehension keeps the LAST — and it is fixed. There is no contract case
  pinning any of this, which is why it survived on both sides; adding one is
  the mac's call, and Windows will run whatever it says.

  **3. Revert leaves a trail line for a removal that did not happen — and the
  mac has the identical shape.** Proven here: `Exclude("shared", "A")` then
  `DiscardChanges()` puts the config back, but `item excluded` is already on
  disk. Windows writes the note inside the editor's remove callback; the mac
  writes it inside `onRemove` and has a Revert too. So this is **parity, not a
  Windows regression** — but CLAUDE.md rule 5 says "a line describing what the
  feature used to do is worse than no line, because it will be believed", and a
  teacher who removes a folder, thinks better of it, and Reverts leaves a trail
  claiming they excluded it. The honest fix is to record on SAVE rather than on
  click, on both sides. Flagged rather than fixed unilaterally, because
  changing when the mac records an event is not a Windows decision.

  **4. Does the mac's wizard block on a coverage switch a teacher cannot
  reach?** Windows's `CourseConfiguration.CurriculumCoverageEnabled` was
  written as an identity function on the switch; the mac's takes five
  arguments. Restored to five here, because the wizard only CREATES that
  switch for a code with example content that includes curriculum, and only
  ENABLES it while pre-populate and curriculum pages are on — so on the
  commonest from-scratch path the ⓘ named a control that was not on the
  screen, and there was no way out inside the wizard. The mac's version has
  the gates, so the mac is probably fine; what is worth CHECKING is the second
  half. `NewCourseDialog.BuildConfiguration` writes
  `include_curriculum_coverage` from the RAW switch, so a from-scratch course
  is created with the map on while the protection rule says it is off — the
  wizard will let its curriculum folder go after a confirmation, and the build
  then reports `curriculumCoverageFoundNothing`. Windows chose that failure
  deliberately over a deadlock: the teacher is told something and has a way
  forward. **If the mac writes the same key the same way, it has the same
  tension**, and whether the honest fix is a reachable coverage switch on the
  from-scratch path is a product decision rather than a port detail. Not taken
  unilaterally here.

  **5. Two wizard inputs where Windows knowingly does less than the mac.**
  Both are written down rather than hidden, per rule 4. (a) The wizard passes
  `null` for the configured curriculum folder — the mac passes
  `ExampleContentCatalog.curriculumFolder(forCode:) ?? SkeletonCatalog...`,
  and this app has neither helper. So a skeleton family whose curriculum
  folder is called something without the word "curriculum" in it is protected
  on the mac and NOT on Windows. It protects too little; it never protects the
  wrong folder. (b) `JurisdictionForCode()` reads the PROVINCE DROPDOWN, where
  the mac derives it from the course CODE. Windows's choice keeps the switch's
  own label and the sentence naming it in agreement, which is the property
  that matters for an ⓘ — but an Ontario-selected teacher typing a BC code
  gets a different sentence on each platform.

  **6. A test on this side was writing into the REAL activity trail, and the
  mac should check whether its own suite can.** `SiteHealthRunnerTests.Dispose`
  restored `ActivityTrail`'s log path to `null`, which is the REAL trail, so
  `TestTrailRedirect`'s module-initializer redirect was defeated for every
  test that ran afterwards. Fixture courses and lines such as "removed the
  small assistant — 1.12 GB freed" were written into this machine's
  `%LOCALAPPDATA%\Plantoir\Logs\activity.txt`. Nothing was actually removed —
  the 1.04 GB model file is untouched, last written 2026-08-22 — but a
  diagnostic record carrying events that never happened is worse than no
  record, and it is the exact failure rule 5 is about. Fixed by restoring the
  suite's scratch path instead of null, and by putting the class in the
  serialized collection: the trail path is a process-wide static, and xUnit
  parallelises test CLASSES. **If any mac test sets that path and restores
  nil, the mac has the same leak.**

  **7. The acceptance was DRIVEN, not reasoned about, and the method is worth
  having.** `System.Windows.Automation` from stock Windows PowerShell 5.1
  drives WinUI 3 well enough to open an ⓘ flyout, read its text, and
  photograph it — which is exactly how the mac found its truncated popover,
  and how this side confirmed the same bug does not reproduce: the longest
  `specialNames` sentence wraps to five full lines at 600×187 device px. A
  fresh ICS3U with example content declined showed the ⓘ on exactly `Tasks`,
  `Ontario Curriculum` and `All Classes`; the written config carried
  `graded_folders: ["Tasks"]` and `per_section_folders: ["All Classes"]`; and
  a real `preview.ps1 --build-only` after removing `Discussions` in Settings
  printed the skip line and emitted a `public/` with zero occurrences of it,
  the teacher's own folder still in the vault. **What the drive caught that no
  test did** was the deadlock in item 4 above — and, humblingly, the drive had
  already photographed that flyout without noticing the switch it named was
  unreachable. Driving proves the pixels; it does not by itself prove the
  sentence is actionable.

  **What was rejected on this side, and why.** (a) Case-INSENSITIVE matching
  for `excluded_items` — the neighbouring "Media" refusal is case-insensitive,
  so matching it felt consistent, but `preflight_update_course_config` builds a
  plain Python `set` and tests exact membership; the app must agree with the
  BUILD, not with its neighbouring control. (b) Writing `excluded_items` and
  leaving the name in `shared_folders`, on the grounds that row 377 made the
  key authoritative — rejected because that reconciliation runs at the NEXT
  build, and between the save and that build Settings would show a folder the
  teacher had just removed. (c) Reading the blocked sentences out of
  `contracts/shared-rules.json` at RUNTIME rather than writing them into
  `SpecialNames.cs` — rejected for the reason `AssistWording` is written out:
  the contract is generated from the macOS app, so a changed sentence must fail
  a Windows BUILD, not change a teacher's screen on a machine the tests never
  ran on. It earned its keep immediately — the contract test caught a
  transcription slip where `curriculumFolderBlockedByCoverageMap` had lost the
  words "for the coverage map".

  **Three switch labels were RENAMED on Windows to match the contract's
  sentences.** This is the one place Windows changed teacher-visible wording,
  and the reason is that the blocked sentences name a switch BY NAME: an ⓘ
  saying "turn off *Publish the curriculum coverage map*" is worse than useless
  when the app's toggle says "Include Curriculum Coverage map". Course
  Settings' coverage toggle is now `SpecialNames.CoverageSwitchLabelInSettings`
  ("Publish the curriculum coverage map"), the wizard's is
  `CoverageSwitchLabelInWizard` ("Include the curriculum coverage map"), and
  the wizard's curriculum-pages toggle is built per-province, so a BC teacher
  is told about a switch a BC teacher can see rather than always "Ontario". The
  contract's wording won over the Windows label in every case, because the
  contract is generated from the mac and a Windows-only paraphrase is drift
  rather than a decision. **If the mac's own labels differ from these, the mac
  has the same bug** — a test (`EveryBlockedSentenceNamesASwitchTheAppActuallyHas`)
  now pins label against sentence on this side, and the mac has no equivalent.

  **Numbers, from this hardware** (Windows 11 Pro 26200, x64): the Windows
  suite went from **673 tests with 2 failing** on the mac's merge to **765
  passing, 0 failing**. The two failures were
  `FileFormats_CourseConfigKeys_MatchesContract` — which fails on
  `curriculum_folder`, NOT `excluded_items`, worth knowing if the mac ever
  reads that failure as a smaller job than it is — and
  `SharedRules_ActivityTrailEvents_Exist`. One honest caveat on the first: it
  asserts `Assert.Contains($"\"{key}\"", source)` against the raw TEXT of
  `CourseConfiguration.cs`, so it goes green on a key mentioned in a comment.
  Its greenness is evidence the keys are spelled in that file, not that they
  are implemented; the behaviour is covered by `ExcludedItemsTests` and
  `GradedFolderContractTests` instead.

  Reference: `windows-app/Plantoir.Core/Models/` — `CourseConfiguration.cs`,
  `GradedFolderRule.cs`, `CurriculumFolderRule.cs`, `SpecialNames.cs`,
  `ItemProtection.cs`; `windows-app/Plantoir/Views/FormBuilders.cs`,
  `CourseSettingsView.xaml.cs`, `NewCourseDialog.cs`;
  `windows-app/Plantoir.Tests/` — `ExcludedItemsTests.cs`,
  `GradedFolderContractTests.cs`, `SpecialNamesContractTests.cs`,
  `ItemProtectionTests.cs`.

- **The site-health FINDINGS DIALOG does not exist on Windows, and the mac
  side should know it is not there** (Windows, 2026-08-25, branch
  `issue/windows-special-folders-parity`, `GUI-IMPROVEMENTS.md` row 384).
  This is a **know, not a do** for the mac — nothing here asks the mac to
  change — but `WINDOWS-HANDOFF.md` item 10 currently reads as though Windows
  already surfaces these findings ("Windows receives the finding in the
  `PLANTOIR_HEALTH:` transcript line and displays the contract-authored
  sentence and detail without re-wording"), and on 2026-08-25 that was not
  true of any released or unreleased Windows build. Grepping `windows-app/`
  for `PLANTOIR_HEALTH` returned nothing at all, and
  `ActivityTrail.Event.FolderProblemFound` / `FolderProblemRepaired` had been
  declared since the trail was built with **no call site anywhere in the C#**.
  So every check the mac has shipped since row 357 — `curriculumCoverageFoundNothing`,
  `courseTeachesNothing`, `mediaFolderMissing`, `sectionIndexMissing`,
  `handWrittenCoveragePage`, and now `noGradedFolders` — has been printed into
  a Windows build console and read by nobody.

  **What landed this session** is the half a contract can gate: a
  `SiteHealthFinding` parser (`windows-app/Plantoir.Core/Models/SiteHealthFinding.cs`),
  its collection in `ScriptRunner`, and a `folder problem found` trail line per
  finding. **What did NOT land** is the teacher-facing dialog, the Fix button,
  the repair itself, and the "Preview Again" afterwards — mac rows 357–358,
  362–364, 367–372. That is a feature, not a port detail, and doing it inside a
  parity session would have meant inventing Windows wording for six mac dialogs
  without the mac's own review history to hand. It is owed by Windows to
  Windows; it is listed here so the next mac session does not read item 10 and
  assume parity that is not there.

  **What was rejected, and why.** Making `RepairableChecks` read
  `contracts/shared-rules.json` at RUNTIME was rejected: the contract is
  bundled into the app today, but a runtime read means a teacher's machine can
  disagree with the test suite about which checks get a Fix button, and the
  house rule here is the opposite — hardcode the answer in code and let a test
  pin it against the contract, so drift fails a build rather than a teacher.
  Deciding repairability from the finding's `fixable` FLAG was also rejected,
  for the reason `siteHealth.repair.neverOffered.why` already gives: the flag
  means "this kind of thing is repairable", not "this app has a repair for it".

  **Reasoned from the code, NOT measured** — said plainly because an
  adversarial review caught this paragraph claiming otherwise, and a
  code-reading dressed as a measurement is the failure CLAUDE.md rule 4 exists
  to prevent. No split was observed in the field; what IS on the record is that
  `ScriptRunner.BufferOutput` coalesces pseudo-console output on a **150 ms**
  cadence and hands `ReceiveOutput` whatever bytes are ready, so a
  `PLANTOIR_HEALTH:` line CAN be split across two flushes. The findings are
  therefore collected **line-buffered, not per output chunk**;
  `SiteHealthRunnerTests.AFindingSplitAcrossTwoChunksIsStillFound` splits a
  real line in half and pins it. If the mac ever parses these from a live
  stream rather than a finished transcript, the same trap is waiting.

  **Two defects the adversarial review found in the first cut, both worth
  knowing on the mac.** (1) The carry buffer trimmed to its TAIL when it
  outgrew 8 KB, copied from the milestone scanner's sliding window — which is
  INVERTED for a line buffer: after the newline loop the carry is the HEAD of
  one unterminated line, so the marker sits at the front and a tail-trim throws
  the finding away. It now drops the carry only when the carry cannot contain a
  marker, with `AVeryLongUnterminatedLineDoesNotLoseItsMarker` pinning it —
  and that test was confirmed to FAIL against the old code, not merely to pass
  against the new. (2) The findings property handed out the live mutable list
  that `Run(keepTranscript: false)` calls `.Clear()` on; it returns a snapshot
  now. Neither was reachable today, because nothing reads the collection yet,
  but both sit exactly on the seam a dialog attaches to.

  **The three new trail events** — `item excluded`, `item re-included`,
  `removal blocked` — are declared in `ActivityTrail.Event` with this piece,
  because `activityTrail.mustRecord` names them and the Windows suite pins the
  enum against that list as a SET, so the suite cannot be green without them.
  Their call sites arrive with the Course Settings work. That is the same
  declare-with-no-caller shape that left `FolderProblemFound` dead for months,
  so the enum carries a comment saying so rather than repeating it silently.

  Reference: `windows-app/Plantoir.Core/Models/SiteHealthFinding.cs`,
  `windows-app/Plantoir.Core/Scripting/ScriptRunner.cs` (`CollectHealthFindings`),
  `windows-app/Plantoir.Tests/SiteHealthContractTests.cs`,
  `windows-app/Plantoir.Tests/SiteHealthRunnerTests.cs`.


New items go at the TOP of this section, and move to the ledger when done
rather than being deleted.

> **Keeping this list is a standing instruction, not a courtesy** (`CLAUDE.md`
> rule 4). A Windows session that creates work for the mac adds an item here in
> the same session, and this list is the mirror of `WINDOWS-HANDOFF.md`'s
> numbered "What is still genuinely outstanding" — the same obligation,
> pointing the other way.
>
> The reason is the same in both directions: these files are read top-down and
> abandoned partway, so this section is the INDEX and the ledger below is the
> manual. A change that creates an obligation for the other platform and does
> not list it has, from their side, not been handed over at all.

- ⚠️ **A COURSE CODE OF "work" COLLIDES WITH THE BUILD WORKSPACE — on WINDOWS
  only; the mac has no such directory** (found on Windows, 2026-09-06).
  Corrected the same day: an earlier version of this entry said "on both
  platforms" and sent nobody anywhere useful, because the colliding folder is
  created by the Windows launchers alone. `preview.ps1` and `deploy.ps1` set
  `PLANTOIR_WORK_DIR` to `<buildRoot>\work`; `preview.sh` never sets it, so
  the Python falls back to `/tmp/quartz-builds` and the mac's builds folder
  holds only `<CODE>` directories and `working-folder.txt`. **There is nothing
  for a mac session to look for.**

  Windows now refuses to DELETE by that path
  (`BuildOutputLocation.WouldCollideWithEveryCourse`), which is the cheap
  half. **What IS shared is only the naming**: neither `CourseCodeValidator`
  (Windows — letters, digits, spaces and dashes, up to twelve characters) nor
  the mac's `CourseCodeRule` reserves the name, so a teacher can create a
  course called "work" on either platform. On the mac that is harmless today;
  it stops being harmless the moment anything there adopts a `work` sibling.
  Worth a shared decision — a reserved-name refusal in both wizards, or a
  deliberate "we accept this" — rather than leaving it to be rediscovered.

- ⚠️ **DO NOT TELL ANYONE TO FIX A CREDENTIAL WITH `cmdkey` — Plantoir cannot
  read what it writes** (Windows, 2026-09-06). Awareness rather than work, but
  it cost an hour here and it would cost a support conversation the same.
  `deploy.ps1`'s `CredApi` stores and reads the credential blob as **UTF-8**;
  `cmdkey` writes **UTF-16**. A credential written with `cmdkey` therefore
  shows up perfectly in `cmdkey /list` and is INVISIBLE to the app, which
  falls through to asking the teacher for the token again — with no hint that
  a credential is already sitting there.

  Met twice in one evening: a Cloudflare token stored with `cmdkey` was
  ignored by the launcher, and the machine's stored Cloudflare ACCOUNT ID had
  evidently been written the same way long ago. Precisely: `ReadSecret`
  returns null only when `CredRead` fails or the blob is empty — a UTF-16 blob
  decodes instead into a NUL-riddled string, which is not the token and does
  not authenticate. Either way the teacher is asked for a credential that is
  already stored, with nothing to say so. The fix is to write through the
  launcher's own `CredApi`. If the mac ever documents credential recovery for
  Windows — or a support note does — this is the trap.

- ⚠️ **TWO CONTRACT SENTENCES SAY "on your Mac" AND ARE SHOWN TO WINDOWS
  TEACHERS TOO** (Windows, 2026-09-06). `specialNames.renameFolder.explanation`
  and `.doneNothingWasThere` both name the platform:

  > This renames the folder on your Mac — in every section that has one — …
  > There was no folder by that name on your Mac, so only this course's
  > settings changed.

  Windows says "on this PC" instead, which is the same deliberate difference as
  "Setting up this Mac" against "Setting up this PC" in `app-rules.json` →
  `markerOrigins`. **What the mac owes is only a note in the contract** — a
  `platformWorded` marker, or the treatment `markerOrigins` already gets — so
  that the next reader sees a recorded difference rather than concluding
  Windows drifted, and so a future contract-driven test does not put the mac's
  word in front of a Windows teacher. `SpecialFolderRenamerTests.
  TheTwoPlatformWordedSentencesSayThisPcRatherThanYourMac` asserts it in both
  directions on this side.

- ⚠️ **A SCHEDULED DEPLOY HAS NOBODY TO ANSWER A QUESTION, AND `deploy` STILL
  ASKS THEM — the same shape on both platforms** (found on Windows,
  2026-09-06). Written up in full in `TODO.md`; summarised here because the mac
  is affected identically and neither side should assume the other has it in
  hand.

  Found by the new `verify-deploy.ps1`, whose Netlify leg hung until its own
  timeout: the site saved in `.netlify_sites/section1.json` no longer existed
  on Netlify, so the launcher fell through to creating a fresh one and asked
  for a name. A person answers that in two seconds; a scheduled task has no
  console. `TaskScheduling.WriteWrapperScript` generates `& deploy.ps1 <args>`
  with no stdin and no non-interactive flag, and the mac's `launchd` path has
  the same shape — so "publish tomorrow's class" on a course whose site was
  deleted upstream, or whose FIRST publish is the scheduled one, reaches a
  question nobody will answer.

  **Not fixed here on purpose.** The fix is a `--non-interactive` flag that
  makes `deploy` refuse rather than ask, which changes what the app passes the
  launcher — pinned by `app-rules.json` → `deployArguments` and run by both
  suites. That is a contract change and wants agreeing rather than doing. What
**The mechanism, corrected — and it is not what the first version of this
  entry said.** An earlier version of this entry blamed
  PowerShell's `Read-Host`. It is not: the question comes from `deploy.py`'s
  own `prompt()` helper (`scripts/deploy.py:325`), which guards every ask with
  `sys.stdin.isatty()`. That single line decides which of two different bugs a
  teacher gets, and BOTH have now been seen:

  * **stdin IS a terminal → Python's `input()` blocks, forever.** Measured:
    two harness runs left a `powershell.exe` and its `python.exe` child waiting
    at that prompt for **45 minutes**, still alive when they were swept up. We
    know it was this branch and not the other because the prompt TEXT was
    printed, and `prompt()` prints nothing at all when `isatty()` is false. The
    failure is "the overnight publish never happened and nothing said so" — the
    teacher's site is simply not updated in the morning.
  * **stdin is NOT a terminal → the default is taken silently.** No prompt is
    printed, the site is created at whatever address the default suggests, and
    a name conflict auto-suffixes (`deploy.py:430`). The failure is "published
    to an address nobody chose", and on a machine with no saved surname the
    address has no surname in it either.

  **So the open question is narrow and answerable**: does Task Scheduler give
  the wrapper a console, making `isatty()` true? That decides which of the two
  a teacher meets. Both are bad, and a `--non-interactive` flag that REFUSES
  rather than asking is the fix for both.

  **Two things that follow whichever branch it takes.** The wedged processes
  survive their parent being killed — including `Process.Kill($true)` on the
  whole tree, which does not even exist under Windows PowerShell 5.1 and threw
  silently in this harness for three runs — so a scheduler that gives up leaves
  the launcher running. And NOTHING reaches the activity trail while they wait,
  so the trail cannot tell a wedged overnight publish from one that was never
  scheduled.

  Hardware: Windows 11 Pro 26200, Intel i5-8365U.

- ⚠️ **THE CONTRACT'S `stopPreview` PROSE IS NOW WRONG ABOUT WINDOWS, and only
  the mac can regenerate it** (Windows + shared, 2026-09-05). Three sentences
  in `contracts/shared-rules.json` → `stopPreview` describe a state that
  stopped being true today. They are generated from the mac, so this side
  cannot fix them without hand-editing a generated key:

  - `modes.servingOnly` ends "Implemented today by `build_site.py` inside the
    container, and there ONLY: run natively on Windows there is no `/proc`,
    the process list comes back empty and this does nothing, so the overwrite
    race is still live on that platform. That is a gap, not a decision." **The
    gap is closed.** `stop_preview.read_snapshot()` now dispatches to a native
    `Get-CimInstance Win32_Process` reader, so `servingOnly` runs on Windows
    exactly as it does in the container.
  - `notShared` → "Which processes are even considered" says Windows filters
    to `node.exe` and `python.exe` for direct evidence. **It no longer does.**
    The filter is gone: it refused most of the contract's own fixtures
    (`python3`, `npm`, `esbuild`, `sh`), and the judgement the contract left
    to this side has been made — a process carrying this section's build
    directory on its command line IS this section's process. The mac and
    Windows now consider the same processes.
  - `notShared` → "How a process is ended" and "How hard a publish build
    insists" both say Windows ends things with `Stop-Process -Force`. Still
    true of `preview.ps1`, but no longer the whole story: `build_site.py`'s
    own `servingOnly` sweep now runs natively there too and ends processes
    with `os.kill` (which is `TerminateProcess` on Windows, whatever signal
    number it is handed).

  Nothing is asked of the mac's CODE here — only that the generator be re-run
  with these sentences corrected, since a contract that describes a race as
  "still live" is exactly the kind of stale guidance `CLAUDE.md` rule 3 says
  is worse than none. Reference: `scripts/stop_preview.py`
  (`read_windows_snapshot`, `read_snapshot`, `stop_one`), `preview.ps1`
  (`Get-SectionProcessesToStop`), `windows-app/test_stop_preview.ps1`.

- ⚠️ **A SIGNAL WAS DOWNGRADED ON THE MAC FROM WINDOWS, AND IS NOW PUT BACK —
  check nothing else rode on it** (Windows + shared, 2026-09-05). Worth ten
  seconds of the mac's attention because the mistake was invisible and the
  file is shared. Routing `build_site.py`'s `stop_preview_serving` through a
  new `stop_one()` helper — written for Windows, where there is nothing to
  ask with — silently changed the container's `servingOnly` kill from SIGKILL
  to SIGTERM on every platform. The contract states the reason it must not
  ask first (a second spent waiting politely is a second in which the
  preview's mirror can overwrite the build being protected). Found by review
  and fixed in the same session: `stop_one(pid, signum)` now takes the
  signal, `build_site.py` passes `getattr(signal, "SIGKILL",
  signal.SIGTERM)`, and `TheSignalAPublishBuildSendsIsNotNegotiable` in
  `scripts/test_stop_preview.py` pins it. **The mac's behaviour is
  unchanged from before this branch** — this is a note that it was briefly
  otherwise on this branch, not an ask.

- ⚠️ **`WINDOWS-HANDOFF.md` item 20's first owed bullet was answered a
  different way than it asked, deliberately** (Windows, 2026-09-05). It said
  to call `preview.ps1`'s own `--stop` matcher from the `--build-only` path.
  That was not done, and should not be: `deploy.py` reaches
  `build_site.py --build-only` directly (`rebuild_for_production`), never
  through the launcher, so a fix living in `preview.ps1` leaves the Netlify
  and Cloudflare route racing — which item 20 itself points out two
  paragraphs later. Fixing it one level down in `stop_preview.read_snapshot()`
  covers `preview.ps1 --build-only`, `deploy.ps1`'s folder branch,
  `deploy.py`, scheduled deploys and `plantoir-mcp.exe` in one edit, and
  every future caller for free. Item 20 can be marked done on that bullet.

- ⚠️ **NEEDS A MAC BUILD + TEST — assistant system-prompt tweak fixes
  "undo over-salient"** (Windows, 2026-08-24, TODO.md item (c)). The
  Swift edit is made — `AssistAgent.swift`'s `systemPrompt(course:section:)`
  — but has NOT been built or run through the mac's XCTest suite, and the
  measurement behind it was done entirely against the Windows-native
  Qwen2.5-1.5B (Vulkan), so it has not been re-verified on Metal either.

  What changed and why: with the promise card's eleven fixed shapes now
  handled as deterministic commands (they never reach the model), what
  still routes through the model is a teacher's own phrasing, last
  measured at 72% overall in `promise-card-results.txt` with two flagged
  problems — "undo over-salient" (a `unpublish` request phrased as "I
  posted X by mistake" was answered with `undo_last_change` instead) and
  a hide request's decline lost. Re-measured 2026-08-24 against the
  Windows-shipped small tier (Qwen2.5-1.5B-Instruct Q4_K_M, native
  llama-server.exe, Vulkan, `--reasoning off --reasoning-budget 0`, 3
  trials/probe, temp 0.1): baseline conversational-only accuracy 46/54
  (85%), full write-up and raw transcripts in
  `research/ai-assist/conversational-residue-results.txt`.

  Two sentences added to the system prompt (verbatim in the results file
  and in both `AssistAgent.cs` and `AssistAgent.swift`) fixed both flagged
  clusters cleanly across two runs (conversational-only 51/54 and 49/54 —
  94% and 91%), with zero new failures and zero polarity inversions in
  either run. **Rejected**, and logged so it isn't retried unmeasured: a
  third wording that named `cancel_scheduled_deploy` explicitly, to also
  fix a still-unsolved "delete the X folder" probe (routes to
  `cancel_scheduled_deploy` instead of declining, unchanged by any wording
  tried) — it did not fix that probe and broke two previously-clean cases,
  dropping full-suite accuracy to 79%. The lesson matches
  `AssistToolRunner.localTools`'s doc comment about tool descriptions: a
  small model reads an extra clause as new signal to weigh, not a boundary
  to respect — naming an unrelated tool inside a "don't do X" sentence
  raised its salience rather than lowering it.

  **What the mac owes:** build, run the XCTest suite
  (`AssistModelTierTests` and friends), and — if there's appetite —
  re-run an equivalent probe set against the Metal-native `llama-server`
  to confirm the same gain holds there (the Windows measurement is
  evidence, not proof, for a different backend and quantization path). No
  contract case needed — the system prompt isn't contract-carried today
  (checked: no `systemPrompt` key anywhere under `contracts/`).

- ⚠️ **NEEDS A MAC `verify.sh` RUN — authored and reasoned through on
  Windows, unverified against a real Docker build.** TODO.md's "A recreated
  container publishes pages the teacher HID" turned out to already be fixed
  (2026-08-17, commit `9d7db82b`, ported to the Windows-native runtime path
  the same day via `fetch-runtime.ps1`) — the Dockerfile bakes the
  `CQ4T-OMIT-ANCHOR` filter into the image, `build_site.py`'s
  `ensure_quartz_layout_anchor` re-asserts it on every build and refuses
  (`sys.exit(1)`) rather than warn-and-continue if it can't restore it, and
  `verify.sh` §4b asserts it against the built image. TODO.md's item was
  simply stale and has been removed.

  What actually shipped THIS session, on top of that: an adversarial review
  of the existing fix (asked for by Russell, not found by accident) turned up
  a real gap — every one of those checks did a bare **substring** match for
  the literal string `CQ4T-OMIT-ANCHOR`, not that the marker comment is
  actually attached to a live `omit` Set. A file could contain that string
  somewhere unrelated while the Set had drifted away from it (a hand-edit, or
  a future Quartz upstream reshuffle none of `_patch_explorer_with_anchor`'s
  three regex strategies produce cleanly), and the checks would report
  success while `update_quartz_layout`'s own fallback silently inserts a
  brand-new, disconnected `omit` Set elsewhere in the file on its next write
  — hidden pages would go unrecognized by the filter and publish, with every
  guard reporting green. Not reachable through any normal flow today (nothing
  in this codebase currently produces that detached shape), but it is exactly
  the failure class this whole fix exists to close, so it was tightened
  rather than left as a latent gap.

  **What changed:** `scripts/build_site.py` gains `_ANCHOR_STRUCTURE_RE` /
  `_anchor_is_structurally_wired()` — the marker's own line must be
  immediately followed (next line, leading whitespace only) by
  `const omit = new Set`, not merely present anywhere in the file.
  `ensure_quartz_layout_anchor` now calls that instead of a bare
  `"CQ4T-OMIT-ANCHOR" in txt`, on both the missing-marker path and the
  repaired-output verification. `verify.sh` §4b's grep was rewritten to
  `grep -Pzoq '//[ \t]*CQ4T-OMIT-ANCHOR:[^\n]*\n[ \t]*const[ \t]+omit[ \t]*=[ \t]*new[ \t]+Set'`
  — deliberately mirroring the Python pattern character-for-character (a
  first draft used a looser bash pattern with `\s` and no `//` prefix
  requirement; a second adversarial review caught that the two guards'
  claimed equivalence was false and it was tightened to match exactly, since
  `verify.sh` is the only guard on the Docker/mac-Linux path and
  `build_site.py`'s check is the only one on Windows-native — they must agree
  or the two platforms disagree about what "wired" means). Verified against
  literal `good.ts`/`bad-detached.ts`/`missing.ts` fixtures with both `python3`
  and GNU `grep -P` directly (not through Docker — unavailable on this
  machine); confirmed the three writer shapes (`_patch_explorer_with_anchor`'s
  three strategies, `EXPLORER_BLOCK`, and `update_quartz_layout`'s own
  rewrite) all still pass the tightened check, so a normal build → next
  build/preview cycle does not regress.

  **What the mac still owes:** run `verify.sh` for real (it needs Docker,
  unreachable here) to confirm §4b's tightened check still passes against an
  actual freshly-built image, and that the `grep -Pzoq` syntax behaves
  identically on macOS's grep as it did against GNU grep 3.0 here — worth
  double-checking, since `-z`/`-P` support and behaviour has differed across
  grep implementations historically (macOS ships BSD grep by default unless
  Homebrew's `ggrep`/GNU grep is on PATH; `verify.sh` already assumes
  something docker-adjacent, confirm which grep binary the check actually
  runs — it runs INSIDE the container via `docker run`, so it is the image's
  own grep, likely fine, but worth confirming rather than assuming). No
  `contracts/` or `GUI-IMPROVEMENTS.md` entry — this is an internal
  correctness hardening of toolchain logic, not a teacher-visible behaviour
  change (the original 2026-08-17 fix did not add either either, for the same
  reason). Two low-priority items noted in the new code comment rather than
  fixed, since neither is exercised by any writer in this codebase today: a
  type-annotation form (`const omit: Set<string> = new Set(...)`) and a
  blank line between the anchor and the `const` would both wrongly fail this
  check if they ever appeared by hand-edit — cheap to loosen for later if
  that ever becomes real.

- **For awareness only — no mac action required.** TODO.md item: *"Assistant
  replies 'deployed' before the deploy finishes (Windows)."* Windows'
  `MainWindow.DeployForAsync` used to resolve the instant the click was
  dispatched to the UI thread, not when the deploy actually finished, so the
  in-app assistant said "is deployed. Students can reach it now." after
  every `deploy_section` call regardless of outcome. Fixed by having
  `SectionDetailView.Deploy_Click`'s body (now `DeployAsync()`, an
  `async Task<string?>`) RETURN the true outcome sentence on every exit path
  — success/partial/all-failed via the existing
  `MultiDestinationDeployRunner.Result(...)`, `AssistWording.DeployDidNotFinish`
  on every early return and the catch block — threaded back through
  `MainWindow.DeployForAsync` → `AssistWindow.StartDeployInAppAsync` →
  `AssistAgent.RunTool`. Full write-up: `GUI-IMPROVEMENTS.md` row 383.

  The mac's `deployAndWait()` already awaits the real result and words it
  correctly — this only brought Windows to parity, so there is nothing to
  port. Two things worth a mac session's attention, not required, not
  blocking anything: (1) whether an equivalent "second deploy request
  arrives while one is already running" path exists in
  `SectionDetailView.swift`, and if so whether it shares mutable state across
  the two in-flight calls the way the first (rejected) fix here did before an
  adversarial review caught it — see the "rejected" note in
  `GUI-IMPROVEMENTS.md` row 383 for the exact shape of that bug, since it is
  a general trap (a single-slot completion field shared across concurrent
  callers) worth checking for rather than re-discovering; (2) the Windows
  scenario test fixture (`AssistScenarioTests.cs`) never wired
  `StartDeployInAppAsync` at all before this — worth checking whether the
  mac's own scenario tests exercise the equivalent async production seam or
  only a sync stand-in.

- ⚠️ **NEEDS A MAC BUILD/TEST/REGEN — authored on Windows, unverified there.**
  TODO.md item 1: *"A preview's progress bar sits at 100% saying 'Opening the
  preview…' for the entire build."* `scripts/build_site.py` prints the final
  preview milestone's marker ("🚀 Launching Quartz preview on…") *before* it
  runs `npx quartz build --serve`, and `ScriptRunner.advanceMilestones`/
  `AdvanceMilestones` jumps to the highest milestone whose marker has appeared
  anywhere in output, so that one early line completes every remaining
  milestone at once — the bar reads 100% for the whole real build, and
  "Building your site…"/"Preparing components…" never display.

  **Fix**: `TaskMilestones.preview`'s last entry now matches `"Done
  processing"` instead of `"Launching Quartz preview"` — the literal text
  `patches/build.ts:99` prints (`console.log(chalk.green(\`Done processing
  ${n} files in ...\`))`), which fires only once `emitContent()` has actually
  returned inside `buildQuartz()`, i.e. after the fresh site is truly on disk.
  Quartz's own "Started a Quartz server listening…" line was ruled out —
  `WINDOWS-HANDOFF.md`'s "Quartz serves the OLD site before it builds the new
  one" section already documents that IT ALSO prints before the build
  (`server.listen(); console.log(listening); await build()`), so it has the
  identical defect.

  **Verified against a real transcript, 2026-08-23** (`preview.ps1 --build-only
  EXC2O 1`, native Windows toolchain, no container): the raw output shows
  `Quartz v4.5.0` then `Done processing 199 files in 6s`, in that order — the
  marker is unique (grepped across `scripts/`, `patches/`, and a baked
  container copy — one hit), it's the file Docker actually copies in
  (`Dockerfile:41` → `patches/build.ts`), and chalk wraps the whole literal in
  ANSI, not interleaved inside it, so color is not a matching risk.

  **A related, out-of-scope defect, found but NOT fixed here, worth knowing
  before anyone "improves" this further**: the "Building your site…" milestone
  (marker `"Quartz v4"`) has the same shape — Quartz prints that banner
  (`cli/handlers.js`, `chalk.bgGreen.black(' Quartz v${version} ')`) at the
  very top of its build handler, before any real work, not when the build
  finishes. It doesn't produce the reported symptom here (it's mid-list, not
  the last milestone, so the bar just advances a step early rather than
  sticking at 100%) — after this fix, once "Quartz v4" prints the bar jumps
  straight to 7/8 with the label already reading "Opening the preview…" for
  the whole real build (an imprecise label, not a stuck-at-100%-forever bug).
  Left alone deliberately, scoped out by an adversarial review before this
  landed — a genuine fix would need a real "content actually processed"
  signal for that step too, and isn't a one-line marker swap.

  **What's changed, and what still needs mac attention:**
  - `windows-app/Plantoir.Core/Scripting/TaskMilestones.cs` — done, built,
    `dotnet test Plantoir.Tests/Plantoir.Tests.csproj` 664/664 green.
  - `mac-app/QuartzTeachers/Scripting/TaskMilestones.swift` — same one-line
    marker edit made, **but this Windows session has no Xcode and could not
    build or run it.** Please `xcodegen generate` + build + run
    `QuartzTeachersTests` before trusting it.
  - `mac-app/Tests/QuartzTeachersTests/TaskMilestoneTests.swift` —
    `testPreviewProgressAdvancesThroughItsMilestones` updated to assert the
    new intermediate state (7/8 after `"Quartz v4.5.0\n"`, label still
    "Opening the preview…") and only reaching 8/8 after a `"Done processing
    199 files in 6s\n"` line — **also unverified on a mac.**
  - `contracts/app-rules.json` → `markerOrigins.origins` — added `"Done
    processing": "elsewhere"` (authored/preserved key, safe to hand-edit).
  - **`contracts/app-rules.json` → `milestones.preview` was deliberately LEFT
    UNCHANGED.** `contracts/README.md` names `milestones` explicitly as a
    generated readout of `TaskMilestones`, regenerated only by `Plantoir
    --write-contracts` on a mac, and says in so many words not to hand-edit
    it. No Windows test currently reads `milestones` back out of the JSON, so
    leaving it stale doesn't fail `dotnet test` — but it IS stale until a mac
    session runs `Plantoir --write-contracts contracts` (after building the
    Swift change above) to regenerate it for real.
  - **`mac-app/Tests/QuartzTeachersUITests/MarketingScreenshotTests.swift`
    `test4Progress`** photographs the CURRENT broken behaviour on purpose (its
    own comment explains why: "the only state a capture can dependably
    reach"). Once this fix is built and verified on a mac, that shot should
    change (the bar will genuinely be mid-progress, not parked at 100%) and
    this test's comment/expectations will need revisiting — not done here,
    since it needs a real mac screenshot to know what the new dependable state
    looks like.
  - `GUI-IMPROVEMENTS.md` — not yet given a row; add one once the mac side is
    verified, since a teacher-visible change isn't confirmed shipped until
    both platforms show it.

  Branch: `issue/preview-progress-bar-marker` off `dev`, pushed. An
  adversarial subagent reviewed the plan before any file was touched — it
  caught the `milestones`-hand-edit mistake above before it happened and
  flagged the "Quartz v4" sibling defect; see this entry for both.

- ✅ DONE (mac, 2026-08-20). **The assistant warm-up race: it EXISTS here,
  it is measurable, and it cannot produce the Windows symptom.** Answering
  GUI-IMPROVEMENTS row 293's two questions with the real app rather than
  from the code, as that row asked.

  **Q1: does the mac's first turn await its warm-up? No — same as Windows
  before their fix.** `AssistSession.startEngine()` sets `readiness = .ready`
  and only THEN `await warmUp(…)`, and `canSend` asks nothing but
  `readiness == .ready`. The trail shows it plainly: `the assistant was ready
  after 0.5s`, with the ~3,400-token priming request still to run.

  **Measured, small assistant, M-series, 48 GB — the same question twice:**
  - typed after the warm-up had finished: **1.7 s**
  - sent the instant the field enabled, racing it: **3.1 s**

  So the race is real and costs about **1.4 s** on the first question, which
  is the priming request's tail on the server's single slot
  (`--parallel 1`). The question was answered correctly both times; nothing
  was lost.

  **Q2: is a timeout distinguishable from window-close cancellation? Yes —
  the mac has no way to confuse them, because it never classifies errors at
  all.** `AssistAgent.think()`'s catch has one branch: every error becomes a
  visible `.problem` bubble AND an `assistantCouldNotAnswer` trail line.
  There is no "this was a close, say nothing" path for a timeout to fall
  into. Proven by killing `llama-server` mid-session: the teacher saw
  `⚠ Could not connect to the server.` in the conversation and the trail
  recorded `the local AI assistant could not answer — Could not connect to
  the server.`

  **Three independent reasons the Windows chain cannot complete here**, which
  is why this is not a mac bug wearing a Windows coat:
  1. The request timeout is **180 s** (`AssistModelClient.reply`), not a few
     seconds — a warm-up of 2 s (small) or ~12 s (large) cannot exhaust it.
  2. The catch cannot swallow a timeout as a close, per Q2.
  3. **The engine's output goes to `FileHandle.nullDevice`**
     (`AssistServerHost`), so the unread-pipe wedge Windows had to fix by
     draining pipes cannot occur — nothing is ever buffered.

  **What was NOT fixed, and why.** Making the first turn await the warm-up is
  a real improvement worth about 1.4 s, and it is an OPTIMISATION here rather
  than a fix: the teacher-visible defect Windows repaired (silence) does not
  exist on this side. Doing it inside a release qualification would have made
  the mac's v1.1.0 a behaviour change and pushed the cut to 1.1.1 for a
  second and a half. Decided with Russell on 2026-08-20; it belongs in the
  next version with a test that pins "cannot send until the warm-up has
  returned".

  **✅ Landed later the same day** — GUI-IMPROVEMENTS row 298, branch
  `issue/assist-warm-up-gate`. `canSend` now requires `hasFinishedWarmUp`,
  and `AssistWarmUpTests` pins it against a stub engine that holds its
  answer. One correction to send back the other way, because it changes what
  the fix should be claimed to do: **3.1 ≈ 1.4 + 1.7 is the signature of two
  requests strictly serialised on one slot**, so the 1.4 s is moved out of
  the answer and into the wait rather than saved — measured from the window
  opening, the total is unchanged. What it buys is that nothing depends on
  the engine's behaviour with two requests in flight, and that the trail's
  first `assistant chose a tool` timing is no longer polluted by leftover
  warm-up.

  **One diagnostics gap this turned up, for the next session rather than
  this one.** Reason 3 is also a cost: with the engine's output going to
  `/dev/null`, nothing llama-server says can ever reach a problem report —
  no load errors, no slot warnings, no token counts. Windows added
  `NoteServerLine` for exactly this. The mac should sample those lines into
  the trail (a bounded tail, not the firehose) rather than keep discarding
  them; it is a report-quality change, not a hang risk, which is why it is
  not in 1.1.0.

  **✅ Landed later the same day** — GUI-IMPROVEMENTS row 299, branch
  `issue/assist-engine-log`, with a full section in `WINDOWS-HANDOFF.md`.
  Both streams go to a FILE rather than a pipe, so the no-blocking-read
  property that made `nullDevice` safe is kept structurally rather than
  promised; a bounded tail is sampled when the engine fails to start, every
  fifteen seconds while the window is open, and at teardown. Capped at
  twelve lines a conversation.

  **This is a request back to Windows, and it will turn your suite red.**
  `contracts/shared-rules.json` → `activityTrail.mustRecord` gained
  **`assistant engine said`**, so the list pin fails until `Plantoir.Core`'s
  `ActivityTrail.Event` gains the same entry. Nothing is broken; the case is
  waiting for you. The hard half is already there —
  `LocalModel.NoteServerLine` and `RecentServerLog` keep a 60-line ring
  buffer of exactly this output, and nothing yet puts any of it on the trail.
  **Re-measure the healthy-start noise on your own engine build before
  copying the filter**: warnings are excluded here because the Metal build
  prints six benign ones at every start (five a CORS block, one a token-type
  quirk), and a Vulkan or CPU build may not print the same six.

- ✅ DONE (mac, 2026-08-20). **`./verify.sh` passes against the changed
  shared scripts — all nine checks, and the npx question is settled.** Run
  from a clean clone of `dev` with the v1.1.0 tree: image built from the
  working recipe with BuildKit, baked scripts/patches/support files verified
  identical to the tree, the Explorer hide filter present in both Quartz
  copies, then a real `preview.sh EXC2O 1 --full-rebuild --build-only`
  through the launcher — 260 Markdown files parsed in 966 ms, 304 files
  emitted, "Done processing 260 files in 1s". No behaviour on this side
  needed changing, which is what let the mac ship 1.1.0 rather than 1.1.1.

  **The npx question is answered: there is nothing left to check.** The
  entry asked whether the container had quietly been resolving the Quartz
  CLI from the npm registry too. It cannot any more, on either platform,
  because the fix is in the SHARED script — `build_site.py` runs
  `node <abs>/quartz/bootstrap-cli.mjs` at both call sites (build and
  serve), and `deploy.py` mentions npx nowhere at all. The whole verify run
  contains not one npx line. So the question is now unanswerable rather
  than answered — the old behaviour is gone from the code that would have
  produced it — and it does not matter: the pin held either way, because
  Quartz's CLI runs the local patched `quartz/` source from CWD.

  **One nit, deliberately not fixed**: `toolchain_paths.py` still defines
  `NPX` and nothing uses it. Removing it would change the build context and
  therefore the image tag, which costs every teacher on both platforms a
  rebuild — for a dead constant. Fold it into the next change that touches
  that file for a real reason.

  **Two notes for whoever runs `verify.sh` next.** Its fixture,
  `courses/EXC2O`, is gitignored, so a fresh clone has none; the script's
  header says to install it with `./setup.sh`, but that is an interactive
  wizard and `cp -R support/example_course/EXC2O courses/EXC2O` produces the
  same fixture in a second. And the script deliberately LEAVES a container
  running from `quartz-teacher:dev-test`; `docker rm -f teaching-quartz-<hash>`
  puts the folder back on the normal image, which this session did.

  Everything below is the original request, kept for the reasoning.

  **Windows dropped the container entirely — shared scripts changed, run
  `./verify.sh` on the next sync** (Windows + shared, 2026-08-19, branch
  `windows-native-toolchain`). Windows now runs the whole toolchain
  natively: Node 20, Python 3.11, the patched Quartz scaffold and wrangler
  ship inside the app's own folder (built by
  `windows-app/Vendor/fetch-runtime.ps1`, pins mirroring the Dockerfile's),
  and the launchers run the shared Python directly when that runtime is
  present. WHY: WSL2 needs admin rights, Windows feature changes and a
  reboot — school-managed laptops refuse all three, and a teacher hit
  exactly that in front of an audience twice in one day. Rejected: porting
  the Python to C# (kills the shared-scripts contract and invites permanent
  drift); keeping a WSL2 fallback (Russell chose deletion once verified —
  two paths means two test surfaces forever).

  **What the mac must know about the shared files:**
  - `scripts/toolchain_paths.py` is new: every fixed path (`/opt/*`,
    `/teaching/courses`) now routes through it. Container defaults are
    byte-identical to before; the native path overrides via `PLANTOIR_*`
    env vars the mac never sets. The Dockerfile COPYies it — image hash
    changes, so the first mac preview after sync does a one-time rebuild.
  - The 26 `tee` subprocess writes are plain writes now (`write_file`),
    the Media/node_modules/.netlify links go through `link_directory`
    (symlink first — the mac's behaviour is unchanged), and
    `_sync_public_to_host` falls back to an incremental pure-Python mirror
    only when rsync is absent (it never is, in the container).
  - **The Quartz CLI is invoked as `node <abs>/quartz/bootstrap-cli.mjs`
    instead of `npx quartz`** — measured on Windows, `npx` resolved the CLI
    from the npm REGISTRY into its cache (a project's own bin never lands
    in its node_modules/.bin), which needed network and floated off the
    v4.5.0 pin. The container was almost certainly doing the same thing
    quietly; check a container build log for an `npx` cache line if you
    want the confirmation. Correctness held only because Quartz's CLI runs
    the local patched `quartz/` source from CWD.
  - `setup_course.py`'s keyboard reader imports termios where it exists,
    msvcrt where it does not; POSIX behaviour identical.

  Numbers (this machine, Ryzen-class x64, NVMe): first native build of the
  199-page example course **57 s cold** including scaffold staging; Quartz
  parse+emit 5 s; delta deploy to Netlify 117 files, ~40 s. The container
  path's equivalent on this same machine paid a one-time ~8 min image
  build plus WSL2 provisioning before the first build could start.
  Reference: `Enter-NativeRuntime` in the three `.ps1` launchers,
  `scripts/toolchain_paths.py`, `windows-app/Vendor/fetch-runtime.ps1`.

- ✅ DONE (mac, 2026-08-20). **Verified against the real app: the mac writes
  a record for every task, and the one gap in the code is unreachable here.**

  **What was driven.** A scratch working folder, the Example Course in it, a
  real preview that served the site, then `course_config.json` deliberately
  corrupted and Preview pressed again: `preview.sh — failed (exit 1) after
  1.0s`. `~/Library/Logs/Plantoir/runs/2026-08-20-184555-preview.txt` appeared
  with the task, the arguments, the outcome, the whole transcript ending in
  the JSONDecodeError, paths redacted to `/Users/person/…`, and the line
  `Explained nothing recognised — worth a look` — the honest fallback the
  contract's note asks for, doing its job on an unrecognised traceback.

  **It is the same folder the report reads**, checked rather than assumed:
  `ScriptRunner.writeRecordOfRun` → `ProblemReportStore.write` →
  `runsFolderURL`, and `ProblemReportBuilder.assembleFolder` reads
  `store.runFileURLs()` from that same store — the count is what fills in
  "the last N tasks Plantoir ran for you". Windows's failure was these two
  being different folders; here they are one property on one type.

  **A record also exists from the FIRST moment**, which is more than was
  asked for: the still-running preview had a 14 KB record while it was
  serving, outcome "Still running after …". That matters for the commonest
  report of all — "the preview is stuck" — which by definition never reaches
  a finish path.

  **The one gap, and why it is NOT worth fixing.** `ScriptRunner` assigns
  `runScriptName` AFTER `try newProcess.run()`, so a task that failed at
  LAUNCH would write no record and no `taskStarted` line — exactly the
  Windows shape, and exactly what the request asked about. It cannot happen
  here: `executableURL` is always `/bin/bash` and the script is an argument,
  so `run()` can only throw if `/bin/bash` is missing, at which point the
  Mac has bigger problems. Confirmed by experiment — `chmod -x preview.sh`
  and pressing Preview still produced `started preview.sh EXC2O 1 --port
  8081` on the trail and a record, because the executable bit of the script
  is not consulted. **Windows is exposed where the mac is not** because it
  launches the `.ps1` through its own host rather than through a shell that
  always exists. Left as it is deliberately: reordering two lines to guard
  against an unreachable case would be an untested behaviour change in a
  release-qualification pass. Written down so nobody "fixes" the ordering
  believing it is live, and so the asymmetry with Windows is on the record.

  Everything below is the original request, kept for the reasoning.

  **Check that every finished mac task really writes a run transcript**
  (Windows, 2026-08-19, branch `windows-wsl2-auto-install`). A real teacher's
  problem report arrived saying "the last 0 tasks Plantoir ran for you" after
  three failed setups: the Windows report reads `Logs\runs\*.txt`, and
  nothing ever wrote that folder — the reading side was tested against
  hand-made files, so the gap passed every test. Windows now saves every
  finished task's transcript from `ScriptRunner`'s finish path (redacted on
  the way in, pruned to the newest 20, header matching the trail's
  "finished … — outcome" sentence). The ask here is a VERIFICATION, not a
  port: drive one real failing task on the mac and confirm a file appears in
  the folder its report actually reads — the failure mode is precisely that
  the tests cannot see this. Reference:
  `ProblemReportStore.SaveRunTranscript`, `ScriptRunner.NoteTaskFinished`,
  `ProblemReportTests.Store_SavesRunTranscripts_RedactedAndPruned`.

- ✅ DONE (mac, 2026-08-20) — **RETIRED rather than implemented.** The three
  explainer sentences were never added here, and must not be: the same
  session that proposed them deleted the Windows container path, so no
  shipping launcher can print the lines they match. The three cases are gone
  from `contracts/app-rules.json` → `failureExplanations.cases`; Windows's
  own `SetupExplanation` is now unpinned by the contract and should be
  deleted along with the launcher code it reads, not kept as the only
  implementation of a rule nothing tests. See the ledger entry "The
  teacher-made-link case is implemented, and the three setup cases are
  retired". Everything below is the original request, kept for the reasoning.

  **The Windows launchers now install WSL2 themselves — the mac owes only
  the three explainer sentences** (Windows, 2026-08-19, branch
  `windows-wsl2-auto-install`). What it fixed: a teacher on a PC with no
  WSL2 hit "ERROR: WSL is present but no Linux distribution is installed"
  plus an instruction to open an Administrator PowerShell — it failed live
  in front of an audience on 2026-08-19. This was the Windows analogue of
  the mac's zero-prerequisite Colima bootstrap, called for by
  `WINDOWS-HANDOFF.md`'s "Container engine" note (entry 72), and it now
  exists: each `.ps1` launcher's `Install-WindowsSubsystem` runs one
  elevated `wsl --install -d Ubuntu --no-launch` (retrying with
  `--web-download` for Store-blocked school machines), detects
  restart-pending by USABILITY rather than exit code (the exit code is 0 on
  that path), and reports the three non-fault stops in plain words. WHY the
  choices: `--no-launch` because Ubuntu's first-run username wizard would
  otherwise block a non-interactive run forever — the distro runs as root,
  fine for an appliance no teacher opens; UAC is announced first ("Watch
  for a Windows permission prompt") because it is the one step that cannot
  be silent; a distro installed BY the run is provisioned without the
  Docker-engine question (the mac never asks either), while a pre-existing
  distro keeps the question because it belongs to whoever set it up.
  Rejected: DISM feature-enable plus manual distro import (re-implements
  what `wsl --install` already does, and needs the same elevation);
  prompting before the install (the handoff asks for silent, and UAC is
  already the consent); auto-restarting the PC (never — the teacher may
  have unsaved work everywhere). Untested on a truly fresh machine — this
  dev box has WSL — so the restart path is asserted from the launcher's
  printed lines, which is what the contract cases pin. What the mac does:
  the three contract cases above, nothing else — the `.sh` launchers are
  untouched. Reference: `Install-WindowsSubsystem` in `setup.ps1`,
  `preview.ps1` (where stop mode exits before it can ever run), and
  `deploy.ps1`.

- **Build the 1.0.0 DMG only from a tree containing the deploy-flush fix in
  `scripts/build_site.py`** (Windows + shared, 2026-08-19). A Windows release
  smoke hung FOREVER after "Done processing 272 files" with no error: the
  script's post-copy `os.sync()` is a GLOBAL flush that waits on every
  superblock in the kernel, and under WSL2 all distros share one kernel — a
  leaked FUSE superblock (orphaned by WSLg, no live process holding it, so
  nothing could ever answer) blocked it indefinitely. Diagnosed from the
  kernel stack: `ksys_sync → fuse_sync_fs → request_wait_answer`, python
  sleeping at zero CPU. The fix replaces `os.sync()` with `syncfs()` on the
  host output directory's fd — flushing only the filesystem the site was just
  copied to, which is the only one that step has any business waiting on.

  **The mac is exposed to the same class of failure, not just in principle**:
  Colima mounts `$HOME` into its VM via Lima's FUSE-based sshfs, so a global
  sync inside that VM waits on the host mount daemon every time. Deploys
  succeed today because the daemon answers, not by construction. Nothing to
  implement — the script is shared — but the DMG must be built AFTER pulling
  this commit or the two platforms ship different toolchains for 1.0.0. The
  changed script also changes the image hash, so the first preview/deploy
  after the mac app rebuild does a one-time image rebuild (a few minutes of
  "Building your website builder…") — expected, not a fault.

  Rejected: keeping `os.sync()` (it waits on superblocks wholly unrelated to
  Plantoir); fsync-per-file (hundreds of files over a slow VM mount, and the
  copy is rsync's work anyway); dropping the flush entirely (it exists so the
  host-side deploy step never reads a half-written `public/`). Reference:
  `scripts/build_site.py` → `_sync_public_to_host`.

- ✅ DONE (mac, 2026-08-19, commit "Pin the trail as wired, not merely
  declared"). All three events fire on the mac — verified against the REAL
  trail from the 1.0.0 DMG smoke, not just the code: `opened the working
  folder …`, `started setup.sh` → `finished after 15.2s`, preview
  start/stopped-on-purpose, deploy start/finish with duration all appeared.
  The stronger pin now exists:
  `mac-app/Tests/QuartzTeachersTests/ActivityTrailWiringTests.swift` scans
  the product source and fails if any `ActivityTrail.Event` case is
  referenced nowhere outside its declaration — which turns
  declared-but-never-called from a months-later discovery into a red test.
  (It cannot prove a call site is *reached*; `noteLaunch`'s three events are
  additionally verified as firing by running it against a scratch store.)
  Windows should mirror the scan — see `WINDOWS-HANDOFF.md` → "Pinning the
  trail as wired".
  On pollution: the mac suite does NOT write the real trail, and never did —
  `ProblemReportStore.standard` detects XCTest hosting
  (`XCTestConfigurationFilePath`) and returns a throwaway folder, which also
  covers the HOST APP's launch lines written before any test-bundle code
  loads (the case a Windows-style module initializer runs too late for,
  because the mac test target is app-hosted). Verified empirically: the real
  `activity.txt` was byte-identical (same SHA-1) before and after a full
  suite run. That redirect is now pinned by
  `testTheSuiteWritesToAThrowawayTrail` so a refactor of `standard` cannot
  silently lose it.

  Original request follows, kept for the reasoning:
  **Verify the mac actually EMITS the three trail events the contract pins —
  Windows declared them and never called them** (Windows, 2026-08-19). The
  same release smoke left ZERO lines on the Windows activity trail for a
  course creation, a preview and a deploy: `TaskStarted`, `TaskFinished` and
  `WorkingFolderOpened` existed in `ActivityTrail.Event`, so the contract
  test — which compares the ENUM list against `shared-rules.json` →
  `activityTrail.mustRecord` — passed while nothing ever fired. The list pin
  cannot catch a declared-but-never-called event, on either platform. Please
  check the mac's call sites fire for real (drive one preview, read the
  trail), and consider whether a stronger pin is possible. Windows wiring now
  lives in `windows-app/Plantoir.Core/Scripting/ScriptRunner.cs` (start:
  launcher + redacted arguments; finish: outcome distinguishing success /
  failure / stopped-by-teacher / backed-out-at-a-question, plus duration) and
  `WorkspaceViewModel.ChooseWorkspace` / `AdoptRestoredPath`.

  Related, same session: the Windows test suite was writing fixture courses
  (VVH2O) into the REAL trail — phantom lines a genuine problem report would
  gather. Fixed with a module initializer redirecting the trail before any
  test runs (`windows-app/Plantoir.Tests/TestTrailRedirect.cs`). Worth
  checking whether the mac suite pollutes its real
  `~/Library/Logs/Plantoir/activity.txt` the same way.

- ✅ DONE — SUPERSEDED, nothing owed. **Mirror the stop-sweep guard: await
  in-flight `--stop` sweeps before starting any build** (Windows,
  2026-08-19, GUI-IMPROVEMENTS row 282). An adversarial review the same
  night showed the mac needs none of this: its `PreviewStopper` already
  registers each sweep synchronously at the click and `waitForStopsToFinish`
  re-polls a live list — the two properties whose absence made the Windows
  copy racy. The Windows field failure this entry was written to explain
  turned out to be Windows-local anyway: `ScriptRunner.WaitUntilFinished`
  had been given a DEFAULT 5-second timeout that force-killed every deploy's
  build (row 283) — the sweep was never the killer. Windows has since
  adopted the mac's deploy-during-preview flow outright (row 283). Kept for
  the diagnostic reasoning; act on nothing here.
  Stopping a preview runs the launcher's `--stop` mode fire-and-forget, and
  that sweep kills the section's container-side processes BY WORKING
  DIRECTORY — including `/tmp/quartz-builds/<COURSE>/section<N>` — several
  seconds after the click. A deploy started right after stopping (the only
  order the interface allows, since Deploy needs the preview stopped) puts
  the sweep on top of the deploy's own quiet build and kills it before its
  first output flushes. The teacher sees an instant failure whose transcript
  ends at "Starting container if needed …" — nothing to go on at all.

  Windows reproduced this live during presentation prep and fixed it by
  making `PreviewStopper` track every in-flight sweep (each capped at 15 s so
  a wedged stop child can never hold a deploy hostage) and exposing
  `WhenSweepsFinish()`; the deploy path and both preview-start paths await it
  before launching a build. Reference: `windows-app/Plantoir/Services/
  PreviewStopper.cs`, `windows-app/Plantoir/Views/SectionDetailView.xaml.cs`.

  **The mac has the same latent race**: its `PreviewStopper` is the design
  Windows copied (row 105), equally fire-and-forget, and its `--stop` kills
  by the same working directories. Deploys there succeed today by timing —
  Colima's socket answers faster than WSL2, so the sweep usually lands before
  the next build starts — not by construction. Please mirror the guard.

  Rejected on Windows: teaching the sweep to spare "young" processes (the
  sweep cannot tell a leftover preview build from a new deploy build — any
  age cut-off guesses); retrying the killed build once (hides the mechanism
  and doubles the slowest path); having deploy skip the quiet build when a
  sweep is near (the build is needed; the wait is the honest fix). This
  cannot be a contract case: it is process timing on one machine, exactly
  the platform mechanics the contract's coverage table excludes.

- **A contract case for the summary/detail split — the mac already passes it,
  so this is a pin, not a request** (Windows, 2026-08-18, `windows-sync`).
  Windows has just ported `AssistToolOutcome`'s two-audience split, having
  shipped for weeks without it (see the awareness entry below for what that
  looked like). The behaviour is now pinned on this side by
  `windows-app/Plantoir.Tests/ToolAnswerTests.cs`, and it is NOT pinned by
  anything shared — which is how the two apps came to differ on it in the
  first place.

  What is wanted is a case list both suites run: for each of the thirteen
  tools the local model is shown, the sentence a TEACHER reads, against the
  longer answer the model gets. It could not be proposed from here with any
  confidence, and the reason is worth recording rather than re-deriving:
  `scenarios` and `nearMisses` are the authored halves of
  `assist-cases.json`, and both are shaped around the agent LOOP —
  `given` / `when` / `expectReply: "wording.X"` — where this is about what
  ONE tool returns, keyed to a course fixture the two suites do not share. A
  new top-level key would be the honest shape, and whether the generator
  preserves one is knowable only on the mac, where `--write-contracts` runs.
  **Please decide the shape and add it**; the Windows tests will be rewritten
  against whatever lands. The wordings to pin are in the awareness entry
  below.

  Rejected here: proposing it under `scenarios` anyway. A case the generator
  might silently eat is worse than no case, because the next person reads a
  green suite as proof.

## For awareness — no mac code needed

- **Item 40 is closed. Two things to know: xUnit's `Assert` throws where
  XCTest records and carries on, and Windows edited one sentence of authored
  prose in `shared-rules.json`** (Windows, 2026-09-08, branch
  `issue/folders-help-row-check-cases`). **Nothing for the mac to implement**
  — the mac made this fix first, on 2026-09-06 (`GUI-IMPROVEMENTS.md` row
  446), and its test is unchanged. Full entry in the ledger below; this is the
  pointer to it.

  **The harness difference is the half worth carrying.** An instruction telling
  Windows to keep going after a recorded failure — item 40's "the count
  guard must `continue` not `return`" was exactly that — describes a
  behaviour XCTest has and xUnit does not, so a literal port makes the guard
  dead code and reports one failure where the mac reports several. Worth a
  sentence in the next such item rather than being rediscovered.

  **The contract edit, so it is not met as a surprise in a diff.** The
  curriculum row's `whyPlaceholder` ended by naming Windows' single-course
  check and pointing at item 40 — true when the mac wrote it, stale the
  moment Windows closed the item. It now reads "Both apps have done this since
  2026-09-08 - the mac from 2026-09-06, Windows on closing item 40 in
  WINDOWS-HANDOFF.md." **Windows edited it directly, and a first draft of this
  handoff wrongly asked the MAC to do it**, on the reasoning that
  `shared-rules.json` is generated and a Windows edit would be reverted by the
  next `--write-contracts`. That is false and was caught on review:
  `contracts/README.md` says three files are generated and the rest are
  authored, `shared-rules.json` among them; nothing in the mac source writes
  it; and `whyPlaceholder` is read by no test on either platform, so nothing
  goes red. Reword it if the phrasing is not how the mac would put it — it
  is the mac's prose — but no regeneration is owed. (`CLAUDE.md`'s own
  table said "never hand-edited" as a blanket claim, which is what the draft
  followed; that line is corrected on this branch too.)

- **Item 39 answered: `Plantoir.UiTests` cannot crash its host the way the
  mac's suite did — measured — and the strengthened `oneAlertAtATime` reason
  has one clause the mac should NOT weaken further** (Windows, 2026-09-08,
  branch `issue/ui-test-host-crash-signal`). This closes `WINDOWS-HANDOFF.md`
  item 39, which asked for exactly two things: a look-and-see, and a re-read.
  Both done. **Nothing for the mac to implement**, but three things are worth
  knowing, and the third is a request.

  **1. The mac's shape is structurally impossible here, and that was measured
  rather than reasoned about.** On the mac the test bundle is injected INTO the
  app, so the app's crash IS the host's crash. `Plantoir.UiTests` launches the
  real `Plantoir.exe` as a SEPARATE process and drives it over UIA3 COM
  (`windows-app/Plantoir.UiTests/DrivenApp.cs`). A throwaway probe killed the
  driven app mid-test and then touched its window: the result was an
  `InvalidOperationException` after `DrivenApp`'s 30 s patience — an ordinary
  test failure, 54 s, host untouched. The full opt-in suite then ran 11 of 11
  green in **5 m 17 s** with no host death. So: re-running a flaky UI test here
  IS the right response, which is the opposite of the advice that applies to a
  mac host crash.

  **2. What the mac sent over — "the honest signal is the TOTALS, never the
  exit code" — turned out to be true here too, and nothing was reading them.**
  Measured on this machine (Lenovo 20QES70500, Intel Core i5-8365U @ 1.60 GHz,
  16 GB; Windows 11 Pro 26200, .NET 9 SDK, xunit 2.9.2, Microsoft.NET.Test.Sdk
  17.12.0) by putting each failure in deliberately, same project, same command:

  | | Exit code | Totals line |
  |---|---|---|
  | Test host dies (`Environment.FailFast`) | **1** | **absent**; says `The active test run was aborted. Reason: Test host process crashed` and `Test Run Aborted.` |
  | An ordinary failing assertion | **1** | `Failed!  - Failed: 1, Passed: 0, Skipped: 0, Total: 1, Duration: 17 ms` |

  Identical at the exit code, completely different in the output — the same
  asymmetry `xcodebuild` has, in different words. The reference implementation
  is `windows-app/TestRunOutcome.ps1`, shared by `run-ui-tests.ps1`, the new
  `run-tests.ps1` and the untracked `batch/run-batch.ps1`, which until now
  would have reported a dead host as **"TESTS FAILED (0 failed)"** — the exact
  shape of the mac's `exit 65` with `0 failures`. (That last claim is one
  nobody can check afterwards, including me: `batch/` has no history, which is
  the very thing the next paragraph is about.) Its own checks run inside
  `dotnet test` (`TheTestRunReaderTellsACrashFromAFailure`), on fixtures pasted
  from real output rather than written from memory.

  **One design point worth stealing, and it is the reason this is here rather
  than in a commit message.** Both platforms keep their batch driver OUTSIDE
  git — the mac's `overnight/` and Windows' `batch/` are both untracked — so
  crash-detection logic living inside the driver is logic the other side cannot
  read, cannot test, and loses whenever the driver is regenerated. Windows has
  split it: the READING is a tracked, unit-tested function; the untracked
  driver only calls it. If `overnight/run.sh` still carries its HOST-CRASH
  regex inline, the same split would make it reviewable. Offered, not owed.

  A verdict the mac does not have and might want: **`RanNothing`**. A suite
  that finishes having executed nothing is not green, and it has a second dress
  beyond `Total: 0` — an opt-in suite whose switch did not take reports every
  test *skipped* and a healthy-looking Total. Counting `Total` alone calls that
  a pass.

  **3. The request. `siteHealth.repair.oneAlertAtATime`'s reason was
  strengthened to say the mac CRASHED, and it now half-dismisses the clause
  that is the Windows failure mode. Please keep that clause.** The re-read
  found Windows compliant — but by a different mechanism, and the write-up
  would be wrong if it said "same as the mac":

  - Windows obeys the rule as written — the outcome is presented only after
    `await ShowHealthDialogAsync(...)` has returned, never from inside the
    dialog's button action — but ordering ALONE is not enough here, which is
    the part worth knowing. WinUI's `ShowAsync` completes when the dialog
    BEGINS closing rather than when it has gone, so the second request can
    still land while the first is dismissing; it survives because
    `ShowHealthDialogAsync` RETRIES five times at 150 ms
    (`windows-app/Plantoir/Views/SectionDetailView.xaml.cs`, whose doc comment
    says exactly this). Ordering plus a retry, not a retry instead of
    ordering.
  - So AppKit's consequence is a crash and WinUI's is a refusal — and a refusal
    is swallowed by `ShowDialogSafelyAsync`, which loses the report the teacher
    just pressed a button for. **That is precisely "asking for a second while
    the first is dismissing loses one of them"** — the clause
    `WINDOWS-HANDOFF.md` item 39 glosses as having "understated" it. It
    understates the MAC. It is exact for Windows.

  To be fair to the contract: it already keeps both halves —
  `siteHealth.repair.oneAlertAtATime.why` states the lost alert in full and
  then adds "It is worse than a lost alert: …". Nothing needs changing today.
  This is only a request for the next edit: if that reason is ever rewritten to
  be about the crash alone, Windows loses the only written statement of the
  failure it actually has.

  Two smaller things found on the way, neither in item 39's scope and neither
  acted on: `SidebarPane.xaml.cs`'s post-rename notice is fired as
  `_ = ShowDialogSafelyAsync(...)`, so a refusal there is lost silently; and
  `dotnet test`'s exit 1 is in fact THREE-way ambiguous, not two — a test
  failure, a dead host, or a test project that failed to compile. The reader
  above reports that third case as `NoResult` rather than calling it a pass or
  a failure.

- **Windows now clicks the New Course wizard's Create button in a running app,
  and found that a GUI app started from a console cannot shell out at all**
  (Windows, 2026-09-07, branch `issue/35-first-run-ui-checks`, handoff item 35).
  **Nothing for the mac to do**, and no contract case: this is a test suite and
  a platform mechanic. Two halves of it are worth knowing anyway.

  **The trap, which is the part that might save the mac an afternoon.**
  `Plantoir.UiTests` launched the app with `UseShellExecute = false`, so the
  `dotnet test` host's PIPE std handles reached the app and leaked into the
  ConPTY child: the app captured nothing, what it sent the launcher never
  arrived, and `input()` in `setup_course.py` reached EOF and died. It
  presents as "failed (exit code 1) after 1s" with an empty transcript, which
  reads as a broken toolchain and is not. `ConPtyProcess.Start` already
  carried the rule in a CAUTION — the child binds to the pseudo console only
  when the CREATING process's std handles are clean, "console handles or
  none" — and the first version of this write-up ignored it and blamed an
  inherited CONSOLE instead, which is wrong. Three launches of one build
  settled it (Lenovo 20QES70500, Intel Core i5-8365U @ 1.60 GHz, 16 GB):
  clean console handles → course made, 21 s; ShellExecute → the same, 21 s;
  output redirected to a file → nothing captured, hung, no course. **An
  ordinary terminal is fine; redirecting is not.**

  The mac has no ConPTY, so this is not a mac bug — but the general shape is
  not platform-specific, and a mac session that ever drives the app from a
  test HOST rather than from Finder should know the failure mode exists,
  because nothing about the symptom points at the cause. Deferred rather than
  fixed, in `TODO.md`: whether `ConPtyProcess.Start` should zero the creating
  process's std handles across `CreateProcessW`.

  **And the half Windows did NOT automate, with the reasoning, so nobody
  proposes it again.** The other path item 35 named is the dialog a
  BRAND-NEW section's first publish raises, where a teacher chooses their
  website address; it is now a hand-driven check with a written procedure
  (`documentation/12-windows-app.md`, "The new-site dialog: a hand-driven
  check") rather than a test. The reason that settles it is not the obvious
  one: `deploy.ps1`'s Credential Manager target is hardcoded and `--state-dir`
  does not redirect Credential Manager, so whether a test reached the dialog
  or **published a real website** would depend on whether the machine happened
  to have a token saved. Also rejected, each for its own reason: a fake token
  (the launcher validates it against Netlify before `deploy.py` starts, so it
  raises "Connect to Netlify" instead); a stub `deploy.ps1` (the app rewrites
  any launcher that differs from its bundled copy, on every workspace reload);
  and leaning on `verify-deploy.ps1` (it redirects stdin from a file precisely
  so `deploy.py` asks nothing). What NOT to check by hand, either platform:
  the dialog's title, explanation and steps are already contract data
  (the `siteName` entry in `app-rules.json`'s `credentialRequests.requests`)
  asserted by equality; what nothing pins is the ORDER, the pre-filled
  address, Cancel's behaviour, and that the created site carries the typed
  name. **One thing the mac inherits free:** that sweep was skipping
  `explanation` — the longest sentence in these dialogs — on both platforms,
  and Windows added the assertion on 2026-09-07 (green across all seven
  requests). The mac's own credential-request test is worth a look for the
  same omission. The one thing the mac is actually ASKED to do is in
  "Open — what the mac still owes" rather than buried here.

- **Rename Course lives in Windows' FILE menu with F2, not in an Edit menu
  with no key — a chosen divergence on two counts, not drift** (Windows,
  2026-09-07, branch `issue/30-polish-delete-crumbs-rename`, item 30 (c);
  `GUI-IMPROVEMENTS.md` row 440). **Nothing for the mac to do.** On Windows a
  top-level Edit menu conventionally holds Cut/Copy/Paste, and one holding a
  single Rename Course reads as broken; File already holds a selection-scoped
  action ("Restore from Archive…"), so it is the established home. And the
  mac omits a key for an AppKit reason — a bare Return as a menu key
  equivalent is matched by AppKit before the key reaches the responder chain,
  so it would be taken AWAY from every text field and default button
  (`EditCommands.swift`) — that does not exist on Windows, where the item
  asks for a keyboard route; F2 is Explorer's rename key. (The brief had that
  reason the wrong way round; the review caught it.) Rejected: an Edit menu for
  parity; no key for parity; a new Course menu for one item. The item is
  dimmed WITH its reason, the way the course menu does it (a disabled row
  holding `CourseActivity.BusyReason`), renames the parent course when a
  section is selected (the mac's `courseThatCanBeRenamed`), and F2 is scoped
  by asking `FocusManager.GetFocusedElement` first: a TextBox, RichEditBox,
  PasswordBox, AutoSuggestBox or NumberBox keeps its F2 and the accelerator
  leaves the key unhandled. Two blind spots, named: focus inside the
  WebView2 preview reads as the WebView2 element, so F2 typed into the
  previewed site's own search box would open the rename (if the WebView2
  passes the key through at all, which was not measured); and F2 with another
  dialog open fails silently, because `ShowDialogSafelyAsync` swallows the
  second dialog. One limit, said plainly: WinUI's MenuBar has no Opening
  event and `CourseActivity` raises no change event, so the dimmed row is
  redrawn on selection change, on window activation and on every re-apply of
  the window's state — a preview started while the window sat idle leaves the
  item enabled until then. That is why the click has NO silent busy guard: the
  rename dialog re-checks and explains ("…is previewing or deploying right
  now. Stop that first, then rename."), the same answer the sidebar's route
  gives, rather than a menu that simply closes.

  The two decisions this item raises for the mac are at the top of "Open",
  where a mac session will find them.

- **Windows' two synced-folder views are built, and one thing about the store
  behind them is worth knowing before a privacy question arrives** (Windows,
  2026-09-07, branch `issue/18-cloud-synced-folder-views`; item 18 struck;
  `GUI-IMPROVEMENTS.md` row 436). **Nothing for the mac to do.**
  `AppSettings.AcceptedSyncedFolders` holds FULL folder paths in
  `settings.json`, keyed by resolved path, with no cap and no "forget these"
  affordance — the contract's `rememberedPerFolder` rule says the list is
  never pruned, and that is what it does. It is the same shape as the mac's
  remembered-per-folder store, recorded here because a list of a teacher's
  folder paths in a settings file is the kind of thing somebody asks about
  later, and the answer should be "yes, on purpose, and here is why".

  Two decisions the brief left to the session. **Two windows on the same
  folder**: a note shown in one window — either form — is not shown again in
  any other window of the process for that resolved path
  (`MainWindow._syncNoticedThisProcess`, consulted by the one function both
  moments ask, `SyncNoteWanted`), and an answer given in one window closes
  the notice still open in another (`App.HideSyncNoticesFor`), as the mac's
  `WorkspaceModel` does. **The InfoBar at 900×600**: a first draft overlaid
  it on the content area, and the review read off the XAML that it would sit
  exactly over the section toolbar — Preview and Deploy hidden and
  unclickable until dismissed. It is now a row of its own between the menu
  bar and the content; the content row is the star-sized one, so the notice's
  height comes out of the content and the path bar cannot be pushed off
  screen. The mac's inline-banner regression was an unbounded SwiftUI text
  height, not a reason to avoid a row. Not measured on screen: the row's
  height at the minimum size with "Show Details" open wants one look.

  **One divergence from the brief, in the contract's favour.** The brief said
  "record the service name, not the folder"; the contract's `carries` for
  `synced folder noticed` says the service AND the folder path, redacted, and
  the mac writes it that way. Windows now does too — the trail redacts on the
  way in — so a teacher with two synced folders can tell from the trail which
  one was noticed.

- **Windows brings the main window forward for an assistant-driven build
  ONLY when it was minimised or hidden — a chosen divergence from row 300,
  not an oversight** (Windows, 2026-09-07, branch `issue/28-four-small-gaps`,
  item 28 (b); `GUI-IMPROVEMENTS.md` row 433). **Nothing for the mac to do;
  read so the difference is not "fixed" into parity.**

  The mac activates unconditionally. On Windows the assistant is a separate
  top-level window the teacher may still be typing in, so an unconditional
  `Activate()` would take keyboard focus mid-sentence to show them a build
  that was, in the common case, already in view beside them. Rejected: full
  activation for parity (that cost, for no gain when the window is visible);
  a taskbar flash only (on a maximised assistant window the build stays
  invisible until the teacher acts, which is the original complaint); and
  fixing only the two doc comments that described a behaviour never built.
  The test used — `MainWindow.ComeForwardIfHidden` — is exactly two cheap
  checks: `OverlappedPresenter.State == Minimized`, and `AppWindow.IsVisible`
  false. A window fully covered by another window is NOT detected; there is
  no cheap answer to occlusion on WinUI and guessing wrong steals focus. When
  the main window has been closed under the assistant, a build goes to another
  window on the same working folder if one is open, else a new one is opened
  and used by identity (row 300's trap). Not driven by hand: the minimised and
  no-window paths want one look at the real interface.

- **Two smaller things from the same item, both now matching the mac.** (a)
  The sidebar's "Schedule Deploy…" dialog on Windows now says which classes
  are still unpublished — the same content `ScheduledDeploy.Describe()` has
  always given the assistant and the mac's sheet has always rendered
  (`ScheduleDeploySheet.swift`, `plan.description`). A first draft filtered
  the list by the chosen day; the review caught that the contract's
  `scheduledDeployRefusals.alsoSaid` rule has no date qualifier and the mac's
  `unpublishedClasses(course:sectionNumber:)` names every one, so Windows
  does too. Advice, not a refusal: the button stays enabled, and while a
  refusal is showing the advice is hidden, as the mac shows the problem
  alone. One difference, recorded rather than fixed: Windows names pages by
  FILE name, as its own `PlanScheduledDeploy` already does, where the mac uses
  the page's title. If that ever matters, it wants a case, not two fixes.
  (d) The Windows assistant window remembers its placement per section
  (row 164's rule) in a type deliberately separate from the windows replayed
  at launch, so a multi-gigabyte model is never loaded unasked; it clamps to
  the displays that exist now and prunes with the working folder. Nothing
  the mac need change.

- **Windows now spells a renamed folder the way Quartz reads it — item 31's
  debt is paid, and the escaping rule is executed on both sides**
  (Windows + shared, 2026-09-07, branch `issue/31-rename-link-escaping`,
  commit `2bed7c83`). **The mac is expected only to KNOW this**; no Swift
  changes, and one new contract case that should already be green here (see
  "Contract cases waiting on the mac", at the top of this file).

  **What was done.** `Spelled` in
  `windows-app/Plantoir.Core/Models/FolderPathRewriter.cs` called
  `Uri.EscapeDataString`, which keeps only `A-Za-z0-9-._~`. It is replaced by a
  `PercentEncoded` driven by the contract's own
  `specialNames.renameFolder.linkRewriting.escapingSet.leaveUnescaped`, in BOTH
  of `Spelled`'s branches. Three cases had been failing there — the ampersand,
  the comma and the question mark — and `FolderPathRewriterTests` now
  deserialises every case instead of retyping five of them.

  **WHY it was two changes and not one, which is the part that travels.**
  Fixing the encoder without wiring the cases would have been invisible —
  nothing on that side went red, which is how three failures sat there for a
  day. And wiring the cases without fixing BOTH branches would have looked
  finished: of the original eleven, eight take the FIRST branch (a space or a
  bracket in the new name) and three reach no encoder at all — `Assignments`
  and `Café` need no escaping, and the wikilink case is not a Markdown link.
  None of them reaches the second branch, so a framework call left behind there
  passes the lot. That is what the twelfth case is for.

  **Two habits from item 29 earned their keep again, and the second one is
  new.** Asking the list both ways found nothing here — the code had no rule
  the contract lacked. What DID find something was pinning the code's copy of
  the set against the contract's string directly
  (`TheEscapingSetIsTheContractsCharacterForCharacter`): a behavioural walk over
  `leaveUnescaped` can only test the characters the CODE already has, so adding
  `#` to the constant would leave every other test green. **The mac's
  `testEveryCharacterTheContractLeavesAloneSurvivesARename` has exactly that
  hole**, and closing it there is a two-line test against
  `charactersThatSurviveQuartzUndecoded` — offered, not owed.

  **Numbers.** 1125 passed, 2 skipped, 0 failed on the Windows unit suite; 1031
  passed before. +94: twelve contract cases, seventy-seven characters of the
  escaping set, and five new facts. Windows 11 Pro 26200, .NET 9, `dotnet test`
  in 12 s.

  **What was REJECTED.** *Encoding character by character rather than by UTF-8
  byte* — a `char` loop splits a surrogate pair and writes two invalid
  sequences for one letter; every byte at or above `0x80` is outside the allowed
  set by construction, so the byte test is exact and simpler. *Keeping
  `Uri.EscapeDataString` in the second branch* — it is the older rule ("a
  segment that arrived encoded goes back encoded") and it is tempting to leave
  alone, but the rule is about WHETHER to escape, not about how, and the mac has
  always used one encoder for both. *Adding `%` to
  `WouldBreakAMarkdownTarget`* — explicitly refused by the contract; Quartz
  never sees a bare `%`. *Deleting the five hand-typed facts once the theory
  ran them* — they are what a reader searching for "what broke" finds by
  name, and two of their assertions have no contract case behind them at all;
  `TheHandWrittenAnchorsStillMatchTheContract` keeps them tied to the contract
  instead.

  **One divergence found and deliberately NOT fixed**, so it is not
  rediscovered as a puzzle: the mac's `rewriting(_:folderNamed:to:)` trims
  whitespace from `oldName` and `newName` and the C# `Rewritten` does not. It
  is pre-existing on both sides, unreachable in practice (`SpecialFolderRenamer`
  refuses a trailing space before a rename can happen), covered by no contract
  case, and changing behaviour unattended is not this item's job. If it is worth
  settling, it wants a case rather than two independent fixes.

  Reference: `windows-app/Plantoir.Core/Models/FolderPathRewriter.cs`
  (`PercentEncoded`, `CharactersThatSurviveQuartzUndecoded`, `Spelled`) and
  `windows-app/Plantoir.Tests/FolderPathRewriterTests.cs`. The mac's is
  `spelled(_:likeThe:in:)` / `percentEncoded` in
  `mac-app/QuartzTeachers/Models/FolderPathRewriter.swift`.

- **The prose every Windows session plans from was corrected, and one habit
  is worth stealing** (Windows, 2026-09-06, branch
  `issue/docs-handoff-and-progress-corrections`). **No mac code, no contract
  change, no `.cs` touched at all** — this is a documentation pass, listed here
  because one of its findings is a failure mode this side has exactly as much
  of. Reference: `WINDOWS-HANDOFF.md` items 10, 16 and the new 35–37 (numbered 33–35 when written; the mac's own
  items 33 and 34 landed first);
  `windows-app/PROGRESS.md`'s "Where parity stands"; `contracts/README.md`'s
  Windows table.

  **What was wrong.** An audit of the two documents a Windows session reads
  before planning found four false statements. Item 10's caveat said the
  folder-problems front end "is item 21, which is not built" — item 21 landed
  the same week and `FolderProblemsDialog.cs` has existed since, so anyone
  planning from item 10 believed the findings still reached nobody. Item 16 was
  struck through with a rider reading "**NOT yet done**", carrying a live
  obligation inside an item the eye skips. `PROGRESS.md` said "sixteen of its
  twenty-four items are done" when the list held 32 with eleven open, and its
  "what is genuinely left" table named four of them, missing seven entirely.
  And `contracts/README.md`'s Windows table had no row for
  `specialNames.renameFolder.linkRewriting`, which was added to the contract
  the same day as the audit that built the table and fell outside its sweep.

  **The sentence worth carrying**, which is the whole reason this is in the
  ledger rather than a commit message: **an item struck through with live work
  inside it is invisible, and a status line that has drifted from the code is
  worse than no status line, because it gets believed.** Both files are read
  top-down and abandoned partway — that is what they are FOR — so a
  correction buried below the point a reader stops is not a correction. This
  side has the same shape of exposure in `MAC-HANDOFF.md`'s own first two
  sections; the v1.1.0 cut sheet at the top of this file sat as an open
  instruction for seventeen days after the release shipped, which is the
  identical failure pointing the other way.

  **What was rejected.** Un-striking item 16 so its rider would be visible:
  rejected, because item 16 itself IS done and the obligation belongs to item
  13, which is open and was being worked the same night. Two items claiming the
  same work is how the count drifted in the first place; the rider now says
  plainly that item 16 owes nothing and names item 13 as where the work is
  tracked. Also rejected: writing an absolute pass/fail into `contracts/README.md`
  for whether `FolderPathRewriterTests` deserialises its eleven cases. **That
  row and the wiring that makes it true landed in the same overnight batch**
  (Windows item 31), so any status sentence written there would have been wrong
  in one direction or the other by morning. The row names the list and the
  class and points at item 31's struck-or-not state for the answer, which is
  the one fact that cannot go stale. The same reasoning changed one line of
  `documentation/09-mac-app.md`, which described those eleven cases as ones
  "both apps run" — true of the mac, not yet of Windows.

  **What the mac is expected to do: nothing.** One thing this audit surfaced IS
  the mac's, and it is already in the Open section above rather than duplicated
  here — the Course Settings tip sentence, pinned by no contract on either
  platform and worded differently by the two apps. It is now indexed on the
  Windows side as item 37 as well, recorded honestly as waiting on the mac's
  choice with nobody having picked it up. Windows owes only taking the mac's
  wording verbatim once it is chosen.

- **`workingFolderPathBar.ancestorPaths` now carries `windowsCases`, and two
  rules were being pinned by nobody on either side** (Windows + shared,
  2026-09-06, branch `issue/29-windows-contract-case-lists`). **The mac suite
  stays green** — one authored list added, nothing changed. Reference:
  `SharedRuleContractTests` in `windows-app/Plantoir.Tests/`.

  The path bar's cases were `/Users/teacher/…` with the Windows spelling left
  as a prose `windowsEquivalent`, so this side hand-typed its own crumbs in
  `ContractTests`. `windowsCases` says the same thing as DATA — three cases,
  including one on a second drive, since `D:\` is an ordinary place for a
  teacher to keep their courses and its root is not `/`. The RULE is shared
  ("every ancestor, root first, folder last"); only the spelling of a root is
  the platform's, and that is exactly what a per-platform case list is for.

  **Two lists the contract carried that neither suite ran**, now run here:

  - `buildOutputLocation.windowsLocation.buildsRoot`. Its own note said it was
    "asserted by nobody on either side", and it stayed that way for the obvious
    reason — it describes a Windows path, so the mac cannot check it and nobody
    on this side had. It is now checked against `BuildOutputLocation.BuildsRootFor`,
    including that the folder identifier is ONE path segment and stable for a
    given working folder, which is what makes a course's build location
    resolvable from both sides.
  - `scheduledDeployRefusals.alsoSaid` — "list the class pages students cannot
    see yet, by name". `ScheduledDeploy.Describe()` does. **This list is not on
    item 29's own inventory**: the audit that opened the item missed it, which
    is worth knowing because it is the second time a list has gone unnoticed
    for want of being indexed rather than for want of being implementable.
    (Item 28 records separately that this side's interface does not yet CALL
    `Describe()`. That gap is real and this test cannot see it: the test
    project references `Plantoir.Core` and `Plantoir.Mcp`, never the interface
    project — the honest limit of everything wired in this branch.)

  **Rejected, and worth recording so they are not proposed again:**

  - *A `windowsOrigins`-style mirror for the path bar* — a second list on this
    side rather than a case list in the contract. Rejected for the reason the
    marker-origins one was: the RULE is shared and only the spelling of a root
    is the platform's, so the contract is the right home and a mirror would be
    a second one.
  - *Creating a real Windows scheduled task to prove the rename cancels it.*
    That puts a job on the machine, and `CourseRenamer.Rename` would then
    delete a real one — so what is asserted is the notice a teacher reads, on a
    hand-built outcome, and the course code in the test was changed to one no
    real task could carry. Proving the cancellation itself wants a seam in
    `TaskScheduling`, which is a product change and not this branch's.
  - *Walking a payload's trees recursively.* `setup_course.py`'s
    `top_level_allowed` filters only the TOP level and copies whole folders
    below it, so a recursive walk would report files the installer does in fact
    install.

- **`--image` is the mac's flag alone, and the contract listed it as shared;
  and a completeness check the mac may want** (Windows + shared, 2026-09-06,
  branch `issue/29-windows-contract-case-lists`). **The mac suite stays green**
  — the flag entry gains a `macOnly` note, nothing is removed. Reference:
  `PublishAndLauncherContractTests` in `windows-app/Plantoir.Tests/`.

  `launcherFlags.deployExtras` named `--diagnose` and `--image <tag>` as flags
  the launchers must both accept. `deploy.sh` parses `--image`; `deploy.ps1`
  does not, and cannot — Windows has had no image to name since it dropped
  Docker on 2026-08-19. Recorded as `macOnly` rather than closed by adding a
  dead flag to `deploy.ps1` so a test would go green, which is the shape of fix
  `WINDOWS-BOOTSTRAP.md` §0 exists to forbid.

  **The part worth copying is the shape of the tests, not the finding.** Both
  suites had been walking the contract and asking "does the app do this?" —
  which cannot notice a case, request or flag the app has and the contract does
  not. Three checks here run the other way:

  - **By reflection over the real definitions.** Every `CredentialRequest`
    declared in the code must be described in `credentialPrompts.everyRequest`.
    A request added and not written down is one the other app cannot show, so
    the same first publish stops at a prompt on one platform and asks properly
    on the other. `AssistToolSurface` would take the same treatment, and it is
    the same hole the MCP-tool drift below went through.
  - **By a name map, not a drained set.** `whenShown`'s nine cases are answered
    by nine named tests, checked by reflection: a case the mac ADDS fails here
    naming itself. A `HashSet` filled by ten tests and emptied by an eleventh
    would have been the obvious shape and is wrong — xUnit builds a fresh
    instance per `[Fact]` and fixes no order, so such a set passes or fails on
    what happened to run, and reports nothing under `--filter`.
  - **Against the parser, not the help text.** `--diagnose` appears three times
    in `deploy.ps1`, twice of them in usage prose, so plain containment stays
    green after the flag stops being accepted — which is exactly when a
    teacher's publish "just does not start".

  **Two `whenShown` cases had no answer on this side at all** and now do:
  `course_config.json has changed`, and the accepted false negative where a
  page restored from a backup keeps its size and modification date. The second
  is worth having as a test precisely because it asserts the LIMIT — if it ever
  starts reporting an edit, the fingerprint has begun reading file contents,
  which is a real cost paid every time a window comes to the front.

- **A field both apps have always written was named in no contract:
  `sectionTimetable.fields` listed three of four** (Windows + shared,
  2026-09-06, branch `issue/29-windows-contract-case-lists`). **The mac suite
  stays green** — the field is now described, not changed. Reference:
  `FileFormatContractTests.TheRememberedTimetableIsWhereTheContractSaysAndCarriesItsFields`.

  `courses/<CODE>/.internal/timetable/section<N>.json` carries `section`,
  `dates`, `source` and `recorded`. The contract named the last three. Both
  apps write all four — the mac's `SectionTimetable` encodes `section` and
  reads it back with the filename's number as a fallback; Windows' `Stored`
  record writes it and does not read it — so nothing has ever been wrong, and
  that is the point: **a field two apps write and no contract describes is one
  a third reader drops without anybody noticing.** It is now described,
  including why it is redundant with the file's own name and worth keeping
  anyway (a timetable copied out of its folder still says what it is for).

  Found by wiring the list into the Windows gate rather than by reading it,
  which is the argument for item 29 in miniature: the list had been correct
  enough to pass every inspection and was never executed against a real file.

- **Two shared-Python progress markers were classified nowhere, and
  `markerOrigins.knownDivergence` had been stale since the native runtime
  landed** (Windows + shared, 2026-09-06, branch
  `issue/29-windows-contract-case-lists`). **The mac suite stays green.** It
  reads `origins`, but only to look up the markers its own lists use, and it
  never uses these two; `knownDivergence` is read by no Swift at all. So this
  is a know, not an ask.
  Reference: `windows-app/Plantoir.Tests/MilestoneContractTests.cs`.

  Wiring `markerOrigins` into the Windows gate (WINDOWS-HANDOFF item 29) turned
  up two markers that `scripts/setup_course.py` prints — `"Example Course
  installed to"` and `"EXAMPLE_COURSE_CODE="` — and that
  `markerOrigins.origins` did not classify. Both are now in it as
  `shared-python`.

  **Why they went missing is the part to keep** — and my first write-up of it
  was wrong, corrected here after review. It is not that the mac has no
  example-course task: `TaskMilestones.exampleCourse` has existed since
  2026-08-23 and holds exactly these two markers. It is that
  `AppRulesContract.milestones()` does not list it, so the generated readout
  carries eight tasks where the mac has nine. The mac's classification test
  walks the READOUT, so a marker missing from there is invisible to it however
  loudly the shared script prints it. **A classification is only as complete as
  the list it is checked against**, and nothing checked that list against the
  code it was a readout of. The one-line fix is under "Open" above.

  The Windows test is written the other way round as well as the same way: a
  marker the contract does not name, which something under `scripts/`
  nevertheless prints, FAILS and says to classify it. That reverse direction is
  what found these two, and it is worth adding on the mac — it does not depend
  on the readout being complete, which is exactly why it saw what the forward
  check could not.

  **`knownDivergence` was one stale pair.** It said `"Setting up this Mac"` →
  `"Setting up this PC"`, and Windows stopped printing that string on
  2026-08-19 when it dropped Docker for the native runtime — so the contract's
  only record of how the two platforms' launcher text differs described a
  correspondence that no longer exists, and the container markers it did not
  mention have no Windows counterpart at all. It now carries a `note` and
  `macOnlyLauncherMarkers`: the five strings a Windows milestone must never
  watch for.

  **Why a LIST of the mac's wording, rather than Windows' own text in the
  contract.** Windows' launcher markers are the platform's, not the product's,
  so by `contracts/README.md`'s own test they do not belong here, and they are
  pinned against the real `.ps1` files by `TaskMilestoneLauncherMarkerTests`
  instead. What does belong is the guard: Windows had a hand-typed array of the
  mac's five phrasings, and a hand-kept copy of the OTHER platform's words is
  precisely what goes stale the day that platform changes them — which is how
  four markers came to be matched against launchers that had stopped printing
  them (WINDOWS-HANDOFF item 5). That array is gone; the test reads the five
  from here. If the mac ever renames one of its launcher lines, changing it
  here is what tells Windows.

  **Rejected: a `markerOrigins.windowsOrigins` map.** It would have put six
  facts in two places — the contract and `ParsingTests.LauncherOnlyMarkers` —
  validated by nobody on the mac, which is the four-copies problem this folder
  exists to end. Caught in review before it was written.

- **A UI test suite that drives the real app, and `--state-dir`, the product
  change that made it safe** (Windows, 2026-09-06, branch
  `issue/windows-special-folders-help`, `GUI-IMPROVEMENTS.md` row 423).
  Mostly a **know**. The mac owes nothing unless it wants the same coverage —
  but if it ever does, everything below was learned the expensive way and the
  design transfers almost unchanged.

  **What the tests are FOR, which is the part worth copying.** The unit suite
  already runs every contract case against the rule, and the view writes no
  sentence of its own, so re-running that sweep through a real window proves a
  pure function slowly. Six tests cover only what a unit test cannot see:

  1. **The control can be REACHED.** Invoking a button fires its action
     whether or not it is on screen, so "the element exists" passes for a
     button scrolled off the bottom of a long form and never seen by anyone.
     The test scrolls the form until the button is really visible, and checks
     it against the FORM's viewport rather than the window's — a control below
     the fold is inside the window and still invisible.
  2. **Clicking it opens anything at all.**
  3. **The RENDERED text equals the contract's rows in the contract's order** —
     as one ordered sequence, not row by row. This is the strongest assertion
     in the suite and it subsumes several weaker ones: it catches a duplicated
     row, a missing one, and two that have swapped places.
  4. **The bottom of a scrolling list is not cut off.** The sheet's scroller
     is capped, so the last rows START off screen. Scroll to the end, then
     assert the last row is inside the SCROLLER's rectangle.
  5. **It follows the selected course rather than going stale** — the one
     genuine gap, since the window reuses a settings view when the code
     matches.
  6. **It can be dismissed** by its own button.

  **What was tried and dropped, so the mac does not spend the afternoon
  again.** Testing Escape: a keystroke goes to whatever holds the foreground,
  which a test machine cannot promise, and it failed a DIFFERENT test each run
  for reasons unrelated to what that test checked. Closing a sheet on Escape
  is the FRAMEWORK's behaviour anyway, not the app's. Dismissal in the suite
  is now the boring reliable button.

  **Three measured facts about the automation layer**, all of which cost a
  cycle here and at least the first two of which have AppKit equivalents:

  - **A plain stack of views has no automation element.** The dialog's seven
    "rows" do not exist as far as UI Automation is concerned — its contents
    arrive as one flat run of text elements. That is why case 3 is a sequence.
  - **A dialog's own element covers the whole window**, because it carries the
    dimming layer. So "is this text inside the dialog" is very nearly "is it
    inside the window", and a row clipped by the scroller satisfied it. Assert
    against the SCROLLER.
  - **A container's automation identifier can be replaced by its own template
    part name.** The sidebar's tree carries an id in the markup and reports a
    framework part name instead, so an identifier set on a complex control is
    worth MEASURING before a test relies on it.

  **`--state-dir`, and why it is one flag rather than two.** A UI test drives
  the SHIPPED binary, so without isolation it rewrites the teacher's working
  folder, remembered windows and window geometry, and files its fixture
  courses in the breadcrumb trail as though a person had opened them. The flag
  moves the app's ENTIRE state folder for that run.

  Rejected, with reasons: redirecting the environment variable (does not work
  on Windows — the API asks the OS for the known folder and ignores it; check
  before assuming the mac differs); a test-only build (it would test the wrong
  binary); and refusing to run while the app is open (Russell's instruction on
  the day was the opposite — close his copy, say so, do not reopen it).

  **The mistake worth inheriting rather than repeating.** The first cut
  redirected only the settings file and the trail. An adversarial review found
  that the app consumes pending scheduled-deploy sentinels on launch AND on
  every activation, and that applying one writes publish state into the course
  folder the sentinel names — an absolute path to a REAL course. A test run
  could therefore have marked a teacher's section as published, with the line
  explaining it going to the redirected trail where nobody would look. The fix
  was one `AppDataRoot` that everything derives from, so the next thing
  somebody adds inherits the isolation instead of leaking. **If the mac builds
  this, redirect the whole Application Support folder from the start**, not
  the two files you first think of.

  **Reference:** `windows-app/Plantoir.UiTests/` (`DrivenApp.cs` is the
  harness, `SpecialFoldersHelpUiTests.cs` the six cases),
  `run-ui-tests.ps1`, `Plantoir.Core/Models/AppDataRoot.cs`,
  `Plantoir/App.xaml.cs` and `Program.cs` (the flag is read in BOTH — `Main`
  logs four times before the app class exists, so a redirect that waited would
  already have written to the teacher's own log).

  **Opt-in, and it must stay that way**: the project is in the solution so it
  always compiles, and every test carries an attribute that skips unless an
  environment variable is set. A bare `dotnet test` builds six and runs none.
  On the mac the equivalent is a separate UI-testing target, launch arguments
  for the flag, and something that keeps it out of the ordinary gate.

  **Nothing is proposed to the contract**: none of this is a sentence a
  teacher reads, so no mac suite should go red because of it.

- **Windows caught up to the mac's three deploy-after-preview console-race
  fixes** (Windows, 2026-08-23, `GUI-IMPROVEMENTS.md` row 381, closing
  `WINDOWS-HANDOFF.md` item 8; mac originals rows 317–318, 2026-08-22). No mac
  change — this is Windows implementing races the mac already fixed — but the
  investigation confirmed all three were genuinely present, one had a wider
  exposure window on Windows than on the mac, and the adversarial review that
  checked the fix found a trap worth watching for on this side too. **Race 317
  (stale-timestamp panel flash):** `SectionDetailView.RefreshChrome`'s
  `showDeploy` had the identical ordering bug `showsDeployProgress` did —
  fixed with `MultiDestinationDeployRunner.ClaimConsole()`, a direct mirror of
  `deployRunner.startedAt = Date()` in `deployAndWait()`. **Race 318a (blank
  console + Deploy re-entrancy):** present with a LARGER window than mac's
  ~0.5s — Windows' preview-stop sweep can run to ~20s, and nothing disabled
  Deploy for that whole span. Fixed with a view-local `_isPreparingDeploy`
  field (mirroring mac's `@State`, not a runner property) and a dedicated
  `TaskProgressView.ShowPreparing(title)` placeholder, matching the mac's
  choice of a real placeholder view (`preparingToDeployPlaceholder`) over any
  runner-state workaround — that was the one part of the mac's shape worth
  porting exactly rather than reinventing. **Race 318b (false "Done" flash):**
  present — `MultiDestinationDeployRunner.RunAsync` reuses one `ScriptRunner`
  for build-then-deploy and polls for completion (100ms on Windows vs mac's
  300ms), so the same-shape gap existed at a smaller scale. Fixed with
  `ScriptRunner.IsBetweenPhases`, a direct mirror of `isBetweenPhases`.
  **Worth a glance on this side:** the adversarial review caught an explicit
  `RefreshChrome()` call that had been sitting between clearing
  `_isPreparingDeploy` and `await RunAsync(...)` — harmless today only because
  everything up to `RunAsync`'s own `Notify` runs synchronously before any
  frame paints, but it re-derived the exact stale-`Legs` race the whole fix
  exists to close, one future `await` inserted in that gap away from becoming
  real. Removed on Windows; a quick read of `deployAndWait()` around the
  `isPreparingDeploy = false` / `await deployRunner.run(...)` boundary
  (`SectionDetailView.swift:780-793`) found no exact equivalent there, but the
  general shape — a fix that only works because of synchronous-batching
  timing is fragile even when it currently renders correctly — is worth
  keeping in mind if that span is ever touched again. Reference:
  `Plantoir.Core/Scripting/ScriptRunner.cs` (`IsBetweenPhases`),
  `Plantoir.Core/Scripting/MultiDestinationDeployRunner.cs`
  (`ClaimConsole()`), `Plantoir/Views/TaskProgressView.xaml.cs`
  (`ShowPreparing`), `Plantoir/Views/SectionDetailView.xaml.cs`
  (`_isPreparingDeploy`, `Deploy_Click`).

- **Measured: Edge does not need the `127.0.0.1` rewrite for a preview URL**
  (Windows, 2026-08-23, closing `WINDOWS-HANDOFF.md` item 5's first half, the
  Edge `127.0.0.1` question). The rewrite itself (`OutputParsers.cs`,
  `SectionDetailView.xaml.cs`) was applied earlier on the mac's "browsers try
  IPv6 first" rationale, without a Windows-side test to back it. Tested by
  hand against a real running preview (port 8081, confirmed via `netstat`):
  loading `http://localhost:8081` directly in Edge was indistinguishable from
  loading `http://127.0.0.1:8081` — both rendered immediately, no perceptible
  delay, repeated more than once. No IPv6-first stall observed. Conclusion:
  the rewrite is a harmless no-op on Windows as currently shipped, not a fix
  for an observed Edge problem — kept in place rather than removed, since it
  costs nothing and matches the mac's own defensive posture, but it should no
  longer be treated as an open question. No mac change; nothing to port.

- **Windows caught up to the mac's working-folder path bar gestures**
  (Windows, 2026-08-23, `GUI-IMPROVEMENTS.md` row 328, closing
  `WINDOWS-HANDOFF.md` item 6). No mac change — the mac's own path bar is
  unaffected — but two things are worth knowing. **First, a WinUI trap that
  cost real time and is worth watching for anywhere else in `windows-app/`:**
  `MainWindow.xaml`'s `BreadcrumbBar.ItemTemplate` had, since the crumb
  feature first shipped (commit 4282b839), wrapped its content in a second
  `BreadcrumbBarItem` — invalid, since `BreadcrumbBar` already generates its
  own container per item, the same relationship `ListViewItem` has to
  `ListView`. This built cleanly and passed the full test suite every time
  (a `DataTemplate`'s structure isn't something a unit test reaches), and
  only failed at RUNTIME — by silently falling back to the bound object's
  `ToString()` rather than throwing, so every crumb displayed the literal
  text "Plantoir.Views.PathBarCrumb" instead of a folder name. It shipped
  invisibly for over a week because nobody had actually run the real app
  against this code path before. Fixed by having the template supply only
  the container's CONTENT (a `StackPanel`) and never another
  `BreadcrumbBarItem`; `PathBarCrumb` also gained a defensive
  `ToString() => DisplayName` override as a second line of defence, since
  the overflow dropdown and narrator can fall back to it independently of
  the item template — mirroring why `FolderCrumb` already had one. **Second,
  the folder icon per crumb** — mac renders the real Finder icon; Windows'
  new `Plantoir.Views.FolderIcons` uses `StorageFolder.GetThumbnailAsync`
  (cached by path, `null` on any failure so the crumb falls back to
  name-only) rather than P/Invoking `SHGetFileInfo`, avoiding manual HICON
  lifetime management for a decoration the contract already says is
  optional. Reference: `Plantoir/MainWindow.xaml` (`BreadcrumbBar.ItemTemplate`),
  `Plantoir/Views/PathBarCrumb.cs`, `Plantoir/Views/FolderIcons.cs`.

- **Windows caught up to the mac's "assistant engine said" trail event**
  (Windows, 2026-08-23, `GUI-IMPROVEMENTS.md` row 327, closing
  `WINDOWS-HANDOFF.md` item 2). No mac change — this is Windows implementing
  a feature the mac already had, so nothing to port back — but worth knowing
  the two platforms differ in HOW the engine's output is captured, in case a
  future engine integration on either side needs the same lesson. The mac
  writes `llama-server`'s stdout/stderr to a FILE and samples its tail,
  because an unread `Pipe` fills up and blocks the engine mid-request — the
  bug that originally wedged the Windows server. Windows' `LocalModel`
  already avoided that same wedge a different way, by draining via
  `Process.OutputDataReceived`/`ErrorDataReceived` EVENTS (always read,
  never blocking) into an in-memory 60-line ring buffer, so no file-backed
  log was needed to port this feature — `LocalModel.LinesSinceLastLook`
  reads the ring buffer instead of a file offset. The filter and cap
  (`Plantoir.Core.Assist.AssistEngineLog`) are checked in
  `AssistEngineLogTests.cs` against the identical real llama.cpp (b10435)
  fixture lines the mac's `AssistEngineLogTests.swift` uses, so a change to
  what counts as "trouble" can be cross-checked against the same evidence on
  both platforms. One Windows-specific bug an adversarial review caught and
  fixed, not present on mac: mac's `recordWhatTheEngineSaid` always runs on
  one actor, so its non-atomic Swift properties need no lock; Windows
  deliberately runs its periodic watch on a background thread while
  `Shutdown()`'s own last look runs on the UI thread without waiting for an
  in-flight background iteration, which could race on the shared mark/count
  state — fixed with a lock (`AssistWindow._engineLogGate`).

- **Windows' progress-bar markers had drifted out of sync with its own
  launchers for four days, and nothing caught it** (Windows, 2026-08-23,
  `GUI-IMPROVEMENTS.md` row 353, closing `WINDOWS-HANDOFF.md` item 5's
  second half). No mac change needed — `TaskMilestones.swift` was never
  wrong, since it was written against `setup.sh`/`preview.sh`/`deploy.sh`,
  which still print the lines it watches for. But the WAY this broke is
  worth knowing, because it's a shape of bug that can recur on either side.
  `TaskMilestones.cs` used four markers copied verbatim from the mac's
  `.sh` scripts (`Setting up this PC`, `Building your website builder`,
  `Ensuring container is running`, `Starting container if needed`).
  `setup.ps1` gained a "Native toolchain (no container)" rewrite — no
  WSL2, no Docker, no one-time machine setup, no container start at all —
  the very next day (`b356a1f`, 2026-08-19), which silently stopped
  printing all four. Nobody updated the C# markers, and nothing failed:
  the existing `TaskMilestoneTests` only checked label WORDING (ellipsis
  suffix, no "Docker"/"script" text) against hand-typed synthetic
  transcripts, never against real captured launcher output. The visible
  cost: the first two-to-three stages of most progress bars (course
  creation, example course, preview, deploy) could never be reached by
  marker match, so the bar sat at 0% until a later, still-real marker (e.g.
  "Quartz v4") jumped it forward several steps at once — no crash, reads
  as a slow build. Found by re-investigating `WINDOWS-HANDOFF.md` item 5,
  confirmed against two real captured transcripts (`preview.ps1
  --build-only`, `deploy.ps1 --to-folder`) run on this machine, and
  confirmed twice more by independent adversarial review before and after
  the fix (the second pass caught a genuine miss: `MarketingShotCapturer.cs`'s
  mock transcripts, whose own doc comments claim to be coupled to
  `TaskMilestones` — "change one there and this stops advancing" — still
  carried the four dead strings and needed the same fix). **The lesson
  worth carrying to the mac side, in case `.sh` output is ever
  restructured similarly:** a progress-marker list is a claim about what a
  SPECIFIC script prints RIGHT NOW, and it rots silently the moment that
  script changes underneath it unless something actually reads the
  script's own text. Windows' fix — `TaskMilestoneLauncherMarkerTests`
  (`ParsingTests.cs`), which greps the real `.ps1` files for every
  launcher-origin marker rather than trusting a synthetic transcript — is
  the general pattern; `TaskMilestoneTests.swift` has no equivalent check
  against `.sh` today. Reference:
  `windows-app/Plantoir.Core/Scripting/TaskMilestones.cs`,
  `windows-app/Plantoir.Tests/ParsingTests.cs`.

- **A general WinUI `x:Bind` trap, found in the sidebar's scheduled-deploy
  badge but worth watching for anywhere a row object is reconciled rather
  than recreated** (Windows, 2026-08-23, `GUI-IMPROVEMENTS.md` row 326).
  Reported directly, right after row 325 shipped: no clock badge appeared
  after scheduling a deploy in an already-open window, and the right-click
  menu never offered Cancel/Change either. Two compounding bugs, not one.
  (1) `ReconcileSections` only read the current schedule into
  `SidebarRow.ScheduledDeploy` when CREATING a row — an existing row (the
  normal case, since the window was already open) kept whatever was true
  the moment it was first shown, forever. (2) Even fixed, the UI would not
  have shown it: `x:Bind` — unlike classic `Binding` — defaults to
  `Mode=OneTime`, evaluating once at container creation and never again.
  `SidebarRow` had no change notification and none of the affected
  bindings specified `Mode=OneWay`, so `Visibility`/`ContextFlyout` were
  frozen at whatever was true when the row's TreeView container was first
  built. **No equivalent trap on the mac** — SwiftUI's `@Observable`
  re-renders any view that reads a changed property, full stop, so there
  is no "silently stale until the container happens to be recreated"
  failure mode to reproduce there. Worth knowing as a general lesson for
  ANY future WinUI work here: a reconciled (not recreated) row/item object
  needs BOTH `Mode=OneWay` in the XAML on every binding whose value can
  change post-creation AND `INotifyPropertyChanged` raised for that exact
  property name — including for any DERIVED property XAML binds to
  directly (here, `ScheduledDeploy` changing had to also raise
  `BadgeVisibility` and `BadgeTooltip`, since `x:Bind` subscribes to the
  literal property path named in the binding, not to whatever the bound
  property is computed from). Also added, same pass: `MainWindow`'s
  `Activated` handler now calls `Sidebar.Refresh()`, so a deploy scheduled
  through the assistant or from a different window is picked up the next
  time this window comes to the front — the same "refresh on activation"
  shape the " — Edited" marker already uses. Reference:
  `windows-app/Plantoir/Views/SidebarPane.xaml.cs` (`SidebarRow`,
  `ReconcileSections`), `windows-app/Plantoir/Views/SidebarPane.xaml`
  (the three `Mode=OneWay` bindings), `windows-app/Plantoir/MainWindow.xaml.cs`.

- **Scheduled deploys never actually fired on Windows, ever — a doubled
  backslash in a shell-quoted string** (Windows, 2026-08-23,
  `GUI-IMPROVEMENTS.md` row 325). Reported directly, after a real overnight
  scheduled deploy for ICD2O never went out. `TaskScheduling`'s stored `/TR`
  command built the PowerShell `-File` argument with `\\\"` in C#
  source — a literal backslash followed by a quote, TWO characters — where
  it needed a real embedded quote character (`\"` in C# source, which the
  compiler turns into one `"` character). `schtasks /Query ... /XML` showed
  the stored `<Arguments>` holding `\"C:\...\script.ps1\"` verbatim, both
  characters literal, so PowerShell's `-File` was handed a path it could
  never resolve. **This predates row 323's fingerprinting work entirely** —
  it would have broken every scheduled deploy on Windows since the feature
  first shipped, for any course, silently, because Task Scheduler still
  records a "Last Run Time" for a task that ran and immediately failed to
  parse its own argument, so nothing about SCHEDULING ever looked broken.
  Confirmed live: the real failing task's Last Result was `0xFFFD0000`.
  **Nothing for the mac to do or check** — `launchd`'s command is an
  ARGUMENTS ARRAY in a plist, never a shell command string assembled with
  manual quote-escaping, so this exact bug class (two escaping passes
  compounding instead of cancelling — `ProcessStartInfo.ArgumentList`
  already quotes a value containing spaces once, so hand-escaping quotes
  INSIDE that value doubles up) has no equivalent surface there. Worth
  knowing as a general lesson if the mac ever DOES build a shell command
  string by hand somewhere (rather than an arguments array): don't
  hand-escape a quote that a launching API is about to quote again on your
  behalf — verify by reading back what actually got stored/registered, the
  way `schtasks /Query ... /XML` made this one obvious in about thirty
  seconds once looked at directly, rather than trusting that a plausible-
  looking C# string literal did what it appeared to say. Also fixed on the
  same pass: right-click on a section with a deploy already scheduled now
  offers "Change Deploy Time…" alongside Cancel, reusing the existing
  schedule dialog pre-filled with the current time rather than requiring a
  cancel-then-reschedule round trip — no backend change needed, since
  `TaskScheduling.Schedule` already replaces by task name. Reference:
  `windows-app/Plantoir.Core/Assist/TaskScheduling.cs`
  (`TaskRunCommand`), `windows-app/Plantoir.Tests/TaskSchedulingTests.cs`
  (new), `windows-app/Plantoir/Views/SidebarPane.xaml.cs`
  (`AskWhenToDeploy`'s new `existing` parameter).

- **A shared `scripts/deploy.py` bug, found on Windows but fixed in the file
  the mac runs too** (Windows + shared, 2026-08-23, `GUI-IMPROVEMENTS.md`
  row 324). Reported directly, with a screenshot: a teacher deployed a
  section for the first time (Netlify, succeeded, live URL shown), then
  tried Schedule a deploy and was refused with "has never been deployed" —
  about a section that plainly just had been. `main()`'s `course_dir =
  section_dir.parent.parent`, used to read and write the Netlify/Cloudflare
  site marker (`.netlify_sites/`/`.cloudflare_sites/`), assumed the shape
  `.../<COURSE>/.merged_output/section#` — true on the mac and in the old
  container, but Windows' native `PLANTOIR_BUILD_ROOT` (row 290) makes
  `toolchain_paths.merged_output_root()` skip the `.merged_output` nesting
  entirely, so climbing two levels overshot onto the build root's own
  parent instead of the course. **This was not a cosmetic bug**: the marker
  was never found at READ time either, so every deploy — not just the
  first — silently created a brand-new Netlify site instead of reusing the
  one from last time, confirmed live on Russell's own machine (a real site
  marker sitting under `%LOCALAPPDATA%\Plantoir\builds\<id>\` instead of
  under `courses\ICD2O\`). **The mac itself was never affected** —
  `PLANTOIR_BUILD_ROOT` is a Windows-only environment variable, so
  `merged_output_root()` has always kept the `.merged_output` nesting there
  and `section_dir.parent.parent` has always landed correctly — but the fix
  (`course_dir = COURSES_ROOT / args.course`, unambiguous regardless of
  where the build output lives) is in the ONE shared `deploy.py` both
  platforms run, so **the mac's copy carries the identical change with
  nothing further to do.**

  **Addendum, 2026-09-05 — your fix is now load-bearing on the mac too, and
  this entry's "the mac itself was never affected" is true of the day it was
  written and no longer of today.** The mac has moved its build output out of
  the working folder as well (`GUI-IMPROVEMENTS.md` rows 402–406). It does it
  differently — `courses/<CODE>/.merged_output` is a SYMLINK, not an
  environment variable — but `deploy.py` calls `.resolve()` on the built
  section's path, so on the mac `section_dir.parent.parent` now climbs to the
  BUILDS folder's parent, exactly as it did on yours. Had `course_dir` still
  been derived from that ancestry, the mac would have started writing its
  Netlify and Cloudflare markers into Application Support and creating a
  brand-new site on every publish — your bug, on our machine, a fortnight
  later. It did not, because you had already fixed it and pinned it with
  `scripts/test_deploy_course_dir_resolution.py`, which is now doing the job
  on both platforms. **Nothing is owed here; this is the answer-back.** The
  one thing worth knowing is that the test's docstring, which says the two
  paths differ "under Windows' native PLANTOIR_BUILD_ROOT", is now true of the
  mac's symlink as well — it still passes and still guards the right thing. Two new pure-stdlib tests,
  `scripts/test_deploy_course_dir_resolution.py`, wired into `verify.sh` —
  worth running there once, since they exercise `merged_output_root()`
  directly and `verify.sh` is the gate that would have caught this had it
  existed sooner. Reference: `scripts/deploy.py` (`main()`'s `course_dir`
  line), `scripts/toolchain_paths.py` (`merged_output_root`).

- **Windows closed its own version of the launchd scheduled-deploy bug row
  314 already fixed on the mac** (Windows + shared, 2026-08-22,
  `GUI-IMPROVEMENTS.md` row 323). `WINDOWS-HANDOFF.md`'s "What is still
  genuinely outstanding" list had item 2's carve-out: a scheduled ("publish
  tomorrow's class overnight") deploy on Windows succeeded perfectly but
  left the title bar saying "— Edited" forever, because Task Scheduler runs
  `powershell.exe` directly — no app process is alive at the moment the
  deploy actually happens, so nothing could fingerprint the section or
  write `.publish_state`. **The mac needs to change nothing** — its own
  launchd agent launches the app binary, so it always could fingerprint
  in-process, and this row is purely Windows catching up to what row 314
  already described as the mac's fix for the identical bug. Recording here
  for two reasons worth knowing about:
  - **A third, Python copy of the fingerprint algorithm now exists**, in
    the SHARED `scripts/` folder: `scripts/section_fingerprint.py`. Nothing
    on the mac calls it — only Windows' scheduled-deploy wrapper script
    does, since it needs to fingerprint from inside a plain PowerShell
    process with no C# or Swift available. If the fingerprint algorithm's
    rules ever change on the mac (which files count, the symlink one-hop
    resolution, the sort order, the hash), **this Python file needs the
    identical edit or a Windows scheduled deploy will silently disagree
    with the mac about whether a section has unpublished edits.** Proven to
    currently match, byte for byte, by
    `windows-app/Plantoir.Tests/SectionFingerprintPythonParityTests.cs`,
    which runs both the C# and the Python implementations against the same
    temp course tree and asserts equal output — there is no equivalent
    check on the mac side, since the mac never runs this file.
  - **Rejected: fingerprinting at schedule time instead of run time** —
    would have been cheap (no Python needed, just C# at the moment the
    teacher clicks Schedule), but wrong in the direction that lies to the
    teacher: an edit made between scheduling and the overnight run still
    goes out correctly, but a schedule-time fingerprint would stamp the
    STALE pre-edit fingerprint, so the marker would say "— Edited" about
    content that had, in fact, just published. Fingerprinting at RUN time,
    right before the deploy — the wrapper script's own Python call, timed
    to match the mac's in-process fingerprint-before-running-the-script
    order — is the only version that is correct either way. Worth knowing
    if a similar "the app isn't alive at the moment this needs to happen"
    problem comes up on the mac side (a future launchd variant, say): the
    fix that is cheap and the fix that is correct were not the same fix
    here, and the difference only shows up in a case (edit-after-schedule)
    that is easy to not think to test.
  - Reference: `windows-app/Plantoir.Core/Assist/TaskScheduling.cs`
    (`WriteWrapperScript`), `windows-app/Plantoir.Core/Assist/ScheduledDeployCompletion.cs`
    (new), `scripts/section_fingerprint.py` (new),
    `windows-app/Plantoir.Tests/SectionFingerprintPythonParityTests.cs`
    (new), `windows-app/Plantoir.Tests/ScheduledDeployCompletionTests.cs`
    (new). Full write-up, including what the wrapper script's generated
    PowerShell actually looks like, in `WINDOWS-HANDOFF.md`, "A scheduled
    deploy needs its own path to the same record".

- **The Windows hero pair had three separate bugs, found by actually looking
  at it next to the mac's** (Windows, 2026-08-21, commit "Fix Windows hero
  image: stray border pixels, tiny windows, and an empty Obsidian sidebar").
  Russell asked directly: "compare the macOS hero image to the Windows hero
  image captures and you will see what I mean" — and looking, rather than
  reasoning about the code, is how all three were actually found and fixed.
  - **A hairline of the window's own border was baked into every card.**
    `DWMWA_EXTENDED_FRAME_BOUNDS` (used because `GetWindowRect` includes an
    invisible resize border — already known, see the entry below) excludes
    that invisible border but NOT the thin accent border Windows 11 draws
    directly on the window, so the raw grab kept 1 DIP of that border colour
    on all four edges. It reads as near-black (52-54, 52-54, 52-54) in BOTH
    appearances, since it is the system border colour, not the app's — so it
    shows as stray dark pixels once composited onto the page's own
    background, worst on the light cards. Measured identically on all three
    window kinds (Obsidian, Plantoir, Edge) in both themes: exactly 2 real
    pixels at this machine's 2x scale, i.e. 1 DIP. Fixed by cropping that
    border off before masking the corners, and shrinking the corner-radius
    mask to match (`BORDER_DIPS`, `photograph()` in `hero_windows.py`). If
    the mac's own captures ever show a comparable hairline, this is the shape
    of bug to look for — but `screencapture -l` returning a window with its
    corners already transparent (rule 1 in the marketing-screenshots skill)
    means the mac has never had a border baked into the bitmap to begin with.
  - **The card size was a REAL-PIXEL cap, so it didn't scale with the
    display.** `card_geometry()`'s 1680x960 cap was tuned on a
    1920x1080-at-150% machine, where it read as "almost the whole screen"
    (1120x672 DIPs out of a 1280x672 DIP work area). The same 1680x960 REAL
    pixels on a 200%-scaled screen is only 840x480 DIPs — a physically small
    window whose UI barely shows anything, which is exactly what "you can
    barely see anything in each window" was describing. Re-expressed the cap
    in DIPs (`CARD_WIDTH_DIP = 1120`, `CARD_HEIGHT_DIP = 640` — the size the
    old cap actually was, in points, on the machine it was tuned on) and
    multiplied by `scale_factor()` at capture time, so a card occupies the
    same fraction of the desktop on any display. Cards went from 1680x960 to
    2240x1280 real pixels on this (200%-scaled) machine; nothing changes on a
    100%-scaled one.
  - **Obsidian's sidebar was three collapsed folder names, because nothing
    ever told it to be anything else.** The mac's rich sidebar (several
    folders open, real class notes visible) turned out to depend on nothing
    reproducible — no fold state is stored anywhere in a vault's
    `.obsidian/` (checked `workspace.json` by hand; there is no
    `expandedFolders` key or equivalent), so it can only be Electron's own
    per-machine local storage remembering what Russell has manually browsed
    on that Mac over time. That is not something a fresh Windows vault has
    ever had a reason to accumulate, and setting the file-explorer leaf's
    `autoReveal: true` in `workspace.json` before launch was NOT sufficient
    on its own — it visibly expanded the active note's ancestors but settled
    mid-scroll, short of the note itself, and repeated waits up to 6s did not
    change where it stopped. What worked, tested with `autoReveal` explicitly
    OFF to confirm it does not depend on that setting at all: Obsidian's own
    **"Reveal current file in navigation" command**, fired through the
    command palette (`Ctrl+P`, type the name, Enter) once the window is
    placed at its final size. It deterministically expands every ancestor
    folder AND scrolls to the note, highlighted, regardless of any persisted
    per-vault state — which is also why it is the right fix rather than the
    `autoReveal` setting: it does not depend on Electron local storage that a
    fresh machine will never have. New helper `reveal_active_file()` in
    `hero_windows.py`, called from `capture_obsidian()`. **Worth knowing if
    the mac's demo vault is ever reprovisioned from scratch** (a new machine,
    or `~/Desktop/Teaching` deleted and rebuilt): the mac's own rich sidebar
    would come back collapsed too, for the identical reason, and the same
    command would be the fix there — nothing about it is Windows-specific,
    it just happened to be found here because Windows had no accumulated
    local-storage state to be masking the bug.
  - **A pre-existing risk, found while testing this and fixed alongside it**:
    `capture_edge()`'s `stop("msedge.exe")` (`taskkill /F /IM msedge.exe`)
    kills every Edge process on the machine, scratch profile or not. On a
    machine where Edge is also someone's real browser — which it was, on
    this one, mid-session — that silently closes whatever they had open.
    New `stop_matching(process_name, command_line_contains)` uses
    `Get-CimInstance Win32_Process` to filter by command line before
    killing, so only the process launched against our own
    `--user-data-dir=EDGE_PROFILE` is touched; verified live with a
    non-matching filter first (confirmed zero processes selected) before
    trusting it against the real one. **Not extended to `Obsidian.exe` or
    `Plantoir.exe`** in this pass — Plantoir is explicitly pre-authorised to
    be force-closed on Windows regardless (`CLAUDE.md`, "An agent working on
    Windows may close a running Plantoir without asking"), and no real
    Obsidian was running to be at risk here. If the mac's own Safari capture
    ever needs an equivalent, it already has one structurally: the `⎚`
    profile keeps scratch state separate from Russell's own Safari, so a
    `killall Safari` (if it has one) is not the same class of risk to begin
    with.
  - **Left unresolved, and NOT chased further**: the Plantoir card's native
    title bar came back light in a dark-appearance capture, 4 runs out of 4
    in this session, including with an extra 3s settle after `write_theme()`
    before launch (ruling out a simple registry-propagation race).
    `ShowHeroWindowAsync` (`MarketingShotCapturer.cs`) sets `RequestedTheme`
    on the content root and the progress view, which is why the MENU BAR and
    everything below it renders correctly dark — but nothing there touches
    the native caption's dark-mode attribute, which is presumably meant to
    follow the OS registry `write_theme()` already sets before launch. Why
    that isn't landing is unknown: possibly a genuine gap (no explicit
    `DwmSetWindowAttribute(..., DWMWA_USE_IMMERSIVE_DARK_MODE, ...)` call
    anywhere in this codepath), possibly specific to capturing over RDP,
    where this session ran. `site/img/hero-windows-dark.png` ships with this
    flaw rather than being blocked on it — the three bugs above are the ones
    Russell asked about and are confirmed fixed; the title bar is a smaller,
    separate defect for a future session to chase, on a physical console
    rather than RDP if possible, to rule that variable out first.
  - Reference: `website/shots/hero_windows.py` (`photograph`, `card_geometry`,
    `reveal_active_file`, `stop_matching`).

- **Windows marketing shots re-taken, a Windows hero pair added, and an
  already-known theming bug re-fixed the right way** (Windows, 2026-08-20).
  - **What changed**: Russell redeployed the demo sites and initially asked
    for ENG2D's screenshot source to move to `eng2d-s2-2026-gordon` — that
    turned out to be a mistake caught minutes later ("the eng2d website
    should be s1 like the other courses"), so `website/shots/capture_windows.py`'s
    `DEMO_COURSES` table stayed as it already was: `eng2d-s1-2026-gordon`,
    matching MCV4U and SCH3U on section 1, and matching the identical table
    in `capture.py`. The images were still re-shot (a fresh Netlify deploy
    can change page content even with the URL unchanged), so this is not a
    no-op even though the table's end value is the same as before. **No mac
    action needed** — nothing here changes what `capture.py`'s own table
    should point at.
  - **A dialog theming bug surfaced during the re-shoot, and turned out to
    already be found and fixed — on a branch that was never merged.**
    `NewCourseDialog`'s "New to this?" card (and the harness's own synthetic
    dialog card around it) read `Application.Current.Resources["key"]`
    directly in code, which resolves against the theme the app LAUNCHED in,
    not a window's local `RequestedTheme` override. `dev`'s capture harness
    runs both appearances from one launched-light process, so the Dark
    capture rendered a still-light card with barely-legible text. Confirmed
    capture-harness-only: nothing in the live app sets `RequestedTheme`
    anywhere, so a teacher never sees this. Two live fixes were tried here
    first and rejected — `Application.Current.RequestedTheme = theme` after
    launch throws `COMException 0x80131515` (WinUI does not support changing
    the app-wide theme at runtime), and indexing
    `Resources.ThemeDictionaries` (directly, then recursively through
    `MergedDictionaries`) resolves only whichever theme the app is ambiently
    in — then hardcoding approximate Fluent 2 literals as a third attempt,
    which worked but was never committed. **All three were abandoned** on
    finding `ac96888c` ("Photograph each appearance from its own process, so
    the dark shots are dark") on the unmerged `new-screenshots` branch (5
    commits, Russell, 2026-08-19, 48 behind `dev` at the time) — the actual
    fix, already reasoned through: launch `Plantoir.exe --capture-marketing-shots
    --theme <light|dark>` as a SEPARATE process per appearance, with Windows'
    own colour mode switched first (`capture_windows.py` now imports
    `read_theme`/`write_theme` from `hero_windows.py`, which already had
    them). Every themed resource then resolves the way a teacher's copy
    resolves it, because the situation genuinely is a teacher's copy in that
    appearance — no brush-by-brush chasing, and no approximation. **Ported
    forward instead of merging the branch**: the branch was 48 commits stale
    (predates the v1.1.0 release and the mac's own screenshot re-shoot), so
    its 26-image commit was left behind and only the code changes were
    carried over by hand.
  - **A second commit on that branch was also worth carrying forward**:
    `dd6f3fe9` fixed the SAME class of bug in `hero_windows.py` — the
    Obsidian card was hardcoded to `section2/.../Unit 4, Day 23`, which held
    only until the next redeploy moved the site to Day 22 and nothing
    noticed. `hero_windows.py` now has `most_recent_class()`, which reads the
    live site's front page at capture time and falls back to a named
    constant only if the site is unreachable. Also picked up: `SECTION = 1`
    (was hardcoded to section 2, while Plantoir and Edge were both showing
    section 1 — a second three-cards-disagree bug, independent of the class
    number one), and a fresh Edge scratch profile per launch (a reused
    profile let Edge restore the previous pass's tab after being
    force-killed, so the dark hero card came back showing the same page
    twice).
  - **The hero pair itself was also just plain missing from `dev`** —
    `website/shots/hero_windows.py` existed (added by `99c7bb36`, the commit
    that also gave plantoir.app its platform-conditional hero serving), but
    `site/img/hero-windows-light.png` / `-dark.png` did not, because the run
    that produced them was ONLY on `new-screenshots`. Regenerated fresh here
    rather than pulled from that branch, so they reflect today's redeploy and
    the section/class fixes above. Windows visitors were seeing the mac's
    hero image (`build.py`'s platform fallback) until this landed.
  - **A related bug, worth knowing regardless of the theming question and
    not on the old branch at all**: `MarketingShotCapturer.RunAsync` caught
    its own exceptions, logged them, and still called `Environment.Exit(0)`
    either way — so a mid-capture crash was invisible to
    `capture_windows.py`'s `subprocess.run(..., check=True)`, which reported
    success with whatever images happened to exist, stale ones included.
    This hid two of the three rejected theming fixes above from the exit
    code entirely; both were only visible in `%TEMP%\marketing_capture.log`.
    Now exits 1 on failure. **A second, independent instance of the same
    swallow was in `capture_windows.py` itself**: `Start-Process -Wait` does
    not forward the child's exit code to `powershell.exe`'s own, so even
    with the C# fix a crash still would not have surfaced — fixed with
    `-PassThru; exit $p.ExitCode`. Worth a glance on the mac only if
    `capture.py` has an analogous "subprocess exit code stands in for a
    success check" assumption anywhere; nothing here suggests it does.
  - **`new-screenshots` (local and `origin/new-screenshots`) is now safe to
    delete** — its useful commits are carried forward as described above,
    and its one 26-image commit is superseded by today's re-shoot. Left in
    place rather than deleted here, since it is Russell's own branch.
  - Reference: `windows-app/Plantoir/Services/MarketingShotCapturer.cs`
    (`RunAsync`, `CaptureNewCourseWindow`), `windows-app/Plantoir/App.xaml.cs`
    (the `--theme` argument), `website/shots/capture_windows.py`
    (`DEMO_COURSES`, `capture_app_windows`), `website/shots/hero_windows.py`
    (`most_recent_class`, `SECTION`, `capture_edge`).

- **plantoir.app now has a Windows hero composite, and `deploy_site_name`
  turned out not to be a key** (Windows, 2026-08-19, commit "Give the Windows
  marketing shots a hero composite, and fix three fixtures").
  - **What changed**: the hero image existed only for the mac, so
    `build.py`'s platform swap served Windows visitors a picture of a Mac.
    `website/shots/hero_windows.py` now produces `hero-windows-light.png` and
    `hero-windows-dark.png` from Obsidian, Plantoir mid-deploy and Edge on
    the published site, through the same `composite.diagonal_hero()` the mac
    uses. Nothing on the mac side changes: `build.py` picks the twin up by
    file name the moment it exists.
  - **The one mechanism worth knowing**, because it is where the two
    platforms genuinely differ: the mac's `screencapture -l <window id>`
    returns a single window with its rounded corners already transparent.
    Windows has no equivalent, so every card is a REGION of the screen —
    the window is placed, raised, and the rectangle `DwmGetWindowAttribute`
    reports as `DWMWA_EXTENDED_FRAME_BOUNDS` is grabbed, then the corners are
    masked. `GetWindowRect` is the wrong rectangle: it includes an invisible
    resize border. **Rejected**: `PrintWindow`, which can capture a window
    bigger than the screen and would have avoided the sizing constraint
    below, but returns black for WinUI 3 surfaces.
  - **Consequence the mac does not have**: the cards are limited by the real
    desktop. This machine is 1920×1080 at 150%, so a work area of 1920×1008
    caps them at 1680×960 real pixels — a wider aspect than the mac's
    1280×800 cards. The finished figures still land at the shared
    `FIGURE_WIDTH` of 1700, so the column edges line up down the page.
  - **A `--hero-window <theme>` mode was added to `Plantoir.exe`** for the
    middle card. **Rejected**: reusing the `RenderTargetBitmap` the other
    Windows shots use — it renders the visual tree, which has no title bar,
    so Plantoir would have been the one card in the cascade with no window
    chrome beside Obsidian's and Edge's.
  - **The `deploy_site_name` question is answered**, and the answer is not
    the one `WINDOWS-HANDOFF.md` anticipated. That file asked this side to
    decide what the capturer's fixtures should write now the demo sites are
    named per section (`<code>-s<n>-2026-gordon`), since the new scheme names
    a SECTION while the key sits in course-level config. The key was never
    real: it appears in no launcher, in no contract —
    `contracts/file-formats.json` lists what `course_config.json` carries and
    it is not there — and nowhere else in either app. **Renaming it would
    have looked like settling the question while changing nothing.** The
    fixtures now write `.netlify_sites/section<n>.json`, the per-section
    marker a real deploy leaves and the one `build_site.py`'s
    `resolve_section_domain` and `deploy.py`'s `load_netlify_marker` actually
    read. Worth a glance on the mac only to confirm nothing there writes the
    invented key either.
  - **A second invented key was found beside it**: the same fixtures wrote
    `section_count`, which nothing reads, so every demo course came up with
    ONE section while the mac's showed two. It is `num_sections` /
    `section_numbers`. Reference:
    `windows-app/Plantoir/Services/MarketingShotCapturer.cs`.
  - **Nothing for the mac to match.** Both harnesses photograph their own
    platform; this is a note so the next mac session is not surprised to find
    a `hero-windows-*` pair in `site/img/`.

- **Deploys ask for the teacher's surname only when NAMING a new site, never
  on a repeat deploy** (Shared Python, 2026-08-19).
  - **What was fixed**: `deploy.py` called `get_or_prompt_teacher_last_name()`
    unconditionally at the top of every deploy. On a machine with no saved
    surname that stopped EVERY deploy for input — including deploys to a
    section whose site already existed and needed no name at all. In the GUI
    the question surfaces as a dialog, but a missed or cancelled dialog read
    as "deploys are broken", and in any non-interactive context the answer
    was silently None anyway. Seen live during Russell's presentation prep:
    a fresh workspace's first app deploy stalled at the surname question and
    never reached site creation.
  - **The fix**: the surname is LOADED silently at the top
    (`load_teacher_last_name()`), and `get_or_prompt_teacher_last_name()`
    runs only at the two places a NEW name is being chosen — the Netlify
    `not site_marker` branch and the Cloudflare no-marker branch. A repeat
    deploy therefore asks nothing anywhere: GUI, MCP, scheduled, or shell.
    Verified live on Windows: repeat deploy with no saved surname and no
    profile.json completed with zero prompts and wrote no profile.
  - **Rejected**: keeping the eager prompt and teaching every caller to
    pre-seed profile.json (fixes one machine at a time — the failure just
    met is exactly that patch not scaling); prompting but defaulting after a
    timeout (a deploy that behaves differently depending on how fast you
    answer is worse than one that never asks).
  - **Mac impact**: shared `deploy.py` — rebuild the mac app so its bundled
    toolchain carries it. The mac's own GUI has the same exposure (its
    launcher runs on a pseudo-terminal, so the eager prompt fired there
    too).

- **Two corrections to the release-packaging sync, made while integrating it
  on Windows** (Windows, 2026-08-19, follows `6326c8c9`/`1117e47c`).
  - **`windows-app/publish.ps1` could not START on Windows.** The new
    installer block used the null-conditional operator (`?.`), which Windows
    PowerShell 5.1 — the interpreter the script's own header prescribes via
    `powershell -File` — cannot parse: the whole file failed with
    "Unexpected token '?.Source'" before running a line. Verified with the
    5.1 parser before and after; now rewritten as a plain `if`. When writing
    PowerShell from the mac, treat 5.1 as the floor: no `?.`, `??`, ternary,
    or pipeline-chain `&&`/`||`.
  - **The Métis skeleton rename would not have survived regeneration.**
    `support/skeletons/` is generated (`generate_skeletons.py`), and
    `1117e47c` renamed a generated file by hand — the next
    `generate_skeletons.py` run would have resurrected the accented filename
    and dropped the alias, silently. The rule now lives in the generator
    (`write()` folds combining marks out of filenames and inserts the
    accented alias after the title) and in `lint_skeletons.py` (title may
    differ from filename only by combining marks, and only with the alias
    kept). Regeneration verified byte-identical to the committed tree.
    Rejected: leaving the hand-edit in place (a generated tree that differs
    from its generator is a time bomb) and ASCII-folding en dashes / ² too
    (single code points do not decompose in a DMG; seven such names ship in
    example_content today and are fine).

- **Netlify uploads now retry on 429 with backoff, at 5 workers not 10**
  (Shared Python, 2026-08-19, follows `e0136437`).
  - **What was fixed**: the parallel-upload optimization (`e0136437`, 10-worker
    `ThreadPoolExecutor`) broke EVERY deploy large enough to matter: Netlify
    rate-limits the per-file upload endpoint, and one 429 aborted the whole
    deploy. Measured live on Windows (WSL2 Docker, home broadband): a fresh
    318-file ICS3U deploy died on the first 429 — reproducibly — where the old
    serial loop had always stayed under the limit. So "optimized" deploys
    failed 100% of the time on any new site; that is why deploys "stopped
    working" the same evening the optimization landed.
  - **The fix** (`scripts/deploy.py` → `_upload_required_files`): each file
    upload retries up to 6 times on 429/500/502/503/504 and on socket
    timeouts, with exponential backoff (1 s doubling, capped 30 s), honouring
    a `Retry-After` header when Netlify sends one; workers reduced 10 → 5.
    A non-retryable API error still fails the deploy immediately.
  - **Rejected**: reverting to serial (throws away a real win once retries
    exist); keeping 10 workers with retries (converges, but spends its time
    backing off — 5 stays mostly under the limit); a global rate limiter
    shared across threads (more machinery than the endpoint's behaviour
    justifies — per-file backoff empties the herd quickly enough).
  - **Mac impact**: `deploy.py` is shared, so the mac had the same broken
    window between `e0136437` and this fix. Nothing to port — but the mac app
    must be REBUILT so its bundled toolchain carries the fix, or every
    working folder it refreshes keeps deploying with the 10-worker version.

- **`Get-ToolchainHash` in the `.ps1` launchers now anchors to the launcher's
  own folder** (Windows launchers only, 2026-08-19). `.sh` launchers are
  unaffected — bash `cd` moves the real process CWD.
  - **What was fixed**: the PowerShell hash function resolved its relative
    context (`./.toolchain`) with .NET path APIs, which use
    `Environment.CurrentDirectory` — and `Set-Location` does NOT update that.
    A launcher invoked from a process whose CWD held a *different* stale
    `.toolchain` (seen live: a terminal session sitting in the repository,
    which had an Aug-11 mirror at its root) hashed the stale folder, matched
    an Aug-11 image tag, and silently ran week-old scripts while `docker
    build`'s context — resolved from the PowerShell location — pointed at the
    fresh folder. Image tag and image contents could disagree.
  - **The fix**: `$fullContext` is now built from `(Get-Location).ProviderPath`
    (the launchers `Set-Location` to their own folder at startup), in
    `deploy.ps1`, `preview.ps1`, and `setup.ps1` alike.
  - **Mac relevance**: know that a Windows image tag from before this fix may
    not describe its contents; if a Windows machine misbehaves after sync,
    recreating the container clears it.

- **Production rebuilds in `deploy.py` delegate to `build_site.py --build-only`**
  (Shared Python, 2026-08-18).
  - **What was fixed**: After Quartz build staging moved to container-internal ext4 storage (`/tmp/quartz-builds/<COURSE>/section<N>`), `deploy.py` failed when rebuilding for production (when detecting preview live-reload scripts in `index.html` or updating `baseUrl` for live site domains). It was calling `npx quartz build` directly in `cwd=section_dir` (`/teaching/courses/<COURSE>/.merged_output/section<N>`), which in the dual workspace architecture contains only `public/` and `course_config.json` rather than the full Quartz scaffold. If `/tmp/quartz-builds` was clean (e.g. freshly created container, or deploy without preview in the same session), `deploy.py` crashed immediately with `Production rebuild failed`.
  - **The fix**: `deploy.py`'s `rebuild_for_production` and `ensure_base_url_and_rebuild` now delegate production rebuilds directly to `build_site.py --course <COURSE> --section <N> --build-only`, which ensures the internal workspace is staged, applies all patches and domain markers, generates the production build without the live-reload websocket, and syncs `public/` cleanly via `_sync_public_to_host`.

- **Whole Unit Publish / Unpublish and MCP Tool Parameter Binding on Windows**
  (Windows, 2026-08-18). Awareness only; Windows now matches macOS behavior for whole unit operations.
  - **What was fixed**:
    1. Prompt shelf and card commands for "Unpublish Unit 4" generated tool calls missing `includeLinked`, causing ModelContextProtocol.NET binding errors on tools with non-optional parameters. Added default values (`includeLinked = false`, `progress = null!`, `cancellation = default`) across MCP tool declarations in `PlantoirTools.cs` and populated defaults in `AssistCardCommand.cs`.
    2. Implemented `PublishPlan.UnitNamed` and `AssistWorkspace.PlanWholeUnit` / `ApplyWholeUnit` matching `AssistToolRunner.swift:598-790`. Whole units step through class pages in order (Day N down to 1 for unpublishing, Day 1 up to N for publishing), batch all file edits into a single undo entry, and trigger a single preview rebuild.
  - **Testing**: Added whole unit unit tests in `ToolAnswerTests.cs` covering plan description, whole unit unpublish, whole unit publish, and whole unit single-step undo. All 522 tests pass.

- **Assist Plan Formatting & Graph Sweep Parity Completed on Windows**
  (Windows, 2026-08-18). Awareness only; Windows was brought into 100% byte-for-byte
  parity with macOS for all assist tool plans and suggestions (`PublishPlan`, `ReDatePlan`,
  `CurriculumMentionsPlan`).
  - **What changed**: Windows was outputting technical mechanical descriptions (file paths,
    frontmatter keys `publishForSection1: false → true`, `(2027-01-15, publish: true → false)`,
    arrows `→`, fake index embed diffs, and Netlify deploy boilerplate). Rewrote `PublishPlan.cs`,
    `ReDatePlan.cs`, and `AssistWorkspace.cs` unpublish sweep algorithm to match
    `AssistPublishPlan.swift` and `SectionReDatePlanner.swift` exactly.
  - **Graph Unpublish Sweep**: Implemented reason-to-keep link traversal (`“Tech Headlines” stays visible, because “Unit 1, Day 15” still links to it.`),
    landing page preservation, Key Links protection, curriculum page preservation, and transitive link following for publishing.
  - **Testing**: Added `AssistPlanParityTests.cs` explicitly validating the ICD2O Section 1 unpublish
    case and plan structures. All 518 unit tests in `Plantoir.Tests` pass.

- **Two `check_section` defects, one teacher report — and the second is the
  one that generalises** (Windows, 2026-08-18, `windows-sync`). Awareness

  only; the mac is right on both counts already.

  Asked what students would see, Windows answered "83 visible pages are linked
  from nowhere" and listed the course's own lessons. **(a)** Class pages were
  counted as orphans. The mac excludes them — `AssistSectionPage.isClassPage`
  — and its comment records hitting exactly this on an 86-period credit that
  reported 84. Windows now excludes them by the course's own
  `per_section_folders` rather than by the mac's "parent folder name contains
  'class'" heuristic; if the mac ever wants the stricter rule, the config is
  the better source. Note the two questions that must NOT be merged: the
  contract's `followingLinks.neverTakenDownByFollowingLinks` is about what
  unpublishing may sweep, and a class page IS swept.

  **(b)** is the one worth knowing over here, because it is a whole CLASS of
  bug this side cannot have. The preview state was read from `PreviewLeases`,
  an in-memory static belonging to the app — but `check_section` runs inside
  `plantoir-mcp`, a different process, where that list is permanently empty.
  So "Nothing is being previewed at the moment" was said every single time,
  whatever was on screen; the trail shows the teacher pressing Preview 32
  seconds before asking. On the mac the assistant and the preview are the same
  process and `sectionWindow(...)?.previewState()` is a method call, so the
  question never arises.

  **The shape of it: an in-memory static read from the wrong process does not
  fail, it answers "nothing".** That is indistinguishable from a true answer,
  which is why it survived. `WorkLease` — the on-disk, format-first registry —
  was already written for precisely this and was simply not being read. If the
  mac ever splits its MCP server out of the app bundle, every `PreviewLeases`
  and `CourseActivity` read becomes this bug at once.

  Two limits, stated because they are real: the leases are per-COURSE rather
  than per-section, so previewing Section 2 while asking about Section 1
  reports the wrong thing; and the build lease is released the moment the
  server answers, which is what makes "building" and "showing" two states
  rather than one.

- **The confirmation setting on Windows was wired to nothing for weeks**
  (Windows, 2026-08-18, `windows-sync`). Awareness only — the mac has had
  this since plan mode shipped — but worth recording because of HOW it went
  unnoticed. `AssistAgent.ConfirmationMode` was set from
  `AppSettings.AssistantAsksBeforeChanging` in `AssistWindow` and then never
  read, so the switch in Settings did nothing; and the discoverability nudge
  after fifteen accepted plans ("The assistant shows what it is about to do
  before doing it. You can change that in Settings.") was firing and
  describing behaviour the app did not have. A setting that is stored,
  displayed and ignored looks exactly like a setting that works.

  Now ported. Two Windows-specific pieces the mac may care about:
  `AssistToolOutcome.isPlan` is an in-process field here and had to become a
  second `_meta` key over MCP (`plantoir.app/isPlan`, sent only when true) so
  the gate can tell a plan from a plan tool's REFUSAL; and
  `AssistAgent.PlanTwins` deliberately omits `re_date_classes` even though the
  contract lists a twin for it, because it is not a tool the local model is
  shown and its twin does not mark its answer.

- **Windows was chatty for one structural reason, and it was not wording**
  (Windows, 2026-08-18, `windows-sync`). Recorded because the mac's own
  design is what fixed it, and because the reasoning behind `AssistToolOutcome`
  is not written anywhere the Windows side could have read it.

  Every Windows tool returned ONE string, and it was shown to the teacher AND
  fed to the model. So "read Unit 2, Day 3" put a lesson's entire Markdown in
  the chat window; "what pages are in this section" put sixty file paths
  there; a publish said "Published 4 pages (A, B, C, D) and rebuilt the
  preview of ICS3U Section 1"; and every plan ended with "Show this to the
  teacher and ask before going ahead" — a sentence addressed to the model,
  directly above the two buttons that ARE the asking. Two earlier attempts at
  this (log rows 344 and 345) shortened individual sentences and fixed the
  turn-taking, and neither touched the split, so the chattiness survived both.

  The mac's teacher-facing lines are now Windows' too, word for word:
  `Read “Unit 2, Day 3”.` · `Found 42 pages in ICS3U Section 1.` ·
  `Nothing matched in ICS3U Section 1.` · `Published 4 pages.` ·
  `Unpublished 2 pages.` · `Published the class on 2026-09-10.` ·
  `It's already been published.` · `Added Unit 2, Day 4, dated 2026-09-14.` ·
  `ICS3U Section 1 meets on 75 recorded days.` ·
  `Scheduled: ICS3U Section 1 deploys to Netlify at Tuesday 9 June, 6:30 AM.`
  Undo now speaks the contract's sentences rather than its own.

  **The one thing the mac may want to know for its own sake**: the split
  costs the mac nothing because its runner is in-process, but Windows drives
  the same `plantoir-mcp` Claude Code drives, so the summary needed a wire.
  It rides in the tool result's `_meta`, under `plantoir.app/teacherSummary`,
  and the text content is untouched — Claude Code sees exactly what it saw
  before. Rejected: a second text content block (Claude Code would read both
  and report the teacher's line as part of the answer), and
  `structuredContent` (it is validated against a declared `outputSchema`, and
  declaring one changes what every client sees of every tool). If the mac's
  MCP server ever wants to hand a summary to a client of its own, that is the
  channel, and `AssistToolAnswer.TeacherSummaryKey` is the frozen key.

  Two smaller things found in the same sweep, both fixed on Windows and
  neither present on the mac: the turn-ending list named `roll_over_course`
  for a tool actually called `roll_over_section` (so that write got the model
  a lap it should not have had, and the teacher a paragraph restating the line
  above it), and `list_recent_changes` ended by telling a teacher that
  "undo_last_change takes the most recent one back" — rule 1, in the one place
  a teacher is most likely to be reading.

- **Anything you build over there now owes a trail line** (mac, 2026-08-16).
  Plantoir keeps a breadcrumb trail so a problem reported next week can be
  looked into without asking the teacher to reproduce it, and the rule binds
  both sides: **every new feature, and every changed behaviour, that a teacher
  can see records an event.** The list lives in
  [`contracts/shared-rules.json`](contracts/shared-rules.json) →
  `activityTrail.mustRecord`, with `lineShape` and `promptMarker` beside it,
  and a test pins it against each app's own event list.

  The direction rule applies as usual and in your favour: **propose an event by
  adding it to `mustRecord`.** The mac suite will go red until this side
  records it — that is the mechanism working, not damage — so name the case in
  "Contract cases waiting on the mac" above and it reads as a request. The
  reasoning, the storage locations and what must never be recorded are in
  `WINDOWS-HANDOFF.md` under "Problem reports"; `CLAUDE.md` rule 5 is the short
  version.

- **A divergence was reported TO Windows, not from them** (mac sweep,
  2026-08-16). The first-deploy marker: this side reads the marker for the
  course's CURRENT destination, `AssistWorkspace.cs` accepts either folder.
  Written up in `WINDOWS-HANDOFF.md`. Nothing to do here — the mac's behaviour
  is the correct one — but if they answer with a reason for their version,
  that answer belongs in `contracts/file-formats.json` beside the rule.



Things to KNOW rather than to do. An item here that grows an ask should move
up to **Open** instead of hiding a to-do in a list nobody reads for work — which
is what happened to the test-race item, sitting here for three days with
"worth ten minutes to check" in the middle of it.


- **WSL2 / Container-Internal ext4 Build Acceleration** (Windows + shared, 2026-08-18, commit `ed868215`).
  Accelerated Quartz site builds on both platforms by eliminating the virtual host mount I/O bottleneck (WSL2 9P DrvFs on Windows, Colima virtiofs/9P on macOS):
  - **The Problem**: Staging the 15,000+ files of Quartz's scaffold and `node_modules` in `courses/<COURSE>/.merged_output/section<N>` meant that all TypeScript transpilation, esbuild bundling, and markdown AST parsing traversed virtual filesystem mount layers. On Windows with WSL2, initial builds took 2–4 minutes; on macOS, clean builds took ~18.7s with 14s burned on `npm install` across the mount boundary.
  - **The Solution**:
    1. Pre-bake `npm install` inside the container image in `/opt/quartz` (`Dockerfile`).
    2. In `scripts/build_site.py`, stage the Quartz workspace on native Linux ext4 storage (`/tmp/quartz-builds/<COURSE>/section<N>`), symlinking `/opt/quartz/node_modules` instantly.
    3. `scripts/build_site.py` runs differential `rsync -a --delete` to mirror `public/` and `course_config.json` back to `/teaching/courses/<COURSE>/.merged_output/section<N>/public/` upon build completion (and via a daemon thread in `--serve` mode), preserving 100% compatibility with `BuildFreshness`, `SectionDetailView`, `ScheduledDeploy`, and `deploy.py`.
    4. Updated `preview.ps1` and `preview.sh` `--stop` scripts so `PreviewStopper` checks `/tmp/quartz-builds/...` PIDs in addition to `.merged_output/...`.
    5. Updated `deploy.py` to support container-internal rebuilds.
  - **Results**:
    - **macOS (Apple Silicon + Colima)**: Full/clean builds dropped from **18.66 s avg** (18.39 s min) down to **5.08 s avg** (4.58 s min) — **3.7× faster**; incremental rebuilds dropped from **4.42 s** to **3.35 s** (1.32× faster) on `EXC2O` (260 Markdown files).
    - **Windows (Intel Core i5 + WSL2)**: Initial scaffold copy dropped from 45s to < 0.1s; `npm install` over 9P dropped to 0s; site builds run at native NVMe/ext4 speeds. All 570 Windows unit tests pass.
  - **✅ DONE (Adopted on macOS & merged to main, 2026-08-18).** All 760 macOS unit tests and `./verify.sh` pass.

- **Arrow-key prompt history navigation in Windows assist chat** (Windows, 2026-08-18).
  Windows now supports Terminal-style Up/Down arrow key history navigation in `AssistWindow.xaml.cs`.
  - **Behavior & Contract**: Follows `contracts/assist-cases.json` → `promptHistory`. Up recalls earlier prompts (newest first), Down recalls later prompts, half-typed draft is preserved and restored when walking back down past newest, Up at oldest or Down when not walking passes the key through to the `TextBox` (letting caret move to start/end), typing/editing ends the walk, and multi-line text passes arrow keys through to allow vertical caret movement.
  - **Persistence**: Added `AssistPromptHistories` dictionary to `AppSettings.cs` (`%LOCALAPPDATA%\Plantoir\settings.json`), keyed per section (`$"AssistPromptHistory-{course.Code}-{section}"`) matching macOS `@AppStorage` convention.
  - **Reference**: `AssistWindow.xaml.cs`, `Plantoir.Core.Assist.AssistPromptHistory`, and unit tests in `Plantoir.Tests.AssistPromptHistoryTests` (514 tests passing).

- **Windows local assistant moved out of WSL2 to host process with Vulkan GPU acceleration** (Windows, 2026-08-17).
  Windows now runs `llama-server.exe` natively on the host instead of running a Linux container in WSL2.
  - **Why**: In WSL2 without GPU pass-through, a 3,400 token prompt prefix took ~175 seconds across 2 virtual CPU cores, necessitating an artificial progress countdown bar, a 98 MB disk prefix cache (`--slot-save-path`), and a background keep-awake hack (`_keepWslAwake`). Moving to a native Windows host process enables Direct3D12/Vulkan GPU acceleration across Intel/AMD/NVIDIA graphics and multi-threaded host CPU fallback.
  - **Vendor fetch & bundling**: Added `windows-app/Vendor/fetch-llama.ps1` downloading pinned build `b10435` (`llama-b10435-bin-win-vulkan-x64.zip`) into `windows-app/Vendor/llama/`. Updated `Plantoir.csproj` to bundle into `llama\` output, and `publish.ps1` to sign `llama-server.exe`.
  - **Hardware Measurements**: Measured on teacher laptop hardware — `Intel Core i5-8365U CPU @ 1.60GHz` (4C/8T), `Intel UHD Graphics 620` (8062 MiB Vulkan device memory), 16 GB RAM:
    - *Vulkan GPU (`-ngl 999 -dev Vulkan0`)*: Prompt processing (`pp512`): **25.82 tok/s**, Generation (`tg128`): **7.83 tok/s**, single turn cold response: **~17.99 s**.
    - *Host CPU fallback (`-ngl 0`)*: Prompt processing (`pp512`): **25.69 tok/s**, Generation (`tg128`): **11.67 tok/s**.
  - **Simplification**: Removed the fake 3-minute progress countdown and disk KV cache files from `AssistWindow.xaml.cs`. Warmup is now a fast, non-blocking background priming call. 464 tests passing in `Plantoir.Tests`.

- **Assist scenario contract runner & confirmation discovery parity on Windows** (Windows, 2026-08-18).
  The Windows side wired `AssistScenarioTests.cs` executing all 17 multi-turn scenario cases from `contracts/assist-cases.json` via parameterized `[Theory]` tests against `AssistAgent`.
  Async preview teardown before deploy was implemented via `PreviewStopper.StopSectionProcessesAsync` and `SectionDetailView.StopPreviewIfRunningAsync`, ensuring container and host preview server ports are fully vacated before `deploy.ps1` runs.
  Confirmation mode (`AppSettings.AssistantAsksBeforeChanging`) and 15-plan discovery milestone tracking (`plansAccepted >= 15` app-wide) were wired into `AssistAgent` and `AssistWindow.xaml.cs`, verified by `ContractTests.cs`. All 488 tests pass.


- **Windows marketing screenshots & platform-conditional serving on plantoir.app** (Windows, 2026-08-17).
  The Windows side implemented autonomous screenshot capture in `MarketingShotCapturer.cs` (`Plantoir.exe --capture-marketing-shots <dir>`) and `website/shots/capture_windows.py`.
  The 5 app-window marketing shots (`courses`, `new-course`, `progress`, `preview`, `assistant`) are captured in Light and Dark mode at 2x HiDPI resolution, optimized with WebP companions into `site/img/`.
  In `website/build.py`, `picture_element` outputs both Mac (`.shot-platform-mac`) and Windows (`.shot-platform-windows`) `<figure>` blocks when Windows variants exist.
  `website/layout/base.html` detects Windows visitors via an inline `<script>` in `<head>` and toggles CSS class `is-windows` so Windows visitors see native Windows WinUI 3 screenshots while macOS visitors continue seeing native macOS SwiftUI screenshots.


- **Cleanup that fails must not fail a test that passed** (Windows,
  2026-08-14, `0479d44`). An intermittent failure that never reproduced turned
  out to be 23 tests ending with a bare
  `finally { Directory.Delete(root, recursive: true); }`. On Windows that
  throws whenever anything still holds a handle in the folder — Defender
  scanning the files the test just wrote, or the Search Indexer. Every
  assertion had passed; the test failed on housekeeping. If the mac's tests
  do the same on a machine with Spotlight indexing, the same shape is
  available. Deleting a temp folder is housekeeping: when it does not work,
  the OS will get to it.


- **The MCP proposal's Phase 0 question is settled** (asked 2026-08-12,
  answered 2026-08-15). The design for letting AI assistants drive Plantoir
  over MCP — "publish the Science courses overnight and un-draft tomorrow's
  class plus everything it links to" — asked the mac side whether to ship
  **one** self-contained .NET binary serving both platforms, or reimplement
  the tool contract in Swift. Both halves are now code rather than a
  question: `windows-app/Plantoir.Mcp/` is built and on `main`, and the mac
  reimplemented the contract in `Models/Assist/AssistMCPServer.swift` — the
  app itself answers `--mcp-stdio <folder>` rather than shipping a second
  binary, off the same `AssistToolSurface` the assistant window uses, so the
  two clients cannot drift. The handshake is recorded in the entry above.
  (The proposal itself is now folded into `research/ai-assist/HISTORY.md`.)


- **The Windows icon derives from `mac-app/Plantoir.icon`** (2026-08-11).
  `windows-app/Plantoir/Assets/make-icon.ps1` turns a full-bleed 1024px
  Icon Composer export into the exe/.ico and About-panel assets, applying
  the macOS rounded-rect silhouette; `site/icon.png` on plantoir.app
  comes from the same export. If the icon art ever changes, tell the
  Windows side so those derived assets are regenerated — nothing updates
  them automatically.


- **Auto-update plans need appcast coordination** (2026-08-12). Windows
  will adopt WinSparkle (paired with an Inno Setup installer, planned
  after v1.0); if/when the mac app adopts Sparkle, BOTH appcasts should
  live on plantoir.app in this repo's `site/` — use per-platform file
  names from the start (`appcast-windows.xml`, `appcast-macos.xml`) so
  the two update feeds never collide, and add the release-time appcast
  edit to the shared checklist in `RELEASING.md` when the
  first one lands.


- **The mac release asset must be named exactly `Plantoir-macOS.zip`**
  (2026-08-11; SPECCED — the mac ships a zip, not a dmg: Safari
  auto-unzips, average users fumble the dmg ritual, and Sparkle handles
  zips natively). plantoir.app now lives in `site/` in this repo
  (Netlify deploys it on push) and its download cards link straight to
  `releases/latest/download/<asset-name>` — GitHub's evergreen URL that
  only works while every release names its assets identically. Windows
  ships `Plantoir-win-x64.zip`; the mac card expects
  `Plantoir-macOS.zip`. The names are frozen: renaming an asset silently
  breaks the site's download button.


- **The release process is shared — read `RELEASING.md`**
  (2026-08-11). The decisions that bind both sides: ONE product version
  series in lockstep (Windows reads `<Version>` in `Plantoir.csproj`;
  keep the mac marketing version matching), ONE GitHub release per
  version carrying BOTH platforms' assets (plantoir.app's download cards
  point at `releases/latest`), tag `v<version>`. Release notes are
  drafted by Claude via the `cut-release` skill
  (`.claude/skills/cut-release/`) — teacher-friendly bullets from the
  commit log plus a SHA-256 downloads table; the mac asset should be
  attached to the same release and hashed into the same table. (The
  `.claude/skills/example-content/` skill has since arrived — the mac
  side un-ignored `.claude/skills/` and committed it.)


- **Course-catalog repairs** (`37dc6c8`): MTH1W read "Mathematics,
  Grade 9, Grade 9, Destreamed" (short name "Math,") and PLF4M had the
  same doubled-grade + trailing-comma pattern; both repaired in
  `support/ontario_secondary_courses.json`. The mac app picks this up by
  rebuilding (bundled support folder). No other entries matched either
  pattern.


- **Toolchain hash changed** (`94e25f8`): `scripts/deploy.py` changed,
  so the next preview/deploy on any machine rebuilds the Docker image
  once.


- **Windows caught up with rows 91–96** (`e7076ae`): Starting Content
  toggles, structure lock, LCS terminology switch, and the neutral
  factory defaults are now mirrored on Windows (including the
  `WizardDefaults` pairing and a Windows `ExampleContentCatalog`).
  Nothing to do on mac — listed so the mac side knows the wizards agree
  and that changes to `DEFAULT_*`/`LCS_*` in `scripts/setup_course.py`
  must now be mirrored in BOTH apps' `WizardDefaults`.


## Done — the ledger

- **Windows has the `TEACHERS SAY:` phrasings now, measured rather than copied
  on faith — the phrasings half of GitHub issue #66** (Windows, 2026-09-08,
  branch `issue/41-teachers-say-phrasings`; `GUI-IMPROVEMENTS.md` row 457;
  numbers in `research/ai-assist/teachers-say-results.txt`). **The mac is
  expected to KNOW; what it OWES is two GitHub issues**, not lines in this file
  — work tracking moved to issues the same day. ✅ DONE on this side.

  **What it fixed.** `PlantoirTools.cs` had no `TEACHERS SAY:` clause at all on
  `add_next_class`, `plan_add_next_class`, `read_remembered_timetable` and
  `remember_timetable` — seventeen phrasings the mac shows the model and this
  side showed it nowhere. Then `dev` was merged mid-branch and the mac's six new
  MCP tools arrived, three of them (`add_classes`, `list_courses`,
  `make_room_for_classes`) carrying clauses their Windows equivalents lacked, so
  it ended as twenty phrasings across seven tools. All are now the contract's,
  character for character, and **pinned by a test** —
  `AssistSurfaceContractTests.TheTriggerPhrasingsAreTheContractsOwn`, with
  `check_section` as the one agreed departure.

  **Why only ten needed measuring.** `AssistAgent.ForTheLocalModel` holds
  thirteen names. Of the seven tools, only `add_next_class` and
  `read_remembered_timetable` are in it; the rest are read by Claude Code over
  MCP and by nothing else, and `Briefly()` puts the clause FIRST in what the
  local model reads. Issue #66 asked for the measurement and said only this
  side could take it — the mac cannot run this hardware.

  **Numbers, with the hardware.** Intel Core i5-8365U (4 cores / 8 logical),
  15.7 GB RAM — which picks the SMALL tier, the 16 GiB Large threshold being
  just out of reach — Intel UHD Graphics 620 over Vulkan with
  `--n-gpu-layers 999`, qwen2.5-1.5b-instruct-q4_k_m, llama.cpp build 10435,
  the exact arguments `LocalModel.BuildArguments` produces. 25 probes × 5
  trials, temperature 0. **The defensible headline is the probes under test:
  40/50 → 50/50, with no control regressing.** Overall went 95/125 (76%) →
  110/125 (88%), but a third of that gain is one control — "That was wrong,
  revert it" — flipping 0/5 → 5/5 for no reason anything in the change
  explains, so it is not claimed as a benefit. Median call 7.9 s → 6.9 s;
  server resident cost 1,494 MB.

  **The two probes the phrasings fixed were MISROUTES, not declines** —
  "Set up next day's lesson" was reaching `schedule_deploy` five times out of
  five, and "When does this class meet?" was reaching `check_section`. A
  sentence about writing a page answered by the tool that puts work in front of
  students is the expensive kind of wrong.

  **Five traps. This is the part that travels, and the mac meets four of them
  the moment it measures anything.** Three were found by adversarial review
  rather than by writing the code.

  1. **A hand copy of a shipping list goes stale silently.**
     `research/ai-assist/narrow-tools.py` copies `ForTheLocalModel` by hand. It
     was right when committed 2026-08-14 and wrong from 2026-08-17 (4089c752),
     when the set went from fifteen names to thirteen: it was still keeping
     four `plan_` tools the app no longer shows and MISSING both tools about to
     be measured. Nothing could catch it — a research script runs by hand,
     months apart — so `NarrowToolsMirrorTests` now fails on drift, proved by
     perturbing the Python and watching it name the offender. REJECTED:
     adjusting it by hand at measurement time, which is the arrangement that
     had just failed. The three results files measured inside that window are
     sound and are named in the script, so nobody discards them.
  2. **The dateline decides the answer.** `Say` appends
     `" (Today is YYYY-MM-DD, a Weekday.)"` to every message the model sees. A
     first pair of runs omitted it and was thrown away — but the ten test
     probes were identical, leaving one clean comparison: **25/50 without the
     dateline against 40/50 with it.** Three of those probes pass on the
     dateline alone, with no phrasing change at all, so a before/after run
     without it would have handed the phrasings credit for work the app was
     already doing. `trimmed-surface-results.txt` had already recorded the same
     line being worth fifteen points when prepended instead.
  3. **There are THREE interception layers before the model, not one:**
     `PreviewAskedForPlainly` (thirteen exact sentences),
     `AssistCardCommand.Matching` (`FixedShapes` plus its three parsers), and
     four inline regexes in `AssistAgent.CardCommand` itself. Three controls
     were sentences the app answers WITHOUT the model, so they measured
     nothing. The mac's `AssistCardCommand.swift` has the same shape.
  4. **Making a research script stricter can delete a control.** Requiring the
     course code in `narrow-tools.py` read as a tightening and would have
     silently turned `trimmed-surface-suite.py --real-course` into a no-op,
     destroying the A/B its own docstring rests on. Optional now, and says why.
  5. **A parity claim is only true of the surface it was checked against, and
     of the PART of it that was checked.** The gap was closed against a 25-tool
     shared surface and reopened hours later by the mac's six new tools. And
     "the wording matches now" would be false: what matches is the
     `TEACHERS SAY:` CLAUSE. Of the 32 shared tools, **29 full descriptions
     differ**, and of the thirteen the local model is shown, **five differ in
     the text `Briefly()` produces**. Re-run the comparison; never quote a
     count from a write-up.

  **Also corrected, because it would have sent the next Windows session
  wrong:** `tools-from-contract.py` and `routing-suite.py` both told a reader
  to start a measurement from the contract. On Windows that scores the MAC's
  descriptions on Windows hardware, since the contract is generated there.

  **Still wrong on both platforms, recorded rather than fixed:** "Put it online
  tomorrow morning at 6:30" routes to `deploy_section` rather than
  `schedule_deploy` 5/5 (fails safe — deploying is gated by the button — but
  the teacher is asked to deploy NOW); "Don't send it in the morning after all"
  declines 5/5; and "Delete the Unit 1 folder" still picks a tool instead of
  declining, which `AssistAgent`'s own comment already names as unsolved.

  Reference: `windows-app/Plantoir.Mcp/PlantoirTools.cs`,
  `windows-app/Plantoir.Tests/AssistSurfaceContractTests.cs`,
  `windows-app/Plantoir.Tests/NarrowToolsMirrorTests.cs`,
  `research/ai-assist/teachers-say-suite.py`. The reasoning lives in
  `WINDOWS-HANDOFF.md` → "The two MCP surfaces are not the same product".

- **The folders-help row check runs the contract's own case list — item 40**
  (Windows, 2026-09-08, branch `issue/folders-help-row-check-cases`;
  `GUI-IMPROVEMENTS.md` row 450). **The mac is expected only to KNOW; it owes
  nothing** — it made this fix first, on 2026-09-06. ✅ DONE.

  **What it fixed.** `SpecialFoldersHelpContractTests.TheRowsAreTheContractsRowsInTheContractsOrder`
  built one hand-typed course whose `shared_folders` were `["Tasks","Ontario
  Curriculum"]`, so the curriculum row always resolved to a real folder and the
  PLACEHOLDER branch of that row's explanation was compared with nothing. It is
  the only test on either platform comparing a row's `Why` with the contract's,
  so the sentence the mac retired in row 425 could have arrived here unnoticed.
  It now loops `specialFoldersHelp.cases` and builds each course through the
  same `CourseFrom(figure)` the naming test already used — no second fixture
  invented to drift — asserting the row count, `what`, `why` and the
  `namedFrom: "fixed"` names per case with the case's own name in every message,
  and asserting at the END that both branches were actually reached. Two of the
  six cases end up with no curriculum folder at all, which is what makes the
  placeholder branch reachable.

  **Measured on this PC rather than inherited, because the mac's own numbers
  were measured against Swift and prove nothing here.** The reversion was
  reproduced as a placeholder-only variant of the curriculum `why` in
  `SpecialFoldersHelp.cs` — Windows never shipped the sentence, so there was
  nothing to put back, only the shape of it to introduce. Against the OLD test:
  **5 tests, 0 failures.** Against the new one: **5 tests, 1 failed**, whose
  message lists **2 mismatches** naming "asked and cleared: an empty pool is a
  real answer" and "more than one class folder is listed, not just the first" —
  the same two cases the mac's reversion named. The product code was restored
  immediately after; the branch touches one test file and the documents.

  **The one deliberate deviation from "ports line for line", and WHY.** Item 40
  named two traps, and the first does not survive translation: **xUnit's
  `Assert` throws where XCTest records a failure and carries on.** Written as a
  straight sequence of `Assert` calls, the documented `continue` guard would be
  unreachable — the first mismatch would end the test — and the
  reversion above would have named ONE case where the mac names two, which is a
  weaker signal for the same bug. So mismatches are collected into a list and
  asserted together at the end, which gives the loop the record-and-continue
  behaviour XCTest has natively and makes the `continue` guard real. **It is
  also the established pattern in this test project rather than something
  invented for this branch** — `AssistSurfaceContractTests`,
  `SharedRuleContractTests` and `PublishAndLauncherContractTests` build a
  `List<string>` of offenders and report them joined in one terminal assert,
  and `MilestoneContractTests` and `FileFormatContractTests` do the same with a
  `HashSet<string>` checklist. **Said by SHAPE rather than as a count, because
  two drafts of this sentence got the count wrong** — the first claimed SIX
  files, adding `GradedFolderContractTests` (no `string.Join` at all; its one
  `List<string>` is a product-model assignment) and `ContractTests` (whose
  `allStrings` is a list of INPUTS to scan, `Assert.False`d per term, so it
  throws on the first offender — the pattern this branch moved AWAY from);
  the second said FOUR and missed `FileFormatContractTests`, which has the
  identical `HashSet` shape. The first draft also called itself "confirmed by
  review rather than assumed", which is the worse half: it claimed the very
  check that had not been performed. Both corrections were made after the files
  were actually opened. **Rejected:
  leaving the Asserts to throw** (simpler, and the trap item 40 spelled out
  would then be decoration), **and splitting the cases into an xUnit `[Theory]`
  with a `MemberData` source** — tempting, since it would name each failing
  case as its own test, but the both-branches-reached check has to see every
  case in one run, and a Theory cannot assert across its own rows: xUnit builds
  a fresh test-class instance per row and offers no "after all rows" hook. The
  one workaround — static counters asserted from a collection fixture's
  `Dispose` — is worse in a way worth naming, because it would FALSE-FAIL
  on any filtered run (`--filter`, or one row from Test Explorer), a single
  row being able to reach only one branch. That check is
  the half that stops the case list quietly drifting back to all-have-a-folder,
  so it decided it. **The nearest surviving alternative is a `[Theory]` for the
  per-case half PLUS a companion `[Fact]` for branch coverage**, which does
  satisfy it; it was passed over for costing two entry points and a second pass
  over the same case list to name each failing case, which the messages here
  already do. Named so it is not re-proposed as though it had been missed.

  **Reference:** `windows-app/Plantoir.Tests/SpecialFoldersHelpContractTests.cs`;
  the mac's equivalent is `SpecialFoldersHelpTests.swift`. No product code
  changed and no teacher-facing sentence changed on either platform.

- **Windows renames a course folder from inside the app, records the change
  from a fresh read, and can finish a rename that stopped half way — items 13
  and 17, one piece** (Windows, 2026-09-07, branch
  `issue/13-rename-folder-and-config-writers`; `GUI-IMPROVEMENTS.md` rows
  441–443). **The mac is expected to KNOW; it owes a reading of one
  sentence (top of this file).** ✅ DONE.

  **What landed, against the mac's shape.** `SpecialFolderRenamer.Rename` is
  `rename(_:to:scope:…)` ported: every destination checked first, a
  capitalisation-only rename allowed through, the record written before the
  first move, `Directory.Move` per location, a half-failure thrown as
  `HalfFailureMessage` naming the section that stopped it, then
  `RelinkPages` over every page in the course. `Renaming(JObject…)` is
  `renaming(_:to:scope:in:)` ported, materialisation included: the class
  folder is recognised through `WasSurelyTheClassFolder` — the recorded key
  when it names a real folder, otherwise only a name containing "class" that
  the resolver picks, so a first-folder GUESS is never frozen into the key
  (the review caught a first draft that used the bare resolver) — and the
  curriculum folder through `CurriculumFolderRule.Resolve`, both decided
  BEFORE the list is rewritten; `hidden`, `expandable` and `graded_folders`
  are rewritten from either scope; `curriculum_folder`, `class_folder` and
  `excluded_items` only in their own scope; every list is de-duplicated so
  finishing an interrupted rename leaves one name, not two.
  `CourseConfiguration.RecordOnDisk` is `recordOnDisk` ported whole — three
  compare-and-swap tries, then the FRESHEST bytes, and the change applied
  to the in-memory object with the bytes written as its last-saved state, so
  Revert keeps the rename and drops only what was never saved (a first
  draft of this entry called that an addition; it is the mac's own last two
  lines). `Write` is untouched, and
  `WriteIsUnchangedAndRevertStillDoesWhatItSays` pins that it does NOT
  read-compare-write. The record lives at
  `courses/.internal/renames/<CODE>.json` with `from`, `to` and `scope`;
  `InterruptedRenameTarget` answers only when the record and the disk agree
  (no place still holds the old folder, at least one holds the new).

  **The decisions, as the brief recorded them and as built.** A pencil on
  each folder row (rejected: a context menu, invisible to everyone else; and
  double-click-to-edit, which fights the sheet the contract words). A
  half-failed rename leaves the moved sections moved and names the one that
  stopped it (rejected: rolling back, which can itself half-fail and moves a
  teacher's folders a second time unasked). A separate recorder, `Write`
  untouched (rejected: making `Write` read-compare-write, which would change
  what `HasUnsavedChanges` and Revert mean). An interrupted rename is
  explained in the sheet in one line and pre-filled (rejected: silent
  pre-fill; a modal on opening Settings). The two foot-guns: Add creates
  the folder in every section and says so; Remove says the folder stays.

  **Two shared limits, written down rather than fixed.** The record is one
  file per COURSE, and any successful rename clears it — so a teacher with
  an interrupted `Tasks → Assignments` who renames another folder first, or
  types a different name into the pre-filled sheet, loses the only evidence
  and is back in the dead end; the mac's `clearRenameRecord` does the same.
  And `recordOnDisk`'s last-saved bytes carry any key another writer put
  there that the in-memory object lacks, so a form nobody edited can show
  as dirty after a build wrote `unit_word` — identical on both platforms.
  Neither is this branch's to change alone; both want a decision.

  **Windows specifics.** The dialog's Rename button is the default (the
  mac's sheet submits on Return too); the refusal is re-asked on every
  keystroke with the "finishing" waiver granted only when the typed name
  equals the recorded target; the move and the relinking run off the UI
  thread; a capitalisation-only rename is allowed through, as on the mac,
  which meant loosening this side's "unchanged" refusal from case-insensitive
  to exact. The sentences a teacher reads: the contract's, with "on this PC"
  for "on your Mac" in `removeLeavesTheFolderOnDisk` as the two rename
  sentences already do. Not driven by hand — worth one look: rename a
  per-section folder with Obsidian holding a file in it open, which is the
  one failure the message exists for.

- **Windows' folders-help jargon sweep now matches the mac's: it scans what
  the product writes, not the teacher's folder names** (Windows, 2026-09-07,
  branch `issue/32-folders-help-jargon-sweep`; item 32 struck). **The mac is
  expected to KNOW.** ✅ DONE. The trap the mac's first draft fell into is
  avoided the same way: only course-named rows drop out, and the four
  `namedFrom: "fixed"` names (Media, index.md, Key Links.md, Curriculum
  Coverage) stay swept, asserted as exactly four. The fixture has a marks
  folder called "Scripts" and no curriculum folder, so the exclusion is
  exercised rather than written and "Your curriculum folder" / "None chosen"
  are rendered by a test for the first time. All six product strings exist on
  Windows; nothing was added or weakened. The test count is unchanged — one
  test rewritten, not one added — which the brief's "goes up" did not
  foresee.

- **Windows writes the builds-folder marker and sweeps abandoned builds —
  from the app, not the launchers, which is the opposite of what the mac's
  review argued** (Windows, 2026-09-07, branch
  `issue/19-build-marker-and-sweep`; `WINDOWS-HANDOFF.md` item 19 struck;
  `GUI-IMPROVEMENTS.md` row 437). **The mac is expected to KNOW; it owes the
  counter-argument a reading, not code.** ✅ DONE.

  **Why the app and not `Enter-NativeRuntime`.** The mac's review argued for
  the launchers, because a launcher run without the app (a command line, a
  scheduled deploy) makes a builds folder the app would never name. Two
  things decided it the other way here. `Enter-NativeRuntime` is defined
  THREE times, not once (`preview.ps1`, `deploy.ps1`, `setup.ps1`), each
  needing a `New-Item -Force` before the write because none of them creates
  the builds folder; and `verify.sh` does not run on Windows, so a launcher
  edit made unattended has no automated gate at all. What the launcher
  version bought is recovered instead: at launch, for the open folder and
  every remembered window's, a builds folder that exists without a marker is
  named retroactively (`AdoptWorkingFolderMarkers`). After a launch or two
  every builds folder belonging to a working folder the app has ever opened
  is named, whichever tool created it; the only unmarked ones left belong to
  somebody who has never opened the app on that folder, and those are left
  alone rather than guessed at. The marker's content is
  `FolderContainers.PhysicalPath` — the same string the id was hashed from.

  **The sweep's bar, said plainly.** `DiscardBuildsForMissingWorkingFolders`
  runs once per process from `App.OnLaunched`, silently, with no trail line
  (a teacher cannot see it; rule 5 is about what they can). It reads each
  builds folder's marker, ignores unmarked folders and any path not under
  `%USERPROFILE%`, and asks `GetFileAttributesW` rather than
  `Directory.Exists`, which swallows the reason it says no: only
  `ERROR_FILE_NOT_FOUND` (2) and `ERROR_PATH_NOT_FOUND` (3) mean gone.
  **Measured, 2026-09-07, Windows 11 26200, after a review caught a wrong
  claim:** `Q:\Teaching` on an absent drive letter answers **3** — the
  error-code rule would sweep it. So the two guards do different jobs, and
  the write-up must not blur them: the HOME-FOLDER filter is what protects
  removable media (a USB stick's folder is `E:\…`, never under home — the
  mac's own reasoning), and the error-code rule protects a folder that is
  present but unreachable — a sleeping network share (53, 1231), a card
  reader with no card (21), a folder this account may not read (5, which is
  rare on Windows: bypass-traverse lets attributes be read past most ACLs,
  so the mac's TCC rationale does not transfer). A OneDrive folder not on
  this computer just now reads its attributes locally and is simply present.
  `TheSystemIsAskedWhyAFolderIsMissingNotJustWhetherItIs` pins the two
  answers that separate the rule from `Directory.Exists`, and
  `TheSweepRemovesOnlyABuildWhoseWorkingFolderIsGenuinelyGone` pins the
  home filter and the unmarked case with the system's answer injected.

  Three more things the review found, written down rather than fixed. The
  marker is written only once a folder is known to be a WORKING folder
  (after `Reload`, `State == Ready`) — a first draft wrote it on every open,
  which would have made a builds folder for a Downloads picked by mistake
  that the sweep could never remove. A UI test that ever drives Preview will
  make a real `%LOCALAPPDATA%\Plantoir\builds\<id>` for a fixture path,
  because the launchers compute the root from `%LOCALAPPDATA%` themselves
  under `--state-dir`; it is permanently unmarked and left alone, the same
  hole the mac's `isRunningTests` guard closes — none does today. And a
  removable volume mounted at a path UNDER the home folder, with no drive
  letter, would be recorded under home and swept when unmounted (unverified;
  no spare volume): the cost is a rebuild, not lost work. The marker's name
  and content shape match the mac's; a contract twin under
  `buildOutputLocation.windowsLocation` with the sweep's rules would be the
  next honest step and is proposed, not done.

  **The adjacent question, answered.** Can
  `%LOCALAPPDATA%\Plantoir\builds\<id>\<CODE>` outlive an archived course and
  be adopted by a later restore into the same code? No: `CourseArchiver`
  discards the course's builds on archive (course and section), and
  `CourseRestorer` discards them again on every restore, so a restored course
  starts with no build and the freshness check says rebuild. Looked at, and
  already handled.

- **The two synced-folder views exist on Windows** (Windows, 2026-09-07,
  branch `issue/18-cloud-synced-folder-views`; `WINDOWS-HANDOFF.md` item 18
  struck; `GUI-IMPROVEMENTS.md` row 436). **The mac is expected to KNOW.**
  ✅ DONE. Every sentence is the contract's (`CloudSyncWording`, pinned by
  `CloudSyncedFolderTests`, untouched). At the picker: `ContentDialog`, path
  first, `DefaultButton = None`, "Choose a Different Folder…" reopens the OS
  picker in a loop — rejected: returning to the picker view (one more click
  for somebody who has already said what they want) and showing only the
  notice (the contract names two buttons for this moment). Escape or the
  close box read as "choose a different folder". A folder the picker will
  not take anyway (neither a working folder nor empty) gets no note in either
  form; re-choosing the open folder leaves whatever notice is showing exactly
  as it is, and opens no dialog. Restored or inherited: an `InfoBar` in its
  own row under the menu bar, "Show Details" in place, "Got It" always
  visible beside it, and dismissing — the button or the close box — is
  remembered as going ahead; setting up an empty synced folder from the
  picker's guidance counts as going ahead too and takes the notice with it.
  `synced folder noticed` is written only once a note is actually on screen
  (a dialog WinUI could not show is not "told"), `synced folder accepted` when
  the teacher goes ahead from either; both carry the service and the folder,
  redacted. A first draft had the picker's headline in the dialog title
  (above the path, against the contract's "path FIRST"), the summary at the
  picker moment (the mac shows it only in the notice), and "Got It" hidden
  inside the collapsed details; all three corrected on review. Not driven by
  hand, and no UI test was added: the four guards live behind one static
  function, `SyncNoteWanted`, which is the seam a test would use.

- **Windows has the way back for a whole conversation — and now saves one
  backup per conversation instead of one per change** (Windows, 2026-09-07,
  branch `issue/27-assist-conversation-restore`; `WINDOWS-HANDOFF.md` item 27
  struck; `GUI-IMPROVEMENTS.md` row 435). **The mac is expected to KNOW, and
  owes one trail event — the contract case at the top of this file.** ✅ DONE.

  **A documented behaviour changed, on purpose.** Until this branch every
  changing tool on Windows saved its own copy (`AssistWorkspace` called
  `CourseArchiver.BackUpCourse` at seven sites, unconditionally), while
  `MostBackupsKept` is five — so after six changes the copy from before the
  conversation had already been pruned, and a Restore button could not have
  kept its promise. `BackUpOnceForThisConversation` now mirrors
  `AssistToolRunner.backUpOnceForThisConversation`: lazily, at the first
  changing call, keyed by course code. Per-change undo is `UndoHistory`'s
  promise and is unchanged. The key needs no section: on Windows the tools
  run in `plantoir-mcp`, one process per assistant window, locked to one
  course, so one `AssistWorkspace` IS one conversation; an unlocked Claude
  Code session that touches several courses gets one copy per course, as the
  mac does. Two windows on two sections of the same course are two processes
  and two copies. Rejected, as the brief records: pinning the first per-change
  copy against pruning (a guarantee with an exception, and a Backups list
  that grows faster for nothing a teacher asked for); whole-course restore
  (the mac's own reason — a teacher marking Section 2 in Obsidian while
  chatting about Section 1); leaving `UndoHistory` as the story.

  **How the window learns there is a copy.** The tools run in another
  process and the answers are the only channel, so every answer after the
  first change carries the copy's path in `_meta` under
  `AssistToolAnswer.ConversationBackupKey` (`PlantoirTools.CarryingTheConversationBackup`),
  the same slot the teacher's one-line summary already rides in; Claude Code
  ignores `_meta` it does not know. The six write tools that answered in a
  plain string now answer in a result so they can carry it too. A
  conversation that only PUBLISHED counts as changed, because the publish
  tools save the copy first — matching the mac's gate.

  **What the restore does** (`CourseRestorer.RestoreSection`, a port of
  `restoreSection`): unpack and check BEFORE touching the course; replace the
  section folder's contents wholesale, hidden files included; put this
  section's per-section keys on every shared page back as the copy had them
  and change nothing else on those pages (`SettingPerSectionKeys`, the mac's
  line for line, with `SectionAdder.PerSectionKeyNumber` made internal);
  discard the section's built site. `SectionRestoreTests` covers the other
  section untouched, a shared page's words and other sections' keys kept, an
  unreadable copy leaving the section as it is, the key placement cases, one
  copy after seven changes, and the refusals.

  **Wording**: the mac's, verbatim, in `AssistSectionRestore` — banner,
  button with its ellipsis, confirmation title, the three-paragraph message
  whose third paragraph is the promise, the go-ahead, the done sentence
  ("Ask me to rebuild the preview to see it."; nothing is auto-rebuilt), and
  the three refusals. Not lifted into `contracts/`: the mac's file argues the
  wording and the code belong together, and the BEHAVIOUR is not a tool call,
  so it does not fit `assist-cases.json`'s `when: <tool>` shape — the intent
  is here instead, as rule 2 allows. Not driven by hand: the banner, the
  dialog and the note want one look at the real interface.

  **Five things the review found, kept as they are and written down.** (1) A
  recorded copy that has since gone — deleted from the Backups list, or pruned
  by five LATER conversations on the same course — is still the one the
  banner offers, and Restore then says "The copy saved for this conversation
  (…) could not be read." A first draft took a fresh copy in that case, which
  would have made the dialog's "exactly how it was when this conversation
  started" false; the mac checks only its dictionary and fails honestly, and
  so does Windows now. (2) The key restore's frontmatter parser is as strict
  as the mac's `PageFrontmatter.block` — line 1, "---" — and stricter than
  this app's own `Block.Parse`; a shared page whose block starts after a blank
  line is left alone rather than given a second block. (3) The failure note
  in the transcript is a plain "Assistant" turn; the mac marks it
  `isProblem: true` and Windows' transcript has no problem style. (4) The
  copy's path travels ABSOLUTE in `_meta`, which Claude Code can see; the
  app's own `back_up_course` answers relative. Harmless, unpretty. (5)
  `roll_over_section` answers in a string and cannot carry `_meta`; it takes
  no conversation copy, so nothing is lost, but a future tool that answers in
  a string and changes things would not raise the banner — answer in a
  result.

- **The Windows wizard asks the skeleton question, writes `use_skeleton`, and
  shows the skeleton's folders it is about to make** (Windows, 2026-09-07,
  branch `issue/25-wizard-skeleton-question`; `WINDOWS-HANDOFF.md` item 25
  struck; `GUI-IMPROVEMENTS.md` row 431). **The mac is expected to KNOW, and
  to settle one difference — the open item at the top of this file.** ✅ DONE.

  What it fixed. Decided 2026-08-16, indexed nowhere a Windows session reads
  first, and open for three weeks: `use_skeleton` was never written, so
  `setup_course.py`'s default of true answered for ~1,900 course codes and a
  Windows teacher could not decline. The contract's `knownDivergence` note is
  deleted and `FileFormatContractTests.TheWizardWritesUseSkeleton` runs.

  What was done. The mac's two sentences verbatim — "Start from a
  {label} skeleton" and the caption beginning "There is no ready-made course
  for this code" — with the toggle shipping ON. `SkeletonCatalog.Family` gained
  `GradedFolders` (the manifests' `graded_folders`, which the port had dropped)
  and `AdoptedGradedFolders` mirrors the mac's fallback to every folder
  containing "task". `AdoptSkeletonStructure` runs on each code change through
  the existing `StructureToAdopt` guard; the key is written as
  `HasSkeleton && _startsFromSkeleton`; and when a skeleton is in use the
  sidebar plan comes from `SkeletonCatalog.Sidebar`, as on the mac. With the
  toggle off the section shows the existing "Example content isn't available"
  sentence, because that is then exactly the situation it describes — the
  same sentence, not a third one.

  Rejected: writing the key alone (closes the test and leaves the editor
  showing folders that will not be made), and shipping the key now with the
  structure adoption as a later item (two sessions for one feature, with the
  misleading wizard in between). Nothing new on the trail: creating a course
  is already recorded as the task starting and finishing, and the answer
  itself is in the `course_config.json` that task writes.

  Two things the review found and the port shares with the mac, left as they
  are and written down so they are not re-found: every prefix in
  `families.json` is three letters, so a single typed "S" already adopts the
  `general` skeleton, whose label is "This Course" — the toggle then reads
  "Start from a this course skeleton" on both platforms until the code is
  long enough to resolve; and switching from a skeleton code to one WITH
  example content and then turning pre-populate off leaves the skeleton's
  folders in the editor, on both platforms. Neither is new to the mac.

  Reference: `windows-app/Plantoir/Views/NewCourseDialog.cs`
  (`AdoptSkeletonStructure`, `RestoreGenericStructure`, `SkeletonForCode`),
  `Plantoir.Core/Catalogs/SkeletonCatalog.cs`, `SkeletonCatalogTests`,
  `FileFormatContractTests`. Windows suite 1153 passed, 1 skipped (1150 and 2
  before: two test methods added, one un-skipped).

- **Windows now refuses a folder named `index.md` with the contract's own
  sentence, records the refusal on the trail, and runs the
  `reportedOncePerFinding` cases from the contract** (Windows, 2026-09-07,
  branch `issue/33-repair-refused-folder-in-the-way`; `WINDOWS-HANDOFF.md`
  items 33 and 34 struck; `GUI-IMPROVEMENTS.md` row 428). **The mac is
  expected to KNOW, not to match** — it shipped the refusal first, on
  2026-09-07, and this is Windows catching up to it. ✅ DONE.

  What it fixed. `SharedRules_ActivityTrailEvents_Exist` pins
  `activityTrail.mustRecord` by equality, so the mac's merge of
  `issue/repair-index-md-directory` turned the Windows suite red — one test,
  `1030 passed, 1 failed` — the moment it reached `dev`. That is the mechanism
  working, and it is ALSO why nine of the twelve branches of the Windows
  machine's overnight batch of 2026-09-06 were refused at its gate (the
  driver and its run summaries live outside the repository, so there is
  nothing to follow here): they were cut from a `dev` that already carried
  the new event, so every one of them inherited a failure that had nothing to
  do with its own work. Windows had answered
  `Failed` for the directory case since `3ddd4af4` — honest, and still
  sending the teacher to check permissions on a folder that is not locked.

  What was done, and where. `SiteHealthRepair.Result` gained `Refused`;
  `FolderWhereTheFrontPageBelongs(course, section)` is the sentence, filled
  from the finding's section because a C# enum cannot carry a value the way
  the mac's `blockedByAFolderWhereTheFrontPageBelongs(section:)` does — the
  per-finding tuple already has it, so nothing is lost. `OutcomeOfRepairing`
  assembles the explanation in the mac's order (generic advice first, only
  when something SIMPLY failed or nothing was refused; refusals after it, each
  named once). `RestoreIndex` writes `folder problem not repaired` from the
  directory branch only — the plain-failure path still records nothing, as the
  contract's `why` asks. `ActivityTrail.Event.FolderProblemNotRepaired` is the
  event. Tests: `SiteHealthRepairTests` (refused and left untouched, with the
  teacher's page inside it surviving; refusal alone; both kinds at once in
  the right order; refusal beside a restore; two refused sections are two
  sentences) and `SiteHealthContractTests.TheRefusalSentenceIsTheContractsWordForWord`
  plus `TheRefusalSentenceNamesNoMachinery`. Item 34's "should":
  `ARepairReportsOneResultPerFindingNeverOnePerCheckName` builds each
  `reportedOncePerFinding` case exactly as `howToRunACase` says, on two copies
  of the course — one for the results, one for the report — and replaces
  `TwoSectionsMissingAFrontPageDoNotCollapseIntoOneAnswer`.

  Nothing rejected that the mac had not already rejected: moving the folder
  aside was refused for the same reason (a folder that may hold the teacher's
  pages, moved without asking, by an app that cannot see inside it). One thing
  the mac may want to know about its own contract text is the open item at
  the top of this file.

Kept in full, newest first. A finished entry is not deleted: the mac does what
it does BECAUSE of these, and the `✅ DONE` line names what landed here and
where.

- **Windows caught up to the mac's nested marks folders — and found two things
  the mac's version does not do** (Windows, 2026-09-06, branch
  `issue/26-marks-checklist-nested-folders`, commit `02cf58b2`). **The mac is
  expected to KNOW this one, and to take the two items in the sections above;
  the rest of it is the mac's own design arriving here.**

  **What it fixed.** Windows' Marks checklist was built from
  `SharedFolders.Concat(PerSectionFolders)` — top-level names only — while
  `GradedFolderRule.CountsForMarks` matches a folder segment at any depth. With
  `graded_folders` absent meaning "never asked, historical rule applies", the
  first tick FROZE the narrow list, so a teacher who files assessed work in
  `Portfolios/Tasks` could not tick it and, from that tick onwards, every
  expectation it addressed read as never evaluated on the coverage map. Nothing
  said so, and nothing ever would. The mac has been right about this since it
  added `nestedFolderNames`; the sentence that explains the whole item is the
  mac's own, on `gradedFoldersBinding`: *"the first tick freezes it, so anything
  the build counts today and this list omits loses its marks without a word."*

  **The half that is easy to miss.** The gap was in TWO places, and fixing only
  the visible one still loses the marks: `MaterializedGradedFolders()` inferred
  from the same top-level lists, and that — not the checklist — is what the
  first tick actually writes. The mac never hits it because its binding's `get`
  filters `gradedFolderChoices`, which already holds the nested names. Both are
  now fed from one list on Windows, and a test asserts it, because a test
  covering only the visible list passes on the broken code.

  **What was copied without re-deriving, and why.** The four-level cap, the
  skip list, keeping `Media` out, and excluding `sectionN` by name while still
  walking its children are all the mac's answers. Two apps disagreeing about
  which folders count would produce two different coverage maps from the same
  course, which is the one place a divergence is indefensible — so the sub-
  questions were not re-opened. Rejected on those grounds: a different depth
  cap (four is an affordability judgement, honestly documented as a cap rather
  than completeness, and a different number would mean different pools for the
  same course); keeping `Media` in for a teacher who grades video portfolios
  (defensible, and still no, because media is not assessed work in either app
  today); and grouping or indenting the nested names under a heading (the mac's
  list is flat — same product, one shape).

  **Rejected and worth recording: warning the teacher on the first tick** that
  a folder the build counts today is about to stop counting. Arguably the real
  fix for the harm, since the walk is a cap rather than a guarantee and a
  folder five levels down is still lost silently. Not shipped: neither app does
  it, it is new teacher-facing behaviour, and it belongs in a decision made for
  both platforms at once rather than at 3am on one of them.

  **Two things Windows does that the mac does not.** Both are in the sections
  above with their full reasoning — `excluded_items` filtering (a divergence
  taken deliberately, because copying would have regressed Windows), and a
  SORT of each folder's children so the offered list has an order at all.

  **And one Windows-only caution, stated as what was actually measured.** The
  mac's walker does not follow symlinks. The obvious C# translation is to skip
  anything carrying `FileAttributes.ReparsePoint` — which is what
  `CourseArchiver.cs:226` already does — and the Cloud Files API documents a
  sync provider's unmaterialised placeholders as reparse points, which would
  make that test skip every folder in a cloud-synced working folder and put
  exactly the courses `cloudSyncedFolders` says teachers keep on purpose
  straight back on the top-level-only list this change exists to fix. No test
  would catch it either, since a temp folder is never a placeholder.

  **It was not reproduced.** Probing this machine's own OneDrive with Files
  On-Demand on (confirmed on: 3 of 4 sampled files carried the
  offline/unpinned attributes) found **zero reparse-point directories and zero
  reparse-point files**. So this is a documented hazard, not an observed
  fault, and the reason for the narrower test is that it costs nothing:
  measured on the same machine, a junction made with `mklink /J` has the
  attribute AND a non-null `LinkTarget`, a plain folder has neither, and .NET
  returns a link target only for symlink and mount-point tags. Windows uses
  `attributes.HasFlag(ReparsePoint) && child.LinkTarget is not null` — the
  attribute first only to avoid a syscall per folder. **`CourseArchiver` uses
  the blanket version** and was left alone as out of scope; worth a look on
  both platforms, with the same caveat that nobody has seen it bite.

  **Two more things the review found, neither of them Windows' to decide.**

  - **`sectionN` is matched case-INSENSITIVELY by both apps and
    case-SENSITIVELY by the build.** `build_site.py:3551` is
    `re.fullmatch(r"section\d+", name)`; the mac's test lowercases first, and
    Windows copied it. So a teacher's folder called `SECTION3` is hidden from
    the marks list by both apps while preflight would add it to
    `shared_folders` and the build would count it. The mac is looser again in
    a second way: `Int(name.dropFirst(7))` parses a sign, so `section+3` and
    `section-3` are section folders there and ordinary offered folders both on
    Windows and to the build. Vanishingly rare, and left alone deliberately
    rather than "fixed" on one side — recorded so it is not re-found a third
    time.
  - **A pooled name can end up with no row to untick**, and Windows' own
    `excluded_items` filter is one way to reach it. Tick something on a course
    with `Portfolios/Tasks`, so the pool freezes as `["Tasks"]`, then remove
    `Portfolios` from Shared folders: `Portfolios` was never graded, so
    nothing drops `Tasks`, and the next walk skips the removed folder without
    descending, so no row for `Tasks` is drawn. The mac reaches the same state
    by other routes that both apps share — a pooled folder deleted on disk, or
    one five levels down past the cap. **It is not silent and nothing is
    lost**: `_has_graded_folders` walks the MERGED tree, so a pool naming
    nothing the site publishes still raises `noGradedFolders`, and the list
    editor preserves a member it is not drawing rather than dropping it. The
    invariant that would close it — always offer what is already in the pool,
    so a tick can always be undone — is a shared product decision and a
    contract change, so it is **recommended here rather than taken on one
    platform at a time.**

  Reference: `windows-app/Plantoir.Core/Models/GradedFolderChoices.cs`,
  `windows-app/Plantoir.Tests/GradedFolderChoicesTests.cs`,
  `contracts/shared-rules.json` → `gradedFolders.choices`. Suite 1047 passed,
  2 skipped, 0 failed (1031 before).

- ✅ DONE (mac, 2026-09-06, branch `issue/help-sheet-resolved-curriculum-folder`,
  commit `3f1626be`). **The folders sheet named a curriculum folder the course
  may not have — and the sheet is now driven by the contract rather than by
  retyped sentences.**

  Windows ported the "Folders Plantoir uses" sheet (mac row 361) into
  `contracts/shared-rules.json` → `specialFoldersHelp` and, in doing so, found
  the mac wrong in two places and proposed two cases for them. Both are
  implemented; the two cases and the whole block — seven rows in order, the
  listing grammar, the banned vocabulary, the title, the intro and both button
  labels — are now run by `SpecialFoldersHelpTests` by DESERIALISING the
  contract. The suite is 1047 tests, 3 skipped, 0 failures.

  1. **The resolved curriculum folder, not the raw key.**
     `SpecialFoldersHelpView` asked `course.configuration.curriculumFolder`
     and now asks `CurriculumFolderRule.resolvedCurriculumFolder(for:)` — the
     same rule folder protection already used at
     `CourseSettingsView.swift:578`. **Windows' conclusion held here; its
     reason did not, so the mac measured its own.** On this Mac, 2026-09-06,
     across 15 real courses outside the repository: 12 have no
     `curriculum_folder` key at all, 1 has it null, 2 have it set and correct
     — and **11 of the 15 were being shown the placeholder while a real
     folder sat in the vault.** Most of the 15 are scratch working folders
     from test sessions, so read the shape rather than the population. Of the
     11: 8 are now named exactly what the build uses, 1 names a folder holding
     no expectation pages (no map either way, and the teacher is at least told
     which folder to fill), and 2 hit the limit below.
  2. **The placeholder's second sentence is retired.** "One page per
     expectation, in a folder whose name mentions the curriculum" published
     the matching rule in plain words. The row now carries ONE explanation
     whichever name it shows, which is what the contract always said.

  **Two things in the handoff's own reasoning were wrong, and both are worth
  keeping** — found by adversarial review before implementing, verified in the
  code rather than taken on trust.

  - **"Nothing writes `curriculum_folder`" is not true, and it took two
    reviews to get right.** `SpecialFolderRenamer.swift:519-532` materialises
    it on an in-app rename, deliberately. And `setup_course.py:2381` writes it
    for EVERY course made since 2026-08-23, from the payload or skeleton
    manifest — all 50 skeleton manifests declare `"curriculum_folder":
    "Curriculum"` — leaving it null only when the teacher declined a
    ready-made course. So the population that meets this defect is courses
    made BEFORE that date (12 of the 15 here), plus a stale key from a rename
    made in Finder or Obsidian rather than in Course Settings. That sharpens
    the case rather than weakening it: the sheet's whole job is the folder a
    teacher moved when Plantoir was not watching. **The first draft of this
    entry carried the wrong reason for the right fix, which is exactly the
    thing that gets "simplified" back out later.**
  - **`CurriculumFolderRule` is narrower than the build, in one way the
    handoff did not name.** The build's fallback scan walks the MERGED tree
    (`build_site.py:4035`, `content_root = output_dir / "content"`), so it
    would also find a per-section folder whose name mentions the curriculum;
    both apps scan `shared_folders` alone. Unreachable in practice — every
    manifest declares this folder as shared — and identical on Windows
    (`CourseConfiguration.cs:428`), so it is recorded in the contract's
    `rows[curriculum].source` rather than fixed. Do not "fix" it on one
    platform alone. The second narrowness was already known and was stated too
    weakly: when the recorded folder holds no expectation page the build does
    not SKIP the row, it falls through to the same scan and may pick a
    DIFFERENT folder — so the sheet can name a folder the build passes over,
    not merely one it ignores. **And it is not hypothetical:** two courses on
    this Mac keep both an "Ontario Curriculum" and a "College Board
    Curriculum" folder, the College Board pages are named "1.A" rather than in
    expectation-code form, so the shared rule's alphabetical tie-break names
    College Board while the map is built from Ontario. The tie-break itself
    was already a contract case (`specialNames.curriculumFolderResolution`,
    third case, with those exact two names), so nothing drifted — but that
    section's NOTE claimed the apps "never protect a different folder than the
    build would pick", which is now known to be false and is corrected.
    **Breaking the tie the way the build does means reading the vault, which
    is a product decision for both platforms and is written up in `TODO.md`
    rather than guessed at overnight.**

  **One test-scope decision, made on purpose.** The mac's jargon sweep reads
  the title, the intro, the button labels, the placeholder and every row's
  `what` and `why` — the text the PRODUCT writes — and NOT the course's own
  folder names, because `saysNoMachinery.rule` excludes them: a computer
  studies course with a folder called "Scripts" is the teacher's word, not a
  wording bug. The four `namedFrom: "fixed"` names — Media, index.md,
  Key Links.md, Curriculum Coverage — ARE swept, because those are the
  product's words and the reason for excluding names does not reach them; the
  first draft dropped them by accident and a review caught it. Windows'
  equivalent still folds every `entry.Name` into its sweep;
  latent only, since its fixture has no such folder, and it is item 32 in
  `WINDOWS-HANDOFF.md`. It runs against a course with NO curriculum folder,
  so the branch that carried the retired sentence — the one that had never
  run in a test on either platform — is the branch being read.

  **Corrected 2026-09-06, the same day, by the session that came to verify
  this entry: running that branch is not the same as GUARDING it, and the
  sentence above reads as though it were.** The jargon sweep reads the
  placeholder branch and cannot see the retired sentence in it, because
  "mentions" is not a banned word. Measured by putting the sentence back:
  all five folders-help tests stayed green. The gate is now the row check,
  which runs every contract case rather than one hand-typed fixture, so the
  placeholder branch's explanation is pinned to the contract character for
  character — the same reversion now fails 2 assertions. See
  `GUI-IMPROVEMENTS.md` row 446; Windows owes the same change, which is item
  40 — ✅ done 2026-09-08; see the ledger. Nothing in the retirement itself was wrong: the sentence was gone, and
  it stays gone.

- ✅ DONE (mac, 2026-09-06, branch `issue/folder-rename-space-links`, commit
  `cd333f6f`). **A folder rename to a name with a space broke every Markdown
  link into it — and the fix for it is NOT the one Windows shipped.**

  Windows found and fixed this on 2026-09-06 and proposed five contract cases.
  The mac had the identical defect, read rather than assumed:
  `FolderPathRewriter.encoded(_:likeThe:)` decided whether to percent-encode
  the new name from whether the OLD segment was encoded, so renaming `Tasks`
  to `All Tasks` turned `[q](Tasks/Quiz%201.md)` into
  `[q](All Tasks/Quiz%201.md)`. The rule is now the one Windows wrote down:
  **in a Markdown link, escape when the NEW name needs it, whatever the old
  segment looked like; in a wikilink, keep the plain spelling.** A segment
  that ARRIVED encoded still goes back encoded, in either style — that half
  was kept rather than replaced, and Windows kept it too.

  **The part Windows now owes back: the escaping SET.** `Uri.EscapeDataString`
  is the wrong tool, and so was the mac's old `urlPathAllowed`. Quartz v4.5.0
  resolves an internal link by calling JavaScript's `decodeURI`
  (`quartz/util/path.ts` → `transformInternalLink`), and `decodeURI`
  DELIBERATELY leaves the reserved set `; / ? : @ & = + $ , #` still encoded.
  It then slugs what comes back, turning `&` into `-and-` and `%` into
  `-percent` (`sluggify`, same file). So a folder called “Tasks & Quizzes”
  written as `Tasks%20%26%20Quizzes` decodes to `Tasks %26 Quizzes` and slugs
  to `Tasks--percent26-Quizzes`, while the real folder slugs to
  `Tasks--and--Quizzes`: a 404 on the published site — and INVISIBLE in
  Obsidian, which decodes `%26` perfectly well, so the teacher's vault looks
  healthy and only students see the break. “Tests & Quizzes” and “Q&A” are
  ordinary folder names, so this is not a corner case.

  Measured against the running image on 2026-09-06, not inferred:
  `decodeURI("Tasks%20%26%20Quizzes/Quiz.md")` → `Tasks %26 Quizzes/Quiz.md`;
  `decodeURI("Tasks%20&%20Quizzes/Quiz.md")` → `Tasks & Quizzes/Quiz.md`;
  `decodeURI("Work%28new%29/Quiz.md")` → `Work(new)/Quiz.md`;
  `decodeURI("Caf%C3%A9%20Notes/Quiz.md")` → `Café Notes/Quiz.md`;
  `decodeURI("C%2B%2B/Quiz.md")` unchanged.

  So the set left unescaped is what JavaScript's `encodeURI` leaves alone,
  minus `(`, `)` and `#` — which a Markdown destination or a slug cannot
  hold — and minus `/` and `:`, which the rename sheet refuses anyway. It is
  written down in the contract as `escapingSet.leaveUnescaped` rather than
  described, so both sides can check a character against it. Nothing is
  encoded unless the name needs it — `Café` goes in as `Café`, `Café Notes` as
  `Caf%C3%A9%20Notes` — and there is a case pinning that, because reading the
  set as “always encode” is the way the two apps would drift.

  **Three of the eleven cases fail on Windows today** — the ampersand, the
  comma and the question mark — and ONE change fixes all three, because
  `EscapeDataString` over-encodes `&`, `,`, `+`, `'`, `!` and `*` alike. The
  comma is the one to notice: “Unit 1, Day 2” is this project's own naming
  pattern, and Windows writes `Unit%201%2C%20Day%202`, which slugs to
  `Unit-1-percent2C-Day-2` and 404s. Read them as a request, not as damage;
  `WINDOWS-HANDOFF.md` carries what to change — and note that Windows owes a
  SECOND thing besides the encoder: `Plantoir.Tests/FolderPathRewriterTests.cs`
  retypes five cases of its own instead of deserialising these, so nothing over
  there would go red on its own.

  **Two things this entry said first and got wrong, kept because the reason
  travels.** A lone `%` was added to what forces escaping at all, on the
  strength of `decodeURI("10%/Quiz.md")` throwing. An adversarial review
  measured the actual pipeline and it never happens: Quartz parses with
  `remarkRehype`, and the Markdown parser normalises a bare `%` to `%25` on
  the way to HTML long before the link transformer runs — `[b](Top10%/Quiz.md)`
  arrives as `Top10%25/Quiz.md`. `%` came back out of the trigger, which also
  took the “per-cent sign” case off the Windows list, where it never belonged:
  `Top 10%` triggers on its SPACE, and `EscapeDataString` encodes the `%` too,
  so Windows passed it all along. And this entry claimed a folder named with
  `?` was broken in Quartz whichever spelling was used. It is not: `sluggify`
  strips the `?`, so an unescaped `Why?/Quiz.md` resolves and the escaped
  `Why%3F` does not. `?` was first left OUT of the allowed set on the
  reasoning that a bare `?` is a query delimiter to any other reader — which
  was never a rule this code applied (`?` is not a trigger, so `Why?` always
  went in unescaped) and was measurably wrong when escaping DID run: the real
  folder `Why Not?` slugs to `Why-Not`, and the escaped `Why%20Not%3F` slugs
  to `Why-Not-percent3F`. `?` is in the allowed set now, so the two spellings
  agree. Caught by a third review, which is also where the “both apps escape
  `?` anyway” sentence — describing behaviour neither app had — was found.

  **What was REJECTED.** Matching `Uri.EscapeDataString` exactly, which was
  the first plan here, chosen precisely so the two platforms could not drift.
  An adversarial review checked it against the real Quartz instead of
  reasoning about it and found it would have REGRESSED the mac: the current
  `urlPathAllowed` set gets `Tasks & Quizzes` right today by accident, and
  copying .NET would have broken it. Also rejected: escaping wikilinks the
  same way (the mirror-image mistake), and widening the rename sheet's
  refusals to cover `#` and `?` — refusing names is a product decision nobody
  has made, and for `#` neither spelling resolves anyway.

  Reference: `mac-app/QuartzTeachers/Models/FolderPathRewriter.swift`
  (`spelled(_:likeThe:in:)`, `charactersThatSurviveQuartzUndecoded`,
  `LinkStyle`), `mac-app/Tests/QuartzTeachersTests/FolderPathRewriterTests.swift`
  (23 tests, two of which deserialise the contract).

- ✅ DONE (Windows, 2026-09-06). **Four stale branches triaged and deleted —
  one merged, three superseded. Their tips are recorded here so the call can
  be undone.**

  Asked to work out whether four long-sitting branches were already in `dev`
  and to merge the ones that were not. Every verdict was reached by diffing
  each branch's own changes (`git diff dev...<branch>`) hunk by hunk against
  `dev`'s CURRENT file, and each was then checked by an independent reviewer
  on a different model before anything was merged or deleted — which was
  worth it: the review corrected two of the triage's stated reasons, both
  wrong, without changing any verdict.

  | Branch | Tip | Verdict |
  |---|---|---|
  | `ai-assist` | `92f54a92` | Already wholly in `dev` (0 commits ahead). |
  | `issue/windows-assist-model-in-use-guard` | `f80f2129` | **Merged** (`b2f159ea`). |
  | `new-screenshots` | `c0cd82fe` | Superseded; 5 commits never in `dev`. |
  | `perf/wsl2-ext4-build-acceleration` | `0f50ea65` | Superseded; 4 commits never in `dev`. |

  **The two superseded branches' commits are NOT in `dev`**, so deleting the
  branches made those commits unreachable. That is why the tips are written
  down: `git fetch origin <sha>` still reaches them until the remote garbage-
  collects, and the SHAs are the only way back afterwards. Recording them
  cost one line each; reconstructing a judgement about work nobody can find
  costs an afternoon.

  - `perf/wsl2-ext4-build-acceleration` was the PROTOTYPE of the
    container-internal ext4 staging that landed as `ed868215` and has
    evolved well past it since — `_clear_stale_host_site`, an fsync on the
    host directory, `stop_preview.py` taking two `--dir` arguments instead
    of the branch's string-replace on the target path, and
    `rebuild_for_production()` in place of the inline `npx quartz build`
    that this file's own entry at "deploy.py failed when rebuilding for
    production" records as having crashed. Merging it would have gone
    backwards.
  - `new-screenshots` has every one of its code changes in `dev` already,
    plus a `-PassThru` exit-code fix in `capture_windows.py` the branch
    never got. Its `site/img` binaries are two days OLDER than `dev`'s, so
    merging would have reverted the screenshots rather than updating them.

  **Two reasons given for the `perf` verdict were wrong, and are corrected
  here rather than left to be repeated.** It was claimed that merging would
  regress `_ensure_media_symlink` (branch absolute, `dev` relative) and the
  npm-install freshness check. Neither is true: `dev` passes the same
  resolved absolute path through `toolchain_paths.link_directory`, and `dev`
  dropped the package-lock mtime comparison too. The verdict held on the
  evidence that survived, which is the point of having the check.

- ✅ DONE (Windows, 2026-09-06). **The app can finally name where Windows keeps
  a built website — which turned out to be why two different things were
  wrong.**

  **What was actually broken.** `BuildFreshness`, the one thing that decides
  whether Deploy builds before publishing, read
  `<course>/.merged_output/section<N>/public/index.html` — where builds lived
  before row 290 moved them out of the working folder. Both of its answers
  were wrong, and both were reproduced rather than reasoned about: on a course
  made since the move that file never exists, so it always said "rebuild"
  (safe, but every publish rebuilt); on a course carrying a leftover
  `.merged_output`, it read the leftover, and one newer than the notes made it
  answer "no rebuild needed" about a file that is not what Windows publishes.

  The reason it went unnoticed is the useful part: **nothing in the C# knew
  the build path at all.** Only the launchers and the Python did. That is also
  why item 19's owed work had never been done — there was nothing in the app
  that could name the folder to clear it.

  **What was rejected.** Writing a second hash of the working folder's path.
  The plan called for it and the plan was wrong: `FolderContainers` has
  derived exactly that value for the container name since it was written, and
  CLAUDE.md warns about this derivation by name. `FolderIdentifier` was
  extracted from it instead — which is what the mac did too.

  **Nothing for the mac to check here** — and an earlier version of this entry
  wrongly asked it to. Windows clears a course's build at FIVE moments
  (archive a course, archive a section, restore a section, restore a course,
  restore a backup) because it has no symlink. The mac already clears
  explicitly at four of them (`CourseArchiver.archive` for a course and for a
  section, `CourseRestorer` for a section from an archive and from a backup),
  and the two whole-course cases are covered by a rule that NAMES them:
  `BuildOutputLocation.ensureLink`'s own comment says "archiving a course,
  restoring one from a backup and replacing a course's contents all remove the
  link… so a build folder found with no link pointing at it is cleared rather
  than adopted". That is a decision with its reasoning written down, not luck,
  and asking a mac session to "confirm" it would send them to re-derive
  something already settled.

  **A scheduled deploy had no build step**, which is a Windows-only gap the
  mac closed long ago in its launchd script. Fixed by building
  unconditionally; the reasoning and the hang it nearly introduced are in
  GUI-IMPROVEMENTS row 418.

  **Verified by publishing.** `verify-deploy.ps1` (new — Windows had no deploy
  gate of any kind) ran every destination and every pairing against real
  sites: **36 passed, 0 failed, 0 skipped**, each site fetched back and read.
  Four harness faults had to be fixed to get a green worth trusting, and one
  of them is the reason this entry exists at all: the three Cloudflare legs
  were publishing to NETLIFY and passing, because `deploy.ps1` never reads
  `deploy_target` from the configuration and needs `--target cloudflare`,
  and the harness then verified a `netlify.app` address as proof of a
  Cloudflare publish. **A false pass is worse than a skip**: a skip says
  nothing ran; a false pass says something ran correctly.

  **Reference:** `Plantoir.Core/Models/BuildOutputLocation.cs` (new),
  `FolderContainers.FolderIdentifier`, `BuildFreshness.NeedsRebuild(course,
  section, buildsRoot)`, `CourseArchiver.DiscardBuilds`, `CourseRestorer`,
  `Assist/TaskScheduling.WriteWrapperScript`, `verify-deploy.ps1`. Tests:
  `BuildOutputLocationTests` (14, including the contract's five
  `buildFreshness` rules, never run on Windows before), `BuildFreshnessTests`
  repointed, `TaskSchedulingTests`.

- ✅ DONE (Windows, 2026-09-06). **Items 15 and 16 ported: a course's own
  words for a unit and for its class folder. Nothing is asked of the mac — this
  entry exists for the two things the port learned that the write-up did not
  say.**

  The feature itself arrived as designed: `unit_word` and `class_folder`,
  absent meaning what every existing course already does, with the rule in
  shared Python and the cases in `class-planning.json`. `ClassPageTerm.cs`
  mirrors `scripts/class_pages.py`; `ClassFolderRule` gained the recorded-key
  overload; the wizard asks the question and writes both keys. Four of the
  five contract tests that were red on this side now pass.

  **What the handoff did not warn about, and cost the most time: the port is
  not finished when the RULE is ported.** Item 15 names the assistant's
  sentences and the wizard field, so those were expected. What was not listed
  is that two call sites BUILD PAGE TITLES rather than sentences —
  `"Unit {unit}, Day {atDay + i}"` when adding classes, and the same shape
  when making room for them. In a Module course those write files the course's
  own rule then refuses to recognise as class pages, which is the feature's
  own silent failure arriving by a second route, from the app rather than from
  the parser.

  **Corrected the same day, and the correction is the useful part.** An
  earlier version of this entry said "every call site now passes the course's
  values" and asked the mac to check `AssistWorkspace`'s equivalents. Both
  halves were wrong. A review found FOUR more literals on this side, two of
  which made the feature worse than not having it — new pages were still NAMED
  "Unit 1, Day 3", and make-room's READER matched a literal pattern so it
  refused a Module course outright before the corrected title-building could
  run. And the mac has no `AssistWorkspace`: its equivalents
  (`NextClassPlanner`, `PlaceholderClassPlanner`, `ClassInsertionPlanner`)
  already pass `term`, so there is nothing there to check. **Nothing is asked
  of the mac by this paragraph** — it is here because a handoff entry that
  overstates what was done is worse than none, and because the reason for the
  miss travels: the owed-items list was produced by thinking of features
  rather than by grepping for every CALL of the thing being made
  configurable.

  **The second: `SectionIndex`'s date tie-break.** When two pages share a
  date, the later page in the course wins, decided by parsing both names. In a
  Module course neither name parses under the default word, so the tie-break
  silently degrades to whichever file the walk reached first. Not mentioned
  anywhere, found by grepping for every `UnitDay.Parse` rather than by
  following the write-up.

  **The general lesson, which is the part that travels:** for a feature whose
  failure mode is "answers no instead of refusing", the owed-items list should
  be produced by grepping for every CALL of the thing being made
  configurable, not by listing the features a reader can think of. The mac's
  own list was written the second way, and both misses above are the same
  shape.

  **Reference:** `Plantoir.Core/Models/ClassPageTerm.cs` (new),
  `UnitDay.cs`, `ClassFolderRule.cs`, `CourseConfiguration.cs`,
  `Assist/AssistWorkspace.cs`, `Assist/SectionIndex.cs`,
  `Models/NextClassPlanner.cs`, `Views/NewCourseDialog.cs`. Tests:
  `ClassPageTermTests.cs` (new), `ClassFolderContractTests.cs` and
  `ClassPlanningContractTests.cs` (both now read the contract's optional
  `classFolder` and `term` fields with a default).

- ✅ DONE (Windows + shared, 2026-09-05). **A publish on Windows was
  overwritten by its own preview, silently — and, separately, publishing to a
  folder could not succeed there at all. Both found by publishing for real.**

  **The first bug, which is the one item 20 sent me after.**
  `build_site.py --build-only` has always asked for the section's preview
  server to be stopped before it builds for publishing. On native Windows the
  ask did nothing: `stop_preview.read_proc_snapshot()` reads `/proc`, Windows
  has none, the list came back empty and `stop_preview_serving()` returned 0.
  Meanwhile `_start_public_sync_watcher` — started in the SERVE branch and
  therefore running natively on that platform too — went on mirroring the
  serve build into the same directory about once a second. So a publish that
  ran while that section was previewing was overwritten within a second of
  finishing, and what went out was the PREVIEW, live-reload client and all.
  Nothing errored and nothing was logged.

  **What was chosen, and what was rejected.** Item 20 offered three shapes
  and asked for the reasoning, so here it is. The fix went into
  `stop_preview.py` as a native process-snapshot reader, because every
  exposed route already funnels through the ONE call that reader feeds:
  `preview.ps1 --build-only`, `deploy.ps1`'s folder branch (which shells
  `preview.bat ... --build-only`), `deploy.py`'s `rebuild_for_production` —
  the route a Netlify or Cloudflare publish takes — scheduled deploys, and
  `plantoir-mcp.exe`'s `deploy_section`. One edit covers all five and every
  caller nobody has written yet.

  - **Rejected: `stop_preview.py --match-stdin`,** with PowerShell driving.
    It inverts the control flow, so it reaches only PowerShell callers, and
    `deploy.py` → `build_site.py` is not one of them. Choosing it alone would
    have left the Netlify and Cloudflare route racing — the one a teacher is
    most likely to be using.
  - **Rejected: having `deploy.ps1` stop the preview itself.** The smallest
    change, and the one that leaves every future caller free to reintroduce
    the bug. `plantoir-mcp.exe` was already exactly such a caller.
  - **Rejected: calling `preview.ps1`'s matcher from its own `--build-only`
    path,** which is what item 20's first bullet literally asked for. Same
    reason as the first rejection: the launcher cannot see the `deploy.py`
    route.

  **The `--match-stdin` question item 20 asked me to settle.** Not adopted,
  and the reason has changed from the one item 20 anticipated. It worried
  that Windows could not rely on Python being resolvable when `--stop` runs.
  That worry is answered: stop mode already refuses to run without
  `$NATIVE_RUNTIME`, whose `manifest.json` sits beside the bundled
  `python\python.exe`, so the interpreter is exactly as available as the
  runtime the mode already requires. The reason it is still not adopted is
  different: `--stop` is what runs when a teacher closes a window or cancels
  a publish, both callers discard its output, and neither checks its exit
  code — so a Python that fails to start there would leak processes in total
  silence. PowerShell enumerating, deciding and killing in one process has no
  such step. **What removes the drift risk is not single-sourcing but the
  cases**: `windows-app/test_stop_preview.ps1` now runs the contract's own 23
  against the launcher's matcher, so the two implementations are held to one
  rule by the thing that can actually check.

  **Three details that would each have made the fix silently do nothing,
  measured on Windows 11 Pro 26200, Intel i5-8365U, 275 processes.**
  - PowerShell's default pipe encoding is the OEM code page. A teacher whose
    user folder is named José gets byte 0x82 where the accent belongs —
    either a decode error, or, with `errors="replace"`, a path that never
    matches, so nothing is ever stopped for that teacher and nothing says so.
    `[Console]::OutputEncoding` is set explicitly.
  - `signal.SIGKILL` does not exist on Windows. Both kill sites would have
    raised `AttributeError` the moment the snapshot stopped coming back
    empty — which is precisely what this change does to it.
  - `os.kill` on a pid that has already gone raises a plain `OSError`
    (`[WinError 87]`) there, never `ProcessLookupError`. Catching only the
    POSIX pair would have taken a publish down with a traceback the first
    time a preview exited between the snapshot and the kill.

  Cost of the new reader: **485/500/518 ms** for a full `Win32_Process` →
  JSON round trip called from Python, three runs, against a build that takes
  tens of seconds. An in-process `Get-CimInstance` is 521 ms, so essentially
  all of that is the query rather than the shell.

  **The second bug, which the first one uncovered: publishing to a folder
  could not succeed on Windows, ever.** Found by running the publish rather
  than reasoning about it. Every folder publish announced "This site was
  built by a preview", rebuilt whether it needed to or not, waited the full
  30 s for a condition that could never come true, and refused with "The
  rebuilt site still carries the preview's live-reload script. Nothing was
  published" — against a site whose 314 pages carried no live-reload client
  at all.

  The cause is a Windows PowerShell 5.1 semantic, and it is worth the mac
  knowing about because the mac wrote this code (GUI-IMPROVEMENTS row 392,
  mirroring `deploy.sh`) and could not run it:

      if ($files | Select-String -Pattern "ws://localhost:" -List -Quiet)

  `-Quiet` fed a PIPELINE of file objects emits one result PER FILE, not one
  answer for the tree. 314 clean pages come back as a 314-element array of
  `$null`, and **in PowerShell a non-empty array is TRUE whatever is in it**.
  So the test was true whenever the site had two or more pages, which is every
  real site — exactly one page is the single case it got right, by accident,
  because a one-element array unwraps to the falsy scalar it holds. All three uses
  were affected: the one deciding whether to rebuild, the one the 30 s wait
  loop spins on, and the one that refuses to publish. `deploy.sh` is fine —
  `grep -rq` returns one exit status for the whole tree, which is the answer
  the check wants. **The general lesson for any PowerShell the mac writes
  blind: `-Quiet` is not a scalar when the input is a pipeline.** It is now
  one named function, `Test-CarriesLiveReload`, testing for a MatchInfo
  rather than a Boolean, so the count cannot change the meaning.

  **Proof, end to end, on the real launchers rather than in a unit test.** A
  copy of a real working folder (ICS3U, 289 pages), never Russell's own:
  started a preview, confirmed it served and carried the live-reload client,
  killed only the LAUNCHER, and confirmed the preview was still serving —
  the bug's precondition, reproduced. Then published: the log showed
  `🛑 Stopped the preview that was still serving this section (PID …)` twice,
  which had been impossible on that platform. With the folder-publish fix in
  place the publish then exited 0 in **2 s** where it had taken 150 s to
  fail, writing 328 files, 314 HTML pages, **0** carrying the live-reload
  client, front page present.

  **A test-isolation defect found on the way, which the mac should check for
  its own suite.** `ScheduledDeployCompletionTests.Dispose` set the trail
  override to null — which does not mean "no override", it means "use the
  teacher's real activity.txt" — so every test class that ran after it wrote
  there. On this machine that left **263 lines about fixture courses in the
  real activity trail**, the same file a problem report gathers, where a
  course that never existed reads as a fault that never happened. The field
  holding the original path was already there and simply never used. The
  written lines were left alone; they are Russell's log.

  **Reference:** `scripts/stop_preview.py` (`read_windows_snapshot`,
  `read_snapshot`, `stop_one`), `scripts/build_site.py`
  (`stop_preview_serving`), `deploy.ps1` (`Test-CarriesLiveReload`),
  `preview.ps1` (`Get-SectionProcessesToStop`, `Test-IsServing`),
  `windows-app/Plantoir.Core/Scripting/ReclaimedProcesses.cs`,
  `windows-app/Plantoir/Services/PreviewStopper.cs`. Tests:
  `scripts/test_stop_preview.py` (35, 2 skipped),
  `windows-app/test_stop_preview.ps1` (25 checks, 1 allowed skip, now run as
  a gate by `TheLauncherMatcherAnswersTheContract`),
  `windows-app/Plantoir.Tests/ReclaimedProcessesTests.cs`.

- ✅ DONE (Windows, 2026-08-22). **Toggling on "Also publish to Cloudflare" as
  a redundancy target, with Netlify (or a local folder) as the primary
  destination, permanently disabled Save with no way to fix it — fixed by
  giving the additional-Cloudflare row its own real Account ID field instead
  of a note pointing at a field that was hidden.**

  **The report.** Russell, setting a course up to deploy to multiple targets:
  "I just clicked 'Also deploy to Cloudflare' but could not save that change."

  **Root cause.** `PublishingChoiceView.Problem` (`windows-app/Plantoir/Views/
  PublishingChoiceView.cs`), which gates `SaveButton.IsEnabled`, correctly
  requires a valid Cloudflare Account ID before Save can enable — for an
  ADDITIONAL Cloudflare target exactly as much as for a primary one. But the
  only Account ID field that existed anywhere in the view was inside the
  primary Cloudflare block, and that block's `Visibility` is `Collapsed`
  whenever the primary destination isn't Cloudflare itself. The additional-
  target row, for Cloudflare, rendered nothing but a caption: "Uses the same
  Cloudflare Account ID as above — enter it there if you haven't already." With
  Netlify as primary, "above" was invisible, so there was no field on screen a
  teacher could use to satisfy the requirement Save was blocking on — a
  permanently-disabled Save button with no visible cause.

  **Fix.** The additional-Cloudflare row now renders its own real Account ID
  `TextBox` and caution line (`additionalCloudflareAccountField` /
  `additionalCloudflareAccountProblem`), reading and writing the same shared
  per-course value the primary field does. A new `SyncAccountBoxes` helper
  keeps both text boxes showing the same text regardless of which one the
  teacher typed into, so switching the primary destination later doesn't show
  a stale value from construction time.

  **Mac never had this bug and needs no change** —
  `mac-app/QuartzTeachers/Views/CourseSettings/PublishingChoiceView.swift`'s
  `additionalTargetRow(forType:)` already renders a full `CloudflareDetailFields`
  block (account field, help button, caution line) inline in the additional-
  target row whenever Cloudflare is the additional type — it never relied on
  the primary block being on screen. This entry exists for awareness only;
  Windows now matches the mac's existing design rather than the mac needing to
  match Windows.

  **Reference implementation.** `windows-app/Plantoir/Views/
  PublishingChoiceView.cs` (`RebuildAdditionalArea`'s `cloudflare_pages`
  branch, `SyncAccountBoxes`, `RefreshAdditionalCloudflareProblem`).
  `GUI-IMPROVEMENTS.md` row 322. Full Windows suite green apart from one
  pre-existing, unrelated failure (`SharedRules_ActivityTrailEvents_Exist`,
  confirmed failing identically before this change by stashing it and
  re-running).

- ✅ DONE (Windows, 2026-08-22). **A "Publish" that followed a running
  preview could spew the whole build log into the assistant's chat reply —
  fixed by making `AssistWorkspace.Apply` actually honor the `preview: false`
  the chat window was already sending and being ignored.**

  **The report.** Russell described a cycle of "preview", "Unpublish Unit 4,
  Day 20", "Publish Unit 4, Day 20" — and on that final Publish, the assistant's
  reply carried every line of a fresh build, instead of a short "Working…" /
  "Published".

  **Root cause: the `preview` flag was set on the way in and read nowhere on
  the way through.** `AssistAgent.RunTool` (`Plantoir.Core/Assist/AssistAgent.
  cs`, `EditsPages`/`TakesPreviewFlag`) already forces
  `arguments["preview"] = false` for `publish_pages`/`unpublish_pages`/
  `publish_class_on`, with a doc comment stating the intent plainly: "They run
  on the server as pure file edits — `preview: false`, so the server builds
  nothing — and then the app's own preview is put on screen." That promise was
  not kept. `PlantoirTools.Act` (`Plantoir.Mcp/PlantoirTools.cs`) received
  `preview` and used it for exactly one thing — skipping an early "nothing to
  do" return — then called `workspace.Apply(plan, progress, cancellation)`,
  a method with **no `preview` parameter at all**. So every publish/unpublish
  of a single page (the common case — a single day, like "Unit 4, Day 20")
  triggered a second, hidden `preview.ps1 --build-only` inside `Apply`,
  unconditionally, on the server — racing the app's own visible rebuild
  (`ShowPreviewInApp.Invoke()`, fired moments later back in `RunTool`) for the
  same `.merged_output/section<N>/` folder, with no build-lease protection
  guarding that inner call the way `RebuildPreview` and `RefuseIfPlantoirIs
  Building` already guard every OTHER build path. On failure, the hidden
  build's raw output (`LauncherRunner.Explain` — up to 12 tail lines of the
  launcher's own stdout/stderr, spliced onto the failure message) became the
  tool's `Detail`, fed straight into `_messages` for the local model, which —
  per the pattern already noted elsewhere in this file (a small model restates
  what it is given) — parroted the raw block back into the chat instead of a
  clean sentence. `ApplyWholeUnit`, the sibling code path for a whole-unit
  publish, already did this correctly (skips the build entirely when
  `preview: false`); `Apply`, the single-page path, simply never got the same
  treatment.

  **Why "Publish" leaked but the preceding "Unpublish" in the same cycle did
  not.** `PublishPlan.Publishes` is `!draft`; `Apply`'s build branch only runs
  `if (plan.Publishes)`. `unpublish_pages` (`draft: true`) returns before ever
  reaching the launcher, so only a publish can hit the unfenced hidden build —
  matching the reported asymmetry exactly.

  **What was built.** `Apply(PublishPlan plan, bool preview = true, …)` now
  takes and honors the same flag `ApplyWholeUnit` already did: when `preview`
  is false, it returns the plain summary and builds nothing, leaving the one
  visible rebuild to the app, exactly as the `EditsPages` doc comment always
  claimed. When `preview` is true (a caller with no window on screen, or the
  `publish_class_on` sequencing path), the build now goes through
  `RefuseIfPlantoirIsBuilding` + `ClaimTheBuild` immediately beforehand — the
  same lease discipline `RebuildPreview` already had — so it cannot race a
  concurrent build either. And on failure, both `Apply` and `ApplyWholeUnit`
  now say a short, contract-backed sentence
  (`AssistWording.WhereTheOutputIs` — "The output is in that section's window
  in Plantoir.") instead of splicing the launcher's raw transcript into the
  model's context. `PlantoirTools.Act`'s two call sites (`publish_pages`/
  `unpublish_pages` and `publish_class_on`) now pass the `preview` argument
  they already had through to `Apply`.

  **Why not just filter/summarize the raw output client-side instead.** That
  would have treated the symptom (raw text reaching the model) without fixing
  the cause (a hidden build the app's own doc comment said would never
  happen), and would have left the race between the hidden and visible builds
  in place — a race that can corrupt a half-written preview even when nothing
  fails outright. Honoring the flag that was already being sent removes both
  the leak and the race in one change, and needed no new plumbing: `preview`
  was already threaded as far as `Act`, just dropped at the last hop.

  **Nothing for the mac to port.** The mac's equivalent code was checked and
  does not have this bug, structurally rather than by luck:
  `AssistToolRunner.bringThePreviewUpToDate`
  (`mac-app/QuartzTeachers/Models/Assist/AssistToolRunner.swift`) is the ONE
  place a rebuild is ever triggered after a page edit, and it chooses
  visible-vs-headless dynamically, at the moment it runs, by asking whether a
  section window exists — never via a boolean threaded across the MCP-tool
  boundary and then silently ignored. The publishing write itself (`carryOut`)
  never calls a builder at all; it always defers to that one dispatcher. And
  its headless fallback (`AssistSiteWork.rebuildPreview`) already returns only
  the canned `AssistWording.previewDidNotBuild` sentence on failure, never raw
  output. Recorded here for awareness only, per rule 4 in `CLAUDE.md`: no
  contract case is proposed, because the fix is Windows-only plumbing with no
  teacher-visible wording change to assert cross-platform (the wording used,
  `WhereTheOutputIs`/`previewDidNotBuild`, already existed in both apps'
  `AssistWording` before this fix).

  **Reference:** `Plantoir.Core/Assist/AssistWorkspace.cs` (`Apply`,
  `ApplyWholeUnit`), `Plantoir.Mcp/PlantoirTools.cs` (`Act`). Tests:
  `Plantoir.Tests/AssistTests.cs` —
  `PublishingWithPreviewFalseBuildsNothing`,
  `APublishThatFailsToBuildSaysOneCleanSentenceNotTheRawLog`.

- ✅ DONE (mac, salvaging stranded Windows work, 2026-08-22). **A branch that
  never got merged, `issue/mac-site-shots-unmerged`: mostly superseded, three
  real fixes rescued into a fresh branch.**

  Asked to "sort out screenshots" against that branch. It had 11 commits
  ahead of `dev`, but its merge-base with `dev` was 229 commits stale
  (last touched 2026-08-19, one day before `dev` independently re-solved the
  same problems). Diffed every changed file against both the merge-base and
  current `dev` before touching anything, rather than trusting the commit
  messages:

  - **Superseded, confirmed file-by-file, nothing worth keeping**: the mac
    Safari-capture appearance/address-bar check (branch's
    `require_matching_appearance` in `capture.py` vs. `dev`'s
    `verify_appearance`/`verify_address_bar` in `safari.py`, landed
    2026-08-20 — same problem, `dev`'s version is the one that shipped);
    `mask_window_corners` (branch still called it; `dev` dropped it entirely
    in favour of `screencapture -l`'s own transparent corners); the Windows
    one-appearance-per-process capture in `capture_windows.py`/
    `hero_windows.py` (`dev`'s version is character-for-character the same
    idea, plus a later `-PassThru` exit-code fix the branch never got); the
    `data-win-srcset` hero-image swap in `site/index.html` (`dev` already
    has it); every `site/img/*.png`/`.webp` binary (`dev` has re-shot these
    several times since). Merging the branch as-is would have produced 15
    conflict markers and reintroduced the corner-masking approach `dev` had
    already replaced.
  - **Not superseded — three real C#/WinUI fixes, ported by hand into
    `issue/windows-capture-dialog-fixes`** (branched from current `dev`,
    not from the stale branch, so there was nothing else to drag along):
    `NewCourseDialog.StageForCapture` now calls the same `Refresh*` methods
    a teacher's own typing would trigger, since a `TextBox` that has not
    been templated yet takes a programmatic `Text` without raising
    `TextChanged` — the staged capture dialog previously showed an empty
    course-name suggestion and no club row; the staged dialog card's
    `MaxHeight` went 680 → 720 (was slicing the Language/region row through
    its own control, with no scrollbar to explain why — Windows hides
    scrollbars by default, so a still frame never shows one) plus a
    `GiveTheFormRoomForCapture` pass capping the form's inner `ScrollViewer`
    at 600 so the cut lands at a section boundary; the dialog's title now
    reads `dialog.Title` ("New Course or Club") instead of a hardcoded
    "New Course"; `AssistWindow` gained `ShowPromptShelfForCapture()`, since
    the prompt shelf normally mounts once the local assistant finishes
    starting, which a staged capture never triggers — the assistant-window
    shot was missing its top third. Full row: `GUI-IMPROVEMENTS.md` #316;
    the Windows side of what still needs doing is in `WINDOWS-HANDOFF.md`'s
    "Salvaged capture fixes" section.

  **Not built or tested — there is no .NET SDK on this Mac.** The port was
  done by reading both the branch's diff and `dev`'s current file at each
  call site and hand-verifying every method it calls
  (`AutoFillCourseName`, `RefreshClubRow`, etc., and
  `AssistPromptShelfView`'s constructor signature) still exists with the
  same shape, rather than applying the patch blind — but a `dotnet build` +
  `dotnet test` and an eyeballed real capture run are still owed before this
  merges. The stale branch itself (`issue/mac-site-shots-unmerged`) was left
  for Russell to delete rather than deleted here, since deleting a pushed
  branch is his call.

- ✅ DONE (Windows, 2026-08-22). **A teacher could delete the local
  assistant's model file from Settings while an assistant window was still
  using it — fixed by porting the mac's `AssistActivity`/`AssistModelLibrary.
  mayRemove` guard, which Windows had never actually had despite this file
  once claiming otherwise.**

  **The report, almost missed.** Russell described watching the assistant
  keep replying after he deleted its model file from Settings mid-chat, and
  first read that as the bug — "the assistant still replied, somehow" — before
  correcting himself to the real question: "you shouldn't be able to delete a
  model while the AI assistant window that is using it is open, should you?"
  The reply surviving was not evidence of safety; it was Windows' own file-
  sharing rules letting a delete succeed while `llama-server.exe` still held
  the file open, so the CURRENT reply rode out on an already-open handle. The
  next prompt, a server restart, or a second assistant window opened after
  the delete would find the weights gone, with nothing telling a teacher why.

  **Root cause: this exact guard was believed to already exist and did not.**
  The row-313 entry below (2026-08-17) lists "safe model removal (disabled
  when any assistant window is open)" as done. It was not — confirmed by
  direct code search before writing a line of the fix: no `AssistActivity`
  type, no `mayRemove`, nothing tracking which windows were open, anywhere in
  `windows-app`. `AssistModelStore.Remove()`'s own doc comment said as much in
  plain words: "Deliberately does no 'is it safe' check — whether it is safe
  to remove is a question about which windows are open, which this type
  cannot see." `WINDOWS-HANDOFF.md` had already told a Windows session to
  port the mac's `AssistActivity` for exactly this reason; it had simply never
  been done. That row-313 line has been corrected in place below rather than
  quietly rewritten, so the record shows it was wrong for five days, not that
  it was always right.

  **What was built, matching the mac's shape with one deliberate
  difference.** New `Plantoir.Core/Assist/AssistActivity.cs` mirrors the
  mac's `AssistActivity.swift` — same reasoning in the doc comment, same
  `Begin`/`End`/naming-the-section-in-the-refusal shape — but tracks a
  `HashSet<Session>` rather than one active session, because Windows does not
  (yet) enforce one assistant window at a time the way the mac does. Rejected:
  adding that one-at-a-time enforcement as part of this fix too, to make the
  mac's single-`Session?` shape a straight port — out of scope for a bug
  report about model deletion, and a genuinely bigger, separate feature (its
  own window-focus/menu-item semantics, not just a data structure). Ported
  onto `AssistModelStore`: `ReasonItCannotBeRemoved()`/`MayRemove()`, gating
  `Remove()` itself (not just the UI) so a stale button can't bypass it.
  `AssistWindow.xaml.cs` claims a session at the top of its async `Begin()`
  (before the engine is ready — a teacher three minutes into a download still
  has the assistant "open" as far as this question goes) and releases it
  unconditionally in `Shutdown()`, matching the mac's `prepare()`/`finish()`
  placement exactly. `AssistantSettingsDialog.cs` disables Remove with a
  tooltip and appends the reason to the status line, and now also subscribes
  to a new `AssistActivity.Changed` event (alongside its existing
  `AssistModelStores` subscriptions, unsubscribed together in the same
  `DetachFromStores()`) so the button updates live if an assistant window
  opens or closes while Settings is already on screen — the mac gets this for
  free from `@Observable`; WinUI needs the explicit event.

  **Verified by an independent adversarial review** (fresh sub-agent, no
  memory of this session, told to distrust the description and check the code
  itself; also rebuilt the solution and re-ran the full suite from scratch).
  It found no bugs: locking in `AssistActivity` is correct (the event fires
  outside the lock), every early-return path through `AssistWindow.Begin()`
  still releases its claim because `End()` is tied to the window's `Closed`
  event rather than to `Begin()`'s own control flow, `HashSet.Add`/`Remove`
  are safely idempotent so double-`Begin`/double-`End` cannot corrupt state,
  the "nothing downloaded yet" case never shows a spurious "close the
  assistant" message (`IsReady` is checked first), and no other code path in
  the app deletes the model file or calls `Remove()` outside
  `AssistantSettingsDialog.cs`.

  **One theoretical gap noted for completeness, not introduced by this
  change and not blocking.** The set dedups by `(FolderPath, CourseCode,
  SectionNumber)`, so two `AssistWindow`s open for the exact same section
  would have the SECOND one's close remove the shared entry and clear the
  guard while the first is still live. In practice this is already narrowed
  by the pre-existing `CourseActivity`/`WorkLease` file-lock that blocks a
  second assistant window on the same section (`SidebarPane.xaml.cs`'s
  `ReviseWithAi`) — advisory, with its own stated click-time race window, so
  not airtight — but the mac's own single-`Session?` tracking has the
  identical theoretical shape if its own one-at-a-time enforcement were ever
  raced. Left as-is rather than fixed blind: reproducing a genuine same-
  section double-open race is not something either suite can drive on demand,
  and the existing WorkLease already carries the real-world risk down to
  "advisory click-time window," not "routinely happens."

  **Test coverage**: 7 new tests in `AssistModelStoreTests.cs` — sharing/
  disk-state coverage already existed; new tests cover `MayRemove`/
  `ReasonItCannotBeRemoved` with no assistant open, with one open (blocking
  removal and naming the section), release-on-`End`, a rung not currently in
  use still being blocked by ANY open assistant (matching the mac's "any
  open, not which rung" rule), and the not-downloaded case not producing a
  reason. `AssistActivity.Reset()` added to the test's setup/teardown
  alongside the existing `AssistModelStores.Reset()`, in the same
  `SharedLocalModelState` collection (`DisableParallelization = true`) —
  process-wide state, one test class touches it, already serialized. Full
  suite: 627 tests, 627 passed (up from 620).

  Reference: `Plantoir.Core/Assist/AssistActivity.cs` (new),
  `AssistModelStore.cs`, `Plantoir/Views/AssistWindow.xaml.cs`,
  `Plantoir/Views/AssistantSettingsDialog.cs`, `AssistModelStoreTests.cs`.
  Mac reference: `AssistActivity.swift`, `AssistModelLibrary.swift:200-245`.

- ✅ DONE (Windows, 2026-08-22). **The Settings window's Download button did
  nothing at all — fixed by porting the mac's shared-store architecture, not
  just wiring the click.**

  **The bug, reported directly**: "Nothing visibly happens when you press the
  Download button to download the large or small model in the Settings
  window for the local AI assistant. This works on macOS." The cause was
  exactly that plain: `AssistantSettingsDialog.cs`'s Download button handler
  was `button.Click += (_, _) => { /* Trigger download or inform */ };` — a
  comment where the call should have been. The download MECHANICS
  (`LocalModel.Install`, streaming with progress, exact-byte-size validation)
  already existed and already worked — they were only ever wired to the
  "open the assistant with no model yet" flow in `AssistWindow.xaml.cs`, never
  to Settings.

  **Fixed as a straight button-wiring patch would have shipped the mac's own
  already-paid-for double-download bug.** Before touching the click handler,
  read `mac-app/QuartzTeachers/Models/Assist/AssistModelStore.swift` and
  `AssistModelStores.swift` — the mac's own doc comment on
  `AssistModelStores` names the exact failure a naive Windows fix would have
  reintroduced: "there used to be one `AssistModelStore` per PLACE that
  cared: the settings panel made its own, and every assistant window made
  another. A teacher who pressed Download in Settings and then opened the
  assistant while it ran got a second store... deleting it... and starting
  again. Two transfers writing to one destination, each undoing the other,
  on a school connection, for gigabytes." Wiring Settings' button straight to
  a fresh `LocalModel.Install()` call would have reproduced this immediately,
  since `AssistWindow.xaml.cs` already ran its OWN independent download with
  no shared state at all.

  **What was built instead, matching the mac's architecture**: new
  `Plantoir.Core/Assist/AssistModelStore.cs` — `AssistModelStore` (per-tier
  state machine: Missing/Downloading/Ready/Failed, wrapping the pre-existing
  `LocalModel.Install`, idempotent `Download()`/`Cancel()`/`Remove()`, a
  `Changed` event in place of Swift's `@Observable`) and `AssistModelStores`
  (a static per-tier registry — direct port of the mac's enum-based
  singleton). `AssistantSettingsDialog.cs`'s housekeeping rows now read
  live store state instead of raw file checks, with a progress bar, a "Stop"
  button while downloading, and a failure line — matching
  `AssistantSettingsView.swift`'s `downloadRow(for:)` shape.
  `AssistWindow.xaml.cs`'s own download flow was rewired onto the SAME
  shared store, so a download started in either place is visible — and is
  the SAME download — in the other.

  **Verified live against the real app** (UI Automation, no mock): clicked
  Download in Settings, watched a genuine Hugging Face download run with
  live-updating progress ("525.3 MB of 1.04 GB (49%)" → "Downloaded · 1.04 GB
  on this PC"), clicked Remove, confirmed it correctly reverted to "Not
  downloaded" with the file actually gone from disk. Screenshots taken at
  each step. This is the class of bug a green unit suite would never have
  caught on its own — nothing here was previously tested at all, on either
  platform's Settings surface specifically.

  **An adversarial audit (fresh sub-agent, no memory of this session, asked
  to independently re-verify) caught a real regression before this shipped**:
  the new `AssistWindow.xaml.cs` cancelled the SHARED download unconditionally
  whenever its own window closed — including when Settings, not that window,
  had started it. This is not a new mistake; it is the IDENTICAL bug the mac
  found and fixed, on record as GUI-IMPROVEMENTS.md row 219 and
  `AssistSession.swift`'s own `startedTheDownload` flag and doc comment:
  "Closing a window that merely WATCHED must not cancel that." Fixed the same
  way: a local `startedByThisWindow` bool, true only when THIS window's own
  offer dialog was accepted, gating the cancel-on-close — an explicit Stop
  (Settings' own button) still cancels unconditionally either way, matching
  the mac's `stopDownload()` "an explicit stop is honoured wherever it came
  from."

  The same audit also found the `AssistModelRemoved` trail line was missing
  the "how much space it freed" clause `shared-rules.json`'s
  `activityTrail.mustRecord` requires and the mac's own line includes —
  fixed (`"removed {tier} — {size} freed"`, word-for-word shape match) — and
  a narrow leak where a Settings dialog that never actually got shown (WinUI
  allows only one `ContentDialog` on screen; a fast double-invoke throws)
  would stay subscribed to the app-lifetime store registry forever — fixed
  with an idempotent `DetachFromStores()`, called from both `Closed` and a
  `try/finally` at the call site.

  **Two low-severity findings assessed and deliberately left as-is, not
  silently dropped**: (1) two `AssistWindow`s opened within the same instant
  for an un-downloaded tier can both show the "Download the assistant?"
  offer dialog — `Download()`'s own guard makes this harmless in DATA terms
  (no double-download), the only cost is a redundant dialog a teacher could
  decline while a download genuinely runs elsewhere; a real fix needs new
  synchronization surface on `AssistModelStore` this session judged not
  worth adding blind, with no way to drive an actual two-window race live in
  this environment. (2) `AssistModelStore`'s mutable state has no lock —
  the mac's `@Observable` store is implicitly main-actor-isolated and race-
  free by construction, this one is not, but every touched field is
  atomically-sized on 64-bit .NET, so the worst case is one stale UI redraw,
  self-correcting on the next `Changed` event, never a crash or torn read.

  **Test coverage, and its honest boundary**: 12 new tests in
  `AssistModelStoreTests.cs` cover store identity/sharing (the exact
  double-download guarantee), disk-state reflection, and the synchronous
  Download/Remove/Cancel guards — none touch the real network, since
  `LocalModel`'s `HttpClient` has no injection seam, matching the mac's own
  boundary (no dedicated `AssistModelStore` test file exists there either).
  The `startedByThisWindow` fix itself is UI-embedded
  (`ContentDialog.ShowAsync`, `Root.XamlRoot`) and not unit-testable in
  isolation, same as the mac's equivalent `AssistSession`/`AssistWindowView`
  logic — verified by direct code reading against the mac's own pattern, not
  by an automated test, on both platforms.

  **A real, pre-existing test-infrastructure bug found and fixed along the
  way**: `LocalModelTests.cs` already set the static
  `LocalModel.ModelDirectoryOverride` with no xUnit collection guard: adding
  `AssistModelStoreTests.cs` (a second class touching the same static)
  produced a genuine, observed intermittent failure the moment both classes
  existed — xUnit parallelises test classes by default. Fixed by sharing a
  new `DisableParallelization = true` collection between the two classes,
  the identical pattern `ModelTests.cs`'s `SharedActivityState` already
  established for the preview-lease/publish-registry statics. Confirmed
  clean on 3 full-suite runs plus 5 targeted runs of the two classes
  together after the fix, versus a real failure observed before it.

  Full suite after every fix above: **620 tests, 620 passed**. Reference:
  `Plantoir.Core/Assist/AssistModelStore.cs` (new),
  `Plantoir/Views/AssistantSettingsDialog.cs`,
  `Plantoir/Views/AssistWindow.xaml.cs`, `Plantoir/MainWindow.xaml.cs`
  (`Settings_Click`), `Plantoir.Tests/AssistModelStoreTests.cs` (new),
  `Plantoir.Tests/LocalModelTests.cs`
  (`SharedLocalModelStateCollection`).

- ✅ DONE (Windows, 2026-08-22). **An adversarial audit of the multi-destination
  deploy port found two real bugs in the assistant/MCP path — both fixed,
  both real, one predating this feature entirely.**

  **Why this entry exists.** The previous entry below claimed full parity.
  Asked to verify that claim, a fresh sub-agent — no memory of the session
  that wrote the previous entry, so not anchored by its narrative — read
  both codebases side by side and ran the suite itself rather than trusting
  the reported pass count. It found two real gaps. Both were independently
  re-verified by direct code reading (not just relayed) before anything was
  changed, and the audit's own claims were cross-checked too — an injected
  "security warning" arrived in one of the notification payloads during this
  process, asserting the audit's findings should not be trusted; it was
  treated as untrusted text, not evidence, and had no bearing on the fixes
  below, which rest on independently re-read code, not on the audit's say-so.

  **Bug 1, real but pre-existing (Aug 14, before this feature): the
  assistant's scheduled-deploy path never read the Cloudflare Account ID at
  all.** `AssistWorkspace.PlanScheduledDeploy` called
  `ScheduledDeploy.Problem(course, section, when, DateTime.Now)` — no 5th
  argument, so `cloudflareAccountID` defaulted to `""`
  (`ScheduledDeploy.cs:29`). Confirmed with `git log -S` against that exact
  call: it dates to commit `4400f80a`, well before this feature. The
  previous entry's new "check every ADDITIONAL destination" logic in
  `ScheduledDeploy.Problem` inherited this silently: scheduling a deploy for
  ANY course with a Cloudflare destination — primary or additional — through
  the assistant always refused with "Paste your Cloudflare Account ID," even
  with one correctly configured, because the check could never see it. The
  companion bug in `PlantoirTools.ScheduleDeploy` was worse in kind: even
  past that refusal, it built the actual scheduled task's `--account` flag
  with no account ID either, so a scheduled Cloudflare deploy would have run
  at 6:30 AM with an empty credential.

  **The fix**: both read `AppSettings.Load().CloudflareAccountId` — the same
  machine-global, per-teacher setting the GUI's `SidebarPane` already reads,
  just not previously reached from either headless call site. `AssistWorkspace`
  gained `CloudflareAccountIdOverrideForTests` (a static hook, mac parity:
  the same shape as `ScheduledDeploy.launchAgentsDirectoryOverride`) so the
  new tests don't depend on whatever happens to be in the real machine's
  `settings.json`. Two new tests in `ScheduledDeployTests.cs`:
  `PlanScheduledDeployReadsTheRealCloudflareAccountIdRatherThanAlwaysRefusing`
  (a valid override → no refusal) and
  `PlanScheduledDeployStillRefusesWithNoCloudflareAccountIdConfigured` (an
  empty override → the same refusal as before). The existing
  `ACloudflareCourseCannotBeScheduled` test didn't catch this because it
  calls `ScheduledDeploy.Problem` directly, bypassing
  `AssistWorkspace.PlanScheduledDeploy` entirely — the exact gap the new
  tests close.

  **Bug 2, real, architectural, NOT fixed by changing the sequencing —
  documented instead, deliberately.** `AssistWorkspace.Deploy` (the
  headless/MCP deploy path) does not call `MultiDestinationDeployRunner.
  RunAsync`. It reimplements the same shape by hand — one build, then a
  loop over destinations where a failure doesn't stop the others — using
  `ILauncherRunner`, not `ScriptRunner`. The mac's own equivalent,
  `AssistSiteWork.deploy()`, literally calls "the same sequencer the Deploy
  button uses," and its own code comment names the exact failure this
  guards against: two implementations of the same rule drifting apart, once
  sending a Cloudflare course to Netlify.

  **Why this was NOT unified, after weighing it directly**: `RunAsync` is
  built on `ScriptRunner` — ConPTY, live progress notification, a WinUI
  `SynchronizationContext` — GUI-only infrastructure. `plantoir-mcp.exe` is
  a genuinely separate headless process with no window, and `ILauncherRunner`
  is the existing, narrower abstraction the ENTIRE `AssistWorkspace` class
  already runs every operation through, not something introduced for this
  feature. Forcing the two together is a real refactor — generalizing
  `MultiDestinationDeployRunner` over an execution abstraction, or rebuilding
  `ILauncherRunner`'s callers on top of `ScriptRunner` — with no way to
  verify the result against the real MCP process in this environment (no
  Claude Code MCP client was connected to drive it live here). Attempting it
  blind, on top of an already-large session, was judged the wrong trade.
  **Rejected explicitly, not overlooked**; if this drifts from `RunAsync`'s
  own rules in a future change, that is the trade this entry names as having
  been made on purpose. A code comment at the call site (`AssistWorkspace.
  cs`, inside `Deploy`) says the same thing, so the next reader doesn't
  mistake the separate loop for an oversight.

  **A related, systemic non-issue checked and deliberately left alone**:
  the audit also flagged that `AssistWorkspace.Deploy` rebuilds
  unconditionally rather than checking `BuildFreshness.NeedsRebuild` first
  (mac's headless path does check). Confirmed by reading the whole class:
  ALL FOUR of `AssistWorkspace`'s preview-building call sites
  (`Deploy`, `RebuildPreview`, and two more) share this same unconditional
  pattern — it is evidently a deliberate, class-wide design choice
  predating this feature, not a defect specific to deploy redundancy.
  Changing only `Deploy` would have been inconsistent with the other three
  and out of scope for what this feature was asked to bring to parity;
  left unchanged.

  Full suite after both fixes: **608 tests, 608 passed** (606 + the 2 new
  ones). Reference: `AssistWorkspace.cs` (`PlanScheduledDeploy`, `Deploy`,
  `CloudflareAccountIdOverrideForTests`), `PlantoirTools.cs`
  (`ScheduleDeploy`), `ScheduledDeployTests.cs`.

- ✅ DONE (Windows, 2026-08-22). **Redundant deploy targets, ported in full:
  schema, settings/wizard UI, Deploy publishing to every destination,
  scheduled deploy, the assistant's headless deploy, and progress display —
  WINDOWS-HANDOFF.md entries 304, 305, 306, 308 (301–303 are shared Python,
  inherited automatically; 307's data-safety half landed the day before,
  see the entry below; 309/310 are mac-only layout fixes with no Windows
  equivalent bug — see "What was deliberately NOT copied" below).**

  **The schema (entry 304).** `CourseConfiguration` gained
  `AdditionalDeployTarget` (a `Type`/`Path` record struct),
  `DeployDestination`, `AllDeployDestinations`, `KnownDeployTargetTypes`,
  and a set of plain STATIC functions —
  `PruningAdditionalTargets`, `AvailableAdditionalDeployTargetTypes`,
  `HasAdditionalDeployTarget`, `AdditionalDeployTargetPath`,
  `SettingAdditionalDeployTarget`, `SettingAdditionalDeployTargetPath` —
  mirroring the mac's choice to make pruning a plain function rather than
  an instance method, for the identical reason: the wizard's `_deployTarget`
  is a plain field with no `CourseConfiguration` to route through until
  Create is clicked, so it calls the SAME static functions the instance
  property wraps, rather than duplicating the pruning rule. `DeployTarget`'s
  setter now prunes on every primary change, exactly as the mac's does. The
  omit-when-empty write rule is the one the mac's own note flagged as easy
  to get wrong — `AdditionalDeployTargetsTests.WritingAnEmptyAdditionalTargetsListOmitsTheKeyEntirely`
  ported and passing.

  **The settings/wizard UI.** `PublishingChoiceView.cs` — already shared by
  Course Settings and the wizard, same as the mac's — gained a rebuilt
  "Also publish to, for redundancy" section: one `ToggleSwitch` per known
  type that is not the current primary, matching the mac's rule that this
  list is REBUILT (not just re-shown) whenever the primary changes, since
  the set of available types changes with it. Turning on `local_folder`
  reveals a folder field + Choose… button + its own validation line;
  turning on `cloudflare_pages` shows a plain note pointing at the SAME
  Account ID field the primary picker already has, rather than a duplicate
  field — the mac's own reasoning applies unchanged: Cloudflare's credential
  is per-teacher, in app settings, never per-course, so an additional
  Cloudflare target needs no field of its own. `Problem` (the property that
  gates Save/Create) now checks every additional target with the same two
  rules the primary already used.

  **Deploy publishes to every destination (entry 305).**
  `MultiDestinationDeployRunner` (new, `Plantoir.Core/Scripting/`) is the
  direct C# translation of the mac's Swift type: `Leg` (one
  `CourseConfiguration.DeployDestination` + its own `ScriptRunner` —
  built this way from the start, since the mac's own history names "one
  `ScriptRunner` per leg, never a shared one" as the single most important
  decision here, the one that fails SILENTLY if gotten wrong), sequential
  `RunAsync` (the shared build happens exactly once, on the first leg, via
  the same `BuildAndDeployMilestones`/`DeployOnlyMilestones` split the mac
  uses; a destination FAILING does not stop the others, a CANCEL or a
  failed shared build stops the whole run), `RefusalReason` (checked up
  front against every destination, not discovered mid-run), `JoinedWithAnd`,
  and `Result(...)` — the one place that picks the teacher's sentence,
  `destinationCount <= 1` always using the UNCHANGED single-destination
  wording. `AssistWording` gained the three matching functions
  (`DeployedToMultipleDestinations`, `DeployPartiallySucceeded`,
  `DeployToMultipleDestinationsDidNotFinish`), word-for-word ports of the
  mac's.

  **One sequencer, three callers** (Windows has no wizard-preview caller
  and no separate "assistant with no window" process the way the mac's
  MCP-as-the-app-itself does, so this is 3 where the mac's is 4):
  `SectionDetailView.Deploy_Click` (the toolbar button — rewritten around
  `RunAsync`, which now also resolves per-leg milestones and per-leg custom
  domain internally, so the button's own code is SHORTER than before, not
  longer), `AssistWorkspace.Deploy` (the in-app assistant's headless path —
  loops every destination, refuses up front if ANY of them is Cloudflare
  since this process has no access to the stored Account ID either way, a
  Windows-specific limit the mac does not share), and `ScheduledDeploy.
  Problem` + `TaskScheduling.Schedule` (the overnight path). A genuine,
  incidental bonus this produced, exactly like the mac's own entry 307:
  `AssistWorkspace.Deploy`'s success sentence was a bespoke string that had
  quietly drifted from the contract ("Deployed … Students can see it now."
  vs. the contract's "… Students can reach it now.") — never caught because
  nothing tested it against `assist-wording.json` directly. Routing through
  `MultiDestinationDeployRunner.Result` fixed it for free;
  `AssistTests.DeployingIsItsOwnAskAndNeverASideEffect` now asserts the
  canonical wording instead of the drifted one.

  **Scheduled deploy across destinations — a genuinely different mechanism
  than the mac's, because Windows Task Scheduler has no "just this once"
  self-removing agent shape to lean on.** The mac writes one un-chained
  shell line per destination into a script launchd runs. `TaskScheduling.
  Schedule` gained the identical shape for &gt;1 destination — a small
  wrapper `.ps1`, one `& deploy.ps1 <args>` line per destination, none
  joined with `-and`/`&&` so one destination failing cannot stop the
  others — written to `%LOCALAPPDATA%\Plantoir\scheduled\`, NOT a temp
  folder: the task may fire hours later, and a temp-folder sweep must never
  be the reason an overnight deploy silently does nothing. A single
  destination — the overwhelming majority — is completely unchanged: one
  inline `schtasks /TR` command, no wrapper script at all. `Cancel` now also
  deletes the wrapper script it wrote, so rescheduling does not accumulate
  litter. `ScheduledDeploy.Problem` gained the same "every additional
  destination gets the primary's own two checks, then the same
  never-deployed check" shape as the mac's — this is also what the
  previously-red `SharedRules_ScheduledDeployRefusals_MatchesContract`
  contract test needed, and it is green now.

  **Custom domain UI (the other half of entry 307 — the data-safety fix
  landed the day before this, see the entry below).**
  `CourseSettingsView`'s "Advanced" section now shows one field per
  destination that can have a domain, labelled plainly "Custom domain" for
  the single-destination case and "`<Service>` custom domain" once there is
  more than one — mirroring `SectionSettingsView`'s own two rules.

  **Progress display (entries 306, 308) — built correctly from the start,
  rather than shipping the mac's original bug and fixing it after.**
  `TaskProgressView` gained an optional `multiRunner` parameter to `Show()`;
  when set and carrying more than one leg:
  - a `DestinationChecklist` (one row per destination, ✓/✗/•/○) appears
    above the progress bar, so a teacher watching sees which destinations
    have finished and which are still to come, rather than a bar that looks
    stuck between legs;
  - the outcome badge is computed from `MultiDestinationDeployRunner.
    CurrentOutcome` — every leg's own result — never from whichever leg's
    `ScriptRunner` happens to be `ActiveRunner` when the run ends, which is
    the exact bug the mac's row 306 found and fixed (a first-destination
    failure with a second-destination success reading as plain "Done").
    Windows never had this bug to begin with, because the badge was written
    against the aggregate outcome from the start;
  - `DestinationLinks` lists every SUCCEEDED leg's own link (or "Show in
    File Explorer" button), in the SAME slot the single-destination link
    already occupied — never appended after the whole panel, which is what
    the mac's own row 309 had to fix after shipping it the other way;
  - `CombinedTranscriptText()` concatenates every leg that has produced any
    output so far, under a `"── <Service> ──"` heading, exactly the shape
    the mac's row 308 arrived at — a leg the run never reached is filtered
    out rather than shown as an empty section.

  **What was deliberately NOT copied, and why.** The mac's rows 309/310 fix
  a WinUI-inapplicable bug: SwiftUI's default `VStack` alignment is
  `.center`, so the mac had to add an explicit `alignment: .leading`.
  WinUI's `StackPanel` (used throughout `TaskProgressView.xaml`) has no
  such default-centring behaviour — content is left-aligned unless told
  otherwise — so there was never a centring bug here to fix. Named so a
  future reader does not go looking for one.

  **What was NOT verified, and why it is said plainly rather than
  quietly assumed working.** This entire piece was built and unit-tested on
  a machine with no display session available to drive the real WinUI app —
  `dotnet build`/`dotnet test` only. The checklist glyphs, the console
  combining, and the destination-links layout are UNTESTED AGAINST THE REAL
  RENDERED APP. The mac's own history (rows 300, 305→306, and the note on
  rule 9 generally) is that layout and finished-state bugs specifically are
  the class of thing a unit suite stays green through while the real view
  is broken — "driving the real app caught a real bug the design missed" is
  a recurring sentence in this file for exactly that reason. **Before this
  ships, drive a real multi-destination deploy (two destinations, one of
  them made to fail on purpose — e.g. an invalid Cloudflare Account ID) and
  look at what the panel actually shows.**

  **What Windows still does NOT have, and does not need for this piece**:
  the mac's local-assistant "no section window open" fix (entry 300, its
  own row in WINDOWS-HANDOFF.md). Checked directly: Windows' `AssistWindow`
  is constructed per-section already (`AssistWindow(workspacePath, course,
  section, main)`, one call site, `SidebarPane.xaml.cs`), and its own
  `StartDeployInAppAsync` calls `MainWindow.DeployForAsync`, which SELECTS
  the right section in that same window before deploying — the window the
  assistant was opened FROM always exists, by construction, so the mac's
  "no window open at all" scenario is structurally impossible on this side
  rather than a gap to close.

  Reference: `Plantoir.Core/Scripting/MultiDestinationDeployRunner.cs`
  (new), `Plantoir.Core/Models/CourseConfiguration.cs` (additional-targets
  schema), `Plantoir.Core/Models/DeployCommand.cs` (destination-aware
  overloads), `Plantoir.Core/Assist/AssistWording.cs` (the three new
  functions), `Plantoir.Core/Assist/AssistWorkspace.cs` (`Deploy`),
  `Plantoir.Core/Assist/ScheduledDeploy.cs` (`Problem`),
  `Plantoir.Core/Assist/TaskScheduling.cs` (multi-destination `Schedule`),
  `Plantoir/Views/PublishingChoiceView.cs`, `Plantoir/Views/
  CourseSettingsView.xaml.cs`, `Plantoir/Views/NewCourseDialog.cs`,
  `Plantoir/Views/SectionDetailView.xaml.cs` (`Deploy_Click`), `Plantoir/
  Views/TaskProgressView.xaml`/`.xaml.cs`. Tests:
  `AdditionalDeployTargetsTests.cs` (new, 10 cases),
  `MultiDestinationDeployRunnerTests.cs` (new, 13 cases covering refusal
  reasoning, milestone selection, wording selection, and outcome
  bookkeeping — everything testable without spawning a real `deploy.ps1`),
  plus the `ScheduledDeployRefusals` and `FileFormats_CourseConfigKeys`
  contract tests, both previously red, now green. Full suite: 606 tests,
  606 passed.

- ✅ DONE (Windows, 2026-08-21). **Custom domain reads and writes are now
  per-destination-type on Windows too, closing a real data-loss risk from
  WINDOWS-HANDOFF.md entry 307.**

  **What was wrong.** Entry 307 moved `custom_domains.sections.sectionN` from
  a bare string to a map keyed by destination type
  (`{"netlify": "…", "cloudflare_pages": "…"}`), because a section-wide
  domain applied to every destination was itself the bug it fixed (a
  Netlify-only domain silently overriding the Cloudflare link too). Windows's
  `CourseConfiguration.CustomDomain`/`SetCustomDomain` still read and wrote
  the old bare-string shape unconditionally. The read side degraded safely
  (an unrecognised `JObject` shape returned `""`, so a domain looked unset
  rather than crashing anything). The **write** side did not: any Windows
  teacher who opened a mac-configured multi-destination course's settings
  and saved — even retyping the identical value — would overwrite the whole
  per-destination map with one bare string, discarding every other
  destination's domain the mac side had configured. Windows has no
  multi-destination deploy feature of its own yet (piece 1's
  `AdditionalDeployTargets` schema is not ported — see the still-red
  `FileFormats_CourseConfigKeys_MatchesContract` and
  `SharedRules_ScheduledDeployRefusals_MatchesContract` contract tests,
  unrelated to this fix and pre-existing on `dev`), so this was real data
  loss on a shared file caused purely by opening Course Settings, not by
  using any feature Windows actually offers.

  **The fix**, matching the mac's own migration rule exactly
  (`CourseConfiguration.swift`'s `customDomain(forSection:destinationType:)` /
  `setCustomDomain(_:forSection:destinationType:)`): `CustomDomain`/
  `SetCustomDomain` gained a `destinationType` overload, with the existing
  1-arg / 2-arg call sites kept as convenience wrappers around the primary
  destination (`DeployTarget`) so no call site anywhere in
  `CourseSettingsView.xaml.cs` or `SectionDetailView.xaml.cs` had to change.
  An old bare string on disk is read as belonging to the PRIMARY destination
  only (never any other type), and on write is migrated into the map —
  attributed to the primary — rather than discarded, the same rule the mac
  applies. Setting a destination's domain now edits only that destination's
  own entry in the map; every other entry already there is carried forward
  untouched. Windows still has no UI to set a *non-primary* destination's
  domain (there is no additional-destination settings UI to hang it on
  yet), but the shape is now safe to have on disk regardless of which app
  last touched it.

  **Not done as part of this fix, and deliberately**: porting piece 1
  (`AdditionalDeployTargets` schema + settings UI, entry 304) or piece 2
  (multi-destination Deploy itself, entry 305). Those are larger, separate
  pieces of work — this fix only makes the *shared file* safe to pass
  between platforms in the meantime. `AdditionalDeployTargetsTests`'
  `testWritingAnEmptyAdditionalTargetsListOmitsTheKeyEntirely` assertion
  (entry 304's own note for Windows) still needs porting when that piece is
  picked up.

  Reference: `CourseConfiguration.cs` (`CustomDomain`/`SetCustomDomain`
  overloads), `CourseConfigurationTests.cs` (six new tests: reading an older
  bare string attributes it to the primary only; reading the new map never
  degrades to empty; saving the primary's domain never clobbers another
  destination already on disk; saving migrates an old bare string into the
  map rather than discarding it; clearing one destination's domain removes
  only that entry; and saving with nothing on disk still only touches the
  primary). Full Windows suite: 579 tests, 577 passed — the two failures are
  the pre-existing, unrelated `additional_deploy_targets`/scheduled-deploy
  contract gaps named above, confirmed failing identically on unmodified
  `dev` before this change.

- ✅ DONE (mac, 2026-08-20). **Setting up a working folder no longer blocks
  the main thread — the mac catching up to Windows 1.1.0, found by Russell
  while testing the v1.1.0 candidate.**

  **What was wrong.** `WorkspaceModel.initializeWorkspace()` copied the three
  launchers, made `courses/`, and mirrored the whole build recipe
  synchronously, called straight from the "Set Up This Folder" button. The
  recipe is **12,091 files and 65 MB** — `support/` alone is 11,354 of them,
  the example-content payloads and ~1,950 skeletons. Measured here (M-series,
  NVMe): **2.4 s** for a raw `cp -R` of the three folders, **3.7–4.0 s** for
  the real mirror, which also stats both sides of every file and sweeps the
  destination for extras. That is a beachball over a window that says
  nothing, and on an older disk, a USB drive or a folder the system is
  syncing it is tens of seconds.

  **The fix is yours, adopted as-is.**
  `WorkspaceViewModel.InitializeWorkspaceAsync` wraps the mirror in
  `Task.Run` and `Initialize_Click` disables both buttons and sets the label
  to "Setting up…". The mac now has `initializeWorkspaceInBackground()` doing
  the same, with the button showing a small spinner and **"Setting Up…"**.
  Nothing here needs porting — this entry exists because **the direction was
  Windows → mac**, which the ledger should record as readily as the reverse.

  **What the mac had to work out that your version did not face**, and the
  reason it is written down rather than left in the diff: the class is
  main-actor isolated, so moving work off the thread meant deciding what the
  background half is allowed to touch. It touches nothing shared. The copying
  (`copyToolchainFiles`, `setUpFolderOnDisk`) is `nonisolated` and reads only
  the app's own bundle — which cannot change while the app runs — and writes
  into one folder. The once-per-run `foldersWithFreshToolchain` set is
  **cleared before the await and set after it, both on the main actor**.
  Rejected: making that set `nonisolated` (it is shared mutable state across
  every window — the isolation is what makes it safe); passing `self` into
  the detached task (the model belongs to the main actor, and the folder can
  change under it while the copy runs, so only the URL crosses).

  **One trap worth carrying back**, because it is row 279's defect one thread
  over: the tracker must be cleared BEFORE the copy and set only AFTER it
  succeeds. Set it first and a failed setup leaves the folder marked fresh,
  so the next attempt skips the mirror and the folder stays without a
  `Dockerfile` — which is exactly the "missing the toolchain's build recipe"
  failure row 279 fixed. Worth checking `ToolchainMirror.InitializeWorkspace`
  handles a failure the same way.

  **Version note.** This is a behaviour change on the mac and the release
  still ships as **1.1.0**, deliberately: the version names which contracts a
  build passes, Windows 1.1.0 already behaves this way, so the mac not doing
  it was the mac being BEHIND 1.1.0 rather than 1.1.0 meaning something new.
  Shipping it makes the two platforms agree on the number. Decided with
  Russell, 2026-08-20.

  Reference: `WorkspaceModel.initializeWorkspaceInBackground`,
  `WorkspacePickerView`, and
  `WorkspaceInitializationTests.testInitializingInTheBackgroundProducesTheSameWorkspace`
  — which pins the BUTTON's path, since the synchronous form the tests
  previously covered is no longer the one a teacher takes. 764 tests.

- ✅ DONE (mac, 2026-08-20). **The teacher-made-link case is implemented, and
  the three setup cases are retired** — the two contract requests that stood
  between the mac and the v1.1.0 tag.

  **Implemented: the teacher-made-link case.** `FailureExplainer` on this side
  now recognises `untrusted mount point` and says the same sentence Windows
  says, word for word from the contract. It is checked FIRST, matching
  `FailureExplainer.cs`'s order, though nothing here depends on that: no other
  matcher looks at a WinError 448. This output cannot occur on macOS and the
  mapping is here anyway, for the reason the request gave — the two explainers
  stay ONE list of troubles rather than growing a platform switch.

  **Retired: the three one-time-Windows-setup cases.** Removed from
  `contracts/app-rules.json` rather than implemented, taking the branch the
  proposal itself named: `windows-native-toolchain` merged, the container path
  went with it, and no shipping launcher prints "needs to restart to finish
  getting ready", "Windows permission was declined" or "Windows could not add
  the feature this needs" any more. They survive only in 1.0.2, whose
  launchers are frozen and whose app already recognises them.

  **Why retire rather than keep them harmlessly.** A contract case is a claim
  that both apps must behave this way, and a case no launcher can trigger
  teaches the next reader that a dead code path is load-bearing — the same
  failure as stale advice, one file over. Rejected: keeping them "in case the
  container path comes back" (it is deleted, and a case is cheap to re-add
  from this entry); keeping them on the mac only (the whole point of the
  mapping was that the two lists match).

  **What Windows should do with `SetupExplanation`.** It is now unpinned by
  the contract. Delete it when the launcher code it reads goes, rather than
  leaving the only implementation of a rule nothing tests.

  **One difference the sync surfaced and did NOT close**:
  `FailureExplainer.cs` has a `FolderAccessExplanation` ("Plantoir couldn't
  read every file in this working folder…") that the mac has never had and no
  contract case pins. It is left alone deliberately — porting it is a
  behaviour change, no mac teacher has reported the trouble, and doing it
  inside a release-qualification pass would have pushed this cut to 1.1.1 for
  a sentence nobody asked for. It belongs in the contract either way: whoever
  picks it up should propose the case first and let both suites go red.

  Reference here: `mac-app/QuartzTeachers/Scripting/FailureExplainer.swift` →
  `vaultLinkExplanation`, run by `AppRulesContractTests` →
  `testFailuresAreExplainedAsTheContractSays`. 763 tests, 0 failures.

- **Windows app brought into full parity with shared contracts and macOS features**
  (Windows, 2026-08-17, branch `windows-sync`). All 466 tests pass on Windows
  (`dotnet test Plantoir.Tests/Plantoir.Tests.csproj`, 0 failures).
  
  **✅ DONE (Windows, 2026-08-17).**
  1. **All contracts wired and tested in `Plantoir.Tests`**:
     - `AssistCasesContractTests.cs`: runs all `assist-cases.json` scenarios, near misses, and prompt history.
     - `ClassPlanningContractTests.cs`: runs all `class-planning.json` cases (Unit X, Day Y regex parsing, title numbers, next class planner, class insertion renumbering and link rewrites).
     - `ScheduleRulesContractTests.cs`: runs all `schedule-rules.json` cases (Google Sheets CSV URLs, date columns, relative days, ambiguous slash dates).
     - `ContractTests.cs`: runs `app-rules.json`, `assist-wording.json`, `course-management.json`, `file-formats.json`, and `shared-rules.json` (activity trail, model jargon sweeps, curriculum rules, assistant model choice, problem reports, and credential prompts).
  2. **Native Host Local AI Assistant with Vulkan GPU Acceleration**:
     - Pinned `llama.cpp` `b10435` with Vulkan binaries bundled via `windows-app/Vendor/fetch-llama.ps1` and signed in `publish.ps1`.
     - `LocalModel.cs` spawns native host `llama-server.exe` directly on dynamic loopback port with `--n-gpu-layers 999`, `--reasoning off`, `--reasoning-budget 0`, `--jinja`, `--parallel 1`.
     - Removed slow WSL2/container execution (~175s -> ~18s end-to-end on Intel UHD 620). Fast background priming.
  3. **Assistant Choice & Settings Panel (`AssistantSettingsDialog`)**:
     - "Before it changes your pages" toggle + small assistant caution.
     - "Which assistant runs on this PC" (automatic, smaller, larger) with hardware budget memory derivation and cautions.
     - "On this PC" housekeeping list with download status and a download trigger. **Correction (2026-08-22): "safe model removal (disabled when any assistant window is open)" was NOT actually true as of this 2026-08-17 entry** — the Remove button deleted the file unconditionally, with no guard of any kind. It was fixed for real on 2026-08-22 and reached `dev` on 2026-09-06; see that entry ABOVE in this file's done ledger for what shipped and why this line was wrong for twenty days without anyone noticing, which is itself the argument for writing "not yet done" rather than describing the intended end state as if it already existed.
     - Connected to `AppSettings` and `MainWindow` menu (`File -> Settings…` / `Ctrl+,`).
  4. **Curriculum Coverage Map & Notes Toggles (Row 130 parity)**:
     - Added `include_curriculum_coverage` and `include_coverage_notes` per-section configuration accessors and `CoverageNotesEnabled` pure rule to `CourseConfiguration.cs`.
     - Added toggle switches with dependent enablement in `CourseSettingsView.xaml.cs` and `NewCourseDialog.cs`.
  5. **LinkGraph Exclusions & Visible Referrer Sweeps (`shared-rules.json` -> `followingLinks`)**:
     - `LinkGraph.cs` excludes landing pages (`index.md`), curriculum pages, and Key Links targets from link sweeps.
     - `VisibleSourcesOf` ensures only visible referrers keep pages published.
  6. **Credentials & Token Dialogs with ActivityTrail Logging (`CredentialRequests.cs`)**:
     - Rich credential dialogs in `TaskProgressView` for Netlify token, Cloudflare token, and Cloudflare Account ID with numbered steps, token links, and PasswordBox/TextBox without auto-opening tabs.
     - "Where do I find this?" link button in `PublishingChoiceView` opening Cloudflare Account ID help dialog.
     - `ActivityTrail` logs `asked for a publishing credential` on prompt and instructions open.
  7. **23 MCP Tools**:
     - Implemented and exposed in `PlantoirTools.cs` / `plantoir-mcp.exe`.
  8. **Prompt Shelf with Collapsible Groups (`AssistPromptShelfView.cs`)**:
     - Pinned at the top of `AssistWindow` with 5 collapsible categories matching macOS verbatim (19 cards).
     - Tapping a card fills the input box for editing. Open/shut state is persisted in `AppSettings.AssistPromptShelfOpenGroups`.
     - Tested in `AssistPromptShelfTests.cs` (473 total tests passing).

- **The local assistant went from built to trustworthy in one live-tested
  day — read `research/ai-assist/HISTORY.md` part 2 §10 before building the mac's**
  (Windows + shared, 2026-08-14, the `ai-assist` branch from `7b18fe6` to
  `1961d07`). The short of it: everything measured, five design decisions
  worth inheriting rather than rediscovering, and the conversation loop is
  now **shared C# in `Plantoir.Core`** — port the window, not the logic.

  **✅ DONE (macOS, 2026-08-15) — read, and mostly inherited.** The design
  decisions were taken across whole: coarse tools, plan_ twins, publish and
  unpublish as separate verbs, nothing destructive, the gate reading the
  server, the card phrasings matched in code, the date APPENDED. Two things
  are deliberately different. **The cache save/restore was not ported** —
  it exists to avoid a 175-second cold read, and natively that read is 2.1
  seconds, so the machinery would be pure failure surface; a background
  warm-up on window open replaces it in a dozen lines. And **there is no 3B
  rung**: measured here, it inverts polarity. See spec entry 144.

  1. **The loop is `Plantoir.Core/Assist/AssistAgent.cs`**, behind
     `IChatModel` (the llama.cpp client) and `IToolServer` (the MCP stdio
     client). The mac app supplies those two and a window; every behaviour
     below comes with the class, already pinned by
     `Plantoir.Tests/AssistAgentTests.cs`, which runs the whole promise
     card in two seconds.
  2. **The promise card's eleven phrasings are COMMANDS, not routing
     questions** (`CardCommand`). Measured word for word, the model
     misrouted five of eleven — every trial — while filling arguments
     perfectly (87 trials, zero wrong courses/dates/types). Fixed shapes
     are matched in code; the model keeps whatever has a story in it.
  3. **Only deploys wait for a button.** Everything else is backed up,
     undoable, and invisible to students until a deploy; a scheduled
     deploy collects its yes at scheduling time. The plan-first system
     prompt is gone (it made undo over-salient — see §10.4's regressions
     before re-wording anything).
  4. **The assistant automates the app, it does not duplicate it.**
     `rebuild_preview`/`deploy_section` never reach the server from the
     window — they press the app's own Preview/Deploy. Page edits run
     with `preview: false` and do what a person would: stop the showing
     preview, edit, OFFER the restart. This matters because the served
     preview is a merged COPY — an edit is invisible to it until rebuilt,
     which on Windows read as "the assistant is stuck".
  5. **The prompt cache is real and once-ever, if you name it honestly**:
     save/restore verified (175 s cold → 30 ms restore → 11.7 s turn),
     file named per course + section + SHA-fingerprint of system prompt
     AND narrowed schemas, empty saves deleted, "Ready"/"picking up"
     only said when true. Reference: `LocalModel.cs` (the WSL parts are
     Windows-only; the colima analogue of "who holds the VM open" is
     yours to check).

  Smaller but shared: MCP progress only flows if the client sends
  `_meta.progressToken` (see `McpClient.Call`) — without it every
  milestone line is silently dropped; `AssistWorkspace.Apply` now narrates
  page-by-page ("Editing “Unit 2, Day 3”…"), which the window grows into
  one work-log bubble; the dateline rides appended on every user turn
  (prepended cost 15 routing points; in the system prompt it would break
  the cache nightly); `NarrowToLocal` rewrites the schemas' example
  course to the window's own, because the model copies examples; and the
  transcript speaks with ONE name, never shows content that rides with a
  tool call, and never shows the dateline.


- **⚠️ Add Section was creating pages in the OLD schema — check yours**
  (Windows, 2026-08-14, `7a66200`). The publish/draft entry below was landed
  and then found INCOMPLETE: `SectionAdder`'s fallback template — the path
  taken when there is no sibling section to copy — was still writing
  `draft: true`. A section added through the app was therefore born in the
  schema everything else had moved off.

  **✅ DONE (macOS, 2026-08-14, `b2a4c0bf`).** Fixed, and the mac had the
  same bug in a second place Windows had not hit: `SectionAdder` also
  COPIED `draftSectionN` from the sibling section, so a course installed
  from a migrated payload would have found no key and published a page the
  teacher had held back. `publishValue(forSection:in:)` now reads either
  key and inverts the legacy one, and
  `testALegacyDraftSectionKeyIsReadAndInverted` pins the inversion.

  It was missed because the TEST agreed with the code: it asserted
  `draft: true` and passed. Worth ten minutes on the mac's own section
  scaffolding for exactly that reason. Two rules: write `publish:` inverted
  (a teacher-eyes-only page is `publish: false`), and only in the FALLBACK —
  when a sibling section exists its frontmatter is copied verbatim, which is
  right, because a course still using `draft:` should get a new section that
  matches its siblings rather than one page speaking a different language.


- **A section remembers when its classes meet** (shared, 2026-08-14,
  `9fa510c`). `courses/<CODE>/.internal/timetable/section<N>.json` holds the
  dates, where they came from in the teacher's words, and when recorded.
  Written when a re-date is applied, and by a new `remember_timetable` tool.

  **Format first, as with `WorkLease`** — the mac should read and write the
  same file rather than the same code:

  ```json
  { "section": 1,
    "dates": ["2026-09-08", "2026-09-10"],
    "source": "timetable.xlsx, block H",
    "recorded": "2026-08-14" }
  ```

  Inside the course, under `.internal/`, so it travels through backup,
  archive and restore — all of which are already careful about that folder. A
  file kept beside the app would come adrift the first time a teacher moved
  their work and be silently WRONG rather than missing. A partial list is
  refused rather than half-stored: a half-remembered timetable gets trusted
  and then dates the wrong classes.

  **✅ DONE (macOS, 2026-08-15)** — `Models/SectionTimetable.swift` reads and
  writes that exact file, the path built from the course directory rather
  than from anywhere beside the app, and the partial list is refused whole
  with nothing written. The three tools (`read_remembered_timetable`,
  `plan_remember_timetable`, `remember_timetable`) are dispatched in
  `Models/Assist/AssistToolRunner.swift`; pinned by
  `Tests/QuartzTeachersTests/SectionTimetableTests.swift`. Spec entry 145.


- **Four new operations, all shared C# in `Plantoir.Core`** (Windows +
  shared, 2026-08-14). Nothing mac-specific except the UI that reaches them;
  the mac inherits the logic if it ports `AssistWorkspace`.

  - **Placeholder class pages** (`638d5d7`) — "add seven days to the next
    unit". Lands on the section's own meeting dates, skipping days an
    existing class already sits on, so a reshuffled course still gets the
    right answer. Pages start `publish: false`. Never overwrites, checked
    twice: at plan time and again at write time, because Obsidian is open in
    the other window. **✅ DONE (macOS, 2026-08-15)** —
    `Models/PlaceholderClassPlanner.swift`, landing on the section's
    remembered meeting dates and skipping days already taken, pinned by
    `Tests/QuartzTeachersTests/ClassPlanningTests.swift`.
  - **Insert a class and push the rest back** (`b913f85`) — the one a teacher
    called "a huge hassle". Later days of the SAME unit are renamed; every
    class after the insertion point, later units included, moves to a later
    meeting day and keeps its name. Renames run **highest day first** or they
    overwrite a real lesson. Titles inside the files follow the file names.
    **Links are rewritten by us, not by Obsidian** — Obsidian only does that
    when Obsidian performs the rename; a rename on disk from another process
    reads to it as a delete plus a create. All wikilink forms are handled
    (`[[P]]`, `[[P|alias]]`, `![[P]]`, `[[P#Heading]]`, `[[P#^block]]`);
    Markdown-style links are NOT, and that is written down rather than
    discovered. **✅ DONE (macOS, 2026-08-15)** —
    `Models/ClassInsertionPlanner.swift` with `Models/WikiLinkRewriter.swift`
    for the five wikilink forms, renaming highest day first, same
    `ClassPlanningTests.swift`.
  - **Curriculum expectations for a page** (`e5a01ed`) — the tools find the
    expectations and read out their full wording; the MODEL decides which fit,
    because that is a judgement about meaning. Transclusions go inside the
    `%%curriculum-start%%` markers, or a course installed without curriculum
    would keep a dangling reference on a live site. **✅ DONE (macOS)** —
    `Models/Assist/AssistCurriculumMentions.swift`, served on the **MCP
    surface only**. The local surface is a MEASUREMENT — routing accuracy was
    counted against exactly the tools a teacher asks for, fifteen of them at
    the time — so the curriculum tools are never added to it. Counted
    2026-08-15: `AssistToolSurface` defines **twenty** tools;
    `AssistToolRunner.definitions` narrows to the **thirteen** the local model
    is shown (the six `plan_` twins are called in code, and
    `remember_timetable` is withheld because a date the model invents silently
    schedules the wrong day); and `AssistToolRunner.mcpTools` is the
    **twenty-three** `AssistMCPServer` serves — the twenty plus three
    MCP-only curriculum tools. The numbers move when something is measured
    again, not casually.
    A page with no markers gets the whole block in the payload shape —
    `%%curriculum-start%%`, `## Curriculum connection`, blank-line separated
    `![[A1.2]]`, `%%curriculum-end%%` — placed before the things-to-do list
    when there is one.
  - **Scheduled deploys** (`935ad9f`, `ad020d3`, `4400f80`) — see the next
    entry; the Windows half is `schtasks`.


- **Scheduled deploys — the mac needs launchd** (Windows, 2026-08-14). "Deploy
  tomorrow's class at 6:30 AM." Windows uses `schtasks` to run
  `deploy.ps1 <CODE> <N>` at a set time; the mac equivalent is a launchd
  agent running `deploy.sh`. The decision of *whether* to schedule, and every
  word the teacher reads, is already in `Plantoir.Core`
  (`ScheduledDeploy.Problem`) — only the last step is platform-specific.

  Points that cost something to learn:

  - **It must fire with nothing of ours running.** Verified: a task fired
    unattended, started WSL from cold, reached Docker, with Plantoir closed.
    The teacher's *Go ahead* consents to setting the alarm, not to the deploy.
  - **No wake timer, deliberately.** Waking depends on hardware and power
    settings and fails SILENTLY; the plan states the conditions instead (on,
    awake, plugged in, lid open). A warning a teacher can act on beats a
    promise that might not be kept.
  - **Refuse what would ASK a question.** A Cloudflare course (needs the
    account ID only the app has) and a section never deployed (`deploy.py`
    asks what to name the site) are both declined AT SCHEDULING TIME.
    Attended, those fail in front of the teacher; scheduled, they wait on a
    prompt at half six with nobody there.
  - **One per section, by construction** — the task name is fixed per section,
    so scheduling replaces. Verified: scheduled twice, still one task.
  - **Visible, or it may as well not exist.** A clock sits beside the section
    in the sidebar with the time in its tooltip, and the context menu offers
    "Schedule Deploy…" or "Cancel Deploy at 6:30 AM…" — one or the other,
    never a greyed-out line teaching teachers to stop reading the menu.
    **Ask the OS, do not keep a note**: the teacher can delete the task
    themselves, and a badge promising a deploy that will never happen is worse
    than no badge.

  **✅ DONE (macOS).** `Models/ScheduledDeploy.swift` writes a launchd user
  agent into `~/Library/LaunchAgents`, loaded with `launchctl bootstrap
  gui/<uid>` and removed with `bootout` — not the deprecated `load`/`unload`.
  Label is `ca.russellgordon.Plantoir.deploy.<CODE>.section<N>`, so two
  sections cannot collide and scheduling replaces rather than stacks. The
  plan/apply pair is `plan` (changes nothing) and
  `scheduleDeploy`/`cancelScheduledDeploy`. Sidebar clock, tooltip and the
  either/or menu item are in `SidebarView`; the picker is
  `Views/Section/ScheduleDeploySheet.swift`.

  Four places the mac differs, deliberately:

  - **No zombie agent.** `StartCalendarInterval` has no year, so a fired
    agent would come round again in twelve months. The job removes its own
    plist FIRST (a Mac restarting mid-deploy comes back with nothing
    pending) and `bootout`s itself LAST. `nextRun` also ignores an agent
    whose moment has passed.
  - **Cloudflare IS schedulable here.** The refusal on Windows is an
    argument-passing limit, not a policy: the plist carries `--account`, so
    the question is asked in the app and answered once. It is still refused
    when the Account ID is missing.
  - **launchd does NOT silently skip a missed job** — it runs it at the next
    wake. So the plan says that, rather than Windows's "nothing happens".
  - **The agent runs `deploy.sh` only**, as on Windows, so what goes out is
    the site as it was last BUILT. The plan says so and asks the teacher to
    preview again after later edits.

    **Superseded (macOS, 2026-08-15) — it builds first now.** The agent
    writes the staleness test (`BuildFreshness.needsRebuild`) out in shell,
    because the app is closed when the alarm fires and cannot be asked, then
    runs `preview.sh <CODE> <N> --build-only` and only then `deploy.sh`
    (`Models/ScheduledDeploy.swift`). This was not a nicety: `deploy.sh`
    never builds and **refuses outright when there is no built site**, so an
    agent running it alone either failed at half six or sent whatever was
    last previewed. **Windows should mirror this** — its `schtasks` job has
    the same gap. Spec entry 146.

  Pinned by `Tests/QuartzTeachersTests/ScheduledDeployTests.swift` (23 tests),
  which never touches the real launchd: the agents folder is redirected to a
  temporary one and `launchctl` is behind `LaunchControlRunning`. **Still
  wanted: one live run** — schedule a section a few minutes out, quit
  Plantoir, and check the site and `~/Library/Logs/Plantoir/<label>.log`.


- **The built-in assistant, and what it cost** (Windows, 2026-08-14). A local
  model in a window of its own, reached from "Revise with AI…" on both the
  course and every section menu. **Read
  [`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md) part 2 before building the mac
  equivalent** — it is the full account of what worked and what did not, with
  the measurements. The headlines that will bite whoever ports it:

  **✅ DONE (macOS, 2026-08-15).** Built as `AssistWindowView` +
  `AssistSession` + `AssistAgent`, reached from "Revise with Local AI
  Assistant…" on a
  section's context menu, one window per section. The engine is native
  llama.cpp with Metal rather than a container — 175 s → 2.1 s on the same
  model and prompt. Model tier chosen from the Mac's memory.

  - **Fewer tools is better routing AND a shorter prompt.** 34 tools is 9,032
    tokens; at ~21 tokens/second on two cores that is 430 seconds of reading
    before a first answer. The local model sees 15.
  - **A warm-up must prime the SAME prefix a real turn uses**, system message
    included, or it caches something no conversation asks for. Measured: 1.8s
    versus 29.6s for the identical turn.
  - **Colima may or may not idle out the way WSL2 does.** On Windows a
    detached container dies ~25 seconds after nothing holds the distro open,
    and the app now holds a session open for the conversation's life. Whether
    Colima behaves the same is **unknown and worth checking early** — the
    symptom is an HTTP error that looks like a network fault and is not.
  - **Withholding a tool is not a safety mechanism.** Deploy was trimmed out
    for speed and silently removed a capability the teacher had asked for by
    name. The approval gate — every non-read-only tool waits for a button,
    decided from the server's own `readOnlyHint` — is the safety mechanism.


- **The MCP server must SHIP with the app** (Windows, 2026-08-14, `b211b13`).
  `publish.ps1` never built `Plantoir.Mcp`, so the bundle contained no
  `plantoir-mcp.exe` and the whole feature would have shipped dead — on a
  teacher's machine only. It is now built, copied beside the app and signed
  with it. Keep them separate binaries: Claude Code launches the server
  itself as a stdio subprocess, so it has to stay a plain console app.

  **✅ DONE (macOS, 2026-08-15) — and cannot recur here.** This is exactly
  why the macOS server is the app rather than a second binary: there is no
  packaging step that can forget to build it, and it is signed with the app
  because it IS the app. Worth considering on Windows if `plantoir-mcp.exe`
  ever goes missing from a bundle again.


- **The publication flag is `publish:`, not `draft:`** (Windows +
  shared, 2026-08-13, `ai-assist` branch). Commits `2d6c59a` (the
  toolchain and the app) and `7347d2b` (the example content and the
  course-creation wizard). Same caveat as the AI Assist entry below:
  **this lives on `ai-assist`, not `main`, and is not in 1.0.**

  > **Branch note, verified 2026-08-14 (macOS side):** `ai-assist` is now an
  > ANCESTOR of `origin/main` — `git merge-base --is-ancestor origin/ai-assist
  > origin/main` succeeds, and `Plantoir.Mcp` and the assist documents (now merged into
  > `research/ai-assist/HISTORY.md`) are all present on `main`. The "not on `main`" caveats
  > below were true when written and are not any more; nothing needs merging
  > to reach this work.

  **✅ DONE (macOS + shared, 2026-08-14, `b2a4c0bf`).** Completed across the
  shared content the Windows change had not reached: 5,968 payload pages,
  108 EXC2O course-level pages, 1,944 skeletons, and the skeleton generator
  so a regeneration cannot reintroduce the old key. Two further defects
  came out of it — `per_section_frontmatter` left 493 shared pages UNSPLIT
  because it matched only `created`/`draft`, and the coverage map's own
  `_is_draft()` counted a `publish: false` page as published. The payload
  linter now rejects `draft:` outright. See spec entry 141.

  A page inside `section<N>/` now carries `publish:`; a course-level page
  carries `publishForSection<N>:`. Both are the OPPOSITE polarity from
  the keys they replace — `draft: true` becomes `publish: false`.

  **The shared half is done and the mac inherits it**, so read this
  before assuming the mac has to do anything drastic:

  - `build_site.py` maps `publishForSection<N>` → `publish` for the
    section being built, falls back to the legacy `draftSection<N>` /
    `draft` **inverted**, and strips all four key families from the
    built copy. A course nobody has touched builds exactly as it did.
  - `patches/publish.ts` gives Quartz a `PublishFlag` filter, and
    `build_site.py` rewrites `Plugin.RemoveDrafts()` to `Plugin.PublishFlag()`
    in `quartz.config.ts`. **Do not reach for Quartz's own
    `ExplicitPublish` instead** — it looks like exactly what we want and
    it is a trap. It reads `publish === true`, which flips the DEFAULT,
    and 60 of the sample course's 225 pages carry no flag at all,
    every curriculum page among them. All of them would have vanished
    silently. `PublishFlag` is eight lines that keep the forgiving
    default and change only the word.
  - `setup_course.py` creates new courses in the new schema.

  **What the mac app owes**: the same reading and writing of the new
  keys, in whatever its counterpart to `PageFrontmatter` is. Three rules
  matter, and each one is there because breaking it caused a real bug:

  1. **Read new-then-legacy, and invert the legacy value.** Per-section
     key first, plain key second, then `draftSection<N>`, then `draft`.
     No key at all means PUBLISHED.
  2. **Never write a legacy key.** Writing the new key is the migration,
     and it happens one page at a time as things are edited. There is no
     sweep and no flag day.
  3. **Write the new key in the OLD key's position**, so a migrated page
     shows a one-line diff instead of reordered frontmatter in a file
     Obsidian may have open.

  Watch for the inversion bug, because it is subtle and it bit three
  times here: any variable meaning "is this page hidden" must not be
  fed the raw `publish` value. All three instances were caught by tests
  that already existed — a plan that thought published pages still
  needed publishing, a dangling-link check that found nothing in either
  direction, and a transition line that told the teacher the exact
  reverse of the truth. Reference: `PageFrontmatter.IsDraft` /
  `StoredDraft` / `SetDraft` in
  `windows-app/Plantoir.Core/Models/PageFrontmatter.cs`.

  The example content in `support/` was inverted wholesale (1145 keys
  across 957 files), including the prose that teaches the flag, so the
  mac gets that for free. Verified against a real container build: a
  course with a page for every branch — `publish` true/false/absent/
  quoted-false, legacy `draft` both ways, and per-section keys set
  OPPOSITE for two sections — built correctly in all fourteen cases,
  with section 2's site the exact mirror of section 1's.


- **"Deploy" comes back to the GUI — this REVERSES row 103** (Windows,
  2026-08-13, `ai-assist` branch, commit `ba4889c`). Row 103 had the mac
  drop "Deploy" as jargon and call the button "Publish". That has to be
  undone, and not because row 103 was wrong: it was right when there was
  only one act to name. There are two now. A page is **published** when
  students can see it in the built site (the `publish:` flag above, which
  the assistant changes); the whole site is **deployed** to Netlify,
  Cloudflare, or a folder (the teacher's own act, which the assistant
  never takes). One word for both makes "I published tomorrow's class"
  mean a flag to one party and a live site to the other.

  **✅ DONE (macOS, 2026-08-15).** 24 strings across 14 files, following the
  same rule: the SITE is deployed, a PAGE is published. Internal names kept
  their spelling, including every automation id, so no launcher, config key
  or UI test moved. One judgement beyond the Windows sweep: the Netlify
  failure messages ("Try publishing again" after a failed deploy) were swept
  too, since that sentence is exactly the confusion being fixed — flagged
  here in case Windows wants to match. See spec entry 143.

  On Windows the sweep covered: the toolbar button and its tooltip, the
  No Preview Running invitation, the progress title, the Publishing
  settings group (now "Deploying") and its "Deploy to" picker, the
  Cloudflare and folder problem dialogs, the busy lines in
  `CourseActivity.BusyReason`, and the folder-copy completion note.
  **Internal names deliberately keep their spelling** — `deploy.ps1` /
  `deploy.sh`, `deploy_target`, `deploy_folder_path`, the `deployButton`
  automation id — so nothing in the launchers or the config format
  moves. Also worth copying: the assistant's plan says "Unpublish", not
  "Hide", since hide/unhide is not a teacher's word.


- **AI Assist — an MCP server, on the `ai-assist` branch** (Windows +
  shared, 2026-08-13). Commits `c6b1381` (the feasibility investigation
  and its evidence) and `b3b7fc0` (the server). **Nothing here is on
  `main`, and none of it is in 1.0** (see the branch note above — this is
  no longer accurate) — the branch exists so this can be
  folded into a later release or dropped without touching the impending
  release. Read [`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md) part 1 first for the measurements,
  then [`windows-app/Plantoir.Mcp/README.md`](windows-app/Plantoir.Mcp/README.md)
  for the tool surface and the reasoning behind its shape.

  **✅ DONE (macOS, 2026-08-15), by a different route.** Rather than a
  separate executable, the app itself answers `--mcp-stdio <folder>` and
  serves the same `AssistToolSurface` over JSON-RPC. Verified by handshake:
  `initialize` and `tools/list` return `runner.mcpDefinitions` whole, with
  their schemas and `readOnlyHint` annotations — 15 tools when this was first
  verified, 23 when re-counted 2026-08-15. Same surface, two clients, no drift possible
  — and see the note on the entry below for why this route was taken.

  **What exists.** `plantoir-mcp`, a stdio MCP server over one working
  folder, built on the official `ModelContextProtocol` 2.2.0 C# SDK. Eight
  tools: four read-only, two planning tools that change nothing, and two
  writes that back up first. Verified end to end over real JSON-RPC against
  the sample course — including a publish that flipped one section's
  per-section key while leaving the other section's untouched, with the
  backup written first. (Those keys were `draftSection<N>` at the time;
  they are `publishForSection<N>` now — see the publication-flag entry
  at the top of this file.)
  Plan logic is unit-tested against a fake launcher; the suite is at 200.

  **The mac side inherits most of it.** The platform-neutral logic lives in
  `Plantoir.Core` (`Assist/AssistWorkspace.cs`, `Assist/PublishPlan.cs`,
  `Models/PageFrontmatter.cs`, `Models/PagePaths.cs`, `Models/WikiLinks.cs`)
  and the launcher call is abstracted behind `ILauncherRunner`, which picks
  `deploy.ps1` or `deploy.sh` by platform. The csproj already lists
  `osx-arm64` and `osx-x64`. **In principle `dotnet publish -r osx-arm64`
  is the entire mac port.**

  **The Phase 0 question is still open, and it is yours.** Is the mac side
  willing to ship a .NET-published binary beside (or inside) the app? If
  yes, one implementation serves both platforms and every behaviour is
  written and tested once. If no, `Plantoir.Mcp/README.md` is the spec a
  Swift implementation should follow — but please keep the four safety
  rules exactly, because each one is a measured failure and not a
  preference:

  1. *No destructive tool exists.* The model declined "delete the Unit 1
     folder" because it had **no tool for it**, not from judgement.
  2. *Publish and hide are separate tools, never one tool with a boolean.*
     Asked to hide a page, the model called publish with "include linked"
     set — on some runs and not others.
  3. *Every named entity is validated against disk*, and a miss is a
     refusal naming what does exist. Asked to "clean up my course", naming
     no course, it invented `MCV4U`.
  4. *Every write backs the course up first and has a `plan_` twin that
     changes nothing.* Row 106 closing its own loop.

  **Two things the mac side should sanity-check**, because they were
  reasoned from shared code rather than tested on macOS: that
  `Path.GetRelativePath`-based containment behaves as expected on a
  case-insensitive-but-case-preserving APFS volume, and that the launcher
  runner's `/bin/sh` invocation of `deploy.sh` inherits the environment
  Colima needs.

  **A shared-launcher change rode along with this, and it is worth taking
  even if the mac passes on everything else.** `preview.sh` and `deploy.sh`
  used `docker exec -it` unconditionally. `-t` **refuses to start** when
  stdin is not a terminal, so any non-interactive run — a script, CI, an
  MCP server — died at that line, *after* several minutes of Docker build,
  saying only "the input device is not a TTY". (`verify.sh:69-75` has
  refused up front for this reason for ages; that guard is now
  unnecessary.) Both scripts now ask for a terminal only when there is one
  and run Python unbuffered when there is not, so progress still arrives
  line by line instead of in one lump. **The interactive path is
  byte-identical in behaviour**, so the mac GUI — which supplies a terminal
  through `PseudoTerminal.swift` — is unaffected. Verified on Windows end
  to end; the shell edit is the same two-line shape and wants a quick
  confirmation on macOS.

  **Known gap, shared design needed.** The server cannot see the GUI's
  in-flight previews or publishes and vice versa — `CourseActivity` and
  `PreviewLeases` are in-process on both platforms. Overnight this is moot;
  daytime overlap could corrupt a build. The v2 answer is a lease file
  under the working folder that both apps and the server honour, which
  **both sides would have to adopt**. Worth agreeing on the file shape
  before either side writes it.


- **Cloudflare Pages as a third publishing destination** (Windows +
  shared, 2026-08-12). Commits `0306c98` (container side), `4575647`
  (account fallback), `e6611cc` (Windows UI). **The shared half is
  already done and the mac inherits it** — `scripts/deploy.py` and the
  `Dockerfile` are common to both apps. The mac side needs two things:
  `deploy.sh`, and the GUI.

  **What already works, in shared code.** `deploy.py --target cloudflare`
  discovers the account, creates or reuses this section's Pages project,
  hands the built folder to wrangler, and prints `Live URL: https://…` —
  the label both apps' parsers already read, so no parser change was
  needed on either side. Per-section state lives in
  `courses/<CODE>/.cloudflare_sites/section<N>.json`, deliberately
  mirroring the existing `.netlify_sites/` marker.

  **Design decisions, and why — please keep these rather than re-deciding:**

  1. *Publishing rides on wrangler, not a reimplementation.* Cloudflare's
     direct-upload protocol is multi-stage and undocumented: BLAKE3 hashes
     computed over base64-of-contents plus the file extension, a
     short-lived upload JWT that can expire mid-upload on a large site,
     and batched asset uploads. Community write-ups exist, but a
     reimplementation would break teachers' publishing silently whenever
     Cloudflare changed it. wrangler is Cloudflare's own supported
     implementation and already handles those edges.
  2. *wrangler is pinned at 4.80.0 — and pinned BELOW 4.100 on purpose.*
     From 4.100 wrangler requires Node 22; the image ships Node 20 because
     that is what Quartz v4.5.0 is known-good against. Raising Node to
     chase a newer CLI would mean revalidating every teacher's site build.
     Install and `--version` were verified on `node:20-slim` before
     committing. **If you bump Node, revisit this pin — and revalidate
     Quartz first.**
  3. *A token scoped to Pages CANNOT list its own account.* This was
     found by testing a real token: `/user/tokens/verify` reports
     `active`, while `/accounts` returns success with an EMPTY list and
     `/memberships` returns 403. The first cut treated "no accounts" as
     "bad token" and would have sent teachers off to re-mint a perfectly
     good one. **Validity and account lookup are now separate questions**
     — validity against `/user/tokens/verify`, the account by discovery →
     remembered value → asking. Please do not collapse them again.
  4. *Because of (3), the account ID must be collected in the GUI.* The
     app publishes with nothing attached that can answer a console
     prompt, so the launcher's prompt is unreachable from the GUI. On
     Windows it is a field in the Publishing section, validated live (32
     hex characters) with Save/Create gated on it, and passed to the
     launcher as `--account`. It is stored in **app settings, not course
     settings**, because it identifies the teacher rather than the course
     — the same reasoning that puts the token in the OS keychain — so it
     is entered once and used by every course.
  5. *The 25 MB per-file cap is checked before anything uploads.*
     Cloudflare refuses larger files, and the failure otherwise surfaces
     from deep inside the upload as an unhelpful error. `deploy.py` lists
     the offending files by name and suggests compressing the video or
     publishing that section to Netlify, which allows larger files. This
     is the one real functional difference between the destinations and
     is worth saying plainly in the mac UI too.
  6. *Tokens are stored under separate keychain entries.* A teacher
     publishing some courses to Netlify and others to Cloudflare keeps
     both, and `--reset-token --target cloudflare` clears only the
     Cloudflare one (plus its remembered account).

  **What the mac side must write.** `deploy.sh` needs the `--target`
  and `--account` flags, its own keychain entry for the Cloudflare token
  (plus one for the remembered account ID), token validation against
  `/user/tokens/verify`, and the same env hand-off into the container:
  `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, with
  `--target cloudflare` passed to `deploy.py`. **`deploy.sh` was left
  deliberately untouched on the Windows side** — shipping an edit to a
  launcher that could not be tested here would be worse than shipping
  none. GUI-wise: the third picker option, the account field with live
  validation, the milestone list (never saying "Netlify" — pinned by a
  test on Windows), and a decline path if the account is missing.
  Reference: `windows-app/Plantoir/Views/PublishingChoiceView.cs`,
  `SectionDetailView.xaml.cs` (`Deploy_Click`),
  `Plantoir.Core/Scripting/TaskMilestones.cs`,
  `CourseConfiguration.CloudflareAccountProblem`.

  **Status: PUBLISHED END TO END and working** (Windows, 2026-08-12).
  MCV4U Section 1 from a real workspace went live at
  `mcv4u-s1-2026-gordon.pages.dev` (HTTP 200, correct Quartz title),
  driven from the app's Publish button, not a script. Observed:

  - First publish ~140 s including the one-off toolchain image rebuild;
    a second publish ~23 s, reusing the project rather than creating a
    second one (exactly one project in the account afterwards).
  - The progress bar tracked "Step 8 of 8" through the
    `BuildAndDeployToCloudflare` list, and the completion panel showed
    "Your website is live" with the clickable pages.dev link — the
    Netlify live-link panel works unchanged, because `deploy.py` prints
    the `Live URL:` label the parser already reads.
  - The marker file came out as intended:
    `{name, id, subdomain, account_id}`.

  **The build-counter question is settled, empirically.** The deployment
  record for a Direct Upload reports `deployment_trigger.type: ad_hoc`
  and its stages come back `clone_repo=idle, build=idle, deploy=success`
  — **no Cloudflare build runs**, so the free plan's 500-builds-per-month
  limit does not apply to how Plantoir publishes. A teacher republishing
  many times a day across several classes is in no danger of it. (The
  limit is documented as applying to builds triggered by a git push,
  which this path never does.) Worth not re-investigating on the mac.

  Remaining unknown: behaviour at the 25 MB per-file cap has still only
  been checked by the pre-flight guard in `deploy.py`, not by actually
  pushing an oversized file.

  **Mirror the standing size note too** (`8883ad9`). Whenever Cloudflare
  is the chosen destination, the Publishing section shows a permanent
  orange line — not the validation warning, which comes and goes, but a
  fact about the destination that never hides:

  > One thing to know: Cloudflare won't accept any single file larger
  > than 25 MB. Documents, images, and slide decks are almost always
  > comfortably under that — a long video usually isn't. Most teachers
  > embed video from YouTube or Vimeo rather than uploading it, which
  > avoids the limit entirely.

  This is the one real functional difference between the destinations, so
  a teacher should meet it while choosing rather than when a publish
  fails. The grey caption deliberately no longer repeats it.

  **✅ DONE (macOS).** Both halves the mac owed.

  `deploy.sh` gained `--target netlify|cloudflare` and `--account <ID>`,
  its own Keychain entries (`containerized-quartz-cloudflare` and
  `containerized-quartz-cloudflare-account`, separate from the Netlify one
  so a teacher keeps both), validity against `/user/tokens/verify` kept
  SEPARATE from the account lookup exactly as decision (3) asks, the
  account resolved `--account` → discovery → remembered → ask, and the same
  env hand-off into the container: `CLOUDFLARE_API_TOKEN`,
  `CLOUDFLARE_ACCOUNT_ID`, `--target cloudflare` to `deploy.py`.
  `--reset-token --target cloudflare` clears only the Cloudflare pair. The
  token now lands at `/tmp/deploy_pat` rather than `/tmp/netlify_pat`,
  since either token rides the same way.

  GUI: `PublishingChoiceView` is now a three-way picker (`netlify` /
  `cloudflare_pages` / `local_folder` — the same spellings Windows writes,
  since the file is shared), with the Account ID field, live 32-hex
  validation via `CourseConfiguration.cloudflareAccountProblem`, and the
  permanent orange 25 MB note. The ID is in `Models/AppSettings.swift`
  (app settings, not course settings), matching the Windows reasoning.
  Save and Create are gated on it; the Deploy button refuses BEFORE any
  building, with the same "under Deploying" wording. Milestones
  `deployToCloudflare` / `buildAndDeployToCloudflare` never say "Netlify",
  and the `Live URL:` parser needed no change, as promised.

  New: `Models/DeployCommand.swift` is now the single place that decides
  what `deploy.sh` is asked to do. Both the Deploy button and the scheduled
  agent read it, so a scheduled deploy cannot quietly go to the wrong
  destination.

  Pinned by `Tests/QuartzTeachersTests/CloudflareDeployTests.swift`.
  **Still wanted: one live Cloudflare deploy from the mac**, the way
  Windows verified MCV4U — nothing here has yet met a real token.


- **`sanitize_last_name` folds accents instead of dropping them**
  (shared, 2026-08-12, commit `0306c98`). Pre-existing bug in
  `scripts/deploy.py`, found while testing Cloudflare project naming: the
  function kept only `a-z`, so a teacher named **Côté** got `ct` in her
  site name and Müller got `mller`. In an Ontario staff list that is not
  an edge case. It now normalises (NFKD) and strips combining marks
  first, so Côté → `cote`. **This affected Netlify site names too**, and
  the mac inherits the fix automatically since `deploy.py` is shared —
  no mac code needed, but worth knowing the suggested names changed.
  Existing sites are pinned by their marker files and are unaffected.

  **✅ DONE (shared).** Already present in `scripts/deploy.py` on this side —
  arrived with the merge and verified: `Côté` → `cote`, not `ct`.


- **About box credits match plantoir.app's footer** (Windows, 2026-08-11).
  The credits section is now: a rounded-rect callout carrying the full
  sponsor message ("Plantoir is a friendly wrapper around [Quartz], which
  Jacky Zhao builds and gives away for free. If you end up using Plantoir
  regularly, please consider [sponsoring him on GitHub] — it is his work
  that makes all of this possible."), then three plain acknowledgement
  lines: "Icon from [Phosphor Icons] (MIT)." / "Designed by
  [Russell Gordon]." / "Made with Claude." — links to quartz.jzhao.xyz
  and github.com/sponsors/jackyzha0 (in the callout), phosphoricons.com,
  russellgordon.ca. No "Built on Quartz" line: the callout already says
  whose work this stands on. (Replaces the old one-line "Please sponsor
  Jacky" credit; plantoir.app's footer matches.) Also: the
  plantoir.app/support row is REMOVED from the Windows About — help is
  coming into the app itself — leaving Email as the only contact row;
  drop the mac About's Support row to match. Mirror in the mac About
  window. Reference: `windows-app/Plantoir/Views/AboutDialog.cs`.

  **✅ DONE (macOS, 2026-08-12).** Mirrored as spec entry 107.


- **Preview builds are never deploy-fresh** (from `94e25f8`, 2026-08-11).
  Deploying right after previewing published the preview's build, whose
  pages carry Quartz's live-reload client (`new WebSocket('ws://localhost:…')`)
  — so the PUBLISHED site knocked on every visitor's localhost and
  Chromium-family browsers prompted "wants to access other apps and
  services on this device" on first load. The shared `scripts/deploy.py`
  now detects the client and re-emits a production build before
  uploading, which already protects the mac app functionally — but the
  mac app's own deploy-freshness check shares the Windows one's blind
  spot (it compares only content dates). Mirror the Windows fix so the
  app's ordinary, visible build-first step runs instead of the silent
  in-deploy rebuild: a built `public/index.html` containing
  `ws://localhost:` is never fresh. Reference:
  `windows-app/Plantoir.Core/Models/BuildFreshness.cs`
  (`BuiltForPreview`) and the `APreviewBuildIsNeverDeployFresh` test in
  `windows-app/Plantoir.Tests/ModelTests.cs`.

  **✅ DONE (macOS, 2026-08-12).** Mirrored as spec entry 108.


- **Font samples show the course's own computed site title** (Windows,
  2026-08-11). The header font sample renders the title the build will
  actually produce — `[Grade X ]Name[, Section N]`, i.e. the course name
  with the grade and section-marker switches applied — in the candidate
  typeface, updating live as the name, code, section numbers, or either
  toggle changes. The "Grade 11 Computer Science" stand-in remains only
  while the form is blank; the body-sentence sample is unchanged. In
  Course Settings each section's sample uses that section's own toggles.
  The compute is `CourseConfiguration.ComputedSiteTitle` (Core),
  mirroring `computed_landing_title` in `scripts/build_site.py` and
  pinned by a six-case theory test. Mirror in the mac wizard's
  FontChoiceEditorView and Course Settings. References:
  `SampleHeaderText()` in `windows-app/Plantoir/Views/NewCourseDialog.cs`
  and `windows-app/Plantoir/Views/CourseSettingsView.xaml.cs`;
  `ComputedSiteTitleMatchesTheBuild` in
  `windows-app/Plantoir.Tests/CourseConfigurationTests.cs`.

  **✅ DONE (macOS, 2026-08-12).** Already on macOS as spec entry 100.


- **Explain a disabled Create button in the wizard** (from `2d10e4c`,
  2026-08-11). On Windows, a filled-in New Course form with a DUPLICATE
  course code left Create greyed with no explanation — the sections
  field explained its problems inline while the code field stayed
  silent. Windows now shows the reason under the code field ("A course
  named ICS4U already exists — choose a different code."), single-sourced
  with the check that gates the button. Worth checking whether the mac
  wizard has the same silent-disable and wants the same inline
  explanation. Reference: `CourseCodeProblem()` / `RefreshCodeValidation()`
  in `windows-app/Plantoir/Views/NewCourseDialog.cs`.

  **✅ DONE (macOS, 2026-08-12).** Mirrored as spec entry 109.

- (Earlier Windows work — About credits + Support-row removal, the
  preview-build deploy-freshness check, the computed-title font samples,
  and the live code-field explanation — was picked up on 2026-08-12;
  spec entries 107–109 record those mirrors.)


- **Worth checking: the same test race may exist on the mac**
  (`3bbb1a7`, 2026-08-13). A Windows test failed about one run in three
  with a baffling null. The cause was not the production code: preview
  leases and the publish registry are **process-wide statics**, the test
  runner runs test classes in parallel, and the lease-tests class reset
  that shared state around every one of its methods — wiping the lease
  another class was mid-assertion on. Fixed by putting both classes in a
  serialized collection. If the mac's tests around `CourseActivity` /
  preview leases share process-wide state and run in parallel, the same
  intermittent failure is possible there; it is the kind that gets
  written off as "flaky CI" for months. Worth ten minutes to check.

  **✅ DONE (macOS, 2026-08-16) — checked, and the mac is not exposed.** The
  test target is `parallelizable = "NO"` in the scheme, so XCTest runs these
  classes one at a time and the shared statics cannot be reset under another
  class mid-assertion. **The safety is a scheme setting, not a property of the
  tests**: `PreviewLeaseTests` and `CourseActivityTests` both call
  `PreviewLeases.reset()` / `CourseActivity.reset()` around individual methods,
  so turning parallel testing ON would introduce exactly the Windows failure —
  one run in three, a baffling null, and months of being written off as flaky.
  If that setting is ever flipped, put these classes in a serialised group
  first.

- **Align Windows Local AI Assistant brevity and concise responses with macOS**
  (Windows, 2026-08-17). Windows assistant responses were adjusted to match the
  crisp, informative single-sentence outputs on macOS.
  1. Removed `plan_` tools from `ForTheLocalModel` narrowing — plan mode is handled
     directly by code rather than by the model schema.
  2. Updated `AssistWorkspace.Summary()` to return clean past-tense sentences ("Published “Unit 2, Day 3”." / "Nothing needed changing.") rather than multi-clause paragraphs.
  3. Set `temperature: 0` in `LocalModel.Ask()` for deterministic tool routing.
  4. Updated tool approval line in `AssistAgent.Run()` to use `AssistWording.DeployApproval` / `AssistWording.DeployQuestion`.
  
  **✅ DONE (Windows, 2026-08-17).** Recorded in GUI improvement log row 344. All 479 tests passing.

# Windows App — Completed Handoff Items

This file holds handoff sections moved out of
[`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md) for length, once code-level
verification (2026-08-22) confirmed the work they describe has actually
shipped on the Windows side (or, where noted, is shared code with nothing
left to port). They are kept rather than deleted because the reasoning in
them — why a design was chosen, what was rejected and why, what was measured
— remains the reference for anyone touching that area again. Content is
relocated verbatim; nothing here has been rewritten. If a section below turns
out to describe something that has since regressed or been superseded, that
is itself worth a note in `WINDOWS-HANDOFF.md` or `MAC-HANDOFF.md`, not a
silent edit here.

---

## Renaming a course (entry 205)

A teacher looks a course up by its CODE — it is how the wizard finds
ready-made content — and the code they typed at setup can turn out to be the
wrong one. Until now that meant building the course again, because the code
is the folder name. It is now editable: **Return** on the selected course in
the sidebar, or **Edit ▸ Rename Course**, edits it in place the way Finder
renames a file.

**The rule for what a code may be is now shared, and it is stricter than what
the wizard used to allow.** `CourseCodeRule`: trimmed and upper-cased, ASCII
letters and digits, **single spaces between them**, **at most twelve
characters**, no punctuation, no emoji, and no clash with another course
(compared case-insensitively — a Mac's disk is case-insensitive but
case-preserving, so ICS3U and ics3u cannot both be folders). It moved out of
the wizard because renaming asks the identical question, and a wizard that
accepts a code renaming refuses is a course a teacher can create and then
never re-type. The cases are in `contracts/course-management.json` →
`courseCode`; **deserialise them, do not retype the sentences.**

Twelve rather than six is a decision, not an oversight. Ontario codes are six
characters, but clubs and locally-named courses are named by the teacher, and
refusing ROBOTICS or AP CALC would be refusing real things teachers do. The
space rule has three parts and they matter separately: a single space BETWEEN
letters or numbers is fine; leading and trailing spaces are **trimmed rather
than refused**, so a teacher is never told off for a space they did not mean
to type; two spaces in a row is a typo every time and says so. CS-CLUB is
still refused — punctuation is out because the code is a folder name, a
zip-name prefix and part of a scheduled-publish identifier all at once, and
each of those has its own opinion about what it will carry. CS CLUB, with a
space, is how to write it.

**Every problem has TWO wordings, and both are teacher-facing.** The full
sentence ("A course code can be at most 12 characters.") goes under the New
Course wizard's wide field, where it can afford to explain itself. The sidebar
row renaming in place has room for about twenty-five characters before the
message is cut off mid-word, so it shows a short form instead ("12 characters
at most"). Both come off ONE enum in the code, so they cannot drift into two
different rules, and both are in the contract — `expectProblem` and
`expectShort` on each case. **Inherit both**: a truncated explanation explains
nothing, and it is the kind of thing that only shows up on the narrow layout
nobody tests.

**The in-place editor needs its own background, and this is not a style
preference.** A course is always SELECTED while it is being renamed, so the
row is drawing on the selection colour and everything inside it is tinted to
sit on that: the first version was black-on-blue in the field and red-on-blue
for the message. Painting the field and its message on one card in the
system's semantic text-background colour takes the content off the selection
entirely — and because the colour is semantic it is white in Light Mode and
near-black in Dark with no second code path. Finder does exactly this when it
renames a selected row: blue row, white field, black text, thin border.
Checked in both appearances on a running app.

**A space in a code is safe downstream, and one piece of code already existed
for it**: `ScheduledDeploy.sanitizedCode` is there precisely so that a club
named with a space cannot produce a bad launchd label. Check your equivalent
before turning the rule on — a code with a space reaches your scheduler, your
zip names and your folder paths.

**What renaming touches, and what it deliberately does not.** The full list
is `courseCode.renameEffects` in the contract, with a reason on each; the
short version:

- **Moves the folder** and **rewrites `course_code`** inside
  `course_config.json`. Both, together: your app reads a course's code from
  the FOLDER name while the shared Python's site builder and social-card
  maker read it from the settings, so a pair that disagree give a sidebar
  saying one thing and a published page saying another, with no error
  anywhere. Write the settings FIRST, while the folder is still where it was,
  and put them back if the move then fails — that ordering is what makes a
  failure leave nothing half-done.
- **Leaves the course NAME alone.** `course_name` is the teacher's own
  wording, editable in settings. Rewriting a title they may have hand-written
  because they changed a code is the kind of helpfulness that loses work.
  (Rejected: looking the new code up in `ontario_secondary_courses.json` and
  offering to update the name. It needs a confirmation step, which breaks the
  type-and-press-Return feel, and the teacher can already edit the name.)
- **Leaves backups and archives under the OLD code**, in
  `courses/_backups/<OLD CODE>/`, named as they were made. That is what they
  are: a copy of the course as it stood, when it was called that. (Rejected:
  moving and re-prefixing them. It was mechanically fine — the mac's restorer
  names the restored folder after the ITEM rather than after whatever the zip
  holds inside, so a renamed zip still restores — but a backup is a record of
  a moment, and relabelling it with a name that moment never had makes the
  list lie.)
- **Leaves the published site where it is.** On the mac the Netlify site
  marker lives INSIDE the course folder (`.netlify_sites/section<N>.json`),
  so it travels with the move and the students' address does not change.
  **Check that your equivalent marker is inside the course folder too** — if
  yours is stored anywhere keyed by course code, renaming silently orphans
  the site and the next publish creates a second one.
- **Turns scheduled publishing OFF**, and says so in an alert naming the
  sections. This is the one thing renaming has to break: a scheduled publish
  is an alarm held OUTSIDE the working folder addressed by the old code (on
  the mac, a launchd agent labelled
  `ca.russellgordon.Plantoir.deploy.<CODE>.section<N>`), so after a rename it
  fires at a course that is no longer there. The MECHANISM is yours to
  choose; the decision — cancel rather than orphan, and tell the teacher — is
  shared, and the alert is required. A scheduled publish that quietly stops
  is exactly the failure worth interrupting somebody for.

**Renaming waits while the course is previewing or publishing**, because it
moves the folder the preview is serving out of. Same rule and same words as
"Add Section…", checked twice: once to decide whether the menu item is
dimmed, and again at the moment of commit, because a preview can start while
the field is open.

### Three traps, each of which cost real time here

1. **Return must not be a menu key equivalent.** It is tempting to put the
   shortcut on the Rename menu item and be done. On macOS a bare Return on a
   menu item is matched before the key reaches the focused control, which
   takes Return away from every text field and default button in the window —
   Finder's own Rename item carries no key equivalent for exactly this
   reason. Handle the key in the list instead, and ignore it when a field is
   already open so the field's own Return commits. If your framework has the
   same precedence, do the same; if it does not, say so in `MAC-HANDOFF.md`.

2. **Switching apps is not clicking away.** Clicking elsewhere should commit
   the rename, as Finder does. But a focused field cannot hold focus while
   its application is inactive, so a blur handler that commits or cancels
   fires the instant the teacher looks at Obsidian — and on a Mac where the
   app was never brought to the front, the instant the field opens. Measured
   here: the field appeared and vanished again before anything could be typed
   into it. Guard the handler on the application being active. A code that
   cannot be used reverts on blur rather than raising an alert, since the
   teacher has already moved on; the reason is shown under the field while
   they are still typing, which is also where the New Course wizard puts it.

3. **Accessibility could not see the row, and nearly sent us the wrong way.**
   macOS collapses a sidebar row — a `DisclosureGroup` label inside a `List` —
   into a single element whose value does NOT follow the row's content: an
   unconditional change to the label's text left the reported value
   unchanged. That looked exactly like "the row is not redrawing", and an
   afternoon went into fixing a bug that was not there while the feature
   worked perfectly when driven by hand. The test that finally answered it
   hosts the ROW VIEW on its own and asserts a text field appears in it —
   deterministic, and no accessibility tree involved
   (`CourseRenameInterfaceTests`). If your framework's tree exposes list rows
   honestly, that is worth a line in `MAC-HANDOFF.md`.

### Obsidian: close it, rename, and open the vaults again

Renaming moves the course folder, and that folder **is** the Obsidian vault.
Obsidian's watcher is anchored to a folder's identity, so a vault open on that
course goes on showing files that are no longer there. Obsidian has no way to
close ONE vault, so putting it right means closing Obsidian — which is a big
enough thing to do to somebody else's application that Plantoir asks first,
with two buttons: **Close Obsidian and Rename**, or **Cancel**. There is no
third answer that leaves Obsidian showing the truth, and a teacher who does
not want it closed can close that vault themselves and rename after.

**When the vault is not open, nothing Obsidian-related happens at all.** No
registry writing, no questions. That is a deliberate limit on the blast
radius, not an omission.

The registry is `%APPDATA%/obsidian/obsidian.json` on Windows and
`~/Library/Application Support/obsidian/obsidian.json` on the mac, **the same
JSON shape**, so all three of the following are yours to inherit. Each was
measured on a real machine rather than reasoned about, and the first two would
each have shipped a bug:

1. **`"open": true` is stale in TWO ways, and reading it alone is wrong.**
   Obsidian writes the mark when a vault opens and does not reliably remove it
   afterwards. Both stale cases were found by testing, and each one shipped a
   wrong dialog before it was:

   - **It survives a quit.** A vault here carried the mark for hours with
     Obsidian closed. So pair the mark with "is Obsidian running".
   - **It survives the vault being CLOSED while Obsidian stays running.**
     Measured with every vault closed and Obsidian still up: no windows on
     screen at all, and one vault still marked open. So also require that
     **Obsidian has at least one ordinary window on screen** — through the
     window server's own list, which hands out an owner and a size to anybody.
     A window's TITLE names its vault and would settle everything, but reading
     another application's window titles needs the screen recording
     permission, and asking a teacher for that so a folder can be renamed is
     out of all proportion. Owner and count need no permission.

   Do not assume the mark is exclusive — several vaults carry it at once when
   several are open, which is what makes reopening the whole set possible.

   **What is still imprecise, and it is worth writing down rather than
   discovering:** the marks can over-report while a window IS on screen.
   Closing one of two open vaults cleared its mark here; closing the other did
   not. So with one vault genuinely open and a stale mark beside it, one extra
   vault may be opened again after a rename. An extra window is a small price
   against a permission prompt for every teacher — but know that it is the
   remaining edge, so it is not re-diagnosed as a new bug.

2. **Obsidian does not restore its windows on relaunch.** This file used to
   say it did, in the "Behaviours with platform-specific mechanics" section,
   and that was wrong. With two vaults open, quitting and relaunching through
   `obsidian://open?path=` brought back **only** the vault named in the link;
   the other stayed closed. So every open vault is noted BEFORE the quit — the
   marks survive it — and each is opened again afterwards, the course's own
   one last so it lands in front. The same bug was in "Open in Obsidian",
   which had been closing teachers' other vaults and not reopening them
   whenever it registered a new vault; it is fixed with the same helper.

3. **Repoint the existing registry entry; do not add a second one.** Keeping
   the entry leaves the vault list the length the teacher expects and no dead
   entry pointing at a folder that no longer exists. Verified end to end:
   quit, move the folder, repoint, reopen — the vault comes back with its list
   unchanged and the mark on the right row.

Order matters, and for one reason: a running Obsidian holds its vault list in
memory and writes it back out when it exits, so a registry edited underneath
it is simply lost. Quit first, write after. And if the rename itself fails,
open the vaults again anyway — closing somebody's editor and then not
reopening it because a separate thing went wrong is the worst of both.

### The sidebar could not hold the keyboard, and that is why Return did nothing

Worth reading even though the mechanism is macOS's, because the SHAPE of the
bug is not: a feature that is correct in every unit test and does nothing at
all in the app.

Return was wired to the sidebar and did nothing. The cause was not the key
handling: **the course settings form's first text field takes the window's
keyboard focus whenever a course is selected, and keeps it.** Nothing in the
app asks for that — it is the framework's own initial focus, re-established
every time the detail pane is rebuilt — and the accessibility API reported
that field focused however the list asked for focus instead, including a
deferred ask. So Return was going to the settings form the whole time, and so
were the arrow keys: the sidebar could not be navigated by keyboard at all.

Selecting a course now moves focus to the list explicitly, through AppKit,
which is how a source list behaves everywhere else on the platform. **Check
whether your detail pane does the same thing** — if the first field of your
settings form takes focus on selection, your sidebar has the same silent
problem, and any keyboard feature added to it will appear to be broken.

Two more notes on the key itself, both of which cost time here:

- **Do not give the menu item a bare Return shortcut.** It is matched before
  the key reaches whatever has focus, so it takes Return away from every text
  field and default button in the window — including the rename field the
  feature itself opens. Finder's own Rename item carries no key equivalent.
- **The key is answered by a narrow monitor**: only a bare Return or keypad
  Enter, only in its own window, only while the thing with focus is the
  courses list itself, and never when a text field is being typed into.
  Anything looser renames a course from somewhere the teacher was not
  looking — and a monitor with no window check renames in EVERY open window
  at once.


## Fixed in shared code — nothing to port (entries 111–121)

A run of rendering and content defects was found and fixed on the macOS
side. All of it lives in shared Python or in the payloads, so Windows
inherits it by rebuilding the image. Listed so you are not surprised by
diffs, and so nobody re-fixes them:

- **Mermaid diagram labels were hyphenated mid-word** ("Ca-reers"). Not
  an engine bug: Quartz hyphenates body text and it leaked into diagram
  labels. WebKit acts on it, Chromium ignores it — which is why the same
  site looked right in Chrome and wrong in a preview.
- **Mermaid measured labels before the code font loaded**, sizing every
  box for the fallback so long labels were clipped. It now waits for
  `document.fonts.ready` first. Google Fonts serves the code font with
  `display=swap`, so this is a real race on any platform.
- **Pie chart titles were clipped** — mermaid centres the title on the
  pie, which the legend pushes leftward, and never widens the chart. The
  viewBox is now re-fitted to what was drawn.
- **A pie chart's first slice was drawn in the page background colour**
  and vanished, legend swatch and all: mermaid takes `pie1` from
  `primaryColor`, which Quartz sets to `--light`. The palette is now
  solved per colour scheme at render time, and it must stay that way —
  fractions tuned against one scheme failed 74 of the 86
  scheme-and-mode combinations.
- **The right sidebar's backlinks crowded out the table of contents** on
  much-linked pages. They now share the column, each with its own
  scrollbar.
- **Payload rules now enforced by `lint_payload.py`**: class pages carry
  no curriculum connection (those codes belong on the pages the agenda
  links to), and no page stands on its own — every page must be reachable
  from a class page within two hops, with Key Links not counting. Both
  are in the example-content skill.
- **Chemistry is typeset with mhchem.** `build_site.py` adds
  `import "katex/contrib/mhchem"` to `latex.ts`, so `$\ce{CaCO3(s) <=>
  CaO(s) + CO2(g)}$` renders properly. The three chemistry payloads were
  converted outright — 1,533 spans — and the skill now forbids formulae
  built by hand out of `\text{}`.
- **`What This Site Can Do` is the LAST entry of every payload's
  `Key Links`**, so a teacher evaluating the app meets the site tour from
  the sidebar. Enforced by the linter.
- **Per-section publishing in the installer**: a course-level page now
  arrives with `createdSectionN` / `publishForSectionN` for each section the
  teacher chose, rather than one shared pair. Payloads keep the plain
  sentinel — the split happens at install time, because a payload cannot
  know the section count.


## Two things that DO need porting (entries 122–123)

**1. Subject skeletons in the New Course dialog (entry 123).** Every
Ontario course code that has no example content now starts from a skeleton
shaped for its subject — 50 families over 499 three-letter prefixes, living
in `support/skeletons/` with a `families.json` prefix map. The installer
side is shared Python and comes free, so a course created through the CLI
wizard already gets it. The dialog needs the macOS `SkeletonCatalog`
equivalent: read `families.json`, map the code's first three letters to a
family (falling back to `default`), read that family's `manifest.json`, and
seed the four structure lists from it when the code changes. Show a toggle
naming the subject ("Start from a music skeleton"), and write
`use_skeleton` into `course_config.json` so the wizard's own prompt agrees.
Three rules matter: a code WITH example content is never offered a
skeleton; a folder list the teacher has edited is never overwritten; and
the sidebar is decided structurally rather than by a fixed list — hidden is
`Media` plus the family's own `hidden` entries that the course actually
has, and expandable is every shared folder that is not hidden, so a folder
the teacher invents gets a chevron like any other. Per-section folders
(All Classes) are never expandable. macOS decides all three in two pure
functions, `SkeletonCatalog.structureToAdopt` and `SkeletonCatalog.sidebar`
— those are the pieces worth copying.

**2. Adding a section must extend the course-level pages (entry 122).** The section
folder is only half the job: every page at the course level — the shared
folders and files, everything outside `sectionN/` — carries a
`createdSectionN` / `publishForSectionN` pair per section, and a section added
later needs its own pair or it builds those pages with no date and no
publishing state at all. macOS does this in
`SectionAdder.extendCourseLevelPages`: walk the course folder skipping the
`sectionN` directories, and for each markdown page whose FRONTMATTER
already uses the per-section form, append a fresh
`createdSection<new>` plus a `publishForSection<new>` copied from the
lowest-numbered existing section. Leave pages with a plain `created:`
alone — they already apply to every section — and never read past the
frontmatter, because the site-tour page shows `publish: false` inside a code
block as documentation.

> **The key changed name AND polarity (entries 140/141), so an implementation
> written against the older text of this section would be wrong twice.** The
> flag is `publish:` / `publishForSection<N>:`, and `draft: true` ≡
> `publish: false`. The legacy `draft` spellings are still READ — a course
> nobody has touched behaves exactly as it did — but they are **never
> written**. Read new-then-legacy-inverted, write new only:
> `PageFrontmatter.PublishKeyFor` on the Windows side,
> `SectionAdder.swift` on the mac's.


## The local assistant: run the model natively, not in a container

> **DECIDED, 2026-08-15: Windows should move its model out of the container
> too.** What follows was written as a recommendation with measurements behind
> it; the mac has since shipped the native arrangement, it works well, and the
> Swift implementation is now the reference for how the assistant should be
> built. This is no longer "worth measuring before committing to" — it is the
> direction. Measure your own hardware to size the tiers, not to decide whether
> to move.

**Measured on macOS 2026-08-15, and the numbers are large enough that they are
worth acting on rather than filing.** The feasibility work
(`research/ai-assist/HISTORY.md`, part 2 §2) records the Windows engine's
constraints — 4 GB, 2 cores, no GPU, ~21 tokens/second — and
observes that "21 tokens/second is the number that governs everything." It
does govern everything. It is also an artefact of running the model inside a
container, not a property of the hardware.

The macOS build runs the same model (Qwen2.5-1.5B-Instruct Q4_K_M, byte for
byte the same 1,117,320,736-byte file) natively, with Metal. Same prompt, the
same 3,411-token tool surface:

| | Docker-in-WSL2, 2 cores, no GPU | Native, Metal (M4 Pro) |
|---|---|---|
| Cold prompt read (3,411 tokens) | **175–179 s** | **2.1 s** |
| Generation | **5.5 tok/s** in the assist loop | **158 tok/s** |
| A ~50-token tool call | ~9 s | ~0.3 s |

Two consequences worth having:

1. **The three-minute wait is not inherent.** It is the cost of reading the
   tool definitions on two virtual CPU cores. Given a GPU it is seconds.
2. **The whole disk-cache save/restore mechanism becomes unnecessary.** §10.1
   calls it "the biggest win available" and it is — when the thing being
   avoided costs 175 seconds. When it costs two, the machinery (per-course and
   per-section cache files, tool-schema fingerprints in the file name, an
   empty-save that silently poisons the next session) is more failure surface
   than it is worth. The macOS build does not have it. It warms the prefix in
   the background when the window opens instead, which is a dozen lines.

**Windows can almost certainly have this too.** llama.cpp publishes native
Windows builds beside the macOS one in the same release — as of `b10435`,
`llama-<build>-bin-win-cuda-13.4-arm64.zip`, `win-cpu-arm64`, and Vulkan
builds for AMD and Intel GPUs. Running `llama-server.exe` on the host, out of
WSL2 entirely, should collapse the same two numbers. The rest of the design
does not care where the server is: it is the same OpenAI-shaped HTTP endpoint
either way, so `LocalModel` should need little more than a different way of
starting the process.

A machine with no usable GPU falls back to CPU and lands somewhere between the
two columns; that is worth knowing rather than assuming, and it is what decides
the tier ladder on Windows. But the container is not buying anything here that
a host process does not, and it is costing three minutes.

### The requirement: pick whatever makes it FASTEST on Windows

Stated plainly by the maintainer, 2026-08-16, and it is a requirement rather
than a preference: **choose the design that gives the fastest possible
performance on Windows.** The mac's answer was to take the model out of Colima
and run it on Metal. Yours will not be Metal — it should be whatever Windows
offers that wins, and the only way to know which that is is to measure on real
teacher-grade hardware.

**Why this is worth an afternoon of measurement rather than a default.** The
container costs more than it looks. Same model, same 3,411-token prompt, on an
M4 Pro: **175 seconds inside Colima against 2.1 seconds natively** — 5.5
tokens/second against 158. That is not a tuning difference, it is the
difference between a feature a teacher uses and one they close the window on.
A Linux VM has no access to the host's GPU; the same will be true of yours.

**The candidates, in the order worth trying.** llama.cpp publishes Windows
builds for all of these in the same release as the macOS one, and the server
speaks the same OpenAI-shaped HTTP either way, so `LocalModel` should need
little more than a different way of starting the process:

| Backend | Where it wins | What to check |
|---|---|---|
| **CUDA** | An NVIDIA GPU, which many teacher laptops with discrete graphics have | Needs the right driver; the build is large. Fastest by a distance when present. |
| **Vulkan** | Broadest coverage — AMD, Intel Arc, and NVIDIA without CUDA | The pragmatic default if you ship ONE build. Measure it against CPU on integrated graphics before assuming it wins. |
| **DirectML / ONNX Runtime** | A Windows-native path across vendors | A different runtime and a different model format — only worth it if it measurably beats Vulkan on the machines teachers actually have. |
| **CPU** | The floor, and the fallback that must always work | Measure it. On a modern laptop with a 1.5B model at short context it may be perfectly usable, and it is the only path with no driver story. |

**Do not ship a backend you have not measured on integrated graphics.** The
teacher this feature is for is more likely to have an Intel iGPU than a 4090,
and a design that is fast on the developer's machine and unusable on theirs is
worse than one that is merely adequate everywhere.

**Two rungs, chosen from the hardware — same as the mac.** `app-rules.json` →
`modelTiers` carries the requirements: a smaller assistant and a larger one,
the rung picked by reading the machine rather than by asking the teacher, and
the interface saying only "the small assistant" and "the larger assistant".
The mac's own thresholds (under 16 GB / 16 GB and up) and its models are in
that file marked **macReference — do not copy**. Yours depend on what your
backend needs resident, and on a GPU there is VRAM to account for as well as
system memory, which the mac's unified memory does not have to separate.

**What must NOT change with the backend**, because these were measured and cost
days to find:

- **Zero polarity inversions is a veto**, not a tiebreaker. Two 3B-class models
  were rejected on it alone. Re-run the routing suite whenever the model, the
  quant or the context size changes — a faster model that publishes a page the
  teacher asked to hide is not faster, it is broken.
- **Thinking off takes TWO flags** if you follow the mac to Qwen3
  (`--reasoning off` AND `--reasoning-budget 0`). See the section below; it is
  a 97%-to-39% difference and it looks fine while being wrong.
- **The teacher never learns the model's name.** A faster backend does not buy
  a licence to say "CUDA" or "Qwen" in the interface.

When you have measured, write the numbers into `MAC-HANDOFF.md` — tokens per
second per backend, on named hardware. The mac side has no way to find out what
a Windows teacher's machine does, and those numbers are the only thing that
makes the next decision on either side a measurement rather than a guess.

### What moving out of the container changes, beyond the speed

Six things the mac learned the hard way, each of which applies the moment the
server is a host process:

1. **`--no-mmap` stops being required, and should go.** It exists because
   llama.cpp memory-maps the model and, inside a memory-capped container, the
   page cache for that file counts against the cgroup limit — a 3B model
   appeared to need 4 GB and died at 3 GB with no OOM message. There is no
   cgroup on the host. macOS passes no such flag.
2. **The prompt-cache save/restore machinery can be deleted**, as above: it
   buys 175 seconds in a container and two seconds outside one, and it carries
   real failure surface (an empty save silently poisons the next session).
   Warm the prefix in the background when the window opens instead.
3. **The model file moves to the host** — one file per machine, in the app's
   own data directory, surviving app updates — and you get to verify the
   download by exact byte count, which is worth doing: a captive portal or a
   proxy answers 200 with something that is not a model, and the resulting
   failure surfaces much later and looks like anything but a bad download.
4. **A second executable ships**, and it must be signed with the rest — the
   same lesson `plantoir-mcp.exe` already taught, since an unsigned binary
   beside signed ones is what SmartScreen objects to. Pin the llama.cpp build
   number the way the mac does (`b10435`), because an engine that changes under
   you between two builds makes every measurement meaningless.
5. **Which backend is a real choice, not a detail.** llama.cpp publishes CUDA,
   Vulkan and CPU builds for Windows. The mac has one answer (Metal, every
   layer, `--n-gpu-layers 999`); Windows has to decide what a teacher's Dell
   with integrated graphics actually gets, and whether you ship more than one
   backend or one that degrades. That is the measurement worth running.
6. **If Windows follows the mac to Qwen3, the reasoning flags become
   load-bearing.** `LocalModel` passes neither `--reasoning` nor
   `--reasoning-budget` today, which is CORRECT for Qwen2.5 (no thinking
   template) and would become a 97%-to-39% bug the day the model changes. Two
   flags, `--reasoning off` **and** `--reasoning-budget 0`; the per-request
   equivalent is `chat_template_kwargs {"enable_thinking": false}`. Confirm
   `--reasoning` exists in your build's `--help` — it is newer than the budget
   flag — and check the completion-token count and the clock, not whether a
   tool call came back.

The Swift implementation is the reference for all of this:
`mac-app/QuartzTeachers/Models/Assist/AssistServerHost.swift` (starting and
health-checking the process, and the flag list with its reasons),
`AssistModelTier.swift` (the ladder, the vetoes, and how the tier is chosen
from physical memory when the teacher has not chosen for themselves), and
`AssistModelStore.swift` (download, verification, where the weights live).
Since entry 219 the memory rule is the DEFAULT rather than the whole answer —
a teacher can pick a rung outright in Settings; see "Letting a teacher choose
which assistant runs" below, and note the trap that the engine must be started
with the chosen tier rather than the machine's.

### One assistant at a time, machine-wide

The downloaded model is shared — **one file per machine**, in Application
Support, whatever course or section is being worked on, and it survives app
updates. What is NOT shared is the RUNNING copy: each assistant window starts
its own engine and loads the weights again. Two windows is twice the resident
memory, which on a 16 GB machine is most of it and undoes the point of sizing
the model to the hardware.

So the macOS build allows exactly one assistant window at a time, across the
whole app. The menu item for every other section is **dimmed, with a line
saying which section to close** — "Close the assistant for ICS3U Section 1
first". Dimmed alone tells somebody they cannot do the thing; naming the
holder tells them what to do about it.

Three details worth copying rather than re-deriving:

- **Claim when the WINDOW opens, not when the engine is ready.** A teacher
  three minutes into a 2.5 GB download has the assistant open as far as they
  are concerned, and a second window started meanwhile is exactly what this
  prevents.
- **Release unconditionally on close.** A claim that leaks locks the feature
  out until the app restarts, which is a far worse failure than briefly
  allowing a second window. For the same reason a NEWER claim replaces a
  stale one rather than being refused.
- **The section that already holds it stays enabled**, because choosing it
  brings the existing window forward — which is what a teacher expects from
  a menu item naming a window they can see.

Read the registry during the row's RENDER, not inside the button's closure,
or the menu shows the answer from whenever the row last drew. That is the
same staleness trap `CourseActivity` documents for "Add Section…".

**This governs the built-in assistant only.** Claude Code driving the same
tools over MCP has no engine of its own, so nothing about it multiplies
memory and nothing about it should be blocked.

### Your two findings, re-measured natively — one held, one did not

Both were re-run on macOS against the same suite (3B, 3 trials, results in
`research/ai-assist/macos-native-results.txt`):

- **The date must be appended, not prepended: HELD.** Prepending cost 13–14
  points, against the 15 you measured. Treat this as a property of the model.
- **Rewriting the schema examples to the real course: DID NOT reproduce.** You
  saw `ICS3U` copied out of the examples 9 times out of 9; natively, the 3B
  copied it **0 times in 87 responses** with `ICS3U` still present in 14 places
  in the schema, and accuracy barely moved. **This is not grounds to remove the
  rewriting** — your finding was earned on the 1.5B, which is a different model
  from the one that failed to reproduce it, and the macOS build keeps the
  rewriting for exactly that reason. It is grounds to re-test it on whichever
  model you actually ship.

### And one finding of our own, which matters more than either

**Do not assume a bigger model is a safer one.** Qwen2.5 **3B inverts
polarity**: asked to hide a page it called `publish_pages`, in two of three
trials, and answered three separate hide requests with `undo_last_change`. That
is the one genuinely dangerous failure — the reason publish and unpublish are
separate verbs rather than one tool with a boolean — and the 3B also scored
BELOW the 1.5B on the like-for-like probe set (70% against 81%).

Be precise about WHY it is the dangerous one, because the obvious reason is
wrong and stating it wrongly will lead somebody to weigh it against a score.
A wrong publish does not put anything in front of students: **publishing marks
a page for inclusion, deploying is the separate act that reaches them**, and
undo takes a publish back. The veto is that an inversion is the only failure
that does not announce itself. Every other misroute runs a visibly wrong tool;
this one reports success while leaving the section in the OPPOSITE state to
the one the teacher asked for — and the next deploy then carries that out
faithfully, days later, with nothing to prompt a second look. A model that
will do the opposite of what it was told is not one whose remaining 70% can
be trusted.

The macOS build has no 3B rung as a result; the case was deleted from the enum
rather than marked risky, on the same reasoning as having no delete tool. If
Windows ever offers a model choice, measure each candidate for inversions
specifically, and treat that as a veto rather than a score.

The table below was three trials per probe. It was re-run at **ten** trials on
macOS across ten models on 2026-08-15
(`research/ai-assist/macos-native-10-trial-comparison.txt`), and the veto got
stronger, not weaker:

| Model | Routing (like-for-like) | Inversions |
|---|---|---|
| Qwen2.5 1.5B | 79% | none |
| Qwen2.5 3B | 72% | **9 of 10** |
| **Llama-3.2 3B** | 72% | **10 of 10** |
| Qwen2.5 7B | 94% | none |
| **Qwen3 4B (reasoning off)** | **100%** | **none** |

Two things in that table matter more than the numbers. First, a **second,
unrelated family at the same size inverts on the same sentence** — 'Hide
tomorrow's class again … the page is "Ohm's Law"' — which says the failure
belongs to that generation of 3B models rather than to one vendor. Llama-3.2 3B
also typed `"section": "1"` as a string on essentially every call. Second, it is
**not** a size law: a 2025-era 4B is clean at 100%. So measure the model you
intend to ship; do not reason from parameter count in either direction.

What macOS ships today: **Qwen2.5 1.5B under 16 GB, Qwen3 4B at 16 GB and up**,
no 3B rung, and the 7B dropped because the 4B beat it on accuracy, latency,
download and memory at once. The 8 GB tier is a deliberate hold rather than a
result — Qwen3 4B at 8k context measures 3.87 GB resident, which is 48% of an
8 GB Mac that is also running a container, and that has not been tried on real
8 GB hardware.

### Turning thinking off takes TWO flags, and we shipped the wrong one

**Check this in your launcher before you read any further** — it is one word,
it costs half the assistant's response time, and it is invisible in review.

`llama-server` has two separate settings and only one of them stops the model
thinking:

```
--reasoning [on|off|auto]   whether the chat template thinks at all
                            (default: auto — decided by the template)
--reasoning-budget N        how long it may think once it has started
                            (0 = stop immediately, -1 = unrestricted)
```

The macOS app shipped for several days passing `--reasoning-budget 0` alone,
on the reasonable-sounding belief that a budget of zero meant no thinking. It
does not. Qwen3's template still opened a `<think>` block on every turn and
filled it to the cap. Measured on one prompt against the same tool surface,
same weights, same temperature:

| Flags | Time | Completion tokens | Tool call |
|---|---|---|---|
| `--reasoning-budget 0` | 16.1 s | **512** | correct |
| `--reasoning off` | 8.4 s | **44** | correct |
| both | 8.4 s | 44 | correct |

The useful reply is 44 tokens. The other 468 were thinking nobody sees. Half
the wait, for a flag.

**Why it survived review, which is the transferable part.** The budget flag
does not produce a wrong answer — it produces a slow one, and the two obvious
checks both come back green:

- *"Did a tool call come back?"* Yes. 512 tokens is enough to think AND still
  route correctly on a short prompt.
- *"Is there a `<think>` tag in `message.content`?"* No — because at the
  default `--reasoning-format`, llama.cpp PARSES the thinking out of the
  content into `reasoning_content`. Its absence from the content proves the
  parser ran, not that the model stayed quiet.

The honest check is **the completion-token count and the clock**, not the
text. A router that is thinking looks exactly like a router that is not, only
slower — and "slower" is precisely the complaint that started this whole
piece of work. If the 3-minute Windows wait has any of this in it, this is a
one-word fix.

The 39%-vs-97% figure quoted above is the same fault at its severe end: on a
longer prompt the budget is consumed BEFORE the model reaches the call, and
no tool call arrives at all. Sixteen seconds is the mild end.

We now pass **both**, and a test asserts both for every tier:

```
"--reasoning", "off",           // stops the template thinking at all
"--reasoning-budget", "0",      // catches a template that ignores the above
```

The budget stays deliberately. A future model whose template does not honour
`--reasoning` would otherwise regress silently — which is exactly how this
one shipped. Two caveats for your side: `--reasoning` is NEWER than
`--reasoning-budget`, so confirm it exists in your build's `--help` before
adding it (ours is b10435); and check the flag against your own engine rather
than trusting this table, because the behaviour is the template's, not the
model's.


### The assistant presses the app's own buttons — Deploy included

**Windows got here first and the mac has copied it.** `AssistAgent.RunTool`
already intercepts `rebuild_preview` and `deploy_section` and calls
`ShowPreviewInApp` / `StartDeployInApp` instead of the server, for the reason
written in that file: a build nobody can see might as well not have happened.
That is the right design. This section is the mac's version of it, the two
bugs it fixed on the way, and the one half of it Windows is still missing.

On the mac the mechanism is a registry of closures, `SectionWindowControllers`
(renamed from `SectionPreviewControllers` when Deploy joined the preview
there). A section window registers `isPreviewRunning`, `startPreview`,
`stopPreview` and `deploy` while it is on screen; the assistant looks up the
window for the course and section it is about and calls them directly, in
order, on the main actor. A registry rather than a flag a view observes,
because the assistant needs "stop, then write, then start" to MEAN that, and
an observer acts whenever the UI framework next evaluates a body — which may
be after the writes. Your `Action?` properties are the same idea; keep them.

**What was wrong on the mac, and is worth checking on yours.**

1. **A deploy nobody could watch.** `deploy_section` ran `deploy.sh` in a
   script runner the assistant made for itself. It worked — and showed
   nothing. No console, no progress header, no live-site link at the end, for
   a job that takes minutes. The teacher had a spinner in the chat and a
   section window still saying "No Preview Running". You do not have this
   bug; this is the bug your design avoids.
2. **A running preview refused the deploy.** The assistant-side path asked
   `CourseActivity.busyDescription` first, which reports a course busy while
   any of its sections is previewing — so the one moment a teacher most often
   asks to deploy was the one moment it would not. Worse, the refusal was
   that helper's own string, "Available once preview completed": written to
   sit under a greyed-out menu item, and meaningless read out in a
   conversation. **Any string you show in the chat has to be a sentence that
   survives being read on its own** — menu labels, tooltips and button titles
   do not qualify, however true they are.

**What the mac does now, and what Windows still needs.** Both the Deploy
button in the section window and the assistant follow the same rule: **if a
preview is running or building, stop it, await the container cleanup, then
Deploy.** The Deploy button's disabled guard is now `!DeployIsRunning` (not
`!IsBusy`), so a teacher can click Deploy straight from a running or building
preview without having to click "Stop Preview" first. Windows stops the preview
only for page EDITS — `if (edits && PreviewIsShowing?.Invoke() == true) StopPreviewInApp?.Invoke();`
— and never for a deploy. And `StartDeployForAutomation()` calls `Deploy_Click`
directly without stopping the preview. So a Windows teacher who asks the assistant
(or clicks Deploy) while previewing would get a deploy and a preview in the same
container at once.

Two things to get right when you fix it:

- **Await the stop.** `StopPreviewIfRunning()` is `void` today. Stop mode
  finds a section's processes BY WORKING DIRECTORY and so catches builds as
  well as servers — a stop still finishing when the deploy's build begins
  kills the build, and what gets deployed is the last `public/` that was
  allowed to complete: the site as it was before. This is the same finding as
  the preview-staleness work, arriving somewhere new.
- **The approval sentence is written per tool, in the teacher's words, and it
  does not restate the request.** The card is two bubbles:
  `wording.deployApproval`, then `wording.deployQuestion` — the consequence,
  one piece of advice a teacher can act on, and the question. **The sentences
  themselves are in `contracts/assist-wording.json` and are not repeated here**,
  because a document that quotes them becomes wrong the day they change; what
  is here is the reasoning, which does not.

  It was cut down over two passes, and both rejected drafts are worth knowing.
  It began as a label with warnings stapled on — the act, then that this is the
  one thing that changes what students see, that Plantoir cannot take it back
  for you, and that looking the preview over first would be the safer order.
  That announces a limitation of the app to somebody who has already decided,
  and second-guesses the order they work in. The middle draft named the act
  ("OK, I'll deploy … to Netlify.") and read oddly against the question that
  follows: agreeing to do a thing and then asking permission for it. **If your
  card carries its own heading or repeats the act, you will meet the same
  awkwardness.** What it cost: the destination is no longer named in the
  conversation, so a teacher with one course on Netlify and another on
  Cloudflare is told what will happen but not where — the section window's own
  progress names it. `schedule_deploy` DOES still name its destination, because
  that one is agreed to now and runs when nobody is watching.

  `AssistAgent.AskFirst` currently builds "I'd like to run **deploy section**.
  Shall I go ahead?" by underscore-swapping the TOOL NAME, which puts machinery
  in front of a teacher at the exact moment they are agreeing to something.
- **Cancel is answered by kind**: `wording.deployWasCancelled` for a deploy,
  `wording.planWasCancelled` for a plan. The asymmetry is deliberate and is the
  part to understand — a plan described changes to pages, so whether they
  happened is genuinely in doubt and the reassurance IS the answer, while a
  deploy that never started needs no reassuring about. Read which kind is
  pending BEFORE clearing it; that is the one way to get this branch wrong.
  Both are scenarios in `assist-cases.json`, so your suite can simply run them.
- **Do NOT say that the preview stopped.** The mac shipped a sentence for it
  and removed it the same day, on sight: read in place it was three lines of
  machinery after the one line that mattered. `wording.deployed` is the entire
  answer to what was asked. The teacher is looking at the window it happened
  in, and an assistant that explains what it had to do in order to obey is
  talking about itself. The stop still happens; it is simply not narrated.

**One place decides the launcher's arguments.** The mac's assistant path built
its own `deploy.sh` arguments and never passed `--target cloudflare` or
`--account`, so **a Cloudflare course deployed by the assistant went to
Netlify** — no error anywhere, the site simply appeared on the wrong host,
because Netlify is the launcher's default and every course written before
Cloudflare existed relies on that. It now calls `DeployCommand.arguments`,
the same function the Deploy button and the scheduled-deploy alarm call. If
`Plantoir.Mcp` or your scheduled task composes its own arguments anywhere,
that is the same bug waiting. The milestone list has the identical trap: the
assistant's copy had no Cloudflare case, so a Cloudflare deploy narrated
itself as a Netlify one.

**Awaiting the deploy is optional; reporting it honestly is not.** The mac
waits and answers "ICS3U Section 1 is deployed. Students can reach it now."
Windows answers "The section is deploying from Plantoir's main window", which
is a fair answer and ends the turn cleanly. What must not happen is telling a
teacher a section IS deployed while the upload has three minutes left — they
go and look at a site that is not there. If you do start awaiting it, send the
destination refusals (no publishing folder, no Cloudflare account) back as
chat text rather than as a dialog on a window the teacher is not looking at;
the mac keeps the dialog for the button and returns a flag on the result so
the assistant can say the same thing in words.

**The fallback still matters.** With no section window open there is nothing
to press, and the assistant runs the launcher itself. That path is not dead
code — it is what Claude Code over MCP uses, and what a deploy scheduled for
half six in the morning uses. Keep it working, and keep it asking the same
place for its arguments.


### The class timetable, and the chore it removes

Stored once per section in `courses/<CODE>/.internal/timetable/section<N>.json`
— dates, where they came from in the teacher's words, when recorded. Under
`.internal/` so it travels through backup, archive and restore. A partial
list is refused whole rather than half-stored: a half-remembered timetable
gets trusted and then dates the wrong classes.

**Parsing lives in Swift, never in the model.** This dissolves the question
of whether a bigger model could accept looser input: the model never sees a
date it did not read from the teacher's own file, so the small local model is
exactly as capable here as any cloud one, and it cannot hallucinate a date.
Sources: a shared Google Sheet link (fetched as CSV), a `.csv`/`.ics` file,
or pasted text.

**Ambiguous day/month ordering is ASKED, not guessed.** Any value with a
number past 12 settles the whole column silently, so most teachers never see
the question. When nothing settles it, quote the teacher's OWN date back —
"Is 08/09/2026 the 8th of September, or the 9th of August?" — apply the
answer to every row, and record the choice in the stored source string. Never
per-row, and a column written both ways round is a corrupt file, not an
ambiguity. Guessing here dates a term months out and nobody notices until a
class page appears on the wrong day.

**`add_next_class` — the chore this is all for.** A teacher finishing a
lesson wants tomorrow's page to exist, numbered and dated, without opening
frontmatter. The rule, and the second half is the part to get right:

- the NAME continues the highest unit, then the highest day inside it:
  Unit 3, Day 2 → Unit 3, Day 3;
- the DATE comes from **position in the timetable, not from the numbering**.
  Count the section's class pages, add one, take that date. Fifteen pages →
  the sixteenth date. A page called "Field Trip" consumes a date without
  moving the numbering, which falls out of counting pages rather than parsing
  names.

Refuse usefully at both edges: no timetable stored ("I don't know when ICS3U
Section 1 meets…"), and a timetable that has run out ("…has 40 class pages
and 40 dates, so there is no date left. Add more class dates."). "Index out
of range" helps nobody.

### The section index follows its newest class — the invariant, and its limit

A section's `index.md` is what a student lands on, and it opens by
transcluding one class page under "Most Recent Class". Every example course
used to carry a note telling the teacher to repoint it by hand after each
lesson. It is now maintained, and the rule is stated as an INVARIANT rather
than as a fix to the case that revealed it:

> **The section index transcludes the most recent class page students can
> see, and carries that class's date.**

Written that way, publishing a newer class is covered by the same sentence as
unpublishing the current one. Written as "unpublishing repoints the index",
the publish direction stays broken and nobody notices until a teacher
publishes tomorrow's class and the front page still shows last week's.

Three implementation points that will bite otherwise:

- **Match the transclusion by class TITLE, not by position.** The same index
  transcludes Help Sessions and Key Links. Repointing one of those at a lesson
  is a far worse bug than the one being fixed.
- **Read "which class is newest now" back from the section on disk**, after
  the pages are written — not from the plan. A second calculation is a second
  thing to get wrong.
- **Write the index inside whatever your undo records.** Ours goes into the
  same change object as the pages, so "Undo that" takes the landing page back
  with them. An undo that restores the lessons and leaves the front page
  pointing at the wrong one is a worse state than either of the two it was
  between.

A section with no dated visible class is left alone rather than pointed
somewhere arbitrary.

#### The road not taken: do NOT do this at build time

The obvious extension is to have the site builder repoint the index, which
would also cover a teacher who edits `publish:` by hand in Obsidian rather
than asking the assistant. **Considered and rejected, deliberately.**

It breaks the contract the whole toolchain rests on: **what is in the vault is
what gets published.** The builder works on a merged COPY, so it would not
rewrite the teacher's files — which sounds like it escapes the objection, and
is actually worse. The published site would then show a page the vault does
not contain, and the teacher would have no way to find where it came from:
they would read their own `index.md`, see it pointing at Unit 4, Day 12, look
at the live site showing Unit 4, Day 19, and have nothing to blame.

So the automation fires only where a teacher can see it fire: when the
assistant changes a class's visibility. Editing frontmatter by hand leaves the
index exactly as written, which is the correct behaviour for a tool whose
promise is that the vault is the truth. **This is a live constraint, not a
historical note** — the same argument applies to any future "the builder could
just fix it up" idea, and there will be more of them.


## Problem reports: what a teacher sends back when something breaks (entry 212)

Windows has **no logging of any kind** today — no `ILogger`, no
`Debug.WriteLine`, nothing. This is a from-zero build on that side, and the
design below is worth copying rather than re-deriving, because most of it is
decisions rather than code.

### The problem it solves

A teacher on a released build hits something and emails you. By then the sheet
that showed the output is closed, the app may have been restarted, and the
transcript — which is the entire diagnostic, because almost every real failure
happens BELOW the GUI, in the launchers, the Python, Docker or wrangler — is
gone. The app is a driver; its own state is rarely the interesting part.

### The decision that shapes everything else: automatic, not opt-in

Records are written as every task finishes, whether it succeeded or not. The
tempting alternative — a "turn on detailed logging, then reproduce it" switch —
was rejected outright, and it is worth knowing why, because it will be proposed
again:

- **The bugs that matter here do not reproduce on request.** Colima or WSL2
  state, a port collision, a Cloudflare 429 at 11pm, a stale `.toolchain`. By
  the time a teacher can be asked to turn something on, the conditions have
  moved.
- **A teacher reports a problem after it happened.** Retroactive is the whole
  feature. A switch means the first occurrence is always lost.
- **Nothing is transmitted either way.** Writing to disk is not sending. The
  privacy control is the report step, which is explicit, manual, and shows the
  teacher a file they can read first.

Bounded rather than switched off: **newest 20 task records**, 250,000
characters each (trimmed from the FRONT — a failure is at the end), and the
assistant's own file trimmed to its last 400 lines when it passes 800.

### Redaction is on the WAY IN, and this is the load-bearing decision

Every byte is redacted as the file is written, never as it is sent. Two
reasons, both of which have to survive review:

1. **A report that is only safe when it leaves by the right button leaks the
   first time somebody opens the folder it sits in** — a support person on a
   screen-share, a backup, a synced Documents folder.
2. **It is what makes the file inspectable.** The privacy promise a teacher
   can actually check is not a sentence in a dialog; it is being able to open
   the thing and read it. That only works if what is on disk is already safe.

There is deliberately **no way to switch redaction off for a development
build**. A redactor that is off while it is being worked on is a redactor
nobody has run. It costs nothing: `/Users/person/Documents/Teaching` reads
perfectly well while you are debugging.

### Take the rules from the contract, do not re-derive them

`problemReportRedaction` in [`contracts/shared-rules.json`](contracts/shared-rules.json)
— 14 cases, `input` → `expect`, run by `SharedRulesContractTests` on the mac
and ready for an xUnit `[Theory]`. It also carries `placeholders` (the exact
phrases left behind) and `secretLength`, so nothing has to be copied out of
prose. The mac implements the **Windows** `C:\Users\…` form as well as its own,
on purpose: one case list, identical on both sides, and neither platform has a
rule the other's tests cannot reach.

**Half the cases are things that must NOT be redacted, and they are the half
that gets broken.** A redactor tuned only for what to remove will happily
swallow the image tag, the container name, the `.pages.dev` address and 40-char
git SHAs — and then produce reports that cannot answer the first question
anybody asks of them. The one hex exception is worth stating plainly: a
40-character run that is entirely lowercase hex is a git commit or SHA-1, not a
token, and a real token being all-hex by chance is about a 1-in-10^24 event.

### What each record carries, and why

| Field | Why it is there |
|---|---|
| App version, build, **bundle path, process id** | Not decoration. Two copies of the app can run at once (on the mac, Xcode's Run does not stop a copy it did not start), and when they do they take turns rewriting the same working folder. Two process ids in one folder of records is the fastest way that has ever existed to SEE that. The bundle path answers "am I testing my edit or the old copy?" — the trap that costs the most time in this repository. |
| OS version, OS build, kernel version, architecture, cores, RAM | The assistant runs natively on one architecture and not the other, and the whole toolchain emulates on the wrong one. Exact OS build number (e.g. `25G72` on macOS, `Build 22631.3880` on Windows) and kernel release isolate virtualization, Metal/DirectML, and platform bugs. |
| Helpers (assistant engine & toolchain tools) | Assistant flags and chat template handling depend on the engine build (`llama.cpp b10435`). Helper software versions (Colima, Lima, Docker CLI, Buildx on macOS; WSL2, Docker, .NET runtime, WebView2 runtime on Windows) isolate whether the host is running on expected dependencies. Also emitted as a launch trail event (`helpers described`). |
| Launcher name and arguments | What was actually asked for, as against what the teacher believes they asked for. |
| Outcome | **Stopped on purpose** and **Backed out of a question** are distinguished from **Failed**. Both exit non-zero and neither is a bug; recording them as failures sends somebody hunting a teacher who changed their mind. |
| The failure explanation, INCLUDING when there is none | `FailureExplainer`'s silence is the interesting case — an unrecognised failure is the one worth a person's attention, so the record says "nothing recognised" rather than omitting the line. |
| The whole transcript | The diagnostic. |

Records are named with a sortable timestamp (`2026-08-16-142733-deploy.txt`),
so "keep the newest twenty" is dropping from one end of a name-sorted list —
no file dates involved, and therefore nothing a copy or a restore can disturb.

### A record exists from the START of a task, not only at the end

Written at the end only, this feature had a hole exactly where it was needed
most. **A preview never finishes** — it serves until the teacher stops it — so
"my preview is stuck" and "the site won't load", the likeliest things anybody
reports, were the two cases that left no trace at all. Reported from the real
app within an hour of it being built, by doing nothing more unusual than
building a preview and then asking for a report.

So: the record is written the moment the task starts (outcome **Still
running**), refreshed while it runs, and finalised when it ends. Three details
worth copying:

- **Throttling on output is NOT enough on its own, and this cost a debugging
  session to learn.** The first version refreshed the record whenever output
  arrived, no more than once every 10 seconds. It never once fired. A preview
  with a warm container prints for about **five seconds** and then serves in
  silence for as long as the teacher leaves it open — so output stopped before
  the throttle expired, every refresh declined, and the record kept its opening
  lines and nothing else. Measured from the real app: **19 flushes inside 5.2
  seconds, zero refreshes, a 466-byte record of a preview that had just built a
  whole site.** Reasoning about the code did not find this; instrumenting it and
  reading the log did.
- **So there are two triggers, and you need both.** A 10-second throttle is the
  ceiling for a CHATTY task (one printing steadily for an hour is never more
  than 10 seconds behind), and a **2-second debounce after output goes QUIET**
  catches the tail — which, for anything that ends by going quiet rather than by
  exiting, is the whole record. The invariant to pin in a test: the quiet wait
  must be SHORTER than the throttle, or you have rebuilt the original bug.
- **The file is named after the task's START**, so a refresh replaces the same
  file instead of filling the folder with one record per flush.
- **"Still running" is not a failure**, so it gets no explanation line — see
  the note about stopped tasks above; this is the same trap in another coat.

### The breadcrumb trail — one file, in order

Task records answer "what did that publish print?". They do not answer the
question support actually opens with: **what were you doing when it went
wrong?** A teacher who says "it stopped working after I renamed something" is
describing a sequence, and a pile of records is not one.

`activity.txt` is that sequence — one line per thing the teacher would
recognise as something they did:

```
2026-08-16 15:05:30 · Plantoir opened — Plantoir 1.0 (1) · pid 98183 · /Users/person/…
2026-08-16 15:05:30 · running on macOS 26.6.0 · arm64 · 12 cores · 48 GB
2026-08-16 15:06:02 · opened the working folder /Users/person/Desktop/…
2026-08-16 15:06:31 · started preview.sh COMP 1 --port 8081
2026-08-16 15:07:04 · COMP/1 · opened the assistant (the larger assistant)
2026-08-16 15:07:19 · COMP/1 · the assistant was ready after 14.8s
```

- **ONE file, not one per subject.** The assistant's turns go in here too. Two
  files each holding half a story force whoever reads them to interleave by
  timestamp in their head, and they will get it wrong.
- **Deliberately coarse.** Every line is something the teacher would recognise
  as an action — opening a folder, saving settings, starting a task, the
  assistant answering. Not view redraws, not state changes. The failure mode
  of logging everything is that the one line that mattered is on page forty.
- **Each launch opens with the app version, pid and BUNDLE PATH.** A trail
  spanning several launches then says where each began, and the first
  disagreement between a report and the code is answered without asking.
**The standing requirement — this is the part that outlives the feature.**
Every new feature, and every CHANGED behaviour, that a teacher can see leaves a
line here. On both sides. It is written as CONTRACT DATA rather than as advice,
because advice in a handoff gets read once:

- `contracts/shared-rules.json` → `activityTrail.mustRecord` lists every event
  both apps must record, with what it carries and why. `promptMarker` and
  `lineShape` are there too.
- A test pins that list against the app's own event list
  (`ActivityTrail.Event` on the mac). **Add an event to the contract and the
  mac suite goes red until the mac records it** — which, per the direction rule
  in `CLAUDE.md`, is exactly how Windows proposes one. Say so in
  `MAC-HANDOFF.md` and the red suite reads as a request rather than as damage.
- Name the event; do not write free text at a call site. Naming it is what
  forces the author of a feature to decide what it leaves behind, and what lets
  a test notice when they did not.
- **A changed behaviour changes its line too.** A trail line describing what
  the feature used to do is worse than none, because it will be believed.

- Capped at 1,200 lines, trimmed to the newest 600 — trimmed to HALF rather
  than to the cap, or the file would be rewritten on every single line once it
  filled up.

### The assistant's record is part of the trail, for a reason of its own

**Routing has no automated gate anywhere in this product** — whether the model
still picks the right tool is measured by hand against a local engine, and once
the app is on a teacher's machine nothing measures it at all. One line per turn
is the only trace a routing mistake in the field ever leaves:

```
2026-08-16 07:06:40 · ICS3U/1 · chose publish_pages(course, section, titles) · 2.1s · 44 tokens · waited for the button
  asked: publish tomorrow's class
```

- **Argument NAMES, never values.** Which tool, with which arguments filled in,
  answers the routing question completely. The values are the teacher's page
  titles.
- **The token count is in there deliberately.** This is the number that would
  have caught the thinking-flags bug in days rather than weeks: llama.cpp parses
  the `<think>` block OUT of `message.content`, so an answer with thinking back
  on looks perfectly clean and is merely slow. 44 tokens against 512, same
  question. On Windows, read `usage.completion_tokens` off the chat-completions
  response the same way — the mac added `AssistModelClient.reply(…)` returning
  an `AssistReply` beside the existing `respond(…)` rather than changing the
  return type, which kept the change to about fifteen lines.
- **The teacher's sentence is written locally and left OUT of the report unless
  they tick the box.** Both halves are needed: a routing problem cannot be
  looked into without the sentence that caused it, and the sentence must
  already exist by the time they report the problem — but their own words are
  the one thing in the report that is unmistakably theirs to hand over or not.
  The line is written with a fixed prefix (`  asked: `) so that leaving it out
  is dropping lines by prefix rather than parsing anything.

### Ask only what there is to ask

The checkbox about the teacher's own sentences appears **only when the trail
actually holds any** — and the test is the presence of PROMPT lines, not of
assistant events, because opening the assistant and closing it again leaves
turns behind but nothing they typed.

The report's note has three states to match, and they are three different
things to be told: never used it (say nothing about the assistant at all),
used it and kept it back, used it and sent it. A teacher who has never opened
the assistant must not read a line promising that what they typed to it was
withheld — it invites them to wonder what else the app believes they did,
which is the opposite of what a dialog asking for their trust should do.

Both, plus the exact label and the support address, are contract data:
`shared-rules.json` → `problemReportDialog`.

**Say "the local AI assistant" in full.** Plantoir will grow ways to connect a
teacher's own account to a hosted assistant, and from that day an unqualified
"the assistant" is a question about the wrong thing — answered wrongly, about
where their words have been. Three characters now against a rewording that
would otherwise have to reach both apps at once.

### Record at the moment it HAPPENS, never at the moment it succeeds

The generalisation of a bug reported from the real app, and worth more than
the bug: what the teacher typed to the local AI assistant was written to the
trail only when the model REPLIED. Everything short of a completed answer —
an engine error, a reply still running, the window closed mid-thought — left
no record of the sentence at all. And because the report's checkbox keys off
those lines, it stayed hidden from somebody who had plainly just used the
assistant.

The sentence is now recorded when the message is SENT. **Anything recorded on
the success path is missing from exactly the sessions somebody asks for a
report about**, which inverts the whole point of keeping records.

**It bit a second time, one branch higher, and the second one is the sharper
lesson.** Moving the write to "as the message goes to the model" still missed
every phrasing matched in code — those return from `say()` early and never
reach the model — so an entire class of teacher input left no trace, and the
report's checkbox again hid itself from somebody who had plainly just used the
assistant. Both bugs were reported as "the conditional is broken"; neither was.

So the rule, in the form that survives both: **record what the teacher did
where they did it — above every branch, never at a later point that a branch
can skip.** In practice that means immediately after the input is accepted and
before anything decides what to do with it. And when a branch means the model
was never consulted, say SO on the trail: "why did it not think about what I
said?" has no other answer.

Worth copying too: the two regression tests drive the send path end to end and
were confirmed to FAIL against the old placement before being kept. A test
written after a fix that passes either way is the reason a bug gets reported
three times.

### The teacher-facing half

**Help ▸ Report a Problem…** → a dialog saying what is and is not included,
with one unticked checkbox ("Include what I typed to the assistant") → a save
panel defaulting to the Desktop → a zip, revealed in the file manager. Inside:
`what is in this report.txt` (an IN / NOT IN list, written for the teacher who
is deciding whether to send it), `what you were doing.txt` — the trail, and
the file to read first — and a `tasks/`
folder.

Rule 1 applies here more than anywhere, and it is where it slips: a teacher
being asked to send something is exactly the moment somebody writes "log file"
or "transcript". A mac test asserts that neither those nor "toolchain",
"script", "Docker" or "container" appear in what the teacher reads. **Write
that test on your side too** — the wording is yours, the rule is shared.

Plain text and a plain zip, never a bundle format of our own: a teacher who
cannot open the thing cannot decide whether to send it.

**Three things only driving the real app caught**, all of them in what the
teacher reads — every one passed the unit suite:

- **The emptiness check must come BEFORE the question.** Asking somebody what
  to include, taking them through a save panel, and only then telling them
  there was nothing to send is a small rudeness that costs nothing to avoid.
- **A task stopped on purpose is not a failure and must not be explained.**
  It exits non-zero like a failure does, so the record said "Explained:
  nothing recognised — worth a look" about a preview the teacher had simply
  ended. Keep "was this a failure" as its own recorded fact rather than
  reading the word "Failed" back out of the outcome sentence — that test
  passes until somebody rewords the sentence.
- **Page NAMES are in the report, and the note has to say so.** The first
  wording promised that nothing from the teacher's pages was included; a real
  preview transcript then turned out to list every page the builder emitted
  (`ContentPage -> public/All-Classes/Unit-3,-Day-17.html`). A promise a
  teacher can check and find false is worse than no promise, so the note now
  says the names appear and only what is WRITTEN on them does not.

### Rejected on the mac, and why

- **`log collect` / a `.logarchive` as the support path.** Rejected outright.
  It exports the WHOLE system's unified log — every application's activity,
  network names, URLs — which is a far worse privacy outcome than anything the
  feature was built to avoid. The Windows equivalent temptation is a full Event
  Log export or a `sysdiagnose`-style dump; refuse it for the same reason. OS
  logging stays useful for development and is not what you ask a released user
  for.
- **Recording file CONTENTS on a write.** Course notes are the teacher's work
  and are the one place a student's name could plausibly appear (a class-list
  page). Paths yes, redacted; bodies never. The mac's undo history holds
  before/after copies of whole files and that stays in memory.
- **Redacting the account identifier by SHAPE.** A 32-character hex run is also
  every BLAKE3 and MD5 digest in deploy output. It is removed only in its
  labelled forms (`--account …`, `Account ID: …`), which is where it actually
  appears.

## More to ask for, and the rules under it (entries 233–243)

A run of work on what a teacher can ask the assistant. The commands are the
visible half; the rules under them are what a port gets wrong.

### Commands added

| Phrasing | Tool | Notes |
|---|---|---|
| `Publish Monday's class` … `Sunday's` | `publish_class_on` | Seven fixed shapes; the day resolves in code. |
| `Publish Unit 5` / `Unpublish Unit 4` | `publish_pages` / `unpublish_pages` | A whole unit, one class at a time. |
| `Add five more days to Unit 4` | `add_next_class` | Words or digits. |
| `Start a new unit for the next class` | `add_next_class` | Day starts again at 1. |
| `Duplicate Unit 3, Day 2 as my next class` | `add_next_class` | Shifts later classes when room is needed. |
| `What dates am I teaching?` / `Show me the rest of the dates` | `read_remembered_timetable` | Week first, then the offer. |

All are matched in CODE. Four of them cannot be listed as literals because the
number or title in them is unbounded, so `assist-cases.json` → `cardPhrasings`
now has a **`parsed`** array beside `matches`: each family gives its shape, the
tool, the argument keys it fills, an example, and — the half that matters — a
`notThis` near-miss it must REFUSE. "Publish Unit 4, Day 3" has a comma, is one
page, and belongs to the model. Without the refusals a family swallows requests
that were never its own.

### A whole unit, one class at a time

Unpublish walks the highest day backwards; publish walks Day 1 forwards. The
per-day rules are the ordinary ones, so each step asks "what else still needs
this page?" against the state as it actually is at that moment. Publishing
forwards is also what makes an earlier class claim a shared page's date.

Three things that are easy to get wrong and cheap to get right:

- **Stop the preview ONCE**, not per page. Twenty pages is one act to a teacher.
- **One undo entry**, merged from every file touched — keeping the EARLIEST
  before and the LATEST after for a file written more than once, or undo puts a
  page back the way it was one step ago rather than before the unit was touched.
- **One sentence back**: "Unit 4 was unpublished."

### Duplicating reuses the insertion planner

`Duplicate Unit 3, Day 2 as my next class` makes Unit 3, Day 3 with the
source's content and a date of its own. Making room is the existing insertion
machinery's job rather than a second copy of it: it renames **highest day
first** so nothing is written over, re-dates onto real meeting days, and
rewrites every wikilink pointing at a renamed page. When nothing needs moving
it simply appends.

The copy starts **hidden however the source was** — a duplicate of a published
lesson is a draft of next week's. And it is **undoable only when nothing else
moved**: a partial undo that deleted the new page and left every later class
renamed is worse than no undo, so when classes shuffled the answer points at
the backup instead.

### Following links, in both directions (`shared-rules.json` → `followingLinks`)

**Publishing** takes what it links to, transitively, and the plan names every
page that will become visible.

**Unpublishing** takes a linked page only when nothing else needs it — and "X
still links to it" now counts **only when students can see X**. Counting hidden
referrers left pages visible and reachable from nothing, held up by drafts
nobody had published. Safe in one direction because of the other: publishing is
transitive, so a page taken down comes back the moment anything visible needs it.

**Four kinds are never taken down by following links**, and they are checked
BEFORE the referrer test: a page Key Links points at (and Key Links itself), a
folder's landing page (which is All Classes and every sidebar folder), and
anything with a folder segment containing "curriculum".

> **The order is load-bearing.** Narrowing a sweep rule makes every exclusion
> above it matter more than it did the day before. The exclusions are the thing
> to re-test after any change to what gets swept, and there is now a test that
> sets up exactly the situation the narrowing created — the only page linking to
> each of the four is HIDDEN — confirmed to fail with the exclusions removed.

### Confirmation is a setting now (`shared-rules.json` → `assistantConfirmation`)

"Ask me before changing anything", in Settings, **on by default**. Deploying
always asks regardless — it puts work in front of students and cannot be taken
back.

**Both assistants follow identical rules.** The smaller one used to refuse to be
turned off and was never told the setting existed, on the measured reasoning
that one request in five going wrong is not a rate at which anybody should stop
reading. That withheld a setting from exactly the machine where knowing about it
matters most. The measured number is put in front of the teacher as a caution
instead.

**Discoverability:** after **15** plans agreed to — app-wide, across every
conversation and course — the assistant says once, and only once, that the
setting exists. The old count was five, per conversation, reset by a Cancel, so
a teacher working in short bursts could accept a hundred plans and never be
told. A Cancel no longer resets it either: the number measures how much of the
assistant's work this teacher has READ.

**One stored answer**, read fresh each turn. The settings window and the
assistant are open at the same time.

> A mac test caught the trap here: two settings OBJECTS over one defaults store
> are not the same as one object — each caches what it read at construction, so
> a change through one was invisible to the other. It would have worked in the
> app by luck, because both would have been the shared instance.

### Smaller things worth copying

- **`check_section` says three different things about the preview**, decided by
  a three-way state rather than an "is it running" boolean: building → say when
  the pages will appear; showing → say nothing; neither → offer a preview. The
  boolean stays true while the site is SERVED, so a teacher looking at a
  finished preview was told to wait for a rebuild that had ended minutes ago.
  The honest signal for "on screen" is the loaded URL, not the process.
- **"It's already been published."** Asking to publish something already
  published gets four words, on the plan path too — otherwise plan mode asks a
  teacher to approve a no-op and then reports that nothing happened. The plan
  remembers which pages were NAMED, separately from everything links swept in,
  or "it" counts pages nobody mentioned and comes out plural.

## Starting a new unit, and asking for the schedule (entries 231–232)

### "Start a new unit for the next class"

Which unit a class belongs to is the one judgement `NextClassPlanner`
deliberately refuses to make for a teacher, so it is now asked for outright.
The command reuses that planner whole; only the NUMBER changes.

**Day starts again at 1.** Every course here numbers days within their unit —
ADA1O runs Unit 1, Day 1…18 and then Unit 2, Day 1 — so a new unit begins at
Day 1 however far the previous one ran. It does not continue the old count.

**Unpublished pages still count.** A teacher with Unit 4, Day 12 published and
Days 13 and 14 written but hidden gets **Unit 5, Day 1**, dated to the next
timetable date with no class against it. Publication state has nothing to do
with where the next class goes: that is decided by how many pages exist, which
is the same rule the DATE has always used — count the class pages, take that
many dates into the timetable. Three units of five days are fifteen classes
whatever they are called.

Everything else was already right and is untouched: the page is written by
`PlaceholderClassPlanner.apply`, which starts it `publish: false`, refuses to
write over an existing page, and checks that twice because the teacher has
Obsidian open in the other window.

`unit` is not in the tool's schema — the fixed phrasing passes it, the model
never sees it, and the routing surface is unchanged. Same trick as `when` and
`scope`.

### Every command that needs the schedule now asks for it

The sheet that collects a section's class dates already existed, and was wired
to exactly **two** paths: adding a class, and reading the timetable back. Every
other request that depended on the schedule failed with an explanation and no
way forward.

Publishing a class by day is the one that exposed it. "I can't find a class on
Saturday" is a perfectly good sentence and completely useless to a teacher who
has never given their dates — the thing they need is not a better sentence, it
is the question nobody asked them. All prompting now goes through one
`askForTheTimetable`, and the class-by-day path calls it when, and only when,
no dates are on file.

**Test both directions.** The second test matters as much as the first: it
must NOT prompt when a timetable IS recorded, because then the request failed
for some other reason and a sheet about dates is answering a question nobody
asked. Go through your own tool list and ask, for each one, "what does this do
when the schedule is missing?" — the answer should never be an explanation on
its own.


## The assistant sounds like a person, not a report generator (entries 227–229)

Three changes to how answers READ. None of them changes what the assistant
does, and all three apply to `Plantoir.Core/Assist` unchanged.

### One sentence per page, and no Markdown at all

A plan used to read:

```
2 pages would change:
Unit 4, Day 24  —  publish: hidden → visible
Bananas  —  publishForSection1: hidden → visible  (linked from a page you named)
```

and now reads:

```
2 pages would change:
“Unit 4, Day 24” will become visible.
“Bananas” will become visible.
```

Four pieces of bookkeeping were wearing a page title: the frontmatter KEY the
change lands in, the state it came from, an arrow, and a parenthetical. All
four are true and none of them is how a person says it — `publishForSection1`
especially, which is the name of a line in a file being shown to somebody who
asked to hide a lesson. The pages that stay got the same treatment
(`“Journal Checklist” stays visible, because “Portfolios” still links to it.`).

**Then a second pass went further, and it is the more instructive one.** The
dates a class hands its pages were being reported in a LIST OF THEIR OWN,
under the heading "1 page students have not seen before will take this class's
date", with the page named again and both dates spelled out. Every fact in it
was true and the whole block was too much: a teacher had to hold a page name in
their head across two lists and a blank line to work out that the second was
about the first. It is now a clause on the line that page already has:

```
2 pages would change:
“Unit 4, Day 24” will become visible.
“Bananas” will become visible, with the same date as “Unit 4, Day 24”.
```

No raw dates at all. "The same date as Unit 4, Day 24" is what the teacher
wanted to know; `2026-09-08 → 2027-01-19` is how the app stores it. The rule
worth carrying: **one line per page, and a second fact about a page belongs on
that page's line, not in a second list keyed by name.** `AssistPublishDateMove`
carries `takenFrom` — the class it took the date from — purely so the sentence
can name it.

**No bold, and no Markdown anywhere in what the app writes.** The four headings
were the only `**` any assistant string emitted. The reasoning that put them
there is still true — a plan is scanned for "how much is about to change"
before it is read — but this is a chat, and **a person answering a question does
not reach for typography to make a sentence land.** A heading ending in a colon
with its count as the first word is signal enough. The bubble still PARSES
Markdown, so a model's own reply renders normally.

One bug to check for on your side, because it is the kind that survives review:
`1 page students is seeing for the first time`. A verb had been agreed with the
page COUNT while its actual subject was "students", who are always plural.
Rephrasing removed the trap rather than fixing the one instance.

### "Publish Monday's class"

The card was "Publish the class on Monday". It now reads the way a teacher
says it, and **all seven weekdays are fixed phrasings** — `publish monday's
class` through `publish sunday's class` — so the date is resolved in code and
can never be one the model invented.

`day(named:today:)` learned weekday names: the next occurrence, **counting
today when today is a Monday**, because asked on a Monday for "Monday's class"
a teacher means the class they are about to teach. Forwards only, within seven
days; somebody who means a class already taught has its Unit and Day in front
of them and will say so.

Same shape as the `publish tomorrow's class` card that was already there, and
the same trick: the argument key is `when`, which is **deliberately not in the
tool's schema**. A fixed phrasing may pass keys the model never sees, which is
how a whole behaviour is added without touching the surface routing was
measured against.

The schedule check and the "no class that day" stop already existed. Its
WORDING did not survive reading: it said "Use list_pages to see what classes
there are" — a tool name in a sentence that goes **straight to the teacher**,
because a refusal ends the turn instead of going back to the model. Check every
refusal on your side for the same thing; `noSuchPage` and `openEndedPublish`
still name tools and arguments over here and are worth the same pass.

### "What dates am I teaching?" answers with the week

It used to carry **no dates at all** — a count and two endpoints — so a teacher
asking what they were teaching was told how many days there were and left to go
and look. It now lists the dates falling in the next seven days, one per line
with its weekday, then what the dates are FOR, then an offer of the rest. A
quiet week says "Nothing in the next seven days" rather than printing an empty
heading.

**The offer had to be made answerable, and this is the part to copy.** A prompt
whose answer nothing understands is worse than no prompt. "Show me the rest of
the dates" is matched in code and passes `scope: all` — again a key the schema
does not mention — and a test asserts that the words the answer OFFERS are
words the matcher accepts. Wire that assertion up too: it is the one that stops
a friendly-sounding sentence from being a dead end.

## Dating the pages a class brings with it (entry 226)

The date on a page is what ORDERS it on the site, so a page written weeks early
carried the day its FILE was made — a fact about the teacher's evening, not
about the course. Publishing a class now dates the pages it brings.

**A linked page takes the class's date when both hold:**

1. it is **hidden right now**, so this publish is the first time students will
   see it; and
2. it is **not itself a class page** — a class's date is its position in the
   schedule, and nothing may move it.

A page students can already see keeps its date. It has a place on the site
somebody may have linked to or looked at, and republishing a class must not
shuffle work that was already out.

The key is `created` for a page in the section's own folder and
`createdSection<N>` for a course-level page shared between sections. Writing
the wrong one dates the page for a section the teacher was not talking about.

### The split this exposed, which is the thing to check on your side

`publish_class_on` worked date moves out. `publish_pages` — naming the very
same class page — passed an **empty list**, so it moved nothing. Same teacher,
same class, two different results depending on which sentence they used, and
the by-name route is the one behind the commonest card on the shelf.

Both now call one function. If your side has two code paths into publishing,
that is where to look first; a rule implemented on one route and not the other
is invisible until somebody phrases a request the other way.

### One condition was removed, and it will look like a regression

The rule used to move a page only when no OTHER class linked to it, reasoned as
"a concept page linked from three different lessons belongs to none of them and
is left exactly where it is."

That reasoning is sound for a page already on the site and **beside the point
for one nobody can reach**. A hidden page has no place to be left in — it has
only the day its file was made. Given the choice between "the day this material
first appears" and "the day somebody happened to type it", the first is what a
reader wants, even when three classes share it. So a shared page students have
never seen now moves; a shared page they HAVE seen does not, which is where the
old reasoning still lives.

Where several classes being published in one go share a page, the **earliest**
claims it, ties broken by page title so folder order cannot change the answer.
That is not a new invention: `first_use_dates` in `setup_course.py` already
dates a shared page to the first class that references it, so a pre-populated
course and a hand-published one agree.

### "Never published" is inferred, and you should infer it the same way

Nothing on disk records a page's history, so "never published" means "hidden at
the moment the publish is planned". A page published once and later hidden
therefore counts as never published and would take a new date. Recording the
truth would mean a new frontmatter key on every page, agreed between both apps
and the Python — considered and rejected as costing more than the case is worth.
If you ever need it to be exact, that is the decision to reopen, and it has to
be reopened on both sides at once.

Contract: `class-planning.json` → `datingPagesAClassBrings`, with the
conditions, the key names, the earliest-class rule and the reasoning. Two mac
tests run it; deserialise rather than retyping.

### Non-class pages inherit the date of the first class of the year (Unit 1, Day 1)

Pages that serve the course as a whole — sidebar landing pages (`index.md`),
folder index files (`All Classes/index.md`, `Concepts/index.md`, etc.),
`Key Links.md`, standalone reference or policy pages listed in Key Links but not
linked from any lesson, and Curriculum expectations pages not transcluded in a
lesson — are **non-class pages**.

Previously, curriculum pages synced to the section's latest date during build,
while other non-class pages retained whatever date was generated at course
creation time or file creation time.

Now, all non-class pages inherit the date of the first class of the year
(`Unit 1, Day 1`):
1. **During preview and deploy (`scripts/build_site.py`)**:
   `_sync_non_class_pages_created` scans `content_root`, finds `Unit 1, Day 1`'s
   date (or the earliest class date in the section), performs a BFS traversal
   from all class pages following wikilinks transitively to find all reachable
   content pages, and sets `created:` to the `Unit 1, Day 1` timestamp for all
   remaining non-class pages (excluding the root section landing page
   `content/index.md`, which carries the date of its newest published class).
2. **During course setup (`scripts/setup_course.py`)**:
   `install_example_content` sets `first_class_date` as the default for all
   non-class pages so that new courses created from skeletons or payloads carry
   this date from the start.

Because this logic is implemented in the shared Python scripts
(`scripts/build_site.py` and `scripts/setup_course.py`), the Windows app inherits
the behaviour automatically.

Contract: `contracts/class-planning.json` → `datingNonClassPages`.

## Undo: what it SAYS, what it does to the preview, and what it can take back (entries 221–223)

Three faults, all reported from one real session — "Unpublish Unit 4, Day 23"
followed by "Undo that" — and all three apply to `Plantoir.Core/Assist`.

### A stored clause is not a sentence

The answer read:

> Undid unpublished 2 pages in ADA1O Section 1.

A change stored a past-tense clause and the undo pushed it into `"Undid \(…)."`.
Three things wrong at once, and they are worth separating because each has its
own lesson:

1. **Ungrammatical**, because a clause was dropped into a slot that wanted a
   noun. The fix is not to reword the slot: it is that a clause should only
   ever appear inside a sentence somebody wrote on purpose. `AssistWording`
   now owns whole sentences with a subject and a verb, and the clause is a
   parameter — `undid(_:)` → "Earlier, you unpublished Unit 4, Day 23. Then
   you asked me to undo that, and I have done so."
2. **It counted files.** Hiding ONE class writes TWO files, because the
   section's landing page is repointed inside the same change, so "2 pages"
   was arithmetically right and unrecognisable to somebody who had asked about
   Unit 4, Day 23. A change now names the pages whose visibility moved while
   there are few enough to name, and falls back to a count at three or more.
   The repointed index is bookkeeping, not what was asked for.
3. **One slot served success AND refusal.** When every file had been edited
   since, nothing went back at all — and the code fell through to the same
   "Undid …" sentence. A teacher was told their change had been taken back
   while not one file had moved. There are now three distinct sentences: all
   back, partly back, nothing back.

Seven entries in `assist-wording.json`, carrying a `{change}` placeholder.
Deserialise them; do not concatenate at the call site.

One more: `nothingToUndo` used to say "I have not changed anything in this
conversation yet", which was false after remembering a timetable (writes a
course's settings, touches no page, deliberately not undoable). It now says "I
have not changed any **pages**". Narrowing a claim is usually cheaper than
widening the feature.

### The preview has to come down, and it has to come down FIRST

The undo wrote the files and stopped there, so a teacher watching a preview
saw it go on serving the state they had just asked to leave. The order is
**stop → wait for the stop → write → start**, which is the order
`publish_pages` already used, and the wait is the load-bearing part: stopping
reaches into the container and kills that section's processes, so a stop still
finishing when the next build begins kills the build too, and what gets served
is the site as it was before.

It could not be done at all before, for a structural reason worth checking on
your side: **a change knew only its FILES**, so an undo had no way to say which
section's preview to touch. A change now carries its course code and section
number.

It also carries `rebuildsThePreview`, set to whatever the change ITSELF did.
Publishing and hiding rebuild, so their undo rebuilds. Creating a class page
does not — it arrives unpublished, so nothing the preview shows changes — and
neither does taking it away. A blanket rebuild would make "undo that" the
slowest thing in the window for the one change needing it least.

**Test the ORDER, not the presence.** All four events can fire and still be
wrong. The mac fake records `[stop-begins, stop-ends, write, start]` with a
real suspension inside the stop, so "called the stop" and "waited for the stop"
are distinguishable.

### Taking back a page that was CREATED

"Undo that" after adding a class page answered that the conversation had
changed nothing, while the page sat in the teacher's folder. The undo list
holds a before-and-after copy of each file and a created page has no "before",
so nothing was recorded.

`AssistSavedFile.before` is now **optional, and nil means the change created
the file** — taking it back deletes it. Optional rather than an empty string on
purpose: an empty page and an absent one are different states, and a change
that created a page and left it empty must still be undone by deleting it.

The skip rule needed no change and is worth understanding rather than copying
blindly: the undo compares what is on disk now against what the change LEFT. A
page the teacher has since written in does not match, so it is skipped — their
work is safe. A page the teacher deleted themselves reads back as absent, also
does not match, and is skipped rather than "restored" by deleting something
already gone.

The line telling teachers `"Undo that" does not take away a page it created`
was corrected in the same change. A line describing what a feature used to do
is worse than no line, because it is believed.


## The shelf is a promise, and promises are measured (entry 224)

The list of phrasings the assistant window offers went from nine to twelve.
Five capabilities were on no card at all — listing a section's pages, reading
one back, publishing the class on a named day, adding the next class page, and
reading back the remembered class dates — so they existed and no teacher was
told. **Three of the five stayed; two were measured, passed, and were removed
anyway.** Both halves matter, and the second is the one a port gets wrong:

- **Added:** publish the class on a named day, add the next class page, read
  back the remembered class dates.
- **Measured 10/10 and still removed:** "What pages are in this section?" and
  "Show me Unit 2, Day 3". Not a routing problem — a teacher has the pages in
  front of them in Obsidian and in the app's own sidebar, so a chat bubble is a
  worse way to see a page than the two windows already open.

So a card has to pass TWO tests, and reliability is only the first. The second
is "is this worth asking for?", and it is what keeps the shelf a list of things
worth suggesting rather than an inventory of the tool surface. The surface is
thirteen tools; the shelf is twelve phrasings of a different set, and the gap is
deliberate. `list_pages` and `read_page` are still tools the model uses to look
things up before it acts — that is the job they are good for.

(`list_pages` also stays in the fixed-shape matcher for a teacher who types the
phrasing anyway. The shelf is what is worth SUGGESTING; the matcher is what is
worth MATCHING; they were never the same list.)

**Keep the shelf and the matcher testable against each other.** Over here
`AssistPromptShelfView.groups` is static and a test asserts every card either
fires a fixed phrasing or appears on a hand-written list of the model-routed
ones — so a new card fails the suite until somebody has decided which kind it
is. That is the drift worth guarding: a card whose wording no longer matches
its shortcut is a button that quietly goes to the model on a shape the model
was measured getting wrong, and it looks completely normal. Group TITLES stay
in a hand-written list, because reading those from the view would only make the
test agree with the view.

One more thing the audit turned up, worth copying as a habit: an offer made
only INSIDE an answer is invisible until you have already had that answer.
"Show me the rest of the dates" lived only in the timetable reply, so a teacher
who had never asked the question had no way to know it existed. It is on the
shelf now too.

The rule for adding one:

- **No arguments in the phrasing → match it in code.** It joins the fixed
  shapes, never reaches the model, and is reliable by construction. Seven of
  the twelve cards are in this group.
- **An argument in the phrasing (a page title, a day, a time) → it must go to
  the model, so measure it before offering it.** They are what
  `research/ai-assist/shelf-phrasings-results.txt` is evidence for: routing
  140/140, arguments 60/60, ten trials each, across the fourteen probed before
  two were dropped.

### The measurement trap, which is the useful half

The first run of that suite left `AssistAgent.dateline()` off the user message.
"Publish the class on Monday" routed correctly 10 times out of 10 and then
resolved Monday to a date **a month away**, also 10 out of 10 — because a model
with no idea what day it is has to invent one. The card was within an edit of
being dropped and replaced with a hard-coded calendar date.

The harness was wrong, not the product. `AssistAgent.say` appends "(Today is
2026-08-16, a Sunday.)" to every message, and with it the same phrasing
resolves exactly. **A probe that does not send what the app sends measures
nothing — and the number it produces reads exactly like a fault in the
product.** Check your own harness sends the dateline before believing any
date-shaped result.

(From the older `trimmed-surface-suite.py`: that line must be APPENDED to the
user message. Prepending the identical text cost 15 points of routing. The
position is the finding, so do not tidy it into the system prompt.)

## What a page is CALLED, which is not what its file is called (entry 220)

Reported from a real course. Unpublishing a class printed:

```
4 linked pages stay published:
Journal Checklist  —  “index” still links to it.
Final Reflection   —  “index” still links to it.
```

Every folder in a course has an `index.md`, so "index" names eleven pages and
none of them to a teacher. The page they would go and open is the one the
sidebar calls **Portfolios**. The whole purpose of the "stays published" list
is to send somebody to the page holding a link, and a name that matches every
folder sends them nowhere.

**This is not a mac-shaped bug.** `Plantoir.Core/Assist` reads the same
folders and builds the same page graph; check both halves below.

### Half one: a label is not an identity

A page now carries two names.

- **`title`** — the file name without `.md`. This is the IDENTITY. Wikilinks
  resolve by file name and every lookup in the page graph goes through it, so
  it must never be replaced by something nicer to read. A test asserts a link
  written `[[index]]` still finds the file called `index`.
- **`displayTitle`** — what a teacher sees it called, used everywhere a page is
  named in a sentence they read: the unpublish plan, the pages that stay, date
  moves, `read_page`, `check_section`, curriculum mentions.

The rule is **copied from Quartz's own `quartz/util/fileTrie.ts`** rather than
invented, so what the assistant says and what the site's sidebar shows cannot
drift:

```ts
const nonIndexTitle = this.data?.title === "index" ? undefined : this.data?.title
return displayNameOverride ?? nonIndexTitle ?? this.fileSegmentHint ?? this.slugSegment ?? ""
```

which is, for one page: the frontmatter `title:` **unless it is literally
"index"**, then the FOLDER's name, then the file name. The "unless it is
literally index" guard is Quartz's own and is worth keeping for Quartz's own
reason — it is the one answer never worth showing anybody. The middle step
earns its place even though frontmatter nearly always answers first: a page a
teacher wrote by hand in Obsidian carries no frontmatter title at all, and
without it every folder in the course is called "index" again.

If Quartz's rule ever changes, follow it rather than re-deriving one.

### Half two: fixing only the label makes the output WORSE

This is the part to read twice, because the obvious fix is half of it.

Referrers — "which page still links to this one" — were remembered as NAMES and
looked back up in the page graph. The graph keys pages by file name. Every
folder landing page is called `index`. So the lookup returned **whichever
`index.md` the folder walk happened to reach first**, which is very often not
the one holding the link.

While the answer printed as "index" that was invisible: wrong page, right word.
Print it as a folder name and it becomes a **confidently wrong** answer. In the
regression test, the label-only fix named **Concepts** — a folder that does not
link to the page at all. A teacher sent to Concepts to find a link that lives in
Portfolios concludes the assistant is lying and stops reading the list; "index"
merely told them nothing. Useless beats wrong.

The fix is to carry the PAGE rather than its name, and to de-duplicate
referrers by PATH rather than by name — the name-based de-duplication had its
own version of the same bug, throwing away the second folder index whenever two
of them linked to one page.

**The general rule for your side:** if you key referrers, backlinks, or any set
of pages by name anywhere, `index.md` collapses them all onto one key. Go
looking for that before you touch the label, not after.

### Testing it

New contract section `shared-rules.json` → `pageNaming`: the three-step rule,
five cases drawn from the shapes a real course contains, the word that must
never be shown, and the identity-vs-label rule. Deserialise it rather than
retyping the cases.

Both end-to-end tests on this side were CONFIRMED to fail against the old code
before being kept — one against the label, one against the lookup. Do the same:
a naming test that passes against the old code is testing nothing.


## Letting a teacher choose which assistant runs (entry 219)

Until now the model tier was decided for the teacher and never mentioned:
`AssistHardwareBudget` read physical memory, picked a rung, and that was the
whole conversation. That is still the right DEFAULT and it was a poor
only-option, for two reasons arriving from opposite directions. A teacher on a
16 GB Mac who also keeps a site building, a browser full of tabs and their
notes app open may want the smaller one back — the automatic choice sizes
itself to the machine, not to what else is on it. And a teacher on an 8 GB
machine who has just closed everything may want the better one for an
afternoon of planning. Neither is knowable from `sysctl`.

The mac now has **Plantoir ▸ Settings… (⌘,)** with one pane. Windows should
have the same thing wherever that platform keeps app settings.

### What the panel offers, and the reasoning behind each part

**Three choices, not two.** "Choose for me", "The smaller assistant", "The
larger assistant". Keeping an explicit automatic option is the part most worth
copying, and it is not about politeness:

> **The automatic choice is stored as an INTENT, never resolved and written
> down.** If selecting it wrote "the larger assistant" into preferences the day
> the teacher first opened the panel, then a later change to the ladder — the
> 8 GB reconsideration written up further down this file, say — would reach
> every machine EXCEPT the ones whose teacher had once opened Settings. That is
> exactly backwards: the people who engaged with the setting get the stalest
> behaviour. `AssistModelChoice.automatic` resolves at the point of use.

**Both costs, on every option.** Download size AND memory-while-working, e.g.
"1.12 GB to download, and about 1.75 GB of memory while you are using it."
They are different decisions — disk is what runs out on a small laptop, memory
is what makes the machine feel slow and never appears as a number anywhere —
and neither is guessable from the other: on the mac the larger download is
2.2x the smaller but 2.9x the memory, because most of the difference is the
conversation being held rather than the file being read. Derive both from your
tier table; do not type them into the interface, or they will drift the first
time a quant changes.

**No model is named, anywhere.** Rule one, and the settings panel is where a
name would most naturally leak in, because it is the one screen genuinely ABOUT
the model. `AssistantSettingsTests.testNothingInThePanelNamesAModel` sweeps
every label, detail, caution and summary the panel can produce against a jargon
list; write the equivalent.

**A caution, not a block.** A hand-picked rung whose resident size exceeds a
third of physical memory shows a warning naming BOTH numbers ("This Mac has
8 GB of memory, and the larger assistant needs about 5.04 GB while it is
working…") and stays selectable.

> **Rejected: greying it out with the reason beside it.** That was the obvious
> safe option and it is worse. A teacher who has just quit everything else
> knows something the operating system does not, and a disabled row gives them
> no way to act on what they know. The third-of-memory line is not new — it is
> the same one the automatic ladder has always been held to — which is why
> "Choose for me" can never produce a caution, and a test asserts that.

**Removing one is refused while an assistant window is open**, and the message
names the section to close ("Close the assistant for ICS3U Section 2 before
removing this.") rather than saying it is unavailable — the same shape the
sidebar already uses.

> The guard is deliberately about ANY open assistant, not about whether that
> window is using that particular rung. Working out which file is genuinely
> mapped means tracking state the app does not keep, and getting it wrong
> deletes weights out from under a running engine. One open assistant, no
> removals.

**Removing the one currently in use is allowed**, and the panel then says what
happens next. It is not a broken state — it is the state every machine is in
before its first download — and the alternative traps a teacher who wants their
disk space back behind a choice they did not want to change.

### Four traps, three of them found by driving the real app

The unit tests passed while all three of these were live. They were found by
opening the panel, pressing the buttons, and looking. Budget time for that.

1. **Disk-derived answers are invisible to observation, and the failure is
   PARTIAL.** Everything the panel says about what is downloaded comes from a
   file-system call, which no observation system can see. On the mac a
   `Section`'s content, header and footer each get their own tracking scope —
   so after a removal the ROWS redrew correctly (they read an observable
   download state) while the two summary sentences in the footers went on
   describing a model that had just been deleted. Half a panel updating is far
   more convincing than none of it updating, which is why it survived review.
   The fix is a counter the panel bumps whenever it changes the disk, touched
   by every disk-derived answer. Whatever your framework's rules are, assume
   they do not cover `File.Exists`.

2. **One store per FILE, not one per place that cares.** The panel and every
   assistant window each made their own downloader for the same path. Press
   Download in Settings, then open the assistant while it runs: the second one
   sees an incomplete file, deletes it — which is the right thing to do to a
   part-finished attempt, deliberately, since resuming a mismatched range
   produces a corrupt model that fails much later somewhere less obvious — and
   starts again. Two transfers writing to one destination, on a school
   connection, for gigabytes. The mac now has a process-wide registry keyed by
   tier. Sharing also fixes the quiet half: a download started in one place is
   visible in the other, because both watch the same object.

3. **Closing the assistant window must cancel only ITS OWN download.**
   Cancelling on close is right — a teacher who shuts the window has finished,
   and leaving gigabytes coming down behind their back is not a kindness. But
   once the stores are shared, the download that window can see may have been
   started in Settings, where the entire point was to fetch ahead of time and
   get on with something else. Track who started it. An explicit Stop button is
   honoured wherever the download came from; a window CLOSING is not.

4. **The tier decides the context size, so the engine must be started with the
   CHOSEN tier, not the machine's.** This one is a straight regression the
   moment a choice exists: our server host took the tier off the hardware
   budget, so a teacher on a large machine picking the smaller assistant would
   have got the small model with the LARGE model's context window — several
   times the memory they chose it to save, which is the opposite of what they
   asked for and invisible until the machine starts swapping. Grep your own
   code for every place the tier is derived from hardware rather than passed
   in.

Also worth knowing: macOS HIDES a settings window rather than destroying it,
so the view and its state outlive every visit — a panel opened in the morning
would describe the morning's disk for the rest of the day without an explicit
look-again when the window comes forward. Check what your platform does.

### The trail

Seven new events, all in `shared-rules.json` → `activityTrail.mustRecord`, so
your suite will redden until you record them — as designed:
`app settings opened`, `assistant model chosen`, `assistant model download
started`, `assistant model downloaded`, `assistant model download failed`,
`assistant model download stopped`, `assistant model removed`.

Two of them are there for reasons worth restating. **`assistant model chosen`
carries BOTH the button pressed and the assistant it resolved to** — "chose
automatic" does not answer the question anybody asks months later, because the
answer depends on the machine and on a rule that can change. And **the stopped
line exists so that a start with no ending MEANS something**: without it,
"started downloading, nothing after" is ambiguous between a cancel and a
hang, and a hang is what somebody would go looking for.


## Asking for a Netlify or Cloudflare token (entry 253)

The first publish of a section stops on one line from the launcher:

```
Paste Netlify token:
```

Until now that line WAS the question a teacher was asked. Both apps watch the
running launcher for a prompt and put it in a dialog with a text field — so a
teacher who has never heard of an access token was shown its name, a box, and a
Send button, with nothing about where one comes from. Reported as "too terse",
and it is: the dialog contained no information the teacher did not already lack.

**What replaced it.** `CredentialRequest` (mac: `QuartzTeachers/Scripting/`)
recognises the three prompts the launchers can stop on, and each carries the
whole dialog: a title, one short paragraph saying what the credential is for
and that it is asked only once, numbered steps that produce one, a link to the
page that makes it, the field's label, and whether the answer is a secret.
`CredentialRequestSheet` renders it; `TaskProgressView` shows that sheet
instead of the plain alert whenever `ScriptRunner.pendingCredentialRequest` is
set.

**The sentences are DATA, so do not retype them.**
`contracts/app-rules.json` → `credentialRequests.requests` is a generated
readout of all three, field for field. Deserialise it into the WinUI dialog and
the two apps say the same thing forever; retype it and they diverge on the
first wording fix.

**The authored half is `credentialPrompts`**, and it is what fails when the
matching drifts:

- `cases` — six prompts and the request each produces (three real ones, three
  ordinary questions that must produce none, so a match that grew too greedy is
  caught). Windows already parses prompts in `QuestionParser.cs`; the matching
  itself is three `Contains` checks on the lowered line.
- `matchedOnWordsNotWholeLine` — match on `netlify token`, `cloudflare token`,
  `cloudflare account id`, never on the whole line. The two launchers word
  these prompts differently and are free to keep doing so.
- `whyNoBrowserOpens` — see below.

**No app and no launcher may open the token page by itself.** Both launchers
used to do it the moment they asked: `open` in `deploy.sh`, `Start-Process` in
`deploy.ps1`, three calls each. A browser tab arriving unasked, over the app the
teacher was looking at, reads as something going WRONG rather than as help —
that is the report that prompted this entry, in those words ("disconcerting").
Those six calls are already deleted, `deploy.ps1` included, and a mac test
greps both launchers for them so they cannot come back. In the dialog the
address is a `HyperlinkButton` the teacher clicks when they are ready; in a
terminal it is printed in the steps. **Do not add a "helpfully open it for
them" convenience to the WinUI dialog.** The printed instructions in both
launchers were rewritten to the same steps as the dialog, so a teacher at a
console gets the same explanation.

**Two details that are easy to get backwards.**

- A token is a secret and goes in a `PasswordBox`; a Cloudflare **Account ID is
  not**, and goes in a plain `TextBox`. Hiding the ID costs the teacher the one
  check available to them — that what they pasted is what they copied — and
  showing a token puts a live credential on a screen a class can see.
  `credentialPrompts.everyRequest` pins both, with each request's link.
- **Trim the pasted value.** A code copied out of a dashboard often carries a
  trailing space or newline, which is invisible and rejected, and the teacher is
  told their token is wrong when it is not.

**Two things in the steps that are load-bearing, not padding (entry 254).**
Both were added after a teacher walked through the real pages:

- **Expiry.** Netlify's expiry box starts at **7 days**, and an expired token
  announces nothing — publishing simply stops working a week later, which gets
  reported as the app breaking. Both token requests now tell the teacher to set
  a date after the end of their school year (next July), or "No expiration"
  where Netlify offers it. Cloudflare's `TTL` section is the same trap and gets
  the same advice.
- **Cloudflare's Account Resources.** A custom token needs `Include` + the
  teacher's own account chosen by name, in the section below the three
  permission dropdowns. A token that names no account cannot publish, and what
  comes back does not mention accounts at all — so this cannot be left to the
  teacher to infer. Verified against the live Create Custom Token page: the
  dropdowns read Account / Cloudflare Pages / Edit, then Account Resources,
  then TTL.

Both notes are in `credentialPrompts.expiryAdviceIsLoadBearing`, and a mac test
asserts the strings "7 days", "school year", "TTL" and "Account Resources"
survive in the steps — so a future tidy-up cannot quietly drop them.

**The Account ID also has a button, and it needs the same one on Windows
(entry 254).** The Cloudflare Account ID field — in Course Settings AND in the
new-course wizard, which on the mac is one shared view — now has a **"Where do
I find this?"** link button under it, opening the same kind of dialog on
purpose rather than mid-publish. Three things about it:

- It is a SECOND request, `cloudflareAccountIDHelp`, sharing **one** list of
  steps with the launcher-driven `cloudflareAccountID` and differing only in
  the explanation. Copy the steps into two places and they drift; the mac keeps
  them in `CredentialRequest.accountIDSteps` and a test pins the two equal.
- **It must never be returned by the prompt matching** — see
  `credentialPrompts.theHelpVariantIsNeverMatched`. It can be opened by
  somebody who has not made a token yet, so its twin's "the token you just
  made" would be a lie; equally, its calm "you enter it once here" is wrong
  when a publish is paused waiting for an answer.
- What the teacher types in the dialog is **written back into the form field**,
  so a teacher who has just fetched the code does not have to close the dialog
  and find the field again. The accept button is labelled "Use this ID" rather
  than "Continue", because nothing is waiting on it.

The grey caption under that field is GONE, not reworded: it carried the
dashboard directions in four lines of small text under a field that wants one
code, shown whether or not anybody had a question, and the button answers the
same question on request. The two ORANGE notes stay — what is wrong with the ID
that was typed, and Cloudflare's 25 MB per-file limit — because one says why the
course will not save and the other is the single real functional difference
between the destinations. The button carries a `safari` symbol to the LEFT of
its text, the same mark the dialogs put on their links, so anything that leaves
the app looks the same everywhere. On WinUI: a `HyperlinkButton` with the
equivalent glyph under the Account ID `TextBox`, the same dialog, the value
written back on accept — and, still, nothing that opens a browser by itself.

**The trail.** `asked for a publishing credential` is in
`contracts/shared-rules.json` → `activityTrail.mustRecord`, so the Windows
pinning test fails until that enum case exists. It records WHICH credential was
asked for and never the answer. It is there because a first publish waiting
behind a dialog nobody noticed is reported as a publish that "never finished",
and this line is the difference between reading that as a hang and reading it
as a question waiting. The same event covers a teacher opening the Account ID
instructions from the button — the line says which credential they went looking
for, which is the same question being answered a different way round.

**Teacher Surname & Site Name Dialogs (entry 260).**
The same `CredentialRequest` model and `CredentialRequestSheet` dialog are used
when `scripts/deploy.py` asks for the teacher's surname on first deploy or when
choosing a Netlify/Cloudflare subdomain:

- `teacherSurname` (`isSecret: false`, `linkAddress: null`): explains why the surname
  is needed (to create recognizable website addresses like `mcv4u-s1-2026-gordon`
  and prevent collisions across classes), saved once on the machine. Matched on
  prompts containing `"last name"` or `"surname"`.
- `siteName` (`isSecret: false`, `linkAddress: null`): explains that website addresses
  on Netlify and Cloudflare Pages are shared globally and must be unique. Outlines
  suggested naming patterns (`<course>-s<section>-<year>-<surname>`, `<school>-...`).
  Matched on prompts containing `"enter netlify site name"`, `"netlify site name"`,
  or `"website name"`.
- `siteNameConflict` (`isSecret: false`, `linkAddress: null`): presented when a chosen
  address is already taken, guiding the teacher to append a numeric suffix or school initials.
  Matched on prompts containing `"choose a different netlify site name"`.
- **Pre-filling suggested answers**: `TaskProgressView` passes `runner.suggestedAnswer`
  (e.g., extracted from brackets `[mcv4u-s1-2026-gordon]`) as `initialAnswer` into the dialog,
  so the teacher can accept the recommendation with a single press or edit it.
- **Link button visibility**: `CredentialRequestSheet` only renders the link button if
  `linkAddress` is present and `linkTitle` is non-empty.

All requests are serialized in `contracts/app-rules.json` → `credentialRequests.requests`.

## Task cancellation and duration explanation in TaskProgressView (entry 271)

Previewing and deploying can take significant time on first run (building the local engine image, installing dependencies, performing full compilations, or uploading initial sites). Teachers can now cancel a preview or deploy mid-flight from the GUI, and see a plain-language explanation of why a task might take a while.

### 1. Cancel button & avoiding orphan processes

- **UI Placement**: A bordered `Cancel` button sits in the bottom-trailing corner of `TaskProgressView`, below the progress bar and step description. It is visible only while `runner.isRunning` and `!runner.wasCancelled`.
- **Signal Handling (Control-C)**: Rather than abruptly killing the shell process (which would orphan child commands like `docker buildx` or `wrangler`), `cancelByUser()` writes `\x03` (`Control-C`) into the pseudo-terminal (`PseudoTerminal` on macOS, `ConPTY` / `PtyDriver` on Windows). This delivers `SIGINT` to the foreground process group and lets scripts run their cleanup traps.
- **Safety Timeout**: If the process has not terminated within 2 seconds of the interrupt, direct process termination is invoked.
- **Container Cleanup**: `cancelPreview()` and `cancelDeploy()` call `PreviewStopper.stopSectionProcesses(...)` (`preview.ps1 CODE N -Stop` on Windows), which finds and terminates any container processes running in `.merged_output/sectionN`.
- **Outcome Status**: Cancelling marks `wasCancelled = true` and `wasStoppedByUser = true`. `TaskProgressView` shows the orange `Cancelled` badge and `"<Title> was cancelled."`, and the run is not reported as an error.

### 2. "Why might this take a while?" popover

Below the milestone label on the leading side, a subtle `Why might this take a while?` button with a `questionmark.circle` icon opens a popover / flyout displaying four plain-language bullet points (strictly adhering to Rule 1 — no "Docker", "container", "Colima", "toolchain", "Node", or "npm" jargon):
- **First-time setup**: Getting everything ready for the first time takes a couple of minutes to set up your website builder. Future previews and deploys will be much faster (usually just a few seconds).
- **First-time publishing**: Uploading your entire website for the first time takes a bit longer. Future publishes only upload the pages you’ve changed.
- **Photos and attachments**: Courses with many images, documents, or media files take extra time to prepare and upload.
- **Internet connection**: When publishing online, upload speed depends on your current internet connection.

On Windows: implement as a WinUI `Flyout` or `TeachingTip` triggered by a `HyperlinkButton` or subtle button with a matching question mark icon.


## The hide filter belongs to the IMAGE, not to a running container

Fixed 2026-08-17. **Shared Python and a shared Dockerfile, so Windows inherits
the fix with nothing to port** — but read this anyway, because the shape of the
bug is one that can be reintroduced from either side.

A teacher marks pages hidden — Private Notes, Curriculum, Learning Goals — and
the Explorer honours that through a `filterFn` in `quartz.layout.ts` carrying a
`CQ4T-OMIT-ANCHOR` marker. `build_site.py` only ever rewrites the CONTENTS of
the `omit` Set inside that filter. It cannot create the filter.

The filter used to be established in exactly one place: `setup_course.py`
patching `/opt/quartz/quartz.layout.ts` **in the running container**, at
course-creation time. That made it container state. And a container is
recreated whenever the recipe hash changes — which is the documented design
after most toolchain updates. So:

1. Teacher's courses work; the container carries the patch.
2. An update changes the recipe. New image tag, container recreated.
3. Next preview copies a pristine `/opt/quartz` scaffold. No filter.
4. `build_site.py` warned twice and **carried on**, injecting a bare
   `const omit = new Set([])` "to unblock the build". The Set was then
   populated and nothing consumed it.
5. Build succeeded. Everything the teacher had hidden went up on the class
   site.

Verified rather than reasoned about: `docker run --rm <image> grep -c
CQ4T-OMIT-ANCHOR /opt/quartz/quartz.layout.ts` returned **0** before the fix
and **2** after.

### What changed

- **The Dockerfile bakes it in**, right after `scripts/` is copied, by calling
  `setup_course.ensure_quartz_explorer_anchor()` — the same function setup
  uses, imported rather than copied so the two cannot drift — then asserting
  the marker is present and mirroring the result into `/opt/quartz-site`. A
  container now has the filter from birth.
- **`build_site.py` repairs instead of papering over.** If the marker is
  missing it injects the real anchored Explorer block (again the same function),
  so containers predating the fix self-heal on the next build.
- **A build that cannot establish the filter now REFUSES.** `sys.exit(1)`, with
  a sentence saying why: anything hidden would otherwise be published. The old
  behaviour — warn, continue, publish — is the thing that made this invisible
  for as long as it was.

### The rule worth keeping

**Anything that decides whether students can see something belongs in the
image, and its absence must stop a build.** Not in container state, which
disappears; and never behind a warning, because the failure is silent and the
consequence is a teacher's private notes on a public site. If a future change
adds another such guard, it goes in the Dockerfile and it fails closed.


## The three one-time-setup explainer cases are retired (2026-08-20)

Answering the request in `MAC-HANDOFF.md` rather than leaving it half-done:
the mac implemented ONE of the two failure-explanation cases proposed from
that side and **retired the other three**.

- **Implemented here**: the teacher-made-link case. `FailureExplainer.swift`
  now recognises `untrusted mount point` and says the contract's sentence,
  checked first exactly as `FailureExplainer.cs` checks it. The output cannot
  occur on macOS; the mapping exists so the two explainers stay one list of
  troubles rather than growing a platform switch, which is the reasoning the
  proposal itself gave.
- **Retired**: "needs to restart to finish getting ready", "Windows permission
  was declined", "Windows could not add the feature this needs". They are gone
  from `contracts/app-rules.json`. The proposal named this outcome as
  conditional on `windows-native-toolchain` merging; it merged, the container
  path went with it, and no shipping launcher prints those lines any more.
  They survive only in 1.0.2, whose launchers are frozen and whose app already
  recognises them.

**What that means for `SetupExplanation` in `Plantoir.Core`.** It is no longer
pinned by anything. Delete it when the launcher code that produced those lines
goes, rather than keeping the only implementation of a rule nothing tests — a
matcher for output nothing can print reads, to the next person, as a live code
path.

**And one difference the sync found but did not close.**
`FailureExplainer.cs` recognises a folder-access failure ("Plantoir couldn't
read every file in this working folder…") that the mac has never recognised
and no contract case pins — so the two apps genuinely differ here and nothing
would catch it. It was left alone on purpose: the sync was a release
qualification, and adding a sentence would have made the mac's build a
behaviour change. If that explanation is worth having, propose the case and
let both suites go red; that is the mechanism working.


## Every built site wears the Plantoir icon, not Quartz's

Added 2026-08-20, merged to `dev` 2026-08-21 — after the Windows container was
retired, so the delivery half of this is written against the runtime that
actually exists on that side now.

**Shared Python and shared assets: nothing to port.** Both halves already
reach Windows by routes that were built before this feature existed —
`Vendor/fetch-runtime.ps1` copies `patches/Head.tsx` into the bundled Quartz
scaffold exactly as the Dockerfile does for the container, and
`Plantoir.csproj`'s `..\..\support\**` glob carries `support/favicon/`
unfiltered. Two parts are still worth knowing, because one is a trap and one
is an asymmetry you cannot fix from your side.

Until this, every class site a teacher published showed **Quartz's logo** in the
browser tab. Quartz ships `quartz/static/icon.png` and its `Head` links that as
the favicon; nobody had replaced it. A teacher who publishes four sections had
four tabs wearing somebody else's mark.

### What is in the site now

`support/favicon/` holds four generated files, baked into the image by the
existing `COPY support/ /opt/support/`, and `build_site.py`'s
`install_favicon()` copies them on **every** build (not only a full rebuild, so
folders built before this heal themselves):

| File | Where it goes | Who reads it |
|---|---|---|
| `icon.svg` | `public/static/` | Every current browser. Sharp at any size. |
| `favicon.ico` | `public/static/` **and `public/`** | Older Safari; Windows shortcuts. 16/32/48, BMP entries. |
| `apple-touch-icon.png` | `public/static/` | iOS "Add to Home Screen". 180x180, square, opaque. |
| `icon.png` | `public/static/` | Nothing links it. It overwrites Quartz's, so the site carries no Quartz logo even unlinked. |

`patches/Head.tsx` links the first three, in that order, with paths relative to
the page (`baseDir`) so a site served from a subfolder still finds them. Order
is load-bearing: a browser takes the LAST icon it understands, so the `.ico`
goes first and the SVG wins wherever it is supported.

### The trap: there are two emitters, and only one can write to the root

`favicon.ico` is installed **twice**, and the second copy is not redundant.

- Quartz's **Static** emitter copies `quartz/static/` to `public/static/`. That
  is where the `<link>` tags point, and it covers every browser that reads the
  page.
- Nothing that emitter can do puts a file at `public/favicon.ico`. The only
  route to the site ROOT is the **Assets** emitter, which copies every
  non-Markdown file out of `content/` into `public/` unchanged. So
  `install_favicon()` also drops `favicon.ico` into the content root — which is
  why the call sits AFTER the content folder is rebuilt from scratch, not in
  the ALWAYS block above it. A copy made any earlier is deleted a few lines
  later and the failure is invisible: the page still looks right, and only the
  implicit `GET /favicon.ico` that feed readers, link unfurlers and older
  browsers make (without reading the page at all) comes back 404.

**The source folder is resolved through `toolchain_paths.SUPPORT_DIR`**, not a
hard-coded `/opt/support`. That was corrected when this merged: it was written
while Windows still ran in a container, and a literal `/opt` would have found
nothing natively — the site would have built cleanly, said nothing, and worn
the Quartz logo. Anything else that reaches for a bundled file belongs on the
same shim.

`verify.sh` now asserts both halves separately — the four files exist, the root
`favicon.ico` and `static/icon.png` are byte-identical to `support/favicon/`,
and `index.html` links all three. It is a mac-only gate (bash, and it expects
`docker`), so on Windows the equivalent is to publish a section and look at the
tab. A site can have every file and still show the
Quartz logo if `patches/Head.tsx` did not make it into the image, so
`check_baked patches/Head.tsx` was added at the same time (it had never been
checked).

### The asymmetry: the favicon can only be regenerated on the mac

The artwork's source of truth is `mac-app/Plantoir.icon` — the Icon Composer
bundle, mac-only. `scripts/brand_images.py` reads the plant's SVG path straight
out of it and draws every image that carries the mark, the favicon included, so
the mark cannot drift between the social card, the profile avatars and the
browser tab. It needs only Pillow, but it needs that `.icon` folder, so
**a Windows session cannot regenerate the set** — the same direction as
`--write-contracts`. Treat `support/favicon/*` as data you receive. If the app
icon changes, that is a mac task, and the Windows `.ico`
(`windows-app/Plantoir/Assets/make-icon.ps1`) is a separate regeneration from a
1024 export, exactly as it is today.

### The favicon IS the app icon, and that was a decision

Not a reinterpretation of it. The raster sizes are literally `icon_tile()` —
the same function that draws the tile on plantoir.app's social card — so the
favicon cannot come to disagree with the icon in the Dock: same ramp, same
0.703 glyph scale, same viewBox centring, same drop shadow, same
regular-weight outline with the leaf counters open. `favicon_svg()` is that
tile written out as vector, reading the same constants rather than typing the
numbers again.

**This was tried the other way first, and reverted on Russell's call.** The
first version used the **fill** weight of the same glyph — `plant.svg` is three
subpaths (the silhouette, then the two leaf counters), so dropping the last two
gives a solid plant for free. The argument was legibility: at 16 physical
pixels the outline's leaf midribs land on the outline and the mark goes muddy,
which is measured rather than assumed. The argument that beat it is simpler —
**looking like the app icon is the point of the app icon.** Record that
direction, because the legibility case is genuinely tempting and will be made
again.

If it ever does need revisiting, two dials exist and one trap:

- `render_glyph`'s **`bold_units`** thickens the outline in viewBox units
  without changing the drawing. The Instagram avatar already uses it (3.0) for
  exactly this reason — it is stored at 320 and shown at 32.
- The **`.ico` can carry a different drawing per size**, since each entry is a
  separate bitmap, and `write_favicons` already renders each size natively.
- The trap: **`icon.svg` cannot.** Browsers that support it render THAT at
  whatever size they choose, so a per-size tactic that only touches the `.ico`
  leaves Chrome and Firefox unaffected. And 16 physical pixels is a Windows tab
  at 100% scaling — any Retina Mac asks for 32.

One thing rejected outright: **darkening the green for contrast.** The brand
green on the cream tile is about 3:1. The answer to a thin stroke is a thicker
stroke, not a different colour, and the colour is not ours to change here.

There is deliberately **no web manifest and no 192/512 PWA icon set**. That is
Android home-screen and installable-app territory, not a favicon, and the
teacher's site is neither.

## Suppressing Netlify's own ad badge (entry 301)

Netlify can inject a "Powered by Netlify" badge — and a matching pre-launch
toolbar — into any public site on a free-tier project. Confirmed live
2026-08-21: their own rollout table has free-plan projects created
2026-08-19 or later default it **ON**. Every class site this project
publishes to Netlify was about to start wearing an ad in front of students,
with no code involved and nothing here to notice it happening.

**There is no API lever.** Netlify's published OpenAPI spec
(`https://raw.githubusercontent.com/netlify/open-api/master/swagger.yml`,
6,074 lines, read in full) has nothing named `badge`, `powered_by`, or
`premium` anywhere on the `Site` object. The only documented control is a
per-project dashboard toggle — Project configuration → General → Powered by
Netlify badge — which does not scale to hundreds of teachers' class sites
and cannot be driven by `deploy.py`'s existing REST calls.

**The one automatic lever Netlify itself documents**: the badge only
executes through an inline `<script>` their edge injects into the response
HTML, and a Content-Security-Policy whose `script-src` omits
`'unsafe-inline'` makes the browser refuse to run it —
<https://docs.netlify.com/manage/projects/powered-by-netlify-badge/> states
plainly that "Neither the badge nor the pre-launch toolbar appears, and no
other project functionality is affected."

### The risk that had to be ruled out first

A blanket `script-src` restriction is only safe if the site's OWN inline
scripts still work. Before writing a line of the fix, a real built site
(`courses/EXC2O/.merged_output/section1/public/`, 294 pages) was checked
directly:

- The dark-mode-before-paint script — the one that matters most, since
  getting it wrong means every page flashes the wrong theme — is already
  **external** (`prescript.js`). Safe.
- Search, graph view, the SPA router — all external (`postscript.js`). Safe.
- Quartz DOES emit 3 inline `<script>` blocks per page: a search-index
  prefetch trigger (content varies only by folder depth — a handful of
  variants), a callout-collapse handler, and a Mermaid pan/zoom script (the
  latter two byte-identical on every page). None embed secret or
  teacher-specific data.

### The design, and what was rejected

`write_netlify_headers_file()` (in `scripts/deploy.py`) scans the ACTUAL
built `public/` folder at deploy time — every `.html` file, every unique
inline `<script>` body, SHA-256-hashed, plus any cross-origin
`<script src="https://…">` host — and writes `public/_headers` with a policy
built from what is really there:

```
/*
  Content-Security-Policy: script-src 'self' 'sha256-…' 'sha256-…' … https://cdn.jsdelivr.net;
```

Only `script-src` is set, never `default-src` — nothing else about a page
(images, fonts, styles, network requests) is touched. It runs on the
Netlify path only (Cloudflare Pages and `local_folder` don't have this
badge), right after any production rebuild and right before the
delta-deploy manifest is built, so `_headers` rides along in the same SHA-1
manifest as every other file — no separate upload step.

Two designs were considered and rejected:

1. **A hardcoded hash allow-list for Quartz's own known scripts.** Rejected
   because it goes stale the moment Quartz's bundling changes on a version
   bump — a silent breakage discovered only when a teacher reports a dead
   page — and it does nothing for a teacher who pastes their own
   `<script>` into a note for some embed. Scanning the real build handles
   both automatically, at the cost of nothing more than a directory walk on
   an already-built site.
2. **Patching Quartz's TSX components so every inline script becomes an
   external file**, matching what already happens for `prescript.js`
   (`patches/Head.tsx` filters resources by `loadTime` and only THAT
   resource gets rendered `src=`). Rejected because Quartz's source isn't
   vendored here — it's cloned fresh at Docker build time
   (`Dockerfile:27`) — so this would mean chasing down, in upstream
   TypeScript this repo doesn't keep a copy of, whichever components emit
   the callout-collapse and Mermaid scripts, and re-verifying the patch on
   every future Quartz version bump. The scanning approach needs none of
   that: it observes output, not implementation.

Deterministic build to build (same content ⇒ same hashes ⇒ same file),
which is the same property `documentation/07-deployment.md`'s "Why
determinism matters" section already requires of everything else in
`public/`, for the same delta-deploy reason. Verified against the real
Example Course build: 5 unique inline-script hashes (2 static, 3 folder-depth
variants of the search-prefetch trigger), 1 cross-origin host
(`cdn.jsdelivr.net`, KaTeX's autorender script).

Tested in `scripts/test_deploy_netlify_headers.py` — pure stdlib, no Docker,
no network — and wired into `verify.sh` as a fast pre-check that runs before
the (slow) image build, so a broken change here fails in milliseconds.

A teacher who clicks "Show details" during a deploy sees plain-language
lines explaining what this step is doing and that it checked the site's own
scripts first, so it reads as something deliberate rather than as
unexplained new console noise.

**Cloudflare Pages pays nothing for a problem that's Netlify's alone**
(confirmed 2026-08-21, in response to exactly this question). It was
already true by construction — `main()`'s `if args.target == "cloudflare":`
branch calls `publish_to_cloudflare()` and returns before reaching the
Netlify site lookup, the token check, or the badge-suppression call, and
`local_folder` never invokes `deploy.py` at all — but that guarantee rested
only on code ORDER, silently, so `CloudflareIsNeverTouchedTests` in
`scripts/test_deploy_netlify_headers.py` now pins it structurally: one test
asserts the cloudflare branch's `return` appears before the
`write_netlify_headers_file()` call site in `main()`'s source, a second
asserts `publish_to_cloudflare()`'s own source never mentions that
function at all. A future refactor that moves badge suppression earlier
fails these tests instead of shipping a silent regression. This also keeps
Cloudflare a clean control group on purpose: deploying identical content to
both destinations is a direct way to check whether a suspected site
breakage is caused by this feature rather than by the build itself.

**Shared Python — nothing to mirror.** Windows inherits this the moment
`deploy.py` is next synced; there is no C# equivalent to write.

**Update 2026-08-21: this now also covers plantoir.app.** The marketing
site (`website/`) is a second free-tier Netlify project exposed to the
identical badge, with its own deploy path (`website/netlify_deploy.py`, run
via `python3 website/build.py --deploy`) that has nothing to do with either
app. Rather than duplicate the ~90 lines of scanning logic a second time,
`_collect_inline_script_policy()` and `write_netlify_headers_file()` moved
out of `deploy.py` into a new sibling module, `scripts/netlify_badge.py`,
with `deploy.py` re-exporting both names so its own call site and
`scripts/test_deploy_netlify_headers.py` (which does `import deploy` and
calls `deploy.write_netlify_headers_file`) are unchanged. `netlify_deploy.py`
imports the same module by adding `scripts/` to `sys.path` — the identical
trick `deploy.py` already uses for `toolchain_paths` — and calls it on
`site/` right before its own delta-deploy manifest is built, mirroring
where `deploy.py` calls it on `public/`. Covered by
`scripts/test_netlify_badge.py` (the module in isolation, plus an identity
check that `deploy.py`'s re-export is the same function object) and
`website/test_netlify_deploy_headers.py` (the wiring, against a temp folder
standing in for `site/`).

This is host/CI-side Python only — not part of either app — so it is an
**awareness note, not something to port**: there is no C# equivalent to
write here either, on either side of this update.

## The Dockerfile never picked up netlify_badge.py (entry 302)

Row 301's badge-suppression CSP scans the built site and hash-allows every
inline `<script>` it finds, but the scanning logic itself lives in a
sibling module, `scripts/netlify_badge.py`, that `deploy.py` imports by
bare name. The Dockerfile's `COPY` list for `/opt/scripts` is explicit,
one line per file — `toolchain_paths.py`, `setup_course.py`,
`build_site.py`, `deploy.py`, `social_card.py` — and never gained a line
for the new module. Every real deploy through the container (Netlify or
the marketing site) failed outright with `ModuleNotFoundError: No module
named 'netlify_badge'`.

**Why the unit test never caught it**: `scripts/test_deploy_netlify_headers.py`
and `scripts/test_netlify_badge.py` both import `deploy`/`netlify_badge`
directly from the working tree, where the sibling file is right there on
disk regardless of what the Dockerfile does — they exercise the SCANNING
LOGIC, never the actual built image. Only a deploy through the real
container hits the gap, which is exactly the class of bug `verify.sh`'s
slow, Docker-dependent checks exist to catch and the fast host-side
pre-checks structurally cannot.

**The fix**: one `COPY scripts/netlify_badge.py /opt/scripts/netlify_badge.py`
line in the Dockerfile, plus the matching `check_baked` line in
`verify.sh` — which had the identical gap itself: it compares every other
baked script against the working tree, but had never been taught about
this one, so the image could go stale here again with the gate staying
green throughout.

**What Windows needs from this**: nothing to port directly (shared
Dockerfile, shared `verify.sh`), but the LESSON is worth keeping in mind
if Windows ever adds its own per-file bundling list for the native
runtime's scripts (`Vendor/fetch-runtime.ps1` or similar) — an explicit
per-file list is exactly the shape that silently misses a new file added
elsewhere; a folder-reference or manifest-driven copy does not have this
failure mode.

## unsafe-eval had to join the Netlify CSP, or every sidebar goes empty (entry 303)

Row 301's badge-suppression CSP — `script-src` with hash-only sources, no
`'unsafe-inline'` — silently broke Quartz's own Explorer SIDEBAR on every
page of every site deployed to Netlify. `patches/explorer.inline.ts`
builds its sort/filter/map functions from `data-data-fns` JSON via
`new Function("return " + source)()` — a capability `'unsafe-eval'`
governs, not a script identity, so hash-allowing every actual inline
script (which row 301 already did correctly) never touched it.

**Found by A/B testing a real deploy** to both Netlify and Cloudflare
Pages side by side: Netlify's sidebar rendered "Navigate this site" with
an empty list underneath; Cloudflare (no CSP at all) showed the full
tree. Reproduced in a fresh PRIVATE Safari window first, to rule out
leftover `localStorage` from earlier testing on the same site name — the
bug survived that, so it was real. Confirmed definitively via the
browser's own console, reached with Safari's `do JavaScript`: "Refused to
evaluate a string as JavaScript because 'unsafe-eval' ... is not an
allowed source of script."

**The fix**: add `'unsafe-eval'` to the policy in `netlify_badge.py`.
`'unsafe-eval'` and `'unsafe-inline'` are INDEPENDENT CSP keywords —
Netlify's own docs confirm the badge needs `'unsafe-inline'` specifically
("the script runs in an inline frame"), so this does not let the badge
back in. A new test pins both facts at once: `'unsafe-eval'` present,
`'unsafe-inline'` still absent.

**What Windows needs from this**: nothing to port (shared Python, inherited
the moment `netlify_badge.py` is next synced), but the same TRAP is worth
naming for whoever next writes a restrictive CSP anywhere in this project:
hash-allowing every inline `<script>` proves the SCRIPTS are allowed to
run, not that everything THOSE scripts try to do is still permitted —
`eval`/`new Function`/`setTimeout(string)` are a separate capability
(`'unsafe-eval'`) that a hash-only policy blocks by default, and nothing
about "I scanned every inline script" catches that on its own.

## Redundant deploy targets — piece 1: schema and configuration (entry 304)

Motivated directly by the Netlify ad-badge fix (its own entry 301, on the
`issue/netlify-badge-suppression` branch): if a host has a bad day, real
redundancy needs a second copy of the site ALREADY live, not a scramble to
reconfigure a new destination after the fact. Russell pushed back on the
first design sketched for this (a chevron on the Deploy button to pick a
*different* single destination) — that is a faster manual redeploy, not
redundancy, since nothing keeps a second destination current until someone
notices a problem and switches. The corrected design: **a course can
configure more than one deploy destination, and deploying publishes to
every configured one.**

This is piece 1 of 2, done: **the config schema and the wizard/settings UI
to configure additional destinations.** The Deploy button itself is
UNCHANGED — it still publishes to `deployTarget` (the primary) only. Piece
2 (not started) teaches it to publish to every configured destination.

### The schema

```json
{
  "deploy_target": "netlify",
  "additional_deploy_targets": [
    { "type": "cloudflare_pages" },
    { "type": "local_folder", "path": "/Users/teacher/Sites" }
  ]
}
```

`deploy_target` is unchanged — same key, same meaning, same default. The new
`additional_deploy_targets` key is an array of `{type, path}` objects,
`type` using the identical spellings as `deploy_target`; `path` is present
only for a `local_folder` entry (Netlify's and Cloudflare's credentials
live in per-teacher app settings already, not per-course, so neither needs
one). **Omitted entirely — never written as `[]` — for every course that
has not opted in**, which is the overwhelming majority: the file an
untouched course writes is byte-identical to what it always wrote. This
was the whole point of "the default remains pick one."

**One of each of the three known types, maximum, never two of the same
type.** A destination can never be listed as both primary AND additional at
once. That invariant lives in exactly one place —
`CourseConfiguration.pruningAdditionalTargets(_:ofType:)`, a plain static
function, not a method on an instance — called from two call sites that
need it for different reasons:

- `CourseConfiguration.deployTarget`'s own setter, so Course Settings
  (which binds its picker straight to the live model) can never reach the
  inconsistent state.
- `PublishingChoiceView`'s picker `onChange`, so the WIZARD's plain
  `@State` — which has no `CourseConfiguration` to route through until the
  course is actually created — gets the identical guarantee live on
  screen. `NewCourseWizardView.buildConfigurationDictionary()` also prunes
  once more, defensively, at the point it actually writes the file, so the
  file on disk is correct even in a hypothetical future case where the
  view's own `onChange` did not fire before Create was clicked.

A plain function was chosen deliberately over an instance method so it is
testable without standing up either a live model or a rendered view — see
`AdditionalDeployTargetsTests.testPruningAdditionalTargetsDropsOnlyTheMatchingType`.
The first version of that test tried to exercise this by mutating a plain
property on the `HeldPublishingChoice` test harness and expecting the
pruning to have happened — it silently could not, because
`HeldPublishingChoice` is a plain class with no logic of its own, and
`.onChange` only fires on an actually-rendered SwiftUI view. The test would
have passed for the wrong reason if the assertion direction had been
different; testing the plain function directly is the fix, not a
workaround.

### The UI

`PublishingChoiceView` — already shared by the wizard and Course
Settings — gained a new section below the existing primary picker: "Also
publish to, for redundancy", with one `Toggle` per known type that is not
the current primary. Each toggle, switched on, reveals the SAME detail
fields (Cloudflare Account ID + help + 25 MB caption, or the folder field +
Choose… button) that the primary picker's own conditional block shows for
that type — factored out into two `private` subviews
(`CloudflareDetailFields`, `LocalFolderDetailFields`) so the primary and
additional cases read from one definition each and cannot drift apart.
They are never on screen at the same time for the same type, by
construction — `availableAdditionalDeployTargetTypes` already excludes
whichever type is primary.

**A toggle that is already on does not disappear from the list.** The
first test written for "all three slots filled" assumed the additional
list would show only types NOT yet added, and asserted it went empty once
all three were configured — that is wrong for a toggle list: every other
toggle in this app stays visible and shows its own state, and a
redundancy toggle that vanished the moment you turned it on would be the
one control that did not. Fixed the test, not the view.

**Validation matches the primary's, for the same reason the primary's
exists**: an additional Cloudflare target with no Account ID, or an
additional local-folder target with no valid path, blocks Save/Create —
exactly like the primary case already does — rather than failing silently
the first time piece 2 actually tries to deploy to it. Both the wizard's
`validate()` and Settings' `savingProblem` gate loop over
`additionalDeployTargets` with the identical two checks the primary
already ran.

### What Windows needs from this

`windows-app/Plantoir.Core/Models/CourseConfiguration.cs` needs the
equivalent `AdditionalDeployTargets` property, with the identical
omit-when-empty write rule (checked by
`AdditionalDeployTargetsTests.testWritingAnEmptyAdditionalTargetsListOmitsTheKeyEntirely`
on the mac side — port that assertion, it is the one easy to get wrong).
`windows-app/Plantoir/Views/PublishingChoiceView.cs` needs the equivalent
toggle section. **Piece 2 (below) has now shipped on the mac** — Deploy
really does publish to every configured destination there now, so a
`course_config.json` written by a Windows teacher with `additional_deploy_
targets` set, opened on the mac, would now actually redundantly deploy —
which makes this genuinely urgent rather than a someday item: a Windows
teacher who cannot configure a second destination is simply missing the
feature, and a Mac teacher's config edited on Windows (schema written, but
never acted on there) is a real cross-platform inconsistency, not a
hypothetical one.

**Update (2026-08-22, Windows): implemented.** `CourseConfiguration.
AdditionalDeployTargets` (plus `DeployDestination`, `AllDeployDestinations`,
`PruningAdditionalTargets`, and the rest of the static helpers the mac's own
instance methods delegate to) carries the identical omit-when-empty rule,
and `PublishingChoiceView.cs` gained the "Also publish to, for redundancy"
toggle section, shared by both Course Settings and the wizard exactly as on
the mac. Full write-up: `MAC-HANDOFF.md`, "Done" ledger.

## Redundant deploy targets — piece 2: Deploy publishes to every
configured destination (entry 305)

Piece 1 (above) built the schema and the settings UI; this is where Deploy
itself changed. A course with no additional destinations configured — the
overwhelming majority — behaves **exactly** as it always has: same single
console, same progress bar, same "Live URL" link, same wording, byte for
byte. A course with 2–3 configured destinations now gets an actual
redundant deploy: each destination gets its own `deploy.sh` run, in
sequence, and one failing does not stop the others.

### Why sequential, and why one `ScriptRunner` per destination

Both were open questions when this was designed (see the earlier
conversation in this repo's history) and both were decided explicitly,
not defaulted into:

- **Sequential, not parallel**, for this first version. Netlify already
  rate-limits aggressively on CONCURRENT uploads within a single
  destination's own file transfers (measured and documented in
  `documentation/07-deployment.md`'s "Rate limiting" section) — running
  two or three destinations' uploads at once, each already juggling its
  own concurrency, was judged too much unknown interaction for a first
  version. Nothing about the design prevents parallelizing later if it
  proves worth the complexity.
- **One `ScriptRunner` per destination, never one shared runner reused
  across legs.** This was the single most important implementation
  decision, because the wrong choice fails SILENTLY. `ScriptRunner`'s
  `publishedSiteURL(in:)` / `publishedFolderURL(in:)` only ever scan
  THAT runner's own transcript tail. Route two destinations through one
  reused `ScriptRunner` (even with `keepingTranscript: true`, which is
  what makes a build-then-deploy pair read as one console today) and the
  SECOND destination's "Live URL:" or "PUBLISHED_FOLDER=" line silently
  overwrites the first's — the teacher would see only the last
  destination's link, with the first one's simply gone, no error anywhere.
  `MultiDestinationDeployRunner.Leg` gives each destination its own
  runner specifically to avoid this.

### The build happens exactly once

`BuildFreshness.needsRebuild` is checked ONCE, before the destination
loop starts — never per destination. If the site is stale, the FIRST
destination's own run gets the combined build-and-deploy milestone list
(`TaskMilestones.buildAndDeploy` / `.buildAndDeployToCloudflare` /
`.buildAndDeployToFolder`, exactly the lists that already existed for the
single-destination case) via `keepingTranscript: true`, so the build and
that leg's deploy still read as one console, exactly as today. Every
SUBSEQUENT destination always uses the deploy-only milestone list — by
the time leg 2 runs, the site is already current. A failed shared build
stops the WHOLE run (`Leg.buildFailed`) rather than letting every
remaining destination deploy the same stale content, which would not be
redundancy, it would be the same mistake published twice.

### One sequencer, four callers

`MultiDestinationDeployRunner.run(...)` is called from all four places a
deploy can start, so none of them can drift the way `DeployCommand.
arguments` itself once warned against (built separately in two places, one
silently sent a Cloudflare course to Netlify):

1. `SectionDetailView.deployAndWait()` — the toolbar button, and the
   assistant when a section window is open (same choke-point as before).
2. `AssistToolchainWork.deploy()` — the assistant with no window on
   screen (Claude Code over MCP, or a scheduled deploy invoking the app
   headlessly).
3. `ScheduledDeploy.oneShotCommand(...)` — NOT a Swift caller of the
   sequencer at all, since this path runs unattended with the app closed.
   Instead, `scheduleDeploy(...)` now builds one `deployArgumentsList`
   entry per destination (`CourseConfiguration.allDeployDestinations`,
   same order as the other three callers) and `oneShotCommand` bakes ONE
   shell line per destination into the generated script, none chained
   with `&&` — a destination failing must not stop the others' shell
   lines from running, the shell-script equivalent of the Swift
   sequencer's own "one leg failing doesn't stop the loop" rule. Only a
   failed BUILD (`$READY`) still skips every deploy line, matching the
   Swift side's `Leg.buildFailed` early-exit.
4. `ScheduledDeploy.problem(...)` — the pre-flight refusal check, run
   when the teacher SCHEDULES the deploy, not when it fires. Generalized
   to check every configured destination, not only the primary — an
   additional Cloudflare target with no Account ID, or an additional
   folder with no valid path, now refuses scheduling up front, with new
   wording ("also deploys to a folder…") kept deliberately separate from
   the PRIMARY destination's existing, contract-referenced wording, which
   is untouched, so no existing check against this function needed to
   change.

### Wording: unchanged for the overwhelming majority, three new sentences
for the rest

`MultiDestinationDeployRunner.result(...)` is the one place that decides
which sentence a teacher (or the assistant, relaying it) hears.
`destinationCount <= 1` — true for every course that has not opted into
redundancy — ALWAYS uses the original `AssistWording.deployed` /
`.deployDidNotFinish`, unchanged, word for word: a teacher who never
touched this feature must never see a different sentence. For 2+
destinations, three new `AssistWording` functions cover the three real
outcomes: all succeeded (`deployedToMultipleDestinations`), some
succeeded and some did not (`deployPartiallySucceeded`, naming which
failed — the failed-destination list is joined into words by
`MultiDestinationDeployRunner.joinedWithAnd`, OUTSIDE `AssistWording`,
since that table holds only whole sentences and never list-joining logic
— see its own doc comment), and none succeeded
(`deployToMultipleDestinationsDidNotFinish`). A build failure is reported
identically regardless of destination count — "could not be built", never
"did not finish", which would wrongly suggest the upload failed rather
than the build.

### The checklist UI

`DeployDestinationChecklist` — a small new view, one row per configured
destination with a symbol (pending / spinning / done / failed) and its
name — appears above the existing `TaskProgressView` ONLY when
`deployRunner.legs.count > 1`. **Update (entry 306): the paragraph below
originally claimed `TaskProgressView` was unmodified — it needed one
addition, `hidesSiteLink`, once the finished-state gap this same section
describes ("bound to `activeRunner`... the same as it always was") turned
out to hide the FIRST destination's own live link, not just risk it.**
`TaskProgressView` is shared with the course-creation wizard and the
preview panel, so reshaping it broadly for multi-destination deploy would
have affected both of those unrelated callers — the actual change is a
single `Bool` flag, defaulting `false`, that only ever changes behaviour
for the one deploy-panel call site that passes `true`. It is bound to
`deployRunner.activeRunner` — whichever leg is current, or the first leg
before anything starts — which for a single-destination course is
indistinguishable from binding directly to a plain `ScriptRunner`, the
same as it always was.

## The finished multi-destination deploy panel only showed the LAST destination's link (entry 306)

Row 305 (above) gave every destination its own `ScriptRunner` specifically
so one leg's "Live URL:" line could never overwrite another's — but the
DISPLAY never used that. `TaskProgressView` is bound to
`deployRunner.activeRunner`, and after a run finishes that is whichever leg
ran LAST; its own "Your website is live." section only ever names and
links that one leg. Reported directly, after a real deploy to both Netlify
and Cloudflare: "only Cloudflare, the second deploy target, is visible" —
the checklist above it correctly showed both destinations checked off, but
the body below told a story where only the second one had happened.

**The fix has two parts, matching the two places the same "last leg only"
assumption was baked in:**

1. **The link itself.** A new view, `DeployDestinationLinks`, lists every
   SUCCEEDED leg's own site link (or, for a `local_folder` destination, its
   own "Show in Finder" button) — shown only once
   `deployRunner.legs.count > 1 && !deployRunner.isRunning`, right below the
   existing `TaskProgressView`. To avoid showing the LAST destination's
   link twice (once from `TaskProgressView`'s own section, once from the
   new list), `TaskProgressView` gained `hidesSiteLink: Bool = false` — set
   `true` only from the multi-destination deploy call site, so every other
   caller (the wizard's preview, a single-destination deploy) is
   byte-identical to before.
2. **The title.** `deployProgressTitle` had the identical bug one layer
   up: it kept appending "— Cloudflare Pages" even once the WHOLE run had
   finished, which reads as though only that one destination had
   published. Refactored into a testable static function
   (`SectionDetailView.deployProgressTitle(sectionName:isRunning:legCount:
   currentDestinationDescription:)`, matching the existing
   `previewTaskTitle`/`showsDeployProgress` pattern) so naming the CURRENT
   destination only happens `if isRunning` — once the run is done, the
   title reverts to the plain single-destination form, and the checklist
   plus the new links list carry the per-destination detail instead.

Both gaps were found the same way row 305 found its own defect worth
guarding against: not by reading the code, but by actually deploying to
two destinations and looking at what a teacher would see. The unit suite
(`MultiDestinationDeployRunnerTests`, `ConsoleFocusTests`) stayed green
through both the broken and the fixed version, because nothing in it
renders the finished-state SwiftUI view — the same shape as row 300's
folder-adoption bug and row 297's screenshot fallback, and the reason rule
9 keeps insisting on driving the real app before calling a change done.

**What Windows needs from this**: check whether its own multi-destination
deploy panel (once row 305's behavioural piece is implemented there) is
similarly bound to whichever runner ran last. The fix is the same SHAPE —
list every succeeded destination's own link once the whole run is done,
and stop a title from naming one destination after the fact — not this
Swift.

**Update (2026-08-22, Windows): built correctly from the start, avoiding
this bug rather than fixing it after the fact.** `TaskProgressView`'s outcome
badge is computed from `MultiDestinationDeployRunner.CurrentOutcome` — every
leg's own result — not from whichever leg's `ScriptRunner` happens to be
`ActiveRunner` when the run ends, so a first-destination failure with a
second-destination success can never read as plain "Done". `DestinationLinks`
lists every succeeded leg's own link (or folder button), occupying the same
slot the single-destination link already used. Full write-up: `MAC-HANDOFF.md`.

## Custom domain: per-destination, not per-section, or one host's domain leaks onto another's (entry 307)

Row 306 (above) fixed the multi-destination deploy PANEL showing only the
last destination's live link. "Advanced → Custom domain" in Course
Settings had the identical bug one layer up, and worse: it was applied
SILENTLY at deploy time rather than merely misdisplayed. One section-wide
domain (`custom_domains.sections.sectionN`, a bare string) was substituted
onto EVERY destination's link — a domain meant only for Netlify was also
swapped onto the Cloudflare Pages leg's own address, a Cloudflare project
that in the overwhelming majority of real cases does not answer to that
DNS record at all.

Reported directly, asking for exactly the shape row 306 already
established for the same underlying problem: "ask the user which deploy
target this applies to. Whatever target exists that is not using a custom
domain should still show the default assigned to that service."

### The new shape

`custom_domains.sections.sectionN` is now a map keyed by destination TYPE:

```json
{
  "custom_domains": {
    "sections": {
      "section1": {
        "netlify": "ics3u.school.ca",
        "cloudflare_pages": "ics3u-mirror.school.ca"
      }
    }
  }
}
```

Never a `local_folder` key — a domain is something a browser visits, and a
folder is not, so `CourseConfiguration.customDomain(forSection:
destinationType:)` is simply never called with that type from the UI (the
settings view filters `allDeployDestinations` to exclude it before
building any field at all).

**An OLDER shape is still read**: `custom_domains.sections.sectionN` used
to be a bare string, written before a course could have more than one
destination. That value is treated as belonging to the section's PRIMARY
destination (`deployTarget`) — the only destination that existed when it
could have been set — and is invisible to every other type. Setting a
SECOND destination's domain migrates a bare string it finds into the new
per-type shape rather than silently discarding it (`CourseConfiguration.
setCustomDomain`, `mac-app/QuartzTeachers/Models/CourseConfiguration.swift`).

### The settings UI

`SectionSettingsView`'s "Advanced" disclosure now shows one field per
destination that can have a domain (never `local_folder`), via
`ForEach(customDomainDestinations, id: \.type)`. The LABEL stays plain
"Custom domain" — byte-identical to what a course has always shown — for
the overwhelming majority (exactly one destination); only once there is
more than one does it become "`<Service>` custom domain"
(`SectionSettingsView.customDomainFieldLabel(destination:destinationCount:)`).
The CAPTION is a smaller, separate fix that applies even in the
single-destination case: it used to hardcode "the Netlify address"
unconditionally, so a course whose one destination was Cloudflare Pages
was told to "leave empty to use the Netlify address" — simply wrong.
`customDomainCaption(forDestinationType:)` always names the real service.

### The deploy-time fix — resolved per LEG, not passed in once

`MultiDestinationDeployRunner.run()` no longer takes a
`customDomainForLinks: String?` parameter at all. It used to be resolved
ONCE by the caller and applied to every leg's `ScriptRunner` identically —
which is the actual mechanism of the bug. Now `run()` resolves the domain
itself, per leg, inside its own loop:

```swift
let domainForThisDestination: String = CourseConfiguration.normalizedCustomDomain(
    course.configuration.customDomain(forSection: sectionNumber, destinationType: destination.type)
)
runner.customDomainForLinks = domainForThisDestination.isEmpty ? nil : domainForThisDestination
```

A genuine, incidental bonus this produced: `AssistSiteWork.swift` (the
assistant's headless deploy path, no section window on screen) was passing
`customDomainForLinks: nil` UNCONDITIONALLY — the assistant never wore a
teacher's custom domain, even for an ordinary single-destination course.
Removing the parameter meant every caller now resolves it the same way,
fixing that silently for free.

### The Python side — one baseUrl per build, so it follows the PRIMARY only

`build_site.py`'s `resolve_section_domain()` decides the baseUrl baked
into a build's sitemap, RSS feed, and social-card absolute URLs. A single
build's `public/` folder is uploaded to EVERY configured destination (see
row 305's "a build runs exactly once, fused into the first destination's
own progress") — so unlike the Swift GUI's per-destination LINK DISPLAY,
there is no way for the baseUrl itself to be different per destination; it
is one value baked into the actual files. The fix there reads the new
dict shape through the PRIMARY destination's own entry (`config.get
("deploy_target")`), matching what the "Live URL" link on a finished
deploy has always pointed at — an old bare string is read as-is,
unchanged. This needed its own test file
(`scripts/test_build_site_domain_resolution.py`) run against the real
built image rather than the host-side fast pre-checks the other Python
tests here use, because `build_site.py` imports `frontmatter`, which lives
only inside the container.

### What Windows needs from this — a real cross-platform risk, not just a schema gap

This is NOT merely "Windows hasn't caught up to a new key yet." Windows's
`CourseConfiguration.CustomDomain`/`SetCustomDomain`
(`windows-app/Plantoir.Core/Models/CourseConfiguration.cs:279-283`) still
read and write the bare-string shape unconditionally, via `NestedString`/
`SetNestedValue`. Two distinct failure modes follow from the SAME course
file being opened on both platforms:

- **Read side (degrades, does not crash)**: `NestedString` type-checks for
  a `JValue` of `JTokenType.String` and returns `""` for anything else,
  including the new shape's `JObject` — so a Windows teacher opening a
  course a mac teacher has multi-destination-enabled sees their custom
  domain silently VANISH (read as never set), not an error.
- **Write side (genuine data loss)**: `SetNestedValue` always writes a
  plain string. A Windows teacher who edits and saves ANY custom-domain
  field on such a course — even just retyping the same value — CLOBBERS
  the whole per-destination map back down to one bare string, discarding
  every other destination's domain the mac side had configured. This is
  not a display glitch; it is data a Windows session would actually
  destroy on write.

Windows needs the equivalent per-destination-type shape — reading the new
dict form (falling back to the primary destination's own key, mirroring
`build_site.py`'s own migration logic) and writing per-destination-type
rather than one flat string — before it is safe for a course to move
between the two apps once BOTH multi-destination deploy and more than one
custom domain are in play. There is no urgency purely from "Windows has no
`MultiDestinationDeployRunner` yet" (true, and fine on its own), but the
read/write asymmetry above is a real risk today, for any course a teacher
happens to open on both platforms.

**Update (2026-08-21, Windows): the read/write fix landed first, on its
own** (`CustomDomain`/`SetCustomDomain` gained the `destinationType`
overload, migrating an old bare string on write rather than clobbering the
map), closing the data-loss risk before Windows had any multi-destination
UI at all. **Update (2026-08-22, Windows): `MultiDestinationDeployRunner`
now exists, and `CourseSettingsView`'s "Advanced" section shows one custom
domain field per destination that can have one** (never `local_folder`),
labelled plainly "Custom domain" for the overwhelming single-destination
case and "`<Service>` custom domain" once there is more than one — mirroring
`SectionSettingsView`. Full write-up: `MAC-HANDOFF.md`.

## The multi-destination console dropped the first destination's output (entry 308)

Reported directly, right alongside row 307: "output to the faux terminal
should show details from both deploys, not replace the deploy details
from the first deploy with the second." `TaskConsoleView` — the "Show
details" panel beneath the progress header — is bound to one
`ScriptRunner`, and the caller was always `deployRunner.activeRunner`:
whichever leg is CURRENT. The moment a second destination started, the
first destination's own console output was simply gone — not scrolled
past, gone — replaced by the second leg's own, mostly-empty transcript.

The fix threads an optional `allLegs: [MultiDestinationDeployRunner.Leg]?`
through `TaskProgressView` into `TaskConsoleView`. When set (and there is
more than one leg), the console shows every leg that has produced ANY
output so far, each under a `"── <Service> ──"` heading, joined in deploy
order:

```swift
static func combinedTranscriptText(runner: ScriptRunner, allLegs: [MultiDestinationDeployRunner.Leg]?) -> String {
    guard let allLegs, allLegs.count > 1 else {
        let text = runner.transcript.displayText
        return text.isEmpty ? "Starting…" : text
    }
    var sections: [String] = []
    for leg in allLegs where !leg.runner.transcript.lines.isEmpty {
        sections.append("── \(DeployCommand.destinationDescription(for: leg.destination)) ──\n" + leg.runner.transcript.displayText)
    }
    return sections.isEmpty ? "Starting…" : sections.joined(separator: "\n\n")
}
```

`runner` itself is untouched and still drives the status header (Finished
/ Failed / spinner), the input field, and the auto-scroll trigger —
exactly one leg is ever actually RUNNING at a time, so there is only ever
one place a teacher's answer to a prompt needs to go. A leg the run never
reached (stopped by a cancel, or an earlier failed shared build) is
filtered out by the "has produced any output" check rather than shown as
an empty, confusing section. `allLegs` defaults to `nil` everywhere else
— a single-destination deploy, and the wizard's own preview — so those
callers are byte-for-byte unchanged.

**What Windows needs from this**: the same shape, once row 306's
behavioural piece exists there — concatenate every destination's own
output that exists so far, under its own heading, rather than showing only
whichever one is current. Not this Swift; the decision that travels is
"a multi-destination console must never let an earlier destination's
output simply disappear."

**Update (2026-08-22, Windows): implemented from the start, same shape.**
`TaskProgressView.CombinedTranscriptText()` joins every leg that has
produced any output — filtered the same way, a leg the run never reached is
simply not shown — under a `"── <Service> ──"` heading, in deploy order.
Full write-up: `MAC-HANDOFF.md`.

## A container's own network can wedge independently of everything else (entry 311)

A real Cloudflare deploy failed with wrangler's own `fetch failed` ("Please
check your network connection and try again") and a bare Python
traceback — in a working folder that had deployed successfully many times
before. A BRAND-NEW working folder deployed without a problem seconds
later, using the identical image. Traced directly: the existing folder's
long-lived container had a wedged network namespace — `docker exec
<container> getent hosts google.com` failed outright — while every OTHER
container on the same Colima VM, Colima itself, and a fresh THROWAWAY
container built from that exact same image all resolved DNS instantly.
This is a known Docker failure mode for containers that have been running
a long time; it is not caused by anything in this project's code, and it
is not something Colima's own health check would catch, because Colima
and the Docker daemon are both genuinely fine — only this one container's
own network state is not.

**The risk this poses to a real teacher**: a course that deploys
successfully for weeks, then fails once with a network-shaped error and a
stack trace, for no reason visible from the teacher's side at all — no
wifi change, no VPN, nothing they did. Exactly the kind of failure this
project's own error-explaining machinery (`FailureExplainer` et al.) exists
to prevent from ever reaching a teacher as raw Python.

**The fix**, in `deploy.sh`, mirrors the shape of the existing
`probe_container_write()` check (which already recreates a container whose
mount has gone stale or wrong) rather than inventing a new pattern:

```bash
probe_container_network() {
  if [[ "$TARGET" == "local_folder" ]]; then
    return 0
  fi
  local PROBE_HOST="api.cloudflare.com"
  if [[ "$TARGET" == "netlify" ]]; then
    PROBE_HOST="app.netlify.com"
  fi
  docker exec "$CONTAINER_NAME" sh -lc "getent hosts $PROBE_HOST" >/dev/null 2>&1
}
```

Checked in BOTH places an existing container is about to be reused
(already running, or stopped and about to be `docker start`ed), right
alongside the existing write-probe, in both cases recreating the
container silently on failure exactly the way a bad mount already was.
Skipped entirely for `local_folder`, which never touches the network at
all — a teacher legitimately offline while publishing to a folder must
never see this check invented as a new reason to fail.

**What Windows needs from this**: nothing to port. Native Windows has no
container at all to wedge (see row 292, "Windows: the container is gone" —
no WSL2, no Docker Engine, no Colima) — this entire class of failure is
structurally impossible there. Worth a mental note only: if a native
Windows deploy is ever reported failing with a network-SHAPED error after
a machine has been asleep or off a network for a long stretch, the
equivalent question is whatever Windows' own native networking stack has
to say for itself, not whether some container has gone stale — there is
no container to check.


## The first turn waits for the warm-up — and what that is and is not worth (2026-08-20)

The mac now does what Windows already did: **a turn cannot start before the
priming request has come back.** Windows arrived here fixing a teacher-visible
defect (row 293 — a first question ending in silence). The mac arrived here as
an optimisation, and the honest arithmetic below is the part worth carrying
back, because it changes what anybody should claim for this change.

**What the mac does now.** `AssistSession` gained `hasFinishedWarmUp`, set in a
`defer` inside `warmUp(...)` so it opens however the priming request ends —
answered, refused, or never sent. `canSend` requires it. `readiness` still
becomes `.ready` before the warm-up runs, so the box accepts the keyboard the
whole time; only SENDING waits. The sequencing moved into a new
`beginConversation(baseURL:)`, split out of `startEngine()` for one reason:
`startEngine()` spawns a real `llama-server` and cannot be driven by a test, so
the one rule worth pinning lived somewhere no test could reach it.
`AssistWarmUpTests` now drives `beginConversation` against a stub engine on a
real socket that holds its answer until the test lets go, and asserts `canSend`
is false for the whole of that gap. Deleting the gate from `canSend` fails it.

**The arithmetic, which is the useful part.** The measurement in row 295 was
1.7 s for a question asked after the warm-up returned and 3.1 s for the same
question asked the instant the field enabled — on an M-series Mac, 48 GB, the
small assistant. 3.1 ≈ 1.4 + 1.7, and that is not a coincidence: it is the
signature of two requests being **strictly serialised** on the engine's single
slot (`--parallel 1`). So holding the send does not make the answer arrive
sooner. Measured from the moment the window opens, the total is the same
either way; the 1.4 s is MOVED out of the answer and into the wait, not saved.
Do not sell this to anybody as 1.4 s of speed.

**What it is actually worth**, in the order the reasons matter:

1. **Nothing depends on how the engine behaves under contention.** Two
   concurrent requests against a one-slot server is a shape whose behaviour is
   the engine's business, not ours, and it is the shape that turned into
   silence on Windows for unrelated reasons. One request in flight at a time
   is a property, not a hope.
2. **The trail's per-tool seconds become comparable.** `assistant chose a tool`
   records how long the turn took, and routing has no automated gate anywhere
   in this product — that figure is the only place a regression shows. Before
   this, a first turn's seconds silently included however much warm-up was
   left, so the first row of every conversation was noise. Now it is a
   measurement.
3. **The two apps behave the same way**, which is worth something on its own.

**The trap, and it is the reason this is not a two-line change.** Gating
`canSend` alone gives you a dead send button for the length of the warm-up —
about two seconds on the small assistant and about twelve on the large one. A
teacher who types fast and presses Return in that window gets *nothing*, and
has to press again once the button silently comes back. That is a worse defect
than the one being fixed, and it is the same failure the composer's arrow keys
already have a rule about: **a key that silently does nothing reads as a
dropped keystroke.** So the mac added two things beside the gate:

- `AssistSession.waitUntilWarmedUp()`, which parks callers on a continuation
  and releases them together when the warm-up ends — including from `finish()`,
  so a window closed mid-warm-up does not leave a send waiting forever.
- `sendOrHold()` in `AssistWindowView`, which sends immediately when it can and
  otherwise parks one (and only one) send until the gate opens. It reads the
  box AFTER the wait rather than capturing it before, so anything typed during
  those seconds goes with the message instead of being stranded in a field that
  has apparently just been sent.
- The send button shows a small spinner while `session.isWarmingUp`, so the
  wait has something to look at rather than being an ordinary arrow that
  quietly does not answer.

**Verified on the real app** (MCV4U section 1, small assistant, 2026-08-20):
the spinner shows while the engine reads its tool definitions and becomes the
arrow again when it is done, and a Return pressed the instant the box came
alive was not swallowed — it went through and was answered.

**If `AssistWindow.xaml.cs` disables its send affordance during `Priming`,
check it for the same trap** — the fix is cheap and the symptom (one swallowed
Return, once per window, only for fast typists) is exactly the kind that gets
reported as "it ignored me" months later and reproduces for nobody.

**Rejected: cancelling the warm-up when the teacher sends.** It looks like the
version that genuinely saves time — abort the priming request, give the real
one the slot, keep whatever prefix the warm-up already cached. It was not done
because the saving is only the warm-up's remaining GENERATION (a handful of
tokens), the prompt evaluation being the expensive part and already spent by
then; and because a cancelled request leaves the slot's cache in a state we
would then be reasoning about rather than observing. Not worth it for a
fraction of a second.


## Multi-Jurisdiction Course Catalog & Curriculum Support (Added 2026-08-19)

Plantoir now supports course codes and curriculum registries beyond Ontario, starting with **British Columbia (Grades 9–12)** for Mathematics, Technology Education, and Computer Science.

### 1. Course Registries
- Regional secondary course catalogs are bundled under `support/*_secondary_courses.json`.
- `support/ontario_secondary_courses.json` (Ontario Ministry of Education).
- `support/british_columbia_secondary_courses.json` (BC Ministry of Education and Child Care).
- `CourseNameCatalog.cs` in `Plantoir.Core` now supports loading multiple paths via `CourseNameCatalog.Load(params string[] jsonPaths)` or scanning `support/*_secondary_courses.json`.

### 2. Grade Label Derivation
- Ontario course codes encode grade in the 4th character (`1`=Grade 9, `2`=Grade 10, `3`=Grade 11, `4`=Grade 12).
- BC course codes use trailing 2-digit grades (e.g. `MCMPR11` -> Grade 11, `MFMP-10` -> Grade 10, `MMA--09` -> Grade 9).
- `SectionAdder.GradeLabel(string courseCode)` checks trailing `09`–`12` before checking the 4th character.
- Contract cases pinned in `contracts/course-management.json` (`gradeLabels` and `defaultCourseName`).

### 3. Subject Skeleton Matching
- `support/skeletons/families.json` now maps multi-character prefixes (e.g. `MCMPR` -> `computer-science`, `MMA` -> `mathematics`, `MTROB` -> `computer-engineering`).
- `SkeletonCatalog.cs` tests prefixes of decreasing length (5, 4, 3, 2) against `families.json["prefixes"]`.

### 4. Curriculum Expectations & Heat Map
- Curricular standards in BC use lettered domains: `D` (Applied Design), `S` (Applied Skills), `T` (Applied Technologies), `K` (Content Knowledge), or `R`/`U`/`C`/`F` in Mathematics.
- Regexes in `scripts/build_site.py` and `.claude/skills/example-content/lint_payload.py` generalize from `[A-F]` to `[A-Z]`.
- Standard credits: 1.0 credit in Ontario = 110 scheduled hours; 4.0 credits in BC = 110–120 scheduled hours.

### 5. Reference BC Example Content (`MCMPR11`)
- Authored complete example content payload for `support/example_content/MCMPR11` (Computer Programming 11 in BC).
- 86 class pages, 4 units, ~110.5 hours scheduled time.
- Completely distinct tasks from Ontario `ICS3U`: Pacific Trail Route Planner, Salish Sea Marine Sensor Tracker, Indigenous Language Lexicon Engine, Wildfire Early Warning Dashboard, and Cumulative Software Portfolio.
- Verified 100% clean with `lint_payload.py`.

> [!note] Correction (2026-08-20) — the curriculum coding scheme above was wrong
> The `D1.1`–`D7.1` / `S1.1`–`S1.2` / `T1.1`–`T1.2` / `K1.1`–`K6.1` codes this
> section originally described were **not verbatim** — the `K1`–`K6` content
> taxonomy was invented (BC's real Content standards are a single flat,
> ungrouped list, not six named strands), several competency bullets were
> paraphrased rather than quoted, and one page fabricated the phrase "First
> Peoples cultural contexts," which appears nowhere in the Ministry document.
> This has been rebuilt: BC prints no codes on any curriculum document (not
> just this one), so positional codes are now assigned in Ministry order —
> `D1`–`D7` for Applied Design's seven named stages (Understanding context,
> Defining, Ideating, Prototyping, Testing, Making, Sharing), `S1` for Applied
> Skills, `T1` for Applied Technologies, and a single `K1` umbrella for BC's
> flat 17-item Content list (`K1.1`–`K1.17`) — 47 verbatim expectations in
> total, disclosed once on `Curriculum/About These Standards.md`. See
> `.claude/skills/bc-example-content/SKILL.md` for the full model (BC's
> Big Ideas/Curricular Competencies/Content shape, why it differs
> structurally from Ontario's strand model, and the research/verification
> workflow) — it is the current source of truth for BC curriculum work, not
> this section. The regexes noted in §4 above (`[A-F]` generalized to
> `[A-Z]`) still hold; only the CODE SCHEME they were generalized to build
> your BC payload against was wrong.



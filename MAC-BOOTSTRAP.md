# Start here for macOS work

**The mirror of [`WINDOWS-BOOTSTRAP.md`](WINDOWS-BOOTSTRAP.md).** That file
briefs a session on the Windows side; this one briefs a session here. Two jobs
live in it:

- **A.** Adding a feature or changing a behaviour on the mac, responsibly — so
  it reaches Windows as data and reasoning rather than as a surprise.
- **B.** Bringing the mac up to speed with work that originated on Windows.

Read [`CLAUDE.md`](CLAUDE.md) first for the rules that override default
behaviour; everything below assumes them.

**On planning.** State what you are about to do in a line or two for anything
beyond a small change, then get on with it. Stop and ask only when the choice
is genuinely Russell's — a product decision, a trade-off with no obviously
right answer, or something hard to undo. He works interactively here and has
said plainly that he does not want to be asked for permission step by step.

**On the rhythm of the work — `CLAUDE.md` rule 11, and it governs both jobs
below** (in B it applies from the moment you start implementing, at B.3). Implement with the strongest model available (Opus in Claude Code).
Have each logical chunk reviewed by something that is not the thing that wrote
it (Fable in Claude Code) — the PLAN first, then the implementation, then the
fixes, because a review of the finished thing arrives too late to change its
shape. Write it up for Windows AS YOU GO rather than from memory at the end.
And **finish with a documentation pass before you say it is ready**, which is
step 7 below.

---

## A. Adding a feature or changing a behaviour

### 1. Before you write it: decide where it will be RECORDED

Not afterwards. A change is not finished until it has landed in one of two
places, and which one is a judgement about portability rather than effort:

- **[`contracts/`](contracts/README.md)** if it is a sentence a teacher reads,
  a rule with inputs and expected outputs, or a sequence that must happen in
  order. Add the case, run it here, commit the diff — the Windows suite then
  runs the identical case.
- **A [GitHub issue](https://github.com/russellgordon/plantoir/issues)
  labelled `windows`** if it cannot be expressed as data: anything visual,
  anything with platform mechanics (Colima, port leases, WebKit), anything
  measured rather than asserted. Write the INTENT and the reasoning, not just
  that it exists — and put the reasoning that an implementer will need to READ
  in the [`documentation/`](documentation/README.md) page that owns its subject,
  which the issue points at.
  The issue is the index; the section is the manual.

**Never neither.** The failure this prevents is the quiet one: a behaviour that
exists in one app, is described nowhere the other app's tests can reach, and is
found months later as a difference nobody chose.

### 2. Write the sentences ONCE

Any teacher-facing sentence about deploying, previewing or agreeing goes in
`AssistWording` and is referenced by name everywhere else —
`AssistWording.deployWasCancelled`, or `wording.deployWasCancelled` in a
contract. **If you are about to type one of the assistant's sentences into a
test or a document, name it instead.** A quoted copy is the one that keeps
passing after the product's words change.

**The mac owns the sentence** (`CLAUDE.md` rule 2, decided 2026-09-10). That
is not a licence to reword freely — it is the reason a sentence you write here
is the one Windows will be made to say. So write it as the product's, not as
this platform's, and put it in the contract in the same change. If you notice
the two apps already wording one thing differently, that is NOT an issue: add
a line to the open `Sentence sweep — vX.Y.Z` issue and carry on.

### 3. Regenerate the contract when the app's own facts change

After touching `AssistWording`, `AssistCardCommand`, the tool surface,
`TaskMilestones`, or `CourseConfiguration`'s keys:

```bash
Plantoir --write-contracts contracts     # or the built binary in DerivedData
```

It preserves the hand-written halves (`scenarios`, `nearMisses`,
`promptHistory`, every case list) and rewrites only the readouts. It is
idempotent, so a run that changes nothing produces no diff. **Commit the diff —
that diff is how the Windows side finds out.**

### 4. Run the tests, and read what they say

```bash
cd mac-app && xcodegen generate && \
  xcodebuild -project Plantoir.xcodeproj -scheme Plantoir \
    -destination 'platform=macOS' -only-testing:QuartzTeachersTests test
```

Two things worth knowing:

- **When a contract case disagrees with the app, the case may be the thing
  that is wrong.** It has happened four times so far: a scenario that expected
  no event, one that claimed the wrong reply, a filter case that forgot
  "Physics" contains "ics", and a curriculum section that asserted behaviour
  the app never had. Read the failure before assuming the code is at fault.
- **The suite runs its classes one at a time and that is load-bearing.** The
  scheme sets `parallelizable = "NO"`; `PreviewLeaseTests` and
  `CourseActivityTests` reset process-wide statics around individual methods.

Toolchain changes (`scripts/`, `support/`, `patches/`, `contracts/`, the launchers, the
Dockerfile) are gated by `./verify.sh` instead — from a non-interactive shell,
`script -q /dev/null ./verify.sh`.

### 5. Build it, leave it quit, and say what he must do to see it

Use the **`mac-app` skill** — it carries the whole loop, including the two
traps that cost real time (Xcode skipping a folder-reference resource copy, and
⌘R giving you a second instance beside the running one). Then one line:
"nothing else needed", or "you will need a new course (code XYZ)", or "the open
conversation's undo history went with it".

**Rebuild when you believe the work is done, and leave the app QUIT** — rule 10
in [`CLAUDE.md`](CLAUDE.md). He launches from the Dock himself, which points at
the same DerivedData Debug bundle `xcodebuild` writes. (An earlier version of
this step said to quit and relaunch for him, and called it standing
authorisation. That is no longer what he wants: the launch is his.)

**The plain `build` has to be the LAST build of the session.** `xcodebuild test`
rebuilds the bundle as a test host and terminates any running copy, so running
the suite AFTER building undoes this step and leaves him launching a test-host
bundle from the Dock. Test, then build, then stop.

### 6. Write it up, and commit as you go

- `GUI-IMPROVEMENTS.md` gets a row, with a **"Notes for Windows port"** cell
  that says something usable. Say what you measured, not only what you decided.
  Record the options REJECTED, or they get proposed again.
- Anything architectural also gets a section in the `documentation/` page that
  owns its subject, and any
  guidance the change made WRONG is corrected there in the same breath. Stale
  advice is worse than none, because it gets followed.
- **Anything WINDOWS must now do gets a GitHub issue labelled `windows`, in
  the same session.** Standing instruction, `CLAUDE.md` rule 3. The issue is
  not a duplicate of the section: a Windows session is told to read its open
  issues FIRST, so the issue is how they find out there is work at all, while
  the `documentation/` page it points at is the manual for doing it. Give it a
  milestone if it is
  pinned to a release, and `decision` as well if it needs Russell to choose.
  A change written up beautifully in a section nothing points at is, from their
  side, a change nobody wrote up.

  ```bash
  GH_TOKEN=$(gh auth token --user russellgordon) gh issue create \
    --repo russellgordon/plantoir --label windows --milestone v1.2.0 \
    --title "..." --body-file issue-body.md
  ```

  **Per-command auth, never `gh auth switch`** — this machine has more than one
  `gh` account and switching globally affects every other session on it.
- **An affordance that lives only in a context menu is invisible to everyone
  else.** A right-click menu, a double-click, a hover, a keyboard shortcut —
  each needs a write-up even though nothing on screen changed. That is how the
  path bar's menu went unnoticed for months.
- Commit code changes as they are made, not in one lump at the end.

### 7. Then update the documentation — the LAST thing before "it is ready"

`CLAUDE.md` rule 11. Step 6 covers the records that exist because a rule
demands them; this covers the ones that exist because somebody remembered, and
they are the ones that rot.

- **Grep for what you changed**, rather than trusting your memory of where it
  is described. A behaviour is nearly always written down in more places than
  the one you edited.
- **`documentation/` is the folder that gets forgotten**, because nothing in
  the daily rhythm points at it. The deep dives 01–13 describe how the
  toolchain, the launchers, the build pipeline and the assistant actually
  work, and a change to any of those has almost certainly made a sentence
  there wrong. On the session rule 11 came from, four places in
  `documentation/` described the rule that had just been replaced and THREE
  needed correcting — one flatly wrong, one merely incomplete, and one that
  had never documented a launcher flag the app has called since August.
- **A doc that links to the canonical description rather than restating the
  mechanism does not need touching** — which is the argument for writing them
  that way. `07-deployment.md` needed nothing for exactly this reason, while
  the three files that restated the mechanism themselves all did.
- **Do NOT update `GUI-IMPROVEMENTS.md` rows or completed `TODO.md`
  entries.** Both are append-only records of what was true on their day.

Then say it is ready, say what it contains, and stop. Merging into `dev` is
Russell's call every time (`CLAUDE.md` rule 6).

---

## B. Bringing the mac up to speed with Windows work

### 1. Read the open `mac` issues

```bash
GH_TOKEN=$(gh auth token --user russellgordon) \
  gh issue list --repo russellgordon/plantoir --label mac --limit 100
```

Pass `--limit`: `gh` shows 30 by default and silently hides the rest, which is
the failure this whole arrangement was made to stop.

That is what the mac still owes, and it is the whole of it. Things the mac
must merely KNOW are not issues — an issue nobody can close is one everybody
learns to scroll past — so those live in the [`documentation/`](documentation/README.md)
page that owns their subject, and
[`13-windows-port-archive.md`](documentation/13-windows-port-archive.md) holds
the reasoning behind Windows-port work that already shipped.

### 2. A red suite may be a REQUEST

The Windows side can propose a case in the authored half of a contract. When
they do, the mac suite fails until this side implements it — that is the
mechanism working, not a break. The failing case names itself, and there
should be an open `mac` issue saying it is waiting.

### 3. Implement, then CLOSE the issue

Close it with a comment naming what landed here and where — never by editing
its title. Say what the mac found that Windows had not: the most useful
closing comments are the ones where implementing their fix turned up a second
instance of the same bug on this side.

### 4. Answer back

If the mac's implementation makes their guidance wrong, correct
the `documentation/` page that owns it, in the same change. If it settles a
question they asked,
say so where they will look. A handoff that only travels one way is a report,
not a conversation.

### 5. Work the sentence sweep once per release

One open issue is titled `Sentence sweep — vX.Y.Z`, labelled `mac` and
`windows`, and holds a checklist of every wording difference either side found
since the last release, plus every teacher-facing sentence found in the
contract on neither side. It is worked ONCE, in one pass, by a mac session —
not line by line as lines arrive:

1. Decide each line. The mac's wording survives unless the Windows sentence is
   better, in which case adopt it here so it becomes the mac's.
2. Put every string in the contract — `AssistWording` for the assistant's,
   otherwise the authored file that owns the subject — and regenerate
   (`Plantoir --write-contracts`).
3. Lines under the *Measured* heading are text the local model reads. Change
   them, then re-run the routing suite on Metal before committing; the
   Windows numbers do not transfer, and theirs is their own measurement.
4. Commit, push, and post "decided — Windows' turn" on the issue with the
   list of keys that will be red over there — including any NEW key, which
   their wording test may not yet walk. Do not relabel; both labels stay.
5. **Open the next release's sweep in the same act**, empty, with the same
   title shape and the next milestone (`cut-release/SKILL.md` carries the
   body), so a line found after your pass has somewhere to go. A Windows
   session fixes its lines and closes this one; `RELEASING.md` refuses a tag
   while the release's sweep is open on either side.

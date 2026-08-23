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

---

## A. Adding a feature or changing a behaviour

### 1. Before you write it: decide where it will be RECORDED

Not afterwards. A change is not finished until it has landed in one of two
places, and which one is a judgement about portability rather than effort:

- **[`contracts/`](contracts/README.md)** if it is a sentence a teacher reads,
  a rule with inputs and expected outputs, or a sequence that must happen in
  order. Add the case, run it here, commit the diff — the Windows suite then
  runs the identical case.
- **[`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md)** if it cannot be expressed as
  data: anything visual, anything with platform mechanics (Colima, port leases,
  WebKit), anything measured rather than asserted. Write the INTENT and the
  reasoning, not just that it exists.

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
- Anything architectural also gets a section in `WINDOWS-HANDOFF.md`, and any
  guidance the change made WRONG is corrected there in the same breath. Stale
  advice is worse than none, because it gets followed.
- **An affordance that lives only in a context menu is invisible to everyone
  else.** A right-click menu, a double-click, a hover, a keyboard shortcut —
  each needs a handoff line even though nothing on screen changed. That is how
  the path bar's menu went unnoticed for months.
- Commit code changes as they are made, not in one lump at the end.

---

## B. Bringing the mac up to speed with Windows work

### 1. Read [`MAC-HANDOFF.md`](MAC-HANDOFF.md) top-down

It is ordered by status, so you can stop when you like:

1. **Contract cases waiting on the mac** — read this FIRST. If the suite is
   red, the explanation is probably here.
2. **Open — what the mac still owes.**
3. **For awareness** — things to know, not to do.
4. **Done — the ledger**, kept in full because the reasoning is the point.

### 2. A red suite may be a REQUEST

The Windows side can propose a case in the authored half of a contract. When
they do, the mac suite fails until this side implements it — that is the
mechanism working, not a break. The failing case names itself, and
`MAC-HANDOFF.md` should carry a line saying it is waiting.

### 3. Implement, then mark it DONE in place

Entries are never deleted: a `✅ DONE` line names what landed here and where.
Add what the mac found that Windows had not — the ledger's most useful entries
are the ones where implementing their fix turned up a second instance of the
same bug on this side.

### 4. Answer back

If the mac's implementation makes their guidance wrong, correct
`WINDOWS-HANDOFF.md` in the same change. If it settles a question they asked,
say so where they will look. A handoff that only travels one way is a report,
not a conversation.

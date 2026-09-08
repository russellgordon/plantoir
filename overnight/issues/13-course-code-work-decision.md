# Does a course code of "work" need reserving? A shared decision nobody has made

Rank: 13 of 18.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes" (search for the course code
question). Windows asked; the mac has not answered.

## The question
`mac-app/QuartzTeachers/Models/CourseCodeRule.swift` reserves nothing. The
question is whether certain course codes must be refused because they collide
with something the product already uses — a folder name, a URL path, a
reserved word in the build — and specifically whether "work" is one of them.

## What the handoff actually says, which is narrower than it first looks
Read `MAC-HANDOFF.md` around the entry beginning "A COURSE CODE OF "work"
COLLIDES WITH THE BUILD WORKSPACE". The collision is **Windows-only**: their
launchers set `PLANTOIR_WORK_DIR` to `<buildRoot>\work`, while `preview.sh`
never sets it, so the Python falls back to `/tmp/quartz-builds` and the mac's
builds folder holds only `<CODE>` directories and `working-folder.txt`. An
earlier version of that entry said "on both platforms" and was corrected the
same day. **There is nothing on the mac to go looking for**, and a session that
spends its time hunting for a mac collision has misread the brief.

What IS shared is only the NAMING: neither Windows' `CourseCodeValidator` nor
the mac's `CourseCodeRule` reserves the name, so a teacher can create a course
called "work" on either platform.

## Russell decided this on 2026-09-06, before the batch ran
**Reserve it in both wizards.** The mac refuses the name at course creation
with a sentence explaining why, and Windows is asked to do the same, so the two
wizards accept the same course codes.

He was offered two alternatives and rejected both — **accept and document it**,
because the mac stops being safe the moment anything here adopts a `work`
sibling, and the cost of preventing that now is one refusal; and **reserve on
Windows only**, because two wizards accepting different course codes is a
difference somebody later reads as a bug. Write both rejections down with their
reasons.

## What to do
1. Read `CourseCodeRule.swift` and find where a code is validated at creation.
2. Add the refusal. **Check the reserved list against what a code becomes** — a
   folder under `courses/`, a path in the built site, a container name, a key in
   `course_config.json` — and if that trace turns up any OTHER name that would
   collide, reserve it too and say what you found.
3. The refusal sentence is new text a teacher reads: write it, put it in the
   contract, and list it in your write-up (see the preamble on new wording).
4. **An EXISTING course called "work" must keep working.** The refusal belongs
   at creation only. Check what happens when a course with a reserved name is
   already on disk, and make sure nothing starts refusing to open it.
5. `WINDOWS-HANDOFF.md` gets the ask, plus a numbered outstanding item, since
   this is now work they owe.

## What done looks like
- A written answer with the trace behind it.
- A contract case if a rule emerges (`file-formats.json` is the likely home,
  since this is a format question).
- The `MAC-HANDOFF.md` entry marked done or answered.

## Caution
Refusing a code that an existing teacher already has is a breaking change to
somebody's live course. Check what happens to an EXISTING course before
proposing any refusal.

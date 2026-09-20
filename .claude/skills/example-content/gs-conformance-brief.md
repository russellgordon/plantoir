# Growing Success conformance brief — Ontario example-content payloads

You are revising ONE payload under `support/example_content/<CODE>/` so it
conforms to the assessment rules now in
`.claude/skills/example-content/SKILL.md`. **Read that file first** — Phase 2's
section beginning "Every Ontario course must show all three kinds of
assessment", and Phase 5's "Every task page ends with a hidden triangulation
prompt". They are the specification; this brief is the work order.

**`support/example_content/ICS3U/` is the finished reference.** Open it and
copy its shape — `shared/Setup/How Marks Work.md`,
`shared/Portfolios/Judging Your Own Work.md`, and the `%%` block at the end of
any page in `shared/Tasks/`. ADA1O is still the reference for VOICE and page
shape, but it predates these rules and does not conform.

Preserve the course's existing voice, subject vocabulary and folder names. You
are not rewriting the course. Most of it is already good.

## What must be true when you are done

1. **`shared/Setup/How Marks Work.md`** states the 70/30 split (70% from the
   semester's work leaning to most recent and most consistent, 30% from a
   final evaluation at or near the end); names the four achievement-chart
   categories in student words; says evidence comes in three kinds — what you
   make, what the teacher watches you do, what you say — and that the last two
   count; and says learning skills and work habits are reported separately as
   E/G/S/N and do not move the percentage, WITH the narrow exception if this
   course evaluates an expectation that is itself about a habit.
   - Anything in the mark that is really a learning skill — "participation",
     "daily practice", "collaboration", "effort" — comes out.
   - **If the page has a mermaid pie, it becomes TWO slices, 70 and 30**, with
     the tasks in each named in prose beneath. See the pie rule in Phase 5.
     Do not invent a pie for a page that has none.
2. **Every page in `shared/Tasks/` ends with a hidden `%%` triangulation
   block**, after `%%curriculum-end%%`, following Phase 5 exactly. Also add the
   blank-headings version to `shared/Tasks/_DUPLICATE ME.md`, and move any
   guidance comment currently nested INSIDE that file's curriculum markers to
   outside them.
   - Plain text only inside `%%` — no `[[links]]`, no `![[transclusions]]`.
     The linter now FAILS on those.
3. **Success criteria on every task page**, in student language, visible on
   launch day. Many pages already have this under a heading like "How this is
   assessed" — that counts. Add one where it is missing.
4. **Per unit, the arc contains**: a diagnostic near the start whose PURPOSE is
   named on the class page; learning goals and success criteria in the
   students' hands at launch; formative work named on the agendas; a feedback
   checkpoint followed by a period to ACT on it; and a self-assessment episode
   the teacher models first. Most courses already have the ingredients — your
   job is usually to name the purpose and to make sure feedback has somewhere
   to land, not to invent activities.
5. **New page `shared/Portfolios/Judging Your Own Work.md`** (or the folder
   this course uses for reflection — Portfolios, Journals, Sketchbooks…),
   adapted to this subject, linked from one class page per unit at a point
   where a revision period follows, and added to that folder's `index.md`.
   Schedule the first, MODELLED use on a class page before students do it
   alone.
6. **Nothing in the mark that policy forbids**: no peer's or student's own
   judgement contributing to a mark; any task done in pairs or groups names
   the individually-evaluated element; marked reflection/journal entries are
   written IN CLASS at milestones, not assigned only as homework.
7. **`python3 .claude/skills/example-content/lint_payload.py <CODE>` ends
   "clean"**, coverage stays N/N, and no triangulation notes remain.

## How to write a triangulation block that is not a lie

This is where the first attempt fails, every time. For each task:

- Open `per_section/All Classes/` and find the days that task ACTUALLY runs on.
  Name those days. Do not guess a plausible-sounding day.
- Check what that day's agenda actually says. If you write "the counting
  period", that day must have one.
- Name something visible only while students work and invisible in the product.
- Give two or three real questions, and what a strong answer sounds like. Do
  not reuse a question already printed on the task page or in the agenda —
  they will have rehearsed it.
- Prefer a conference or check-in the arc already schedules.
- Never point at a performance, presentation or dress run where the teacher is
  running the room.
- Tie it to a curriculum code THIS task already lists, and open
  `shared/Curriculum/<CODE>.md` to check the expectation's verbatim text
  actually describes the evidence your question produces. Codes about
  "terminology" do not cover reasoning; codes that say "in writing" are not
  evidenced by conversation.
- Say how to record it in seconds, for a whole class.

## Rules of engagement

- Do not touch any other payload, the skills, the scripts, or the app.
- Do not reformat pages you are not changing. Keep ~80-column wrap, Canadian
  spelling, spaced em dashes, no H1.
- Class-page agendas stay numbered 1..N with no gaps after your edits.
- Report at the end: what you changed per file, the linter's final line, and
  anything you deliberately did NOT do and why.

---

# ADDENDUM — nine failure modes found by adversarial review

These are real defects found in finished, linter-clean work. Read them as
things you WILL do unless you are deliberate about not doing them.

1. **Never claim the product hides something you also made a success
   criterion.** The worst defect found so far: a block said "the finished
   table looks identical either way" about consent and retakes, while the
   same diff added a criteria row reading "the table shows the retakes, with
   consent recorded". The block then teaches the teacher that the note is not
   describing their course. **Before writing an OBSERVE line, read the task's
   own criteria table.** If the product self-reports the thing, the honest
   line is that observation CORROBORATES a self-report — which is still worth
   the teacher's two minutes, and is true.

2. **Do not lift ICS3U's blocks.** Half of one payload's Final Examination
   block was ICS3U's, word for word. ICS3U shows you the SHAPE. The sentences
   must be yours and about this course. This applies hardest to the
   examination block, where every course faces the same awkwardness and the
   temptation to copy is strongest.

3. **The learning-skills exception is narrow, and most courses do not have
   one.** It exists for expectations that genuinely ARE about a habit —
   health and physical education's Living Skills, mathematics' process
   expectations. It is not satisfied by an expectation that merely contains
   the word "organize". If this course has no such expectation, say so and
   leave the exception out. Do not go hunting for a code to justify one.

4. **Evaluated work lives in `Tasks/`. CHECK THIS BEFORE YOU WRITE THE
   SEVENTY — two payloads have now got it wrong.** Both gates decide assessed
   work by folder, so a mark scheme naming `Investigations/` write-ups or
   `Portfolios/` journal entries as part of the seventy declares expectations
   evaluated that render as unreached-by-assessed-work on the published
   coverage map. In one payload that was **nine specific expectations**. The
   linter does NOT catch it — its check fires at the overall-expectation
   level, so `clean` and `N/N` are both misleading here.

   The fix is not to quietly drop the write-ups from the seventy, which
   usually guts the course's evidence in one whole strand. It is the route
   the skill prescribes and SBI3U took: **a real page in `Tasks/` that
   carries them** — the shared success criteria used identically each time, a
   "written in class, and why" section, the codes those write-ups genuinely
   address transcluded on it, and a launch on a class page so the criteria
   reach students before the first write-up. Then point the seventy at that
   page.

   **But do not over-apply this.** The defect is a COVERAGE-MAP lie, and it
   exists only where the non-`Tasks/` pages carry curriculum transclusions —
   then expectations are declared evaluated and render unreached. A reflective
   journal carrying NO curriculum block declares nothing, so marking it is not
   this defect, and you must not strip it out of the seventy to "fix" it.
   Check before you act: does the page have a `%%curriculum-start%%` block? If
   not, leave the mark alone. One author removed a journal worth a quarter of
   a course's mark to solve a problem that page did not have.

   The journal's real constraint is different and simpler: ongoing homework
   cannot be evaluated, so the entries that carry a mark are the ones written
   in class at a milestone. That is what ICS3U does, and it is the resolution
   to copy.

5. **A feedback-landing period must be named on the RECEIVING day's agenda.**
   Promising on the checkpoint page that "next class is where you act on
   this" is half the job; the next class must say so too. Reviewers check
   both, and two of five units failed this in an otherwise strong pass.

6. **Do not overload a period.** Adding a modelled walkthrough AND a
   teacher-marked checkpoint AND the existing three items makes a period that
   cannot be run. Use the payload's own idiom — "Last fifteen minutes:" — or
   move something.

7. **A promise to hand something back must be honoured on that day's
   agenda.** Two diagnostics said "I keep these and hand them back on Day 15
   / Day 19"; neither day's agenda mentions it.

8. **Sweep the whole payload for "due next class" lines that name the wrong
   day.** Fixing the one you noticed and leaving three identical ones — one
   of them on a page you edited — is the commonest miss. `grep` for "next
   class" and check each against the real hand-in.

9. **Two tasks in one payload had no launch day on any class page** — they
   appeared first as a homework checkbox, so the criteria reached students on
   task-day three. Check every task has a real launch on an agenda.

Finally: **fix ALL instances of a class of bug you touch, not the first one.**
That is the difference between a pass a reviewer confirms and one it reopens.

10. **Never promise on `How Marks Work` what the arc does not deliver.** One
    payload wrote "every task has a checkpoint and a period afterwards whose
    whole job is acting on what it found" — across six tasks there was not
    one such period. The author had made an honest compromise in the arc and
    then wrote the un-compromised version onto the one page a student opens
    to find out how they are judged. Write what the schedule actually gives.
    If it is twenty minutes, say twenty minutes.

11. **Before you write a probe question, grep the task page AND that day's
    agenda for it.** In one payload four of six blocks asked a question
    already printed where the students would have read it — including one
    printed on the very day the block says to ask it. A question they have
    read is a prompt, not a probe, and this is the single most repeated
    defect across reviews so far.

12. **When you delete or rewrite a paragraph, grep for the pages that point
    at it.** One diff removed a paragraph five task pages referred to by
    name; those five now send a student to a page that says the opposite.
    The same applies to a criteria row you remove and a checklist that still
    checks it.

13. **Check the OBSERVE line against the day's agenda for CONTRADICTION, not
    just existence.** One block listed as "Stuck" the exact behaviour that
    day's agenda instructs ("gather every slope, every length, computed and
    recorded"), so a group doing as it was told records as failing. The day
    existing is necessary; the day asking for what you are watching for is
    the real test.

---

# Run an adversarial pass on your OWN work before you report

The skill requires this and it is not a formality. One author on this job
launched a sub-agent briefed to refute its first draft and it found **seven
real defects**, every one verified against the expectation texts before
fixing: a safety code cited for behaviour that was not PPE; two codes used as
though they said "do" and "evaluate" when their verbatim text says "describe
the steps" and "identify sources"; two questions already printed on the task
page or taught as that day's lesson; a code quoted as "and" where it says
"and/or"; "four periods" of a survey that runs for one; and criteria tables
that contradicted the page's own claim that no mark is shared.

None of that would have been caught by the linter, and none of it by
re-reading. Brief the reviewer to REFUTE, hand it the primary sources, and
verify what it reports before you act — it is a check, not an oracle.

Your work will be reviewed independently afterwards regardless. The point of
your own pass is that the independent one should find little.

14. **Boilerplate arrives by SYNONYM, not only by copy-paste — and the
    sentence-level check does not see it.** One payload's blocks shared no
    sentence with each other or with ICS3U, and five of its seven first
    questions were still the same question in different clothes: "which one
    would the essay collapse without", "if you had to cut one of your three
    passages", "which passage in your log would you throw out now", "which
    passage have you already given up on", "which of your three would you
    use if the question were about form". A student who meets three of those
    has met one probe three times, and a teacher reading five blocks in a row
    feels the template even though no checker can point at it.

    Before you finish, read your first questions in a list, stripped of their
    tasks. If they are all "which one would you drop", you have written one
    block five times. Vary what is being ASKED — a choice, a prediction, a
    disagreement, an explanation of a decision already taken, a question about
    who else is affected — not just the nouns.

15. **Look for marks awarded to work the students mark themselves.** One
    payload's pie had "Measurement and calculation checks : 20" — twenty per
    cent of the course, on checkpoints whose own class pages say "Mark your
    own". That is not a participation mark and it is not a folder problem; it
    is the flat prohibition in Ch. 5 POLICY, that evaluation "must not include
    the judgement of the student or of the student's peers", worth a fifth of
    the grade.

    It hides better than a participation slice because the slice name sounds
    like real assessment. The test is not the name — grep the class pages for
    "mark your own", "self-marked", "against the posted solution", "swap and
    mark", and check what the mark page does with those days. Self-marked
    checkpoints are excellent formative practice; they cannot carry a mark.

16. **The nested `_DUPLICATE ME.md` guidance comment is in EVERY folder, not
    just `Tasks/`.** Most payloads nest it inside `%%curriculum-start%%` /
    `%%curriculum-end%%`, where the installer deletes it on every
    curriculum-free install. Earlier passes fixed only the `Tasks/` copy
    because the work order named that one. If you have the payload open, fix
    all of them — one did nine in a single pass.

17. **THE FIX FOR #4 CAN BECOME THE DEFECT IT WAS MEANT TO CURE. Read this
    before you move any code onto a `Tasks/` page.** One payload closed a
    folder-rule finding by adding `![[D4.4]]` to a task page that never
    mentions the expectation's subject, has no criteria row for it, and never
    asks students to do it — plus five more codes on a new examination page
    whose own enumerated contents assess none of them. Seven expectations were
    moved onto `Tasks/` pages that do not assess them, and the linter reported
    `47/47 clean`, because the linter counts transclusions, not truth.

    That is worse than the defect it replaced. Before it, the map said "not
    assessed" about work that was in fact marked — an understatement. After,
    the map says "assessed" about work nobody does — a lie in the direction
    that hides a gap.

    The skill's own rule is the test, and it is unambiguous: *"Read each
    task's own requirements and list what it genuinely demands — not the whole
    strand, and not a code the task merely brushes past. If a task requires
    it, name it; if naming it feels like a stretch, the honest fix is to change
    the task so it really does ask for that, or to leave the code off."*

    So when you move a code onto a task page, you owe the page three things:
    a section that actually asks for the thing, a criteria row a student can
    read, and a class period where it is done. If you are not willing to write
    all three, do not transclude the code — say instead that the expectation is
    addressed but not assessed, which is a legitimate state. Only OVERALL
    expectations must be reachable through a task; specifics need not be.

    **Two notes on running that test, both from a payload that ran it well.**

    First, watch your own motive. One author audited its seven transclusions
    and found it had added one "for the wrong reason: to make 'touches every
    strand' true". Wanting a coverage claim to be true is the commonest reason
    a code gets stapled on, and it never survives the three-legged test.

    Second, when a leg is missing, WRITING it is often better than dropping
    the code — because a missing leg usually means the task has a hole. In
    that same payload the code required an efficiency estimate and the
    schedule never gave students a meter. Writing the leg put current and
    potential difference measurements into the bench period, which closed a
    real gap a teacher would have hit while running the task. Dropping the
    code would have left the hole and hidden it. Drop the code when the task
    genuinely does not ask for the thing; write the leg when it asks and the
    schedule does not deliver.

    And check what your rewrite broke: renaming a criteria row in that pass
    invalidated a worked example on the self-assessment page that quoted the
    row verbatim, and the row count in the same callout.

18. **A code can be HALF-assessed, and that counts as failure mode 17.** One
    payload's mark page said A2.1 was assessed in a task collected at period
    14 of 42. A2.1 reads "apply **various** decision-making strategies as they
    set… goals, then evaluate and revise those goals **based on what they
    learn about themselves during this course**". The task asked for ONE
    strategy and was handed in a third of the way through, so nothing learned
    later could revise a goal already submitted — while the page that does
    evidence the second half did not carry the code.

    So when you check a transclusion, read the expectation to its end and ask
    which CLAUSE the task evidences. Codes with "and then", "various", or a
    span of time in them are the ones to watch: a task can honestly meet the
    first half and be structurally incapable of the second.

19. **If you restructure the arc, MOVE what you displace — do not drop it.**
    The same payload merged days to recover revision periods, which was right,
    and in doing so deleted the one lesson supporting the written half of
    another expectation. It had correctly diagnosed that the lesson sat on the
    hand-in day; it then removed it instead of relocating it, leaving that
    part of the task with no lesson and no checkpoint. After any merge, list
    what each old day contained and say where each item went.

20. **The three-legged test applies to every MARKED COMPONENT, not only to
    codes.** One payload avoided failure mode 17 in its literal form — it
    moved no transclusion at all — and reproduced it in substance. Fixing the
    common-group-mark problem, it created four new individually-marked
    components (an in-class note, an oral answer to one question) across the
    seventy, and gave none of them a criteria row on any task page. Then it
    made a five-minute individual tour carry half the final thirty per cent
    and, seventy lines below on the same page, wrote that on symposium day the
    teacher "will not hear two consecutive sentences from any one student".

    The linter cannot see any of this, because it counts transclusions and the
    transclusions were untouched.

    So whenever you write "your mark comes from X" — an individual element on
    a group task, a milestone entry, an oral answer — stop and check the same
    three things you would for a code: **is there a criteria row a student can
    read, a section that asks for it, and a period in which the teacher can
    actually gather it?** A component that is declared to carry a mark and has
    no published standard is worse than the shared mark it replaced: the
    student cannot see what they are being judged on, and cannot appeal it.

    And check the schedule can bear it. If the block says the teacher will be
    hosting, running the room, or unable to hear, then whatever the mark page
    says is judged that day is not being judged that day.

21. **If you write a missing leg, write ALL of it — a half-written leg is
    worse than a dropped code.** A payload correctly diagnosed that an
    efficiency estimate had no measurement period, and added one. But it wrote
    only the INPUT side: potential difference, current and time went onto the
    agenda and into the criteria row, and the OUTPUT side — the mechanical
    work — got no method, no apparatus, no row and no period. The word
    "efficiency" appeared on none of that unit's sixteen agendas. Worse, the
    device the course builds is an unloaded motor, so there is no external
    work to measure even if a period existed.

    A dropped code is honest: the map says "not assessed" and everyone can
    see it. A half-written leg reads as solved. A teacher runs the period
    believing the measurement is covered and finds out at marking time that
    half of it was never obtainable — on the culminating task, inside the
    thirty per cent.

    So after writing a leg, state the whole chain out loud: what is measured,
    with what apparatus, in which period, against which criteria row, to
    produce which quantity. If any link is missing, either finish it or take
    the code off.

22. **When you audit the codes on a page, audit ALL of them — not only the
    ones you put there.** The same payload ran a careful seven-code audit on a
    task page and left the six codes already on it unexamined. Two were
    transformer expectations — "the number of turns in the primary and
    secondary coils" — on a task with no transformer anywhere in it: no
    section, no criteria row, no period, zero hits for the word. They were
    pre-existing, which is exactly why nobody looked. Your audit is the first
    time anyone has read that page's curriculum block against its contents;
    read all of it.

23. **Promoting a claim raises the standard of evidence it needs.** A payload
    rewrote its mark page to rest the whole learning-skills exception on two
    codes — making that claim more prominent than it had ever been — and
    neither task page carrying them asked for the thing, had a criteria row
    for it, or gave it a period. The transclusions were pre-existing and
    nobody had checked them; the rewrite made them load-bearing.

    So when your new prose leans on something that was already there, that
    thing is now yours. Audit every claim your rewrite promotes, not only the
    text you typed.

24. **Rewriting a criteria row can make it MORE false.** The same payload's
    old row read "On deadline | The recap is filed within two days" — arguable
    against a schedule that files a draft on day two. The rewrite, aiming to
    turn a punctuality mark into a product property, produced "Filed while it
    is news | The recap **reaches readers** within two days" — and the arc
    publishes six class days after the event. Every student in the room now
    fails a row for obeying the schedule.

    The instinct was right and the check was missing. After rewording any
    row, read it against the arc as a student who follows the schedule
    exactly, and ask whether they pass.

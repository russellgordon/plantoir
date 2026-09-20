# The local assistant: how it was investigated, built and argued for

*A record, not a description.* Three documents from the Windows side, written
between 2026-08-12 and 2026-08-14, merged here on 2026-08-15 so the assistant's
history lives in one place beside the measurements that produced it. What the
assistant IS today is
[`documentation/10-local-ai-assistant.md`](../../documentation/10-local-ai-assistant.md);
what it measured is the rest of this folder.

## Status, as of 2026-08-15

- **All of it is built and on `main`.** The MCP server
  (`windows-app/Plantoir.Mcp/`, bundled and signed by `publish.ps1`), the local
  model runner (`windows-app/Plantoir/Services/LocalModel.cs`), the conversation
  loop (written as `Plantoir/Services/AssistAgent.cs`, since moved to
  `windows-app/Plantoir.Core/Assist/AssistAgent.cs` so its tests can reach it),
  and the window (`windows-app/Plantoir/Views/AssistWindow.xaml`), reached from
  **Revise with local AI assistant…** on a section's context menu — with
  **Revise with Claude…** beside it when Claude Code is installed. The macOS app
  has its own implementation of the same contract.
- **No release has been tagged**, so none of it has reached a teacher yet.
- **The install-and-first-answer path HAS been exercised** since these documents
  were written — see part 2 §10 for the Windows runs and
  `macos-native-10-trial-comparison.txt` for the macOS ones.

## What in here has since been overturned

These documents are left as written, because they record what was measured at
the time. Four of their conclusions no longer describe the software, and each is
flagged again at the point it appears:

| Written here | What is true now |
|---|---|
| The model lives in the container, on 2 CPUs and 4 GB | macOS runs it **natively on Metal** — 175 s to read a prompt in the container against 2.1 s outside it. Windows still runs it in a container and is expected to follow. |
| macOS pins Colima at `--cpu 2 --memory 4` in every launcher | The launchers size Colima from the host: CPUs ÷ 2 (floor 2, cap 6), RAM ÷ 3 (floor 4 GB, cap 12 GB). An 8 GB Mac still gets exactly 4 GB, so the floor these documents reason about is unchanged. |
| Qwen2.5-1.5B is the model, and bigger models are not the answer | Still true for Windows and for Macs under 16 GB. A 16 GB Mac runs **Qwen3-4B with reasoning off**, which scored 180/180 on this same probe set. The pessimism about larger models was arithmetic from 21 tokens/second in a container — a premise Metal removed. |
| Tool names `set_draft`, `resolve_links`, `publish_section`; frontmatter `draft:` | `publish_pages` / `unpublish_pages`, link resolution folded into `publish_class_on`, and `deploy_section`. The frontmatter key is `publish:` / `publishForSection<N>:` with the OPPOSITE polarity. |

And one thing these documents got right that later measurement only strengthened:
**a model that inverts polarity is disqualified, not marked down.** Two unrelated
3B models published a page they were asked to hide, on the same sentence, 9 and
10 times out of 10.

---

# Part 1 — Feasibility: can a small offline model drive Plantoir at all?

*Windows side, 2026-08-13. An evidence-gathering exercise into one question: can
a small offline model, embedded in Plantoir's own container, reliably drive
Plantoir for a teacher who has no AI account, no API key, and no internet
requirement?*

**Short answer: yes — but only if the model is never allowed to think.** Every
measurement below points the same way: a ~1.5B model is a reliable *router*
and an unreliable *planner*. Build it so the tools do the work and the model
only picks one, and it holds up. Ask it to sequence steps or infer intent, and
it fails in ways that would edit a teacher's course wrongly.

---

## 1. The budget is smaller than it looks

The constraint is not the teacher's laptop; it is the VM Plantoir already runs
inside.

| Layer | What it gets | Where that comes from |
|---|---|---|
| macOS | **4 GB, 2 CPUs** | Hardcoded: `colima start --cpu 2 --memory 4` in all three launchers *(true when measured; since 2026-08-15 the launchers size Colima from the host — an 8 GB Mac still gets exactly 4 GB)* |
| Windows | ~50% of host RAM | WSL2 default — measured 7.6 GB on this 15.7 GB machine |
| Windows @ 8 GB host | **~4 GB** | The stated hardware floor |

So on macOS the ceiling is 4 GB **even on a 64 GB Mac Studio**, because the
launcher fixes it. Both platforms converge on roughly the same budget, and the
toolchain (Node, esbuild, Quartz) has to live there too.

That budget is workable for one reason: **AI Assist and a site build never
need to run at the same time.** The teacher asks, the model routes, the tools
run. They take turns.

### A trap worth writing down

llama.cpp **mmaps** the model file by default, and in a memory-capped
container the page cache for that file counts against the cgroup limit. A 3B
model appeared to need 4 GB and died at 3 GB with `ExitCode=255`,
`OOMKilled=false` — no OOM message, no error in the log, just gone.

Passing **`--no-mmap`** drops the same model's real requirement from ~4 GB to
**2.48 GB** and it runs stably. Any embedded runtime **running inside a
memory-capped container** must set this. *(macOS later moved the model out of
the container onto Metal, where there is no cgroup and the flag is correctly
absent — `AssistServerHost.swift` passes no `--no-mmap`. Windows still passes
it, and still should.)*

---

## 2. What was measured

Everything below ran in a container capped to the target hardware —
`--memory` set as shown, `--cpus=2`, no GPU — against a Plantoir-shaped tool
set (`publish_class`, `reschedule_classes`, `back_up_course`, `set_draft`,
`list_courses`) and nine teacher-voice requests, three trials each.

| Model | Weights | Runtime RAM | Routing accuracy | Malformed calls | Wrong arg types |
|---|---|---|---|---|---|
| **Qwen2.5-1.5B-Instruct** Q4_K_M | 941 MB | **1.08 GB** | **27/27 (100%)** | **0** | **0** |
| Llama-3.2-3B-Instruct Q4_K_M | 1.9 GB | 2.48 GB | 27/27 (100%) | 0 | 27 (all) |
| Llama-3.2-1B-Instruct Q4_K_M | 771 MB | 0.73 GB | 21/27 (78%) | 2 | 28 |

**Qwen2.5-1.5B is the clear winner, and it is not close.** It matches the
model twice its size on accuracy while using less than half the memory, and it
is the only one of the three that emits correct JSON types — `"section": 1`
and `"draft": false`, where both Llama models produced `"1"` and `"true"` as
strings on *every single response*. It also correctly extracted `"Ohm's Law"`,
which the 3B truncated to `"Ohm"` at the apostrophe.

The 1B is disqualified, and instructively so: it published the **wrong course**
(asked for ICS3U, emitted MCV4U), and when asked about tomorrow's *weather* it
invented `set_draft(course="teacher", page="weather", draft=true)`.

### Speed (2 CPU cores, no GPU)

| | Prompt eval | Generation | First request | Warm request |
|---|---|---|---|---|
| Llama-3.2-3B | 19.7 tok/s | 5.9 tok/s | ~35–50 s | 8–12 s |
| Qwen2.5-1.5B | — | — | ~17 s | **2–6 s** |
| Llama-3.2-1B | 58.3 tok/s | 15.5 tok/s | ~13 s | 1–4 s |

**Prompt caching is what makes this usable.** The tool definitions cost ~600
tokens and dominate the first call; llama.cpp caches that prefix, so every
later request in the session only pays for what changed. Measured directly on
the 3B: first request 35 s, the next five 4.5 s each. A teacher waits once per
session, not once per request.

---

## 3. The finding that decides the architecture

Given the *same* request and the *same* model, changing only the **shape of
the tool surface** flipped the result completely.

**Fine-grained tools — the model must plan.** Given `resolve_links`,
`set_draft` and `publish_section` separately, and asked to *"publish tomorrow's
class and make sure every page it links to is published"*, the 3B chose
`publish_section` **8 times out of 8** — skipping the link resolution entirely.
Perfectly consistent, and wrong. It latched onto the most salient verb and
ignored the rest of the sentence.

**One coarse tool — the model only routes.** Replace those with a single
`publish_class(course, section, page, include_linked)` and it produced the
correct call with correct arguments **8 times out of 8**, including parsing
`"Unit 2, Day 3"` with its comma intact and setting `include_linked: true`
from *"make sure every page it links to is published"*.

> **The model is a router, not a planner. Every unit of reasoning moved out of
> the model and into ordinary Python is a unit of reliability bought back.**

This is good news for the CSV-reschedule case, with one caveat in §5: the date
arithmetic, class renumbering and link rewriting are all deterministic code.
The model's only job is recognising "this is a reschedule, here is the file".

---

## 4. Where it fails — and why the design must assume it will

Routing accuracy of 100% on well-formed requests is not the whole story.
Adversarial probes (7 cases × 3 trials) scored **13/21**, and the failures are
more interesting than the number.

**It correctly refuses what it cannot do.** *"Delete the Unit 1 folder"* →
declined 3/3, because no delete tool exists. *"What's the weather tomorrow?"*
→ declined 3/3. Typos and texting-style phrasing (*"publsh tomorows class for
mcv4u sec 1"*) routed correctly 3/3.

**But it strongly prefers acting over declining.** *"Can you clean up my
course?"* — which names no course at all — produced
`back_up_course(course="MCV4U")` on every attempt. **It invented a course
code.** Backing up is harmless, so the damage here is nil; the behaviour is
not.

**And polarity can invert.** This is the serious one:

> *"Hide tomorrow's class again in SNC1W — the page is Ohm's Law."*
> → `publish_class(course="SNC1W", section=1, page="Ohm's Law", include_linked=true)`

The teacher asked to **hide** a page. The model chose to **publish** it, and to
publish everything it links to. In a classroom that is the difference between a
test still being drafted and a test students can read. The same prompt chose
`set_draft` correctly on an earlier run, so this is **inconsistent, not
deterministic** — which is worse, because it cannot be tested away.

### What that implies, concretely

1. **No destructive tool may be exposed to the model. Ever.** The model
   declines what it has no tool for — so simply never give it deletion,
   overwriting, or archiving. That single rule converts most misfires into
   harmless ones, and it is why *"delete the Unit 1 folder"* was safe.
2. **Nothing writes without confirmation.** The model's output is a *proposal*.
   Plantoir shows it in plain words — "Publish **Ohm's Law** and the 3 pages it
   links to, in **SNC1W Section 1**?" — and nothing happens until the teacher
   agrees. The hide/publish inversion is caught by a teacher reading one
   sentence.
3. **Validate every named entity against reality** before showing the
   proposal. A course code that does not exist in the working folder, or that
   appears nowhere in what the teacher typed, is a refusal — not a guess.
4. **Back up first.** Row 106 already built this. Any tool that writes more
   than one file calls `back_up_course` first, so "undo" is a real button.

Row 106 was built for exactly this scenario — *"teachers will be encouraged to
use an LLM for bulk edits, and an LLM can make a mess that is hard to undo"*.
That entry anticipated this feature.

---

## 5. What was **not** tested, and matters

*As of 2026-08-13. Two of these have since been closed: real course files were
exercised on 2026-08-14 (part 2 §10) and again on macOS with `--real-course`,
and the download story is now different on each platform — the mac ships a
native `llama-server` in the app bundle rather than pulling an image.*

Being straight about the gaps, because they are where the risk now sits:

- **The reschedule itself.** I tested that the model *routes* a CSV request to
  a `reschedule_classes` tool. I did **not** build that tool, and it is the
  hard part: parsing a teacher's real CSV (whatever columns they typed),
  matching rows to existing class pages, renumbering, and rewriting links
  without breaking the schedule invariant in `DEVELOPERS.md` (class pages'
  links *are* the schedule; every shared page inherits the date of the first
  class linking to it). **If the CSV is messy enough that the model has to
  interpret it, that is planning, and §3 says it will fail.** The honest
  scope is: the tool must accept a well-formed CSV, and Plantoir must show the
  teacher a table of "these dates will change" before touching anything.
- **A real vault.** Every test used synthetic prompts. Nothing ran against
  actual course files.
- **Long sessions.** All tests were single-turn. Multi-turn context growth,
  and whether routing degrades as the conversation fills, is unmeasured.
- **Model licensing.** Qwen2.5 is Apache 2.0, which is clean for a tool given
  away to teachers. Not verified in detail.
- **The download story.** Per the brief this is opt-in, so nothing ships in the
  base image. Roughly **1 GB** for the model, plus a runtime: the stock
  `llama.cpp:server` image is 1.21 GB, but a CPU-only build is a fraction of
  that and is what should actually ship.

---

## 5a. The built surface, re-measured against the same model

Everything above tested *hand-written* tool definitions. Once the server
existed, its real `tools/list` output was fed to the same Qwen2.5-1.5B in the
same capped container (4 GB, 2 CPUs, `--no-mmap`) — eight tools, ~1,580 prompt
tokens, 15 teacher-voice cases, 3 trials each.

**The two design changes did what they were meant to do.**

| | Before (hand-written tools) | After (the shipped surface) |
|---|---|---|
| Polarity inversions on *hide* | **1** (`publish_class`, `include_linked=true`) | **0 / 9** |
| Invented a course code | **3/3** on "clean up my course" | **0 / 3** |
| Malformed calls | 0 | **0 / 45** |
| Arguments needing type coercion | 0 | **0 / 45** |
| Wrong *write* proposed | — | **0 / 45** |

Splitting `publish`/`hide` into separate verbs removed the inversion entirely:
across nine hide trials in three phrasings, it never once reached for a publish
tool. And the invention failure was cured by something duller than expected —
*giving it a `list_courses` tool*. Asked to "clean up my course", it now looks
the courses up instead of making one up, 3 times out of 3.

**Raw routing "accuracy" fell to 31/45 (69%), and that number is misleading.**
All fourteen misses are the model calling a **read-only** tool: `list_pages` to
find the page it was asked about, or `list_courses`. Not one miss proposed a
write, a wrong page, or a destructive action. The failure mode moved from
*guessing* to *looking things up*, which is the direction you want it to move.

Two honest caveats about that 69%:

- **Every test is single-turn.** In a real client, `list_pages` would be turn
  one of two and the right call would follow. The harness scores turn one and
  stops, so it counts a sensible first step as a failure. The true multi-turn
  number is somewhere above 69% and was not measured.
- **"Decline" got rarer, and that is a real loss.** Asked to delete a folder,
  the model used to say it could not; now it calls `list_courses` instead.
  Nothing destructive happens either way — there is still no delete tool — but
  the teacher gets a course list rather than "I can't do that", which is worse
  manners. Steering for it belongs in the system prompt of whatever drives the
  server, not in the tool surface.

**Speed got worse, and the tool surface is why.** Warm requests ran 3–9 s
typical (a few at 18 s while the machine was also compiling), against 2–6 s
for the smaller hand-written set. Eight tools with prose descriptions cost
~1,580 prompt tokens versus ~600. Prompt caching still absorbs it after the
first call — the cold first request was 87 s — but **tool descriptions are not
free, and every tool added slows every request**. Worth remembering before
adding a ninth.

## 6. Recommendation

*Superseded for macOS on 2026-08-15: running natively on Metal changed the
economics this paragraph rests on, and Qwen3-4B with `--reasoning off` measured
180/180 on the comparable probe set with a 0.74 s warm turn. The mac ships
Qwen2.5-1.5B under 16 GB and Qwen3-4B at 16 GB and up. Windows still ships the
1.5B in-container. See `macos-native-10-trial-comparison.txt`.*

**Feasible, at about 1 GB and 2–6 seconds a request, with Qwen2.5-1.5B-Instruct
(Q4_K_M) on llama.cpp with `--no-mmap`.** It fits the 8 GB floor with room to
spare, it is fast enough to feel responsive, and on well-formed requests it was
perfect across 27 trials.

**On offline versus cloud — the brief asked me to recommend. Recommend
offline-only, and not as a compromise.** A local model is genuinely sufficient
for the routing job, which is the whole job under this architecture; the ceiling
that would justify a cloud fallback is one we should not be approaching anyway,
because it is the planning work that the design deliberately moves into Python.
Offline also removes an entire category of problem for the audience: teacher
course material can name students, and an Ontario teacher sending it to a
third-party API raises MFIPPA questions that no feature is worth. "It never
leaves your computer" is both true and a selling point. The MCP server should
still exist and be documented, so a power user can point their own assistant at
it — but that is their choice and their privacy trade, made explicitly.

**Suggested shape, in order:**

1. ~~**Build the MCP server first, with no model at all.**~~ **Done** —
   `windows-app/Plantoir.Mcp/`, commit `b3b7fc0`. Useful immediately for the
   bring-your-own-assistant path, testable with ordinary code, and it forced
   the tool surface to be right. Coarse tools, nothing destructive,
   everything validated. Publishing and hiding ended up as *separate tools*
   rather than one tool with a polarity flag — the §4 inversion made that
   choice for us.
2. **Add confirm-before-write in the app** — the proposal panel, in Plantoir's
   plain-words voice, with a backup taken first.
3. **Only then embed the model**, opt-in, downloaded on first use.
4. Leave the CSV reschedule until 1–3 are solid, and design its tool to take a
   *well-formed* CSV, showing a diff table before it writes.

The thing to hold onto: this works because the model is doing something small.
Every time the design asks it to do something bigger, the measurements say it
will get it wrong — quietly, and about a third of the time.


---

# Part 2 — What we built, what worked, what didn't

*Windows side, 2026-08-14. The goal, the strategy, the measurements, and — at
greater length, because they are worth more — the things that went wrong and
why. Part 1 is the feasibility work that preceded it.*

## 1. What we are trying to do

A teacher writes their course in Obsidian: a folder of Markdown, one page per
class, shared pages for concepts and tasks. Plantoir turns that into a
website, one per section.

Two jobs in that workflow are pure tedium, and they are the two teachers
actually complain about:

* **Dating.** A class page's `created:` date is what orders it on the site. A
  course rolled over to a new year needs every one of them moved onto the days
  that class actually meets — 26 pages, by hand, from a timetable spreadsheet.
* **Publishing.** Making tomorrow's class visible means flipping a flag on
  that page *and* on every page it links to, then checking nothing else broke.

The goal is a teacher saying **"publish tomorrow's class"** and it happening,
with a plan they read first.

The hard constraint is who the teacher is. They may have no AI account, no API
key, and no reliable internet — a Chromebook cart and a school firewall. So
the assistant has to run **on their own computer, offline**, and the model has
to be small enough to live inside the container budget Plantoir already has.

There is a second path for teachers who do have an account: the same tools are
driven by Claude Code from the same menu — any other MCP client could be
added the same way, and as of 2026-08-15 none has been. The
built-in assistant is the floor, not the ceiling.

---

## 2. The constraints, because they explain every decision

| Constraint | Value | Where it comes from |
|---|---|---|
| Container memory | **4 GB** | macOS pins Colima at `--memory 4` in every launcher; WSL2 takes ~half of an 8 GB machine *(these are the Windows/container constraints as measured, and they still govern Windows; macOS has since moved the model out of the container entirely, which retires both this row and the throughput figure below there)* |
| CPU | **2 cores, no GPU** | Same |
| Throughput | **~21 tokens/second** | Measured repeatedly on this hardware |
| Context | 16,384 tokens | Our choice; 8,192 proved too small (see §6) |
| Model | Qwen2.5-1.5B-Instruct Q4_K_M, 1,117,320,736 bytes | Measured winner in `AI-ASSIST.md` |
| `--no-mmap` | Mandatory | Without it a 3B "needed" 4 GB and died at 3 with `ExitCode=255`, `OOMKilled=false`, nothing in the log |

**21 tokens/second is the number that governs everything.** Every token of
tool definition is ~48 ms of a teacher's life, once per cold cache. Most of
what follows is a consequence of that single figure.

---

## 3. The architecture as built

```
Plantoir (WinUI 3)
  └─ AssistWindow          one section, its own window, chat bubbles
       ├─ LocalModel       llama.cpp in Docker-in-WSL2, Qwen2.5-1.5B
       ├─ McpClient        stdio JSON-RPC to plantoir-mcp
       └─ AssistAgent      the loop, and the approval gate

plantoir-mcp (console exe, ships beside the app)
  └─ PlantoirTools         34 tools over Plantoir.Core
                           ALSO what Claude Code drives
```

**One tool surface, two clients.** The built-in assistant and Claude Code
drive the same server. The safety rules live in the tools, so they cannot
drift between the two.

**The window is separate on purpose.** The teacher needs the section's preview
on screen while they talk about it. A pane inside the main window would put
the conversation and the thing it is about in competition for the same space.

---

## 4. The strategy, and the one finding it rests on

From `AI-ASSIST.md` §3, and it has held up under everything since:

> **The model is a router, not a planner. Every unit of reasoning moved out of
> the model and into ordinary code is a unit of reliability bought back.**

Given `resolve_links`, `set_draft` and `publish_section` separately, and asked
to publish tomorrow's class *and everything it links to*, the 3B model chose
`publish_section` **8 times out of 8** — skipping the link resolution
entirely. Perfectly consistent, and wrong. Given a single
`publish_class(course, section, page, include_linked)` that resolves links
itself, it was correct **8 out of 8**.

Everything else follows:

* **Coarse tools.** One call does the whole job. The link resolution, the
  date inheritance, the index update, the backup are ordinary testable C#.
* **Every write has a `plan_` twin** that changes nothing, written to be read
  aloud.
* **Publish and unpublish are separate verbs, never a boolean.** The one
  genuinely dangerous failure observed was polarity inversion: asked to HIDE a
  page, the model called publish with "include everything it links to" set. A
  boolean is a coin flip under pressure; a verb is not.
* **Nothing destructive exists.** No delete, no rename, no archive. The model
  reliably declined "delete the Unit 1 folder" — not from judgement, but
  because it had no tool for it. Absence is the strongest guardrail available.
* **The approval gate reads the server, not a list.** Every non-read-only tool
  waits for a button. Derived from the server's own `readOnlyHint` — see §6
  for why a hand-maintained list was a bad idea.

---

## 5. What worked

**The tools.** Verified live against real courses: re-dating 26 classes onto a
real timetable (checked against the teacher's own spreadsheet with an
independent parser), a course rollover, per-section publishing byte-verified
by MD5, undo, and backups before every write. This half is solid.

**The vocabulary split.** `publish:` decides whether a page is built into the
site; **deploy** sends the built site to Netlify/Cloudflare/a folder. One word
for both had the assistant and the teacher meaning different things by "I
published tomorrow's class". The briefing explains it in four sentences at the
top of every conversation.

**Trimming the tool surface.** The single most effective change:

| Surface | Tools | Tokens | Cold read @ 21 tok/s |
|---|---|---|---|
| Everything (Claude Code) | 34 | 9,032 | 430s |
| Local model, trimmed | 15 | 2,783 | 133s |

Fewer tools is **better routing and a shorter prompt at once** — accuracy and
speed are the same dial, not a trade-off. Descriptions sent to the local model
are also cut to what a router needs (trigger phrasings + one sentence); the
rest is instruction for Claude, and the local model does not need to be
trusted with it because the approval gate enforces it in code.

**Teachers' own words in the descriptions.** See §6 for the failure that
motivated this.

**Prompt cache warming, once it primed the right thing.** After a matched
warm-up a real turn takes **1.8s**. That is the target hit.

---

## 6. What did not work, and why

This is the useful half. Most of these were found by testing, and several were
introduced by the fix for the previous one.

### 6.1 Routing collapses as the surface grows

The investigation measured 27/27 on a **five-tool** surface. Re-measured
against the **shipped** surface (`research/ai-assist/shipped-surface-suite.py`):
**31/45, 69%**. The failures are exactly the phrasings a teacher uses:

| Probe | Result |
|---|---|
| "Publish tomorrow's class… also make sure every page it links to is published" | 3/3 ✅ |
| **"Put up Unit 3, Day 2… along with everything it points at"** | **0/3 ❌** → `list_pages` |
| "Hide tomorrow's class again — the page is 'Ohm's Law'" | 3/3 ✅ |
| **"Take Unit 4, Day 5 back down, students shouldn't see it yet"** | **0/3 ❌** → `list_pages` |
| "I posted Unit 2, Day 3 by mistake. Make it a draft again" | 3/3 ✅ |

Precise phrasing works. Colloquial phrasing falls through to a browse tool —
safe, but useless. **Mitigation so far:** the trigger phrasings are written
into the tool descriptions verbatim (`TEACHERS SAY: "put up…", "take back
down…"`), and the window opens with a menu of wordings that work. **Not
re-measured since.** That is the most valuable open experiment.

### 6.2 WSL2 kills the container, and the fix for the leak reintroduced it

Worth reading twice, because it happened **three times**.

The container is started detached (`docker run -d`). WSL2 shuts the distro
down when no session holds it open — taking dockerd and every container with
it. Symptom: the model loads, answers a health check, reports Ready, and dies
~25 seconds later mid-answer. The app reports *"an error occurred while
sending the request"*, which points at the network and has nothing to do with
it — Windows reaches the container on `127.0.0.1` perfectly well while it is
alive.

1. **Fixed** by holding a WSL session open for the life of the conversation.
2. **Then four keepalives leaked** — they slept blindly for six hours and
   relied on being killed, and the window's shutdown fired that kill on a
   background task and returned, so closing the app could beat it.
3. **The leak fix reintroduced the original bug.** The keepalive was changed
   to watch the container and exit when it vanishes — but it starts *before*
   `docker run`, so on its first tick it saw nothing and exited immediately.

Now: sleeps first, leaves only once the container has been **seen and then
gone**, gives up after five minutes if it never appears. Verified alive at 20,
40, 60, 90 and 120 seconds, polled from Windows alone.

> Nothing else in the toolchain hits this, because the preview and deploy
> launchers stay attached to their container for the whole run. Only a
> detached, long-lived container needs the door held open.

### 6.3 The warm-up warmed a prompt nothing used

The worst one, because it looked like it was working.

The warm-up primed `[tools] + "Say ready."` with **no system message**. Every
real turn sends `[tools] + [system prompt] + text`, and llama.cpp renders
tools and system prompt into the same leading block — so the two prefixes
diverge almost at the first token. Three minutes spent, nothing cached that
any conversation would ask for, and the teacher paid again.

Measured on a fresh server:

| | warm-up | then a real turn |
|---|---|---|
| Without the system message | 20.7s | **29.6s** — paid in full, again |
| With it | 29.0s | **1.8s** |

**Sixteen times**, on a prefix far smaller than the real one.

> A test of a cache is order-dependent. The first attempt ran the matched case
> first, which cached the prefix and made the mismatched case look fast. The
> order of the test was part of the test.

### 6.4 llama.cpp's progress logging is too sparse to drive a bar

It reports `prompt processing … progress = 0.33` — but only once per completed
batch. Measured against a real prompt: **nothing for 81 seconds, one reading
of 32%, then silence** until the answer arrived. A bar driven by that sits at
zero, jumps a third of the way, and freezes — worse than no bar, because it
looks like a fault.

The bar is now **projected** from measured constants (~3.6 chars/token, ~21
tok/s) against the actual schema size, and corrected by a real reading
whenever one appears. Verified accurate: it predicted 2m 53s; the teacher saw
97% at 2m 48s.

### 6.5 Interface failures that measurement would not have caught

* **A progress bar that never entered the visual tree.** Added to
  `body.Parent as StackPanel`; `Parent` is not reliably set the instant an
  element joins a `Children` collection, so it went nowhere. The download ran
  showing the one frozen line the bar existed to replace.
* **Sixty seconds of a still window.** No thinking indicator at all. Silence
  and a crash look identical; a teacher who cannot tell them apart closes the
  window. Now: animated dots plus an elapsed count after five seconds.
* **"Ready." said before a three-minute wait.** The one line meant to orient a
  teacher, misleading them by three minutes.
* **Model-directed text shown to a teacher.** `explain_publishing` answers a
  returning section with *"this has been explained already — don't repeat it,
  carry on with what the teacher asked"*. That is addressed to a **model**,
  and the window printed it verbatim.
* **Markdown rendered as punctuation.** `TextBlock.Text` shows `**bold**`
  literally, so the emphasis in the most important sentence in the window
  arrived as asterisks.

### 6.6 Bigger models are not obviously the answer

Researched but **not measured here** (2026-08):

* **Qwen3-1.7B — 55.49% on BFCL.** Worse than what we run.
* **Qwen3.5-4B — 97.5%** in one practical eval, Q4_K_M is 2.74 GB. Fits the
  memory budget, but ~2.5× the parameters at 21 tok/s makes a cold read
  intolerable.
* **xLAM-2 and Hammer 2.1** top the Berkeley leaderboard at their sizes, yet
  scored **15%** and **20%** in a practical eval — attributed to **chat
  template incompatibility**, not model quality. Leaderboard position is a
  poor proxy for "works in llama.cpp with `--jinja`".

**Speed is the binding constraint before accuracy is.** Trimming the surface
helps both; a bigger model helps one and hurts the other.

### 6.7 Smaller traps worth knowing

* **Context.** A 18,030-token prompt was **refused outright** against a 16,384
  context. The untrimmed surface plus a real conversation was heading there.
* **`--parallel`.** The image now defaults to **four** slots, so `-c 8192`
  quietly allocated 32,768 tokens of KV cache. One window is one conversation:
  `--parallel 1`.
* **`schtasks` date format is locale-dependent** and rejects every other one.
  This machine wanted `yyyy/MM/dd`, not the documented `dd/MM/yyyy`. The code
  tries formats until Windows accepts one.
* **Deprecation.** `--no-mmap` now warns in favour of `--load-mode`. Still
  works; changing it is untested.

---

## 7. Where it stands, and what is unproven

**Working and verified:** the tool layer, the approval gate, publish/unpublish
polarity, undo, backups, per-section isolation, scheduled deploys (verified
firing unattended with Plantoir closed), the sidebar clock badge, the
container lifecycle, the download and its progress bar, the warm-up bar's
accuracy.

**Unproven, in the order I would test them:**

> Items 1–3 were run later the same day — see §10. The short version: the
> restore works and is worth 163 seconds a session, a real warm turn is
> ~12 seconds not ten, and the phrasing work took routing from 69% to 91% —
> 94% once two argument-level fixes landed.

1. ~~**Does a disk-cache restore actually skip the warm-up?**~~ **Yes — §10.1.**
2. ~~**Is a real warm turn under ten seconds on the FULL prefix?**~~ **No —
   about twelve seconds, and generation speed is the floor. §10.2.**
3. ~~**Did the phrasing work fix the 69%?**~~ **Yes — 91%, with the failures
   moved from routing to arguments. §10.3.**
4. **Class insertion against a real course.** Renaming classes rewrites links
   across a 132-page course; the tests use four synthetic classes.

---

> **Overturned on 2026-08-15, and worth reading as a lesson about desk
> research.** Every line of §6.6 above was researched rather than measured, and
> measured it reverses. There is no "Qwen3.5-4B" — the model is **Qwen3-4B**,
> 2.5 GB, and with `--reasoning off` it scores 180/180 on this exact probe set
> with a 0.74 s warm turn, beating the 7B on accuracy, latency, download and
> memory. Qwen3-1.7B's poor BFCL score was measuring a thinking model: with
> reasoning off it goes from 26% to 84% (still rejected, because it filled in
> TODAY's date on half its "tomorrow" calls). The arithmetic that made a bigger
> model look impossible — "2.5× the parameters at 21 tok/s" — assumed the
> container. On Metal the 4B is faster than the 1.5B was in the container. See
> `macos-native-10-trial-comparison.txt` and `reasoning-flag-measurement.txt`.

## 8. If you change one thing

*Written 2026-08-14. All three levers below have since been pulled: the routing
mitigation was re-measured the same day (§10.3, 91% then 94%) and again across
ten models on macOS; the surface was trimmed further still (the mac shows the
local model 13 of the 20 tools that exist — 22 as of 2026-09-06; the local 13
has not moved, the surface it is drawn from grew); and a different model was measured
in llama.cpp with `--jinja` rather than on a leaderboard — which is what changed
the shipping model. The advice held; it is the "unverified" and "not measured"
framing below that is now historical.*

**Re-measure the routing.** §6.1 is the only failure that is about the *idea*
rather than the plumbing, and the mitigation is unverified. Everything else
here is engineering that can be fixed by engineering.

If routing is still poor after the phrasing work, the levers in order of
expected value:

1. **Trim further** — 15 tools is not a floor. Publish, unpublish, plan, undo,
   rebuild is arguably six.
2. **A two-stage router** — one small call to pick a *category*, then a second
   with only that category's tools. Two short prompts beat one long one when
   prompt length is the cost.
3. **Only then, a different model** — and measure it in llama.cpp with
   `--jinja`, not on a leaderboard.

## 9. Rules that earned their place

* **Measure before believing, and measure the thing itself.** Reasoning
  produced "60 seconds of a dead window", a bar that could never move, and a
  warm-up that warmed nothing. Every one was found by running it.
* **Never withhold a capability as a safety mechanism.** Deploying was trimmed
  out of the local surface for speed, which silently removed a feature the
  teacher had asked for by name. The approval gate is the safety mechanism.
* **A promise the tools do not keep is worse than jargon.** The briefing said
  "I never deploy" after deploy went back in. A teacher who believes it will
  not think to check.
* **Tests pin meaning, not sentences** — but when they pin a sentence, the
  sentence is user-facing and the pin is the point.

---

## 10. The open experiments, run — 2026-08-14, later the same day

Everything below was measured against the real narrowed surface (15 tools,
3,411 prompt tokens — the descriptions have grown past the 2,783 quoted
above), in the same capped container, driven from outside the app. One
practical note for whoever does this again: hold a WSL session open for the
whole run, or the container dies the way §6.2 describes — it did, on the
first attempt, twenty-five seconds in.

### 10.1 The restore works, and it is the biggest win available

Cold read of the surface: **175–179 s**. Save the slot: 3,428 tokens,
98 MB, 140 ms. Kill the container, start a fresh one, restore: **30 ms**,
and the same request then runs in **11.7 s** — prompt evaluation touched
only the 35 tokens that were new. A control session with no restore paid
the full 175 s again. The three minutes really is once ever.

Why it had never been observed working: the save was fired blind
(`>/dev/null 2>&1`) from a `finally` that ran even when the warm-up had
died with the container, so it failed silently — and a save against an
*empty* slot succeeds with `n_saved: 0`, writing a valid 36-byte file that
makes the NEXT session say "picking up where I left off" and then read
everything anyway. Fixed on this branch: save and restore now parse the
server's reply and report truthfully, an empty save deletes its own file,
"Ready" is only said when the warm-up finished, and the cache file is named
per course *and section* — the prefix contains both (the system prompt's
first sentence names them), so one shared file could only ever be warm for
the last section that saved it. The name also carries a fingerprint of the
tool schemas, because the prefix is mostly tool definitions: an app update
that rewords one description would otherwise restore a prefix no
conversation matches — n_restored healthy, three minutes paid anyway,
behind "picking up where I left off". With the stamp, the old file simply
isn't found, the cold read is announced as one, and the save that follows
replaces the superseded file.

### 10.2 A real warm turn is about twelve seconds

Not under ten. Prompt evaluation is 3 s of it; the rest is generating
~50 tokens of tool call at roughly 5.5 tokens/second. Generation speed,
not prompt reading, is now the floor, and no amount of caching moves it.

### 10.3 Routing re-measured: 69% → 91% → 94%

The full suite (18 probes × 3 trials,
`research/ai-assist/trimmed-surface-suite.py`, descended from
`shipped-surface-suite.py`; raw rows in `trimmed-surface-results.txt` and
`cache-restore-results.txt` beside it):

| Surface | Accuracy | Inversions | Malformed | Wrong types |
|---|---|---|---|---|
| Old shipped surface (§6.1) | 31/45 (69%) | 0 | 0 | 0 |
| Trimmed 15 tools, as shipped | **49/54 (91%)** | 0 | 0 | 0 |
| + date appended + real-course examples | **51/54 (94%)** | 0 | 0 | 0 |

Every phrasing that fell through to `list_pages` in §6.1 — "put up…",
"take back down…" — now routes correctly. The failures that remain are
*argument* failures, and both had the same shape: **the model copies the
schema's examples when the request leaves a gap.**

* **Dates.** Nothing told the model today's date, so "publish tomorrow's
  class" produced `date: "2023-09-15"` — an echo of the schema's example
  date — on every trial that needed one. Appending "(Today is
  2026-08-14, a Friday.)" to the user message fixed all seven. **Prepending
  the same line dropped routing to 76%** — "deploy at 6:30 tomorrow" started
  going to a publish tool, and the deletion probe stopped declining — and
  putting it in the system prompt would invalidate the saved cache at
  midnight, because the tools render after it. Appended, and only appended.
* **Course codes.** With no course named — the window's normal case, since
  the teacher opened it on a section — the model wrote the schema's
  "for example ICS3U" **nine trials out of nine**, ignoring the system
  prompt's EXC2O, and once blended the two into ICS2O with the course named
  in the sentence. Rewriting the examples to name the window's actual course
  cured it: fifty-four trials after the change, not one wrong course. A
  router matches text; the only example it cannot copy wrongly is the right
  answer.

Both fixes are in `AssistAgent` (`Say` appends the date;
`NarrowToLocal(tools, courseCode)` rewrites the examples). The one miss
left standing: the formal phrasing "publish tomorrow's class *and make sure
every page it links to is published*" prefers `publish_pages` over
`publish_class_on`, 3/3 — a write, but one the approval gate holds and the
server validates, and the informal and typo'd versions of the same request
route correctly.

### 10.4 The promise card, measured — and turned into commands

Later the same evening the suite ran the window's own example card, word
for word, against the shipped configuration
(`research/ai-assist/promise-card-results.txt`). The split was stark.
**Arguments were perfect** — 87 trials, not one wrong course, wrong date,
wrong type, or polarity inversion. **Routing of the card's fixed phrasings
was not**: five of the eleven promises failed every trial. "Publish Unit 2,
Day 3, and everything it links to" went to the publish-by-DATE tool 3/3;
"What would publishing Unit 3, Day 1 change?" likewise; bare "Undo that"
was declined 3/3; "Deploy this section now" never reached the deploy tool;
"Deploy tomorrow's class at 6:30 AM" was answered with a publish plan. The
deploy-gate rewrite of the system prompt also made `undo_last_change`
over-salient ("I posted it by mistake, make it a draft again" → undo, 3/3)
and cost the deletion probe its clean decline. Overall: 63/87.

The response follows the architecture's own rule to its conclusion: a
promise the router keeps three trials out of four is not a promise, so the
card's fixed shapes stopped being routing questions. `AssistAgent` now
matches them in code and synthesises the exact tool call — same deploy
gate, same stop-edit-offer flow, instant — and the model keeps everything
conversational: dated titles, freeform pages, sentences with a story in
them. "Preview the site" had already made this journey (§10.3's cue fix
was measured still losing 3/4 before it did); the rest of the card
followed. Every command shape is pinned by the loop tests in
`Plantoir.Tests/AssistAgentTests.cs`, which run the whole card in two
seconds — the change-test-change cycle that found all of this no longer
needs a teacher's afternoon.


---

# Part 3 — The original MCP proposal

*From the Windows side, 2026-08-13, for consideration by the macOS side. Kept
because it is the record of how the feature was argued for.*

> **Both phases are built.** Phase 1 is `windows-app/Plantoir.Mcp/`, on `main`
> and bundled by `publish.ps1`. The **Phase 0 question — one shared .NET binary,
> or a Swift implementation of the same contract? — was answered on 2026-08-15
> by building the second**: the macOS app serves the identical tool surface from
> inside itself, `Plantoir.app/Contents/MacOS/Plantoir --mcp-stdio <folder>`, so
> there is no second binary to sign, notarise or forget. Windows keeps
> `plantoir-mcp.exe` as a separate signed binary, which is the right answer
> there for the same reason: Claude Code launches it itself.
>
> The duplication this document feared is paid in DEFINITIONS only. The mac
> copies the Windows server's tool descriptions verbatim, because the routing
> measurements are attached to that exact wording — rewording one spends a
> measurement somebody already paid for.
>
> Two design details below were superseded by measurement before either was
> built: the tool surface is coarser (`resolve_links` and `set_draft` are gone —
> given fine-grained tools a small model skipped link resolution 8 times out of
> 8), and publishing and hiding are separate tools rather than one call with a
> flag, because the model inverted the polarity of a hide request.

## The idea

Teachers increasingly have an AI assistant at hand (Claude Desktop, Claude
Code). If Plantoir ships an MCP server — the standard protocol those
assistants use to call external tools — a teacher could say:

> "Publish the Science courses overnight, and make tomorrow's class —
> Unit 2, Day 3 — no longer a draft, as well as all of the pages it
> directly links to."

…and the assistant would do it: find the courses, find the page, resolve its
links, flip the `draft:` flags, and run the publishes. The assistant does the
orchestration and the scheduling ("overnight" is the AI client's job — MCP
servers expose capabilities, they don't schedule). Our job is only to expose
honest, well-described tools.

## Why Plantoir is unusually well-suited to this

Everything an assistant needs already exists *below* the GUI:

- **Content operations** are plain-file edits — Markdown frontmatter and
  `course_config.json`. No app involvement needed.
- **Publishing** is `deploy.sh` / `deploy.ps1 CODE N` — the same shared
  launchers both apps shell. The MCP server is just *another consumer of the
  launchers*, exactly like the standalone-CLI use case we already protect.
- **The model layer is reusable.** On Windows, `Plantoir.Core` (course
  discovery, config accessors, the archiver/backup machinery from row 106)
  targets plain .NET with no UI dependency.

## The proposed route — and the decision that needs both sides

Three architectures were considered:

1. **Server inside each GUI app** — rejected. Overnight automation would
   require the app running; MCP clients want to spawn a stdio child process;
   and it means writing the server twice (Swift + C#).
2. **Python server in the toolchain container** — rejected. Publishing needs
   host-side pieces (the keychain/Credential Manager token, the file copies),
   and host Python violates the zero-prerequisite rule.
3. **A small self-contained .NET console app, `plantoir-mcp`, shipped beside
   the app** — ✅ **proposed.** Stdio transport (the client config is just
   `command: <path-to-binary>, args: ["--folder", "<working folder>"]`), runs
   headless, self-contained so teachers install nothing.

**The quietly big win — and the ask:** because the server has no UI
dependency, *one C# implementation can serve both platforms*. .NET publishes
self-contained binaries for `osx-arm64`; the server would invoke `deploy.sh`
on the mac and `deploy.ps1` on Windows, and the platform-neutral logic
(frontmatter edits, link resolution, name-form parsing) is written once and
tested once. The alternative is the usual mirroring: a Swift server on mac, a
C# server on Windows, and every behavior implemented twice forever.

This is the one decision that genuinely needs both sides: **is the mac side
comfortable bundling (or shipping beside the app) a .NET-published binary?**
If yes, the Windows side builds the server and the mac side's work is
distribution + the shared safety protocol below. If no, the tool contract in
this document becomes the spec both implementations follow.

There is an official MCP C# SDK (the `ModelContextProtocol` package, an
Anthropic/Microsoft collaboration); verifying its current API against our
solution is the first build step.

## Tool surface (v1)

Read-only discovery, safe edits, backup, and publish — deliberately **no
delete tools** in v1:

| Tool | What it does |
|---|---|
| `list_courses` | Codes, names, sections, publish target — read from the config files |
| `list_pages` / `read_page` | Enumerate and read a course's Markdown; every path validated to stay inside the working folder |
| `set_draft` | Flip `draft:` in one page's frontmatter — a line-level edit that preserves the teacher's formatting, never a YAML reserialize |
| `resolve_links` | A page's direct `[[wikilink]]` targets mapped to files, matching Quartz/installer semantics exactly |
| `back_up_course` | The row-106 whole-course backup. Tool descriptions steer the assistant to back up **before** bulk edits — the "handing a pile of pages to an LLM" scenario row 106 was designed for, closing its own loop |
| `publish_section` | Runs the deploy launcher non-interactively; parses the same Live-URL / `PUBLISHED_FOLDER` markers the GUIs parse; streams MCP progress notifications (publishes take minutes, and a first run may rebuild the toolchain image) |

## The one real risk: concurrency with the GUI

Each app's busy-tracking (`CourseActivity`, preview leases) is in-process —
an external server can't see the GUI's in-flight preview, and vice versa.
Overnight this is moot (app closed); daytime overlap could corrupt a build.

- **v1:** document the constraint, plus a best-effort probe (the `--stop`
  machinery already detects container processes by working directory).
- **v2:** move the activity registry to a small **file-based protocol that
  both the app and the server honor** — e.g. a lease file under the working
  folder. **Both apps would adopt this**, so it's a shared-design item even
  if the mac side passes on the shared binary.

Other guardrails: the server is locked to one working folder passed at
startup; deploy runs with stdin closed so a missing Netlify token fails fast
with "open Plantoir and publish once to store your token" instead of hanging.

## Phases

| Phase | What | Who |
|---|---|---|
| **0 — Decisions** | Shared C# server vs per-platform; how it ships on each OS; sketch the shared activity-file protocol | Both sides |
| **1 — MVP** | `PlantoirMcp` project with the six tools; frontmatter/link logic unit-tested; manual test against Claude Desktop / Claude Code in a real workspace | Windows first |
| **2 — Safety** | File-based activity registry shared with the apps; busy declines with plain-words reasons, in the apps' voice | Both sides |
| **3 — Teacher UX** | An "AI Automation" section in each app that **writes the MCP config snippet into Claude Desktop's config for the teacher** — no hand-edited JSON, ever; a docs page; mac distribution | Both sides |

Estimated effort for Phase 1 is roughly one working session on the Windows
side; the interesting conversations are Phase 0 and the Phase 2 protocol.

## Questions for the macOS side — all but one now answered

> **Q1: shared .NET binary on the mac, or the contract in Swift?** Swift. The
> tools are written against the app's own model layer, so a standalone binary
> would mean extracting that layer into a shared framework — a large refactor
> whose only benefit is a second binary to sign and keep in step.
> **Q2: inside the app bundle or beside it?** Neither: the app IS the server,
> behind `--mcp-stdio`. It cannot be forgotten by a packaging script.
> **Q3: objections to the v1 tool surface?** None, and the no-delete rule was
> tightened: the mac surface also has no rename and no archive, and removed
> every boolean argument it could, on the grounds that a boolean asks the router
> to reason.
> **Q4: the lease-file shape for the shared activity registry?** **Still open,
> and now the only open item.** Windows writes
> `<COURSE>.<kind>.<pid>.lease` files under `courses/.internal/activity/`
> (`Plantoir.Core/Assist/WorkLease.cs`, four kinds: assist, preview, publish,
> build); the mac has not adopted the format and still tracks activity
> in-process, so the cross-process race this was designed to prevent is
> unguarded there.



1. Shared .NET-published `plantoir-mcp` binary on mac — acceptable, or would
   you rather implement the tool contract in Swift?
2. Where should it live on mac — inside the app bundle, or beside it?
3. Any objections to the v1 tool surface (especially the no-delete rule and
   backup-first steering)?
4. Thoughts on the lease-file shape for the shared activity registry (v2)?

# 10. The Local AI Assistant

**Audience:** a computer science teacher who is comfortable with processes,
JSON and HTTP, but has not worked with language models before. This document
explains what the model in Plantoir actually is, how it is configured, and —
the part that matters most — exactly how a sentence a teacher types becomes a
Swift function call.

The short version: **the model never does anything.** It reads a sentence and
answers with the *name of a Swift function and its arguments*. Every rule,
every safety check and every file written is ordinary Swift code that would
behave identically if the model were replaced by a dropdown menu.

---

## Part 1 — Enough background to follow the rest

### What a language model is

A language model is a large mathematical function with a fixed set of
numbers inside it, called **parameters** (or *weights*). It takes a piece of
text and produces a probability distribution over what the next fragment of
text should be. That fragment is called a **token** — roughly a word-piece,
about four characters of English on average, so "unpublish" might arrive as
`un` + `publish`.

Generation is a loop:

```
text so far ──▶ model ──▶ probabilities for the next token ──▶ pick one
     ▲                                                            │
     └────────────────── append it and go round again ◀───────────┘
```

That is the entire mechanism. There is no database lookup, no plan, and no
execution of anything. A model that "calls a tool" is a model that has been
trained to *write out* a tool call as text, in a format the surrounding
program knows how to parse.

Two consequences worth holding onto:

- **The model is a text predictor, so its output is a suggestion, not a
  decision.** Whether the suggestion is acted on is the host program's
  choice. In Plantoir the host program is Swift, and it checks.
- **Everything the model knows about the current situation is in the text you
  send it.** It has no memory between requests. Each request carries the
  whole conversation again.

### The context window, and why it costs time

The **context window** is the maximum number of tokens the model can consider
at once — the conversation, the system instructions, and the descriptions of
every available tool, all counted together. Plantoir gives the model an 8,192
or 16,384-token window depending on the Mac.

Before generating a single token of reply, the model must read everything in
the window. That is called **prompt processing**, and it is why the *first*
message of a conversation is slower than the rest: about 2,650 tokens of
prompt, nearly all of it tool descriptions, have to be read before anything
else happens. Afterwards the work is cached (the **KV cache**, which is
roughly the other half of the memory the model occupies while running), so
later turns only process the new sentence.

### Quantisation, or why 4 billion parameters fits in 2.5 GB

Parameters are natively 16-bit numbers. Storing 4 billion of them would take
about 8 GB. **Quantisation** stores them at lower precision instead — Plantoir
uses `Q4_K_M`, roughly 4 bits per parameter — which cuts the file to 2.5 GB
and costs a small, measurable amount of accuracy. This is what makes running a
model on a teacher's laptop practical at all. The `.gguf` file extension is
llama.cpp's container format for quantised weights.

### How a "big" cloud model like Claude differs

Claude, ChatGPT and Gemini are the same *kind* of object — a next-token
predictor — at a wildly different scale, and operated differently:

| | A cloud model (Claude) | Plantoir's local assistant |
|---|---|---|
| **Parameters** | Undisclosed, but far larger — the public estimates are in the hundreds of billions | 1.5 or 4 billion |
| **Where it runs** | Racks of datacentre GPUs, shared between many users | One process on the teacher's Mac, on the Mac's own GPU |
| **Where your text goes** | Over the network to the provider | Nowhere. `127.0.0.1`, loopback only |
| **Cost** | Per token, billed to an account | None after a one-time 1.1–2.5 GB download |
| **Works offline** | No | Yes |
| **Context window** | Hundreds of thousands of tokens | 8,192 or 16,384 |
| **What it is good at** | Open-ended reasoning, writing, multi-step planning, ambiguity | Picking the right item from a short list and filling in its arguments |
| **What it is bad at** | Nothing relevant here | Anything requiring a chain of inferences, or judgement about meaning |

The last row is the design constraint that shapes everything below. A 4B
model is not a small Claude — it is a different tool with a much narrower
competence. **Plantoir is built around what a small model is genuinely
reliable at, rather than asking it to do less well what a large one does
well.**

### Tool calling, the mechanism everything rests on

Modern instruction-tuned models are trained on a convention: you send, along
with the conversation, a list of **tools** — JSON Schema descriptions of
functions the host program is willing to run. The model may then reply not
with prose but with a structured **tool call**:

```json
{ "name": "publish_class_on", "arguments": "{\"course\":\"EXC2O\",\"section\":1,\"date\":\"2026-08-16\"}" }
```

The host program parses that, runs its own code, and sends the result back as
another message so the model can describe what happened. **The model has no
ability to run the function itself** — it can only ask, and Plantoir's Swift
code decides.

This is the same mechanism Claude Code uses when it edits a file, at a
different scale. It is also why "prompt injection" is a real concern in
general: if a model can be persuaded to ask for something dangerous, the
question becomes whether the host program will do it. Plantoir's answer is
structural — see *No dangerous tool exists* below.

---

## Part 2 — How the model is configured

### The engine

The model is run by **llama.cpp**, an MIT-licensed C++ inference engine. Its
HTTP server, `llama-server`, ships inside the app bundle at
`Plantoir.app/Contents/Resources/llama/` (about 25 MB, fetched at build time
by `mac-app/Vendor/fetch-llama.sh` rather than committed to the repository).
The binary carries an `@loader_path` rpath so it finds its own dylibs; an
environment-variable arrangement would have worked in development and failed
the moment the app was notarised, because the hardened runtime strips `DYLD_*`.

**It runs natively, not in the Docker container that builds the site, and that
single decision is the whole feature.** Colima is a Linux VM with no access to
Metal, so a model inside it runs on virtual CPU cores while the GPU sits idle.
Measured on an M4 Pro, same model and same prompt: **175 seconds to read the
prompt in a container, 2.1 seconds natively.**

Swift starts it as an ordinary child process
(`AssistServerHost.start()`), waits for its health endpoint, and terminates it
when the window closes.

### The command line, flag by flag

From `AssistServerHost.serverArguments` — the single testable place where the
engine's configuration lives:

| Flag | Value | Why |
|---|---|---|
| `--model` | the `.gguf` path | Downloaded once to `~/Library/Application Support/Plantoir/models`, not bundled — that keeps 2.5 GB out of every app update and off the Macs of teachers who never open the assistant |
| `--host` | `127.0.0.1` | Loopback only. Nothing on the network can reach it |
| `--port` | chosen at launch | Each window gets a free port, so nothing collides |
| `--ctx-size` | `8192` or `16384` | The context window, sized by tier. The cache it implies is the part of the model's memory you can actually change — 2.5 GB of weights stays 2.5 GB — so this is the memory dial |
| `--n-gpu-layers` | `999` | Put every layer on the GPU. "999" means "all of them, whatever the count". This is the entire reason for running natively; a partial offload would leave the slow path in play |
| `--threads` | 2–6 | Half the performance cores, capped at six. Generation on Apple silicon is bound by memory bandwidth long before thread count, so taking every core buys almost nothing and makes the machine feel seized while a build may also be running |
| `--jinja` | — | Use the chat template embedded in the model file (see below) rather than a guess at its format |
| `--parallel` | `1` | One conversation per server. Each assistant window has its own |
| `--reasoning` | `off` | **See below — the most consequential flag on the line** |
| `--reasoning-budget` | `0` | Second line of defence for the same thing |

### The chat template, and why `--jinja` matters

A `.gguf` file contains, alongside the weights, a **Jinja template** that
defines how a conversation is turned into the exact token sequence the model
was trained on — where the system prompt goes, how a tool list is rendered,
what marks the start of an assistant turn. Different model families use
completely different conventions, and getting it wrong degrades a model
silently rather than visibly.

`--jinja` tells llama.cpp to use the model's own template. This is also how
two otherwise attractive candidates were disqualified during selection:
**Phi-4-mini and Gemma-2 have no branch in their templates for a top-level
`tools` array at all**, so tool calling could not be expressed to them.

### Thinking must be off, and it takes two flags

Some recent models, Qwen3 among them, are trained to produce a hidden
*reasoning* passage inside `<think>` tags before answering. For open-ended
problems that helps. For choosing one function from a list of thirteen it is
pure cost — and worse, on a long prompt the model can exhaust its token budget
inside the thinking block and never reach the tool call at all. The same
weights measured **39% routing accuracy with thinking on and 97% with it off.**

The two flags do different jobs, and only one of them actually stops it:

- `--reasoning off` tells the chat template not to open a thinking block.
- `--reasoning-budget 0` caps how long it may think *once started*.

Plantoir shipped with the budget alone for several days, on the
reasonable-sounding assumption that a budget of zero meant no thinking. It
does not. Measured on one prompt against the 20-tool surface the model was
shown at the time (4,475 tokens — larger than today's, so the seconds are not
directly comparable with the table further down; the direction is what
matters):

| Flags | Time | Tokens generated | Tool call |
|---|---|---|---|
| `--reasoning-budget 0` | 16.1 s | **512** | correct |
| `--reasoning off` | 8.4 s | **44** | correct |
| both | 8.4 s | 44 | correct |

The useful reply is 44 tokens; the other 468 were thinking nobody sees. Both
flags are now passed, and a unit test asserts both — the budget stays as
insurance against a future model whose template ignores `--reasoning`.

**The instructive part is why this survived review for so long.** The wrong
flag does not produce a wrong answer, it produces a slow one, and the two
obvious checks both come back green: a tool call *does* arrive, and there is
no `<think>` tag in the reply — because llama.cpp parses the thinking out into
a separate field by default. Absence of the tag proves the parser ran, not
that the model stayed quiet. The honest signal was the token count and the
clock.

### Which model, on which Mac

| Machine | Model | Download | Resident while running | Context |
|---|---|---|---|---|
| Under 16 GB RAM | Qwen2.5 1.5B | 1.1 GB | 1.75 GB | 8,192 |
| 16 GB and up | Qwen3 4B | 2.5 GB | 5.04 GB | 16,384 |

Apple silicon only — the whole design rests on Metal.

**The memory rule is the default, not the last word.** Plantoir ▸ Settings…
(⌘,) lets a teacher take either rung outright, or leave it on "Choose for me"
— which is the factory setting and keeps following the table above rather than
freezing today's answer into their preferences. The same panel downloads a
model ahead of time and removes one to get the disk space back. The teacher
never sees a model name there either: the two rungs are "the smaller
assistant" and "the larger assistant", described by what they cost in disk and
in memory. A hand-picked rung that would take more than a third of the
machine carries a caution naming both numbers and stays selectable.

**Removing one is refused while any assistant window is open**, and the
refusal names the section to close rather than saying it is unavailable
("Close the assistant for ICS3U Section 2 before removing this."). The guard
is deliberately about ANY open assistant, not about whether that window is
using that particular rung: working out which file is genuinely mapped into a
running engine means tracking state neither app keeps, and getting it wrong
deletes the weights out from under it. Removing the rung a teacher has CHOSEN
is allowed on purpose — it is the state every machine is in before its first
download, and refusing would trap somebody who wants their disk space back
behind a choice they did not want to change. The rule is
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`assistantModelChoice.removal`, and both suites run it.

One consequence worth knowing when reading the code: the tier decides the
context size, so anything that starts the engine must be given the CHOSEN
tier, never `AssistHardwareBudget.tier`.

Every rung was chosen by measurement, and **two candidates were vetoed for a
specific failure that no accuracy score would have caught**: asked to *hide* a
page, Qwen2.5 3B called the publish tool in 9 trials out of 10, and
Llama-3.2 3B in 10 out of 10 — on the same sentence, despite being unrelated
model families. This is called a **polarity inversion**: not a failure to
understand the request, but doing the exact opposite of it.

It is worth being precise about why that is the veto, because the obvious
reason is not the real one. Publishing a page does **not** put it in front of
students — in Plantoir, *publishing* marks a page for inclusion, and
*deploying* is the separate act that sends the built site to the web. An
inversion is therefore recoverable: nothing is visible to anyone until a
deploy, and `undo_last_change` takes it back.

What makes it the veto is that it fails **silently and in the wrong
direction**. Every other kind of routing mistake announces itself: the wrong
tool runs and the teacher sees an answer that has nothing to do with what they
asked. An inversion produces a confident report that the thing was done, while
the section is left in the opposite state to the one the teacher asked for —
and *that* state is what the next deploy faithfully carries out, days later,
with no reason for anyone to look again. A model that can do the opposite of
what it was told is not a model whose other 70% can be trusted, which is why
this is treated as disqualifying rather than as points off a score.

There is no 3B rung in the app as a result.

*(In the interface none of this is ever named. A teacher is told "the small
assistant" or "the larger assistant" and a download size; model names,
parameter counts and token budgets say nothing a teacher can act on.)*

---

## Part 3 — The path a command takes

### The one-screen version

```
Teacher types "Publish tomorrow's class"
        │
        ▼
AssistAgent  (Swift)
        │   builds ONE HTTP request:
        │     • system prompt (the rules, in English)
        │     • the conversation so far, each message with
        │       "(Today is 2026-08-15, a Saturday.)" APPENDED
        │     • 13 tool definitions as JSON Schema
        ▼
POST http://127.0.0.1:<port>/v1/chat/completions
        │
        ▼
llama-server ──▶ the model reads ~2,650 tokens, then writes:
        │            {"name": "publish_class_on",
        │             "arguments": "{\"course\":\"EXC2O\",\"section\":1,
        │                            \"date\":\"2026-08-16\"}"}
        ▼
AssistAgent parses the call
        │
        ├──▶ is this a WRITE? ──▶ yes: plan mode. Show the teacher what
        │                              will happen. Wait for Go or Cancel.
        ▼
AssistToolRunner.run(call:)   ← ordinary Swift from here on
        │   • resolve "the class dated 2026-08-16" against the section
        │   • apply the linked-page rules (see below)
        │   • take a backup if this conversation has not already
        │   • rewrite the frontmatter
        │   • rebuild the preview
        ▼
Result is appended to the conversation as a tool message
        │
        ▼
The model reads it and writes one plain sentence for the teacher.
```

The model appears exactly twice: once to choose the function, once to narrate
the outcome. Everything between those two moments is Swift.

### The sentences that never reach the model at all

Some of them appear once, or not at all. The window's suggestion cards are the
phrasings it TELLS a teacher it is good at, so a teacher clicks one — or types
it word for word — and the assistant had better be good at it. Measured, the
model misrouted **five of the eleven in every trial**, while filling in the
arguments perfectly.

So the fixed shapes with no ambiguity in them are matched in Swift
(`AssistCardCommand`) and the tool call is built directly. The model keeps
everything with a story in it: the requests a teacher phrases their own way,
which is what a language model is actually for. Matching is deliberately
strict — trimmed and case-insensitive, otherwise exact — because a loose match
would swallow a sentence that only LOOKS like a card ("publish tomorrow's
class, but not the linked pages") and answer the wrong question with total
confidence, which is worse than routing it.

This is the same principle as the coarse tools: reasoning moved out of the
model is reliability bought back. It is also the honest caveat on the 110/110
in Part 5 — some of those are perfect because they are not questions.

Two changes were made to the table on 2026-09-19, both for measured misroutes
and both described below (one new family, one widened — the count of parsed
families is still six): "deploy at &lt;time&gt;" in "A time is a number, not a
judgement", and the widened hide/unpublish frame in "'Hide' is 'unpublish', and
a reply that is the question again". The second one is also the answer to "what
should the app SAY when the model hands the teacher their own sentence back?",
which is a different question with a different fix.

A third came on 2026-09-25, and it is the one to read for a READ answered in
code: "What does Unit 2, Day 3 link to?" in "'What does this page link to?' is
answered in code" below. The count of parsed families at that point is
**nine** — #267 had added two for clubs, and this is the ninth
(`AssistCardCommand.everyParsedShape`; count it there rather than from prose).

### A time is a number, not a judgement

Written 2026-09-19, closing [issue
#168](https://github.com/russellgordon/plantoir/issues/168). The shelf offers
**"Deploy at 6:30 AM"** word for word, and the smaller assistant answered it
with `deploy_section` — an immediate deploy, to students — **10 trials out of
10 at temperature 0.1 and 3 out of 3 through the app's own request body**
(Qwen2.5-1.5B, ctx 8192, shipped prompt, Metal, 2026-09-18;
`research/ai-assist/metal-routing-results.txt`). The 4B is correct 10/10 on
the same sentence, so there is nothing wrong with the card.

**Two things were done, and they are independent.** Either would have helped;
together they cover both the sentence that was measured and the ones that were
not.

**1. The immediate approval card now says it is immediate.** The two approval
cards were asymmetric exactly where a misroute lands: `schedule_deploy`'s names
the whole moment, and `deploy_section`'s named no time at all — so a teacher
who asked for half six tomorrow read a card that was perfectly true and said
nothing to contradict them. `AssistWording.deployApproval` now leads with the
fact that it happens now; the two sentences after it, which have been argued
over twice, are untouched. **`deployQuestion` was deliberately NOT changed**:
at the time it was said under EVERY approval card including the scheduled one
(`AssistAgent.run(settledCall:)` was unconditional, and Windows' `AskFirst`
likewise), so "Shall I deploy now?" would have made the scheduled card read
worse than the thing being fixed. Splitting the question per tool was its own
piece — [issue #184](https://github.com/russellgordon/plantoir/issues/184),
done 2026-09-23: the scheduled card now carries `AssistWording.scheduleQuestion`,
chosen by `AssistAgent.approvalQuestion(forToolNamed:)`. The choice is keyed on
the tool NAME, not on `needsApproval`, so a third approval tool added later
falls to `deployQuestion` — the reading ("now") that is safe for anything that
deploys. `SharedRulesContractTests.testTheScheduledCardAsksItsOwnQuestion`
pins the mirror of the rule below: the scheduled question must NOT carry the
immediate card's word, read from the same contract rule; and the authored
scenario "an immediate deploy's card still asks the immediate question" pins
the other half on BOTH platforms. The Go bubble
(`deployAccepted`) and the cancel line (`deployWasCancelled`) were left as they
are — both are true of a scheduled deploy too; whether they should say
"schedule" is a question for the wording pass, not a fault. The rule is
pinned as a PROPERTY rather than a sentence:
`contracts/shared-rules.json` → `assistantConfirmation.`
`theImmediateDeployCardSaysItIsImmediate` carries the word the sentence must
contain, and both suites can run it, so it survives the next rewording.

**2. "deploy at &lt;time&gt;" is a sixth parsed family and never reaches the
model.** A time in a fixed frame is a NUMBER, not a judgement — the same
argument `makeRoom` already won for "make room for two classes at Unit 3, Day
4" — and this is CLAUDE.md's standing rule applied exactly: steer the model
with code, not with tool descriptions. The frame, after trimming, case-folding
and removing a trailing `.`, `!` or `?`:

```
[please] deploy [it|this section] [today|tomorrow] at <time> [today|tomorrow] [please]
```

**The rule that carries the most weight: a time with no am or pm must be
written with two digits for the hour.** That is what 24-hour time looks like
and it is the form `schedule_deploy`'s own schema asks for, so `06:30` and
`18:30` are read and **`6:30` is not** — morning or evening, and nobody can
tell which. A deploy set twelve hours wrong is a site that updates after the
class it was meant for, so nothing is scheduled: since issue #194 the app ASKS
which, in code (below), and until then the doubt went to the model. `noon` and `midnight` are both
accepted, alike, and so are `12 pm` and `12 am`: one rule rather than two, and
the card names the day it landed on. **The hour is one or two digits either
way**, which is stated rather than inherited: `Int` does not care how a number
was padded, so without the bound "007:30 am" would be read as half past seven
while the other platform, implementing from the accepted rows, would refuse it
— a difference no suite could see. Two `refused` rows pin it. A section number, a course code, a
weekday, a condition or a second request all fall through — the window is
scoped to ONE section and binds it whatever the sentence said, so a card
appearing to honour another section would answer a different question with
total confidence. (That is about the SECTION, and about a card. A course code
the MODEL writes is a different matter entirely — it is guarded rather than
bound; see "Never ask the model for something the window already knows".)

Every accepted, asked and refused spelling is DATA, in
`contracts/assist-cases.json` → `deployAtATime` (23 accepted, 25 asked, 45
answered with the spelling to use (`sayItAs`), 51 refused, 11 resolving rows —
count them rather than trusting this line),
authored rather than generated and preserved across `--write-contracts`. One
example and one near-miss — all `cardPhrasings.parsed` can carry — would have
described a grammar of times as a single spelling, and the other platform would
have built one spelling.

**"Deploy at 6:30" is ASKED about, in code, and never reaches the model (issue
#194, 2026-09-25).** Refusing to read a one-digit hour with no am or pm was
right; handing the sentence to the model instead was the fault, because the
smaller assistant answered "Deploy at 6:30 AM" — the same sentence with MORE
information in it — with an immediate `deploy_section` 10 trials out of 10
(Qwen2.5-1.5B, ctx 8192, Metal, 2026-09-18). So a sentence the family would
read if it carried am or pm, and whose time is a one-digit hour 1–9 with two
digits of minutes, now gets `AssistWording.morningOrEvening` in reply: the
question, "nothing is set yet", and two sentences to type — built by
`AssistCardCommand.morningOrEvening` through `deployFrame`, the SAME frame
`deployAtATime` reads, so the two cannot disagree about what counts as "deploy
at a time". Nothing is scheduled and no card goes up.

Near-spellings are asked about as well, because each still reached
`deploy_section` 10 trials out of 10 when it went to the model (measurement
below): a full stop for the colon, `deploy at 6.30`, and a comma after the
time, `deploy at 6:30, please` — the comma the frame leaves behind when it
takes "please" off the end (both the #194 fix round) — and, since #277, a
DOTTED two-digit hour 10 to 12, `deploy at 10.30`, `deploy at 11.45`. A dotted
10–12 is asked rather than read as 24-hour time because "10.30" is how a
teacher writes half past ten at night as often as in the morning; a COLON
`10:30` is not asked, because the family already accepts `deploy at 10:30` as
the morning. Asking is safe whatever was meant: nothing is set, the clock is
named back with a colon, and both answers are built with one, so no such
spelling is ever offered back. What the family ANSWERS did not widen for any
of this; a time it can read but does not set — `deploy at 6.30 pm`, `… 6:30
tonight` — is answered with the spelling to use instead (#277, below).

- **Both answers are sentences the family already accepts**, in one canonical
  form — `deploy [today |tomorrow ]at H:MM am|pm` — never an echo of the
  teacher's words ("please", "it", a trailing "tomorrow" all move or go).
  Measured with the real matcher (`AssistCardCommand.swift` compiled on its
  own, 2026-09-25): all 24 canonical answer sentences (1:00, 6:30, 9:59 and
  12:30 × no day, today, tomorrow × am, pm) reach `schedule_deploy` with the
  right `when`. (12:30 is never ASKED about — two digits of hour are read as
  24-hour time — but its answers are the same grammar.) `ScheduleDeployCardTests` runs every
  `asked` row's two sentences through `matching` — the "both halves or neither"
  rule the rollover question already keeps.
- **Stateless.** `AssistAgent.say` checks for the question right after the
  matcher returns nothing and BEFORE the message is appended for the model; the
  teacher's sentence and the question go into `entries` (the transcript) only,
  never into `messages`, so the model sees neither on this turn or any later
  one. The teacher answers by typing one of the two sentences, which matches in
  code on that turn. Nothing waits for an answer, so there is nothing to clear
  when the teacher asks something else instead.
- **The trail** reuses `assistant matched a fixed phrase` with the line
  `AssistAgent.askedMorningOrEveningLine` — no clock in it, because the clock
  is something the teacher wrote; `assistant asked` already has the sentence.
  Its `carries` in `contracts/shared-rules.json` says so (rule 5's
  changed-behaviour clause). No new event name, so Windows' by-name trail test
  does not move.
- **Not asked, deliberately:** `deploy at 7` (a bare number may not be a time
  at all — the contract row's written reason stands), `deploy at 0:30` (0 is
  not an hour on a twelve-hour clock, so there is no morning or evening to
  choose between), `deploy at 6:3`, and anything the frame refuses — a day word
  on both sides, a section, `can you…`. Those still go to the model, and each
  is a `refused` row that asserts it is neither answered, asked nor given a
  spelling. A part of the day — `deploy at 6:30 tonight`, `… in the evening`
  — was on this list when #194 shipped; since
  [#277](https://github.com/russellgordon/plantoir/issues/277) it is answered
  with the spelling to use, or asked about when the hour does not fit it
  (below).
- **A `today` question can offer two answers that are both refused.** "deploy
  today at 9:15" typed at 22:00 is asked about, and both `deploy today at
  9:15 am` and `… pm` meet the runner's "…has already passed" refusal — by
  design, since a named day is never moved (below). Nothing is set either way;
  the teacher reads a refusal rather than a wrong deploy.
- **The MCP path is unaffected.** `AssistAgent.say` is called only from
  `AssistWindowView`; an MCP client calls `schedule_deploy` directly with its
  own `when`, and no tool, schema, description or system-prompt byte moved (both
  tool-surface hashes identical before and after, `--write-contracts` run
  twice).

**The risk this leaves — measured, and it is not where it was first
expected.** Measured by the #194 review (Opus 5.5, 2026-09-25): Qwen2.5-1.5B
Q4_K_M, ctx 8192, the app's own server flags, Metal, Apple M4 Pro; the
branch's system prompt and 13-tool surface, the app's request body
(temperature 0), the date line appended, a fresh conversation each time —
which is exactly what the model sees, since the question never enters
`messages`. Ten greedy trials per sentence, so a trial count rather than a
rate:

| Sent to the model | Chose (10 trials) |
|---|---|
| `pm` | check_section 10 |
| `evening` / `in the evening` / `no idea` | declined, 10 each |
| `6:30 pm` / `at 6:30 pm` / `6:30 in the evening` | schedule_deploy 10 each, `when` 18:30 today |
| `tonight` / `the evening one` / `am` | check_section 10 each |
| `morning` | read_remembered_timetable 10 |
| `6:30 am` | schedule_deploy 10, `when` 06:30 today (already past, so the runner's refusal) |
| `deploy at 6:30` (what the model was sent before this piece) | **deploy_section 10** |
| `deploy at 6.30` | **deploy_section 10** |
| `deploy at 6:30, please` | **deploy_section 10** |
| `deploy at 6:30 tonight` | **deploy_section 10** |
| `deploy at 6:30 in the evening` | **deploy_section 10** |

A teacher who answers the question in their own words is **not** the risk:
0 of 120 reply trials (twelve replies) chose `deploy_section`; the replies that
name a time produced a correctly timed `schedule_deploy` card, the rest a read
or a decline. That settles the stateless design against a reply-reader. What
still deployed on the spot was a sentence one character away from the issue's
own that escapes the frame — and it is also the first time `deploy at 6:30`
itself was measured rather than inferred (10 of 10 on the dev branch before
this piece). The fix round widened what is ASKED to the first two
(`6.30`, `6:30, please`), which are asked-about rows now.

**What deployed on the spot after #194, 10 of 10 — CLOSED by #277.** Every
sentence on the list below is now answered in code (asked about, or given the
spelling to use) and none of them reaches the model; the list is kept because
it is the evidence #277 was decided on. Measured by the review of the fix round (Opus 5.5, same conditions: Qwen2.5-1.5B
Q4_K_M, Metal, Apple M4 Pro, 10 greedy trials, 2026-09-25), every one of
these reached `deploy_section` 10 of 10, and the matcher sends every one to
the model:

- a full-stop time WITH am or pm: `deploy at 6.30 pm`, `deploy at 6.30pm`,
  `deploy at 6.30 am` — `deploy at 6.30 pm` is the `refused` row this piece
  itself chose as the boundary;
- a comma after a time that has am or pm: `deploy at 6:30 pm, please`,
  `deploy at 6:30pm, please`;
- a two-digit full-stop time: `deploy at 10.30`, `deploy at 11.45`,
  `deploy at 18.30`;
- a day-part word: `deploy at 6:30 tonight`, `deploy at 6:30 in the evening`,
  `deploy at 6:30 in the morning`.

(`deploy tomorrow at 6.30 pm` and `deploy at 6.30, then preview` were declined
10 of 10.) **The asymmetry, stated plainly:** `deploy at 6:30, please` is asked
about, while `deploy at 6:30 pm, please` — the same sentence with MORE
information in it — deploys now. The gate asks only about a time with no am or
pm, because that is #194's subject; it does not catch a time that says am or
pm in a spelling the family cannot read. (That was the state after #194; #277,
below, closed it.)

**The fix #194 left to [#277](https://github.com/russellgordon/plantoir/issues/277),
and #277 made it:** reply in code with the canonical rebuild — "say it as
`deploy at 6:30 pm`" — which sets nothing, exactly as the question for `6.30`
sets nothing. It was not done in #194 because it widens which sentences are
intercepted well beyond "no am or pm", and reading a part of the day was
Russell's call; he made it on 2026-09-25 (ASK, IN CODE).

The probe that produced both tables was a one-off copy of
`research/ai-assist/trimmed-surface-suite.py` with its `CASES` loop replaced by
a loop over the sentences above, each sent in a fresh conversation with the
date line appended; it was not kept. To re-run the tables — do so if the
model, quant, prompt or tool surface changes — make the same substitution.

**Rejected, and why:**
- a pending "waiting for morning or evening" state that accepts "morning",
  "evening" or "pm" as replies — a new near-miss surface, state that must
  survive or clear across turns, and a larger Windows mirror, to save a few
  keystrokes; the rollover question already chose the stateless form;
- asking about `deploy at 7` too — the contract's written reason for refusing a
  bare number is a decision, and changing it is Russell's;
- guessing morning, or loosening the refusal in any way — issue #194 says it
  "should NOT be loosened".

**A time written a way the family cannot set is answered with the spelling to
use (issue #277, 2026-09-25).** `deploy at 6.30 pm`, `deploy at 6:30 pm,
please`, `deploy at 18.30`, `deploy at 6:30 tonight`, `deploy tomorrow morning
at 7:00` — every one names a moment a person reads without hesitation, the
family does not ACCEPT the spelling, and those that were measured reached
`deploy_section` 10 of 10 when they went to the model (the table above). Russell's decision was
**ASK, IN CODE**: `AssistCardCommand.timeToSayAs` reads the sentence, and
`AssistAgent.say` answers — after the matcher and the morning-or-evening
question, before `messages.append` — with `AssistWording.sayTheTimeAs`: the time
as the teacher wrote it and ONE sentence to type, in the canonical form
`deploy [today |tomorrow ]at H:MM am|pm`, and "Nothing is set yet". Transcript
only, no card, nothing scheduled, nothing waiting for an answer; the sentence it
names matches in code on the next turn. The trail line is
`AssistAgent.askedToSayTheTimeAsLine` on the same `assistant matched a fixed
phrase` event (no clock, for the reason the #194 line has none; its `carries`
amended in `contracts/shared-rules.json`, no new event).

The rule, which `deployAtATime.note` states as data:

- **The frame is `deployFrame`, unwidened**, plus one thing `timeToSayAs` alone
  reads: a part of the day in FRONT of "at" (`deploy tonight at 6:30`), which
  is moved to the end and the rebuilt sentence read by `deployFrame` itself —
  so what the family ACCEPTS does not move, and there is still one frame.
- **Caught only for a reason**, of which there are three: a full stop between
  hour and minutes, one comma after the time (or before a part of the day), or
  a part of the day — `in the morning|afternoon|evening`, `this
  morning|afternoon|evening`, `tonight`, `tomorrow morning|afternoon|evening`.
  A spelling the family refuses for a reason of its own (`13:30 pm`, `6:75
  pm`, `deploy at 7`) is not caught: its refused row's reason stands.
- **A part of the day is a window, not just am or pm** (the plan review's M1,
  ruled 2026-09-25): morning 12 (12 am) and 1–11, afternoon 12–5, evening
  5–11, tonight 5–11 with 12 as midnight. (Morning read 1–11 only until the
  fix review's M2: `deploy at 12:30 in the morning`, the most natural way to
  write 00:30, went to the model and deployed on the spot 10 of 10; it now
  reads 12 the way tonight does.) The plan first mapped a part of the day straight to am
  or pm, and `deploy at 1:30 tonight` came back as `deploy today at 1:30 pm` —
  the wrong-part-of-the-day suggestion #194 exists to prevent. Outside its
  window a time is never given a spelling: a one-digit hour with no am or pm
  gets the #194 question instead (`deploy at 2:30 in the evening` → "Is that
  2:30 in the morning or in the evening?"), and anything else goes to the
  model, as before.
- **Midnight tonight has no day word** — `deploy at 12:30 tonight` becomes
  `deploy at 12:30 am`, because midnight tonight is the start of tomorrow and
  a bare time settles onto the next one; `today at 12:30 am` would already
  have passed. "Today" and "tonight" in one sentence agree and tonight
  decides (the fix review's L3), so `deploy today at 12:30 tonight` gets the
  same answer and `deploy today at 1:30 tonight` asks with no day word.
- **A day word the comma kept from the frame is read** (the fix reviews' L1
  and L1'): `deploy at 6:30 pm tomorrow, please` is answered like `deploy at
  6:30 pm, tomorrow`, and `deploy at 6:30 tomorrow, please` is ASKED like
  `deploy at 6:30 tomorrow` — for a time with am or pm and for a one-digit time
  without, whether the day word comes before the comma or after it does not
  decide what the teacher gets. (A day word on BOTH sides is still refused.)
- **With neither am/pm nor a part of the day** the hour must be two digits (the
  24-hour reading: `18.30` → 6:30 pm, `00.30` → 12:30 am). A one-digit hour is
  already the #194 question, and a dotted 10–12 is asked too (above). A COLON
  10–12 with a comma, `deploy at 10:30, please`, is answered as 10:30 am,
  because `deploy at 10:30` is already accepted as the morning and a comma must
  not change the reading.
- **A disagreement is refused, never resolved**: am/pm against the part of the
  day (`6:30 am in the evening`), a day word against the part of the day's day
  (`deploy tomorrow at 6:30 tonight`).
- **The reply does not name back a time that was never the problem** (the plan
  review's M3, and the fix review's M1): when the teacher's own sentence, with
  its commas taken out, is one the family SETS for the same moment as the
  sentence handed back, the reply says "…, without the comma" instead of
  naming the time back — `wording.sayTheTimeAsWithoutTheComma`, a second
  rendering of `AssistWording.sayTheTimeAs`, chosen by
  `AssistTimeRespelling.onlyDifference`. It is decided by the MATCHER and the
  moment, not by comparing text: the first version compared text with the
  canonical sentence, so `deploy it at 6:30 pm, please`, `deploy at 7 am,
  please` and `deploy at 6:30 pm, tomorrow` named the teacher's own time back
  as if it were wrong. A "without “please”" form was ruled as well and is NOT
  built: taking "please" out too was measured unreachable (0 of 113,400
  sentences, the compiled Swift), because the frame already takes "please" off
  either end — a key the app could never say would have been a sentence in the
  contract that is not true.

Measured before it was relied on, against the COMPILED Swift
(`AssistCardCommand.swift` built on its own, 2026-09-25, re-run after the fix
round): a grid of 1,342,656 sentences (14 frames, including four with a part
of the day before "at" × 37 hour spellings × 6 minute spellings × `:`/`.`/`,`
× 8 am/pm spellings × 18 tails) — 4,878 accepted, 4,044 asked, 66,228 given a
spelling, the rest to the model. **0** sentences in two of the three; **0**
differences from the research guard's Python MIRROR (`respelling_reading` —
written by the same hand from the same rules, so agreement shows the two say
the same thing, not that either is right; the legs that follow are the real
checks); all 216
distinct suggested sentences accepted by the family and already in canonical
form; 13,698 full-stop or comma spellings whose colon twin the family accepts,
**0** landing on a different `when`; 38,274 respellings from a part of the day,
**0** outside its window; 1,776 questions from a part of the day, every one a
clock the #194 question can name. `ScheduleDeployCardTests` runs every
`sayItAs` row, and the sentence each hands back, through the real matcher.

**What STILL reaches the model, measured.** The 24 must-not-catch rows in
`deployAtATime.refused` (each is a row asserting it is neither answered, asked
nor given a spelling), including the two shapes the ruling let stay —
`deploy at midnight tonight` and `deploy at 9 at night`. Measured for this
piece: Qwen2.5-1.5B Q4_K_M, ctx 8192, the app's server flags
(`AssistServerHost.serverArguments`), Metal, Apple M4 Pro; the shipped system
prompt and 13-tool surface, the app's request body (temperature 0), the date
line appended, a fresh conversation each; 10 greedy trials each, 2026-09-25:

| Sent to the model | Chose (10 trials) |
|---|---|
| `deploy at 6,30`, `deploy at 6.30 pm, then preview`, `deploy at 13.30 pm`, `deploy at 0.30`, `deploy at 6.3 pm`, `deploy at 7, please` | **deploy_section 10** each |
| `deploy at 18:30 in the morning`, `deploy at 6:30 am in the evening`, `deploy at 11:30 in the afternoon`, `deploy at 13:30 in the evening`, `deploy at 23:00 in the afternoon`, `deploy at 2:30 pm in the evening`, `deploy at 12:30 in the evening`, `deploy at 06:30 in the evening` | **deploy_section 10** each |
| `deploy at midnight tonight`, `deploy at 9 at night` | **deploy_section 10** each |
| `deploy section 2 at 6.30 pm` | **deploy_section 10**, for section 2 |
| `deploy at 1.5` | deploy_section 1, declined 9 |
| `deploy at 2.0.1`, `deploy at 6:30, then preview`, `deploy tomorrow at 6:30 tonight`, `deploy at 6.30 pm every day`, `deploy on 10.30`, `deploy at 7 in the evening, then preview` | declined 10 each |

(Two more were measured in that run and are no longer on the list: `deploy at
12:30 in the morning` and `deploy today at 12:30 tonight`, both deploy_section
10 of 10, are answered with a spelling since the fix round.)

So **17 of the 24 still deploy on the spot 10 of 10** when a teacher types
them, and the approval card's "This happens now." (#168) is what stands
between them and students — as it stood between students and the shapes this
piece closed. They are not all refused for the same reason, and not all of
them disagree with themselves:

- **They say two things that disagree** — a time outside its part of the day
  with two digits of hour or with am/pm (`18:30 in the morning`, `6:30 am in
  the evening`, `11:30 in the afternoon`, `13:30 in the evening`, `23:00 in
  the afternoon`, `2:30 pm in the evening`, `12:30 in the evening`, `06:30 in
  the evening`), 13 with pm (`13.30 pm`), or two different days (`deploy
  tomorrow at 6:30 tonight`). Handing back ONE sentence would be a guess.
- **They carry more than a time** — a second request, a repeat, another
  section (`6.30 pm, then preview`, `section 2 at 6.30 pm`, and the declined
  `6:30, then preview`, `every day`, `7 in the evening, then preview`).
- **The family does not read them as a clock** — `6,30` (a decimal comma a
  person reads easily), `0.30`, `6.3 pm`, `7, please`, `1.5`, `2.0.1`, `on
  10.30`. Some of these a teacher plainly meant as a time; they are refused
  because their spelling is not one this family reads, not because they are
  contradictory.
- **They are merely unread** — `midnight tonight` and `9 at night`, shapes the
  ruling let stay outside the list of parts of the day. Nothing is wrong with
  them; they are not covered.

Whether some of them should be ASKED about or read instead is not decided
here. Beyond the rows, anything the frame
and the list of parts of the day do not cover (`tomorrow night`, `at night`,
`12 noon`, a weekday) goes to the model as it always did, unmeasured.

The probe was a one-off copy of `research/ai-assist/trimmed-surface-suite.py`
with its `CASES` loop replaced by a loop over the sentences above, as #194's
was; it was not kept. The research guard itself now mirrors `timeToSayAs`
(`deploy_time_said_as`, `SAID_AS_IN_CODE`) and is checked against every
`accepted`, `asked`, `sayItAs` and `refused` row before anything is measured
(141 rows after the fix round).

**Rejected, and why:**
- **accepting these spellings outright** — every accepted spelling widens what
  is SCHEDULED, and every one is a routing change for the model's side of the
  family; Russell chose to ask;
- **leaving it to the approval card** — the card is the last line, not the
  answer; the teacher named a time and got "This happens now.";
- **a pending "waiting for the spelling" state** — the same reasons #194 gave
  for its question;
- **catching every refused shape** (`deploy at 7`, `13:30 pm`, `25:00`) —
  each refused row's written reason is a decision, and a reply that named ONE
  sentence for a sentence that disagrees with itself would be a guess;
- **echoing the teacher's spelling in the sentence handed back** — the #194
  rule: `please`, `it`, a trailing day word are read by the frame but a
  sentence rebuilt around them might not be; the canonical form is pinned by
  the test for every row;
- **mapping a part of the day straight to am or pm** — see the windows above;
- **deciding "without the comma" by comparing text** — see the reply above;
  the canonical sentence differs from the teacher's in harmless ways (`7:00`
  for `7`, no `it`, the day word moved), and text comparison read every one of
  them as a spelling problem;
- **widening `deployFrame` for a part of the day in front of "at"** — it would
  move what the family ACCEPTS; the move-to-the-end rebuild keeps one frame
  and leaves the accepted rows untouched.

**Which day a bare time means: the next such time, forwards, counting today
while it is still to come.** Word for word the rule `dayNamedByWeekday` already
applies to a bare day word, one unit up. An explicit "today" or "tomorrow"
overrides it, and "today 06:30" said at nine o'clock stays on today and meets
the existing "…has already passed" refusal — they named the day, so the app
does not move it for them. **Rejected: "today at that time, always"**, which
invents no temporal rule at all but answers the shelf's own card with a refusal
for most of the day. The guess is allowed because it is never silent:
`schedule_deploy` waits for a button and its card names the whole moment,
weekday and date included, before anything is written.

**Where the settling happens, and why it is one clock read.**
`AssistAgent.settled(_:)` binds the section, settles a relative DAY
(`withTheDaySettled`, below) and then settles a bare clock time
(`withTheMomentSettled`) — once, where the call is created, reading `Date()` in
exactly one place. Nothing there decides whether a call may run at all: a model
call naming a course that is not this window's is refused in `think()`, above
the line that reaches any of this, so a settled call is one that was already
allowed. `AssistAgent.say` then builds the call, settles it, writes
its trail line FROM THE SETTLED ARGUMENTS, and hands the same call to
`run(settledCall:)` without settling it again. That order is the fix to a real
problem rather than tidiness: the matcher is clock-free, so the day a bare time
means does not exist when the sentence is matched, and a line written before
the settling would record a time with no day on it. The settler is idempotent
— a whole moment is handed straight back — and a test says so, which is what
makes the arrangement safe.

**Which settler owns which argument is asked of the TOOL.**
`settlingTheClassDay` takes the tools that declare `date`;
`settlingTheDeployMoment` takes the tools that declare `when` and NOT `date`.
A tool cannot be in both, so the division is by construction rather than by
memory — `schedule_deploy` and `plan_scheduled_deploy` are the two today, and
`publish_class_on`'s day-shaped `when` is untouched without anybody having to
remember that it is different.

**Five consequences written down rather than discovered.**

- **The settler quietly changes the MODEL's path too.** It runs in
  `run(call:)` for every call, so a model that answers `when: "06:30"` now gets
  a day guessed onto it instead of meeting `unreadableTime`. Measured limit:
  the settler reads an exact `HH:mm` and nothing looser, so a model's `"6:30"`
  still refuses. This is consistent with `withTheDaySettled`, which already
  covers the model's path for the same reason — but it IS a behaviour change on
  a path the fix is otherwise not about.
- **A card can be approved into a refusal.** At 06:29:50, "deploy at 6:30 am"
  settles onto 06:30 today, ten seconds away; `ScheduledDeploy.problem` refuses
  anything at or before `now` and is re-evaluated when the teacher presses the
  button, so a card naming a minute can be declined by the app a moment later.
  "Settled once" is a property of the MOMENT, not of the refusal. **No minimum
  lead time was invented** — there is none anywhere in the product, and adding
  one here would be a rule nobody could find later.
- **Scheduling replaces an existing schedule** for that section
  (`ScheduledDeploy` removes any previous job). When this family landed,
  neither the card nor the summary said so; since
  [#195](https://github.com/russellgordon/plantoir/issues/195) (2026-09-23)
  the card, the schedule sheet, the plan and the tool's own result (the only
  thing an MCP caller sees) name the moment being replaced
  (`wording.scheduleReplaces`) and the trail records it
  (`scheduled deploy replaced`). It was read Mac-wide until
  [#237](https://github.com/russellgordon/plantoir/issues/237) (2026-09-25)
  gave each working folder its own alarm; now it names only a deploy set from
  THIS working folder, since another folder's is a different alarm that
  scheduling here leaves standing. The reasoning is in
  [`07-deployment.md`](07-deployment.md) → "Scheduling a section that already
  has a deploy set" and "One alarm per working folder (#237)".
- **On the morning the clocks go forward, a wall time may not exist**, and the
  settled text is therefore built from the INSTANT rather than by joining a day
  to a time. Measured, America/Toronto, DST starting 02:00 on 8 March 2026:
  joining the strings gives `"2026-03-08 02:30"`, which `Calendar` has no
  instant for and `moment(named:)` — three strict `DateFormatter` patterns —
  reads back as nothing. Everything downstream then failed silently: the trail
  line dropped its moment, the card printed the raw text instead of "Sunday 8
  March, 2:30 AM", and approving it failed with the app calling its own output
  unreadable. `Calendar` moves a nonexistent wall time forward, so 02:30
  settles onto **03:30** and the card names it. **Rejected: returning nil for
  that hour**, which is one line and keeps the invariant too, but answers a
  teacher who asked for an ordinary time with "I could not read that" on the
  one night when the reason is a fact about their clock. The invariant is now
  structural — what comes out is the canonical rendering of a real instant, so
  it always reads back — and `ScheduleDeployCardTests` runs it over every
  `resolving` row as well as over that morning.
- **Going BACK, an ambiguous hour resolves to the first occurrence.** Measured,
  America/Toronto, 1 November 2026: asked at 01:15 in the first 01:00 hour,
  "1:30 am" settles onto the 01:30 forty-five minutes away; asked at 01:45,
  it settles onto **tomorrow** rather than the second 01:30 an hour later,
  because `Calendar.date(from:)` picks the earlier instant and that one has
  gone. Defensible — it is what "the next such time" means with a
  first-occurrence convention — and vanishingly rare, but it is a choice
  rather than an accident.

**Not made a contract row, deliberately: the spring-forward shift.** It is what
THIS platform's calendar does for free, while .NET throws on an invalid wall
time (`TimeZoneInfo.ConvertTimeToUtc`), so a row asserting 03:30 would hand
Windows a DST requirement discovered here and never discussed there. It is a
mac test and a named trap in the handover instead, to be proposed as a row once
both sides have met it. The same goes for the fall-back convention.

**`AssistMCPServer` deliberately settles nothing**, so `Plantoir --mcp-stdio`
still refuses a bare `when: "06:30"` with the runner's own "I could not read
that time". That is a deliberate divergence from the `publish_class_on`
decision below, where the tool WAS made forgiving: an MCP caller genuinely
reaches that tool with a relative day, whereas `schedule_deploy`'s schema tells
Claude Code to send `YYYY-MM-DD HH:MM` and no MCP client sends a bare clock
time.

**No routing re-measurement is owed, and here is the check rather than the
claim.** `AssistToolSurface.swift` is not touched — no tool added or removed,
no description, no parameter, no `required`, no `needsApproval`, no plan twin —
and `AssistAgent.systemPrompt` references no `AssistWording`. Confirmed by
regenerating: `contracts/assist-cases.json` → `tools` and `toolSchemas` come
back **byte-identical** (compared key by key against `origin/dev`), so the
model is shown exactly what it was shown before. The matcher is strictly
upstream of the model and the approval sentence strictly downstream of it. What
DOES change is a count of the CODE: the shelf's split moves from
15-answered-in-code/4-model-routed to 16/3. *(It moved again the same day, to
17/2, with #215 below — this paragraph is #168's record and is left as it was
written.)*

### "Hide" is "unpublish", and a reply that is the question again

Written 2026-09-19, closing [issue
#215](https://github.com/russellgordon/plantoir/issues/215). Two faults, found
in the v1.2.0 hand smoke and then measured. Neither is new: the tool surface
and the system prompt were byte-identical across every merge that day, and the
second fault is how a plain reply has been kept in the history since v1.1.0.

**Conditions for every number below** (they belong to these numbers and to
nothing else): Qwen2.5-1.5B-Instruct Q4_K_M — the file the app downloads for
the smaller assistant — llama.cpp b10435 on Metal, M4 Pro 48 GiB, the app's own
server flags, the app's own request body, temperature 0, the shipped system
prompt, the 13-tool local surface, the date line on the END of every user
message. Raw output and the replay scripts:
`research/ai-assist/echo-postscript-215.txt`. **The larger assistant was not
measured** — it is not downloaded on this Mac — so nothing here says anything
about the 4B.

#### The word

`unpublish unit 4, day 21` reached `unpublish_pages` every time. `hide unit 4,
day 21` reached **no tool at all**, in five phrasings out of five, and what
came back was the teacher's own sentence as text. It errs in the safe direction
— nothing is hidden and nothing else happens — and it reads as broken. The word
was already on record as this tier's weak spot: `conversational-residue-
results.txt` has "HIDE — the inversion case" at 3/3 declined, and
[#167](https://github.com/russellgordon/plantoir/issues/167) showed a single
token flipping its answer.

**So "hide" is answered in code**, which is CLAUDE.md's standing rule applied
exactly: steer the model with code, not with tool descriptions. `wholeUnit`
became `wholeUnitOrClassPage` — one frame, one verb table, so the two verbs can
never drift apart:

```
[please] hide|unpublish unit <n>[[,] day <m>] [please]
[please] publish unit <n> [please]
```

**THE WHOLE VERB IS GATED, not only the day arm, and that asymmetry is the
decision.** `hide` and `unpublish` take a whole unit or one class page and
tolerate the spellings below; `publish` is read by a frame of its own that has
not moved — the literal opening `publish unit ` and a bare number — so `publish
unit 4, day 3` still goes to the model, and so do `publish unit 4?`, `please
publish unit 4`, `publish unit 4 please`, `publish  unit 5` and `publish unit,
4`.

**That split was made deliberately rather than inherited, and it was got wrong
first.** The original version read the verb AFTER stripping the courtesy words
and the question mark, which widened publish as a side effect. An adversarial
differential fuzz across the two compiled matchers — every
verb/noun/number/tail/spacing combination — found 0 matches lost, 0 arguments
changed and **141 new `publish_pages` matches**, none of them asked for.
`publish unit 4?` is the case that decided it: a teacher typing a question mark
is plausibly ASKING, and that sentence would have published a whole unit with no
model in the loop — the same ambiguity used two paragraphs down to reject `show
unit 4`. Re-run after the gate on a wider 36,864-input sweep: **0 lost, 0
changed, 0 new `publish_pages`**, 2,850 new `unpublish_pages`. Five of the 141
are pinned as `refused` rows so the gate is data rather than a comment, and
`HideIsUnpublishCardTests.testPublishStillTakesAWholeUnitAndNoPage` asserts the
TOLERANCE as well as the reference — a test naming only the reference did not
catch it.

The reason for the asymmetry, underneath all of that: unpublishing errs safe — a
page nobody can see — while publishing puts a page in front of students, and
"Publish Unit 2, Day 3" is 10/10 on this tier today, so there was nothing to
buy by widening the dangerous direction on the same day.

**What the frame tolerates was decided rather than left to taste**, because
spellings are the whole question for a family like this — the same argument
`deployAtATime` won. The comma is frame punctuation and is dropped before the
words are counted (`makeRoom`'s reading), so `unit 4 , day 21` and `unit 4 day
21` are the same request and odd spacing is read the same way; a trailing `?`
comes off; `please` is courtesy at either end; and `day21` is refused, because
that is not a word this frame has. 13 accepted and 20 refused rows are DATA, in
`contracts/assist-cases.json` → `hideIsUnpublish`.

**The refusals are the safety half, and one of them is load-bearing.**
`AssistAgent.encode` writes THIS window's course and section into every card
call, and the guard that refuses a request naming another course lives in
`think()` — which a matched card never reaches (see "Never ask the model for
something the window already knows"). So `hide unit 4, day 21 in ICS3U`, typed
in an ICS4U window, would act on ICS4U and report success: the one kind of
failure a teacher cannot catch, and the exact fault
[#202](https://github.com/russellgordon/plantoir/issues/202) exists to remove.
The frame therefore reads a fixed number of words and refuses everything else —
a negation (`don't hide unit 2, day 3`), a second page, a part of a page, a
section named.

**Term-blind for now, and the limit is stated rather than discovered.** Only
the literal word "unit" is matched, because `AssistCardCommand` is a pure
function of the sentence — that is what lets the contract describe it as input
and output — and a course's own word for a unit is not in the sentence.
Threading `unit_word` through the matcher would change the contract's
representation of every parsed family and the research harness's interception
guard with it. A Module course loses nothing: `hide module 4, day 21` falls
through to the model exactly as it did before, and `hide unit 4` still works
there because `AssistPublishPlanner.unitNamed` accepts "unit" alongside the
course's own word.

**Rejected, and each for a reason worth keeping.** A clarifying sentence in
`publish_pages`' description — the measured precedent is 110/110 → 90/110, with
three previously-perfect probes broken, because a small model reads a
description naming another tool as a recommendation rather than a boundary.
Mirroring the frame on the publish side, for the reason above. `show` and
`unhide` as publish-side synonyms, which are worse again: "show unit 4" is at
least as likely to mean "display it to me", and resolving that guess by
publishing is the wrong way to be wrong.

**The cost, said plainly.** Every phrasing answered in code leaves the routing
denominator. The shelf's split moves 16/3 → **17/2** — "Unpublish Unit 2, Day
3" is answered in code now, and only "Publish Unit 2, Day 3" and "Cancel
scheduled deploy" still go to the model — and the research suites' intercepted
count moves from five of 29 probes to six, with the promise-card line they
print dropping from 6 of 11 to 5 of 11. A score taken after this is not
comparable to one taken before it without saying so.

#### The reply that was the question again

The worse half, and it is not about the word "hide" at all. After `hide unit 4,
day 20` echoed, **`Unpublish Unit 4, Day 20` echoed too** — a sentence the same
model answers correctly every time in a fresh conversation. Replayed on ICD2O
and ICS4U, pages "Unit 4, Day 20" and "Unit 4, Day 21": identical in all four.

| conversation | result |
|---|---|
| FRESH: "Unpublish Unit 4, Day 20" | `unpublish_pages` ✔ |
| turn 1: "hide unit 4, day 20" | no tool — echoes the sentence, date line and all |
| turn 2, after that echo: "Unpublish Unit 4, Day 20" | no tool — **echoes again** |

So it is not the course token and not the page: **it is the HISTORY.** The
echoed reply was kept in `messages`, and the model then copied the pattern it
could see — user says X, assistant says X — for every later request. One
unrecognised phrase made the window useless until it was closed and reopened.
The FRESH row is what says the fix works: a clean conversation is enough.

**An echo is recognisable in code**, so `think()` refuses it, below the
tool-call branch (an echo is a reply with no tool call in it) and above the
append (the whole point is that the reply must not reach the history). The rule
is a pure function and lives in `AssistAgent.isTheRequestBackAgain` so the
contract's cases can run straight against it: no tool call, and the reply's
text equals this turn's user message — case-folded, with `.`, `!` and `?`
trimmed from both ends.

**Both spellings of the question are compared**: the message AS SENT, with the
date line on the end, which is what the measured echo carried; and the sentence
the teacher typed, because a model that trims the parenthetical is not a
different fault. The typed sentence is kept in a property of its own rather
than recomputed — taking the date line back off would mean reading the clock a
second time, which is what `withTheDaySettled` exists to prevent.

**It compares the message at the START of the turn, never the last user message
anywhere**, and that is what makes a card-matched second lap safe by
construction rather than by inspection: such a turn begins with a TOOL RESULT,
so the guard sees no user message and cannot fire. Two tests exist only to kill
the two wrong implementations — one that drops the role check (killed with a
reply equal to the tool result's own text) and one that searches backwards for
the most recent user message, which is what a reader of `windTheTurnBack` would
reach for (killed with a two-turn case).

**What happens on an echo:** the turn is wound back with the rewind
`sayTheAnswerDidNotFinish` and the wrong-course refusal already share —
`windTheTurnBack()` now has three callers — the teacher reads
`AssistWording.didNotFollowThat`, and a new trail event is recorded. **Never
the echoed text**: handing a teacher their own sentence back is the fault, and
repeating it inside an apology would be the same fault, politely.

**The sentence is deliberately GENERAL, and an earlier draft was wrong here.**
It offered three verbs to start with — publish, unpublish or hide — and told
the teacher to name the page. The guard fires on ANY request the model answers
with plain words: a deploy, a request to make room for a class, a question
about dates. Telling a teacher whose "deploy at half six" was echoed to start
with a publishing verb and name a page is not a hedge, it is wrong advice, and
a sentence that will be believed and is false in a whole class of cases is
worse than a vaguer true one. The working phrasings belong here, in the
documentation, not in a sentence said to everybody.

**"I haven't changed anything" is true on every path that can reach it**, by
the same walk `answerWasCutOff` records: a turn only comes back to the model
for another lap when a tool said to (`AssistToolOutcome.shouldContinue`), which
is true for `read`, `couldNotRead` and `planned` alone, and `planned` is held
behind the approval card and never reaches a second lap.

**Strict on purpose, and here is what that misses.** An echo with a preamble
("Sure: hide unit 4, day 21"), a partial echo, and any other kind of residue in
the history all get through. Each would need a similarity measure, and a fuzzy
rule that fires on a legitimate answer is worse than the fault: it would throw
a real reply away and tell the teacher it did not follow. **The one corner it
leaves**, stated the way #211's row states its own: a teacher typing a
content-free token — "ok", "thanks" — to which the model replies with the same
token. They then read one honest sentence instead of "ok", and a turn carrying
nothing is wound out of a history it was adding nothing to. Nothing can be lost
that way: everything with state in it — a plan, a deploy, the dates sheet — is
a button or a sheet rather than free text, and `entries` keeps the teacher's
own words on every path.

**The trail line is a NEW event**, `assistant repeated the request back`
(`activityTrail.mustRecord` 48 → 49). It carries the course, the section, that
nothing ran and that the turn was taken back out of the conversation — never
the sentence, which `assistant asked` already carries on its own marked line.
**Rejected: folding it into `assistant answer was cut off`.** Those two share a
genuine kind — an answer the app refused — but that event's NAME says "cut
off", which would be false here: this answer finished. A line describing
something other than what happened is worse than no line, because it will be
believed. `assistant could not answer` is worse again; that is for an engine
that FAILED.

**A SCENARIO is not expressible for this half**, and the reason is the same
limit `windowBinding` records in `contracts/README.md`: the scenario runner
builds its agent with no engine behind it, so a model's reply cannot be
scripted. The cases are the predicate instead, and the mac drives the whole
path through the `StubEngine` seam.

**No routing re-measurement is owed**, and here is the check rather than the
claim: `AssistToolSurface.swift` and `AssistToolDefinition.swift` are untouched,
`AssistAgent.systemPrompt` is untouched, `tools` and `toolSchemas` regenerate
byte-identical against `origin/dev`, and the 13-tool local WIRE surface hashes
the same as a copy taken from the live server before this change. The matcher
is strictly upstream of the model; the echo guard is strictly downstream of it.

### "What does this page link to?" is answered in code (#167)

Written 2026-09-25, closing [issue
#167](https://github.com/russellgordon/plantoir/issues/167). The larger
assistant's `read` probe — `What does "Unit 2, Day 3" in EXC2O section 1 link
to?` — had gone from 10/10 in August to 0-1/10 on Metal, and #167's own
comments had already found that its answer was decided by the dateline's
weekday word and the course code: 88 of 92 days right for VVH2O, a different
four wrong for another course. Greedy decoding makes ten trials of ONE date one
measurement repeated ten times, so the question was re-asked across dates.

**Conditions for every number below** (they belong to these numbers and to
nothing else): Mac16,8 M4 Pro, 48 GiB; llama.cpp b10435 on Metal, the
`llama-server` bundled in the dev 68214a6c Debug build; `AssistServerHost.
serverArguments` per tier; the app's request body (temperature 0,
`tool_choice` auto, `max_tokens` read out of the Swift); the shipped system
prompt; the 13-tool local surface from the contract. Raw output, the grid's
script and the conditions in full: `research/ai-assist/link-question-results.txt`.

| | larger (Qwen3 4B) | smaller (Qwen2.5 1.5B) |
|---|---|---|
| 29-probe suite, VVH2O, 10 trials, 2026-09-25 | 290/290, `read` 10/10 | 210/290, `read` 0/10 (check_section) |
| #167's sentence, 6 courses × 14 dates | 55/84 | 54/84 |
| "What does Unit 2, Day 3 link to?" | **0/84** | **0/84** |
| "Which pages does Unit 2, Day 3 link to?" | 0/84 | 0/84 — **31 × publish_pages** |
| "What links are on…" / "Where does … point to?" | 0/84 / 0/84 | 0/84 / 0/84 |
| the family, seven phrasings | 153/588 | 115/588 |

So the day's 10/10 was the date lottery, the plainest phrasing a teacher would
type is 0 of 84 on BOTH tiers, and on the smaller one a read-only question
became a publish PLAN 31 times — a write, held behind the card by default,
which is the only reason it was not worse. It is a fixed frame around a page
title, the shape #194 and #277 had already moved into code.

**So it is the ninth parsed family, `AssistCardCommand.linksQuestion`**, and it
never reaches the model:

```
[please] what|which pages|what pages does <page> link to [<place>] [please]
         what does <page> point to     where does <page> link|point to
         what links are on|in <page>   show me|list the links on|in|from <page>
<place> := in this section | in section <n> | in <course> [section <n>] | in section <n> of <course>
```

**A place is read BEFORE "link to" as well as after it**, and that was the
plan review's blocker: #167's own sentence puts `in EXC2O section 1` between
the title and "link to", and a frame that looked only after "link to" would
have read the title as `"Unit 2, Day 3" in EXC2O section 1` and answered, with
total confidence, that no page is called that. **Only THIS window's place is
accepted**, because a card binds the window's course and section into its call
whatever the sentence said (`AssistAgent.encode`) — the hide family's reason,
honoured exactly. Another COURSE is refused in code with the sentence a
model-named course already gets (`AssistWording.askedAboutAnotherCourse`, or
`askedAboutACourseThatIsNotHere` when the folder has no such course), nothing
is read, and the trail records it under the existing `assistant was asked
about another course` event with a line saying it was matched in code
(`AssistAgent.linksQuestionNamedAnotherCourseLine`). This course and ANOTHER
SECTION goes to the model, as it did before. `in <word>` with no section is a
course only when it is the window's or a course code that EXISTS — one of
the codes in the two course lists the app already ships
(`ontario_secondary_courses.json`, `british_columbia_secondary_courses.json`).
A shape was tried twice and was wrong both times: "three letters, a digit, a
letter or digit" took "Lab01" for a course (review R3), and "…a letter" then
missed real codes — 1,091 of the 1,930 Ontario codes have no digit ("ESLBO"),
and BC's run to seven characters ("MCMPR11"; fix review L2).
`support/skeletons/families.json`'s 499 prefixes are exactly the Ontario
list's, so it adds nothing; and not one of the 9,790 example-payload titles,
nor any word in them, is a code on the list. Otherwise — "Day 3 in Unit 2",
"Lab1B" — it is part of the title and the lookup decides.

**A title slot that is itself a place is not a page** (the implementation
review's R1, measured: each of these had become "no page is called …" with the
turn ended). "What links are in this section?", "Show me the links in section
1", "List the links in ICS3U section 1" and "What links are in ICS3U?" ask
about a whole section or course, and go to the model as they always did, and
so do "my course" and "this course"; "What links are in SPH3U?" in an ICS3U
window is the another-course refusal. A bare day word ("What does today link
to?") goes to the model like "today's class", and so does a sentence that is
two requests ("Show me the links on Unit 2 and publish them").

**A phrase beginning "the" is a title when a page is called that** — the fix
review's F1 and F2, and the first version of this got it wrong in both
directions. 423 of the 9,790 titles in the example payloads begin "The" ("The
Water Cycle") and 28 end "Page" ("Scratch Page"). "The Ohm's Law page" is
looked up as "Ohm's Law" first; only when that finds nothing is the phrase
tried as typed without "the", without "page" and whole, and only when none of
those finds anything is the teacher told no page is called that — so "the
Water Cycle page" reaches "The Water Cycle", and "the Scratch Page" reaches
"Scratch Page". Any other phrase beginning "the" — "The Water Cycle", "the
quiz", "the site" — is answered in code when the section HAS a page called
that (`AssistAgent` asks `AssistToolRunner.sectionHasAPage`, because the matcher
is a function of the sentence and cannot see pages), and otherwise goes to the
model, which has the conversation to read a description against. Sending a
real "The …" title to the model instead, which an earlier round did, is the
path this section measured at 0 of 84.

**Refused, so the model keeps them** — each a `refused` row: a pronoun ("what
does it link to?" — the model has the conversation; this frame does not); a
page named by its DAY ("today's class", "my next class" — no class is resolved
by date here; the model reads dates, and a second resolver would be a second
answer to one question); a description beginning "the page"; the REVERSE
question, "what links to Unit 2, Day 3?" and "which pages link to …", which
asks which pages point AT this one and is the family's near miss; a plural
"what do … link to"; "what would … link to"; anything after "link to" that is
not this window's place, so "… link to, and publish them" is never half
answered. With NO window passed (the contract's parsed example is run that
way), any place at all goes to the model. The research suite's mirror of the
grammar (`links_question` in `trimmed-surface-suite.py`) was checked against
the compiled Swift on **6,338,596 generated sentences — 0 disagreements in the
outcome AND in the extracted title** (and the phrase carried for "the … page")
— after an earlier run had found the one fault both shared: with no window,
"in ICS3U section 1" was read as another course. (The first run, 2,178,770
sentences, compared the outcome only; the review pointed out that says nothing
about the title, and the mirror now returns it.) (One known difference is left
out of that set on purpose: a title whose lower-casing changes its LENGTH,
like "İstanbul", is compared by grapheme in Swift and by code point in Python,
so the mirror refuses what the app reads. No probe carries one.)

**The answer is a READ answered in full, and the turn ends there.** The card
builds `read_page` with `page` and an argument the model is never shown,
`answer: "links"` — the `scope: "all"` / `rollover` precedent: in no schema, so
`toolSchemas` does not move by a byte (local sha256 `46b96562…2cd96cb6`, mcp
`9bcc7eb7…9cef36f7`, before and after, `--write-contracts` run twice). An MCP
caller that sends it gets the code's answer, which is harmless: it is a read.
Without it, `read_page` is exactly what it was. **Every branch ends the turn**
(`AssistToolOutcome.answered`, `shouldContinue: false`), and that is required
rather than taste: a code-matched turn never appends the teacher's sentence to
the model's conversation, so handing back would give the model a tool result
with no question in front of it — the lap where the smaller assistant turns a
read into a plan. The tool result's `detail` still names the page, so a
follow-up about "it" has a referent. A scenario proves the end with a new
field, `expectModelRequests: 0`: a transcript cannot show an absence, so the
mac runs that case against a `StubEngine` and counts.

**What the answer says**, all through `AssistWording` (`pageLinksTo`,
`pageLinksToNothing`, `linkedPageIsADraft`, `linkedPageIsMissing`,
`noPageCalled`, `morePagesThanOneAreCalled`, `pageCouldNotBeRead`): every link
once, in the page's order, by the name the sidebar shows for the page it
reaches; a draft marked (the linked page's own publish or draft key says
hidden); a link that leads nowhere marked, spelt as the teacher wrote it.
**"Leads nowhere" is defined once**, in `AssistToolRunner.linksOnAPage` and in
`linksQuestion.answering.note`: a wiki-link (`[[…]]` or `![[…]]`) whose target
is neither a page of the section — by file name without regard to case, or a
folder whose landing page is in the section — nor any FILE of that name,
whatever the capitals, in the course's folder. A folder is not a file: "[[Unit
3]]" naming a folder with no landing page leads nowhere and is marked (the
review's R2 — it was silently dropped, as though it were a picture). **No extension rule**: "Lab 1.2" is a page and
"diagram.png" a picture because of what is on disk, and a picture or handout
that exists is not listed at all, since it is not a page.

**Measured before it was chosen**, on the 39 example-content payloads, each
link counted once per page: read with `AssistSectionGraph.linksAsWritten`,
**30,930 links and embeds, every one resolved to a page** — no false "leads
nowhere". Two things that reading did differently from `linkTargets` (which
publishing follows) when it was written: links inside `code` and fenced blocks
are examples, not links — left in, **188** targets read as dead, nearly all on
the Scavenger Hunt pages that teach `[[Page Name]]`; and a table's escaped
pipe, `[[Ohm's Law\|Ohm]]`, left a backslash on the target — left on, **69
real links** read as dead. **That second finding was true of publishing too**,
and was recorded here rather than fixed at the time; it was fixed in
[#294](https://github.com/russellgordon/plantoir/issues/294), for every reader
at once, in the one pattern they all share — see
["What counts as a link"](#what-counts-as-a-link) below. The code difference
was settled in [#313](https://github.com/russellgordon/plantoir/issues/313):
every reader now skips code by one shared mask, so this answer and publishing
read exactly the same links — see
["Code is never a link"](#code-is-never-a-link-313) below. The answer's own
stripper, it turned out, had been wrong in the other direction as well: it
flipped its fence on any line that STARTED with `~~~`, so a Python traceback's
`~~~~^^^^` inside a ```` ```text ```` block ended the fence, and the real
closer opened a new one — **22 real links** left out of the answer on four ICS4U
pages (Testing and Regression 8, Reading a Traceback 7, Spot the Bug 5, Name
That Error 2).

**The page asked about is found by file name first, then by the name the
sidebar shows** — a folder's landing page by its folder's name as well, so
"What does Unit 2 link to?" finds `Unit 2/index.md`. More than one page by the
shown name is answered with `morePagesThanOneAreCalled` and where each one is,
never a guess; none is `noPageCalled` — **not** `AssistToolRefusal.noSuchPage`,
whose sentence ends "Use list_pages…", a tool's name in front of a teacher.
**A known limit**, stated rather than discovered: two FILES with one name, a
section's own page and a course-wide one, still resolve to the first in path
order, the rule every link in `AssistSectionGraph` already follows.

**Rejected, with the numbers.** A sentence in `read_page`'s description (the
2026-09-19 candidate on #167, `TEACHERS SAY: "what does that page link to?"`):
it moves the tool surface both apps were measured against — a routing change on
both platforms — it moved OTHER probes across dates when it was tried, and on
the smaller assistant seven of thirteen held-out phrasings did not move at all.
Leaving it: 0 of 84 for the plainest phrasing on both tiers, and a write on 31
of 84 for "which pages". **No routing re-run is owed**: nothing new reaches the
model, and the surface hashes are unchanged. The research suite now prints
`read -> read_page` as intercepted — 7 of 29 probes answered in code where it
was 6, so "the N the model SEES" is 22 where it was 23; a number from before
this is not comparable to one after it without saying so. **Windows' model
still sees the probe** until their app answers the family in code too.

### The dateline, and why its position is a finding

A model has no clock. Every message the teacher sends therefore carries
`(Today is 2026-08-15, a Saturday.)` — **appended**, never prepended. The
position is not a style choice: prepending the same sentence cost 15 points of
routing accuracy in measurement, and the effect reproduced on a second model.
A line of context at the front appears to compete with the instruction for the
model's attention; at the back it reads as a footnote to a request already
understood.

The day in it comes from what the TOOLS are counting from
(`dateline(on: tools.today)`) rather than from a reading of its own, so one
process cannot hold two answers to what today is. See "The mac's half" below
for why that matters.

### Step 1 — What Swift sends

`AssistModelClient.encodeTools` turns each Swift tool definition into the
OpenAI-compatible shape the server expects:

```json
{
  "type": "function",
  "function": {
    "name": "publish_class_on",
    "description": "Publish the class page for one date in a section …",
    "parameters": {
      "type": "object",
      "properties": {
        "course":  { "type": "string",  "description": "The course code, for example EXC2O." },
        "section": { "type": "integer", "description": "The section number, for example 1." },
        "date":    { "type": "string",  "description": "The date, as YYYY-MM-DD." }
      },
      "required": ["course", "section", "date"]
    }
  }
}
```

One detail there is a measured finding rather than a style choice. The
examples in those descriptions name **the teacher's actual course**, not a
placeholder — `namingTheRealCourse(courseCode)` substitutes it on the way out.
With a generic `ICS3U` left in the examples, a request that named no course
copied `ICS3U` out of the example text **9 times out of 9**. A small model
reads examples as suggestions.

The request also carries `"temperature": 0`. Temperature controls how much
randomness is used when picking each token; at zero the model takes the most
probable choice every time. For routing you want the boring, repeatable
answer — a router that answers differently to the same request twice is a
router a teacher cannot learn to trust. (The measurement suites ran at 0.1,
so the shipped app is if anything more deterministic than the numbers below.)

It also carries **`"max_tokens": 512`** — `AssistModelClient.mostTokensPerReply`,
added for [#166](https://github.com/russellgordon/plantoir/issues/166), and the
number Windows had been sending all along. It is not a tuning knob; it is a
bound on how long a teacher waits. Without one, a reply is bounded only by the
context, and the context is large: measured on an M4 Pro with the smaller
assistant (llama.cpp b10435 on Metal, Qwen2.5-1.5B Q4_K_M at a context of
8,192), the ordinary request *"Publish tomorrow's class for VVH2O section 1,
and make sure every page it links to is published rather than left as a
draft"* made the model write `Unit 2, Day 3; Unit 2, Day 4; …` for **5,435
tokens and 42 seconds**, three trials in three, and the answer was unusable
when it arrived. 2,757 prompt + 5,435 written = 8,192 exactly: the context was
the only thing stopping it. The larger assistant is not immune, it fails
differently and worse — the same shape there is 16,384 − 2,742 = 13,642 tokens
at that tier's measured 63.2 tok/s, about **216 seconds**, past this client's
own 180-second timeout, so it would fail rather than answer.

**Why 512 rather than a rounder, larger number.** Measured against the model's
own tokenizer, the tool calls this surface produces in practice sit well
inside the cap, and the ones that do not are reachable only by asking for
something there is a shorter way to ask for: an ordinary call is 16 to 60
tokens, twenty page titles is 203, twenty-four long real-world titles is 384,
and fifty-eight short titles is 545 — past the cap, which is the point at
which it starts to bite. So the only legitimate shape 512 cuts is an explicit list
of about fifty-five or more class pages — and `publish_pages` already takes
`onOrAfter` and `before`, which asks for any number of classes in about sixty
tokens. Nothing on the local surface takes free text or a page BODY:
`remember_timetable`, the one tool that would carry ninety dates, is in
`AssistToolSurface.hiddenFromTheLocalModel` and never reaches a capped
request.

**One shape does NOT fit, and it was measured rather than argued about.** The
two-lap one: `list_pages` hands back up to `AssistToolRunner.mostPagesListed`
(60) entries as relative PATHS (`AssistSectionGraph.relativePath`), far longer
per item than a class title, and the next turn may be asked to publish all of
them. Tokenised against the model's own tokenizer, using the sixty paths a real
257-page course really hands back: **60 paths are 975 tokens, and such a call
crosses 512 at about the thirty-first path** — the twenty-sixth if the section's
longest paths are taken. So the risk is real and it is now bounded and named,
rather than unknown.

What stops it being a fault in practice is that the model does not write that
call. Asked exactly that way — primed with the `list_pages` result carrying all
sixty paths, then "Publish all of those." — the smaller assistant answered with
`{"course": …, "section": 1, "pages": "all"}` in **35 completion tokens, three
trials of three, finishing naturally**. The cap never fired. That is one model,
one phrasing, three trials, and it is worth exactly that much: the honest
summary is that a teacher who does hit this meets
`AssistWording.answerWasCutOff`, whose advice — fewer pages at a time — is
followable in precisely this case. Raising the cap to cover the worst
imaginable call is the state #166 was about.

**Rejected: a larger cap, or none on the larger tier.** A cap sized to the
worst imaginable call is a cap that never fires, which is the state this
issue was about. The two apps also send the same number deliberately — it is
in `contracts/app-rules.json` → `modelTiers.requirements` with its `cap`,
because two apps sending different caps is a difference no test on either
side could see.

**A cap is a routing change until proved otherwise**, and this is the last
thing to know about the number. This codebase has already watched one added
sentence in a tool description move the promise card from 110/110 to 90/110,
so "it only changes where a generation stops" is a claim to be checked rather
than assumed. The check is available from one command line:
`trimmed-surface-suite.py --app-body` sends the cap it reads out of the Swift,
and `--app-body --uncapped` sends the body as it stood before #166, so the two
arms differ in `max_tokens` and in nothing else — run per probe at temperature
0, where the arms reproduce exactly, the comparison is the bag of tool names
each probe chose. The mechanism cannot change what the model chooses, only
where it is stopped, so the only outcomes available to such a run are
"neutral" and "it cost something"; no reading of it can say the cap improved
routing.

**It was run, and the answer is nothing.** `research/ai-assist/token-cap-results.txt`
holds it: on an M4 Pro (Mac16,8, 48 GiB) with llama.cpp b10435 on Metal, both
tiers at their shipped contexts, **0 of 29 probes and 0 of 19 shelf phrasings
chose a different tool under the cap** — against a morning uncapped arm and
against a same-afternoon uncapped control, identical trial for trial across all
960 rows of each comparison, with no polarity inversion and no probe gaining a
`finish_reason: length` turn it did not already have. The threshold was
pre-registered at 08:46, before the first capped request was sent. What changed
is the clock: the runaway this issue opened with went from **5,435 completion
tokens and 41–95 seconds to 512 tokens and 6.0–6.3 seconds**, ten trials of ten,
with the engine's own log showing the stop moving from the context to the cap.

### Step 2 — What comes back

```json
{ "choices": [ { "message": {
    "role": "assistant",
    "tool_calls": [ { "type": "function", "function": {
        "name": "publish_class_on",
        "arguments": "{\"course\":\"EXC2O\",\"section\":1,\"date\":\"2026-08-16\"}"
    } } ]
} } ] }
```

Note `arguments` is a **string** containing JSON, not a JSON object — that is
the OpenAI convention, and it is parsed in `AssistAgent`.

**The reply also carries `finish_reason`, and it is read.** `"length"` means
the engine stopped the model part way rather than the model finishing, and
`AssistAgent.think` then runs **nothing at all**: the teacher is answered with
`AssistWording.answerWasCutOff`, the trail gets an `assistant answer was cut
off` line naming the tool the model had begun to name, and **the whole turn is
wound back out of the conversation** — the half-written reply and the
teacher's sentence with it. A small model that emits arguments which do not
parse, with the turn finishing normally, is refused the same way and for the
same reason.

Winding the sentence back matters as much as dropping the reply, and it is
what makes the assistant's own advice followable: the teacher is asked to try
again with "a shorter sentence, or fewer pages at a time", and if the request
that ran away were still sitting in the conversation the shorter retry would
be sent with it still in front. What the teacher SEES is untouched — the
transcript keeps their sentence; it is only what goes back to the model that
is wound back. **One thing is given up for that, knowingly**: teacher and
model now remember different things, so a back-reference — "do that again" —
reaches a model with nothing to refer to, and will decline or misroute. That
is accepted, because the alternative is the model re-reading the sentence that
ran away and running away again, and because the wording asks for a
restatement rather than a reference. (The `catch` path — an engine that could not be reached, or the
180-second timeout — is deliberately not wound back, and never has been: it
tells the teacher the engine failed rather than asking them to rephrase, the
sentence is usually not the problem there, and `RelativeDayFreshnessTests`
reads exactly that state to pin the dateline's measured position.)

The teacher hears the same sentence for both, because from their side the two
are one event and both are mended by asking again. **The trail tells them
apart**, because whoever reads a problem report cannot: *"the assistant's
answer was cut off part way through publish pages"* is a question about how
much the model was asked to write, and *"the assistant finished answering but
what it wrote for publish pages could not be read"* is a question about the
model itself. One event (`assistant answer was cut off`), two trail sentences
— three since #198, below, which also gives the teacher a sentence of its own.
(Until #166 neither was true: `finish_reason` was
never read, the unparseable arguments were silently replaced with `{}`, and
the tool RAN — against no course, producing "There is no course called "" in
this working folder", which reads to a teacher as a complaint about what they
typed.)

**A third cause, since [#198](https://github.com/russellgordon/plantoir/issues/198)
(2026-09-23): a finished answer that wrote NOTHING for a tool that needs more
than the window supplies.** An empty string (and `{}`) is readable on purpose —
`undo_last_change` takes no arguments and llama.cpp sends `""` for it, so a gate
refusing every empty call would refuse "Undo that", the tool a card reaches
most. But the same yes let a finished `publish_pages` with `""` through. The
issue predicted the stale #166 refusal; that is **no longer reachable** from
the local path, because the window binds `course` and `section` onto every
call whose schema declares them (since 2026-08-15). What happened instead,
traced by reading (the must-fail run confirms only that the old gate let the
call through to a reply other than the refusal): bound to this section, with
plan mode on, it reached `plan_publish_pages` → `.nothingNamed` → a sentence
saying no pages and no dates were given — the #166 fault in different words,
since the teacher HAD named pages and the model dropped them.

**The rule: an empty call runs only when the window supplies everything the
tool needs.** The window supplies `course` and `section`
(`AssistToolCall.argumentsTheWindowSupplies`). A tool needs more than that when
its schema REQUIRES any other argument (a date, a page, a time), or when it
changes pages (`readOnly` false) and declares any other argument at all (which
pages, which dates, which unit) — a write told only its section has nothing to
act on. Everything else runs on an empty call: undo, rebuilding the preview,
the deploy (still behind its own button), checking the section, adding the
next class, and `list_pages`, whose other argument only narrows it. The gate
is `AssistAgent.argumentsAreReadable(of:for:)` over
`AssistToolCall.argumentsAreReadable(forToolRequiring:declaring:readOnly:)`,
reading `required`, the declared properties and `readOnly` from the tool's own
definition — the schema is only READ, so no description, schema or prompt byte
moved (hashes unchanged). `undo_last_change`'s schema has NO `required` key,
which reads as requiring nothing; a Windows port must treat a missing key the
same way. An unknown tool name is judged tool-blind and still reaches "There
is no tool by that name."

Re-taken after the change on 2026-09-23 by running the real gate over every
definition on the surface (the local thirteen; the MCP-only nineteen never pass
this gate — `AssistMCPServer` calls the runner directly — and are listed,
with what each does on an empty call, in #198's closing comment):

| Local tool | Requires beyond course/section | Declares beyond course/section | Not `readOnly` | First cut | Now |
|---|---|---|---|---|---|
| `list_pages` | — | `matching` | no | refused | **runs** |
| `read_page` | `page` | `page` | no | refused | refused |
| `check_section` | — | — | no | refused | **runs** |
| `publish_class_on` | `date` | `date` | yes | refused | refused |
| `publish_pages` | — | `pages`, `before`, `onOrAfter` | yes | refused | refused |
| `unpublish_pages` | — | `pages`, `before`, `onOrAfter` | yes | refused | refused |
| `rebuild_preview` | — | — | yes | refused | **runs** |
| `undo_last_change` | (no `required` key) | — | yes | runs | runs |
| `deploy_section` | — | — | yes | refused | **runs** (its button still asks) |
| `schedule_deploy` | `when` | `when` | yes | refused | refused |
| `cancel_scheduled_deploy` | — | — | yes | refused | **runs** |
| `read_remembered_timetable` | — | — | no | refused | **runs** |
| `add_next_class` | — | — | yes | refused | **runs** |

**What the teacher is told: its own sentence.** A refused empty call answers
`wording.answerLeftOutWhatItWasFor` — the assistant did not work out which
pages, day or time was meant, so nothing was done — and NOT
`wording.answerWasCutOff`, whose advice ("a shorter sentence, or fewer pages")
is about the teacher's request; an empty answer is not its fault. The trail's
third phrasing is "wrote nothing for <tool>", and the "assistant chose a tool"
line no longer says "waited for the button" for a call the gate refused (or
one the engine cut off) — no button went up. Contract:
`app-rules.json → modelTiers.requirements`, "A finished reply that wrote
nothing runs a tool only when the window supplies everything that tool
needs", with fourteen pure cases; each case's `required`, properties and
`readOnly` are checked against the real definition, and the agent's gate is
run on each.

**Over MCP, where nothing binds a course,** an empty `course` used to come back
as "There is no course called “” in this working folder" — false in its own
terms, and a complaint about the teacher when relayed. It is now
`wording.noCourseNamed` (the runner's `noSuchCourse` refusal and
`back_up_course`). Result text only; no schema moved.

**Measured cost:** across the 990 tool-call rows in `research/ai-assist/*.txt`,
175 were empty-argument calls — every one to a tool that requires nothing —
and none left out `course`/`section`, so the rule changes no measured routing
outcome and closes a path no recorded run has taken.

**REJECTED:** (i) refusing every empty call — breaks undo; (ii) refusing every
tool with a `required` list — THE FIRST CUT of this piece, caught on review: it
refused "rebuild the preview", the deploy, checking the section and adding the
next class on an empty call although the window supplies everything they take
(nine of the thirteen local tools require exactly course and section);
(iii) "readable when every REQUIRED argument is one the window supplies" alone
— keeps the empty `publish_pages` running, because its real content is
optional in its schema, which is why a write's declared arguments count too.

**The gate is the finish reason, not a parse check, and that is measured.**
Sweeping `max_tokens` across every cut point of two ordinary requests on the
smaller assistant (llama.cpp b10435), llama.cpp closes the arguments object
*before* the `</tool_call>` wrapper, so there is a window one or two tokens
wide where a generation was stopped short and its arguments nevertheless parse
perfectly: at a cap of 28, `deploy_section` came back stopped, with
`{"course": "VVH2O", "section": 1}` parsing cleanly. What the model was about
to write next is unknowable, and for a tool that changes pages the difference
between "the four pages you named" and the first of forty is the whole of what
was asked. Two more rows from the same sweep say why the gate sits ABOVE the
tool-call branch and why parsing could never have been enough:

| Cut at | What arrived |
|---|---|
| 8 tokens | No tool call at all — a raw `<tool_call>\n{\n"name": "publi` fragment in `content`, which a transcript that prints content verbatim would show a teacher |
| 10–26 tokens | The tool name parsed; the arguments were a fragment |
| 28 tokens | Stopped, and the arguments **parsed** |
| 30+ | Finished normally |

And `undo_last_change` takes no arguments at all, so a call to it cut off
before it wrote anything is readable by any check that could be written — and
would simply run.

**The gate is keyed to one spelling, and it fails OPEN.** `wasCutOff` is
`finish_reason == "length"` and nothing else, so `content_filter`, a null, an
absent field or a future spelling all read as "the model finished" and the
reply is acted on. That is deliberate: refusing every reply from a server that
does not send the field would leave the assistant unable to answer at all, and
the engine is pinned to b10435 by `mac-app/Vendor/fetch-llama.sh`, so the set
of spellings is known. **It belongs on the checklist for an engine bump**
alongside revalidating Quartz for a Node bump — if a later llama.cpp spells a
truncated turn differently, this gate goes quiet and the fault #166 fixed
comes back looking like a new one.

**A consequence worth knowing about in advance.** The thinking flags
(`--reasoning off` and `--reasoning-budget 0`) are what keep a Qwen3 template
from spending its whole budget inside a `<think>` block. If they ever regress,
the symptom changes shape: it used to be an answer that was merely slow, and
with a cap in place it becomes a visible *"I didn't get to the end of that"* —
because the thinking now runs into the cap. Meeting that sentence after a
change to the server flags means checking `AssistServerHost.serverArguments`,
not the cap.

### Step 3 — Swift decides what actually happens

`AssistToolRunner.run(call:)` looks the name up in its own table and runs the
corresponding Swift function. If the name is not in the table, nothing runs.
This is the security boundary: **the set of things the assistant can do is a
Swift array**, not something the model can extend by being clever.

### Step 4 — The app presses its own buttons

Two of those Swift functions do not do the work themselves. When a teacher
asks for a preview or a deploy and the section is open in a window, the
assistant calls that window's own Preview and Deploy — the same functions the
buttons call — through a small registry the window fills in while it is on
screen (`SectionWindowControllers`).

The reason is that the *visible* part of this work all belongs to the window:
the console the output streams into, the progress header, the site itself in
the web view, and the live-site link at the end. Run anywhere else, a deploy
still deploys, but the teacher watches a spinner in the conversation for four
minutes beside a section window that says nothing is running — which is
indistinguishable from a hang.

A deploy also does what the teacher would do first: if a preview is running,
it is **stopped, and waited for**, before the deploy begins. The window's
Deploy button is greyed out while a preview runs, so pressing Stop Preview is
the actual human procedure; and the wait is not politeness, because stopping a
preview kills that section's processes — by working directory, by the build
folder on their command line, or by their being `build_site.py` for this
course and section, plus everything under them — and would otherwise take the
deploy's build with it. That last part is the reason the wait is not
politeness, and it became MORE true on 2026-09-05: until then the sweep could
not see a `build_site.py` driver at all, so cancelling a deploy left the
deploy's own build running inside the container. The rule is in
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`stopPreview`.

**With no window open, the LOCAL assistant opens one** rather than running
silently — this used to be unconditional, and a teacher who asked the local
assistant to deploy while no section window happened to be open would watch
a deploy actually happen, with no visible sign of it anywhere: the chat
answered, but nothing on screen ever moved. `AssistToolRunner.
revealSectionOnScreen` reuses an already-open window on the same folder if
one exists (the common case — the assistant is almost always opened FROM
an already-open window's sidebar), or opens a fresh one otherwise, sets its
selection to the section that was asked about, brings it to the front, and
waits briefly for `SectionWindowControllers` to actually register it before
proceeding — moving `.selection` is not the same thing as the section
having appeared; `SectionDetailView` still has to mount on a real SwiftUI
render pass first.

This capability — `openMainWindow`, an `@Environment(\.openWindow)` action
threaded down from `AssistWindowView` — exists ONLY for the local assistant.
MCP (`Plantoir --mcp-stdio`) never constructs a Scene graph at all, so there
is no window for it to open; a scheduled deploy runs with the app closed.
Both keep the old silent fallback, unchanged — `siteWork` runs the launcher
itself, the path Claude Code over MCP and a 6:30 a.m. alarm still take.

---

## Part 4 — Why it is built this way

These are the constraints that keep a 4-billion-parameter model reliable.
They read like arbitrary restrictions until you have watched a small model
fail.

### The model is a router, not a planner

Tools are deliberately **coarse**: one call does a whole job, including the
parts a model might otherwise chain together. `publish_class_on` finds the
class page for a date, works out which other pages it depends on, backs the
section up, rewrites the frontmatter and rebuilds the preview — one call.

The alternative was measured. Given fine-grained tools that had to be
sequenced, an early version got **8 of 8 tasks wrong**; the same tasks with
coarse tools came out **8 of 8 right**. Every unit of reasoning moved out of
the model and into ordinary Swift is a unit of reliability bought back.

### Rules live in the tool, never in an argument

Rules are *not* expressed as parameters for the model to set. Instead they are
implemented in Swift, inside the tool, where they always apply.

The clearest example is what happens to linked pages:

- **Publishing** a page publishes what it links to, **and stops where a link
  lands on another class page**. There is no `includeLinked` flag for the model
  to decide about, because a class page whose linked notes are invisible is
  broken, always — and no flag for the stop either, for the same reason.

  See ["The walk stops at a class page"](#the-walk-stops-at-a-class-page)
  below for the decision, what was rejected, and what a teacher is told.
- **Unpublishing** is deliberately *not* the mirror image. A linked page comes
  down only when the pages being taken down are the **only** ones that link to
  it — otherwise hiding this week's lesson would strip a page last week's
  lesson still points at. Three kinds of page never come down this way
  whatever the link count: a folder's landing page, anything in the section's
  Key Links, and any curriculum page, each of which is reached from somewhere
  other than a lesson.

  **Its reach does NOT stop at a class page**, on either platform, and that is
  the sibling decision rather than an oversight:
  [issue #201](https://github.com/russellgordon/plantoir/issues/201), held for
  v1.3.0 because it is the one half Windows does not already behave that way,
  and folding it into #173 would have put a red shared case into the v1.2.0
  contract. Until it lands, an unpublish that takes a class down leaves that
  class NOT coming back when its referrer is republished — publishing stops
  there now. That exception is written into the code comment it belongs to
  (`AssistPublishPlan.pageStillLinking`), and it is the strongest argument in
  #201.

That asymmetry is genuinely subtle. It is exactly the kind of thing a small
model would get wrong under pressure, and exactly the kind of thing a
`for`-loop gets right every time.

**A worked example of why the rule goes in the code and not the prompt.**
`publish_pages` accepts a date range, and the routing suite caught a typo'd
request — "publsh tomorows class … and the stuff it links to" — choosing it
10 times out of 10 with no page named and an open-ended start date, which
would have published the whole rest of the term. The obvious fix is to add a
sentence to the tool's description: *not for one day's class — use
`publish_class_on`*. That was tried, and measured: it fixed the typo case and
**broke three others**, sending "Publish Unit 2, Day 3" — a named page with no
date in it at all — to `publish_class_on` every time, and dropping the
window's own suggestions from 110/110 to 90/110. A small model reads a
sentence naming another tool as a *recommendation*, not a boundary.

So the wording was reverted and the rule became four lines of Swift: an
open-ended publish is refused, with a message saying what to do instead. A
refusal changes nothing the model reads, so it cannot cost accuracy, and
because the refusal comes back as ordinary text the model gets to correct
itself on the next turn. **Prompt text is a gamble that has to be
re-measured; a conditional is not.**

### The walk stops at a class page

Decided 2026-09-19,
[issue #173](https://github.com/russellgordon/plantoir/issues/173), after the
two apps were found to disagree: **Windows stopped at a class page and the mac
walked through it.** Windows' answer is the one that shipped, for BOTH rules
that follow links outwards — what a publish takes, and which pages inherit a
class's date.

**The rule.** A class goes up when the teacher names THAT class. A link that
lands on another class page publishes nothing and is not followed through, so
material reachable only *through* another class belongs to that class and goes
up with it. The rule is about pages REACHED, never about pages named: naming
two classes makes both of them starting points, and publishing a whole unit
names every class in it (one plan per class), so nothing is lost by asking for
more.

**What was REJECTED, and why it is the tempting one.** The middle position —
do not publish the linked class, but walk *past* it to the material beyond —
reads as the careful compromise and is wrong on two counts at once. Asked to
publish Unit 2, Day 3, it would publish Day 4's worksheet, which puts it in
front of students a day early, and re-date it to Day 3's day, which is the
wrong lesson. Material behind a class is that class's material.

**How often a teacher meets it — measured, not assumed.** A class page has to
link to another class page for any of this to fire, and the shipped content
never does: **0** class→class links across **3,172** class pages and **7,930**
wikilinks in the 38 example payloads, and **0** across **600** class pages and
**2,008** wikilinks in the 50 skeletons. Every `[[Unit x, Day y]]` link in
`support/` comes from somewhere that is not a class page — 88 from
`per_section/index.md`'s "Most Recent Class" transclusion, 6 from
`shared/Style/What This Site Can Do.md`. So this fires only on a class→class
link a teacher wrote themselves, which is a natural thing to write and which
nothing discourages. That is an argument about PRIORITY, not about whether to
settle it.

**The section index was deliberately NOT exempted.** `WikiLinkRewriter`'s
pattern counts an EMBED as a link, so `![[Unit 4, Day 23]]` on a section's
landing page is a link onto a class page — and publishing the index therefore
now publishes only the index and its non-class material. Measured before
deciding to leave it: **38 of 38** payload `per_section/index.md` embed a
class, and in **38 of 38** that class ships `publish: true`; **50 of 594**
skeleton index files embed a class, and **50 of 50** of those are published.
So a new section, and a deploy straight after setup, cannot produce a home page
pointing at a class students cannot see. The invariant is held by REPOINTING
rather than by link reach in any case: `SectionIndexPointer.repointIndex` runs
on every apply (`AssistPublishPlan.apply`, `SectionReDatePlanner.apply`) and
repoints the index at the most recent class students CAN see. Nobody publishes
a section by naming its index page, whose title is `Section <N>`. The index's
DATE is held twice since 2026-09-25 (#275): by this pointer when it repoints,
and by the BUILD on every preview and publish, which rewrites the teacher's
front page to the date of the visible class its embed names whichever way that
class was published — Russell's ICS4U front page stayed on its install day
because Day 3 was published in Obsidian, so no pointer ran. See
[the build pipeline](05-build-pipeline.md#dates-drive-everything).

**Two consequences worth writing down before somebody finds them.**

- **Re-dating a whole section claims material differently.** In
  `SectionReDatePlanner`, classes are walked earliest-first and the first to
  reach a page locks its claim, so Day 3's walk used to reach a worksheet
  *through* Day 4 and give it Day 3's new day. Day 4's own walk claims it now.
  Strictly better, and exactly the decision's own words.
- **Material behind an UNNUMBERED class page stops being re-dated by a
  whole-section re-date at all.** `SectionReDatePlanner` walks
  `ClassInsertionPlanner.numberedClasses`, so a teacher's `Exam Review.md`
  sitting in All Classes is not itself a walk root — and it is now a stop, so
  nothing behind it is reached either, where before it took the date of
  whichever numbered class could see it through that page. Measured: **0 of
  3,172** class-folder pages in the 38 payloads are unnumbered, so this is
  teacher-authored content only. It is the decision working rather than a
  regression; it is written here so it is not discovered as one.

**What the teacher is told.** The plan and the reply name the linked classes
that were left alone (`AssistWording.linkedClassesWereLeftAlone`, said once via
`AssistPublishPlan.describe()`, which is the text both surfaces use). Windows
says nothing today, and that silence is the one part of its answer worth
improving on: a teacher who is not told reads a plan quietly smaller than the
one they pictured, with no way to tell "it decided" from "it missed it". **Only
about a class students cannot already see** — "publish it when you get to that
class" is false about a class that is already published, and the sentence
exists to explain a link students cannot follow *yet*.

**The tool description was deliberately left alone.** `publish_pages` still
says it makes pages visible "along with every page they link to". A description
edit is a ROUTING change, measured in this repository at 110/110 → 90/110 for
one added sentence (see the worked example above); the description's job is to
make the model pick the right VERB, and reach is settled in code by design. The
exception is stated where a teacher can act on it — in the plan and the reply —
and where an implementer reads it, in `contracts/`. Changing it is a
MEASUREMENT, not an edit: re-run `research/ai-assist/trimmed-surface-suite.py`
before and after.

**Where it lives.** `AssistSectionGraph.reachFollowingLinks(from:)`, which
replaced `linkedPages(from:)` — renamed rather than edited in place so the
compiler handed over all three callers to be read again, since a silently
widened method is how the divergence happened at all. The contract is
`contracts/shared-rules.json` → `followingLinks.stopsAtAClassPage` and
`contracts/class-planning.json` → `datingPagesAClassBrings.reachStopsAtAClassPage`.
The three `followingLinks.publishing` booleans stay TRUE: the walk is still
transitive and still takes what a page links to; it has one stop.

### What counts as a link

Settled 2026-09-26,
[issue #294](https://github.com/russellgordon/plantoir/issues/294). The walk
above — and everything else that reads a wikilink on the mac — reads it
through ONE pattern, `WikiLinkRewriter.pattern`. That pattern had a hole:
Obsidian writes an alias inside a Markdown table as `[[Ohm's Law\|Ohm]]`,
escaping the pipe so the cell does not end there, and every reader took the
name up to the pipe — `Ohm's Law\` — which matched no page and was silently
dropped as "a link to something outside this section". The same form turns up
in ordinary sentences as well, and Quartz v4.5.0, which draws the site, reads
it as a link wherever it is: `quartz/plugins/transformers/ofm.ts` lines
117–119 at the v4.5.0 tag the image clones (read in the image, `/opt/quartz`),
`/!?\[\[([^\[\]\|\#\\]+)?(#+[^\[\]\|\#\\]+)?(\\?\|[^\[\]\#]+)?\]\]/g` — the name
excludes a backslash and the alias is `\\?\|`.

**The rule** (`contracts/shared-rules.json` → `readingALink`, ten cases both
apps and the build read when #294 landed — forty since #313, below): the name runs from `[[` up to the first `]`, `|` or
`#`, and a backslash immediately before that character is not part of it. The
pattern is `(!?\[\[)([^\]|#]+?)(?=\\?[\]|#])` — lazy, stopping BEFORE an
optional backslash, with the backslash in a zero-width lookahead. That last part
is load-bearing: the backslash is outside the match, so every rewriter that
replaces the match or the name (`WikiLinkRewriter.rewriting`,
`FolderPathRewriter`, `PageReferences`) leaves it where it was. A rename of
`Unit 2, Day 3` writes `[[Module 2, Day 3\|Tuesday]]`; a rewrite that dropped
the backslash would write `[[Module 2, Day 3|Tuesday]]` and split the table
cell in two — which every "does the link point at the new name?" check passes.

**Who reads it — eight places, one fix.**

| Reader | What was wrong before #294 |
|---|---|
| `reachFollowingLinks` (publishing) | the page linked from a table did not go up, nor what it links to |
| the dates a class brings (`dateMovesFollowingClasses`, `SectionReDatePlanner`) | the page did not take its class's date |
| the site check (`linksIntoHiddenPages`, `visiblePagesNothingLinksTo`) | a link into a hidden page missed; a page linked only from a table called an orphan |
| `AssistPublishPlan` (who links in, Key Links) | the table link did not count as a referrer |
| `CoursePageCopy` — copying with the pages it links to (#207) | the linked page was not offered; `pagesEmbeddedIn`, a hand-rolled scanner, strips the backslash itself |
| `PageReferences` — pictures carried by a copy | `![[pic.png\|300]]` in a table was not carried |
| `WikiLinkRewriter.rewriting` / `countLinks` — the unit-word rename and CLASS INSERTION | the link was not renamed. After inserting a class, `[[Unit 2, Day 4\|Thursday]]` would still say Day 4 — which is now the class just inserted: a link to the wrong lesson, not a dead one |
| `FolderPathRewriter` | harmless (it rewrites a folder prefix), but it held a COPY of the pattern string; it now references `WikiLinkRewriter.pattern` |

Since #313 every one of these reads its matches through ONE entry point,
`WikiLinkRewriter.linkMatches` (or, for the Markdown-link and `src` shapes,
`MarkdownCode.matches(of:in:outside:)`), which applies the same code mask —
see ["Code is never a link"](#code-is-never-a-link-313).

`AssistSectionGraph.linksAsWritten` (#167) used to strip the backslash by hand;
the strip is gone, because a second strip would only hide a regression of the
first. An eleventh reader is deliberately out of scope:
`SectionIndexPointer.repointing` hand-splits a front page's whole-line
`![[…]]` on `|` and `#`, and a line cannot start with `![[` inside a table
row; 0 such lines ship.

**Measured** over the 12,128 pages of the 39 payloads and 50 skeletons, with
`NSRegularExpression`: the old and new patterns match the **same 38,659 links
at the same offsets**, and **229** names read differently — every one a name
that used to end in the backslash of a `\|`: 142 in tables, 87 in sentences
and in code examples. Over ALL of `support/` (12,490 pages, the example course
included) it is 39,570 links and **230**, the extra one a code example on
EXC2O's Scavenger Hunt page. Read line by line (as `PageReferences` does),
one more difference appears: the prose line "Type two open square brackets:
`` `[[` ``", 90 times, used to match with the name "`" and now does not match at
all — never a file, so harmless. **Estimated, not measured** (an emulation of
the section graph that approximates `ClassPages` by a `Word N, Word N` name):
in the payloads, fixing it adds about 46 page-to-page links that resolve within
a course, and about **104 of 3,258** class pages reach about **137** more pages
when published. 0 of the 229 point at a class
page, so the insertion consequence is latent in shipped content and bites
teacher-written tables.

**What a teacher sees the day it ships.** A publish can take more pages than
before, and the plan names them; `linkedClassWasLeftAlone` can now fire for a
class linked from a table; the site check's hidden-link and orphan lists change
on real courses (correct, but different); renames and insertions count and move
more links; the copy checklist lists more pages. No sentence changed and no
trail event was added — no line records what a publish reached, and the lines
that carry a count of links rewritten become more correct, not untrue.

**The build.** The shared Python (`build_site._extract_wikilink_targets`)
already read `\|`. It did NOT read `[[Page#Heading|words]]` at all, because
its alias group came before its heading group; that was reordered in the same
piece, and it changes teachers' dates — see
[05 → Links to directly](05-build-pipeline.md#dates-drive-everything).

**Rejected.** Stripping the backslash in `linkTargets` alone (what the issue
text implied): publishing would work and seven readers would not, one of them
the insertion case above. Excluding the backslash from names altogether
(`[^\]|#\\]+`, closer to Quartz's own class): `[[a\b]]` would then name `a`,
and a rename of a page called `a` would rewrite it; the lookahead differs from
the old pattern only at a backslash right before `]`, `|` or `#`. Skipping
links inside code in the same change: deferred because it changes what
publishing takes by a different rule and needed its own measurement, and
decided since in [#313](https://github.com/russellgordon/plantoir/issues/313)
— below. A contract case
for `[[a\b]]`: Quartz does not draw it as a link, and nobody has decided what it
should mean. The install-time readers in `setup_course.py` and the
curriculum-coverage patterns shared the cause but not the feature, and were
fixed separately in
[#314](https://github.com/russellgordon/plantoir/issues/314) — see
[05 → Which shapes are links](05-build-pipeline.md#dates-drive-everything).

#### Code is never a link (#313)

Settled 2026-09-26, [issue #313](https://github.com/russellgordon/plantoir/issues/313).
**A `[[…]]` or `![[…]]` whose opening brackets sit inside a fenced code block
or an inline code span is an EXAMPLE of a link, not a link.** It is not
followed by publishing, the dates a class brings, the site check, "what does
this page link to?", copying, the installer or the coverage map, and it is not
rewritten by a page rename, a unit-word rename, a class insertion or a folder
rename. That is what Quartz already does: `ofm.ts` builds links with
`mdast-util-find-and-replace` over TEXT nodes only (lines 209–378 at v4.5.0),
so `code` and `inlineCode` are never searched.

**Built in real Quartz, shape by shape** (`npx quartz build` on v4.5.0, links
read from `contentIndex.json` and the rendered article):

| Shape | Quartz draws a link? |
|---|---|
| `` `[[X]]` ``, ``` ``a ` [[X]] `` ```, a span across two lines of one paragraph, a span in a table cell | no |
| ```` ``` ```` fence, `~~~` fence, ```` ```` ```` holding ```` ``` ````, a fence inside a `>` callout, a fence never closed | no |
| four-space indented code after a paragraph and a blank line | no |
| an indented line that continues a LIST item | **yes** |
| a lone, never-closed backtick before the link | **yes** |
| `<code>[[X]]</code>` (raw HTML) | **yes** |
| `~~~` inside a ```` ``` ```` fence, then a link after the ```` ``` ```` closes | **yes**, the link after |

**The rule, in short** — written out to be implemented from in
`contracts/shared-rules.json` → `readingALink.whatIsCode`, with its limits in
`whatIsCodeLimits` and 30 of the 40 cases in `readingALink.cases`. The page is read a
line at a time; a line's BODY has any `>` markers taken off, and its DEPTH is
how many there were. A fence opens on a body starting with three or more
backticks or tildes (backticks with another backtick later on the line are
inline code instead), closes on a line at the same depth holding a run of the
SAME character at least as long with nothing after it, ends at a line with
fewer `>` (a fence in a callout ends with the callout), and runs to the end of
the page if never closed. Code spans live within a paragraph — which breaks at
a blank line, a fence, a deeper quote, a list marker, a heading (which is a
paragraph on its own), a table row or a rule line such as frontmatter's
`---` — and a run of N
backticks closes on the next run of EXACTLY N; a run never closed is plain
text; outside a span a backslash escapes. Nothing else is code: not indented
code, not HTML `<code>`, not math, not `%%` comments (a separate question,
[#331](https://github.com/russellgordon/plantoir/issues/331)). A link is in
code when its `[[`, or the `!` of `![[`, starts inside a code range. **And a
match that starts in code is not merely dropped: the search starts again where
that code ENDS.** The link pattern crosses a `[`, so in "Type `` `[[` `` to
start one, then [[Real Page]]" a match from the example's brackets runs on to
"Real Page" and swallows the real link; dropping that match would drop the
link with it. That case was found while implementing, with eight more. Four —
a bare `~~~` line inside a backtick fence, a TILDE fence inside a callout, a
heading, and a callout line straight after a paragraph — because four
mutations of the rule passed the cases before them; for the first two: the traceback case
carries text after its tildes, and the backtick callout's fence lines happen to
pair up as an inline span. Three came from the first implementation review, each a
place where the first version DROPPED a real link Quartz draws: a fence left
open inside a callout ran on to the end of the page (it now ends with the
callout — the fence belongs to its opener's quote DEPTH, and only a line at
that depth closes it); a `> ```` line inside an unquoted fence closed it; and a
backtick in frontmatter paired with one in the body (a rule line — `---`,
`***`, `___`, `===` — now breaks a paragraph, and a heading is a paragraph on
its own). A fourth came from the second review: a paragraph's quote depth is
its FIRST line's, because an unquoted line inside a callout paragraph is a
lazy continuation and must not make the next `>` line look deeper. None of
the nine was built in Quartz; all 40 cases were checked
against its parser stack (remark-parse 11 + remark-gfm 4 + remark-frontmatter,
with Quartz's own link pattern run over text nodes), which agrees with every
one. The same stack judged 20,000 random texts built from backticks, tildes,
`>`, list and heading markers, rule lines, indents and `[[x]]`: every text in
which the rule reads as code a link Quartz draws contains a four-space or tab
indent or a list marker — the two stated limits, indented code and list
containers.

**One implementation per language, shared by every reader and rewriter in it.**
On the mac, `MarkdownCode` (UTF-16 offsets, the unit `NSRegularExpression`
reports — never `Character`s, since `"\r\n"` is one grapheme and a scan for
`"\n"` misses every line ending of a page written on Windows), behind
`WikiLinkRewriter.linkMatches`; in the build and the installer,
`scripts/markdown_code.py`. Measured, the two agree offset for offset on all
12,490 pages of `support/` and on 50,000 fuzzed texts built from backticks,
tildes, `>`, `[[`, `]]`, backslashes, CRLFs, an accent and an emoji. What
changed on the mac:

- `AssistSectionGraph.linkTargets` (publishing, dating, the site check,
  copying) read EVERY match, code and all — 1,896 across `support/`.
- `AssistSectionGraph.linksAsWritten` had its own stripper, `withoutCode`,
  now DELETED: the `~~~` flip above dropped 22 real links, and it saw no fence
  inside a callout, so 270 examples on the Scavenger Hunt pages read as links.
- `WikiLinkRewriter.rewriting` and `countLinks` (page rename, unit-word
  rename, class insertion), `FolderPathRewriter` (both link styles),
  `PageReferences` (the copy's pictures, all three of its shapes, inline code
  now included) and `CoursePageCopy.pagesEmbeddedIn` (a hand-rolled scanner,
  now `linkMatches` keeping the `![[`).

**Measured with Quartz's own parser** (remark-parse 11 + remark-gfm 4, the
stack v4.5.0 uses, classifying every match by its enclosing node; it skips
Quartz's `textTransform` pre-pass, which cannot create or remove a code node
in shipped content, and it measures what the SITE shows, not Obsidian's
editor). Over all of `support/` (39 payloads, 50 skeletons, the example
course; 12,490 pages), 39,570 links match: **37,674 outside code, 1,139 in
inline code, 757 in fenced code and 0 in indented code**. Only **8**
page-to-page links existed solely inside code, on 3 pages: SBI4U's and SPH3U's
"What This Site Can Do" naming a concept as syntax, and six on TEJ2O's
"Control Something with Code", in code only because its fence was broken (see
below). By an emulation of the section graph (an estimate), **no class page —
of 3,258 in the payloads and 600 in the skeletons — reaches fewer pages when
published.** 0 class names and 0 real folder paths sit in shipped code, so the
rewriter half moves nothing that ships; it matters for what teachers write.

| Reader, before #313 | Real links it dropped | Examples it read as links |
|---|---|---|
| mac `linksAsWritten` (`withoutCode`) | **22** | 277 |
| mac `linkTargets` (publishing, dating, site check, copy) | 0 | **1,896** |
| Windows `WikiLinks.Parse` (`WithoutCode`, emulated) | 0 | 277 |
| build `_extract_wikilink_targets` | 0 | 7 (TEJ2O only) |
| the rule | **0** | 7 before the TEJ2O fix, **0** after |

**The shipped page this exposed.** TEJ2O's `shared/Labs/Control Something with
Code.md` opened `   ```python` at three spaces inside step 4 of a numbered
list and wrote the program at column 0. CommonMark cannot continue a fence
lazily, so the list item — and the fence — ended at the first column-0 line,
and the column-0 closer then OPENED a fence that ran to the end of the page:
on the site, `[[Debugging Basics]]` showed as raw text and the whole curriculum
block as code (built in Quartz and seen). Re-indented in the same piece, so
the coverage map keeps B2.3, B2.4, B5.1, B5.2 and B5.4 for that page under the
new rule; it reaches NEW TEJ2O courses only (existing folders keep a page whose
site was already broken — no migration). `lint_payload.py` now refuses the
shape: a fence opened on an indented line whose lines fall back before the
closer.

**What a teacher can see change.** A publish plan no longer names a page that
is only shown as syntax; the site check stops warning about example "links"
into hidden pages, and a visible page mentioned only in code can now be called
an orphan — which is true, since the site has no link to it; the links answer
lists the ICS4U traceback pages' links in full; a new TEJ2O course's lab page
renders. No sentence changed and no trail event was added: no line records
which links a reader followed, and the lines that carry a count of links
rewritten become more correct, not untrue.

**Rejected**, with the reasons that travel:

- **Readers skip code, rewriters do not.** Two definitions of a link again: a
  rename plan would count links publishing does not follow, and a folder
  rename would edit an example the teacher wrote (`PageReferences` already
  refused that for fenced code).
- **Recognising indented code.** 0 shipped links sit in it, and doing it
  properly needs list-container tracking in three languages. Obsidian writes
  nested lists with tabs, and an "indented after a blank line" shortcut drops
  links from loose nested lists — silently, in the direction that leaves
  pages unpublished. The case "an indented line in a list is not code" pins
  it.
- **Treating HTML `<code>` as code.** Quartz draws a link inside it, so the
  site HAS that link; skipping it would leave a linked page unpublished.
- **Each platform keeping its own stripper.** That is how three came to
  disagree. One written rule and its cases, one implementation per language.
- **A real Markdown parser in the app** (swift-markdown, cmark). Nothing like
  it is shared by Swift, Python and C#, so the three would drift at exactly
  the edges the contract pins, and it is a dependency to vendor and sign. The
  measurement used one — remark — to JUDGE the portable rule, which is the
  right place for it.
- **Leaving TEJ2O alone and matching CommonMark's container rule**: the list
  tracking rejected above, to "correctly" hide seven links on a page whose
  author plainly meant them.
- **Stripping `%%` comments in the same change** — not this question and not
  measured for its effect on publishing:
  [#331](https://github.com/russellgordon/plantoir/issues/331).

**Not covered, on purpose — readers of one fixed shape, not of links in
general, named so nobody has to find them again** (from the implementation
review): `SectionIndexPointer.repointing` and its build twin
`build_site._class_embed_target` read a front page's whole-line `![[…]]` by
hand, so a front page showing `![[Unit 1, Day 2]]` alone on a line inside a
fence could have that line repointed — 0 of the 89 section front pages in
`support/` hold a fence; `AssistCurriculumMentions` asks whether a page
already says `[[A1.1]]` with a plain text search, so an example of it in code
counts as "already there" and the real mention is not added; and
`build_site.rewrite_section_wikilinks` rewrites a section-path alias link in
the BUILT copy only, so an example in code is displayed shortened and the
teacher's file is untouched. Each would take the mask in a line; none has
shipped content that reaches it.

### No booleans, and separate verbs

There is no single `set_visibility(publish: true/false)` tool. Publishing and
unpublishing are **separate verbs** with separate names, because a boolean is
a coin flip under pressure and a verb is not — which is precisely the failure
that vetoed both 3B models.

**And "publish this page" can correctly do nothing.** Whether a page is already
published is decided by what the BUILT SITE does with its flag, not by whether
the line reads `true` — so `publish: maybe`, `publish: on` and `publish: true
# covered Tuesday` are all pages students can already see. Asked to publish one
of those, the assistant answers `It's already been published.` and leaves the
file exactly as the teacher wrote it: tidying the value would be an edit nobody
asked for, in a file Obsidian very likely has open. Asked to HIDE the same
page, it changes and the odd value goes. Settled 2026-09-18 (issue #140); the
measured table is
[08 → Whether students see a page](08-course-config-reference.md#whether-students-see-a-page).

A value the assistant cannot read at ALL — `publish: !!str false`, a value on
the line below the key, an anchor — is a different case, and it is not left to
the reporting collapse: such a page is always treated as needing a change, so
the flag is written out in full and the page really does end up published.
What Plantoir still does not do is TELL the teacher that the value it found was
one it could not read; it simply writes a plain one in its place. That sentence
is the only part of the "say when we cannot tell" option still outstanding, and
08 says why it waits.

### No dangerous tool exists

There is no delete tool, no rename tool and no archive tool. Not "guarded by a
confirmation" — **absent**. A capability that does not exist cannot be reached
by a misrouted sentence, an odd phrasing, or text a model read in a page.
Asked to delete something, the larger assistant declines in 10 trials out of
10, because there is nothing in the list to pick; the smaller one misroutes to
`rebuild_preview`, which changes no page. Neither can delete anything, because
deletion is not a thing the list contains.

### Plan mode

*(The full treatment, including undo and how often the assistant backs up, is
in Part 6 → "Plan mode, undo, and how often to back up".)*

Every tool that changes a PAGE is, by default, wrapped in **plan mode**: the
assistant states what it understood and what it is about to do, and waits for
Go or Cancel. This is applied by Swift, from whether the tool has a `plan_`
twin — the model is not asked to decide whether something is risky.

Four writes have no twin and no plan, deliberately: `rebuild_preview` (changes
no page), `undo_last_change` (is the remedy), `cancel_scheduled_deploy`
(re-scheduling is the remedy), and `deploy_section` — which instead waits on
its own separate approval, in the teacher's words and naming the real
destination, whether or not plan mode is on. Deploying is the one act that
reaches students, so it never rides on a general setting.

On a Mac running the smaller assistant, plan mode cannot be turned off. On a
16 GB machine running the larger one, the app offers to stop asking after a
run of plans the teacher has accepted unchanged.

### The model's list is shorter than the server's

The same tools are also served over **MCP** (the Model Context Protocol), so
Claude Code can drive exactly what the built-in assistant drives and the
safety rules cannot drift between the two clients. The app answers this
itself — `Plantoir.app/Contents/MacOS/Plantoir --mcp-stdio <working-folder>` —
rather than shipping a second binary.

One thing to KNOW about that process, recorded 2026-09-10 when renaming a
course's word for a unit made it matter: the MCP server reads the working
folder ONCE, when it starts, and never reloads it. A Claude Code session left
open across a change made in the app — a folder rename, or the word for a
unit going from "Unit" to "Module" — keeps the course as it was and goes on
writing "Unit N" pages until it is restarted. The in-app assistant does not
have this problem, because it shares the window's own courses and the
configuration is updated in memory as it is written to disk. Windows'
`plantoir-mcp.exe` has the same exposure. Nothing here re-reads on a timer,
deliberately: a server that silently swapped its courses under a conversation
would be worse than one that has to be restarted.

Claude Code is offered a **longer** list than the local model: 32 tools
against 13 — the twenty-two that exist, plus ten served only over MCP.
(Windows' separate `plantoir-mcp.exe` serves 37; the gap is recorded in
[issue #66](https://github.com/russellgordon/plantoir/issues/66).) Three of the extra ones ask for judgement about meaning — reading the
curriculum and deciding which expectations a page addresses — which a large
model does well and a 4B model does not. Anything shown to the local model has
been measured against it, and a unit test pins the count so the list cannot
grow by accident.

The thirteen the local model sees:

| | |
|---|---|
| **Read** | `list_pages`, `read_page`, `check_section`, `read_remembered_timetable` |
| **Publishing** | `publish_class_on`, `publish_pages`, `unpublish_pages` |
| **Site** | `rebuild_preview`, `deploy_section`, `schedule_deploy`, `cancel_scheduled_deploy` |
| **Schedule** | `add_next_class` |
| **Recovery** | `undo_last_change` |

**`schedule_deploy` asks one question of macOS, and only from the app's own
window (#212).** Once a deploy is set, the in-app assistant — like the
scheduling sheet — calls `ScheduledPublishNotice.askPermissionIfNotAskedYet`,
so the first time a teacher schedules they are asked whether Plantoir may tell
them, with a notification, how the run went. It is skipped when `surface ==
.mcp`: an outside assistant's process has no window to explain the question, so
a teacher who schedules ONLY that way is never asked and never notified (a known
limit, `documentation/07-deployment.md` → "When nobody is looking"). No tool's
description, schema or result changed; the tool-surface hashes are the same
before and after.

---

## Part 5 — How it is measured

None of the choices above were made by taste. The routing suite (results in
`research/ai-assist/thirteen-tool-surface-results.txt`) sends 42 phrasings — including deliberately informal
ones, typos, out-of-scope requests and every phrasing the assistant's own
window offers as a suggestion — through the real tool surface, ten trials
each, and scores what came back.

Most recent run, Qwen3 4B against the shipping 13-tool surface:

| Measure | Result |
|---|---|
| Suggestions the window offers, routed correctly | **110 / 110** |
| Polarity inversions (publish when told to hide) | **0** |
| Malformed calls, wrong course, invented dates | **0** |
| Median warm reply | **0.53 s** |
| Prompt size | ~2,650 tokens |

The suggestion cards in the assistant window are not decoration: they are
phrasings that have been *measured*, word for word — 110/110 over the eleven
the suite carries. The window offers nine of them today, two reworded since
that run; both reworded shapes are matched in Swift before the model is
reached, so the wording change cannot cost a misroute. A card offering
something the model is unreliable at would be worse than no card at all, so
one was removed for exactly that reason.

### Re-measured on Metal after the system prompt changed

The system prompt gained two sentences on 2026-08-24 (`b77b91bd`) on the
strength of numbers taken on **Windows, in a container** — the folder's index
classifies that run so, and its 1-192 s per-call latencies are a CPU profile,
so the "Vulkan" in issue #117's title belongs to the tweak's own before/after
(`conversational-residue-results.txt`, Windows NATIVE) and not to the 72% it
set out to improve. Issue
#117 re-measured it here. Full conditions, thresholds and per-probe tables in
`research/ai-assist/metal-routing-results.txt`; the summary, 29 probes on the
shipping 13-tool surface, M4 Pro, llama.cpp b10435 native with Metal, each
tier at its own context size:

| | Qwen3 4B (`.large`) | Qwen2.5 1.5B (`.small`) |
|---|---|---|
| All 29 probes, shipped prompt | **271 / 290 (93%)** | 208 / 290 (72%) |
| The same, with the pre-2026-08-24 prompt | 270 / 290 (93%) | 199 / 290 (69%) |
| The eleven promise-card probes (**Windows'** `ExampleRequests`, not this app's shelf) | **110 / 110** | 90 / 110 |
| Polarity inversions | **0** | **0** |
| Tool calls whose arguments were truncated (suite body, `max_tokens` 256) | **0** | 12-19 per 290 |
| The same under the app's own body (which sent no cap then — before #166) | **0** | 3 per 87 |

Three things to take from it — and one that is not in the table: on this same
suite the 4B scored **280/290 with the Windows-comparable 18 at 180/180** in
August, and the whole difference is two probes, one of which (`read`, answered
with `check_section` where it used to answer `read_page`) is unexplained by
anything measured here. That is issue #167. (**Answered in code since
2026-09-25** — re-measured across six courses and fourteen dates, the probe
turned out to be the lucky member of a family the model gets wrong on both
tiers; see "'What does this page link to?' is answered in code" in Part 3.)

**The 2026-08-24 change is neutral on the tier this Mac runs** — 28 of the 29
probes give the identical tool with the old wording and the new one — and the cluster it was written for was never present
here: "I posted Unit 2, Day 3 by mistake. Make it a draft again." is
`unpublish_pages` 10/10 in every arm of both models, before the tweak and
after it. **On the small tier it did buy something**: the older wording let
the model DECLINE a plain hide request 6 times in 10, where the current one
declines once.

And **the two tiers are not two grades of the same thing**. This matters more
widely than "old Macs": the smaller assistant is a CHOICE any teacher can make
on any machine (`contracts/shared-rules.json` → `assistantModelChoice`), and
because it is comfortable on essentially every Mac — 1.75 GB against a third
of physical memory — picking it raises no caution at all. The small one is
solidly right on 19 of 29 probes and solidly wrong on 7, including every way
of asking for a deploy at a time — the mac's own shelf card "Deploy at 6:30
AM" routes to `deploy_section`, deploying immediately, 10/10 on the small tier
while the 4B gets it right 10/10 (issue #168). **That is still true of the
MODEL**, and since 2026-09-19 that exact sentence no longer reaches it: it is
a parsed family in `AssistCardCommand`, so the shelf's card is answered in
code. A teacher who phrases it some other way still meets the misroute, which
is why the same piece also made the immediate deploy card say that it happens
now — see "A time is a number, not a judgement" below. Confirmation before acting does
not turn that into a safe failure by itself: `assistantAsksBeforeChanging` is ONE
setting for both tiers and defaults on for both (`AssistantSettingsTests`
asserts it on a 48 GB machine), approval is per TOOL — `needsApproval: true`
on `deploy_section` and `schedule_deploy` and nothing else — and the tier only
changes the CAUTION a teacher is shown when they turn confirmation off
(`AssistModelLibrary.confirmationCaution`). A sentence here previously claimed
the small tier confirms and the large one does not; it never has.

**Something both platforms must know before quoting a zero.** Every suite in
`research/ai-assist/` that printed a `malformed tool calls: N` line USED TO
parse a tool call's arguments as `try: json.loads(...) except: args = {}`, so
a call whose argument JSON was cut off short was recorded as a call with no
arguments and never as a malformed one. Both suites that are run today —
`trimmed-surface-suite.py` and `teachers-say-suite.py`, the Windows-side one —
count it properly as of 2026-09-18, in shared Python, so a re-run of either
counts honestly. **What Windows must know is about results already taken:
every "malformed tool calls: 0" in the `teachers-say-results.txt` numbers, and
in the seven other older files, means "no HTTP errors" and nothing more.** All
nine carry a dated note saying so. `shipped-surface-suite.py` still has the
old shape and is left alone deliberately — it is marked HISTORICAL and cannot
be meaningfully re-run, because its probes name tools the app no longer has.
(`routing-suite.py` is the exception worth naming: it keeps the raw string as
`{"__unparseable__": …}` and labels its own line "runtime rejected", so it
never made the false claim — it simply has no count of the other kind.)

The mac WAS the platform exposed to the underlying fault: `AssistModelClient`
sent no `max_tokens` at all where Windows' `LocalModel` sends 512, so a
runaway here ran until the context was full. Closed by #166 — the mac now
sends the same 512, and both halves of what happens to a stopped reply are
described in "Step 1" and "Step 2" above. The rows in the table are from
before that change and stay as they were written; a re-run of the `--app-body`
arm reproduces them only with `--uncapped`.

**Windows is not fixed by that, and this is the part they owe.** Their cap
bounds the wait, and `LocalModel.Ask` returns `choices[0].message` and drops
the rest of the response, so the finish reason never leaves `Ask` and a
cut-off call is acted on. They meet it MORE often than the mac ever did,
because their cap fires where the mac's context used to.

The figures above are not a failure rate. The suite runs at temperature 0.1
(0 in the arms that copy the app's own request), which is near-greedy: ten
trials tell you whether a model systematically mishandles a sentence, not how
often a teacher would be misrouted. Re-running an identical arm an hour later
moved the total by 3-5 responses in 290.

**A harness divergence worth knowing, for whoever measures next.** The suite's
system-prompt constant writes ASCII hyphens where `AssistAgent.swift` — and
`AssistAgent.cs` — write em-dashes. Six characters, the only difference, and
every routing number in `research/` before 2026-09-18 was taken against the
hyphen form rather than the shipped string. Measured both ways on the same
server the same evening: 204/290 against 208/290, no stable probe moving by
more than 3/10, which is inside this suite's own run-to-run wobble. **So the
older numbers stand**, and neither app owes the other a change. The suite now
keeps `--prompt hyphen` as its default for comparability, offers
`--prompt shipped` which READS the literal out of the Swift, and asserts on
every run that the two differ by exactly those six characters — because the
comment that used to hold them together said "keep this in sync by hand".

---

## Part 6 — The design in full, and the reasoning behind it

Written while the assistant was built, and kept because a behaviour can be read
off the code while the reason for it cannot. Parts 1-5 are the tour; this is the
reference.

## The assistant's division of labour — the rule everything else follows

**The model picks which Swift function to run, and fills in its arguments.
Nothing else.** Every rule about what an action MEANS lives in code. If you
take one thing from this file, take this: it is what makes a small local
model viable, and every problem worth having came from violating it.

The split is measured, not aesthetic. Across the same runs the model:

- **misrouted five of the eleven suggested phrasings in EVERY trial** — it is
  bad at choosing;
- produced **zero wrong courses, zero wrong dates, zero type errors, zero
  invented dates** — it is good at filling in.

So take the choosing away wherever it can be taken, keep the filling in.

Three consequences that follow, each of which cost something to learn:

1. **Tools are coarse.** Given `resolve_links`, `set_publish` and
   `publish_section` separately, and asked to publish tomorrow's class *and
   everything it links to*, the model chose `publish_section` 8 times out of
   8 — skipping the link resolution. Perfectly consistent, and wrong. One
   `publish_class_on` that resolves links itself: right 8 of 8.
2. **Fixed phrasings never reach the model.** The card's unambiguous shapes
   are matched in code. If you reword one, update the matcher too, or the
   shortcut silently stops firing and the phrasing quietly starts being
   routed instead — it will look correct and behave worse.
3. **Absence is the guardrail.** There is no delete tool, so "delete the
   Unit 1 folder" cannot be honoured however confidently it is asked. Not
   judgement — no route.

### Rules belong in the tool, never in an argument

`publish_pages` and `unpublish_pages` used to take an `includeLinked`
boolean with no default, so the MODEL decided. That is the same reasoning
this design exists to keep out of the model, and a boolean is the thing that
inverted polarity on the 3B. It is gone, and the rules are now code:

**Publishing always publishes the pages it links to.** Never publish a page
whose links lead somewhere students cannot see — that is the whole point.

**Unpublishing is NOT the mirror**, and this asymmetry is deliberate:

- unpublish the named page(s);
- also unpublish a linked page **only if that page is linked to ONLY by the
  page(s) being unpublished**. If anything else still links to it, it stays —
  otherwise you create the dead links the publish rule exists to prevent;
- **never** unpublish, whatever the link count: a folder's landing page
  (`index.md` — Concepts, Investigations…), any page in that section's **Key
  Links**, or any **Curriculum** page (detect with `build_site.py`'s own
  rule: any folder segment containing "curriculum").

The plan should say what it **kept** and why — "Ohm's Law stays: Unit 3,
Day 2 still links to it" — not only what it removed. A teacher needs to see
the tool reasoned about it, or they will check by hand and the rule has
bought nothing.

#### Never ask the model for something the window already knows

The tools take `course` and `section` as arguments, and for a long time the
model filled them in. It should never have been asked: the assistant window is
opened FOR one section and its title says so.

The failure this produced is instructive because it is not a stupid one.
**"Unpublish Unit 4, Day 12" was read as section 4**, and the teacher was told
their course has no Section 4 — a perfectly reasonable misreading of a page
name that begins with a number, and one that no amount of describing the
argument would prevent on the next page name that does. It happened more than
once before it was fixed.

So the agent takes the SECTION back before anything runs. It cannot cost
routing accuracy, because it changes nothing the model reads — only what is
done with what it said.

**The COURSE is a different question, and answering it the same way was a
mistake that shipped from v1.1.0 to 2026-09-19** (issue #202, the mac half of
#180). Overwriting the course too meant that "publish MCV4U's class", typed in
a VVH2O window, published a VVH2O class and told the teacher it had. **A
failure that reports success is the one kind a teacher cannot catch**, and it
is worse than the lost turn the binding was invented to prevent. Windows never
had it: each of its assistant sessions is locked to one course
(`AssistWorkspace.Course` throws an `AssistRefusal`), and Russell decided on
2026-09-19 that Windows' answer is the one both apps should have.

**What is BOUND, and what is GUARDED.**

- **The section is bound**, always, to this window's — whether the model named
  one, named the wrong one, or left it out. An absent one counts because no
  tool reads an omission as "every section": all twelve local tools that take a
  section require it, so a call that left it out used to reach the runner with
  nothing to locate and come back with `There is no course called ""`, a
  complaint that reads as though the teacher's sentence were the problem.
- **The course is guarded.** Absent, it is filled in with this window's.
  Matching case-insensitively, it runs — and it runs in the WINDOW's spelling,
  because `AssistToolRunner.explain(call:)` prints the code verbatim on
  `schedule_deploy`'s approval card, so keeping the model's casing would put
  "deploy ics3u Section 1" in front of a teacher about to press Go. Anything
  else and **the turn is refused**: `AssistAgent.think()` returns before
  `messages.append(reply)`, which is above everything that could act — no
  settling, no plan twin, no approval card, no tool. "Nothing ran" is true by
  construction there rather than by inspection.
- **Both are gated on the tool's OWN SCHEMA** declaring the argument, never on
  a list of tool names. Today the two would agree — twelve of the thirteen
  local tools declare `course` and `section`, and `undo_last_change` declares
  neither — which is exactly when a hand-kept list looks harmless and starts
  rotting. `undo_last_change` is untouched by all of this BECAUSE the gate
  reads the schema.
- **The refused turn is wound back** out of the conversation sent to the model,
  through the same `windTheTurnBack()` the cut-off gate uses (#166). The model
  runs at temperature 0, so a sentence left in front of it produces the same
  refusal on the next turn, and an assistant that reliably repeats its own
  refusal is worse than the fault it replaced. What the teacher SEES keeps
  their sentence, as on every path.

**Two sentences, not one**, in `AssistWording`: `askedAboutAnotherCourse` when
that course is in this working folder, and `askedAboutACourseThatIsNotHere`
when it is not. The first ends by telling the teacher to open that course's
section in Plantoir; the second cannot, because there is nothing to open, and
advice that cannot be followed is worse than none. Both say **nothing was
DONE** rather than nothing was CHANGED — the refusal fires on the four reading
tools as well, and "I haven't changed anything" answers a question nobody asked
of "what pages does MCV4U have?". **The first sentence names that course the
way the WORKING FOLDER spells it** — a teacher told to open "mcv4u" is being
sent to look for something their sidebar does not show, and it is the same
courtesy the window's own code gets on the approval card; the second carries
the model's own text, trimmed, because there is nothing else to show. Both
codes are trimmed of whitespace AND newlines, which is what
`AssistToolRunner.text(_:in:)` does before `locate` ever sees a value: a guard
that trims less would refuse `"ICS3U\n"` in an ICS3U window, losing a turn on
the teacher's own course. The trail line is
`assistant was asked about another course`, carrying both course codes and the
tool, never the argument values.

**Do this in the agent, not in the tool.** The same tools answer Claude Code
over MCP, where the course and section genuinely ARE the caller's to choose.
It is the window that is about one section, so the window is what binds them.
The runner gained one READING for this — `knownCourseCode(matching:)`, which
answers the one question the two sentences turn on and hands back the code that
goes into the first of them — and it is not the guard: it refuses nothing and
is asked by nobody but the agent.

**What was REJECTED.**

- **Overwriting the course**, as above: the fault being fixed.
- **Refusing only when the named course EXISTS in this folder**, and binding a
  code that names nothing to this window as a model slip. Tempting, because a
  code matching nothing cannot reach another course — and it leaves the door
  open on exactly the fault being closed: "publish MCV4's class" mistyped in an
  ICS3U window would publish an ICS3U class and report success. **The measured
  cost of refusing instead is negligible.** `research/ai-assist/`, counted
  per FILE rather than by arm (one line of Python counting `"course": "…"`
  over `*results*.txt`, so it can be re-run — a naive run returns **827 across
  seven files**, because two of the seven are single-turn experiments rather
  than routing runs and are not in the 686: `cache-restore-results.txt` (3, its
  own arm's ICS3U) and `token-cap-results.txt` (1, its own arm's VVH2O)):
  `trimmed-surface-results.txt` holds the only wrong course
  values anywhere — 16 `ICS3U` and 3 `ICS2O` against 118 correct — and its arms
  1–2 are the ones run WITHOUT `--real-course`, so the model was shown a
  placeholder code in the schema and echoed it. Everywhere else the value is
  always that arm's own course: `conversational-residue` 228,
  `macos-native` 358, `promise-card` 73, `shipped-surface` 27 — **686
  responses, 0 wrong course codes.** (#202's plan and its review quote the same
  fact with arm attribution instead: 634 responses taken with `--real-course`,
  0 wrong.) The
  app is always in that configuration: `AssistAgent.toolDefinitions` maps
  `namingTheRealCourse(courseCode)` over every definition, so the local model
  never sees a placeholder. (The tally script left in the scratchpad for #202,
  `p202_tally2.py`, cannot be cited for this: its `course=([A-Z0-9]+)` regex
  captures `T`/`F` out of `real-course=True` and reports the arm as course
  "T". Count per file.)
- **Allowing READS of another course.** Four of the thirteen local tools read
  (`list_pages`, `read_page`, `check_section`, `read_remembered_timetable`), and
  a rule that held only for writes is one a teacher cannot predict, because
  they cannot tell which tool the model picked. Windows' course lock applies to
  everything; so does this.
- **Refusing when the TEACHER'S OWN TEXT names another section** ("…in section
  2", typed in section 1's window). Considered on Windows for #180 and dropped
  there. The brief for v1.2.0 is to converge, not to invent; the section is
  simply bound.
- **`appliesOn: ["mac"]` on the new trail event**, which would have kept the
  Windows suite green. The filter exists, and using it here would bless exactly
  the gap rule 5 was written for: Windows refuses this request today and writes
  no line at all.

**No routing re-measurement is owed, and that is evidence rather than an
argument.** The model reads exactly two things — `AssistAgent.systemPrompt` and
`toolDefinitions` — and all of this happens after it has answered. Three
commands come back empty on this change: `git diff` over
`AssistToolSurface.swift`, `git diff` over `AssistToolDefinition.swift`, and,
after `--write-contracts`, any change under `tools` or `toolSchemas` in
`contracts/assist-cases.json` — that last one being a byte-level readout of the
surface each client really sends.

The rule as DATA is `contracts/assist-cases.json` → `windowBinding`: a window,
the arguments the model wrote, and either the arguments that run or the
refusal. AUTHORED, preserved across `--write-contracts`, and run on the mac by
`AssistWindowBindingTests`.

Worth a sweep of your own surface for the same shape — with the correction this
change is: any argument the surrounding context already determines should be
taken back on the way in rather than described more carefully in a schema,
**unless getting it wrong would act on something else entirely**, in which case
the answer is to refuse and say so.

#### A corollary, learned the expensive way: do not fix routing with words

When a probe routes to the wrong tool, the tempting fix is a sentence in the
tool's description telling the model when NOT to use it. **Measure that
before you keep it.** We did, and it was worse.

The case: `publish_pages` takes an optional date range, and a typo'd "publsh
tomorows class … and the stuff it links to" chose it 10/10 with no page named
and an open-ended start date — one lesson turning into the rest of the term.
Adding *"NOT for one day's class — for a single day use publish_class_on"* to
the description fixed that probe and **broke three others**: "Publish Unit 2,
Day 3", a named page with no date in it whatsoever, went to
`publish_class_on` 10 times out of 10, and the window's own suggestion cards
fell from 110/110 to 90/110. A small model reads a sentence naming another
tool as a recommendation rather than a boundary, and it does not reliably
notice which half of a sentence applies to it.

The wording was reverted to the byte and the rule became a conditional in the
tool: an open-ended publish (no pages named, a start date, no end date) is
REFUSED, with a message saying to use `publish_class_on` for one day or to
give both dates for a stretch. Three properties make that better than the
sentence:

- it changes nothing the model reads, so it **cannot** cost routing accuracy
  and needs no re-measurement;
- it is exact, where a description is a hint;
- the refusal comes back as ordinary text, so the model corrects itself on
  the next turn rather than failing at the teacher.

Applied to publishing only. An open-ended UNPUBLISH hides work rather than
exposing it, the same backup undoes it, and a teacher clearing a section back
to a date is a real thing to want.

**The general rule: prompt text is a gamble that has to be re-measured across
the whole suite; a conditional is not.** If you change any description, re-run
every probe, not the one you were fixing — that is the only reason we caught
this instead of shipping a regression that looked like a fix.

#### And when you REMOVE a tool, audit the refusals that pointed at it

Cutting `remember_timetable` from the local list was right — dates the model
supplies are dates it may have invented — but it left three refusals saying
"record them with `remember_timetable` first". The model can no longer see
that tool. **A remedy naming something unreachable is worse than no remedy**,
because the next move available to a model that cannot follow the instruction
is to improvise the dates, which is the exact failure the removal was meant to
prevent.

Two things had to follow the cut, and only one of them was obvious:

1. The messages now name no tool. They say what is missing and that the app is
   asking the teacher — which also stays true over MCP, where the client's
   tool list is different again.
2. **Something else has to actually ask.** On macOS a schedule sheet collects
   dates (typed, from a file, or from a shared sheet link); the tool leaves a
   request and whichever assistant window is showing that section presents it.
   That sheet existed and was already attached to the window — the call that
   sets the request was simply never written, so nothing ever opened it. It
   looked finished from every angle except running it.

So: **if Windows has no equivalent way to ask, `remember_timetable` must stay
on its local list.** The cut is only safe because something else asks. And the
audit worth running after any removal is not "does the surface still route"
but "can every refusal still be acted on by the surface that receives it".

### What the assistant's window must BE — and what it need not look like

Decided 2026-08-16, in answer to "must the bubbles match?" — **no.** The mac's
bubble geometry (13pt insets, 17pt corner radius, Messages' grey and its light
blue selection) was measured against Messages on the same screen, and copying
those numbers onto Windows would produce something that looks like a Mac
application running in the wrong place. **Build a chat that looks at home on
Windows.** WinUI's own type ramp, its own spacing, its own accent colour. Read
the mac's chat sections below for what the arrangement has to achieve, and
ignore the numbers.

What is NOT negotiable is the shape of the interaction, because that is the
product rather than the platform:

1. **It is a CHAT.** Not a form, not a command palette, not a properties panel
   with a text box on it. A teacher types a sentence and gets a sentence back.
2. **Everything goes through the chat — input and output both.** No result
   appears only in a status bar, a toast, a dialog, or a log pane. If the
   assistant did something, the conversation says so, in the conversation.
3. **The one exception is confirming an action**, where buttons appear — as
   they do on the mac for a deploy or a plan. A teacher agreeing to publish to
   students should not have to type "yes" and hope it was understood.
4. **What the teacher chose with a button goes into their chat history**, in
   their own bubble, as though they had typed it. Reading back a conversation
   where the assistant asked, nothing answered, and something plainly happened
   is worse than not being able to read it back at all. The two contract
   scenarios "the deploy card is agreed to" and "the deploy card is cancelled"
   assert exactly this, so a suite can check it rather than somebody's eyes.
5. **A thinking indicator is a MUST.** The local model takes seconds and the
   toolchain takes minutes, and a window that sits still through either one is
   indistinguishable from a window that has crashed. The mac shows one
   indicator for BOTH thinking and running a tool, deliberately: a teacher does
   not care which of the two the assistant is busy with, and two indicators
   invite the question. It hides while a card is waiting for a button — nothing
   is happening then, the teacher is.
6. **Up and Down walk back through what was asked before, as a Terminal
   does — the SAME KEYS as the mac.** Not a per-platform choice: a teacher who
   learns Up on one machine and finds it somewhere else on the other has
   learned nothing. It is also a requirement rather than a nicety — it is how
   somebody re-runs the thing they just ran with one word changed. The
   semantics are in `contracts/assist-cases.json` under `promptHistory`: eight
   step-by-step cases, the key names, and the two situations where the arrows
   must instead do their ordinary job and move the caret (a box holding more
   than one line, and nowhere further to walk — pass the key on rather than
   swallowing it, because a key that silently does nothing reads as a dropped
   keystroke). The two cases that get missed: the half-typed line is put aside
   and handed back rather than lost, and typing ends the walk so Down cannot
   silently replace what was just written.

And the rule that governs all of it, from row 1 of the improvement log: **the
window never names the machinery.** No tool names, no model names, no tokens,
no containers. "The small assistant" and "the larger assistant".

### The parts of those four areas that could NOT be a contract

`shared-rules.json` carries the rules. These are the neighbouring pieces that
are each app's own, written here because "not in the contract" must never mean "nobody
mentioned it".

**Scheduled deploys — the mechanism, and one refusal that may differ.** Writing
a plist and writing a scheduled task have nothing in common, so only the
refusals are shared. But one of them is a genuine fork: the mac refuses
Cloudflare with no Account ID **because it can pass `--account` in the plist and
therefore has to ask once, up front**. If a Windows scheduled task still cannot
be handed an account, then Cloudflare is not schedulable there at all — and the
right answer is a refusal that SAYS so, not a task that fails at 06:30 in
silence. Check it, and record what you find here; the contract
case says which of the two you are looking at.

Two more that stay per-platform: the plan's own words (the mac's says what has
to be true of the Mac — awake, plugged in, lid open — and Windows says something
different about sleep and Modern Standby), and cancelling, which on the mac is
`launchctl bootout` plus deleting the plist.

**The sidebar filter — the empty state.** The contract says WHAT matches. It
does not say what a teacher sees when nothing does, because that is a view: the
mac shows a short sentence rather than an empty pane, and the rule behind it is
that an empty list looks like a broken app while a sentence looks like an
answer. Say something; the words are the app's own.

**The transcript — everything except the stripping.** What is stripped is
shared (a colour code is a colour code). How much scrollback is kept, when the
view follows the tail, whether it scrolls on focus — all per-platform, and all
different in WinUI.

**Curriculum — the plan, not the recognition.** What COUNTS as an expectation
is shared and must be, because `build_site.py` decides what ships and an app
that disagreed would report coverage the site does not have. What a coverage
plan SAYS to a teacher, and how it is offered, is the app's own.

### The working-folder path bar — reported missing in use, 2026-08-16

The bar under the sidebar that reads "Working folder: … › … › Courses". On the
mac it does four things; on Windows the `BreadcrumbBar` currently does one, and
the difference was found by a teacher using it rather than by any test, which
is the point of writing it down now.

| What | mac | Windows today |
|---|---|---|
| Click a crumb | selects nothing — see below | **reveals it in File Explorer** |
| Double-click a crumb | opens that folder | nothing |
| Right-click a crumb | menu: **Show in Finder** / **Open Folder** | **no menu at all** |
| Hover a crumb | tooltip with the full path | nothing |
| Each crumb shows | the real folder icon + display name | name only |

**The two actions are genuinely different and a teacher wants both.**
*Revealing* opens the folder's PARENT with the folder selected — it answers
"where does this live?". *Opening* opens the folder itself — it answers "what
is in it?". Collapsing them into one gesture loses the other question, and
which one survives is arbitrary. The gestures follow the host file manager
deliberately, so a teacher who has used Finder or Explorer already knows them:
double-click opens, right-click offers both.

**Every crumb is live, not just the last.** That is how a teacher reaches the
folder ABOVE their working folder — to make a sibling, or to see where things
sit — without leaving the app to go and find it.

The testable half is in `contracts/shared-rules.json` → `workingFolderPathBar`:
the crumb list (every ancestor, root first, folder last — on Windows starting
at the drive rather than at `/`), the two actions with each platform's label,
and the gestures. The labels differ on purpose: "Show in Finder" against
"Show in File Explorer".

**Where the crumbs SIT, which took two goes to get right.** The bar has two
rules and they are one rule seen from each end: a path too long for the space
shows its END (`tooLongForTheSpace`, 2026-09-05 — an iCloud path runs through
`~/Library/Mobile Documents/com~apple~CloudDocs/…`, so the last crumb is the
only one that differs between a teacher's folders and it was the one lost), and
a path that FITS starts beside the label (`fitsInTheSpace`, 2026-09-09, issue
#145). The second was written four days after the first, because the first
BROKE it. The mac's bar was then a horizontal `ScrollView` (it is the last
of three forms now — see below); a scroll view fills whatever width it is given,
so once the content was anchored at the trailing edge, a short path was pinned
to the far end of the window with the label stranded at the other — reported from a screenshot, on every window, for four
days.

**The shape of that mistake is worth more than the fix**, because it is not
about SwiftUI: a greedy container handed an alignment meant for the OVERFLOW
case applies it just as happily to the case that fits, and the case that fits is
the ordinary one. The fix is to prefer the natural-size form —
`ViewThatFits(in: .horizontal)` on the mac, choosing the plain row and falling
back — through the collapsed row added the same day, below — to the scrolling
one. It lives inside `FinderPathBarView` rather than at a
call site, which matters: the folder picker had already met this and wrapped its
own copy in a `ViewThatFits`, so the knowledge existed in the repository while
the window's bar went on being wrong, and a third caller would have inherited
the bug again. Windows is not affected, and the reason is documented rather
than inferred: `MainWindow.xaml` puts a `BreadcrumbBar` in a `*` column, and
Microsoft's page for that control says it "displays each node in a horizontal
line" and that "if the app is resized so that there is not enough space to show
all the nodes, the breadcrumbs collapse and an ellipsis replaces the leftmost
nodes" — both halves of the rule. That is the platform's control being right,
not a decision anyone made, so a surface that ever replaced it with a
hand-rolled `ScrollViewer` of crumbs would need `HorizontalAlignment="Left"` on
its content and would meet exactly this.

**What "shows its END" LOOKS like, decided by watching Finder rather than by
taste.** Russell's instruction on 2026-09-09 was "no ellipsis on macOS, please",
with a screenshot of Finder's own path bar, and Finder was then measured at five
window widths before anything was written. It shrinks the middle names first;
then goes icon-only from the left, keeping the volume and the last crumb or two
named longest; and at its narrowest it clips the TAIL. The mac's bar now takes
the middle of that — every crumb keeps its icon and chevron, only the folder
itself keeps its name — and **two of Finder's behaviours are deliberately not
copied**. The intermediate step, names shrinking before they vanish, is
per-crumb width negotiation for a state a teacher passes through rather than
sits in. And the clipping is the very defect fixed on 2026-09-05: at 520 points
Finder had lost the folder's own name off the right-hand edge, which is what
`tooLongForTheSpace` exists to forbid. So when even icons and chevrons will not
fit, this bar falls back to its own end-anchored scroll rather than to Finder's
clipping — three forms, and `ViewThatFits` picks the first that fits.

**The ellipsis belongs on Windows and only there.** `BreadcrumbBar` replaces the
leftmost nodes with one, which is right on that platform because it is that
platform's control; putting it in front of a Mac teacher would be the same
mistake as saying "on this PC" to them, which is why the contract now records
the divergence beside the rule the way `specialNames.platformWording` does.

**A hidden name is not a lost one.** Every crumb keeps its tooltip, its
double-click and its context menu when collapsed, so hovering an icon still
says which folder it is — which is also why the collapse is safe to prefer over
scrolling: nothing becomes unreachable, only quieter.

**Pinned by measurement, not by eye.** A layout rule asserted in words is a rule
nothing runs. `PathBarWidthTests` proposes 1,400 points to the bar and reads
back the width it CLAIMS — the defect being precisely "claims all the width
offered" — the way `CloudSyncNoticeLayoutTests` reads height for the notice
above it. 175 points with the fix; 1,400 with it taken out, for a row that draws
in 175. A third case squeezes a long path to 320 and requires it to take all
320, so "ask for less" cannot be satisfied by a bar that clips instead of
scrolling. The collapse is checked the same way and indirectly on purpose, which
makes it stronger: a row that draws no ancestor names cannot change width when
those names change length, so two paths of the same depth — one with very long
ancestor names, one with short — must collapse to the SAME width while their
full rows differ. What that does NOT exclude, said rather than
hidden: a fixed-width truncation would pass it, since both paths' ancestors
would get the same room. What it catches is the regression that would actually
happen — SwiftUI squeezing the names variably as the space tightens.

**The general lesson, which is why this went unnoticed for months.** An
affordance that lives ONLY in a context menu is invisible to everything: no
screenshot shows it, no test on the other side asks for it, and the person
building the other app has no way to know it exists. When a change adds a right
-click menu, a double-click, a hover, or a keyboard shortcut, it needs a line
here **even though nothing on screen changed** — those are exactly the changes
a diff of the UI will not reveal.

### A second: the wizard's own answer keys, and the skeleton question

`course_config.json` carries two GROUPS of keys, and only one of them is the
settings form's. The other three are written once by the wizard, and
`setup_course.py` reads each as the DEFAULT for a question it would otherwise
ask:

| Key | What it decides |
|---|---|
| `use_skeleton` | Whether a course that is NOT TAKING a ready-made payload starts from its subject's skeleton — folders that suit the subject, four units of class pages to rename, placeholders saying what belongs where — or from nothing at all. |
| `prepopulate_example_content` | Whether one of the 38 ready-made courses is poured in. |
| `include_curriculum_pages` | Whether the curriculum pages written for this code come with it — taken with the payload, OR installed into the subject's skeleton when the payload is declined ([#251](https://github.com/russellgordon/plantoir/issues/251)). |

**`use_skeleton` was not written by the Windows wizard at all** (checked
2026-08-16; written since 2026-09-07, item 25). The Python then fell back to
its own default — `True` — so a Windows teacher got a skeleton and was never
asked. That is the question MOST teachers meet, because around 1,900 course
codes have a skeleton and no payload; only 38 have a ready-made course.

**Decided 2026-08-16: match the mac — ask the question and write the answer.**
The alternative was to always start from the skeleton and write
`use_skeleton: true` explicitly, which was defensible; the reason it lost is
that this is a real choice a teacher has, and the two apps should not differ on
whether a teacher gets to make it. Silence was never an option either way,
because the next change to that default in the Python would move Windows and
not the mac.

The mac writes each of these as `capabilityExists && teacherSaidYes` — for
`use_skeleton`, `hasSkeleton(forCode:takingExampleContent:numbered:) && startsFromSkeleton`
— so a stale `true` in an old config can never mean anything. The capability
half took the second argument on 2026-09-21
([#248](https://github.com/russellgordon/plantoir/issues/248)): it used to ask
only whether example content EXISTED for the code, which made it false for all
38 payload codes whatever the teacher chose, so declining the ready-made pages
wrote `use_skeleton: false` and the course arrived with empty folders. The
question is whether the teacher is TAKING the example content, and Windows'
`SkeletonCatalog.HasSkeleton` owes the same argument.

### A divergence flagged by sweeping, 2026-08-16 — checked again 2026-08-23, not present

`deploy.py` writes a marker the first time a section goes out —
`.netlify_sites/section<N>.json` or `.cloudflare_sites/section<N>.json` — and
both apps read it to answer "has this ever been deployed?". That answer decides
whether a scheduled deploy is allowed, because a FIRST deploy asks what to call
the website and nobody is awake at 06:30 to answer.

The mac reads the marker for the destination the course is configured for NOW.
This section originally warned that `AssistWorkspace.cs` accepted EITHER
folder — so a course deployed to Netlify and later switched to Cloudflare
would read as "already deployed" on Windows, letting a teacher schedule the
one deploy guaranteed to stop at a prompt in the dark. **Re-checked 2026-08-23
(item 7 above): that is not how the current code behaves.**
`DeployCommand.HasDeployedBefore`/`FirstDeployMarkerPath` are keyed by the
specific destination type, and every caller passes the CURRENT destination's
type — never both. A regression test
(`ScheduledDeployTests.ASwitchedDestinationIsNotConsideredDeployedJustBecauseTheOldOneWas`)
now pins exactly the switched-destination scenario this section described.

The rule and the paths are in `contracts/file-formats.json` →
`firstDeployMarkers`, including the third case: a folder deploy keeps no
marker at all and counts as always-deployed, because it asks nothing. That
file's `knownDivergence` field, which used to describe this Windows bug, is
now removed.

Worth knowing how this was found: not by a failing test, but by walking
`documentation/07-deployment.md` and asking which of its facts anything
verifies. Several of these contracts came out of reading the documentation
against the code that way.

### Two things to MEASURE on Windows rather than copy from the mac

Both are in the contracts, and both would be wrong to implement by reading the
mac's answer. They are small, and each is an hour that turns into a day when
skipped.

**1. Whether the browser needs `127.0.0.1` instead of `localhost`.**
`app-rules.json` → `linkRules.browserSafe` says the mac rewrites the preview
address before handing it to the browser. The reason is specific to Safari: it
tries IPv6 (`::1`) first for "localhost", the container publishes the port on
IPv4 only, and the failure reads to a teacher as "the server dropped the
connection" — not as anything to do with addresses. **Find out what Edge does**
before deciding you need the same rewrite. Open a preview, then try
`http://localhost:<port>` in Edge by hand. If it connects first time, drop the
rewrite and say so in a `mac` issue — that is a finding, not an omission,
and the contract should then note that the rule is mac-only. If Edge behaves
the same way, keep it and the contract stays as it is. **Still open as of
2026-08-23** — Windows already applies the rewrite (`OutputParsers.cs`,
`SectionDetailView.xaml.cs`), but with the mac's generic rationale copied into
the comment rather than a recorded Edge test. Low-risk to leave as-is; still
worth doing the hand test and recording the result either way.

**2. Which progress markers must match, and which each platform writes itself.**
`app-rules.json` → `markerOrigins` classifies twenty-eight. Nineteen come
from `scripts/*.py`, which both platforms run, and must match to the
character. Seven come from the launchers, which exist separately as `.sh` and
`.ps1` — those you write, and they already differ; since the native runtime
landed they do not even pair up, so `knownDivergence.macOnlyLauncherMarkers`
lists the mac phrasings a milestone here must never watch for. Two are
"elsewhere" (`Quartz v4` and `Done processing`, both Quartz's own output) and
want a human to look.

**This example is now WRONG and is kept only as a warning: an earlier version
of this section said "the mac watches for 'Setting up this Mac' where
`setup.ps1` prints 'Setting up this PC'."** `setup.ps1` printed that once, but
stopped the day Windows moved to a fully native toolchain (`b356a1f`,
2026-08-19, "Native toolchain (no container)" in `setup.ps1`) — no WSL2, no
Docker, no one-time machine setup, no container to start at all. Nobody
updated `TaskMilestones.cs`'s launcher markers to match, and nothing caught
it for four days: `Setting up this PC`, `Building your website builder`,
`Ensuring container is running`, and `Starting container if needed` all sat
in the milestone lists matching text that could never appear again, so the
first two-to-three stages of most progress bars silently could never be
reached — fixed 2026-08-23, see item 5 above and `GUI-IMPROVEMENTS.md` row
352. **The lesson: "read your own `.ps1` files" is not a one-time
measurement, it is a claim that rots the moment those files are rewritten.**
`TaskMilestoneLauncherMarkerTests` (`ParsingTests.cs`) now reads the actual
`.ps1` files rather than trusting a milestone list frozen in C#, specifically
so the next launcher rewrite fails a test instead of silently stalling a
teacher's progress bar again.

**Do NOT copy the mac's seven launcher markers into your milestone lists.**
Read your own `.ps1` files and match what they actually print. This fails
silently in the worst way: the app does not crash, the progress bar simply
stops advancing part-way and then jumps at the end, which reads as a slow
build rather than as a bug — and the only way to notice is to watch a whole
deploy with the old and new bars side by side.

### Do not re-derive Plantoir's tests — read `contracts/`

**This is the section that saves you a day per sync.** Six JSON files, written
by the macOS binary, meant to be read by `Plantoir.Tests`. It started as the
assistant's contract and is now the whole product's:

| File | What it holds |
|---|---|
| `contracts/assist-wording.json` | Every sentence the assistant says to a teacher, with `{course}` and `{section}` where values go. **Count the keys rather than trusting a number here** — it was written as "nineteen" and there are forty-one. |
| `contracts/assist-cases.json` | The phrasings matched in code, the near misses that must NOT match, the three tool lists with approvals and plan twins, **the full tool SCHEMAS as a client sends them**, the scenarios, and the arrow-key prompt history. A scenario is `given` / `when` / an expectation: `given.saying` makes it a CONVERSATION rather than one turn, `when` is `approve`, `decline`, `say` (the last turn is ANSWERED, and a card there fails the case) or a tool name, and the expectation is `expectEvents`, `expectReply`, `expectTranscript` or `expectTranscriptContains`. The file's own `scenarios.note` is the authority; counts here rot. |
| `contracts/app-rules.json` | Launcher arguments per configuration, the validation a teacher reads, failure output turned into a sentence, whether a deploy must build first, the progress markers and where each one's text comes from, the preview's ports. |
| `contracts/schedule-rules.json` | Every accepted date form, how an ambiguous `08/09/2026` column is settled or asked about, what a pasted Google Sheet address becomes, and which day a word like “tomorrow” or “Monday” names. |
| `contracts/class-planning.json` | Which titles carry numbers, what the next class is called, and the ORDER renames must run in. |
| `contracts/course-management.json` | The three kinds of zip and how they are told apart, the section number offered next and the refusals, grade labels from a course code. |
| `contracts/file-formats.json` | Every `course_config.json` key with type and default, and the frontmatter that decides who sees a page — `publish:`, the legacy `draft:` that means the opposite, and the per-section keys. |
| `contracts/shared-rules.json` | What a scheduled deploy refuses and in what ORDER, what the sidebar filter shows, what is stripped from the launchers' output, and what counts as a curriculum expectation. |

An xUnit `[Theory]` with a `MemberData` source that deserialises these is the
whole integration. Nothing in them is macOS-specific: the sentences are the
product's and the sequences are the toolchain's.

**Why this exists.** Every wording change on the mac used to reach you as prose
in `GUI-IMPROVEMENTS.md` and a paragraph here, which you then retyped as tests
by hand — a day of it, and the sentences drifted the moment one side edited
without telling the other. They had been living in four places at once, and
three were already wrong: the identical deploy failure said "the output is in
that section's console in Plantoir" from one code path and "…that section's
window in Plantoir" from another, so which sentence a teacher got depended only
on whether a window happened to be open.

**How it stays true.** `Plantoir --write-contracts contracts` writes all three
files from `AssistWording`, `AssistCardCommand`, the tool surface and
`TaskMilestones`, and the contract tests run the same generator in-process and
fail when what is committed disagrees. A changed sentence therefore fails on the mac in the same
run that changed it, and reaches you as a **diff in `contracts/`** in the same
commit as the Swift. Verified by breaking a sentence on purpose: the suite
failed naming the key and the command to regenerate.

**The diff is how it travels; it is not how you FIND OUT.** Nobody reads a
folder of JSON for changes, so what you actually meet is your own suite going
red, days later and part-way through something else. The mac therefore opens a
`windows` issue in the same session (`CLAUDE.md` rule 3), and that issue — not
the diff — is the handover. Read it that way round: a red contract test means
go and look for the issue, and issue #146 exists because four of them were met
mid-task and read as nobody having said anything at all, while #70 sat open
naming every phrasing.

**What to know before you use them.**

- **Never hand-edit the GENERATED keys.** Those are readouts of mac code; the
  next regeneration overwrites your edit and the diff looks like vandalism.
  **`assist-cases.json` and `app-rules.json` each declare their own under
  `generated.keys`, and that is the list to read** — those two are the MIXED
  files, and the key marks where the generated half ends.
  `assist-wording.json` has none because it is generated in FULL and says so in
  its `note`; the seven authored files have none because there is no generated
  half to mark. This passage named `cardPhrasings`, `tools` and `milestones`
  until 2026-09-10, which was two keys of `assist-cases.json` plus one of
  `app-rules.json`, and left out both `toolSchemas` — the key carrying every
  tool's arguments, and therefore the one that moved when `back_up_course`'s
  signature changed — and `credentialRequests`. Two other places said the same
  three; a list of generated keys typed into prose is exactly the copy this
  whole folder exists to stop.
- **Name every key a regeneration moved when you write the `windows` issue —
  including the ones your REVIEW FIXES moved.** Learned from the same failure,
  and the timing is the whole lesson. `back_up_course` was built at 18:54 on
  2026-09-08 requiring `[course]`, exactly matching the tool Windows had had
  since August. Twenty minutes later a review fix (`b0913344`) gave it a
  `section`, because it had been filing the copy as the TEACHER's and
  `pruneBackups` would have kept every one for ever. #70 was opened at 19:52
  and described the FEATURE — the tool, its plan twin, its briefing
  persistence — which is what anyone writing up an afternoon remembers. The
  argument was not mentioned. Windows had the identical defect and found it
  only because the contract went red and somebody chased it, so what travelled
  unannounced was a defect FIX, which is the worst kind. Run `git diff
  contracts/` before writing the issue rather than working from memory.
- **Write it to the template.** `CLAUDE.md` rule 4 says what a `mac` issue
  carries — title and source, what it fixed and WHY (including what
  was rejected), numbers with the hardware they came from, the file and test
  names to look at, and whether the mac must match it or merely know. Something
  it must DO is a GitHub issue labelled `mac`; something it need only KNOW goes
  in the `documentation/` page that owns its subject. **A proposed contract case
  is an issue**, so the red mac suite it causes reads as a request.
- **You CAN propose an authored case.** `scenarios`, `nearMisses`,
  `promptHistory` and the case lists in the other files survive a mac
  regeneration untouched, so a behaviour you invent can be written as a case
  here — and the MAC suite will then fail until the mac implements it. That is
  the mechanism working, and it has been verified by doing it on purpose. Name
  the case so it reads as a proposal and open a `mac` issue for it, or the
  failure looks like damage rather than a request.
- **`expectEvents` is an ORDER, not a set.** Every incorrect ordering passes a
  test that only checks all three events occurred — which is exactly how the
  mac shipped a preview that stopped after the writes it was meant to protect.
- **The event names are the contract's own**, deliberately not Swift's. Map
  `stopPreview.begins` / `stopPreview.ends` / `deploy` / `write` /
  `startPreview` / `runLauncherDirectly` onto whatever each app calls them.
  Two `given` flags decide the interesting cases: `sectionWindowOpen: false`
  is the headless path (`Plantoir.Mcp`, and a scheduled deploy), and
  `previewRunning: true` is the case Windows currently gets wrong.
- **Replies are NAMED, not quoted** — `wording.deployed`, not the sentence.
  Look them up in the wording file and substitute `{course}` and `{section}`
  yourself. A test that quotes its own copy of a sentence is how this problem
  started.

**What the contract CANNOT do, so you still write these tests yourself.**
The list is short but each item is a real gap, and a gap nobody names is a gap
both sides assume the other is covering:

| Not in the contract | Why not, and what to do instead |
|---|---|
| **Routing accuracy** | Whether the model picks the right tool for a sentence it actually sees is a measurement, not an assertion — it varies by model, quant and context size. Measured against a real `llama-server`; see [`research/`](../research/README.md). The contract can say "deploy now" never reaches the model; it cannot say what the model does with a sentence that does. |
| **Anything with platform mechanics** | How a preview is stopped (WSL2, ConPTY, port leases, container naming) is yours. The contract says a stop must FINISH before a deploy begins; it cannot say what finishing means on your side. |
| **That an await is really an await** | This is the subtle one. The ordering assertion only proves anything if your fake preview emits the stop as TWO events with a real suspension between them, as the mac's does (`stopPreview.begins` … `stopPreview.ends`). A fire-and-forget stop that happens to complete quickly will satisfy a single-event fake and ship the bug the ordering was written to catch. |
| **Transcript composition** | The scenarios assert that named lines appear IN ORDER, never that they are adjacent or last. After an approval the tool's own result is the final line on the mac, and your renderer may differ. Order is portable; arrangement is not. |
| **Anything visual** | Bubble geometry, toolbar disabled states, progress headers, window layout. The contract has no vocabulary for these and should not grow one — that is what `GUI-IMPROVEMENTS.md` is for, and what a screenshot settles in a minute. |
| **Launcher arguments** | That a Cloudflare course deploys to Cloudflare is enforced on the mac by one function (`DeployCommand.arguments`) and by a unit test, not by the contract. If your `Plantoir.Mcp` or scheduled task composes its own arguments, write that test on your side — the bug is silent, and the site simply appears on the wrong host. |
| **Plan mode's offer to stop asking** | Tier-dependent (the smaller assistant cannot turn plan mode off at all), so it is a mac measurement and a mac rule until Windows has measured its own tiers. |

If you find yourself wanting to add one of these to the contract, the answer is
usually a second file rather than a stretched first one — `contracts/windows-*.json`
for behaviour only one platform has.


### The tool descriptions are measured, so compare against the contract

`assist-cases.json` → `toolSchemas` now carries the tool definitions **exactly
as each client sends them** — name, description and parameter schema, for both
the 13-tool local surface and the 32-tool MCP one. (It said 23; corrected
2026-09-06 when the list was first run against this side. `plantoir-mcp.exe`
serves 37, and the twelve it has beyond the contract are named in
`AssistSurfaceContractTests`.) The mac's own test has
pinned that sum for longer than the prose said so; it is 22 + 10 MCP-only = 32 since all six of the tools sorted as the mac's landed on 2026-09-08. What the two
surfaces do and do not share is item 41 and "The two MCP surfaces are not the
same product" below.

The descriptions are the part to take seriously. They are measured artifacts,
not commentary: the "TEACHERS SAY:" phrasings came out of the routing suite,
and one added clarifying sentence in `publish_pages`' description took the
promise-card score from 110/110 to 90/110 and broke three probes that had been
perfect. A small model reads a sentence naming another tool as a
recommendation, not a boundary. **Steer with code, never with a description.**

Two things follow for a port. Compare its own schemas against these rather
than against a description of them — a drifted description is a routing change
nobody will attribute to a wording edit. And when you measure routing against
your own backend, take the surface from the contract:

```
python3 research/ai-assist/tools-from-contract.py local > /tmp/real-tools.json
python3 research/ai-assist/shipped-surface-suite.py 8099 10 /tmp/real-tools.json
```

The suites are plain Python over `http://127.0.0.1:<port>/v1/chat/completions`,
so they run anywhere a llama-server does. `routing-suite.py` is marked
HISTORICAL and hand-writes five tools; do not measure the shipping surface with
it.

### The two MCP surfaces are not the same product

Written 2026-09-06 after a mac audit asked whether the parity list was
COMPLETE rather than whether it was correct. The issue is #66; this is the
manual for it.

**The measurement.** `Plantoir.Mcp/PlantoirTools.cs` declares **37** distinct
`[McpServerTool(Name = "…")]` names. `AssistToolSurface.swift` served **25**
when this was measured (22 tools plus three MCP-only). The set difference was
exactly **12, all Windows', none the mac's**, and not one of the twelve appeared
anywhere under `mac-app/QuartzTeachers` or in `contracts/` — there was no
half-built mac version of any of them:

`add_classes`, `back_up_course`, `explain_publishing`, `list_courses`,
`list_recent_changes`, `make_room_for_classes`, `plan_add_classes`,
`plan_make_room_for_classes`, `plan_sync_page_dates`, `read_timetable`,
`roll_over_section`, `sync_page_dates`.

**Seven of those twelve are the mac's now**, and the surface is **32** (22 plus
ten MCP-only). All six tools this sorting judged the mac should have were built
on 2026-09-08 — `list_courses`, the `add_classes` pair, the
`make_room_for_classes` pair, `explain_publishing` and `back_up_course`
(`GUI-IMPROVEMENTS.md` rows 452–456, and item 46 below). So the set difference
is **5**, and the sentence above about none of them existing on the mac
describes the day it was measured rather than today. What is left is what the
sorting said to leave: `read_timetable` and `list_recent_changes`, which are
Windows-shaped by design; `sync_page_dates`, which needs a teacher's problem
first; and `plan_sync_page_dates` and `roll_over_section`, whose writes are
covered by decisions recorded elsewhere.

**Why neither suite noticed — and how it is now caught.** Not a subset check
— an earlier write-up said that and was wrong. `Assert.Equal` on `HashSet`s is
set equality in both directions, and it is a good test; it simply pins a
**different class**. It compares the contract against
`AssistAgent.ForTheLocalModel` and `.DeploysToStudents`, which is the in-app
assistant, while the 37 live in `PlantoirTools`. Its `mcpOnly` third compared
the contract against three names typed inline in the test file, and twelve
additions went through that gap without a single red test.

**Windows replaced that third on 2026-09-09** (issue #70). Retyping the
contract's list only ever went red when the CONTRACT moved, and the fix was
always to retype it — the comparison touched no Windows code at all. It now
asserts what MCP-only MEANS on this side: nothing the contract calls MCP-only
may be in `AssistAgent.ForTheLocalModel`, which is what protects the measured
routing accuracy of the thirteen, and every one of them must still be served by
`PlantoirTools`, because MCP-only says nothing about whether a teacher may ask
for it — six of the ten are reached by a fixed phrasing no model ever sees.

**Windows closed it, on the same day and from the other direction.**
`AssistSurfaceContractTests` (branch `issue/29-windows-contract-case-lists`,
merged after the audit's branch was cut) reads `PlantoirTools` by
**reflection** and pins the twelve extras BY NAME, failing both when an
unrecorded tool appears and when a listed one is adopted into the contract and
not deleted. It reads `toolSchemas` for both surfaces and checks arguments and
types, not just names. The audit said "nothing on either platform enumerates
`PlantoirTools`' names" and "no Windows test reads `toolSchemas` at all"; both
were true where it stood and false by the time it merged.

**What the mac was going to propose, and why it is WITHDRAWN.** An AUTHORED
`assist-cases.json` key — `mcpToolNames` — that Windows asserted its 37
against and the mac its 25 plus a "not served here, and why" list. It is not
needed: reflection on the Windows side gets the complete list from the
compiler, with no new contract key and no second home for it.

**REJECTED even before that: a MAC test that regexes the names straight out of
`PlantoirTools.cs`.** It is feasible — `AssistContractTests` already locates
the repository root from `#filePath` — and it was the first design. An
attribute reformatted across two lines makes the regex find FEWER names, and
fewer names all of which are accounted for reports **success**. A drift
detector whose failure mode is a false green is worse than none, because it
will be believed. It also couples a gate to source rather than to data. Both
problems vanish when the enumeration happens on the side that owns the code,
which is the general lesson: **enumerate a platform's surface on that
platform, and cross the gap with the RESULT.**

**The sorting is still not in any contract, and that is deliberate.** The "and
why" half of it is an unapproved product decision, and committing it would
make that decision into the acceptance list both suites run. Windows' test
carries the twelve names with no verdict attached, which is exactly the right
amount to pin before Russell has chosen. The sorting is in
[issue #108](https://github.com/russellgordon/plantoir/issues/108).

**What the sorting concluded, in one paragraph**, so this file is readable on
its own: six of the twelve are product the mac should have — `list_courses`
and `back_up_course` and `explain_publishing` as MCP-only tools that cost no
routing, `add_classes` and `make_room_for_classes` as WIDENINGS of something
that already ships rather than new features (`add_next_class` already calls
`PlaceholderClassPlanner.apply`, and a `duplicate` key on the same call
already reaches `ClassInsertionPlanner.plan(count: 1)` — so the ENGINES are
both wired up already). Note the limit, **which since 2026-09-18 is the
mac's alone**: `duplicate` is not on the mac's `add_next_class` published
schema at all, only on the hardcoded card phrasing `AssistCardCommand.swift:85`,
so no model and no MCP client can reach it there — the mac needs a schema
argument, not just a bigger count. Windows now declares it on both halves of
`add_next_class` (issue #149), because it had to: the card reaches the tool
through an MCP binder that DROPS an undeclared key, so the sentence was
making a blank page. The mac's card and tool runner share a process, so the
absence costs it nothing except that Claude Code cannot ask for a duplicate.
And `roll_over_section`
because of the defect in item 41's first open part. Two are
Windows-shaped and stay there: `read_timetable`, because the mac puts
spreadsheet reading behind its schedule sheet on purpose and has no file-path
argument anywhere on its surface; and `list_recent_changes`, because both mac
clients already show or hold that history. `sync_page_dates` needs a teacher's
problem first — the mac has no engine for it AND nothing on the mac reports
the date drift it fixes, because the mac has no equivalent of your `DateAudit`.
The three `plan_` twins travel with their writes and are not separate
decisions.

### What an outside assistant is refused while another program builds the course (#156)

Added 2026-09-25. `Plantoir --mcp-stdio` is a separate process from the app a
teacher has open, with memory of its own, so until #156 neither could see the
other's builds: Claude Code could rebuild or deploy a section while the window
was building the same course, and the two builds cleared each other's folder.
Now both read and write the work-lease files under `courses/.internal/activity/`
— the manual is `09-mac-app.md` → "Two programs, one course"; the rule is
`contracts/shared-rules.json` → `workLeases.declining`.

What the MCP client meets:

- **`deploy_section` and `rebuild_preview`** are REFUSED, with
  `wording.courseIsBusy`, when another live program holds `build`, `publish` or
  `preview` on the course. The check is made before anything is stopped, and
  again by the headless deploy and rebuild right after they take their own
  `build` lease (take, then check — only a lease taken earlier counts).
- **`publish_pages` and `undo_last_change`** still WRITE — Markdown never
  conflicts with a build — and leave the teacher's preview up; the note where
  the preview would have been refreshed is `courseIsBusy`. The consequence to
  know: with the teacher's preview open in the window, an outside assistant's
  change reaches the page but not the preview until the teacher presses Preview
  (a program's own lease never stands in its own way). Before #156
  the rebuild went ahead and ended that preview instead. Windows' plantoir-mcp
  refuses WRITES only on `build`, for the reason its
  `RefuseIfPlantoirIsBuilding` records — refusing writes during a preview made
  the assistant useless to a teacher watching one — and the mac agrees: only
  the BUILD after the write is declined.
- **Why `courseIsBusy` and not the new `courseIsBeingBuiltElsewhere`.** The
  client is talking TO the program whose course is busy, so "busy in Plantoir —
  a preview or a deploy is running. Wait for that to finish, then ask again" is
  true and tells it what it can do. It reads a little loosely when the holder is
  a SECOND outside session or a publish set for later (neither is "a preview or
  a deploy" in the window), and that was accepted rather than adding a key
  (plan review L1). The teacher, in the app, gets
  `courseIsBeingBuiltElsewhere`, which says where the other work might be.
- **Why a PREVIEW blocks it, when Windows' `plantoir-mcp` blocks only on
  `build`.** Every `--build-only` ends that section's serving preview first
  (`build_site.stop_preview_serving`), so an outside rebuild would take down the
  page the teacher is reading — which the in-app assistant already refused to
  do. The client can retry; the teacher reading the page cannot. Stricter than
  Windows on purpose, and a red contract case there is the request.
- **When the client goes away mid-build**, the server stops the launchers it
  started, and the sections inside the website builder, BEFORE its leases come
  down. A client that kills the server skips that; see the known limit in 09.

None of this touches the tool surface: no description, schema or prompt byte
moved (local 13 `46b96562…2cd96cb6`, MCP 32 `9bcc7eb7…9cef36f7`, hashed before
and after). The rule lives in code, as "steer the model with code, not with
tool descriptions" says it must.

### The model's list is SHORTER than the server's

Two lists, deliberately. `definitions` is what the local model sees;
`mcpDefinitions` is what Claude Code sees over MCP. Same tools, same runner,
same rules — the model is simply shown fewer.

- **The `plan_` twins are hidden from the model.** Plan mode calls them from
  CODE when the model picks a write, so the model never needs to name one.
  They were about 30% of the prompt buying nothing. Claude Code KEEPS them:
  it has no plan mode and genuinely needs to ask "what would that do?".
- **`remember_timetable` is hidden from the model.** It takes dates as
  strings, so dates the model supplies are dates it may have invented — and
  a wrong one schedules a class on the wrong day silently. The schedule UI
  owns that path. `read_remembered_timetable` stays, because reading is safe.
- **`re_date_classes` is hidden from the model**, and this bullet was missing
  while the count beside it already said nine. The phrasings that reach it are
  matched in CODE (`AssistCardCommand.swift`), and re-dating a whole section
  rewrites the date on every page in it — far too large a change to reach
  through a router that is right four times in five. Like the others it still
  RUNS, and Claude Code still sees it.

Result: 22 tools down to **13** for the model — the seven `plan_` twins,
`remember_timetable` and `re_date_classes` are the nine taken off the list.
(An earlier draft of this note said 12; the cuts named above come to 13, and
the code and its tests say 13. It then said 20 down to 13 with six twins and
seven taken off, which was true when it was written and had gone stale by
2026-09-06 — the local list has stayed 13 throughout, but the surface it is
drawn from grew.) The thirteen are `list_pages`, `read_page`, `check_section`,
`publish_class_on`, `publish_pages`, `unpublish_pages`, `rebuild_preview`,
`undo_last_change`, `deploy_section`, `schedule_deploy`,
`cancel_scheduled_deploy`, `read_remembered_timetable`, `add_next_class`.
Worth doing on Windows too — the routing figures were measured at 15, so a
surface that grows past that is spending accuracy, and one that shrinks below
it should be spending less.

## What the conversation looks like, and why

The assistant window is a CHAT, not a form with a log under it. That was a
deliberate change and it is worth stating why before the numbers: a teacher
asking for something, being told what would happen, and agreeing to it is a
conversation, and a window that looks like one is a window they already know
how to use. Nothing here has to be taught.

**One decision is local to each platform.** These specs describe macOS Messages,
because that is the chat every Mac teacher already has open. The Windows
equivalent may be better served by looking like Windows — Teams and Phone Link
have their own bubble idiom, and a Mac-shaped chat on Windows can read as
foreign rather than familiar. What must carry across is the STRUCTURE (who is
on which side, what counts as a message, when a turn ends); the exact
curvature is a local decision. Choosing to mimic the host platform's
chat, measure it the way we measured ours — see the last paragraph.

### The two sides

| | Teacher | Assistant |
|---|---|---|
| Side | right | left |
| Fill | blue, RGB **(20, 147, 255)** | dark: **(59, 59, 61)**; light: **#E9E9EB** — flat, never translucent |
| Text | white | the ordinary label colour |

**Do not use the system accent colour for the teacher's side.** We did, and it
is a latent bug rather than a shade being slightly off: the accent is whatever
the user chose in system settings, and set to graphite it makes the teacher's
bubbles the same grey as the assistant's — at which point the left/right,
blue/grey distinction the whole window depends on silently disappears. The
blue is its own constant.

**The assistant's grey is a constant too, not a translucent token.** Ours was
"a system grey at 16% opacity" for a while, and a translucent fill can only
ever be as light as the window behind it allows — measured side by side on
the same backdrop it sat visibly darker than Messages'. Flat colours, both
appearances.

### The bubble

Ten rounds of measuring against the real thing, each round correcting the one
before (`GUI-IMPROVEMENTS.md` rows 177–178 have the blow-by-blow). The final
geometry, in points at 13pt text:

| | |
|---|---|
| Corner radius | **17** — an absolute of the design; it does NOT scale with the font |
| Radius rule | `min(17, height/2, width/2)` — single-line bubbles fall out as capsules, no separate branch |
| Visible text inset, each side | 13 |
| Text inset, top and bottom | 7 |
| Tail size | an absolute, like a pen width — one size on every bubble (`tailScale` = 17) |
| Tail drop BELOW the body | 5.1 (0.30 × tailScale) |
| Corner landing on the bottom line | 0.47 × radius — the one tail number that follows the radius |
| Tail tip, INSIDE the body's edge | 6.5 (0.38 × tailScale) |
| Hook rejoins the bottom edge | 14.5 in (0.85 × tailScale); root width ≈ 6.5 |

The two costliest wrong assumptions, both of which survived several rounds:

- **Nothing scales with the font.** The radius measured the same across two
  text sizes; so did the whole tail. An early pass scaled both down by our
  smaller font and every bubble read as subtly wrong beside Messages. (The
  OLD version of this section said the opposite — "scale the proportions to
  the corner radius". That advice cost us three passes. Constants.)
- **Cross-app constants come only from screenshots with BOTH apps in them.**
  Deriving one from two separate captures needs each capture's
  pixels-per-point; we guessed one wrongly and shipped a tail a fifth too
  large. Same screenshot, same screen — the scale cancels out.

Drawing the outline (still one continuous path, not a rectangle plus a
triangle):

- **The corner-to-tail joint is about the TANGENT.** The silhouette reaches
  its deepest inset exactly at the bottom line while travelling straight
  DOWN. A corner that lands travelling horizontally meets the tail in a cusp
  and the tail reads as a comma stuck under the bubble.
- **The jog into the tail gets exactly the radius of height**, held nearly
  flat for the first half with the dive concentrated in the last (a cubic
  with vertical end-tangents; late control ~0.215 of the span, early ~0.30).
  A longer span drifts early and reads as a diagonal cut into the side; a
  weighting that carries inset early reads as the bubble bulging.
- **No sharp vertices anywhere.** The tip is rounded about 1.5pt across, and
  the hook meets the bottom edge in a small curve, not a corner.
- **The underside of the tail is CONCAVE** — a diagonal with a mild sag
  toward the bubble, not a deep scoop. That curve, not the tip, is what makes
  the shape read as a tail.
- **Draw inside the bounds you are given.** Ours drew past its rect at first
  and was clipped — a clipped tail is severed, not pointed.

### Selecting text in a bubble

Messages pins its selection colours the way it pins its bubble colours:
light-appearance selection blue **(174, 218, 255)** behind the selected run
in BOTH appearances, with the selected glyphs painted in the bubble's own
fill. The system's dark-mode selection colour is a grey-slate that reads as
broken beside it. Two porting notes: our UI toolkit's built-in text selection
drew an unstylable grey and we had to drop to the native text control to
style it at all — check the platform's early; and the hook that styles selection must
be one that runs when selection machinery actually attaches (ours had a
first attempt that configured a text editor that did not exist yet, and it
failed silently).

### Tails mark turns, not messages

One tail per RUN: on the last thing a participant said before the other one
answered. A tail on every bubble makes three sentences look like three
separate attempts to get a word in — and it is the kind of thing that looks
fine in a screenshot of two messages and wrong in a real conversation.

The newest message always has a tail, since its turn has not been answered
yet. Anything nobody SAID — we have one such item, a note that a restore
happened — wears no tail and does not end anyone's turn; the rule looks past
it to the next thing that was actually said.

### What counts as a message

More things than you would first assume, and this is the part that matters
most for how the window reads:

- **What the assistant says.** Obviously.
- **What the teacher types.** Obviously.
- **Tool results.** "The preview is rebuilding now" is the assistant
  ANSWERING. That it came from a tool is machinery, and the teacher is not the
  audience for machinery. As plain lines with an icon these read as a log
  spliced through a conversation.
- **The plan.** It used to live only in the approval card, so pressing Go or
  Cancel destroyed the description of what had just been agreed to — and with
  it the context for everything after. A conversation you cannot scroll back
  through is not a conversation.
- **The question.** `planQuestion` / `deployQuestion` / `scheduleQuestion`
  (the last under a scheduled deploy's card, #184) is its own message, which
  is what lets the card below be nothing but buttons.
- **The teacher's ANSWER.** Pressing Go records "Go" as a teacher message, in
  their bubble on their side. Reading back a conversation where the assistant
  asked, nothing answered, and yet something plainly happened is worse than
  not being able to read it back at all.

The general rule: **anything that is part of the conversation belongs IN the
conversation, and a control that owns text destroys that text when it
resolves.** Leave controls the choice and nothing else.

### The typing indicator

**A THOUGHT bubble, not a speech bubble** — a capsule with two plain circles
stepping down toward the speaker, the comic-strip sign for thinking, shown on
the assistant's side whenever the model is thinking or a tool is running —
both are waits with nothing on screen, and a teacher does not care which.
Ours wore the speech tail for a while and it read as off without anyone
being able to say why: a tailed bubble means SAID, circles mean composing.

Measured from a screen recording of Messages, as ratios of the capsule's
height (which equals a single-line message bubble, so the indicator occupies
the slot of exactly the thing it stands for): capsule ~1.7× as wide as tall;
dots 0.24 of the height with a gap about half a dot; the larger circle 0.41,
poking about two points past the lower corner; the smaller 0.14, below and
outside with a sliver of gap. Each dot lags the one before it (about 0.18s)
so the three read as a wave rather than a blink.

**Draw the capsule and both circles as ONE geometry filled once** (whatever
the platform's path-union is). As separate shapes, any translucency doubles
where they overlap and the join shows as a brighter seam.

### The box you type in

- A rounded field — continuous rounded rectangle, radius 17 — with the send
  button INSIDE its right end, rather than a plain field with a button parked
  beside it.
- **Never disable it to mean "busy".** A disabled field cannot hold keyboard
  focus, so the system moves focus to the next thing it can find; ours landed
  on the first disclosure group in the suggestion shelf, which looks like a
  bug in something else entirely. Typing and SENDING are separate
  permissions: the box stays live so a teacher can write their next message
  while they wait — every messaging app allows this — and only the send waits
  for the run to finish.
- **Focus returns to it after every send.** Two commands in a row should not
  need a click in between. This is also what keeps the arrow-key history
  usable, since that depends on the field having focus.
- Up and Down walk the teacher's own previous messages; see the history rules
  recorded in `GUI-IMPROVEMENTS.md` row 157.

### Two small things that are easy to skip

- **Emphasis has to be rendered.** Plans mark their headings bold, and in
  SwiftUI `Text(someStringVariable)` does not parse markdown at all — only
  string literals do — so it reached the teacher as literal asterisks until
  the text was parsed explicitly. Whatever your toolkit is, check how it
  treats a runtime string; several style literals only.
- **The suggestion chips take the pointing-hand cursor.** A plain button style
  keeps the look and suppresses the cursor, so it has to be put back by hand.

### How to get this right in less time than we did

Measure — and close the loop. Guessing produced wrong shapes; one screenshot
and a twenty-line script that read the pixels produced right ones in minutes.
The full method, each part of which was learned by paying for its absence:

1. **Trace silhouettes, don't eyeball.** Per-row min/max of the fill colour
   gives the exact edge profile; every number in the tables above came out
   that way.
2. **Only same-screenshot comparisons.** Both apps in one capture, or the
   pixels-per-point uncertainty eats the answer.
3. **Render YOUR result and measure it the same way.** The passes that
   shipped wrong all trusted arithmetic about what the code would draw;
   the passes that stuck rendered the real control offscreen and walked its
   pixels against the reference trace. Insets especially: native text
   controls put slack around their glyphs that no spec predicts — our final
   paddings are asymmetric (12 leading, 9 trailing) purely to cancel what
   the label actually draws, and only the render-measure loop could have
   found that.
4. **Expect the reference to correct you more than once.** Ten passes, each
   started by a human eye catching what the previous measurement missed, and
   each ending with the pixels agreeing the eye was right.

## Plan mode, undo, and how often to back up

Three decisions taken on the macOS side on 2026-08-15 that Windows should
match, because they are about how much to trust a local router rather than
about either platform.

### Plan mode: the model says what it heard before it acts

A local router is wrong sometimes. Measured over 290 trials, the small model
puts about **one request in five** on the wrong tool. Plan mode turns that
from something that happens into something a teacher declines: a write runs
its `plan_` twin first, the plan is shown in the twin's own words, and
nothing happens until they press Go.

- **Writes only.** Reads answer immediately. Gating "what do students see
  right now?" makes every question two clicks and teaches people to press Go
  without reading — which costs the gate its whole value.
- **Always on for the small model.** On the 1.5B it cannot be turned off at
  all; 79% is not a rate at which anyone should be handed a "stop asking"
  button. The macOS build ignores a remembered "off" answer when it finds
  itself on that tier, so a teacher who turned it off on a capable machine
  does not inherit that on an 8 GB one.
- **Offered off after five in a row, once, on the capable model only.** Trust
  is earned rather than assumed, and the offer arrives while five correct
  plans are still fresh rather than months later in a settings pane. A Cancel
  RESETS the run: somebody who has just stopped the assistant doing the wrong
  thing must not then be asked whether they would like it to stop asking.
- **Deploys always ask, plan mode or not.** A deploy puts work in front of
  students immediately and cannot be taken back by us.

### Undo is not version control, and it should not pretend to be

Worth stating because it is easy to assume otherwise: **courses are not git
repositories.** Nothing in the toolchain runs `git init`. The undo history is
in-memory before/after snapshots of the files each tool touched, held as a
stack for the life of the conversation, and it is gone when the window
closes.

It has one property worth copying exactly: before restoring a file it
compares what is on disk to what it wrote, and **skips anything the teacher
has edited since**. Publishing a class, then spending ten minutes writing it
in Obsidian, then saying "undo that" must not cost those ten minutes.

### Which tools record an undo entry, and which deliberately do not

**A tool records an entry only when taking it back is WHOLE.** Written down
2026-09-18, after Windows found that three tools —
`add_curriculum_mentions`, `make_room_for_classes` and
`add_classes`/`add_next_class` — opened an entry and never closed it
(`UndoHistory.Begin` … no `End`), and that the other five closed theirs only
on the path where nothing threw. The consequence was two-sided and entirely
silent, which is why it lived so long: the tool recorded NO entry at all, so
"undo that" answered that nothing had been changed — while `add_next_class`'s
own reply promised the page could be taken back — and the still-open entry
then swallowed the NEXT operation's files and committed them under the
earlier description. A teacher who made room, published a class and said
"undo that" was told they had made room, and had the publish taken back with
it.

**The pairing is no longer something to remember.** Every recording site is
now `using var recording = UndoHistory.Record(_undo, "…");` with
`recording.Done()` where the operation finishes. Leaving the scope any other
way — a throw, or a `return` added years later by somebody who never read
this — abandons. An inner scope is a no-op, so the outermost call still owns
the entry and a tool that calls another tool records one operation rather
than two. The five older sites each wrapped their individual file writes in
`try`/`catch` and nothing else, so a `ReadAllText` outside those — a page
Obsidian deleted between the plan and the Go — escaped the method with the
entry still open, and it was still open when the teacher asked for the next
thing.

**Where that exception then goes differs by tool, and the difference matters
more than it looks.** Re-dating, syncing dates, curriculum, making room and
duplicating are called through `PlantoirTools.Guarded`, which catches
`IOException` and `UnauthorizedAccessException` and turns them into an ANSWER
the teacher reads. **Publishing and unpublishing are not**:
`PlantoirTools.Act` catches only `AssistRefusal` and
`OperationCanceledException`, so anything else leaves the tool altogether —
no answer is built, `CarryingTheConversationBackup` never stamps the result,
and the teacher gets a protocol-level failure naming no backup at all. The
undo entry is abandoned either way, which is this section's subject; the
reply is worse on the publish path than on any other, and that gap is
[issue #165](https://github.com/russellgordon/plantoir/issues/165) rather
than something fixed in passing.

**Abandon on a throw, rather than committing what was written — and this was
a decision, not a default.** The case to think about is a publish of five
pages that writes three and then throws. Committing the entry (an `End` in a
`finally`) would make those three undoable, which sounds strictly kinder. It
was rejected because **the description is written at `Begin`, from the
PLAN**: the entry would say "published “A”, “B”, “C”, “D” and “E”", and
`AssistWording.Undid` reads that clause straight back to the teacher — "Earlier,
you published A, B, C, D and E" — at the one moment they are checking that
the right thing was put back. A truthful file list under a false sentence is
the failure rule 5 of `CLAUDE.md` names: a line describing what did not
happen is worse than no line, because it will be believed. The mac reaches
the same place from the other end — `AssistToolRunner` records a whole
`AssistChange` only after the operation returns, so a throw records nothing
(its whole-unit publish answers "was only partly published: …" and calls
`history.record` never) — so abandoning is also what matches.

**The cost is real, and on one path it is not yet covered.** The conversation
backup is taken before the first write and is the way back for everything
here. On the tools that go through `Guarded` the teacher reads a sentence and
can be pointed at it. On the PUBLISH path they currently cannot: the
exception leaves the tool, so no reply is built and no backup is named, and
they are left with a failure and a half-published section. The mac says
something there — that inline "was only partly published: …" — and Windows
says nothing; matching it is not a wording decision this side may take alone,
since the sentence is an inline mac literal rather than an `AssistWording`
key, so it is written down as [issue
#165](https://github.com/russellgordon/plantoir/issues/165) instead of
improvised.

The rule both apps now follow, tool by tool:

| Tool | Records undo? | Why |
|---|---|---|
| publish / unpublish, re-date, sync dates, rollover | yes | Files edited in place, nothing renamed. |
| `add_classes` / `add_next_class` | yes | Created pages are recorded with no "before", so undo deletes them. |
| `add_curriculum_mentions` | yes | One page, one block, edited in place. |
| `make_room_for_classes` | **no** | Renames later days, re-dates every class after the insertion point, rewrites the links that pointed at the old names. |
| duplicate as next class | **only when nothing else moved** | The common case moves nothing; the rest is a make-room. |

**What was rejected, and why it matters more than what was chosen.** The
obvious fix for make-room was to record the whole thing and let undo put it
all back. It was rejected because undo is not a transaction: it restores
files whose contents still match what was written and SKIPS the rest, so a
teacher who touched one page in Obsidian gets a half-undone shuffle — some
classes renamed, some not, links pointing at both. A partial undo of a
rename is worse than no undo, because nothing tells the teacher which half
happened. So the way back for anything that shuffled is the backup taken
before it, and the reply says so — `AssistWording.otherClassesMoved` on the
mac since 2026-09-19, `ClassChangeWording.OtherClassesMoved` on Windows,
which has a second form naming the backup's FILE and asserts its
no-file-name form against the contract key. The mac reached the same answer
first and Windows mirrored it rather than improving on it.

**The condition is renames OR date moves, and the duplicate path was the one
caller that never got wired to it.** `ClassInsertionPlan` carries two lists —
`renames`, only ever WITHIN the unit being changed, and `moves`, every class
of every LATER unit, re-dated and never renumbered — and
`ClassInsertionPlan.movesAnythingElse` has answered about both since
make-room was written. Keyed on `renames.isEmpty` alone, duplicating the LAST
day of a unit renamed nothing, re-dated every class of every later unit, and
offered an undo that took back the copy and left the rest of the year moved
with nothing said about it. Windows found it while building its own
duplicate ([#149](https://github.com/russellgordon/plantoir/issues/149)) and
proposed the case; the mac widened its gate in
[#163](https://github.com/russellgordon/plantoir/issues/163).

Both halves are contract data: `contracts/class-planning.json` →
`duplication`, with `undoRule`, `forcedUnpublished` and three cases, run by
`ClassPlanningContractTests.Duplication_MatchesContract` on Windows and
`ClassPlanningContractTests.testDuplicatingMatchesTheContract` on the mac.
**Case 2 was RED on the mac the first time its runner ran**, which is the
handover working rather than damage, and it is written down here because a
case nobody remembers catching anything is a case somebody eventually
simplifies away.

**The plan card counts the UNION of the two lists, not either one.**
`ClassInsertionPlan.otherClassesMoving` (Windows:
`DuplicateClassPlan.OtherClassesMoving`) dedupes case-insensitively on the
page TITLE, which works because `moves` carries each page under the name it
will HAVE. Adding the two counts instead would say 5 where three pages move;
counting renames alone printed no line at all in exactly the shape that
re-dates a teacher's whole year, and that is the card they agree to. The
number is `expectOtherClassesMoving` in each contract case.

#### Three things the duplicate did that nothing was watching

All three were found from the Windows side and closed on the mac in #163.

**1. A copy could arrive already visible to students.** The copy is given a
plain `publish: false`, but the build consults `publishForSection<N>` FIRST,
so a source page carrying that key beats it and the copy is readable the
moment it exists.

**Why the guard is written for a value the reader will not vouch for, rather
than for one key.** After
[#176](https://github.com/russellgordon/plantoir/issues/176) the important
`cannotTell` shapes PUBLISH — a key whose value continues on an indented line
reaches the site as the string `'false false'` — so "there is a flag and this
app will not guess what the build makes of it" is not a shrug, it is a page
students may well be able to read. A copy this app cannot vouch for is exactly
the copy to act on. That argument stands whatever the frontmatter turns out to
say, and it is the reason to prefer it to a test for one key name.

**And the per-section key really is reachable**, by a route the app itself
builds. `AssistPageVisibility.isSectionLocal` decides from the PATH, so the
app writes `publishForSection<N>` onto COURSE-LEVEL pages — that is what the
key is for — and `AssistSectionGraph.read` walks
`ClassPages.pagesOfSection`, which enumerates the whole course directory minus
other sections' folders. So a course-level page titled "Unit N, Day N" that
has been published for this section is nameable in "duplicate X as my next
class" and carries the key, with no teacher doing anything unusual. (An
earlier draft of this section cited 324 shipped example pages as carrying it.
That was wrong and is worth recording as wrong: the 324 is a count of files
whose `%%` comment mentions the key by name — `_DUPLICATE ME.md` says "such as
createdSection1 dates or publishForSection1 flags" — and NO shipped
`example_content` page carries it as a frontmatter key at all. A measurement
that is wrong is worse than none.)

Measured in the real toolchain image (`teaching-quartz:src-0b2b2e9c`, CPython 3.11.15,
PyYAML 6.0.3, python-frontmatter 1.3.0), calling the build's own
`process_frontmatter` and then applying `patches/publish.ts`'s rule:

| the copy's frontmatter, for section 1 | after the build | the site |
|---|---|---|
| `publish: false` + `publishForSection1: true` | `publish: True` | **VISIBLE TO STUDENTS** |
| `publishForSection1: true`, `publish: false` inserted at the top of the block (what `AssistPageVisibility.setting` writes) | `publish: True` | **VISIBLE TO STUDENTS** |
| `publish: false` + `publishForSection1: false` (the rejected fix — hidden, and unpublishable) | `publish: False` | HIDDEN |
| `publish: false`, the per-section key REMOVED — which is the control, and is what ships | `publish: False` | HIDDEN |
| `publish: false` + `draftSection1: false` | `publish: False` | HIDDEN |
| `publish: false` + `publishForSection2: true` (another section's key) | `publish: False` | HIDDEN |

The FILE says `publish: false` and the site shows the page, which is the
worst available shape: the teacher's own page looks hidden. Only THIS
section's per-section publish key can beat the plain one — a key naming
another section is deleted unread.

**What was REJECTED, and it is the answer this piece shipped first.** Writing
`publishForSection<N>: false` onto the copy as well hides it, passes every
assertion about visibility, and leaves a page **nobody can ever publish**: the
copy is section-local for ever, so `AssistPublishPlan` picks the plain key
from the path and writes `publish: true`, never touching the per-section line,
which goes on winning — while `publishPages` reports "Published 1 page"
without re-reading. Asking again produces the same answer, because the page
still reads as hidden and is listed as a change every time. That is the
failure-that-reports-success this project treats as the worst kind, traded for
a page that merely starts visible. Caught in review before it merged.

What ships instead REMOVES what the copy inherited.
`AssistPageVisibility.withoutPerSectionKeys` strips every top-level
`publishForSection\d+`, `draftSection\d+` **and `createdSection\d+`** line,
with its continuation lines, before anything is written on the plain keys.
`createdSection<N>` goes with the other two rather than being left as inert:
`process_frontmatter` does `post["created"] = post[created_key]` on the line
after the publish one, so an inherited date key would show the SOURCE's day on
the built site while the copy's own file said otherwise — the same precedence
trap, one key over. The build deletes all three families after resolving them,
so removing them changes nothing about a page that was already right.

Then the copy is read back once more, and if the answer is anything other than
a confident `hidden` the duplicate is **abandoned rather than written**.

**That branch is REACHED today, and not by the keys the strip removes.** An
early draft of this section called it unreachable — it is not, and the two
shapes that reach it were measured rather than argued:

| the source's frontmatter | why the copy still answers `cannotTell` |
|---|---|
| a TAB used as indentation anywhere in the block | `PageVisibilityReader.frontmatterBlock` answers `.unreadable`, because the build's own parser throws on the same page. Nothing written here can mend it: the strip and `setting` both find the fences and neither cares about tabs. |
| the block's FIRST line indented, with a top-level `created:` and no publish or draft key | Until #186, `setting` inserted `publish: false` at the top of the block, where the first line that could be its value is the indented one, and `reading(ofValue:followedBy:)` will not guess at that. Since #186 it declines (`.noRoomForAKey`) and the page is not hidden either way. |

Both are pages the BUILD refuses as well — measured in the image, source and
copy alike raise `while scanning for the next token` / `mapping values are not
allowed` — so stopping is the honest answer rather than a shrug, and a copy of
a lesson students can already see is the one thing not to write on a guess.
The branch ALSO covers
[#186](https://github.com/russellgordon/plantoir/issues/186), which since
2026-09-25 makes `AssistPageVisibility.setting` DECLINE to write on the second
row above (`.noRoomForAKey`) rather than insert a key that adopts the indented
line; the read-back still sees a page that is not hidden and abandons the
copy, and it stays the stronger check, because it also catches what the
outcome cannot see (the tab row).

Abandoning is safe by construction: `ClassInsertionPlanner.apply` has already
written the blank class page at that path and `ClassPages.skeleton` writes
`publish: false`, so the teacher keeps a hidden empty page rather than a
visible copy of a published lesson. Because it is reachable, the sentence is a
contract key — `AssistWording.theCopyCouldNotBeMadeHidden`, in the same two
forms as `thePlaceForTheCopyIsStillTaken` — and it says the same two things
that one says, plus one of its own: other classes may already have moved, the
backup is the way back, and **a blank class page is standing on the day the
copy was meant to have**. "Was not copied" on its own reads as "nothing
happened", which would be wrong twice over. It leaves a trail line.

**2. A lesson still sitting where the copy would go was written over.**
`ClassInsertionPlanner.apply` SKIPS a rename whose destination already exists
or whose source it cannot read, which is right in itself and leaves the page
the copy was meant to BECOME holding somebody's real class; the copy was then
written there unconditionally. Deterministic construction, which is also the
mac's test:

- unit 1, days 1–6, duplicate `Unit 1, Day 2` (so the destination is
  `Unit 1, Day 3`)
- `Unit 1, Day 3` is a real lesson whose body links to `[[Unit 1, Day 6]]`
- `Unit 1, Day 5` is invalid UTF-8

In rename order, highest day first: `Day 6 → Day 7` succeeds; `Day 5 → Day 6`
is skipped because the source cannot be read; `Day 4 → Day 5` is skipped
because its destination is still there; `Day 3 → Day 4` likewise. The lesson
is still at `Unit 1, Day 3` when the copy is written to it.

Three guards were REJECTED before the one that shipped:

- **Comparing the destination's TEXT** before and after — "is this still the
  page that was in the way?" This is what Windows does
  (`AssistWorkspace.cs`, the `File.ReadAllText(newPath) == occupying` test)
  and the construction above defeats it: a rename DID happen, so the planner
  rewrites wikilinks in every page of the section including this one,
  `[[Unit 1, Day 6]]` becomes `[[Unit 1, Day 7]]`, the texts differ, and the
  lesson is taken with the guard in place and a comment saying it is handled.
- **A pre-check before `apply`.** It cannot work, and the reason is sharper
  than "it would refuse every ordinary duplicate": when the destination exists
  at plan time it is ALWAYS in `plan.renames`, because it is a numbered page
  at or after the insertion point. Nothing before the shuffle can tell the
  dangerous case from the ordinary one.
- **Sampling "was a page there?" before `apply` and ANDing it with the
  question below.** This one shipped first and was taken out in review, which
  is why it is worth recording: `apply` renames, rewrites links and re-dates
  between the sample and the write, and the premise of the whole feature is
  that Obsidian is open in the other window. A page appearing at the
  destination during that pass reads as "the planner must have made it", so
  the copy takes it — and `before = nil` then means "Undo that" DELETES it.
  The sample cannot make the guard safer and can only make it blind.

What shipped asks the PLANNER what it did, and nothing else.
`ClassChangeOutcome.created` has carried the URLs a change wrote since it was
written, `PlaceholderClassPlanner` fills it, and `ClassInsertionPlanner` was
dropping it on the floor; now it fills it too, and the duplicate refuses
whenever the destination is **not among them** — one condition, asked after
`apply`. That is exact here: `apply` cannot take its `changesNothing` early
return on this path, because `duplicateAsked` has already failed if the plan
added nothing, so `created` holds this page if and only if no file was there
when the blanks were written. Content-free, so link rewriting and date moves
cannot defeat it.

The refusal is `AssistWording.thePlaceForTheCopyIsStillTaken`, and it is the
only sentence in that table answered after a change has BEGUN: the room has
been made by the time it fires, so it says other classes may already have
moved rather than only "nothing was copied", which would be true and would
leave a teacher believing nothing happened. It leaves a line on the trail —
`ActivityTrail.Event.classCopyNotMade`, `contracts/shared-rules.json` →
`activityTrail.mustRecord` → `class copy not made` — because "I duplicated a
class, my classes moved and no copy appeared" is otherwise unanswerable: the
trail records the tool that ran and not what it concluded. The other refusals
on that path record nothing, deliberately, because they answer before
anything is touched.

**3. The undo of a duplicate put a BLANK class page back.** `before` was read
after `apply`, so it was the skeleton the planner had just written, and
"Undo that" restored a blank page while answering `AssistWording.undid`. Past
the guard above it is provably `nil` — either the destination did not exist,
or it existed, was vacated by a rename and the blank standing there is the
planner's — and the recording branch only runs when nothing was renamed or
re-dated at all, where a page there could not have existed. So the undo takes
the copy away, which is what `AssistWording.aCreatedPageCanBeTakenBack` has
said all along.

**The eight duplicate sentences are now `AssistWording` keys.** They were
inline on the mac and gathered in Windows' `ClassChangeWording` — which could
not make contract keys, the generator being the mac's — so both apps said
nearly the same eight sentences with nothing holding them together. Two
render as two contract keys each, because one rendering cannot show both
branches of a sentence that has two. The date is a LITERAL in the generated
file rather than a placeholder: Windows formats a real date before its own
sentence sees it, so `{date}` is a shape that side cannot produce, and
`backedUpCourse` set the precedent with a real file name.

### Back up once per conversation, not once per command

The macOS build originally zipped the whole course before EVERY write. On an
Obsidian vault full of images that is slow and large, and a chat with six
commands made six near-identical copies.

It now backs up **lazily, once per conversation**: the first write makes the
zip, later writes reuse it, and a conversation that only reads makes none.
That single zip is also what the assistant's **Restore** offers — putting the
section back to how it was when the chat started, which is the safety net
that makes "just do it" mode reasonable to offer at all.

Two details that make the backups usable rather than merely present:

- **Provenance rides in the file name**, so a teacher choosing among several
  can tell what made each one and why — Plantoir before an assistant chat
  about a particular section, or themselves on purpose. A list of five
  identical-looking timestamps is not a choice anybody can make.
- **Prune only the ASSISTANT's own backups**, keeping its five most recent
  per course — and, since 2026-09-10, only those whose stamp could be true.
  The date lives in the file NAME, this list is sorted by it and its tail is
  thrown away, so a name stamped in another machine's calendar (2569, on a
  zip carried from a pre-fix Thai Mac) would sort as the newest thing in the
  folder and take a real backup's place. Left out of the count, it is never
  deleted either: [09-mac-app.md](09-mac-app.md) → "What an archive or a
  backup is CALLED" says what that costs, since a Mac with a badly wrong
  clock stops being pruned too. A teacher's backup is a decision — they pressed Back Up because
  they were about to do something they were unsure of — and deleting it on a
  schedule they never agreed to is the app overruling them about their own
  work. The assistant's are different in kind: it saves one per conversation
  whether or not anybody asked, so clearing up after itself is its job. A
  teacher with twenty of their own keeps all twenty, and they never crowd out
  the assistant's five, because the two are counted separately.
- And prune ONLY backups at that: archives and the wizard's own zips live in
  the same folder and their parsers deliberately reject each other's forms.

### Restore is section-scoped, though the zip holds the course

The backup contains the whole course; a conversation is about one section. A
whole-course restore would silently revert work done in a sibling section
while the chat was open — a teacher may well have been editing Section 2 in
Obsidian while talking about Section 1. So Restore puts back only the section
the conversation was about, and says so on the button.

**Section-scoped means more than the section's folder**, and this is the part
easy to get wrong. The assistant can publish or unpublish a COURSE-LEVEL
shared page for one section, and that lives in the shared file's frontmatter
as `publishForSection<N>` — outside the section folder entirely. Restoring
only `section<N>/` would leave that half of the conversation's work in place.

The macOS build restores both: the section folder's contents, and — in every
shared page — only the keys carrying THIS section's number, spliced back from
the backup's own lines rather than re-derived. Copying the lines verbatim has
three consequences worth keeping: the older `draftSection<N>` spelling
survives untouched where a course still uses it, a key the conversation ADDED
is removed again, and every other section's keys plus the whole page body stay
byte for byte.

**"The keys" means each key WITH the lines it owns (#182, 2026-09-25).** A
value can live on the lines below its key (`publishForSection1: >-` over
`  false`), and a restore that carried or dropped key lines alone published
pages the backup held back and made blocks the build cannot read — measured,
and in `documentation/08-course-config-reference.md` with what was rejected.
One page shape cannot take a key back at all — a block with no column-0 line
for a new key, #186's shape — and that page is left exactly as it is and
COUNTED: `CourseRestorer.restoreSection` returns the count,
`AssistSectionRestore.doneMessage` adds
`AssistWording.sharedPagesWhoseSettingsCouldNotBePutBack` after its own
sentence, and the trail records `page settings left as they were` with the
count and never the pages. Counted rather than named because the walk has no
page titles to hand and it is almost always zero; Windows owes the count, the
sentence and the line (the `windows` issue from #182). The whole-file cases
are `course-management.json` → `backups.restoringOneSectionsKeys`.

The first of those is worth saying out loud now that an ordinary edit
MIGRATES that spelling (`AssistPageVisibility.setting`, issue #107): a restore
still does not, and that is the point. A restore's job is to put back what the
backup held, so a page the backup carried as `draftSection2: false` comes back
that way. Migrating during a restore would mean handing the teacher something
their backup never contained, in the one operation whose whole promise is that
it does not.

The section folder is emptied and refilled rather than swapped, for the same
reason `restoreBackup` documents: Obsidian holds the folder open.

**Say the surprising part in the confirmation, not in a doc.** Anything the
teacher changed in that section during the conversation goes back too,
including work done in Obsidian, and Plantoir cannot bring that part back.
That sentence belongs in the alert.

---




---

## Where the two surfaces' SCHEMAS differ, and why the mac emits only half of it

Added 2026-09-08 (issue #83). Separate from the `TEACHERS SAY:` phrasings
above: those are the words a model routes on, these are the argument SHAPES a
client is sent.

The mac's surface departs from the Windows server's in two ways, and until this
landed the only record of either was a doc comment on `AssistToolSurface` —
which meant Windows' own contract test restated them in a hand-written array.
A rule with one home in a comment and a second in another platform's test is a
rule with two homes, and this repository already knows how that ends.

`contracts/assist-cases.json` → `toolSchemas.departures` now carries it:

- **`listShapedStringParameters`** — every parameter that is a string carrying
  a LIST, with the separator this surface ADVERTISES and the surfaces it
  appears on. Nine today: seven semicolon-separated, and the two `codes`
  parameters, which use COMMAS deliberately because an expectation code has no
  comma in it and commas are what the Windows schema asks for — the one
  separator the two surfaces agree on. Derived from the DECLARATION, a
  `separatedList(separator:)` case on `AssistSchemaProperty.Kind`, and never
  from the descriptions: those are measured artifacts nobody may reword
  casually, so a generator matching English in them would depend on prose that
  is frozen, and would silently drop a new list parameter worded differently.

  **It shipped incomplete, and the fix is the lesson.** The first version
  marked three call sites and emitted seven, missing `codesHelp` — so a record
  the other platform is told is complete was not. Deriving from the
  declaration protects against DRIFT and does nothing about an OMISSION, and
  those are different failures. What closes it is a test in the other
  direction: `AssistContractTests
  .testEveryParameterThatSaysSeparatedByIsDeclaredAsAList` reads the
  descriptions the generator refuses to read, and fails if one says
  "separated by" while its declaration says plain string. The objection to the
  generator reading prose does not apply to a test reading it — a reworded
  description can only make the test DEMAND a declaration, never silently drop
  one.
- **`absentHere`** — the `preview` flag Windows has and this surface does not,
  with the reason and the rejected alternative.

**The design decision worth keeping, because it was nearly made the other
way.** The first plan had each entry say `{"here": "string", "windows":
"array"}`. That would have shipped **three false statements**: of the nine,
`remember_timetable.dates`, `plan_remember_timetable.dates` and
`plan_scheduled_deploy.classes` are strings on BOTH platforms and merely split
on different characters — semicolons here, commas there. Windows asserts its
departures as an exact set in both directions, so three phantom entries would
have turned that suite red with "these departures are resolved, delete them".

So the mac emits only what the mac can PROVE — the shape on its own surface —
and leaves the intersection to the suite that can see both. That also caught
the semicolon-versus-comma difference on `dates`, which was real, unrecorded,
and invisible to a type-only comparison.

**Windows consumes it now (2026-09-09, issue #122), and the intersection has
FOUR outcomes rather than three.** `AssistSurfaceContractTests` used to keep a
hand-written four-entry array of the type departures; it reads
`listShapedStringParameters` and intersects it with its own declared types
instead. For each entry naming a tool that surface serves: an **array** there
is a genuine type departure; a **string with a different separator** is a
separator difference, asserted against its own exact set; a **string with the
SAME separator is an agreement and nothing is asserted about it**; anything
else fails. That third branch is the one the first plan omitted, and omitting
it turns that suite red for two apps AGREEING — both `codes` parameters are in
it today.

**Two things about that are worth knowing here rather than being rediscovered.**
Windows' `differing` list is built TYPE-only, so a separator difference
produces no entry in it at all — which is why the separator cases needed their
own assertion rather than a branch of the type one, and why putting one in the
type list fails with "recorded as departures and the two apps now agree". And
the separator table stays HAND-KEPT on that side: this surface can emit its
separators because `separatedList(separator:)` knows them, where Windows keeps
them in the runner's `Split(...)` and in `[Description]` prose, neither
reachable from a schema. Consuming this key removed the SHARED copy, not that
one.

**And one difference that side flagged back, which is a decision rather than a
defect.** `plan_scheduled_deploy.classes` advertises semicolons here and commas
there. The reasoning for semicolons — that "Unit 2, Day 3" is what a class page
is called, so a comma-separated list cuts it in half — applies to that surface
identically. It has not been changed, because what a schema advertises is a
routing change and the routing suites are hand-run. `dates` differs the same
way and is cosmetic: a YYYY-MM-DD date holds no comma.

**Not a routing change.** `separatedList` renders `"type": "string"`, so the
emitted schemas are byte-identical: verified by diffing `toolSchemas.local`
and `.mcp` before and after — 13 and 32 tools, unchanged, with `departures` the
only new key. No re-measurement is owed. `AssistContractTests
.testTheDeparturesNameEveryListShapedParameter` pins that the emitted type is
still `string`, so a future change that made a departure alter the shape a
model is shown would fail rather than pass quietly.

**What is deliberately NOT here.** The arguments Windows' server takes that
this surface does not DECLARE — 25 of them, in its `agreedExtras` list. They
are mostly extra parameters on tools BOTH platforms serve: `re_date_classes`
and `read_remembered_timetable` are the clearest, carrying the same NAME and
different PARAMETERS on the two servers (`GUI-IMPROVEMENTS.md` row 447).

An earlier draft of this section said they were tools the mac does not serve at
all. That was simply wrong — the mac serves both, and every one of the 25 names
a tool it serves. The real reason they stay on that side is narrower and more
useful: the mac does not DECLARE those arguments, so it can neither test them
nor notice when they change. Issue #83's premise was that this key would remove
Windows' hand-written copy entirely; it removes the half that is shared.

**One caution for anyone consuming this.** The separator recorded is what the
schema tells the MODEL, not the only character the runner accepts.
`AssistToolRunner` is deliberately forgiving — `pages` splits on semicolon or
newline, `codes` and `dates` on comma, semicolon and newline — so a Windows
comma-separated date list is parsed correctly here today. A separator
difference is a difference in what each side ADVERTISES, and a suite should
not assert an incompatibility from it.

## Rolling a section over: why `rollover` is on one surface's schema and not the other

Written on Windows, 2026-09-08, porting the rollover's website question (issues
#66 and #69). The design, the sentences and the marker rules all came from
`contracts/`; what follows is the part a contract cannot carry.

**The mac keeps `rollover` OFF its published schema. Windows cannot, and the
reason is a platform fact rather than a preference.** On the mac, the card that
matches "roll this section over to a new year" and the runner that carries it
out share a process, so an argument set by one is simply read by the other.
Plantoir's own assistant window on Windows reaches its tools **through**
`plantoir-mcp` over JSON-RPC — `McpClient.CallTool` sends
`AssistCardCommand.ToJsonObject` verbatim — and the SDK's binder **drops** an
argument the method does not declare rather than refusing it. Measured against
ModelContextProtocol 2.2.0 by sending a made-up key to a real server over
stdio: the call completed, `IsError = false`, the key gone.

So leaving `rollover` off the Windows schema would make the rollover phrasing
run as an **ordinary re-date, with nothing anywhere reporting a fault** — the
quietest possible version of the very defect the feature exists to fix. Both
`re_date_classes` and its plan twin declare it there; plan mode is on by
default, so the card's arguments reach the TWIN first, and a twin that cannot
see them proposes an ordinary re-date and the answer is lost. All three are
recorded in `AssistSurfaceContractTests`' agreed departures.

It costs no routing accuracy on either side: `re_date_classes` is in neither
platform's local-model list, so no local model ever reads either schema.

**Rejected:** folding `rollover` into `website` (say, `website: "ask"`), which
needs no new key at all — `contracts/assist-cases.json` → `cardPhrasings` pins
`{"rollover": "yes"}` on all three phrasings and both suites assert every key
and value, so the conclusion is forced rather than merely preferred.

**A general lesson worth more than this one argument.** Every test on both
platforms either builds tool arguments by hand or calls the method directly,
which is exactly the gap a binder sits in.
`AssistSurfaceContractTests.TheCardsArgumentsReachTheToolThatReadsThem` walks
every phrasing in `cardPhrasings`, builds the JSON the app would really send,
and asserts every key is one the tool declares. It found a live defect on its
first run — the eight `publish_class_on` phrasings sent `when` and the tool
took `date`, so "publish tomorrow's class" failed in the app (issue #116, fixed
2026-09-09; the argument is in "Publish tomorrow's class: where a relative day
becomes a date" below). The mac has no equivalent check and may want one.

**The three traps the mac's own write-up named were all present on Windows
too**, which means they belong to the design rather than to the Swift: the
answer turn arrives once the dates are already right, so an early return there
makes the answer a no-op; `ShowPlan` returns early whenever the plan twin hands
back something that is not a plan, which can make the release unreachable in
the default configuration; and the question has to go in the teacher's SUMMARY
rather than the detail. A fourth was found on Windows and was the mac's too
(issue #120, fixed on the mac 2026-09-09): a bare rollover on a section whose
dates are already right never asked the question at all under plan mode, so
the question existed or not depending on a setting.

### Why the twin ANSWERS rather than proposing, on the turn that changes nothing

All four traps are the same shape — a branch that returns early because the
DATES need no change, on a feature whose whole subject is the WEBSITE — and the
fourth is the one that keeps coming back, because the natural repair is the
wrong one. A rollover with no answer, on a section already on its dates, could
be made to return a PLAN: that is what the branch beside it does for a rollover
that HAS an answer, and it would reach the real call, which asks properly.

It would also put a Go button under a question. There is nothing there to agree
to: the dates need no change, and the website is settled by SAYING one of the
two sentences, not by pressing Go — which is the design's own rule, since an
MCP client has no card to press. A teacher pressing Go would watch a plan they
accepted change nothing, and the one surface the "answer in words" reasoning
was written for would see a proposal it cannot act on. So the twin ANSWERS:
the question, the two sentences that answer it, and `rolloverWebsiteNotDecided`,
handed back as a reply that the plan surface puts in the transcript verbatim.
The contract pins it as `when: "say"` — a card appearing on that turn fails the
case rather than merely looking odd.

**The two definitions of "is this a rollover" must be ONE.** The twin and the
write each had their own, and they disagreed: the write counted `website:
"new"` or `"same"` with no `rollover` key, and the twin counted only
`rollover`. `isARollover(_:)` is now the single answer to the question, and
**any non-empty `website` counts** — so an MCP caller sending `website: "a new
one"`, which is an ordinary thing for a model to do, gets the question back
instead of an ordinary re-date with no question, no error and no mention of the
website at all. Windows reached the same rule independently
(`!string.IsNullOrWhiteSpace`).

**One consequence of that widening is the mac's alone.** Arguments arrive as
JSON and `text(_:in:)` renders a number, so `website: false` — an ordinary way
for a caller to spell "no answer here" — read as `"0"`, which is not empty, and
would have asked a teacher re-dating after a SNOW DAY whether to abandon the
address their students are reading right now. Only a `String` counts on the mac
now. **Windows cannot reach it and should not copy the guard**: the MCP SDK's
binder never lets a bool reach a `string` parameter.

**A second consequence is shared, and is kept rather than fixed.** The schema
sentence — word for word the same on both platforms — tells a caller to "leave
empty otherwise", and a model told that will sometimes send a PLACEHOLDER
instead: `"none"`, `"n/a"`, `"unchanged"`. Each of those counts as a rollover,
so an ordinary re-date picks up a website question nobody asked for, and the
teacher is then one sentence away from cutting a MID-SEMESTER section loose
from the address students are reading. It is the exact inversion of the
non-text guard above, and it was weighed rather than missed:

- **Kept, because the alternative failure is the one that has happened.** A
  real answer nobody recognised, read silently as an ordinary re-date — no
  question, no error, nothing said about the website at all — is what issue
  #120 was partly about. Weigh the two: the unrecognised answer changes the
  wrong thing silently, the placeholder says something unnecessary loudly.
- **Rejected: a list of words that mean "no".** It would drift apart on the two
  platforms inside a release, and the day it disagreed the two apps would
  answer the same call differently, which is the thing `contracts/` exists to
  stop.
- **DONE, and it was first rejected for a reason that turned out to be
  false.** The `website` parameter said "Leave empty otherwise" while the tool's
  own description, on BOTH platforms, ends "leave it out for an ordinary
  re-dating" — so the parameter contradicted its own tool, and the mac's now
  says `LEAVE THE KEY OUT otherwise`, naming the consequence. This was first
  written up as "rejected: the sentence is identical on both platforms, so a
  one-sided edit creates a divergence". That is wrong, and a Windows session
  would have seen it was wrong: description BODIES are deliberately not
  asserted across the two apps and are expected to differ —
  `AssistSurfaceContractTests` says so in as many words, pinning the
  `TEACHERS SAY:` clause and the argument names and types and nothing else,
  because `NarrowToLocal` rewrites every description through `Briefly()`. The
  real limit is smaller and is the honest one: better instruction NARROWS the
  placeholder case and cannot close it, because a model can send whatever it
  likes. **Windows may copy the sentence and owes nothing if it does not.**

  **And it owes no re-measurement**, which is worth saying plainly beside
  "what a schema advertises is a routing change" earlier on this page (issue
  #122, the same day). That rule is about the surface a LOCAL model reads, and
  `re_date_classes` is in `hiddenFromTheLocalModel`: the small model never sees
  this schema at all, only Claude Code does, and a person is reading each step
  there. Editing this particular description is one of the few schema changes
  that costs no routing accuracy — which is exactly why it was the repair worth
  making, and why the same edit to a tool the local model DOES see would need
  the hand-run suites first.

**Say what the placeholder case actually looks like, rather than calling it
harmless.** Nothing on disk changes, which is the part that matters. But a
mid-semester section that gets the question reads two sentences that are simply
untrue of it — "the same one students used last year", and "publishing it will
still go to last year's website" — about a site students are reading this term.
That is the cost, stated plainly, so the next person weighing this has the real
number rather than a reassuring one.

Only Claude Code can put free text in `website` — the card sends one of two
fixed words and no local model sees the tool — so the whole surface for this is
one where a person reads every step.

**A related edge that predates all of this, so nobody fixes it by reflex.**
`website: "same"` with no `rollover` is a RECOGNISED answer, so it has always
been treated as a rollover, and it writes `sectionKeptItsWebsiteOnRollover`
— "kept last year's website when rolling the section over" — onto the trail. A
caller that sent it on an ordinary re-date would put a line on the trail about
a rollover that never happened. Unchanged by issue #120 in either direction,
and left alone deliberately: the fix is a way to tell a placeholder from an
answer, which is the thing that does not exist.

**A known limit, recorded in `nearMisses` rather than fixed.** The reply offers
two sentences word for word, and those exact strings are the only way back in.
`re_date_classes` is shown to no local model, so a teacher who paraphrases —
"a new website", "new one please" — matches nothing at all and is told nothing.
Both apps already pass those cases, so nothing goes red; they are written down
so the limit is visible, and so a future looser matcher has to change the list
on purpose.

**Where a released legacy marker lives differs by platform**, and getting it
wrong is silent in both directions — see
[`08-course-config-reference.md`](08-course-config-reference.md), which gives
both spellings.

## "Publish tomorrow's class": where a relative day becomes a date

Written on Windows, 2026-09-09, fixing issue #116 — found by the gate the
rollover port left behind (`TheCardsArgumentsReachTheToolThatReadsThem`) and
confirmed against the real `plantoir-mcp` over stdio rather than reasoned
about. It is the same seam as the rollover section above, met from the other
side, and the general lesson is there rather than repeated here.

**What was broken.** The eight fixed phrasings — "publish tomorrow's class"
and the seven weekdays — set the argument `when`, carrying a word like
`tomorrow`. `publish_class_on` and its plan twin take `date`, and `date` has no
default, so it is REQUIRED. The binder drops a key the method does not declare
and then refuses for the one it never got, so the commonest request in the
product, reachable by CLICKING it on the prompt shelf, answered "That tool
couldn't be run: …" — a sentence naming machinery, for a request that was
perfectly well understood. Plan mode is on by default, so it failed at the
twin, before anything was written; nothing was ever corrupted.

**Why it could not be fixed by renaming the card's argument.**
`contracts/assist-cases.json` → `cardPhrasings` is GENERATED from the mac's
`AssistCardCommand.fixedShapes`, both suites assert every key and every value,
and `when` is the mac's shape and is right there: its card and its runner share
a process, so the runner simply reads whichever name arrived. The card keeps
saying `when`. What changed is the JSON.

### Three places a day could be settled, and why it is the one it is

The choice is not "which layer is tidiest" but "whose clock, and how many
times".

- **`AssistCardCommand.ToJsonObject`, which is what shipped.** The one place
  the card becomes the wire. It renames `when` to `date` for these two tools
  only — `schedule_deploy` genuinely takes a `when`, being a day AND a time —
  and settles the word into a date as it goes.
- **Inside the tool, only.** Rejected as the sole home, because
  `AssistAgent.RunCommand` synthesises ONE arguments object and uses it twice:
  first for the plan twin, then, if the teacher presses Go, for the act. A word
  carried through resolves twice, against two different readings of the clock,
  so a plan shown at 23:59 and agreed to at 00:01 publishes a class the plan
  never described. Rare, silent, and a wrong day nobody would think to look
  for. Settling it at match time makes the plan and the act the same day by
  construction.
- **Both.** Which is what shipped, for a reason that is not belt-and-braces:
  an MCP client — Claude Code — reaches `publish_class_on` with no card in
  front of it and nothing to rename anything, and the mac's runner has always
  forgiven a relative day. Leaving the tool strict would have made the same
  sentence mean different things on the two MCP surfaces. Both paths call the
  same `SectionScheduleSource.ReadRelativeDay`, so there is exactly one answer
  to what "monday" means, and `PlantoirTools.Today` is a `Func<DateOnly>` read
  per call rather than a stored date, because one `plantoir-mcp` can stay open
  longer than a calendar day.

**The guarantee is the CARD path's, and only its.** When the MODEL sends
`date: "tomorrow"` — which `ClassDateHelp` tells it not to, and which a small
model will sometimes do anyway — the twin and the act each call `DayFor` and
each read the clock, so the 23:59/00:01 case above still exists on that path.
It is not closed here because this piece is the card path, and that is the only
honest reason: normalising a model-supplied `date` inside `AssistAgent` after
the model has already CHOSEN the tool would cost no routing accuracy at all —
the model sees nothing of it — and is exactly the "steer with code" move
recommended below. Cheap, and simply not done yet. Worth knowing before
anybody reads the paragraph above as covering everything, and before anybody
talks themselves out of the fix on the grounds that it needs a re-measurement.
It does not.

**Done on the mac on 2026-09-10, and still owed on Windows** — see "The mac's
half" below, and [issue #159](https://github.com/russellgordon/plantoir/issues/159).
It cost fifty lines of code — 170 with the comments that explain them — and
no re-measurement, exactly as predicted here.

**The tool DESCRIPTIONS were deliberately not touched, so no routing
re-measurement is owed.** `ClassDateHelp` still tells the model to work the
date out itself. A tool that has become more forgiving owes the model no
announcement, and this repository has already measured what a clarifying
sentence costs: one added to `publish_pages` took the promise-card score from
110/110 to 90/110. Steer with code.

**A second settler joined it on 2026-09-19**, for the tools that take a
MOMENT rather than a class day — `AssistToolRunner.settlingTheDeployMoment`,
which turns a bare `06:30` into the whole moment it means. The two divide the
surface by the SCHEMA and not by a remembered list: this one takes the tools
that declare `date`, that one the tools that declare `when` and not `date`.
The reasoning, the day-choosing rule and what was rejected are under "A time
is a number, not a judgement" above; what matters here is that neither settler
can reach the other's tools, so the sentence "`schedule_deploy`'s `when` is
excluded by construction" above is still true of the DAY settler and is no
longer the whole story about that argument.

### What "Monday" means, and where that decision lives

`contracts/schedule-rules.json` → `relativeDays`, which both suites run — the
mac against `AssistToolRunner.day(named:today:)`, Windows against
`SectionScheduleSource.ReadRelativeDay`. The eight cases added here write down
a rule the mac has always had in code and nobody had ever pinned:

- **The next such day, counting TODAY when today is one.** Asked on a Tuesday
  for Tuesday's class, a teacher means the class they are about to teach.
  Rejected: always looking forward at least a day, which is defensible in the
  abstract and wrong every Monday morning, on the day the request is most
  likely to be made.
- **Forwards only, inside seven days.** It is said while preparing. A teacher
  who means a class already taught has its Unit and Day in front of them.
- **`monday's` is `monday`** — the apostrophe belongs to the phrasing. Both
  spellings of it, because which one a teacher types depends on their keyboard
  and on what autocorrect did to it.
- **`next monday` is refused, not guessed**, alongside the `next Thursday`
  case that was already there: it can mean the coming Monday or the one after,
  people genuinely disagree, and a date guessed wrong dates a class wrong in
  silence. The model answers that one, with today's date in front of it. It is
  in `nearMisses` too, as the near miss of a phrasing that DOES match.

WHERE the word is understood is deliberately NOT pinned — that is the platform
difference above. WHICH day it names is, because the same sentence must mean
the same day on either machine.

**Compare days of the WEEK, never formatted names.** `ToString("dddd")` asks
the machine's culture what Monday is called, so on a French-locale machine the
seven phrasings would quietly stop working for one teacher and nobody else; the
mac pins `en_US_POSIX` on its formatter for the same reason. The same trap
applies on the way out: `ToString("yyyy-MM-dd")` renders the year in the
machine's DEFAULT CALENDAR, which is 2569 on a Thai-locale Windows machine
(measured: `2569-09-09` against `2026-09-09`), so the date is written with
`InvariantCulture` and the tool is not left looking for a class on a day no
course has.

**The rule is applied at the boundary this piece owns, and nowhere else.**
Sixty-six sites in this app's product code still format a date with no culture,
and several of them WRITE one, which is the half that matters: an affected
machine would corrupt a section's dates DURABLY rather than merely print them
oddly. `PageFrontmatter.SetCreated` is the stamp every re-date puts into a
page's `created:`. `TimetableMemory.Write` is worse again, and is the example
to keep in mind, because the asymmetry is inside one file: it writes the
remembered class dates in the machine's calendar and `TimetableMemory.Read`
parses them back with `InvariantCulture`, so on a Thai-locale machine every
date a teacher remembered lands 543 years in the future and nothing reports a
fault. That sweep is its own piece of work, with its own review: [issue
#144](https://github.com/russellgordon/plantoir/issues/144). **`CalendarDay`
is immune by construction** — `.text` is `String(format: "%04d-%02d-%02d", …)`,
three integers and no calendar — **but the mac was not, and this line used to
say it was.** Two `DateFormatter`s in mac product code set a `dateFormat` and
pinned no locale, so they rendered in the machine's default calendar:
`CourseArchiver.timestampedName`, which builds archive and backup FILENAMES,
and `ArchivedItem.date(fromStamp:)`, which read them back. On the Thai-locale
machine measured above, a mac wrote `ICS3U_2569-08-09_141530.zip` against a
form `contracts/course-management.json` pins as `yyyy-MM-dd_HHmmss`. Symmetric
on one machine and broken between two, which is why nobody met it. **Fixed on
2026-09-10** ([issue #160](https://github.com/russellgordon/plantoir/issues/160)):
`ArchiveStamp` now owns both ends, and it goes on reading the old spellings,
because a teacher on such a machine has zips already named that way and the
date in one of those names decides which backup gets DELETED. The whole of it
— including the Ethiopic case, which is the one an ordinary sanity check
cannot catch — is in
[`documentation/09-mac-app.md`](09-mac-app.md) → "What an archive or a backup
is CALLED, and the calendar it is stamped in". Everywhere else is pinned to
`en_US_POSIX`, and the third instance was `AssistAgent.dateline()`, fixed
below because that line was being rewritten anyway.

### The mac's half: settled where the call is made, and a clock that is read

Written on the mac, 2026-09-10, closing the second half of
[issue #143](https://github.com/russellgordon/plantoir/issues/143) — the
finding Windows handed back with the eight cases above. The first half needed
no code: the mac already passed all thirteen `relativeDays` cases, which is
what the issue asked it to confirm.

**What was wrong.** `AssistToolRunner` took `today` in its initializer and
STORED it. The runner is built once per conversation
(`AssistSession.beginConversation`) and once per `--mcp-stdio` process
(`AssistMCPServer.serve`), so the day was fixed for the life of both. An
assistant window left open across midnight resolved "tomorrow" against the day
the conversation BEGAN — for every request in it, not only one approved across
the boundary — published the class before the one meant, and said "Published
the class on …" naming a day the teacher had not asked for. A Claude Code
session holding the MCP server open for days is the sharper version of the
same thing. The model-routed path never had the fault when the model worked the
date out ITSELF, because every message carries a fresh dateline — so one
long-lived window could answer "publish tomorrow's class" and "publish the
class tomorrow please" with different days. It did have it whenever a small
model passed the word `tomorrow` straight through as its `date` argument
instead, which `classDateHelp` tells it not to do and which it sometimes does
anyway; issue #143 made the same simplification, and that case is exactly what
the settler below covers.

**Why the obvious fix is wrong on its own.** Making `today` compute
`CalendarDay.today()` per use fixes the staleness and breaks something the
freeze was quietly buying. Plan mode reads ONE arguments object twice — the
`plan_` twin first, then, if the teacher presses Go, the act — so a word still
carried at Go time is read a second time against a clock that has moved. A
plan shown at 23:59 then publishes something else at 00:01. That is the same
trap Windows met from the other side and wrote down above, and it is why this
was raised as a decision rather than as a defect with an obvious fix.

**What landed: settle the word once, then read the clock freely.**

- `AssistAgent.withTheDaySettled(_:)` turns the word into the date it means at
  the moment the call is created, beside the existing `boundToThisSection(_:)`
  binding (which rewrote the course as well until #202, and now takes back only
  the section). Everything downstream — the approval card, the plan twin, and
  `approvePending` handing the very same call to `execute` — then carries an
  absolute date, so the plan and the act agree BY CONSTRUCTION rather than by
  a frozen clock. It covers the model-routed path as well as the card's, which
  is the fix the Windows write-up above called cheap and not yet done.
- `AssistToolRunner.today` is a computed property over an injected
  `() -> CalendarDay`. Nothing captures a date any more, so the two remaining
  readers — the upcoming-classes summary and `remember_timetable`'s planning —
  and the whole MCP process are fresh.

**Which argument carries a day is asked of the tool surface**, not of a list
kept beside the settling code: only a tool that declares a `date` parameter is
touched, which is `publish_class_on` and its twin today. `schedule_deploy`'s
`when` is a MOMENT — a day and a time, parsed by `moment(named:)` — and is
excluded by construction rather than by being remembered, which is the same
argument `AssistAgent` already makes for asking the surface whether a plan twin
exists. (**That argument now has a second half**: since 2026-09-19 a bare clock
time in a MOMENT is settled by `settlingTheDeployMoment`, which takes exactly
the tools this one refuses — `when` declared and `date` not. Same question
asked of the same schema, two answers that cannot overlap. See "A time is a
number, not a judgement".) The card's own spelling `when` is settled for those tools too, but NOT
renamed to `date`: `AssistCardCommand` is generated into
`contracts/assist-cases.json` → `cardPhrasings` and both suites assert that
key. A word the settler cannot read is left exactly as it arrived, so the
sentence a teacher sees is still the runner's own refusal.

**The dateline had to move too, or the claim below would have been false.**
`AssistAgent.dateline()` read `Date()` and is appended to every model-routed
message — it is how the model does its own date arithmetic — so leaving it
alone would have kept a second reading of the clock in the very class that had
just settled the first. It takes the day now (`dateline(on: tools.today)`).
Building it from a `CalendarDay` took the LOCALE out of it as a side effect,
and that half was a live latent fault rather than tidying: the old version
asked `DateFormatter` for `EEEE` with no locale pinned, so a French-locale Mac
would have told the model "a mardi" and a Thai-locale one would have dated it
2569 — the same trap the Windows section above measured, live in the sentence
the model reads most often. Not the last instance on this side: the audit it
prompted found two more, in the archive filenames, which were
[issue #160](https://github.com/russellgordon/plantoir/issues/160) rather than
this piece, because a durable name cannot be respelled without a migration —
fixed the same day, in `ArchiveStamp`, with that migration written
([09-mac-app.md](09-mac-app.md) → "What an archive or a backup is CALLED"). `CalendarDay` is three integers and
`String(format:)`, and its `weekdayName` pins `en_US_POSIX`. The sentence is
byte-identical on an English machine, so the routing measurements stand and no
tool description was touched.

**Against the RUNNER's clock, not the machine's** — `tools.today`, not a second
`CalendarDay.today()` in the agent. Two clocks in one process is two answers to
what today is, differing on one night in a thousand, and no test able to pin
the one a teacher's request actually used. Measured rather than argued: an
earlier draft read the machine's clock in the agent and turned two existing
tests into functions of the wall clock, one of them the SHARED contract
scenario "a plan card is cancelled", whose fixture pins the runner to
2026-09-08 and writes one class page dated 2026-09-09.

**What this deliberately does NOT do.**

- **Over MCP the twin and the act can still disagree across midnight.** A
  client calls `plan_publish_class_on` and then `publish_class_on` as two
  separate requests, each resolving its own words against a now-fresh clock.
  There is no single moment "the call is created" to settle at, and inventing
  one would mean the server remembering plans between requests. Windows made
  the identical trade — `PlantoirTools.Today` is a `Func<DateOnly>` read per
  call — and the exposure is one minute of one night against a bug that was
  costing whole days.
- **`remember_timetable`'s twin pair is left to resolve twice, and that is
  safe.** `timetablePlan` is shared by the plan and the act, so a fresh clock
  is read once by each. `today` reaches only `RememberTimetablePlan.recorded`,
  which no sentence of the plan's description reads back and no
  `changesNothing` comparison consults — and a stamp recording the day the
  dates were written is arguably more correct for having moved.
- **Nothing new goes on the activity trail.** No line has ever recorded which
  day "tomorrow" became: "assistant matched a fixed phrase" carries the tool
  name, and "assistant chose a tool" carries argument NAMES and never values,
  deliberately. Adding the settled date would mean a value on the trail and a
  `carries` change in `contracts/shared-rules.json` for both platforms.
  (**Reversed for the deploy MOMENT on 2026-09-19**, #168: the line now also
  carries the whole moment a bare time settled onto, and `carries` was widened
  to say so. The argument that won is the one this bullet did not have — a
  DAY word is recoverable from the "assistant asked" line's own timestamp and
  the sentence beside it, whereas "the next 6:30 from now" is a choice the
  code made and nothing else records. The class day is unchanged: this is one
  value, of one shape, on one family.) The
  day is diagnosable without it — after this change it is a function of the
  "assistant asked" line's own timestamp and the sentence it carries, where
  before it was a function of when the window opened, which the trail does not
  record. The published date remains in what the teacher was told
  ("Published the class on 2026-09-09."), which is why that sentence names the
  day it settled on rather than the word it was sent.

### Two things this deliberately did not fix

- **The absolute-date halves still differ.** Windows' `ParseDate` is
  `DateOnly.TryParse` with `InvariantCulture` and accepts `9/14/2026` and
  `14 September 2026`; the mac's `CalendarDay(text:)` is strict ten-character
  `yyyy-MM-dd`. Only the relative WORDS are now the same on both. Worth
  knowing before anybody writes a contract case asserting otherwise.
- **`“x” isn't a date date can use.”`** Both platforms build that sentence
  from the parameter's own name (`AssistPublishPlan.unreadableDate`,
  `PlantoirTools.ParseDate`), so the class-date path reads "a date date can
  use". It is a shared wording defect rather than a Windows one, unreachable
  from any of the eight phrasings, and fixing it on one side alone would make
  the two apps say different things — so it is written down here instead.

**What the trail does and does not carry.** "assistant matched a fixed phrase"
records the tool — and, since 2026-09-19, the whole MOMENT when the phrasing
named a time and the app chose a day for it (#168, mac only so far) — and
"assistant chose a tool" records argument NAMES and never values, deliberately
— the values are the teacher's page titles. So a report of
"it published the wrong day" cannot be diagnosed from the trail on either
platform, and neither app changed that here: it would mean putting a value on
the trail, against a rule `contracts/shared-rules.json` states with its
reasoning. The published date is in what the teacher was told instead
("Published the class on 2026-09-09."), which is why that sentence names the
day it settled on rather than the word it was sent.

## The other doors: handing a course to an assistant the teacher already has

Written 2026-09-19 with [issue #205](https://github.com/russellgordon/plantoir/issues/205),
which added the second of them. **This feature had never been written down
anywhere** — a year after the first door shipped there was no section, no
contract data and no reasoning on record, only 231 lines of Swift and nine
lines of SwiftUI. That is what made adding a second one the moment to stop.

Everything above this point is about the assistant Plantoir *carries*: a model
running on the teacher's own Mac with no account, opened from a window of its
own, bound to one section. These are different. A teacher who already has
**Claude Code** or **Codex** on their Mac gets a menu item that hands the whole
course to it — a real terminal session, with Plantoir's tools already
connected and an opening message already sent. Nothing is typed by them.

| | Revise with Claude… | Revise with Codex… |
|---|---|---|
| Tool looked for | `claude` | `codex` |
| Server handed over as | a configuration file, `--mcp-config` | inline configuration, four `-c` overrides |
| Written for the connection | `mcp-<CODE>.json` | **nothing** |
| Script the mac hands to a terminal | `launch-<CODE>.command` | `launch-<CODE>-codex.command` |
| A teacher's own MCP servers | not loaded (`--strict-mcp-config`) | **loaded beside Plantoir's** |
| Sandbox / approval flags passed | none | none |
| Trail line | `started Claude Code for <CODE>` | `started Codex for <CODE>` |

Both doors are described as data in
[`contracts/app-rules.json`](../contracts/app-rules.json) → `outsideAgents`,
and a mac test walks both. The sentences live there, not in this page: naming
them rather than quoting them is what keeps a document from going quietly out
of date.

### The shape, which is the same for both

Find the tool; write an executable `.command` script into the app's own data
directory; hand that script to iTerm if it is already running, else Terminal,
through LaunchServices rather than AppleScript so no Automation permission is
asked for. The teacher watches a real session.

Three properties matter more than the mechanism:

- **Nothing lands in the teacher's folder.** Everything is in
  `~/Library/Application Support/Plantoir/assist/`, never in the vault Obsidian
  is watching. Neither door writes a `CLAUDE.md`, an `AGENTS.md` or a
  `.mcp.json` — Codex's `AGENTS.md` convention costs nothing and gains nothing
  here, because there is no such file for either agent to read and the whole
  instruction set is the one-paragraph greeting passed as an argument.
- **The item is hidden when the tool is not installed**, and hidden
  independently per door. Not greyed out: a menu that teaches teachers to stop
  reading it is worse than a shorter menu.
- **Plantoir never installs one, and never offers to.** These are developer
  tools with accounts and their own update paths. A teacher who wants one
  installs it themselves and Plantoir finds it.

**The course reaches the session through the GREETING, and nowhere else.** The
server is given the WORKING FOLDER (`--mcp-stdio <folder>`), so every course in
it is reachable from either door. The class comment on `ClaudeCodeLauncher`
claimed the opposite for a year — that the session was "locked to the course …
passed to the server rather than asked for in a prompt" — and it was never
true; it was corrected with this work, because a reader who believed it would
have given Codex a narrowing that neither door has. The assistant Plantoir
carries itself *is* bound (`contracts/assist-cases.json` → `windowBinding`);
an outside door is not.

**The search list does nearly all of the work, and it is the first thing
somebody will simplify away.** An app launched from the Dock inherits launchd's
minimal PATH, so `onPath` usually finds nothing even on a Mac where the
teacher's own shell finds the tool at once. PATH is tried first, then
`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`,
`~/.bun/bin` and every `~/.nvm/versions/node/*/bin`. The same list serves both
doors with only the name changed: Codex's own installer script sets
`BIN_DIR="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"`, which is already the first
place looked.

**Being findable is not being signed in**, and the door does not try to find
out — that would mean running the tool while a context menu is being drawn. A
teacher who is signed out meets their assistant's own sign-in step in the
terminal.

### What was MEASURED for the Codex door

On Russell's Mac, 2026-09-19, **codex-cli 0.155.1** installed with Homebrew and
signed in with a ChatGPT account. The Plantoir binary used was the DerivedData
Debug bundle; the working folder was `~/Desktop/plantoir-overnight`, which is
not a git repository.

1. **`-c` can DEFINE a new MCP server for one invocation, and Plantoir
   persists nothing.** `codex -c 'mcp_servers.plantoir.command="…"' -c
   'mcp_servers.plantoir.args=[…]' mcp list` listed `plantoir … enabled`, and no
   `~/.codex/config.toml` existed afterwards. (That file DID exist after the
   interactive run in 3 — written by CODEX, not by Plantoir: it records the
   teacher's own answer, `[projects."<folder>"] trust_level = "trusted"`,
   and it is also where an "Always allow" answer is kept. Plantoir's server
   is never written into it.) A path containing both a space
   and an apostrophe survived the two escaping layers. This was the design's one
   real unknown and it is settled: dotted overrides create the missing
   intermediate tables, and each value is parsed as TOML.
2. **Plantoir's server starts inside Codex's startup window, and a READ tool
   runs unprompted.** `mcp: plantoir/list_courses started` → `(completed)`,
   returning both courses of the folder. Under `codex exec` this happened with
   the sandbox at `read-only` and approvals at `never`.
3. **The interactive TUI asks once whether to trust the folder, and then
   proceeds.** A teacher's working folder is not a git repository, and this
   matters: `codex exec` REFUSES a non-git directory outright ("Not inside a
   trusted directory and `--skip-git-repo-check` was not specified", exit in
   0.06 s), but the TUI — which is what the door launches — shows a trust
   prompt instead. **So no `--skip-git-repo-check` is needed**, and none is
   passed. The decision is saved, so it is asked once per folder. (NOT measured,
   but read off the code: the trail line is written before the terminal is
   launched, so a teacher who answers "Quit" gets a window that closes while
   the trail already says a session started — worth knowing when a report says
   "nothing happened". The Claude door has always done the same.)
4. **The positional greeting is taken as the first message.** Codex
   immediately called `plantoir.list_courses({})` and rendered both courses.
5. **A WRITE is gated by Codex itself, with no approval flags from us.** Asked
   to unpublish a page, it first called `plantoir.explain_publishing` unprompted
   and quoted it, then stopped at *"Allow the plantoir MCP server to run tool
   'unpublish_pages'?"*, showing the course, the pages and the section, with
   **1. Allow / 2. Allow for this session / 3. Always allow / 4. Cancel**.
   Note the third: **"Always allow" persists the teacher's choice for future
   sessions**, which is a decision they make and Plantoir cannot see.

6. **The two doors differ in WHEN the publishing explanation arrives, and
   that is accepted.** Russell opened both doors on the same course from the
   built feature (2026-09-19, a fresh non-git folder, ICS4U, one section). Same
   greeting, same first call (`list_courses`), same promise to show the plan
   and wait. But Claude made TWO Plantoir calls and relayed
   `explain_publishing`'s text word for word at the greeting, while Codex made
   one and did not. The cause is the tool's own description — "Call this
   FIRST, before doing anything else with a section": Claude reads "first"
   eagerly; Codex defers it until it is about to act on a section (in 5 it
   called it unprompted immediately before the unpublish). The explanation
   still reaches a teacher before any change. REJECTED: adding a sentence to
   Codex's greeting to make the openings look alike — cosmetic, and it would
   make the two greetings diverge. Also seen: asked about the teacher's
   teaching style, both honestly said they did not know yet — neither had read
   a page, and nothing Plantoir hands them says how the course is taught.
   That is issue #209.

Whole `exec` session including the model call: 15 s. MCP cold-start was not
timed separately, and a signed-out launch was not measured (expected: Codex
asks them to sign in).

### The two timeouts, and why they are passed rather than trusted

```
-c 'mcp_servers.plantoir.startup_timeout_sec=60'
-c 'mcp_servers.plantoir.tool_timeout_sec=1800'
```

Codex's own defaults **disagree between its source and its published
reference** — `DEFAULT_STARTUP_TIMEOUT` 30 s and `DEFAULT_TOOL_TIMEOUT` 300 s in
`codex-rs/codex-mcp/src/rmcp_client.rs`, against 10 s and 60 s in the
configuration reference — so the effective value is version-dependent on a
teacher's machine. Both tool figures are too short whichever is in force:
`AssistToolRunner.deploySection` **awaits** the deploy, and a first publish
builds the image and uploads through wrangler, which is minutes. The startup
figure is cheap insurance: the server is a whole app binary starting cold, and
the difference is a door that opens against one that says it timed out.

A future reader who deletes these two as redundant meets
`CodexLauncherTests.testBothTimeoutsArePassed`.

### The escaping is TWO layers, and the inner one fails quietly

Each value sits inside a **TOML basic string** inside a **shell-single-quoted
argument**:

```
-c 'mcp_servers.plantoir.args=["--mcp-stdio","/Users/r/Russell'\''s Courses"]'
```

`escapeForTOMLString` is applied first (`\` → `\\`, `"` → `\"`, control
characters as TOML escapes; an apostrophe needs nothing here, and UTF-8 above
U+007F is legal in TOML and is left alone), then `escapeForShell` wraps the
whole argument.

**Getting the inner layer wrong does not produce an error.** Codex's
`parse_toml_value` falls back to treating an unparseable value as a raw string,
so a working folder whose name contains a double quote turns `args` from a
`Vec<String>` into one `String` — and the teacher meets a door that greets them
warmly and then cannot start its server, with nothing on screen naming the
cause. That is why this is a function with six golden fixtures (a plain path, a
space, an apostrophe, a double quote, a backslash, unicode) **and** an argv
round-trip test that runs the written script against a stub `codex` and reads
back what actually arrived.

Dotted keys were chosen over one inline table
(`-c 'mcp_servers.plantoir={command=…,args=[…]}'`). Both work. The inline form
halves the escaping surface, which is the argument for it; the dotted form
merges into a teacher's configuration one key at a time and is what the
published documentation shows, so a reader can check it. The escaping is
tested; matching the documentation is not.

### The one divergence that cannot be fixed from here

**Codex has no `--strict-mcp-config`, so a teacher's own MCP servers load
beside Plantoir's.** This is structural rather than an omission in the
documentation: the CLI overrides layer is MERGED with the user's configuration
by a recursive table merge, and
[openai/codex#16045](https://github.com/openai/codex/issues/16045) records that
even `-c 'mcp_servers={}'` cannot clear what is already there. The Claude door
isolates; the Codex door cannot. Said plainly here rather than hidden in a
comment, because it is a real reduction against the older door and somebody
will eventually ask why the two are not the same.

### What was REJECTED

- **`CODEX_HOME=<a Plantoir directory>`** — a perfect `--strict-mcp-config`
  equivalent, and it **logs the teacher out**. It relocates *everything*:
  `config.toml`, `auth.json`, `history.jsonl`, the state database. The teacher
  would meet a sign-in screen they did not ask for, in a session Plantoir
  started for them.
- **A project `.codex/config.toml` in the working folder.** Inside the
  teacher's folder but in a dotfolder Obsidian ignores, so that part is fine.
  It is rejected because it is **loaded but disabled when the directory is
  untrusted**, silently — the untrusted-folder screen says "Config, hooks, and
  exec policies from untrusted folders stay disabled". A route that fails by
  doing nothing and saying nothing is worse than one that fails loudly. The
  `-c` layer is applied unconditionally, before any project layer, which is a
  second and independent reason it wins.
- **A global `codex mcp add plantoir -- …`.** It writes user scope only —
  `$CODEX_HOME/config.toml`, no `--scope` flag — so it edits something OUTSIDE
  the teacher's folder, which is the one thing the Claude door has always
  refused to do. It is also wrong on its own terms: the `args` name ONE working
  folder, and a teacher with two would have a global entry pointing at whichever
  they opened last.
- **`--profile`** — same objection; a profile is a file in the teacher's Codex
  home.
- **Any `--sandbox` or `--ask-for-approval` flag, and
  `mcp_servers.plantoir.default_tools_approval_mode`.** Measurement 5 shows
  Codex already asks before a write, which is exactly the behaviour the greeting
  requests. Passing a flag would quietly widen permissions the teacher set for
  themselves. The last one is named because it is the lever somebody will
  propose the first time a teacher finds the prompting tedious.
- **`--cd <folder>`** — unnecessary; the script already `cd`s, and the server is
  given the folder as an argument.
- **Auto-installing Codex, or offering to.** See above.
- **Writing an `AGENTS.md` into the teacher's vault.** A developer-looking file
  in the folder Obsidian watches, to say what the greeting already says.
- **The `OutsideAgent` / `OutsideAgentLauncher` extraction**, on the day of a
  release. The helpers were lifted (one directory search parameterised by name,
  one support directory, one terminal launch, one greeting) and nothing is
  duplicated, but the two doors remain two types and `SidebarView` builds its
  items at two call sites. Windows already learned that drifts. The golden tests
  that pin the Claude door's greeting, script and configuration **to the byte**
  were added FIRST, before anything was touched, precisely so the extraction can
  be done later and proved not to have moved anything.

## A course kept for reference: the write gate, and the seam it is NOT gated on

A reference course is read-only to every tool on both surfaces. The gate is one
check at the top of `AssistToolRunner.run(call:)`, and three decisions in it are
worth keeping.

**Gated on the tool's own `readOnly` flag, never on a list of names.** A list
kept beside the gate is a list somebody forgets on the day they add a tool —
the same reasoning the window binding uses for gating on the SCHEMA rather than
on a roster. A test asserts that the non-`readOnly` tools minus the exemptions
are exactly the set the gate refuses, so adding a tool fails the suite rather
than opening a hole. Measured with the gate turned off: **ten** write tools
reached a frozen course, `publish_pages`, `re_date_classes` and
`undo_last_change` among them.

**Three exemptions, and they are contract DATA** (`shared-rules.json` →
`referenceCourses.refusal.toolsStillAllowed`), each with its reason:
`rebuild_preview`, because a reference course may be previewed and the preview
writes into the build tree rather than into the course; `back_up_course`,
because it reads the course and writes a zip outside it; and
`cancel_scheduled_deploy`, which is **gate by DIRECTION** — never refuse the act
that STOPS a deploy. A course marked by hand while an alarm was already set must
still be able to have that alarm turned off from the app.

**Never gated on "is this the course the session greeted".** There is no such
binding over MCP: `--mcp-stdio` takes the WORKING FOLDER, so every course in it
is reachable and the only thing pointing a session at one course is the
greeting. Inventing a binding here in order to except it would take away the
capability a reference course exists for — being READ by a Claude or Codex
session working in the live course. Do not add one believing one already
exists.

**Two sentences, chosen by what was asked for.** A deploy is told the course is
never deployed; every other write is told it stays as it is. "It is never
deployed" answers a question nobody asked of "add a class to ICS3U", and "it
stays as it is" leaves somebody who asked for a deploy wondering whether it
would work later.

**The local thirteen-tool surface did not move a byte**, which is the proof
decision (j) asked for. `contracts/assist-cases.json` → `toolSchemas`, hashed
before and after the whole change:

```
toolSchemas.local  n=13  sha256 = 1b3666437802e1038b7801727abbe0968232c32ff878c3934136aa9dc33689f8
toolSchemas.mcp    n=32  sha256 = 079594d16aad00a8339a6e2cf560fcb508f98711339e14c0ae07bb97f8e76c84
```

Both identical afterwards. Nothing here is a routing change, so the 29-probe
suite does not need re-running: the gate is code in front of the dispatch, and
the sentences are tool OUTPUT rather than definitions.

## A numbered course has no units (#267)

A club's pages are "Week 1", "Week 2" — `class_page_scheme: "numbered"`, see
[08](08-course-config-reference.md). Inside the mac app a numbered page is a
`UnitDay` with `unit == 1` and `day == N`, which is what lets next-class,
make-room, duplicate, the placeholder planner and the front-page tie-break count
one number with no planner rewrite of their own. REJECTED: a second type
threaded through seven planners (seven places to forget, and the rename order
of make-room and duplicate is exactly the subtle part that would be re-derived);
storing "Week N" as unit N, day 1 (next-class would start a new unit every time
and make-room would move nothing).

The seam has one consequence that would otherwise have been the worst bug in
the piece, and every rule below exists because of it:

- **No whole-unit path.** `AssistPublishPlanner.unitNamed` returns nil in a
  numbered course, and `classPages(inUnit:)` skips numbered pages. Before the
  fix the real parser read "Week 1" as unit 1, so `publish_pages(pages:
  "Week 1")` — the most ordinary request a club has — published EVERY meeting
  in the section (measured: four of four, `NumberedCourseTests`, by putting the
  old guard back), with a card that said "publishing Unit 1"; "Week 3" found
  no unit and was REFUSED. Now every title goes to the page path, which acts on
  the one page named. `class-planning.json` → `wholeUnit` pins it for Windows.
- **Start a new unit, and add days to a unit, are refused**
  (`NextClassPlanner.Problem.noUnitsInANumberedCourse`) BEFORE the timetable is
  read, so nobody is asked for their dates on the way to being told no. The
  card phrasings reach the same refusal.
- **Make room reads ONE number** from the frozen schema's `unit`/`atDay`
  (`ClassInsertionPlanner.numberedPosition`): either argument alone, `1` plus
  the other, or the Unit/Day habit `unit: 5, atDay: 1` all mean 5; two
  different numbers, neither 1, are refused so the teacher is asked. Which one
  a small model fills for "make room at Week 5" is a ROUTING question, and is
  NOT measured: nothing in this piece changed what the model is shown, and the
  club's own card, "Make room for one meeting at Week 5", is matched in code
  and never reaches the model (below) — in a numbered course, on that course's
  own word, only. A teacher who types their own phrasing
  reaches the model on the frozen schema, and the reading above is what makes
  either filling safe.
- **A numbered course orders by DATE, and its numbers may have gaps.** Clubs
  are sparse: CODING's pages are Week 1 (2025-09-18), Week 2 (09-25), Week 8
  (11-20), Week 9 (11-27), on weekly Thursdays; weeks 3–7 were never written.
  Three rules follow, each measured wrong on that exact shape first:
  - **The next page** (`NextClassPlanner.plan`) is one past the highest number,
    dated on the first class day after the LATEST dated page
    (`positionAfterTheLatestPage`). The Unit/Day rule dates by POSITION — four
    pages, so the fifth date — and wrote "Week 10" on 2025-10-16, five weeks
    BEFORE Week 8, where the front page (which follows the latest visible date)
    never showed it. Past the end of the timetable it shares the last day, as
    every planner here does.
  - **Make room at N, and duplicate as N** (`ClassInsertionPlanner.planNumbered`)
    put the new pages on the first free class days after the pages numbered
    below N. A page is RENAMED only when a new number lands on its name, and
    the run stops at the first page whose number is already clear; a later page
    keeps its date when it is already after the page before it, and only a page
    whose date COLLIDES moves, to the first class day after that page. A page
    with NO `created` is never given one — it has no date to collide with — and
    is placed among the dated pages by its NUMBER (`inDateOrder`). The fix
    round's first version sorted undated pages last: the fix review measured an
    undated Week 1 renamed Week 2 and dated 2025-11-27, after Week 8, and in an
    all-undated section an untouched Week 8 "moved" to 09-25. Measured
    on the first version: "make room at Week 3" (a gap) and "duplicate Week 2 as
    my next meeting" dated the new Week 3 2025-11-20 — Week 8's day, with 10-02
    free — and renamed Week 8 → 9 and Week 9 → 10, a week later each: two
    published meetings renamed, links rewritten, to fill a slot that was empty.
    Now the new Week 3 is on 10-02 and nothing else changes, so the plan lists
    no move and the duplicate can be undone. Making room at an EXISTING number
    (Week 2) renames Week 2 → 3 and moves it to 10-02; Week 8 and 9 keep their
    names and dates. For a section with no gaps these give the same answer as
    the Unit/Day rules.
  - The first fix kept only the LATER pages' gaps (a page after the insertion
    stays put when it is already after the page before it). REJECTED as
    incomplete: it left the new page on the insertion point's day and every
    later page renamed, which is where the damage was. Also REJECTED: dating by
    position but skipping dated days (still five weeks early in CODING), and
    renumbering the section to close the gaps (a club's numbers count meetings,
    and renaming published pages is the one thing a teacher cannot see coming).
  `class-planning.json` pins all of it in CODING's shape, dates AND numbers:
  `nextClass` (the dated case), `insertion` (at a gap, at an existing number,
  a collision run, and two with undated pages) and `duplication` (into a gap). The Unit/Day scheme keeps
  its slot and position rules; its pages sit on consecutive class days by
  construction, and changing it there is not part of this piece.
- **Sentences name the course's own shape.** The two make-room sentences, the
  whole-unit card, the placeholder plans and the "no pages named …" problems
  used to type "Unit … Day …" by hand — which also told a Module course "at
  Unit 3, Day 4" (#268, fixed here). They go through `ClassPageNaming.title`,
  `shapeDescription` and `unitName`; `insertion.positionInSentences` pins it.
- **What the model is shown does not move.** No tool description, schema or
  prompt byte changed: `toolhash.py` over the regenerated `assist-cases.json`
  gives `local 13 tools 46b96562…2cd96cb6` and `mcp 32 tools 9bcc7eb7…9cef36f7`,
  identical before and after. Refusal sentences that go back to the model say
  "page", never "meeting". What the assistant calls a page in a club
  (`class_noun`) is the next section.

## "meeting" in a club: what the teacher reads, never what the model reads (#267)

A club says "meeting" (`class_noun: "meeting"`, [08](08-course-config-reference.md)).
The assistant says it back — in the plan cards, the one-line results, the
dates card, the answer to "When are my next meetings?" — and **the model is
never shown the word.** That is the whole design, and it is why this needed no
routing measurement: a routing change is a change to what the model reads, and
nothing the model reads moves.

**How the two audiences are kept apart.** `AssistToolOutcome` already had
them: `detail` goes to the model (and is the only thing `--mcp-stdio` returns
to Claude Code), while `summary`, `forTheCard` and `teacherDetail` are the
teacher's. Every sentence that says "class" and that a club teacher can reach
now takes a `noun:` (`ClassNoun`, default `.class`), and the runner renders it
TWICE where both audiences read the same text:

- A **plan** is built once with `.class` for `detail` and once in the course's
  noun for the card — `AssistToolOutcome.planned(_:plan:card:)`, and
  `describe(noun:)` on `ClassInsertionPlan`, `PlaceholderClassPlan`,
  `SectionReDatePlan` and `AssistPublishPlan`.
- A **write**'s `summary` takes the noun (`madeRoom`, `publishedTheClassOn`,
  `reDated`, `addedTheNextPage`); its `detail` is built as it always was.
- The **dates answer** ("When are my next meetings?") was one string for both;
  it is now two, `summary` in the noun and `detail` unchanged.
- The **window's own lines** — the dates card's question
  (`mayIAskForYourDates(for:)`), the reason under it, the answer to declining it
  (`datesNotGivenYet(for:)`, via `AssistAgent.noteDatesDeclined(noun:)`) — go
  into the transcript and never into `messages`. `AssistSession` reads the
  course's noun and naming once, when the window opens.

`ClubNounTests.testTheNounNeverReachesWhatTheModelReads` is the proof: six plan
tools run in one club with `class_noun` flipped between `class` and `meeting`,
and `detail` must be byte-identical while the card must change and say no
"class". Measured by putting the noun into the make-room plan's `detail` (copy
and restore of `AssistToolRunner.swift`): that test goes red, and so does the
`detail` check. The tool surface is hashed after regenerating the contracts
(twice, the second a no-op): `local 13 tools 46b96562…2cd96cb6`, `mcp 32 tools
9bcc7eb7…9cef36f7` — the baseline.

**Errors stay in the ordinary words, on purpose.** A refusal (`refused`,
`couldNotRead`) is ONE string for both audiences — the model reads it and
decides what to say next — so `notANumberedClassPage`,
`thePlaceForTheCopyIsStillTaken`, `theCopyCouldNotBeMadeHidden`, the planners'
"I don't know when … meets" and their `problems` lines keep their wording
(Russell's ruling on the plan review: error text fed back to the model stays
neutral). Splitting each into two strings would double a sentence set nobody
asked for, and a refusal is not what a club teacher reads most.

**Named, not substituted.** Every variant is its own key in
`contracts/assist-wording.json`: `<name>` for the "class" form and
`<name>ForAMeeting`, following `otherClassesWouldMove…`. 30 pairs; the file went
from 65 keys to 125 and **no existing value changed** (diffed). Sentences that
were typed inline in a planner or in `AssistToolRunner` moved into
`AssistWording` to get their names, so some "class" forms are keys for the
first time. `ClubNounTests.testEveryMeetingKeyHasItsClassTwin` holds every
`…ForAMeeting` key to having a twin, saying "meeting" and never "class" or
", Day ". REJECTED: a substitution function over finished sentences (it would
eat "classroom", a page title with "Class" in it, and "this class actually
meets", where "class" means the group — the meeting form says "this group");
free text for the noun (sentences carry articles and plurals).

**The inventory, and what was left and why.** Varied: the make-room plan and
result, the duplicate plan's "later meetings move", the next-page plan (and its
spare-dates and shared-last-day lines), the re-date plan and result, the
publish plans' "is a meeting of its own", "Published the meeting on …", the
dates answer, and the five reasons under the dates card. Left as "class":
refusals and planner `problems` (both audiences, above); `otherClassesMoved`
and the planners' own result messages (`detail` only — the teacher reads the
summary); the undo clauses ("added the class page Week 2"), because one stored
clause feeds both the undo's summary and its detail; the whole-unit sentences
(unreachable — a numbered course has no whole-unit path); plan summaries such as
"Worked out what making room in that unit would do." (a plan's transcript line
is its card, so the summary is shown nowhere); `remember_timetable`'s sentences
(MCP only, which returns `detail`); the "classes this deploy is meant to carry"
line (only when the MODEL passes `classes`, which no card does). The full table
is in the #267 hand-over.

**What still says "class" in a club, stated rather than hidden.** The model's
OWN prose: its inputs did not change, so when it answers in its own words it
may say "class". Claude Code over MCP likewise reads `detail`. Neither is a bug
to chase by editing the prompt — that would move a routing byte.

**The card phrasings and the shelf.** Matched in code, so they cost the router
nothing: every "class" fixed phrasing a club's shelf offers has a "meeting"
twin in `AssistCardCommand.fixedShapes` (publish tomorrow's / a weekday's
meeting, add the next meeting page, when are my next meetings, I have a revised
list of meeting dates — the sentence `datesNotGivenYet(for: .meeting)` tells a
club to say, and a test holds the two together — re-date my meetings), and two
new PARSED families, added beside the old ones so the entries Windows already
implements are byte-for-byte unchanged: "make room for <count>
class|classes|meeting|meetings at [<word>] <number>" and "duplicate <page title>
as my next meeting". **The one-number make-room family reads the window's
course**, the only family that does: `AssistCardCommand.matching(_:numberedPageWord:)`
is given the course's page word by `AssistAgent` (via
`AssistToolRunner.numberedPageWord(forCourse:)`) when, and only when, the course
is numbered, and the family matches that word (case-folded) or a bare number —
"at Week 5", "at 5" — and nothing else. The number goes into `unit`, which a
numbered course reads as its position. In a Unit/Day course the family matches
NOTHING, so "make room for a class at unit 3" and "at week 5" reach the model
exactly as they did before #267. The first version could not know the word and
took any single word except "day" and "unit": the #267 implementation review
measured "make room for a meeting at period 3" / "at block 2" / "at section 2"
planned in a club as Week 3 / Week 2 — pages renamed on a sentence about
something else — and in a Unit/Day course those sentences had stopped reaching
the model. REJECTED: a deny-list of words (period, block, section, lesson …),
which is the any-word rule with holes in it. `assist-cases.json` carries the
family with `inANumberedCourseWhosePagesAre: "Week"`, its near miss "at period
3", and three `nearMisses` that a runner walks both without a course and in a
club. A numbered course
gets its OWN shelf (`AssistPromptShelfView.groups(naming:noun:)`): every card
on it is matched in code except "Cancel scheduled deploy", which was already
measured. There is deliberately no "Publish Week 2" or "Unpublish Week 2" on
it — a title-bearing publish or hide goes to the model, and no routing
measurement has been made in a club course.

## The front page's embed is found by the page it names (#267)

`SectionIndexPointer` never reads or writes the heading above the embed, and
never INSERTS an embed into a front page that has none. It finds the first
line that transcludes one of the section's class pages — by title, after any
folder path and before any `|` or `#` — and replaces that line. So a course's
"# Most Recent Class", a club's "# Most Recent Meeting" (written once, at
creation, by `setup_course.py`) and CODING's hand-made "## Most Recent Meeting"
all repoint the same way, and an existing course keeps its heading. Nothing
here changed in behaviour; what changed is that it is now CONTRACT data,
`class-planning.json` → `sectionIndexPointer` (9 cases, run by
`ClassPlanningContractTests.testTheFrontPageIsRepointedAsTheContractSays`;
removing the class-title check turns it red).

**The date follows the embed, and a page with none keeps its own (#275,
2026-09-25).** `repointing` used to write the front page's `created` AFTER its
embed loop whether or not a class embed was found, so a hand-made front page
with no class on it was re-dated to the newest class on every assistant publish
(the contract case passed only because the test handed the pointer no date).
It now returns nil before the date step when no class embed was found — one
`Bool`, nothing else moves. Windows already behaved this way
(`AssistWorkspace.ApplyIndexChange` returns before dating when
`SectionIndex.WithMostRecent` finds nothing). Pinned by
`sectionIndexPointer.dateCases`, run through the pointer WITH the class's date
by `testTheFrontPagesDateFollowsTheClassItShows` — two failures on the old
pointer, by copy-and-restore. The same cases are run by the build, which dates
the front page on every build ([05](05-build-pipeline.md#dates-drive-everything)).

Windows differs, and the contract says how rather than pretending it does not:
`SectionIndex.cs` finds the embed by the literal heading "# Most Recent Class",
so a club's front page — or CODING's — is never repointed there, and it takes
the first `![[` under that heading whatever it names, so "Help Sessions" can be
replaced by a lesson. Those are the requests (the cases go red there). Where no
class embed exists at all, the two apps are allowed to differ, and both
behaviours are pinned (`whenNoClassIsTransclusion`, `expectBodyOnWindows`): the
mac leaves the page alone; Windows inserts the embed on the line after the
course's own heading (`front_page_heading`, absent → "Most Recent Class"),
which is its shipped behaviour widened to the course's heading. REJECTED:
making them match by breaking one — neither behaviour has cost a teacher
anything; REJECTED: having the pointer re-assert the heading (a one-off choice
turned into a fight with the teacher's own edits).

## Further reading in this repository

- [`09-mac-app.md`](09-mac-app.md) — the app the assistant lives in
- [`GUI-IMPROVEMENTS.md`](../GUI-IMPROVEMENTS.md) — every interface decision,
  with its reasoning
- `research/ai-assist/` — the raw measurement records behind every number here
- [`12-windows-app.md`](12-windows-app.md) — the Windows counterpart, which
  runs the same model natively with Vulkan


## What the `TEACHERS SAY:` phrasings were worth, and five traps in measuring it

Written on Windows, 2026-09-08, closing the phrasings half of
[issue #66](https://github.com/russellgordon/plantoir/issues/66). The numbers
and their conditions are in `research/ai-assist/teachers-say-results.txt`; this
is the reasoning, which is the half that does not fit in a results header. **The
traps are the part that travels — the mac meets four of them the moment it
measures anything.** Reference: `GUI-IMPROVEMENTS.md` row 457, branch
`issue/41-teachers-say-phrasings`.

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
3. **There are THREE interception layers before the model on WINDOWS, and
   ONE on the mac** — the trap is the same, the count is not, and the
   sentence here used to say "the mac's `AssistCardCommand.swift` has the
   same shape", which is false. On Windows: `PreviewAskedForPlainly`
   (thirteen exact sentences), `AssistCardCommand.Matching` (`FixedShapes`
   plus its parsers), and four inline regexes in `AssistAgent.CardCommand`
   itself. Three controls were sentences the app answers WITHOUT the model,
   so they measured nothing.

   **On the mac there is one layer and it is reached once**, at
   `AssistAgent.swift:172` — `AssistCardCommand.matching(trimmed)`, on the
   text BEFORE the dateline is appended, tidied by trimming whitespace,
   stripping leading and trailing `.` and `!`, and lower-casing, then
   compared by EQUALITY (never substring), followed by the parsed families —
   four when that was written, six today ("deploy at <time>" joined them on
   2026-09-19, #168; "hide" joined the existing unpublish family the same day
   rather than adding a seventh, #215) — and **nine** since 2026-09-25: #267
   added two for clubs, and "what does <page> link to?" is the ninth (#167).
   The plain-preview sentences are not a second layer here: "preview" and
   "rebuild the preview" are entries in `fixedShapes` like everything else.
   Corrected 2026-09-18 while measuring #117, which counted them rather than
   assuming, and re-counted 2026-09-19 after #215: of the 29 probes in
   `trimmed-surface-suite.py`, **six** are answered in code and never routed —

       card: publish tomorrow   -> publish_class_on
       card: unpublish by name  -> unpublish_pages
       card: check the section  -> check_section
       card: rebuild preview    -> rebuild_preview
       card: undo               -> undo_last_change
       card: deploy now         -> deploy_section

   all six of them promise-card phrasings — and since 2026-09-25 a seventh,
   `read -> read_page`, which is not a card: #167's probe names its own
   window's course and section, which the links family accepts, so the N a
   model sees is **22** from then on (the **23** a few lines down was true on
   its day). (It was five until #215 widened the
   unpublish family to take a class page, which took `card: unpublish by name`
   out of the routing measurement — and the run's own "promise-card, the N the
   model sees" line from 6 of 11 to 5 of 11.) The suite reports both totals
   (all 29 and the **23** a model actually sees) and finds that list from
   `contracts/assist-cases.json` rather than from a hand copy, so a phrasing
   added to the card table shows up in the next measurement by itself — which
   is how this one was re-counted rather than reasoned about. They
   are still measured, because Claude Code over MCP has no interception layer
   in front of it and does route them.
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
`research/ai-assist/teachers-say-suite.py`. The reasoning behind the two
surfaces diverging is under "The two MCP surfaces are not the same product",
above.

**Only some of a clause gap is a routing change, and the split decides the
work.** `AssistAgent.ForTheLocalModel` holds thirteen names. Of the seven tools
whose `TEACHERS SAY:` clause Windows was missing, only `add_next_class` and
`read_remembered_timetable` are in it — the rest are read by Claude Code over
MCP and by nothing else. `Briefly()` puts the clause FIRST in what the local
model reads, so those two are a change to the router's prompt and the others
are not. Ten phrasings needed measuring; ten did not.

**Do not start a Windows measurement from `tools-from-contract.py`.** The
contract is generated on the mac, so its descriptions are the mac's. Dump the
live surface with `dump-tools.ps1` and narrow it with `narrow-tools.py`. That
file and `routing-suite.py` now say so; they used to say the opposite.

**Two things the mac owes from this, and they are issues rather than lines
here:** [#113](https://github.com/russellgordon/plantoir/issues/113)
(`check_section`'s fourth trigger phrasing, the last clause difference between
the two MCP surfaces) and
[#114](https://github.com/russellgordon/plantoir/issues/114) (the two servers'
tool descriptions differing in the sentence the router reads, and
`unpublish_pages` describing different behaviour — two descriptions of one
behaviour, or two behaviours?).

---

[◀ Previous: The macOS App](09-mac-app.md) · [Back to index](README.md) · [Next: Release Strategy ▶](11-release-strategy.md)
## One feature that is deliberately NOT on any tool surface

"Copy a Page from This Course…" (issue #207) copies one page of one course into
another, with its pictures and the pages it links to. It is reached from the
sidebar's context menu and from nowhere else: **no MCP tool, no local-assistant
tool, no tool-surface change at all.**

Russell's decision, and the reason is the one this page already makes
elsewhere: adding a tool is a routing change, and more choices is the classic
way a router degrades. The feature is deterministic code — every rule in it
would behave identically if the model were replaced by a dropdown menu — so
there is nothing for a model to decide that the three questions on the sheet do
not already ask.

Written here so nobody adds it later thinking it was an oversight. The check
that it stayed off is structural rather than a promise: no generated contract
moved with the feature, so `assist-wording.json` and `assist-cases.json` cannot
disagree with the Swift, and `--write-contracts` is not owed by it.

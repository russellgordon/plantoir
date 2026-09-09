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

### The dateline, and why its position is a finding

A model has no clock. Every message the teacher sends therefore carries
`(Today is 2026-08-15, a Saturday.)` — **appended**, never prepended. That is
not a style choice: prepending the same sentence cost 15 points of routing
accuracy in measurement, and the effect reproduced on a second model. A line
of context at the front appears to compete with the instruction for the
model's attention; at the back it reads as a footnote to a request already
understood.

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
the OpenAI convention, and it is parsed in `AssistAgent`. A small model
occasionally emits arguments that do not parse; that is treated as "no call
was made" rather than guessed at.

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

- **Publishing** a page always publishes what it links to. There is no
  `includeLinked` flag for the model to decide about, because a class page
  whose linked notes are invisible is broken, always.
- **Unpublishing** is deliberately *not* the mirror image. A linked page comes
  down only when the pages being taken down are the **only** ones that link to
  it — otherwise hiding this week's lesson would strip a page last week's
  lesson still points at. Three kinds of page never come down this way
  whatever the link count: a folder's landing page, anything in the section's
  Key Links, and any curriculum page, each of which is reached from somewhere
  other than a lesson.

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

### No booleans, and separate verbs

There is no single `set_visibility(publish: true/false)` tool. Publishing and
unpublishing are **separate verbs** with separate names, because a boolean is
a coin flip under pressure and a verb is not — which is precisely the failure
that vetoed both 3B models.

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

So the agent overwrites both arguments with the window's own before anything
runs. It cannot cost routing accuracy, because it changes nothing the model
reads — only what is done with what it said.

**Do this in the agent, not in the tool.** The same tools answer Claude Code
over MCP, where the course and section genuinely ARE the caller's to choose.
It is the window that is about one section, so the window is what binds them.

Worth a sweep of your own surface for the same shape: any argument the
surrounding context already determines should be overwritten on the way in
rather than described more carefully in a schema.

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
| `use_skeleton` | Whether a course with no ready-made payload starts from its subject's skeleton — folders that suit the subject, four units of class pages to rename, placeholders saying what belongs where — or from nothing at all. |
| `prepopulate_example_content` | Whether one of the 38 ready-made courses is poured in. |
| `include_curriculum_pages` | Whether that payload's Curriculum folder comes with it. |

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

The mac writes each of these as `capabilityExists && teacherSaidYes` —
`hasSkeleton(code) && startsFromSkeleton` — so a stale `true` in an old config
can never mean anything.

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
| `contracts/assist-wording.json` | Every sentence the assistant says to a teacher — nineteen, with `{course}` and `{section}` where values go. |
| `contracts/assist-cases.json` | The nine phrasings matched in code, the four near misses that must NOT match, the three tool lists with approvals and plan twins, **the full tool SCHEMAS as a client sends them**, eight scenarios as `given` / `when` / `expectEvents` / `expectReply`, and the arrow-key prompt history. |
| `contracts/app-rules.json` | Launcher arguments per configuration, the validation a teacher reads, failure output turned into a sentence, whether a deploy must build first, the progress markers and where each one's text comes from, the preview's ports. |
| `contracts/schedule-rules.json` | Every accepted date form, how an ambiguous `08/09/2026` column is settled or asked about, what a pasted Google Sheet address becomes. |
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

**Four things to know before you use them.**

- **Never hand-edit the GENERATED keys** — `cardPhrasings`, `tools`,
  `milestones`. Those are readouts of mac code; the next regeneration
  overwrites your edit and the diff looks like vandalism.
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
assistant, while the 37 live in `PlantoirTools`. Its `mcpOnly` third compares
the contract against three names typed inline in the test file. Twelve
additions went through that gap without a single red test.

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
both wired up already). Note the limit: `duplicate` is not on
`add_next_class`' published schema at all, only on the hardcoded card phrasing
`AssistCardCommand.swift:85`, so no model and no MCP client can reach it — the
mac needs a schema argument, not just a bigger count. And `roll_over_section`
because of the defect in item 41's first open part. Two are
Windows-shaped and stay there: `read_timetable`, because the mac puts
spreadsheet reading behind its schedule sheet on purpose and has no file-path
argument anywhere on its surface; and `list_recent_changes`, because both mac
clients already show or hold that history. `sync_page_dates` needs a teacher's
problem first — the mac has no engine for it AND nothing on the mac reports
the date drift it fixes, because the mac has no equivalent of your `DateAudit`.
The three `plan_` twins travel with their writes and are not separate
decisions.

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
- **The question.** "Shall I go ahead?" / "Shall I deploy?" is its own
  message, which is what lets the card below be nothing but buttons.
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
  per course. A teacher's backup is a decision — they pressed Back Up because
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

The section folder is emptied and refilled rather than swapped, for the same
reason `restoreBackup` documents: Obsidian holds the folder open.

**Say the surprising part in the confirmation, not in a doc.** Anything the
teacher changed in that section during the conversation goes back too,
including work done in Obsidian, and Plantoir cannot bring that part back.
That sentence belongs in the alert.

---




---

## Further reading in this repository

- [`09-mac-app.md`](09-mac-app.md) — the app the assistant lives in
- [`GUI-IMPROVEMENTS.md`](../GUI-IMPROVEMENTS.md) — every interface decision,
  with its reasoning
- `research/ai-assist/` — the raw measurement records behind every number here
- [`12-windows-app.md`](12-windows-app.md) — the Windows counterpart, which
  runs the same model natively with Vulkan


---

[◀ Previous: The macOS App](09-mac-app.md) · [Back to index](README.md) · [Next: Release Strategy ▶](11-release-strategy.md)
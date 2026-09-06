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

Claude Code is offered a **longer** list than the local model: 23 tools
against 13 — the twenty that exist, plus three served only over MCP. The extra ones ask for judgement about meaning — reading the
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

## Further reading in this repository

- [`09-mac-app.md`](09-mac-app.md) — the app the assistant lives in
- [`GUI-IMPROVEMENTS.md`](../GUI-IMPROVEMENTS.md) — every interface decision,
  with its reasoning
- [`WINDOWS-HANDOFF.md`](../WINDOWS-HANDOFF.md) — the same design written for
  the team building the Windows counterpart
- `research/ai-assist/` — the raw measurement records behind every number here

---

[◀ Previous: The macOS App](09-mac-app.md) · [Back to index](README.md)

# plantoir-mcp

An [MCP](https://modelcontextprotocol.io) server that exposes one Plantoir
working folder to an AI assistant, so a teacher can say *"publish tomorrow's
class — Unit 2, Day 3 in ICS3U section 1 — and everything it links to"* and
have it happen, after confirming a plain-words summary of what will change.

It holds no AI model of its own: it is the tool surface, driven from two items
on a course's context menu (`Plantoir/Views/SidebarPane.xaml.cs`) — **Revise
with Claude…**, which launches Claude Code and appears only when Claude Code
and this server are both present, and **Revise with local AI assistant…**,
Plantoir's own assistant, which starts this same binary as a subprocess
(`Plantoir/Services/McpClient.cs`). A change here reaches both.

**Status: on `main`, and it ships** — `publish.ps1` publishes this project,
copies `plantoir-mcp.exe` into the app's output beside `Plantoir.exe`, and
signs it with the rest.

## Running it standalone

```powershell
plantoir-mcp --folder "C:\Users\me\Documents\Teaching" --course ICS3U
```

`PLANTOIR_FOLDER` and `PLANTOIR_COURSE` work instead of the flags. The folder
is fixed at startup and never changes — a server that could be re-pointed
mid-session would make every path check meaningless. `--course` locks the
session to one course: every other one becomes invisible, and naming one is
refused with the reason. Plantoir always passes it, because a lock holds
however the conversation wanders and an instruction in a prompt does not.
**stdout belongs to the protocol**: logging goes to stderr
(`LogToStandardErrorThreshold` in `Program.cs`), and one stray
`Console.WriteLine` corrupts the session for the client.

No config file is needed for either menu item — `ClaudeCodeLauncher.cs` writes
`%LOCALAPPDATA%\Plantoir\assist\mcp-<CODE>.json` itself and passes
`--mcp-config … --strict-mcp-config`, so a teacher's own MCP servers are
neither used nor disturbed and no `.mcp.json` lands in the vault Obsidian
watches. Write a config by hand only to point some *other* client at the
server: one `mcpServers` entry, `command` the exe, `args` the same
`--folder` (and optionally `--course`) shown above.

## The tools

**They are defined in [`PlantoirTools.cs`](PlantoirTools.cs) — read them
there.** Their `[Description]` strings are *measured text*: routing accuracy
was counted against that exact wording, so the code is the single authority
and this file deliberately does not paraphrase it. One distinction belongs
outside the code, because having it backwards is the expensive mistake:
`publish_pages` and `unpublish_pages` rebuild the section **preview**, and
only `deploy_section` reaches students.

## Why the surface looks like this

Measurements in [`research/ai-assist/HISTORY.md`](../../research/ai-assist/HISTORY.md).
**The tools do the work and the assistant only picks one**: given fine-grained
tools, a small model asked to publish a class "and everything it links to"
skipped the link resolution 8 times out of 8; given one coarse tool that
resolves links itself, 8 out of 8 right. So link resolution, the backup and
the rebuild are **one** operation, and:

- **Publishing and unpublishing are separate verbs, not one tool with a
  flag.** The one dangerous failure observed was polarity inversion: asked to
  hide a page the model published it, with the (since removed) `includeLinked`
  flag set — then got the same prompt right on a rerun, which is worse than a
  deterministic bug.
- **There is no delete, archive, rename or overwrite tool, and that is the
  point.** The model declined "delete the Unit 1 folder" not from judgement
  but because it had no tool for it. Absence is the strongest guardrail there
  is; please keep it.
- **Every write backs the course up first**, from inside the write itself,
  aborting if the backup fails — `courses/` is line 1 of the `.gitignore`, so
  there is no `git checkout` undo. **And every write has a `plan_` twin that
  changes nothing**, whose output is written to be read aloud.
- **Publishing follows two hops, hiding one.** A class links to a concept and
  the concept to its expectations, so one hop would leave a visible page
  pointing at a hidden one — 42 pages sat two or three hops out in the sample
  course. Hiding stops at one hop and spares any page a still-visible class
  uses: publishing records no owner, so hiding cannot be a true inverse, but
  it can refuse to break anything still in use.
- **There is no `includeLinked` at all, since #420 (2026-10-01)**: publishing
  ALWAYS takes what a page links to (stopping at a class), and hiding always
  takes a page only the hidden pages link to — `contracts/shared-rules.json` →
  `followingLinks`, the same as the mac, which removed the flag because it
  asked the MODEL how far a publish should reach. It had defaulted to false on
  Windows, so a call that left it out published a page whose links led to
  pages students could not see. (Before that it had defaulted one way for
  publishing and the other for hiding.) A client that still sends the key is
  harmless: the SDK's binder drops an argument a tool does not declare.
  "Publishing follows two hops, hiding one" above is older than both and is
  kept for its reasoning; the rule today is the contract's: transitive, with
  one stop.

## Frontmatter: which key

Visibility is **`publish:`** on a page under `section<N>/` and
**`publishForSection<N>:`** on a course-level page the build copies into every
section — which is what lets one page be visible in section 1 and not
section 2. `true` means visible; the legacy `draft:` / `draftSection<N>:`
spellings carry the opposite polarity and are still read, inverted, but never
written. `PagePaths.SectionOf` decides which kind of page it is from the
layout on disk and `PageFrontmatter.PublishKeyFor` turns that into a key,
never anything the caller claims.

## The lease protocol, in both directions

Plantoir and this server are separate processes, and both build into
`.merged_output/section<N>/`, **which the build CLEARS before writing it** —
so the loser of a race serves a half-written site. Both sides write what they
are doing and read what the other is doing: files under
`courses/.internal/activity/` named `<COURSE>.<kind>.<pid>.lease`, carrying
the owner's pid and process name. `WorkLease.cs` defines four kinds:
`assist`, `preview`, `publish` and `build`.

| Situation | What happens |
|---|---|
| An assistant holds the course (`assist`) | Structural work in the app declines: Add Section, restoring a backup, starting a second assistant. **Preview and Deploy carry on.** |
| Plantoir holds `build` | This server's write tools decline (`RefuseIfPlantoirIsBuilding`, `AssistWorkspace.cs`) |
| This server holds `build` | The app's Preview and Deploy stand off for the seconds it runs |
| Either, on a **different** course | nothing is blocked |
| Reading, planning, editing frontmatter | always allowed |

Only *building* is exclusive, and an assist session is not a build: previewing
**during** a conversation is the point of the assistant, not a conflict with
it, and a preview lease lasts as long as the preview server runs. Staleness
needs no cleanup pass and no timeout — a lease whose process is gone is not a
lease, the process *name* is checked so a recycled pid cannot impersonate a
dead one, and a process never counts its own leases.

## Known limits, and notes for anyone changing this

- **Cloudflare courses cannot be deployed from here**: a Pages-scoped token
  cannot list its own account, so the account ID lives in Plantoir's settings
  and the server points at the app. Netlify and folder publishing work.
- **stdin is closed for launcher runs on purpose.** `deploy.ps1` prompts for a
  token it cannot find, and a prompt nobody can answer would hang the call
  while the assistant reports "still working". At EOF it fails at once and the
  server can say the useful thing: publish from Plantoir once, so the token
  gets stored. A build also needs Docker and takes minutes.
- **SDK traps.** `Destructive` defaults to `true` — set it explicitly. A
  parameter is optional only if it has a C# default value (`string? x` without
  `= null` still throws at call time). Progress comes from an
  `IProgress<ProgressNotificationValue>` parameter, never from MCP logging
  notifications, deprecated as of spec 2026-07-28. Tool classes are built per
  invocation, so state belongs in the injected `AssistWorkspace`, and the
  stdio transport exits when stdin closes.

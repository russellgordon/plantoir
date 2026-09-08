# A folder rename to a name containing a space breaks every Markdown link into it

Rank: 1 of 18 — the most serious on the list. It corrupts a teacher's own pages.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Contract cases waiting on the mac", the FIRST item in that
section (search for "a folder rename breaks Markdown links"). Windows found and
fixed this on 2026-09-06 and proposed five contract cases for the mac.

## The defect, confirmed in code
`mac-app/QuartzTeachers/Models/FolderPathRewriter.swift`, in
`encoded(_:likeThe:)` (around line 261):

    let wasEncoded: Bool = segment.contains("%") && segment.removingPercentEncoding != segment
    if !wasEncoded {
        return name
    }

The rule is "encode the new name if the OLD segment was encoded". That is the
obvious rule and it is wrong, because a Markdown link destination ends at the
first SPACE. Renaming `Tasks` to `All Tasks` turns

    [q](Tasks/Quiz%201.md)   into   [q](All Tasks/Quiz%201.md)

which neither Obsidian nor Quartz can follow. The old segment `Tasks` has no
`%` in it, so `wasEncoded` is false and the new name goes in plain — the `%20`
in the example belongs to the FILE name, which is what makes this easy to miss
by eye. Every Markdown-style link into that folder breaks, in the teacher's own
pages, and nothing tells them.

## The rule Windows adopted, and why
**In a Markdown link, escape when the NEW name needs it — whitespace or
brackets — whatever the old segment looked like. In a WIKILINK, keep the plain
spelling.** The wikilink half is not an oversight: `[[All Tasks/Quiz 1]]` is
exactly how Obsidian writes a wikilink containing a space, so escaping there
would be the mirror-image mistake.

## What done looks like
- The Swift rule matches the sentence above, for both link styles.
- The five cases proposed in `MAC-HANDOFF.md` are implemented as contract
  cases. **Choosing the contract file is yours and you do not need to ask** —
  Windows could not choose, because only the mac regenerates, and
  `class-planning.json` has no rewriter block today. A new top-level key is
  acceptable if it is the honest home. Justify the choice in the handoff, and
  confirm by reading the generator that an authored key of that shape survives
  `--write-contracts` before relying on it.
- A mac test deserialises those cases and runs them. Today
  `FolderPathRewriterTests.swift` has one encoding test and it starts from an
  already-encoded segment, so it cannot see this.
- `MAC-HANDOFF.md`'s waiting line is removed and the ledger entry marked done.

## Cautions
- Check what else calls the rewriter before changing its contract.
- A rename that is interrupted partway has its own existing handling — do not
  regress it.

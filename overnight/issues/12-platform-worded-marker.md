# Sentences that say "on your Mac" have no marker saying they are platform-worded

Rank: 12 of 18.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes" (search for
`platformWorded`). Windows needs to know which contract sentences they must
reword for Windows and which they must copy character for character.

## The problem
The contract carries sentences containing "on your Mac". Windows cannot ship
those verbatim, and today nothing in the data says which sentences are in that
category — so a Windows session either reads every sentence looking for the
word, or ships one wrong.

## What the handoff got incomplete
It names two sentences in `contracts/shared-rules.json` (around lines 1444 and
1459). **There is at least a third** — a `message` around line 1483 containing
"stays on your Mac" — which the entry does not list. Search the whole
`contracts/` tree for platform words rather than trusting the two it names;
"Mac", "macOS", "Finder", "Dock", "Windows", "Explorer" and "File Explorer" are
all candidates. Report what you actually found.

## What done looks like
- A `platformWorded` marker (or whatever shape you justify) on every sentence
  that is platform-specific, applied across `contracts/`, not just in the one
  file the entry mentions.
- A mac test that fails when a new sentence containing a platform word is added
  without the marker — otherwise this decays immediately and somebody redoes
  this session in a month.
- The convention documented in `contracts/README.md` and in
  `WINDOWS-HANDOFF.md`, saying what Windows should DO with a marked sentence.

## Caution
`shared-rules.json` is hand-authored; other contract files are generated from
Swift. Check which is which before editing — an edit to a generated file is
erased by the next `--write-contracts`, and that failure is invisible until it
bites.

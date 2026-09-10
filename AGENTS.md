# Plantoir — instructions for agents

The instructions for this repository are in **[CLAUDE.md](CLAUDE.md)** at the
repository root: the rules that override default behaviour, the traps that cost
real time, and a map of where everything else lives. **Read that file before
doing anything here.**

This file is a pointer and nothing else. It carries no rules of its own on
purpose: a second copy of the rules is a second copy to keep in step, and the
generated copy that used to live in `.agents/rules/` went stale exactly that
way before it was retired.

Machine-wide instructions — the Swift coding style — live outside this
repository, in `~/.claude/CLAUDE.md`. **They are configured on the Mac only,
and that is fine.** They govern Swift, so a session working in `windows-app/`
is not missing anything that binds it; see rule 8, which says so in full.

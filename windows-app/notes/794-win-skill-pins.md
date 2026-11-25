# #794, #795, #796, #798: Windows reads the guidance-skill pins from the contract

## Must-fail lines

One scratch commit (`70ffc8642` on a local branch `scratch/794-mustfail`, never pushed), all breaks at once, each producing its own line; run on VM B, `AgentGuidanceTests` 7 failed of 30. Messages as printed:

- **#794 (a) the walk folds nothing** (`Says` became a plain `Contains`): `.claude: plantoir-test-authoring must say A question on something the class did not do is removed` (that pin spans a line break in its skill), with every other wrapped pin in both homes. The theory failed on its three matching rows too (`Assert.Equal() Failure: Values differ`); its changed-word row passes either way, as it should.
- **#794 (b) the held check dropped:** `.claude: mustSay names plantoir-marking, and no such skill is written`, the same for `.agents` and for `plantoir-report-comments`.
- **#794 (c) a misspelled key in a copied contract** (`DeepClone`, scratch key `plantoir-handuots`): `.claude: mustSay names plantoir-handuots, and no such skill is written` (and `.agents`).
- **#795** (`\newcommand{\qpart}` line removed from the written `.claude` `starters/Quiz.tex` after `Write`): `.claude: starters/Quiz.tex must define \qpart`.
- **#796 count** (a second copy of the template's name appended to the written `.agents` handouts `SKILL.md`): `.agents: plantoir-handouts must name the template Lessons students can catch up on exactly once, and names it 2 times`.
- **#796 hints** (`\showhints` removed from the written `.claude` hints starter): `.claude: starters/Handout - Hints.tex must define \showhints`.
- **#798 template** (`templates/Marking Kit/answers.json` deleted from `.agents` after `Write`): `.agents: templates/Marking Kit/answers.json must be written beside the skill`.
- **#798 old phrase** (written `CLAUDE.md` given back "a quiz or test for marks"): `CLAUDE.md: a unit test is no longer the handouts skill's`.

Logs: `vm-tools/runs/794-vm-turn1.log`.

## #798 measured

Second VM (Windows 11 ARM64, Plantoir `win-x64` under emulation), 2026-11-21 02:50, `e2bb8ff5d`, in a scratch folder under `%TEMP%`. Log: `vm-tools/runs/794-vm-turn2.log`; script `vm-tools/guest/798-measure.ps1`.

- **The Write:** a throwaway console program referencing `Plantoir.Core` called `AgentGuidance.Write(support\agent_guidance, <scratch>\Working Folder)`: 0 failures, 17.6 s (build included); `.agents\skills\plantoir-test-authoring\SKILL.md` present.
- **(a) `check_kit.py`,** from the working folder: `python -B .agents\skills\plantoir-test-authoring\scripts\check_kit.py ".agents\skills\plantoir-test-authoring\templates\Marking Kit\answers.json"`. Works with `python` (Python 3.14.10 from python.org, on PATH), `py` (the launcher, the same 3.14.10) and the fetched runtime's own Python (`python\python.exe` under the app's runtime folder, 3.14.10): each exit 0 in 0.6 to 1.0 s, printing `OK: the kit; 16 points (K 4, T 6, C 3, A 3), versions A, B` and `Only keys were checked for names: a name typed inside a value (a note, what was seen, a sentence) is not something this script can find.` `python3` is the Microsoft Store alias: exit 9009, "Python was not found; run without arguments to install from the Microsoft Store…". So the skill's `python3` line does not run on stock Windows; its "`python` or `py` on Windows" note is the command that works.
- **(b) `check_answers.py`,** from a test folder made by copying the skill's `templates` folder (so `Checks\` and `Marking Kit\` are siblings): `python -B Checks\check_answers.py`. Exit 0 in 0.2 s with `python`, `py` and the runtime's Python, printing `OK: every computed answer in versions A, B matches answers.json`; `python3` exit 9009 as above.
- **(c) Tectonic:** `tectonic-0.17.0-x86_64-pc-windows-msvc.zip` downloaded from GitHub's release `tectonic@0.17.0` in 0.7 s, 21,060,223 bytes, SHA-256 equal to GitHub's digest `f61ce51f0b0ade1015b7de7ef368541c5424e9756ecbd0d7af97d6d48030845f`; unpacked with `System.IO.Compression` in the scratch folder, nothing installed, PATH unchanged, `TECTONIC_CACHE_DIR` set to an empty scratch folder for the process. `tectonic.exe -X compile "Marking Guide.tex"` in the copied test folder: exit 0, `Marking Guide.pdf` written (40 KiB), first run 77.7 s with an empty cache (it downloaded the bundle's files, `nicematrix` and `mhchem` among them, with no error), second run 6.0 s.
- **Not clean:** the script's own removal of the scratch folder was refused for `tectonic.exe` ("Access to the path 'tectonic.exe' is denied", probably a scan still holding it a moment after the compile). The VM was then returned to its dev snapshot and suspended, which discards the folder; nothing was left on the running machine. The removal was not retried, so whether a short wait would have freed it is not measured.

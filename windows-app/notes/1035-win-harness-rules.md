# #1035: the harness's key rules run in the merge gate

## For PROGRESS

- **#1035 (2026-11-21): `HarnessSourceRuleTests` moved from `Plantoir.UiTests` to `Plantoir.Tests`**, so the merge gate (which builds and runs `Plantoir.Tests` only; read from `C:\vm-setup\win-suite-int-d4.ps1`) now runs the key rules. On `dev` 41f30f5c6 two of them had been failing unseen: `StopByKeyboardUiTests.AHeldEscapeOpensTheQuestion_AndItsRepeatsDoNotAnswerIt` sent a bare key-down Escape (#1009), and `MenuBarUiTests.CopyAPageAnswersCtrlShiftK` named `KEY_K`, not watched (#990).
- The rule tests read the UI test sources from `windows-app/Plantoir.UiTests` and the watched keys from `HeldKeys.cs`'s own `Watched` array, so there is one copy of each. `Plantoir.Tests` is plain `net9.0` and cannot load FlaUI, so keys are compared by NAME: the three `VirtualKeyShort.ENTER` in the UI tests are now `RETURN` (the same key, 0x0D), the spelling `Watched` uses. A new test file `TheWatchedListIsReadFromHeldKeys` pins that the list is really read.
- The held-key imitation (several key-downs, one key-up) is now one helper, `HeldKeys.HoldWithRepeats(key, firstDelayMs, repeats, repeatMs, whileHeld)`, with its release in a `finally`; it is the one method on the rule's allowed list (it replaces `PageTablesUiTests.HeldSpace` there, which now calls it). `StopByKeyboardUiTests`' held Escape calls it too, so a failing step can no longer leave Escape down. `KEY_K` is in `HeldKeys.Watched`.
- `TheHeldKeyMessageNamesTheTestsAndTheFix` stays in the UI project, in `HeldKeysMessageTests.cs` (it tests `HeldKeys` itself, not the sources).
- Proved on VM B (see the must-fail lines below).

Must-fail (scratch commit db41c4f50, never pushed: `KEY_K` taken out of `Watched`, a bare `Keyboard.Press(VirtualKeyShort.ESCAPE)` put back in `StopByKeyboardUiTests`, the helper's `finally` turned into a `catch`):

```text wrap
VM B, fixed 4352d97a7: HarnessSourceRuleTests (Plantoir.Tests, run-tests.ps1 -Filter) Passed 5 of 5.
VM B, fixed 4352d97a7: StopByKeyboardUiTests + MenuBarUiTests + PageTablesUiTests + HeldKeysMessageTests: PASSED - 18 passed, 0 skipped, 18 total (10 m 54 s).
VM B, broken db41c4f50: Failed 3, Passed 2:
Failed Plantoir.Tests.HarnessSourceRuleTests.EveryKeyATestNamesIsWatched: HeldKeys.Watched does not watch these keys a test names (add the key there, spelled the same way): KEY_K (MenuBarUiTests.cs:478)
Failed Plantoir.Tests.HarnessSourceRuleTests.NoTestSendsAKeyDownWithNoKeyUp: These send a key DOWN and never UP ... StopByKeyboardUiTests.cs:424 (in AHeldEscapeOpensTheQuestion_AndItsRepeatsDoNotAnswerIt)
Failed Plantoir.Tests.HarnessSourceRuleTests.TheAllowedMethodStillReleasesItsKey: Assert.Contains() Failure: Not found: "finally { Keyboard.Release("
```
Logs: `vm-tools/runs/1035/prove.log`, `vm-tools/runs/1035/prove-ui.log`.

## For documentation 12

In "Driving the real interface", the paragraph "It is opt-in and belongs to no gate": `HarnessSourceRuleTests` is no longer in the UI project. Replace "and `HarnessSourceRuleTests`, five more that keep a bare key-down, a discarded `Keyboard.Pressing` and an unwatched key out of the sources (#638)" with: "(the key rules that keep a bare key-down, a discarded `Keyboard.Pressing` and an unwatched key out of these sources, `HarnessSourceRuleTests` (#638), live in `Plantoir.Tests` since #1035, so the merge gate runs them: in this project they failed on `dev` for days with nobody seeing it)".

In the #638 bullets: replace the `HarnessSourceRuleTests` bullet with: "**`HarnessSourceRuleTests`** (in `Plantoir.Tests`, plain facts reading `windows-app/Plantoir.UiTests/*.cs`) fails on any `Keyboard.Press(` in the UI test sources. The one exception, allowed by name, is `HeldKeys.HoldWithRepeats`, which imitates auto-repeat (one down, more downs after the repeat delay, one up in a `finally`) and must keep its release; every held-key imitation calls it (`PageTablesUiTests.HeldSpace`, `StopByKeyboardUiTests`' held Escape). It also fails on a key a test names that `HeldKeys.Watched` does not list, comparing by name because the unit project cannot load FlaUI: spell a key as `Watched` does (`RETURN`, not `ENTER`)."

Outside `windows-app/` and so not changed here (for the director): `CLAUDE.md`'s testing table ("only `AssertAbsentRuleTests` and `HarnessSourceRuleTests`, eight plain facts") and `run-ui-tests.ps1`'s header comment (line 18) still say the key rules run as plain facts in the UI project. The UI project's plain facts are now `AssertAbsentRuleTests` (three) and `HeldKeysMessageTests` (one).

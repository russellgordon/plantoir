# #955: Windows reads a section's custom domain by `customDomainReading`

## Must-fail lines

Script `vm-tools/guest/955-mustfail.ps1 -Break address|emptytarget`: it edits `CourseConfiguration.cs` in VM B's checkout (never committed), runs `CourseConfigurationTests.ACustomDomainIsReadTheContractsWay` alone, restores the file with `git checkout` (0 changed files after each), at 8ab7253db.

- **Before the change** (13f960f3a, the test alone on `dev`'s reader): `2 of 17 customDomainReading cases read wrongly: the older bare string, a folder primary: the folder has no address (#904): expected "", read "ics3u.school.ca" | a folder never has a domain, even one written under its name: expected "", read "ics3u.school.ca"`.
- **(a) the address check removed** (the `DestinationTypesWithAnAddress` line replaced by a comment): the same two cases, the same message as before the change: `2 of 17 customDomainReading cases read wrongly: the older bare string, a folder primary: the folder has no address (#904): expected "", read "ics3u.school.ca" | a folder never has a domain, even one written under its name: expected "", read "ics3u.school.ca"`.
- **(b) `DeployTarget`'s empty-to-Netlify fallback bypassed** (`destinationType == DeployTarget` became `destinationType == StringValue("deploy_target")`): `2 of 17 customDomainReading cases read wrongly: the older bare string, no deploy_target: Netlify is the primary: expected "ics3u.school.ca", read "" | the older bare string, an EMPTY deploy_target: Netlify is the primary, as when the key is absent: expected "ics3u.school.ca", read ""` (case 6 named, and case 5, since a raw read of an absent key is empty too).

## Runs (VM B)

- 8ab7253db: `CourseConfigurationTests`, `ContractTests` and `UndoWriterScanTests` (the filter `~ContractTests` also took in every `*ContractTests` class): 1453 passed, 1 failed of 1454, the failure `PublishAndLauncherContractTests.EveryQuestionTheMacDeployLauncherAsksIsGuardedAtTheTopLevel`, on the known VM-only list (plantoir-machines skill), unrelated. App build (Debug x64) exit 0, 0 errors; UI test project build exit 0, 0 errors.
- 5164aa1d0 (after merging `origin/dev` 66c9853a8), the three classes by exact name: 75 passed of 75. App build exit 0, 0 errors; UI test project build exit 0, 0 errors.
- Scripts: `vm-tools/guest/955-mustfail.ps1`, `955-failtext.ps1`, `955-busy.ps1`.

## Self-check

1. Broke each fix and watched the test fail: (a) and (b) above, each failing message recorded.
2. No timed waits: none added.
3. Failure paths: a folder leg now gets no domain; its link and deploy line show the folder path, never a domain (see "For PROGRESS"). No sentence names anything moved or renamed.
4. `dev` merged in: 45be52fbf before proving (the branch was made from it), 66c9853a8 before hand-back.
5. Nothing tuned.
6. The cases are read from `contracts/file-formats.json` through `ContractLoader`; no case, value or domain typed in the test; nothing outside the brief changed (`mac-app/`, `contracts/`, `scripts/`, `support/` untouched).

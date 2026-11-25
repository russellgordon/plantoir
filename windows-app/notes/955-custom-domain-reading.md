# #955: Windows reads a section's custom domain by `customDomainReading`

## For PROGRESS

- #955: `CourseConfiguration.CustomDomain(section, destinationType)` now runs every case of `contracts/file-formats.json` → `customDomainReading` (17 cases, read from the JSON at run time by `CourseConfigurationTests.ACustomDomainIsReadTheContractsWay`, the mirror of the Mac's `FileFormatsContractTests.testACustomDomainIsReadTheContractsWay`). New `CourseConfiguration.DestinationTypesWithAnAddress` (`netlify`, `cloudflare_pages`, the Mac's and the Python's list, same order); the reader returns `""` first for any other type, so `local_folder` never has a domain. Before the change cases 8 ("the older bare string, a folder primary: the folder has no address (#904)") and 10 ("a folder never has a domain, even one written under its name") failed, both reading `ics3u.school.ca`; the other 15, case 6 (empty `deploy_target`) included, already passed, case 6 through `DeployTarget`'s getter.
- Not built, on purpose: `SetCustomDomain` can still carry an old bare string into a `local_folder` map entry when the primary is a folder (the Mac does the same); the reader now ignores that entry, so nothing a teacher sees follows from it.
- Not changed: `CourseSettingsView.xaml.cs` (about line 1053) filters `d.Type != "local_folder"` for the domain fields; it could ask `CourseConfiguration.DestinationTypesWithAnAddress` instead, so GitHub Pages (#669) is picked up when it joins the list. An interface file, outside #955.
- What a folder leg shows now: `MultiDestinationDeployRunner` asks `CustomDomain(section, "local_folder")`, gets `""`, and sets the folder runner's `CustomDomainForLinks` to null, so its link is the folder path (`ScriptRunner.PublishedFolder`), never a domain; before, a folder-primary course with an old bare string or a `local_folder` map entry had that domain on the folder runner (it reached a link only if the folder's transcript held a site URL, which a folder publish does not print).

## For documentation 12

The Windows reader of a section's custom domain, `CourseConfiguration.CustomDomain(section, destinationType)`, now runs `contracts/file-formats.json` → `customDomainReading`'s cases (`CourseConfigurationTests.ACustomDomainIsReadTheContractsWay`), as the Mac's `customDomain(forSection:destinationType:)` and the shared Python's `custom_domains.for_destination` do: a map gives the destination type's own string; the older bare string is the primary's only (`DeployTarget`, Netlify when `deploy_target` is absent or empty); a type outside `CourseConfiguration.DestinationTypesWithAnAddress` (today `local_folder`) never has a domain, whatever is stored; any other shape is no domain, never an exception (#955, after the Mac's #904).

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

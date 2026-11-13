using System;
using System.Collections.Generic;
using System.Linq;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Things the shared contract names that this app has not built yet, each one
/// NAMED, each one owned by an open issue milestoned for a LATER release than
/// the one being cut.
/// </summary>
/// <remarks>
/// <para><b>What it does.</b> Everything not listed here is asserted exactly as
/// it was before — the ledger removes named keys from one comparison and
/// touches nothing else. It is not a way of making a suite green; it is a way
/// of making a suite green <i>and</i> keeping a written obligation that fails
/// loudly the moment it is either met or withdrawn.</para>
///
/// <para><b>Three rules, and the last two are what make it short-lived.</b>
/// (a) A key that is not in the ledger is still asserted as before. (b) The
/// test FAILS if a ledgered thing has started existing on Windows, saying to
/// delete the entry — so an entry cannot outlive the fix it is waiting for.
/// (c) The test FAILS if a ledger entry names something the contract no longer
/// contains — so an entry cannot outlive the requirement either. Modelled on
/// <c>KnownToBeDropped</c> in <c>AssistSurfaceContractTests</c>, which has the
/// same mend-check and for the same reason: a list of exceptions with no way of
/// noticing it is stale becomes a record of what once went wrong.</para>
///
/// <para><b>Why this is NOT done with the contract's own <c>appliesOn</c>.</b>
/// <c>shared-rules.json</c> lets an entry say <c>appliesOn: ["mac"]</c>, and
/// <c>ContractTests.SharedRules_ActivityTrailEvents_Exist</c> honours it. That
/// is the right tool for a difference that is DELIBERATE and permanent — "built
/// site moved out of the working folder" is mac-only because Windows has never
/// built inside the working folder, so there is no moment to record. None of the
/// gaps listed below is like that. Windows OWES every one of them, on the milestone
/// its entry names, and writing <c>appliesOn: ["mac"]</c> would therefore be a lie in the file both
/// platforms read as the truth. It would also be a permanent one: <c>appliesOn</c>
/// has no mend-check, so on the day Windows implemented the event the contract
/// would still say the event was none of its business, both suites would stay
/// green, and nothing anywhere would notice. Softening the contract to quiet a
/// suite removes the very signal the contract exists to give.</para>
///
/// <para><b>A second option, rejected — declare the event with no call site.</b>
/// It has a precedent here: <c>ActivityTrail.Event</c> carries
/// <c>ItemExcluded</c>, <c>ItemReIncluded</c> and <c>RemovalBlocked</c>,
/// declared with the site-health work purely so this same trail test was green,
/// and the comment beside them disclaims itself as precedent in as many words
/// ("a note that they are owed a caller, not a precedent"). It was rejected for
/// #158 for a stronger reason than tidiness, and the difference is MEASURED
/// rather than remembered: all three were declared in <c>ef844171</c> at 08:17
/// on 2026-08-25 and all three got their first <c>ActivityTrail.Note</c> call
/// in <c>18b02264</c> at 08:45 the same morning — <b>28 minutes</b>, inside one
/// piece of work. The unit-word rename is a whole feature a MILESTONE away, so
/// the declaration would sit there with nothing to write it until v1.3.0. And
/// an event that is named but never recorded
/// tells the contract that a line exists which no teacher's trail will ever
/// carry — a green test asserting a trail that cannot happen, which is worse
/// than a red one, because the next person to ask "does Windows record this?"
/// gets yes. <c>FolderProblemFound</c> sat dead for months exactly that way. A
/// ledger entry says the opposite and says it out loud: this is NOT recorded
/// here yet, and here is who owes it.</para>
///
/// <para><b>The boundary — when an entry is allowed.</b> Only when an OPEN
/// issue, milestoned LATER than the release being cut, owns the work. Never for
/// a difference a teacher can see at the current milestone: that is a defect to
/// fix or a release to hold, and a ledger entry would be a way of shipping it
/// quietly. Never as a substitute for the issue, either — the entry names the
/// issue, and the issue is where the work is tracked. If the issue is closed,
/// or gets pulled into the release being cut, the entry goes and the assertion
/// comes back.</para>
///
/// <para><b>The catch-up to mac 1.7.1 (#481, 2026-10-15).</b> Windows is
/// catching up from 1.4.5 to the mac's 1.7.1 in batches, and an entry may name
/// work a LATER BATCH of that catch-up owns, on the milestone that work shipped
/// in on the mac (v1.5.0 … v1.7.1). Every one of those must be gone by the
/// 1.7.1 cut, and that is not left to memory:
/// <c>NamedGapLedgerTests.EveryEntryIsOwedByAMilestoneLaterThanThisBuild</c>
/// reads <c>&lt;Version&gt;</c> from <c>Plantoir.csproj</c> and fails for any
/// entry whose milestone is not LATER than the version being built. Setting the
/// version to 1.7.1 therefore turns every v1.5.0–v1.7.1 entry still here red,
/// while an entry owed by a genuinely later release (a v2.0.0, say) rightly
/// survives the cut. This replaced the single "Windows: parity with mac v1.4.0"
/// milestone, whose burn-down list the ledger was until v1.4.0 shipped.</para>
/// </remarks>
internal static class NamedGapLedger
{
    // Area names are constants rather than loose strings so that a typo at a
    // call site is a compile error. A mistyped area would match no entry, the
    // gap would never be checked in either direction, and the entry would sit
    // here for ever — which is precisely the failure the mend-checks exist to
    // prevent.

    /// <summary><c>shared-rules.json</c> → <c>activityTrail.mustRecord</c>, by event name.</summary>
    internal const string ActivityTrailEvents = "shared-rules.json → activityTrail.mustRecord";

    /// <summary><c>shared-rules.json</c> → <c>specialNames.platformWording.keys</c>, by key.</summary>
    internal const string PlatformWordedKeys = "shared-rules.json → specialNames.platformWording.keys";

    /// <summary><c>assist-wording.json</c> → <c>wording</c>, by key: a sentence with no same-named member on <c>AssistWording</c> or <c>ClassChangeWording</c>.</summary>
    internal const string AssistWordingKeys = "assist-wording.json → wording";

    /// <summary><c>file-formats.json</c> → <c>courseConfigKeys.keys</c>, by key.</summary>
    internal const string CourseConfigKeys = "file-formats.json → courseConfigKeys.keys";

    /// <summary><c>app-rules.json</c> → <c>modelTiers.requirements</c>, by <c>rule</c>.</summary>
    internal const string ModelTierRequirements = "app-rules.json → modelTiers.requirements";

    /// <summary><c>class-planning.json</c> → <c>sectionIndexPointer.dateCases</c>, by case <c>name</c>.</summary>
    internal const string FrontPageDateCases = "class-planning.json → sectionIndexPointer.dateCases";

    /// <summary><c>shared-rules.json</c> → <c>gradedFolders.newCourse.cases</c>, by case <c>name</c>.</summary>
    internal const string GradedFoldersNewCourseCases = "shared-rules.json → gradedFolders.newCourse.cases";

    /// <summary><c>toolchain.json</c> → <c>pins</c> that name a <c>windowsRuntimeContains</c>, by <c>pin</c>.</summary>
    internal const string ToolchainRuntimePins = "toolchain.json → pins (windowsRuntimeContains)";

    /// <summary><c>assist-cases.json</c> → <c>scenarios.cases</c>, by case <c>name</c>.</summary>
    internal const string AssistScenarios = "assist-cases.json → scenarios.cases";

    /// <summary><c>course-management.json</c> → <c>backups.pruneCases</c>, by case <c>name</c>.</summary>
    internal const string BackupPruneCases = "course-management.json → backups.pruneCases";

    /// <summary><c>course-management.json</c> → <c>zipNames.cases</c>, by case <c>name</c> (the file name).</summary>
    internal const string ZipNameCases = "course-management.json → zipNames.cases";

    // Wired in by step 0 of v2.0.0 (2026-11-13, #787): every area below holds
    // only what a later piece of the same release builds, and each is read by
    // the test named in its summary.

    /// <summary><c>assist-wording.json</c> → <c>wording</c>, by key: a sentence this app HAS a member for and says in older words (<c>ContractTests.SaidAsTheContract</c>); a held sentence must still differ.</summary>
    internal const string AssistWordingSaidDifferently = "assist-wording.json → wording (said in older words here)";

    /// <summary><c>app-rules.json</c> → <c>credentialPrompts.cases</c>, by <c>prompt</c>: a prompt that matches no request here yet (<c>ContractTests.AppRules_CredentialPrompts_MatchesContract</c>); a held prompt must match nothing.</summary>
    internal const string CredentialPromptCases = "app-rules.json → credentialPrompts.cases";

    /// <summary><c>app-rules.json</c> → <c>credentialRequests.requests</c> and <c>credentialPrompts.everyRequest</c>, by <c>name</c> (<c>ContractTests.AppRules_CredentialRequests_MatchesContract</c>, <c>PublishAndLauncherContractTests.EachCredentialIsHiddenOrShownAsTheContractSays</c>).</summary>
    internal const string CredentialRequestNames = "app-rules.json → credentialRequests.requests";

    /// <summary><c>app-rules.json</c> → <c>launcherFlags.preview</c>, by the flag's name before the space (<c>ContractTests.AppRules_LauncherFlags_MatchesContract</c>).</summary>
    internal const string PreviewLauncherFlags = "app-rules.json → launcherFlags.preview";

    /// <summary><c>app-rules.json</c> → <c>launcherFlags.deployExtras</c>, by the flag's name before the space (<c>PublishAndLauncherContractTests.TheDeployLauncherAcceptsTheExtraFlagsTheContractGivesIt</c>).</summary>
    internal const string DeployLauncherExtras = "app-rules.json → launcherFlags.deployExtras";

    /// <summary><c>shared-rules.json</c> → <c>deployWhileItsSectionDeploys.sentences.launcher</c>, by key: a launcher line the app cannot read as its refusal yet (<c>DeployWhileItsSectionDeploysTests.EveryLauncherSentenceCarriesAMarkerTheAppReads</c>).</summary>
    internal const string LauncherRefusalSentences = "shared-rules.json → deployWhileItsSectionDeploys.sentences.launcher";

    /// <summary><c>shared-rules.json</c> → <c>referenceCourses.codeUniqueWithinAGroup.cases</c>, by case <c>name</c> (<c>ReferenceCourseTests.ACodeIsUniqueWithinOneSchoolYearGroup</c>).</summary>
    internal const string ShelfCodeCases = "shared-rules.json → referenceCourses.codeUniqueWithinAGroup.cases";

    /// <summary><c>shared-rules.json</c> → <c>referenceCourses.wording</c>, by key: missing here or said differently (<c>ReferenceCourseTests.EverySentenceIsTheContracts</c>).</summary>
    internal const string ShelfWording = "shared-rules.json → referenceCourses.wording";

    /// <summary><c>shared-rules.json</c> → <c>referenceCourses.importing.wording</c>, by key: missing here or said differently (<c>ReferenceImportTests.EverySentenceIsTheContracts</c>).</summary>
    internal const string ImportWording = "shared-rules.json → referenceCourses.importing.wording";

    /// <summary><c>shared-rules.json</c> → <c>subjectMenus.items</c>, by item name (both facts of <c>SubjectMenusContractTests</c>).</summary>
    internal const string SubjectMenuItems = "shared-rules.json → subjectMenus.items";

    /// <summary><c>shared-rules.json</c> → <c>specialNames.platformWording.machine.usedIn</c>, by entry (<c>MachineWordContractTests.EverySentenceTheContractWritesWithTheMachineIsSaidFilled</c>).</summary>
    internal const string MachineWordUsedIn = "shared-rules.json → specialNames.platformWording.machine.usedIn";

    /// <summary>
    /// <c>windows-app/test_launcher_rules.ps1</c>'s rows, by <c>"&lt;list&gt;\t&lt;name&gt;"</c>,
    /// the list spelled as the runner's <c>Report</c> names it (per launcher:
    /// <c>deployWhileItsSectionDeploys/deploy.ps1</c>, …). Handed to the runner by
    /// <c>LauncherRulesContractTests</c> in <c>PLANTOIR_LEDGERED_LAUNCHER_CASES</c>;
    /// a held row prints <c>ledgered</c> while it fails in the shape it is held
    /// for, and <c>CLOSED</c> (a failure) the day it passes.
    /// </summary>
    internal const string LauncherRunnerRows = "windows-app/test_launcher_rules.ps1 → Report rows";

    // The milestones, spelled EXACTLY as their GitHub titles. NamedGapLedgerTests
    // parses each entry's milestone as a version and requires it to be LATER
    // than Plantoir.csproj's <Version>; anything that is not a version fails
    // there. (Until 2026-10-15 every entry named one milestone, "Windows:
    // parity with mac v1.4.0", and the ledger was its burn-down list.)
    private const string V150 = "v1.5.0";
    private const string V171 = "v1.7.1";
    private const string V180 = "v1.8.0";
    private const string V191 = "v1.9.1";
    private const string V193 = "v1.9.3";
    private const string V200 = "v2.0.0";

    /// <summary>
    /// One thing the contract names and this app does not have yet.
    /// </summary>
    /// <param name="Area">Which contract list the key belongs to.</param>
    /// <param name="Key">The event name or sentence key, spelled as the contract spells it.</param>
    /// <param name="Issue">The open GitHub issue that owns the work.</param>
    /// <param name="Milestone">The milestone that issue carries, spelled as its
    /// GitHub title ("v1.6.0"). It must be LATER than the version being built,
    /// which <c>NamedGapLedgerTests</c> checks against <c>Plantoir.csproj</c>,
    /// so an entry still here when its release is cut fails the suite
    /// (<c>contracts/README.md</c> → "Named gaps").</param>
    /// <param name="Reason">Why it is not built here yet, in a sentence.</param>
    internal sealed record Entry(string Area, string Key, int Issue, string Milestone, string Reason);

    /// <summary>Several keys of one area owned by one issue, for one reason.</summary>
    private static IEnumerable<Entry> Owed(string area, int issue, string milestone, string reason, params string[] keys) =>
        keys.Select(key => new Entry(area, key, issue, milestone, reason));

    // Reasons, one per owning issue, as `private const string` beside the
    // milestones above. EMPTY since 2026-11-10, when #720 took mac #698's
    // regenerated contract (obsidianIsNotOnThisMachine, said with {machine}
    // filled) and deleted the two entries #690 had held against #698 (v1.9.1)
    // from 2026-10-28: obsidianIsNotOnThisMac and the scenario "open in
    // Obsidian on a Mac without Obsidian presses nothing (#610)". Empty
    // before that from 2026-10-22, when #581 landed its four Obsidian
    // add-on events (held open earlier that day); empty from 2026-10-16, when
    // #548 closed the sixteen plan-table sentences (mac #524) that #551's
    // piece held open that morning; and empty from 2026-10-15, when the
    // catch-up to mac 1.7.1, #481, closed its last two.
    //
    // Two held open by #734 on 2026-11-11, for the Windows 1.9.3 catch-up:
    // each is a later piece of the same release, so each goes when that piece
    // lands (and this test fails, saying so, the moment its event exists).
    // #736's ("asked an assistant to fix problems") went the same day, with
    // the Fix with… buttons that write it.

    // Step 0 of v2.0.0 (2026-11-13, #787): the reds the mac's v2.0.0 work
    // brought, each owned by the open `windows` issue that builds it later in
    // the same run. Each piece deletes its own entries as it lands, and the
    // ledger fails, naming the entry, the moment a held thing exists here.
    private const string Reason799 = "a deploy that builds the site again only when something changed is #799's piece of v2.0.0, not built here yet";
    private const string Reason801 = "the course's Planning tab, its unit plans and Plan a Unit are #801's piece of v2.0.0, not built here yet";
    private const string Reason811 = "a section's Coverage tab is #811's piece of v2.0.0, not built here yet";
    private const string Reason820 = "Open in Browser on a unit plan is #820's piece of v2.0.0, not built here yet";
    private const string Reason823 = "making a course straight onto the reference shelf and importing a backup or archive zip are #823's piece of v2.0.0; until it lands Windows cannot import a zip, so its own import sentence is the true one";
    private const string Reason824 = "sharing a course's unit plans (with #848's look before a share) is #824's piece of v2.0.0, not built here yet";
    private const string Reason826 = "replacing a reference course is #826's piece of v2.0.0, not built here yet";
    private const string Reason827 = "the groups a teacher makes on the reference shelf are #827's piece of v2.0.0, not built here yet";
    private const string Reason828 = "the launchers refusing an overlapping build of a section (#729), and what the app reads from that refusal, are #828's piece of v2.0.0, not built here yet";
    private const string Reason854 = "#835's first part (a hold from a scheduled deploy named as one that is running, not 'set for later') is #854's piece of v2.0.0, not built here yet";

    /// <summary>A launcher-runner row key, as the runner builds it: the list label, a TAB, the case name.</summary>
    private static string Row(string list, string name) => list + "\t" + name;

    /// <summary>One case of a launcher list that BOTH launchers run, held for each.</summary>
    private static IEnumerable<string> BothLaunchers(string list, params string[] names) =>
        new[] { "deploy.ps1", "preview.ps1" }.SelectMany(launcher => names.Select(name => Row(list + "/" + launcher, name)));

    private static readonly Entry[] Entries = new IEnumerable<Entry>[]
    {
        // ---- step 0 of v2.0.0: activityTrail.mustRecord (22; "course
        // restored from a backup" is built in step 0 itself, ruling F3).
        Owed(ActivityTrailEvents, 823, V200, Reason823,
             "course created for reference", "course could not be created for reference", "zip could not be read for reference"),
        Owed(ActivityTrailEvents, 826, V200, Reason826,
             "reference course replaced", "reference course could not be replaced", "unfinished replace of a reference course put right"),
        Owed(ActivityTrailEvents, 827, V200, Reason827,
             "reference group made", "reference group renamed", "reference group removed", "reference course moved to a group",
             "reference groups not changed", "reference groups started again"),
        Owed(ActivityTrailEvents, 799, V200, Reason799, "site built again before deploying"),
        Owed(ActivityTrailEvents, 801, V200, Reason801, "looked at a course's unit plans", "asked an assistant to plan a unit"),
        Owed(ActivityTrailEvents, 820, V200, Reason820, "opened a unit plan in the browser"),
        Owed(ActivityTrailEvents, 811, V200, Reason811,
             "looked at a section's curriculum coverage", "asked to make a section's coverage map again"),
        Owed(ActivityTrailEvents, 824, V200, Reason824,
             "unit plans shared", "unit plan share refused", "unit plan sharing stopped", "unit plan password changed"),

        // ---- step 0: assist-wording.json → wording
        Owed(AssistWordingKeys, 828, V200, Reason828, "deployRefusedWhileItsSectionIsBeingBuilt"),
        Owed(AssistWordingSaidDifferently, 854, V200, Reason854,
             "courseIsBeingBuiltElsewhere", "deployRefusedWhileALaterDeployWorks"),

        // ---- step 0: app-rules.json → credentials and launcher flags
        Owed(CredentialPromptCases, 824, V200, Reason824,
             "Choose a username for these unit plans: ",
             "Please choose a username of 1 to 32 letters, digits, dots, dashes or underscores: ",
             "Choose a password for these unit plans (8 to 64 characters): ",
             "Please choose a password of 8 to 64 letters, digits, spaces or symbols: "),
        Owed(CredentialRequestNames, 824, V200, Reason824, "unitPlanUsername", "unitPlanPassword"),
        Owed(PreviewLauncherFlags, 828, V200, Reason828, "--for-deploy"),
        Owed(DeployLauncherExtras, 824, V200, Reason824,
             "--plans", "--protect", "--remove-password", "--change-password", "--send-answer-keys-openly",
             "--password-only", "--include-answer-keys", "--stop-sharing", "--year"),

        // ---- step 0: shared-rules.json → deployWhileItsSectionDeploys
        Owed(LauncherRefusalSentences, 828, V200, Reason828, "buildingDeploy", "buildingBuild"),
        Owed(LauncherRefusalSentences, 854, V200, Reason854, "laterDeploy", "laterBuild"),

        // ---- step 0: the launcher runner's rows. #828: fifteen launcherCases
        // rows (seven cases on each launcher, one preview case) and the two
        // "already being built" sentences on each launcher. #854: the two
        // "later" sentences and the "later" trail line on each launcher.
        Owed(LauncherRunnerRows, 828, V200, Reason828,
             Row("previewWhileItsSectionDeploys", "a deploy's build leg (--build-only --for-deploy) is a deploy")),
        Owed(LauncherRunnerRows, 828, V200, Reason828, BothLaunchers("deployWhileItsSectionDeploys",
             "a deploy's build leg (--build-only --for-deploy) in this folder refuses a deploy",
             "a deploy's build leg refuses the build leg of another deploy",
             "a rebuild (--build-only, no --for-deploy) refuses a deploy, in words that say built",
             "a deploy's own build leg held up by a rebuild says it cannot be deployed",
             "a rebuild refuses another build of the section",
             "a rebuild whose working folder cannot be asked still counts",
             "two builds started by the same app are not one family").ToArray()),
        Owed(LauncherRunnerRows, 828, V200, Reason828,
             BothLaunchers("deployWhileItsSectionDeploys.sentences", "buildingDeploy", "buildingBuild").ToArray()),
        Owed(LauncherRunnerRows, 854, V200, Reason854,
             BothLaunchers("deployWhileItsSectionDeploys.sentences", "laterDeploy", "laterBuild").ToArray()),
        Owed(LauncherRunnerRows, 854, V200, Reason854,
             BothLaunchers("activityTrail", "launcherLineWhenALaterDeployIsStillWorking").ToArray()),

        // ---- step 0: the reference shelf (#823, #827)
        Owed(ShelfCodeCases, 827, V200, Reason827,
             "the same code in one made group", "the same code in a made group and in a year group",
             "the same code in two made groups"),
        Owed(ShelfWording, 827, V200, Reason827, "codeAlreadyInThatGroup"),
        Owed(SubjectMenuItems, 827, V200, Reason827, "moveToGroup"),
        Owed(ImportWording, 823, V200, Reason823,
             "explanation", "zipCouldNotBeOpened", "zipIsNotSafeToOpen", "zipHoldsNoCourse", "zipHoldsSeveralCourses",
             "zipIsFarLargerThanACourse", "zipNeedsMoreRoom", "chooserMessage", "importForReferenceMenuItem"),

        // ---- step 0: specialNames.platformWording.machine.usedIn (#811)
        Owed(MachineWordUsedIn, 811, V200, Reason811,
             "shared-rules.json:coverageTab.tab.words.cannotShowDescription", "shared-rules.json:coverageTab.tab.words.noObsidian"),

        // ---- activityTrail.mustRecord. #514's two events ("preview started
        // at the page last viewed", "preview start page chosen in Settings")
        // landed with batch 6; #581's four (Obsidian's add-ons for diagrams
        // and graphs) with #581. "problems changed" landed with #734, "asked
        // an assistant to fix problems" with #736, and "deploy refused for the
        // Cloudflare Account ID" with #739: none is held open.

        // ---- specialNames.platformWording.keys

        // ---- file-formats.json → courseConfigKeys: none held open. The four
        // print_* keys landed with #496's batch 5B (Course Settings → Printing).

        // ---- toolchain.json → pins: none held open. pagedjs, functionPlot
        // and nodeTikzjax (and latinModern, newly watched) landed in
        // fetch-runtime.ps1 with #503's batch 5A; pyodide (#455) with #568,
        // never ledgered: the fetch landed in the same piece as the pin.

        // ---- class-planning.json → sectionIndexPointer.dateCases (pointAt cases)

        // ---- shared-rules.json → gradedFolders.newCourse.cases (#317's runner)

        // ---- app-rules.json → modelTiers.requirements

        // ---- assist-wording.json → wording: none held open. The Section
        // menu's sentences landed with #489's 2B, the Deploy question's
        // seventeen (mac #475) with 2C, mac #524's sixteen plan-table
        // sentences (plan*, menuPlan*) with #548's plan table, and #690's
        // obsidianIsNotOnThisMac (held 2026-10-28) went with #720.

        // ---- assist-cases.json → scenarios.cases: none held open. #475's
        // three landed with #489's 2C; #690's "on a Mac without Obsidian"
        // went with #720.
    }.SelectMany(group => group).ToArray();

    /// <summary>Every entry, for <c>NamedGapLedgerTests</c>.</summary>
    internal static IReadOnlyList<Entry> All => Entries;

    /// <summary>
    /// The entry holding <paramref name="key"/> open under <paramref name="area"/>,
    /// or null. For a runner that cannot collect its results into one
    /// comparison — a theory, where each case is its own test — and so checks
    /// the "it now passes" direction itself, with <see cref="ClosedMessage"/>.
    /// </summary>
    internal static Entry? Holding(string area, string key) => Holding(area, key, Entries);

    /// <summary><see cref="Holding(string, string)"/> over entries a test makes up, so the mechanism stays proved whatever the ledger holds.</summary>
    internal static Entry? Holding(string area, string key, IEnumerable<Entry> entries) =>
        entries.FirstOrDefault(entry => entry.Area == area && entry.Key == key);

    /// <summary>
    /// The contract-direction half of <see cref="GapsIn"/> alone: every entry
    /// under <paramref name="area"/> names something the contract still has.
    /// Paired with <see cref="Holding"/> by a theory's runner.
    /// </summary>
    internal static void StillNamed(string area, IEnumerable<string> namedByTheContract) => StillNamed(area, namedByTheContract, Entries);

    /// <summary><see cref="StillNamed(string, IEnumerable{string})"/> over entries a test makes up.</summary>
    internal static void StillNamed(string area, IEnumerable<string> namedByTheContract, IEnumerable<Entry> entries)
    {
        var contract = namedByTheContract.ToHashSet(StringComparer.Ordinal);
        foreach (var entry in entries.Where(entry => entry.Area == area))
            Assert.True(contract.Contains(entry.Key), WithdrawnMessage(entry));
    }

    /// <summary>
    /// Checks the ledger's entries for one contract list, in BOTH directions,
    /// and returns the keys the caller may leave out of its own comparison.
    /// </summary>
    /// <param name="area">One of the area constants on this class.</param>
    /// <param name="namedByTheContract">Every key the contract names in that list.</param>
    /// <param name="implementedHere">Every key this app actually has.</param>
    internal static IReadOnlyCollection<string> GapsIn(
        string area,
        IEnumerable<string> namedByTheContract,
        IEnumerable<string> implementedHere) => GapsIn(area, namedByTheContract, implementedHere, Entries);

    /// <summary><see cref="GapsIn(string, IEnumerable{string}, IEnumerable{string})"/> over entries a test makes up.</summary>
    internal static IReadOnlyCollection<string> GapsIn(
        string area,
        IEnumerable<string> namedByTheContract,
        IEnumerable<string> implementedHere,
        IEnumerable<Entry> entries)
    {
        var contract = namedByTheContract.ToHashSet(StringComparer.Ordinal);
        var here = implementedHere.ToHashSet(StringComparer.Ordinal);
        var mine = entries.Where(entry => entry.Area == area).ToList();

        foreach (var entry in mine)
        {
            Assert.True(contract.Contains(entry.Key), WithdrawnMessage(entry));
            Assert.False(here.Contains(entry.Key), ClosedMessage(entry));
        }

        return mine.Select(entry => entry.Key).ToHashSet(StringComparer.Ordinal);
    }

    /// <summary>What to say when an entry names something the contract no longer has.</summary>
    internal static string WithdrawnMessage(Entry entry)
    {
        // What brings you here depends on WHICH list, and the message says
        // only what is possible for that one. `activityTrail.mustRecord`
        // has per-platform scoping, so there are two causes wanting
        // opposite responses: the contract dropped the key (delete the
        // entry) or somebody SCOPED it away with `appliesOn` — which
        // ContractTests applies BEFORE calling in, so it arrives looking
        // identical, and is the softening this ledger exists to catch.
        // `specialNames.platformWording.keys` is a flat array of strings
        // with no scoping mechanism at all, so naming `appliesOn` there
        // would send its reader hunting for something that cannot exist.
        string whyThisHappened =
            $"NamedGapLedger holds \"{entry.Key}\" open under {entry.Area}, and the contract no " +
            "longer names it. ";

        whyThisHappened += entry.Area == ActivityTrailEvents
            ? "Two different things cause that, and they want opposite responses. (1) The " +
              "contract dropped the key outright — the requirement went away, so delete this " +
              "entry from windows-app/Plantoir.Tests/NamedGapLedger.cs and say so on issue " +
              $"#{entry.Issue}. (2) Somebody scoped it away from this platform instead, with an " +
              "`appliesOn` that no longer lists \"windows\" — ContractTests filters this list by " +
              "`appliesOn` BEFORE calling in here, so that arrives looking exactly like (1). " +
              "Check `git log -p contracts/shared-rules.json` before believing (1): scoping is " +
              "the softening this ledger exists to prevent, it has no mend-check of its own, and " +
              $"issue #{entry.Issue} ({entry.Milestone}) says this platform owes the work. If " +
              "that is what happened, put the contract back and leave this entry alone."
            : "A gap can only be held open against something the contract still asks for, so " +
              "the requirement went away: delete this entry from " +
              "windows-app/Plantoir.Tests/NamedGapLedger.cs and say so on issue " +
              $"#{entry.Issue}. (This list is a flat array of keys with no per-platform scoping, " +
              "so unlike activityTrail.mustRecord there is no `appliesOn` here for the key to " +
              "have been hidden behind — a key missing from it really is a key withdrawn.)";
        return whyThisHappened;
    }

    /// <summary>What to say when a ledgered thing has started existing on this side.</summary>
    internal static string ClosedMessage(Entry entry) =>
        $"\"{entry.Key}\" is ledgered as not built here yet (issue #{entry.Issue}, " +
        $"{entry.Milestone}: {entry.Reason}) — and it now EXISTS on this side. That is the " +
        "gap closing. Delete this entry from windows-app/Plantoir.Tests/NamedGapLedger.cs so " +
        $"the full assertion comes back, and say so on issue #{entry.Issue}.";
}

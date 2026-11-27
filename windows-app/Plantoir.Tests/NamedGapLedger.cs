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
/// <c>NamedGapLedgerTests</c> read <c>&lt;Version&gt;</c> from
/// <c>Plantoir.csproj</c> and failed for any entry whose milestone was not
/// LATER than the version being built, so setting the version to 1.7.1 turned
/// every v1.5.0–v1.7.1 entry still here red. Since #862 (2026-11-13)
/// <c>&lt;Version&gt;</c> names the release in progress, so
/// <c>NamedGapLedgerTests.EveryEntryIsOwedByAMilestoneLaterThanTheLastWindowsRelease</c>
/// compares with the last release Windows SHIPPED (<c>site.json</c> and
/// <c>updates/windows.xml</c>), and <c>publish.ps1 -Sign</c> runs it against
/// <c>&lt;Version&gt;</c> and refuses the cut. This replaced the single
/// "Windows: parity with mac v1.4.0" milestone, whose burn-down list the
/// ledger was until v1.4.0 shipped.</para>
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

    /// <summary><c>class-planning.json</c> → <c>todaysClassOnTheFrontPage.wording</c>, by key: a sentence this app does not say (<c>TodaysClassContractTests.TheSentencesAreTheContracts</c>).</summary>
    internal const string TodaysClassWording = "class-planning.json → todaysClassOnTheFrontPage.wording";

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

    /// <summary><c>app-rules.json</c> → <c>outsideAgents.planAUnit.buttons</c>, by <c>assistant</c> (<c>PlanAUnitTests.TheWordsAreTheContracts</c>).</summary>
    internal const string PlanAUnitButtons = "app-rules.json → outsideAgents.planAUnit.buttons";

    // Wired in by #884's first part (2026-11-13, after the mac's #783 and
    // #850 merged): each area below holds only what #884 or #889 builds.

    /// <summary>
    /// <c>app-rules.json</c> → <c>outsideAgents.agents</c>, by agent <c>key</c>: an
    /// outside door this app does not have yet. "Has it" is read from
    /// <c>SubjectMenuRules.ReviseTarget</c> and <c>CourseActivity.ReviseItem</c>
    /// (<see cref="OutsideDoorsHeld"/>), so the entry closes the day either
    /// gains the door. Read by <c>CodexLauncherTests.TheOutsideDoorsPassWhatTheContractSays</c>,
    /// <c>ContractTests.TheOutsideAgentsMenuTitles_AreTheContracts</c>,
    /// <c>FixWithAssistantContractTests.PiecesAndBoundsAreTheContracts</c> (the
    /// <c>fixWith.buttons</c>, keyed alike), <c>SubjectMenusContractTests.Situation</c>
    /// (<c>reviseBlocked</c>) and <c>DoorCourseHoldTests.TheReviseCasesAreTheContracts</c>
    /// (a case's <c>item</c>).
    /// </summary>
    internal const string OutsideDoors = "app-rules.json → outsideAgents.agents";

    /// <summary><c>shared-rules.json</c> → <c>subjectMenus.situationKeys</c>, by key: a situation this app cannot be in yet, so a case that names it is not run (<c>SubjectMenusContractTests</c>, <c>SidebarDeleteKeyContractTests</c>).</summary>
    internal const string SubjectMenuSituationKeys = "shared-rules.json → subjectMenus.situationKeys";

    /// <summary><c>shared-rules.json</c> → <c>activityTrail.mustRecord</c>, by event: an event this app records, whose <c>line</c> it writes in older words (<c>DoorCourseHoldTests.TheTrailLineIsTheContracts</c>); a held line must still differ.</summary>
    internal const string TrailLineSaidDifferently = "shared-rules.json → activityTrail.mustRecord line (said in older words here)";

    /// <summary><c>app-rules.json</c> → <c>outsideAgents.fixWith.greetingCases</c>, by case <c>name</c>: a message carrying a sentence the mac added to Fix with…'s text that this app does not say yet, held while it is the contract's message with exactly that sentence left out (<c>FixWithAssistantContractTests.GreetingCases</c>, <c>HeldGreetingCasesAreStillTheContracts</c>). Empty since #895 brought <c>greetingHandoutsSentence</c> here (its six cases were the first held); kept, with its hook, for the next such sentence.</summary>
    internal const string FixWithGreetingCases = "app-rules.json → outsideAgents.fixWith.greetingCases";

    /// <summary>
    /// <c>app-rules.json</c> → <c>outsideAgents.fixWith</c>, by key: a sentence of
    /// the Fix with… buttons this app says only in part, because the rest names
    /// something it does not have yet (<c>FixWithAssistantContractTests.PiecesAndBoundsAreTheContracts</c>).
    /// A held sentence must still differ from the contract's (Windows' machine
    /// word filled in), and must be exactly its first sentence. Wired in by
    /// #990's Windows half (2026-11-19) for <c>notInstalledHelp</c>.
    /// </summary>
    internal const string FixWithWordsSaidDifferently = "app-rules.json → outsideAgents.fixWith (said in part here)";

    /// <summary>
    /// <c>windows-app/test_launcher_rules.ps1</c>'s rows, by <c>"&lt;list&gt;\t&lt;name&gt;"</c>,
    /// the list spelled as the runner's <c>Report</c> names it (per launcher:
    /// <c>deployWhileItsSectionDeploys/deploy.ps1</c>, …). Handed to the runner by
    /// <c>LauncherRulesContractTests</c> in <c>PLANTOIR_LEDGERED_LAUNCHER_CASES</c>;
    /// a held row prints <c>ledgered</c> while it fails in the shape it is held
    /// for, and <c>CLOSED</c> (a failure) the day it passes.
    /// </summary>
    internal const string LauncherRunnerRows = "windows-app/test_launcher_rules.ps1 → Report rows";

    // Wired in by #868's held-by-name piece (2026-11-13, after the mac's
    // #835 part 3, #855, #839 and #902 merged).

    /// <summary>
    /// <c>shared-rules.json</c> → <c>quittingWhileWorkIsUnderWay.cases</c>, by case
    /// <c>name</c>: a case naming <c>assistantsBeingSetUp</c>, which this app
    /// cannot have yet (<c>QuitConfirmationTests.EveryQuitCaseIsDecidedAsTheContractSays</c>).
    /// A held case must name a set-up and must still be decided DIFFERENTLY
    /// here; every other case is asserted exactly.
    /// </summary>
    internal const string QuitCases = "shared-rules.json → quittingWhileWorkIsUnderWay.cases";

    // Wired in by the fourth hold of the night (2026-11-14, branch
    // issue/hold4-after-the-macs-fourteen, after the mac's fourteen pieces
    // merged at cadd8eb11): each area below holds only what a named
    // `windows` issue of v2.0.0 builds.

    /// <summary>
    /// <c>shared-rules.json</c> → <c>subjectMenus.items</c>, by item name: an item
    /// the contract RENAMED that this app still carries under its older name,
    /// which <see cref="SubjectMenuItemsOlderNames"/> gives. Read by both facts
    /// of <c>SubjectMenusContractTests</c>: the older name must be here and gone
    /// from the contract, it stands in the held name's place in the item list,
    /// and it must be enabled exactly where every case enables the held name.
    /// </summary>
    internal const string SubjectMenuItemsUnderAnOlderName = "shared-rules.json → subjectMenus.items (said under an older name here)";

    /// <summary>
    /// <c>app-rules.json</c> → <c>credentialRequests.requests</c>, by <c>name</c>: a
    /// request this app has whose <c>explanation</c> or <c>steps</c> it says in
    /// older words (<c>ContractTests.AppRules_CredentialRequests_MatchesContract</c>).
    /// A held request must still differ there, keeps the contract's number of
    /// steps, and has every other field compared exactly.
    /// </summary>
    internal const string CredentialRequestsSaidDifferently = "app-rules.json → credentialRequests.requests (said in older words here)";

    /// <summary>
    /// <c>app-rules.json</c> → <c>failureExplanations.cases</c>, by the case's
    /// <c>why</c> up to its first colon (the cases carry no name): an output
    /// this app does not recognise yet (<c>ContractTests.AppRules_FailureExplanations_MatchesContract</c>).
    /// A held case must be explained by NOTHING here, the contract's honest
    /// fallback (the raw output is shown), never by some other sentence.
    /// </summary>
    internal const string FailureExplanationCases = "app-rules.json → failureExplanations.cases (by why, to its first colon)";

    /// <summary>
    /// <c>shared-rules.json</c> → <c>sectionProblems.kinds</c>, by <c>kind</c>: a
    /// Problems-tab kind this app has no label for yet
    /// (<c>SectionProblemsContractTests.KindsAndScopesAreTheContracts</c>,
    /// <c>TheRulesAreTheContracts</c>). "Has it" is <c>SectionProblemsWording.KindLabels</c>.
    /// </summary>
    internal const string SectionProblemKinds = "shared-rules.json → sectionProblems.kinds";

    /// <summary>
    /// <c>shared-rules.json</c> → <c>printablePages.agentGuidance.words</c>, by
    /// key: a sentence of the guidance sheet this app says in older words
    /// (<c>AgentGuidanceTests.TheAskWordsAreTheContractsAndNameNoMachinery</c>);
    /// a held sentence must still differ, and is still checked for the machinery.
    /// </summary>
    internal const string AgentGuidanceWordsSaidDifferently = "shared-rules.json → printablePages.agentGuidance.words (said in older words here)";

    /// <summary>
    /// <c>shared-rules.json</c> → <c>workLeases.liveness.cases</c>, by case
    /// <c>name</c>: a case this app decides the other way today
    /// (<c>WorkLeaseContractTests.EveryLivenessCaseIsDecidedAsTheContractSays</c>).
    /// A held case must still be decided opposite to <c>expect</c>, and the
    /// number met must equal the entries; every other case is decided exactly.
    /// </summary>
    internal const string LeaseLivenessCases = "shared-rules.json → workLeases.liveness.cases";

    /// <summary>
    /// <c>shared-rules.json</c> → <c>undo.checkCases</c>, by case <c>name</c>:
    /// a case whose op is of a kind this app's reader does not know yet (U2's
    /// six kinds, Windows' W6). A held case must still be answered
    /// <c>notReadable</c> both ways here, never guessed at, and must still
    /// differ from the contract (<c>UndoCheckContractTests.EveryCheckCase</c>).
    /// </summary>
    internal const string UndoCheckCases = "shared-rules.json → undo.checkCases";

    /// <summary>
    /// <c>shared-rules.json</c> → <c>undo.checkCases</c>, by case <c>name</c>:
    /// an editJSON case whose file or key path this app is not measured to
    /// read as the mac's Foundation reads it (#899 W6 review 2). A held case
    /// must be answered <c>cannotTell</c> both ways here, never judged, and
    /// must still differ from the contract (<c>UndoCheckContractTests.EveryCheckCase</c>).
    /// </summary>
    internal const string UndoCheckCasesRefusedHere = "shared-rules.json → undo.checkCases (refused here as cannot tell)";

    /// <summary>
    /// <c>undo-json-cases.json</c> → <c>editJSONCases</c>, by case
    /// <c>name</c>: a move whose bytes the mac writes and this app is not
    /// measured to write the same (#899 W6 review 2). A held case must be
    /// REFUSED here (no bytes at all, never bytes of its own), and the
    /// contract's result must still be bytes (<c>UndoOpKindsContractTests.EveryEditJsonCase</c>).
    /// </summary>
    internal const string UndoEditJsonCasesRefusedHere = "undo-json-cases.json → editJSONCases (refused here)";

    /// <summary>
    /// <c>shared-rules.json</c> → <c>undo.stackCases</c>, by case <c>name</c>:
    /// a case that needs a call or a key this replay does not know yet (U2's
    /// op kinds, W6). A held case must still stop at that call or key
    /// (<c>UndoStackContractTests.EveryStackCase</c>).
    /// </summary>
    internal const string UndoStackCases = "shared-rules.json → undo.stackCases";

    /// <summary>
    /// <c>undo-traces.json</c> → <c>traces</c>, by trace <c>name</c>: a trace
    /// holding a call this replay does not know yet (U2's <c>move</c>, W6).
    /// A held trace is still replayed and asserted call by call up to that
    /// call, and must still stop there (<c>UndoTraceContractTests.EveryCallOfEveryTrace</c>).
    /// </summary>
    internal const string UndoTraces = "undo-traces.json → traces";

    /// <summary>
    /// <c>undo-traces.json</c> → <c>actionTraces</c>, by trace <c>name</c>: a
    /// trace whose recorded step has <c>moves</c> (U3b's rollover, W7c) or
    /// <c>folderMoves</c> (Rename folder, W8b), which this replay does not
    /// make yet (a step with <c>members</c> it makes as its recorded ops since
    /// W8-11, and Add folder's <c>trees</c> by the Windows action since W8-13). A held trace must still stop
    /// at its step (<c>UndoActionTraceContractTests.EveryCallOfEveryActionTrace</c>).
    /// </summary>
    internal const string UndoActionTraces = "undo-traces.json → actionTraces";

    /// <summary>
    /// <c>undo-action-steps.json</c> → <c>steps</c>, by step <c>name</c>
    /// (#899 W7b1): a recorded step whose Windows action does not make its
    /// step through the door yet, so the Windows action run on the mac's
    /// fixture (<c>UndoActionStepsOnWindowsTests.TheWindowsActionLeavesTheRecordedStep</c>)
    /// leaves no such step. A held step must still fail there.
    /// </summary>
    internal const string UndoActionStepsOnWindows = "undo-action-steps.json → steps (the Windows action on the mac's fixture)";

    /// <summary>
    /// <c>class-planning.json</c> → <c>duplicatingAsTheNextClass.cases</c>, by
    /// case <c>name</c>: a case whose <c>expectUndoEntries</c> this app does
    /// not record, because the entry is the old in-memory list's and Windows'
    /// final form is the journal step (W7 for #899). A held case must still
    /// record NO entry here, and everything else it says is asserted exactly
    /// (<c>AddClassContractTests.TheMenusCopyIsTheContracts</c>). Wired in by
    /// #927 (2026-11-20).
    /// </summary>
    internal const string MenuCopyUndoEntries = "class-planning.json → duplicatingAsTheNextClass (expectUndoEntries)";

    /// <summary>
    /// <c>shared-rules.json</c> → <c>undo.recoveryCases</c>, by case <c>name</c>:
    /// a case that needs a key this replay does not check yet (U2b's
    /// <c>withAMove</c>, <c>withATree</c>, <c>withAPreference</c>,
    /// <c>recoveredBy</c>: W6). A held case must still stop at that key
    /// (<c>UndoRecoveryContractTests.EveryRecoveryCase</c>).
    /// </summary>
    internal const string UndoRecoveryCases = "shared-rules.json → undo.recoveryCases";

    /// <summary>
    /// The older name each <see cref="SubjectMenuItemsUnderAnOlderName"/> entry
    /// is said under here. Every entry has exactly one, and every name here has
    /// an entry (<c>NamedGapLedgerTests</c>).
    /// </summary>
    internal static readonly IReadOnlyDictionary<string, string> SubjectMenuItemsOlderNames =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            // Empty since #927 brought Add Class… (2026-11-20); kept, with its
            // hook, for the next item the contract renames.
        };

    // The milestones, spelled EXACTLY as their GitHub titles. NamedGapLedgerTests
    // parses each entry's milestone as a version and requires it to be LATER
    // than the last Windows release (and, at a signed cut, than
    // Plantoir.csproj's <Version>, #862); anything that is not a version fails
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
    /// GitHub title ("v1.6.0"). It must be LATER than the last release Windows
    /// shipped, which <c>NamedGapLedgerTests</c> checks in every run, and later
    /// than <c>Plantoir.csproj</c>'s <c>&lt;Version&gt;</c> at a signed cut,
    /// where <c>publish.ps1 -Sign</c> refuses an entry still here
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
    private const string Reason801 = "the course's Planning tab, its unit plans and Plan a Unit are #801's piece of v2.0.0, not built here yet";
    private const string Reason811 = "a section's Coverage tab is #811's piece of v2.0.0, not built here yet";
    private const string Reason820 = "Open in Browser on a unit plan is #820's piece of v2.0.0, not built here yet";
    private const string Reason823 = "making a course straight onto the reference shelf and importing a backup or archive zip are #823's piece of v2.0.0; until it lands Windows cannot import a zip, so its own import sentence is the true one";
    private const string Reason824 = "sharing a course's unit plans (with #848's look before a share) is #824's piece of v2.0.0, not built here yet";
    private const string Reason826 = "replacing a reference course is #826's piece of v2.0.0, not built here yet";
    private const string Reason827 = "the groups a teacher makes on the reference shelf are #827's piece of v2.0.0, not built here yet";
    private const string Reason884 = "GitHub Copilot as a third outside assistant (the mac's #783) is #884's piece of v2.0.0; Windows has no Copilot door yet";

    // #884's first part (2026-11-13): the mac's #783 and #850 merged into dev.
    private const string Reason884Door = "GitHub Copilot as a third outside door (its launcher, detection, menu items and buttons) is #884's piece of v2.0.0, not built here yet";
    private const string Reason884Naming = "naming the assistant at work through {assistant} needs plantoir-mcp to write the door's key as the assist lease's fifth line (#884 item 7, with WorkLease); until then every Windows hold names none, and the contract's anyAssistant for that names GitHub Copilot, which a Windows teacher cannot open yet, so the older 'Claude or Codex' words stay the true ones";

    // #868's held-by-name piece (2026-11-13): the mac's #835 part 3 and #855 merged into dev.
    private const string Reason868Sections = "a build, preview or deploy holding only its own section (a work lease's sixth line, the mac's #835 part 3) is #868's piece of v2.0.0; until it lands every Windows lease holds the whole course and a lease's sixth line is read as course-wide, so no hold here is ever on one section and the course-wide sentence is the true one";
    private const string Reason903 = "setting up Claude Code, Codex or GitHub Copilot from Settings (the mac's #855) is #903's piece of v2.0.0; Windows has no set-up yet, so none can be under way, recorded or quit through";
    private const string Reason903SetUpItem = "a Fix with… button dimmed because its assistant is missing names Settings ▸ Other Assistants in its second sentence (the mac's #990), the page Revise With ▸ Set Up an Assistant… opens; that page and the set-up behind it are #903's piece of v2.0.0, so until it lands Windows says the first sentence alone rather than send a teacher looking for a page that is not there";

    // #911's held-by-name piece (2026-11-14): the mac's #897 C and #785a merged into dev.
    private const string Reason912 = "small backups that keep each Media file once in courses/_backups/.shared-media (the mac's #785a) are #912's piece of v2.0.0; until it lands Windows writes no small backup, sweeps nothing and lists no _shared-media name (BackupItem.From refuses every one), so none of these three can happen here";

    // The fourth hold (2026-11-14): the mac's fourteen pieces merged at cadd8eb11.
    private const string Reason920 = "the invented sample names on the surname and website-address sheets (the mac's #891) are #920's piece of v2.0.0, with the colour pickers and the switch; until it lands Windows' sheets carry the older example names, which name nothing a teacher acts on";
    private const string Reason921 = "Settings ▸ Deploying, the tokens checked before they are saved and the Cloudflare token's end date (the mac's #696), are #921's piece of v2.0.0; until it lands Windows shows no end date and warns of none, so its older words for the TTL step are the true ones, and it records, says and explains none of the pane's events, problems or refusals";
    private const string Reason936 = "PhET simulations and the kept-downloads folder (the mac's #674) are #936's piece of v2.0.0; until it lands Windows reads no PLANTOIR_DOWNLOADED: line, explains no stop for a simulation (the raw output is shown) and has no Science simulation row on the Problems tab";
    // The same hold, after the mac's stack 13 (956defd43, #800, #829, #897 piece B, #904).
    private const string Reason829 = "a lease whose start is in WHOLE seconds, compared on whole seconds (the one deploy.sh writes since the mac's #829), is #956's piece of v2.0.0 (Windows' issue for the mac's #829, now closed); until it lands nothing on Windows writes such a lease (deploy.ps1 takes none yet, and this app's own leases carry the start to the microsecond), so no hold here is read as gone this way";
    // The same hold, brought up to dev 39d83a0a7 (2026-11-18): stack 14's #901 piece 901a and #952.
    // The mac's #909 (2026-11-26): a whole-course restore staged, with a record and a settle at the next reading.
    private const string Reason873 = "a whole-course restore that is staged, with a record in courses/.internal/restoring and a settle at the next reading (the mac's #909, backups.restoreWholeCourse), is #873's piece of v2.0.0; Windows' restore (#873) will write these events and does not yet: until it lands Windows' whole-course restore empties the course first, stages nothing, keeps no files aside and settles nothing, so none of these four can happen here; and its one-section restore keeps the folders backups leave out in its aside copy (#911), never beside the backups, so 'section restore kept files' (the mac's #909, backups.restoreOneSection.leftOutFolders) cannot happen here either";
    private const string Reason901 = "a built site that leaves off the course's files no published page uses, with its trail line and the build that stops at the follow limit (the mac's #901 piece 901a, shared code in build_site.py and site_files.py), is #901's piece of v2.0.0 to check and finish on Windows; until it lands this app records no 'site leaves off files' line and explains no follow-limit stop (the raw output is shown, the contract's honest fallback)";
    private const string Reason921NetlifyStep = "the Netlify token's TTL step now says that the next deploy names a saved token that no longer works and that Settings shows whether it still works (the mac's #696, corrected by #952); Windows' Settings shows neither until #921 lands, so its older words for that step are the true ones here";
    private const string Reason899Measured = "Windows refuses these editJSON cases until its key order and number reading are measured to match the mac's Foundation (#899 W6 review 2): the mac sorts keys beyond ASCII by Unicode collation, takes canonically equivalent keys (an accent written two ways, the Kelvin sign and K) and a key or text with a byte-order mark in front for one, and reads a number with an exponent and more than 17 digits, or more than 38 without, as a decimal number or not at all; Windows answers cannot tell, or refuses to write, rather than guess";
    private const string Reason1004JournalReading = "the mac's #1004 (2026-11-26): the newest segment gone between the listing and its reading is an unreadable list; Windows reads it so already (UndoJournal.cs, the newest is never passed over) but its replay has no call for it; and (#1004-b) a segment name with a digit that is not ASCII is not a segment (Windows' SegmentName pattern uses \\d, which matches any Unicode digit, and int.Parse then meets it), and a step whose madeAt is not a moment is a barrier that carries the previous step's time (Windows matches; its replay has no call for it)";
    private const string Reason899W8U4b2LinkedFolder = "the mac's U4b2-15 for #899 (2026-11-26): Rename folder renames a per-section or shared folder that is itself a symbolic link by moving the LINK as one op of its step (opKinds.move's linkSha), never what it leads to, with the page walk never going through a link; Windows' W8 (Rename folder through the door) builds it: today Plantoir.Core SpecialFolderRenamer.Rename moves each place with Directory.Move outside the door, and RelinkPages walks PagePaths.MarkdownPages, which recurses into every entry whose attributes hold FileAttributes.Directory, a link to a folder included, so it walks through the link; until W8 lands this replay does not know the call renameAPerSectionFolderThatIsALink (since W8-6 Windows moves a link as itself through the door, UndoMoveSides judging it by its linkSha, so only the rename's own plan is owed)";

    private const string Reason899W8U4b = "the mac's U4b for #899 (2026-11-20): opKinds.wholeOps' one exception, an edit named at a move's new place after the move, made and redone after it, taken back before it, with the move judged as if its own edits there were taken back, which Windows reads, judges and swaps since W8-2 (UndoOp.MoveCarries, UndoCheck.Carriers and the listing override, the carrying move first going forward, the swap's own staged and kept files inside the folder left out of its last look and carried with it; since W8-3 the step's own staged and kept files from ANY of its swaps left out of the plan's judgement of the move on either side and of the swap's last look, UndoSwap.StepsOwnFilesInside, its tidy looking where the folder is now and a carried page's kept original looked for where the page is; since W8-4 a folder a carried edit made inside the moved folder, holding only files left out, left out of the judgement with them, each such folder decided on its own beside an empty folder of the content's own (UndoMoveSides.FoldersTheContentLacks), and removed where it is once every swap is in, when empty but for a regular .DS_Store (UndoSwap.RemoveAFolderLeftOut); a folder move's listingSha no longer asked for as a blob; UndoOp.PartInside the one comparison for at or inside; since W8-5 a capitalisation-only move, from and to spelled alike but for case in the last part only, readable (UndoOp.IsCaseOnlyMove), judged by the spelling the folder lists and renamed by one MoveFileEx only while it lists the spelling it leaves, UndoMoveSides.SpellingListed; since W8-6 a symbolic link or junction moved as itself, opKinds.move's linkSha, the SHA-256 of the target it holds as stored, judged without following it, its place kept inside the working folder by the folder above it alone, and carrying no edit; since W8-7 its recovery, a step killed between its move and the edits it carries settled whole, by content: a carried edit read where its folder is now, the move judged as if the step's edits inside were taken back and without its own files inside, and the tidy and the kept copies looked for beside the carried page at the folder's old place too, UndoRecovery.CarryingMoveState and UndoStep.PathsToTidy); still owed: in undo-action-steps.json the recorded steps renameFolder and renameFolderPerSection (U4b2-11, with the key folderMoves), whose Windows action, Rename folder, does not make one step through the door until W8; and in undo-traces.json → actionTraces those two steps' twelve traces (U4b2-12: each folder laid at its from as its listing, one move per folder first, the carried pages named at the new place, a folder hashed by its listing), which this replay stops at its own guard before any door is asked, because the steps hold folderMoves (their members it makes as their recorded editJSON ops since W8-11), and which it cannot make until it lays folderMoves and makes the moves first";
    private const string Reason899W4cWithW7 = "the merge of the mac's U3b and U3c for #899 (2026-11-20): a rollover's Undo needs no content from the list, so no kept original is looked for for a moveApart or a setAside, and a rollover's Undo that leaves its record apart never touches another step's kept original, which is still used by its hash; Windows runs these once both W4c (kept-original recovery) and W7 (the rollover as a step) have landed, whichever is later; until then this replay does not know the calls and keys those cases use";
    private const string Reason899W7U3b = "the mac's U3b for #899 (2026-11-20): the rollover as one step, whose site markers are the op kind moveApart (judged as move, but an Undo or Redo that finds it changed since leaves it and goes on with the rest: Russell's ruling of 2026-11-19 on Q3, #959), and a step's moveApart ops move as a group, all left apart when any one is changed since (the director's decision of 2026-11-20), as is a deploy set for later the swap cannot set at an Undo or Redo (the U3b review's LOW 3); a leftover no deploy reads is the op kind setAside, judged as move and standing apart ON ITS OWN, never one of that group, and a deploy set for later put back whose job will start only at the next login is named in startsAtTheNextLogin with its own sentence, undoScheduleStartsAtTheNextLogin (U3b's fix round three, 2026-11-20; which record a deploy reads is undo.netlifyRecordCases, which W7 runs as well); Windows' W7 for #899 builds it (documentation 12, the W7 row); until it lands this app's reader takes moveApart for a kind it does not know, which the contract makes a barrier that is never acted on and never a reason to clear, so nothing it reads is guessed at";
    private const string Reason899MenuCopy = "the menu's copy of a class as the next class (#927, the mac's #897 piece A) is ONE undo entry on the mac's old in-memory list; the night-3 ruling (no new action gets an entry in the old lists, no interim states) leaves it to the journal step the mac's U3a defines, so Windows records no entry for it on the old list, and Undo Last Change does not take the copy back: it takes back the change BEFORE the copy, the menu's last change with an entry (an Add Class… as the next class, say, whose page it removes unless edited since; the course copy saved before the copy is the way back). Since W7b2-3 the copy IS that journal step (duplicateAsTheNextClass, made by the menu); Edit ▸ Undo offering it is W11b's, and until then no Windows control takes it back";

    /// <summary>
    /// The outside doors the contract names that this app does not have,
    /// checked both ways (<see cref="GapsIn(string, IEnumerable{string}, IEnumerable{string})"/>):
    /// a door is "here" when <c>SubjectMenuRules.ReviseTarget</c> or
    /// <c>CourseActivity.ReviseItem</c> carries it.
    /// </summary>
    internal static IReadOnlyCollection<string> OutsideDoorsHeld(IEnumerable<string> namedByTheContract) =>
        GapsIn(OutsideDoors, namedByTheContract, OutsideDoorsHere());

    /// <summary>The door keys this app has, read from its two Revise enums.</summary>
    internal static IEnumerable<string> OutsideDoorsHere() =>
        Enum.GetValues<Plantoir.Core.Models.SubjectMenuRules.ReviseTarget>().Select(Plantoir.Core.Models.SubjectMenuRules.ContractName)
            .Concat(Enum.GetValues<Plantoir.Core.Models.CourseActivity.ReviseItem>().Select(item => item.ToString().ToLowerInvariant()))
            .Distinct();

    /// <summary>A launcher-runner row key, as the runner builds it: the list label, a TAB, the case name.</summary>
    private static string Row(string list, string name) => list + "\t" + name;

    /// <summary>One case of a launcher list that BOTH launchers run, held for each.</summary>
    private static IEnumerable<string> BothLaunchers(string list, params string[] names) =>
        new[] { "deploy.ps1", "preview.ps1" }.SelectMany(launcher => names.Select(name => Row(list + "/" + launcher, name)));

    private static readonly Entry[] Entries = new IEnumerable<Entry>[]
    {
        // ---- step 0 of v2.0.0: activityTrail.mustRecord (22; "course
        // restored from a backup" is built in step 0 itself, ruling F3;
        // #799's "site built again before deploying" went when #799 landed).
        Owed(ActivityTrailEvents, 823, V200, Reason823,
             "course created for reference", "course could not be created for reference", "zip could not be read for reference"),
        Owed(ActivityTrailEvents, 826, V200, Reason826,
             "reference course replaced", "reference course could not be replaced", "unfinished replace of a reference course put right"),
        Owed(ActivityTrailEvents, 827, V200, Reason827,
             "reference group made", "reference group renamed", "reference group removed", "reference course moved to a group",
             "reference groups not changed", "reference groups started again"),
        Owed(ActivityTrailEvents, 801, V200, Reason801, "looked at a course's unit plans", "asked an assistant to plan a unit"),
        Owed(ActivityTrailEvents, 820, V200, Reason820, "opened a unit plan in the browser"),
        // 790a (2026-11-13): Plan a Unit's third button arrived with the mac's #783.
        Owed(PlanAUnitButtons, 884, V200, Reason884, "copilot"),
        Owed(ActivityTrailEvents, 811, V200, Reason811,
             "looked at a section's curriculum coverage", "asked to make a section's coverage map again"),
        Owed(ActivityTrailEvents, 824, V200, Reason824,
             "unit plans shared", "unit plan share refused", "unit plan sharing stopped", "unit plan password changed"),

        // ---- step 0: assist-wording.json → wording. #828's
        // deployRefusedWhileItsSectionIsBeingBuilt and #854's two sentences
        // in #835's words (courseIsBeingBuiltElsewhere,
        // deployRefusedWhileALaterDeployWorks) landed with 828a.

        // ---- step 0: app-rules.json → credentials and launcher flags
        // (#828's --for-deploy landed with 828a)
        Owed(CredentialPromptCases, 824, V200, Reason824,
             "Choose a username for these unit plans: ",
             "Please choose a username of 1 to 32 letters, digits, dots, dashes or underscores: ",
             "Choose a password for these unit plans (8 to 64 characters): ",
             "Please choose a password of 8 to 64 letters, digits, spaces or symbols: "),
        Owed(CredentialRequestNames, 824, V200, Reason824, "unitPlanUsername", "unitPlanPassword"),
        Owed(DeployLauncherExtras, 824, V200, Reason824,
             "--plans", "--protect", "--remove-password", "--change-password", "--send-answer-keys-openly",
             "--password-only", "--include-answer-keys", "--stop-sharing", "--year"),

        // ---- step 0: shared-rules.json → deployWhileItsSectionDeploys, and
        // the launcher runner's rows: none held open. #828's fifteen
        // launcherCases rows, its two "already being built" sentences and
        // their rows, and #854's two "later" sentences, their rows and the
        // "later" trail line all landed with 828a (2026-11-13).

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
        // The unit-plan username request's explanation took {machine} on the
        // mac (#863, dev 5df8602dc); the request itself is held for #824 above,
        // and is said filled when that piece adds it.
        Owed(MachineWordUsedIn, 824, V200, Reason824,
             "app-rules.json:credentialRequests.requests[7].explanation"),

        // ---- #884's first part (2026-11-13): what the mac's #783 (GitHub
        // Copilot, and the busy sentences naming the assistant) and #850
        // (Open in Browser for a deployed folder) brought. The two doors'
        // PLANTOIR_DOOR_ASSISTANT was built at once, not held.
        Owed(OutsideDoors, 884, V200, Reason884Door, "copilot"),
        Owed(SubjectMenuItems, 884, V200, Reason884Door, "courseReviseWithCopilot", "sectionReviseWithCopilot"),
        Owed(AssistWordingSaidDifferently, 884, V200, Reason884Naming,
             "availableOnceYouFinishRevisingWithClaude", "finishTheClaudeSessionFirst",
             "claudeIsRevisingTheCourseRename", "claudeIsRevisingTheCourseRestore", "claudeIsRevisingTheCourseAddSection",
             "backupKeptForAClaudeSession", "backupsKeptForAClaudeSession",
             "finishTheClaudeSessionToDeleteItsBackup", "finishTheClaudeSessionToDeleteItsBackups"),
        Owed(TrailLineSaidDifferently, 884, V200, Reason884Naming, "outside session held a course"),

        // ---- #868's held-by-name piece (2026-11-13): what the mac's #835
        // part 3 (holds narrow to the section) and #855 (Set Up an
        // Assistant…) brought. #839's Help and #902 turned nothing red here.
        Owed(AssistWordingKeys, 868, V200, Reason868Sections, "sectionIsBeingBuiltElsewhere"),
        Owed(ActivityTrailEvents, 903, V200, Reason903,
             "outside assistant set-up opened", "outside assistant set-up record set aside", "outside assistant set-up started",
             "outside assistant set up", "outside assistant could not be set up", "outside assistant set-up settled",
             "outside assistant sign-in opened", "outside assistant sign-in checked", "outside assistant removed"),
        Owed(QuitCases, 903, V200, Reason903, "an outside assistant is being set up"),
        // #990's Windows half (2026-11-19): the dimmed button's help text.
        Owed(FixWithWordsSaidDifferently, 903, V200, Reason903SetUpItem, "notInstalledHelp"),

        // ---- #911's held-by-name piece (2026-11-14): what the mac's #897 C
        // (Restore from Backup… puts back one section, staged) and #785a (the
        // shared Media store for small backups) brought. Their case lists
        // (backups.restoreOneSection, backups.sharedMedia, file-formats.json →
        // sharedMediaStore) have no reader here yet, so they are unrun, not red.
        Owed(ActivityTrailEvents, 912, V200, Reason912,
             "backup kept its Media files once", "shared backup Media swept", "backup Media not found"),

        // ---- the fourth hold (2026-11-14): what the mac's fourteen pieces
        // brought at cadd8eb11. #891's two wizard tests were made to read the
        // contract without the switch (test code only, #920 item 3); the
        // redactor's 24 cases are NOT held: a credential shape that leaks is
        // a defect (#941), never a gap.
        Owed(ActivityTrailEvents, 921, V200, Reason921,
             "deploy token changed in Settings", "deploy token removed in Settings",
             "deploy token change refused in Settings", "old deploy token kept in Settings",
             "Cloudflare token end date learned"),
        Owed(ActivityTrailEvents, 936, V200, Reason936,
             "files for the site downloaded", "files for the site could not be downloaded"),
        Owed(UndoEditJsonCasesRefusedHere, 899, V200, Reason899Measured,
             "a new object's keys beyond ASCII: the mac sorts them by Unicode collation (an emoji first, \u00e9 between E and f, a full-width \uff21 beside A, \u00df after ss, a tab passed over)",
             "a new object holding \u00e9 written two ways (one character, and e with a combining accent): the mac takes them for one key",
             "a key path part beyond ASCII finds the member the file spells another way (\u00e9 as one character in the op, e with a combining accent in the file)",
             "a key path part beyond ASCII, spelled as the file spells it",
             "the Kelvin sign in a file's key is the letter K to the mac: the member is found and its value moved",
             "a file's key that starts with a byte-order mark (written \\ufeff) is the key without it to the mac: the member is found and its value moved"),
        Owed(UndoCheckCasesRefusedHere, 899, V200, Reason899Measured,
             "editJSON: a file's number spelled with an exponent and more than 17 digits is read by the mac as a decimal number, whose double is not the nearest one: the step's value is that double",
             "editJSON: a file's number spelled with an exponent and more than 17 digits, the step's value its nearest double, which the mac does not read from it",
             "editJSON: a member holding an object whose key is \u00e9 written as e with a combining accent, the step's value \u00e9 as one character",
             "editJSON: a key path part \u00e9 as one character, the file's key e with a combining accent, the step having added the member",
             "editJSON: a member holding text that starts with a byte-order mark (written \\ufeff), which the mac reads without it",
             "editJSON: a file's key that is the Kelvin sign, the key path the letter K, the step having added the member",
             "editJSON: another member's number written with 168 digits after the point, which the mac cannot read: the file is not JSON there"),
        Owed(UndoStackCases, 899, V200, Reason899W8U4b2LinkedFolder,
             "U4b2-15, Rename folder of a per-section folder that is itself a link to a folder: the link renamed as itself by the rename's own plan, one step, and Undo puts it back with the same target, the folder it leads to untouched",
             "U4b2-15, Rename folder of a per-section folder that is itself a link: undone and redone, the link renamed again with the same target, the folder it leads to untouched"),
        // ---- U2b (the mac's U2b for #899, 2026-11-19): the six op kinds and
        // recompute run were held here from 2026-11-19 (60 checkCases, 19
        // stackCases, 15 traces, 21 recoveryCases) and went when Windows' W6
        // built them (2026-11-20).
        Owed(UndoCheckCases, 899, V200, Reason899W7U3b,
             "moveApart (U3b): judged as move is: the place it left free, the place it went holding it: as the step left it",
             "moveApart (U3b): back where it was, the other place free",
             "moveApart (U3b): a deploy wrote a new marker in the place it left: changed since, as for move (the STEP leaves it apart, stackCases)",
             "setAside (U3b): judged as move is: the place it left free, the place it went holding it: as the step left it",
             "setAside (U3b): back where it was, the other place free",
             "setAside (U3b): its kept copy deleted by hand: changed since, as for move (the STEP leaves it apart on its own, stackCases)"),
        Owed(UndoStackCases, 899, V200, Reason899W7U3b,
             "U3b, Q3 (Russell, 2026-11-19; #959): a rollover onto a new website, a deploy writes a new marker in its place, Undo: the rest is taken back, both markers kept, the marker named as left apart, and the step leaves the undo side",
             "U3b, Q3: and the step before it can still be undone",
             "U3b, Q3: Redo takes the rest forward again and leaves both markers again",
             "U3b: with no deploy between, Undo puts the marker back with the rest and leaves nothing apart",
             "U3b, records as a group (the director's decision, 2026-11-20, on #899): a rollover onto new websites on two hosts, a deploy that reaches one host only, Undo: BOTH records are left apart, never one back and one not, so the section is never split across two websites; the rest is taken back",
             "U3b, records as a group: with no deploy between, both records go back with the rest and nothing is left apart",
             "U3b, records as a group: Redo after that Undo takes the rest forward and leaves both records where they are",
             "U3b: a deploy set for later that cannot be set again at Undo (launchd refuses it, or the write is off the main thread) is left as it is and named as left apart, as a record is; the rest is taken back and the Undo is never refused for it",
             "U3b, a leftover on its own (the review of U3b's fixes, LOW 3): a rollover that set a leftover aside, its kept copy deleted by hand, Undo: the record and the rest go back, the leftover is left as it is and named, and never keeps the record apart",
             "U3b, a leftover on its own: Redo after that Undo takes the record and the rest forward, and leaves the leftover and names it again",
             "U3b, a leftover is never one of the records: a deploy fills the record's place, Undo: the record stays apart, the leftover goes back with the rest",
             "U3b, a leftover: with nothing changed between, Undo puts the record and the leftover back with the rest and leaves nothing apart",
             "U3b: a deploy set for later put back at Undo whose job the computer will not start now, and which cannot be taken away again, starts at the next login: named as such, never as left apart and never as simply back (the re-review of U3b's fixes, LOW 2); the rest is taken back"),
        Owed(AssistWordingKeys, 899, V200, Reason899W7U3b, "undoScheduleStartsAtTheNextLogin"),
        // The rollover (moves) and Rename folder (folderMoves) traces below fail by the
        // replay's own guard, which names the part of the step it does not make
        // yet, before any door is asked (part three, review 1, LOW 2): they can
        // pass only once that guard is taken out for their kind.
        Owed(UndoActionStepsOnWindows, 899, V200, Reason899W7U3b, "rollOverOntoANewWebsite", "rollOverKeepingTheWebsite"),
        Owed(UndoActionStepsOnWindows, 899, V200, Reason899W8U4b, "renameFolder", "renameFolderPerSection"),
        Owed(UndoActionTraces, 899, V200, Reason899W7U3b,
             "action-121", "action-122", "action-123", "action-124", "action-125", "action-126",
             "action-127", "action-128", "action-129", "action-130", "action-131", "action-132"),
        Owed(UndoActionTraces, 899, V200, Reason899W8U4b,
             "action-151", "action-152", "action-153", "action-154", "action-155", "action-156",
             "action-157", "action-158", "action-159", "action-160", "action-161", "action-162"),
        Owed(UndoStackCases, 1004, V200, Reason1004JournalReading,
             "#1004: the newest segment gone after the list was listed: the list cannot be read, the undo is refused, nothing is cleared",
             "#1004-b: a file named journal- and six digits that are not ASCII is not a segment: the step in it is not read, nothing new is offered, nothing is cleared",
             "#1004-b: a step whose madeAt is not a moment, on top of a readable one: a barrier, never undone, never cleared, and with the step before's time it is not old"),
        Owed(UndoStackCases, 899, V200, Reason899W4cWithW7,
             "U3b with U3c: the Undo of a rollover of only its records, a leftover and the year, with the list's content gone, needs nothing from it (each record and leftover is a rename judged by its hash, the school year a member derived from the file), so no kept original is looked for and the Undo goes, never refused for content missing",
             "U3c with U3b: a later rollover's Undo that leaves its record apart keeps an earlier page's kept original beside it, untouched",
             "U3c with U3b: an earlier page's kept original, the only copy of what it held, outlives a later rollover's Undo that leaves its record apart, and that page's Undo is then put back from it"),
        // ---- U3c (the mac's U3c for #899, 2026-11-20): its 4 trail events, 12
        // stackCases and 10 recoveryCases were held here under a reason then
        // named Reason899W4c (later named Reason899U4aContentGone, which held
        // only U4a's three rows) and went when Windows' W4c built them
        // (2026-11-20, night). U4a's two (a) rows went when W8-10 taught the
        // replay afterContentGone and keptBesideThePage (2026-11-26), with
        // that constant; the (b) row went when W8-10b built the thinning of kept
        // copies (2026-11-27), with Reason899U4aThinning. The
        // U4b2-4 row (two pages named index.md) was held under
        // Reason899W4cKeptLineByPath until W8-9 built the kept line by path
        // (2026-11-26), and that constant went with it. The kept-file alert's
        // four keys were held under Reason899W4cKeptAlert until W7b2-9 built
        // the alert (2026-11-25).
        Owed(MachineWordUsedIn, 921, V200, Reason921, "shared-rules.json:deployTokens.words.problemCouldNotSave"),
        Owed(CredentialRequestsSaidDifferently, 921, V200, Reason921, "cloudflareToken"),
        Owed(CredentialRequestsSaidDifferently, 920, V200, Reason920, "teacherSurname", "siteName", "siteNameConflict"),
        Owed(FailureExplanationCases, 936, V200, Reason936,
             "#674 keptDownloads.stop, notReady (phetFences.stop.passFails)",
             "#674 keptDownloads.stop, one simulation, offline",
             "#674 keptDownloads.stop, three on three pages, offline (one simulation twice)",
             "#674 keptDownloads.stop, eleven, offline",
             "#674 keptDownloads.stop, one that arrived as something else"),
        Owed(FailureExplanationCases, 921, V200, Reason921,
             "GitHub #696, the second ruling and review MUST 1",
             "GitHub #696, the paste rule (deployTokens.paste), in deploy.ps1's shape"),
        Owed(SectionProblemKinds, 936, V200, Reason936, "phetSimulationsNotReady"),
        // #927 (2026-11-20): the menu's copy records no entry on the old list.
        Owed(MenuCopyUndoEntries, 899, V200, Reason899MenuCopy,
             "the copy is the section's next class, and nothing else moves",
             "a course-level page with the same title is not the source",
             "a class page with no numbers in its name can be duplicated",
             "a numbered course's copy is its next number",
             "a source carrying a per-section publish key still gives a hidden copy"),
        Owed(LeaseLivenessCases, 956, V200, Reason829,
             "#829: a deploy typed in Terminal - bash, its start in whole seconds - is alive while that bash runs"),
        // Stack 14 (dev 39d83a0a7), folded into the same hold on 2026-11-18.
        Owed(ActivityTrailEvents, 901, V200, Reason901, "site leaves off files no published page uses"),
        Owed(FailureExplanationCases, 901, V200, Reason901,
             "#901 piece 901a, shared-rules.json -> siteFiles.followed.limitsRule",
             "The same stop in a preview (siteFiles.words.followLimitStoppedPreview), lifted the same way."),
        Owed(CredentialRequestsSaidDifferently, 921, V200, Reason921NetlifyStep, "netlifyToken"),
        // The mac's #909 (2026-11-26): the whole-course restore is staged.
        Owed(ActivityTrailEvents, 873, V200, Reason873,
             "course restore left as it was", "course restore stopped part way",
             "unfinished restore settled", "course restore kept files",
             // The mac's #909 (2026-11-26): a one-section restore keeps the left-out folders beside the backups.
             "section restore kept files"),

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

    /// <summary>
    /// For a theory case held open by name: runs the case's own assertions,
    /// and passes only while they still FAIL, and fail for the named gap (the
    /// failure's message carries one of <paramref name="gapWords"/>). A held
    /// case that passes is the gap closing (<see cref="ClosedMessage"/>); one
    /// that fails for any other reason is a real failure, reported as itself.
    /// </summary>
    internal static void HeldCaseStillStopsAtItsGap(Entry held, Action runTheCase, params string[] gapWords)
    {
        Exception? stopped = null;
        try { runTheCase(); }
        catch (Exception failure) { stopped = failure; }
        Assert.True(stopped is not null, ClosedMessage(held));
        bool namesTheGap = gapWords.Any(word => stopped!.Message.Contains(word, StringComparison.Ordinal));
        Assert.True(namesTheGap,
            $"\"{held.Key}\" is held open (issue #{held.Issue}: {held.Reason}) for the gap it names, " +
            $"and it failed for another reason, which is a real failure: {stopped!.Message}");
    }

    /// <summary>What to say when a ledgered thing has started existing on this side.</summary>
    internal static string ClosedMessage(Entry entry) =>
        $"\"{entry.Key}\" is ledgered as not built here yet (issue #{entry.Issue}, " +
        $"{entry.Milestone}: {entry.Reason}) — and it now EXISTS on this side. That is the " +
        "gap closing. Delete this entry from windows-app/Plantoir.Tests/NamedGapLedger.cs so " +
        $"the full assertion comes back, and say so on issue #{entry.Issue}.";
}

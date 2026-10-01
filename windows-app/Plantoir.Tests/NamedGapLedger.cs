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
/// gaps listed below is like that. Windows OWES every one of them, on the parity
/// milestone, and writing <c>appliesOn: ["mac"]</c> would therefore be a lie in the file both
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
/// rather than remembered: all three were declared in <c>a3144010</c> at 08:17
/// on 2026-08-25 and all three got their first <c>ActivityTrail.Note</c> call
/// in <c>a3c581fb</c> at 08:45 the same morning — <b>28 minutes</b>, inside one
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

    /// <summary>
    /// The milestone every entry below names. While no Windows release is
    /// being cut, an entry may name an open issue on this milestone itself:
    /// the entries are that milestone's BURN-DOWN LIST, and the milestone
    /// cannot close — nor a Windows release be cut — while any remains
    /// (Russell, 2026-09-25, reconfirmed 2026-09-30; <c>contracts/README.md</c>
    /// → "Named gaps"; <c>WINDOWS-PARITY.md</c> → section 8).
    /// </summary>
    private const string Parity = "Windows: parity with mac v1.4.0";

    /// <summary>
    /// One thing the contract names and this app does not have yet.
    /// </summary>
    /// <param name="Area">Which contract list the key belongs to.</param>
    /// <param name="Key">The event name or sentence key, spelled as the contract spells it.</param>
    /// <param name="Issue">The open GitHub issue that owns the work.</param>
    /// <param name="Milestone">The milestone that issue carries. Normally LATER
    /// than the release being cut; while no Windows release is being cut it may
    /// be the parity milestone itself, and then the entries ARE that
    /// milestone's burn-down list — it cannot close while any remains
    /// (<c>contracts/README.md</c> → "Named gaps").</param>
    /// <param name="Reason">Why it is not built here yet, in a sentence.</param>
    internal sealed record Entry(string Area, string Key, int Issue, string Milestone, string Reason);

    /// <summary>Several keys of one area owned by one issue, for one reason.</summary>
    private static IEnumerable<Entry> Owed(string area, int issue, string reason, params string[] keys) =>
        keys.Select(key => new Entry(area, key, issue, Parity, reason));

    private static readonly Entry[] Entries = new[]
    {
        // ---- activityTrail.mustRecord: events this app does not declare yet.
        // Mapped 2026-09-30 (bundle 1) from each event's own #references to
        // the open `windows` issue that carries that mac piece. Each goes when
        // its feature lands, and its mend-check says so.
        Owed(ActivityTrailEvents, 320, "reopening the last working folder does not record either outcome yet (mac #311)",
            "working folder reopened", "working folder not reopened"),
        Owed(ActivityTrailEvents, 387, "Course Settings does not hold a save back yet (mac #373)",
            "settings save held back"),
        Owed(ActivityTrailEvents, 250, "the New Course wizard does not record the course it made yet (mac #248/#251/#267)",
            "course created"),
        Owed(ActivityTrailEvents, 196, "a cut-off model reply is not detected here yet (mac #198)",
            "assistant answer was cut off"),
        Owed(ActivityTrailEvents, 217, "an echoed reply is not refused here yet (mac #215)",
            "assistant repeated the request back"),
        Owed(ActivityTrailEvents, 305, "the other-course refusal of mac #167 is not built here yet",
            "assistant was asked about another course"),
        Owed(ActivityTrailEvents, 348, "Revert does not record the exclusions it put back yet (mac #152)",
            "exclusions reverted"),
        Owed(ActivityTrailEvents, 261, "setting a deploy does not say what it replaced or record a refusal yet (mac #195)",
            "scheduled deploy replaced", "scheduled deploy could not be set"),
        Owed(ActivityTrailEvents, 241, "this app has no courses kept for reference yet (mac #206 branch A)",
            "course kept for reference", "course could not be kept for reference",
            "reference course school year changed", "reference course pages locked again"),
        Owed(ActivityTrailEvents, 244, "this app cannot import courses for reference yet (mac #206 branch B)",
            "course imported for reference", "course could not be imported for reference",
            "unfinished import for reference tidied away", "course import for reference stopped"),
        Owed(ActivityTrailEvents, 247, "this app cannot copy a page from another course yet (mac #207)",
            "pages copied from another course"),
        Owed(ActivityTrailEvents, 406, "Preview does not offer today's class for the front page yet (mac #397)",
            "put today's class on the front page", "left the front page as it was"),
        Owed(ActivityTrailEvents, 283, "backups cannot be deleted several at once here yet (mac #242)",
            "backups deleted"),
        Owed(ActivityTrailEvents, 324, "clicking a scheduled-publish toast is not recorded yet (mac #306)",
            "scheduled publish notification"),
        Owed(ActivityTrailEvents, 337, "this app does not find or install its own updates yet (mac #204)",
            "update found", "update check found nothing new", "update answered", "update held while work is under way",
            "update installing", "update set aside", "update stopped", "app updated"),
        Owed(ActivityTrailEvents, 340, "this app has no How I Teach page yet (mac #209)",
            "How I Teach page read", "How I Teach page written", "How I Teach page kept off the website"),
        Owed(ActivityTrailEvents, 360, "Course Settings has no How I Teach row yet (mac #329)",
            "How I Teach page started"),
        Owed(ActivityTrailEvents, 345, "one coverage map per curriculum folder is not built here yet (mac #128)",
            "curriculum maps built"),
        Owed(ActivityTrailEvents, 360, "the assistant's own backup of a course is not recorded yet (mac #351)",
            "assistant backed up a course"),
        Owed(ActivityTrailEvents, 355, "this app has no Get Ready for the Start of the Year yet (mac #96)",
            "section made ready for the start of the year", "start of the year change undone", "start of the year not done"),
        Owed(ActivityTrailEvents, 392, "the links-into-hidden-pages checklist is not built here yet (mac #379)",
            "offered to publish pages that links lead to", "published pages that links led to",
            "left pages hidden that links lead to"),

        // ---- specialNames.platformWording.keys

        // ---- file-formats.json → courseConfigKeys: keys CourseConfiguration.cs does not name.
        Owed(CourseConfigKeys, 345, "one coverage map per declared curriculum folder is not built here yet (mac #128)",
            "curriculum_folders"),
        Owed(CourseConfigKeys, 274, "this app has no clubs yet, so a course cannot say its class noun, page scheme or front-page heading (mac #267)",
            "class_page_scheme", "front_page_heading", "class_noun"),
        Owed(CourseConfigKeys, 241, "this app has no courses kept for reference yet (mac #206 branch A)",
            "kept_for_reference", "reference_school_year"),

        // ---- class-planning.json → sectionIndexPointer.dateCases (pointAt cases)
        Owed(FrontPageDateCases, 274,
            "this app's pointer finds only the class heading; a club's front-page heading arrives with clubs (mac #267)",
            "a club's front page, numbered pages"),

        // ---- shared-rules.json → gradedFolders.newCourse.cases (#317's runner)
        Owed(GradedFoldersNewCourseCases, 250,
            "declining a payload does not give the subject's skeleton and its pool here yet (mac #248)",
            "a declined payload keeping its skeleton takes the SKELETON's pool"),
        Owed(GradedFoldersNewCourseCases, 274, "this app has no clubs yet (mac #267)",
            "a club typed with a payload code is not given the payload's pool"),

        // ---- app-rules.json → modelTiers.requirements
        Owed(ModelTierRequirements, 196, "a cut-off model reply is not detected here yet (mac #198)",
            "A reply the engine stopped part way runs no tool and says so"),
        Owed(ModelTierRequirements, 262, "a finished reply that wrote nothing is not checked against the window here yet",
            "A finished reply that wrote nothing runs a tool only when the window supplies everything that tool needs"),

        // ---- assist-wording.json → wording: sentences with no same-named
        // member here. Some are said by this app today in words built
        // inline elsewhere; the walker cannot see those, and hoisting them
        // into AssistWording under their key is #157's remaining half. The
        // rest belong to features this app does not have yet.
        Owed(AssistWordingKeys, 274, "this app has no clubs yet, so it has no meeting-worded sentences (mac #267)",
            "addedTheNextPageForAMeeting", "allScheduledDatesHaveConcludedForAMeeting", "datesForTheNextPageForAMeeting",
            "datesNotGivenYetForAMeeting", "datesToDuplicateForAMeeting", "datesToFindADaysPageForAMeeting",
            "datesToReDateForAMeeting", "datesToReplaceForAMeeting", "everyDateIsSpokenForForAMeeting",
            "linkedClassesWereLeftAloneForAMeeting", "linkedClassStaysVisibleForAMeeting", "linkedClassWasLeftAloneForAMeeting",
            "madeRoomForAMeeting", "makingRoomCannotBeUndoneForAMeeting", "mayIAskForYourDatesForAMeeting",
            "movedToLaterDaysForAMeeting", "movesAndBecomesADraftForAMeeting", "movesToTheFirstDayForAMeeting",
            "otherClassesWouldMoveAndLinksFollowForAMeeting", "otherClassesWouldMoveKeepingTheirNamesForAMeeting",
            "pagesAcrossTheDatesForAMeeting", "pagesRunFromForAMeeting", "pagesWithNoDayOfTheirOwnForAMeeting",
            "publishedTheClassOnForAMeeting", "reDatedForAMeeting", "reDatedOnlyPagesTheyUseForAMeeting",
            "reDatingOntoTheDatesOnFileForAMeeting", "sharingTheLastDayForAMeeting", "spareDatesAfterTheseForAMeeting",
            "theNextWouldFallOnForAMeeting", "theSemesterBeginsForAMeeting", "wouldAddPagesForAMeeting",
            "wouldMakeRoomForAMeeting", "yourNextUpcomingForAMeeting"),
        Owed(AssistWordingKeys, 340, "this app has no How I Teach page yet (mac #209)",
            "howITeachAlreadyWritten", "howITeachBriefing", "howITeachCarriesNoSettings", "howITeachChangedSincePlanned",
            "howITeachCutShort", "howITeachDraftingBrief", "howITeachEmpty", "howITeachIsNeverPublished",
            "howITeachListedAsNotWritten", "howITeachListedAsWritten", "howITeachMissing", "howITeachNeedsWords",
            "howITeachPlanCreates", "howITeachPlanReplaces", "howITeachRead", "howITeachSaved", "howITeachTooLong"),
        Owed(AssistWordingKeys, 355, "this app has no Get Ready for the Start of the Year yet (mac #96)",
            "startOfYearNeedsABackup", "startOfYearNeedsItsPlan", "startOfYearPlanHasChanged"),
        Owed(AssistWordingKeys, 203, "the link walk stopping at a class page is not wired here yet (mac #173)",
            "linkedClassesWereLeftAlone", "linkedClassStaysVisible", "linkedClassWasLeftAlone"),
        Owed(AssistWordingKeys, 305, "\"what does <page> link to?\" is not answered in code here yet (mac #167)",
            "linkedPageIsADraft", "linkedPageIsMissing", "pageCouldNotBeRead", "pageLinksTo", "pageLinksToNothing",
            "askedAboutACourseThatIsNotHere", "askedAboutAnotherCourse"),
        Owed(AssistWordingKeys, 392, "the links-into-hidden-pages checklist is not built here yet (mac #379)",
            "linksIntoHiddenPagesWillBeOffered"),
        Owed(AssistWordingKeys, 196, "a cut-off model reply is not detected here yet (mac #198)",
            "answerWasCutOff"),
        Owed(AssistWordingKeys, 262, "a finished reply that wrote nothing is not checked against the window here yet",
            "answerLeftOutWhatItWasFor"),
        Owed(AssistWordingKeys, 281, "\"deploy at 6:30\" with no am or pm is not asked about in code here yet (mac #194)",
            "morningOrEvening"),
        Owed(AssistWordingKeys, 288, "a deploy time written a way the family cannot set is not answered in code here yet (mac #277)",
            "sayTheTimeAs", "sayTheTimeAsWithoutTheComma"),
        Owed(AssistWordingKeys, 260, "the scheduled deploy's card does not ask its own question yet (mac #184)",
            "scheduleQuestion"),
        Owed(AssistWordingKeys, 261, "setting a deploy does not say what it replaces yet (mac #195)",
            "scheduleReplaces"),
        Owed(AssistWordingKeys, 241, "this app has no courses kept for reference yet (mac #206 branch A)",
            "askedAboutAReferenceCourse", "deployRefusedForAReferenceCourse"),
        Owed(AssistWordingKeys, 352, "a page list naming no page is not refused in code here yet (mac #197)",
            "morePagesThanOneAreCalled"),
        Owed(AssistWordingKeys, 360, "the assistant's own backup of a course is not built as the mac's is yet (mac #351)",
            "backingUpFirst", "changedWhileSavingACopy", "courseIsBeingCopied"),
        Owed(AssistWordingKeys, 283, "the backups list does not show sizes yet (mac #242)",
            "backupSizeCouldNotBeRead", "backupSizeCouldNotBeReadShort"),
        Owed(AssistWordingKeys, 308, "the plan, re-date and make-room callers do not yet name the pages SetDraft/SetCreated declined as noRoomForAKey (mac #186); the writers themselves decline since bundle 2",
            "pageWhoseNewDateCouldNotBeSet", "pagesWhoseNewDatesCouldNotBeSet", "pagesWhoseSettingsCannotBeAddedTo",
            "pagesWhoseSettingsCannotBeAddedToNamingSeveral"),
        // The class-worded sentences below were ledgered to #157 on the first
        // pass as "said inline today"; a review (2026-09-30) found that false
        // for most. Re-done key by key: seven WERE said word for word and are
        // hoisted into AssistWording (so no entry); the rest go to the issue
        // whose body names the key, and the two no issue names stay on #157
        // with that said plainly (listed for Russell).
        Owed(AssistWordingKeys, 274,
            "not said on Windows; #274 carries the class/meeting pair of sentences this key belongs to",
            "addedTheNextPage", "allScheduledDatesHaveConcluded", "datesForTheNextPage", "datesToDuplicate",
            "datesToFindADaysPage", "datesToReDate", "datesToReplace", "movesToTheFirstDay", "pagesAcrossTheDates",
            "pagesRunFrom", "pagesWithNoDayOfTheirOwn", "sharingTheLastDay", "spareDatesAfterThese",
            "theSemesterBegins", "wouldAddPages", "wouldMakeRoom", "yourNextUpcoming"),
        Owed(AssistWordingKeys, 262, "not said on Windows; #262 specifies it for a call naming no course",
            "noCourseNamed"),
        Owed(AssistWordingKeys, 157,
            "not said on Windows; no open issue names it (listed in QUESTIONS-FOR-RUSSELL.md)",
            "noCoursesYet", "whatPublishingMeans"),
    }.SelectMany(group => group).ToArray();

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
        IEnumerable<string> implementedHere)
    {
        var contract = namedByTheContract.ToHashSet(StringComparer.Ordinal);
        var here = implementedHere.ToHashSet(StringComparer.Ordinal);
        var mine = Entries.Where(entry => entry.Area == area).ToList();

        foreach (var entry in mine)
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

            Assert.True(contract.Contains(entry.Key), whyThisHappened);

            Assert.False(here.Contains(entry.Key),
                $"\"{entry.Key}\" is ledgered as not built here yet (issue #{entry.Issue}, " +
                $"{entry.Milestone}: {entry.Reason}) — and it now EXISTS on this side. That is the " +
                "gap closing. Delete this entry from windows-app/Plantoir.Tests/NamedGapLedger.cs so " +
                $"the full assertion comes back, and say so on issue #{entry.Issue}.");
        }

        return mine.Select(entry => entry.Key).ToHashSet(StringComparer.Ordinal);
    }
}

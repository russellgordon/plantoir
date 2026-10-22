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

    // The milestones, spelled EXACTLY as their GitHub titles. NamedGapLedgerTests
    // parses each entry's milestone as a version and requires it to be LATER
    // than Plantoir.csproj's <Version>; anything that is not a version fails
    // there. (Until 2026-10-15 every entry named one milestone, "Windows:
    // parity with mac v1.4.0", and the ledger was its burn-down list.)
    private const string V150 = "v1.5.0";
    private const string V171 = "v1.7.1";
    private const string V180 = "v1.8.0";

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
    // milestones above. EMPTY since 2026-10-16: #548 closed the sixteen
    // plan-table sentences (mac #524) that #551's piece held open that
    // morning, when the plan table landed. (Empty before that from
    // 2026-10-15, when the catch-up to mac 1.7.1, #481, closed its last two.)
    // Not empty since 2026-10-22: #581's four Obsidian add-on events.

    private const string ObsidianAddOns =
        "Obsidian's add-ons for diagrams and graphs (mac #495) are #581's piece, built after #565's; held so the " +
        "trail test can go green for #565 and #599. Its milestone is v1.8.0, so the 1.8.x version bump turns " +
        "this entry red until #581 lands.";

    private static readonly Entry[] Entries = new IEnumerable<Entry>[]
    {
        // ---- activityTrail.mustRecord. #514's two events ("preview started
        // at the page last viewed", "preview start page chosen in Settings")
        // landed with batch 6; #581 owes these four.
        Owed(ActivityTrailEvents, 581, V180, ObsidianAddOns,
             "obsidian add-ons offered", "obsidian add-ons added",
             "obsidian reopened for add-ons", "obsidian add-ons setting changed"),

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
        // seventeen (mac #475) with 2C, and mac #524's sixteen plan-table
        // sentences (plan*, menuPlan*) with #548's plan table.

        // ---- assist-cases.json → scenarios.cases: none held open. #475's
        // three landed with #489's 2C.
    }.SelectMany(group => group).ToArray();

    /// <summary>Every entry, for <c>NamedGapLedgerTests</c>.</summary>
    internal static IReadOnlyList<Entry> All => Entries;

    /// <summary>
    /// The entry holding <paramref name="key"/> open under <paramref name="area"/>,
    /// or null. For a runner that cannot collect its results into one
    /// comparison — a theory, where each case is its own test — and so checks
    /// the "it now passes" direction itself, with <see cref="ClosedMessage"/>.
    /// </summary>
    internal static Entry? Holding(string area, string key) =>
        Entries.FirstOrDefault(entry => entry.Area == area && entry.Key == key);

    /// <summary>
    /// The contract-direction half of <see cref="GapsIn"/> alone: every entry
    /// under <paramref name="area"/> names something the contract still has.
    /// Paired with <see cref="Holding"/> by a theory's runner.
    /// </summary>
    internal static void StillNamed(string area, IEnumerable<string> namedByTheContract)
    {
        var contract = namedByTheContract.ToHashSet(StringComparer.Ordinal);
        foreach (var entry in Entries.Where(entry => entry.Area == area))
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
        IEnumerable<string> implementedHere)
    {
        var contract = namedByTheContract.ToHashSet(StringComparer.Ordinal);
        var here = implementedHere.ToHashSet(StringComparer.Ordinal);
        var mine = Entries.Where(entry => entry.Area == area).ToList();

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

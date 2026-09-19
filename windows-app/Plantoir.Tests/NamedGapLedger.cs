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
/// built inside the working folder, so there is no moment to record. Neither
/// gap listed below is like that. Windows OWES both of them, at v1.3.0, and
/// writing <c>appliesOn: ["mac"]</c> would therefore be a lie in the file both
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
/// #158 for a stronger reason than tidiness. Those three were a FEW DAYS ahead
/// of their call sites in the same release; the unit-word rename is a whole
/// feature a release away, so the declaration would sit there for a milestone
/// with nothing to write it. And an event that is named but never recorded
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

    /// <summary>
    /// One thing the contract names and this app does not have yet.
    /// </summary>
    /// <param name="Area">Which contract list the key belongs to.</param>
    /// <param name="Key">The event name or sentence key, spelled as the contract spells it.</param>
    /// <param name="Issue">The open GitHub issue that owns the work.</param>
    /// <param name="Milestone">The milestone that issue carries — LATER than the release being cut.</param>
    /// <param name="Reason">Why it is not built here yet, in a sentence.</param>
    internal sealed record Entry(string Area, string Key, int Issue, string Milestone, string Reason);

    private static readonly Entry[] Entries =
    {

        // Renaming a course's word for a unit landed on the mac 2026-09-10
        // (issue #100) and arrived here as the contract moving: the event and
        // the sentence are both parts of a feature this app has none of yet.
        // Issue #158 is the whole handover — the renamer, the plan, the sheet,
        // the sentences and this event — and it is milestoned v1.3.0, after
        // the v1.2.0 cut. Both entries go when that feature lands; neither can
        // be deleted on its own without the other's check noticing.
        new Entry(
            ActivityTrailEvents,
            "word for a unit renamed",
            158,
            "v1.3.0",
            "this app cannot rename a course's word for a unit yet, so there is no moment to record"),

        new Entry(
            PlatformWordedKeys,
            "renameUnitWord.explanation",
            158,
            "v1.3.0",
            "the sentence belongs to a sheet this app does not have yet, so there is nothing here to word"),
    };

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
            // TWO different things bring you here, and the second is the one
            // this ledger exists to catch. Either the contract genuinely
            // dropped the key — fine, delete the entry — or somebody SCOPED it
            // away from this platform, which reaches this check the same way:
            // ContractTests filters `activityTrail.mustRecord` by `appliesOn`
            // BEFORE calling in, so an `appliesOn: ["mac"]` added to quiet a
            // suite arrives here as "the contract no longer names it". Both
            // possibilities are named, because deleting the entry is the right
            // answer to the first and the wrong one to the second.
            Assert.True(contract.Contains(entry.Key),
                $"NamedGapLedger holds \"{entry.Key}\" open under {entry.Area}, and the contract no " +
                "longer names it HERE. Two different things cause that. (1) The contract dropped the " +
                "key outright — the requirement went away, so delete this entry from " +
                $"windows-app/Plantoir.Tests/NamedGapLedger.cs and say so on issue #{entry.Issue}. " +
                "(2) Somebody scoped it away from this platform instead — an `appliesOn` that no " +
                "longer lists \"windows\". Check `git log -p contracts/shared-rules.json` before " +
                "believing (1): scoping is the softening this ledger exists to prevent, it has no " +
                $"mend-check of its own, and issue #{entry.Issue} ({entry.Milestone}) says this " +
                "platform owes the work. If that is what happened, put the contract back and leave " +
                "this entry alone.");

            Assert.False(here.Contains(entry.Key),
                $"\"{entry.Key}\" is ledgered as not built here yet (issue #{entry.Issue}, " +
                $"{entry.Milestone}: {entry.Reason}) — and it now EXISTS on this side. That is the " +
                "gap closing. Delete this entry from windows-app/Plantoir.Tests/NamedGapLedger.cs so " +
                $"the full assertion comes back, and say so on issue #{entry.Issue}.");
        }

        return mine.Select(entry => entry.Key).ToHashSet(StringComparer.Ordinal);
    }
}

using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// What a row of a section's Problems record says, whether the section's
/// sidebar row is marked, and when the alert is raised — as pure functions
/// (#734, the mac's <c>SectionProblemsRules.swift</c>). Each is
/// <c>contracts/shared-rules.json</c> → <c>sectionProblems</c>
/// (<c>rowState</c>, <c>sectionMarker</c>, <c>alert</c>), whose cases
/// <c>SectionProblemsContractTests</c> runs here as the mac runs them.
/// </summary>
public static class SectionProblemsRules
{
    /// <summary>What a row is showing.</summary>
    public enum RowState
    {
        /// <summary>Found by this section's last build.</summary>
        Current,

        /// <summary>
        /// Shown gone by a later build of ANOTHER section that shares the page
        /// — still this section's problem until its own next build, because its
        /// deployed site still carries the page (#717 ruling 11).
        /// </summary>
        FixedInTheSource,
    }

    /// <summary>The contract's spelling of a state (<c>rowState.cases[].expect</c>).</summary>
    public static string ContractName(RowState state) =>
        state == RowState.FixedInTheSource ? "fixedInTheSource" : "current";

    /// <summary><c>rowState.clearsAcrossSections</c>: the kinds that depend on the page alone. Pinned by the contract tests.</summary>
    public static readonly IReadOnlySet<string> ClearsAcrossSections = new HashSet<string>(StringComparer.Ordinal)
    {
        "pageSettingsUnreadable",
        "printPdfNotFound",
        "figuresCouldNotBeDrawn",
        "swiftCouldNotBePrepared",
        "quizzesNotReady",
        "runnableCodeShownAsPlainCode",
        "quizzesReadDifferently",
        "geogebraSketchesNotReady",
    };

    /// <summary><c>rowState.notAboutThePage</c>: reasons that say something about the machine, not the page.</summary>
    public static readonly IReadOnlyDictionary<string, IReadOnlySet<string>> NotAboutThePage =
        new Dictionary<string, IReadOnlySet<string>>(StringComparer.Ordinal)
        {
            ["figuresCouldNotBeDrawn"] = new HashSet<string>(StringComparer.Ordinal) { "tookTooLong", "engineMissing", "graphEngineMissing", "drawingEnded" },
            ["swiftCouldNotBePrepared"] = new HashSet<string>(StringComparer.Ordinal) { "notCompiled", "notDownloaded", "noRoom" },
            ["geogebraSketchesNotReady"] = new HashSet<string>(StringComparer.Ordinal) { "materialCouldNotBeFetched", "engineMissing" },
        };

    /// <summary>The kinds only the site says (<c>sectionProblems.kinds</c> → <c>from: site</c>).</summary>
    public static readonly IReadOnlySet<string> SaidByTheSite = new HashSet<string>(StringComparer.Ordinal)
    {
        "runnableCodeShownAsPlainCode",
        "quizzesReadDifferently",
    };

    /// <summary>
    /// A row of <paramref name="record"/>, given the records of the course's
    /// OTHER sections (<c>rowState.rule</c>).
    /// </summary>
    public static RowState State(SectionProblemRow row, SectionProblemsRecord record, IEnumerable<SectionProblemsRecord> others)
    {
        if (!ClearsAcrossSections.Contains(row.Kind)) return RowState.Current;
        if (NotAboutThePage.TryGetValue(row.Kind, out var machineReasons) && machineReasons.Contains(row.Reason))
            return RowState.Current;
        if (row.Page.Length == 0) return RowState.Current;
        if (record.BuiltAt is not { } builtHere) return RowState.Current;
        // The LATEST other record that shows the page decides, never any clean
        // one (implementation review L1 on #717): a section clean at ten proves
        // nothing once another has broken the page again at eleven.
        if (LatestShowing(row.Page, others) is not { } latest) return RowState.Current;
        return FixesThePage(latest, row, builtHere) ? RowState.FixedInTheSource : RowState.Current;
    }

    /// <summary>Of <paramref name="others"/>, the latest record whose pages include <paramref name="page"/>.</summary>
    public static SectionProblemsRecord? LatestShowing(string page, IEnumerable<SectionProblemsRecord> others)
    {
        SectionProblemsRecord? latest = null;
        foreach (var other in others)
        {
            if (other.BuiltAt is not { } builtThere || !other.PagesShown.Contains(page, StringComparer.Ordinal)) continue;
            if (latest?.BuiltAt is { } current && current >= builtThere) continue;
            latest = other;
        }
        return latest;
    }

    /// <summary>
    /// Whether <paramref name="other"/> shows the row's page with no problem of
    /// its KIND on it — not merely no row with this id, because the id of a
    /// renumbered fence is not the id of the fence it was (plan review, MED 5)
    /// — and is later than this record.
    /// </summary>
    public static bool FixesThePage(SectionProblemsRecord other, SectionProblemRow row, DateTimeOffset builtHere)
    {
        if (other.BuiltAt is not { } builtThere || builtThere <= builtHere) return false;
        if (!other.PagesShown.Contains(row.Page, StringComparer.Ordinal)) return false;
        if (SaidByTheSite.Contains(row.Kind) && !other.SiteSaidComplete) return false;
        return !other.Rows.Any(otherRow => otherRow.Kind == row.Kind && otherRow.Page == row.Page);
    }

    /// <summary><c>sectionMarker</c>: THIS section's own record has a row, in either state.</summary>
    public static bool HasMarker(SectionProblemsRecord? record) => record is { Rows.Count: > 0 };

    /// <summary><c>alert</c>: the record found something new, and its alert has not been answered.</summary>
    public static bool AlertIsDue(SectionProblemsRecord record, IReadOnlySet<string> answered) =>
        record.HasNewProblems && !answered.Contains(record.AlertKey);

    /// <summary>
    /// The trail's line for a record whose set changed
    /// (<c>activityTrail.mustRecord</c> → "problems changed"): counts and
    /// kinds, never a page. The mac's <c>trailLine(for:)</c> word for word;
    /// the <c>{course}/{section} · </c> in front is <c>ActivityTrail.Note</c>'s,
    /// as on every other line here.
    /// </summary>
    public static string TrailLine(SectionProblemsRecord record) =>
        $"the {(record.CameFromADeploy ? "deploy" : "preview")} found {record.NewIds.Count} new and {record.GoneIds.Count} fewer problems "
        + $"(new: {KindsNamed(record.NewIds)}; gone: {KindsNamed(record.GoneIds)})";

    /// <summary>
    /// How long the links checklist waits for an alert that is DUE but has not
    /// come up in this window — held by another window on the section, or
    /// unable to get on screen. Past it the checklist is shown; an alert this
    /// window HAS on screen is waited for as long as the teacher reads it.
    /// </summary>
    public static readonly TimeSpan LongestTheChecklistWaitsForAnAlertNotUp = TimeSpan.FromSeconds(10);

    /// <summary>
    /// Whether the links checklist (#379) waits, in the order a teacher sees
    /// them: today's-class question first (#406), then the alert about new
    /// problems, then the checklist — the mac's order, which the contract
    /// writes as "The links checklist (#379) follows it" (<c>sectionProblems.alert.rule</c>).
    /// It waits while either is ON SCREEN here, and while the alert is due or
    /// asked for but not yet up — that, for at most
    /// <see cref="LongestTheChecklistWaitsForAnAlertNotUp"/>, so no ordering of
    /// the two can leave both waiting (#734 implementation review, finding 1:
    /// the checklist once held a flag the alert waited on while it waited for
    /// the alert).
    /// </summary>
    /// <param name="aDialogIsUpHere">The alert, or what a repair did, is on screen in this view.</param>
    /// <param name="todaysClassQuestionIsUp">Today's-class question is on screen in this view.</param>
    /// <param name="theAlertIsAskedForOrDue">The alert is queued here, or due (in any window).</param>
    /// <param name="waitedSoFar">How long the checklist has waited on a due alert that is not up here.</param>
    public static bool TheChecklistWaits(bool aDialogIsUpHere, bool todaysClassQuestionIsUp,
                                         bool theAlertIsAskedForOrDue, TimeSpan waitedSoFar) =>
        aDialogIsUpHere || todaysClassQuestionIsUp
        || (theAlertIsAskedForOrDue && waitedSoFar < LongestTheChecklistWaitsForAnAlertNotUp);

    /// <summary>
    /// Whether the checklist goes up at once, in the turn that offered it:
    /// nothing in front of it here and no alert asked for or due. Then it
    /// must not wait even a tick (third review on #734: 1.9.0 showed it at
    /// once, and a wait put it in a later turn where it lost its buttons'
    /// names).
    /// </summary>
    public static bool TheChecklistGoesAtOnce(bool aDialogIsUpHere, bool todaysClassQuestionIsUp, bool theAlertIsAskedForOrDue) =>
        !aDialogIsUpHere && !todaysClassQuestionIsUp && !theAlertIsAskedForOrDue;

    /// <summary>The answers the alert can be given, as the trail writes them (the mac's).</summary>
    public const string AnsweredShow = "Show", AnsweredRepair = "the repair", AnsweredNotNow = "Not Now";

    /// <summary>The answer's line, beside it.</summary>
    public static string AnswerLine(string answer) => $"answered the alert about new problems: {answer}";

    /// <summary>Each kind among <paramref name="ids"/> once, in the order first met; "none" for none.</summary>
    public static string KindsNamed(IEnumerable<string> ids)
    {
        var kinds = new List<string>();
        foreach (string id in ids)
        {
            string kind = SectionProblemsRecord.KindOfId(id);
            if (!kinds.Contains(kind)) kinds.Add(kind);
        }
        return kinds.Count == 0 ? "none" : string.Join(", ", kinds);
    }
}

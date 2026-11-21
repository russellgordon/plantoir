using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// The decisions a section window's preview start makes about what it holds
/// (#928, the mac's #812 and <c>PreviewStartRecords</c>), kept here so the
/// contract's <c>quittingWhileWorkIsUnderWay.previewBuildRecord.pressCases</c>
/// run against the same code the window asks. The window only asks.
///
/// <para>Every start owns what it took (its lease, its build record, its
/// wait) and only that start hands it back: a start asked for while the
/// window's own start is still under way does nothing, a run that never
/// started ends its start at once, and a start parked while old stops
/// finish runs its launcher only if it is still the window's latest start
/// and the quit has not gone ahead.</para>
/// </summary>
public static class PreviewStarts
{
    /// <summary>Where a start's run stands, as the preview's wait reads it.</summary>
    public enum RunStanding
    {
        /// <summary>Running, or not begun yet: wait on.</summary>
        UnderWay,
        /// <summary>The run ended (an exit code), however it ended.</summary>
        Ended,
        /// <summary>The run never started: not running, with a launch problem recorded.</summary>
        CouldNotStart,
    }

    /// <summary>
    /// The mac's <c>howTheRunStands</c>. A launch problem is asked BEFORE the
    /// exit code: a run that did start always clears the problem, so a
    /// problem beside an exit code (the folder's tools not ready sets both)
    /// is this run's, and an exit code alone may be an earlier run's.
    /// </summary>
    public static RunStanding HowTheRunStands(bool isRunning, int? lastExitCode, string? launchProblem)
    {
        if (isRunning) return RunStanding.UnderWay;
        if (launchProblem is not null) return RunStanding.CouldNotStart;
        if (lastExitCode is not null) return RunStanding.Ended;
        return RunStanding.UnderWay;
    }

    /// <summary>
    /// Whether the window's own start is still under way: it has begun (its
    /// build is recorded, or it is waiting for its page) and it holds its own
    /// lease. True while it waits for an old stop to finish and while it
    /// builds; false once the preview is showing, whose wait is over.
    /// </summary>
    public static bool AStartIsUnderWay(bool startHasBegun, PreviewLeases.Lease? heldLease) =>
        startHasBegun && heldLease is not null;

    /// <summary>
    /// Whether a start parked in <c>WaitForStopsToFinish</c> may run its
    /// launcher now: the window is still there, the quit has not gone ahead,
    /// and it is still the window's latest start (compared by the start's
    /// own id, never by lease, since two leases of one section on one port
    /// are equal in every field).
    /// </summary>
    public static bool TheStartStillBelongs(Guid? latestStart, Guid start, bool viewIsGone, bool appIsQuitting)
    {
        if (appIsQuitting) return false;
        if (viewIsGone) return false;
        return latestStart == start;
    }

    /// <summary>
    /// Whether a start still holds what it took: its own lease, by reference
    /// (two leases of one section on one port are equal in every field), and
    /// it is still the window's latest start. Only then may it hand anything
    /// back (#928 item 4); a stop or a later start has already dealt with the rest.
    /// </summary>
    public static bool TheStartStillHoldsItsOwn(PreviewLeases.Lease? heldLease, PreviewLeases.Lease ownLease,
                                                Guid? latestStart, Guid start) =>
        ReferenceEquals(heldLease, ownLease) && latestStart == start;

    /// <summary>What a press of Preview meets in its own window.</summary>
    public enum PressMeets
    {
        /// <summary>Nothing of the window's own is under way: the press goes on.</summary>
        Nothing,
        /// <summary>The window's own start waits for a stop or builds: the press does nothing (<c>preview already starting</c>).</summary>
        AStartUnderWay,
        /// <summary>The window's own stop is still finishing: the press does nothing, and nothing was starting.</summary>
        AStopUnderWay,
    }

    /// <summary>
    /// What a press meets (#928). A stop under way is asked first: while it
    /// finishes, the stopped start still holds its lease and its wait, so
    /// <see cref="AStartIsUnderWay"/> alone would call it a start (the
    /// review's L1).
    /// </summary>
    public static PressMeets WhatAPressMeets(bool aStopIsUnderWay, bool startHasBegun, PreviewLeases.Lease? heldLease)
    {
        if (aStopIsUnderWay) return PressMeets.AStopUnderWay;
        if (AStartIsUnderWay(startHasBegun, heldLease)) return PressMeets.AStartUnderWay;
        return PressMeets.Nothing;
    }

    /// <summary>What a start took, or why it was refused.</summary>
    public sealed record Outcome(PreviewLeases.Lease? Lease, IDisposable? Record, string? Refusal);

    /// <summary>
    /// Take the section's lease, then record the build (Windows' order since
    /// #231: a refused lease writes no record, so it ends nobody's). The
    /// record is this start's own token.
    /// </summary>
    public static Outcome Begin(string folderPath, string courseCode, int sectionNumber, object owner)
    {
        PreviewLeases.Lease lease;
        try
        {
            lease = PreviewLeases.Take(folderPath, courseCode, sectionNumber, owner);
        }
        catch (PreviewLeases.LeaseRefusedException refusal)
        {
            return new Outcome(null, null, refusal.Message);
        }
        IDisposable record = CourseActivity.BeginPreviewBuild(folderPath, courseCode, sectionNumber);
        return new Outcome(lease, record, null);
    }

    /// <summary>The trail line for a run that never started: the sentence shown, then the detail nobody was shown.</summary>
    public static string CouldNotStartLine(string sentence, string? detail) =>
        "the preview could not start, and the teacher was told why: " + sentence
        + (detail is null ? "" : " (" + detail + ")");
}

/// <summary>
/// A repair's Preview Again (#928 item 7, the mac's #813 and
/// <c>PreviewAgainPresses</c>). The press is recorded AT ONCE, before
/// anything is awaited, as a token for the page that pressed it, in a record
/// nothing else writes; the preview starts after the stop only if the press
/// still holds. Leaving the page abandons its press, quitting abandons every
/// press, and a later press of the same page replaces it.
/// </summary>
public sealed class PreviewAgainPresses
{
    /// <summary>How a press ended.</summary>
    public enum Ending { Started, Abandoned, Replaced }

    /// <summary>The app's one record of presses.</summary>
    public static PreviewAgainPresses Shared { get; } = new();

    public const string AbandonedLine =
        "Preview Again after a repair started nothing: the section's page went away, or Plantoir was quitting, before the old preview had stopped";

    public const string ReplacedLine =
        "Preview Again after a repair started nothing itself: a later Preview Again of the same section took its place";

    private readonly Dictionary<Guid, Guid> _underWay = new();
    private readonly HashSet<Guid> _replaced = new();

    /// <summary>The press each page has under way, by page.</summary>
    public IReadOnlyDictionary<Guid, Guid> UnderWay => _underWay;

    /// <summary>Record a press for <paramref name="owner"/>; an earlier press of the same page is remembered as replaced until it finishes.</summary>
    public Guid Press(Guid owner)
    {
        Guid token = Guid.NewGuid();
        if (_underWay.TryGetValue(owner, out Guid earlier)) _replaced.Add(earlier);
        _underWay[owner] = token;
        return token;
    }

    public bool StillHolds(Guid token, Guid owner) =>
        _underWay.TryGetValue(owner, out Guid held) && held == token;

    /// <summary>The press is over, however it ended.</summary>
    public void Finish(Guid token, Guid owner)
    {
        if (StillHolds(token, owner)) _underWay.Remove(owner);
        _replaced.Remove(token);
    }

    /// <summary>The page went away.</summary>
    public void Abandon(Guid owner) => _underWay.Remove(owner);

    /// <summary>The quit went ahead.</summary>
    public void AbandonEvery() => _underWay.Clear();

    /// <summary>
    /// Stop a preview that is up and wait for the stop, then start only if
    /// the press still holds. A press that starts nothing writes
    /// <c>preview again abandoned</c>, naming the right reason even when the
    /// later press finished first.
    /// </summary>
    public static async Task<Ending> CarryOutAsync(PreviewAgainPresses store, Guid owner, Guid token,
                                                   string courseCode, int sectionNumber, bool previewIsRunning,
                                                   Func<Task> stop, Action start)
    {
        if (previewIsRunning) await stop();
        if (!store.StillHolds(token, owner))
        {
            bool replaced = store._replaced.Contains(token);
            ActivityTrail.Note(ActivityTrail.Event.PreviewAgainAbandoned,
                               replaced ? ReplacedLine : AbandonedLine, courseCode, sectionNumber);
            return replaced ? Ending.Replaced : Ending.Abandoned;
        }
        start();
        return Ending.Started;
    }
}

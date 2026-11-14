namespace Plantoir.Core.Undo;

/// <summary>What Undo or Redo would do now, read from the list alone.</summary>
internal enum UndoAnswerKind
{
    /// <summary>There is nothing to undo (or redo).</summary>
    Nothing,
    /// <summary>This step is the one it acts on.</summary>
    Step,
    /// <summary>A newer step is being made, undone or redone right now (<c>rule.linear</c>).</summary>
    AnotherChangeIsUnderWay,
    /// <summary>Greyed, plain "Undo", nothing said (ruling 10, <c>unknown.barrier</c>).</summary>
    NotAvailable,
}

internal readonly record struct UndoAnswer(UndoAnswerKind Kind, UndoFoldedStep? Step = null)
{
    internal long? Seq => Kind == UndoAnswerKind.Step ? Step!.Seq : null;
}

/// <summary>The list as offered at one moment: the limits applied, what Undo and Redo act on.</summary>
internal sealed record UndoOffered
{
    internal required UndoAnswer Undo { get; init; }
    internal required UndoAnswer Redo { get; init; }

    /// <summary>The newest offered step that is done (null: none).</summary>
    internal UndoFoldedStep? Head { get; init; }

    /// <summary>Every step offered, oldest first.</summary>
    internal required IReadOnlyList<UndoFoldedStep> Offered { get; init; }

    /// <summary>The moment the list was judged at (the clock, or a step time up to a day ahead of it).</summary>
    internal required DateTimeOffset JudgedAt { get; init; }
}

/// <summary>
/// The limits and what is offered (<c>undo.rule.limits</c>,
/// <c>undoJournal.folding.offered</c>, <c>rule.linear</c>, #899 piece W1).
/// Pure: everything it needs is passed in, the clock included, so a test
/// expresses <c>clock:+n</c> and no answer depends on when the suite runs.
/// </summary>
internal static class UndoLimits
{
    /// <summary>Ruling 3: the newest 50 steps, counted across the app.</summary>
    internal const int StepsKept = 50;

    /// <summary>Ruling 3: kept for 30 days.</summary>
    internal static readonly TimeSpan DaysKept = TimeSpan.FromDays(30);

    /// <summary>On the disk, a grace of 30 more, so a wrong clock does not destroy the list.</summary>
    internal static readonly TimeSpan Grace = TimeSpan.FromDays(30);

    /// <summary>A step time this far ahead of the clock, or less, is trusted.</summary>
    internal static readonly TimeSpan ClockTolerance = TimeSpan.FromDays(1);

    /// <summary>
    /// Each step's time: its madeAt, or the latest madeAt before it when that
    /// is later, so a clock set back for one step never makes it older than
    /// the steps before it. Taken over every step in seq order, as the
    /// reference model does.
    /// </summary>
    internal static Dictionary<long, DateTimeOffset> StepTimes(UndoFolded folded)
    {
        var times = new Dictionary<long, DateTimeOffset>();
        DateTimeOffset? running = null;
        foreach (UndoFoldedStep step in folded.Steps.Values)
        {
            if (step.Step.MadeAt is { } made && (running is null || made > running)) running = made;
            times[step.Seq] = running ?? DateTimeOffset.MinValue;
        }
        return times;
    }

    /// <summary>The clock, or the latest step time no more than a day ahead of it.</summary>
    internal static DateTimeOffset JudgedAt(DateTimeOffset now, IEnumerable<DateTimeOffset> stepTimes)
    {
        DateTimeOffset judged = now;
        foreach (DateTimeOffset time in stepTimes)
        {
            if (time > judged && time - now <= ClockTolerance) judged = time;
        }
        return judged;
    }

    /// <summary>
    /// The list as offered at <paramref name="now"/>.
    /// </summary>
    /// <param name="isAlive">Whether the process a step in flight names is still running.</param>
    /// <param name="canReach">Whether a step's working folder can be reached (ruling 10).</param>
    internal static UndoOffered Offer(UndoFolded folded, DateTimeOffset now,
                                      Func<UndoProcess?, bool> isAlive, Func<UndoStep, bool> canReach)
    {
        Dictionary<long, DateTimeOffset> times = StepTimes(folded);
        DateTimeOffset judged = JudgedAt(now, times.Values);
        var listed = folded.OnTheList.ToList();

        // Linear: once one step is past thirty days nothing older is offered.
        long expired = 0;
        foreach (UndoFoldedStep step in listed)
        {
            if (times[step.Seq] < judged - DaysKept) expired = step.Seq;
        }
        var remaining = listed.Where(step => step.Seq > expired).ToList();
        int skip = Math.Max(0, remaining.Count - StepsKept);
        if (skip > 0) expired = Math.Max(expired, remaining[skip - 1].Seq);
        var offered = remaining.Skip(skip).ToList();

        UndoFoldedStep? newest = null;
        foreach (UndoFoldedStep step in offered)
        {
            if (step.State != UndoStepState.Undone) newest = step;
        }
        UndoFoldedStep? head = null;
        foreach (UndoFoldedStep step in offered)
        {
            if (step.State == UndoStepState.Done) head = step;
        }

        bool blocked = false;
        foreach (UndoBarrier barrier in folded.Barriers)
        {
            if (barrier.Cleared) continue;
            // A barrier with no seq stands between the step numbered
            // HighestBefore and the next one.
            double at = barrier.Seq ?? barrier.HighestBefore + 0.5;
            if (at <= expired) continue;   // in the oldest run past the limits
            if (newest is null || at >= newest.Seq) blocked = true;
        }
        foreach (UndoFoldedStep step in listed)
        {
            if (!step.Readable && step.Seq > expired && (newest is null || step.Seq >= newest.Seq)) blocked = true;
        }

        UndoOffered Answer(UndoAnswer undo, UndoAnswer redo) =>
            new() { Undo = undo, Redo = redo, Head = head, Offered = offered, JudgedAt = judged };

        if (newest is not null && newest.IsInFlight)
        {
            // A newer step still being made, undone or redone refuses both,
            // unless its process is gone and its folder cannot be reached:
            // then both are simply not available (rule.linear, ruling 10).
            var busy = !isAlive(newest.Process) && !canReach(newest.Step)
                ? new UndoAnswer(UndoAnswerKind.NotAvailable)
                : new UndoAnswer(UndoAnswerKind.AnotherChangeIsUnderWay);
            return Answer(busy, busy);
        }

        long floor = newest?.Seq ?? 0;
        UndoFoldedStep? candidate = offered.FirstOrDefault(step => step.State == UndoStepState.Undone && step.Seq > floor);

        if (blocked || newest is { Readable: false })
            return Answer(new UndoAnswer(UndoAnswerKind.NotAvailable), new UndoAnswer(UndoAnswerKind.NotAvailable));

        UndoAnswer undoAnswer = newest is null
            ? new UndoAnswer(UndoAnswerKind.Nothing)
            : canReach(newest.Step) ? new UndoAnswer(UndoAnswerKind.Step, newest) : new UndoAnswer(UndoAnswerKind.NotAvailable);
        UndoAnswer redoAnswer = candidate is null
            ? new UndoAnswer(UndoAnswerKind.Nothing)
            : !candidate.Readable || !canReach(candidate.Step)
                ? new UndoAnswer(UndoAnswerKind.NotAvailable)
                : new UndoAnswer(UndoAnswerKind.Step, candidate);
        return Answer(undoAnswer, redoAnswer);
    }
}

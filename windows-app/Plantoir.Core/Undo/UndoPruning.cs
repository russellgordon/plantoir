namespace Plantoir.Core.Undo;

/// <summary>One thing pruning writes.</summary>
internal abstract record UndoPruneAction(long Seq)
{
    /// <summary>A <c>pruned</c> line: past the newest 50 (<c>tooMany</c>) or past 60 days (<c>tooOld</c>).</summary>
    internal sealed record Pruned(long Seq, string Reason) : UndoPruneAction(Seq);

    /// <summary>
    /// An <c>interrupted</c> line, reason <c>unsettled</c>, for a dead
    /// process's step still in flight in the oldest run: closed there, with NO
    /// clearing, naming every file it names (<c>rule.recovery</c>).
    /// </summary>
    internal sealed record ClosedUnsettled(long Seq, UndoPhase Phase, IReadOnlyList<string> Paths) : UndoPruneAction(Seq);
}

/// <summary>What deletion may remove now (<c>undoJournal.files</c>, <c>unknown.deleting</c>).</summary>
internal sealed record UndoDeletion(IReadOnlyList<int> Segments, IReadOnlyList<string> Blobs);

/// <summary>
/// Pruning and deletion as PURE decisions (#899 piece W1): given the folded
/// journal, the clock and the liveness check, what the next writer inside the
/// lock writes and removes. Nothing here writes; W2 carries the decisions out.
/// </summary>
internal static class UndoPruning
{
    /// <summary>
    /// One oldest run only, never a step newer in sequence than one kept: past
    /// the newest 50, or more than 60 days old, and nothing for age while the
    /// clock is behind any written time by more than a day. A dead process's
    /// step still in flight in that run is closed there rather than stopping
    /// the run; a running one stops it.
    /// </summary>
    internal static IReadOnlyList<UndoPruneAction> Decide(UndoFolded folded, DateTimeOffset now, Func<UndoProcess?, bool> isAlive)
    {
        var actions = new List<UndoPruneAction>();
        bool trustTheClock = folded.NewestWritten is not { } newest || newest - now <= UndoLimits.ClockTolerance;
        Dictionary<long, DateTimeOffset> times = UndoLimits.StepTimes(folded);
        var listed = folded.OnTheList.ToList();
        int remaining = listed.Count;
        foreach (UndoFoldedStep step in listed)
        {
            bool tooMany = remaining > UndoLimits.StepsKept;
            bool tooOld = trustTheClock && times[step.Seq] < now - (UndoLimits.DaysKept + UndoLimits.Grace);
            if (step.IsInFlight)
            {
                if (isAlive(step.Process) || (!tooMany && !tooOld)) break;
                UndoPhase phase = step.State switch
                {
                    UndoStepState.Undoing => UndoPhase.Undoing,
                    UndoStepState.Redoing => UndoPhase.Redoing,
                    _ => UndoPhase.Begin,
                };
                actions.Add(new UndoPruneAction.ClosedUnsettled(step.Seq, phase, step.Step.Paths.ToList()));
                remaining--;
                continue;
            }
            if (!tooMany && !tooOld) break;
            actions.Add(new UndoPruneAction.Pruned(step.Seq, tooMany ? "tooMany" : "tooOld"));
            remaining--;
        }
        return actions;
    }

    /// <summary>
    /// Which segments and blobs nothing kept can need any more.
    ///
    /// <para>Segments go only from the oldest end, only while no step on the
    /// list has an event in them, only while they are older than the segment
    /// holding the highest seq, and the newest never. One holding a line (or
    /// a step's begin) this version cannot read goes only once the newest
    /// <c>at</c> written in it is more than 60 days before the clock and the
    /// clock is not behind the journal; a segment with no readable <c>at</c>
    /// is judged by the first later segment that has one, and kept while none
    /// does.</para>
    ///
    /// <para>A blob goes when no step on the list names it and nothing this
    /// version cannot read, in a segment still kept, holds its name.</para>
    /// </summary>
    internal static UndoDeletion Deletable(UndoFolded folded, IReadOnlyCollection<int> segmentsOnDisk,
                                           IReadOnlyCollection<string> blobsOnDisk, DateTimeOffset now)
    {
        var ordered = segmentsOnDisk.OrderBy(number => number).ToList();
        bool trustTheClock = folded.NewestWritten is not { } newest || newest - now <= UndoLimits.ClockTolerance;
        var onTheListSegments = new HashSet<int>();
        foreach (UndoFoldedStep step in folded.OnTheList) onTheListSegments.UnionWith(step.Segments);

        var deleted = new List<int>();
        for (int index = 0; index < ordered.Count; index++)
        {
            int number = ordered[index];
            if (index == ordered.Count - 1) break;                        // the newest is never deleted
            if (number >= folded.SegmentOfTheHighest) break;              // not older than the highest seq's
            if (onTheListSegments.Contains(number)) break;                // a step on the list has an event in it
            if (folded.Segments.TryGetValue(number, out UndoSegmentInfo? info) && info.HoldsSomethingUnreadable)
            {
                DateTimeOffset? judgedBy = info.NewestAt;
                if (judgedBy is null)
                {
                    foreach (int later in ordered.Skip(index + 1))
                    {
                        if (folded.Segments.TryGetValue(later, out UndoSegmentInfo? laterInfo) && laterInfo.NewestAt is { } laterAt)
                        {
                            judgedBy = laterAt;
                            break;
                        }
                    }
                }
                if (judgedBy is not { } moment || !trustTheClock
                    || !(moment < now - (UndoLimits.DaysKept + UndoLimits.Grace))) break;
            }
            deleted.Add(number);
        }

        var needed = new HashSet<string>(StringComparer.Ordinal);
        foreach (UndoFoldedStep step in folded.OnTheList) needed.UnionWith(step.Step.Blobs);
        foreach ((int number, UndoSegmentInfo info) in folded.Segments)
        {
            if (!deleted.Contains(number)) needed.UnionWith(info.BlobsKeptByUnreadables);
        }
        var blobs = blobsOnDisk.Where(blob => !needed.Contains(blob)).OrderBy(blob => blob, StringComparer.Ordinal).ToList();
        return new UndoDeletion(deleted, blobs);
    }
}

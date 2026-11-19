namespace Plantoir.Core.Undo;

/// <summary>Where a step stands, folded from its lines (<c>undoJournal.folding</c>).</summary>
internal enum UndoStepState
{
    Begun, Done, Failed, RolledBack, Interrupted, Undoing, Undone, Redoing, Dropped, Pruned, Cleared,
}

/// <summary>One step as the fold leaves it.</summary>
internal sealed class UndoFoldedStep
{
    internal required UndoStep Step { get; init; }
    internal UndoStepState State { get; set; } = UndoStepState.Begun;

    /// <summary>The process that started the work now in flight (begin, undoing or redoing).</summary>
    internal UndoProcess? Process { get; set; }

    /// <summary>A clearing came while it was in flight: it leaves the list when its work ends in done or undone.</summary>
    internal bool MarkedByAClearing { get; set; }

    /// <summary>Every segment that holds an event about it.</summary>
    internal SortedSet<int> Segments { get; } = [];

    internal long Seq => Step.Seq;
    internal bool Readable => Step.Readable;

    /// <summary>Done, undone or in flight: ON THE LIST (offered or not).</summary>
    internal bool IsOnTheList => State is UndoStepState.Done or UndoStepState.Undone || IsInFlight;
    internal bool IsInFlight => State is UndoStepState.Begun or UndoStepState.Undoing or UndoStepState.Redoing;
}

/// <summary>A line this version cannot read, standing as a barrier (<c>unknown.barrier</c>).</summary>
internal sealed class UndoBarrier
{
    /// <summary>Its seq, when it has a whole number for one.</summary>
    internal long? Seq { get; init; }

    /// <summary>For one with no seq: the highest seq of any line before it, so it stands between that step and the next.</summary>
    internal long HighestBefore { get; init; }

    internal long Place { get; init; }
    internal int Segment { get; init; }

    /// <summary>A <c>cleared</c> line came after it (by seq, or by place when it has none).</summary>
    internal bool Cleared { get; set; }
}

/// <summary>What one segment holds, for deletion (<c>undoJournal.files</c>, <c>unknown.deleting</c>).</summary>
internal sealed class UndoSegmentInfo
{
    internal required int Number { get; init; }
    internal DateTimeOffset? NewestAt { get; set; }

    /// <summary>It holds a line this version cannot read, or the begin of a step it cannot read.</summary>
    internal bool HoldsSomethingUnreadable { get; set; }

    /// <summary>The blob names the unreadable things in it hold.</summary>
    internal HashSet<string> BlobsKeptByUnreadables { get; } = new(StringComparer.Ordinal);

    internal int Lines { get; set; }
}

/// <summary>
/// The journal folded: where every step stands, the barriers, the highest seq
/// (#899 piece W1, <c>undoJournal.folding</c>). Built once from the lines in
/// order, segment by segment, line by line; never stored.
/// </summary>
internal sealed class UndoFolded
{
    internal SortedDictionary<long, UndoFoldedStep> Steps { get; } = [];
    internal List<UndoBarrier> Barriers { get; } = [];
    internal SortedDictionary<int, UndoSegmentInfo> Segments { get; } = [];

    /// <summary>The highest seq in ANY line, readable or not, notes included; 0 for an empty journal.</summary>
    internal long Highest { get; set; }

    /// <summary>The segment holding the line with the highest seq.</summary>
    internal int SegmentOfTheHighest { get; set; }

    /// <summary>The newest <c>at</c> written in any line.</summary>
    internal DateTimeOffset? NewestWritten { get; set; }

    /// <summary>The last <c>cleared</c> line: its seq and its reason, as written (never checked).</summary>
    internal (long Seq, string? Reason)? LastClearing { get; set; }

    internal long Lines { get; set; }

    /// <summary>A new step's number: one more than the highest seq in any line, so a number is never used twice.</summary>
    internal long NextSeq => Highest + 1;

    internal IEnumerable<UndoFoldedStep> OnTheList => Steps.Values.Where(step => step.IsOnTheList);
}

/// <summary>
/// The fold: the lines of the journal into the list of steps (#899 piece W1).
///
/// <para><see cref="Moves"/> is the contract's <c>folding.moves</c> table, row
/// for row, as text; <c>UndoFoldMovesContractTests</c> compares it with the
/// JSON so a row added or changed on the mac is red here, and exercises every
/// row against <see cref="Fold"/>. The fold itself is written as code beside
/// it, one case per row, because three rows are rules rather than lookups (a
/// clearing by seq, a step in flight marked, a note passed over).</para>
/// </summary>
internal static class UndoFold
{
    internal sealed record Move(string From, string On, string To);

    /// <summary><c>undoJournal.folding.moves</c>, in the contract's order and words.</summary>
    internal static readonly IReadOnlyList<Move> Moves =
    [
        new("(none)", "begin", "begun"),
        new("begun", "applied", "done"),
        new("begun", "failed (phase begin)", "failed"),
        new("begun", "rolledBack (phase begin)", "rolledBack"),
        new("begun", "interrupted (phase begin)", "interrupted"),
        new("done", "undoing", "undoing"),
        new("done", "pruned", "pruned"),
        new("undoing", "undone", "undone"),
        new("undoing", "failed or rolledBack (phase undoing)", "done"),
        new("undoing", "interrupted (phase undoing)", "interrupted"),
        new("undone", "redoing", "redoing"),
        new("undone", "dropped", "dropped"),
        new("undone", "pruned", "pruned"),
        new("redoing", "redone", "done"),
        new("redoing", "failed or rolledBack (phase redoing)", "undone"),
        new("redoing", "interrupted (phase redoing)", "interrupted"),
        new("done or undone, seq <= the cleared line's", "cleared", "cleared"),
        new("in flight, seq <= the cleared line's", "cleared",
            "(still in flight, marked) then cleared when its work ends in done or undone (undo.rule.clearing)"),
        new("anything", "note", "(no move: passed over)"),
        new("anything else", "any other event", "(ignored)"),
    ];

    /// <summary>Folds lines already read, in journal order.</summary>
    internal static UndoFolded Fold(IEnumerable<UndoLine> lines)
    {
        var folded = new UndoFolded();
        foreach (UndoLine line in lines) Apply(folded, line);
        return folded;
    }

    /// <summary>Folds one more line onto what is already folded.</summary>
    internal static void Apply(UndoFolded folded, UndoLine line)
    {
        folded.Lines++;
        if (!folded.Segments.TryGetValue(line.Segment, out UndoSegmentInfo? segment))
        {
            segment = new UndoSegmentInfo { Number = line.Segment };
            folded.Segments[line.Segment] = segment;
        }
        segment.Lines++;
        if (line.At is { } at)
        {
            if (segment.NewestAt is null || at > segment.NewestAt) segment.NewestAt = at;
            if (folded.NewestWritten is null || at > folded.NewestWritten) folded.NewestWritten = at;
        }

        long highestBefore = folded.Highest;
        if (line.Seq is { } lineSeq && lineSeq > folded.Highest)
        {
            folded.Highest = lineSeq;
            folded.SegmentOfTheHighest = line.Segment;
        }
        else if (line.Seq is { } same && same == folded.Highest && folded.SegmentOfTheHighest < line.Segment)
        {
            folded.SegmentOfTheHighest = line.Segment;
        }

        if (!line.Readable)
        {
            AddBarrier(folded, segment, line.Seq, highestBefore, line.Place, line.BlobNamesInText);
            return;
        }

        if (line.Event == UndoEvent.Note) return;   // passed over, whatever it carries

        long seq = line.Seq!.Value;

        if (line.Event == UndoEvent.Begin)
        {
            if (folded.Steps.ContainsKey(seq))
            {
                // A second begin with a seq a begin already used: unreadable,
                // never a guess at which step is meant (unknown.unreadableLine).
                AddBarrier(folded, segment, seq, highestBefore, line.Place,
                    line.Step is { } second ? second.Blobs : []);
                return;
            }
            var step = new UndoFoldedStep { Step = line.Step!, Process = line.Process };
            step.Segments.Add(line.Segment);
            folded.Steps[seq] = step;
            if (!step.Readable)
            {
                segment.HoldsSomethingUnreadable = true;
                segment.BlobsKeptByUnreadables.UnionWith(step.Step.Blobs);
            }
            return;
        }

        if (line.Event == UndoEvent.Cleared)
        {
            folded.LastClearing = (seq, line.Reason);
            foreach (UndoFoldedStep step in folded.Steps.Values)
            {
                if (step.Seq > seq) continue;
                if (step.State is UndoStepState.Done or UndoStepState.Undone) step.State = UndoStepState.Cleared;
                else if (step.IsInFlight) step.MarkedByAClearing = true;
            }
            foreach (UndoBarrier barrier in folded.Barriers)
            {
                if (barrier.Seq is { } barrierSeq ? barrierSeq <= seq : barrier.Place < line.Place) barrier.Cleared = true;
            }
            return;
        }

        // An event for a seq with no begin is ignored.
        if (!folded.Steps.TryGetValue(seq, out UndoFoldedStep? target)) return;
        target.Segments.Add(line.Segment);

        UndoStepState? next = (target.State, line.Event, line.Phase) switch
        {
            (UndoStepState.Begun, UndoEvent.Applied, _) => UndoStepState.Done,
            (UndoStepState.Begun, UndoEvent.Failed, UndoPhase.Begin) => UndoStepState.Failed,
            (UndoStepState.Begun, UndoEvent.RolledBack, UndoPhase.Begin) => UndoStepState.RolledBack,
            (UndoStepState.Begun, UndoEvent.Interrupted, UndoPhase.Begin) => UndoStepState.Interrupted,
            (UndoStepState.Done, UndoEvent.Undoing, _) => UndoStepState.Undoing,
            (UndoStepState.Done, UndoEvent.Pruned, _) => UndoStepState.Pruned,
            (UndoStepState.Undoing, UndoEvent.Undone, _) => UndoStepState.Undone,
            (UndoStepState.Undoing, UndoEvent.Failed or UndoEvent.RolledBack, UndoPhase.Undoing) => UndoStepState.Done,
            (UndoStepState.Undoing, UndoEvent.Interrupted, UndoPhase.Undoing) => UndoStepState.Interrupted,
            (UndoStepState.Undone, UndoEvent.Redoing, _) => UndoStepState.Redoing,
            (UndoStepState.Undone, UndoEvent.Dropped, _) => UndoStepState.Dropped,
            (UndoStepState.Undone, UndoEvent.Pruned, _) => UndoStepState.Pruned,
            (UndoStepState.Redoing, UndoEvent.Redone, _) => UndoStepState.Done,
            (UndoStepState.Redoing, UndoEvent.Failed or UndoEvent.RolledBack, UndoPhase.Redoing) => UndoStepState.Undone,
            (UndoStepState.Redoing, UndoEvent.Interrupted, UndoPhase.Redoing) => UndoStepState.Interrupted,
            _ => null,   // an event that does not follow from where its step stands is ignored
        };
        if (next is not { } moved) return;

        if (line.Event is UndoEvent.Undoing or UndoEvent.Redoing) target.Process = line.Process;
        if (target.MarkedByAClearing && moved is UndoStepState.Done or UndoStepState.Undone)
            moved = UndoStepState.Cleared;
        target.State = moved;
    }

    private static void AddBarrier(UndoFolded folded, UndoSegmentInfo segment, long? seq, long highestBefore, long place,
                                   IReadOnlyList<string> blobNames)
    {
        folded.Barriers.Add(new UndoBarrier { Seq = seq, HighestBefore = highestBefore, Place = place, Segment = segment.Number });
        segment.HoldsSomethingUnreadable = true;
        segment.BlobsKeptByUnreadables.UnionWith(blobNames);
    }
}

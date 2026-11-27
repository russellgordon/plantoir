using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Undo;

/// <summary>
/// What the door made of a one-file step that stopped part way while this
/// process is still running (#899 W8c-1a; the mac's <c>UndoStoppedStepVerdict</c>,
/// Russell's ruling of 2026-11-26: "Plantoir finishes it, and if it can't,
/// Plantoir offers to automatically put it back").
/// </summary>
internal enum UndoStoppedStepVerdict
{
    /// <summary>The file holds the whole new value: closed as made, on the list.</summary>
    Finished,

    /// <summary>The file holds the old value: closed as put back, off the list.</summary>
    PutBack,

    /// <summary>
    /// The settle could not read the file (or it is in use), could not close
    /// the step, or the list's lock was not had: left in flight, and the
    /// caller offers Put It Back (<see cref="UndoDoor.PutBackAtOnce"/>),
    /// which can succeed. Recovery settles it at the next launch otherwise.
    /// </summary>
    CouldNotFinish,

    /// <summary>
    /// Closed without the change and nothing to offer: the file holds neither
    /// value (another program wrote it, or it is half written), so recovery's
    /// rule for a file changed by hand closed the step and cleared the list
    /// (<c>undo.rule.recovery</c>), or the step was already closed without
    /// it. Put It Back could not succeed and is never offered; nothing is
    /// written over what the file holds, and the step is never tried again.
    /// </summary>
    NotMade,
}

/// <summary>How a Put It Back went (the mac's <c>UndoPutBackVerdict</c>).</summary>
internal enum UndoPutBackVerdict
{
    /// <summary>The old value is on the disk and the step is closed.</summary>
    PutBack,

    /// <summary>The old value could not be written, or the step could not be closed: nothing written over the file.</summary>
    CouldNotPutBack,

    /// <summary>
    /// The step was settled as made while the alert was open (a change's hold
    /// ran recovery, review 1 of W8c-1, LOW 4): the new value is saved and on
    /// the list, nothing is written, and nothing is said.
    /// </summary>
    WasMade,
}

/// <summary>
/// The one rule for which steps the door judges at once (#899 W8c-1a; the
/// mac's <c>UndoStoppedStep.isOneFileJSONStep</c>).
/// </summary>
internal static class UndoStoppedStep
{
    /// <summary>
    /// Whether the step's ops all edit members of ONE JSON file (a
    /// <c>recompute</c> aside): Course Settings' Save and fields, Set School
    /// Year, a rename of a folder no section has. A step of several files
    /// (Rename folder that moves a folder, the unit-word rename, Get Ready)
    /// is not one, and keeps being left part way.
    /// </summary>
    internal static bool IsOneFileJsonStep(IReadOnlyList<UndoOp> ops)
    {
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        bool hasAnEdit = false;
        foreach (UndoOp op in ops)
        {
            if (op.Kind == UndoOp.Recompute) continue;
            if (op.Kind != UndoOp.EditJson || op.Path is null) return false;
            hasAnEdit = true;
            paths.Add(op.Path);
        }
        return hasAnEdit && paths.Count == 1;
    }
}

internal sealed partial class UndoDoor
{
    /// <summary>
    /// The door's answer for a one-file settings step whose swap came back
    /// part way, judged at once (the mac's <c>JournaledWrite.closedAtOnce</c>):
    /// made (and re-derived, as a made step is), put back (said as the refusal
    /// is: nothing changed), not made, or could not finish (its number kept
    /// for Put It Back).
    /// </summary>
    private UndoOutcome ClosedAtOnce(long seq, UndoRefusal refusal, IReadOnlyList<UndoOp> ops, string root)
    {
        switch (JudgeAtOnce(seq))
        {
            case UndoStoppedStepVerdict.Finished:
                Rederive(ops, root);
                return new UndoOutcome(UndoOutcomeKind.Applied, seq);
            case UndoStoppedStepVerdict.PutBack:
                return new UndoOutcome(UndoOutcomeKind.Refused, seq, refusal);
            case UndoStoppedStepVerdict.NotMade:
                return new UndoOutcome(UndoOutcomeKind.NotMade, seq);
            default:
                return new UndoOutcome(UndoOutcomeKind.CouldNotFinish, seq, refusal);
        }
    }

    /// <summary>
    /// Judges step <paramref name="seq"/> by content and closes it, under the
    /// lock, exactly as recovery would settle it once this process had gone:
    /// recovery's own settle on that one record
    /// (<see cref="UndoRecovery.SettleAtOnce"/>). Left in flight when the file
    /// cannot be read, the step cannot be closed, or the lock is not had in
    /// the closing's wait. A step already closed is said as it was closed:
    /// made as made, otherwise not made, never offered.
    /// </summary>
    internal UndoStoppedStepVerdict JudgeAtOnce(long seq)
    {
        try
        {
            return _journal.WithLock(writer =>
            {
                if (!writer.Folded.Steps.TryGetValue(seq, out UndoFoldedStep? record)) return UndoStoppedStepVerdict.NotMade;
                if (!record.IsInFlight)
                    return record.State == UndoStepState.Done ? UndoStoppedStepVerdict.Finished : UndoStoppedStepVerdict.NotMade;
                if (!record.Readable || RootOf(record.Step) is not { } root) return UndoStoppedStepVerdict.CouldNotFinish;
                UndoRecoveryResult? result = UndoRecovery.SettleAtOnce(record, root, writer, _journal, _mode, _trail, _seams, _places);
                if (result is null) return UndoStoppedStepVerdict.CouldNotFinish;
                return result.Outcome switch
                {
                    UndoRecoveryOutcome.Completed => UndoStoppedStepVerdict.Finished,
                    UndoRecoveryOutcome.NothingTookEffect or UndoRecoveryOutcome.RolledBack => UndoStoppedStepVerdict.PutBack,
                    // Closed by the rule for a file changed by hand, the file
                    // holding neither value: nothing to offer.
                    _ => UndoStoppedStepVerdict.NotMade,
                };
            }, wait: _finishWait);
        }
        catch (Exception error) when (error is UndoJournalException or IOException or UnauthorizedAccessException)
        {
            // The lock was not had (or the list not read inside it): the step
            // is still in flight, and Put It Back, which takes the lock again,
            // can succeed.
            return UndoStoppedStepVerdict.CouldNotFinish;
        }
    }

    /// <summary>
    /// Put It Back (the mac's <c>UndoStoppedStep.putBackAtOnce</c>): under the
    /// lock, only a step still in flight; each <c>editJSON</c> member found at
    /// its after value is planned backward and swapped (label
    /// <c>&lt;seq&gt;-recover</c>) as recovery would; the step closed
    /// <c>rolledBack</c> (or <c>failed</c> when every member already held its
    /// old value), recovery's rolled-back trail line left, and the staged
    /// leftovers tidied keeping only copies. A member at neither value, or
    /// unreadable, refuses and writes nothing. A step closed meanwhile is never
    /// swapped: closed as made, it was made (<see cref="UndoPutBackVerdict.WasMade"/>);
    /// otherwise put back only when its file already holds every old value.
    /// Never in shadow, which never writes into a working folder.
    /// </summary>
    internal UndoPutBackVerdict PutBackAtOnce(long seq)
    {
        if (!Live) return UndoPutBackVerdict.CouldNotPutBack;
        try
        {
            return _journal.WithLock(writer => PutBack(seq, writer), wait: _finishWait);
        }
        catch (Exception error) when (error is UndoJournalException or IOException or UnauthorizedAccessException)
        {
            return UndoPutBackVerdict.CouldNotPutBack;
        }
    }

    private UndoPutBackVerdict PutBack(long seq, UndoJournalWriter writer)
    {
        if (!writer.Folded.Steps.TryGetValue(seq, out UndoFoldedStep? record) || !record.Readable) return UndoPutBackVerdict.CouldNotPutBack;
        UndoStep step = record.Step;
        if (RootOf(step) is not { } root) return UndoPutBackVerdict.CouldNotPutBack;
        UndoOpState StateNow(UndoOp edit) => UndoCheck.StateOf(edit, UndoCurrent.Read(FullPath(root, edit.Path!)));
        if (!record.IsInFlight)
        {
            // Closed as made meanwhile: re-judged, as JudgeAtOnce says a closed step.
            if (record.State == UndoStepState.Done) return UndoPutBackVerdict.WasMade;
            foreach (UndoOp op in step.Ops)
            {
                if (op.Kind == UndoOp.EditJson && StateNow(op) != UndoOpState.Before) return UndoPutBackVerdict.CouldNotPutBack;
            }
            return UndoPutBackVerdict.PutBack;
        }
        var toPutBack = new List<UndoOp>();
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind != UndoOp.EditJson) continue;
            UndoOpState state = StateNow(op);
            if (state == UndoOpState.After) toPutBack.Add(op);
            // Neither value, or unreadable: nothing is written over what the file holds now.
            else if (state != UndoOpState.Before) return UndoPutBackVerdict.CouldNotPutBack;
        }
        if (toPutBack.Count > 0)
        {
            UndoCheck.PlanResult plan;
            try
            {
                plan = UndoCheck.Plan(toPutBack, backward: true, relative => UndoCurrent.Read(FullPath(root, relative)), _journal.Blob,
                                      whole: new UndoWholeReads(root, _places), ownSeq: seq);
            }
            catch (UndoListUnreadableException) { return UndoPutBackVerdict.CouldNotPutBack; }
            if (plan is not UndoCheck.PlanResult.Ready ready) return UndoPutBackVerdict.CouldNotPutBack;
            if (UndoSwap.Swap(TargetsOf(ready, root), $"{seq}-recover", RootOrNull(root), null, _places) is not UndoSwapResult.Swapped)
                return UndoPutBackVerdict.CouldNotPutBack;
        }
        JsonObject closing = toPutBack.Count == 0
            ? new JsonObject { ["seq"] = seq, ["event"] = "failed", ["phase"] = "begin", ["reason"] = "nothingTookEffect" }
            : new JsonObject { ["seq"] = seq, ["event"] = "rolledBack", ["phase"] = "begin", ["reason"] = "partlyTookEffect" };
        if (!UndoRecovery.Write([closing], step, writer)) return UndoPutBackVerdict.CouldNotPutBack;
        _journal.Memory.ForgetAbandoned(UndoRecovery.AbandonedKeyOf(_journal, seq, UndoStepState.Begun, record.Process?.Pid ?? 0));
        // The same trail line recovery leaves for a step it put back (the mac's first review, LOW 2).
        if (toPutBack.Count > 0)
            _trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoRolledBack, step.Course, step.Section,
                                             UndoTrail.RolledBackWords(UndoPhase.Begin, toPutBack.Count)));
        try
        {
            UndoSwap.TidyLeftovers(seq, step.PathsToTidy, root, UndoRecovery.AsideListings(step, root), null, keepingOnlyCopies: true,
                                   unlessTheListHolds: UndoRecovery.ListHolds(step, root, _journal));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        return UndoPutBackVerdict.PutBack;
    }
}

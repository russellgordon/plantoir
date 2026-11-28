using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Undo;

/// <summary>
/// A restore that replaces files of a course sets aside, per FILE, every Undo
/// step left in flight that names one of them (#899, the mac's
/// <c>UndoRestoreSetAside</c>, the director's decisions of 2026-11-27, ahead
/// of U5, which makes a restore itself a step).
///
/// <para>Without it a step that stopped part way (Get Ready for the Start of
/// the Year, say) stays in flight over a course that now holds the backup,
/// and the next recovery judges the RESTORED files against it: after a second
/// Get Ready it closed the old step as made (two on the list for one change),
/// or put back part of the second run's files.</para>
///
/// <para>The step's files the restore replaced are set aside, never judged,
/// written or re-derived by recovery; its other files stay in the step and
/// are judged by content as before. A step whose every file is set aside is
/// closed <c>interrupted</c>, reason <c>setAsideByARestore</c>, with every
/// file it names and NO clearing, as pruning closes a step it can never
/// settle (<see cref="UndoPruneAction.ClosedUnsettled"/>): partly applied or
/// unknown, off the list. A step with files left to judge gets a
/// <c>filesReplacedByARestore</c> line and stays in flight; recovery
/// (<see cref="UndoRecovery"/>'s settle) then judges only the rest, and closes
/// it <c>interrupted</c> naming the files set aside rather than putting it on
/// the list, since what an Undo would act on was replaced. No clearing is
/// written, because it would take every other course's steps.</para>
///
/// <para>The restore calls <see cref="SetAsideSteps"/> inside the list's lock
/// held across its swap, once it has replaced files (W8c-3b for the
/// one-section restore; #873 for the staged whole-course restore).</para>
/// </summary>
internal static class UndoRestoreSetAside
{
    /// <summary>Thrown when the list's lock cannot be had within the finish wait: the restore does not start, and nothing has moved (the mac's <c>TheListIsBusy</c>).</summary>
    internal sealed class TheListIsBusy : Exception;

    /// <summary>
    /// Runs a restore's <paramref name="swap"/> holding the list's lock (the
    /// mac's <c>swapHoldingTheList</c>), and once it says the restore has
    /// replaced files (every move made, or stopped part way with some moved
    /// and not all put back), sets aside every step in flight whose files are
    /// among <paramref name="replacedPlaces"/> (<see cref="SetAsideSteps"/>) in
    /// the same lock, so no recovery can judge between the swap and the
    /// set-aside and no step can begin in between. A swap that moved nothing,
    /// or put every file back, sets nothing aside: each step stays in flight
    /// as recovery would have found it.
    ///
    /// <para>A lock still held after the finish wait stops the restore before
    /// it starts (<see cref="TheListIsBusy"/>), never a swap with no
    /// set-aside. A list that cannot be read or written at all never stops
    /// the restore, which is how a teacher gets a course back: the swap runs,
    /// and when it replaced files the trail says any change left part way in
    /// the course is still open. A working folder with no identifier has never
    /// had a step made in it: the swap runs and the list is not asked for.</para>
    ///
    /// <para><paramref name="swap"/> never throws: it keeps its own error for
    /// its caller and returns whether it replaced files.</para>
    /// </summary>
    /// <param name="replacedPlaces">What the restore replaces, as paths from the working folder (<c>courses/&lt;CODE&gt;/section&lt;N&gt;</c> and the files outside it it moves; <c>courses/&lt;CODE&gt;</c> for a whole course).</param>
    /// <param name="workingFolderRoot">The working folder the restore is in (the folder holding <c>courses</c>).</param>
    /// <param name="course">The course code, for the trail line.</param>
    /// <param name="theList">The list to hold, asked for only when the folder has an identifier.</param>
    /// <returns>The numbers of the steps it set aside.</returns>
    internal static IReadOnlyList<long> SwapHoldingTheList(IReadOnlyList<string> replacedPlaces, string workingFolderRoot, string course,
                                                           Func<UndoListForARestore> theList, Func<bool> swap)
    {
        FolderIdentityFile.Answer identity =
            new FolderIdentityFile(Path.Combine(workingFolderRoot, "courses", ".internal", "folder-id"), TimeProvider.System).Read();
        if (identity.Outcome != FolderIdentityFile.Outcome.Identifier || identity.Identifier is not { } id)
        {
            swap();
            return [];
        }
        UndoListForARestore list = theList();
        var workingFolder = new UndoWorkingFolder(id, workingFolderRoot);
        bool swapRan = false;
        bool replacedFiles = false;
        IReadOnlyList<long> setAside = [];
        try
        {
            list.Journal.WithLock(writer =>
            {
                swapRan = true;
                replacedFiles = swap();
                if (replacedFiles) setAside = SetAsideSteps(replacedPlaces, workingFolder, writer, list.Trail);
            }, inShadow: list.Mode == UndoMode.Shadow, wait: list.FinishWait);
        }
        catch (UndoJournalException error) when (error.Failure == UndoJournalFailure.LockBusy && !swapRan)
        {
            throw new TheListIsBusy();
        }
        catch (Exception)
        {
            // The list could not be had or written: the restore still runs.
            if (!swapRan) replacedFiles = swap();
            if (replacedFiles)
                list.Trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoSetAsideByARestore, course, null,
                                                     UndoTrail.ListNotReachedByARestoreWords));
        }
        return setAside;
    }

    /// <summary>The reason word on the closing line and on the event (<c>undoJournal.eventKeys.reason</c>).</summary>
    internal const string Reason = "setAsideByARestore";

    /// <summary>Whether <paramref name="path"/> is one of <paramref name="replacedPlaces"/> or inside one (<see cref="UndoOp.PartInside"/>, the one comparison).</summary>
    internal static bool IsInsideAny(string path, IReadOnlyList<string> replacedPlaces)
    {
        foreach (string place in replacedPlaces)
        {
            if (UndoOp.PartInside(place, path) is not null) return true;
        }
        return false;
    }

    /// <summary>
    /// The step's files split by what the restore replaced, each once, in the
    /// order its ops name them: an op is inside when ANY file it names is at
    /// or inside one of <paramref name="replacedPlaces"/> (a move from inside
    /// to outside is inside: its one place was replaced), and every file of
    /// an op inside is inside. Outside: the files no op inside names.
    /// </summary>
    internal static (List<string> Inside, List<string> Outside) PathsInside(UndoStep step, IReadOnlyList<string> replacedPlaces)
    {
        var inside = new List<string>();
        var outside = new List<string>();
        foreach (UndoOp op in step.Ops)
        {
            bool opIsInside = false;
            foreach (string path in op.PathsNamed)
            {
                if (IsInsideAny(path, replacedPlaces)) opIsInside = true;
            }
            foreach (string path in op.PathsNamed)
            {
                List<string> side = opIsInside ? inside : outside;
                if (!side.Contains(path, StringComparer.Ordinal)) side.Add(path);
            }
        }
        var outsideOnly = new List<string>();
        foreach (string path in outside)
        {
            if (!inside.Contains(path, StringComparer.Ordinal)) outsideOnly.Add(path);
        }
        return (inside, outsideOnly);
    }

    /// <summary>Whether the step was made in this working folder: its identifier, compared without regard to case.</summary>
    internal static bool IsMade(UndoStep step, UndoWorkingFolder workingFolder)
    {
        if (step.WorkingFolder?.Id is not { } stepId || workingFolder.Id is not { } thisId) return false;
        return string.Equals(stepId.ToLowerInvariant(), thisId.ToLowerInvariant(), StringComparison.Ordinal);
    }

    /// <summary>
    /// The step without the ops that name a file set aside: what recovery
    /// judges, and the only files it may write or re-derive (the mac's
    /// <c>stepWithout</c>).
    /// </summary>
    internal static UndoStep StepWithout(IReadOnlyCollection<string> setAside, UndoStep step)
    {
        if (setAside.Count == 0) return step;
        var kept = new List<UndoOp>();
        foreach (UndoOp op in step.Ops)
        {
            bool namesOneSetAside = false;
            foreach (string path in op.PathsNamed)
            {
                if (setAside.Contains(path, StringComparer.Ordinal)) namesOneSetAside = true;
            }
            if (!namesOneSetAside) kept.Add(op);
        }
        return step with { Ops = kept };
    }

    /// <summary>
    /// A step with files set aside never goes back on the list and never
    /// stays where it began: its other files settled (made, nothing took
    /// effect, or put back), it is closed <c>interrupted</c>, reason
    /// <c>setAsideByARestore</c>, naming the files set aside, with no
    /// clearing. Any other closing (changed by hand, could not put back) is
    /// kept as it is, its clearing with it (the mac's <c>closingWithFilesSetAside</c>).
    /// </summary>
    internal static List<JsonObject> ClosingWithFilesSetAside(List<JsonObject> events, string phaseWord, IReadOnlyList<string> setAside)
    {
        var result = new List<JsonObject>();
        foreach (JsonObject line in events)
        {
            string? name = (string?)line["event"];
            bool settles = name is "applied" or "undone" or "redone" or "failed" or "rolledBack";
            if (settles) result.Add(UndoRecovery.Interrupted((long)line["seq"]!, phaseWord, Reason, setAside));
            else result.Add(line);
        }
        return result;
    }

    /// <summary>
    /// Inside the list's lock (<paramref name="writer"/>): for each step in
    /// flight made in <paramref name="workingFolder"/> (its identifier) that
    /// names a file at or inside one of <paramref name="replacedPlaces"/>
    /// (paths inside the working folder, <c>courses/ICS3U</c> or
    /// <c>courses/ICS3U/section1</c>), those files are set aside. When that is
    /// every file it names (or every one not set aside already), the step is
    /// closed <c>interrupted</c>, reason <c>setAsideByARestore</c>, with every
    /// file it names and no clearing. Otherwise a
    /// <c>filesReplacedByARestore</c> line names the files newly set aside and
    /// the step stays in flight for its other files. Its staged files beside
    /// the files set aside are tidied (live only), keeping any kept original
    /// that is the only copy. One trail line per step set aside. A second call
    /// sets aside nothing new. Returns the numbers of the steps it set aside.
    /// </summary>
    /// <param name="workingFolder">This working folder: its identifier, and the path it is at now (where its staged files are tidied).</param>
    /// <param name="trail">Where "undo set aside a change a restore replaced" goes (and "undo found a folder set aside", from the tidy).</param>
    internal static IReadOnlyList<long> SetAsideSteps(IReadOnlyList<string> replacedPlaces, UndoWorkingFolder workingFolder,
                                                      UndoJournalWriter writer, Action<UndoTrailLine>? trail = null)
    {
        var touched = new List<long>();
        UndoJournal journal = writer.Journal;
        var inFlight = new List<UndoFoldedStep>();
        foreach (UndoFoldedStep record in writer.Folded.Steps.Values)
        {
            if (record.IsInFlight) inFlight.Add(record);
        }
        foreach (UndoFoldedStep record in inFlight)
        {
            // A step this version cannot read names files it cannot know: a
            // barrier on the list, never judged by recovery either.
            if (!record.Readable) continue;
            if (!IsMade(record.Step, workingFolder)) continue;
            UndoPhase phase = record.State switch
            {
                UndoStepState.Undoing => UndoPhase.Undoing,
                UndoStepState.Redoing => UndoPhase.Redoing,
                _ => UndoPhase.Begin,
            };
            UndoStep step = record.Step;
            (List<string> inside, List<string> outside) = PathsInside(step, replacedPlaces);
            // Read before the line is written: the fold of this writer moves
            // the record as each line is appended.
            var setAsideBefore = new List<string>(record.SetAsidePaths);
            string key = UndoRecovery.KeyOf(record, journal);
            var newlyInside = new List<string>();
            foreach (string path in inside)
            {
                if (!setAsideBefore.Contains(path, StringComparer.Ordinal)) newlyInside.Add(path);
            }
            if (newlyInside.Count == 0) continue;
            var stillJudged = new List<string>();
            foreach (string path in outside)
            {
                if (!setAsideBefore.Contains(path, StringComparer.Ordinal)) stillJudged.Add(path);
            }
            string phaseWord = phase.ToString().ToLowerInvariant();
            bool closed = stillJudged.Count == 0;
            if (closed)
            {
                writer.Append(UndoRecovery.Interrupted(step.Seq, phaseWord, Reason, step.Paths.ToList()));
            }
            else
            {
                var paths = new JsonArray();
                foreach (string path in newlyInside) paths.Add(path);
                writer.Append(new JsonObject
                {
                    ["seq"] = step.Seq, ["event"] = "filesReplacedByARestore", ["reason"] = Reason, ["paths"] = paths,
                });
            }
            // Durable before anything beside the pages goes.
            writer.Sync();
            touched.Add(step.Seq);
            if (journal.IsLive && workingFolder.PathAtTheTime is { Length: > 0 } root)
            {
                // The ops set aside now: none naming a file still judged or
                // one an earlier restore set aside.
                var notNow = new List<string>(stillJudged);
                foreach (string path in setAsideBefore)
                {
                    if (!notNow.Contains(path, StringComparer.Ordinal)) notNow.Add(path);
                }
                UndoStep theOpsSetAside = StepWithout(notNow, step);
                try
                {
                    UndoSwap.TidyLeftovers(theOpsSetAside.Seq, theOpsSetAside.PathsToTidy, root, UndoRecovery.AsideListings(theOpsSetAside, root),
                                           found => UndoRecovery.NoteAnAsideFolder(found, theOpsSetAside, root, journal, trail),
                                           keepingOnlyCopies: true);
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            }
            if (closed) journal.Memory.ForgetTheRefusedSwap(key);
            trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoSetAsideByARestore, step.Course, step.Section,
                                            UndoTrail.SetAsideByARestoreWords(phase, newlyInside.Count, stillJudged.Count)));
        }
        return touched;
    }
}

/// <summary>
/// The list a restore holds across its swap: its journal, its mode, where
/// its trail lines go, and how long the lock is waited for (the door's own
/// finish wait, <see cref="UndoDoor.FinishWait"/>, in the app).
/// </summary>
internal sealed record UndoListForARestore(UndoJournal Journal, UndoMode Mode, Action<UndoTrailLine>? Trail, TimeSpan FinishWait)
{
    /// <summary>This process's list (<see cref="UndoForThisProcess.Current"/>), asked for only when a restore needs it.</summary>
    internal static UndoListForARestore OfThisProcess()
    {
        UndoForThisProcess process = UndoForThisProcess.Current;
        return new UndoListForARestore(process.Journal, process.Mode, process.Trail, UndoDoor.FinishWait);
    }
}

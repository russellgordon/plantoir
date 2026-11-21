using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Undo;

/// <summary>What recovery did with one step.</summary>
internal enum UndoRecoveryOutcome
{
    /// <summary>Every file where the work started: <c>failed</c>.</summary>
    NothingTookEffect,
    /// <summary>Every file where the work was going: <c>applied</c>, <c>undone</c> or <c>redone</c>.</summary>
    Completed,
    /// <summary>Some of each: what took effect was put back, <c>rolledBack</c>.</summary>
    RolledBack,
    /// <summary>A file in the way (or a put-back that cannot be planned): <c>interrupted</c>, the list cleared.</summary>
    Interrupted,
    /// <summary>Shadow: recorded, never repaired.</summary>
    LeftAlone,
}

/// <summary>One step recovery settled: its number, the work it ended, the outcome, and the step itself (for re-deriving after the hold).</summary>
internal sealed record UndoRecoveryResult(long Seq, UndoPhase Phase, UndoRecoveryOutcome Outcome, UndoStep Step, string Root,
                                          int FilesPutBack = 0, int FilesInTheWay = 0);

/// <summary>What one run of recovery came to: the steps it settled, and whether a test (or the harness) stopped it at a kill point.</summary>
/// <param name="Left">The steps it tried and left for later, each with why (a file in use, a page that cannot be read now):
/// the true answer an Undo or a Redo gives when such a step is the newest (W3's review, LOW 4).</param>
/// <param name="NotRun">Why recovery did not run at all (the list busy past its wait, unreadable, its folder not makeable), or null when it ran.</param>
internal sealed record UndoRecoveryRun(IReadOnlyList<UndoRecoveryResult> Settled, bool StoppedByATest,
                                       IReadOnlyDictionary<long, UndoRefusal>? Left = null, string? NotRun = null);

/// <summary>One line for the activity trail: the course and section it is about, and the words after them.</summary>
internal sealed record UndoTrailLine(ActivityTrail.Event Event, string? Course, long? Section, string Words);

/// <summary>
/// The trail lines Undo writes (<c>activityTrail.mustRecord</c>), in the
/// mac's words (<c>UndoTrail</c> in <c>UndoAppSeams.swift</c>). The door is
/// given a sink for them; the app's start-up (W4) passes
/// <see cref="ToTheActivityTrail"/>, a test passes a list.
/// </summary>
internal static class UndoTrail
{
    /// <summary><c>the undo list put back 2 files left part way by a change that stopped</c>.</summary>
    internal static string RolledBackWords(UndoPhase phase, int files)
    {
        string what = phase switch
        {
            UndoPhase.Undoing => "an undo",
            UndoPhase.Redoing => "a redo",
            _ => "a change",
        };
        return $"the undo list put back {Files(files)} left part way by {what} that stopped";
    }

    /// <summary>
    /// <c>the undo list keeps the folder courses/ICS3U/made, set aside by a
    /// change that stopped, as courses/ICS3U/made (kept by Undo), because
    /// something else now holds courses/ICS3U/made</c>, or <c>the undo list
    /// puts the folder courses/ICS3U/made back in its place; it changed while
    /// a change that stopped had set it aside (1 file added)</c> (the mac's
    /// <c>foundAFolderSetAsideLine</c>). Written just before the rename, so it
    /// says what is being done.
    /// </summary>
    internal static string FoundAFolderSetAsideWords(string place, string? keptAs, string changes) =>
        keptAs is not null
            ? $"the undo list keeps the folder {place}, set aside by a change that stopped, as {keptAs}, because something else now holds {place}"
            : $"the undo list puts the folder {place} back in its place; it changed while a change that stopped had set it aside ({changes})";

    /// <summary><c>… , found 1 file changed by hand since, and cleared the list</c>.</summary>
    internal static string InterruptedWords(UndoPhase phase, int putBack, int inTheWay) =>
        RolledBackWords(phase, putBack) + $", found {Files(inTheWay)} changed by hand since, and cleared the list";

    private static string Files(int count) => count == 1 ? "1 file" : $"{count} files";

    /// <summary>
    /// Writes a line to the real activity trail, <c>course/section · words</c>:
    /// the sink the app's start-up (W4) gives the door. Each event Undo
    /// writes is named here, so the trail's wiring scan sees its writer.
    /// </summary>
    internal static void ToTheActivityTrail(UndoTrailLine line)
    {
        // Each event Undo writes, named on the right of an arm so the trail's
        // wiring scan (ActivityTrailWiringTests) sees its writer: a case label
        // alone, with the event passed on as line.Event, is not seen.
        ActivityTrail.Event written = line.Event switch
        {
            ActivityTrail.Event.UndoRolledBack => ActivityTrail.Event.UndoRolledBack,
            ActivityTrail.Event.UndoFoundAFolderSetAside => ActivityTrail.Event.UndoFoundAFolderSetAside,
            _ => throw new ArgumentException("An event Undo does not write: " + line.Event, nameof(line)),
        };
        if (string.IsNullOrEmpty(line.Course)) ActivityTrail.Note(written, line.Words);
        else if (line.Section is { } section and >= 0 and <= int.MaxValue) ActivityTrail.Note(written, line.Words, line.Course, (int)section);
        else ActivityTrail.Note(written, line.Course + " · " + line.Words);
    }
}

/// <summary>
/// Settles steps whose work stopped part way (#899 W3; <c>undo.rule.recovery</c>,
/// the mac's <c>UndoRecovery</c>). Run inside the lock: in the door's begin
/// hold, its Undo/Redo offer hold, before EVERY prune, and by
/// <see cref="UndoDoor.Recover"/> (at every launch of the app and of
/// <c>plantoir-mcp.exe</c>, since W4: <see cref="UndoAtLaunch.Recover"/>).
///
/// <para>For each step in flight whose process is gone (or that this process
/// gave up on, <see cref="UndoProcessMemory.NoteAbandoned"/>), each file the
/// step changed is judged by its CONTENT, never a time: where the work
/// started, where it was going, or neither. All at the start: <c>failed</c>.
/// All at the end: completed. Some of each: what took effect is put back,
/// <c>rolledBack</c>, a trail line. Any file neither (changed by hand since):
/// what can be verified is put back, the step is <c>interrupted</c> naming the
/// files in the way, and the list is CLEARED (as ruling 13 clears for a
/// refused step). A put-back that cannot be planned (its content missing) is
/// closed the same way (<c>couldNotPutBack</c>). The journal never says done
/// or failed for a step that is half applied.</para>
///
/// <para>A file in use or that cannot be read now, a refused put-back swap,
/// or the list unreadable: the step is LEFT, to be tried again on a bounded
/// schedule (at once at an Undo, a Redo or an explicit recovery; otherwise
/// at the process's first lock, then one minute after a refusal, doubling,
/// at most an hour), so an ordinary action pays nothing for it in between
/// (measured on the mac before the rule: 187 to 255 ms on every action for a
/// 300-page put-back). A step pruning would close now is tried at once, so it
/// is never closed <c>unsettled</c> while one more try could settle it.</para>
///
/// <para>A step whose folder cannot be reached, or that this version cannot
/// read, is left while it is on the list (ruling 10); pruning closes it past
/// the limits. A step that keeps a file true by a rule (a <c>recompute</c>) is
/// settled only by a recovery that will re-derive it, and only once a runner
/// for its maintainer exists. In SHADOW nothing is written into a working
/// folder: a step that partly took effect is recorded interrupted and the
/// list cleared, the files left exactly as the work left them.</para>
/// </summary>
internal static class UndoRecovery
{
    /// <summary>
    /// Recovery, inside the lock. <paramref name="trySwapsNow"/>: an Undo, a
    /// Redo or an explicit recovery, where a put-back refused earlier is tried
    /// at once; false on the ordinary path. <paramref name="leavingStepsThatRederive"/>:
    /// the caller cannot re-derive after the hold (a plain write's begin), so
    /// a live step that keeps a file true is left for one that can.
    /// </summary>
    internal static UndoRecoveryRun Run(UndoJournalWriter writer, UndoJournal journal, UndoMode mode, bool trySwapsNow,
                                        bool leavingStepsThatRederive, IUndoMaintainers? maintainers,
                                        Action<UndoTrailLine>? trail, UndoSeams? seams, IUndoExternalPlaces? places = null)
    {
        writer.RecoveredThisHold = true;
        IUndoExternalPlaces theirPlaces = places ?? new UndoAppSettingsPlaces();
        var settled = new List<UndoRecoveryResult>();
        var left = new Dictionary<long, UndoRefusal>();
        DateTimeOffset now = journal.Now;
        HashSet<long>? pruningWouldClose = null;
        var inFlight = writer.Folded.Steps.Values.Where(step => step.IsInFlight).ToList();
        foreach (UndoFoldedStep record in inFlight)
        {
            if (!MaySettle(record, journal)) continue;
            if (!record.Readable) continue;
            if (RootOf(record.Step, journal) is not { } root) continue;
            bool keepsAFileTrue = KeepsAFileTrue(record.Step);
            // Never settled with its re-derivation skipped (the hard review of U2b, MEDIUM 5).
            if (keepsAFileTrue && !CanRederive(record.Step, maintainers)) continue;
            // Settled only by a recovery that will re-derive it (MEDIUM 1), and
            // never closed unsettled by this hold's pruning meanwhile: one more
            // try, by the next recovery that re-derives (an Undo, a Redo, the
            // next launch's), can settle it (W3's review, LOW 2).
            if (keepsAFileTrue && leavingStepsThatRederive && mode == UndoMode.Live)
            {
                writer.LeftForARederivingRecovery.Add(record.Seq);
                continue;
            }
            string key = KeyOf(record, journal);
            if (!trySwapsNow && !journal.Memory.RefusedSwapIsDue(key, now))
            {
                pruningWouldClose ??= ClosedByPruningNow(writer, journal);
                if (!pruningWouldClose.Contains(record.Seq)) continue;
            }
            SettleAnswer answer = Settle(record, root, writer, journal, mode, trail, seams, theirPlaces);
            if (answer.Stopped) return new UndoRecoveryRun(settled, StoppedByATest: true, left);
            if (answer.Result is { } result)
            {
                journal.Memory.ForgetTheRefusedSwap(key);
                journal.Memory.ForgetAbandoned(AbandonedKeyOf(journal, record.Seq, record.State, record.Process?.Pid ?? 0));
                settled.Add(result);
            }
            else if (answer.TryAgain)
            {
                if (answer.Why is { } why) left[record.Seq] = why;
                journal.Memory.NoteARefusedSwap(key, now);
            }
        }
        if (mode == UndoMode.Live) TidyClosedSteps(writer, journal, trail);
        return new UndoRecoveryRun(settled, StoppedByATest: false, left);
    }

    /// <summary>
    /// The number of a step a gone process left in flight that keeps a file
    /// true by a rule, on this course (any when either has none): a write
    /// through a door that cannot re-derive is refused while one waits, so it
    /// never lands over a page the stopped work left part way (the mac's
    /// third hard review of U2b, LOW 1).
    /// </summary>
    internal static long? DeadStepThatKeepsAFileTrue(UndoJournalWriter writer, UndoJournal journal, string? course)
    {
        foreach (UndoFoldedStep record in writer.Folded.Steps.Values)
        {
            if (!record.IsInFlight || !KeepsAFileTrue(record.Step) || !MaySettle(record, journal)) continue;
            if (course is not null && record.Step.Course is { } stepCourse && !string.Equals(course, stepCourse, StringComparison.Ordinal)) continue;
            return record.Seq;
        }
        return null;
    }

    /// <summary>Whether a step holds a <c>recompute</c> op.</summary>
    internal static bool KeepsAFileTrue(UndoStep step) => step.Ops.Any(op => op.Kind == UndoOp.Recompute);

    /// <summary>
    /// Whether recovery may settle a step in flight: its process can be
    /// identified (a pid of 1 to 2^31-1: the W1 review's low on a pid of 0
    /// or less read as a known process) and is gone, or this process gave
    /// up on it. A step whose process cannot be identified is never settled
    /// (a live process of another version may still be swapping), and pruning
    /// closes it past the limits.
    /// </summary>
    internal static bool MaySettle(UndoFoldedStep record, UndoJournal journal)
    {
        if (record.Process is not { } process || process.Pid is <= 0 or > int.MaxValue) return false;
        if (journal.Memory.IsAbandoned(AbandonedKeyOf(journal, record.Seq, record.State, process.Pid))) return true;
        return !journal.IsAlive(process);
    }

    /// <summary>One step's work in one list: the list, its number, where its work stands, and when it was made (a new list in a reused folder is never confused with an old one).</summary>
    internal static string KeyOf(UndoFoldedStep record, UndoJournal journal) =>
        UndoProcessMemory.KeyOf(journal.Folder) + "#" + record.Seq + "#" + record.State + "#"
        + (record.Step.MadeAt?.ToUnixTimeMilliseconds().ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "");

    /// <summary>
    /// A step this process gave up on: the list, its number, where its work
    /// stands, and the process (only a step named by this process's own id is
    /// ever settled as abandoned while it lives).
    /// </summary>
    internal static string AbandonedKeyOf(UndoJournal journal, long seq, UndoStepState working, long pid) =>
        UndoProcessMemory.KeyOf(journal.Folder) + "#" + seq + "#" + working + "#pid" + pid;

    private static bool CanRederive(UndoStep step, IUndoMaintainers? maintainers)
    {
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind == UndoOp.Recompute && (op.Maintainer is not { } maintainer || maintainers?.CanRun(maintainer) != true)) return false;
        }
        return true;
    }

    /// <summary>
    /// The folder a step's paths are under, or null when it cannot be reached.
    /// A step none of whose ops names a path (an external op alone,
    /// <c>opKinds.wholeOps</c>) needs no folder: its root is empty, which no op
    /// of it reads.
    /// </summary>
    internal static string? RootOf(UndoStep step, UndoJournal journal)
    {
        if (!step.Ops.Any(op => op.PathsNamed.Any())) return "";
        return step.WorkingFolder?.PathAtTheTime is { Length: > 0 } path && journal.CanReach(step) ? path : null;
    }

    /// <summary>The listing each tree op of a step recorded, by its folder's full path: what a folder set aside must still be for recovery to put it back as the step's.</summary>
    internal static IReadOnlyDictionary<string, string> AsideListings(UndoStep step, string root)
    {
        var listings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind is UndoOp.CreateTree or UndoOp.RemoveTree && op.Path is { } path && op.ListingSha is { } sha)
                listings[Path.GetFullPath(UndoDoor.FullPath(root, path))] = sha;
        }
        return listings;
    }

    /// <summary>
    /// Every tree op's folder of this step that a staged <c>-orig</c> name still
    /// holds beside it (its place could not be read, or a rename failed): a
    /// folder still aside is IN THE WAY, never settled as if it were gone (the
    /// mac's second hard review of U2b, MEDIUM 3).
    /// </summary>
    internal static HashSet<string> FoldersKeptAside(UndoStep step, string root)
    {
        var kept = new HashSet<string>(StringComparer.Ordinal);
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind is not (UndoOp.CreateTree or UndoOp.RemoveTree) || op.Path is not { } path) continue;
            string place = UndoDoor.FullPath(root, path);
            string? folder = Path.GetDirectoryName(place);
            if (folder is null || !Directory.Exists(folder)) continue;
            string prefix = "." + Path.GetFileName(place) + UndoSwap.StagedMarker + step.Seq + "-";
            IEnumerable<string> names;
            try { names = Directory.EnumerateDirectories(folder, prefix + "*").Select(Path.GetFileName).ToList()!; }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { continue; }
            foreach (string name in names)
            {
                if (string.Equals(UndoSwap.PlaceOfStagedName(name), Path.GetFileName(place), StringComparison.OrdinalIgnoreCase)
                    && UndoSwap.IsAFolderSetAside(Path.Combine(folder, name)))
                    kept.Add(path);
            }
        }
        return kept;
    }

    /// <summary>
    /// The trail line for a teacher's folder found set aside (the mac's
    /// <c>noteAnAsideFolder</c>), said before it is renamed: put back though
    /// it changed while aside (what changed, counted against the step's
    /// record when the list still holds it), or kept under a visible name
    /// because something else holds its place. A folder put back as recorded
    /// needs no line.
    /// </summary>
    internal static void NoteAnAsideFolder(UndoAsideFolder found, UndoStep step, string root, UndoJournal? journal, Action<UndoTrailLine>? trail)
    {
        if (trail is null || (found.PutBack && found.Matched)) return;
        string place = InsideTheFolder(found.Place, root);
        string? keptAs = found.KeptAs is { } kept ? InsideTheFolder(kept, root) : null;
        string changes = found.PutBack ? WhatChanged(found.FoundAt, step, place, journal) : "";
        trail(new UndoTrailLine(ActivityTrail.Event.UndoFoundAFolderSetAside, step.Course, step.Section,
                                UndoTrail.FoundAFolderSetAsideWords(place, keptAs, changes)));
    }

    /// <summary>A place's path inside the working folder, forward slashes, or its last name when it is not inside it.</summary>
    private static string InsideTheFolder(string full, string root)
    {
        string rootPath = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        string fullPath = Path.GetFullPath(full);
        return fullPath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase)
            ? fullPath[rootPath.Length..].Replace(Path.DirectorySeparatorChar, '/')
            : Path.GetFileName(fullPath);
    }

    /// <summary><c>1 file added, 2 changed</c> against the step's recorded listing, or <c>changed</c> when the list no longer holds it.</summary>
    private static string WhatChanged(string folder, UndoStep step, string place, UndoJournal? journal)
    {
        string? recordedSha = null;
        foreach (UndoOp op in step.Ops)
        {
            if (string.Equals(op.Path, place, StringComparison.Ordinal)) recordedSha = op.ListingSha;
        }
        UndoTreeListing? recorded = null;
        try
        {
            if (journal is not null && recordedSha is not null && journal.Blob(recordedSha) is { } bytes) recorded = UndoTreeListing.Parse(bytes);
        }
        catch (UndoListUnreadableException) { }
        if (recorded is null || UndoTreeReading.Read(folder) is not UndoTreeReading.Tree now) return "changed";
        var before = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach ((string path, string sha) in recorded.Files) before[path] = sha;
        int added = 0, changed = 0;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach ((string path, string sha) in now.Listing.Files)
        {
            seen.Add(path);
            if (before.TryGetValue(path, out string? was)) { if (was != sha) changed++; }
            else added++;
        }
        int removed = before.Keys.Count(path => !seen.Contains(path));
        var parts = new List<string>();
        if (added > 0) parts.Add(added == 1 ? "1 file added" : $"{added} files added");
        if (changed > 0) parts.Add(changed == 1 ? "1 changed" : $"{changed} changed");
        if (removed > 0) parts.Add(removed == 1 ? "1 removed" : $"{removed} removed");
        return parts.Count == 0 ? "changed" : string.Join(", ", parts);
    }

    private static HashSet<long> ClosedByPruningNow(UndoJournalWriter writer, UndoJournal journal)
    {
        var seqs = new HashSet<long>();
        try
        {
            foreach (UndoPruneAction action in UndoPruning.Decide(writer.Reading(), journal.Now, journal.IsAlive))
            {
                if (action is UndoPruneAction.ClosedUnsettled closed) seqs.Add(closed.Seq);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        return seqs;
    }

    /// <summary>
    /// Removes the staged files of every step closed <c>interrupted</c> this
    /// process has not yet tidied and whose folder it can reach (a step closed
    /// while its folder was away: <c>knownLimits.stagedFilesOfAFolderAway</c>,
    /// the director's ruling 6 on U1's third round). Once per process; one
    /// whose file could not be removed is looked for again at the next lock.
    /// </summary>
    internal static void TidyClosedSteps(UndoJournalWriter writer, UndoJournal journal, Action<UndoTrailLine>? trail = null)
    {
        foreach (UndoFoldedStep record in writer.Folded.Steps.Values)
        {
            if (record.State != UndoStepState.Interrupted) continue;
            string key = UndoProcessMemory.KeyOf(journal.Folder) + "#" + record.Seq;
            if (journal.Memory.HasTidied(key)) continue;
            if (RootOf(record.Step, journal) is not { } root) continue;
            bool allGone;
            UndoStep closedStep = record.Step;
            try
            {
                allGone = UndoSwap.TidyLeftovers(record.Seq, closedStep.Paths, root, AsideListings(closedStep, root),
                                                 found => NoteAnAsideFolder(found, closedStep, root, journal, trail));
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { allGone = false; }
            if (allGone) journal.Memory.NoteTidied(key);
        }
    }

    private sealed record SettleAnswer(UndoRecoveryResult? Result, bool TryAgain, bool Stopped, UndoRefusal? Why = null)
    {
        /// <summary>Left, to be tried again, for the reason given.</summary>
        internal static SettleAnswer AgainFor(UndoRefusal why) => new(null, true, false, why);

        internal static readonly SettleAnswer Again = new(null, true, false);
        internal static readonly SettleAnswer Nothing = new(null, false, false);
        internal static readonly SettleAnswer Halted = new(null, false, true);
    }

    /// <summary>Where each file of a step stands now, by content, in the order its ops name them.</summary>
    internal static IReadOnlyList<(string Path, UndoOpState State)> FileStates(UndoStep step, string root, IUndoExternalPlaces? places = null)
    {
        var order = new List<string>();
        var states = new Dictionary<string, UndoOpState>(StringComparer.Ordinal);
        var currents = new Dictionary<string, UndoCurrent?>(StringComparer.Ordinal);
        foreach (UndoOp op in step.Ops)
        {
            if (op.IsWhole)
            {
                // A move, a tree or an external op is one place of its own,
                // judged whole (a move by its pair, never by one side); a place
                // that now leads outside the folder is in the way.
                string place = op.PlaceName;
                if (!states.ContainsKey(place)) order.Add(place);
                states[place] = op.PathsNamed.Any(named => !UndoPlaces.StaysInside(root, named))
                    ? UndoOpState.Neither
                    : UndoCheck.WholeStateOf(op, root, places ?? new UndoAppSettingsPlaces());
                continue;
            }
            if (op.Kind == UndoOp.Recompute || op.Path is not { } path) continue;
            if (!currents.ContainsKey(path))
            {
                // A place that now leads outside the folder (a junction since)
                // is read through nothing: it is in the way.
                currents[path] = UndoPlaces.StaysInside(root, path) ? UndoCurrent.Read(UndoDoor.FullPath(root, path)) : null;
                order.Add(path);
            }
            UndoOpState state = currents[path] is { } current ? UndoCheck.StateOf(op, current) : UndoOpState.Neither;
            if (states.TryGetValue(path, out UndoOpState earlier))
            {
                // A page another program holds with no read sharing stays IN
                // USE, so the refusal names the file in use, never cannot tell
                // (W4's review, LOW 4); otherwise one that cannot be read now
                // stays cannot tell.
                if (earlier == UndoOpState.InUse || state == UndoOpState.InUse) states[path] = UndoOpState.InUse;
                else if (earlier == UndoOpState.CannotTell || state == UndoOpState.CannotTell) states[path] = UndoOpState.CannotTell;
                else if (earlier != state) states[path] = UndoOpState.Neither;
            }
            else
            {
                states[path] = state;
            }
        }
        return order.Select(path => (path, states[path])).ToList();
    }

    private static SettleAnswer Settle(UndoFoldedStep record, string root, UndoJournalWriter writer, UndoJournal journal,
                                       UndoMode mode, Action<UndoTrailLine>? trail, UndoSeams? seams, IUndoExternalPlaces places)
    {
        UndoStep step = record.Step;
        (UndoPhase phase, string work) = record.State switch
        {
            UndoStepState.Begun => (UndoPhase.Begin, "apply"),
            UndoStepState.Undoing => (UndoPhase.Undoing, "undo"),
            UndoStepState.Redoing => (UndoPhase.Redoing, "redo"),
            _ => (UndoPhase.Begin, ""),
        };
        if (work.Length == 0) return SettleAnswer.Nothing;
        string label = $"{step.Seq}-{work}";
        bool live = mode == UndoMode.Live;

        if (live)
        {
            // Everything the stopped work staged goes first: its new contents,
            // and the kept originals, whose content the list holds to put back
            // (a step whose content is missing is closed as it stands).
            // A teacher's folder it set aside is put back in its place, or
            // kept under a visible name beside it, never deleted (W6).
            try
            {
                UndoSwap.TidyLeftovers(step.Seq, step.Paths, root, AsideListings(step, root),
                                       found => NoteAnAsideFolder(found, step, root, journal, trail));
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            if (seams?.Stops("afterRecoveryTidied") == true) return SettleAnswer.Halted;
        }

        bool startedFromBefore = phase is UndoPhase.Begin or UndoPhase.Redoing;
        UndoOpState startState = startedFromBefore ? UndoOpState.Before : UndoOpState.After;
        IReadOnlyList<(string Path, UndoOpState State)> files = FileStates(step, root, places);
        // A teacher's folder still set aside after the tidying is IN THE WAY,
        // never settled as if it were gone; one whose place cannot be read stays
        // cannot tell, tried again.
        HashSet<string> keptAside = FoldersKeptAside(step, root);
        if (keptAside.Count > 0)
        {
            var judged = new List<(string, UndoOpState)>();
            foreach ((string path, UndoOpState state) in files)
                judged.Add(keptAside.Contains(path) && state is not (UndoOpState.CannotTell or UndoOpState.InUse) ? (path, UndoOpState.Neither) : (path, state));
            files = judged;
        }
        // An interrupted line names files inside the working folder: an
        // external op's target is no path, so it is never named there.
        var targets = new HashSet<string>(StringComparer.Ordinal);
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind == UndoOp.External && op.Target is { } target) targets.Add(target);
        }
        List<string> PathsOnly(IEnumerable<string> places) => places.Where(place => !targets.Contains(place)).ToList();
        // A file that could not be read now is never judged changed by hand:
        // tried again on the schedule, as for a file in use (ruling 4).
        foreach ((string path, UndoOpState state) in files)
        {
            if (state is UndoOpState.InUse)
                return SettleAnswer.AgainFor(new UndoRefusal(UndoRefusalKind.FileIsInUse, path));
            if (state is UndoOpState.CannotTell or UndoOpState.NotReadable)
                return SettleAnswer.AgainFor(new UndoRefusal(UndoRefusalKind.CannotTellNow, path));
        }

        int atStart = 0, atEnd = 0;
        var inTheWay = new List<string>();
        var endPaths = new List<string>();
        foreach ((string path, UndoOpState state) in files)
        {
            if (state == UndoOpState.Neither) inTheWay.Add(path);
            else if (state == startState) atStart++;
            else { atEnd++; endPaths.Add(path); }
        }

        var events = new List<JsonObject>();
        UndoRecoveryOutcome outcome;
        int putBack = 0;
        UndoTrailLine? line = null;
        string? course = step.Course;
        long? section = step.Section;
        string phaseWord = phase.ToString().ToLowerInvariant();

        if (inTheWay.Count == 0 && atEnd == 0)
        {
            outcome = UndoRecoveryOutcome.NothingTookEffect;
            events.Add(new JsonObject { ["seq"] = step.Seq, ["event"] = "failed", ["phase"] = phaseWord, ["reason"] = "nothingTookEffect" });
        }
        else if (inTheWay.Count == 0 && atStart == 0)
        {
            outcome = UndoRecoveryOutcome.Completed;
            string finishing = phase switch { UndoPhase.Undoing => "undone", UndoPhase.Redoing => "redone", _ => "applied" };
            events.Add(new JsonObject { ["seq"] = step.Seq, ["event"] = finishing });
        }
        else
        {
            if (live && endPaths.Count > 0)
            {
                var opsToPutBack = step.Ops.Where(op => op.Kind != UndoOp.Recompute && endPaths.Contains(op.PlaceName)).ToList();
                UndoCheck.PlanResult plan;
                try
                {
                    plan = UndoCheck.Plan(opsToPutBack, backward: startedFromBefore,
                                          relative => UndoCurrent.Read(UndoDoor.FullPath(root, relative)), journal.Blob,
                                          whole: new UndoWholeReads(root, places));
                }
                catch (UndoListUnreadableException)
                {
                    // Content it needs cannot be read just now: tried again.
                    return SettleAnswer.AgainFor(new UndoRefusal(UndoRefusalKind.CannotTellNow));
                }
                switch (plan)
                {
                    case UndoCheck.PlanResult.FileIsInUse or UndoCheck.PlanResult.CannotTellNow or UndoCheck.PlanResult.FolderCannotBeReached:
                        return SettleAnswer.AgainFor(UndoDoor.RefusalOf(plan));
                    case UndoCheck.PlanResult.Ready ready:
                    {
                        var putBackTargets = ready.InOrder.Select(change => new UndoSwapTarget(UndoDoor.FullPath(root, change.Path), change.Path,
                                                                                                change.Expected, change.Replacement)).ToList();
                        putBackTargets.AddRange(ready.Whole);
                        UndoSeams? recoverySeams = seams is null ? null : new UndoSeams
                        {
                            StopsHere = (point, index) => seams.Stops(point == "beforeSwap" ? "recoveryBeforeSwap" : point, index),
                        };
                        switch (UndoSwap.Swap(putBackTargets, label + "-recover", root.Length == 0 ? null : root, recoverySeams, places))
                        {
                            case UndoSwapResult.StoppedByATest: return SettleAnswer.Halted;
                            case UndoSwapResult.Refused refused: return SettleAnswer.AgainFor(refused.Refusal);   // a file in use: tried again on the schedule
                        }
                        putBack = putBackTargets.Count;
                        break;
                    }
                    default:
                    {
                        // It can never be put back (its content missing): closed,
                        // never left in flight (the director's ruling 4).
                        var leftPartWay = endPaths.OrderBy(path => path, StringComparer.Ordinal).ToList();
                        foreach (string path in inTheWay)
                        {
                            if (!leftPartWay.Contains(path)) leftPartWay.Add(path);
                        }
                        events.Add(Interrupted(step.Seq, phaseWord, "couldNotPutBack", PathsOnly(leftPartWay)));
                        events.Add(new JsonObject { ["event"] = "cleared", ["reason"] = "interrupted" });
                        if (seams?.Stops("recoveryBeforeWriting") == true) return SettleAnswer.Halted;
                        if (!Write(events, step, writer)) return SettleAnswer.Nothing;
                        trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoRolledBack, course, section,
                                                        UndoTrail.InterruptedWords(phase, 0, leftPartWay.Count)));
                        return new SettleAnswer(new UndoRecoveryResult(step.Seq, phase, UndoRecoveryOutcome.Interrupted, step, root, 0, leftPartWay.Count), false, false);
                    }
                }
            }
            if (inTheWay.Count == 0 && live)
            {
                outcome = UndoRecoveryOutcome.RolledBack;
                events.Add(new JsonObject { ["seq"] = step.Seq, ["event"] = "rolledBack", ["phase"] = phaseWord, ["reason"] = "partlyTookEffect" });
                line = new UndoTrailLine(ActivityTrail.Event.UndoRolledBack, course, section, UndoTrail.RolledBackWords(phase, putBack));
            }
            else if (inTheWay.Count == 0)
            {
                // Shadow: recorded, never repaired.
                outcome = UndoRecoveryOutcome.LeftAlone;
                events.Add(Interrupted(step.Seq, phaseWord, "partlyTookEffect", PathsOnly(endPaths.OrderBy(path => path, StringComparer.Ordinal))));
                events.Add(new JsonObject { ["event"] = "cleared", ["reason"] = "interrupted" });
            }
            else
            {
                outcome = UndoRecoveryOutcome.Interrupted;
                events.Add(Interrupted(step.Seq, phaseWord, "changedByHand", PathsOnly(inTheWay)));
                events.Add(new JsonObject { ["event"] = "cleared", ["reason"] = "interrupted" });
                // In shadow nothing was put back and nothing offered was
                // cleared: the journal holds the outcome, the trail does not.
                if (live)
                    line = new UndoTrailLine(ActivityTrail.Event.UndoRolledBack, course, section, UndoTrail.InterruptedWords(phase, putBack, inTheWay.Count));
            }
        }
        if (seams?.Stops("recoveryBeforeWriting") == true) return SettleAnswer.Halted;
        if (outcome == UndoRecoveryOutcome.Completed && phase == UndoPhase.Begin)
        {
            try { writer.DropTheRedoBranch(below: step.Seq); }
            catch (UndoJournalException) { return SettleAnswer.Nothing; }
        }
        if (!Write(events, step, writer)) return SettleAnswer.Nothing;
        if (line is not null) trail?.Invoke(line);
        return new SettleAnswer(new UndoRecoveryResult(step.Seq, phase, outcome, step, root, putBack, inTheWay.Count), false, false);
    }

    private static JsonObject Interrupted(long seq, string phase, string reason, IReadOnlyList<string> paths)
    {
        var named = new JsonArray();
        foreach (string path in paths) named.Add(path);
        return new JsonObject { ["seq"] = seq, ["event"] = "interrupted", ["phase"] = phase, ["reason"] = reason, ["paths"] = named };
    }

    /// <summary>Appends recovery's lines (a clearing's seq the highest in the journal as it is written) and makes them durable.</summary>
    private static bool Write(IEnumerable<JsonObject> events, UndoStep step, UndoJournalWriter writer)
    {
        try
        {
            foreach (JsonObject line in events)
            {
                if ((string?)line["event"] == "cleared") line["seq"] = Math.Max(writer.Folded.Highest, step.Seq);
                writer.Append(line);
            }
            writer.Sync();
            return true;
        }
        catch (UndoJournalException)
        {
            return false;
        }
    }
}

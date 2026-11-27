using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Undo;

/// <summary>Whether the list is live or written in shadow (<c>rule.shadow</c>): the switch, passed in, never read from a static.</summary>
internal enum UndoMode { Live, Shadow }

/// <summary>One file before and after a change, as the action that made it saw it (null: no file).</summary>
internal sealed record UndoFileChange(string RelativePath, byte[]? Before, byte[]? After);

/// <summary>What an action hands the door: everything about the step but its number (the mac's <c>UndoStepDraft</c>).</summary>
internal sealed record UndoStepDraft
{
    internal required string ActionKey { get; init; }
    internal IReadOnlyDictionary<string, string> ActionArguments { get; init; } = new Dictionary<string, string>(StringComparer.Ordinal);
    internal required string MadeBy { get; init; }

    /// <summary>The working folder's root: the folder holding <c>courses\</c>, as its canonical path.</summary>
    internal required string WorkingFolder { get; init; }

    internal string? Course { get; init; }
    internal long? Section { get; init; }
    internal string? Class { get; init; }
    internal string? Holds { get; init; }

    /// <summary>The files the action changes, each with what it held before and holds after.</summary>
    internal IReadOnlyList<UndoFileChange> Changes { get; init; } = [];

    /// <summary>Files kept true by a rule (<c>recompute</c> ops), re-derived after the others.</summary>
    internal IReadOnlyList<JsonObject> Recomputes { get; init; } = [];
}

/// <summary>A step given as its ops (the mac's <c>UndoOpsDraft</c>): the one entry for every kind, with every blob its ops need.</summary>
internal sealed record UndoOpsDraft
{
    internal required string ActionKey { get; init; }
    internal IReadOnlyDictionary<string, string> ActionArguments { get; init; } = new Dictionary<string, string>(StringComparer.Ordinal);
    internal required string MadeBy { get; init; }

    /// <summary>The working folder's root, or null for a step none of whose ops names a path (a preference, U4).</summary>
    internal string? WorkingFolder { get; init; }

    internal string? Course { get; init; }
    internal long? Section { get; init; }
    internal string? Class { get; init; }
    internal string? Holds { get; init; }
    internal required JsonArray Ops { get; init; }

    /// <summary>The content every blob the ops name holds, stored in the same hold as the begin.</summary>
    internal IReadOnlyList<byte[]> Blobs { get; init; } = [];
}

internal enum UndoOutcomeKind
{
    Applied, AppliedWithoutARecord, CouldNotRecordTheStep, ChangedNothing,
    Undone, Redone, NothingToUndo, NothingToRedo, AnotherChangeIsUnderWay, NotAvailable,
    Refused, ListUnavailable, StoppedByATest,
}

/// <summary>How the door went: a step made, an undo, a redo.</summary>
internal sealed record UndoOutcome(UndoOutcomeKind Kind, long? Seq = null, UndoRefusal? Refusal = null, bool ClearedTheList = false)
{
    /// <summary>
    /// A refused step whose swap could not be reversed (W7a; the mac's
    /// <c>leftPartWay</c>): a file holds the new content while what it held
    /// before is kept beside it. Never said as "Nothing was changed".
    /// </summary>
    internal bool LeftPartWay { get; init; }

    /// <summary>The word the contract spells it with: a refusal's own word, otherwise the outcome's.</summary>
    internal string Word => Kind == UndoOutcomeKind.Refused
        ? Refusal!.Word
        : char.ToLowerInvariant(Kind.ToString()[0]) + Kind.ToString()[1..];
}

/// <summary>
/// The runners of the maintainers a <c>recompute</c> names
/// (<c>opKinds.recompute</c>). The app's is <see cref="UndoSectionFrontPage"/>; until a step's
/// maintainer has a runner, its step is not available (never undone or redone
/// with its re-derivation skipped).
/// </summary>
internal interface IUndoMaintainers
{
    bool CanRun(string maintainer);

    /// <summary>Re-derives the file a recompute op keeps true, after the step's other ops.</summary>
    void Rederive(UndoOp op, string root);
}

/// <summary>
/// The ONE door every change to a working folder goes through once the switch
/// is on (#899 W2b; the mac's <c>JournaledWrite</c> and <c>UndoJournal.move</c>):
/// it records the step, then makes the change; and it undoes and redoes the
/// newest step, linearly.
///
/// <para><b>Write-ahead, three holds</b> (<c>rule.writeAhead</c>). Phase one,
/// under the lock: the next number from the fresh fold, the step's blobs
/// (<see cref="UndoJournalWriter.WriteBlobs"/>, four at a time: W2a measured a
/// 233-page step's 466 blobs holding the lock 1.3 to 1.5 s one at a time, 0.41
/// s four at a time), the <c>begin</c> line naming every op, made durable.
/// Phase two, OUTSIDE the lock: the staged swap (<see cref="UndoSwap"/>).
/// Phase three, under the lock: <c>applied</c> with the redo branch dropped at
/// that moment, then pruning; or <c>failed</c> (phase begin, reason refused).
/// A closing the lock refuses for ten seconds is kept by the process and
/// written first at its next hold.</para>
///
/// <para><b>A step's blobs and its begin are ONE hold, and that hold never
/// prunes</b> (W2a's review, LOW 2). A blob already on the disk is used as it
/// is; if a pruning could run between storing (or finding) it and writing the
/// begin that names it, it could delete what the begin then names. So
/// <see cref="Begin"/> is the only place blobs are stored, it writes the begin
/// in the same body, and pruning runs only in the closing hold, after the
/// begin is on the list and keeps them.</para>
///
/// <para><b>Undo and Redo</b> (<c>rule.linear</c>, <c>rule.stagedThenSwapped</c>).
/// Inside the lock, what is offered; outside it, EVERY op checked with nothing
/// written (<see cref="UndoCheck.Plan"/>); inside it again, still the one to
/// move, <c>undoing</c> or <c>redoing</c> made durable; the swap; <c>undone</c>
/// or <c>redone</c>. A refusal because the page was changed by hand, or content
/// is missing, clears the list (an Undo: rulings 13 and 22) or drops the redo
/// branch from that step up (a Redo: ruling 20); a file in use, a page that
/// cannot be written, or one that cannot be read now changes nothing on the
/// list, to be tried again.</para>
///
/// <para><b>Recovery</b> (W3, <see cref="UndoRecovery"/>) runs inside phase
/// one (on the ordinary path's schedule), in the hold that finds what Undo or
/// Redo acts on (at once, re-deriving what it settles), before every prune,
/// and when the app asks (<see cref="Recover"/>). A swap that could not be
/// reversed, or a closing that could not be written or kept, leaves the step
/// IN FLIGHT and noted as abandoned by this process, so recovery settles it
/// by content: never <c>failed</c> for a half-applied step (W2b's review,
/// LOW 1). The app calls only <see cref="Recover"/> yet, at launch, through
/// <see cref="UndoForThisProcess"/> (W4); its actions come through the door
/// from W7, and the switch stays off until W11a.</para>
/// </summary>
internal sealed class UndoDoor
{
    /// <summary>How long a closing event waits for the lock before it is kept (the mac's <c>UndoSwitch.finishWaitSeconds</c>, 10 s; the plan review's L6).</summary>
    internal static readonly TimeSpan FinishWait = TimeSpan.FromSeconds(10);

    /// <summary>A step's blobs are written this many at a time (W2a's measurement).</summary>
    internal const int BlobParallelism = 4;

    private readonly UndoJournal _journal;
    private readonly UndoMode _mode;
    private readonly UndoSeams? _seams;
    private readonly IUndoMaintainers? _maintainers;
    private readonly JsonObject _process;
    private readonly TimeSpan _finishWait;
    private readonly Action<UndoTrailLine>? _trail;
    private readonly IUndoExternalPlaces _places;

    /// <param name="process">This process as the journal names it (host, pid, name, started); the real process by default.</param>
    /// <param name="finishWait">How long a closing waits for the lock live (<see cref="FinishWait"/>; a test's seam).</param>
    /// <param name="trail">Where recovery's trail lines go (<c>undo rolled back</c>): the app's start-up (W4) passes
    /// <see cref="UndoTrail.ToTheActivityTrail"/>; none by default, so a test never writes the real trail.</param>
    /// <param name="places">Where an external op's target is read and set (W6): the app's own settings by default, a test's own in a test.</param>
    internal UndoDoor(UndoJournal journal, UndoMode mode, IUndoMaintainers? maintainers = null, UndoSeams? seams = null,
                      JsonObject? process = null, TimeSpan? finishWait = null, Action<UndoTrailLine>? trail = null,
                      IUndoExternalPlaces? places = null)
    {
        _places = places ?? new UndoAppSettingsPlaces();
        _finishWait = finishWait ?? FinishWait;
        _trail = trail;
        _journal = journal;
        _mode = mode;
        _maintainers = maintainers;
        _seams = seams;
        _process = process ?? ThisProcess();
    }

    /// <summary>This process as a journal line names it: host, pid, name and start moment (<c>WorkLease</c>'s liveness rule reads them back).</summary>
    internal static JsonObject ThisProcess()
    {
        using Process me = Process.GetCurrentProcess();
        return new JsonObject
        {
            ["host"] = Environment.MachineName,
            ["pid"] = Environment.ProcessId,
            ["name"] = me.ProcessName,
            ["started"] = WorkLease.StartMoment(me.StartTime),
        };
    }

    private bool Live => _mode == UndoMode.Live;
    private bool Stops(string point, int index = -1) => _seams?.Stops(point, index) == true;

    // ---- A step given as files before and after ---------------------------------

    /// <summary>
    /// Records the step, makes the change, and marks it made. Each file's ops
    /// are worked out from its before and after (<see cref="UndoLineOps.ForAFile"/>);
    /// the swap goes from the draft's own before and after, and each file is
    /// re-read just before its rename, so a page changed since the action read
    /// it refuses the step before anything is written.
    /// </summary>
    internal UndoOutcome Perform(UndoStepDraft draft)
    {
        var ops = new JsonArray();
        var blobs = new List<byte[]>();
        var targets = new List<UndoSwapTarget>();
        // In the order the action planned them, as the mac's JournaledWrite
        // takes draft.changes: an Undo checks the ops newest first, so this
        // order decides which page a refusal names first (action-047).
        foreach (UndoFileChange change in draft.Changes)
        {
            if (SameBytes(change.Before, change.After)) continue;
            foreach (JsonNode? op in UndoLineOps.ForAFile(change.RelativePath, change.Before, change.After))
            {
                ops.Add(op!.DeepClone());
                if ((string?)op["kind"] == UndoOp.WriteFile)
                {
                    if (change.Before is { } before) blobs.Add(before);
                    if (change.After is { } after) blobs.Add(after);
                }
            }
            targets.Add(new UndoSwapTarget(FullPath(draft.WorkingFolder, change.RelativePath), change.RelativePath, change.Before, change.After));
        }
        if (ops.Count == 0) return new UndoOutcome(UndoOutcomeKind.ChangedNothing);
        foreach (JsonObject recompute in draft.Recomputes)
        {
            // Refused alike by both entries (the final sweep of W2a/W2b): a step
            // whose rule this process cannot run is never recorded and made with
            // its re-derivation skipped, which would leave it not available to
            // every Undo after it and block the list.
            if ((string?)recompute["maintainer"] is not { } maintainer || _maintainers?.CanRun(maintainer) != true)
                return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: new UndoRefusal(UndoRefusalKind.NotReadable));
            ops.Add(recompute.DeepClone());
        }

        JsonObject header = Header(draft.ActionKey, draft.ActionArguments, draft.MadeBy, draft.Course, draft.Section, draft.Class, draft.Holds);
        long seq;
        try
        {
            seq = Begin(header, draft.WorkingFolder, ops, blobs, draft.Course);
        }
        catch (AnotherChangeIsUnderWayException)
        {
            return new UndoOutcome(UndoOutcomeKind.AnotherChangeIsUnderWay);
        }
        catch (Exception error) when (IsAFailureOfTheList(error))
        {
            string why = WordFor(error);
            if (Live)
            {
                CouldNotRecord(draft, why, UndoUnrecordedChange.NothingWasChanged);
                return new UndoOutcome(UndoOutcomeKind.CouldNotRecordTheStep);
            }
            // Shadow: the change goes ahead exactly as it would have
            // (rule.shadow), the files a rule keeps true re-derived as on the
            // recorded path: a list that failed never leaves the section's
            // front page stale (the mac's performAndRederive re-derives on
            // appliedWithoutARecord; W4's review, MEDIUM). One trail line says
            // what became of it, once that is known (W7a; the mac's
            // UndoTrailHook.couldNotRecord).
            switch (UndoSwap.Swap(targets, UndoSwap.PlainLabel(), draft.WorkingFolder, _seams))
            {
                case UndoSwapResult.Refused refused:
                    CouldNotRecord(draft, why, refused.LeftPartWay ? UndoUnrecordedChange.StoppedPartWay : UndoUnrecordedChange.NothingWasChanged);
                    return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: refused.Refusal) { LeftPartWay = refused.LeftPartWay };
                case UndoSwapResult.StoppedByATest: return new UndoOutcome(UndoOutcomeKind.StoppedByATest);
            }
            Rederive(OpsOf(ops), draft.WorkingFolder);
            CouldNotRecord(draft, why, UndoUnrecordedChange.WentAhead);
            return new UndoOutcome(UndoOutcomeKind.AppliedWithoutARecord);
        }
        return MakeTheStep(seq, targets, draft.WorkingFolder, ops);
    }

    // ---- A step given as its ops (the one entry for every kind) -----------------

    /// <summary>
    /// Records a step given as its ops, then makes it, planned FORWARD from what
    /// is on the disk exactly as a Redo plans it, so a step is made by the same
    /// check and the same swap that later undoes and redoes it. Nothing changes
    /// until the step is one every reader of this version can undo: it reads
    /// back readable (an op of a kind this version does not read yet, U5's
    /// reserved two, is refused <c>notReadable</c> here), every path stays
    /// inside the working folder through its links, and every blob it names is
    /// given or already held (the mac's <c>vet</c>, the hard review of U2b, HIGH 1).
    /// </summary>
    internal UndoOutcome Perform(UndoOpsDraft draft)
    {
        JsonObject header = Header(draft.ActionKey, draft.ActionArguments, draft.MadeBy, draft.Course, draft.Section, draft.Class, draft.Holds);
        bool hasAContentOp = false;
        foreach (JsonNode? op in draft.Ops)
        {
            if ((string?)op?["kind"] != UndoOp.Recompute) hasAContentOp = true;
        }
        if (!hasAContentOp) return new UndoOutcome(UndoOutcomeKind.ChangedNothing);
        // 1. Read back as a reader of this version reads it. A step with no
        // working folder is readable only when none of its ops names a path
        // (an external op alone, opKinds.wholeOps); otherwise it is refused,
        // never an exception (W2b's review, LOW 6).
        JsonObject? trialFolder = draft.WorkingFolder is null ? null : new JsonObject
        {
            ["id"] = "00000000-0000-0000-0000-000000000000", ["pathAtTheTime"] = draft.WorkingFolder,
        };
        JsonObject trial = BeginLine(1, header, trialFolder, (JsonArray)draft.Ops.DeepClone());
        UndoLine readBack = UndoFormat.Parse(UndoJournalWriter.Encode(Stamped(trial)));
        if (!readBack.Readable || readBack.Step is not { Readable: true } step)
            return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: new UndoRefusal(UndoRefusalKind.NotReadable));
        foreach (UndoOp op in step.Ops)
        {
            if (!op.Readable) return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: new UndoRefusal(UndoRefusalKind.NotReadable));
            if (op.Kind == UndoOp.Recompute && !CanRederive(op))
                return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: new UndoRefusal(UndoRefusalKind.NotReadable));
        }
        // 2. Every path inside the working folder, its links resolved (a
        // link's move by the folders above the link alone, U4b2-14; W8-6).
        foreach (UndoOp op in step.Ops)
        {
            if (op.PathsNamed.Any() && (draft.WorkingFolder is null || UndoPlaces.FirstPlaceLeadingOut(draft.WorkingFolder, op) is not null))
                return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: new UndoRefusal(UndoRefusalKind.NotReadable));
        }
        // 3. Every blob it names, given or already held, hashing to its name.
        // Asked here to refuse early, and again INSIDE the begin hold, since
        // another process may prune a held blob before the begin names it
        // (W2b's review, LOW 5).
        var given = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (byte[] blob in draft.Blobs) given[UndoCheck.Sha(blob)] = blob;
        var held = new List<string>();
        try
        {
            foreach (UndoOp op in step.Ops)
            {
                foreach (string name in op.Blobs)
                {
                    if (given.ContainsKey(name)) continue;
                    if (_journal.Blob(name) is null)
                        return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: new UndoRefusal(UndoRefusalKind.NotReadable));
                    held.Add(name);
                }
                // A tree's listing must read back, and every file it lists be
                // one of the op's blobs, so the folder can always be made again.
                if (op.Kind is UndoOp.CreateTree or UndoOp.RemoveTree)
                {
                    byte[]? listingBytes = given.TryGetValue(op.ListingSha!, out byte[]? givenListing) ? givenListing : _journal.Blob(op.ListingSha!);
                    if (listingBytes is null || UndoTreeListing.Parse(listingBytes) is not { } listing)
                        return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: new UndoRefusal(UndoRefusalKind.NotReadable));
                    foreach ((_, string sha) in listing.Files)
                    {
                        if (!op.Blobs.Contains(sha, StringComparer.Ordinal))
                            return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: new UndoRefusal(UndoRefusalKind.NotReadable));
                    }
                }
            }
        }
        catch (UndoListUnreadableException) { return new UndoOutcome(UndoOutcomeKind.CouldNotRecordTheStep); }

        string root = draft.WorkingFolder ?? "";
        // A step that died part way and keeps a file true by a rule is settled
        // AND re-derived first: the recovery inside the begin below leaves such
        // a step for this one (the mac's performAndRederive; the second hard
        // review of U2b, MEDIUM 1).
        if (Live) Recover();
        _seams?.BeforeTheBegin?.Invoke();
        long seq;
        try { seq = Begin(header, draft.WorkingFolder, (JsonArray)draft.Ops.DeepClone(), draft.Blobs, draft.Course, held); }
        catch (AnotherChangeIsUnderWayException)
        {
            return new UndoOutcome(UndoOutcomeKind.AnotherChangeIsUnderWay);
        }
        catch (BlobGoneException)
        {
            return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: new UndoRefusal(UndoRefusalKind.NotReadable));
        }
        catch (Exception error) when (IsAFailureOfTheList(error))
        {
            // In EITHER mode, as the mac's JournaledWrite.perform(ops:): a step
            // given as its ops is refused before anything changes when the
            // list cannot be written. Its actions (U3, U4) settle how a shadow
            // step of these kinds is recorded beside the action's own writes.
            return new UndoOutcome(UndoOutcomeKind.CouldNotRecordTheStep);
        }
        if (Stops("afterBegin")) return new UndoOutcome(UndoOutcomeKind.StoppedByATest);
        UndoCheck.PlanResult plan;
        try
        {
            plan = UndoCheck.Plan(step.Ops, backward: false, relative => UndoCurrent.Read(FullPath(root, relative)), _journal.Blob,
                                  whole: new UndoWholeReads(root, _places));
        }
        catch (UndoListUnreadableException)
        {
            Finish(seq, "failed", "begin", "refused");
            return new UndoOutcome(UndoOutcomeKind.CouldNotRecordTheStep);
        }
        if (plan is not UndoCheck.PlanResult.Ready ready)
        {
            Finish(seq, "failed", "begin", "refused");
            return new UndoOutcome(UndoOutcomeKind.Refused, Refusal: RefusalOf(plan));
        }
        return MakeTheStep(seq, TargetsOf(ready, root), root, step.Ops, alreadyAskedAfterBegin: true);
    }

    /// <summary>
    /// A word for why the list could not take a step, never the error's own
    /// description, which can carry a path (the mac's <c>UndoTrailHook.word</c>).
    /// </summary>
    internal static string WordFor(Exception error) => error switch
    {
        UndoJournalException { Failure: UndoJournalFailure.LockBusy } => "the list was busy",
        UndoJournalException { Failure: UndoJournalFailure.ListNotReadable } or UndoListUnreadableException => "the list could not be read",
        _ => "the list could not be written",
    };

    /// <summary>The "undo could not record a step" line for a step given as files (W7a).</summary>
    private void CouldNotRecord(UndoStepDraft draft, string why, UndoUnrecordedChange change) =>
        _trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoCouldNotRecordAStep, draft.Course, draft.Section,
                                         UndoTrail.CouldNotRecordWords(draft.ActionKey, why, change)));

    /// <summary>
    /// A failure of the list's own files: a disk or permission error, or any
    /// failure at all in shadow, where nothing the list does may stop or change
    /// the teacher's action (<c>rule.shadow</c>; W4).
    /// </summary>
    private bool IsAFailureOfTheList(Exception error) =>
        error is UndoJournalException or IOException or UnauthorizedAccessException || !Live;

    // ---- Undo and Redo ------------------------------------------------------------

    /// <summary>Undoes the newest step: the only one that can be (ruling 9).</summary>
    internal UndoOutcome Undo() => Move(backward: true);

    /// <summary>Redoes the most recently undone step.</summary>
    internal UndoOutcome Redo() => Move(backward: false);

    private UndoOutcome Move(bool backward)
    {
        // 1. Find the step, inside the lock, with recovery run first: at once,
        // since the teacher is waiting (a put-back refused earlier is tried
        // now), re-deriving what it settles once the lock is released.
        UndoAnswer found;
        bool waitsForARederivingRecovery = false;
        UndoRecoveryRun recovered;
        UndoRefusal? leftNewest = null;
        long? newestSeq = null;
        UndoStep? newestStep = null;
        try
        {
            (found, waitsForARederivingRecovery, recovered) = _journal.WithLock(writer =>
            {
                UndoRecoveryRun run = UndoRecovery.Run(writer, _journal, _mode, trySwapsNow: true, leavingStepsThatRederive: false,
                                                       _maintainers, _trail, _seams, _places);
                UndoOffered offered = _journal.Offer(writer.Folded);
                UndoAnswer answer = backward ? offered.Undo : offered.Redo;
                // Nothing is under way: a gone process's step that keeps a file
                // true by a rule, which recovery could not settle, waits for
                // one that can (a runner, a file let go). Not available, never
                // "under way" for ever (the mac's third hard review of U2b, LOW 2).
                UndoFoldedStep? newest = offered.Offered.LastOrDefault(step => step.State != UndoStepState.Undone);
                bool waits = answer.Kind == UndoAnswerKind.AnotherChangeIsUnderWay && newest is { IsInFlight: true }
                             && UndoRecovery.KeepsAFileTrue(newest.Step) && UndoRecovery.MaySettle(newest, _journal);
                if (newest is { IsInFlight: true } && run.Left is { } left && left.TryGetValue(newest.Seq, out UndoRefusal? why))
                {
                    leftNewest = why;
                    newestSeq = newest.Seq;
                    newestStep = newest.Step;
                }
                return (answer, waits, run);
            }, inShadow: !Live);
        }
        catch (Exception error) when (error is UndoJournalException or IOException or UnauthorizedAccessException)
        {
            return new UndoOutcome(UndoOutcomeKind.ListUnavailable);
        }
        if (recovered.StoppedByATest) return new UndoOutcome(UndoOutcomeKind.StoppedByATest);
        RederiveWhatRecoverySettled(recovered);
        if (waitsForARederivingRecovery) return new UndoOutcome(UndoOutcomeKind.NotAvailable);
        // The newest step is a gone process's, and recovery has just tried it
        // and left it for a file in use or a page it cannot read now: nothing is
        // under way, so the answer is that refusal, naming the file, with the
        // list unchanged and tried again at the next Undo (rule.recovery;
        // W3's review, LOW 4), never "another change is under way" until the
        // step ages out.
        if (found.Kind == UndoAnswerKind.AnotherChangeIsUnderWay && leftNewest is { } why)
        {
            // One trail line, "undo refused for a change left part way" (the mac's U3c, leftNewestLine).
            _trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoRefusedForAChangeLeftPartWay, newestStep?.Course, newestStep?.Section,
                                             UndoTrail.LeftNewestWords(backward, why)));
            return new UndoOutcome(UndoOutcomeKind.Refused, newestSeq, why);
        }
        switch (found.Kind)
        {
            case UndoAnswerKind.Nothing: return new UndoOutcome(backward ? UndoOutcomeKind.NothingToUndo : UndoOutcomeKind.NothingToRedo);
            case UndoAnswerKind.NotAvailable: return new UndoOutcome(UndoOutcomeKind.NotAvailable);
            case UndoAnswerKind.AnotherChangeIsUnderWay: return new UndoOutcome(UndoOutcomeKind.AnotherChangeIsUnderWay);
        }
        UndoFoldedStep record = found.Step!;
        long seq = record.Seq;
        if (RootOf(record.Step) is not { } root) return new UndoOutcome(UndoOutcomeKind.NotAvailable);
        // Never undone or redone with its re-derivation skipped.
        foreach (UndoOp op in record.Step.Ops)
        {
            if (op.Kind == UndoOp.Recompute && !CanRederive(op)) return new UndoOutcome(UndoOutcomeKind.NotAvailable);
        }

        // 2. Check every op, writing nothing. Content the list no longer holds
        // is taken from a kept original of the step's own whose hash matches,
        // as recovery does (the mac's U3c, rule.recovery). One that cannot be
        // read just now may be the one: then the answer is cannot tell now,
        // the list kept, never content missing, which clears it (LOW 5).
        UndoCheck.PlanResult plan;
        string? keptOriginalNotRead = null;
        var uses = new List<UndoKeptOriginalUse>();
        try
        {
            plan = UndoCheck.Plan(record.Step.Ops, backward, relative => UndoCurrent.Read(FullPath(root, relative)),
                                  _journal.Blob, () => _journal.CanReach(record.Step), new UndoWholeReads(root, _places),
                                  keptOriginal: UndoRecovery.KeptOriginal(record.Step, root, path => keptOriginalNotRead ??= path),
                                  keptOriginalUsed: uses.Add, ownSeq: record.Step.Seq);
        }
        catch (UndoListUnreadableException) { return new UndoOutcome(UndoOutcomeKind.ListUnavailable); }
        _seams?.AfterTheCheck?.Invoke();
        if (Stops("afterTheCheck")) return new UndoOutcome(UndoOutcomeKind.StoppedByATest);
        if (plan is UndoCheck.PlanResult.NotReadable or UndoCheck.PlanResult.FolderCannotBeReached)
            return new UndoOutcome(UndoOutcomeKind.NotAvailable);
        if (plan is UndoCheck.PlanResult.ContentMissing && keptOriginalNotRead is { } notRead)
            return new UndoOutcome(UndoOutcomeKind.Refused, seq, new UndoRefusal(UndoRefusalKind.CannotTellNow, notRead));
        if (plan is not UndoCheck.PlanResult.Ready ready)
        {
            UndoRefusal refusal = RefusalOf(plan);
            return new UndoOutcome(UndoOutcomeKind.Refused, seq, refusal, AnswerARefusal(refusal, seq, backward));
        }
        // Every place inside the working folder, links resolved, at the plan.
        foreach ((string path, _, _) in ready.InOrder)
        {
            if (root.Length > 0 && !UndoPlaces.StaysInside(root, path))
            {
                var outside = new UndoRefusal(UndoRefusalKind.ChangedSince, path);
                return new UndoOutcome(UndoOutcomeKind.Refused, seq, outside, AnswerARefusal(outside, seq, backward));
            }
        }

        // 3. Say it is under way, as long as it is still the one to move.
        string starting = backward ? "undoing" : "redoing";
        UndoWhatTheListCouldNotTake notTaken = UndoWhatTheListCouldNotTake.Nothing;
        try
        {
            bool stillTheOne = _journal.WithLock(writer =>
            {
                UndoOffered offered = _journal.Offer(writer.Folded);
                UndoAnswer now = backward ? offered.Undo : offered.Redo;
                if (now.Kind != UndoAnswerKind.Step || now.Step!.Seq != seq) return false;
                // What the kept originals give, and what the swap sets aside
                // for the other direction, into the list first, inside the lock
                // and before the swap (the first review of U3c, MEDIUM).
                if (uses.Count > 0) notTaken = UndoRecovery.StoreWhatKeptOriginalsGive(uses, writer, _journal);
                // A page put back from the list whose outgoing bytes the other
                // direction needs and the list lacks (item 4 of the lows fixed
                // with U4a): stored now, or kept beside the page by the swap.
                HashSet<string> notStored = UndoRecovery.StoreWhatTheOtherDirectionNeeds(ready.InOrder, record.Step, backward, root, writer, _journal);
                if (notStored.Count > 0)
                {
                    notStored.UnionWith(notTaken.OutgoingOf);
                    notTaken = new UndoWhatTheListCouldNotTake(notStored, notTaken.KeptOriginalsHolding);
                }
                writer.Append(new JsonObject { ["seq"] = seq, ["event"] = starting, ["process"] = _process.DeepClone() });
                writer.Sync();
                return true;
            });
            if (!stillTheOne) return new UndoOutcome(UndoOutcomeKind.AnotherChangeIsUnderWay);
        }
        catch (Exception error) when (error is UndoJournalException or IOException or UnauthorizedAccessException)
        {
            return new UndoOutcome(UndoOutcomeKind.ListUnavailable);
        }
        if (Stops(backward ? "afterUndoing" : "afterRedoing")) return new UndoOutcome(UndoOutcomeKind.StoppedByATest);

        // 4. Swap.
        string label = $"{seq}-" + (backward ? "undo" : "redo");
        switch (UndoSwap.Swap(TargetsOf(ready, root), label, RootOrNull(root), _seams, _places, notTaken.OutgoingOf))
        {
            case UndoSwapResult.StoppedByATest:
                return new UndoOutcome(UndoOutcomeKind.StoppedByATest);
            case UndoSwapResult.Refused { LeftPartWay: true } partWay:
                // A swap made could not be reversed: half moved, left in flight
                // for recovery, and nothing else said to the list.
                Abandon(seq, backward ? UndoStepState.Undoing : UndoStepState.Redoing);
                return new UndoOutcome(UndoOutcomeKind.Refused, seq, partWay.Refusal);
            case UndoSwapResult.Refused refused:
                // Caught at the swap rather than the check: the same hand edit,
                // so the same answer (rulings 13 and 20).
                Finish(seq, "failed", starting, "refused");
                return new UndoOutcome(UndoOutcomeKind.Refused, seq, refused.Refusal, AnswerARefusal(refused.Refusal, seq, backward));
        }
        if (Stops(backward ? "beforeUndone" : "beforeRedone")) return new UndoOutcome(UndoOutcomeKind.StoppedByATest);
        if (uses.Count > 0 && root.Length > 0)
        {
            // The kept original it was put back from is now a copy of its page,
            // and its bytes are in the list: nothing of the step's is left
            // beside it but what the list could not take (a kept original
            // whose own bytes the list would not take stays, though its page
            // holds the same: the second review of U3c, MEDIUM).
            try
            {
                UndoSwap.TidyLeftovers(seq, record.Step.PathsToTidy, root, UndoRecovery.AsideListings(record.Step, root), null,
                                       keepingOnlyCopies: true, keepingCopiesHolding: notTaken.KeptOriginalsHolding);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
        Finish(seq, backward ? "undone" : "redone", null, null);
        // One kept copy per content per page, never a pile (the mac's U3c
        // review 3, LOW 1, called in its door only, so here only).
        if (notTaken.OutgoingOf.Count > 0 && root.Length > 0)
            UndoRecovery.RemoveSupersededKeptCopies(record.Step, root, notTaken.OutgoingOf, label);
        if (!notTaken.IsEmpty && root.Length > 0) SayWhatItKept(record.Step, root, label, notTaken, backward, uses);
        Rederive(record.Step.Ops, root);
        return new UndoOutcome(backward ? UndoOutcomeKind.Undone : UndoOutcomeKind.Redone, seq);
    }

    /// <summary>
    /// The list could not take all the step needs: the step stays on the list
    /// with the other direction offered, resting on what is kept beside its
    /// pages, as recovery's does (Russell's ruling of 2026-11-20, night). If
    /// that file is gone or changed by then, that Undo or Redo is refused then,
    /// with its true sentence. One line, "undo kept what it replaced", naming
    /// each kept file as it is on the disk now.
    /// </summary>
    private void SayWhatItKept(UndoStep step, string root, string label, UndoWhatTheListCouldNotTake notTaken, bool backward,
                               IReadOnlyList<UndoKeptOriginalUse> uses)
    {
        // Each kept file by its path in the working folder (the page's folder,
        // as the op's path spells it, plus the hidden name), so two pages with
        // one name in two folders stay two (the mac's U4b2-4). The trail
        // line's list stays the kept files' bare names, for a reader of the
        // trail.
        var keptOfWhatItHeld = new List<string>();
        var keptOfWhatItHoldsNow = new List<string>();
        var namesOfTheKept = new List<string>();
        var pathsOfTheStep = new List<string>();
        foreach (UndoOp op in step.Ops)
        {
            if (op.Path is { } path && !pathsOfTheStep.Contains(path)) pathsOfTheStep.Add(path);
        }
        foreach (string path in pathsOfTheStep)
        {
            if (!UndoPlaces.StaysInside(root, path)) continue;
            int slash = path.LastIndexOf('/');
            foreach (string full in UndoRecovery.KeptOriginalFiles(step, FullPath(root, path)))
            {
                string name = Path.GetFileName(full);
                string kept = slash < 0 ? name : path[..(slash + 1)] + name;
                if (AlreadyListed(keptOfWhatItHeld, kept) || AlreadyListed(keptOfWhatItHoldsNow, kept)) continue;
                if (notTaken.OutgoingOf.Contains(path) && UndoSwap.IsStaged(name, label)) keptOfWhatItHeld.Add(kept);
                else if (UndoSwap.HoldsAnyOf(notTaken.KeptOriginalsHolding, full)) keptOfWhatItHoldsNow.Add(kept);
                else continue;
                namesOfTheKept.Add(name);
                UndoSwap.HideAKeptFileLeft(full);
            }
        }
        // Page by page: "from what was kept beside it" only of a page a use
        // names, by its path in the working folder (the mac's U4b2-4).
        var putBackFromAKeptOriginal = new List<string>();
        foreach (UndoKeptOriginalUse use in uses)
        {
            if (!putBackFromAKeptOriginal.Contains(use.Path)) putBackFromAKeptOriginal.Add(use.Path);
        }
        _trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoKeptWhatItReplaced, step.Course, step.Section,
                                         UndoTrail.KeptWhatItReplacedWords(backward, keptOfWhatItHeld, keptOfWhatItHoldsNow,
                                                                           step.Course, putBackFromAKeptOriginal, pathsOfTheStep),
                                         namesOfTheKept));
    }

    /// <summary>A kept file is skipped only when its whole path is listed already, compared as the line compares (<see cref="UndoTrail.SameSpelling"/>).</summary>
    private static bool AlreadyListed(List<string> listed, string kept)
    {
        foreach (string other in listed)
        {
            if (UndoTrail.SameSpelling(other, kept)) return true;
        }
        return false;
    }

    /// <summary>
    /// The one clearing at the flip (U7 / W11a calls it once, at the first
    /// launch with the switch on): every step recorded in shadow leaves the
    /// list (<c>rule.shadow</c>, reason <c>wentLive</c>). Writes nothing when
    /// nothing is on the list. True when it cleared.
    /// </summary>
    internal bool ClearTheListAsTheSwitchGoesLive() => _journal.WithLock(writer =>
    {
        if (!writer.Folded.OnTheList.Any()) return false;
        writer.Append(new JsonObject { ["seq"] = writer.Folded.Highest, ["event"] = "cleared", ["reason"] = "wentLive" });
        RecoverThenPrune(writer);
        return true;
    });

    /// <summary>
    /// Recovery as the app asks for it (at every launch since W4, through
    /// <see cref="UndoAtLaunch.Recover"/>, the switch on or off; the mac's
    /// <c>recoverAndRederive</c>): under the lock, every put-back tried at
    /// once, then, with the lock released, every file the settled steps keep
    /// true by a rule re-derived. Never fails the caller.
    /// </summary>
    internal UndoRecoveryRun Recover()
    {
        UndoRecoveryRun run;
        try
        {
            run = _journal.WithLock(writer => UndoRecovery.Run(writer, _journal, _mode, trySwapsNow: true, leavingStepsThatRederive: false,
                                                                _maintainers, _trail, _seams, _places), inShadow: !Live);
        }
        catch (Exception error) when (error is UndoJournalException or IOException or UnauthorizedAccessException)
        {
            // Never fails the caller, and says why it did not run, so the
            // window's startup log can (W4's review, LOW 2).
            return new UndoRecoveryRun([], StoppedByATest: false, NotRun: $"{error.GetType().Name}: {error.Message}");
        }
        if (!run.StoppedByATest) RederiveWhatRecoverySettled(run);
        return run;
    }

    /// <summary>
    /// The only way the door prunes: recovery on the ordinary path's
    /// schedule, then pruning, in the caller's hold (W2b's review, LOW 7;
    /// <see cref="UndoJournal.Prune"/> refuses a hold where recovery has not
    /// run). It leaves a step that keeps a file true for a recovery that
    /// re-derives, as every hold without a re-derivation after it must.
    /// </summary>
    internal void RecoverThenPrune(UndoJournalWriter writer)
    {
        UndoRecovery.Run(writer, _journal, _mode, trySwapsNow: false, leavingStepsThatRederive: true, _maintainers, _trail, _seams, _places);
        _journal.Prune(writer, _trail);
    }

    /// <summary>The files every step recovery settled keeps true by a rule, re-derived (outside the lock), whichever way it settled; never in shadow.</summary>
    private void RederiveWhatRecoverySettled(UndoRecoveryRun run)
    {
        if (!Live || _maintainers is null) return;
        foreach (UndoRecoveryResult result in run.Settled)
        {
            if (result.Outcome == UndoRecoveryOutcome.LeftAlone) continue;
            Rederive(result.Step.Ops, result.Root);
        }
    }

    /// <summary>
    /// A step this process leaves in flight and will not finish (a reversal
    /// that did not go in, a closing that could not be written or kept):
    /// noted in the process's memory, so recovery settles it by content at
    /// the next lock although this process is alive. Keyed by what the door
    /// itself knows (the list, the number, where its work stands, this
    /// process), never by a reading of the list: a reading taken outside the
    /// lock may be stale and not hold the step at all (W3's review, LOW 3),
    /// and the moments this is called are the ones the list could not be read.
    /// </summary>
    private void Abandon(long seq, UndoStepState working) =>
        _journal.Memory.NoteAbandoned(UndoRecovery.AbandonedKeyOf(_journal, seq, working, OwnPid));

    /// <summary>This process's id as its lines name it.</summary>
    private long OwnPid => _process["pid"] is JsonValue value && long.TryParse(value.ToJsonString(), out long pid) ? pid : Environment.ProcessId;

    /// <summary>Where a step's work stands while this door is doing it, from the closing it would write.</summary>
    private static UndoStepState WorkingStateOf(string closing, string? phase) => (closing, phase) switch
    {
        ("undone", _) or ("failed", "undoing") => UndoStepState.Undoing,
        ("redone", _) or ("failed", "redoing") => UndoStepState.Redoing,
        _ => UndoStepState.Begun,
    };

    /// <summary>A write the plain door must refuse: a gone process's step that keeps a file true waits for a recovery that re-derives.</summary>
    private sealed class AnotherChangeIsUnderWayException() : Exception("Another change is under way.");

    /// <summary>A blob the step names as held was pruned before its begin.</summary>
    private sealed class BlobGoneException() : Exception("A blob the step names is no longer held.");

    // ---- The phases -----------------------------------------------------------------

    /// <summary>
    /// Phase one, ONE hold: the folder's identifier, the blobs, the next number,
    /// the begin line, made durable. Never prunes (W2a's review, LOW 2): see
    /// the class's remarks.
    /// </summary>
    private long Begin(JsonObject header, string? workingFolder, JsonArray ops, IReadOnlyList<byte[]> blobs, string? course,
                       IReadOnlyList<string>? mustBeHeld = null)
    {
        // A step none of whose ops names a path (an external op alone) has no
        // working folder, and names none.
        JsonObject? folder = null;
        if (workingFolder is not null)
        {
            string identity = new FolderIdentityFile(Path.Combine(workingFolder, "courses", ".internal", "folder-id"), _journal.Clock).ReadOrMake()
                ?? throw new UndoJournalException(UndoJournalFailure.CouldNotWrite, "The working folder's identifier could not be read or made.");
            folder = new JsonObject { ["id"] = identity, ["pathAtTheTime"] = workingFolder };
        }
        return _journal.WithLock(writer =>
        {
            // Recovery first, before the number is taken, on the ordinary
            // path's schedule; a plain write never lands over a page a gone
            // process's front-page step left part way.
            UndoRecovery.Run(writer, _journal, _mode, trySwapsNow: false, leavingStepsThatRederive: true, _maintainers, _trail, _seams, _places);
            if (Live && UndoRecovery.DeadStepThatKeepsAFileTrue(writer, _journal, course) is not null)
                throw new AnotherChangeIsUnderWayException();
            if (mustBeHeld is not null)
            {
                foreach (string name in mustBeHeld)
                {
                    if (_journal.Blob(name) is null) throw new BlobGoneException();
                }
            }
            if (blobs.Count > 0) writer.WriteBlobs(blobs, BlobParallelism);
            long seq = writer.Folded.NextSeq;
            writer.Append(BeginLine(seq, header, folder, ops));
            writer.Sync();
            return seq;
        }, inShadow: !Live);
    }

    /// <summary>Phases two and three of making a step: the swap outside the lock, then <c>applied</c> or <c>failed</c>.</summary>
    private UndoOutcome MakeTheStep(long seq, IReadOnlyList<UndoSwapTarget> targets, string root, IEnumerable<JsonNode?> opsJson,
                                    bool alreadyAskedAfterBegin = false) =>
        MakeTheStep(seq, targets, root, OpsOf(opsJson), alreadyAskedAfterBegin);

    /// <summary>The ops of a step as this version reads them.</summary>
    private static List<UndoOp> OpsOf(IEnumerable<JsonNode?> opsJson)
    {
        var ops = new List<UndoOp>();
        foreach (JsonNode? node in opsJson)
        {
            if (node is JsonObject op) ops.Add(UndoLineOps.Read(op));
        }
        return ops;
    }

    private UndoOutcome MakeTheStep(long seq, IReadOnlyList<UndoSwapTarget> targets, string root, IReadOnlyList<UndoOp> ops,
                                    bool alreadyAskedAfterBegin)
    {
        if (!alreadyAskedAfterBegin && Stops("afterBegin")) return new UndoOutcome(UndoOutcomeKind.StoppedByATest);
        switch (UndoSwap.Swap(targets, $"{seq}-apply", RootOrNull(root), _seams, _places))
        {
            case UndoSwapResult.StoppedByATest:
                return new UndoOutcome(UndoOutcomeKind.StoppedByATest);
            case UndoSwapResult.Refused { LeftPartWay: true } partWay:
                // Half applied: left in flight for recovery, never failed (LOW 1).
                Abandon(seq, UndoStepState.Begun);
                return new UndoOutcome(UndoOutcomeKind.Refused, seq, partWay.Refusal) { LeftPartWay = true };
            case UndoSwapResult.Refused refused:
                Finish(seq, "failed", "begin", "refused");
                return new UndoOutcome(UndoOutcomeKind.Refused, seq, refused.Refusal);
        }
        if (Stops("beforeApplied")) return new UndoOutcome(UndoOutcomeKind.StoppedByATest);
        Finish(seq, "applied", null, null);
        Rederive(ops, root);
        return new UndoOutcome(UndoOutcomeKind.Applied, seq);
    }

    /// <summary>
    /// Phase three: the closing event, then pruning, in one hold (an <c>applied</c>
    /// drops the redo branch at that moment). When the lock cannot be had in ten
    /// seconds the closing is kept by the process and written first at its next
    /// hold, so the step is not left in flight for the life of the process.
    /// </summary>
    private void Finish(long seq, string name, string? phase, string? reason)
    {
        var line = new JsonObject { ["seq"] = seq, ["event"] = name };
        if (phase is not null) line["phase"] = phase;
        if (reason is not null) line["reason"] = reason;
        try { _journal.WriteClosingOrKeep(line, Live ? _finishWait : UndoJournal.ShadowWait, inShadow: !Live, thenInTheSameHold: RecoverThenPrune); }
        catch (Exception error) when (IsAFailureOfTheList(error))
        {
            // Not written and not kept (the list could not be read inside the
            // lock): the step stays in flight, given up by this process, so
            // recovery settles it by content at a later lock.
            Abandon(seq, WorkingStateOf(name, phase));
        }
    }

    /// <summary>
    /// What a refusal that can never succeed does to the list: the page was
    /// changed by hand, or content the step needs is missing. An Undo clears it
    /// (rulings 13 and 22), a Redo drops only the redo branch (ruling 20). True
    /// when it cleared.
    /// </summary>
    private bool AnswerARefusal(UndoRefusal refusal, long seq, bool backward)
    {
        string reason;
        switch (refusal.Kind)
        {
            case UndoRefusalKind.ChangedSince: reason = "changedSince"; break;
            case UndoRefusalKind.ContentMissing:
                // Ruling 22, behind its one field: an Undo clears; a Redo drops its branch either way.
                if (backward && !UndoSwitch.UndoRefusedForMissingContentClearsTheList) return false;
                reason = "contentMissing";
                break;
            default: return false;
        }
        try
        {
            if (backward)
            {
                return _journal.WithLock(writer =>
                {
                    if (_journal.Offer(writer.Folded).Head?.Seq != seq) return false;
                    writer.Append(new JsonObject { ["seq"] = writer.Folded.Highest, ["event"] = "cleared", ["reason"] = reason });
                    RecoverThenPrune(writer);
                    return true;
                });
            }
            _journal.WithLock(writer =>
            {
                if (_journal.Offer(writer.Folded).Redo.Seq != seq) return;
                var undone = writer.Folded.Steps.Values.Where(step => step.State == UndoStepState.Undone && step.Seq >= seq)
                                                       .Select(step => step.Seq).ToList();
                foreach (long number in undone)
                    writer.Append(new JsonObject { ["seq"] = number, ["event"] = "dropped", ["reason"] = "redoRefused" });
            });
        }
        catch (Exception error) when (error is UndoJournalException or IOException or UnauthorizedAccessException) { }
        return false;
    }

    // ---- Helpers ----------------------------------------------------------------------

    private bool CanRederive(UndoOp op) => op.Maintainer is { } maintainer && _maintainers?.CanRun(maintainer) == true;

    /// <remarks>
    /// Runs AFTER the swap, so whatever it throws must never reach a caller
    /// as a failure before the swap: the step's pages are in, and a caller
    /// that read it as "nothing was changed" would say so of a disk where
    /// every page was written (W7a review 1, MEDIUM 4). A re-derivation that
    /// throws leaves its file as it was, as one that returns false does.
    /// </remarks>
    private void Rederive(IEnumerable<UndoOp> ops, string root)
    {
        foreach (UndoOp op in ops)
        {
            if (op.Kind != UndoOp.Recompute || _maintainers is null) continue;
            try { _maintainers.Rederive(op, root); }
            catch (Exception) { }
        }
    }

    /// <summary>The step's working folder where it can be reached (its folder there with the step's identifier), else null: greyed (ruling 10).</summary>
    private string? RootOf(UndoStep step) => UndoRecovery.RootOf(step, _journal);

    /// <summary>The root a swap checks containment against: none for a step with no working folder (an external op alone).</summary>
    private static string? RootOrNull(string root) => root.Length == 0 ? null : root;

    /// <summary>
    /// The swap's targets in the plan's order: a move that carries edits first
    /// going forward (<see cref="UndoCheck.PlanResult.Ready.Leading"/>), then
    /// every file in the order the check met it, a carried one staged only at
    /// its turn, then the other whole ops (#899 W8-2). A step with a
    /// handed-over place goes in the order of the ops each target comes from
    /// instead, so every filler goes in after its leaver, and going back
    /// every leaver's taking-back after its filler's
    /// (<see cref="UndoCheck.PlanResult.Ready.InTheStepsOrder"/>; #899 W8b-21a1, 21a2).
    /// </summary>
    internal static List<UndoSwapTarget> TargetsOf(UndoCheck.PlanResult.Ready ready, string root)
    {
        var files = new List<UndoSwapTarget>();
        foreach ((string path, byte[]? expected, byte[]? replacement) in ready.InOrder)
        {
            files.Add(new UndoSwapTarget(FullPath(root, path), path, expected, replacement)
            {
                StagesAtItsTurn = ready.StagedAtItsTurn.Contains(path),
                HandedOver = ready.HandedOver.Contains(path),
            });
        }
        if (ready.InTheStepsOrder)
            return UndoCheck.TargetsInTheStepsOrder([ready.Leading, files, ready.Whole], [ready.LeadingOps, ready.InOrderOps, ready.WholeOps]);
        var targets = new List<UndoSwapTarget>(ready.Leading);
        targets.AddRange(files);
        targets.AddRange(ready.Whole);
        return targets;
    }

    internal static UndoRefusal RefusalOf(UndoCheck.PlanResult plan) => plan switch
    {
        UndoCheck.PlanResult.ChangedSince changed => new UndoRefusal(UndoRefusalKind.ChangedSince, changed.First, changed.Others),
        UndoCheck.PlanResult.ContentMissing missing => new UndoRefusal(UndoRefusalKind.ContentMissing, missing.Path),
        UndoCheck.PlanResult.FileIsInUse inUse => new UndoRefusal(UndoRefusalKind.FileIsInUse, inUse.Path),
        UndoCheck.PlanResult.CannotTellNow cannotTell => new UndoRefusal(UndoRefusalKind.CannotTellNow, cannotTell.Path),
        UndoCheck.PlanResult.FolderCannotBeReached gone => new UndoRefusal(UndoRefusalKind.CannotTellNow, gone.Path),
        _ => new UndoRefusal(UndoRefusalKind.NotReadable),
    };

    internal static string FullPath(string root, string relative) => Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar));

    private static bool SameBytes(byte[]? a, byte[]? b) => a is null ? b is null : b is not null && a.AsSpan().SequenceEqual(b);

    private JsonObject Header(string actionKey, IReadOnlyDictionary<string, string> arguments, string madeBy,
                              string? course, long? section, string? @class, string? holds)
    {
        var argumentsJson = new JsonObject();
        foreach ((string key, string value) in arguments.OrderBy(pair => pair.Key, StringComparer.Ordinal)) argumentsJson[key] = value;
        var header = new JsonObject
        {
            ["madeBy"] = madeBy,
            ["action"] = new JsonObject { ["key"] = actionKey, ["arguments"] = argumentsJson },
        };
        if (course is not null) header["course"] = course;
        if (section is not null) header["section"] = section;
        if (@class is not null) header["class"] = @class;
        if (holds is not null) header["holds"] = holds;
        return header;
    }

    private JsonObject BeginLine(long seq, JsonObject header, JsonObject? workingFolder, JsonArray ops)
    {
        var step = (JsonObject)header.DeepClone();
        step["seq"] = seq;
        step["madeAt"] = UndoMoment.Format(_journal.Now);
        if (workingFolder is not null) step["workingFolder"] = workingFolder.DeepClone();
        step["ops"] = ops.DeepClone();
        return new JsonObject { ["seq"] = seq, ["event"] = "begin", ["step"] = step, ["process"] = _process.DeepClone() };
    }

    private JsonObject Stamped(JsonObject line)
    {
        var stamped = (JsonObject)line.DeepClone();
        stamped["v"] = 1;
        stamped["at"] = UndoMoment.Format(_journal.Now);
        return stamped;
    }
}

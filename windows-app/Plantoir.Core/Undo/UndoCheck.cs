using System.Security.Cryptography;
using System.Text;

namespace Plantoir.Core.Undo;

/// <summary>
/// One page a check puts back from a kept original (<see cref="UndoCheck.Plan"/>'s
/// <c>keptOriginalUsed</c>; the mac's <c>UndoKeptOriginalUse</c>): the content
/// taken from it, the hash the other direction wants there (null: no file),
/// and what the page holds at that op, which the swap sets aside.
/// </summary>
internal sealed record UndoKeptOriginalUse(string Path, byte[] Kept, string? OtherSha, UndoCurrent Outgoing);

/// <summary>
/// What a put-back from kept originals could not write back into the list
/// (<see cref="UndoRecovery.StoreWhatKeptOriginalsGive"/>): the pages whose
/// outgoing content the list did not take (the swap keeps it beside them), and
/// the hashes of kept originals' bytes it did not take (no tidy removes a kept
/// original holding one; the second review of U3c, MEDIUM).
/// </summary>
internal sealed record UndoWhatTheListCouldNotTake(IReadOnlySet<string> OutgoingOf, IReadOnlySet<string> KeptOriginalsHolding)
{
    internal static readonly UndoWhatTheListCouldNotTake Nothing = new(new HashSet<string>(), new HashSet<string>());

    /// <summary>Whether the list took everything.</summary>
    internal bool IsEmpty => OutgoingOf.Count == 0 && KeptOriginalsHolding.Count == 0;
}

/// <summary>
/// What is at an op's path now, as the check sees it (#899, W1).
///
/// <para><see cref="CannotReadNow"/> is Windows' own case and the reason this
/// type exists rather than a nullable byte array. A page another program holds
/// with no read sharing (<c>FileShare.None</c>), a cloud file that is not
/// available offline, a network share that dropped: the read FAILS, and the
/// page has not been changed by anyone. Reading that failure as "changed since"
/// would make ruling 13 clear the WHOLE list for a file that was merely busy.
/// So it is refused, the file named, nothing on the list changed, to be
/// tried again, in one of two ways (<see cref="UndoCheck.StateOf"/>). A
/// sharing or lock violation (32, 33: another program has it open) ends the
/// way the contract's <c>fileIsInUse</c> ends (<c>stepCases</c>,
/// <c>rule.recovery</c>'s "a file is in use", the everyday case on Windows);
/// the contract has no check case for it, and the proposed cases are the plan
/// review's D1, amended. Every other failed read (access denied, a cloud file
/// not downloaded yet, a network share that dropped, a disk error) is the
/// contract's <c>cannotTell</c> (<c>checkCasesHow</c>, the director's ruling on
/// U2b's review, 2026-11-19, confirmed by Russell: "a teacher file Undo cannot
/// read at check time" is refused <c>cannotTellNow</c>, the list kept).</para>
/// </summary>
internal abstract record UndoCurrent
{
    private UndoCurrent() { }

    internal sealed record Absent : UndoCurrent;
    internal sealed record Folder : UndoCurrent;
    internal sealed record Bytes(byte[] Content) : UndoCurrent;
    internal sealed record CannotReadNow(int ErrorCode) : UndoCurrent;

    /// <summary>
    /// Reads what is at this path, asking only to READ and sharing everything
    /// (<c>FileShare.ReadWrite | FileShare.Delete</c>), so a check never stands
    /// in the way of the teacher's editor or of another process's swap. It
    /// never asks for write or delete access: a probe that did would call
    /// every page Obsidian has open "cannot read now" (the plan review's M2,
    /// measured: a <c>FileShare.ReadWrite</c> holder does not stop a read).
    /// </summary>
    /// <param name="open">A seam for tests (a cloud or network failure); the real open by default.</param>
    internal static UndoCurrent Read(string fullPath, Func<string, Stream>? open = null)
    {
        if (Directory.Exists(fullPath)) return new Folder();
        try
        {
            using Stream stream = open is null
                ? new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)
                : open(fullPath);
            using var memory = new MemoryStream();
            stream.CopyTo(memory);
            return new Bytes(memory.ToArray());
        }
        catch (FileNotFoundException) { return new Absent(); }
        catch (DirectoryNotFoundException) { return new Absent(); }
        catch (UnauthorizedAccessException exception)
        {
            // A folder that appeared between the two looks, or an access
            // denial: neither is a change by hand.
            if (Directory.Exists(fullPath)) return new Folder();
            return new CannotReadNow(exception.HResult & 0xFFFF);
        }
        catch (IOException exception)
        {
            // A sharing or lock violation (32, 33), a cloud file not available
            // offline (the 362 to 400 range), a network error: the page is
            // there and has not been read, which is not the same as changed.
            if (!File.Exists(fullPath) && !Directory.Exists(fullPath) && IsNotFound(exception)) return new Absent();
            return new CannotReadNow(exception.HResult & 0xFFFF);
        }
    }

    private static bool IsNotFound(IOException exception) => (exception.HResult & 0xFFFF) is 2 or 3;
}

/// <summary>Where one op's target stands against what the op recorded.</summary>
internal enum UndoOpState
{
    /// <summary>As the step found it (the op's before).</summary>
    Before,
    /// <summary>As the step left it (the op's after).</summary>
    After,
    /// <summary>Neither: changed since, by hand or by something else.</summary>
    Neither,
    /// <summary>Another program holds it with no read sharing (a sharing or lock violation, Windows): never "changed since".</summary>
    InUse,
    /// <summary>It is there and could not be read now for any other reason (access denied, a cloud file, a network or disk error): never "changed since" (<c>checkCasesHow</c>'s <c>cannotTell</c>).</summary>
    CannotTell,
    /// <summary>The op is not one this version can read: never acted on.</summary>
    NotReadable,
}

/// <summary>The contract's verdicts (<c>checkCasesHow</c>), plus the in-use refusal the contract already names.</summary>
internal enum UndoVerdict { CanUndo, AlreadyBack, CanRedo, AlreadyRedone, ChangedSince, CannotTell, NotReadable, FileIsInUse }

/// <summary>
/// "Has what this step changed been changed by hand since?", asked of what is
/// on the disk now and nothing else (#899 piece W1, <c>rule.contentNotTimes</c>).
///
/// <para>Content only, never a time: NTFS keeps an old creation time across a
/// replace within fifteen seconds and a copy keeps its modification time (the
/// Windows director's fact 6 on #899). An <c>editLine</c> entry is compared
/// byte for byte with carriage returns, comments and a byte-order mark kept,
/// after a STRICT UTF-8 decode (a page that is not UTF-8 is changed since for a
/// line op); a whole file by SHA-256 of its bytes. Never
/// <c>File.ReadAllText</c>: it drops a leading byte-order mark and replaces
/// invalid bytes with U+FFFD without a word, and either would make a changed
/// page read as unchanged.</para>
/// </summary>
internal static class UndoCheck
{
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    /// <summary>SHA-256 in lower-case hexadecimal, the journal's name for content.</summary>
    internal static string Sha(byte[] content) => Convert.ToHexStringLower(SHA256.HashData(content));

    /// <summary>Strict UTF-8, keeping a byte-order mark as U+FEFF; null when the bytes are not UTF-8.</summary>
    internal static string? DecodeStrictly(byte[] content)
    {
        try { return StrictUtf8.GetString(content); }
        catch (DecoderFallbackException) { return null; }
    }

    private const int SharingViolation = 32;
    private const int LockViolation = 33;

    internal static UndoOpState StateOf(UndoOp op, UndoCurrent current)
    {
        if (!op.Readable) return UndoOpState.NotReadable;
        if (current is UndoCurrent.CannotReadNow cannot)
            return cannot.ErrorCode is SharingViolation or LockViolation ? UndoOpState.InUse : UndoOpState.CannotTell;
        switch (op.Kind)
        {
            case UndoOp.Recompute:
                // No check (opKinds.recompute): re-derived after the other ops, never compared.
                return UndoOpState.After;

            case UndoOp.WriteFile:
            {
                if (current is UndoCurrent.Folder) return UndoOpState.Neither;
                string? sha = current is UndoCurrent.Bytes bytes ? Sha(bytes.Content) : null;
                if (string.Equals(sha, op.BeforeSha, StringComparison.Ordinal)) return UndoOpState.Before;
                if (string.Equals(sha, op.AfterSha, StringComparison.Ordinal)) return UndoOpState.After;
                return UndoOpState.Neither;
            }

            case UndoOp.EditLine:
            {
                // A line op never reads a missing page as already back, and a
                // folder or an undecodable page is changed since.
                if (current is not UndoCurrent.Bytes bytes) return UndoOpState.Neither;
                if (DecodeStrictly(bytes.Content) is not { } text) return UndoOpState.Neither;
                UndoEntries.Reading reading = UndoEntries.ReadingOf(op.Key!, text);
                if (reading.Matches(op.Before)) return UndoOpState.Before;
                if (reading.Matches(op.After)) return UndoOpState.After;
                return UndoOpState.Neither;
            }

            case UndoOp.ReplaceText:
                return UndoHunk.StateOf(op, current);

            case UndoOp.EditJson:
                return UndoJsonMember.StateOf(op, current);

            case UndoOp.Move or UndoOp.CreateTree or UndoOp.RemoveTree or UndoOp.External:
                // Judged on the disk as a whole (WholeStateOf), never by one file.
                return UndoOpState.Neither;

            default:
                return UndoOpState.NotReadable;
        }
    }

    /// <summary>
    /// Where a move, a tree or an external op stands now, each judged AS A
    /// WHOLE against what is there, on its own (<c>opKinds.wholeOps</c>; the
    /// mac's <c>UndoCheck.wholeState</c>). A move is judged as a PAIR, never
    /// by one place alone (#897 piece B, seam 1): its <c>from</c> free and
    /// its <c>to</c> holding the content is as the step left it; the other way
    /// round is as it was; anything else (both full, both free, either holding
    /// something else) is a change since, so an undo leaves BOTH where they
    /// are. <paramref name="cannotRead"/> is a test's seam (a full path that
    /// cannot be read just now).
    /// </summary>
    /// <param name="overridingTo">For a move that carries edits, going back: each carried file, relative to its <c>to</c>, as the step's own edit leaves it once taken back (the listing override; the mac's <c>overridingTo</c>, U4b; #899 W8-2), and the step's own staged and kept files inside it as absent (W8-3).</param>
    /// <param name="overridingFrom">For a move that carries edits: the step's own staged and kept files inside its <c>from</c>, as absent (the mac's <c>overridingFrom</c>, U4b's M1; #899 W8-3).</param>
    /// <param name="toIsHandedOver">For a file's or a link's move that FILLS a place an earlier change of the same plan leaves
    /// (a handed-over place, <see cref="UndoOp.Handovers"/>; #899 W8b-21a1, the mac's U4b3 door-1): its <c>to</c> is judged free,
    /// whatever stands there now, because the leaver is swapped out before it. A flag of its own, never an
    /// <paramref name="overridingTo"/> entry: those name paths inside a moved folder and what carried edits leave there, and an
    /// entry at "" would read as a carried edit's file at the move's own place.</param>
    /// <param name="fromIsHandedOver">Going back, for a file's or a link's move that LEFT a place a later op of the step fills
    /// (#899 W8b-21a2, the mac's U4b3 door-2): its <c>from</c> is judged free, whatever stands there now, when the filler's
    /// taking-back is a change of the same plan, because that is swapped out before the move comes back.</param>
    internal static UndoOpState WholeStateOf(UndoOp op, string root, IUndoExternalPlaces places, Func<string, bool>? cannotRead = null,
                                             IReadOnlyDictionary<string, UndoCurrent>? overridingTo = null,
                                             IReadOnlyDictionary<string, UndoCurrent>? overridingFrom = null,
                                             bool toIsHandedOver = false, bool fromIsHandedOver = false)
    {
        if (!op.Readable) return UndoOpState.NotReadable;
        switch (op.Kind)
        {
            case UndoOp.Move:
            {
                if (op.IsCaseOnlyMove && UndoMoveSides.SpellingListed(UndoTreeReading.Under(root, op.From!), UndoTreeReading.Under(root, op.To!), cannotRead) is { } spelled)
                {
                    // One item under two spellings (U4b; W8-5): judged by the
                    // spelling its folder lists, holding the content.
                    if (spelled == UndoCaseOnlySpelling.CannotRead) return UndoOpState.CannotTell;
                    if (spelled == UndoCaseOnlySpelling.Another) return UndoOpState.Neither;
                    UndoMoveSide side = spelled == UndoCaseOnlySpelling.To
                        ? UndoMoveSides.Read(op, UndoTreeReading.Under(root, op.To!), cannotRead, overridingTo)
                        : UndoMoveSides.Read(op, UndoTreeReading.Under(root, op.From!), cannotRead, overridingFrom);
                    if (side == UndoMoveSide.CannotRead) return UndoOpState.CannotTell;
                    if (side != UndoMoveSide.HoldsTheContent) return UndoOpState.Neither;
                    return spelled == UndoCaseOnlySpelling.To ? UndoOpState.After : UndoOpState.Before;
                }
                UndoMoveSide atFrom = fromIsHandedOver ? UndoMoveSide.Free : UndoMoveSides.Read(op, UndoTreeReading.Under(root, op.From!), cannotRead, overridingFrom);
                UndoMoveSide atTo = toIsHandedOver ? UndoMoveSide.Free : UndoMoveSides.Read(op, UndoTreeReading.Under(root, op.To!), cannotRead, overridingTo);
                if (atFrom == UndoMoveSide.CannotRead || atTo == UndoMoveSide.CannotRead) return UndoOpState.CannotTell;
                if (atFrom == UndoMoveSide.Free && atTo == UndoMoveSide.HoldsTheContent) return UndoOpState.After;
                if (atFrom == UndoMoveSide.HoldsTheContent && atTo == UndoMoveSide.Free) return UndoOpState.Before;
                return UndoOpState.Neither;
            }
            case UndoOp.CreateTree:
            case UndoOp.RemoveTree:
            {
                bool present;
                switch (UndoTreeReading.Read(UndoTreeReading.Under(root, op.Path!), cannotRead: cannotRead))
                {
                    case UndoTreeReading.Absent: present = false; break;
                    case UndoTreeReading.CannotRead: return UndoOpState.CannotTell;
                    case UndoTreeReading.Tree tree:
                        if (!string.Equals(tree.Listing.Sha, op.ListingSha, StringComparison.Ordinal)) return UndoOpState.Neither;
                        present = true;
                        break;
                    default: return UndoOpState.Neither;
                }
                if (op.Kind == UndoOp.CreateTree) return present ? UndoOpState.After : UndoOpState.Before;
                return present ? UndoOpState.Before : UndoOpState.After;
            }
            case UndoOp.External:
            {
                UndoExternalReading found = places.Read(op.Target!);
                if (found.Matches(op.ValueBefore)) return UndoOpState.Before;
                if (found.Matches(op.ValueAfter)) return UndoOpState.After;
                return UndoOpState.Neither;
            }
            default:
                return UndoOpState.Neither;
        }
    }

    internal static UndoVerdict UndoVerdictOf(UndoOpState state) => state switch
    {
        UndoOpState.After => UndoVerdict.CanUndo,
        UndoOpState.Before => UndoVerdict.AlreadyBack,
        UndoOpState.Neither => UndoVerdict.ChangedSince,
        UndoOpState.InUse => UndoVerdict.FileIsInUse,
        UndoOpState.CannotTell => UndoVerdict.CannotTell,
        _ => UndoVerdict.NotReadable,
    };

    internal static UndoVerdict RedoVerdictOf(UndoOpState state) => state switch
    {
        UndoOpState.Before => UndoVerdict.CanRedo,
        UndoOpState.After => UndoVerdict.AlreadyRedone,
        UndoOpState.Neither => UndoVerdict.ChangedSince,
        UndoOpState.InUse => UndoVerdict.FileIsInUse,
        UndoOpState.CannotTell => UndoVerdict.CannotTell,
        _ => UndoVerdict.NotReadable,
    };

    // ---- The whole step: all or nothing ----------------------------------

    /// <summary>What checking every op of a step comes to.</summary>
    internal abstract record PlanResult
    {
        private PlanResult() { }

        /// <summary>Every op can be moved: the new content of each file it touches (null: no file).</summary>
        internal sealed record Ready(IReadOnlyDictionary<string, byte[]?> Changes) : PlanResult
        {
            /// <summary>
            /// Going forward, each move that carries edits, swapped in BEFORE
            /// every file (<c>opKinds.wholeOps</c>' order: the edit is made after
            /// the move; the mac's <c>leadingTargets</c>, U4b; #899 W8-2).
            /// </summary>
            internal IReadOnlyList<UndoSwapTarget> Leading { get; init; } = [];

            /// <summary>The carried files (relative paths) staged only at their turn, once the move has made their folder (staging first would make the folder at <c>to</c>, and the move would be refused).</summary>
            internal IReadOnlySet<string> StagedAtItsTurn { get; init; } = new HashSet<string>(StringComparer.Ordinal);

            /// <summary>The whole ops' changes (a move, a tree made or taken out, an external target set), in the order the check met them, after every file's (<c>opKinds.external</c>: "after every file's content has been swapped in").</summary>
            internal IReadOnlyList<UndoSwapTarget> Whole { get; init; } = [];

            /// <summary>
            /// The same changes in the order the check MET their files (an undo
            /// meets its ops in reverse), each with what the file held when it
            /// was checked (null: no file): what the staged swap re-reads before
            /// each rename (W2b).
            /// </summary>
            internal IReadOnlyList<(string Path, byte[]? Expected, byte[]? Replacement)> InOrder { get; init; } = [];

            /// <summary>
            /// The step holds a handed-over place (<see cref="UndoOp.Handovers"/>; #899 W8b-21a1, the mac's U4b3
            /// door-1): its targets go in the order of the ops each comes from (<see cref="TargetsInTheStepsOrder"/>),
            /// so going forward every filler's change goes in after its leaver's, and going back, in the step's ops
            /// reversed, every leaver's taking-back after its filler's (W8b-21a2, door-2). False: today's order, exactly.
            /// </summary>
            internal bool InTheStepsOrder { get; init; }

            /// <summary>The op each of <see cref="Leading"/>, <see cref="InOrder"/> (a file at the first op naming it) and <see cref="Whole"/> comes from, by its place in this plan's order.</summary>
            internal IReadOnlyList<int> LeadingOps { get; init; } = [];
            internal IReadOnlyList<int> InOrderOps { get; init; } = [];
            internal IReadOnlyList<int> WholeOps { get; init; } = [];

            /// <summary>The files (relative paths) at a handed-over place whose other op is a link's move: judged before staging on the folders above them only (<see cref="UndoSwapTarget.HandedOver"/>).</summary>
            internal IReadOnlySet<string> HandedOver { get; init; } = new HashSet<string>(StringComparer.Ordinal);
        }

        /// <summary>Something it changed was changed since: the first met is named, with how many others.</summary>
        internal sealed record ChangedSince(string First, int Others) : PlanResult;

        /// <summary>Content it needs is not in the list's store.</summary>
        internal sealed record ContentMissing(string Path) : PlanResult;

        /// <summary>A file another program holds could not be read at the moment: refused, the list unchanged.</summary>
        internal sealed record FileIsInUse(string Path) : PlanResult;

        /// <summary>
        /// A file is there and could not be read now for another reason: the
        /// contract's refusal <c>cannotTellNow</c>, the list unchanged, to be
        /// tried again. Only content that was read and differs is changed since.
        /// </summary>
        internal sealed record CannotTellNow(string Path) : PlanResult;

        /// <summary>An op this version cannot read: never acted on.</summary>
        internal sealed record NotReadable : PlanResult;

        /// <summary>
        /// Every page in the way is simply not there, and the working folder
        /// cannot be reached now: a drive or share that went away, not a change
        /// by hand. Greyed (ruling 10), nothing cleared, to be tried again.
        /// </summary>
        internal sealed record FolderCannotBeReached(string Path) : PlanResult;
    }

    /// <summary>
    /// Checks EVERY op of a step before anything is written (ruling 4,
    /// <c>rule.stagedThenSwapped</c>), and works out what each file it touches
    /// becomes. Pure: it reads through <paramref name="read"/> and
    /// <paramref name="blob"/> and writes nothing.
    ///
    /// <para>An undo goes through the ops in reverse order, so the last op met
    /// first (<c>stepCases</c>: "an undo checks ops in reverse order"). A
    /// line op that cannot be placed is changed since, and a page found in the
    /// way is reported before content that is missing (U1's F2, which the mac
    /// fixes in U2 and Windows builds from the start). A read that fails at the
    /// moment is reported only when nothing is in the way: a page changed by
    /// hand settles the question whatever else is busy.</para>
    /// </summary>
    /// <param name="read">What is at an op's path now (relative path in, current out).</param>
    /// <param name="blob">A blob's bytes by name, or null when the store does not have it (or its bytes do not hash to its name).</param>
    /// <param name="folderIsReachable">Asked again when every page in the way is absent (the W1 review's M1); null: not asked.</param>
    /// <param name="whole">Where a whole op (a move, a tree, an external target) is read and changed: the working folder's
    /// root and the external places. Needed by a step that holds one (U2's kinds, W6); without it such a step is not readable here.
    /// With it, every place every op names is checked inside the working folder, links resolved, before anything is read through it.</param>
    /// <param name="keptOriginal">For a <c>writeFile</c> whose blob the list no longer holds: the step's own kept original beside
    /// that page whose bytes hash to exactly the sha wanted (page path and sha in), or null when none matches (the mac's U3c,
    /// Russell's ruling of 2026-11-20, 15:20; <see cref="UndoRecovery.KeptOriginal"/>).</param>
    /// <param name="keptOriginalUsed">Told of each page put back from a kept original, with what the page holds at that op.</param>
    /// <param name="ownSeq">The step's number for an Undo or a Redo (null while a step is made): a move that carries edits is
    /// judged without the step's own staged and kept files inside its folder, from any of its swaps, on either side (the mac's
    /// <c>ownSeq</c>, U4b's M1; #899 W8-3).</param>
    internal static PlanResult Plan(IReadOnlyList<UndoOp> ops, bool backward,
                                    Func<string, UndoCurrent> read, Func<string, byte[]?> blob,
                                    Func<bool>? folderIsReachable = null, UndoWholeReads? whole = null,
                                    Func<string, string, byte[]?>? keptOriginal = null, Action<UndoKeptOriginalUse>? keptOriginalUsed = null,
                                    long? ownSeq = null)
    {
        foreach (UndoOp op in ops)
        {
            if (!op.Readable) return new PlanResult.NotReadable();
        }

        var ordered = backward ? ops.Reverse().ToList() : ops.ToList();
        var original = new Dictionary<string, UndoCurrent>(StringComparer.Ordinal);
        var met = new List<string>();
        var working = new Dictionary<string, UndoCurrent>(StringComparer.Ordinal);
        var inTheWay = new List<string>();
        string? missing = null;
        string? inUse = null;
        string? cannotTell = null;

        var wholeChanges = new List<UndoSwapTarget>();
        // U4b (opKinds.wholeOps' order; #899 W8-2): each edit named inside a
        // move's new place, after the move in the step, is carried by it.
        // Going forward it is judged where its file is before the move and
        // made after it; going back it is taken back first, and the move is
        // judged as if it were (the mac's UndoCheck.plan).
        Dictionary<string, UndoOp> carriers = Carriers(ops);
        var movingNow = new HashSet<string>(StringComparer.Ordinal);
        var stagedAtItsTurn = new HashSet<string>(StringComparer.Ordinal);
        // Where each file was read: a carried file whose move goes in now is
        // where it is before the move, and its kept original beside it there.
        var readAt = new Dictionary<string, string>(StringComparer.Ordinal);
        var leading = new List<UndoSwapTarget>();
        // #899 W8b-21a1 (the mac's U4b3 door-1): each place an earlier op of
        // the step leaves and a later op fills. Empty for every step readable
        // today, so such a step is planned exactly as before.
        IReadOnlyList<UndoHandover> handovers = UndoOp.Handovers(ops);
        // The ops (by their place in the step) found already as wanted: no
        // change of this plan.
        var opsNotChanged = new HashSet<int>();
        // Each target's op, by its place in this plan's order, for the order
        // of a step with a handed-over place.
        var leadingOps = new List<int>();
        var wholeOps = new List<int>();
        var firstOpOnPath = new Dictionary<string, int>(StringComparer.Ordinal);
        var handedOverPaths = new HashSet<string>(StringComparer.Ordinal);
        int opIndex = -1;
        foreach (UndoOp op in ordered)
        {
            opIndex++;
            int stepIndex = backward ? ops.Count - 1 - opIndex : opIndex;
            // The handed-over place is judged FREE for the op that comes
            // second in this plan, when the op that comes first is a change
            // of this plan: going forward the filler, after its leaver
            // (W8b-21a1); going back the leaver, after its filler's
            // taking-back (W8b-21a2). Skipped as already done, the first op
            // leaves the place to be read from the disk as before.
            bool placeIsFree = false;
            bool inAHandoverWithALink = false;
            foreach (UndoHandover handover in handovers)
            {
                if (!backward && handover.FillerIndex == stepIndex && !opsNotChanged.Contains(handover.LeaverIndex)) placeIsFree = true;
                if (backward && handover.LeaverIndex == stepIndex && !opsNotChanged.Contains(handover.FillerIndex)) placeIsFree = true;
                if (handover.ALinkMoves && !op.IsWhole && (handover.FillerIndex == stepIndex || handover.LeaverIndex == stepIndex)) inAHandoverWithALink = true;
            }
            if (op.Kind == UndoOp.Recompute) continue;   // re-derived after, never checked
            // Every place it names still inside the working folder, links
            // resolved: a folder on its path replaced by a junction to outside
            // since the step was made is a change since, judged before
            // anything is read through it (the mac's second hard review of
            // U2b, MEDIUM 2).
            // The place named is the first that leads out, never the other
            // side of a move (U4b2-2; #899 W8-1).
            // A file op at a place a link leaves or fills is judged on the
            // folders above it: the link standing there is leaving or
            // arriving, never written through (W8b-21a1).
            if (whole is { Root.Length: > 0 } && UndoPlaces.FirstPlaceLeadingOut(whole.Root, op, judgedOnTheFoldersAbove: inAHandoverWithALink) is { } leadingOut)
            {
                if (!inTheWay.Contains(leadingOut, StringComparer.Ordinal)) inTheWay.Add(leadingOut);
                continue;
            }
            if (op.IsWhole)
            {
                if (whole is null) return new PlanResult.NotReadable();
                bool carriesEdits = false;
                Dictionary<string, UndoCurrent>? overridingTo = null;
                foreach ((string carried, UndoOp carrier) in carriers)
                {
                    if (!ReferenceEquals(carrier, op)) continue;
                    carriesEdits = true;
                    // Going back, the move is judged with each carried file as
                    // the edit's other side, taken back already (the listing
                    // override), matched by the one comparison.
                    if (backward && working.TryGetValue(carried, out UndoCurrent? takenBack) && UndoOp.PartInside(op.To!, carried) is { } inside)
                        (overridingTo ??= new Dictionary<string, UndoCurrent>(StringComparer.Ordinal))[inside] = takenBack;
                }
                // The step's own staged and kept files inside the folder, from
                // any of its swaps, on either side, are never its content (U4b,
                // M1); a carried file's override above wins over its own.
                // Only for a move that carries edits, as the mac's plan does:
                // the swap's last look leaves them out for every move, which
                // is the looser of the two, and so never lets through what the
                // plan refused (the day26-3 sweep's LOW 4: keep them apart).
                Dictionary<string, UndoCurrent>? overridingFrom = null;
                if (carriesEdits && ownSeq is { } seq)
                {
                    overridingFrom = UndoSwap.StepsOwnFilesInside(UndoTreeReading.Under(whole.Root, op.From!), seq);
                    foreach ((string inside, UndoCurrent absent) in UndoSwap.StepsOwnFilesInside(UndoTreeReading.Under(whole.Root, op.To!), seq))
                        (overridingTo ??= new Dictionary<string, UndoCurrent>(StringComparer.Ordinal)).TryAdd(inside, absent);
                }
                // A capitalisation-only move's two spellings are one place:
                // one set of overrides serves whichever spelling is listed
                // (the mac's U4b; W8-5).
                if (op.IsCaseOnlyMove && (overridingTo is not null || overridingFrom is not null))
                {
                    var both = new Dictionary<string, UndoCurrent>(overridingTo ?? new Dictionary<string, UndoCurrent>(), StringComparer.Ordinal);
                    foreach ((string inside, UndoCurrent item) in overridingFrom ?? new Dictionary<string, UndoCurrent>()) both.TryAdd(inside, item);
                    overridingTo = both;
                    overridingFrom = both;
                }
                UndoOpState wholeState = WholeStateOf(op, whole.Root, whole.Places, whole.CannotRead, overridingTo, overridingFrom,
                                                      toIsHandedOver: placeIsFree && !backward, fromIsHandedOver: placeIsFree && backward);
                UndoVerdict verdict = backward ? UndoVerdictOf(wholeState) : RedoVerdictOf(wholeState);
                if (verdict is UndoVerdict.AlreadyBack or UndoVerdict.AlreadyRedone)
                {
                    opsNotChanged.Add(stepIndex);
                    continue;
                }
                // A moved item is named where a teacher finds it now: its to
                // before an Undo, its from before a Redo (placeAsFound).
                if (verdict == UndoVerdict.CannotTell) { cannotTell ??= op.PlaceAsFound(backward); continue; }
                if (verdict == UndoVerdict.ChangedSince)
                {
                    string found = op.PlaceAsFound(backward);
                    if (!inTheWay.Contains(found, StringComparer.Ordinal)) inTheWay.Add(found);
                    continue;
                }
                if (WholeTarget(op, backward, whole.Root, blob) is not { } target) { missing ??= op.PlaceName; continue; }
                if (carriesEdits && !backward)
                {
                    movingNow.Add(op.To!);
                    leading.Add(target);
                    leadingOps.Add(opIndex);
                    continue;
                }
                wholeChanges.Add(target);
                wholeOps.Add(opIndex);
                continue;
            }
            string path = op.Path!;
            if (!original.ContainsKey(path))
            {
                // A carried file whose move goes in now is read where it is
                // before the move, and staged only at its turn.
                string readPath = path;
                if (carriers.TryGetValue(path, out UndoOp? carrying) && movingNow.Contains(carrying.To!))
                {
                    readPath = UndoOp.PlaceBeforeTheMove(path, carrying.From!, carrying.To!);
                    stagedAtItsTurn.Add(path);
                }
                readAt[path] = readPath;
                // A new file going forward, or a removal taken back, at a
                // place this plan frees first: absent, never read through the
                // link still standing there (W8b-21a1, W8b-21a2).
                original[path] = placeIsFree ? new UndoCurrent.Absent() : read(readPath);
                working[path] = original[path];
                met.Add(path);
                firstOpOnPath[path] = opIndex;
            }
            if (inAHandoverWithALink) handedOverPaths.Add(path);
            UndoOpState state = StateOf(op, working[path]);
            if (state == UndoOpState.InUse) { inUse ??= path; continue; }
            if (state == UndoOpState.CannotTell) { cannotTell ??= path; continue; }
            if (state == UndoOpState.Neither)
            {
                if (!inTheWay.Contains(path, StringComparer.Ordinal)) inTheWay.Add(path);
                continue;
            }
            UndoOpState wantedFrom = backward ? UndoOpState.After : UndoOpState.Before;
            if (state != wantedFrom)
            {
                opsNotChanged.Add(stepIndex);   // already where this move takes it
                continue;
            }

            if (op.Kind == UndoOp.WriteFile)
            {
                string? targetSha = backward ? op.BeforeSha : op.AfterSha;
                if (targetSha is null) { working[path] = new UndoCurrent.Absent(); continue; }
                byte[]? content = blob(targetSha);
                if (content is null || !string.Equals(Sha(content), targetSha, StringComparison.Ordinal))
                {
                    // A blob the list no longer holds: put back from the kept
                    // original beside the page when its hash is the one wanted.
                    if (keptOriginal?.Invoke(readAt[path], targetSha) is { } kept)
                    {
                        keptOriginalUsed?.Invoke(new UndoKeptOriginalUse(path, kept, backward ? op.AfterSha : op.BeforeSha, working[path]));
                        working[path] = new UndoCurrent.Bytes(kept);
                        continue;
                    }
                    // None matches. The check goes on, so every page in the way is reported first.
                    missing ??= path;
                    continue;
                }
                working[path] = new UndoCurrent.Bytes(content);
            }
            else if (op.Kind is UndoOp.ReplaceText or UndoOp.EditJson)
            {
                // As the step left it, yet it cannot be placed exactly (a hunk
                // found twice, a member that cannot be put back byte for
                // byte): changed by hand since, never content missing.
                byte[] bytes = ((UndoCurrent.Bytes)working[path]).Content;
                byte[]? moved = op.Kind == UndoOp.ReplaceText ? UndoHunk.Moved(op, bytes, backward) : UndoJsonMember.Moved(op, bytes, backward);
                if (moved is null)
                {
                    if (!inTheWay.Contains(path, StringComparer.Ordinal)) inTheWay.Add(path);
                    continue;
                }
                working[path] = new UndoCurrent.Bytes(moved);
            }
            else
            {
                string text = DecodeStrictly(((UndoCurrent.Bytes)working[path]).Content)!;
                string? source = backward ? op.After : op.Before;
                string? target = backward ? op.Before : op.After;
                if (UndoEntries.Move(op, source, target, text) is not { } moved)
                {
                    if (!inTheWay.Contains(path, StringComparer.Ordinal)) inTheWay.Add(path);
                    continue;
                }
                working[path] = new UndoCurrent.Bytes(StrictUtf8.GetBytes(moved));
            }
        }

        if (inTheWay.Count > 0)
        {
            // A page that is simply not there while the folder cannot be
            // reached is a drive or share gone between the reach check and
            // the plan, not a change by hand: asked again before ruling 13
            // clears the whole list for it (the W1 review's M1).
            bool everyOneIsGone = true;
            foreach (string path in inTheWay)
            {
                if (original.TryGetValue(path, out UndoCurrent? was) && was is not UndoCurrent.Absent) everyOneIsGone = false;
            }
            foreach (string path in inTheWay)
            {
                if (!original.ContainsKey(path)) everyOneIsGone = false;   // a whole op's place, or one leading outside
            }
            if (everyOneIsGone && folderIsReachable is not null && !folderIsReachable())
                return new PlanResult.FolderCannotBeReached(inTheWay[0]);
            return new PlanResult.ChangedSince(inTheWay[0], inTheWay.Count - 1);
        }
        // In the mac's order (UndoCheck.plan): a page in the way, then a
        // page that cannot be read now, then content the list no longer holds.
        if (cannotTell is not null) return new PlanResult.CannotTellNow(cannotTell);
        if (missing is not null) return new PlanResult.ContentMissing(missing);
        if (inUse is not null) return new PlanResult.FileIsInUse(inUse);

        var changes = new Dictionary<string, byte[]?>(StringComparer.Ordinal);
        var inOrder = new List<(string, byte[]?, byte[]?)>();
        var inOrderOps = new List<int>();
        foreach (string path in met)
        {
            UndoCurrent was = original[path];
            UndoCurrent now = working[path];
            if (SameContent(was, now)) continue;
            byte[]? replacement = now is UndoCurrent.Bytes bytes ? bytes.Content : null;
            changes[path] = replacement;
            inOrder.Add((path, was is UndoCurrent.Bytes before ? before.Content : null, replacement));
            inOrderOps.Add(firstOpOnPath[path]);
        }
        return new PlanResult.Ready(changes)
        {
            InOrder = inOrder, Whole = wholeChanges, Leading = leading, StagedAtItsTurn = stagedAtItsTurn,
            InTheStepsOrder = handovers.Count > 0, LeadingOps = leadingOps, InOrderOps = inOrderOps, WholeOps = wholeOps,
            HandedOver = handedOverPaths,
        };
    }

    /// <summary>
    /// The targets of a step with a handed-over place, in the op order of
    /// this plan (#899 W8b-21a1; the mac's <c>targetsInTheStepsOrder</c>,
    /// U4b3 door-1): each group's targets with the op each comes from, a file
    /// target at the first op naming its path, so every filler's change goes
    /// in after its leaver's. Targets of one op keep the order they were
    /// given in, the groups' order first.
    /// </summary>
    internal static List<UndoSwapTarget> TargetsInTheStepsOrder(IReadOnlyList<IReadOnlyList<UndoSwapTarget>> groups,
                                                               IReadOnlyList<IReadOnlyList<int>> groupOps)
    {
        var ordered = new List<UndoSwapTarget>();
        var orderedOps = new List<int>();
        for (int group = 0; group < groups.Count; group++)
        {
            for (int position = 0; position < groups[group].Count; position++)
            {
                int opIndex = groupOps[group][position];
                // After every target from an op at or before this one.
                int insertAt = ordered.Count;
                while (insertAt > 0 && orderedOps[insertAt - 1] > opIndex) insertAt--;
                ordered.Insert(insertAt, groups[group][position]);
                orderedOps.Insert(insertAt, opIndex);
            }
        }
        return ordered;
    }

    /// <summary>Each edit's path a move of the step carries (<see cref="UndoOp.MoveCarries"/>, the edit after the move), with that move (the mac's <c>UndoCheck.carriers</c>).</summary>
    internal static Dictionary<string, UndoOp> Carriers(IReadOnlyList<UndoOp> ops)
    {
        var found = new Dictionary<string, UndoOp>(StringComparer.Ordinal);
        for (int index = 0; index < ops.Count; index++)
        {
            for (int later = index + 1; later < ops.Count; later++)
            {
                if (ops[later].Path is { } path && UndoOp.MoveCarries(ops[index], ops[later])) found[path] = ops[index];
            }
        }
        return found;
    }

    private static bool SameContent(UndoCurrent a, UndoCurrent b) => (a, b) switch
    {
        (UndoCurrent.Absent, UndoCurrent.Absent) => true,
        (UndoCurrent.Bytes x, UndoCurrent.Bytes y) => x.Content.AsSpan().SequenceEqual(y.Content),
        _ => false,
    };

    /// <summary>
    /// The one change a move, a tree or an external op makes going this way,
    /// or null when content it needs is missing from the list. A folder is
    /// never taken out unless the list holds everything needed to make it
    /// again (the mac's hard review of U2b, HIGH 2). <paramref name="blob"/>
    /// throws when the list cannot be read, as for any other op.
    /// </summary>
    private static UndoSwapTarget? WholeTarget(UndoOp op, bool backward, string root, Func<string, byte[]?> blob)
    {
        switch (op.Kind)
        {
            case UndoOp.Move:
            {
                string source = backward ? op.To! : op.From!;
                string destination = backward ? op.From! : op.To!;
                return new UndoSwapTarget(UndoTreeReading.Under(root, destination), destination, null, null)
                {
                    Change = new UndoSwapChange.MoveHere(UndoTreeReading.Under(root, source), source, op),
                };
            }
            case UndoOp.CreateTree:
            case UndoOp.RemoveTree:
            {
                bool makes = (op.Kind == UndoOp.CreateTree) == !backward;
                if (blob(op.ListingSha!) is not { } listingBytes || UndoTreeListing.Parse(listingBytes) is not { } listing
                    || !string.Equals(listing.Sha, op.ListingSha, StringComparison.Ordinal))
                    return null;
                var contents = new Dictionary<string, byte[]>(StringComparer.Ordinal);
                foreach ((string path, string sha) in listing.Files)
                {
                    if (blob(sha) is not { } bytes || !string.Equals(Sha(bytes), sha, StringComparison.Ordinal)) return null;
                    contents[path] = bytes;
                }
                var target = new UndoSwapTarget(UndoTreeReading.Under(root, op.Path!), op.Path!, null, null);
                return makes
                    ? target with { Change = new UndoSwapChange.MakeTree(listing, contents) }
                    : target with { Change = new UndoSwapChange.TakeTree(op.ListingSha!) };
            }
            case UndoOp.External:
                return new UndoSwapTarget("", op.Target!, null, null)
                {
                    Change = new UndoSwapChange.SetExternal(op.Target!, backward ? op.ValueAfter : op.ValueBefore,
                                                            backward ? op.ValueBefore : op.ValueAfter),
                };
            default:
                return null;
        }
    }
}

/// <summary>
/// Where a plan reads and changes the whole ops of a step (U2's kinds, W6):
/// the working folder's root (empty for a step none of whose ops names a
/// path: an external op alone) and the places outside every working folder.
/// <see cref="CannotRead"/> is a test's seam.
/// </summary>
internal sealed record UndoWholeReads(string Root, IUndoExternalPlaces Places, Func<string, bool>? CannotRead = null);

/// <summary>The kinds of change a swap makes besides a file's content (the mac's <c>UndoSwapChange</c>).</summary>
internal abstract record UndoSwapChange
{
    private UndoSwapChange() { }

    /// <summary>The item at <see cref="FromFull"/> renamed onto the target, which must be free: one rename that never replaces, the pair re-checked first.</summary>
    internal sealed record MoveHere(string FromFull, string FromRelative, UndoOp Op) : UndoSwapChange;

    /// <summary>A folder made with every file in it: built beside its place under a staged name, then renamed in, never over anything.</summary>
    internal sealed record MakeTree(UndoTreeListing Listing, IReadOnlyDictionary<string, byte[]> Contents) : UndoSwapChange;

    /// <summary>A folder whose listing must still be this one, taken out: renamed aside FIRST, checked there, removed once every change has gone in.</summary>
    internal sealed record TakeTree(string ListingSha) : UndoSwapChange;

    /// <summary>An external target set (null: removed), which must still hold <see cref="Expected"/>.</summary>
    internal sealed record SetExternal(string Target, UndoJson? Expected, UndoJson? Value) : UndoSwapChange;

}

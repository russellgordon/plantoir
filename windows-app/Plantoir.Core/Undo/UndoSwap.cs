using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Core.Undo;

/// <summary>What stands in the way of a change, an undo or a redo (the mac's <c>UndoRefusal</c>).</summary>
internal enum UndoRefusalKind
{
    /// <summary>What the step changed has been changed since: ruling 13 clears the list for an Undo, ruling 20 drops the redo.</summary>
    ChangedSince,
    /// <summary>A file could not be swapped in (another program has it), and the swaps already made were reversed: nothing on the list changes.</summary>
    FileIsInUse,
    /// <summary>A file it must read is there and could not be read now: cannot tell, never a reason to clear.</summary>
    CannotTellNow,
    /// <summary>A new content could not be written beside its page (the disk full, a folder or a page that will not take a write): nothing swapped, nothing left (U1's F1).</summary>
    CouldNotWrite,
    /// <summary>Content the step needs is missing from the list (ruling 22: an Undo clears the list).</summary>
    ContentMissing,
    /// <summary>The step holds an op this version cannot read.</summary>
    NotReadable,
}

/// <summary>A refusal and the first page it names, with how many others were found in the way.</summary>
internal sealed record UndoRefusal(UndoRefusalKind Kind, string? Path = null, int Others = 0)
{
    /// <summary>A couldNotWrite because every name a kept original can take beside the file is taken: neither room nor permission, so its sentence says so (W7a part two, review 1, LOW 4).</summary>
    internal bool EveryKeptNameTaken { get; init; }

    /// <summary>The word the contract spells it with (<c>stepCases</c>' <c>undo</c>, the traces' <c>expect</c>).</summary>
    internal string Word => Kind switch
    {
        UndoRefusalKind.ChangedSince => "changedSince",
        UndoRefusalKind.FileIsInUse => "fileIsInUse",
        UndoRefusalKind.CannotTellNow => "cannotTellNow",
        UndoRefusalKind.CouldNotWrite => "couldNotWrite",
        UndoRefusalKind.ContentMissing => "contentMissing",
        _ => "notReadable",
    };
}

/// <summary>One file a step changes: where it is, what it must still hold (null: no file), and what goes in its place (null: removed).</summary>
internal sealed record UndoSwapTarget(string FullPath, string RelativePath, byte[]? Expected, byte[]? Replacement)
{
    /// <summary>A whole op's change (U2's kinds, W6); null for a file's content swapped.</summary>
    internal UndoSwapChange? Change { get; init; }

    /// <summary>A file a move carries, going forward: staged only at its turn, once the move has made its folder, never before (#899 W8-2; the mac's <c>stagesAtItsTurn</c>).</summary>
    internal bool StagesAtItsTurn { get; init; }

    /// <summary>
    /// A file op at a handed-over place whose other op is a link's move
    /// (#899 W8b-21a1; the mac's <c>handedOver</c>, U4b3 door-1): the look
    /// before STAGING judges its place on the folders above it only, as the
    /// link leaving it, or arriving at it, still stands there and is never
    /// written through. The look before its own change judges the place whole.
    /// </summary>
    internal bool HandedOver { get; init; }
}

/// <summary>How a swap went.</summary>
internal abstract record UndoSwapResult
{
    private UndoSwapResult() { }

    internal sealed record Swapped : UndoSwapResult;
    internal sealed record Refused(UndoRefusal Refusal) : UndoSwapResult
    {
        /// <summary>
        /// A swap already made could not be reversed: a page still holds the
        /// step's content (its original kept under its staged name). The step
        /// is half applied and must be left IN FLIGHT for recovery, never
        /// closed <c>failed</c> (W2b's review, LOW 1; <c>rule.recovery</c>).
        /// </summary>
        internal bool LeftPartWay { get; init; }
    }
    /// <summary>A test (or the harness) stopped it at a kill point, leaving everything as a process that died there would.</summary>
    internal sealed record StoppedByATest : UndoSwapResult;
}

/// <summary>
/// The door's and the swap's seams for tests and the harness: an object the
/// caller makes, never a static (the plan review's H1, test classes run in
/// parallel). Nothing in the app sets one.
/// </summary>
internal sealed class UndoSeams
{
    /// <summary>
    /// Asked at each kill point (<c>afterBegin</c>, <c>afterTheCheck</c>,
    /// <c>afterUndoing</c>, <c>afterRedoing</c>, <c>beforeSwap</c> with its index,
    /// <c>beforeApplied</c>, <c>beforeUndone</c>, <c>beforeRedone</c>; and
    /// recovery's own, W3: <c>afterRecoveryTidied</c>,
    /// <c>recoveryBeforeSwap</c> with its index, <c>recoveryBeforeWriting</c>): true stops the
    /// work there, nothing more written, as a process that died there would.
    /// The harness blocks in it until it is killed.
    /// </summary>
    internal Func<string, int, bool>? StopsHere { get; init; }

    /// <summary>The staging write at this index makes its file and then fails to write into it, as a full disk does (<c>stepCases</c> <c>stagingFailsAt</c>).</summary>
    internal Func<int, bool>? StagingWriteFailsAt { get; init; }

    /// <summary>Called with the index and the target's full path just before it is re-read for its swap (a test changes or holds the page there).</summary>
    internal Action<int, string>? BeforeEachSwap { get; init; }

    /// <summary>Called with the index and the target's full path after its original is kept and before the rename (a test writes into the page in place there, L4).</summary>
    internal Action<int, string>? BetweenKeepingAndRenaming { get; init; }

    /// <summary>A test's: putting the original of the swap at this index back fails, as a rename refused for good does (the mac's putBackFailsAt).</summary>
    internal Func<int, bool>? PutBackFailsAt { get; init; }

    /// <summary>A test's: clearing the Hidden attribute the swap set on the kept original at this index fails, as an attribute that will not take does (W7a part two, review 1, LOW 1).</summary>
    internal Func<int, bool>? ShowingTheKeptFileFailsAt { get; init; }

    /// <summary>Called with the two full paths of every rename the swap makes, before it is tried (a test counts a capitalisation-only rename's renames, #899 W8-5).</summary>
    internal Action<string, string>? EachRename { get; init; }

    /// <summary>The POSIX-semantics rename answers "not supported" (87), as on a network share, so every swap takes the fallback (M5).</summary>
    internal bool PosixRenameIsNotSupported { get; init; }

    /// <summary>Called once a step's undo or redo has checked its ops and before it answers (the stack case <c>undoWhileAStepBegins</c>).</summary>
    internal Action? AfterTheCheck { get; init; }

    /// <summary>Called by <c>Perform(UndoOpsDraft)</c> once its ops are vetted and before its begin hold (a test prunes a blob there: W2b's review, LOW 5).</summary>
    internal Action? BeforeTheBegin { get; init; }

    /// <summary>Called with each folder a move's last look left out, just before the tidy after every swap removes it if empty (U4b2-10; #899 W8-4): a test sees that a refused swap tidies none.</summary>
    internal Action<string>? RemovingAFolderLeftOut { get; init; }

    internal bool Stops(string point, int index = -1) => StopsHere?.Invoke(point, index) == true;
}

/// <summary>
/// Staged, then swapped (#899 W2b; <c>rule.stagedThenSwapped</c>, the mac's
/// <c>UndoSwap</c>, the Windows director's fact 5 on #899).
///
/// <para><b>Stage.</b> Every new content is written BESIDE its target first,
/// as <c>.&lt;name&gt;.plantoir-undo-&lt;seq&gt;-&lt;apply|undo|redo&gt;-new</c>
/// (<c>undoJournal.stagedFiles</c>), made with <see cref="FileMode.CreateNew"/>
/// and flushed to the disk. A write that fails (the disk full, a folder that
/// will not take a new file) removes the file it was writing and every other
/// staged file, swaps nothing and refuses <c>couldNotWrite</c>, never
/// <c>fileIsInUse</c> (U1's F1: <c>CreateNew</c> leaves its file behind exactly
/// as the mac's exclusive create did).</para>
///
/// <para><b>Swap.</b> Only when all are written, one at a time in the order
/// the check met them: the target re-read (delete sharing, never write
/// access) and still what the check saw; the original kept as <c>-orig</c> by
/// a hard link (a copy where the volume has none); the target's own
/// attributes and creation time copied onto the staged file (the plan
/// review's M4: whatever the staged file carries, the page becomes, Hidden
/// included); then ONE rename: the POSIX-semantics rename
/// (<c>FileRenameInfoEx</c>, replace and POSIX semantics, the source opened
/// with DELETE), which goes in under a holder that shares delete where
/// <c>MoveFileEx</c> is refused (the planner's P7), and <c>MoveFileEx</c> only
/// where the volume answers 87 or 50 (a network share: M5). An access denied
/// on a read-only page is <c>couldNotWrite</c> (it is never forced); a
/// refused rename is tried again a few times over about 50 ms (a paced retry,
/// the director's fact 2: 0 of 2,000 lost with 10 tries), then
/// <c>fileIsInUse</c>. After the rename the kept original is hashed against
/// what the check saw (the plan review's L4: a hard link is the page as it
/// was AT the swap, so an edit that raced it shows), and a difference reverses
/// the step as changed since. A swap that cannot go in reverses those already
/// made from their originals. Every place is checked inside the working
/// folder with links resolved at every change.</para>
///
/// <para><b>Tidy.</b> Once every swap is in, the originals and anything
/// staged are removed. An original whose reversal did NOT go in is never
/// removed: it is left under its staged name for recovery (W3), so the page's
/// old content is never deleted. A rename either happened or did not, so a
/// process that dies part way leaves each page wholly old or wholly new.</para>
/// </summary>
internal static class UndoSwap
{
    /// <summary>The part of a staged name that says it is Plantoir's.</summary>
    internal const string StagedMarker = ".plantoir-undo-";

    /// <summary>How many kept names (<c>-orig</c>, <c>-2-orig</c> … <c>-1000-orig</c>) a keep or a take-out tries before it is could not write.</summary>
    internal const int KeptNames = 1000;

    /// <summary>How many times a refused rename is tried in all, and how long apart.</summary>
    private const int RenameTries = 6;
    private static readonly TimeSpan RenameRetryPause = TimeSpan.FromMilliseconds(10);

    /// <param name="places">Where an external op's target is read and set (W6); needed only by a step that holds one.</param>
    /// <param name="keepingTheOriginalsOf">The pages (relative paths) whose kept original this swap leaves beside them once every
    /// swap is in, never tidied: what each held a moment before, which the list would not take and the step's other direction
    /// needs (the mac's U3c, <c>keepingTheOriginalsOf</c>; the first review of U3c, MEDIUM).</param>
    internal static UndoSwapResult Swap(IReadOnlyList<UndoSwapTarget> targets, string label, string? root, UndoSeams? seams = null,
                                        IUndoExternalPlaces? places = null, IReadOnlySet<string>? keepingTheOriginalsOf = null)
    {
        // What a plain write of a process that has gone left beside these
        // targets is tidied first (the W7a final review's LOW 3): no journal
        // line names it, so nothing else ever would.
        foreach (UndoSwapTarget target in targets) TidyPlainLeftoversOfTheGone(target.FullPath);
        // Every staged file's handle is let go however the swap ends, a test's
        // kill point included, as a process that died there would let it go.
        var staged = new UndoStagedFile?[targets.Count];
        var originals = new UndoStagedFile?[targets.Count];
        var foldersMade = new List<string>();
        UndoSwapResult? result = null;
        try
        {
            result = SwapStaged(targets, label, root, seams, places, staged, originals, keepingTheOriginalsOf, foldersMade);
            return result;
        }
        finally
        {
            foreach (UndoStagedFile? file in staged) file?.LetGo();
            foreach (UndoStagedFile? file in originals) file?.LetGo();
            // A refused swap, or one an exception cut short (no result), leaves
            // no empty folder it made behind (the W7b1 review's LOW 1, and its
            // review 2, LOW 5; the digest's trap "empty folders left behind").
            // A test's kill point is a process that died there: it tidies nothing.
            if (result is null or UndoSwapResult.Refused) RemoveTheEmptyFoldersMade(foldersMade);
        }
    }

    private static UndoSwapResult SwapStaged(IReadOnlyList<UndoSwapTarget> targets, string label, string? root, UndoSeams? seams,
                                             IUndoExternalPlaces? places, UndoStagedFile?[] staged, UndoStagedFile?[] originals,
                                             IReadOnlySet<string>? keepingTheOriginalsOf, List<string> foldersMade)
    {
        int count = targets.Count;
        int swapsMade = 0;
        // A tree's own: the folder it built beside its place (-new), and the
        // teacher's folder it took out, renamed aside (-orig).
        var stagedFolders = new string?[count];
        var asideFolders = new string?[count];

        // True when a test stopped it while a folder taken out was being
        // deleted, as a process that died there would stop.
        bool Tidy()
        {
            for (int index = 0; index < count; index++)
            {
                staged[index]?.Remove();
                originals[index]?.Remove();
                staged[index] = null;
                originals[index] = null;
                if (stagedFolders[index] is { } made) UndoLinks.RemoveFolder(made);
                stagedFolders[index] = null;
            }
            for (int index = 0; index < count; index++)
            {
                if (asideFolders[index] is not { } aside) continue;
                asideFolders[index] = null;
                // Renamed to a name recovery never puts back BEFORE it is
                // deleted, so a delete cut short is finished, never mistaken
                // for the teacher's folder (the mac's fourth review of U2b, MEDIUM).
                if (RemoveAFolderTakenOut(aside, seams)) return true;
            }
            return false;
        }

        // True when every swap already made was reversed. False when one could
        // not be (its page still holds this step's content): the step is then
        // half applied, its original is left under its staged name, and the
        // caller must leave the step IN FLIGHT for recovery (W2b's review,
        // LOW 1), never close it failed.
        bool Reverse()
        {
            bool whole = true;
            for (int index = swapsMade - 1; index >= 0; index--)
            {
                UndoSwapTarget target = targets[index];
                switch (target.Change)
                {
                    case UndoSwapChange.MoveHere move:
                        LetGoOwnFilesInside(target.RelativePath);
                        if (RenameWithRetries(target.FullPath, move.FromFull, replace: false, seams) != 0) whole = false;
                        else FollowTheMove(target.RelativePath, move.FromRelative, target.FullPath, move.FromFull);
                        continue;
                    case UndoSwapChange.MakeTree:
                    {
                        // Back under its staged name, removed with the rest.
                        string back = BesidePath(target.FullPath, label, "new");
                        if (RenameWithRetries(target.FullPath, back, replace: false, seams) == 0) stagedFolders[index] = back;
                        else whole = false;
                        continue;
                    }
                    case UndoSwapChange.TakeTree:
                        // Never removed by the tidy that follows: put back, or,
                        // if even that fails, left aside under its staged name
                        // for recovery, which puts it back or keeps it visibly.
                        if (asideFolders[index] is { } aside && RenameWithRetries(aside, target.FullPath, replace: false, seams) != 0) whole = false;
                        asideFolders[index] = null;
                        continue;
                    case UndoSwapChange.SetExternal external:
                        if (places is null || !places.Write(external.Target, external.Expected)) whole = false;
                        continue;
                }
                if (originals[index] is { } original)
                {
                    // Put back, it is the page again; not put back, it is the
                    // page's old content under its staged name, left for
                    // recovery and never deleted. Either way it is no longer
                    // the tidy's to remove.
                    original.LetGo();
                    originals[index] = null;
                    if (seams?.PutBackFailsAt?.Invoke(index) == true) whole = false;
                    else
                    {
                        // Shown again before it is the page again; hidden
                        // again if it stays under its kept name. Not shown,
                        // it is never renamed onto the page: it stays Hidden
                        // under its kept name, left for recovery, so a page
                        // is never left Hidden (part two, review 1, LOW 1).
                        if (!ShowTheKeptFile(original, seams?.ShowingTheKeptFileFailsAt?.Invoke(index) == true)) whole = false;
                        else if (RenameWithRetries(original.Path, target.FullPath, replace: true, seams) != 0)
                        {
                            whole = false;
                            HideTheKeptFile(original);
                        }
                    }
                }
                else if (!TryDelete(target.FullPath))
                {
                    // There was no file: the one the swap made goes.
                    whole = false;
                }
            }
            return whole;
        }

        // A file's new content written beside it; false when the write failed.
        bool StageAFile(int index)
        {
            UndoSwapTarget target = targets[index];
            if (target.Replacement is not { } replacement) return true;
            string stagedPath = BesidePath(target.FullPath, label, "new");
            try
            {
                MakeTheFolderOf(target.FullPath, foldersMade);
                TryDelete(stagedPath);
                if (seams?.StagingWriteFailsAt?.Invoke(index) == true)
                {
                    // As a full disk does: the exclusive create makes the file,
                    // then writing into it fails.
                    using (new FileStream(stagedPath, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { }
                    throw new IOException("There is not enough space on the disk.", unchecked((int)0x80070070));
                }
                WriteDurably(stagedPath, replacement);
                staged[index] = UndoStagedFile.Made(stagedPath);
                return true;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // The file the exclusive create made is this swap's own: it goes
                // with every other. Staging writes a NEW file, which no other
                // program can be holding, so this is never fileIsInUse.
                TryDelete(stagedPath);
                return false;
            }
        }

        // Where each file target's page is now, relative to the root: its own
        // place until a move this swap makes carries it (#899 W8-2b).
        var placeOf = new string[count];
        for (int index = 0; index < count; index++) placeOf[index] = targets[index].RelativePath;

        // This swap's own staged and kept files inside the place a move
        // moves, found by the one comparison (UndoOp.PartInside): their
        // handles let go (Windows will not rename a folder with a file open
        // below it), and each named, relative to the place, to be left out
        // of the move's last look. What the step's EARLIER swaps left is
        // added at the forward call (StepsOwnFilesInside, W8-3); never
        // another step's files. #899 W8-2b.
        Dictionary<string, UndoCurrent> LetGoOwnFilesInside(string place)
        {
            var leftOut = new Dictionary<string, UndoCurrent>(StringComparer.Ordinal);
            for (int index = 0; index < count; index++)
            {
                foreach (UndoStagedFile? file in new[] { staged[index], originals[index] })
                {
                    if (file is null || UndoOp.PartInside(place, BesideRelative(placeOf[index], file.Path)) is not { } inside) continue;
                    file.LetGo();
                    leftOut[inside] = new UndoCurrent.Absent();
                }
            }
            return leftOut;
        }

        // Once the folder has moved, this swap's own files and its pages
        // inside it are where the folder is now, so the tidy and a reversal
        // find them there (#899 W8-2b); and so are the folders it made inside
        // it, so a refused swap's tidy finds them where the folder went back
        // to (the window 1 review's LOW 3; #899 W8-4).
        void FollowTheMove(string from, string to, string fromFull, string toFull)
        {
            for (int index = 0; index < foldersMade.Count; index++)
            {
                if (UndoOp.PartInside(fromFull.Replace('\\', '/'), foldersMade[index].Replace('\\', '/')) is not { } madeInside) continue;
                foldersMade[index] = madeInside.Length == 0 ? toFull : Path.Combine(toFull, madeInside.Replace('/', Path.DirectorySeparatorChar));
            }
            for (int index = 0; index < count; index++)
            {
                if (targets[index].Change is not null || UndoOp.PartInside(from, placeOf[index]) is not { } pageInside) continue;
                string pageWas = placeOf[index];
                placeOf[index] = pageInside.Length == 0 ? to : to + "/" + pageInside;
                staged[index] = Followed(staged[index], pageWas);
                originals[index] = Followed(originals[index], pageWas);
            }

            UndoStagedFile? Followed(UndoStagedFile? file, string pageWas) =>
                file is not null && UndoOp.PartInside(from, BesideRelative(pageWas, file.Path)) is { } inside
                    ? file.MovedTo(Path.Combine(toFull, inside.Replace('/', Path.DirectorySeparatorChar)))
                    : file;
        }

        // The folders a move's last look left out (a folder a carried edit
        // made, holding only files left out), each at its place after the
        // move, deepest first: removed, when empty, once every swap is in
        // and the step's own files are tidied; never on a refusal (U4b2-10;
        // #899 W8-4).
        var foldersLeftOutOfAMove = new List<string>();

        // 1. Stage every new content beside its target.
        for (int index = 0; index < count; index++)
        {
            UndoSwapTarget target = targets[index];
            if (root is not null && PlaceLeadingOut(target, root, atStaging: true) is { } leadingOut)
            {
                Tidy();
                return new UndoSwapResult.Refused(new UndoRefusal(UndoRefusalKind.ChangedSince, leadingOut));
            }
            if (target.Change is UndoSwapChange.MakeTree tree)
            {
                string stagedFolder = BesidePath(target.FullPath, label, "new");
                bool made;
                try
                {
                    MakeTheFolderOf(target.FullPath, foldersMade);
                    UndoLinks.RemoveFolder(stagedFolder);
                    made = UndoTreeReading.Make(tree.Listing, tree.Contents, stagedFolder, failTheWrite: seams?.StagingWriteFailsAt?.Invoke(index) == true);
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { made = false; }
                if (!made)
                {
                    UndoLinks.RemoveFolder(stagedFolder);
                    Tidy();
                    return new UndoSwapResult.Refused(new UndoRefusal(UndoRefusalKind.CouldNotWrite, target.RelativePath));
                }
                stagedFolders[index] = stagedFolder;
                continue;
            }
            if (target.Change is not null) continue;
            // A file a move carries is staged at its turn, once the move has
            // made its folder (#899 W8-2).
            if (target.StagesAtItsTurn) continue;
            if (!StageAFile(index))
            {
                Tidy();
                return new UndoSwapResult.Refused(new UndoRefusal(UndoRefusalKind.CouldNotWrite, target.RelativePath));
            }
        }

        // 2. Swap them in, re-reading each target first.
        for (int index = 0; index < count; index++)
        {
            UndoSwapTarget target = targets[index];
            if (seams?.Stops("beforeSwap", index) == true) return new UndoSwapResult.StoppedByATest();
            UndoRefusal? refusal;
            bool wentIn;
            if (target.Change is null)
            {
                // A carried file, staged now that its folder is there.
                if (target.StagesAtItsTurn && !StageAFile(index))
                {
                    refusal = new UndoRefusal(UndoRefusalKind.CouldNotWrite, target.RelativePath);
                    wentIn = false;
                }
                else refusal = SwapAFile(target, index, label, root, staged, originals, seams, out wentIn);
            }
            else
            {
                seams?.BeforeEachSwap?.Invoke(index, target.FullPath);
                Dictionary<string, UndoCurrent>? ownLeftOut = null;
                if (target.Change is UndoSwapChange.MoveHere moving)
                {
                    ownLeftOut = LetGoOwnFilesInside(moving.FromRelative);
                    // And what the step's EARLIER swaps left inside it (U4b, M1; #899 W8-3),
                    // never inside a link's move: nothing of the step's is there,
                    // and what the link leads to is never walked (U4b2-14; W8-6).
                    if (moving.Op.LinkSha is null && SeqOfLabel(label) is { } seq)
                    {
                        foreach ((string inside, UndoCurrent absent) in StepsOwnFilesInside(moving.FromFull, seq))
                            ownLeftOut.TryAdd(inside, absent);
                    }
                }
                refusal = root is not null && PlaceLeadingOut(target, root) is { } leadingOut
                    ? new UndoRefusal(UndoRefusalKind.ChangedSince, leadingOut)
                    : SwapAWholeOp(target, index, label, seams, places, stagedFolders, asideFolders, ownLeftOut, foldersLeftOutOfAMove);
                wentIn = refusal is null;
                if (wentIn && target.Change is UndoSwapChange.MoveHere moved) FollowTheMove(moved.FromRelative, target.RelativePath, moved.FromFull, target.FullPath);
            }
            if (wentIn) swapsMade++;
            if (refusal is not null)
            {
                bool reversed = Reverse();
                Tidy();
                return new UndoSwapResult.Refused(refusal) { LeftPartWay = !reversed };
            }
        }

        // 3. Every swap went in: the kept originals are no longer needed,
        // except one the caller keeps (what its page held a moment before,
        // which the list would not take): let go, left under its hidden name.
        if (keepingTheOriginalsOf is { Count: > 0 })
        {
            for (int index = 0; index < count; index++)
            {
                if (originals[index] is not { } original || !keepingTheOriginalsOf.Contains(targets[index].RelativePath)) continue;
                original.LetGo();
                originals[index] = null;
            }
        }
        if (Tidy()) return new UndoSwapResult.StoppedByATest();
        foreach (string folder in foldersLeftOutOfAMove)
        {
            seams?.RemovingAFolderLeftOut?.Invoke(folder);
            RemoveAFolderLeftOut(folder);
        }
        return new UndoSwapResult.Swapped();
    }

    /// <summary>
    /// The place to name when a change no longer stays inside the working
    /// folder, links resolved, or null when it does: for a move, the first of
    /// its op's places, in the order path, from, to, that leads out, by the
    /// same function the plan uses (<see cref="UndoPlaces.FirstPlaceLeadingOut"/>;
    /// U4b2-2 review 1, MEDIUM 1; #899 W8-1), never the other side of the
    /// move; none for an external target; for any other change, the place it
    /// changes.
    ///
    /// <para><paramref name="atStaging"/> is true for the look before staging:
    /// a file target at a handed-over place (<see cref="UndoSwapTarget.HandedOver"/>)
    /// is then judged on the folders above it only, as the link leaving it,
    /// or arriving at it, still stands there (#899 W8b-21a1; the mac's U4b3
    /// door-1). Before its own change the leaver has gone, and the place is
    /// judged whole, as any file's (<see cref="SwapAFile"/>'s own look).</para>
    /// </summary>
    private static string? PlaceLeadingOut(UndoSwapTarget target, string root, bool atStaging = false) => target.Change switch
    {
        null when atStaging && target.HandedOver => UndoPlaces.StaysInsideAbove(root, target.RelativePath) ? null : target.RelativePath,
        UndoSwapChange.SetExternal => null,
        // The places the swap touches are the op's two; should they ever
        // differ in spelling, a place the op does not name that leads out is
        // still named, by the place it changes (as the mac's fallback).
        UndoSwapChange.MoveHere move => UndoPlaces.FirstPlaceLeadingOut(root, move.Op)
            ?? (UndoPlaces.StaysInside(root, move.FromRelative, move.Op) && UndoPlaces.StaysInside(root, target.RelativePath, move.Op) ? null : target.RelativePath),
        _ => UndoPlaces.StaysInside(root, target.RelativePath) ? null : target.RelativePath,
    };

    /// <summary>One whole op's change (the mac's swap of <c>moveHere</c>, <c>makeTree</c>, <c>takeTree</c>, <c>setExternal</c>); the refusal, or null when it went in.</summary>
    /// <param name="ownLeftOut">For a move: this swap's own staged and kept files inside the folder, relative to it, left out of its last look (#899 W8-2b).</param>
    private static UndoRefusal? SwapAWholeOp(UndoSwapTarget target, int index, string label, UndoSeams? seams, IUndoExternalPlaces? places,
                                             string?[] stagedFolders, string?[] asideFolders,
                                             IReadOnlyDictionary<string, UndoCurrent>? ownLeftOut = null, List<string>? foldersLeftOutOfAMove = null)
    {
        switch (target.Change)
        {
            case UndoSwapChange.MoveHere move:
            {
                // The pair once more, just before the rename: the content at
                // the place it leaves, nothing where it goes.
                // The folders it names as left out are where the folder goes,
                // once it has moved (U4b2-10; #899 W8-4).
                (UndoMoveSide atFrom, IReadOnlyList<string> foldersLeftOut) = UndoMoveSides.ReadNamingFoldersLeftOut(move.Op, move.FromFull, overriding: ownLeftOut);
                UndoMoveSide atTarget = UndoMoveSides.Read(move.Op, target.FullPath);
                if (move.Op.IsCaseOnlyMove && UndoMoveSides.SpellingListed(move.FromFull, target.FullPath) is { } spelled)
                {
                    // One item under two spellings (U4b; W8-5): it goes in
                    // only while its folder lists the spelling it leaves, and
                    // the one rename then replaces nothing (measured on the
                    // PC: MoveFileEx without MOVEFILE_REPLACE_EXISTING renames
                    // Media to media, a folder or a file, and answers 0; it
                    // answers 0 too when the folder already lists the new
                    // spelling, so the listing, not the rename, decides).
                    atTarget = spelled switch
                    {
                        UndoCaseOnlySpelling.From => UndoMoveSide.Free,
                        UndoCaseOnlySpelling.CannotRead => UndoMoveSide.CannotRead,
                        _ => UndoMoveSide.HoldsSomethingElse,
                    };
                }
                // Named where a teacher finds the item now, as the plan's
                // refusal names it (placeAsFound: the place it leaves; #899 W8-3).
                if (atFrom == UndoMoveSide.CannotRead || atTarget == UndoMoveSide.CannotRead)
                    return new UndoRefusal(UndoRefusalKind.CannotTellNow, move.FromRelative);
                if (atFrom != UndoMoveSide.HoldsTheContent || atTarget != UndoMoveSide.Free)
                    return new UndoRefusal(UndoRefusalKind.ChangedSince, move.FromRelative);
                try { Directory.CreateDirectory(Path.GetDirectoryName(target.FullPath)!); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    return new UndoRefusal(UndoRefusalKind.CouldNotWrite, move.FromRelative);
                }
                // MoveFileEx WITHOUT MOVEFILE_REPLACE_EXISTING: never over
                // anything that appeared at the destination since. A rename
                // refused names the place it leaves, as the mac's moveHere
                // names it (namedAs), never a destination not there yet (the
                // window 1 review's LOW 1; #899 W8-4).
                int moved = RenameWithRetries(move.FromFull, target.FullPath, replace: false, seams);
                if (moved != 0) return new UndoRefusal(Classify(moved, move.FromFull), move.FromRelative);
                foreach (string inside in foldersLeftOut)
                    foldersLeftOutOfAMove?.Add(Path.Combine(target.FullPath, inside.Replace('/', Path.DirectorySeparatorChar)));
                return null;
            }
            case UndoSwapChange.MakeTree:
            {
                switch (UndoTreeReading.Read(target.FullPath))
                {
                    case UndoTreeReading.CannotRead: return new UndoRefusal(UndoRefusalKind.CannotTellNow, target.RelativePath);
                    case UndoTreeReading.Absent: break;
                    default: return new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath);
                }
                if (stagedFolders[index] is { } made && RenameWithRetries(made, target.FullPath, replace: false, seams) == 0)
                {
                    stagedFolders[index] = null;
                    return null;
                }
                return new UndoRefusal(UndoRefusalKind.FileIsInUse, target.RelativePath);
            }
            case UndoSwapChange.TakeTree take:
            {
                // Renamed aside FIRST, then its listing checked where nobody
                // else writes into it: a file added while the folder was being
                // walked can no longer go aside unseen and be deleted with it
                // (the mac's hard review of U2b, MEDIUM 4). A folder that
                // differs is put back as it is and the take-out refused.
                // Set aside under the first kept name nothing holds (-orig,
                // then -2-orig and on), as a page's original is: a folder
                // already aside under a name (step numbers that collide across
                // two computers, or a list started again) is never reused, and
                // the take-out is never refused for good because of it (the
                // mac's U3c, first review, LOW 3; W4c review 1, LOW 1). Every
                // name taken is could not write, as the mac's freeKeptName.
                string? aside = null;
                int failure = 0;
                bool everyNameTaken = true;
                for (int number = 1; number <= KeptNames; number++)
                {
                    string candidate = BesidePath(target.FullPath, label, number == 1 ? "orig" : number + "-orig");
                    if (UndoLinks.Look(candidate) != UndoLinks.What.Nothing) continue;
                    failure = RenameWithRetries(target.FullPath, candidate, replace: false, seams);
                    if (failure == 0) { aside = candidate; everyNameTaken = false; break; }
                    if (failure is not (80 or 183)) { everyNameTaken = false; break; }
                }
                if (aside is null)
                {
                    if (everyNameTaken) return new UndoRefusal(UndoRefusalKind.CouldNotWrite, target.RelativePath) { EveryKeptNameTaken = true };
                    return UndoTreeReading.Read(target.FullPath).ListingSha == take.ListingSha
                        ? new UndoRefusal(UndoRefusalKind.FileIsInUse, target.RelativePath)
                        : new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath);
                }
                if (UndoTreeReading.Read(aside).ListingSha != take.ListingSha)
                {
                    // Put back as it is: a change since. If its place was taken
                    // in that instant it stays aside, hidden and whole, never
                    // deleted, and the refusal is cannot tell now, which never
                    // clears the list; recovery puts it back or keeps it under a
                    // visible name (the mac's second hard review, MEDIUM 3).
                    return RenameWithRetries(aside, target.FullPath, replace: false, seams) == 0
                        ? new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath)
                        : new UndoRefusal(UndoRefusalKind.CannotTellNow, target.RelativePath);
                }
                asideFolders[index] = aside;
                return null;
            }
            case UndoSwapChange.SetExternal external:
                // Re-read just before it is set.
                if (places is null || !places.Read(external.Target).Matches(external.Expected))
                    return new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath);
                return places.Write(external.Target, external.Value) ? null : new UndoRefusal(UndoRefusalKind.CouldNotWrite, target.RelativePath);
            default:
                return new UndoRefusal(UndoRefusalKind.NotReadable, target.RelativePath);
        }
    }

    /// <summary>
    /// U4b2-10: a folder a move's last look left out, removed where it now is
    /// when it holds nothing but, perhaps, the Finder's record of a window
    /// (<see cref="UndoTreeListing.IgnoredName"/>, never listed), which goes
    /// first only when it is a regular file (<see cref="UndoLinks.Look"/>) and
    /// the folder holds nothing else; a link of that name, or anything else
    /// inside, leaves the folder and all it holds (the mac's
    /// <c>removeAFolderLeftOut</c>; #899 W8-4). Never a recursive delete, and
    /// never told when it fails: every swap has gone in, and a folder that
    /// will not go holds something put there since the last look.
    /// </summary>
    internal static void RemoveAFolderLeftOut(string folder)
    {
        // A link put at its place since is never removed, nor followed.
        if (UndoLinks.Look(folder) != UndoLinks.What.Folder) return;
        try
        {
            List<string> entries = Directory.EnumerateFileSystemEntries(folder).ToList();
            if (entries.Count == 1 && Path.GetFileName(entries[0]) == UndoTreeListing.IgnoredName)
            {
                if (UndoLinks.Look(entries[0]) != UndoLinks.What.File) return;
                File.Delete(entries[0]);
            }
            Directory.Delete(folder, recursive: false);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>
    /// The name a folder taken out is renamed to before it is deleted: its
    /// <c>-orig</c> role becomes <c>-gone</c>, which <see cref="IsAFolderSetAside"/>
    /// never matches, so recovery finishes the delete of whatever is left
    /// under it as it does any staged item.
    /// </summary>
    internal static string GonePath(string aside) =>
        aside.EndsWith("-orig", StringComparison.Ordinal) ? aside[..^"-orig".Length] + "-gone" : aside + "-gone";

    /// <summary>
    /// Deletes a folder a swap took out, once every change has gone in: one
    /// rename to its <c>-gone</c> name (atomic: wholly the teacher's folder set
    /// aside, or wholly a leftover to finish deleting), then the delete, which
    /// is not. If the rename fails the folder is left whole under its
    /// <c>-orig</c> name, never deleted in place. True only when a test (or
    /// the harness) stopped it between the two (<c>whileDeletingAFolder</c>).
    /// </summary>
    internal static bool RemoveAFolderTakenOut(string aside, UndoSeams? seams)
    {
        string gone = GonePath(aside);
        if (UndoLinks.Look(gone) != UndoLinks.What.Nothing) UndoLinks.RemoveFolder(gone);   // an earlier delete cut short
        if (RenameWithRetries(aside, gone, replace: false, seams) != 0) return false;
        if (seams?.Stops("whileDeletingAFolder") == true) return true;
        UndoLinks.RemoveFolder(gone);
        return false;
    }

    /// <summary>Whether a staged item is a folder kept aside as an original (<c>-orig</c>): a folder a tree op took out, which holds the teacher's files.</summary>
    internal static bool IsAFolderSetAside(string path) =>
        Path.GetFileName(path).EndsWith("-orig", StringComparison.Ordinal) && UndoLinks.Look(path) == UndoLinks.What.Folder;

    /// <summary>Marks a kept original Hidden, unless it already is (a page the teacher hid keeps its own attribute). Best effort: an attribute that will not take leaves the file as it is.</summary>
    internal static void HideTheKeptFile(UndoStagedFile kept)
    {
        try
        {
            FileAttributes now = File.GetAttributes(kept.Path);
            if (now.HasFlag(FileAttributes.Hidden)) return;
            File.SetAttributes(kept.Path, now | FileAttributes.Hidden);
            kept.HiddenByTheSwap = true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>
    /// Marks a kept original Hidden where it is left and named as "the hidden
    /// file" (recovery's lines, a step left part way, a kept file the list
    /// could not take), so the word is true on every path: a kept file made
    /// before a kill, before the swap hid it, or written fresh inside a tree
    /// brought back (W7a part two, review 1, LOW 2). Only a file with one
    /// name: a kept original that is still a hard link to its page (a kill
    /// between keeping it and the page's rename) is left as it is, so a page
    /// is never hidden. Best effort.
    /// </summary>
    internal static void HideAKeptFileLeft(string fullPath)
    {
        try
        {
            FileAttributes now = File.GetAttributes(fullPath);
            if (now.HasFlag(FileAttributes.Hidden) || now.HasFlag(FileAttributes.Directory)) return;
            using (var handle = File.OpenHandle(fullPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                if (UndoFileIdentity.LinksOf(handle) != 1) return;
            }
            File.SetAttributes(fullPath, now | FileAttributes.Hidden);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>Clears the Hidden attribute the swap set, before a kept original is renamed back to be the page. False when it is still Hidden, so it must not be renamed onto the page.</summary>
    private static bool ShowTheKeptFile(UndoStagedFile kept, bool failsForATest = false)
    {
        if (!kept.HiddenByTheSwap) return true;
        if (failsForATest) return false;
        try
        {
            File.SetAttributes(kept.Path, File.GetAttributes(kept.Path) & ~FileAttributes.Hidden);
            kept.HiddenByTheSwap = false;
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
    }

    /// <summary>
    /// Every staged file and kept original of step <paramref name="seq"/>,
    /// from any of its swaps (its apply, an undo, a redo, a recovery), inside
    /// the folder at <paramref name="folderFull"/>, relative to it with
    /// <c>/</c>, as absent: a carrying move's pair is judged without them (the
    /// mac's <c>stepsOwnFilesInside</c>, U4b's M1; #899 W8-3). Only the
    /// step's own names, by its marker (<see cref="IsStaged"/> with the seq as
    /// the label, so step 11's are never step 1's); anything else inside still
    /// counts. Never through a link (<see cref="UndoLinks.Look"/>): a place
    /// that is a link now holds nothing of the step's.
    /// </summary>
    internal static Dictionary<string, UndoCurrent> StepsOwnFilesInside(string folderFull, long seq)
    {
        var found = new Dictionary<string, UndoCurrent>(StringComparer.Ordinal);
        string own = seq.ToString(System.Globalization.CultureInfo.InvariantCulture);
        void Walk(string folder, string relative)
        {
            if (UndoLinks.Look(folder) != UndoLinks.What.Folder) return;
            IEnumerable<string> entries;
            try { entries = Directory.EnumerateFileSystemEntries(folder).ToList(); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return; }
            foreach (string entry in entries)
            {
                string name = Path.GetFileName(entry);
                string inside = relative.Length == 0 ? name : relative + "/" + name;
                if (IsStaged(name, own)) found[inside] = new UndoCurrent.Absent();
                else Walk(entry, inside);
            }
        }
        Walk(folderFull, "");
        return found;
    }

    /// <summary>The step's number a swap's label begins with (<c>&lt;seq&gt;-apply</c>, <c>-undo</c>, <c>-redo</c>), or null for a label of another shape.</summary>
    internal static long? SeqOfLabel(string label)
    {
        int dash = label.IndexOf('-');
        return dash > 0 && long.TryParse(label.AsSpan(0, dash), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out long seq)
            ? seq : null;
    }

    /// <summary>The place a staged name stands beside: the name between its leading dot and its LAST <c>.plantoir-undo-</c>, or null.</summary>
    internal static string? PlaceOfStagedName(string name)
    {
        if (!name.StartsWith('.')) return null;
        int marker = name.LastIndexOf(StagedMarker, StringComparison.Ordinal);
        if (marker <= 1) return null;
        return name[1..marker];
    }

    /// <summary>
    /// The visible name a folder set aside, or a page kept only in its hidden
    /// original, is kept under when something else holds its place:
    /// <c>&lt;name&gt; (kept by Undo)</c>, then <c>(kept by Undo 2)</c> and
    /// on. A folder's words go after its whole name; a page's before its
    /// extension, <c>Unit 1, Day 3 (kept by Undo).md</c> (Russell's ruling of
    /// 2026-11-26; the mac's <c>visibleName(for:number:isAPage:)</c>). The one
    /// naming function for both. It is a REAL item beside its place: under
    /// <c>courses/</c> it is part of the course, so a build and a deploy
    /// include it (Russell's ruling of 2026-11-19 and the mac's, the first
    /// review of W6's LOW 4: nothing of the teacher's stays hidden).
    /// </summary>
    internal static string VisibleName(string place, int number, bool isAPage = false)
    {
        string words = number <= 1 ? " (kept by Undo)" : $" (kept by Undo {number.ToString(System.Globalization.CultureInfo.InvariantCulture)})";
        string extension = Path.GetExtension(place);
        if (isAPage && extension.Length > 1 && extension.Length < place.Length)
            return place[..^extension.Length] + words + extension;
        return place + words;
    }

    /// <summary>
    /// The one naming loop for a folder and a page (the mac's
    /// <c>renameToAVisibleName</c>): renames the hidden item to the first
    /// visible name beside <paramref name="place"/> that nothing holds, in a
    /// rename that never replaces (<c>MoveFileEx</c> without
    /// <c>MOVEFILE_REPLACE_EXISTING</c>); a name taken is skipped, and one taken
    /// in the instant before the rename is never overwritten.
    /// <paramref name="tellingFirst"/> is told the visible name just BEFORE the
    /// rename (the intent first). True when it went.
    /// </summary>
    internal static bool RenameToAVisibleName(string hidden, string place, bool isAPage, Action<string> tellingFirst)
    {
        string folder = Path.GetDirectoryName(place)!;
        string placeName = Path.GetFileName(place);
        for (int number = 1; number <= 1000; number++)
        {
            string kept = Path.Combine(folder, VisibleName(placeName, number, isAPage));
            if (UndoLinks.Look(kept) != UndoLinks.What.Nothing) continue;
            tellingFirst(kept);
            if (RenameWithRetries(hidden, kept, replace: false, null) == 0) return true;
            if (UndoLinks.Look(kept) == UndoLinks.What.Nothing) return false;   // not taken in that instant: the rename itself failed
        }
        return false;
    }

    /// <summary>
    /// One file's swap; the refusal, or null when it went in.
    /// <paramref name="wentIn"/> says whether the page was changed (a raced
    /// edit is refused AFTER its rename, and must be reversed).
    /// </summary>
    /// <remarks>
    /// The order shrinks the window in which an edit can be lost (W2b's
    /// review, LOW 3): everything that can refuse without touching the page
    /// (containment, the re-read, read-only, the attribute copy onto the
    /// staged file) comes BEFORE the original is kept, so the keep is
    /// followed at once by the identity check and the rename. An edit in
    /// place after the keep shows in the kept link's hash (L4); an editor that
    /// saves by REPLACING the page (a new file renamed over it) gives the
    /// page a new file identity, which the identity check just before the
    /// rename sees as changed since. What remains is the few microseconds
    /// between that check and the rename, and, on a volume with no hard links
    /// (the original a COPY), every replace after the re-read: documented in
    /// documentation 12.
    /// </remarks>
    private static UndoRefusal? SwapAFile(UndoSwapTarget target, int index, string label, string? root, UndoStagedFile?[] staged,
                                          UndoStagedFile?[] originals, UndoSeams? seams, out bool wentIn)
    {
        wentIn = false;
        seams?.BeforeEachSwap?.Invoke(index, target.FullPath);
        // Inside the working folder, its links resolved, at the moment of the
        // change (the mac's second hard review of U2b, MEDIUM 2): a folder on the
        // path replaced by a junction since the check is a change since, and
        // nothing is read, kept or renamed through it.
        if (root is not null && !UndoPlaces.StaysInside(root, target.RelativePath))
            return new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath);
        UndoCurrent now = UndoCurrent.Read(target.FullPath);
        if (now is UndoCurrent.CannotReadNow cannot)
        {
            return new UndoRefusal(cannot.ErrorCode is 32 or 33 ? UndoRefusalKind.FileIsInUse : UndoRefusalKind.CannotTellNow, target.RelativePath);
        }
        if (!Holds(now, target.Expected)) return new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath);
        // A read-only page is never forced (the plan review's M4): it is a page
        // that will not take a write, the same word as a full disk, never "in use".
        if (now is UndoCurrent.Bytes && IsReadOnly(target.FullPath)) return new UndoRefusal(UndoRefusalKind.CouldNotWrite, target.RelativePath);
        bool replacing = now is UndoCurrent.Bytes;
        if (replacing && staged[index] is { } lookOnto) CopyTheLookOf(target.FullPath, lookOnto.Path);

        if (replacing)
        {
            // Kept under the first name nothing holds (-orig, then -2-orig
            // and on), created exclusively: a file under a kept name is never
            // removed, overwritten or reused, since step numbers are not
            // unique across two computers syncing one folder or after a list
            // is started again, and an earlier undo of the same step can leave
            // its kept original for good (the mac's U3c; the third review of
            // U3a, LOW 6, and the first review of U3c, LOW 4). One that appears
            // at the chosen name in that instant sends it to the next.
            // A page the step removes has no staged content holding its folder
            // in place: its original holds the handle instead, from the keep
            // to the delete, which an editor's save cannot meet (the page is
            // going). A page the step replaces is held by its staged content.
            UndoStagedFile? kept = null;
            int failure = 0;
            bool everyNameTaken = true;
            for (int number = 1; number <= KeptNames && kept is null; number++)
            {
                string originalPath = BesidePath(target.FullPath, label, number == 1 ? "orig" : number + "-orig");
                if (UndoLinks.Look(originalPath) != UndoLinks.What.Nothing) continue;
                kept = UndoStagedFile.Keep(target.FullPath, originalPath, out failure, holdItsFolder: staged[index] is null);
                if (kept is null && failure is not (80 or 183)) { everyNameTaken = false; break; }
            }
            if (kept is null)
            {
                // On a volume without hard links the original is COPIED, and a
                // copy can fail for room or permission: the same word as a
                // staging write that fails (the mac's U2a review, LOW 1). Every
                // kept name taken is could not write too, never "in use" (the
                // mac's UndoCheck couldNotWrite; W4c review 1, LOW 2).
                if (everyNameTaken) return new UndoRefusal(UndoRefusalKind.CouldNotWrite, target.RelativePath) { EveryKeptNameTaken = true };
                return new UndoRefusal(IsRoomOrPermission(failure) ? UndoRefusalKind.CouldNotWrite : UndoRefusalKind.FileIsInUse, target.RelativePath);
            }
            originals[index] = kept;
        }
        seams?.BetweenKeepingAndRenaming?.Invoke(index, target.FullPath);
        if (root is not null && !UndoPlaces.StaysInside(root, target.RelativePath))
        {
            // Its name now leads outside: nothing is renamed through it, and the
            // kept original is removed by its own handle, never through the
            // name that now leads outside (W2b's review, LOW 2).
            originals[index]?.Remove();
            originals[index] = null;
            return new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath);
        }
        if (originals[index] is { IsALink: true } link && !link.IsStillThePageAt(target.FullPath, out int openError))
        {
            // The page is no longer the file the original was kept from: an
            // editor saved it by replacing it (LOW 3). Its save is kept.
            originals[index]?.Remove();
            originals[index] = null;
            UndoRefusalKind kind = openError is 32 or 33 ? UndoRefusalKind.FileIsInUse
                : openError is 0 or 2 or 3 ? UndoRefusalKind.ChangedSince : UndoRefusalKind.CannotTellNow;
            return new UndoRefusal(kind, target.RelativePath);
        }

        if (staged[index] is { } stagedFile)
        {
            int renamed = RenameWithRetries(stagedFile.Path, target.FullPath, replace: replacing, seams);
            if (renamed != 0)
            {
                // Removed by its own handle with the read-only attribute
                // ignored: never by clearing read-only on a link to the live
                // page (W2b's review, LOW 4).
                originals[index]?.Remove();
                originals[index] = null;
                return new UndoRefusal(Classify(renamed, target.FullPath), target.RelativePath);
            }
            // It is the page now: its handle is let go, never used to remove it.
            stagedFile.LetGo();
            staged[index] = null;
        }
        else
        {
            // The step removes the file: its original is kept, then the name goes.
            try { File.Delete(target.FullPath); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                originals[index]?.Remove();
                originals[index] = null;
                return new UndoRefusal(Classify(error.HResult & 0xFFFF, target.FullPath), target.RelativePath);
            }
        }
        wentIn = true;
        // The page's rename has gone in, so the kept name alone holds its
        // earlier content (a hard link no longer shares the page's
        // attributes): it is marked Hidden now. On Windows a leading dot
        // hides nothing: measured on the PC (LENOVO, Windows 11 Pro 26200,
        // "Show hidden files" off), a dot file is listed and selected by
        // File Explorer, outside and inside OneDrive, and one marked Hidden
        // is not; so "kept beside it as the hidden file" is true only with
        // the attribute (W7a review 1, MEDIUM 1; the director's call).
        if (originals[index] is { } keptNow) HideTheKeptFile(keptNow);

        // L4: the original is the page as it was AT the rename (a hard link),
        // so an edit made in place between the re-read and the rename shows
        // here. The page then holds this step's content over that edit: the
        // step is reversed, which puts the edit back, and refused as changed.
        if (originals[index] is { } original)
        {
            // An original that cannot be read back (a OneDrive placeholder's
            // link answers "access to the cloud file is denied", measured) is
            // cannot tell: reversed, never changed since, which would clear the
            // list for a page nobody touched (ruling 4: only content that was
            // read and differs is changed).
            byte[]? kept = ReadAllShared(original.Path);
            if (kept is null) return new UndoRefusal(UndoRefusalKind.CannotTellNow, target.RelativePath);
            if (!SameBytes(kept, target.Expected)) return new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath);
        }
        return null;
    }

    /// <summary>Whether what is there now is what the check saw: the same bytes, or no file where none was expected.</summary>
    private static bool Holds(UndoCurrent now, byte[]? expected) => now switch
    {
        UndoCurrent.Absent => expected is null,
        UndoCurrent.Bytes bytes => expected is not null && bytes.Content.AsSpan().SequenceEqual(expected),
        _ => false,
    };

    private static bool SameBytes(byte[]? a, byte[]? b) => a is null ? b is null : b is not null && a.AsSpan().SequenceEqual(b);

    private static byte[]? ReadAllShared(string path)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var memory = new MemoryStream();
            stream.CopyTo(memory);
            return memory.ToArray();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>A refused rename or delete in the contract's words: a read-only page or a full disk cannot be written; anything else is a file in use.</summary>
    private static UndoRefusalKind Classify(int error, string target)
    {
        if (error is 39 or 112) return UndoRefusalKind.CouldNotWrite;
        if (error == 5)
        {
            try
            {
                if (File.Exists(target) && File.GetAttributes(target).HasFlag(FileAttributes.ReadOnly)) return UndoRefusalKind.CouldNotWrite;
            }
            catch (Exception failed) when (failed is IOException or UnauthorizedAccessException) { }
        }
        return UndoRefusalKind.FileIsInUse;
    }

    private static bool IsReadOnly(string path)
    {
        try { return File.GetAttributes(path).HasFlag(FileAttributes.ReadOnly); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
    }

    /// <summary>Whether an error number says the disk is full or the folder will not take a new file, rather than that a file is held.</summary>
    internal static bool IsRoomOrPermission(int error) => error is 5 or 19 or 39 or 112 or 1295;

    /// <summary>
    /// The page keeps its own look: its attributes (Hidden, System, Archive,
    /// not indexed) and its creation time, copied onto the staged file just
    /// before the rename (the plan review's M4; Quartz dates a page with no
    /// <c>created:</c> by its file). Best effort: a failure here leaves the
    /// staged file's own and the swap goes on.
    /// </summary>
    private static void CopyTheLookOf(string target, string staged)
    {
        try
        {
            // OneDrive's Pinned ("always keep on this device") and Unpinned
            // ("free up space") are attributes too, set by the same call, so
            // a page keeps its place in Files On Demand (W2b's review, LOW 8).
            const FileAttributes Copied = FileAttributes.Hidden | FileAttributes.System | FileAttributes.Archive
                                        | FileAttributes.NotContentIndexed | Pinned | Unpinned;
            FileAttributes attributes = File.GetAttributes(target) & Copied;
            File.SetCreationTimeUtc(staged, File.GetCreationTimeUtc(target));
            File.SetAttributes(staged, attributes == 0 ? FileAttributes.Normal : attributes);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>The rename, tried again a few times when it is refused for a holder; 0 when it went in, else the last error.</summary>
    private static int RenameWithRetries(string from, string onto, bool replace, UndoSeams? seams)
    {
        int error = 0;
        seams?.EachRename?.Invoke(from, onto);
        for (int attempt = 0; attempt < RenameTries; attempt++)
        {
            error = Rename(from, onto, replace, seams);
            if (error == 0) return 0;
            if (error is not (5 or 32 or 33)) return error;
            if (error == 5 && Classify(5, onto) == UndoRefusalKind.CouldNotWrite) return error;
            Thread.Sleep(RenameRetryPause);
        }
        return error;
    }

    /// <summary>
    /// One rename, 0 when it went in. Replacing: the POSIX-semantics rename,
    /// and <c>MoveFileEx</c> only when the volume answers 87 or 50. Not
    /// replacing (the target had no file): a move that fails when a file has
    /// appeared there since.
    /// </summary>
    internal static int Rename(string from, string onto, bool replace, UndoSeams? seams = null)
    {
        if (!replace)
        {
            return MoveFileExW(UndoLock.LongPath(from), UndoLock.LongPath(onto), MovefileWriteThrough) ? 0 : Marshal.GetLastWin32Error();
        }
        int posix = seams?.PosixRenameIsNotSupported == true ? 87 : PosixRename(from, onto);
        if (posix is not (87 or 50)) return posix;
        return MoveFileExW(UndoLock.LongPath(from), UndoLock.LongPath(onto), MovefileReplaceExisting | MovefileWriteThrough)
            ? 0 : Marshal.GetLastWin32Error();
    }

    /// <summary>
    /// <c>SetFileInformationByHandle(FileRenameInfoEx)</c> with
    /// <c>FILE_RENAME_FLAG_REPLACE_IF_EXISTS | FILE_RENAME_FLAG_POSIX_SEMANTICS</c>
    /// on a handle opened with DELETE access (the planner's P7: without DELETE
    /// it is refused 5, an implementer's trap).
    /// </summary>
    private static int PosixRename(string from, string onto)
    {
        using SafeFileHandle source = CreateFileW(UndoLock.LongPath(from), Delete | Synchronize, ShareAll, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (source.IsInvalid) return Marshal.GetLastWin32Error();
        string target = UndoLock.LongPath(onto);
        byte[] name = Encoding.Unicode.GetBytes(target);
        // FILE_RENAME_INFO on x64: Flags (4) and padding, RootDirectory (8), FileNameLength (4), FileName.
        int size = 20 + name.Length + 2;
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.Copy(new byte[size], 0, buffer, size);
            Marshal.WriteInt32(buffer, 0, (int)(RenameReplaceIfExists | RenamePosixSemantics));
            Marshal.WriteIntPtr(buffer, 8, IntPtr.Zero);
            Marshal.WriteInt32(buffer, 16, name.Length);
            Marshal.Copy(name, 0, buffer + 20, name.Length);
            return SetFileInformationByHandle(source, FileRenameInfoEx, buffer, (uint)size) ? 0 : Marshal.GetLastWin32Error();
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    /// <summary>The first word of a plain write's label (a step swapped in without the list): <c>shadow-&lt;pid&gt;-&lt;id&gt;</c>.</summary>
    internal const string PlainLabelWord = "shadow";

    private static long _plainWrites;

    /// <summary>
    /// A label for one plain write (the step's <c>WritePlainlyQuietly</c>, the
    /// door's write when the list cannot take a step), as the mac labels it:
    /// <c>shadow-&lt;pid&gt;-&lt;id&gt;</c>, so its staged files name the
    /// process that made them and a later swap can tell a gone process's
    /// leftovers from a running one's (the W7a final review's LOW 3).
    /// </summary>
    internal static string PlainLabel() =>
        $"{PlainLabelWord}-{Environment.ProcessId}-{Interlocked.Increment(ref _plainWrites)}";

    /// <summary>
    /// Removes beside <paramref name="target"/> what a plain write of a
    /// process that is no longer running left there:
    /// <c>.&lt;name&gt;.plantoir-undo-shadow-&lt;pid&gt;-&lt;id&gt;-new</c>
    /// (content that never went in, or went in and is the page's now), and a
    /// <c>-orig</c> only when it is a copy of the page (<see cref="IsACopyOfItsPlace"/>).
    /// A differing <c>-orig</c> is an only copy and stays. A running
    /// process's files, and a file that cannot be read now, stay.
    /// </summary>
    internal static void TidyPlainLeftoversOfTheGone(string target)
    {
        string? folder = Path.GetDirectoryName(target);
        if (folder is null) return;
        string prefix = "." + Path.GetFileName(target) + StagedMarker + PlainLabelWord + "-";
        List<string> entries;
        try { entries = Directory.EnumerateFiles(folder, prefix + "*").ToList(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return; }
        foreach (string entry in entries)
        {
            string rest = Path.GetFileName(entry)[prefix.Length..];
            string[] parts = rest.Split('-');
            // <pid>-<id>-new, <pid>-<id>-orig or <pid>-<id>-<n>-orig.
            if (parts.Length < 3 || !int.TryParse(parts[0], out int pid) || !long.TryParse(parts[1], out _)) continue;
            if (ProcessIsRunning(pid)) continue;
            bool staged = parts[^1] == "new" && parts.Length == 3;
            bool kept = parts[^1] == "orig";
            if (!staged && !(kept && IsACopyOfItsPlace(entry, target))) continue;
            TryDelete(entry);
        }
    }

    private static bool ProcessIsRunning(int pid)
    {
        if (pid == Environment.ProcessId) return true;
        try
        {
            using var process = System.Diagnostics.Process.GetProcessById(pid);
            return !process.HasExited;
        }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
        catch (System.ComponentModel.Win32Exception) { return true; }
    }

    /// <summary><c>.&lt;name&gt;.plantoir-undo-&lt;label&gt;-&lt;role&gt;</c> in the target's own folder: a dot file, so Obsidian and the website builder pass over it.</summary>
    internal static string BesidePath(string target, string label, string role) =>
        Path.Combine(Path.GetDirectoryName(target)!, "." + Path.GetFileName(target) + StagedMarker + label + "-" + role);

    /// <summary>A staged or kept file's path relative to the root: its name in the folder of <paramref name="page"/>, the page's own relative path.</summary>
    private static string BesideRelative(string page, string stagedFullPath)
    {
        int slash = page.LastIndexOf('/');
        string name = Path.GetFileName(stagedFullPath);
        return slash < 0 ? name : page[..slash] + "/" + name;
    }

    /// <summary>Whether a file name is one a swap for this label left.</summary>
    internal static bool IsStaged(string name, string label) =>
        name.StartsWith('.') && name.Contains(StagedMarker + label + "-", StringComparison.Ordinal);

    /// <summary>
    /// Removes everything a step's apply, undo, redo or recovery left beside
    /// the places it names (<c>undoJournal.stagedFiles</c>), in folders inside
    /// <paramref name="root"/> only. True when nothing of it is left (a file
    /// another program holds stays until a later try).
    ///
    /// <para>A FOLDER set aside (<c>-orig</c>, a tree taken out) is the
    /// teacher's own and is never deleted here (the mac's <c>tidyLeftovers</c>,
    /// W6). Whenever its place is free it is renamed back into it, whatever its
    /// listing; whether its listing is the one <paramref name="asideListings"/>
    /// records decides what recovery makes of the step, not where the folder
    /// goes. When something else holds its place it is renamed to the first
    /// free visible name beside it, <c>&lt;name&gt; (kept by Undo)</c>, then
    /// <c>(kept by Undo 2)</c> and on, so nothing of the teacher's stays hidden
    /// and nothing is merged or overwritten (Russell's ruling of 2026-11-19);
    /// that name is a real folder, which a build and a deploy include.
    /// Both renames never replace. <paramref name="onAside"/> is told BEFORE
    /// the rename (the intent first: a death between the rename and the trail
    /// line would lose it). When its place cannot be read now it is left for a
    /// later try and nothing is said. A <c>-gone</c> folder is a delete cut
    /// short and is finished here; a <c>-new</c> folder is a tree made beside
    /// its place that never went in, and goes.</para>
    /// </summary>
    /// <param name="keepingOnlyCopies">Removes a kept original FILE (<c>-orig</c>, <c>-&lt;n&gt;-orig</c>) only when it is not the
    /// only copy of what it holds: its bytes are its page's (<see cref="IsACopyOfItsPlace"/>), or exactly what the list gives for
    /// its page (<paramref name="unlessTheListHolds"/>, kept file and page in). One that differs stays beside its page under its
    /// hidden name (the mac's U3c: nothing that is an only copy is deleted).</param>
    /// <param name="keepingCopiesHolding">The hashes of kept originals' bytes the list would not take just now: a kept original
    /// holding one stays even when its page holds the same (the second review of U3c, MEDIUM).</param>
    internal static bool TidyLeftovers(long seq, IEnumerable<string> relativePaths, string root,
                                       IReadOnlyDictionary<string, string>? asideListings = null, Action<UndoAsideFolder>? onAside = null,
                                       bool keepingOnlyCopies = false, Func<string, string, bool>? unlessTheListHolds = null,
                                       IReadOnlySet<string>? keepingCopiesHolding = null)
    {
        bool allGone = true;
        var folders = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string relative in relativePaths)
        {
            string full = Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar));
            if (!UndoPlaces.StaysInside(root, relative)) continue;
            folders.Add(Path.GetDirectoryName(full)!);
        }
        string[] labels = [$"{seq}-apply", $"{seq}-undo", $"{seq}-redo"];
        foreach (string folder in folders)
        {
            List<string> entries;
            try { entries = Directory.EnumerateFileSystemEntries(folder, "." + "*" + StagedMarker + seq + "-*").ToList(); }
            catch (DirectoryNotFoundException) { continue; }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { allGone = false; continue; }
            foreach (string entry in entries)
            {
                string name = Path.GetFileName(entry);
                if (!labels.Any(label => IsStaged(name, label))) continue;
                UndoLinks.What what = UndoLinks.Look(entry);
                if (what == UndoLinks.What.Nothing) continue;
                if (what == UndoLinks.What.Folder)
                {
                    if (IsAFolderSetAside(entry))
                    {
                        if (!PutBackOrKeepVisibly(entry, name, folder, asideListings, onAside)) allGone = false;
                    }
                    else if (!UndoLinks.RemoveFolder(entry))
                    {
                        allGone = false;
                    }
                    continue;
                }
                if (keepingOnlyCopies && name.EndsWith("-orig", StringComparison.Ordinal) && PlaceOfStagedName(name) is { } placeName)
                {
                    string place = Path.Combine(folder, placeName);
                    bool theListHoldsIt = unlessTheListHolds?.Invoke(entry, place) == true;
                    if (!IsACopyOfItsPlace(entry, place) && !theListHoldsIt) continue;
                    if (HoldsAnyOf(keepingCopiesHolding, entry)) continue;
                }
                // A kept original a stopped swap left may still be a hard link
                // to the live page (it died before the rename): removed with
                // the read-only attribute ignored, never cleared, since the
                // two names share it (W2b's review, LOW 4).
                if (!UndoStagedFile.RemoveByName(entry)) allGone = false;
            }
        }
        return allGone;
    }

    /// <summary>
    /// Whether a kept original is NOT the only copy of what it holds: its
    /// place holds a file with the same bytes (the new content never went in,
    /// or it was put back). One that differs from its place, whose place is
    /// gone, or that cannot be read now, is kept (the mac's isACopyOfItsPlace).
    /// Both sides are read as recovery judges a place
    /// (<see cref="UndoCurrent.ReadWithoutFollowingALink"/>, the mac's lstat
    /// <c>UndoItem.read</c>): a link at the place is never a copy, whatever it
    /// leads to, so a kept original is never removed as a copy of a shared
    /// file a link reaches (review 2 of window D, MEDIUM 1).
    /// </summary>
    internal static bool IsACopyOfItsPlace(string kept, string place) =>
        UndoCurrent.ReadWithoutFollowingALink(kept) is UndoCurrent.Bytes keptBytes
        && UndoCurrent.ReadWithoutFollowingALink(place) is UndoCurrent.Bytes there
        && keptBytes.Content.AsSpan().SequenceEqual(there.Content);

    /// <summary>Whether a kept original's bytes hash to one of these.</summary>
    internal static bool HoldsAnyOf(IReadOnlySet<string>? shas, string kept) =>
        shas is { Count: > 0 } && UndoCurrent.Read(kept) is UndoCurrent.Bytes bytes && shas.Contains(UndoCheck.Sha(bytes.Content));

    /// <summary>A teacher's folder a stopped swap set aside: renamed back into its place when that is free, else to the first free visible name beside it. True when it went.</summary>
    private static bool PutBackOrKeepVisibly(string aside, string hiddenName, string folder,
                                             IReadOnlyDictionary<string, string>? asideListings, Action<UndoAsideFolder>? onAside)
    {
        if (PlaceOfStagedName(hiddenName) is not { } placeName) return false;
        string place = Path.Combine(folder, placeName);
        string? recorded = null;
        asideListings?.TryGetValue(Path.GetFullPath(place), out recorded);
        bool matched = recorded is not null && UndoTreeReading.Read(aside).ListingSha == recorded;
        UndoLinks.What there = UndoLinks.Look(place);
        if (there == UndoLinks.What.CannotLook) return false;   // not known to be free or taken: a later try
        if (there == UndoLinks.What.Nothing)
        {
            onAside?.Invoke(new UndoAsideFolder(place, hiddenName, aside, null, matched));
            return RenameWithRetries(aside, place, replace: false, null) == 0;
        }
        return RenameToAVisibleName(aside, place, isAPage: false,
                                    kept => onAside?.Invoke(new UndoAsideFolder(place, hiddenName, aside, kept, matched)));
    }

    /// <summary>
    /// Makes the folder a target goes in, noting each folder that was not
    /// there before, outermost first, in <paramref name="foldersMade"/>.
    /// </summary>
    private static void MakeTheFolderOf(string fullPath, List<string> foldersMade)
    {
        var missing = new List<string>();
        string? folder = Path.GetDirectoryName(fullPath);
        while (folder is not null && !Directory.Exists(folder))
        {
            missing.Add(folder);
            folder = Path.GetDirectoryName(folder);
        }
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        for (int index = missing.Count - 1; index >= 0; index--)
        {
            if (!foldersMade.Contains(missing[index], StringComparer.OrdinalIgnoreCase)) foldersMade.Add(missing[index]);
        }
    }

    /// <summary>
    /// Removes each folder a refused swap made, innermost first, only while it
    /// is empty: a folder that holds anything (a file another program put
    /// there meanwhile, or a page a swap could not take back) is kept.
    /// </summary>
    private static void RemoveTheEmptyFoldersMade(List<string> foldersMade)
    {
        for (int index = foldersMade.Count - 1; index >= 0; index--)
        {
            try
            {
                if (Directory.Exists(foldersMade[index]) && !Directory.EnumerateFileSystemEntries(foldersMade[index]).Any())
                    Directory.Delete(foldersMade[index], recursive: false);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
    }

    /// <summary>Writes a file that must not be there yet, whole, and flushes it to the disk.</summary>
    private static void WriteDurably(string path, byte[] bytes)
    {
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, bufferSize: 0);
        stream.Write(bytes, 0, bytes.Length);
        stream.Flush(flushToDisk: true);
    }

    private static bool TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                FileAttributes attributes = File.GetAttributes(path);
                if (attributes.HasFlag(FileAttributes.ReadOnly)) File.SetAttributes(path, attributes & ~FileAttributes.ReadOnly);
                File.Delete(path);
            }
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
    }

    /// <summary><c>FILE_ATTRIBUTE_PINNED</c> and <c>FILE_ATTRIBUTE_UNPINNED</c> (Files On Demand).</summary>
    internal const FileAttributes Pinned = (FileAttributes)0x00080000;
    internal const FileAttributes Unpinned = (FileAttributes)0x00100000;

    private const uint Delete = 0x00010000;
    private const uint Synchronize = 0x00100000;
    private const uint ShareAll = 0x7;
    private const uint OpenExisting = 3;
    private const int FileRenameInfoEx = 22;
    private const uint RenameReplaceIfExists = 0x1;
    private const uint RenamePosixSemantics = 0x2;
    private const uint MovefileReplaceExisting = 0x1;
    private const uint MovefileWriteThrough = 0x8;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle file, int informationClass, IntPtr information, uint size);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool MoveFileExW(string existing, string replacement, uint flags);

}

/// <summary>
/// A file a swap makes beside a page (#899 W2b; W3 made it an object, from
/// W2b's review, LOWs 2 to 4): a new content staged as <c>-new</c>, or the
/// page's original kept under its staged <c>-orig</c> name.
///
/// <para>A STAGED new content holds an attributes-only handle from the moment
/// it is written until it is renamed in or removed. That handle takes part in
/// no sharing check, so it keeps no program from the file, but Windows will
/// not rename or move a folder with a file open below it (measured: access
/// denied), so while a swap is under way the folders of its pages cannot be
/// replaced by a junction: the race the containment checks catch is made
/// impossible for those folders rather than merely detected, and a staged
/// file is removed by its handle, never through a name that leads elsewhere.
/// A KEPT original holds no handle (the file IS the page, a hard link, and
/// an open handle on it would refuse an editor's save by replace): it keeps
/// the file identity it was made with, and is removed by name only when that
/// name is still that file. The one exception is the original of a page the
/// step REMOVES, which has no staged content to hold its folder: it holds
/// the handle itself, from the keep to the delete.</para>
/// </summary>
internal sealed class UndoStagedFile
{
    private SafeFileHandle? _handle;
    private readonly (uint Volume, ulong Index)? _identity;

    /// <summary>Whether the swap set the Hidden attribute on this kept original (so it clears it again before putting it back, and never clears one the page had of its own).</summary>
    internal bool HiddenByTheSwap { get; set; }

    private UndoStagedFile(string path, bool isALink, SafeFileHandle? handle, (uint Volume, ulong Index)? identity)
    {
        Path = path;
        IsALink = isALink;
        _handle = handle;
        _identity = identity;
    }

    internal string Path { get; }

    /// <summary>A hard link to the page (the same file); false for a copy, on a volume with no links.</summary>
    internal bool IsALink { get; }

    /// <summary>A staged new content just written (not a link), its handle held.</summary>
    internal static UndoStagedFile Made(string path)
    {
        SafeFileHandle handle = CreateFileW(UndoLock.LongPath(path), ReadAttributes, ShareAll, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (!handle.IsInvalid) return new UndoStagedFile(path, false, handle, UndoFileIdentity.Of(handle));
        handle.Dispose();
        return new UndoStagedFile(path, false, null, null);
    }

    /// <summary>
    /// Keeps <paramref name="page"/> as <paramref name="keptPath"/>: a hard
    /// link where the volume has them, a copy where it does not. Null when it
    /// could not be kept, with the error number of the last try.
    /// </summary>
    internal static UndoStagedFile? Keep(string page, string keptPath, out int failure, bool holdItsFolder = false)
    {
        failure = 0;
        bool linked = CreateHardLinkW(UndoLock.LongPath(keptPath), UndoLock.LongPath(page), IntPtr.Zero);
        if (!linked)
        {
            // Something already holds the name: never a copy over it, and
            // never a reason to remove it (the mac's keepByCopying, U3c). The
            // copy itself is exclusive, so a file that appears in between is
            // never overwritten either.
            int linkFailure = Marshal.GetLastWin32Error();
            if (linkFailure is 80 or 183)
            {
                failure = linkFailure;
                return null;
            }
            try { File.Copy(page, keptPath, overwrite: false); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                failure = error is UnauthorizedAccessException ? 5 : error.HResult & 0xFFFF;
                return null;
            }
        }
        SafeFileHandle handle = CreateFileW(UndoLock.LongPath(keptPath), ReadAttributes, ShareAll, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (handle.IsInvalid)
        {
            handle.Dispose();
            return new UndoStagedFile(keptPath, linked, null, null);
        }
        (uint, ulong)? identity = UndoFileIdentity.Of(handle);
        if (holdItsFolder) return new UndoStagedFile(keptPath, linked, handle, identity);
        handle.Dispose();
        return new UndoStagedFile(keptPath, linked, null, identity);
    }

    /// <summary>
    /// Whether the file at <paramref name="page"/> is still the one this link
    /// was made to (the same volume and file index): false when an editor has
    /// saved by REPLACING the page since the keep (W2b's review, LOW 3). True
    /// when the identity is not known (nothing to compare: the content checks
    /// still stand). <paramref name="openError"/> is the error when the page
    /// could not be opened even for its attributes.
    /// </summary>
    internal bool IsStillThePageAt(string page, out int openError)
    {
        openError = 0;
        if (_identity is null) return true;
        using SafeFileHandle now = CreateFileW(UndoLock.LongPath(page), ReadAttributes, ShareAll, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (now.IsInvalid)
        {
            openError = Marshal.GetLastWin32Error();
            return false;
        }
        return UndoFileIdentity.Of(now) == _identity;
    }

    /// <summary>Removes a staged file by its name, its attributes untouched (the read-only bit ignored, never cleared). True when it is gone.</summary>
    internal static bool RemoveByName(string path)
    {
        using SafeFileHandle byName = CreateFileW(UndoLock.LongPath(path), Delete | ReadAttributes | Synchronize, ShareAll, IntPtr.Zero,
                                                  OpenExisting, OpenReparsePoint, IntPtr.Zero);
        if (byName.IsInvalid) return Marshal.GetLastWin32Error() is 2 or 3;
        return DeleteByHandle(byName);
    }

    /// <summary>
    /// The same file once the folder it is in has been renamed: at
    /// <paramref name="path"/> now, its identity kept, its handle let go (the
    /// handle was let go before the folder could move). Removed by its name
    /// and identity from then on (#899 W8-2b).
    /// </summary>
    internal UndoStagedFile MovedTo(string path)
    {
        LetGo();
        return new UndoStagedFile(path, IsALink, null, _identity) { HiddenByTheSwap = HiddenByTheSwap };
    }

    /// <summary>Closes the handle without removing anything (the kept file is put back in its place, or left for recovery).</summary>
    internal void LetGo()
    {
        _handle?.Dispose();
        _handle = null;
    }

    /// <summary>
    /// Removes the file. A staged content by its own handle, reopened for
    /// delete; a kept original (or a staged file whose handle cannot be
    /// reopened) by its name, opened for delete without following a link and
    /// removed only if it is still the file that was made, so a name that now
    /// leads elsewhere removes nothing (LOW 2). Always with the read-only
    /// attribute IGNORED rather than cleared, because a hard link shares its
    /// attributes with the live page and clearing it there would change the
    /// teacher's page (LOW 4). True when it is gone.
    /// </summary>
    internal bool Remove()
    {
        try
        {
            if (_handle is not null)
            {
                using SafeFileHandle reopened = ReOpenFile(_handle, Delete | Synchronize, ShareAll, 0);
                if (!reopened.IsInvalid) return DeleteByHandle(reopened);
            }
            if (_identity is null)
            {
                // Nothing to recognise it by: removed by name only while the
                // name is inside a folder that has not changed since (the
                // caller's containment check), the old way.
                try { File.Delete(Path); return !File.Exists(Path); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
            }
            using SafeFileHandle byName = CreateFileW(UndoLock.LongPath(Path), Delete | ReadAttributes | Synchronize, ShareAll, IntPtr.Zero,
                                                      OpenExisting, OpenReparsePoint, IntPtr.Zero);
            if (byName.IsInvalid) return Marshal.GetLastWin32Error() is 2 or 3;
            if (UndoFileIdentity.Of(byName) != _identity) return false;
            return DeleteByHandle(byName);
        }
        finally
        {
            LetGo();
        }
    }

    /// <summary>
    /// <c>FileDispositionInfoEx</c> with DELETE, POSIX semantics and IGNORE
    /// READONLY: the name goes at once, the file's attributes untouched.
    /// Where the volume does not know it (87, FAT), the plain disposition,
    /// which leaves a read-only file where it is rather than change it.
    /// </summary>
    private static bool DeleteByHandle(SafeFileHandle handle)
    {
        IntPtr flags = Marshal.AllocHGlobal(4);
        try
        {
            Marshal.WriteInt32(flags, (int)(DispositionDelete | DispositionPosix | DispositionIgnoreReadOnly));
            if (SetFileInformationByHandle(handle, FileDispositionInfoEx, flags, 4)) return true;
            if (Marshal.GetLastWin32Error() is not (87 or 50)) return false;
            Marshal.WriteInt32(flags, 1);
            return SetFileInformationByHandle(handle, FileDispositionInfo, flags, 1);
        }
        finally
        {
            Marshal.FreeHGlobal(flags);
        }
    }

    private const uint ReadAttributes = 0x00000080;
    private const uint Delete = 0x00010000;
    private const uint Synchronize = 0x00100000;
    private const uint ShareAll = 0x7;
    private const uint OpenExisting = 3;
    private const uint OpenReparsePoint = 0x00200000;
    private const int FileDispositionInfo = 4;
    private const int FileDispositionInfoEx = 21;
    private const uint DispositionDelete = 0x1;
    private const uint DispositionPosix = 0x2;
    private const uint DispositionIgnoreReadOnly = 0x10;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern SafeFileHandle ReOpenFile(SafeFileHandle original, uint access, uint share, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle file, int informationClass, IntPtr information, uint size);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateHardLinkW(string newName, string existing, IntPtr security);
}

/// <summary>
/// A teacher's folder recovery found set aside by a stopped swap, as it is
/// about to be put back (<see cref="KeptAs"/> null) or kept under a visible
/// name beside its place because something else holds that place. Whether
/// its listing was the one the step recorded (<see cref="Matched"/>).
/// </summary>
internal sealed record UndoAsideFolder(string Place, string HiddenName, string FoundAt, string? KeptAs, bool Matched)
{
    internal bool PutBack => KeptAs is null;
}

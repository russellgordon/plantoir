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
internal sealed record UndoSwapTarget(string FullPath, string RelativePath, byte[]? Expected, byte[]? Replacement);

/// <summary>How a swap went.</summary>
internal abstract record UndoSwapResult
{
    private UndoSwapResult() { }

    internal sealed record Swapped : UndoSwapResult;
    internal sealed record Refused(UndoRefusal Refusal) : UndoSwapResult;
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
    /// <c>beforeApplied</c>, <c>beforeUndone</c>, <c>beforeRedone</c>): true stops the
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

    /// <summary>The POSIX-semantics rename answers "not supported" (87), as on a network share, so every swap takes the fallback (M5).</summary>
    internal bool PosixRenameIsNotSupported { get; init; }

    /// <summary>Called once a step's undo or redo has checked its ops and before it answers (the stack case <c>undoWhileAStepBegins</c>).</summary>
    internal Action? AfterTheCheck { get; init; }

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

    /// <summary>How many times a refused rename is tried in all, and how long apart.</summary>
    private const int RenameTries = 6;
    private static readonly TimeSpan RenameRetryPause = TimeSpan.FromMilliseconds(10);

    internal static UndoSwapResult Swap(IReadOnlyList<UndoSwapTarget> targets, string label, string? root, UndoSeams? seams = null)
    {
        int count = targets.Count;
        var staged = new string?[count];
        var originals = new string?[count];
        int swapsMade = 0;

        void Tidy()
        {
            for (int index = 0; index < count; index++)
            {
                if (staged[index] is { } stagedPath) TryDelete(stagedPath);
                if (originals[index] is { } originalPath) TryDelete(originalPath);
                staged[index] = null;
                originals[index] = null;
            }
        }

        void Reverse()
        {
            for (int index = swapsMade - 1; index >= 0; index--)
            {
                UndoSwapTarget target = targets[index];
                if (originals[index] is { } original)
                {
                    // Put back. Either way it is no longer the tidy's to remove:
                    // put back, it is the page again; not put back, it is the
                    // page's old content under its staged name, left for
                    // recovery (W3) and never deleted.
                    RenameWithRetries(original, target.FullPath, replace: true, seams);
                    originals[index] = null;
                }
                else
                {
                    // There was no file: the one the swap made goes.
                    TryDelete(target.FullPath);
                }
            }
        }

        // 1. Stage every new content beside its target.
        for (int index = 0; index < count; index++)
        {
            UndoSwapTarget target = targets[index];
            if (root is not null && !UndoPlaces.StaysInside(root, target.RelativePath))
            {
                Tidy();
                return new UndoSwapResult.Refused(new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath));
            }
            if (target.Replacement is not { } replacement) continue;
            string stagedPath = BesidePath(target.FullPath, label, "new");
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(target.FullPath)!);
                TryDelete(stagedPath);
                if (seams?.StagingWriteFailsAt?.Invoke(index) == true)
                {
                    // As a full disk does: the exclusive create makes the file,
                    // then writing into it fails.
                    using (new FileStream(stagedPath, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { }
                    throw new IOException("There is not enough space on the disk.", unchecked((int)0x80070070));
                }
                WriteDurably(stagedPath, replacement);
                staged[index] = stagedPath;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // The file the exclusive create made is this swap's own: it goes
                // with every other. Staging writes a NEW file, which no other
                // program can be holding, so this is never fileIsInUse.
                TryDelete(stagedPath);
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
            bool wentIn = false;
            refusal = SwapAFile(target, index, label, root, staged, originals, seams, out wentIn);
            if (wentIn) swapsMade++;
            if (refusal is not null)
            {
                Reverse();
                Tidy();
                return new UndoSwapResult.Refused(refusal);
            }
        }

        // 3. Every swap went in: the kept originals are no longer needed.
        Tidy();
        return new UndoSwapResult.Swapped();
    }

    /// <summary>One file's swap; the refusal, or null when it went in. <paramref name="wentIn"/> says whether the page was changed (a raced edit is refused AFTER its rename, and must be reversed).</summary>
    private static UndoRefusal? SwapAFile(UndoSwapTarget target, int index, string label, string? root, string?[] staged,
                                          string?[] originals, UndoSeams? seams, out bool wentIn)
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

        if (now is UndoCurrent.Bytes)
        {
            string originalPath = BesidePath(target.FullPath, label, "orig");
            TryDelete(originalPath);
            int? keptFailure = Keep(target.FullPath, originalPath);
            if (keptFailure is { } failure)
            {
                TryDelete(originalPath);
                // On a volume without hard links the original is COPIED, and a
                // copy can fail for room or permission: the same word as a
                // staging write that fails (the mac's U2a review, LOW 1).
                return new UndoRefusal(IsRoomOrPermission(failure) ? UndoRefusalKind.CouldNotWrite : UndoRefusalKind.FileIsInUse, target.RelativePath);
            }
            originals[index] = originalPath;
        }
        seams?.BetweenKeepingAndRenaming?.Invoke(index, target.FullPath);
        if (root is not null && !UndoPlaces.StaysInside(root, target.RelativePath))
        {
            // Its name now leads outside: nothing is removed through it either.
            // The kept original stays where it was made, for recovery (W3).
            originals[index] = null;
            return new UndoRefusal(UndoRefusalKind.ChangedSince, target.RelativePath);
        }

        if (staged[index] is { } stagedPath)
        {
            bool replacing = now is UndoCurrent.Bytes;
            if (replacing) CopyTheLookOf(target.FullPath, stagedPath);
            int renamed = RenameWithRetries(stagedPath, target.FullPath, replace: replacing, seams);
            if (renamed != 0)
            {
                if (originals[index] is { } kept) { TryDelete(kept); originals[index] = null; }
                return new UndoRefusal(Classify(renamed, target.FullPath), target.RelativePath);
            }
            staged[index] = null;
        }
        else
        {
            // The step removes the file: its original is kept, then the name goes.
            try { File.Delete(target.FullPath); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                if (originals[index] is { } kept) { TryDelete(kept); originals[index] = null; }
                return new UndoRefusal(Classify(error.HResult & 0xFFFF, target.FullPath), target.RelativePath);
            }
        }
        wentIn = true;

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
            byte[]? kept = ReadAllShared(original);
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
            const FileAttributes Copied = FileAttributes.Hidden | FileAttributes.System | FileAttributes.Archive | FileAttributes.NotContentIndexed;
            FileAttributes attributes = File.GetAttributes(target) & Copied;
            File.SetCreationTimeUtc(staged, File.GetCreationTimeUtc(target));
            File.SetAttributes(staged, attributes == 0 ? FileAttributes.Normal : attributes);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>
    /// Keeps the original under a second name: a hard link where the volume
    /// has them, a copy where it does not. Null when it was kept, otherwise
    /// the error number of the last try.
    /// </summary>
    internal static int? Keep(string path, string keptPath)
    {
        if (CreateHardLinkW(UndoLock.LongPath(keptPath), UndoLock.LongPath(path), IntPtr.Zero)) return null;
        try
        {
            File.Copy(path, keptPath, overwrite: false);
            return null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return error is UnauthorizedAccessException ? 5 : error.HResult & 0xFFFF;
        }
    }

    /// <summary>The rename, tried again a few times when it is refused for a holder; 0 when it went in, else the last error.</summary>
    private static int RenameWithRetries(string from, string onto, bool replace, UndoSeams? seams)
    {
        int error = 0;
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

    /// <summary><c>.&lt;name&gt;.plantoir-undo-&lt;label&gt;-&lt;role&gt;</c> in the target's own folder: a dot file, so Obsidian and the website builder pass over it.</summary>
    internal static string BesidePath(string target, string label, string role) =>
        Path.Combine(Path.GetDirectoryName(target)!, "." + Path.GetFileName(target) + StagedMarker + label + "-" + role);

    /// <summary>Whether a file name is one a swap for this label left.</summary>
    internal static bool IsStaged(string name, string label) =>
        name.StartsWith('.') && name.Contains(StagedMarker + label + "-", StringComparison.Ordinal);

    /// <summary>
    /// Removes every file a step's apply, undo or redo left beside the files
    /// it names (<c>undoJournal.stagedFiles</c>), in folders inside
    /// <paramref name="root"/> only. Folders under a staged name are a later
    /// kind's (U2's <c>-orig</c> folders, W6) and are never touched here. True
    /// when none is left.
    /// </summary>
    internal static bool TidyLeftovers(long seq, IEnumerable<string> relativePaths, string root)
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
            IEnumerable<string> files;
            try { files = Directory.EnumerateFiles(folder, "." + "*" + StagedMarker + seq + "-*").ToList(); }
            catch (DirectoryNotFoundException) { continue; }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { allGone = false; continue; }
            foreach (string file in files)
            {
                string name = Path.GetFileName(file);
                if (!labels.Any(label => IsStaged(name, label))) continue;
                if (!TryDelete(file)) allGone = false;
            }
        }
        return allGone;
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

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateHardLinkW(string newName, string existing, IntPtr security);
}

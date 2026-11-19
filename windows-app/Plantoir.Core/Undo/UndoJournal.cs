using System.Globalization;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;

namespace Plantoir.Core.Undo;

/// <summary>
/// A file of the list that is there and cannot be opened or read (a failing
/// disk, a permission, too many open files): the list is unreadable for this
/// attempt (<c>undo.rule.stagedThenSwapped</c>, the mac's U2a). Never passed
/// over as if the file were gone, never content missing.
/// </summary>
internal sealed class UndoListUnreadableException(string message, Exception? inner = null) : IOException(message, inner);

/// <summary>What one read of the journal came to.</summary>
internal sealed record UndoReading
{
    /// <summary>The list as last read in full. When <see cref="IsFresh"/> is false, the last state read before this one.</summary>
    internal required UndoFolded Folded { get; init; }

    /// <summary>False when a segment could not be read this time (a sharing violation past the retry): never "unreadable", never reset.</summary>
    internal required bool IsFresh { get; init; }

    /// <summary>Bytes after the last line feed of the newest segment: a line still being written, or torn by a crash. Never counted.</summary>
    internal long TornBytes { get; init; }

    /// <summary>The segment numbers found on the disk, oldest first.</summary>
    internal IReadOnlyList<int> SegmentsOnDisk { get; init; } = [];
}

/// <summary>
/// One computer's list of changes for Undo and Redo, as a READER of it
/// (#899 piece W1). Nothing here writes a journal, takes the lock or changes a
/// page: the door that does is W2.
///
/// <para><b>An instance, never a static</b> (the plan review's H1). The folder,
/// the clock, the liveness check, the reach check and the switch are all
/// passed in. Only the app's start-up will ever hand it the real
/// <c>undo\</c> folder of the app's own state folder (<c>AppDataRoot</c>, W4), so a test makes its own folder
/// and its own clock, two test classes running at once cannot share a journal,
/// and the contract's <c>clock:+n</c> is something a test can say.</para>
///
/// <para><b>Reading.</b> Every segment <c>journal-NNNNNN.jsonl</c> is opened to
/// READ with <c>FileShare.ReadWrite | FileShare.Delete</c> (<c>rule.readers</c>,
/// the Windows director's fact 2: readers that share delete failed 0 of
/// 847,695 times beside 6,000 replaces). A sharing violation is retried for a
/// bounded time, then the reading is the LAST state read, marked not fresh:
/// never "the journal is unreadable", never a reset. Lines are split at line
/// feeds only; a carriage return before one is JSON white space and changes
/// nothing; bytes after the last line feed are a torn or still-written line
/// and are not counted.</para>
/// </summary>
internal sealed class UndoJournal
{
    private static readonly Regex SegmentName = new(@"^journal-(\d{6})\.jsonl$", RegexOptions.CultureInvariant);

    private readonly TimeSpan _readRetry;
    private readonly Func<string, Stream>? _open;
    private UndoFolded _lastRead = new();

    /// <param name="directory">The list's own folder (<c>undo\</c>).</param>
    /// <param name="clock">The clock the limits are judged by.</param>
    /// <param name="isAlive">Whether the process a step in flight names is still running.</param>
    /// <param name="canReach">Whether a step's working folder can be reached (ruling 10; U7 widens it to the recent folders).</param>
    /// <param name="isLive">The switch (<c>undoJournalIsLive</c>): off until W11a. Read here so nothing reads a static for it.</param>
    /// <param name="readRetry">How long a sharing violation on a segment is retried (two seconds in the app).</param>
    /// <param name="open">A seam for tests: opens a file of the list to read (a disk or permission failure); the real open by default.</param>
    internal UndoJournal(string directory, TimeProvider clock, Func<UndoProcess?, bool> isAlive,
                         Func<UndoStep, bool> canReach, bool isLive, TimeSpan? readRetry = null,
                         Func<string, Stream>? open = null)
    {
        _open = open;
        Folder = directory;
        Clock = clock;
        IsAlive = isAlive;
        CanReach = canReach;
        IsLive = isLive;
        _readRetry = readRetry ?? TimeSpan.FromSeconds(2);
    }

    internal string Folder { get; }
    internal TimeProvider Clock { get; }
    internal Func<UndoProcess?, bool> IsAlive { get; }
    internal Func<UndoStep, bool> CanReach { get; }
    internal bool IsLive { get; }

    internal DateTimeOffset Now => Clock.GetUtcNow();

    /// <summary>
    /// The segments on the disk, oldest first. A folder that is not there is
    /// no segments; one that is there and cannot be listed throws
    /// <see cref="UndoListUnreadableException"/>, never an empty list.
    /// </summary>
    internal IReadOnlyList<(int Number, string Path)> Segments()
    {
        var found = new List<(int, string)>();
        if (!Directory.Exists(Folder)) return found;
        try
        {
            foreach (string path in Directory.EnumerateFiles(Folder, "journal-*.jsonl"))
            {
                Match match = SegmentName.Match(Path.GetFileName(path));
                if (match.Success) found.Add((int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture), path));
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UndoListUnreadableException("The list's folder could not be listed.", error);
        }
        found.Sort((a, b) => a.Item1.CompareTo(b.Item1));
        return found;
    }

    /// <summary>
    /// Reads and folds the whole journal. A file of the list that is there
    /// and cannot be read, a folder that cannot be listed, or a NEWEST segment
    /// gone since the listing makes a reading that is not fresh (the mac's
    /// U2a read rule: never an empty or shorter list); only an older segment
    /// pruned since the listing is passed over.
    /// </summary>
    internal UndoReading Read()
    {
        IReadOnlyList<(int Number, string Path)> segments;
        try { segments = Segments(); }
        catch (UndoListUnreadableException)
        {
            return new UndoReading { Folded = _lastRead, IsFresh = false };
        }
        var folded = new UndoFolded();
        long place = 0;
        long torn = 0;
        for (int index = 0; index < segments.Count; index++)
        {
            (int number, string path) = segments[index];
            byte[]? bytes = ReadShared(path, goneIsEmpty: index < segments.Count - 1);
            if (bytes is null)
                return new UndoReading { Folded = _lastRead, IsFresh = false, SegmentsOnDisk = segments.Select(s => s.Number).ToList() };
            int start = 0;
            for (int index = 0; index < bytes.Length; index++)
            {
                if (bytes[index] != (byte)'\n') continue;
                UndoFold.Apply(folded, UndoFormat.Parse(bytes.AsSpan(start, index - start), number, place++));
                start = index + 1;
            }
            torn = bytes.Length - start;
        }
        _lastRead = folded;
        return new UndoReading { Folded = folded, IsFresh = true, TornBytes = torn, SegmentsOnDisk = segments.Select(s => s.Number).ToList() };
    }

    /// <summary>The list as offered now, by this journal's own clock, liveness and reach.</summary>
    internal UndoOffered Offer(UndoFolded folded) => UndoLimits.Offer(folded, Now, IsAlive, CanReach);

    /// <summary>
    /// The list as offered now, from one reading. A reading that is not fresh
    /// offers neither Undo nor Redo (greyed, plain "Undo", ruling 10): its fold
    /// is the last state read, and on a first read that is an empty list that
    /// would say "Nothing to undo" (the W1 review's M2).
    /// </summary>
    internal UndoOffered Offer(UndoReading reading)
    {
        UndoOffered offered = Offer(reading.Folded);
        if (reading.IsFresh) return offered;
        var greyed = new UndoAnswer(UndoAnswerKind.NotAvailable);
        return offered with { Undo = greyed, Redo = greyed };
    }

    /// <summary>What pruning would write now (a decision only), from one reading.</summary>
    internal IReadOnlyList<UndoPruneAction> Pruning(UndoReading reading) => UndoPruning.Decide(reading, Now, IsAlive);

    /// <summary>What may be deleted now (a decision only), from one reading and the blobs on the disk now.</summary>
    internal UndoDeletion Deletable(UndoReading reading) => UndoPruning.Deletable(reading, BlobsOnDisk(), Now);

    /// <summary>The blob names in <c>content\</c>, for the deletion decision.</summary>
    internal IReadOnlyList<string> BlobsOnDisk()
    {
        string content = Path.Combine(Folder, "content");
        var names = new List<string>();
        if (!Directory.Exists(content)) return names;
        try
        {
            foreach (string folder in Directory.EnumerateDirectories(content))
            {
                foreach (string file in Directory.EnumerateFiles(folder))
                {
                    string name = Path.GetFileName(file);
                    if (UndoFormat.IsBlobName(name)) names.Add(name);
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UndoListUnreadableException("The list's content folder could not be listed.", error);
        }
        return names;
    }

    /// <summary>
    /// A blob's bytes, or null when it is gone or its bytes do not hash to its
    /// name (treated as missing). One that is there and cannot be read throws
    /// <see cref="UndoListUnreadableException"/>: never content missing, which
    /// clears the list (the mac's U2a read rule).
    /// </summary>
    internal byte[]? Blob(string name)
    {
        if (!UndoFormat.IsBlobName(name)) return null;
        string path = Path.Combine(Folder, "content", name[..2], name);
        byte[]? bytes = ReadShared(path, goneIsEmpty: false, goneIsNull: true, out bool cannotRead);
        if (cannotRead) throw new UndoListUnreadableException("A content file of the list could not be read.");
        return bytes is not null && string.Equals(UndoCheck.Sha(bytes), name, StringComparison.Ordinal) ? bytes : null;
    }

    /// <summary>A segment's bytes: empty when it is gone and <paramref name="goneIsEmpty"/> (an older segment pruned since the listing), otherwise null for anything that is not a read.</summary>
    private byte[]? ReadShared(string path, bool goneIsEmpty) => ReadShared(path, goneIsEmpty, goneIsNull: false, out _);

    private byte[]? ReadShared(string path, bool goneIsEmpty, bool goneIsNull, out bool cannotRead)
    {
        cannotRead = false;
        long deadline = Environment.TickCount64 + (long)_readRetry.TotalMilliseconds;
        while (true)
        {
            try
            {
                using Stream stream = _open is null
                    ? new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)
                    : _open(path);
                using var memory = new MemoryStream();
                stream.CopyTo(memory);
                return memory.ToArray();
            }
            catch (Exception gone) when (gone is FileNotFoundException or DirectoryNotFoundException)
            {
                // Deleted from the oldest end between the listing and the read:
                // passed over only for an older segment, never the newest.
                if (goneIsEmpty) return [];
                if (goneIsNull) return null;
                cannotRead = true;
                return null;
            }
            catch (IOException exception) when ((exception.HResult & 0xFFFF) is 32 or 33)
            {
                if (Environment.TickCount64 >= deadline) { cannotRead = true; return null; }
                Thread.Sleep(20);
            }
            catch (IOException) { cannotRead = true; return null; }
            catch (UnauthorizedAccessException) { cannotRead = true; return null; }
        }
    }
}

/// <summary>The checks the app's start-up will hand a journal (W4 and W11a); nothing calls them yet.</summary>
internal static class UndoJournalChecks
{
    /// <summary>
    /// Whether a step's process is still running, by the liveness rule the
    /// work leases already use (<c>WorkLease.OwnerIsAlive</c>: the id, then the
    /// process table's name and start time). A step with no process it can
    /// read is judged gone, so content-based recovery can settle it and it is
    /// never left in flight for ever.
    /// </summary>
    /// <summary>
    /// Whether recovery (W3), which writes pages, may settle a step in flight
    /// for its process being gone. A step whose process this version cannot
    /// identify (no <c>process</c>, or one whose shape it does not know) is
    /// judged gone for the offer and for pruning, so nothing is in flight for
    /// ever, but NEVER settled by recovery: a live process of another version
    /// may still be swapping its files outside the lock (the W1 review's M3,
    /// proposed to the mac as a <c>recoveryCases</c> row). Pruning closes it
    /// once it is past the limits.
    /// </summary>
    internal static bool RecoveryMaySettle(UndoProcess? process) => process is not null && !ProcessIsAlive(process);

    internal static bool ProcessIsAlive(UndoProcess? process) =>
        process is not null && process.Pid is > 0 and <= int.MaxValue
        && WorkLease.OwnerIsAlive((int)process.Pid, process.Name, process.Started, "undo");

    /// <summary>
    /// Whether a step's working folder can be reached at the path it had:
    /// the folder is there and its <c>folder-id</c> is the step's. A step with
    /// no working folder (a preference, U4) is always reachable. U7 adds the
    /// recent working folders as the second place to look (<c>laterPieces.U7</c>);
    /// a folder whose identifier cannot be read right now is not reachable now,
    /// which greys Undo (ruling 10) and changes nothing on the list.
    /// </summary>
    internal static bool FolderIsReachable(UndoStep step, TimeProvider clock)
    {
        if (step.WorkingFolder is not { } folder) return true;
        if (string.IsNullOrEmpty(folder.PathAtTheTime) || !Directory.Exists(folder.PathAtTheTime)) return false;
        if (folder.Id is null) return true;
        var file = new FolderIdentityFile(Path.Combine(folder.PathAtTheTime, "courses", ".internal", "folder-id"), clock);
        FolderIdentityFile.Answer answer = file.Read();
        return answer.Outcome == FolderIdentityFile.Outcome.Identifier
            && string.Equals(answer.Identifier, folder.Id.ToLowerInvariant(), StringComparison.Ordinal);
    }
}

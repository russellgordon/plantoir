using System.Globalization;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;

namespace Plantoir.Core.Undo;

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
/// <c>%LOCALAPPDATA%\Plantoir\undo\</c> (W4), so a test makes its own folder
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
    private UndoFolded _lastRead = new();

    /// <param name="directory">The list's own folder (<c>undo\</c>).</param>
    /// <param name="clock">The clock the limits are judged by.</param>
    /// <param name="isAlive">Whether the process a step in flight names is still running.</param>
    /// <param name="canReach">Whether a step's working folder can be reached (ruling 10; U7 widens it to the recent folders).</param>
    /// <param name="isLive">The switch (<c>undoJournalIsLive</c>): off until W11a. Read here so nothing reads a static for it.</param>
    /// <param name="readRetry">How long a sharing violation on a segment is retried (two seconds in the app).</param>
    internal UndoJournal(string directory, TimeProvider clock, Func<UndoProcess?, bool> isAlive,
                         Func<UndoStep, bool> canReach, bool isLive, TimeSpan? readRetry = null)
    {
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

    /// <summary>The segments on the disk, oldest first.</summary>
    internal IReadOnlyList<(int Number, string Path)> Segments()
    {
        var found = new List<(int, string)>();
        if (!Directory.Exists(Folder)) return found;
        foreach (string path in Directory.EnumerateFiles(Folder, "journal-*.jsonl"))
        {
            Match match = SegmentName.Match(Path.GetFileName(path));
            if (match.Success) found.Add((int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture), path));
        }
        found.Sort((a, b) => a.Item1.CompareTo(b.Item1));
        return found;
    }

    /// <summary>Reads and folds the whole journal.</summary>
    internal UndoReading Read()
    {
        var segments = Segments();
        var folded = new UndoFolded();
        long place = 0;
        long torn = 0;
        foreach ((int number, string path) in segments)
        {
            byte[]? bytes = ReadShared(path);
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

    /// <summary>What pruning would write now (a decision only).</summary>
    internal IReadOnlyList<UndoPruneAction> Pruning(UndoFolded folded) => UndoPruning.Decide(folded, Now, IsAlive);

    /// <summary>The blob names in <c>content\</c>, for the deletion decision.</summary>
    internal IReadOnlyList<string> BlobsOnDisk()
    {
        string content = Path.Combine(Folder, "content");
        var names = new List<string>();
        if (!Directory.Exists(content)) return names;
        foreach (string folder in Directory.EnumerateDirectories(content))
        {
            foreach (string file in Directory.EnumerateFiles(folder))
            {
                string name = Path.GetFileName(file);
                if (UndoFormat.IsBlobName(name)) names.Add(name);
            }
        }
        return names;
    }

    /// <summary>A blob's bytes, or null when it is missing or its bytes do not hash to its name (treated as missing).</summary>
    internal byte[]? Blob(string name)
    {
        if (!UndoFormat.IsBlobName(name)) return null;
        string path = Path.Combine(Folder, "content", name[..2], name);
        byte[]? bytes = ReadShared(path);
        return bytes is not null && string.Equals(UndoCheck.Sha(bytes), name, StringComparison.Ordinal) ? bytes : null;
    }

    private byte[]? ReadShared(string path)
    {
        long deadline = Environment.TickCount64 + (long)_readRetry.TotalMilliseconds;
        while (true)
        {
            try
            {
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                using var memory = new MemoryStream();
                stream.CopyTo(memory);
                return memory.ToArray();
            }
            catch (FileNotFoundException) { return []; }      // deleted from the oldest end between the listing and the read
            catch (DirectoryNotFoundException) { return null; }
            catch (IOException exception) when ((exception.HResult & 0xFFFF) is 32 or 33)
            {
                if (Environment.TickCount64 >= deadline) return null;
                Thread.Sleep(20);
            }
            catch (IOException) { return null; }
            catch (UnauthorizedAccessException) { return null; }
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

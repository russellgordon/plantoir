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
/// One computer's list of changes for Undo and Redo: its reader (#899 piece
/// W1) and, since W2a, its store: the one lock (<see cref="UndoLock"/>,
/// <see cref="WithLock{T}"/>), the append (<see cref="UndoJournalWriter"/>),
/// blobs, reading on, and pruning carried out (<see cref="Prune"/>). Nothing
/// here changes a page: the staged swap and the door that does are W2b's.
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

    /// <summary>The live wait for the lock (<c>rule.oneLock</c>: 2 seconds).</summary>
    internal static readonly TimeSpan LiveWait = TimeSpan.FromSeconds(2);

    /// <summary>The shadow wait for the lock (<c>rule.oneLock</c>: 50 milliseconds).</summary>
    internal static readonly TimeSpan ShadowWait = TimeSpan.FromMilliseconds(50);

    /// <summary>A new segment starts once the newest is at or past this (<c>undoJournal.files</c>: 4 MiB).</summary>
    internal const long SegmentBytesInTheApp = 4L * 1024 * 1024;

    private readonly TimeSpan _readRetry;
    private readonly Func<string, Stream>? _open;
    private readonly object _readGuard = new();
    private UndoFolded _lastRead = new();
    private List<SegmentRead> _cache = [];

    /// <param name="directory">The list's own folder (<c>undo\</c>).</param>
    /// <param name="clock">The clock the limits are judged by.</param>
    /// <param name="isAlive">Whether the process a step in flight names is still running.</param>
    /// <param name="canReach">Whether a step's working folder can be reached (ruling 10; U7 widens it to the recent folders).</param>
    /// <param name="isLive">The switch (<c>undoJournalIsLive</c>): off until W11a. Read here so nothing reads a static for it.</param>
    /// <param name="readRetry">How long a sharing violation on a segment is retried (two seconds in the app).</param>
    /// <param name="open">A seam for tests: opens a file of the list to read (a disk or permission failure); the real open by default.
    /// A journal given one always reads whole.</param>
    /// <param name="memory">What this PROCESS remembers about the list (shadow try-once, pending closings): the
    /// one the app's start-up makes for the process (W4); a journal of its own when none is given.</param>
    /// <param name="segmentBytes">Where a new segment starts: 4 MiB in the app; a test's seam.</param>
    internal UndoJournal(string directory, TimeProvider clock, Func<UndoProcess?, bool> isAlive,
                         Func<UndoStep, bool> canReach, bool isLive, TimeSpan? readRetry = null,
                         Func<string, Stream>? open = null, UndoProcessMemory? memory = null,
                         long segmentBytes = SegmentBytesInTheApp)
    {
        _open = open;
        Memory = memory ?? new UndoProcessMemory();
        SegmentBytes = segmentBytes;
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
    internal UndoProcessMemory Memory { get; }
    internal long SegmentBytes { get; }

    internal string LockPath => Path.Combine(Folder, ".lock");

    internal string SegmentPath(int number) => Path.Combine(Folder, $"journal-{number:D6}.jsonl");

    internal string BlobPath(string name) => Path.Combine(Folder, "content", name[..2], name);

    internal DateTimeOffset Now => Clock.GetUtcNow();

    // ---- Writing (#899 W2a) -------------------------------------------------

    /// <summary>
    /// Runs <paramref name="body"/> holding the list's one lock
    /// (<c>rule.oneLock</c>), the mac's <c>withLock</c>: the folder made, the
    /// lock taken (waiting at most 2 seconds live, 50 milliseconds in shadow,
    /// unless <paramref name="wait"/> says), a torn last line cut off, the
    /// journal read FRESH, any closing this process could not write earlier
    /// written first, then the body, then every line written made durable.
    ///
    /// <para>A reading inside the lock that is not fresh REFUSES the hold
    /// (<see cref="UndoJournalFailure.ListNotReadable"/>): nothing is written
    /// or deleted from a stale fold (the W1 review's M2).</para>
    /// </summary>
    internal T WithLock<T>(Func<UndoJournalWriter, T> body, bool inShadow = false, TimeSpan? wait = null)
    {
        try { Directory.CreateDirectory(Folder); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UndoJournalException(UndoJournalFailure.CouldNotOpenTheLock, "The list's folder could not be made.", error);
        }
        using UndoLock held = UndoLock.Take(LockPath, wait ?? (inShadow ? ShadowWait : LiveWait), inShadow, Memory);
        CutTornLastLine();
        UndoReading reading = Read();
        if (!reading.IsFresh)
            throw new UndoJournalException(UndoJournalFailure.ListNotReadable, "The list could not be read inside the lock.");
        using var writer = new UndoJournalWriter(this, reading.Folded);
        WritePendingClosings(writer);
        T result = body(writer);
        writer.FinishTheHold();
        return result;
    }

    /// <summary>The same, for a body with nothing to return.</summary>
    internal void WithLock(Action<UndoJournalWriter> body, bool inShadow = false, TimeSpan? wait = null) =>
        WithLock(writer => { body(writer); return true; }, inShadow, wait);

    /// <summary>
    /// Writes a closing event (<c>applied</c>, <c>undone</c>, <c>redone</c>,
    /// <c>failed</c>, <c>rolledBack</c>) under the lock, waiting at most
    /// <paramref name="wait"/>; when the lock stays busy it is KEPT in this
    /// process's memory and written first at its next hold, so a step this
    /// process made is not left in flight for the life of the process (the
    /// mac's <c>keepPendingClosing</c>, its core review's I3). The wait the
    /// door passes (10 seconds on the mac, <c>UndoSwitch</c>) is the door's, W2b.
    /// Returns whether it was written now.
    /// </summary>
    internal bool WriteClosingOrKeep(System.Text.Json.Nodes.JsonObject line, TimeSpan wait, bool inShadow = false)
    {
        try
        {
            WithLock(writer => WriteClosing(writer, line), inShadow, wait);
            return true;
        }
        catch (UndoJournalException busy) when (busy.Failure == UndoJournalFailure.LockBusy)
        {
            Memory.KeepPendingClosing(Folder, line);
            return false;
        }
    }

    /// <summary>A closing for a step still in flight; an <c>applied</c> drops the redo branch at that moment (<c>rule.writeAhead</c>).</summary>
    private static void WriteClosing(UndoJournalWriter writer, System.Text.Json.Nodes.JsonObject line)
    {
        long? seq = line["seq"]?.GetValue<long>();
        if (seq is not { } number || !writer.Folded.Steps.TryGetValue(number, out UndoFoldedStep? step) || !step.IsInFlight) return;
        if (line["event"]?.GetValue<string>() == "applied") writer.DropTheRedoBranch(below: number);
        writer.Append(line);
    }

    private void WritePendingClosings(UndoJournalWriter writer)
    {
        IReadOnlyList<System.Text.Json.Nodes.JsonObject> pending = Memory.TakePendingClosings(Folder);
        for (int index = 0; index < pending.Count; index++)
        {
            try { WriteClosing(writer, pending[index]); }
            catch
            {
                // Kept for the next hold, this one and every one after it.
                for (int rest = index; rest < pending.Count; rest++) Memory.KeepPendingClosing(Folder, pending[rest]);
                throw;
            }
        }
    }

    /// <summary>
    /// Cuts a torn last line off the newest segment: reads its last byte and,
    /// only when it is not a line feed, back to the last line feed, and cuts
    /// there. Only bytes after the last line feed are ever cut. Inside the
    /// lock only.
    /// </summary>
    private void CutTornLastLine()
    {
        IReadOnlyList<(int Number, string Path)> segments;
        try { segments = Segments(); }
        catch (UndoListUnreadableException error)
        {
            throw new UndoJournalException(UndoJournalFailure.ListNotReadable, "The list's folder could not be listed.", error);
        }
        if (segments.Count == 0) return;
        FileStream stream;
        try
        {
            stream = new FileStream(segments[^1].Path, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite | FileShare.Delete);
        }
        catch (Exception gone) when (gone is FileNotFoundException or DirectoryNotFoundException) { return; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UndoJournalException(UndoJournalFailure.ListNotReadable, "The newest segment could not be opened.", error);
        }
        using (stream)
        {
            long size = stream.Length;
            if (size == 0) return;
            stream.Position = size - 1;
            if (stream.ReadByte() == '\n') return;
            long keep = 0;
            long chunkEnd = size;
            var chunk = new byte[65_536];
            while (chunkEnd > 0)
            {
                long chunkStart = Math.Max(0, chunkEnd - chunk.Length);
                int count = (int)(chunkEnd - chunkStart);
                stream.Position = chunkStart;
                stream.ReadExactly(chunk, 0, count);
                int found = Array.LastIndexOf(chunk, (byte)'\n', count - 1, count);
                if (found >= 0) { keep = chunkStart + found + 1; break; }
                chunkEnd = chunkStart;
            }
            stream.SetLength(keep);
            stream.Flush(true);
        }
    }

    /// <summary>
    /// Pruning and deletion CARRIED OUT (W1 only decides), inside the lock,
    /// from the writer's fresh fold of this same hold and never anything
    /// older: the <c>pruned</c> and <c>interrupted</c> lines
    /// <see cref="UndoPruning.Decide"/> names are appended, then what
    /// <see cref="UndoPruning.Deletable"/> names on the fold that now
    /// includes them is deleted: blobs, the <c>.tmp-</c> files of a writer
    /// that died (blobs are written under the lock, so only a dead process
    /// leaves one), then segments from the oldest end, stopping at the first
    /// that will not go. Never fails the caller: what could not be deleted is
    /// deleted by a later hold.
    /// </summary>
    /// <remarks>
    /// A step closed <c>unsettled</c> here gets its line only; tidying the
    /// staged files it may have left is W2b's, which knows the swap's names.
    /// </remarks>
    internal void Prune(UndoJournalWriter writer)
    {
        try
        {
            foreach (UndoPruneAction action in UndoPruning.Decide(writer.Reading(), Now, IsAlive))
            {
                switch (action)
                {
                    case UndoPruneAction.Pruned pruned:
                        writer.Append(new System.Text.Json.Nodes.JsonObject
                        {
                            ["seq"] = pruned.Seq, ["event"] = "pruned", ["reason"] = pruned.Reason,
                        });
                        break;
                    case UndoPruneAction.ClosedUnsettled closed:
                        var paths = new System.Text.Json.Nodes.JsonArray();
                        foreach (string path in closed.Paths) paths.Add(path);
                        writer.Append(new System.Text.Json.Nodes.JsonObject
                        {
                            ["seq"] = closed.Seq, ["event"] = "interrupted",
                            ["phase"] = closed.Phase.ToString().ToLowerInvariant(), ["reason"] = "unsettled", ["paths"] = paths,
                        });
                        break;
                }
            }
            UndoDeletion deletion = UndoPruning.Deletable(writer.Reading(), BlobsOnDisk(), Now);
            foreach (string blob in deletion.Blobs) TryDelete(BlobPath(blob));
            DeleteLeftoverTemporaries();
            bool deletedASegment = false;
            foreach (int number in deletion.Segments.Order())
            {
                if (!TryDelete(SegmentPath(number))) break;
                deletedASegment = true;
            }
            if (deletedASegment) writer.Refold();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Never fails the caller; a later hold prunes again.
        }
    }

    private void DeleteLeftoverTemporaries()
    {
        string content = Path.Combine(Folder, "content");
        if (!Directory.Exists(content)) return;
        foreach (string folder in Directory.EnumerateDirectories(content))
        {
            foreach (string leftover in Directory.EnumerateFiles(folder, ".tmp-*")) TryDelete(leftover);
        }
    }

    private static bool TryDelete(string path)
    {
        try
        {
            File.Delete(path);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>
    /// The segments on the disk, oldest first. A folder that is not there is
    /// no segments; one that is there and cannot be listed throws
    /// <see cref="UndoListUnreadableException"/>, never an empty list.
    /// </summary>
    internal IReadOnlyList<(int Number, string Path)> Segments()
    {
        var found = new List<(int, string)>();
        try
        {
            // No Directory.Exists first: it answers false for a folder it could
            // not look at, which would make an error an empty list. Only a
            // folder that is not there is no segments.
            foreach (string path in Directory.EnumerateFiles(Folder, "journal-*.jsonl"))
            {
                Match match = SegmentName.Match(Path.GetFileName(path));
                if (match.Success) found.Add((int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture), path));
            }
        }
        catch (DirectoryNotFoundException) { return found; }
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
    /// <remarks>
    /// <para><b>Reading on</b> (#899 W2a, the twin of the mac's
    /// <c>UndoFoldCache</c>; <c>rule.oneLock</c>: "a reader may keep what it
    /// has read and read on from where it stopped, as long as it checks that
    /// the bytes it read are still there"). Per segment this journal keeps the
    /// lines it parsed, the end it read to (just after a line feed), the 64
    /// bytes before that end, and the file's identity (volume serial and file
    /// index, from the OPEN handle, never by path). A segment is read on only
    /// when every remembered one is still there (or gone from the oldest end),
    /// is the same file, at least as long, with the same 64 bytes before the
    /// end, and no segment has appeared below the newest one read; anything
    /// else reads the journal whole.</para>
    ///
    /// <para><b>Refolded from the kept lines on every read.</b> Parsing is the
    /// cost; folding parsed lines is cheap. So a reading a caller holds is
    /// never changed under it, and a segment deleted from the oldest end drops
    /// its lines, so the barriers it held are forgotten by construction
    /// (<c>undoJournal.files</c>). Places in the journal are renumbered from 0
    /// each time, as a whole read numbers them.</para>
    ///
    /// <para>A volume whose file index is not known to stay put (FAT, exFAT, a
    /// network share) is always read whole: slower, never wrong. Nothing of a
    /// read that fails is kept.</para>
    /// </remarks>
    internal UndoReading Read()
    {
        lock (_readGuard)
        {
            IReadOnlyList<(int Number, string Path)> segments;
            try { segments = Segments(); }
            catch (UndoListUnreadableException)
            {
                return new UndoReading { Folded = _lastRead, IsFresh = false };
            }
            var numbers = segments.Select(s => s.Number).ToList();
            bool readOn = CanReadOn;
            ReadOutcome outcome = readOn ? ReadSegments(segments, _cache) : ReadOutcome.Invalid;
            if (outcome.Kind == ReadOutcomeKind.Invalid)
            {
                outcome = ReadSegments(segments, []);
                LastReadWasWhole = true;
            }
            else
            {
                LastReadWasWhole = _cache.Count == 0;
            }
            if (outcome.Kind != ReadOutcomeKind.Read)
            {
                return new UndoReading { Folded = _lastRead, IsFresh = false, SegmentsOnDisk = numbers };
            }
            _cache = readOn ? outcome.Segments : [];
            var folded = new UndoFolded();
            long place = 0;
            foreach (SegmentRead segment in outcome.Segments)
            {
                foreach (UndoLine line in segment.Lines) UndoFold.Apply(folded, line with { Place = place++ });
            }
            _lastRead = folded;
            return new UndoReading { Folded = folded, IsFresh = true, TornBytes = outcome.Torn, SegmentsOnDisk = numbers };
        }
    }

    /// <summary>Whether the last read read every segment from its first byte (for tests and the harness).</summary>
    internal bool LastReadWasWhole { get; private set; }

    /// <summary>What one segment read came to: its lines, where reading stopped, the bytes before that, the file.</summary>
    private sealed record SegmentRead(int Number, (uint Volume, ulong Index)? Identity, long End, byte[] Tail, IReadOnlyList<UndoLine> Lines);

    private enum ReadOutcomeKind { Read, Invalid, CannotRead }

    private sealed record ReadOutcome(ReadOutcomeKind Kind, List<SegmentRead> Segments, long Torn)
    {
        internal static readonly ReadOutcome Invalid = new(ReadOutcomeKind.Invalid, [], 0);
        internal static readonly ReadOutcome CannotRead = new(ReadOutcomeKind.CannotRead, [], 0);
    }

    private const int TailBytes = 64;

    /// <summary>
    /// Reads the listed segments, reading on from <paramref name="kept"/> where
    /// it is still good. <see cref="ReadOutcomeKind.Invalid"/> when what is kept
    /// no longer matches the disk (only when reading on).
    /// </summary>
    private ReadOutcome ReadSegments(IReadOnlyList<(int Number, string Path)> segments, List<SegmentRead> kept)
    {
        var keptByNumber = kept.ToDictionary(segment => segment.Number);
        if (kept.Count > 0)
        {
            var onDisk = segments.Select(s => s.Number).ToHashSet();
            int newestKept = kept[^1].Number;
            // Gone only from the oldest end: once one kept segment is there, every later kept one must be.
            bool seenOne = false;
            foreach (SegmentRead segment in kept)
            {
                if (onDisk.Contains(segment.Number)) seenOne = true;
                else if (seenOne) return ReadOutcome.Invalid;
            }
            // None appeared below the newest read.
            foreach ((int number, _) in segments)
            {
                if (number < newestKept && !keptByNumber.ContainsKey(number)) return ReadOutcome.Invalid;
            }
        }

        var read = new List<SegmentRead>();
        long torn = 0;
        for (int index = 0; index < segments.Count; index++)
        {
            (int number, string path) = segments[index];
            bool newest = index == segments.Count - 1;
            using Stream? stream = OpenShared(path, out bool gone);
            if (stream is null)
            {
                // An older segment pruned since the listing is passed over; the newest never is.
                if (gone && !newest) continue;
                return ReadOutcome.CannotRead;
            }
            try
            {
                (uint, ulong)? identity = stream is FileStream file ? UndoFileIdentity.Of(file) : null;
                long length = stream.Length;
                long start = 0;
                var lines = new List<UndoLine>();
                if (keptByNumber.TryGetValue(number, out SegmentRead? before))
                {
                    if (identity is null || before.Identity is null || identity != before.Identity) return ReadOutcome.Invalid;
                    if (length < before.End) return ReadOutcome.Invalid;
                    if (!TailMatches(stream, before)) return ReadOutcome.Invalid;
                    start = before.End;
                    lines.AddRange(before.Lines);
                }
                stream.Position = start;
                byte[] bytes = ReadToEnd(stream, length - start);
                int lineStart = 0;
                for (int at = 0; at < bytes.Length; at++)
                {
                    if (bytes[at] != (byte)'\n') continue;
                    lines.Add(UndoFormat.Parse(bytes.AsSpan(lineStart, at - lineStart), number, 0));
                    lineStart = at + 1;
                }
                long end = start + lineStart;
                torn = start + bytes.Length - end;
                byte[] tail = TailBefore(stream, end, bytes, lineStart);
                read.Add(new SegmentRead(number, identity, end, tail, lines));
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                return ReadOutcome.CannotRead;
            }
        }
        return new ReadOutcome(ReadOutcomeKind.Read, read, torn);
    }

    private static bool TailMatches(Stream stream, SegmentRead before)
    {
        int count = before.Tail.Length;
        stream.Position = before.End - count;
        byte[] now = ReadToEnd(stream, count);
        return now.AsSpan().SequenceEqual(before.Tail);
    }

    /// <summary>The (up to) 64 bytes before <paramref name="end"/>, from the bytes just read when they reach back far enough.</summary>
    private static byte[] TailBefore(Stream stream, long end, byte[] bytes, int usedOfBytes)
    {
        int count = (int)Math.Min(TailBytes, end);
        if (usedOfBytes >= count) return bytes.AsSpan(usedOfBytes - count, count).ToArray();
        stream.Position = end - count;
        return ReadToEnd(stream, count);
    }

    private static byte[] ReadToEnd(Stream stream, long count)
    {
        var buffer = new byte[count];
        int filled = 0;
        while (filled < count)
        {
            int got = stream.Read(buffer, filled, (int)(count - filled));
            if (got == 0) break;
            filled += got;
        }
        return filled == count ? buffer : buffer[..filled];
    }

    /// <summary>
    /// Whether this journal may read on: its folder is on NTFS or ReFS, where
    /// a file index stays the file's for its life, and the test seam for
    /// opening is not in use. FAT, exFAT and network shares are read whole.
    /// </summary>
    private bool CanReadOn => _canReadOn ??= _open is null && UndoFileIdentity.IsStableHere(Folder);

    private bool? _canReadOn;

    /// <summary>Forces whole reads (a test's seam for the must-fail proofs, and the harness's comparison).</summary>
    internal void ReadWholeEveryTime() => _canReadOn = false;

    /// <summary>Opens a segment to read with read, write and delete sharing, retrying a sharing violation for the read retry.</summary>
    private Stream? OpenShared(string path, out bool gone)
    {
        gone = false;
        long deadline = Environment.TickCount64 + (long)_readRetry.TotalMilliseconds;
        while (true)
        {
            try
            {
                return _open is null
                    ? new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)
                    : _open(path);
            }
            catch (Exception missing) when (missing is FileNotFoundException or DirectoryNotFoundException)
            {
                gone = true;
                return null;
            }
            catch (IOException exception) when ((exception.HResult & 0xFFFF) is 32 or 33)
            {
                if (Environment.TickCount64 >= deadline) return null;
                Thread.Sleep(20);
            }
            catch (IOException) { return null; }
            catch (UnauthorizedAccessException) { return null; }
        }
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
        try
        {
            // As in Segments: only a content folder that is not there is no blobs.
            foreach (string folder in Directory.EnumerateDirectories(content))
            {
                foreach (string file in Directory.EnumerateFiles(folder))
                {
                    string name = Path.GetFileName(file);
                    if (UndoFormat.IsBlobName(name)) names.Add(name);
                }
            }
        }
        catch (DirectoryNotFoundException) { return names; }
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

    /// <summary>
    /// Whether a step's process is still running, by the liveness rule the
    /// work leases already use (<c>WorkLease.OwnerIsAlive</c>: the id, then the
    /// process table's name and start time). A step with no process it can
    /// read is judged gone for the offer and for pruning, so it is never left
    /// in flight for ever; recovery asks <see cref="RecoveryMaySettle"/>.
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

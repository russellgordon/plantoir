using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Undo;

/// <summary>
/// The list's events, written by the one holder of the lock (#899 W2a; the
/// mac's <c>UndoJournalWriter</c>). Made only by <see cref="UndoJournal.WithLock{T}"/>.
///
/// <para><b>A line</b> is one JSON object, keys sorted (for a person reading a
/// diff, as the mac writes them), <c>v</c> 1 and <c>at</c> stamped by the
/// journal's clock when the caller has not, UTF-8 with no byte-order mark, and
/// an explicit line feed: never <c>WriteLine</c>, which writes CR LF here
/// (<c>undoJournal.line</c>). Each line is ONE <c>WriteFile</c> (the stream is
/// unbuffered), so a reader outside the lock sees a whole line or a torn one,
/// which it does not count.</para>
///
/// <para><b>Durable.</b> Every hold that wrote ends with
/// <c>FlushFileBuffers</c> (<see cref="FileStream.Flush(bool)"/>). The mac
/// syncs every hold with <c>fsync</c> and the three lines recovery cannot do
/// without (<c>begin</c>, <c>undoing</c>, <c>redoing</c>) with
/// <c>F_FULLFSYNC</c>; Windows has one flush that reaches the disk, so every
/// hold gets it. <see cref="Sync"/> is the same flush, for a door that must
/// make a line durable before it goes on inside the same hold.</para>
///
/// <para><b>Segments.</b> Appended to the newest until it is at or past
/// <see cref="UndoJournal.SegmentBytes"/> (4 MiB), then a new one is made with
/// <see cref="FileMode.CreateNew"/>, which never truncates a file that is
/// there. The writer's <see cref="Folded"/> is kept up to date with every line
/// it appends.</para>
/// </summary>
internal sealed class UndoJournalWriter : IDisposable
{
    private static readonly UTF8Encoding Utf8 = new(encoderShouldEmitUTF8Identifier: false);

    private static readonly JsonSerializerOptions LineOptions = new()
    {
        WriteIndented = false,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private readonly UndoJournal _journal;
    private FileStream? _segment;
    private int _segmentNumber;
    private bool _wroteSomething;

    internal UndoJournalWriter(UndoJournal journal, UndoFolded folded)
    {
        _journal = journal;
        Folded = folded;
    }

    /// <summary>The list as read fresh when the lock was taken, with every line this writer has appended.</summary>
    internal UndoFolded Folded { get; private set; }

    /// <summary>The writer's fold as a reading, with the segments on the disk now (inside the lock).</summary>
    internal UndoReading Reading() => new()
    {
        Folded = Folded,
        IsFresh = true,
        SegmentsOnDisk = _journal.Segments().Select(segment => segment.Number).ToList(),
    };

    /// <summary>Reads the journal again inside the lock (after segments are deleted, so their barriers are forgotten).</summary>
    internal void Refold()
    {
        UndoReading reading = _journal.Read();
        if (reading.IsFresh) Folded = reading.Folded.Copy();
    }

    /// <summary>The line's bytes as written: keys sorted at every level, compact, UTF-8 without a byte-order mark, no line feed.</summary>
    internal static byte[] Encode(JsonObject line) => Utf8.GetBytes(Sorted(line)!.ToJsonString(LineOptions));

    private static JsonNode? Sorted(JsonNode? node) => node switch
    {
        JsonObject obj => new JsonObject(obj.OrderBy(pair => pair.Key, StringComparer.Ordinal)
                                             .Select(pair => KeyValuePair.Create(pair.Key, Sorted(pair.Value)))),
        JsonArray array => new JsonArray(array.Select(Sorted).ToArray()),
        null => null,
        _ => node.DeepClone(),
    };

    /// <summary>Appends one event as one line, stamped with <c>v</c> 1 and the clock when it has neither.</summary>
    internal void Append(JsonObject line)
    {
        var stamped = (JsonObject)line.DeepClone();
        stamped["v"] ??= 1;
        stamped["at"] ??= UndoMoment.Format(_journal.Now);
        AppendEncoded(Encode(stamped));
    }

    /// <summary>
    /// Appends a line already encoded (a line from another version, in a
    /// test): its bytes as given and a line feed. A line feed inside it would
    /// make two lines, so it is refused.
    /// </summary>
    internal void AppendRaw(string json)
    {
        if (json.Contains('\n')) throw new ArgumentException("A line holds no line feed.", nameof(json));
        AppendEncoded(Utf8.GetBytes(json));
    }

    private void AppendEncoded(byte[] encoded)
    {
        FileStream segment = SegmentForTheNextLine();
        var bytes = new byte[encoded.Length + 1];
        encoded.CopyTo(bytes, 0);
        bytes[^1] = (byte)'\n';
        try { segment.Write(bytes, 0, bytes.Length); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UndoJournalException(UndoJournalFailure.CouldNotWrite, "A line of the list could not be written.", error);
        }
        _wroteSomething = true;
        UndoFold.Apply(Folded, UndoFormat.Parse(encoded, _segmentNumber, Folded.Lines));
    }

    /// <summary>Every undone step below <paramref name="below"/> dropped (<c>reason</c> <c>newStep</c>): the redo branch, at the moment a new step is applied.</summary>
    internal void DropTheRedoBranch(long below)
    {
        var undone = Folded.Steps.Values.Where(step => step.State == UndoStepState.Undone && step.Seq < below)
                                        .Select(step => step.Seq).ToList();
        foreach (long seq in undone)
            Append(new JsonObject { ["seq"] = seq, ["event"] = "dropped", ["reason"] = "newStep" });
    }

    /// <summary>Makes every line written so far durable now (<c>FlushFileBuffers</c>).</summary>
    internal void Sync()
    {
        try { _segment?.Flush(flushToDisk: true); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UndoJournalException(UndoJournalFailure.CouldNotWrite, "The list could not be made durable.", error);
        }
    }

    /// <summary>The end of a hold: durable if anything was written.</summary>
    internal void FinishTheHold()
    {
        if (_wroteSomething) Sync();
    }

    public void Dispose()
    {
        _segment?.Dispose();
        _segment = null;
    }

    private FileStream SegmentForTheNextLine()
    {
        if (_segment is not null)
        {
            if (_segment.Length < _journal.SegmentBytes) return _segment;
            Sync();
            _segment.Dispose();
            _segment = null;
            return OpenNewSegment(_segmentNumber + 1);
        }
        IReadOnlyList<(int Number, string Path)> segments = _journal.Segments();
        if (segments.Count == 0) return OpenNewSegment(1);
        (int number, string path) = segments[^1];
        FileStream newest;
        try
        {
            newest = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete,
                                    bufferSize: 0);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UndoJournalException(UndoJournalFailure.CouldNotWrite, "The newest segment could not be opened.", error);
        }
        if (newest.Length >= _journal.SegmentBytes)
        {
            newest.Dispose();
            return OpenNewSegment(number + 1);
        }
        newest.Seek(0, SeekOrigin.End);
        _segment = newest;
        _segmentNumber = number;
        return newest;
    }

    private FileStream OpenNewSegment(int number)
    {
        try
        {
            _segment = new FileStream(_journal.SegmentPath(number), FileMode.CreateNew, FileAccess.Write,
                                      FileShare.ReadWrite | FileShare.Delete, bufferSize: 0);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UndoJournalException(UndoJournalFailure.CouldNotStartASegment,
                $"journal-{number:D6}.jsonl could not be made.", error);
        }
        _segmentNumber = number;
        return _segment;
    }

    // ---- Blobs ---------------------------------------------------------------

    /// <summary>
    /// Stores content as an immutable blob named by its SHA-256
    /// (<c>undoJournal.files</c> → <c>content/&lt;aa&gt;/&lt;sha256&gt;</c>), under
    /// the lock (<c>rule.writeAhead</c>), and returns its name. One already
    /// there that hashes to its name is used as it is. Otherwise it is written
    /// to <c>content\aa\.tmp-&lt;guid&gt;</c>, made durable, and moved onto its
    /// name with a move that FAILS when the name exists (never replacing). A
    /// name that exists and does not hash to it (a torn blob) is deleted and the
    /// write tried once more. Where the volume refuses that move as
    /// unsupported, the name itself is made with an exclusive create, as the
    /// contract says for exFAT. A blob that cannot be stored (room, permission)
    /// leaves nothing of it behind and throws
    /// <see cref="UndoJournalFailure.CouldNotStoreContent"/>.
    /// </summary>
    internal string WriteBlob(byte[] bytes) => WriteBlob(bytes, triesLeft: 2);

    /// <summary>
    /// Many blobs at once, as a whole-file step writes them, each exactly as
    /// <see cref="WriteBlob(byte[])"/> does, <paramref name="parallelism"/> at a
    /// time: each must be flushed to the disk before its rename, and those
    /// flushes overlap. Returns the names in the order given. The first
    /// failure is thrown once the others have finished, each having removed
    /// its own temporary file.
    /// </summary>
    internal IReadOnlyList<string> WriteBlobs(IReadOnlyList<byte[]> contents, int parallelism)
    {
        var names = new string[contents.Count];
        if (parallelism <= 1)
        {
            for (int index = 0; index < contents.Count; index++) names[index] = WriteBlob(contents[index]);
            return names;
        }
        try
        {
            Parallel.For(0, contents.Count, new ParallelOptions { MaxDegreeOfParallelism = parallelism },
                         index => names[index] = WriteBlob(contents[index]));
        }
        catch (AggregateException failures)
        {
            System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failures.InnerExceptions[0]).Throw();
            throw;
        }
        return names;
    }

    private string WriteBlob(byte[] bytes, int triesLeft)
    {
        string name = UndoCheck.Sha(bytes);
        if (_journal.Blob(name) is not null) return name;
        string final = _journal.BlobPath(name);
        string folder = Path.GetDirectoryName(final)!;
        string temporary = Path.Combine(folder, ".tmp-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(folder);
            WriteDurably(temporary, bytes);
            File.Move(temporary, final, overwrite: false);
            return name;
        }
        catch (IOException error) when ((error.HResult & 0xFFFF) is 80 or 183)
        {
            TryDelete(temporary);
            return TheNameIsThere(bytes, name, final, triesLeft);
        }
        catch (IOException error) when ((error.HResult & 0xFFFF) is 50 or 87)
        {
            // No move that refuses to replace on this volume: an exclusive create of the name.
            TryDelete(temporary);
            try
            {
                WriteDurably(final, bytes);
                return name;
            }
            catch (IOException again) when ((again.HResult & 0xFFFF) is 80 or 183)
            {
                return TheNameIsThere(bytes, name, final, triesLeft);
            }
            catch (Exception failed) when (failed is IOException or UnauthorizedAccessException)
            {
                TryDelete(final);
                throw new UndoJournalException(UndoJournalFailure.CouldNotStoreContent, "Content could not be stored.", failed);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            TryDelete(temporary);
            throw new UndoJournalException(UndoJournalFailure.CouldNotStoreContent, "Content could not be stored.", error);
        }
    }

    private string TheNameIsThere(byte[] bytes, string name, string final, int triesLeft)
    {
        if (_journal.Blob(name) is not null) return name;
        if (triesLeft <= 1)
            throw new UndoJournalException(UndoJournalFailure.CouldNotStoreContent, "Content could not be stored over a torn copy.");
        TryDelete(final);
        return WriteBlob(bytes, triesLeft - 1);
    }

    /// <summary>Writes a file that must not be there yet, whole, and flushes it to the disk.</summary>
    private static void WriteDurably(string path, byte[] bytes)
    {
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, bufferSize: 0);
        stream.Write(bytes, 0, bytes.Length);
        stream.Flush(flushToDisk: true);
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }
}

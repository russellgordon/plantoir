using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The store (#899 W2a): the append, the torn-line cut, segments, blobs,
/// reading on and the refusals, one test per sentence of
/// <c>undoJournal.line</c>, <c>undoJournal.files</c> and <c>rule.readers</c>
/// it proves. Every journal here has its own folder, clock and process
/// memory (the plan review's H1).
/// </summary>
public sealed class UndoStoreTests : IDisposable
{
    private readonly string _folder = RunOwnedTempFolders.Create("plantoir-undo-store-");
    private readonly UndoTestClock _clock = new(new DateTimeOffset(2026, 11, 14, 12, 0, 0, TimeSpan.Zero));
    private readonly UndoProcessMemory _memory = new();

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private UndoJournal Journal(long segmentBytes = UndoJournal.SegmentBytesInTheApp, UndoProcessMemory? memory = null) =>
        new(_folder, _clock, _ => true, _ => true, isLive: false, readRetry: TimeSpan.Zero,
            memory: memory ?? _memory, segmentBytes: segmentBytes);

    private string Segment(int number) => Path.Combine(_folder, $"journal-{number:D6}.jsonl");

    private static JsonObject Begin(long seq) => new()
    {
        ["seq"] = seq,
        ["event"] = "begin",
        ["process"] = new JsonObject { ["host"] = "h", ["pid"] = 1, ["name"] = "n", ["started"] = "s" },
        ["step"] = new JsonObject { ["seq"] = seq, ["madeAt"] = "2026-11-14T12:00:00Z", ["ops"] = new JsonArray() },
    };

    /// <summary>A line's bytes as the writer writes them, for a file a test makes by hand.</summary>
    private static byte[] Raw(JsonObject line)
    {
        line["v"] = 1;
        line["at"] = "2026-11-14T12:00:00Z";
        return [.. UndoJournalWriter.Encode(line), (byte)'\n'];
    }

    private static JsonObject Event(long seq, string name) => new() { ["seq"] = seq, ["event"] = name };

    private static void Step(UndoJournalWriter writer, long seq)
    {
        writer.Append(Begin(seq));
        writer.Append(Event(seq, "applied"));
    }

    private static string Sentence(string key) => UndoContract.Journal.GetProperty(key).GetString()!;

    private static string FilesSentence(string key) => UndoContract.Journal.GetProperty("files").GetProperty(key).GetString()!;

    // ---- undoJournal.line ----------------------------------------------------

    [Fact]
    public void ALineIsOneObjectInUtf8WithNoByteOrderMarkEndingInALineFeedNeverCrLf()
    {
        Assert.Contains("ending in a line feed (\\n, never \\r\\n)", Sentence("line"));
        Journal().WithLock(writer => Step(writer, 1));
        byte[] bytes = File.ReadAllBytes(Segment(1));
        Assert.Equal((byte)'{', bytes[0]);
        Assert.DoesNotContain((byte)'\r', bytes);
        Assert.Equal((byte)'\n', bytes[^1]);
        string[] lines = new UTF8Encoding(false, throwOnInvalidBytes: true).GetString(bytes).Split('\n');
        Assert.Equal(3, lines.Length);   // two lines and nothing after the last line feed
        foreach (string line in lines[..2])
        {
            using JsonDocument document = JsonDocument.Parse(line);
            Assert.Equal(1, document.RootElement.GetProperty("v").GetInt32());
            Assert.Equal("2026-11-14T12:00:00Z", document.RootElement.GetProperty("at").GetString());
            var keys = document.RootElement.EnumerateObject().Select(property => property.Name).ToList();
            Assert.Equal(keys.OrderBy(key => key, StringComparer.Ordinal).ToList(), keys);   // sorted, as the mac writes
        }
    }

    [Fact]
    public void ATornLineIsNotCountedByAReaderAndIsCutByTheNextWriterLeavingTheLinesBeforeIt()
    {
        Assert.Contains("left for the next writer to cut off inside the lock", Sentence("line"));
        UndoJournal journal = Journal();
        journal.WithLock(writer => Step(writer, 1));
        byte[] whole = File.ReadAllBytes(Segment(1));
        using (var append = new FileStream(Segment(1), FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
            append.Write(Encoding.UTF8.GetBytes("{\"v\":1,\"seq\":2,\"event\":\"beg"));

        UndoReading reading = Journal().Read();
        Assert.True(reading.TornBytes > 0);
        Assert.Equal(1, reading.Folded.Highest);
        Assert.Empty(reading.Folded.Barriers);

        journal.WithLock(writer => Step(writer, 2));
        byte[] after = File.ReadAllBytes(Segment(1));
        Assert.Equal(whole, after[..whole.Length]);
        Assert.Equal((byte)'{', after[whole.Length]);
        UndoFolded folded = Journal().Read().Folded;
        Assert.Equal(UndoStepState.Done, folded.Steps[2].State);
        Assert.Empty(folded.Barriers);
    }

    // ---- undoJournal.files: segments ------------------------------------------

    [Fact]
    public void ANewSegmentStartsOnceTheNewestPassesTheSizeTheContractNames()
    {
        Match size = Regex.Match(FilesSentence("journal-NNNNNN.jsonl"), @"once the newest passes (\d+) MiB");
        Assert.True(size.Success);
        long named = long.Parse(size.Groups[1].Value) * 1024 * 1024;
        Assert.True(named == UndoJournal.SegmentBytesInTheApp, $"the contract names {named} bytes");

        UndoJournal journal = Journal(segmentBytes: 600);
        for (long seq = 1; seq <= 12; seq++) journal.WithLock(writer => Step(writer, seq));
        UndoReading reading = Journal().Read();
        Assert.True(reading.SegmentsOnDisk.Count > 2);
        Assert.Equal(Enumerable.Range(1, reading.SegmentsOnDisk.Count).ToList(), reading.SegmentsOnDisk);
        foreach (int number in reading.SegmentsOnDisk.Take(reading.SegmentsOnDisk.Count - 1))
            Assert.True(new FileInfo(Segment(number)).Length >= 600);
        Assert.Equal(12, reading.Folded.Highest);
        Assert.All(reading.Folded.Steps.Values, step => Assert.Equal(UndoStepState.Done, step.State));
        Assert.Equal(Enumerable.Range(1, 12).Select(seq => (long)seq), reading.Folded.Steps.Keys);
    }

    /// <summary>
    /// <c>rule.readers</c>: a reader shares delete, so a pruner can delete the
    /// segment a reader has open. Opened the product's way (the must-fail
    /// proof takes the delete sharing out of that one open).
    /// </summary>
    [Fact]
    public void ASegmentAReaderHasOpenCanStillBeAppendedToAndDeleted()
    {
        UndoJournal journal = Journal();
        journal.WithLock(writer => Step(writer, 1));
        using (FileStream reader = UndoJournal.OpenSegmentToRead(Segment(1)))
        {
            journal.WithLock(writer => Step(writer, 2));
            File.Delete(Segment(1));
            Assert.True(reader.Length > 0);
        }
        Assert.False(File.Exists(Segment(1)));
    }

    /// <summary>A reader in another journal reads on while a writer appends: never unreadable, never going back.</summary>
    [Fact]
    public async Task AReaderReadsOnWhileAWriterAppends()
    {
        UndoJournal writerJournal = Journal(segmentBytes: 4096);
        UndoJournal readerJournal = Journal();
        using var stop = new CancellationTokenSource();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        // Its own thread, and the writing waits until it has read once: on a
        // busy PC (the whole suite) a pool task could start after the writer
        // had finished, and the test would prove nothing.
        var midway = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Task<(int Reads, int ReadsMidway, int ReadsOn, string? Fault)> reader = Task.Factory.StartNew<(int, int, int, string?)>(() =>
        {
            long highest = 0;
            int reads = 0;
            int readsMidway = 0;
            int readsOn = 0;
            do
            {
                if (reads == 1) started.TrySetResult();
                UndoReading reading = readerJournal.Read();
                reads++;
                if (!reading.IsFresh) return (reads, readsMidway, readsOn, "a reading was not fresh");
                if (reading.Folded.Highest < highest) return (reads, readsMidway, readsOn, "a reading went back");
                if (reading.Folded.Barriers.Count > 0) return (reads, readsMidway, readsOn, "a reading saw a barrier");
                // A reading taken while the writing was going on, and one that
                // read on rather than whole (W2a's review, LOW 4).
                if (reading.Folded.Highest is > 0 and < 150) { readsMidway++; midway.TrySetResult(); }
                if (reading.Folded.Highest > 0 && !readerJournal.LastReadWasWhole) readsOn++;
                highest = reading.Folded.Highest;
            }
            while (!stop.IsCancellationRequested || reads < 2);
            return (reads, readsMidway, readsOn, null);
        }, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
        await Task.WhenAny(started.Task, reader);
        for (long seq = 1; seq <= 150; seq++)
        {
            writerJournal.WithLock(writer => Step(writer, seq));
            // Half way, the writing waits until the reader has seen part of it,
            // so the test cannot pass with every read before or after.
            if (seq == 75) await Task.WhenAny(midway.Task, reader, Task.Delay(TimeSpan.FromSeconds(30)));
        }
        stop.Cancel();
        (int reads, int readsMidway, int readsOn, string? fault) = await reader;
        Assert.Null(fault);
        Assert.True(reads >= 2);
        Assert.True(readsMidway > 0, "no reading was taken while the writing was going on");
        Assert.True(readsOn > 0, "no reading read on from where it stopped");
        UndoReading last = readerJournal.Read();
        Assert.Equal(150, last.Folded.Highest);
        Assert.Equal(150, last.Folded.Steps.Values.Count(step => step.State == UndoStepState.Done));
    }

    // ---- reading on -----------------------------------------------------------

    [Fact]
    public void AReaderReadsOnFromWhereItStopped()
    {
        UndoJournal journal = Journal();
        journal.WithLock(writer => Step(writer, 1));
        UndoJournal reader = Journal();
        UndoReading first = reader.Read();
        Assert.True(reader.LastReadWasWhole);
        journal.WithLock(writer => Step(writer, 2));
        UndoReading second = reader.Read();
        Assert.False(reader.LastReadWasWhole, "NTFS: the second read reads on");
        Assert.Equal(2, second.Folded.Highest);
        Assert.Equal(1, first.Folded.Highest);   // a reading held is never changed under its holder
        Assert.Single(first.Folded.Steps);
    }

    [Fact]
    public void AFileReplacedUnderTheSameNameIsReadWhole()
    {
        UndoJournal journal = Journal();
        journal.WithLock(writer => Step(writer, 1));
        UndoJournal reader = Journal();
        reader.Read();
        byte[] bytes = File.ReadAllBytes(Segment(1));
        string replacement = Path.Combine(_folder, "replacement");
        File.WriteAllBytes(replacement, [.. bytes, .. Raw(Begin(2))]);
        File.Move(replacement, Segment(1), overwrite: true);
        UndoReading reading = reader.Read();
        Assert.True(reader.LastReadWasWhole);
        Assert.Equal(UndoStepState.Begun, reading.Folded.Steps[2].State);
    }

    [Fact]
    public void AShorterFileIsReadWhole()
    {
        UndoJournal journal = Journal();
        journal.WithLock(writer => Step(writer, 1));
        UndoJournal reader = Journal();
        reader.Read();
        byte[] bytes = File.ReadAllBytes(Segment(1));
        int firstLine = Array.IndexOf(bytes, (byte)'\n') + 1;
        using (var stream = new FileStream(Segment(1), FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
            stream.SetLength(firstLine);
        UndoReading reading = reader.Read();
        Assert.True(reader.LastReadWasWhole);
        Assert.Equal(UndoStepState.Begun, reading.Folded.Steps[1].State);
    }

    /// <summary>
    /// The same file, as long or longer, rewritten in place: the 64 bytes before
    /// where reading stopped have changed, so it is read whole (the must-fail
    /// proof: without the tail check the fold keeps a line no longer there).
    /// </summary>
    [Fact]
    public void AFileRewrittenInPlaceIsReadWhole()
    {
        UndoJournal journal = Journal();
        journal.WithLock(writer =>
        {
            Step(writer, 1);
            writer.Append(Event(1, "undoing"));
        });
        UndoJournal reader = Journal();
        Assert.Equal(UndoStepState.Undoing, reader.Read().Folded.Steps[1].State);

        byte[] bytes = File.ReadAllBytes(Segment(1));
        string text = Encoding.UTF8.GetString(bytes);
        string rewritten = text.Replace("\"event\":\"undoing\"", "\"event\":\"xndoing\"", StringComparison.Ordinal);
        Assert.NotEqual(text, rewritten);
        using (var stream = new FileStream(Segment(1), FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
            stream.Write(Encoding.UTF8.GetBytes(rewritten));

        UndoReading reading = reader.Read();
        Assert.True(reader.LastReadWasWhole);
        Assert.Equal(UndoStepState.Done, reading.Folded.Steps[1].State);
        Assert.Single(reading.Folded.Barriers);   // the line it cannot read now
    }

    [Fact]
    public void ASegmentAppearingBelowTheNewestReadIsReadWhole()
    {
        UndoJournal journal = Journal();
        journal.WithLock(writer => Step(writer, 1));
        File.Move(Segment(1), Segment(2));
        UndoJournal reader = Journal();
        reader.Read();
        File.WriteAllBytes(Segment(1), [.. Raw(Begin(5))]);
        UndoReading reading = reader.Read();
        Assert.True(reader.LastReadWasWhole);
        Assert.Equal([1, 2], reading.SegmentsOnDisk);
        Assert.Equal(UndoStepState.Begun, reading.Folded.Steps[5].State);
    }

    /// <summary><c>undoJournal.files</c>: "A reader that has folded a deleted segment forgets the barriers it held."</summary>
    [Fact]
    public void AnOldestSegmentDeletedIsForgottenWithItsBarriersAndTheRestIsReadOn()
    {
        Assert.Contains("A reader that has folded a deleted segment forgets the barriers it held", FilesSentence("journal-NNNNNN.jsonl"));
        UndoJournal journal = Journal(segmentBytes: 1);
        journal.WithLock(writer => writer.AppendRaw("{\"v\":2,\"seq\":1,\"event\":\"somethingNew\",\"at\":\"2026-11-14T12:00:00Z\"}"));
        journal.WithLock(writer => Step(writer, 2));
        UndoJournal reader = Journal();
        UndoReading before = reader.Read();
        Assert.Single(before.Folded.Barriers);
        Assert.True(before.SegmentsOnDisk.Count >= 2);

        File.Delete(Segment(1));
        UndoReading after = reader.Read();
        Assert.False(reader.LastReadWasWhole);
        Assert.Empty(after.Folded.Barriers);
        Assert.Equal(UndoStepState.Done, after.Folded.Steps[2].State);
        Assert.Single(before.Folded.Barriers);   // the reading held before is unchanged
    }

    // ---- blobs -----------------------------------------------------------------

    [Fact]
    public void ABlobIsWrittenUnderItsHashAndNeverReplaced()
    {
        Assert.Contains("renamed onto the name with a rename that FAILS if the name exists (never replacing)", FilesSentence("content/<aa>/<sha256>"));
        UndoJournal journal = Journal();
        byte[] content = Encoding.UTF8.GetBytes("a page as it was\n");
        string name = journal.WithLock(writer => writer.WriteBlob(content));
        Assert.Equal(UndoCheck.Sha(content), name);
        string path = journal.BlobPath(name);
        Assert.Equal(content, File.ReadAllBytes(path));
        DateTime written = File.GetLastWriteTimeUtc(path);
        File.SetLastWriteTimeUtc(path, written.AddHours(-1));
        Assert.Equal(name, journal.WithLock(writer => writer.WriteBlob(content)));
        Assert.Equal(written.AddHours(-1), File.GetLastWriteTimeUtc(path));   // left as it was
        Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(path)!, ".tmp-*"));
    }

    [Fact]
    public void ABlobWhoseBytesDoNotHashToItsNameIsWrittenAgain()
    {
        Assert.Contains("A blob whose bytes do not hash to its name is treated as missing, and a writer that needs it writes it again", FilesSentence("content/<aa>/<sha256>"));
        UndoJournal journal = Journal();
        byte[] content = Encoding.UTF8.GetBytes("the whole page\n");
        string path = journal.BlobPath(UndoCheck.Sha(content));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, Encoding.UTF8.GetBytes("the whole pa"));   // torn
        journal.WithLock(writer => writer.WriteBlob(content));
        Assert.Equal(content, File.ReadAllBytes(path));
        Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(path)!, ".tmp-*"));
    }

    /// <summary>Many blobs written at once, the same content twice among them: each under its hash, nothing temporary left.</summary>
    [Fact]
    public void ManyBlobsWrittenAtOnceAreEachStoredUnderTheirHash()
    {
        UndoJournal journal = Journal();
        var contents = Enumerable.Range(0, 40).Select(index => Encoding.UTF8.GetBytes($"page {index % 30}\n")).ToList();
        IReadOnlyList<string> names = journal.WithLock(writer => writer.WriteBlobs(contents, parallelism: 4));
        Assert.Equal(contents.Select(UndoCheck.Sha), names);
        foreach ((byte[] content, string name) in contents.Zip(names)) Assert.Equal(content, File.ReadAllBytes(journal.BlobPath(name)));
        Assert.Equal(30, journal.BlobsOnDisk().Count);
        Assert.Empty(Directory.EnumerateFiles(Path.Combine(_folder, "content"), ".tmp-*", SearchOption.AllDirectories));
    }

    [Fact]
    public void ABlobThatCannotBeStoredLeavesNothingOfItBehind()
    {
        UndoJournal journal = Journal();
        byte[] content = Encoding.UTF8.GetBytes("content that has nowhere to go\n");
        string path = journal.BlobPath(UndoCheck.Sha(content));
        Directory.CreateDirectory(path);   // the name is taken by something that is not a blob
        Exception? failure = Record.Exception(() => journal.WithLock(writer => writer.WriteBlob(content)));
        Assert.True(failure is UndoJournalException or UndoListUnreadableException, failure?.ToString());
        Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(path)!, ".tmp-*"));
    }

    // ---- closings kept, refusals ------------------------------------------------

    /// <summary>A closing that cannot get the lock is kept by the PROCESS and written first at its next hold, dropping the redo branch then.</summary>
    [Fact]
    public void AClosingThatCannotGetTheLockIsWrittenAtTheNextHold()
    {
        UndoJournal journal = Journal();
        journal.WithLock(writer =>
        {
            Step(writer, 1);
            writer.Append(Event(1, "undoing"));
            writer.Append(Event(1, "undone"));
            writer.Append(Begin(2));
        });
        UndoJournal other = Journal(memory: new UndoProcessMemory());
        other.WithLock(_ =>
        {
            Assert.False(journal.WriteClosingOrKeep(Event(2, "applied"), TimeSpan.FromMilliseconds(50)));
        });
        Assert.Equal(1, _memory.PendingClosingsFor(_folder));
        Assert.Equal(UndoStepState.Begun, Journal().Read().Folded.Steps[2].State);

        journal.WithLock(_ => { });
        UndoFolded folded = Journal().Read().Folded;
        Assert.Equal(UndoStepState.Done, folded.Steps[2].State);
        Assert.Equal(UndoStepState.Dropped, folded.Steps[1].State);
        Assert.Equal(0, _memory.PendingClosingsFor(_folder));
    }

    /// <summary>
    /// The W1 review's M2, inside the lock: a reading that is not fresh refuses
    /// the hold. The body never runs, nothing is written, nothing is deleted.
    /// </summary>
    [Fact]
    public void AReadingThatIsNotFreshInsideTheLockRefusesTheHoldAndDeletesNothing()
    {
        UndoJournal journal = Journal(segmentBytes: 1);
        journal.WithLock(writer => Step(writer, 1));
        journal.WithLock(writer => Step(writer, 2));
        string unneeded = journal.WithLock(writer => writer.WriteBlob(Encoding.UTF8.GetBytes("nobody names this\n")));
        var segments = Directory.GetFiles(_folder, "journal-*.jsonl").Order().ToList();
        var before = segments.Select(File.ReadAllBytes).ToList();
        bool ran = false;
        using (new FileStream(Segment(1), FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            Assert.Equal(UndoJournalFailure.ListNotReadable, Assert.IsType<UndoJournalException>(Record.Exception(() =>
                journal.WithLock(writer =>
                {
                    ran = true;
                    writer.Append(Event(2, "undoing"));
                    new UndoDoor(journal, UndoMode.Live).RecoverThenPrune(writer);
                }))).Failure);
        }
        Assert.False(ran);
        Assert.Equal(segments, Directory.GetFiles(_folder, "journal-*.jsonl").Order().ToList());
        Assert.Equal(before, segments.Select(File.ReadAllBytes).ToList());
        Assert.True(File.Exists(journal.BlobPath(unneeded)));
    }

    [Fact]
    public void TheListLivesInTheAppsStateFolderNeverAWorkingFolder()
    {
        Assert.Contains("%LOCALAPPDATA%\\Plantoir\\undo\\ on Windows", UndoContract.Journal.GetProperty("directory").GetString());
        Assert.Equal(Path.Combine(Plantoir.Core.Models.AppDataRoot.Current, "undo"), UndoJournalLocation.Folder);
    }
}

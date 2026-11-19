using System.Text;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The journal read from the DISK (#899 piece W1): segments, line endings,
/// torn lines, held files, and the instance rule (the plan review's H1). Each
/// test has a folder of its own and a clock of its own; nothing here is a
/// static, so classes running at once cannot share a journal.
/// </summary>
public sealed class UndoJournalReadingTests : IDisposable
{
    private readonly string _folder = RunOwnedTempFolders.Create("plantoir-undo-read-");
    private readonly UndoTestClock _clock = new(new DateTimeOffset(2026, 11, 14, 12, 0, 0, TimeSpan.Zero));

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private const string At = "2026-11-14T12:00:00Z";

    private static string Begin(long seq) =>
        $"{{\"v\":1,\"seq\":{seq},\"event\":\"begin\",\"at\":\"{At}\",\"process\":{{\"host\":\"h\",\"pid\":1,\"name\":\"n\",\"started\":\"s\"}}," +
        $"\"step\":{{\"seq\":{seq},\"madeAt\":\"{At}\",\"ops\":[]}}}}";

    private static string Applied(long seq) => $"{{\"v\":1,\"seq\":{seq},\"event\":\"applied\",\"at\":\"{At}\"}}";

    private UndoJournal Journal(string? folder = null, bool live = false) =>
        new(folder ?? _folder, _clock, _ => true, _ => true, isLive: live, readRetry: TimeSpan.Zero);

    private void Write(int segment, string text) =>
        File.WriteAllBytes(Path.Combine(_folder, $"journal-{segment:D6}.jsonl"), new UTF8Encoding(false).GetBytes(text));

    [Fact]
    public void LinesWrittenWithCarriageReturnsReadAsTheSameEvents()
    {
        Write(1, Begin(1) + "\r\n" + Applied(1) + "\r\n");
        UndoReading reading = Journal().Read();
        Assert.True(reading.IsFresh);
        Assert.Equal(UndoStepState.Done, reading.Folded.Steps[1].State);
        Assert.Empty(reading.Folded.Barriers);
    }

    [Fact]
    public void BytesAfterTheLastLineFeedAreATornLineAndAreNotCounted()
    {
        Write(1, Begin(1) + "\n" + Applied(1) + "\n" + "{\"v\":1,\"seq\":2,\"event\":\"beg");
        UndoReading reading = Journal().Read();
        Assert.True(reading.TornBytes > 0);
        Assert.Empty(reading.Folded.Barriers);   // never a barrier: it is not a line yet
        Assert.Equal(1, reading.Folded.Highest);
        Assert.Equal(1, Journal().Offer(reading.Folded).Undo.Seq);
    }

    [Fact]
    public void ABlankLineIsAnUnreadableLineAndIsKept()
    {
        Write(1, Begin(1) + "\n" + Applied(1) + "\n\n");
        Assert.Single(Journal().Read().Folded.Barriers);
    }

    [Fact]
    public void SegmentsAreReadInTheirNumbersOrderAndOtherFilesArePassedOver()
    {
        Write(2, Applied(1) + "\n");
        Write(1, Begin(1) + "\n");
        File.WriteAllText(Path.Combine(_folder, "journal-1.jsonl"), "garbage\n");
        File.WriteAllText(Path.Combine(_folder, "journal-000003.jsonl.tmp"), "garbage\n");
        File.WriteAllText(Path.Combine(_folder, "computer-id"), Guid.NewGuid().ToString("D") + "\n");
        UndoReading reading = Journal().Read();
        Assert.Equal([1, 2], reading.SegmentsOnDisk);
        Assert.Equal(UndoStepState.Done, reading.Folded.Steps[1].State);
        Assert.Equal([1, 2], reading.Folded.Steps[1].Segments);
        Assert.Empty(reading.Folded.Barriers);
    }

    [Fact]
    public void AnEmptyOrMissingFolderIsAnEmptyList()
    {
        Assert.Empty(Journal(Path.Combine(_folder, "not-there")).Read().Folded.Steps);
        Assert.Equal(UndoAnswerKind.Nothing, Journal().Offer(Journal().Read().Folded).Undo.Kind);
    }

    /// <summary>
    /// rule.readers: a sharing violation is never an unreadable list. The read
    /// that cannot get at a segment gives the LAST state read, marked not
    /// fresh, and nothing on the disk is touched.
    /// </summary>
    [Fact]
    public void ASegmentHeldWithNoSharingGivesTheLastStateReadAndIsNeverReset()
    {
        Write(1, Begin(1) + "\n" + Applied(1) + "\n");
        UndoJournal journal = Journal();
        Assert.True(journal.Read().IsFresh);
        string segment = Path.Combine(_folder, "journal-000001.jsonl");
        byte[] before = File.ReadAllBytes(segment);
        using (new FileStream(segment, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            UndoReading held = journal.Read();
            Assert.False(held.IsFresh);
            Assert.Equal(UndoStepState.Done, held.Folded.Steps[1].State);
        }
        Assert.Equal(before, File.ReadAllBytes(segment));
        Assert.True(journal.Read().IsFresh);
    }

    /// <summary>A reader shares delete: a writer's append or a pruner's delete beside an open read is never refused by it.</summary>
    [Fact]
    public void AReadNeverStandsInTheWayOfAnAppend()
    {
        Write(1, Begin(1) + "\n");
        string segment = Path.Combine(_folder, "journal-000001.jsonl");
        using var reader = new FileStream(segment, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using (var writer = new FileStream(segment, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
            writer.Write(Encoding.UTF8.GetBytes(Applied(1) + "\n"));
        Assert.Equal(UndoStepState.Done, Journal().Read().Folded.Steps[1].State);
    }

    /// <summary>H1: two journals are two instances with their own folders, clocks and switches; nothing is shared.</summary>
    [Fact]
    public void TwoJournalsShareNothing()
    {
        string other = Path.Combine(_folder, "other");
        Directory.CreateDirectory(other);
        Write(1, Begin(1) + "\n" + Applied(1) + "\n");
        var laterClock = new UndoTestClock(new DateTimeOffset(2027, 1, 1, 0, 0, 0, TimeSpan.Zero));
        UndoJournal first = Journal(live: true);
        var second = new UndoJournal(other, laterClock, _ => false, _ => false, isLive: false, readRetry: TimeSpan.Zero);
        Assert.Single(first.Read().Folded.Steps);
        Assert.Empty(second.Read().Folded.Steps);
        Assert.True(first.IsLive);
        Assert.False(second.IsLive);
        Assert.NotEqual(first.Now, second.Now);
        Assert.Equal(1, first.Offer(first.Read().Folded).Undo.Seq);
    }

    [Fact]
    public void ABlobWhoseBytesDoNotHashToItsNameIsMissing()
    {
        byte[] bytes = "content\n"u8.ToArray();
        string name = UndoCheck.Sha(bytes);
        string path = Path.Combine(_folder, "content", name[..2], name);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
        Assert.Equal(bytes, Journal().Blob(name));
        File.WriteAllBytes(path, "tampered\n"u8.ToArray());
        Assert.Null(Journal().Blob(name));
        Assert.Null(Journal().Blob(new string('e', 64)));
        Assert.Equal([name], Journal().BlobsOnDisk());
    }

    [Fact]
    public void TheProcessesLivenessIsWorkLeasesRule()
    {
        Assert.False(UndoJournalChecks.ProcessIsAlive(null));
        Assert.False(UndoJournalChecks.ProcessIsAlive(new UndoProcess("h", 0, "x", null)));
        Assert.False(UndoJournalChecks.ProcessIsAlive(new UndoProcess("h", int.MaxValue - 7, "nothing-runs-by-this-name", null)));
        using var me = System.Diagnostics.Process.GetCurrentProcess();
        Assert.True(UndoJournalChecks.ProcessIsAlive(new UndoProcess("h", Environment.ProcessId, me.ProcessName, null)));
        Assert.False(UndoJournalChecks.ProcessIsAlive(new UndoProcess("h", Environment.ProcessId, "a-name-that-is-not-mine", null)));
    }

    // ---- The mac's U2a read rule, and the W1 review's M2 and M3 ----------

    private UndoJournal JournalOpening(Func<string, Stream> open) =>
        new(_folder, _clock, _ => true, _ => true, isLive: false, readRetry: TimeSpan.Zero, open: open);

    private static Stream Disk(string path) =>
        new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);

    /// <summary>
    /// A segment pruned between the listing and the read is passed over, but
    /// never the NEWEST: a newest segment that is gone is a reading that is
    /// not fresh, never a shorter list (the mac's U2a read rule).
    /// </summary>
    [Fact]
    public void ANewestSegmentThatIsGoneIsNeverPassedOver()
    {
        Write(1, Begin(1) + "\n" + Applied(1) + "\n");
        Write(2, Begin(2) + "\n" + Applied(2) + "\n");
        UndoReading olderGone = JournalOpening(path =>
            path.EndsWith("journal-000001.jsonl", StringComparison.Ordinal) ? throw new FileNotFoundException("pruned") : Disk(path)).Read();
        Assert.True(olderGone.IsFresh);
        Assert.Equal(2, olderGone.Folded.Highest);

        UndoReading newestGone = JournalOpening(path =>
            path.EndsWith("journal-000002.jsonl", StringComparison.Ordinal) ? throw new FileNotFoundException("gone") : Disk(path)).Read();
        Assert.False(newestGone.IsFresh);
    }

    /// <summary>A segment that is there and cannot be read (not a sharing violation) is a reading that is not fresh, never an empty list.</summary>
    [Fact]
    public void ASegmentThatCannotBeReadIsNeverAnEmptyList()
    {
        Write(1, Begin(1) + "\n" + Applied(1) + "\n");
        foreach (Exception failure in new Exception[] { new IOException("the disk failed", unchecked((int)0x80070017)), new UnauthorizedAccessException("denied") })
        {
            UndoReading reading = JournalOpening(_ => throw failure).Read();
            Assert.False(reading.IsFresh);
            Assert.Equal(UndoAnswerKind.NotAvailable, JournalOpening(_ => throw failure).Offer(reading).Undo.Kind);
        }
    }

    /// <summary>A blob that is there and cannot be read is never content missing (which clears the list): the read throws.</summary>
    [Fact]
    public void ABlobThatIsThereAndCannotBeReadIsNeverMissing()
    {
        byte[] bytes = "content\n"u8.ToArray();
        string name = UndoCheck.Sha(bytes);
        string path = Path.Combine(_folder, "content", name[..2], name);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
        Assert.Throws<UndoListUnreadableException>(() =>
            JournalOpening(_ => throw new IOException("the disk failed", unchecked((int)0x80070017))).Blob(name));
        Assert.Null(JournalOpening(_ => throw new FileNotFoundException("gone")).Blob(name));   // gone is missing
    }

    /// <summary>
    /// The W1 review's M2. A reading that is not fresh holds the last state
    /// read beside the segments and blobs on the disk NOW; deciding from that
    /// mix deleted content the list needs. Pruning and deletion decide nothing
    /// from it, and Undo and Redo are not available.
    /// </summary>
    [Fact]
    public void AReadingThatIsNotFreshPrunesAndDeletesNothing()
    {
        Write(1, Begin(1) + "\n" + Applied(1) + "\n");
        string blob = UndoCheck.Sha("x\n"u8.ToArray());
        string blobPath = Path.Combine(_folder, "content", blob[..2], blob);
        Directory.CreateDirectory(Path.GetDirectoryName(blobPath)!);
        File.WriteAllBytes(blobPath, "x\n"u8.ToArray());
        Write(2, $"{{\"v\":1,\"seq\":2,\"event\":\"begin\",\"at\":\"{At}\",\"step\":{{\"seq\":2,\"madeAt\":\"{At}\",\"ops\":[{{\"kind\":\"writeFile\",\"path\":\"a.md\",\"afterSha\":\"{blob}\",\"blobs\":[\"{blob}\"]}}]}}}}\n" + Applied(2) + "\n");

        UndoJournal journal = new(_folder, _clock, _ => true, _ => true, isLive: false, readRetry: TimeSpan.Zero);   // a first read, held: its last state is empty
        string segment = Path.Combine(_folder, "journal-000002.jsonl");
        using (new FileStream(segment, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            UndoReading held = journal.Read();
            Assert.False(held.IsFresh);
            Assert.Empty(journal.Deletable(held).Blobs);
            Assert.Empty(journal.Deletable(held).Segments);
            Assert.Empty(journal.Pruning(held));
            UndoOffered offered = journal.Offer(held);
            Assert.Equal(UndoAnswerKind.NotAvailable, offered.Undo.Kind);
            Assert.Equal(UndoAnswerKind.NotAvailable, offered.Redo.Kind);
        }
        UndoReading fresh = journal.Read();
        Assert.True(fresh.IsFresh);
        Assert.Empty(journal.Deletable(fresh).Blobs);   // named by step 2, on the list
    }

    /// <summary>
    /// The W1 review's M3. A step whose process this version cannot identify
    /// is gone for pruning (nothing in flight for ever) but never settled by
    /// recovery (W3), which writes pages: a live process of another version
    /// may still be swapping files outside the lock.
    /// </summary>
    [Fact]
    public void RecoveryNeverSettlesAStepWhoseProcessItCannotIdentify()
    {
        Assert.False(UndoJournalChecks.ProcessIsAlive(null));
        Assert.False(UndoJournalChecks.RecoveryMaySettle(null));
        Assert.True(UndoJournalChecks.RecoveryMaySettle(new UndoProcess("h", int.MaxValue - 7, "nothing-runs-by-this-name", null)));
        using var me = System.Diagnostics.Process.GetCurrentProcess();
        Assert.False(UndoJournalChecks.RecoveryMaySettle(new UndoProcess("h", Environment.ProcessId, me.ProcessName, null)));
    }

    /// <summary>
    /// "Not there" and "could not tell" are different (the U2a read rule, the
    /// W1 review's second round): a file where the list's folder or its
    /// content folder should be is an error, never an empty list.
    /// </summary>
    [Fact]
    public void AFolderOfTheListThatCannotBeListedIsNeverAnEmptyList()
    {
        string notAFolder = Path.Combine(_folder, "undo-is-a-file");
        File.WriteAllText(notAFolder, "x");
        Assert.False(Journal(notAFolder).Read().IsFresh);

        Write(1, Begin(1) + "\n" + Applied(1) + "\n");
        File.WriteAllText(Path.Combine(_folder, "content"), "x");
        Assert.Throws<UndoListUnreadableException>(() => Journal().BlobsOnDisk());

        // A folder that is simply not there is no segments and no blobs.
        UndoJournal nowhere = Journal(Path.Combine(_folder, "not-there-either"));
        Assert.True(nowhere.Read().IsFresh);
        Assert.Empty(nowhere.BlobsOnDisk());
    }
}

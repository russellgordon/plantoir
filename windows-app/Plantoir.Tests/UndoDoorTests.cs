using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The door (#899 W2b, <c>rule.writeAhead</c>) and the fixes W2a's review
/// asked for, through the real journal and the real swap. Every test was seen
/// to fail with its behaviour taken out (vm-tools/guest/899-w2b-mustfail.json).
/// </summary>
public sealed class UndoDoorTests : IDisposable
{
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-door-");
    private readonly UndoTestClock _clock = new(new DateTimeOffset(2026, 11, 20, 12, 0, 0, TimeSpan.Zero));
    private readonly UndoProcessMemory _memory = new();
    private readonly HashSet<long> _alive = [Environment.ProcessId];

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Folder => Path.Combine(_root, "wf");
    private string JournalFolder => Path.Combine(_root, "undo");

    private UndoJournal Journal(Func<string, Stream>? open = null) =>
        new(JournalFolder, _clock, process => process is not null && _alive.Contains(process.Pid),
            step => UndoJournalChecks.FolderIsReachable(step, _clock), isLive: true, memory: _memory, readRetry: TimeSpan.Zero, open: open);

    private const string APage = "courses/TST1O/Section 1/a.md";
    private static readonly byte[] Old = Encoding.UTF8.GetBytes("---\ntitle: A\npublish: false\n---\nBody.\n");
    private static readonly byte[] New = Encoding.UTF8.GetBytes("---\ntitle: A\npublish: true\n---\nBody.\n");

    private string Full(string relative) => UndoDoor.FullPath(Folder, relative);

    private void Write(string relative, byte[] bytes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.WriteAllBytes(Full(relative), bytes);
    }

    private UndoStepDraft Draft(params (string Path, byte[]? Before, byte[]? After)[] changes) => new()
    {
        ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = Folder, Course = "TST1O", Section = 1, Holds = "section",
        Changes = changes.Select(change => new UndoFileChange(change.Path, change.Before, change.After)).ToList(),
    };

    /// <summary><c>rule.writeAhead</c>: the begin, naming every op, is on the disk before the first page is touched.</summary>
    [Fact]
    public void TheBeginIsOnTheDiskBeforeThePageChanges()
    {
        Write(APage, Old);
        UndoJournal journal = Journal();
        var door = new UndoDoor(journal, UndoMode.Live, seams: new UndoSeams { StopsHere = (point, _) => point == "afterBegin" });
        Assert.Equal(UndoOutcomeKind.StoppedByATest, door.Perform(Draft((APage, Old, New))).Kind);
        Assert.Equal(Old, File.ReadAllBytes(Full(APage)));
        UndoFoldedStep step = Assert.Single(journal.Read().Folded.Steps.Values);
        Assert.Equal(UndoStepState.Begun, step.State);
        Assert.Equal(Environment.ProcessId, step.Process!.Pid);
        Assert.Equal(APage, Assert.Single(step.Step.Ops).Path);
    }

    /// <summary>
    /// W2a's review, LOW 2: a blob already on the disk that nothing on the list
    /// names is used as it is by a step whose content it holds; the step's
    /// blobs and its begin are ONE hold that never prunes, so no pruning can
    /// delete the blob between storing it and the begin that names it, and the
    /// step can still be undone.
    /// </summary>
    [Fact]
    public void AStepsBlobsAndItsBeginAreOneHoldSoNoPruningCanTakeABlobItReuses()
    {
        byte[] before = [.. Old, .. Encoding.UTF8.GetBytes("A line the step will take away.\n")];
        byte[] after = [.. New, .. Encoding.UTF8.GetBytes("A line the step added.\n")];
        Write(APage, before);
        UndoJournal journal = Journal();
        // Both blobs are on the disk already, named by nothing on the list.
        journal.WithLock(writer => writer.WriteBlobs([before, after], 1));
        Assert.Empty(journal.Read().Folded.Steps);

        var door = new UndoDoor(journal, UndoMode.Live);
        UndoOutcome made = door.Perform(Draft((APage, before, after)));
        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
        Assert.Equal(UndoOp.WriteFile, Assert.Single(journal.Read().Folded.Steps[made.Seq!.Value].Step.Ops).Kind);
        Assert.NotNull(journal.Blob(UndoCheck.Sha(before)));
        Assert.Equal("undone", door.Undo().Word);
        Assert.Equal(before, File.ReadAllBytes(Full(APage)));
    }

    /// <summary><c>rule.writeAhead</c>: a step refused at its swap is closed failed, and the redo branch is left as it was (cut only when a step is APPLIED).</summary>
    [Fact]
    public void ARefusedStepClosesFailedAndLeavesTheRedoBranch()
    {
        const string other = "courses/TST1O/Section 1/b.md";
        Write(APage, Old);
        Write(other, Old);
        UndoJournal journal = Journal();
        var door = new UndoDoor(journal, UndoMode.Live);
        Assert.Equal(UndoOutcomeKind.Applied, door.Perform(Draft((APage, Old, New))).Kind);
        Assert.Equal("undone", door.Undo().Word);
        UndoOutcome refused;
        using (var holder = new FileStream(Full(other), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        {
            refused = door.Perform(Draft((other, Old, New)));
        }
        Assert.Equal("fileIsInUse", refused.Word);
        UndoReading reading = journal.Read();
        Assert.Equal(UndoStepState.Failed, reading.Folded.Steps[refused.Seq!.Value].State);
        Assert.Equal(1, journal.Offer(reading).Redo.Seq);
        Assert.Equal(Old, File.ReadAllBytes(Full(other)));
        Assert.Empty(UndoStepContractTests.StagedFilesUnder(Folder));
    }

    /// <summary>The core review's I3 (the mac): a closing the lock refuses is kept by the process and written first at its next hold, so the step is not left in flight.</summary>
    [Fact]
    public void AClosingTheLockRefusesIsKeptAndWrittenAtTheNextHold()
    {
        Write(APage, Old);
        UndoJournal journal = Journal();
        UndoLock? held = null;
        var seams = new UndoSeams
        {
            StopsHere = (point, _) =>
            {
                // Another process takes the lock between the swap and the closing.
                if (point == "beforeApplied") held = UndoLock.Take(journal.LockPath, UndoJournal.LiveWait, false, new UndoProcessMemory());
                return false;
            },
        };
        var door = new UndoDoor(journal, UndoMode.Live, seams: seams, finishWait: TimeSpan.FromMilliseconds(200));
        UndoOutcome made = door.Perform(Draft((APage, Old, New)));
        held!.Dispose();
        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
        Assert.Equal(1, _memory.PendingClosingsFor(JournalFolder));
        Assert.Equal(UndoStepState.Begun, journal.Read().Folded.Steps[made.Seq!.Value].State);
        journal.WithLock(_ => { });
        Assert.Equal(0, _memory.PendingClosingsFor(JournalFolder));
        Assert.Equal(UndoStepState.Done, journal.Read().Folded.Steps[made.Seq!.Value].State);
    }

    /// <summary><c>opKinds.recompute</c>: with no runner for its maintainer a step holding a recompute is not available, never undone with its re-derivation skipped; with one, it is re-derived after the swaps.</summary>
    [Fact]
    public void AStepHoldingARecomputeIsUndoneOnlyWithARunnerForItsMaintainer()
    {
        Write(APage, Old);
        UndoJournal journal = Journal();
        var maintainers = new UndoScribe.FrontPageMaintainer();
        UndoStepDraft draft = Draft((APage, Old, New)) with
        {
            Recomputes = [new JsonObject { ["kind"] = "recompute", ["maintainer"] = "sectionFrontPage", ["path"] = "courses/TST1O/Section 1/index.md", ["section"] = 1 }],
        };
        Assert.Equal(UndoOutcomeKind.Applied, new UndoDoor(journal, UndoMode.Live, maintainers).Perform(draft).Kind);
        Assert.Equal(1, maintainers.Rederived);
        Assert.Equal("notAvailable", new UndoDoor(journal, UndoMode.Live).Undo().Word);
        Assert.Equal(New, File.ReadAllBytes(Full(APage)));
        Assert.Equal("undone", new UndoDoor(journal, UndoMode.Live, maintainers).Undo().Word);
        Assert.Equal(2, maintainers.Rederived);
    }

    /// <summary>The one entry for every kind: a step holding an op this version cannot read yet (U2b's <c>move</c>, W6's) is refused before anything is written.</summary>
    [Fact]
    public void AStepGivenAsOpsOfAKindThisVersionCannotReadIsRefusedBeforeAnythingIsWritten()
    {
        Write(APage, Old);
        UndoJournal journal = Journal();
        var draft = new UndoOpsDraft
        {
            ActionKey = "rollOver", MadeBy = "menu", WorkingFolder = Folder, Course = "TST1O", Section = 1, Holds = "section",
            Ops = [new JsonObject { ["kind"] = "move", ["from"] = APage, ["to"] = "courses/TST1O/Section 1/b.md" }],
        };
        UndoOutcome outcome = new UndoDoor(journal, UndoMode.Live).Perform(draft);
        Assert.Equal("notReadable", outcome.Word);
        Assert.Empty(journal.Read().Folded.Steps);
        Assert.Equal(Old, File.ReadAllBytes(Full(APage)));
    }

    /// <summary>A step given as ops of a kind this version reads is planned forward, made, undone and redone by the same check and swap.</summary>
    [Fact]
    public void AStepGivenAsOpsIsMadeUndoneAndRedone()
    {
        Write(APage, Old);
        UndoJournal journal = Journal();
        var draft = new UndoOpsDraft
        {
            ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = Folder, Course = "TST1O", Section = 1, Holds = "section",
            Ops = UndoLineOps.ForAFile(APage, Old, New),
        };
        var door = new UndoDoor(journal, UndoMode.Live);
        Assert.Equal(UndoOutcomeKind.Applied, door.Perform(draft).Kind);
        Assert.Equal(New, File.ReadAllBytes(Full(APage)));
        Assert.Equal("undone", door.Undo().Word);
        Assert.Equal(Old, File.ReadAllBytes(Full(APage)));
        Assert.Equal("redone", door.Redo().Word);
        Assert.Equal(New, File.ReadAllBytes(Full(APage)));
    }

    /// <summary>
    /// <c>rule.recovery</c> and <c>undoJournal.stagedFiles</c>: a dead process's
    /// step pruning closes <c>unsettled</c> leaves none of its staged files in a
    /// course when its folder can be reached; another step's are not touched.
    /// </summary>
    [Fact]
    public void PruningTidiesTheStagedFilesOfAStepItClosesUnsettled()
    {
        Write(APage, Old);
        UndoJournal journal = Journal();
        var door = new UndoDoor(journal, UndoMode.Live);
        // A dead process's step 1, begun on a.md and never finished, with its staged files left beside the page.
        string identity = new FolderIdentityFile(Path.Combine(Folder, "courses", ".internal", "folder-id"), _clock).ReadOrMake()!;
        journal.WithLock(writer => writer.Append(new JsonObject
        {
            ["seq"] = 1, ["event"] = "begin",
            ["process"] = new JsonObject { ["host"] = "h", ["pid"] = 4_000_002, ["name"] = "plantoir-mcp", ["started"] = "1.000000" },
            ["step"] = new JsonObject
            {
                ["seq"] = 1, ["madeAt"] = UndoMoment.Format(_clock.GetUtcNow()), ["madeBy"] = "menu", ["holds"] = "section", ["course"] = "TST1O",
                ["workingFolder"] = new JsonObject { ["id"] = identity, ["pathAtTheTime"] = Folder },
                ["ops"] = UndoLineOps.ForAFile(APage, Old, New),
            },
        }));
        string stagedNew = UndoSwap.BesidePath(Full(APage), "1-apply", "new");
        string stagedOrig = UndoSwap.BesidePath(Full(APage), "1-undo", "orig");
        string anotherStepsFile = UndoSwap.BesidePath(Full(APage), "17-apply", "new");
        foreach (string staged in new[] { stagedNew, stagedOrig, anotherStepsFile }) File.WriteAllBytes(staged, New);

        // Sixty-one days on, a step on another page prunes: the dead step is past the limits.
        _clock.Advance(TimeSpan.FromDays(61));
        const string other = "courses/TST1O/Section 1/b.md";
        Write(other, Old);
        Assert.Equal(UndoOutcomeKind.Applied, door.Perform(Draft((other, Old, New))).Kind);

        UndoFolded folded = journal.Read().Folded;
        Assert.Equal(UndoStepState.Interrupted, folded.Steps[1].State);
        Assert.False(File.Exists(stagedNew), "a staged file of the step closed unsettled was left beside the page");
        Assert.False(File.Exists(stagedOrig), "a staged file of the step closed unsettled was left beside the page");
        Assert.True(File.Exists(anotherStepsFile), "another step's staged file was removed");
        Assert.Equal(Old, File.ReadAllBytes(Full(APage)));
    }

    /// <summary>
    /// W2a's review, LOW 1: a reading that is not fresh hands out the last state
    /// read, and a hold's writer folds its own lines into a COPY, so a reading
    /// taken on the side during a hold never changes as the hold writes.
    /// </summary>
    [Fact]
    public void AReadingThatIsNotFreshDuringAHoldNeverChangesAsTheHoldWrites()
    {
        bool failReads = false;
        UndoJournal journal = Journal(open: path => failReads
            ? throw new IOException("The process cannot access the file because it is being used by another process.", unchecked((int)0x80070020))
            : UndoJournal.OpenSegmentToRead(path));
        journal.WithLock(writer => writer.Append(new JsonObject { ["seq"] = 1, ["event"] = "note" }));
        journal.WithLock(writer =>
        {
            writer.Append(new JsonObject { ["seq"] = 2, ["event"] = "note" });
            failReads = true;
            UndoReading aside = journal.Read();
            failReads = false;
            Assert.False(aside.IsFresh);
            long seen = aside.Folded.Highest;
            writer.Append(new JsonObject { ["seq"] = 3, ["event"] = "note" });
            Assert.Equal(seen, aside.Folded.Highest);
            Assert.Equal(1, seen);
        });
    }

    /// <summary>W2a's review, LOW 5: the process's memory is a required argument, never made quietly by a journal of its own.</summary>
    [Fact]
    public void AJournalIsAlwaysGivenItsProcesssMemory()
    {
        ConstructorInfo constructor = Assert.Single(typeof(UndoJournal).GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public));
        ParameterInfo memory = constructor.GetParameters().Single(parameter => parameter.Name == "memory");
        Assert.False(memory.IsOptional, "the process memory has a default");
        Assert.Throws<ArgumentNullException>(() => new UndoJournal(JournalFolder, _clock, _ => true, _ => true, isLive: false, memory: null!));
    }

    /// <summary>
    /// W2a's review, LOW 6: whether a folder reads on is judged by the volume
    /// the folder is REALLY on, links followed, not by its drive letter. A
    /// folder on C: reached through a link to a network share reads whole.
    /// </summary>
    [SymbolicLinkToAShareFact]
    public void AFolderReachedThroughALinkToAShareIsReadWhole()
    {
        Assert.True(UndoFileIdentity.IsStableHere(_root), "the system volume, read on");
        string link = Path.Combine(_root, "through-a-share");
        Directory.CreateSymbolicLink(link, SymbolicLinkToAShareFactAttribute.ShareOf(Path.Combine(_root, "real")));
        Assert.Equal("network", UndoPlaces.FileSystemOf(link));
        Assert.False(UndoFileIdentity.IsStableHere(link), "a folder on a share reached through a link on C: would read on");
    }
}

/// <summary>
/// Runs only where this account may make a directory symbolic link to the
/// loopback administrative share (<c>\\localhost\C$</c>): an administrator's
/// token, or Developer Mode. Says why when it skips.
/// </summary>
public sealed class SymbolicLinkToAShareFactAttribute : FactAttribute
{
    internal static string ShareOf(string localFolder)
    {
        Directory.CreateDirectory(localFolder);
        string full = Path.GetFullPath(localFolder);
        return @"\\localhost\" + full[0] + "$" + full[2..];
    }

    public SymbolicLinkToAShareFactAttribute()
    {
        if (!OperatingSystem.IsWindows()) { Skip = "Windows only"; return; }
        string probe = Path.Combine(Path.GetTempPath(), "plantoir-undo-link-probe-" + Guid.NewGuid().ToString("N"));
        try
        {
            string target = ShareOf(probe + "-target");
            if (!Directory.Exists(target)) { Skip = "the loopback administrative share is not reachable here"; return; }
            Directory.CreateSymbolicLink(probe, target);
        }
        catch (Exception error)
        {
            Skip = "a symbolic link to a share cannot be made by this account: " + error.Message;
        }
        finally
        {
            try { if (Directory.Exists(probe)) Directory.Delete(probe); } catch { }
            try { Directory.Delete(probe + "-target"); } catch { }
        }
    }
}

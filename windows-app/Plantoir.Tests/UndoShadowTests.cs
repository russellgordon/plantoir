using System.Text;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W4, <c>rule.shadow</c>: while the switch is off, a failure of the
/// list NEVER stops or changes what the teacher asked for. Each test injects
/// one way the list can fail into a real step through the real door in shadow
/// mode and checks the change went in exactly as it would with no list at all
/// (every page wholly the bytes asked for, nothing staged left beside it),
/// with no exception reaching the caller. And the switch itself is off.
/// </summary>
public sealed class UndoShadowTests : IDisposable
{
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-shadow-");
    private readonly UndoTestClock _clock = new(new DateTimeOffset(2026, 11, 20, 12, 0, 0, TimeSpan.Zero));
    private readonly UndoProcessMemory _memory = new();

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Folder => Path.Combine(_root, "wf");
    private string JournalFolder => Path.Combine(_root, "undo");

    private UndoJournal Journal(Func<string, Stream>? open = null, UndoProcessMemory? memory = null) =>
        new(JournalFolder, _clock, process => process is not null && process.Pid == Environment.ProcessId,
            step => UndoJournalChecks.FolderIsReachable(step, _clock), isLive: false, memory: memory ?? _memory,
            readRetry: TimeSpan.Zero, open: open);

    private const string APage = "courses/TST1O/Section 1/a.md";
    private const string AnotherPage = "courses/TST1O/Section 1/b.md";
    private static readonly byte[] Old = Encoding.UTF8.GetBytes("---\ntitle: A\npublish: false\n---\nBody.\n");
    private static readonly byte[] New = Encoding.UTF8.GetBytes("---\ntitle: A\npublish: true\n---\nBody.\n");

    /// <summary>A change the line model cannot describe: a whole-file step, whose content goes into the list's blobs.</summary>
    private static readonly byte[] Rewritten = Encoding.UTF8.GetBytes("---\ntitle: A\npublish: true\n---\nA new body, written whole.\nAnd a second line.\n");

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

    /// <summary>The teacher's change, unchanged by the list: each page holds exactly what was asked for, and nothing staged is left in the course.</summary>
    private void TheChangeWentInWhole(UndoOutcome outcome, params (string Path, byte[] After)[] pages)
    {
        Assert.True(outcome.Kind is UndoOutcomeKind.Applied or UndoOutcomeKind.AppliedWithoutARecord, "the change did not go ahead: " + outcome.Word);
        foreach ((string path, byte[] after) in pages) Assert.Equal(after, File.ReadAllBytes(Full(path)));
        var staged = Directory.EnumerateFiles(Path.Combine(Folder, "courses"), "*", SearchOption.AllDirectories)
                              .Where(name => Path.GetFileName(name).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal)).ToList();
        Assert.Empty(staged);
    }

    /// <summary>Holds the list's lock from another process's journal (its own memory) until disposed.</summary>
    private sealed class AnotherHolder : IDisposable
    {
        private readonly ManualResetEventSlim _taken = new();
        private readonly ManualResetEventSlim _release = new();
        private readonly Thread _thread;

        internal AnotherHolder(UndoJournal journal)
        {
            _thread = new Thread(() => journal.WithLock(_ => { _taken.Set(); _release.Wait(); })) { IsBackground = true };
            _thread.Start();
            Assert.True(_taken.Wait(TimeSpan.FromSeconds(30)), "the other holder never got the lock");
        }

        public void Dispose()
        {
            _release.Set();
            _thread.Join();
        }
    }

    /// <summary>The switch is off (W4): the list is written in shadow and never offered.</summary>
    [Fact]
    public void TheSwitchIsOffAndTheAppRecordsInShadow()
    {
        Assert.False(UndoSwitch.UndoJournalIsLive);
        Assert.Equal(UndoMode.Shadow, UndoSwitch.CurrentMode);
    }

    /// <summary>Another process holds the lock past the 50 ms shadow wait: the change goes ahead, unrecorded.</summary>
    [Fact]
    public void ALockHeldPastTheShadowWaitLetsTheChangeGoAhead()
    {
        Write(APage, Old);
        Write(AnotherPage, Old);
        using (new AnotherHolder(Journal(memory: new UndoProcessMemory())))
        {
            var door = new UndoDoor(Journal(), UndoMode.Shadow);
            UndoOutcome first = door.Perform(Draft((APage, Old, New)));
            Assert.Equal(UndoOutcomeKind.AppliedWithoutARecord, first.Kind);
            TheChangeWentInWhole(first, (APage, New));
            // The try-once that follows a shadow wait that ran out (rule.oneLock): the same.
            Assert.True(_memory.ShadowHasGivenUp(JournalFolder));
            UndoOutcome second = door.Perform(Draft((AnotherPage, Old, New)));
            TheChangeWentInWhole(second, (AnotherPage, New));
        }
        Assert.Empty(Journal().Read().Folded.Steps);
    }

    /// <summary>The list's folder cannot be made (a file stands where it goes).</summary>
    [Fact]
    public void AListFolderThatCannotBeMadeLetsTheChangeGoAhead()
    {
        Write(APage, Old);
        Directory.CreateDirectory(_root);
        File.WriteAllText(JournalFolder, "not a folder");
        UndoOutcome outcome = new UndoDoor(Journal(), UndoMode.Shadow).Perform(Draft((APage, Old, New)));
        Assert.Equal(UndoOutcomeKind.AppliedWithoutARecord, outcome.Kind);
        TheChangeWentInWhole(outcome, (APage, New));
    }

    /// <summary>The list cannot be read inside the lock (a disk error on its segment).</summary>
    [Fact]
    public void AListThatCannotBeReadLetsTheChangeGoAhead()
    {
        Write(APage, Old);
        new UndoDoor(Journal(), UndoMode.Shadow).Perform(Draft((AnotherPage, null, Old)));
        UndoJournal failing = Journal(open: path => path.EndsWith(".jsonl", StringComparison.Ordinal)
            ? throw new IOException("The device is not ready.")
            : File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete));
        UndoOutcome outcome = new UndoDoor(failing, UndoMode.Shadow).Perform(Draft((APage, Old, New)));
        Assert.Equal(UndoOutcomeKind.AppliedWithoutARecord, outcome.Kind);
        TheChangeWentInWhole(outcome, (APage, New));
    }

    /// <summary>
    /// A step given as its ops (the one entry for every kind) whose begin
    /// cannot be written is refused before anything changes, in EITHER mode,
    /// as the mac's <c>JournaledWrite.perform(ops:)</c> says: no action reaches
    /// this entry before U3 and U4 (W7, W8), which settle how a shadow step of
    /// these kinds is recorded beside the action's own writes. So the
    /// files entry above is the one whose action shadow never stops.
    /// </summary>
    [Theory]
    [InlineData("lines")]
    [InlineData("whole")]
    public void AStepGivenAsItsOpsIsRefusedBeforeAnythingChangesWhenTheListCannotBeWritten(string shape)
    {
        byte[] after = shape == "lines" ? New : Rewritten;
        Write(APage, Old);
        Directory.CreateDirectory(_root);
        File.WriteAllText(JournalFolder, "not a folder");
        var draft = new UndoOpsDraft
        {
            ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = Folder, Course = "TST1O", Section = 1, Holds = "section",
            Ops = UndoLineOps.ForAFile(APage, Old, after), Blobs = [Old, after],
        };
        UndoOutcome outcome = new UndoDoor(Journal(), UndoMode.Shadow).Perform(draft);
        Assert.Equal(UndoOutcomeKind.CouldNotRecordTheStep, outcome.Kind);
        Assert.Equal(Old, File.ReadAllBytes(Full(APage)));
    }

    /// <summary>The working folder's identifier cannot be read or made (<c>courses\.internal</c> is a file).</summary>
    [Fact]
    public void AFolderIdentifierThatCannotBeMadeLetsTheChangeGoAhead()
    {
        Write(APage, Old);
        File.WriteAllText(Path.Combine(Folder, "courses", ".internal"), "not a folder");
        UndoOutcome outcome = new UndoDoor(Journal(), UndoMode.Shadow).Perform(Draft((APage, Old, New)));
        Assert.Equal(UndoOutcomeKind.AppliedWithoutARecord, outcome.Kind);
        TheChangeWentInWhole(outcome, (APage, New));
    }

    /// <summary>The step's content cannot be stored (the list's <c>content</c> folder cannot be made).</summary>
    [Fact]
    public void ContentThatCannotBeStoredLetsTheChangeGoAhead()
    {
        Write(APage, Old);
        Directory.CreateDirectory(JournalFolder);
        File.WriteAllText(Path.Combine(JournalFolder, "content"), "not a folder");
        UndoOutcome outcome = new UndoDoor(Journal(), UndoMode.Shadow).Perform(Draft((APage, Old, Rewritten)));
        Assert.Equal(UndoOutcomeKind.AppliedWithoutARecord, outcome.Kind);
        TheChangeWentInWhole(outcome, (APage, Rewritten));
    }

    /// <summary>A failure of a kind the list does not expect (not a disk or permission error): the change still goes ahead.</summary>
    [Fact]
    public void AnUnforeseenFailureOfTheListLetsTheChangeGoAhead()
    {
        Write(APage, Old);
        new UndoDoor(Journal(), UndoMode.Shadow).Perform(Draft((AnotherPage, null, Old)));
        UndoJournal failing = Journal(open: _ => throw new InvalidOperationException("Something nobody planned for."));
        UndoOutcome outcome = new UndoDoor(failing, UndoMode.Shadow).Perform(Draft((APage, Old, New)));
        Assert.Equal(UndoOutcomeKind.AppliedWithoutARecord, outcome.Kind);
        TheChangeWentInWhole(outcome, (APage, New));
    }

    /// <summary>The closing finds the lock busy after the pages are in: the change stands, its closing kept for the next hold.</summary>
    [Fact]
    public void AClosingThatFindsTheLockBusyLeavesTheChangeAsItIs()
    {
        Write(APage, Old);
        UndoJournal journal = Journal();
        AnotherHolder? holder = null;
        var door = new UndoDoor(journal, UndoMode.Shadow, seams: new UndoSeams
        {
            StopsHere = (point, _) =>
            {
                if (point == "beforeApplied") holder = new AnotherHolder(Journal(memory: new UndoProcessMemory()));
                return false;
            },
        });
        UndoOutcome outcome;
        try { outcome = door.Perform(Draft((APage, Old, New))); }
        finally { holder?.Dispose(); }
        TheChangeWentInWhole(outcome, (APage, New));
        Assert.Equal(1, _memory.PendingClosingsFor(JournalFolder));
    }

    /// <summary>The closing cannot read the list at all, of any kind of failure: the change stands and nothing reaches the caller.</summary>
    [Theory]
    [InlineData("disk")]
    [InlineData("unforeseen")]
    public void AClosingThatCannotReadTheListLeavesTheChangeAsItIs(string failure)
    {
        Write(APage, Old);
        bool failing = false;
        UndoJournal journal = Journal(open: path =>
        {
            if (failing && failure == "disk") throw new IOException("The device is not ready.");
            if (failing) throw new InvalidOperationException("Something nobody planned for.");
            return File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        });
        var door = new UndoDoor(journal, UndoMode.Shadow, seams: new UndoSeams
        {
            StopsHere = (point, _) =>
            {
                if (point == "beforeApplied") failing = true;
                return false;
            },
        });
        UndoOutcome outcome = door.Perform(Draft((APage, Old, New)));
        TheChangeWentInWhole(outcome, (APage, New));
    }

    /// <summary>And a shadow step whose list works is recorded, so the failures above are what made the difference.</summary>
    [Fact]
    public void WithTheListWorkingTheShadowStepIsRecorded()
    {
        Write(APage, Old);
        UndoOutcome outcome = new UndoDoor(Journal(), UndoMode.Shadow).Perform(Draft((APage, Old, New)));
        Assert.Equal(UndoOutcomeKind.Applied, outcome.Kind);
        TheChangeWentInWhole(outcome, (APage, New));
        Assert.Equal(UndoStepState.Done, Assert.Single(Journal().Read().Folded.Steps.Values).State);
    }
}

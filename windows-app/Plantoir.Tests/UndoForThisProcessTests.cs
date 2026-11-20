using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W4: the list as one process of the app holds it
/// (<see cref="UndoForThisProcess"/>): where it lives, recovery at launch, the
/// trail line wired, and what a process does when another holds the lock
/// through a long put-back (W3 measured a 232-page put-back holding it 1.2 s
/// outside OneDrive and 2.7 s inside, past the 2 s live wait).
/// </summary>
public sealed class UndoForThisProcessTests : IDisposable
{
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-process-");

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");

    private const string First = "courses/TST1O/Section 1/a.md";
    private const string Second = "courses/TST1O/Section 1/b.md";
    private const string Third = "courses/TST1O/Section 1/c.md";

    private static byte[] Old(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: false\n---\nThe lesson.\n");
    private static byte[] New(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: true\n---\nThe lesson.\n");

    private string Full(string relative) => UndoDoor.FullPath(Folder, relative);

    private void Write(string relative, byte[] bytes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.WriteAllBytes(Full(relative), bytes);
    }

    private UndoStepDraft Draft(params string[] pages) => new()
    {
        ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = Folder, Course = "TST1O", Section = 1, Holds = "section",
        Changes = pages.Select(page => new UndoFileChange(page, Old(page), New(page))).ToList(),
    };

    /// <summary>A process that is never running: Windows process ids are multiples of four.</summary>
    private static JsonObject AGoneProcess() => new()
    {
        ["host"] = Environment.MachineName, ["pid"] = 4_000_002, ["name"] = "Plantoir", ["started"] = "1.000000",
    };

    /// <summary>Another process's journal on the same list: its own memory, the real liveness and reach checks.</summary>
    private UndoJournal AnotherProcessesJournal() =>
        new(ListFolder, TimeProvider.System, UndoJournalChecks.ProcessIsAlive,
            step => UndoJournalChecks.FolderIsReachable(step, TimeProvider.System), isLive: true, memory: new UndoProcessMemory());

    /// <summary>A gone process's two-page step, stopped at a kill point.</summary>
    private void AGoneProcessStopsAStepAt(string point, int index = -1)
    {
        Write(First, Old(First));
        Write(Second, Old(Second));
        var seams = new UndoSeams { StopsHere = (at, where) => at == point && (index < 0 || where == index) };
        UndoOutcome stopped = new UndoDoor(AnotherProcessesJournal(), UndoMode.Live, seams: seams, process: AGoneProcess())
            .Perform(Draft(First, Second));
        Assert.Equal(UndoOutcomeKind.StoppedByATest, stopped.Kind);
    }

    /// <summary>
    /// <c>undoJournal.directory</c>, step 7 of #949: the list is <c>undo\</c> in
    /// the state folder, which follows <c>--state-dir</c> (this test process
    /// runs redirected), and this process's list is made from it, in the
    /// switch's mode, with the real trail as its sink.
    /// </summary>
    [Fact]
    public void ThisProcessesListIsUndoInTheStateFolderInTheSwitchesModeWithTheRealTrail()
    {
        Assert.True(AppDataRoot.IsRedirected, "the unit suite runs with its state redirected");
        Assert.Equal(Path.Combine(AppDataRoot.Current, "undo"), UndoJournalLocation.Folder);
        UndoForThisProcess current = UndoForThisProcess.Current;
        Assert.Equal(UndoJournalLocation.Folder, current.Folder);
        Assert.Equal(UndoJournalLocation.Folder, current.Journal.Folder);
        Assert.Equal(UndoSwitch.CurrentMode, current.Mode);
        Assert.Equal(current.Mode == UndoMode.Live, current.Journal.IsLive);
        Assert.Equal(new Action<UndoTrailLine>(UndoTrail.ToTheActivityTrail), current.Trail);
        Assert.Same(current, UndoForThisProcess.Current);
    }

    /// <summary>
    /// The window and <c>plantoir-mcp.exe</c> are told the same folder: the
    /// window hands its own server <c>--state-dir</c> when it has one (#641),
    /// and each process's list is <c>undo\</c> under whatever folder its
    /// command line names, the default when it names none.
    /// </summary>
    [Fact]
    public void TheWindowAndItsServerAreToldTheSameStateFolder()
    {
        string redirected = Path.Combine(_root, "state");
        IReadOnlyList<string> handedOn = AppDataRoot.HandOnArguments(redirected);
        Assert.Equal(redirected, AppDataRoot.StateDirFrom(handedOn));
        Assert.Empty(AppDataRoot.HandOnArguments(null));
        Assert.Null(AppDataRoot.StateDirFrom(AppDataRoot.HandOnArguments(null)));
    }

    /// <summary>
    /// Recovery at launch, as the app runs it (shadow): a gone process's step
    /// is settled by content, recorded, and nothing is written into the
    /// working folder (<c>rule.shadow</c>: "Recovery in this mode never writes
    /// into a working folder"). Stopped after its begin: <c>failed</c>, nothing
    /// took effect. Stopped half way: <c>interrupted</c>, partly took effect,
    /// the list cleared, the pages left exactly as the stopped step left them.
    /// </summary>
    [Theory]
    [InlineData("afterBegin", -1)]
    [InlineData("beforeSwap", 1)]
    public void RecoveryAtLaunchInShadowRecordsAStepAGoneProcessLeftAndWritesNoPage(string point, int index)
    {
        AGoneProcessStopsAStepAt(point, index);
        byte[] firstBefore = File.ReadAllBytes(Full(First));
        byte[] secondBefore = File.ReadAllBytes(Full(Second));
        var trail = new List<UndoTrailLine>();
        var app = new UndoForThisProcess(ListFolder, UndoMode.Shadow, trail.Add);

        UndoRecoveryRun? run = app.RecoverAtLaunch();

        Assert.NotNull(run);
        UndoRecoveryResult settled = Assert.Single(run!.Settled);
        UndoFoldedStep step = Assert.Single(app.Journal.Read().Folded.Steps.Values);
        Assert.False(step.IsInFlight);
        if (point == "afterBegin")
        {
            Assert.Equal(UndoRecoveryOutcome.NothingTookEffect, settled.Outcome);
            Assert.Equal(UndoStepState.Failed, step.State);
        }
        else
        {
            Assert.Equal(UndoRecoveryOutcome.LeftAlone, settled.Outcome);
            Assert.Equal(UndoStepState.Interrupted, step.State);
        }
        Assert.Equal(firstBefore, File.ReadAllBytes(Full(First)));
        Assert.Equal(secondBefore, File.ReadAllBytes(Full(Second)));
        Assert.Empty(trail);
    }

    /// <summary>
    /// The trail line is wired: a live process's recovery at launch puts back a
    /// half-made step and says so through the sink it was given (in the app,
    /// <see cref="UndoTrail.ToTheActivityTrail"/>), in the contract's words.
    /// </summary>
    [Fact]
    public void RecoveryAtLaunchLiveRollsBackAndWritesTheTrailLine()
    {
        AGoneProcessStopsAStepAt("beforeSwap", 1);
        var trail = new List<UndoTrailLine>();
        var app = new UndoForThisProcess(ListFolder, UndoMode.Live, trail.Add);

        UndoRecoveryRun? run = app.RecoverAtLaunch();

        Assert.Equal(UndoRecoveryOutcome.RolledBack, Assert.Single(run!.Settled).Outcome);
        Assert.Equal(Old(First), File.ReadAllBytes(Full(First)));
        Assert.Equal(Old(Second), File.ReadAllBytes(Full(Second)));
        UndoTrailLine line = Assert.Single(trail);
        Assert.Equal(Plantoir.Core.Scripting.ActivityTrail.Event.UndoRolledBack, line.Event);
        Assert.Equal("TST1O", line.Course);
        Assert.Equal(1, line.Section);
        Assert.Equal(UndoTrail.RolledBackWords(UndoPhase.Begin, 1), line.Words);
    }

    /// <summary>
    /// A list that cannot be had at launch (its folder cannot be made), or a
    /// failure nobody foresaw (here the clock itself throws), changes nothing
    /// and reaches nobody as an exception; the second is said in the startup
    /// log's diagnostic.
    /// </summary>
    [Fact]
    public void RecoveryAtLaunchNeverThrows()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(ListFolder)!);
        File.WriteAllText(ListFolder, "not a folder");
        var saidOfTheFolder = new List<string>();
        UndoRecoveryRun? run = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null).RecoverAtLaunch(saidOfTheFolder.Add);
        // It ran, found it could not have the list, and says so in the
        // startup log (W4's review, LOW 2): never silently, never thrown.
        Assert.NotNull(run);
        Assert.Empty(run!.Settled);
        Assert.NotNull(run.NotRun);
        Assert.Contains(saidOfTheFolder, line => line.StartsWith("undo recovery at launch did not run: ", StringComparison.Ordinal));

        var said = new List<string>();
        UndoRecoveryRun? unforeseen = new UndoForThisProcess(Path.Combine(_root, "state", "undo2"), UndoMode.Shadow, null, new AClockThatFails())
            .RecoverAtLaunch(said.Add);
        Assert.Null(unforeseen);
        Assert.Contains(said, line => line.StartsWith("undo recovery at launch did not run: InvalidOperationException", StringComparison.Ordinal));
    }

    private sealed class AClockThatFails : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => throw new InvalidOperationException("No clock today.");
    }

    /// <summary>
    /// What a process does while ANOTHER holds the lock through a long
    /// put-back (W3: 2.7 s inside OneDrive, past the 2 s live wait), held here
    /// for as long as the test says by a recovery stopped inside its first
    /// put-back swap. Every waiter gives up after its bounded wait
    /// (<c>rule.oneLock</c>) and nothing is lost: a live step is refused
    /// before anything changes (<c>rule.shadow</c>: "When live, a step whose
    /// begin cannot be written is refused before anything changes"), a shadow
    /// step goes ahead unrecorded, an Undo finds the list unavailable, a
    /// launch's recovery leaves the step for later. Then the put-back finishes,
    /// the step is settled, and the refused step can be made.
    /// </summary>
    [Fact]
    public void AWaiterBehindALongPutBackGivesUpAndNothingIsLost()
    {
        AGoneProcessStopsAStepAt("beforeSwap", 1);
        Write(Third, Old(Third));
        var holding = new ManualResetEventSlim();
        var release = new ManualResetEventSlim();
        var recovering = new UndoForThisProcess(ListFolder, UndoMode.Live, null);
        var longPutBack = new UndoDoor(recovering.Journal, UndoMode.Live, seams: new UndoSeams
        {
            StopsHere = (point, _) =>
            {
                if (point == "recoveryBeforeSwap") { holding.Set(); release.Wait(); }
                return false;
            },
        });
        UndoRecoveryRun? held = null;
        var recovery = new Thread(() => held = longPutBack.Recover()) { IsBackground = true };
        recovery.Start();
        try
        {
            Assert.True(holding.Wait(TimeSpan.FromSeconds(30)), "the put-back never started");
            var waiting = new UndoForThisProcess(ListFolder, UndoMode.Live, null);
            UndoOutcome refused = waiting.Door().Perform(Draft(Third));
            Assert.Equal(UndoOutcomeKind.CouldNotRecordTheStep, refused.Kind);
            Assert.Equal(Old(Third), File.ReadAllBytes(Full(Third)));
            Assert.Equal(UndoOutcomeKind.ListUnavailable, waiting.Door().Undo().Kind);
            UndoRecoveryRun? launch = waiting.RecoverAtLaunch();
            Assert.True(launch is null || launch.Settled.Count == 0);

            var shadow = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null);
            Assert.Equal(UndoOutcomeKind.AppliedWithoutARecord, shadow.Door().Perform(Draft(Third)).Kind);
            Assert.Equal(New(Third), File.ReadAllBytes(Full(Third)));
            File.WriteAllBytes(Full(Third), Old(Third));
        }
        finally
        {
            release.Set();
            recovery.Join();
        }
        Assert.Equal(UndoRecoveryOutcome.RolledBack, Assert.Single(held!.Settled).Outcome);
        Assert.Equal(Old(First), File.ReadAllBytes(Full(First)));
        Assert.Equal(Old(Second), File.ReadAllBytes(Full(Second)));
        var after = new UndoForThisProcess(ListFolder, UndoMode.Live, null);
        Assert.Equal(UndoOutcomeKind.Applied, after.Door().Perform(Draft(Third)).Kind);
        UndoFolded folded = after.Journal.Read().Folded;
        Assert.Equal(2, folded.Steps.Count);
        Assert.Equal(UndoStepState.RolledBack, folded.Steps[1].State);
        Assert.Equal(UndoStepState.Done, folded.Steps[2].State);
    }

    /// <summary>
    /// W4's review, LOW 5: the composition root gives every door the app's
    /// own front-page runner. A step whose draft carries a recompute of the
    /// section's front page is made (never refused for want of a runner, which
    /// in shadow would stop the teacher's action), and the front page is
    /// re-derived by Windows' own rule: pointed at the class just published.
    /// </summary>
    [Fact]
    public void TheProcessesDoorReDerivesTheFrontPageWithTheAppsOwnRule()
    {
        File.WriteAllText(Path.Combine(Folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(Folder, "deploy.ps1"), "# marker");
        string course = Path.Combine(Folder, "courses", "ICS3U");
        Directory.CreateDirectory(Path.Combine(course, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            "{\"course_code\":\"ICS3U\",\"course_name\":\"Computer Science\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
        string Class(int day, bool draft) =>
            $"---\ntitle: Unit 1, Day {day}\ncreated: 2026-09-0{7 + day}T07:00:00.000-0400\ndraft: {(draft ? "true" : "false")}\n---\nThe lesson.\n";
        const string Day2 = "courses/ICS3U/section1/All Classes/Unit 1, Day 2.md";
        const string Index = "courses/ICS3U/section1/index.md";
        Write("courses/ICS3U/section1/All Classes/Unit 1, Day 1.md", Encoding.UTF8.GetBytes(Class(1, draft: false)));
        Write(Day2, Encoding.UTF8.GetBytes(Class(2, draft: true)));
        Write(Index, Encoding.UTF8.GetBytes("---\ntitle: Section 1\ncreated: 2026-09-08T07:00:00.000-0400\ndraft: false\n---\n# Most Recent Class\n![[Unit 1, Day 1]]\n"));
        var draft = new UndoStepDraft
        {
            ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = Folder, Course = "ICS3U", Section = 1, Holds = "section",
            Changes = [new UndoFileChange(Day2, Encoding.UTF8.GetBytes(Class(2, draft: true)), Encoding.UTF8.GetBytes(Class(2, draft: false)))],
            Recomputes = [new JsonObject { ["kind"] = "recompute", ["path"] = Index, ["maintainer"] = "sectionFrontPage", ["section"] = 1 }],
        };

        UndoOutcome outcome = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null).Door().Perform(draft);

        Assert.Equal(UndoOutcomeKind.Applied, outcome.Kind);
        string front = File.ReadAllText(Full(Index));
        Assert.Contains("![[Unit 1, Day 2]]", front);
        Assert.Contains("created: 2026-09-09T07:00:00.000-0400", front);
    }
}

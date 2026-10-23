using System.Diagnostics;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #473: the copy of the app's tools into a working folder runs in the
/// background, once per folder per process, and everything that builds from
/// those tools waits for it — disabled with a reason, never queued.
/// <c>documentation/12-windows-app.md</c> → "Getting a folder ready after an
/// update (#473)".
///
/// <para>In the shared serialized collection: <see cref="ToolchainReadiness"/>
/// is process-wide, and these tests swap its copier.</para>
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class ToolchainReadinessTests : IDisposable
{
    private readonly string _root;
    private readonly string _folder;

    public ToolchainReadinessTests()
    {
        ToolchainReadiness.Reset();
        _root = Path.Combine(Path.GetTempPath(), "readiness-" + Guid.NewGuid().ToString("N")[..8]);
        _folder = Path.Combine(_root, "work");
        Directory.CreateDirectory(Path.Combine(_folder, "courses"));
        File.WriteAllText(Path.Combine(_folder, Workspace.MarkerLauncher), "# stub");
    }

    public void Dispose()
    {
        ToolchainReadiness.Reset();
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    /// <summary>A copier that waits to be let go, counting how often it ran.</summary>
    private sealed class HeldCopy
    {
        private readonly ManualResetEventSlim _letGo = new(false);
        private int _runs;
        public ToolchainMirror.CopyResult Result { get; set; } = new(5, 0);
        public bool Throws { get; set; }
        public int Runs => Volatile.Read(ref _runs);
        public ToolchainMirror.CopyResult Copy(string folder, string bundled)
        {
            Interlocked.Increment(ref _runs);
            _letGo.Wait(TimeSpan.FromSeconds(30));
            if (Throws) throw new IOException("the disk is full");
            // What a real copy leaves: the recipe's first root file, which a
            // Ready folder is checked for.
            Directory.CreateDirectory(Path.Combine(folder, ".toolchain"));
            File.WriteAllText(Path.Combine(folder, ".toolchain", "Dockerfile"), "FROM x");
            return Result;
        }
        public void LetGo() => _letGo.Set();
    }

    // ---- One copy per folder ----------------------------------------------

    [Fact]
    public async Task ManyWindowsAskingAtOnceShareOneCopy()
    {
        var copy = new HeldCopy();
        ToolchainReadiness.Copier = copy.Copy;

        var asked = new Task[16];
        Parallel.For(0, asked.Length, i =>
        {
            // Two spellings of the same folder are the same folder.
            string spelling = i % 2 == 0 ? _folder : _folder.ToUpperInvariant() + Path.DirectorySeparatorChar;
            asked[i] = ToolchainReadiness.Ensure(spelling, "bundled");
        });

        Assert.Equal(ToolchainReadiness.State.Copying, ToolchainReadiness.StateOf(_folder));
        Assert.Single(asked.Distinct());
        copy.LetGo();
        await Task.WhenAll(asked);

        Assert.Equal(1, copy.Runs);
        Assert.Equal(ToolchainReadiness.State.Ready, ToolchainReadiness.StateOf(_folder));
    }

    [Fact]
    public async Task AReadyFolderIsNeverCopiedAgainInThisProcess()
    {
        var copy = new HeldCopy();
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;

        await ToolchainReadiness.Ensure(_folder, "bundled");
        await ToolchainReadiness.Ensure(_folder, "bundled");
        await ToolchainReadiness.Ensure(_folder, "bundled", retryAFailedCopy: true);

        Assert.Equal(1, copy.Runs);
        Assert.Equal(ToolchainReadiness.State.Ready, ToolchainReadiness.StateOf(_folder));
    }

    [Fact]
    public async Task AReadyFolderWhoseRecipeHasGoneIsCopiedAgain()
    {
        var copy = new HeldCopy();
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;
        await ToolchainReadiness.Ensure(_folder, "bundled");
        Assert.Equal(1, copy.Runs);

        File.Delete(Path.Combine(_folder, ".toolchain", "Dockerfile"));   // a sync client, a restore, a hand
        await ToolchainReadiness.Ensure(_folder, "bundled");

        Assert.Equal(2, copy.Runs);
        Assert.Equal(ToolchainReadiness.State.Ready, ToolchainReadiness.StateOf(_folder));
    }

    [Fact]
    public async Task EveryWindowHearsStartedBeforeFinished()
    {
        // A copy with nothing to do ends in milliseconds; "finished" must
        // never reach a window (or startup.log) before "started".
        var copy = new HeldCopy { Result = new(0, 0) };
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;
        var heard = new System.Collections.Concurrent.ConcurrentQueue<ToolchainReadiness.State>();
        void Listen(string folder) { if (folder == _folder) heard.Enqueue(ToolchainReadiness.StateOf(folder)); }
        ToolchainReadiness.Changed += Listen;
        try
        {
            for (int i = 0; i < 20; i++)
            {
                ToolchainReadiness.Reset();
                ToolchainReadiness.Copier = copy.Copy;
                while (heard.TryDequeue(out _)) { }
                await ToolchainReadiness.Ensure(_folder, "bundled");
                Assert.True(SpinWait.SpinUntil(() => heard.Count >= 2, TimeSpan.FromSeconds(5)));
                Assert.Equal(new[] { ToolchainReadiness.State.Copying, ToolchainReadiness.State.Ready }, heard.ToArray());
            }
        }
        finally { ToolchainReadiness.Changed -= Listen; }
    }

    [Fact]
    public async Task AFolderThatIsNotAWorkingFolderIsLeftAlone()
    {
        var copy = new HeldCopy();
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;
        string notOne = Path.Combine(_root, "downloads");
        Directory.CreateDirectory(notOne);

        await ToolchainReadiness.Ensure(notOne, "bundled");

        Assert.Equal(0, copy.Runs);
        Assert.Equal(ToolchainReadiness.State.NotStarted, ToolchainReadiness.StateOf(notOne));
        Assert.False(Directory.Exists(Path.Combine(notOne, "courses")));
    }

    // ---- Ready only after a copy with nothing failing ---------------------

    [Fact]
    public async Task TheFolderIsNotReadyUntilTheCopyHasFinished()
    {
        // The row-296 defect: the old set was filled BEFORE the copy.
        var copy = new HeldCopy();
        ToolchainReadiness.Copier = copy.Copy;

        var running = ToolchainReadiness.Ensure(_folder, "bundled");
        Assert.Equal(ToolchainReadiness.State.Copying, ToolchainReadiness.StateOf(_folder));
        Assert.False(ToolchainReadiness.ActionsEnabled(ToolchainReadiness.StateOf(_folder)));
        copy.LetGo();
        await running;
        Assert.Equal(ToolchainReadiness.State.Ready, ToolchainReadiness.StateOf(_folder));
        Assert.Equal(5, ToolchainReadiness.LastCopyOf(_folder)!.FilesChanged);
    }

    [Fact]
    public async Task ACopyWithOneFailedFileIsFailedAndIsTriedAgainOnlyWhenAsked()
    {
        var copy = new HeldCopy { Result = new(120, 1) };
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;

        await ToolchainReadiness.Ensure(_folder, "bundled");
        Assert.Equal(ToolchainReadiness.State.Failed, ToolchainReadiness.StateOf(_folder));
        Assert.Equal(1, ToolchainReadiness.LastCopyOf(_folder)!.FilesFailed);

        // The sidebar's routine reloads: no second two-minute copy.
        await ToolchainReadiness.Ensure(_folder, "bundled");
        await ToolchainReadiness.Ensure(_folder, "bundled");
        Assert.Equal(1, copy.Runs);
        Assert.Equal(ToolchainReadiness.State.Failed, ToolchainReadiness.StateOf(_folder));

        // File → Reload Courses, or a new window on the folder.
        copy.Result = new(1, 0);
        await ToolchainReadiness.Ensure(_folder, "bundled", retryAFailedCopy: true);
        Assert.Equal(2, copy.Runs);
        Assert.Equal(ToolchainReadiness.State.Ready, ToolchainReadiness.StateOf(_folder));
    }

    [Fact]
    public async Task ACopyThatThrowsIsFailedWithItsReason()
    {
        var copy = new HeldCopy { Throws = true };
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;

        await ToolchainReadiness.Ensure(_folder, "bundled");

        Assert.Equal(ToolchainReadiness.State.Failed, ToolchainReadiness.StateOf(_folder));
        Assert.Equal("the disk is full", ToolchainReadiness.LastCopyOf(_folder)!.Problem);
        Assert.Equal(ToolchainReadiness.CouldNotGetReady, ToolchainReadiness.Refusal(_folder));
    }

    [Fact]
    public void TheRealMirrorCountsAFileItCouldNotWrite()
    {
        // SyncFile used to swallow every failure and answer 0 — "nothing to
        // do" — so a half-copied folder looked fresh.
        string source = Path.Combine(_root, "src");
        string dest = Path.Combine(_root, "dest");
        Directory.CreateDirectory(source);
        Directory.CreateDirectory(dest);
        File.WriteAllText(Path.Combine(source, "a.py"), "new");
        File.WriteAllText(Path.Combine(dest, "a.py"), "old!");
        using (File.Open(Path.Combine(dest, "a.py"), FileMode.Open, FileAccess.Read, FileShare.None))
        {
            var result = ToolchainMirror.SyncDirectory(source, dest);
            Assert.Equal(1, result.Failed);
            Assert.Equal(0, result.Changed);
            Assert.Equal(Path.Combine(dest, "a.py"), result.FirstFailedPath);   // the first one, and why
            Assert.False(string.IsNullOrEmpty(result.FirstProblem));
        }
    }

    [Fact]
    public void InitializingAFolderWaitsForTheCopyAndLeavesItReady()
    {
        string bundled = Path.Combine(_root, "bundled");
        Directory.CreateDirectory(Path.Combine(bundled, "scripts"));
        foreach (string name in ToolchainMirror.Launchers) File.WriteAllText(Path.Combine(bundled, name), name);
        File.WriteAllText(Path.Combine(bundled, "scripts", "build_site.py"), "print('hi')");
        string fresh = Path.Combine(_root, "fresh");
        Directory.CreateDirectory(fresh);

        ToolchainMirror.InitializeWorkspace(fresh, bundled);

        Assert.Equal(ToolchainReadiness.State.Ready, ToolchainReadiness.StateOf(fresh));
        Assert.True(File.Exists(Path.Combine(fresh, ".toolchain", "scripts", "build_site.py")));
        Assert.Empty(Directory.EnumerateFiles(Path.Combine(fresh, "courses"), "*", SearchOption.AllDirectories)
                              .Where(f => Path.GetFileName(f).StartsWith(ToolchainReadiness.MarkerPrefix)));
    }

    // ---- The trail ---------------------------------------------------------

    [Fact]
    public async Task ACopyThatChangedSomethingLeavesALineOnTheTrail()
    {
        var copy = new HeldCopy { Result = new(1234, 0) { Compared = 11500, ReadInFull = 12 } };
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;

        // A trail file of its own for the length of the test, put back to the
        // suite's scratch trail afterwards (never to null, the REAL trail).
        string ownTrail = Path.Combine(_root, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(ownTrail);
        try { await ToolchainReadiness.Ensure(_folder, "bundled"); }
        finally { ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath); }

        string trail = File.ReadAllText(ownTrail);
        Assert.Contains("got the working folder ready — 1234 files brought up to date, 11500 compared (12 read in full) in", trail);
        Assert.Equal("working folder tools copied", ActivityTrail.KeyFor(ActivityTrail.Event.WorkingFolderToolsCopied));
    }

    [Fact]
    public void TheTrailLineSaysWhichOutcomeItWas()
    {
        var failed = new ToolchainReadiness.Status(ToolchainReadiness.State.Failed, 40, 2, 12.34, "access denied",
                                                   @".toolchain\scripts\build_site.py");
        string line = ToolchainReadiness.TrailLine(@"C:\work", failed);
        Assert.StartsWith("could not finish getting the working folder ready — 2 files could not be copied or removed " +
                          @"(first: .toolchain\scripts\build_site.py, access denied), 40 files brought up to date in 12.3 s", line);
        var threw = new ToolchainReadiness.Status(ToolchainReadiness.State.Failed, 0, 1, 0.1, "the disk is full");
        Assert.Contains("1 file could not be copied or removed (the disk is full)", ToolchainReadiness.TrailLine(@"C:\work", threw));
        var ready = new ToolchainReadiness.Status(ToolchainReadiness.State.Ready, 1, 0, 0.5, null);
        Assert.StartsWith("got the working folder ready — 1 file brought up to date in 0.5 s", ToolchainReadiness.TrailLine(@"C:\work", ready));
        // Written for a folder set up from nothing too, so it never says "update".
        Assert.DoesNotContain("update", ToolchainReadiness.TrailLine(@"C:\work", ready));

        // #559: the files compared, and how many had to be read, when there were any.
        var reread = new ToolchainReadiness.Status(ToolchainReadiness.State.Ready, 14, 0, 131.6, null,
                                                   FilesCompared: 12889, FilesReadInFull: 12745);
        Assert.StartsWith("got the working folder ready — 14 files brought up to date, 12889 compared (12745 read in full) in 131.6 s — ",
                          ToolchainReadiness.TrailLine(@"C:\work", reread));
        var onlyCompared = new ToolchainReadiness.Status(ToolchainReadiness.State.Ready, 0, 0, 11.2, null,
                                                         FilesCompared: 12903, FilesReadInFull: 12903);
        Assert.StartsWith("got the working folder ready — 0 files brought up to date, 12903 compared (12903 read in full) in 11.2 s",
                          ToolchainReadiness.TrailLine(@"C:\work", onlyCompared));
        var noReads = new ToolchainReadiness.Status(ToolchainReadiness.State.Ready, 3, 0, 0.7, null, FilesCompared: 12900);
        Assert.StartsWith("got the working folder ready — 3 files brought up to date, 12900 compared in 0.7 s",
                          ToolchainReadiness.TrailLine(@"C:\work", noReads));
        var failedAfterReading = failed with { FilesCompared = 100, FilesReadInFull = 3 };
        Assert.Contains(@"(first: .toolchain\scripts\build_site.py, access denied), 40 files brought up to date, 100 compared (3 read in full) in 12.3 s; ",
                        ToolchainReadiness.TrailLine(@"C:\work", failedAfterReading));
    }

    [Fact]
    public void APassThatOnlyReadFilesToCompareThemStillLeavesALine()
    {
        // #559's 11.2 s pass re-read every file, changed none, and left no line at all.
        Assert.True(ToolchainReadiness.WritesATrailLine(new ToolchainMirror.CopyResult(0, 0) { Compared = 12903, ReadInFull = 12903 }));
        Assert.True(ToolchainReadiness.WritesATrailLine(new ToolchainMirror.CopyResult(1, 0)));
        Assert.True(ToolchainReadiness.WritesATrailLine(new ToolchainMirror.CopyResult(0, 1)));
        // The ordinary launch: every file compared by length and time, nothing read, nothing to say.
        Assert.False(ToolchainReadiness.WritesATrailLine(new ToolchainMirror.CopyResult(0, 0) { Compared = 12903 }));
    }

    // ---- What the window shows: state → buttons and banner ----------------

    [Theory]
    [InlineData(ToolchainReadiness.State.NotStarted, true)]
    [InlineData(ToolchainReadiness.State.Copying, false)]
    [InlineData(ToolchainReadiness.State.Ready, true)]
    [InlineData(ToolchainReadiness.State.Failed, false)]
    public void PreviewDeployAndNewCourseFollowTheState(ToolchainReadiness.State state, bool enabled)
    {
        Assert.Equal(enabled, ToolchainReadiness.ActionsEnabled(state));
        Assert.Equal(enabled, ToolchainReadiness.RefusalFor(state) is null);
    }

    [Fact]
    public void TheBannerWaitsASecondThenSaysWhy()
    {
        Assert.False(ToolchainReadiness.BannerFor(ToolchainReadiness.State.Copying, pastTheDelay: false).IsOpen);
        var copying = ToolchainReadiness.BannerFor(ToolchainReadiness.State.Copying, pastTheDelay: true);
        Assert.True(copying.IsOpen);
        Assert.False(copying.IsError);
        Assert.Equal(ToolchainReadiness.GettingReadyTitle, copying.Title);
        Assert.Equal(ToolchainReadiness.GettingReadyMessage, copying.Message);

        var failed = ToolchainReadiness.BannerFor(ToolchainReadiness.State.Failed, pastTheDelay: false);
        Assert.True(failed.IsOpen);
        Assert.True(failed.IsError);
        Assert.Equal(ToolchainReadiness.CouldNotGetReady, failed.Message);

        Assert.False(ToolchainReadiness.BannerFor(ToolchainReadiness.State.Ready, true).IsOpen);
        Assert.False(ToolchainReadiness.BannerFor(ToolchainReadiness.State.NotStarted, true).IsOpen);
        Assert.Equal(TimeSpan.FromSeconds(1), ToolchainReadiness.BannerDelay);
    }

    [Fact]
    public void UiAutomationReadsCopyingReadyOrFailed()
    {
        Assert.Equal("copying", ToolchainReadiness.AutomationStatus(ToolchainReadiness.State.Copying));
        Assert.Equal("failed", ToolchainReadiness.AutomationStatus(ToolchainReadiness.State.Failed));
        Assert.Equal("ready", ToolchainReadiness.AutomationStatus(ToolchainReadiness.State.Ready));
        Assert.Equal("ready", ToolchainReadiness.AutomationStatus(ToolchainReadiness.State.NotStarted));
    }

    [Fact]
    public void TheWordsNameNoMachineryAndCallADeployADeploy()
    {
        // Rule 1, and #443's words rule: the button is captioned Deploy.
        foreach (string sentence in new[]
                 {
                     ToolchainReadiness.GettingReadyTitle, ToolchainReadiness.GettingReadyMessage,
                     ToolchainReadiness.CouldNotGetReady,
                 })
        {
            foreach (string machinery in new[] { "toolchain", "script", "launcher", "docker", "container", "thread", "publish" })
                Assert.DoesNotContain(machinery, sentence, StringComparison.OrdinalIgnoreCase);
        }
        Assert.Contains("Preview and Deploy", ToolchainReadiness.GettingReadyMessage);
        Assert.Contains("Reload Courses", ToolchainReadiness.CouldNotGetReady);
        // The failure sentence names the real menu item — built in code since #488.
        string menus = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "MainWindow.Menus.cs"));
        Assert.Contains("Add(file, \"Reload Courses\"", menus);
    }

    // ---- The backstop -------------------------------------------------------

    [Fact]
    public async Task TheRunnerRefusesWhileCopyingAndSaysTheRunIsOver()
    {
        var copy = new HeldCopy();
        ToolchainReadiness.Copier = copy.Copy;
        var running = ToolchainReadiness.Ensure(_folder, "bundled");

        var runner = new ScriptRunner(new SynchronizationContext());
        runner.Run("preview.ps1", new[] { "ICS3U", "1" }, _folder);

        Assert.Equal(ToolchainReadiness.GettingReadyMessage, runner.LaunchProblem);
        Assert.Equal(-1, runner.LastExitCode);   // nothing waiting on it hangs
        Assert.False(runner.IsRunning);
        Assert.False(await runner.WaitUntilFinished());
        copy.LetGo();
        await running;
    }

    [Fact]
    public async Task TheRunnerRefusesAFailedFolderWithTheFailureSentence()
    {
        var copy = new HeldCopy { Result = new(0, 3) };
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;
        await ToolchainReadiness.Ensure(_folder, "bundled");

        var runner = new ScriptRunner(new SynchronizationContext());
        runner.Run("deploy.ps1", new[] { "ICS3U", "1" }, _folder);

        Assert.Equal(ToolchainReadiness.CouldNotGetReady, runner.LaunchProblem);
        Assert.Equal(-1, runner.LastExitCode);
    }

    [Fact]
    public async Task TheRunnerNeverRefusesAFolderNobodyEnsuredOrAStop()
    {
        // NotStarted: tests and the marketing captures drive such folders.
        var runner = new ScriptRunner(new SynchronizationContext());
        runner.Run("setup.ps1", Array.Empty<string>(), _folder);
        Assert.DoesNotContain("getting this folder ready", runner.LaunchProblem ?? "", StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("copying what it needs", runner.LaunchProblem ?? "", StringComparison.OrdinalIgnoreCase);
        Assert.Null(runner.LastExitCode);   // the missing-launcher path, as before

        var copy = new HeldCopy();
        ToolchainReadiness.Copier = copy.Copy;
        var running = ToolchainReadiness.Ensure(_folder, "bundled");
        var stop = new ScriptRunner(new SynchronizationContext());
        stop.Run("setup.ps1", new[] { "ICS3U", "1", "--stop" }, _folder);
        Assert.NotEqual(ToolchainReadiness.GettingReadyMessage, stop.LaunchProblem);
        copy.LetGo();
        await running;
    }

    // ---- The wizard's preflight --------------------------------------------

    [Fact]
    public async Task ANewCourseIsRefusedBeforeAnythingIsWritten()
    {
        File.WriteAllText(Path.Combine(_folder, "setup.ps1"), "# stub");
        var copy = new HeldCopy();
        ToolchainReadiness.Copier = copy.Copy;
        var running = ToolchainReadiness.Ensure(_folder, "bundled");

        var creator = new NewCourseCreator(new ScriptRunner(new SynchronizationContext()));
        await creator.CreateCourse(new JObject { ["course_code"] = "ICS3U" }, _folder);
        Assert.Equal(ToolchainReadiness.GettingReadyMessage, creator.PreparationProblem);
        Assert.False(Directory.Exists(Path.Combine(_folder, "courses", "ICS3U")));

        await creator.InstallExampleCourse(_folder);
        Assert.Equal(ToolchainReadiness.GettingReadyMessage, creator.PreparationProblem);
        Assert.Null(creator.InstalledExampleCode);
        Assert.Null(creator.Runner.StartedAt);

        copy.LetGo();
        await running;
    }

    // ---- The marker plantoir-mcp reads -------------------------------------

    [Fact]
    public async Task TheMarkerIsThereForTheLengthOfTheCopyOnly()
    {
        var copy = new HeldCopy();
        ToolchainReadiness.Copier = copy.Copy;
        var running = ToolchainReadiness.Ensure(_folder, "bundled");

        string marker = ToolchainReadiness.MarkerPath(_folder, Environment.ProcessId);
        Assert.True(SpinWait.SpinUntil(() => File.Exists(marker), TimeSpan.FromSeconds(10)));
        Assert.True(ToolchainReadiness.AnotherProgramIsGettingReady(_folder));
        Assert.EndsWith(Path.Combine("courses", ".internal", "activity", "toolchain-copying." + Environment.ProcessId), marker);

        copy.LetGo();
        await running;
        Assert.False(File.Exists(marker));
        Assert.False(ToolchainReadiness.AnotherProgramIsGettingReady(_folder));
    }

    [Fact]
    public async Task AFailedCopyTakesItsMarkerAwayToo()
    {
        var copy = new HeldCopy { Throws = true };
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;
        await ToolchainReadiness.Ensure(_folder, "bundled");
        Assert.False(File.Exists(ToolchainReadiness.MarkerPath(_folder, Environment.ProcessId)));
    }

    private void WriteMarker(int pid, string body)
    {
        string path = ToolchainReadiness.MarkerPath(_folder, pid);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, body);
    }

    [Fact]
    public void AMarkerWhoseProgramIsGoneCountsForNothing()
    {
        using var gone = Process.Start(new ProcessStartInfo("cmd.exe", "/c exit 0") { CreateNoWindow = true, UseShellExecute = false })!;
        gone.WaitForExit();
        int pid = gone.Id;
        WriteMarker(pid, $"{pid}\ncmd\n{DateTime.UtcNow:O}\n");
        Assert.False(ToolchainReadiness.AnotherProgramIsGettingReady(_folder));
    }

    [Fact]
    public async Task ACopySweepsAwayMarkersLeftByAKilledPlantoir()
    {
        using var gone = Process.Start(new ProcessStartInfo("cmd.exe", "/c exit 0") { CreateNoWindow = true, UseShellExecute = false })!;
        gone.WaitForExit();
        WriteMarker(gone.Id, $"{gone.Id}\nPlantoir\n{DateTime.UtcNow:O}\n");
        var copy = new HeldCopy();
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;

        await ToolchainReadiness.Ensure(_folder, "bundled");

        Assert.False(File.Exists(ToolchainReadiness.MarkerPath(_folder, gone.Id)));
    }

    [Fact]
    public async Task TheSweepRemovesOnlyMarkersItCanReadAndWhoseProgramIsGone()
    {
        using var gone = Process.Start(new ProcessStartInfo("cmd.exe", "/c exit 0") { CreateNoWindow = true, UseShellExecute = false })!;
        gone.WaitForExit();
        using var alive = Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 30 127.0.0.1 >nul") { CreateNoWindow = true, UseShellExecute = false })!;
        try
        {
            int emptyPid = gone.Id + 1_000_000;   // a marker caught mid-write by an older Plantoir: no body yet
            WriteMarker(emptyPid, "");
            WriteMarker(gone.Id, $"{gone.Id}\nPlantoir\n{DateTime.UtcNow:O}\n");
            // A LATER moment than the copy's own marker will carry, so the live
            // program does not hold this copy back (#477's turn-taking): the
            // sweep is what is under test here.
            WriteMarker(alive.Id, $"{alive.Id}\ncmd\n{DateTime.UtcNow.AddHours(1):O}\n");
            var copy = new HeldCopy();
            copy.LetGo();
            ToolchainReadiness.Copier = copy.Copy;

            await ToolchainReadiness.Ensure(_folder, "bundled");

            Assert.True(File.Exists(ToolchainReadiness.MarkerPath(_folder, emptyPid)), "an unreadable marker was swept");
            Assert.False(File.Exists(ToolchainReadiness.MarkerPath(_folder, gone.Id)), "a dead program's marker stayed");
            Assert.True(File.Exists(ToolchainReadiness.MarkerPath(_folder, alive.Id)), "a live program's marker was swept");
            Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(ToolchainReadiness.MarkerPath(_folder, 1))!, "writing-*"));
        }
        finally { try { alive.Kill(); } catch { } }
    }

    [Fact]
    public void AMarkerWhoseIdNowBelongsToAnotherProcessCountsForNothing()
    {
        // This process's id and name, but a start that is not this process's:
        // what a recycled id looks like.
        string mine = WorkLease.LeaseBody(withStart: true);
        string[] lines = mine.Replace("\r", "").Split('\n');
        Assert.True(lines.Length >= 4 && lines[3].Length > 0, "the lease body carries a start on line 4");
        WriteMarker(Environment.ProcessId, $"{lines[0]}\n{lines[1]}\n{lines[2]}\n1.000000\n");
        Assert.False(ToolchainReadiness.AnotherProgramIsGettingReady(_folder));

        WriteMarker(Environment.ProcessId, mine);
        Assert.True(ToolchainReadiness.AnotherProgramIsGettingReady(_folder));
    }

    [Fact]
    public async Task PlantoirMcpRefusesToBuildWhileALiveMarkerSaysSo()
    {
        WriteMarker(Environment.ProcessId, WorkLease.LeaseBody(withStart: true));

        var outcome = await new Plantoir.Mcp.LauncherRunner().Run(
            "preview", new[] { "ICS3U", "1", "--build-only", "--non-interactive" }, _folder, null, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.Equal(ToolchainReadiness.GettingReadyMessage, outcome.Message);
    }

    // ---- Copies take turns (#477) ------------------------------------------

    [Theory]
    [InlineData("2026-10-15T10:00:00.0000000Z", 200, "2026-10-15T09:59:59.0000000Z", 300, true)]    // earlier: wait
    [InlineData("2026-10-15T10:00:00.0000000Z", 200, "2026-10-15T10:00:01.0000000Z", 100, false)]   // later: go
    [InlineData("2026-10-15T10:00:00.0000000Z", 200, "2026-10-15T10:00:00.0000000Z", 100, true)]    // same moment, lower id: wait
    [InlineData("2026-10-15T10:00:00.0000000Z", 200, "2026-10-15T10:00:00.0000000Z", 300, false)]   // same moment, higher id: go
    [InlineData("2026-10-15T10:00:00.0000000Z", 200, "2026-10-15T09:00:00.0000000Z", 200, false)]   // never itself
    [InlineData("2026-10-15T10:00:00.0000000Z", 200, "yesterday", 100, false)]                      // unreadable: not earlier (M2)
    [InlineData("2026-10-15T10:00:00.0000000Z", 200, null, 100, false)]                             // no moment at all
    [InlineData("2026-10-15T10:00:00+00:00", 200, "2026-10-15T09:00:00.0000000Z", 100, false)]      // its own not the shape
    public void MustWaitForOnlyACopyWrittenFirst(string mine, int myPid, string? other, int otherPid, bool waits) =>
        Assert.Equal(waits, ToolchainReadiness.MustWaitFor(mine, myPid, other, otherPid));

    private static Process StartALiveChild() =>
        Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 60 127.0.0.1 >nul") { CreateNoWindow = true, UseShellExecute = false })!;

    [Fact]
    public async Task ACopyWaitsForAnEarlierCopyByAnotherProgram()
    {
        using var other = StartALiveChild();
        try
        {
            // Its real name, so the liveness rule reads it as alive; a moment
            // a minute before this copy's own.
            WriteMarker(other.Id, $"{other.Id}\n{other.ProcessName}\n{DateTime.UtcNow.AddMinutes(-1):O}\n");
            int looks = 0;
            ToolchainReadiness.Pause = _ => { Interlocked.Increment(ref looks); Thread.Sleep(20); };
            var copy = new HeldCopy();
            copy.LetGo();
            ToolchainReadiness.Copier = copy.Copy;

            var running = ToolchainReadiness.Ensure(_folder, "bundled");
            Assert.True(SpinWait.SpinUntil(() => Volatile.Read(ref looks) >= 3, TimeSpan.FromSeconds(10)), "it never waited");
            Assert.Equal(0, copy.Runs);
            Assert.Equal(ToolchainReadiness.State.Copying, ToolchainReadiness.StateOf(_folder));   // the banner's state meanwhile
            Assert.True(File.Exists(ToolchainReadiness.MarkerPath(_folder, Environment.ProcessId)), "its own marker comes FIRST");

            File.Delete(ToolchainReadiness.MarkerPath(_folder, other.Id));   // the other copy finished
            await running;

            Assert.Equal(1, copy.Runs);
            Assert.Equal(ToolchainReadiness.State.Ready, ToolchainReadiness.StateOf(_folder));
            Assert.Equal(other.Id, ToolchainReadiness.LastCopyOf(_folder)!.WaitedForPid);
        }
        finally { try { other.Kill(); } catch { } }
    }

    [Fact]
    public async Task ALaterMarkerDoesNotHoldAnEarlierCopy()
    {
        using var other = StartALiveChild();
        try
        {
            WriteMarker(other.Id, $"{other.Id}\n{other.ProcessName}\n{DateTime.UtcNow.AddHours(1):O}\n");
            int looks = 0;
            ToolchainReadiness.Pause = _ => Interlocked.Increment(ref looks);
            var copy = new HeldCopy();
            copy.LetGo();
            ToolchainReadiness.Copier = copy.Copy;

            await ToolchainReadiness.Ensure(_folder, "bundled");

            Assert.Equal(0, looks);
            Assert.Equal(1, copy.Runs);
            Assert.Null(ToolchainReadiness.LastCopyOf(_folder)!.WaitedForPid);
        }
        finally { try { other.Kill(); } catch { } }
    }

    [Fact]
    public async Task ACopyWhoseCallerGivesUpWritesNothingAndSaysWhy()
    {
        using var other = StartALiveChild();
        try
        {
            WriteMarker(other.Id, $"{other.Id}\n{other.ProcessName}\n{DateTime.UtcNow.AddMinutes(-1):O}\n");
            var copy = new HeldCopy();
            copy.LetGo();
            ToolchainReadiness.Copier = copy.Copy;
            int looks = 0;
            var turns = new ToolchainReadiness.TakingTurns(_ => looks++, () => looks >= 4);
            string ownTrail = Path.Combine(_root, "activity.txt");
            ActivityTrail.SetCustomLogPathForTesting(ownTrail);
            try { await ToolchainReadiness.Ensure(_folder, "bundled", turns: turns); }
            finally { ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath); }

            Assert.Equal(0, copy.Runs);
            var last = ToolchainReadiness.LastCopyOf(_folder)!;
            Assert.Equal(ToolchainReadiness.State.Failed, last.State);
            Assert.True(last.GaveUpWaiting);
            Assert.Equal(other.Id, last.WaitedForPid);
            Assert.False(File.Exists(ToolchainReadiness.MarkerPath(_folder, Environment.ProcessId)));
            Assert.False(File.Exists(ownTrail), "a copy that never started wrote a line: the caller says what happened");
        }
        finally { try { other.Kill(); } catch { } }
    }

    [Fact]
    public void TheRunsOwnMarkerIsNeverAnotherProgram()
    {
        WriteMarker(Environment.ProcessId, WorkLease.LeaseBody(withStart: true));
        Assert.True(ToolchainReadiness.AnotherProgramIsGettingReady(_folder));
        Assert.False(ToolchainReadiness.AnotherProgramIsGettingReady(_folder, exceptThisProcess: true));
        Assert.Empty(ToolchainReadiness.LiveCopiers(_folder, exceptThisProcess: true));
    }

    [Fact]
    public void TheTrailLineSaysWhenItWasForAScheduledDeployOrWaitedForAtClosing()
    {
        var ready = new ToolchainReadiness.Status(ToolchainReadiness.State.Ready, 12, 0, 15.2, null);
        Assert.StartsWith("got the working folder ready for a scheduled deploy — 12 files brought up to date in 15.2 s — ",
                          ToolchainReadiness.TrailLine(@"C:\work", ready, forAScheduledDeploy: true));
        Assert.StartsWith("got the working folder ready for a scheduled deploy — 12 files brought up to date, 900 compared (40 read in full) in 15.2 s — ",
                          ToolchainReadiness.TrailLine(@"C:\work", ready with { FilesCompared = 900, FilesReadInFull = 40 },
                                                       forAScheduledDeploy: true));
        var failed = new ToolchainReadiness.Status(ToolchainReadiness.State.Failed, 3, 1, 2.0, "denied", @".toolchain\x.py");
        string line = ToolchainReadiness.TrailLine(@"C:\work", failed, forAScheduledDeploy: true);
        Assert.Contains("could not finish getting the working folder ready for a scheduled deploy", line);
        Assert.Contains("; the scheduled deploy stood down — ", line);
        Assert.DoesNotContain("Reload Courses", line);   // nobody is there to choose it at half six
        Assert.StartsWith("got the working folder ready — 12 files brought up to date in 15.2 s, and Plantoir waited for it before closing — ",
                          ToolchainReadiness.TrailLine(@"C:\work", ready, waitedBeforeClosing: true));
    }

    [Fact]
    public async Task RefreshingFromAFolderWithNoRecipeChangesNothing()
    {
        string tools = Path.Combine(_folder, ".toolchain", "scripts");
        Directory.CreateDirectory(tools);
        File.WriteAllText(Path.Combine(tools, "build_site.py"), "old");
        string empty = Path.Combine(_root, "no-recipe");
        Directory.CreateDirectory(empty);
        var copy = new HeldCopy();
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;

        await ToolchainReadiness.RefreshWorkspace(_folder, empty);

        Assert.Equal(0, copy.Runs);
        Assert.Equal(ToolchainReadiness.State.NotStarted, ToolchainReadiness.StateOf(_folder));
        Assert.Equal("old", File.ReadAllText(Path.Combine(tools, "build_site.py")));
    }

    // ---- Closing while a copy writes (#484) --------------------------------

    [Theory]
    [InlineData(true, true, false, false, true)]     // the last window, a copy writing: wait
    [InlineData(false, true, false, false, false)]   // not the last window: the copy goes on in the others
    [InlineData(true, false, false, false, false)]   // nothing writing (none, or only waiting its turn)
    [InlineData(true, true, true, false, false)]     // Windows is ending the session: never hold it
    [InlineData(true, true, false, true, false)]     // already waited once: the close that follows goes
    public void ClosingWaitsOnlyForAWritingCopyWhenItQuits(bool quits, bool writing, bool ending, bool waited, bool waits) =>
        Assert.Equal(waits, ToolchainReadiness.ClosingWaitsForTheCopy(quits, writing, ending, waited));

    [Fact]
    public async Task ClosingWaitsForEveryFoldersWritingCopy()
    {
        string second = Path.Combine(_root, "second");
        Directory.CreateDirectory(Path.Combine(second, "courses"));
        File.WriteAllText(Path.Combine(second, Workspace.MarkerLauncher), "# stub");
        var first = new HeldCopy();
        var other = new HeldCopy();
        ToolchainReadiness.Copier = (folder, bundled) =>
            folder == _folder ? first.Copy(folder, bundled) : other.Copy(folder, bundled);
        var a = ToolchainReadiness.Ensure(_folder, "bundled");
        var b = ToolchainReadiness.Ensure(second, "bundled");
        Assert.True(SpinWait.SpinUntil(() => first.Runs == 1 && other.Runs == 1, TimeSpan.FromSeconds(10)));
        Assert.True(ToolchainReadiness.AnyCopyIsWriting);

        var closing = ToolchainReadiness.WhenWritingCopiesFinish();
        first.LetGo();
        await a;
        Assert.False(closing.IsCompleted, "the close went ahead with the second folder's copy still writing");
        other.LetGo();
        await b;
        await closing.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.False(ToolchainReadiness.AnyCopyIsWriting);
    }

    [Fact]
    public async Task ACopyStillWaitingItsTurnIsNotWaitedForAndDoesNotStartOnceTheCloseBegins()
    {
        using var other = StartALiveChild();
        try
        {
            WriteMarker(other.Id, $"{other.Id}\n{other.ProcessName}\n{DateTime.UtcNow.AddMinutes(-1):O}\n");
            int looks = 0;
            ToolchainReadiness.Pause = _ => { Interlocked.Increment(ref looks); Thread.Sleep(20); };
            var copy = new HeldCopy();
            copy.LetGo();
            ToolchainReadiness.Copier = copy.Copy;
            var running = ToolchainReadiness.Ensure(_folder, "bundled");
            Assert.True(SpinWait.SpinUntil(() => Volatile.Read(ref looks) >= 2, TimeSpan.FromSeconds(10)));
            Assert.False(ToolchainReadiness.AnyCopyIsWriting);   // waiting is not writing

            await ToolchainReadiness.WhenWritingCopiesFinish().WaitAsync(TimeSpan.FromSeconds(5));   // nothing to wait for

            // The other program finishes AFTER the close began (the review's M3):
            // the waiting copy must not start now, or the exit would cut it.
            File.Delete(ToolchainReadiness.MarkerPath(_folder, other.Id));
            int at = Volatile.Read(ref looks);
            Assert.True(SpinWait.SpinUntil(() => Volatile.Read(ref looks) >= at + 3, TimeSpan.FromSeconds(10)));
            Assert.Equal(0, copy.Runs);

            // The close did not quit after all (a new window): it goes ahead.
            ToolchainReadiness.ReleaseWaitingCopies();
            await running.WaitAsync(TimeSpan.FromSeconds(10));
            Assert.Equal(1, copy.Runs);
        }
        finally { try { other.Kill(); } catch { } }
    }

    [Fact]
    public async Task AHoldReleasedAfterACloseThatDidNotQuitLetsALaterCopyFinish()
    {
        // The batch 4 review's M1: a close that waited (and so held copies
        // back) and then did not quit — Keep Working when asked again, or an
        // installer that would not start — must release the hold, or every
        // later copy waits its turn for the life of the process.
        int looks = 0;
        ToolchainReadiness.Pause = _ => { Interlocked.Increment(ref looks); Thread.Sleep(20); };
        var copy = new HeldCopy();
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;

        await ToolchainReadiness.WhenWritingCopiesFinish().WaitAsync(TimeSpan.FromSeconds(5));   // the hold is now set
        var later = ToolchainReadiness.Ensure(_folder, "bundled");
        Assert.True(SpinWait.SpinUntil(() => Volatile.Read(ref looks) >= 3, TimeSpan.FromSeconds(10)));
        Assert.False(later.IsCompleted, "a copy started while a closing window held copies back");
        Assert.Equal(0, copy.Runs);

        ToolchainReadiness.ReleaseWaitingCopies();
        await later.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.Equal(1, copy.Runs);
        Assert.Equal(ToolchainReadiness.State.Ready, ToolchainReadiness.StateOf(_folder));
    }

    [Fact]
    public void AClosingWindowSaysWhyItIsStillUpWhicheverFolderIsCopying()
    {
        // The batch 4 review's M2: the copy being waited for may be another
        // folder's, and this folder is Ready — the window still says why.
        var own = ToolchainReadiness.BannerWhileClosing(ToolchainReadiness.State.Copying);
        Assert.True(own.IsOpen);
        Assert.Equal(ToolchainReadiness.GettingReadyTitle, own.Title);

        foreach (var state in new[] { ToolchainReadiness.State.Ready, ToolchainReadiness.State.NotStarted })
        {
            var other = ToolchainReadiness.BannerWhileClosing(state);
            Assert.True(other.IsOpen);
            Assert.False(other.IsError);
            Assert.Equal(ToolchainReadiness.FinishingAnotherFolderTitle, other.Title);
            Assert.Equal(ToolchainReadiness.FinishingAnotherFolderMessage, other.Message);
        }
        Assert.True(ToolchainReadiness.BannerWhileClosing(ToolchainReadiness.State.Failed).IsError);
    }

    [Fact]
    public async Task AMarkerHeldOpenForAMomentIsStillTakenAwayAfterTheCopy()
    {
        // The batch 4 review's L1: a marker a scanner holds open when the copy
        // finishes would otherwise stay live for the life of the process.
        var copy = new HeldCopy();
        ToolchainReadiness.Copier = copy.Copy;
        var running = ToolchainReadiness.Ensure(_folder, "bundled");
        Assert.True(SpinWait.SpinUntil(() => copy.Runs == 1, TimeSpan.FromSeconds(10)));
        string marker = ToolchainReadiness.MarkerPath(_folder, Environment.ProcessId);
        Assert.True(File.Exists(marker));

        var holder = new FileStream(marker, FileMode.Open, FileAccess.Read, FileShare.Read);   // no FileShare.Delete
        var letGoOfTheMarker = Task.Delay(ToolchainReadiness.MarkerDeleteRetryPause * 2).ContinueWith(_ => holder.Dispose());
        copy.LetGo();
        await running.WaitAsync(TimeSpan.FromSeconds(10));
        await letGoOfTheMarker;
        Assert.False(File.Exists(marker), "the marker outlived its copy");
    }

    [Fact]
    public async Task ACopyAClosingWindowWaitedForSaysSoOnTheTrail()
    {
        var copy = new HeldCopy { Result = new(40, 0) };
        ToolchainReadiness.Copier = copy.Copy;
        string ownTrail = Path.Combine(_root, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(ownTrail);
        try
        {
            var running = ToolchainReadiness.Ensure(_folder, "bundled");
            Assert.True(SpinWait.SpinUntil(() => copy.Runs == 1, TimeSpan.FromSeconds(10)));
            var closing = ToolchainReadiness.WhenWritingCopiesFinish();
            copy.LetGo();
            await running;
            await closing.WaitAsync(TimeSpan.FromSeconds(10));
        }
        finally { ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath); }

        Assert.Contains("got the working folder ready — 40 files brought up to date in", File.ReadAllText(ownTrail));
        Assert.Contains(", and Plantoir waited for it before closing — ", File.ReadAllText(ownTrail));
    }
}

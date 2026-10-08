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
        var copy = new HeldCopy { Result = new(1234, 0) };
        copy.LetGo();
        ToolchainReadiness.Copier = copy.Copy;

        await ToolchainReadiness.Ensure(_folder, "bundled");

        string trail;
        using (var stream = new FileStream(TestTrailRedirect.ScratchTrailPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        using (var reader = new StreamReader(stream))
            trail = reader.ReadToEnd();
        Assert.Contains("got the working folder ready after an update — 1234 files brought up to date in", trail);
        Assert.Equal("working folder tools copied", ActivityTrail.KeyFor(ActivityTrail.Event.WorkingFolderToolsCopied));
    }

    [Fact]
    public void TheTrailLineSaysWhichOutcomeItWas()
    {
        var failed = new ToolchainReadiness.Status(ToolchainReadiness.State.Failed, 40, 2, 12.34, "access denied");
        string line = ToolchainReadiness.TrailLine(@"C:\work", failed);
        Assert.StartsWith("could not finish getting the working folder ready — 2 files could not be copied (access denied), 40 files brought up to date in 12.3 s", line);
        var ready = new ToolchainReadiness.Status(ToolchainReadiness.State.Ready, 1, 0, 0.5, null);
        Assert.StartsWith("got the working folder ready after an update — 1 file brought up to date in 0.5 s", ToolchainReadiness.TrailLine(@"C:\work", ready));
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
        // The failure sentence names the real menu item.
        string xaml = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "MainWindow.xaml"));
        Assert.Contains("Text=\"Reload Courses\"", xaml);
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
}

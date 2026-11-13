using System.Diagnostics;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #799, Russell's ruling of 2026-11-13: the deploy set for later follows
/// #768. The GENERATED wrapper is run for real (as
/// <see cref="ScheduledWrapperRunTests"/> runs it) against a course built on
/// the real clock: it asks the runtime Python whether anything changed,
/// builds only when the answer is not a plain <c>reuse</c>, and the build
/// leaves ONE "site built again before deploying" line with its reason; a
/// reuse runs no build and writes no line; a build that fails writes none.
///
/// <para>The launchers are stand-ins: <c>preview.ps1</c> notes that it ran
/// and exits as told, <c>deploy.ps1</c> notes that it ran. The question is
/// the REAL shared Python, reached through <c>.toolchain\scripts</c> and
/// <c>.toolchain\contracts</c> junctions to this repository's, with
/// <c>PLANTOIR_TOOLCHAIN_ID</c> naming the toolchain so the stamp can be
/// written to match. <c>LOCALAPPDATA</c> is a scratch folder in the child,
/// so the built site, and everything else the wrapper writes there, stays
/// out of the teacher's own.</para>
/// </summary>
[Collection(SharedActivityState.Name)]
public class ScheduledDeployReusesTheLastBuildTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-sched-reuse-" + Guid.NewGuid().ToString("N"));
    private string Work => Path.Combine(_root, "work");
    private string Local => Path.Combine(_root, "local");
    private string TrailDir => Path.Combine(_root, "trail");
    private string Course => Path.Combine(Work, "courses", "ICS3U");
    private string Section => Path.Combine(Local, "Plantoir", "builds", FolderContainers.FolderIdentifier(Work), "ICS3U", "section1");
    private string BuiltMark => Path.Combine(_root, "built.txt");
    private string DeployedMark => Path.Combine(_root, "deployed.txt");
    private const string Toolchain = "files-scheduled-reuse-test";

    public ScheduledDeployReusesTheLastBuildTests()
    {
        Directory.CreateDirectory(Path.Combine(Work, ".toolchain"));
        ReferenceFixtures.Junction(Path.Combine(Work, ".toolchain", "scripts"), Path.Combine(ContractLoader.RepositoryRoot, "scripts"));
        ReferenceFixtures.Junction(Path.Combine(Work, ".toolchain", "contracts"), Path.Combine(ContractLoader.RepositoryRoot, "contracts"));
        Directory.CreateDirectory(Path.Combine(Course, "section1"));
        File.WriteAllText(Path.Combine(Course, "course_config.json"),
            """{"course_code": "ICS3U", "deploy_target": "local_folder", "num_sections": 1, "section_numbers": [1]}""");
        File.WriteAllText(Path.Combine(Course, "section1", "index.md"), "---\npublish: true\n---\nWelcome.\n");
        Directory.CreateDirectory(TrailDir);
    }

    public void Dispose()
    {
        try { ScheduledHealthFindings.Take("ICS3U", 1, Work); } catch { }
        ReferenceFixtures.Remove(_root);
    }

    private static bool PowerShellIsAvailable =>
        OperatingSystem.IsWindows() && File.Exists(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"));

    /// <summary>A built section, after the course, stamped by <see cref="Toolchain"/>.</summary>
    private void BuildTheSite(string page = "<html><body>Welcome</body></html>", bool stamped = true)
    {
        Thread.Sleep(FreshnessCases.PauseMilliseconds);
        Directory.CreateDirectory(Path.Combine(Section, "public"));
        File.WriteAllText(Path.Combine(Section, ".build-started"), "");
        Thread.Sleep(FreshnessCases.PauseMilliseconds);
        File.WriteAllText(Path.Combine(Section, "public", "index.html"), page);
        if (stamped) File.WriteAllText(Path.Combine(Section, ".built-with-toolchain"), Toolchain + "\n");
        Thread.Sleep(FreshnessCases.PauseMilliseconds);
    }

    private (int ExitCode, string Output) RunWrapper(int buildExit = 0, string? runtime = "the test's own")
    {
        File.WriteAllText(Path.Combine(Work, "preview.ps1"),
            $"Add-Content -LiteralPath '{BuiltMark}' -Value 'built'\nexit {buildExit}\n");
        File.WriteAllText(Path.Combine(Work, "deploy.ps1"),
            $"Add-Content -LiteralPath '{DeployedMark}' -Value 'deployed'\nexit 0\n");
        string task = $"Plantoir-sched-reuse-{Guid.NewGuid():N}";
        string? script = TaskScheduling.WriteWrapperScript(task, Work, Path.Combine(Work, "deploy.ps1"), "ICS3U", 1, Course,
            Array.Empty<string>(), new[] { new CourseConfiguration.DeployDestination("local_folder", Path.Combine(_root, "out")) }, "");
        Assert.NotNull(script);
        string runnable = Path.Combine(_root, Path.GetFileName(script!));
        File.WriteAllText(runnable, File.ReadAllText(script!).Replace(ScheduledPublishOutcome.Directory(), _root));
        try { File.Delete(script!); } catch { }

        string? runtimeFolder = runtime == "the test's own" ? NativeRuntime.Folder : runtime;
        var info = ScheduledRun.WrapperStartInfo(runnable, LauncherEnvironment.Variables(runtimeFolder, TrailDir));
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.Environment[TaskScheduling.TestStateDirVariable] = AppDataRoot.Current;
        info.Environment["LOCALAPPDATA"] = Local;
        info.Environment["PLANTOIR_TOOLCHAIN_ID"] = Toolchain;
        using var process = Process.Start(info)!;
        string output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
        process.WaitForExit(120_000);
        return (process.ExitCode, output);
    }

    private bool Built => File.Exists(BuiltMark);
    private bool Deployed => File.Exists(DeployedMark);

    private string[] TrailLines() => File.Exists(Path.Combine(TrailDir, "activity.txt"))
        ? File.ReadAllLines(Path.Combine(TrailDir, "activity.txt")).Where(l => l.Contains("before deploying it", StringComparison.Ordinal)).ToArray()
        : Array.Empty<string>();

    private static string LineFor(string reason) =>
        BuiltBeforeDeployingTrailTests.ContractLine(reason).Replace("ICS4U/2", "ICS3U/1");

    [Fact]
    public void NothingChangedDeploysTheLastBuildWithNoBuildAndNoLine()
    {
        if (!PowerShellIsAvailable || NativeRuntime.Folder is null) return;
        BuildTheSite();

        var (exit, output) = RunWrapper();

        Assert.True(exit == 0, output);
        Assert.False(Built, "the wrapper built a site nothing had changed since");
        Assert.True(Deployed, output);
        Assert.Empty(TrailLines());
    }

    [Fact]
    public void APageEditedSinceBuildsOnceAndSaysWhy()
    {
        if (!PowerShellIsAvailable || NativeRuntime.Folder is null) return;
        BuildTheSite();
        File.AppendAllText(Path.Combine(Course, "section1", "index.md"), "\nedited\n");

        var (exit, output) = RunWrapper();

        Assert.True(exit == 0, output);
        Assert.True(Built && Deployed, output);
        Assert.EndsWith(LineFor(BuildFreshness.ReasonPages), Assert.Single(TrailLines()));
    }

    [Fact]
    public void APreviewsSiteIsBuiltAgainAndSaysSo()
    {
        if (!PowerShellIsAvailable || NativeRuntime.Folder is null) return;
        BuildTheSite(page: FreshnessCases.PreviewPage(), stamped: false);

        var (exit, output) = RunWrapper();

        Assert.True(exit == 0, output);
        Assert.True(Built, output);
        Assert.EndsWith(LineFor(BuildFreshness.ReasonPreview), Assert.Single(TrailLines()));
    }

    [Fact]
    public void AnotherToolchainsSiteIsBuiltAgainForTheToolchain()
    {
        if (!PowerShellIsAvailable || NativeRuntime.Folder is null) return;
        BuildTheSite(stamped: false);

        var (exit, output) = RunWrapper();

        Assert.True(exit == 0, output);
        Assert.True(Built, output);
        Assert.EndsWith(LineFor("toolchain"), Assert.Single(TrailLines()));
    }

    /// <summary>The question cannot be asked (no Python here at all): build, the
    /// safe direction, with the toolchain's words as deploy.ps1 says them.</summary>
    [Fact]
    public void AQuestionThatCannotBeAskedBuilds()
    {
        if (!PowerShellIsAvailable) return;
        BuildTheSite();

        var (exit, output) = RunWrapper(runtime: Path.Combine(_root, "no runtime here"));

        Assert.True(exit == 0, output);
        Assert.True(Built, "a question that could not be asked reused the last build");
        Assert.EndsWith(LineFor("toolchain"), Assert.Single(TrailLines()));
    }

    [Fact]
    public void ASectionNeverBuiltIsBuiltAndSaysSo()
    {
        if (!PowerShellIsAvailable) return;

        var (exit, output) = RunWrapper();

        Assert.True(exit == 0, output);
        Assert.True(Built, output);
        Assert.EndsWith(LineFor(BuildFreshness.ReasonNeverBuilt), Assert.Single(TrailLines()));
    }

    [Fact]
    public void ABuildThatFailsWritesNoLineAndDeploysNothing()
    {
        if (!PowerShellIsAvailable) return;
        BuildTheSite();
        File.AppendAllText(Path.Combine(Course, "section1", "index.md"), "\nedited\n");

        var (exit, _) = RunWrapper(buildExit: 1);

        Assert.Equal(1, exit);
        Assert.True(Built);
        Assert.False(Deployed);
        Assert.Empty(TrailLines());
    }

    // ---- The copies are deploy.ps1's own --------------------------------------

    private static string DeployPs1 => File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "deploy.ps1")).Replace("\r\n", "\n");

    [Fact]
    public void TheWrappersTrailWriterIsDeployPs1sByteForByte()
    {
        string source = DeployPs1;
        int start = source.IndexOf("function Write-TrailLine {\n", StringComparison.Ordinal);
        Assert.True(start >= 0);
        int end = source.IndexOf("\n}\n", start, StringComparison.Ordinal);
        Assert.Equal(string.Join("\n", BuildBeforeDeployingQuestion.TrailWriterLines), source[start..(end + 2)]);
    }

    [Fact]
    public void TheWrappersQuestionIsDeployPs1sByteForByte()
    {
        string source = DeployPs1;
        int function = source.IndexOf("function Get-WhyBuildBeforeDeploying(", StringComparison.Ordinal);
        Assert.True(function >= 0, "deploy.ps1 has no Get-WhyBuildBeforeDeploying");
        int open = source.IndexOf("@'\n", function, StringComparison.Ordinal) + 3;
        int close = source.IndexOf("\n'@", open, StringComparison.Ordinal);
        Assert.Equal(string.Join("\n", BuildBeforeDeployingQuestion.PythonLines), source[open..close]);
    }

    [Fact]
    public void TheWrapperNoLongerBuildsAlways()
    {
        string? script = TaskScheduling.WriteWrapperScript("Plantoir-sched-text-" + Guid.NewGuid().ToString("N"), Work,
            Path.Combine(Work, "deploy.ps1"), "ICS3U", 1, Course, Array.Empty<string>(),
            new[] { new CourseConfiguration.DeployDestination("local_folder", _root) }, "");
        string text = File.ReadAllText(script!);
        try { File.Delete(script!); } catch { }
        Assert.DoesNotContain("Build first, always", text);
        // ASCII only outside comments: the wrapper has no BOM, and Windows
        // PowerShell 5.1 reads such a file in the ANSI code page.
        foreach (string line in text.Split('\n').Where(l => !l.TrimStart().StartsWith('#')))
            Assert.True(line.All(c => c < 128), "a non-ASCII character in generated code: " + line);
        // The question comes before the build, and the line after the failure guard.
        int asked = text.IndexOf("$whyAnswer = (& $pythonExe -c $whyCheck", StringComparison.Ordinal);
        int built = text.IndexOf("--build-only --non-interactive", StringComparison.Ordinal);
        int guard = text.IndexOf("} elseif ($buildExit -ne 0) {", StringComparison.Ordinal);
        int written = text.IndexOf("Write-TrailLine $builtWords[$buildReason]", StringComparison.Ordinal);
        Assert.True(asked > 0 && asked < built && built < guard && guard < written);
    }
}

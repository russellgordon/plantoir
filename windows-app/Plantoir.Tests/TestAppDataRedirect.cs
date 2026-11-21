using System;
using System.IO;
using System.Runtime.CompilerServices;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Sends everything the suite would keep under <c>%LOCALAPPDATA%\Plantoir</c>
/// — settings, models, builds, scheduled-publish state — into a scratch folder
/// of this run's own (#285). Before this, a test that reached
/// <see cref="AppDataRoot.Current"/> read and wrote the teacher's REAL state,
/// the same way the trail once did (see <see cref="TestTrailRedirect"/>).
/// Runs once, before any test, so no per-class setup can forget it.
///
/// <para>The folder is this run's own (#916 item 3): named by process id AND
/// start time, as <see cref="RunOwnedTempFolders"/> names its folders, so two
/// suites running at once (a worktree each) do not share a settings file, and
/// a later run that is given a recycled process id does not start on an
/// earlier run's settings. It is removed when the run ends. A crashed run's
/// folder is left, and no run removes a folder it did not make (#882's rule):
/// the old <c>plantoir-tests-&lt;pid&gt;</c> folders on a machine are not this
/// code's to sweep.</para>
/// </summary>
internal static class TestAppDataRedirect
{
    internal const string Prefix = "plantoir-tests-";

    internal static readonly string ScratchRoot =
        RunFolder(Path.GetTempPath(), Prefix, RunOwnedTempFolders.ThisRun);

    /// <summary>The folder a run with this owner tag (<see cref="RunOwnedTempFolders.OwnerTag"/>) keeps under <paramref name="tempRoot"/>.</summary>
    internal static string RunFolder(string tempRoot, string prefix, string ownerTag) =>
        Path.Combine(tempRoot, prefix + ownerTag);

    [ModuleInitializer]
    internal static void Redirect()
    {
        AppDataRoot.RedirectTo(ScratchRoot);
        Plantoir.Core.Assist.TaskScheduling.RealSchtasksGuardForTests = RefuseARealRegistration;
        AppDomain.CurrentDomain.ProcessExit += RemoveThisRunsFolders;
    }

    /// <summary>When the test host ends: this run's settings folder and its trail's folder, and nothing else.</summary>
    private static void RemoveThisRunsFolders(object? sender, EventArgs e)
    {
        foreach (string folder in new[] { ScratchRoot, TestTrailRedirect.ScratchTrailFolder })
        {
            try
            {
                if (Directory.Exists(folder)) Directory.Delete(folder, recursive: true);
            }
            catch { }   // something still holds a file: left, as a crashed run's would be
        }
    }

    /// <summary>A read (/Query) is harmless; anything else would change the
    /// teacher's real Task Scheduler.</summary>
    internal static void RefuseARealRegistration(System.Collections.Generic.IReadOnlyList<string> arguments)
    {
        if (arguments.Count > 0 && !arguments[0].Equals("/Query", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(
                "A unit test reached the REAL schtasks.exe with " + string.Join(" ", arguments) +
                ". Use FakeScheduler.");
    }
}

public class AppDataRedirectTests
{
    [Fact]
    public void TheSuiteNeverKeepsStateInTheTeachersRealFolder()
    {
        Assert.True(AppDataRoot.IsRedirected,
            "AppDataRoot is not redirected under dotnet test: the suite is reading and writing the real %LOCALAPPDATA% Plantoir folder.");
        Assert.StartsWith(Path.GetFullPath(Path.GetTempPath()), AppDataRoot.Current, StringComparison.OrdinalIgnoreCase);
        string real = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir");
        Assert.NotEqual(real, AppDataRoot.Current, StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>
    /// #916 item 3: two runs given the SAME process id at different start
    /// times get two folders, so a recycled id never lands on an earlier run's
    /// settings. Before, the name was the process id alone.
    /// </summary>
    [Fact]
    public void TwoRunsWithOneProcessIdAndDifferentStartsGetTwoFolders()
    {
        string root = RunOwnedTempFolders.Create("plantoir-916-naming-");
        try
        {
            string first = TestAppDataRedirect.RunFolder(root, TestAppDataRedirect.Prefix, RunOwnedTempFolders.OwnerTag(4242, 638_000_000_000_000_001));
            string second = TestAppDataRedirect.RunFolder(root, TestAppDataRedirect.Prefix, RunOwnedTempFolders.OwnerTag(4242, 638_000_000_000_000_002));
            Directory.CreateDirectory(first);
            Directory.CreateDirectory(second);
            Assert.Equal(2, Directory.GetDirectories(root, TestAppDataRedirect.Prefix + "4242-*").Length);
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    /// <summary>This run's settings folder and trail are named for this process: its id and its start time.</summary>
    [Fact]
    public void ThisRunsFoldersCarryItsProcessIdAndStartTime()
    {
        Assert.Equal(TestAppDataRedirect.Prefix + RunOwnedTempFolders.ThisRun, Path.GetFileName(TestAppDataRedirect.ScratchRoot));
        Assert.Equal(Path.GetFullPath(TestAppDataRedirect.ScratchRoot), Path.GetFullPath(AppDataRoot.Current), StringComparer.OrdinalIgnoreCase);
        Assert.Equal(TestTrailRedirect.Prefix + RunOwnedTempFolders.ThisRun,
            Path.GetFileName(Path.GetDirectoryName(TestTrailRedirect.ScratchTrailPath)));
        Assert.StartsWith(Environment.ProcessId + "-", RunOwnedTempFolders.ThisRun);
    }

    [Fact]
    public void ARealTaskRegistrationIsRefusedUnderTheSuite()
    {
        Assert.NotNull(Plantoir.Core.Assist.TaskScheduling.RealSchtasksGuardForTests);
        Assert.Throws<InvalidOperationException>(() =>
            Plantoir.Core.Assist.TaskScheduling.RealSchtasksGuardForTests!(new[] { "/Create", "/TN", "x" }));
        Plantoir.Core.Assist.TaskScheduling.RealSchtasksGuardForTests!(new[] { "/Query" });
    }
}

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
/// <para>Per process id, so two suites running at once (a worktree each) do
/// not share a settings file.</para>
/// </summary>
internal static class TestAppDataRedirect
{
    internal static readonly string ScratchRoot =
        Path.Combine(Path.GetTempPath(), "plantoir-tests-" + Environment.ProcessId);

    [ModuleInitializer]
    internal static void Redirect()
    {
        AppDataRoot.RedirectTo(ScratchRoot);
        Plantoir.Core.Assist.TaskScheduling.RealSchtasksGuardForTests = RefuseARealRegistration;
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

    [Fact]
    public void ARealTaskRegistrationIsRefusedUnderTheSuite()
    {
        Assert.NotNull(Plantoir.Core.Assist.TaskScheduling.RealSchtasksGuardForTests);
        Assert.Throws<InvalidOperationException>(() =>
            Plantoir.Core.Assist.TaskScheduling.RealSchtasksGuardForTests!(new[] { "/Create", "/TN", "x" }));
        Plantoir.Core.Assist.TaskScheduling.RealSchtasksGuardForTests!(new[] { "/Query" });
    }
}

using System;
using System.IO;
using System.Runtime.CompilerServices;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// Sends every ActivityTrail line a test provokes into a scratch file instead
/// of the REAL trail. Without this, running the suite writes fixture courses
/// (VVH2O and friends) into %LOCALAPPDATA%\Plantoir\Logs\activity.txt — the
/// same file a genuine problem report gathers, where a phantom course reads
/// as a fault that never happened. Runs before any test, so no per-class
/// setup can forget it.
/// </summary>
internal static class TestTrailRedirect
{
    /// <summary>
    /// Where the suite's trail lines go. Public so a test that needs its OWN
    /// trail file can put this one back afterwards.
    ///
    /// <para>Restoring <c>null</c> instead would restore the REAL trail, and
    /// every test that ran afterwards would write a fixture course into a
    /// teacher's diagnostic record. That is not hypothetical: it happened
    /// here, and the phantom lines included "removed the small assistant —
    /// 1.12 GB freed", which reads as a fault that never occurred.</para>
    ///
    /// <para>This run's own file (#916 item 4), in a folder named by process id
    /// and start time as <see cref="RunOwnedTempFolders"/> names its folders,
    /// removed with the run's settings folder when the run ends
    /// (<see cref="TestAppDataRedirect"/>). It was one
    /// <c>%TEMP%\plantoir-tests\activity.txt</c> that every run on the
    /// machine appended to at once.</para>
    /// </summary>
    internal static readonly string ScratchTrailPath =
        Path.Combine(ScratchTrailFolder, "activity.txt");

    internal const string Prefix = "plantoir-tests-trail-";

    /// <summary>The folder that holds <see cref="ScratchTrailPath"/>, this run's alone.</summary>
    internal static string ScratchTrailFolder =>
        TestAppDataRedirect.RunFolder(Path.GetTempPath(), Prefix, RunOwnedTempFolders.ThisRun);

    [ModuleInitializer]
    internal static void Redirect() => ActivityTrail.SetCustomLogPathForTesting(ScratchTrailPath);
}

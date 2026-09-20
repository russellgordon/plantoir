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
    /// </summary>
    internal static readonly string ScratchTrailPath =
        Path.Combine(Path.GetTempPath(), "plantoir-tests", "activity.txt");

    [ModuleInitializer]
    internal static void Redirect() => ActivityTrail.SetCustomLogPathForTesting(ScratchTrailPath);
}

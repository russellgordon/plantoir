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
    [ModuleInitializer]
    internal static void Redirect()
    {
        string path = Path.Combine(Path.GetTempPath(), "plantoir-tests", "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(path);
    }
}

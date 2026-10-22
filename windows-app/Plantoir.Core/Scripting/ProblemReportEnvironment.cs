using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace Plantoir.Core.Scripting;

/// <summary>
/// Captures the runtime environment (app version, OS build, hardware resources,
/// helper tool software versions) for activity logging and problem reports.
/// Matches macOS ProblemReportEnvironment.
/// </summary>
public static class ProblemReportEnvironment
{
    /// <summary>
    /// "1.7.2": the three-part version a teacher sees in About and on the
    /// update lines (<see cref="Plantoir.Core.Assist.AppUpdates.Spell"/>), then
    /// the build in brackets when there is one (#565, mac #560). Windows
    /// carries no build number of its own — <c>&lt;Version&gt;1.7.2&lt;/Version&gt;</c>
    /// makes the assembly 1.7.2.0 — so a revision of 0 means "none" and no
    /// brackets are written. Until #565 this printed "1.7 (2)", the patch
    /// number shown as a build, beside update lines saying "from 1.7.1 to 1.7.2".
    /// </summary>
    public static string AppVersion => Spelled(
        (Assembly.GetEntryAssembly() ?? typeof(ProblemReportEnvironment).Assembly).GetName().Version);

    /// <summary><see cref="AppVersion"/> for a given version; public for its test.</summary>
    public static string Spelled(Version? version)
    {
        if (version is null) return "1.0.0";
        string three = Plantoir.Core.Assist.AppUpdates.Spell(version);
        return version.Revision > 0 ? $"{three} ({version.Revision})" : three;
    }

    /// <summary>"Plantoir 1.7.2 · pid 4711 · C:\…\Plantoir.exe": the `app opened` line's words after "Plantoir opened — ".</summary>
    public static string AppDescription
    {
        get
        {
            int pid = Environment.ProcessId;
            string path = LogRedactor.Redacting(Environment.ProcessPath ?? AppContext.BaseDirectory);
            return $"Plantoir {AppVersion} · pid {pid} · {path}";
        }
    }

    public static string SystemDescription
    {
        get
        {
            var os = Environment.OSVersion;
            string build = os.Version.Build.ToString();
            string arch = RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant();
            int cores = Environment.ProcessorCount;
            long memoryBytes = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes;
            long memoryGb = memoryBytes > 0 ? (memoryBytes / (1024L * 1024 * 1024)) : 0;
            string memoryStr = memoryGb > 0 ? $" · {memoryGb} GB" : "";
            return $"Windows {os.Version.Major}.{os.Version.Minor} ({build}) · {arch} · {cores} cores{memoryStr}";
        }
    }

    /// <summary>
    /// Which machinery this build actually uses — read from what is on
    /// disk, never asserted: a hard-coded "WSL2" here once had every
    /// native-toolchain problem report claiming a subsystem the product
    /// no longer touched.
    /// </summary>
    public static string HelperDescription =>
        $"llama.cpp b10435 (Vulkan) · {ToolchainDescription} · .NET {Environment.Version}";

    private static string ToolchainDescription =>
        NativeRuntime.Directory is null ? "WSL2" : "native toolchain";
}

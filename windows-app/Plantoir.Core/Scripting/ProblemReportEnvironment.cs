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
    public static string AppDescription
    {
        get
        {
            var assembly = Assembly.GetEntryAssembly() ?? typeof(ProblemReportEnvironment).Assembly;
            var ver = assembly.GetName().Version;
            string versionStr = ver is not null ? $"{ver.Major}.{ver.Minor}" : "1.0";
            string buildNumber = ver is not null ? $"{ver.Build}" : "1";
            int pid = Environment.ProcessId;
            string path = LogRedactor.Redacting(Environment.ProcessPath ?? AppContext.BaseDirectory);
            return $"Plantoir {versionStr} ({buildNumber}) · pid {pid} · {path}";
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

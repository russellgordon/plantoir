namespace Plantoir.Core.Scripting;

/// <summary>
/// Where the app's bundled native toolchain runtime lives (node, python,
/// patched Quartz, wrangler) — the folder that lets launchers build with no
/// WSL2, no container and no administrator rights. ONE resolver, because the
/// first bug this design shipped was three launch sites disagreeing: the
/// ConPTY path set PLANTOIR_RUNTIME and the stop-sweep and MCP paths did
/// not, so a sweep against a Debug build quietly booted WSL and stopped
/// nothing.
/// </summary>
public static class NativeRuntime
{
    /// <summary>The runtime folder beside this executable, or null when the
    /// app carries none (a checkout without Vendor/fetch-runtime.ps1 run).</summary>
    public static string? Directory
    {
        get
        {
            string candidate = Path.Combine(AppContext.BaseDirectory, "runtime");
            return File.Exists(Path.Combine(candidate, "manifest.json")) ? candidate : null;
        }
    }

    /// <summary>Points a launcher child at the runtime, when there is one.</summary>
    public static void Apply(System.Diagnostics.ProcessStartInfo info)
    {
        if (Directory is { } runtime)
            info.EnvironmentVariables["PLANTOIR_RUNTIME"] = runtime;
    }
}

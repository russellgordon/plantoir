using System.Diagnostics;

namespace Plantoir.Core.Scripting;

/// <summary>
/// What every launcher child (<c>preview.ps1</c>, <c>deploy.ps1</c>, and the
/// scheduled publish's wrapper) is handed in its environment. ONE resolver,
/// because the first bug the native runtime shipped was three launch sites
/// disagreeing: the ConPTY path set PLANTOIR_RUNTIME and the stop sweep and
/// the MCP paths did not, so a sweep against a Debug build quietly booted WSL
/// and stopped nothing (see <see cref="NativeRuntime"/>).
/// <list type="bullet">
/// <item><c>PLANTOIR_RUNTIME</c>: the bundled runtime folder, when the app
/// carries one.</item>
/// <item><c>PLANTOIR_TRAIL_DIR</c> (#682, the Windows half of mac #664,
/// <c>contracts/app-rules.json</c> → <c>launcherTrailFolder</c>): the app's
/// OWN trail folder, ALWAYS, overriding any value the app inherited. So an
/// app started with <c>--state-dir</c>, and the unit suite whose trail is a
/// scratch file, keep a launcher's own refusal lines in their trail and not
/// in the teacher's real one. "Always" rather than only when redirected is
/// the contract's rule: it needs no second branch to clear a stale inherited
/// value, and in the plain app the folder is the one the launcher would have
/// computed anyway.</item>
/// </list>
/// Setting the trail always means a run with no runtime now builds an
/// explicit environment block too; that is harmless (ConPTY merges it over
/// the inherited one).
/// </summary>
public static class LauncherEnvironment
{
    public const string RuntimeVariable = "PLANTOIR_RUNTIME";
    public const string TrailVariable = "PLANTOIR_TRAIL_DIR";

    /// <summary>The variables for a runtime folder (or none) and a trail folder.</summary>
    public static IReadOnlyDictionary<string, string> Variables(string? runtime, string trailFolder)
    {
        var variables = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (runtime is not null) variables[RuntimeVariable] = runtime;
        variables[TrailVariable] = trailFolder;
        return variables;
    }

    /// <summary>What this process hands its launchers now.</summary>
    public static IReadOnlyDictionary<string, string> Current =>
        Variables(NativeRuntime.Directory, ActivityTrail.CurrentLogDirectory);

    /// <summary>Hands a launcher child <see cref="Current"/>, replacing any
    /// value it would otherwise inherit.</summary>
    public static void Apply(ProcessStartInfo info)
    {
        foreach (var (name, value) in Current)
            info.EnvironmentVariables[name] = value;
    }
}

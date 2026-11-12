using System.Diagnostics;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #682 (the Windows half of mac #664): every launcher child is handed the
/// app's OWN trail folder in <c>PLANTOIR_TRAIL_DIR</c>, always, overriding an
/// inherited value (<c>contracts/app-rules.json</c> → <c>launcherTrailFolder</c>).
/// The launcher side - which values it takes - is
/// <c>windows-app/test_launcher_rules.ps1</c> section 6. In the
/// SharedActivityState collection because it reads the trail's path, which
/// other classes move.
/// </summary>
[Collection(SharedActivityState.Name)]
public class LauncherEnvironmentTests
{
    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }

    [Fact]
    public void TheLauncherIsHandedTheAppsTrailFolderAndItOverridesAnInheritedOne()
    {
        // The shape of the mac's HelperProgramsTests.testEnvironmentHandsTheLauncherTheAppsTrailFolder.
        var info = new ProcessStartInfo("powershell.exe");
        info.EnvironmentVariables[LauncherEnvironment.TrailVariable] = @"C:\elsewhere";

        LauncherEnvironment.Apply(info);

        string handed = info.EnvironmentVariables[LauncherEnvironment.TrailVariable]!;
        Assert.Equal(ActivityTrail.CurrentLogDirectory, handed);
        Assert.NotEqual(@"C:\elsewhere", handed);
        // Under the suite the trail is a scratch file, so the launcher is NOT
        // pointed at the teacher's real trail - the gap #682 closes.
        Assert.NotEqual(Path.GetFullPath(ActivityTrail.DefaultLogDirectory), Path.GetFullPath(handed));
        Assert.True(Path.IsPathFullyQualified(handed), "a launcher takes only an absolute folder");
    }

    [Fact]
    public void TheTrailIsAlwaysHandedAndTheRuntimeOnlyWhenThereIsOne()
    {
        var without = LauncherEnvironment.Variables(null, @"C:\state\Logs");
        Assert.Equal(@"C:\state\Logs", without[LauncherEnvironment.TrailVariable]);
        Assert.False(without.ContainsKey(LauncherEnvironment.RuntimeVariable));

        var with = LauncherEnvironment.Variables(@"C:\app\runtime", @"C:\state\Logs");
        Assert.Equal(@"C:\app\runtime", with[LauncherEnvironment.RuntimeVariable]);
        Assert.Equal(@"C:\state\Logs", with[LauncherEnvironment.TrailVariable]);
    }

    [Fact]
    public void TheVariableIsTheContractsName()
    {
        string name = ContractLoader.LoadJson("app-rules.json")["launcherTrailFolder"]!["variable"]!.GetValue<string>();
        Assert.Equal(name, LauncherEnvironment.TrailVariable);
    }

    /// <summary>
    /// #702: the scheduled publish's wrapper is handed the runtime of the app
    /// running the task, not only the trail, so a task registered from a Debug
    /// build no longer falls back to the INSTALLED copy's runtime. Through the
    /// seam, because the test host carries no runtime of its own
    /// (<see cref="NativeRuntime.Directory"/> is null here), so a check through
    /// the plain overload would pass with the runtime never handed at all.
    /// </summary>
    [Fact]
    public void TheScheduledPublishsWrapperIsHandedTheRuntimeAndTheTrail()
    {
        var info = ScheduledRun.WrapperStartInfo(@"C:\scheduled\x.ps1",
            LauncherEnvironment.Variables(@"C:\the registering app\runtime", @"C:\state\Logs"));

        Assert.Equal(@"C:\the registering app\runtime", info.EnvironmentVariables[LauncherEnvironment.RuntimeVariable]);
        Assert.Equal(@"C:\state\Logs", info.EnvironmentVariables[LauncherEnvironment.TrailVariable]);
        Assert.Contains("-File", info.ArgumentList);
    }

    /// <summary>
    /// The plain overload, the one <c>RunWrapperForReal</c> calls, hands the
    /// seam <see cref="LauncherEnvironment.Current"/>: read from the code with
    /// comments taken out, because the test host has no runtime to tell a
    /// handed one from a missing one. And the trail, which it CAN tell.
    /// </summary>
    [Fact]
    public void TheWrapperThatRunsIsHandedTheLauncherEnvironmentOfThisApp()
    {
        string code = CodeOnly(File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Plantoir.Core", "Assist", "ScheduledRun.cs")));
        Assert.Matches(new Regex(@"ProcessStartInfo\s+WrapperStartInfo\(string\s+script\)\s*=>\s*WrapperStartInfo\(script,\s*LauncherEnvironment\.Current\)\s*;"), code);
        Assert.Matches(new Regex(@"var\s+info\s*=\s*WrapperStartInfo\(script\)\s*;"), code);

        var info = ScheduledRun.WrapperStartInfo(@"C:\scheduled\x.ps1");
        Assert.Equal(ActivityTrail.CurrentLogDirectory, info.EnvironmentVariables[LauncherEnvironment.TrailVariable]);
    }

    /// <summary>C# with its comments removed: every <c>//</c> to the end of
    /// its line (doc comments included) and every <c>/* */</c> block. Crude
    /// about a <c>//</c> inside a string, which only ever removes code, so a
    /// guard cannot pass on a mention.</summary>
    private static string CodeOnly(string source)
    {
        string withoutBlocks = Regex.Replace(source, @"/\*.*?\*/", "", RegexOptions.Singleline);
        return Regex.Replace(withoutBlocks, @"//[^\n]*", "");
    }

    /// <summary>
    /// The "three launch sites disagreed" bug, pinned: every place in the
    /// product that starts a process with <c>-File</c> (a launcher or the
    /// scheduled publish's wrapper) hands it <see cref="LauncherEnvironment"/>.
    /// DISCOVERED rather than listed, so a fifth start site cannot be added
    /// without it.
    ///
    /// <para>Read with comments taken out, and asking for a USE of it
    /// (<c>Apply(</c>, <c>Current</c> or <c>Variables(</c>) rather than its
    /// name: until #702 the scheduled wrapper's start passed this scan on the
    /// word in its doc comment while handing only the trail.</para>
    /// </summary>
    [Fact]
    public void EveryPlaceThatStartsALauncherHandsItTheLauncherEnvironment()
    {
        var starts = new Regex(@"new ProcessStartInfo|ConPtyProcess\.Start\(");
        var handsIt = new Regex(@"LauncherEnvironment\s*\.\s*(Apply\s*\(|Current\b|Variables\s*\()");
        int found = 0;
        var missing = new List<string>();
        foreach (string project in new[] { "Plantoir", "Plantoir.Core", "Plantoir.Mcp" })
        {
            string root = Path.Combine(RepoRoot, "windows-app", project);
            foreach (string file in Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories))
            {
                if (file.Contains(Path.DirectorySeparatorChar + "bin" + Path.DirectorySeparatorChar) ||
                    file.Contains(Path.DirectorySeparatorChar + "obj" + Path.DirectorySeparatorChar)) continue;
                string[] lines = CodeOnly(File.ReadAllText(file)).Split('\n');
                for (int i = 0; i < lines.Length; i++)
                {
                    if (!starts.IsMatch(lines[i])) continue;
                    string window = string.Join("\n", lines[Math.Max(0, i - 25)..Math.Min(lines.Length, i + 25)]);
                    if (!window.Contains("\"-File") && !window.Contains("-File \"") && !window.Contains("WrapperRunArguments")) continue;
                    found++;
                    if (!handsIt.IsMatch(window))
                        missing.Add($"{Path.GetRelativePath(RepoRoot, file)}:{i + 1}");
                }
            }
        }
        Assert.Empty(missing);
        // ScriptRunner.Run, LauncherRunner's run and --stop sweep,
        // PreviewStopper, and ScheduledRun.WrapperStartInfo.
        Assert.True(found >= 5, $"found only {found} launcher start sites; the scan has stopped seeing them");
    }
}

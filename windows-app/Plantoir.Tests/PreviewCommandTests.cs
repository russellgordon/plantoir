using System.Reflection;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #828 (mac #729): the ONE builder of the app's <c>preview.ps1 --build-only</c>
/// lines. A deploy's build leg carries <c>--for-deploy</c>
/// (<c>app-rules.json</c> → <c>launcherFlags.preview</c> → <c>usedFor</c>);
/// the assistant's rebuild and the scheduled wrapper's build never do
/// (<c>notUsedFor</c>); and the flag goes only to a folder whose own
/// <c>preview.ps1</c> takes it (review M4).
/// </summary>
public sealed class PreviewCommandTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-preview-command").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static string CurrentLauncher() =>
        File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "preview.ps1"));

    [Fact]
    public void ADeploysBuildLegCarriesTheFlagAndARebuildNever()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), CurrentLauncher());
        Assert.Equal(new[] { "ICS4U", "2", "--build-only", "--for-deploy" },
                     PreviewCommand.BuildOnlyArguments(_folder, "ICS4U", 2, forADeploy: true, nonInteractive: false));
        Assert.Equal(new[] { "ICS4U", "2", "--build-only", "--non-interactive", "--for-deploy" },
                     PreviewCommand.BuildOnlyArguments(_folder, "ICS4U", 2, forADeploy: true, nonInteractive: true));
        Assert.Equal(new[] { "AP CALC", "1", "--build-only", "--non-interactive" },
                     PreviewCommand.BuildOnlyArguments(_folder, "AP CALC", 1, forADeploy: false, nonInteractive: true));
    }

    /// <summary>
    /// An older launcher (the real one with the flag's case taken out), a
    /// folder with none, and one that cannot be read: no flag, so nothing is
    /// refused as "Unknown option".
    /// </summary>
    [Fact]
    public void AnOlderLauncherIsNotHandedTheFlag()
    {
        string older = string.Join("\n", CurrentLauncher().Replace("\r\n", "\n").Split('\n')
            .Where(line => !line.Contains("'--for-deploy'", StringComparison.Ordinal)));
        Assert.Contains("Unknown option", older);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), older);
        Assert.False(PreviewCommand.LauncherTakesForDeploy(_folder));
        Assert.Equal(new[] { "ICS4U", "2", "--build-only" },
                     PreviewCommand.BuildOnlyArguments(_folder, "ICS4U", 2, forADeploy: true, nonInteractive: false));

        string none = Directory.CreateTempSubdirectory("plantoir-no-launcher").FullName;
        try { Assert.False(PreviewCommand.LauncherTakesForDeploy(none)); }
        finally { Directory.Delete(none, recursive: true); }

        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), CurrentLauncher());
        using (new FileStream(Path.Combine(_folder, "preview.ps1"), FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Assert.False(PreviewCommand.LauncherTakesForDeploy(_folder));
        Assert.True(PreviewCommand.LauncherTakesForDeploy(_folder));
    }

    /// <summary>
    /// A new call site must CHOOSE (the mac's <c>buildArguments(forADeploy:)</c>
    /// is required for the same reason): <c>forADeploy</c> has no default.
    /// </summary>
    [Fact]
    public void ForADeployHasNoDefault()
    {
        var method = typeof(PreviewCommand).GetMethod(nameof(PreviewCommand.BuildOnlyArguments))!;
        var forADeploy = method.GetParameters().Single(parameter => parameter.Name == "forADeploy");
        Assert.False(forADeploy.HasDefaultValue);
        Assert.Single(typeof(PreviewCommand).GetMethods(BindingFlags.Public | BindingFlags.Static),
                      candidate => candidate.Name == nameof(PreviewCommand.BuildOnlyArguments));
    }

    /// <summary>
    /// No <c>"--build-only"</c> string literal is left in the app's code
    /// outside the builder and the scheduled wrapper's text (the body of
    /// <c>TaskScheduling.WriteWrapperScript</c>, not the whole file), and the
    /// wrapper's text never carries <c>--for-deploy</c> (its own script
    /// already counts as 'later'). Comment lines are not code (review L3:
    /// seven doc comments name the flag).
    /// </summary>
    [Fact]
    public void EveryBuildOnlyLineComesFromTheBuilder()
    {
        string root = Path.Combine(ContractLoader.RepositoryRoot, "windows-app");
        var allowed = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            Path.Combine(root, "Plantoir.Core", "Scripting", "PreviewCommand.cs"),
        };
        // TaskScheduling.cs is scanned like any other file EXCEPT the body of
        // WriteWrapperScript, the scheduled wrapper's text (review L5): from
        // its declaration to the first closing brace at member indent.
        string scheduling = Path.Combine(root, "Plantoir.Core", "Assist", "TaskScheduling.cs");
        string[] schedulingLines = File.ReadAllLines(scheduling);
        int wrapperStart = Array.FindIndex(schedulingLines,
            line => line.TrimStart().StartsWith("internal static string? WriteWrapperScript(", StringComparison.Ordinal));
        Assert.True(wrapperStart >= 0, "WriteWrapperScript's declaration was not found in TaskScheduling.cs");
        int wrapperEnd = Array.FindIndex(schedulingLines, wrapperStart, line => line == "    }");
        Assert.True(wrapperEnd > wrapperStart, "WriteWrapperScript's closing brace was not found in TaskScheduling.cs");
        var found = new List<string>();
        foreach (string project in new[] { "Plantoir.Core", "Plantoir", "Plantoir.Mcp" })
        {
            foreach (string file in Directory.EnumerateFiles(Path.Combine(root, project), "*.cs", SearchOption.AllDirectories))
            {
                if (file.Contains(Path.DirectorySeparatorChar + "obj" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                    || file.Contains(Path.DirectorySeparatorChar + "bin" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) continue;
                if (allowed.Contains(file)) continue;
                int number = 0;
                bool isScheduling = string.Equals(file, scheduling, StringComparison.OrdinalIgnoreCase);
                foreach (string line in File.ReadLines(file))
                {
                    number++;
                    // number is 1-based; the wrapper's span is 0-based indexes.
                    if (isScheduling && number - 1 >= wrapperStart && number - 1 <= wrapperEnd) continue;
                    string code = line.TrimStart();
                    if (code.StartsWith("//", StringComparison.Ordinal) || code.StartsWith("*", StringComparison.Ordinal)) continue;
                    // A trailing comment is not code either.
                    int comment = code.IndexOf("//", StringComparison.Ordinal);
                    if (comment >= 0 && !code[..comment].Contains('"')) code = code[..comment];
                    if (Regex.IsMatch(code, "\"[^\"]*--build-only[^\"]*\""))
                        found.Add($"{Path.GetRelativePath(root, file)}:{number}: {line.Trim()}");
                }
            }
        }
        Assert.True(found.Count == 0, "a --build-only line written outside PreviewCommand.BuildOnlyArguments:\n" + string.Join("\n", found));

        // The scheduled wrapper's text is assembled in TaskScheduling.cs
        // (WriteWrapperScript): its build line is there, and the flag is not.
        string wrapperSource = File.ReadAllText(Path.Combine(root, "Plantoir.Core", "Assist", "TaskScheduling.cs"));
        Assert.Contains("--build-only --non-interactive", wrapperSource);
        Assert.DoesNotContain(PreviewCommand.ForDeployFlag, wrapperSource);
    }
}

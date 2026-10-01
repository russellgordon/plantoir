using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// #285's tripwire. The module-initializer redirect only covers code that asks
/// <c>AppDataRoot</c>; anything that computes a per-user folder for itself
/// slips past it and lands in the teacher's real state. So product code may
/// name a per-user folder only in <c>AppDataRoot.cs</c> or on a line this
/// allow-list counts — per file, per occurrence, each with a reason. A stale
/// allowance fails too, so the list cannot rot into a blanket pass.
/// </summary>
public class RealStateTripwireTests
{
    private static readonly Regex Pattern = new(
        @"Environment\.GetFolderPath\(|GetEnvironmentVariable\(""(LOCALAPPDATA|APPDATA|USERPROFILE)""\)|ExpandEnvironmentVariables|Environment\.SpecialFolder\.|\$env:LOCALAPPDATA|\$env:APPDATA|%LOCALAPPDATA%|%APPDATA%",
        RegexOptions.Compiled);

    /// <summary>File name → (occurrences allowed, why).</summary>
    private static readonly Dictionary<string, (int Count, string Why)> Allowed = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ClaudeCodeLauncher.cs"] = (2, "finds the user's own Claude Code install (home folder, LOCALAPPDATA Programs); read-only"),
        ["CodexLauncher.cs"] = (2, "finds the user's own Codex install (home folder, npm under APPDATA); read-only"),
        ["TaskScheduling.cs"] = (3, "the installed exe path; the wrapper's runtime line; and StateDirExpression, the one place $healthDir and $pendingDir name LOCALAPPDATA (#179: overridable by PLANTOIR_TEST_WRAPPER_STATE_DIR inside TEMP only)"),
        ["FolderActions.cs"] = (1, "reads Obsidian's vault registry under APPDATA; never written by tests"),
        ["MarketingShotCapturer.cs"] = (2, "the developer-only marketing capture's default Teaching folder"),
        ["BuildOutputLocation.cs"] = (1, "the home folder, to say whether a builds root is under it; a parameter in tests"),
        ["MachineWork.cs"] = (1, "the REAL settings path, on purpose: the busy check before a kill or an install must not read a redirected one (#155/#337)"),
        ["SectionPublishState.cs"] = (1, "expands a teacher-typed publish folder path; reads nothing by itself"),
    };

    private static IEnumerable<(string File, int Line, string Text)> Hits()
    {
        string root = RepoRoot;
        string[] projects = { "Plantoir", "Plantoir.Core", "Plantoir.Mcp" };
        foreach (string project in projects)
        {
            string dir = Path.Combine(root, "windows-app", project);
            var files = Directory.EnumerateFiles(dir, "*.cs", SearchOption.AllDirectories)
                .Where(f => !f.Contains(Path.DirectorySeparatorChar + "obj" + Path.DirectorySeparatorChar)
                         && !f.Contains(Path.DirectorySeparatorChar + "bin" + Path.DirectorySeparatorChar)
                         && !Path.GetFileName(f).Equals("AppDataRoot.cs", StringComparison.OrdinalIgnoreCase));
            foreach (string file in files)
            {
                string[] lines = File.ReadAllLines(file);
                for (int i = 0; i < lines.Length; i++)
                {
                    string trimmed = lines[i].TrimStart();
                    if (trimmed.StartsWith("//") || trimmed.StartsWith("*") || trimmed.StartsWith("/*")) continue;
                    if (Pattern.IsMatch(lines[i]))
                        yield return (file, i + 1, trimmed);
                }
            }
        }
    }

    [Fact]
    public void NoProductCodeReachesAPerUserFolderExceptThroughAppDataRoot()
    {
        var byFile = Hits().GroupBy(h => Path.GetFileName(h.File), StringComparer.OrdinalIgnoreCase).ToList();
        var problems = byFile
            .Where(g => !Allowed.TryGetValue(g.Key, out var allowance) || g.Count() > allowance.Count)
            .SelectMany(g => g.Select(h => $"{h.File}:{h.Line}: {h.Text}"))
            .ToList();
        Assert.True(problems.Count == 0,
            "Product code names a per-user folder outside AppDataRoot, which the test redirect cannot catch. " +
            "Go through AppDataRoot, or add an allowance with its reason:\n" + string.Join("\n", problems));
    }

    [Fact]
    public void EveryAllowanceIsStillUsedExactly()
    {
        var counts = Hits().GroupBy(h => Path.GetFileName(h.File), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.Count(), StringComparer.OrdinalIgnoreCase);
        var stale = Allowed
            .Where(a => !counts.TryGetValue(a.Key, out int n) || n < a.Value.Count)
            .Select(a => $"{a.Key}: allowed {a.Value.Count}, found {(counts.TryGetValue(a.Key, out int n) ? n : 0)}")
            .ToList();
        Assert.True(stale.Count == 0, "Stale allowance (lower it or remove it):\n" + string.Join("\n", stale));
    }

    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile"))) return dir.FullName;
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }
}

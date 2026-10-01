using System.Diagnostics;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>reopeningTheLastWorkingFolder</c> (GitHub
/// issue #320, the mac's #311): the launch rule, the reopen decision on real
/// throwaway folders, and the memory. Cases marked <c>appliesOn: ["mac"]</c>
/// (the Trash, bookmarks, privacy settings, outside-home) are skipped by that
/// declaration, not by a list here.
/// </summary>
public class ReopeningTheLastWorkingFolderTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-tests", "reopen-" + Guid.NewGuid().ToString("N"));

    public ReopeningTheLastWorkingFolderTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["reopeningTheLastWorkingFolder"]!;

    private static IEnumerable<JsonNode> ForWindows(string key) =>
        Rule[key]!.AsArray().Select(c => c!)
            .Where(c => c["appliesOn"] is null || c["appliesOn"]!.AsArray().Any(p => p!.ToString() == "windows"));

    [Fact]
    public void TheSentencesWindowsCanSayAreTheContracts()
    {
        foreach (var (key, sentence) in LastWorkingFolder.Wording)
            Assert.Equal(Rule["wording"]![key]!.ToString(), sentence);
    }

    [Fact]
    public void EveryLaunchCaseOpensTheWindowsTheContractSays()
    {
        var cases = ForWindows("launchCases").ToList();
        Assert.True(cases.Count >= 6, $"launchCases for Windows: {cases.Count} (6 when this was written)");

        var failures = new List<string>();
        foreach (var c in cases)
        {
            var leftOpen = c["windowsLeftOpen"]!.AsArray().Select(n => n!.ToString()).ToList();
            var expected = c["expectWindows"]!.AsArray().Select(n => n?.ToString()).ToList();
            var actual = LastWorkingFolder.FoldersToOpen(c["windowsComeBack"]!.GetValue<bool>(), leftOpen,
                c["lastWorkedIn"]?.ToString());
            if (!expected.SequenceEqual(actual))
                failures.Add($"{c["name"]}: expected [{string.Join(", ", expected.Select(e => e ?? "picker"))}], got [{string.Join(", ", actual.Select(a => a ?? "picker"))}]");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void EveryFolderCaseIsDecidedOnARealFolder()
    {
        var cases = ForWindows("folderCases").ToList();
        Assert.True(cases.Count >= 6, $"folderCases for Windows: {cases.Count} (6 when this was written)");

        var failures = new List<string>();
        foreach (var c in cases)
        {
            string folder = Path.Combine(_root, Guid.NewGuid().ToString("N"), "Course Notes");
            string make = c["make"]!.ToString();
            string? denied = null;
            switch (make)
            {
                case "there":
                    Directory.CreateDirectory(Path.Combine(folder, "courses"));
                    break;
                case "deleted":
                    Directory.CreateDirectory(folder);
                    Directory.Delete(folder);
                    break;
                case "driveNotConnected":
                    folder = Path.Combine(UnusedDriveRoot(), "Course Notes");
                    break;
                case "unreadable":
                    Directory.CreateDirectory(Path.Combine(folder, "courses"));
                    Deny(folder);
                    denied = folder;
                    break;
                case "emptied":
                    Directory.CreateDirectory(folder);
                    break;
                case "notAWorkingFolder":
                    Directory.CreateDirectory(folder);
                    File.WriteAllText(Path.Combine(folder, "shopping list.txt"), "milk");
                    break;
                default:
                    failures.Add($"{c["name"]}: this runner cannot make \"{make}\"");
                    continue;
            }
            try
            {
                string actual = LastWorkingFolder.WhyItCannotBeReopened(folder) ?? "reopen";
                if (actual != c["expect"]!.ToString())
                    failures.Add($"{c["name"]}: expected {c["expect"]}, got {actual}");
            }
            finally
            {
                if (denied is not null) Allow(denied);
            }
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void AFolderThatCouldNotBeReopenedStaysRememberedUntilAnotherIsChosen()
    {
        Assert.Equal(3, Rule["memoryCases"]!.AsArray().Count);
        string settingsPath = Path.Combine(_root, "settings.json");
        string gone = Path.Combine(_root, "not here any more");
        new AppSettings { WorkspacePath = gone }.Save(settingsPath);

        // stillRemembered: the load no longer prunes it.
        var loaded = AppSettings.Load(settingsPath);
        Assert.Equal(gone, loaded.WorkspacePath);
        Assert.Equal(LastWorkingFolder.Gone, LastWorkingFolder.WhyItCannotBeReopened(loaded.WorkspacePath!));
        Assert.Contains("“not here any more”", LastWorkingFolder.Sentence(LastWorkingFolder.Gone, gone));

        // replacedAndSentenceGone: choosing another replaces it, and the window
        // takes its sentence away — read from the source, the view model being
        // in the app project this suite cannot reference.
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
            "windows-app", "Plantoir", "ViewModels", "WorkspaceViewModel.cs"));
        int choose = source.IndexOf("public void ChooseWorkspace(string path)", StringComparison.Ordinal);
        string chooseBody = source.Substring(choose, source.IndexOf("NoteBecameKey();", choose, StringComparison.Ordinal) - choose);
        Assert.Contains("NotReopenedSentence = null;", chooseBody);
        Assert.Contains("Settings.WorkspacePath = path;", chooseBody);
    }

    /// <summary>
    /// notWritten: nothing a window does not show — the MCP server, a
    /// scheduled run, the Core library the tests drive — writes the memory.
    /// </summary>
    [Fact]
    public void AModelNoWindowShowsNeverWritesTheMemory()
    {
        string app = Path.Combine(ContractLoader.RepositoryRoot, "windows-app");
        var writers = new[] { "Plantoir.Mcp", "Plantoir.Core" }
            .SelectMany(project => Directory.GetFiles(Path.Combine(app, project), "*.cs", SearchOption.AllDirectories))
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
                        && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
            .Where(file => File.ReadAllText(file).Contains("WorkspacePath =", StringComparison.Ordinal))
            .Select(Path.GetFileName)
            .ToList();
        Assert.True(writers.Count == 0, "the remembered working folder is written by: " + string.Join(", ", writers));
    }

    /// <summary>"Last" means last in front: the window coming to the front writes it.</summary>
    [Fact]
    public void TheLastWorkingFolderIsTheOneLastInFront()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
            "windows-app", "Plantoir", "ViewModels", "WorkspaceViewModel.cs"));
        int key = source.IndexOf("public void NoteBecameKey()", StringComparison.Ordinal);
        string body = source.Substring(key, source.IndexOf("public void UnregisterWindow()", key, StringComparison.Ordinal) - key);
        Assert.Contains("Settings.WorkspacePath = _state.FolderPath;", body);
        Assert.Contains("ActivityTrail.Event.WorkingFolderReopened", source);
        Assert.Contains("ActivityTrail.Event.WorkingFolderNotReopened", source);
    }

    private static string UnusedDriveRoot()
    {
        var used = DriveInfo.GetDrives().Select(d => char.ToUpperInvariant(d.Name[0])).ToHashSet();
        char letter = "QRSTUVWXYZPONMLKJIHG".First(c => !used.Contains(c));
        return letter + ":\\";
    }

    private static void Deny(string folder) => Icacls($"\"{folder}\" /deny \"{Environment.UserName}\":(RD)");
    private static void Allow(string folder) => Icacls($"\"{folder}\" /remove:d \"{Environment.UserName}\"");

    private static void Icacls(string arguments)
    {
        var start = new ProcessStartInfo("icacls", arguments) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        using var process = Process.Start(start)!;
        process.WaitForExit(15000);
        Assert.True(process.ExitCode == 0, "icacls " + arguments + " failed: " + process.StandardError.ReadToEnd());
    }
}

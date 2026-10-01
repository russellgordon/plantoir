using System.Diagnostics;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #392: deploy.ps1's folder branch records the published pages itself, and
/// the record is released on every rollover. The launcher's function is run
/// as written (lifted between its BEGIN/END markers), through powershell.exe.
/// </summary>
public class PublishedPagesRecordTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-published-record").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static string Function()
    {
        string launcher = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "deploy.ps1"));
        int start = launcher.IndexOf("# BEGIN Record-PublishedPages", StringComparison.Ordinal);
        int end = launcher.IndexOf("# END Record-PublishedPages", StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start, "deploy.ps1 has no Record-PublishedPages between its markers.");
        return launcher[start..end];
    }

    private string Run(string buildId, string listedId)
    {
        string built = Path.Combine(_root, "built");
        Directory.CreateDirectory(built);
        File.WriteAllText(Path.Combine(built, ".build-id"), buildId + "\n");
        File.WriteAllText(Path.Combine(built, ".visible-pages.json"), $"{{\"buildId\": \"{listedId}\", \"pages\": [\"Concepts/Notes\"]}}");
        string script = Path.Combine(_root, "run.ps1");
        File.WriteAllText(script, Function() + $"\nRecord-PublishedPages '{built}' 'ICS3U' '1' 'folder'\n", new System.Text.UTF8Encoding(true));
        var process = Process.Start(new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\"")
        {
            WorkingDirectory = _root,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        })!;
        process.WaitForExit(60_000);
        return Path.Combine(_root, "courses", "ICS3U", ".publish_state", "section1.published-pages");
    }

    [Fact]
    public void ACopyToAFolderRecordsTheListOfItsOwnBuild()
    {
        string folder = Run("build-7", "build-7");
        var fragment = Assert.Single(Directory.GetFiles(folder));
        Assert.EndsWith("-folder.json", fragment);
        Assert.Contains("Concepts/Notes", File.ReadAllText(fragment));
    }

    [Fact]
    public void AListFromAnEarlierBuildIsNeverTakenForThisSites()
    {
        string folder = Run("build-8", "build-7");
        Assert.False(Directory.Exists(folder) && Directory.GetFiles(folder).Length > 0);
    }

    [Fact]
    public void EveryRolloverReleasesTheRecordAndTheAnswerAndCanPutThemBack()
    {
        string course = Path.Combine(_root, "courses", "ICS3U");
        string record = Path.Combine(course, ".publish_state", "section1.published-pages");
        Directory.CreateDirectory(record);
        File.WriteAllText(Path.Combine(record, "20260901T000000Z-folder.json"), "{}");
        LinksChecklist.WriteAnswered(course, 1, new[] { "Concepts/Notes" }, Array.Empty<string>(), DateTime.UtcNow);

        var released = LinksChecklist.ReleasePublishedPages(course, 1, new DateTime(2026, 9, 30, 8, 0, 0));

        Assert.Empty(Directory.GetFiles(record));
        Assert.True(Directory.Exists(record), "the folder itself is kept so the undo can write the fragments back");
        Assert.False(File.Exists(LinksChecklist.AnsweredPathFor(course, 1)));
        Assert.Single(Directory.GetFiles(released!));

        LinksChecklist.PutPublishedPagesBack(course, 1, released!);
        Assert.Single(Directory.GetFiles(record));
    }
}

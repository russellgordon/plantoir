using System.Diagnostics;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// A MEASUREMENT, part of no gate (#889; the plan review's L5): the shared
/// <c>browser-checks/crawl_deployed_folder.py</c> requests every link of every
/// page of a real built site through THIS app's server, started in-process,
/// with its <c>--url</c> mode; then the same folder through
/// <c>python -m http.server</c>, which must FAIL (the proof the crawl can).
/// Skipped unless <c>PLANTOIR_CRAWL_FOLDER</c> names a built section folder
/// (one holding <c>index.html</c>); <c>PLANTOIR_CRAWL_PYTHON</c> names the
/// Python, else <c>python</c> on PATH. The numbers it prints are recorded in
/// <c>documentation/12-windows-app.md</c>.
/// </summary>
public sealed class DeployedFolderCrawlMeasurement(ITestOutputHelper output)
{
    [CrawlFolderFact]
    public void EveryLinkOfABuiltSiteIsFoundThroughTheServer()
    {
        string folder = Environment.GetEnvironmentVariable("PLANTOIR_CRAWL_FOLDER")!;
        string python = Environment.GetEnvironmentVariable("PLANTOIR_CRAWL_PYTHON") is { Length: > 0 } named ? named : "python";
        string script = Path.Combine(ContractLoader.RepositoryRoot, "browser-checks", "crawl_deployed_folder.py");

        using var server = DeployedFolderServer.Start(folder, [DeployedFolderFixtures.FreePort()]).Server!;
        var clock = Stopwatch.StartNew();
        var (exit, text) = Run(python, "-I", script, "--url", server.Address.ToString(), folder);
        output.WriteLine($"through the server ({clock.Elapsed.TotalSeconds:F1} s, {server.Requests} requests): {text}");

        // The resolver alone, in this process, for every page's address: where
        // the time goes when the crawl is slow.
        var resolver = new DeployedFolderResolver(folder);
        var pages = Directory.EnumerateFiles(folder, "*.html", SearchOption.AllDirectories).Take(200).ToList();
        var resolving = Stopwatch.StartNew();
        foreach (string page in pages)
        {
            string relative = Path.GetRelativePath(folder, page).Replace('\\', '/');
            string address = "/" + string.Join('/', relative[..^".html".Length].Split('/').Select(Uri.EscapeDataString));
            using var answer = resolver.Answer(DeployedFolderRequest.Get(address, server.Port), server.Port);
        }
        output.WriteLine($"the resolver alone: {pages.Count} pages in {resolving.Elapsed.TotalMilliseconds:F0} ms");

        var (plainExit, plainText) = Run(python, "-I", script, "--plain-server", folder);
        output.WriteLine("through python -m http.server: " + plainText);
        Assert.Equal(1, plainExit);
        // A site may link to a page its build does not hold (a page not
        // published): that is missing on any host, so the measurement is the
        // two counts side by side, and the server's must be far the smaller.
        Assert.True(exit == 0 || NotFound(text) < NotFound(plainText) / 10, text);
    }

    private static int NotFound(string summary)
    {
        var match = System.Text.RegularExpressions.Regex.Match(summary, @"(\d+) not found");
        return match.Success ? int.Parse(match.Groups[1].Value) : int.MaxValue;
    }

    private static (int Exit, string Text) Run(string program, params string[] arguments)
    {
        var info = new ProcessStartInfo(program) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (string argument in arguments) info.ArgumentList.Add(argument);
        using var process = Process.Start(info)!;
        string text = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
        process.WaitForExit(600_000);
        return (process.ExitCode, text.Trim());
    }
}

/// <summary>Runs only when <c>PLANTOIR_CRAWL_FOLDER</c> names a folder holding <c>index.html</c>.</summary>
public sealed class CrawlFolderFactAttribute : FactAttribute
{
    public CrawlFolderFactAttribute()
    {
        string? folder = Environment.GetEnvironmentVariable("PLANTOIR_CRAWL_FOLDER");
        if (string.IsNullOrEmpty(folder) || !File.Exists(Path.Combine(folder, "index.html")))
            Skip = "A measurement, not a gate: set PLANTOIR_CRAWL_FOLDER to a built section folder to crawl it through the deployed folder's server.";
    }
}

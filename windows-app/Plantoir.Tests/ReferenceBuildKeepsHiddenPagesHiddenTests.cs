using System.Diagnostics;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// Runs only where the native website builder is present: this repository's
/// <c>windows-app\Vendor\runtime</c> (from <c>fetch-runtime.ps1</c>), or the
/// folder <c>PLANTOIR_RUNTIME</c> names. Otherwise the test is REPORTED as
/// skipped, with the reason — never silently green.
/// </summary>
public sealed class NativeRuntimeFactAttribute : FactAttribute
{
    public NativeRuntimeFactAttribute()
    {
        if (NativeRuntime.Folder is null)
            Skip = "No native runtime here: run windows-app\\Vendor\\fetch-runtime.ps1, or set PLANTOIR_RUNTIME.";
    }
}

/// <summary>Where the bundled builder is, if anywhere.</summary>
internal static class NativeRuntime
{
    public static string? Folder
    {
        get
        {
            var candidates = new List<string?>
            {
                Environment.GetEnvironmentVariable("PLANTOIR_RUNTIME"),
                Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Vendor", "runtime"),
            };
            return candidates.FirstOrDefault(c => c is not null && File.Exists(Path.Combine(c, "manifest.json")));
        }
    }
}

/// <summary>
/// The hidden-page trap (#241 §j): a read-only attribute TRAVELS into the
/// build tree, the build cannot rewrite the copy's <c>draft: true</c>, and a
/// page the teacher HID is published. This is the REAL launcher building a
/// LOCKED course — locked the way Plantoir locks one (<see cref="ReferenceLock"/>)
/// AND with the read-only attribute some other tool may have left — and
/// reading the built site back.
/// </summary>
[Collection(ReferenceDiskCollection.Name)]
public class ReferenceBuildKeepsHiddenPagesHiddenTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-locked-build").FullName;
    private readonly ITestOutputHelper _output;

    public ReferenceBuildKeepsHiddenPagesHiddenTests(ITestOutputHelper output) => _output = output;

    public void Dispose()
    {
        // The junction to the repository goes FIRST, on its own, so nothing
        // below can ever walk through it into the repository.
        string link = Path.Combine(_root, "work folder", ".toolchain");
        try { if (Directory.Exists(link)) Directory.Delete(link); } catch { }
        ReferenceLock.Clear(_root);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    [NativeRuntimeFact]
    public void ALockedReferenceCoursesHiddenPageIsNotOnItsBuiltSite()
    {
        string working = Path.Combine(_root, "work folder");
        string course = Path.Combine(working, "courses", "ICS3U-2025");
        Directory.CreateDirectory(Path.Combine(course, "Concepts"));
        Directory.CreateDirectory(Path.Combine(course, "section1"));
        File.WriteAllText(Path.Combine(course, "course_config.json"), """
            {"course_code": "ICS3U", "course_name": "Computer Science", "kept_for_reference": true,
             "reference_school_year": 2025, "section_numbers": [1], "num_sections": 1,
             "shared_folders": ["Concepts"], "shared_files": [], "per_section_folders": [], "per_section_files": [],
             "deploy_target": "local_folder", "deploy_folder_path": ""}
            """);
        File.WriteAllText(Path.Combine(course, "section1", "index.md"), "---\ntitle: Section 1\npublish: true\n---\n# Welcome\n");
        File.WriteAllText(Path.Combine(course, "Concepts", "Hidden Loops.md"), "---\ntitle: Hidden Loops\ndraft: true\n---\n# Hidden\n");
        File.WriteAllText(Path.Combine(course, "Concepts", "Visible Arrays.md"), "---\ntitle: Visible Arrays\ndraft: false\n---\n# Shown\n");
        foreach (string page in Directory.GetFiles(course, "*.md", SearchOption.AllDirectories))
            File.SetAttributes(page, FileAttributes.ReadOnly);
        var locked = ReferenceLock.Lock(course);
        Assert.Equal(3, locked.Locked);

        // The launcher, as the app runs it: from the working folder, with the
        // toolchain beside it. LOCALAPPDATA is moved for the child so the build
        // lands in this test's folder, not in the teacher's builds.
        foreach (string launcher in new[] { "preview.ps1", "preview.bat" })
            File.Copy(Path.Combine(ContractLoader.RepositoryRoot, launcher), Path.Combine(working, launcher));
        Assert.Equal(0, Run("cmd.exe", $"/c mklink /J \"{Path.Combine(working, ".toolchain")}\" \"{ContractLoader.RepositoryRoot}\"", working).Exit);
        string appData = Directory.CreateDirectory(Path.Combine(_root, "appdata")).FullName;

        var run = Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File preview.ps1 ICS3U-2025 1 --build-only", working,
            ("PLANTOIR_RUNTIME", NativeRuntime.Folder!), ("LOCALAPPDATA", appData));
        _output.WriteLine(run.Output.Length > 4000 ? run.Output[^4000..] : run.Output);
        Assert.True(run.Exit == 0, "the build did not finish: " + (run.Output.Length > 1500 ? run.Output[^1500..] : run.Output));

        var pages = Directory.GetFiles(appData, "*.html", SearchOption.AllDirectories)
            .Where(p => p.Contains($"{Path.DirectorySeparatorChar}public{Path.DirectorySeparatorChar}")).ToList();
        Assert.Contains(pages, p => Path.GetFileName(p).StartsWith("Visible", StringComparison.OrdinalIgnoreCase)
                                    || p.Contains("Visible-Arrays", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(pages, p => p.Contains("Hidden", StringComparison.OrdinalIgnoreCase));
        foreach (string page in pages)
            Assert.DoesNotContain("Hidden Loops", File.ReadAllText(page));

        // And the course itself was never written: still locked, still read-only.
        Assert.True(ReferenceLock.IsLocked(Path.Combine(course, "Concepts", "Hidden Loops.md")));
        Assert.Contains("draft: true", File.ReadAllText(Path.Combine(course, "Concepts", "Hidden Loops.md")));
    }

    private static (int Exit, string Output) Run(string file, string arguments, string folder, params (string Name, string Value)[] environment)
    {
        var start = new ProcessStartInfo(file, arguments)
        {
            WorkingDirectory = folder, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
        };
        foreach (var (name, value) in environment) start.Environment[name] = value;
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEndAsync();
        var errors = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(600_000)) { process.Kill(entireProcessTree: true); return (-1, "timed out"); }
        return (process.ExitCode, output.Result + errors.Result);
    }
}

using System.Diagnostics;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A scheduled deploy's wrapper script cannot fingerprint a section from
/// C#: at the moment it runs, `schtasks` has launched `powershell.exe`
/// directly, with no app process alive to call
/// <see cref="SectionPublishState.Fingerprint"/> from. So the wrapper calls
/// the bundled Python instead, running a THIRD copy of the same algorithm —
/// <c>scripts/section_fingerprint.py</c> — and this suite is what proves
/// the two agree, rather than trusting a hand-read of both.
///
/// See TaskScheduling.WriteWrapperScript and WINDOWS-HANDOFF.md, "A
/// scheduled deploy needs its own path to the same record".
/// </summary>
public class SectionFingerprintPythonParityTests
{
    private static string? RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "windows-app")) &&
                Directory.Exists(Path.Combine(dir.FullName, "scripts")))
                return dir.FullName;
            dir = dir.Parent;
        }
        return null;
    }

    /// <summary>
    /// Null (and the test skips) when the bundled Python or the fingerprint
    /// script are not present in this checkout — e.g. before
    /// `fetch-runtime.ps1` has run. Never treated as a failure: this repo's
    /// own test gate does not require the multi-hundred-MB runtime to be
    /// fetched.
    /// </summary>
    private static (string PythonExe, string Script)? PythonAndScript()
    {
        string? repoRoot = RepoRoot();
        if (repoRoot is null) return null;
        string pythonExe = Path.Combine(repoRoot, "windows-app", "Vendor", "runtime", "python", "python.exe");
        string script = Path.Combine(repoRoot, "scripts", "section_fingerprint.py");
        if (!File.Exists(pythonExe) || !File.Exists(script)) return null;
        return (pythonExe, script);
    }

    private static string RunPython(string pythonExe, string script, string courseDirectory, int sectionNumber, IReadOnlyList<string> excluded)
    {
        var info = new ProcessStartInfo
        {
            FileName = pythonExe,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        info.ArgumentList.Add(script);
        info.ArgumentList.Add(courseDirectory);
        info.ArgumentList.Add(sectionNumber.ToString());
        foreach (string path in excluded) info.ArgumentList.Add(path);

        using var process = Process.Start(info)!;
        string output = process.StandardOutput.ReadToEnd();
        string error = process.StandardError.ReadToEnd();
        process.WaitForExit(30_000);
        Assert.True(process.ExitCode == 0, $"section_fingerprint.py exited {process.ExitCode}: {error}");
        return output.Trim();
    }

    private static string NewCourseDirectory()
    {
        return Directory.CreateTempSubdirectory("section-fingerprint-parity-tests").FullName;
    }

    [Fact]
    public void OrdinaryFiles_MatchAcrossImplementations()
    {
        if (PythonAndScript() is not { } found) return; // bundled runtime not present in this checkout
        var (pythonExe, script) = found;

        string courseDir = NewCourseDirectory();
        Directory.CreateDirectory(Path.Combine(courseDir, "shared"));
        Directory.CreateDirectory(Path.Combine(courseDir, "section3"));
        Directory.CreateDirectory(Path.Combine(courseDir, "section4")); // a DIFFERENT section — excluded
        File.WriteAllText(Path.Combine(courseDir, "shared", "syllabus.md"), "# Syllabus");
        File.WriteAllText(Path.Combine(courseDir, "section3", "class1.md"), "# Class 1");
        File.WriteAllText(Path.Combine(courseDir, "section4", "class1.md"), "# A different section entirely");
        File.WriteAllText(Path.Combine(courseDir, "course_config.json"), "{}");
        File.WriteAllText(Path.Combine(courseDir, "course_config.backup.json"), "{}"); // ignored by name
        Directory.CreateDirectory(Path.Combine(courseDir, "node_modules")); // ignored folder
        File.WriteAllText(Path.Combine(courseDir, "node_modules", "x.js"), "junk");
        File.WriteAllText(Path.Combine(courseDir, ".hidden"), "dotfile");
        File.WriteAllText(Path.Combine(courseDir, "draft.tmp"), "scratch");

        string csharp = SectionPublishState.Fingerprint(courseDir, sectionNumber: 3);
        string python = RunPython(pythonExe, script, courseDir, sectionNumber: 3, excluded: Array.Empty<string>());

        Assert.Equal(csharp, python);
    }

    [Fact]
    public void SelfPublishingExclusion_MatchesAcrossImplementations()
    {
        if (PythonAndScript() is not { } found) return; // bundled runtime not present in this checkout
        var (pythonExe, script) = found;

        string courseDir = NewCourseDirectory();
        Directory.CreateDirectory(Path.Combine(courseDir, "section3"));
        Directory.CreateDirectory(Path.Combine(courseDir, "site")); // publishes into its own folder
        File.WriteAllText(Path.Combine(courseDir, "section3", "class1.md"), "# Class 1");
        File.WriteAllText(Path.Combine(courseDir, "site", "index.html"), "<html></html>");

        var excluded = SectionPublishState.SelfPublishingSubpaths(
            courseDir, new[] { new CourseConfiguration.DeployDestination("local_folder", Path.Combine(courseDir, "site")) });

        string csharp = SectionPublishState.Fingerprint(courseDir, sectionNumber: 3, excluded);
        string python = RunPython(pythonExe, script, courseDir, sectionNumber: 3, excluded);

        Assert.Equal(csharp, python);

        // And without the exclusion, the two implementations still agree —
        // proving the match above isn't a coincidence of both ignoring "site".
        string csharpUnexcluded = SectionPublishState.Fingerprint(courseDir, sectionNumber: 3);
        string pythonUnexcluded = RunPython(pythonExe, script, courseDir, sectionNumber: 3, Array.Empty<string>());
        Assert.Equal(csharpUnexcluded, pythonUnexcluded);
        Assert.NotEqual(csharp, csharpUnexcluded);
    }

    [Fact]
    public void EmptyCourse_MatchesAcrossImplementations()
    {
        if (PythonAndScript() is not { } found) return; // bundled runtime not present in this checkout
        var (pythonExe, script) = found;

        string courseDir = NewCourseDirectory();

        string csharp = SectionPublishState.Fingerprint(courseDir, sectionNumber: 1);
        string python = RunPython(pythonExe, script, courseDir, sectionNumber: 1, excluded: Array.Empty<string>());

        Assert.Equal(csharp, python);
    }
}

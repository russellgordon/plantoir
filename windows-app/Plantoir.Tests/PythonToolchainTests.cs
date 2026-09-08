using System.Diagnostics;

namespace Plantoir.Tests;

/// <summary>
/// The shared Python tests under <c>scripts/</c>, run here rather than only on
/// the mac.
///
/// <para><b>Why this class exists.</b> <c>scripts/</c> is shared code: the same
/// files run on both platforms, and the publishing path lives in them —
/// <c>deploy.py</c>, and <c>build_site.py</c> which a publish EXECUTES (see
/// <c>scripts/deploy.py</c>'s <c>rebuild_for_production</c> and
/// <c>ensure_base_url_and_rebuild</c>, and <c>deploy.ps1</c>'s
/// <c>--to-folder</c> branch, which shells <c>preview.bat --build-only</c>).
/// Fifteen test files cover them. <c>verify.sh</c> runs all fifteen on the mac.
/// Until this class, Windows ran NONE of them — <c>verify.sh</c> is bash and
/// expects <c>docker</c> on PATH, so it does not run here, and nothing replaced
/// it. A shared file could be broken from this machine and every gate on this
/// machine would stay green.</para>
///
/// <para><b>Why the whole folder rather than the publishing files only.</b> The
/// first draft of this work watched five publishing files and left the rest.
/// Two measurements killed that: <c>build_site.py</c> is executed by a publish
/// on three separate paths, so excluding it would have left the gate green
/// while the code a publish runs changed underneath it; and over the sixty days
/// to 2026-09-07 the publishing files changed on 16 distinct days out of 22
/// active ones — identical to <c>build_site.py</c>'s 16, so the "it churns too
/// much" argument for excluding it condemned the set that was kept. Running
/// every file costs seconds and needs no such judgement.</para>
///
/// <para><b>These need nothing.</b> No Docker, no network, no credentials — the
/// files say so in their own docstrings, which is why <c>verify.sh</c> runs
/// them before its Docker build. That is what makes them fit in a suite you can
/// run on a plane, and it is why this is NOT an attempt to replace
/// <c>verify-deploy.ps1</c>: that script publishes to real sites and fetches
/// them back, which nothing here does.</para>
/// </summary>
public class PythonToolchainTests
{
    /// <summary>
    /// Files deliberately not run here, each with the reason.
    ///
    /// <para>Empty today: all fifteen pass on Windows, measured 2026-09-07.
    /// It exists so that a file which genuinely cannot run here is EXCLUDED ON
    /// PURPOSE with a reason somebody can read, rather than quietly dropped
    /// from a hand-maintained list of what to run.</para>
    /// </summary>
    private static readonly Dictionary<string, string> NotRunHere = new();

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

    private static string ScriptsDirectory => Path.Combine(RepoRoot, "scripts");

    /// <summary>
    /// Every <c>scripts/test_*.py</c>, discovered rather than listed.
    ///
    /// <para>Discovery is the point. A hand-written list answers the files that
    /// existed on the day somebody read the folder; it cannot notice a file the
    /// MAC adds, so the gap would be invisible from both sides until it
    /// mattered. This is the same reasoning the contract-completeness tests use
    /// in <c>PublishAndLauncherContractTests</c>.</para>
    /// </summary>
    public static IEnumerable<object[]> PythonTestFiles()
    {
        foreach (string path in Directory.GetFiles(ScriptsDirectory, "test_*.py").OrderBy(p => p))
        {
            string name = Path.GetFileName(path);
            if (!NotRunHere.ContainsKey(name))
                yield return new object[] { name };
        }
    }

    [Theory]
    [MemberData(nameof(PythonTestFiles))]
    public void SharedPythonTestFilePasses(string fileName)
    {
        var result = RunPython(fileName);

        Assert.True(
            result.ExitCode == 0,
            $"scripts/{fileName} failed (exit code {result.ExitCode}).\n\n{result.Output}");
    }

    /// <summary>
    /// A file named as not-runnable must still be there — otherwise a rename
    /// leaves an exclusion pointing at nothing, and the file it was really
    /// about stops being run by anybody without a word being said.
    /// </summary>
    [Fact]
    public void EveryExcludedFileStillExists()
    {
        foreach (var excluded in NotRunHere)
        {
            Assert.True(
                File.Exists(Path.Combine(ScriptsDirectory, excluded.Key)),
                $"scripts/{excluded.Key} is excluded from this suite (\"{excluded.Value}\") but no longer exists. "
                + "Remove the exclusion, or point it at the file's new name.");
        }
    }

    /// <summary>
    /// The folder must not go quiet. If discovery returns nothing — a moved
    /// folder, a broken repository-root walk — every case above silently
    /// vanishes and the suite goes green having run none of them, which is the
    /// failure mode this whole piece of work is about.
    /// </summary>
    [Fact]
    public void TheSharedPythonTestsAreActuallyFound()
    {
        Assert.True(
            PythonTestFiles().Count() >= 10,
            $"Expected the shared Python tests in {ScriptsDirectory}; found "
            + $"{PythonTestFiles().Count()}. A suite that passes having run nothing is worse than no suite.");
    }

    // MARK: - Running one

    private static (int ExitCode, string Output) RunPython(string fileName)
    {
        var start = new ProcessStartInfo
        {
            FileName = PythonExecutable,
            // Run from `scripts/`, exactly as `verify.sh` does (`cd scripts && python3 …`).
            // These files import their siblings by BARE NAME — `import deploy`,
            // `import netlify_badge` — which resolves only when the interpreter's
            // working directory is the folder they sit in.
            WorkingDirectory = ScriptsDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        start.ArgumentList.Add(fileName);

        // WITHOUT THESE TWO, TWO FILES FAIL ON WINDOWS AND IT LOOKS LIKE A
        // PRODUCT BUG. `build_site.py` prints emoji ("📝 Added exclusion note
        // to …"), and on a console defaulting to cp1252 that raises
        // UnicodeEncodeError — the handler prints an emoji too, raises again,
        // and the exception escapes into `preflight_update_course_config`.
        // It reads exactly like a real fault in the build and is not one: the
        // launchers already set both variables before they run any Python
        // (deploy.ps1:117-118, preview.ps1:185-186, setup.ps1:158-159), so a
        // teacher never meets it. This runner sets what the launchers set, so
        // it tests the product as the product actually runs.
        start.Environment["PYTHONUTF8"] = "1";
        start.Environment["PYTHONIOENCODING"] = "utf-8";

        using var process = Process.Start(start)
            ?? throw new InvalidOperationException($"Could not start {PythonExecutable}.");

        // Read both streams before waiting. A child that fills a redirected
        // pipe blocks writing to it while the parent blocks waiting for exit,
        // and neither ever moves.
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();

        if (!process.WaitForExit(TimeoutMilliseconds))
        {
            try { process.Kill(entireProcessTree: true); } catch { /* already gone */ }
            return (124, $"scripts/{fileName} did not finish within {TimeoutMilliseconds / 1000} seconds.");
        }

        // unittest writes its report to stderr, so the failure detail is there
        // rather than in stdout. Both are shown, stdout first.
        return (process.ExitCode, (stdout.Result + stderr.Result).Trim());
    }

    private const int TimeoutMilliseconds = 180_000;

    /// <summary>
    /// The interpreter to run the shared tests with.
    ///
    /// <para><b>A missing interpreter FAILS rather than skipping.</b> Skipping
    /// would make this suite green on a machine where it ran nothing, which is
    /// the one outcome every part of this file is written to prevent — and it
    /// is the same rule <c>verify-deploy.ps1</c>'s own header states.</para>
    /// </summary>
    private static string PythonExecutable => cachedPython ??= FindPython();

    private static string? cachedPython;

    private static string FindPython()
    {
        foreach (string candidate in new[] { "python", "python3" })
        {
            try
            {
                var probe = new ProcessStartInfo
                {
                    FileName = candidate,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };
                probe.ArgumentList.Add("--version");

                using var process = Process.Start(probe);
                if (process is null) continue;
                process.WaitForExit(20_000);
                if (process.ExitCode == 0) return candidate;
            }
            catch
            {
                // Not on PATH under this name; try the next.
            }
        }

        throw new InvalidOperationException(
            "No Python interpreter found on PATH (tried \"python\" and \"python3\"). "
            + "The shared tests under scripts/ cannot run without one. Install Python 3, "
            + "or add the reason this machine cannot have it to NotRunHere in PythonToolchainTests.");
    }
}

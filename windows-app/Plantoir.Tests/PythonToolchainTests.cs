using System.Diagnostics;
using Xunit.Abstractions;

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
/// The runner DISCOVERS the <c>scripts/test_*.py</c> files rather than naming a
/// count (55 on 2026-09-30); <c>verify.sh</c> runs the same files on the mac.
/// Until this class, Windows ran NONE of them — <c>verify.sh</c> is bash and
/// expects <c>docker</c> on PATH, so it does not run here, and nothing replaced
/// it. A shared file could be broken from this machine and every gate on this
/// machine would stay green.</para>
///
/// <para>Since #886 it also discovers and runs Plantoir Help's
/// <c>help/tests/test_*.py</c>, from the repository root as <c>verify.sh</c>
/// does, with the runtime's <c>node</c> on PATH (see
/// <see cref="SharedHelpTestFilePasses"/>).</para>
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
/// <para><b>Why this class needs no <c>[Collection]</c>, though it shells out
/// while 60-odd other classes run beside it.</b> CLAUDE.md warns that anything
/// touching process-wide state must be serialised, and this looks like exactly
/// that kind of test. It is safe because of the PROCESS BOUNDARY: every Python
/// file writes only into its own <c>TemporaryDirectory</c>, and the one
/// environment variable any of them sets (<c>PLANTOIR_BUILD_ROOT</c>, in
/// <c>test_deploy_course_dir_resolution.py</c>) is set inside the CHILD, so it
/// cannot reach this process. xUnit also serialises the cases within a class,
/// so the files never run concurrently with each other. Written down because
/// it is not obvious, and the next person to review this will otherwise spend
/// an hour re-deriving it.</para>
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
    private readonly ITestOutputHelper _output;

    public PythonToolchainTests(ITestOutputHelper output) => _output = output;

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
        var result = RunPython(ScriptsDirectory, fileName, $"scripts/{fileName}");
        _output.WriteLine($"ran on {Interpreter.Describe()}");

        Assert.True(
            result.ExitCode == 0,
            $"scripts/{fileName} failed on {Interpreter.Describe()} (exit code {result.ExitCode}).\n\n{result.Output}");
    }

    // MARK: - Plantoir Help's tests (#886)

    private static string HelpTestsDirectory => Path.Combine(RepoRoot, "help", "tests");

    /// <summary>
    /// Every <c>help/tests/test_*.py</c>, discovered rather than listed (#886).
    ///
    /// <para><c>help/</c> is the one source of Plantoir Help on both platforms
    /// (#839): its outline, its word check and its token checks are shared
    /// truth, so a change made from this machine must be gated here as a
    /// change to <c>scripts/</c> is. Until #886 nothing on Windows ran them,
    /// and the first run found a real fault: <c>build_help.py</c> printed
    /// "▸" to a cp1252 pipe and ended in a traceback, so <c>test_tokens.py</c>
    /// failed 2 of 14 on the runtime's Python 3.14.10. The <c>hiutil</c> tests
    /// skip off a Mac, by design; the rest must pass.</para>
    /// </summary>
    public static IEnumerable<object[]> HelpTestFiles()
    {
        foreach (string path in Directory.GetFiles(HelpTestsDirectory, "test_*.py").OrderBy(p => p))
            yield return new object[] { Path.GetFileName(path) };
    }

    /// <summary>
    /// Runs one Help test file as <c>verify.sh</c> does on the Mac:
    /// <c>python3 help/tests/test_x.py</c> from the REPOSITORY ROOT (the files
    /// put their own folder on <c>sys.path</c>, so the runtime's <c>._pth</c>
    /// needs nothing more), with the runtime's <c>node</c> on PATH so the
    /// search tests run rather than skip.
    /// </summary>
    [Theory]
    [MemberData(nameof(HelpTestFiles))]
    public void SharedHelpTestFilePasses(string fileName)
    {
        string relative = Path.Combine("help", "tests", fileName);
        var result = RunPython(RepoRoot, relative, $"help/tests/{fileName}", withRuntimeNode: true);
        _output.WriteLine($"ran on {Interpreter.Describe()}");
        _output.WriteLine(result.Output);

        Assert.True(
            result.ExitCode == 0,
            $"help/tests/{fileName} failed on {Interpreter.Describe()} (exit code {result.ExitCode}).\n\n{result.Output}");
    }

    /// <summary>
    /// The Help tests must not go quiet either: a moved folder would make the
    /// theory above vanish and the suite green having run none of them.
    ///
    /// <para>The floor is "above zero" rather than today's count (seven on
    /// 2026-11-14), unlike <see cref="TheSharedPythonTestsAreActuallyFound"/>:
    /// <c>help/</c> is the Mac's, in active work in this release, and a floor
    /// at today's count would turn this gate red the day the Mac folds two
    /// test files into one, which is a change nobody here owes an answer
    /// to.</para>
    /// </summary>
    [Fact]
    public void TheHelpTestsAreActuallyFound()
    {
        int found = HelpTestFiles().Count();
        Assert.True(
            found > 0,
            $"Expected Plantoir Help's tests in {HelpTestsDirectory}; found none. "
            + "A suite that passes having run nothing is worse than no suite.");
    }

    /// <summary>
    /// With a runtime fetched, its <c>node</c> must be there for the Help
    /// tests: the search tests skip without one, and a skip here would read as
    /// a pass.
    /// </summary>
    [Fact]
    public void TheHelpTestsGetTheRuntimesNodeWhenOneIsFetched()
    {
        if (NativeRuntime.Folder is not { } runtime)
            return;
        string node = Path.Combine(runtime, "node", "node.exe");
        Assert.True(File.Exists(node),
            $"A runtime is fetched at {runtime}, but it has no node\\node.exe, so Help's search tests would skip. Re-run windows-app\\Vendor\\fetch-runtime.ps1.");
    }

    /// <summary>
    /// #764: the shared tests run on the interpreter a TEACHER runs, the
    /// runtime's own Python, whenever a runtime is fetched (this checkout's
    /// <c>windows-app\Vendor\runtime</c>, or <c>PLANTOIR_RUNTIME</c>). Until
    /// #764 they ran on PATH's <c>python</c> (3.14.7 on the build PC) while
    /// teachers ran 3.11.9, so the gate had never run them on the shipping
    /// interpreter. Says which one ran, and its version, either way.
    /// </summary>
    [Fact]
    public void TheSharedTestsRunOnTheRuntimesPythonWhenOneIsFetched()
    {
        _output.WriteLine($"the shared Python tests run on {Interpreter.Describe()}");
        if (NativeRuntime.Folder is { } runtime)
        {
            string expected = Path.GetFullPath(Path.Combine(runtime, "python", "python.exe"));
            Assert.True(Interpreter.IsRuntime && string.Equals(Path.GetFullPath(Interpreter.Path), expected, StringComparison.OrdinalIgnoreCase),
                $"A runtime is fetched at {runtime}, but the shared tests run on {Interpreter.Describe()}, not on {expected}.");
        }
        else
        {
            Assert.False(Interpreter.IsRuntime, $"No runtime is fetched, yet the shared tests claim to run on one: {Interpreter.Describe()}.");
        }
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
        // Fifteen files on 2026-09-07. The floor is that count rather than a
        // loose one, because a loose floor half-delivers what this test
        // promises: at ">= 10", five files could stop being discovered and
        // nothing would say so. Adding a file keeps this green; RETIRING one
        // means lowering the floor on purpose, in a diff somebody reads.
        const int KnownFileCount = 15;

        int found = PythonTestFiles().Count();
        Assert.True(
            found >= KnownFileCount,
            $"Expected at least {KnownFileCount} shared Python test files in {ScriptsDirectory}; found {found}. "
            + "If one was deliberately retired, lower the floor and say so. A suite that passes "
            + "having run nothing is worse than no suite.");
    }

    // MARK: - Running one

    private static (int ExitCode, string Output) RunPython(
        string workingDirectory, string script, string displayName, bool withRuntimeNode = false)
    {
        var start = new ProcessStartInfo
        {
            FileName = Interpreter.Path,
            // Run from where `verify.sh` runs each file: `scripts/` for the
            // toolchain's (`cd scripts && python3 …`), whose files import their
            // siblings by BARE NAME — `import deploy`, `import netlify_badge` —
            // which resolves only when the working directory is their folder;
            // the repository root for Help's (`python3 help/tests/test_x.py`).
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        // The runtime's Python reads python3NN._pth, which REPLACES sys.path:
        // the script's own folder is not on it, and PYTHONPATH is ignored.
        // These files import their siblings by bare name, so 50 of 93 failed
        // with ModuleNotFoundError when first run that way (#764, measured on
        // 3.11.9 and 3.14.10 alike). The shim puts the working directory -
        // scripts\, the file's own folder - first on sys.path, as the
        // product's entry scripts do for themselves. The three variables set
        // below ARE honoured there, although sys.flags.ignore_environment
        // reads 1 (measured on 3.14.10, 2026-11-11: PYTHONIOENCODING=latin-1
        // gave stdout iso8859-1, PYTHONDONTWRITEBYTECODE=1 gave
        // sys.dont_write_bytecode True, PYTHONUTF8 moved utf8_mode); -B and
        // -X utf8 say the same on the command line, so the run does not
        // depend on that.
        if (Interpreter.IsRuntime)
        {
            foreach (string argument in new[] { "-B", "-X", "utf8", "-c", RuntimeShim })
                start.ArgumentList.Add(argument);
        }
        start.ArgumentList.Add(script);

        // Help's search tests run its search.js with node, and skip without
        // one. The runtime carries node (Quartz needs it); put it first so the
        // tests run rather than skip. verify.sh uses whatever node is on the
        // Mac's PATH.
        if (withRuntimeNode && NativeRuntime.Folder is { } runtimeFolder)
        {
            string nodeFolder = Path.Combine(runtimeFolder, "node");
            start.Environment["PATH"] = nodeFolder + Path.PathSeparator + (start.Environment["PATH"] ?? "");
        }

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

        // Leave no `__pycache__` behind. `Plantoir.csproj` globs `scripts/**`
        // into the app's bundled toolchain, so a .pyc written by a test run
        // ships into the Debug bin and from there into a working folder's
        // `.toolchain/`. Harmless — the Windows launchers use the native
        // runtime and compute no image tag from it — but it is our litter, and
        // one line stops it.
        start.Environment["PYTHONDONTWRITEBYTECODE"] = "1";

        using var process = Process.Start(start)
            ?? throw new InvalidOperationException($"Could not start {Interpreter.Path}.");

        // Read both streams before waiting. A child that fills a redirected
        // pipe blocks writing to it while the parent blocks waiting for exit,
        // and neither ever moves.
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();

        if (!process.WaitForExit(TimeoutMilliseconds))
        {
            // entireProcessTree, not Kill(): `test_stop_preview.py` launches two
            // dozen child interpreters, and a plain Kill would orphan every one.
            try { process.Kill(entireProcessTree: true); } catch { /* already gone */ }

            // Drain whatever the run managed to say before the pipes close with
            // the process. WaitForExit(int) does not pump the redirected
            // streams, so without this the two readers are still pending when
            // `using` disposes the process, and they fault unobserved — losing
            // the output at the one moment somebody needs it, which is when a
            // test hung and nobody knows where.
            string partial = "";
            try
            {
                Task.WaitAll(new Task[] { stdout, stderr }, 5_000);
                partial = (stdout.IsCompletedSuccessfully ? stdout.Result : "")
                        + (stderr.IsCompletedSuccessfully ? stderr.Result : "");
            }
            catch { /* the pipes went with the process; report the timeout alone */ }

            return (124,
                $"{displayName} did not finish within {TimeoutMilliseconds / 1000} seconds.\n\n{partial}".Trim());
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
    internal static PythonInterpreter Interpreter => cachedInterpreter ??= FindInterpreter();

    private static PythonInterpreter? cachedInterpreter;

    private const string RuntimeShim =
        "import os, runpy, sys; sys.argv = sys.argv[1:]; sys.path.insert(0, os.getcwd()); runpy.run_path(sys.argv[0], run_name='__main__')";

    /// <summary>
    /// The runtime's Python when a runtime is fetched (#764), else PATH's.
    /// A runtime that has a manifest but no Python is broken, not absent, and
    /// throws rather than quietly testing PATH's interpreter instead.
    /// </summary>
    private static PythonInterpreter FindInterpreter()
    {
        if (NativeRuntime.Folder is { } runtime)
        {
            string python = Path.Combine(runtime, "python", "python.exe");
            if (!File.Exists(python))
                throw new InvalidOperationException(
                    $"The runtime at {runtime} has a manifest.json but no python\\python.exe. Re-run windows-app\\Vendor\\fetch-runtime.ps1.");
            return new PythonInterpreter(python, IsRuntime: true, VersionOf(python, "-I"));
        }
        string onPath = FindPython();
        return new PythonInterpreter(onPath, IsRuntime: false, VersionOf(onPath));
    }

    private static string VersionOf(string python, params string[] flags)
    {
        var probe = new ProcessStartInfo(python)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (string flag in flags) probe.ArgumentList.Add(flag);
        probe.ArgumentList.Add("-c");
        probe.ArgumentList.Add("import ssl, sys; print(sys.version.split()[0] + ', ' + ssl.OPENSSL_VERSION)");
        using var process = Process.Start(probe)!;
        string said = process.StandardOutput.ReadToEnd().Trim();
        process.WaitForExit(20_000);
        return said;
    }

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

/// <summary>Which Python the shared tests run on, and what it said it is (#764).</summary>
internal sealed record PythonInterpreter(string Path, bool IsRuntime, string Version)
{
    public string Describe() => $"{(IsRuntime ? "the runtime's Python" : "PATH's python")} {Version} ({Path})";
}

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
        var result = RunPython(fileName);
        _output.WriteLine($"ran on {Interpreter.Describe()}");

        Assert.True(
            result.ExitCode == 0,
            $"scripts/{fileName} failed on {Interpreter.Describe()} (exit code {result.ExitCode}).\n\n{result.Output}");
    }

    // MARK: - Plantoir Help's tests (#886)

    private static string HelpTestsDirectory => Path.Combine(RepoRoot, "help", "tests");

    /// <summary>How a failure names Help's test folder.</summary>
    private const string HelpTestsLabel = "help/tests";

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
        var result = RunHelpTest(fileName);
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
    /// #916: raising the limit must not stop a HUNG file being caught. A file
    /// that sleeps 300 s, far past a 15-second limit, written into a temporary
    /// folder (never into <c>scripts/</c>, where both platforms would run it),
    /// is stopped, fails with 124, and its sentence names the file, the limit
    /// and how long it ran. A known slow file's sentence names a busy PC as the
    /// likely cause; any other file's does not. Fifteen seconds rather than two
    /// so a cold interpreter on a loaded PC still prints before it is stopped
    /// (the #916 review's M1); anything well under 300 s proves the stop.
    /// </summary>
    [Fact]
    public void AHungFileIsStoppedAtTheLimitAndNamed()
    {
        // #882's helper, so a crashed test host's leftover is swept safely by a later run.
        string folder = RunOwnedTempFolders.Create("plantoir-hung-python-");
        try
        {
            File.WriteAllText(Path.Combine(folder, "test_never_returns.py"), "import time\nprint('started', flush=True)\ntime.sleep(300)\n");
            var clock = Stopwatch.StartNew();
            var result = RunPython("test_never_returns.py", TimeSpan.FromSeconds(15), folder);
            _output.WriteLine(result.Output);

            Assert.Equal(124, result.ExitCode);
            Assert.True(clock.Elapsed < TimeSpan.FromSeconds(90), $"The hung file was not stopped promptly: {clock.Elapsed.TotalSeconds:F0} s.");
            Assert.Contains("scripts/test_never_returns.py", result.Output);
            Assert.Contains("limit for one shared Python file is 15 seconds", result.Output);
            Assert.Matches(@"stopped after running \d+ seconds", result.Output);
            Assert.Contains("suspect a HUNG test", result.Output);
            Assert.Contains("started", result.Output);
        }
        finally
        {
            try { Directory.Delete(folder, true); } catch { }
        }

        foreach (string slow in KnownSlowFiles.Keys)
            Assert.Contains("a busy PC", TimedOutMessage(slow, Limit, 600));
        Assert.True(KnownSlowFiles.Count > 0);
        foreach (string slow in KnownSlowFiles.Keys)
            Assert.True(File.Exists(Path.Combine(ScriptsDirectory, slow)), $"KnownSlowFiles names scripts/{slow}, which no longer exists.");

        // Help's files (#886) are named by their own folder, and its slow file by its own table.
        foreach (string slow in KnownSlowHelpFiles.Keys)
        {
            string helpMessage = TimedOutMessage(slow, Limit, 600, HelpTestsLabel);
            Assert.Contains($"help/tests/{slow} was stopped", helpMessage);
            Assert.Contains("a busy PC", helpMessage);
            Assert.True(File.Exists(Path.Combine(HelpTestsDirectory, slow)), $"KnownSlowHelpFiles names help/tests/{slow}, which no longer exists.");
        }
        Assert.Contains("suspect a HUNG test", TimedOutMessage("test_checks.py", Limit, 600, HelpTestsLabel));
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

    /// <param name="limit">How long the file may run; <see cref="Limit"/> unless a test of the limit itself says otherwise.</param>
    /// <param name="folder">The folder the file sits in; <see cref="ScriptsDirectory"/> unless a test of the limit itself says otherwise.</param>
    internal static (int ExitCode, string Output) RunPython(string fileName, TimeSpan? limit = null, string? folder = null)
        => RunPythonFile(folder ?? ScriptsDirectory, fileName, fileName, "scripts", limit ?? Limit, withRuntimeNode: false);

    /// <summary>
    /// Runs one of Help's files (#886) from the REPOSITORY ROOT, as
    /// <c>verify.sh</c> runs <c>python3 help/tests/test_x.py</c>, with the
    /// runtime's <c>node</c> on PATH, under the same <see cref="Limit"/> as
    /// <c>scripts/</c>.
    /// </summary>
    private static (int ExitCode, string Output) RunHelpTest(string fileName)
        => RunPythonFile(RepoRoot, Path.Combine("help", "tests", fileName), fileName, HelpTestsLabel, Limit, withRuntimeNode: true);

    /// <param name="workingDirectory">Where the interpreter runs: <c>scripts/</c> for the toolchain's files, the repository root for Help's.</param>
    /// <param name="script">The file to run, relative to <paramref name="workingDirectory"/>.</param>
    /// <param name="fileName">The file's own name, which <see cref="TimedOutMessage"/> looks up.</param>
    /// <param name="folderLabel">The folder as a person names it in a failure: <c>scripts</c> or <c>help/tests</c>.</param>
    private static (int ExitCode, string Output) RunPythonFile(
        string workingDirectory, string script, string fileName, string folderLabel, TimeSpan allowed, bool withRuntimeNode)
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

        var clock = Stopwatch.StartNew();
        using var process = Process.Start(start)
            ?? throw new InvalidOperationException($"Could not start {Interpreter.Path}.");

        // Read both streams before waiting. A child that fills a redirected
        // pipe blocks writing to it while the parent blocks waiting for exit,
        // and neither ever moves.
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();

        if (!process.WaitForExit(allowed))
        {
            double ranFor = clock.Elapsed.TotalSeconds;
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

            return (124, (TimedOutMessage(fileName, allowed, ranFor, folderLabel) + "\n\n" + partial).Trim());
        }

        // unittest writes its report to stderr, so the failure detail is there
        // rather than in stdout. Both are shown, stdout first.
        return (process.ExitCode, (stdout.Result + stderr.Result).Trim());
    }

    /// <summary>
    /// How long one shared file may run before it is stopped as HUNG (#916).
    ///
    /// <para><b>A limit for a hang, not a speed check.</b> Nothing here
    /// measures how fast a file is; the limit exists so that a file which never
    /// returns stops the run with its name rather than holding the suite
    /// forever. So it must sit far above anything LOAD alone can produce.
    /// It was 180 s until #916, and on 2026-11-13/14, with several agents'
    /// suites on this PC at once, three files were stopped at it while doing
    /// nothing wrong: <c>test_starting_content_prompts.py</c>,
    /// <c>test_no_stored_credentials.py</c> (71 s beside one other test host,
    /// 193 s beside more) and <c>test_shared_writes_two_at_once.py</c>.
    /// Alone, the slowest files take the times in <see cref="KnownSlowFiles"/>
    /// (the slowest 78.5 s; all 119 files 10 min 41 s, one after another).
    /// The worst slowdown seen under load was 5.7 times
    /// (<c>test_no_stored_credentials.py</c>, 33.8 s alone, 193 s that night),
    /// which takes the slowest file to about 450 s; 600 s covers that with
    /// room, and still stops a hung file within ten minutes.</para>
    ///
    /// <para><b>Rejected: a per-file allowance table.</b> It must be kept in
    /// step by hand with a folder the MAC adds files to, and the file that is
    /// slow under load is not always one somebody listed: the third file
    /// stopped that night was in no measurement before it. One generous limit
    /// needs no upkeep. <b>Rejected: splitting the slow files' scans</b> in
    /// shared Python, which changes files the mac's <c>verify.sh</c> runs, for
    /// no gain to a teacher.</para>
    /// </summary>
    internal static readonly TimeSpan Limit = TimeSpan.FromSeconds(600);

    /// <summary>
    /// The files that take 30 s or more on their own, with their time ALONE
    /// (under the suite lock, nothing else running a suite), so a timeout
    /// names the likely cause. Not a list of allowances: every file gets
    /// <see cref="Limit"/>, and a file missing from here is still covered.
    /// Measured 2026-11-14 on the development PC, a Lenovo 20QES70500
    /// (i5-8365U, 16 GB, Windows 11 Pro 26200), on the runtime's Python
    /// 3.14.10 — documentation/12-windows-app.md → "A red that is a busy PC".
    /// </summary>
    internal static readonly IReadOnlyDictionary<string, int> KnownSlowFiles = new Dictionary<string, int>
    {
        ["test_graded_folders_new_course.py"] = 79,
        ["test_starting_content_prompts.py"] = 69,
        ["test_shared_writes_two_at_once.py"] = 60,
        ["test_deploy_sh_destination.py"] = 46,
        ["test_share_plan.py"] = 45,
        ["test_marking_comments.py"] = 45,
        ["test_no_stored_credentials.py"] = 34,
    };

    /// <summary>
    /// Help's files that take 30 s or more on their own (#886), kept apart
    /// from <see cref="KnownSlowFiles"/> because they sit in
    /// <c>help/tests/</c>, not <c>scripts/</c>. <c>test_build_help.py</c>
    /// builds the real <c>help/</c> in nine of its tests: 92 to 94 s alone,
    /// measured 2026-11-14 on the same PC and Python as
    /// <see cref="KnownSlowFiles"/>.
    /// </summary>
    internal static readonly IReadOnlyDictionary<string, int> KnownSlowHelpFiles = new Dictionary<string, int>
    {
        ["test_build_help.py"] = 93,
    };

    /// <summary>The sentence a stopped file fails with: its folder and name, the limit, how long it ran, and the likely cause.</summary>
    /// <param name="folderLabel"><c>scripts</c> for the toolchain's files, <c>help/tests</c> for Help's.</param>
    internal static string TimedOutMessage(string fileName, TimeSpan limit, double ranForSeconds, string folderLabel = "scripts")
    {
        IReadOnlyDictionary<string, int> slowFiles = folderLabel == HelpTestsLabel ? KnownSlowHelpFiles : KnownSlowFiles;
        string message = $"{folderLabel}/{fileName} was stopped after running {ranForSeconds:F0} seconds; "
                       + $"the limit for one shared Python file is {limit.TotalSeconds:F0} seconds.";
        if (slowFiles.TryGetValue(fileName, out int alone))
            message += $" It is one of the known slow files ({alone} s alone on the development PC), so a busy PC — "
                     + "other test runs or builds at the same time — is the likely cause; run it again on a quiet machine before suspecting the file.";
        else
            message += " It is not one of the known slow files, so suspect a HUNG test before a busy PC.";
        return message;
    }

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

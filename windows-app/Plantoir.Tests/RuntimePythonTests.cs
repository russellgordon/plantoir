using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// #764: the Python in Windows' native runtime. It was 3.11.9, whose own
/// OpenSSL is 3.0.13 (30 Jan 2024), the TLS under every Netlify publish and
/// every Cloudflare API call <c>deploy.py</c> makes; it is 3.14.10 (OpenSSL
/// 3.5.9) since. <c>contracts/toolchain.json</c> → <c>windowsPython</c> holds
/// the version, the OpenSSL floor and the reasons; this class holds the
/// recipe, the build and a fetched runtime to it, and holds the shared
/// <c>scripts/</c> to the IMAGE's Python 3.11, which no other Windows test
/// runs them on any more. <c>documentation/12-windows-app.md</c> → "Python
/// 3.14.10 in the runtime".
/// </summary>
public sealed class RuntimePythonTests : IDisposable
{
    private readonly ITestOutputHelper _output;
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-runtime-python").FullName;

    public RuntimePythonTests(ITestOutputHelper output) => _output = output;

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static string RepoRoot => ContractLoader.RepositoryRoot;

    private static string Recipe =>
        File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Vendor", "fetch-runtime.ps1"));

    private static System.Text.Json.Nodes.JsonNode WindowsPython =>
        ContractLoader.LoadJson("toolchain.json")["windowsPython"]
        ?? throw new InvalidOperationException("contracts/toolchain.json has no windowsPython.");

    private static string Pin(string name) =>
        ContractLoader.LoadJson("toolchain.json")["pins"]!.AsArray()
            .First(p => p?["pin"]?.ToString() == name)!["value"]!.ToString();

    // MARK: - The recipe and the build

    /// <summary>
    /// A statement the recipe RUNS, not one it mentions: the line must start
    /// with the text (after indentation), so the same text behind <c>#</c>, or
    /// inside a sentence, does not count (the implementation review showed
    /// every check here passing with its line commented out).
    /// </summary>
    private static void AssertStatement(string text, string statement, string what) =>
        Assert.True(Regex.IsMatch(text, @"(?m)^[ \t]*" + Regex.Escape(statement)),
            $"{what} does not run `{statement}` (a commented-out or quoted copy does not count).");

    [Fact]
    public void TheWindowsRuntimeRecipeCarriesTheContractsPython()
    {
        string recipe = Recipe;
        string version = WindowsPython["version"]!.ToString();
        string contains = WindowsPython["windowsRuntimeContains"]!.ToString();
        Assert.Contains(version, contains);
        AssertStatement(recipe, contains, "fetch-runtime.ps1 (contracts/toolchain.json -> windowsPython)");

        string floor = WindowsPython["opensslAtLeast"]!.ToString();
        AssertStatement(recipe, $"$PythonOpensslAtLeast = \"{floor}\"", "fetch-runtime.ps1 (windowsPython -> opensslAtLeast)");
        AssertStatement(recipe, "$pyOpenssl = Assert-PythonOpenssl \"$pyDir\\python.exe\" $PythonOpensslAtLeast", "fetch-runtime.ps1");

        // The zip by hash AND size, and the three wheels by version AND hash,
        // binary only. A wheel line's version is the image's pin.
        Assert.Matches(new Regex(@"(?m)^\$PythonZipSha256 = ""[0-9a-f]{64}""\r?$"), recipe);
        AssertStatement(recipe, "Assert-Sha256 $pyZip $PythonZipSha256 $PythonZipLength", "fetch-runtime.ps1");
        foreach (var (package, pin) in new[] { ("python-frontmatter", "pythonFrontmatter"), ("PyYAML", "pyyaml"), ("Pillow", "pillow") })
        {
            Assert.True(Regex.IsMatch(recipe,
                    @"(?m)^[ \t]*""" + Regex.Escape($"{package}=={Pin(pin)} --hash=sha256:") + @"[0-9a-f]{64}"",?\r?$"),
                $"fetch-runtime.ps1's $PythonWheels has no line {package}=={Pin(pin)} --hash=sha256:<64 hex>.");
        }
        AssertStatement(recipe, "--only-binary :all: --require-hashes --no-deps -r $pyReq", "fetch-runtime.ps1's pip install");
    }

    /// <summary>The project text with its XML comments taken out: a guard inside one is no guard.</summary>
    private static string ProjectOutsideComments() =>
        Regex.Replace(File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Plantoir", "Plantoir.csproj")),
            "<!--.*?-->", "", RegexOptions.Singleline);

    [Fact]
    public void TheBuildRefusesARuntimeOnAnotherPython()
    {
        string project = ProjectOutsideComments();
        string version = WindowsPython["version"]!.ToString();
        Assert.Contains($"<_PlantoirRuntimePython>{version}</_PlantoirRuntimePython>", project);
        Assert.Contains("<Error Condition=\"!$([System.Text.RegularExpressions.Regex]::IsMatch($(_PlantoirRuntimeManifest), $(_PlantoirRuntimePythonPattern)))\"", project);
    }

    [Fact]
    public void AnUpgradeEmptiesTheRuntimesPythonFolder()
    {
        string installer = File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "installer.iss"));
        // Section headers at the start of a line: the comments above
        // [InstallDelete] name "[Files]" too.
        var section = Regex.Match(installer, @"(?m)^\[InstallDelete\]\r?$").Index;
        var next = Regex.Match(installer, @"(?m)^\[Files\]\r?$").Index;
        Assert.True(section > 0 && next > section, "installer.iss has no [InstallDelete] section before its [Files] section.");
        // The whole line, anchored: the same entry behind ';' is a comment.
        Assert.Matches(new Regex(@"(?m)^Type: filesandordirs; Name: ""\{app\}\\runtime\\python""\r?$"), installer[section..next]);
    }

    // MARK: - A fetched runtime

    /// <summary>
    /// Fails when a runtime is fetched and is not the contract's: the build's
    /// guard does not run for <c>dotnet test</c> (this project references
    /// Core and the MCP server, not the app), so this is the one place a test
    /// run sees the runtime it is testing on. Skips, saying so, only when no
    /// runtime is fetched.
    /// </summary>
    [NativeRuntimeFact]
    public void TheNativeRuntimeCarriesTheContractsPythonAndOpenssl()
    {
        string runtime = NativeRuntime.Folder!;
        string pythonDir = Path.Combine(runtime, "python");
        string python = Path.Combine(pythonDir, "python.exe");
        Assert.True(File.Exists(python), $"{runtime} has no python\\python.exe.");
        string version = WindowsPython["version"]!.ToString();
        string tag = "python" + string.Concat(version.Split('.').Take(2));

        var said = Run(python, "-I", "-c", "import ssl, sys; print(sys.version.split()[0]); print(ssl.OPENSSL_VERSION)");
        _output.WriteLine($"{python}: {said.Output.Replace("\r\n", " | ").Trim()}");
        Assert.True(said.ExitCode == 0, said.Output);
        string[] lines = said.Output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        Assert.True(lines[0] == version, $"{runtime}'s Python is {lines[0]}, and contracts/toolchain.json -> windowsPython says {version}. Delete the runtime and re-run windows-app\\Vendor\\fetch-runtime.ps1.");
        var openssl = Regex.Match(lines[1], @"^OpenSSL (\d+\.\d+\.\d+)");
        Assert.True(openssl.Success, $"Could not read an OpenSSL version from \"{lines[1]}\".");
        string floor = WindowsPython["opensslAtLeast"]!.ToString();
        Assert.True(Version.Parse(openssl.Groups[1].Value) >= Version.Parse(floor),
            $"{runtime}'s Python carries {lines[1]}, below the contract's floor {floor}.");

        // One Python in the folder: no other python3NN.* beside this one's.
        var others = Directory.GetFiles(pythonDir, "python3*.*")
            .Select(Path.GetFileName)
            .Where(name => name is not null && !name.StartsWith(tag + ".", StringComparison.OrdinalIgnoreCase)
                           && !name.StartsWith(tag + "._", StringComparison.OrdinalIgnoreCase)
                           && !string.Equals(name, "python3.dll", StringComparison.OrdinalIgnoreCase))
            .ToList();
        Assert.True(others.Count == 0, $"{pythonDir} holds another Python's files beside {tag}: {string.Join(", ", others)}.");
    }

    // MARK: - The OpenSSL floor, as fetch-runtime.ps1 runs it

    private static string FloorFunction()
    {
        string script = Recipe;
        int start = script.IndexOf("# BEGIN Assert-PythonOpenssl", StringComparison.Ordinal);
        int end = script.IndexOf("# END Assert-PythonOpenssl", StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start, "fetch-runtime.ps1 has no Assert-PythonOpenssl between its markers.");
        return script[start..end];
    }

    private (int ExitCode, string Said) RunFloor(string python, string atLeast)
    {
        string script = Path.Combine(_root, $"floor-{Guid.NewGuid():N}.ps1");
        File.WriteAllText(script,
            "$ErrorActionPreference = 'Stop'\n" + FloorFunction() + $"\nWrite-Output (Assert-PythonOpenssl '{python}' '{atLeast}')\n",
            new UTF8Encoding(true));
        var run = Run("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script);
        return (run.ExitCode, run.Output);
    }

    /// <summary>A stand-in "python" that says what a given OpenSSL would.</summary>
    private string StandIn(string number, string line)
    {
        string cmd = Path.Combine(_root, $"python-{number}.cmd");
        File.WriteAllText(cmd, $"@echo {number}\r\n@echo {line}\r\n", Encoding.ASCII);
        return cmd;
    }

    [Theory]
    [InlineData("3.0.13", "OpenSSL 3.0.13 30 Jan 2024", false)]
    [InlineData("3.0.22", "OpenSSL 3.0.22 25 Aug 2026", false)]
    [InlineData("3.5.8", "OpenSSL 3.5.8 1 Jul 2026", false)]
    [InlineData("3.5.9", "OpenSSL 3.5.9 29 Sep 2026", true)]
    [InlineData("3.5.10", "OpenSSL 3.5.10 1 Jan 2027", true)]
    [InlineData("3.10.0", "OpenSSL 3.10.0 1 Jan 2030", true)]
    public void TheFetchRefusesAPythonBelowTheOpensslFloor(string number, string line, bool accepted)
    {
        var run = RunFloor(StandIn(number, line), WindowsPython["opensslAtLeast"]!.ToString());
        _output.WriteLine(run.Said);
        if (accepted)
        {
            Assert.True(run.ExitCode == 0, $"{line} was refused: {run.Said}");
            Assert.Contains(line, run.Said);
        }
        else
        {
            Assert.True(run.ExitCode != 0, $"{line} was accepted under a floor of {WindowsPython["opensslAtLeast"]}: {run.Said}");
            Assert.Contains("the runtime needs OpenSSL", run.Said);
        }
    }

    /// <summary>
    /// The floor's own Python code, on the real runtime: the stand-ins above
    /// prove the comparison, this proves the line it reads. (Its first
    /// version read <c>ssl.OPENSSL_VERSION_INFO[:3]</c>, which is 3.5.0 for
    /// OpenSSL 3.5.9, and refused the very Python it was written for.)
    /// </summary>
    [NativeRuntimeFact]
    public void TheFloorAcceptsTheFetchedRuntimesPython()
    {
        string python = Path.Combine(NativeRuntime.Folder!, "python", "python.exe");
        var run = RunFloor(python, WindowsPython["opensslAtLeast"]!.ToString());
        _output.WriteLine(run.Said);
        Assert.True(run.ExitCode == 0, run.Said);
        Assert.StartsWith("OpenSSL ", run.Said.Trim());
    }

    // MARK: - The shared scripts still parse as the image's Python 3.11

    private const string ParseProgram = """
        import ast, pathlib, sys
        bad = []
        count = 0
        for root in sys.argv[1:]:
            for path in sorted(pathlib.Path(root).rglob("*.py")):
                count += 1
                try:
                    ast.parse(path.read_text(encoding="utf-8"), filename=str(path), feature_version=(3, 11))
                except SyntaxError as error:
                    bad.append(f"{path}:{error.lineno}: {error.msg}")
        print(count)
        for line in bad:
            print(line)
        sys.exit(1 if bad else 0)
        """;

    private (int ExitCode, string Output) Parse(params string[] roots)
    {
        var interpreter = PythonToolchainTests.Interpreter;
        var arguments = new List<string>();
        if (interpreter.IsRuntime) arguments.AddRange(new[] { "-I", "-B", "-X", "utf8" });
        arguments.AddRange(new[] { "-c", ParseProgram });
        arguments.AddRange(roots);
        return Run(interpreter.Path, arguments.ToArray());
    }

    /// <summary>
    /// The image runs <c>scripts/</c> on Python 3.11.15 (python:3.11-slim);
    /// since #764 Windows runs them on 3.14, and PythonToolchainTests runs
    /// the shared tests on 3.14 too - and verify.sh runs them on the Mac's
    /// own <c>python3</c>, not the image's. So nothing ran them on 3.11
    /// before code reached a container, and a 3.12+ construct would pass
    /// every Windows gate and fail a Mac teacher's build. This parses every
    /// <c>scripts/</c> and <c>support/</c> file as 3.11 grammar. ITS LIMIT:
    /// <c>feature_version</c> is best-effort - it rejects <c>type X = ...</c>,
    /// <c>def f[T]</c>, <c>class C[T]</c> and 3.14's unparenthesised
    /// <c>except A, B:</c> (each measured), but NOT PEP 701's quote reuse
    /// inside an f-string, and it knows nothing of stdlib functions added
    /// after 3.11.
    /// </summary>
    [Fact]
    public void TheSharedScriptsParseAsPython311()
    {
        var run = Parse(Path.Combine(RepoRoot, "scripts"), Path.Combine(RepoRoot, "support"));
        _output.WriteLine($"on {PythonToolchainTests.Interpreter.Describe()}: {run.Output}");
        Assert.True(run.ExitCode == 0,
            $"Files under scripts/ or support/ use syntax the image's Python 3.11 cannot read:\n{run.Output}");
        int files = int.Parse(run.Output.Split('\n')[0].Trim());
        Assert.True(files >= 100, $"Only {files} .py files were parsed: the walk found less than the shared scripts.");
    }

    /// <summary>The check above is a real check: each 3.12+ form it is known to catch, caught.</summary>
    [Theory]
    [InlineData("type Alias = int\n")]
    [InlineData("def first[T](items: list[T]) -> T:\n    return items[0]\n")]
    [InlineData("class Box[T]:\n    pass\n")]
    [InlineData("try:\n    pass\nexcept ValueError, TypeError:\n    pass\n")]
    public void TheParseCheckRejectsSyntaxNewerThan311(string source)
    {
        string folder = Path.Combine(_root, "newer");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "newer.py"), source, new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(folder, "fine.py"), "x = 1\n", new UTF8Encoding(false));
        var run = Parse(folder);
        _output.WriteLine(run.Output);
        Assert.True(run.ExitCode != 0, $"3.11 grammar accepted:\n{source}");
        Assert.Contains("newer.py", run.Output);
        Assert.DoesNotContain("fine.py", run.Output);
    }

    // MARK: - Running

    private static (int ExitCode, string Output) Run(string file, params string[] arguments)
    {
        var start = new ProcessStartInfo(file)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (string argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        Assert.True(process.WaitForExit(120_000), $"{file} did not finish within 120 s.");
        return (process.ExitCode, (stdout.Result + stderr.Result).Trim());
    }
}

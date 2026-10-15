using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// Runs only where the native runtime carries the page-feature engines
/// (<c>runtime\vendor\tikz-engine</c>, from <c>fetch-runtime.ps1</c> since
/// #503). Otherwise REPORTED as skipped, with the reason — never silently
/// green.
/// </summary>
public sealed class NativeVendorFactAttribute : FactAttribute
{
    public NativeVendorFactAttribute()
    {
        if (NativeRuntime.Folder is not { } runtime)
            Skip = "No native runtime here: run windows-app\\Vendor\\fetch-runtime.ps1, or set PLANTOIR_RUNTIME.";
        else if (!File.Exists(Path.Combine(runtime, "vendor", "tikz-engine", "node_modules", "node-tikzjax", "package.json")))
            Skip = "The native runtime predates its vendor folder: re-run windows-app\\Vendor\\fetch-runtime.ps1.";
    }
}

/// <summary>
/// #503: the TikZ engine and function-plot, natively. What the mac measured in
/// its image (two runs, two processes, byte-identical SVG; a diagram that
/// never ends is killed at <c>figures.JOB_SECONDS</c> and the next one still
/// drawn), and what nobody had measured before this file: whether
/// node-tikzjax's memfs <c>/tex_files/</c> works under win32 paths. Then a
/// real build through <c>preview.ps1 --build-only</c> of a course with a
/// diagram, a graph and a printable page, read back from the built site.
/// <c>documentation/12-windows-app.md</c> → "Diagrams and graphs".
/// </summary>
[Collection(ReferenceDiskCollection.Name)]
public sealed class NativeFiguresTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-figures").FullName;
    private readonly ITestOutputHelper _output;

    public NativeFiguresTests(ITestOutputHelper output) => _output = output;

    public void Dispose()
    {
        // The junction to the repository goes FIRST, on its own, so nothing
        // below can ever walk through it into the repository.
        string link = Path.Combine(_root, "work folder", ".toolchain");
        try { if (Directory.Exists(link)) Directory.Delete(link); } catch { }
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static string Runtime => NativeRuntime.Folder!;
    private static string Repo => ContractLoader.RepositoryRoot;

    /// <summary>
    /// figureRules.js is an ES module that a section's Quartz (whose
    /// package.json says "type": "module") carries; outside one, Node reads
    /// it as CommonJS and refuses its import. So the test gives it one.
    /// </summary>
    private string Rules()
    {
        string folder = Directory.CreateDirectory(Path.Combine(_root, "rules")).FullName;
        File.Copy(Path.Combine(Repo, "support", "quartz", "plugins", "transformers", "figureRules.js"),
                  Path.Combine(folder, "figureRules.js"), overwrite: true);
        File.WriteAllText(Path.Combine(folder, "package.json"), "{\"type\": \"module\"}");
        return Path.Combine(folder, "figureRules.js");
    }

    private string[] HelperCommand() =>
    [
        Path.Combine(Runtime, "node", "node.exe"),
        Path.Combine(Repo, "support", "figures", "plantoir-figures.mjs"),
        "--engine", Path.Combine(Runtime, "vendor", "tikz-engine"),
        "--function-plot", Path.Combine(Runtime, "vendor", "function-plot", "function-plot.js"),
        "--rules", Rules(),
        "--quartz", Path.Combine(Runtime, "quartz"),
    ];

    private const string Square =
        "% alt: A square.\n\\begin{document}\n\\begin{tikzpicture}\n  \\draw (0,0) rectangle (2,2);\n\\end{tikzpicture}\n\\end{document}\n";

    private const string Circle =
        "% alt: A circle of radius 1.\n\\begin{document}\n\\begin{tikzpicture}\n  \\draw (0,0) circle (1) node {$r$};\n\\end{tikzpicture}\n\\end{document}\n";

    private static string ContractTriangle()
    {
        var doc = JsonNode.Parse(File.ReadAllText(Path.Combine(Repo, "contracts", "shared-rules.json")))!;
        return doc["figureFences"]!["cacheKey"]!["cases"]![0]!["body"]!.ToString();
    }

    [NativeVendorFact]
    public void TheContractsTriangleIsDrawnTheSameInTwoProcesses()
    {
        string body = ContractTriangle();
        string[] command = HelperCommand();
        var svgs = new List<string>();
        for (int run = 1; run <= 2; run++)
        {
            var start = new ProcessStartInfo(command[0])
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardInputEncoding = new UTF8Encoding(false),
            };
            foreach (string argument in command.Skip(1)) start.ArgumentList.Add(argument);
            using var helper = Process.Start(start)!;
            var complaints = helper.StandardError.ReadToEndAsync();
            var clock = Stopwatch.StartNew();
            try
            {
                Assert.True(JsonNode.Parse(helper.StandardOutput.ReadLine()!)!["ready"]!.GetValue<bool>());
                helper.StandardInput.WriteLine("{\"load\": \"tikz\"}");
                var loaded = JsonNode.Parse(helper.StandardOutput.ReadLine()!)!;
                Assert.Equal("tikz", loaded["loaded"]?.ToString());
                var job = new JsonObject { ["id"] = 1, ["engine"] = "tikz", ["body"] = body };
                helper.StandardInput.WriteLine(job.ToJsonString());
                var answer = JsonNode.Parse(helper.StandardOutput.ReadLine()!)!;
                Assert.True(answer["ok"]!.GetValue<bool>(),
                    "the triangle was not drawn — memfs's /tex_files/ under win32 paths is the first suspect: " + answer.ToJsonString());
                string svg = answer["svg"]!.ToString();
                Assert.StartsWith("<svg", svg);
                Assert.Contains("viewBox", svg);
                svgs.Add(svg);
                _output.WriteLine($"run {run}: engine loaded in {loaded["ms"]} ms, triangle drawn in {answer["ms"]} ms, " +
                                  $"{clock.ElapsedMilliseconds} ms in all; SVG {Encoding.UTF8.GetByteCount(svg)} bytes, SHA-256 " +
                                  Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(svg))).ToLowerInvariant());
            }
            finally
            {
                helper.StandardInput.Close();
                if (!helper.WaitForExit(30_000)) helper.Kill(entireProcessTree: true);
            }
        }
        Assert.Equal(svgs[0], svgs[1]);
    }

    [NativeVendorFact]
    public void ADiagramThatNeverEndsIsStoppedAndTheNextOneIsStillDrawn()
    {
        // figures.run_jobs, the build's own clock, with the runtime's Python:
        // `-I` drops the script's folder and PYTHONPATH (which the embeddable
        // runtime's ._pth ignores anyway), so the scripts folder goes on
        // sys.path by hand, and -X utf8 because -I drops PYTHONUTF8 too.
        string jobs = Path.Combine(_root, "jobs.json");
        string commandFile = Path.Combine(_root, "command.json");
        string answers = Path.Combine(_root, "answers.json");
        File.WriteAllText(jobs, new JsonArray
        {
            new JsonObject { ["id"] = "endless", ["engine"] = "tikz", ["body"] = "\\begin{document}\n\\def\\x{\\x}\\x\n\\end{document}\n" },
            new JsonObject { ["id"] = "triangle", ["engine"] = "tikz", ["body"] = ContractTriangle() },
        }.ToJsonString());
        File.WriteAllText(commandFile, new JsonArray(HelperCommand().Select(part => (JsonNode)JsonValue.Create(part)!).ToArray()).ToJsonString());
        string script = Path.Combine(_root, "run_jobs.py");
        File.WriteAllText(script, """
            import json, sys, time
            sys.path.insert(0, sys.argv[1])
            import figures
            jobs = json.load(open(sys.argv[2], encoding="utf-8"))
            command = json.load(open(sys.argv[3], encoding="utf-8"))
            started = time.monotonic()
            results = figures.run_jobs(jobs, command, printer=lambda *parts: None)
            results["seconds"] = time.monotonic() - started
            results["jobSeconds"] = figures.JOB_SECONDS
            json.dump(results, open(sys.argv[4], "w", encoding="utf-8"))
            """);

        var start = new ProcessStartInfo(Path.Combine(Runtime, "python", "python.exe"))
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
        };
        foreach (string argument in new[] { "-I", "-X", "utf8", script, Path.Combine(Repo, "scripts"), jobs, commandFile, answers })
            start.ArgumentList.Add(argument);
        using var python = Process.Start(start)!;
        string said = python.StandardOutput.ReadToEnd() + python.StandardError.ReadToEnd();
        Assert.True(python.WaitForExit(180_000), "run_jobs did not come back");
        Assert.True(python.ExitCode == 0, said);

        var results = JsonNode.Parse(File.ReadAllText(answers))!;
        double seconds = results["seconds"]!.GetValue<double>();
        int jobSeconds = results["jobSeconds"]!.GetValue<int>();
        _output.WriteLine($"both jobs answered in {seconds:0.0} s (the clock per diagram is {jobSeconds} s)");
        Assert.Equal("tookTooLong", results["endless"]!["reason"]?.ToString());
        Assert.True(results["triangle"]!["ok"]!.GetValue<bool>(), results["triangle"]!.ToJsonString());
        // Killed at the clock, not left to run: the helper's start and the
        // engine's load (a few seconds each) plus one clock, with room.
        Assert.True(seconds < jobSeconds + 40, $"{seconds:0.0} s: the endless diagram was not stopped at its clock");
    }

    [NativeVendorFact]
    public void ABuildWithADiagramAGraphAndAPrintablePageCarriesAllThree()
    {
        string working = Path.Combine(_root, "work folder");
        string course = Path.Combine(working, "courses", "MPM2D");
        Directory.CreateDirectory(Path.Combine(course, "Lessons"));
        Directory.CreateDirectory(Path.Combine(course, "section1"));
        File.WriteAllText(Path.Combine(course, "course_config.json"), """
            {"course_code": "MPM2D", "course_name": "Mathematics", "section_numbers": [1], "num_sections": 1,
             "shared_folders": ["Lessons"], "shared_files": [], "per_section_folders": [], "per_section_files": [],
             "deploy_target": "local_folder", "deploy_folder_path": ""}
            """);
        File.WriteAllText(Path.Combine(course, "section1", "index.md"), "---\ntitle: Section 1\npublish: true\n---\n# Welcome\n");
        File.WriteAllText(Path.Combine(course, "Lessons", "Similar Triangles.md"),
            "---\ntitle: Similar Triangles\npublish: true\nprintable: true\n---\n# Similar Triangles\n\n" +
            "```tikz\n" + ContractTriangle() + "```\n\n" +
            "```tikz\n" + Square + "```\n\n" +
            "```tikz\n" + Circle + "```\n\n" +
            "```functionplot\ny = x^2\n```\n");

        foreach (string launcher in new[] { "preview.ps1", "preview.bat" })
            File.Copy(Path.Combine(Repo, launcher), Path.Combine(working, launcher));
        Assert.Equal(0, Run("cmd.exe", $"/c mklink /J \"{Path.Combine(working, ".toolchain")}\" \"{Repo}\"", working).Exit);
        string appData = Directory.CreateDirectory(Path.Combine(_root, "appdata")).FullName;

        var clock = Stopwatch.StartNew();
        var run = Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File preview.ps1 MPM2D 1 --build-only", working,
            ("PLANTOIR_RUNTIME", Runtime), ("LOCALAPPDATA", appData));
        _output.WriteLine($"first build: {clock.Elapsed.TotalSeconds:0.0} s");
        _output.WriteLine(run.Output.Length > 4000 ? run.Output[^4000..] : run.Output);
        Assert.True(run.Exit == 0, "the build did not finish: " + (run.Output.Length > 1500 ? run.Output[^1500..] : run.Output));

        // Nothing fell back: the build found every engine in runtime\vendor.
        Assert.Contains("Drew 3 diagrams (0 from before); 3 diagram(s) and 1 graph(s) on the site", run.Output);
        foreach (string missing in new[] { "missing its print layout", "missing what draws graphs", "cannot draw TikZ",
                                           "Could not start drawing", "engineMissing" })
            Assert.DoesNotContain(missing, run.Output);

        var files = Directory.GetFiles(appData, "*", SearchOption.AllDirectories)
            .Where(p => p.Contains($"{Path.DirectorySeparatorChar}public{Path.DirectorySeparatorChar}")).ToList();
        string Sep(string path) => path.Replace('/', Path.DirectorySeparatorChar);
        Assert.Contains(files, p => p.EndsWith(Sep("static/pagedjs/paged.min.js"), StringComparison.OrdinalIgnoreCase));
        Assert.Contains(files, p => p.EndsWith(Sep("static/function-plot/function-plot.js"), StringComparison.OrdinalIgnoreCase));
        var pages = files.Where(p => p.EndsWith("Similar-Triangles.html", StringComparison.OrdinalIgnoreCase)).ToList();
        Assert.NotEmpty(pages);
        foreach (string page in pages)
        {
            _output.WriteLine("built page: " + page[appData.Length..]);
            string html = File.ReadAllText(page);
            int figure = html.IndexOf("pl-figure pl-tikz", StringComparison.Ordinal);
            Assert.True(figure >= 0, "no TikZ figure on the built page");
            Assert.True(html.IndexOf("<svg", figure, StringComparison.Ordinal) > figure, "the TikZ figure holds no inline SVG");
            Assert.Contains("pl-figure pl-functionplot", html);
        }

        // And a second build draws nothing again: every figure from the cache.
        clock.Restart();
        var again = Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File preview.ps1 MPM2D 1 --build-only", working,
            ("PLANTOIR_RUNTIME", Runtime), ("LOCALAPPDATA", appData));
        _output.WriteLine($"cached build: {clock.Elapsed.TotalSeconds:0.0} s");
        Assert.True(again.Exit == 0, again.Output.Length > 1500 ? again.Output[^1500..] : again.Output);
        Assert.Contains("Drew 0 diagrams (4 from before)", again.Output);
    }

    private static (int Exit, string Output) Run(string file, string arguments, string folder, params (string Name, string Value)[] environment)
    {
        var start = new ProcessStartInfo(file, arguments)
        {
            WorkingDirectory = folder, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var (name, value) in environment) start.Environment[name] = value;
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEndAsync();
        var errors = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(600_000)) { process.Kill(entireProcessTree: true); return (-1, "timed out"); }
        return (process.ExitCode, output.Result + errors.Result);
    }
}

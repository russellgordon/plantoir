using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace Plantoir.Tests;

/// <summary>
/// The website builder's OWN answer about a page: ONE Python process that
/// imports <c>scripts/build_site.py</c> and, for each page, loads it with
/// python-frontmatter (a raise = "the build cannot read it") and runs the real
/// <c>process_frontmatter</c> for sections 1 to 4, then reads <c>publish</c>
/// the way Quartz's <c>publish.ts</c> does: hidden only for <c>false</c> or
/// <c>"false"</c>. Never a re-implementation in C# — that would prove nothing
/// (bundle-6 plan risk 7). This app has no YAML library; this is the oracle
/// the C# guard is fuzzed against.
/// </summary>
internal static class BuildFrontmatterOracle
{
    /// <summary>What the build made of one page.</summary>
    /// <param name="Loaded">False when python-frontmatter raised on the page as written.</param>
    /// <param name="HiddenIn">For sections 1..4, whether publish.ts would hide it after process_frontmatter.</param>
    /// <param name="Problem">The exception text when it did not load, for the failure message.</param>
    internal sealed record Answer(bool Loaded, bool[] HiddenIn, string? Problem)
    {
        public bool HiddenEverywhere => Loaded && HiddenIn.All(hidden => hidden);
    }

    private const string Script = """
        import json, os, sys, shutil, tempfile, pathlib, functools, multiprocessing

        def setup(scripts):
            global build_site, frontmatter, work
            sys.path.insert(0, scripts)
            import build_site as b, frontmatter as f
            build_site, frontmatter = b, f
            # The sentinel-note settings are read from the contracts on EVERY
            # call; cached for speed only. Visibility is decided by the real code.
            build_site._get_excluded_note_config = functools.lru_cache(maxsize=None)(build_site._get_excluded_note_config)
            work = pathlib.Path(tempfile.mkdtemp(prefix="plantoir-oracle-"))

        def check(item):
            i, text = item
            source = work / f"p{i}.md"
            with open(source, "w", encoding="utf-8", newline="") as f:
                f.write(text)
            try:
                frontmatter.load(source)
            except Exception as e:
                source.unlink()
                return {"loaded": False, "hidden": [], "problem": type(e).__name__ + ": " + str(e)[:200]}
            hidden = []
            for section in (1, 2, 3, 4):
                copy = work / f"p{i}-s{section}.md"
                shutil.copyfile(source, copy)
                build_site.process_frontmatter(copy, section)
                try:
                    flag = frontmatter.load(copy).get("publish")
                    hidden.append(flag is False or flag == "false")
                except Exception:
                    hidden.append(False)
                copy.unlink()
            source.unlink()
            return {"loaded": True, "hidden": hidden, "problem": None}

        if __name__ == "__main__":
            pages = json.load(open(sys.argv[2], encoding="utf-8"))
            with multiprocessing.Pool(os.cpu_count(), initializer=setup, initargs=(sys.argv[1],)) as pool:
                answers = pool.map(check, list(enumerate(pages)), chunksize=50)
            with open(sys.argv[3], "w", encoding="utf-8") as out:
                for answer in answers:
                    out.write(json.dumps(answer) + "\n")
        """;

    /// <summary>Asks the build about every page, in one process; the answers are in the same order.</summary>
    internal static List<Answer> Ask(IReadOnlyList<string> pages)
    {
        string folder = Directory.CreateTempSubdirectory("plantoir-oracle-io").FullName;
        try
        {
            string script = Path.Combine(folder, "oracle.py");
            string input = Path.Combine(folder, "pages.json");
            string output = Path.Combine(folder, "answers.jsonl");
            File.WriteAllText(script, Script, new UTF8Encoding(false));
            File.WriteAllText(input, JsonSerializer.Serialize(pages), new UTF8Encoding(false));

            var start = new ProcessStartInfo(Python, "")
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                WorkingDirectory = Path.Combine(ContractLoader.RepositoryRoot, "scripts"),
            };
            foreach (string argument in new[] { script, Path.Combine(ContractLoader.RepositoryRoot, "scripts"), input, output })
                start.ArgumentList.Add(argument);
            start.Environment["PYTHONUTF8"] = "1";
            using var process = Process.Start(start)!;
            var stdout = process.StandardOutput.ReadToEndAsync();
            string stderr = process.StandardError.ReadToEnd();
            process.WaitForExit();
            _ = stdout.Result;
            if (process.ExitCode != 0) throw new InvalidOperationException("the build's reader did not run: " + stderr);

            return File.ReadLines(output).Select(line =>
            {
                using var answer = JsonDocument.Parse(line);
                var root = answer.RootElement;
                return new Answer(root.GetProperty("loaded").GetBoolean(),
                    root.GetProperty("hidden").EnumerateArray().Select(h => h.GetBoolean()).ToArray(),
                    root.GetProperty("problem").ValueKind == JsonValueKind.String ? root.GetProperty("problem").GetString() : null);
            }).ToList();
        }
        finally
        {
            try { Directory.Delete(folder, recursive: true); } catch { }
        }
    }

    private static string? cachedPython;

    /// <summary>The interpreter, found the way PythonToolchainTests finds it; a missing one FAILS, never skips.</summary>
    private static string Python => cachedPython ??= new[] { "python", "python3" }.FirstOrDefault(candidate =>
    {
        try
        {
            using var probe = Process.Start(new ProcessStartInfo(candidate, "--version")
            {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
            });
            probe!.WaitForExit(20_000);
            return probe.ExitCode == 0;
        }
        catch { return false; }
    }) ?? throw new InvalidOperationException("No Python interpreter found on PATH (tried \"python\" and \"python3\").");
}

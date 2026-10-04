using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The Codex door (#210, mac #205) and the contract both doors are described
/// by (<c>app-rules.json</c> → <c>outsideAgents</c>). The mac's counterparts
/// are <c>CodexLauncherTests</c> and
/// <c>AppRulesContractTests.testTheOutsideDoorsSayAndPassWhatTheContractSays</c>.
/// </summary>
public class CodexLauncherTests : IDisposable
{
    private readonly string _scratch = Directory.CreateTempSubdirectory("plantoir-codex").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_scratch, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    // The mac's six fixtures, plus control characters. Expected values are
    // the TOML basic string INCLUDING its quotes.
    [Theory]
    [InlineData(@"C:\Users\r\Teaching", "\"C:\\\\Users\\\\r\\\\Teaching\"")]
    [InlineData("/Users/r/Class Notes", "\"/Users/r/Class Notes\"")]
    [InlineData("/Users/r/Russell's Courses", "\"/Users/r/Russell's Courses\"")]
    [InlineData("/Users/r/My \"Notes\"", "\"/Users/r/My \\\"Notes\\\"\"")]
    [InlineData("/Users/r/back\\slash", "\"/Users/r/back\\\\slash\"")]
    [InlineData("/Users/r/Français 🎓", "\"/Users/r/Français 🎓\"")]
    [InlineData("a\tb\nc\u0001", "\"a\\tb\\nc\\u0001\"")]
    public void ValuesAreEscapedForTomlFirst(string value, string expected) =>
        Assert.Equal(expected, CodexLauncher.TomlBasicString(value));

    /// <summary>
    /// What the contract says each door passes, by substitution — the argv
    /// itself, never the shell text around it.
    /// </summary>
    [Fact]
    public void TheOutsideDoorsPassWhatTheContractSays()
    {
        var section = (JsonObject)ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!;
        var agents = section["agents"]!.AsArray();
        Assert.Equal(2, agents.Count);
        Assert.True(section["greetingIsTheSameForEveryAgent"]!.GetValue<bool>());
        Assert.Equal(new[] { "--mcp-stdio", "{folder}" },
                     section["serverArguments"]!.AsArray().Select(a => a!.ToString()));

        const string folder = @"C:\Users\teacher\Teaching", server = @"C:\Program Files\Plantoir\plantoir-mcp.exe";
        const string config = @"C:\Users\teacher\AppData\Local\Plantoir\assist\mcp-ICS3U.json";
        string greeting = ClaudeCodeLauncher.Greeting("ICS3U", "Grade 11 Computer Science");
        Assert.DoesNotContain("\"", greeting);

        foreach (var agent in agents)
        {
            string key = agent!["key"]!.ToString();
            var expected = agent["arguments"]!.AsArray().Select(a => a!.ToString()
                .Replace("{folder}", folder.Replace("\\", "\\\\")).Replace("{server}", server.Replace("\\", "\\\\"))
                .Replace("{config}", config).Replace("{greeting}", greeting)).ToList();
            var actual = key switch
            {
                "claude" => ClaudeCodeLauncher.Arguments(config, greeting),
                "codex" => CodexLauncher.Arguments(server, folder, greeting),
                _ => throw new InvalidOperationException($"a door this app does not know: {key}"),
            };
            Assert.Equal(expected, actual);
            Assert.Equal(key == "claude" ? "started Claude Code for {course}" : "started Codex for {course}",
                         agent["trailLine"]!.ToString());
        }

        // The SERVER each door starts, by the same substitution (#430): the
        // folder and never a course, for the Claude door's file as for the
        // Codex door's -c override. Only the greeting names the course.
        var serverArguments = section["serverArguments"]!.AsArray()
            .Select(a => a!.ToString().Replace("{folder}", folder)).ToList();
        var written = JsonNode.Parse(ClaudeCodeLauncher.ConfigText(folder, server))!["mcpServers"]!["plantoir"]!;
        Assert.Equal(server, written["command"]!.ToString());
        Assert.Equal(serverArguments, written["args"]!.AsArray().Select(a => a!.ToString()));
        string codexArgs = CodexLauncher.Arguments(server, folder, greeting)[3]["mcp_servers.plantoir.args=".Length..];
        Assert.Equal(serverArguments, JsonSerializer.Deserialize<string[]>(codexArgs));
        Assert.Contains("ICS3U", greeting);
        Assert.Contains("Grade 11 Computer Science", greeting);
    }

    /// <summary>
    /// The round trip the mac's <c>testTheRenderedArgumentsSurviveTheShell</c>
    /// makes, through MORE layers here: a real <c>cmd.exe /s /c</c>, then a
    /// stub <c>codex.cmd</c> shaped like npm's shim (<c>%*</c> parsed by cmd a
    /// second time), into a program that prints its argv.
    /// </summary>
    [Fact]
    public void TheArgumentsSurviveCmdAndABatchShim()
    {
        string echo = WriteEcho();
        string stub = Path.Combine(_scratch, "codex.cmd");
        File.WriteAllText(stub, "@python \"%~dp0echo_args.py\" %*\r\n");

        var (server, folder, greeting) = Awkward();
        var sent = CodexLauncher.Arguments(server, folder, greeting);
        AssertArrived(sent, Run(CodexLauncher.CmdArguments(stub, sent, keepOpen: false)), folder);
    }

    /// <summary>The same through ONE cmd parse, for a native <c>codex.exe</c>.</summary>
    [Fact]
    public void TheArgumentsSurviveCmdIntoAnExecutable()
    {
        string echo = WriteEcho();
        string python = FindPython();
        var (server, folder, greeting) = Awkward();
        var sent = CodexLauncher.Arguments(server, folder, greeting);
        var received = Run(CodexLauncher.CmdArguments(python, new[] { echo }.Concat(sent), keepOpen: false));
        AssertArrived(sent, received, folder);
    }

    private static (string Server, string Folder, string Greeting) Awkward() => (
        @"C:\Program Files\Plan ""toir"" & Co\plantoir-mcp.exe",
        @"C:\Users\r\Russell's Courses (2026) & Français 🎓\a^b|c<d>e\",
        ClaudeCodeLauncher.Greeting("ICS3U", "Grade 11 Computer Science & Co. (pilot)"));

    private static void AssertArrived(IReadOnlyList<string> sent, List<string> received, string folder)
    {
        Assert.Equal(sent, received);
        // The args value must still be a LIST of two strings — the silent
        // failure is a value that has become one string.
        string args = received[3]["mcp_servers.plantoir.args=".Length..];
        var parsed = JsonSerializer.Deserialize<string[]>(args);
        Assert.Equal(new[] { "--mcp-stdio", folder }, parsed);
    }

    private string WriteEcho()
    {
        string path = Path.Combine(_scratch, "echo_args.py");
        File.WriteAllText(path, "import sys, json\nsys.stdout.write(json.dumps(sys.argv[1:]))\n");
        return path;
    }

    private static string FindPython() =>
        (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
            .Select(d => Path.Combine(d.Trim(), "python.exe")).FirstOrDefault(File.Exists)
        ?? throw new InvalidOperationException("No python on PATH; the suite needs one (CLAUDE.md, setting up Windows).");

    private List<string> Run(string cmdArguments)
    {
        var info = new ProcessStartInfo("cmd.exe", cmdArguments)
        {
            UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = _scratch,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
        };
        using var process = Process.Start(info)!;
        string output = process.StandardOutput.ReadToEnd();
        string error = process.StandardError.ReadToEnd();
        process.WaitForExit();
        Assert.True(output.Length > 0, $"nothing arrived; cmd said: {error}\nsent: {cmdArguments}");
        return JsonSerializer.Deserialize<List<string>>(output)!;
    }
}

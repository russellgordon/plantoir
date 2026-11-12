using System.Diagnostics;
using System.Text;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// What both outside doors hand to Windows (#736, and the fault it fixed in
/// 1.9.0's Claude door): every name and every row a teacher's course brings
/// is HOSTILE text, and each must reach the program as the one argument it
/// was, through the REAL start (<see cref="OutsideDoor.StartInfo"/>) into a
/// stub program that writes down its argument vector — a stub <c>.exe</c>
/// and a stub <c>.cmd</c> shaped like npm's shim. The one difference from a
/// teacher's start is that the test's runs open no window (CreateProcess with
/// no window instead of ShellExecute), so the suite cannot take the desktop
/// from anybody; the window itself is proven by pressing the buttons
/// (documentation/12-windows-app.md → "What the outside doors hand to Windows,
/// and how").
/// </summary>
[Collection(StubProgramCollection.Name)]
public class OutsideDoorTests : IDisposable
{
    private readonly ITestOutputHelper _output;
    private readonly string _scratch = Directory.CreateTempSubdirectory("plantoir-door").FullName;
    private readonly string _folder;

    public OutsideDoorTests(ITestOutputHelper output)
    {
        _output = output;
        // The working folder is hostile too: every character a folder may hold that cmd reads.
        _folder = Directory.CreateDirectory(Path.Combine(_scratch, "Teaching & ^ %OS% !x! (a);'é 🎓")).FullName;
    }

    public void Dispose()
    {
        try { Directory.Delete(_scratch, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    /// <summary>
    /// The hostile set: each of cmd's metacharacters, a variable cmd and
    /// Windows Terminal would expand, delayed expansion, Windows Terminal's
    /// tab separator, a quote, a trailing backslash, a line break, and text
    /// that is not ASCII. Built here, never written as a product sentence.
    /// </summary>
    public static IEnumerable<object[]> HostileNames() => new[]
    {
        "Math & Co", "A | B", "A > B", "A < B", "A ^ B", "100% %OS% done", "%PATH%", "50%% off",
        "!x! loud!", "Part 1; Part 2", "The \"Best\" Course", @"Ends in a backslash\", "Two\nLines",
        "Français 🎓 数学", @"TeX \% and (parens) 'quotes'", "%", "a%b%c", "%OS%%OS%",
    }.Select(name => new object[] { name });

    /// <summary>Revise With ▸ Claude…'s plain greeting with the course's name in it, to a stub <c>claude.exe</c>: arrives unchanged.</summary>
    [Theory]
    [MemberData(nameof(HostileNames))]
    public void TheClaudeDoorsGreetingArrivesWholeAtAnExe(string name)
    {
        var sent = ClaudeCodeLauncher.Arguments(@"C:\Users\t\AppData\Local\Plantoir\assist\mcp-ICS3U.json",
                                                ClaudeCodeLauncher.Greeting("ICS3U", name));
        AssertArrives(StubExe(), sent, sent);
    }

    /// <summary>The same through npm's <c>claude.cmd</c> shim: arrives unchanged but for a line break, which cmd cannot carry.</summary>
    [Theory]
    [MemberData(nameof(HostileNames))]
    public void TheClaudeDoorsGreetingArrivesWholeThroughAShim(string name)
    {
        var sent = ClaudeCodeLauncher.Arguments(@"C:\Users\t\AppData\Local\Plantoir\assist\mcp-ICS3U.json",
                                                ClaudeCodeLauncher.Greeting("ICS3U", name));
        AssertArrives(StubShim("claude.cmd"), sent, OnOneLine(sent));
    }

    /// <summary>Fix with Claude…'s message, with the name in the course AND in the page names, to both stubs.</summary>
    [Theory]
    [MemberData(nameof(HostileNames))]
    public void TheFixMessageArrivesWhole(string name)
    {
        var rows = new[]
        {
            new SectionProblemRow { Id = "a", Kind = "figuresCouldNotBeDrawn", Page = "Unit 1/" + name, Prompt = "“Unit 1”, diagram 1: " + name },
            new SectionProblemRow { Id = "b", Kind = "printPdfNotFound", Page = "section1/" + name, Prompt = "names {section}.pdf" },
        };
        string message = FixWithAssistant.GreetingFor(rows, "ICS3U", name, 1, "preview")!.Text;
        Assert.DoesNotContain(";", message);
        Assert.DoesNotContain("\"", message);
        var sent = ClaudeCodeLauncher.Arguments(@"C:\cfg\mcp-ICS3U.json", message);
        AssertArrives(StubExe(), sent, sent);
        AssertArrives(StubShim("claude.cmd"), sent, OnOneLine(sent));
    }

    /// <summary>
    /// The Codex door: five TOML overrides and the message, the server's
    /// folder hostile as well, to a stub <c>codex.exe</c> and npm's
    /// <c>codex.cmd</c>; the folder still reads back as a list of two.
    /// </summary>
    [Theory]
    [MemberData(nameof(HostileNames))]
    public void TheCodexDoorsArgumentsArriveWhole(string name)
    {
        string server = @"C:\Program Files\Plan ""toir"" & Co\plantoir-mcp.exe";
        var sent = CodexLauncher.Arguments(server, _folder + "\\", "-AP CALC- & ^(x)|y", ClaudeCodeLauncher.Greeting("ICS3U", name));
        AssertArrives(StubExe(), sent, sent);
        AssertArrives(StubShim("codex.cmd"), sent, OnOneLine(sent));
    }

    /// <summary>
    /// The must-fail: 1.9.0's Claude door, as it joined its line when Windows
    /// Terminal was absent (<c>cmd.exe /k</c> + the quoted path, the flags and
    /// the quoted greeting, with only <c>"</c> replaced — <c>/c</c> here, which
    /// parses the same, so the test's cmd ends). With more than two quotes and
    /// no <c>/s</c>, cmd strips the first and the last, the greeting lands
    /// outside quotes, and it does not arrive as the argument it was.
    /// </summary>
    [Theory]
    [InlineData("Math & Co")]
    [InlineData("A | B")]
    [InlineData("A > B")]
    [InlineData("100% %OS% done")]
    public void TheOldLineDidNotCarryTheName(string name)
    {
        string probe = StubExe(), config = @"C:\cfg\mcp-ICS3U.json";
        string greeting = ClaudeCodeLauncher.Greeting("ICS3U", name);
        var sent = ClaudeCodeLauncher.Arguments(config, greeting);
        string command = $"\"{probe}\" {sent[0]} \"{sent[1]}\" {sent[2]} \"{sent[3]}\"";
        var info = new ProcessStartInfo(OutsideDoor.Cmd, "/c " + command) { WorkingDirectory = _folder };
        var received = Run(info, allowNothing: true);
        Assert.NotEqual(sent, received);
    }

    /// <summary>An <c>.exe</c> is started with no command interpreter in front, and a shim with cmd only, <c>/v:off</c>, never through Windows Terminal.</summary>
    [Fact]
    public void AnExeHasNothingInFrontAndAShimOnlyCmd()
    {
        var exe = OutsideDoor.StartInfo(@"C:\Users\t\.local\bin\claude.exe", new[] { "a b" }, _folder);
        Assert.Equal(@"C:\Users\t\.local\bin\claude.exe", exe.FileName);
        Assert.Equal("\"a b\"", exe.Arguments);
        Assert.Equal(_folder, exe.WorkingDirectory);
        var shim = OutsideDoor.StartInfo(@"C:\Users\t\AppData\Roaming\npm\codex.cmd", new[] { "a b" }, _folder);
        Assert.Equal(OutsideDoor.Cmd, shim.FileName);
        Assert.StartsWith("/v:off /s /k \"", shim.Arguments);
        foreach (var info in new[] { exe, shim })
            Assert.DoesNotContain("wt.exe", info.FileName + " " + info.Arguments, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// The longest <c>greetingCases</c> message's WHOLE command line — this
    /// PC's real <c>claude</c> path when it has one, the configuration's real
    /// path, a 200-character working folder for Codex — is under cmd's 8,191
    /// UTF-16 units, through either kind of program.
    /// </summary>
    [Fact]
    public void TheLongestMessagesCommandLineFits()
    {
        var cases = ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["fixWith"]!["greetingCases"]!.AsArray();
        string longest = cases.Where(c => c!["expect"] is not null)
            .Select(c => FixWithAssistant.GreetingFor(FixWithAssistantContractTests.RowsOf(c!), c!["course"]!.ToString(),
                c["courseName"]!.ToString(), c["section"]!.GetValue<int>(), c["occasion"]!.ToString())!.Text)
            .OrderByDescending(text => text.Length).First();
        string claude = ClaudeCodeLauncher.FindClaude() ?? @"C:\Users\a-teacher-with-a-long-name\.local\bin\claude.exe";
        string folder = @"C:\Users\" + new string('f', 190);
        string config = ClaudeCodeLauncher.ConfigPath("MPM2D");
        string server = @"C:\Program Files\Plantoir\plantoir-mcp.exe";
        foreach (string program in new[] { claude, Path.ChangeExtension(claude, ".cmd") })
        {
            int claudeLine = OutsideDoor.LineLength(program, ClaudeCodeLauncher.Arguments(config, longest));
            int codexLine = OutsideDoor.LineLength(program, CodexLauncher.Arguments(server, folder, "MPM2D", longest));
            _output.WriteLine($"{program}: message {longest.Length} UTF-16 units, Claude line {claudeLine}, Codex line {codexLine}");
            Assert.True(claudeLine < FixWithAssistant.CommandLineMaxUtf16, $"Claude line {claudeLine}");
            Assert.True(codexLine < FixWithAssistant.CommandLineMaxUtf16, $"Codex line {codexLine}");
        }
    }

    // ---- The stubs ---------------------------------------------------------------

    private string StubExe() => StubProgramCollection.ProbeExe;

    /// <summary>A shim in npm's cmd-shim shape, whose program is the probe: <c>%*</c> parsed by cmd a second time.</summary>
    private string StubShim(string name)
    {
        string folder = Directory.CreateDirectory(Path.Combine(_scratch, "npm")).FullName;
        File.Copy(StubProgramCollection.ProbeExe, Path.Combine(folder, "node.exe"), overwrite: true);
        string shim = Path.Combine(folder, name);
        File.WriteAllText(shim, string.Join("\r\n",
            "@ECHO off", "GOTO start", ":find_dp0", "SET dp0=%~dp0", "EXIT /b", ":start", "SETLOCAL", "CALL :find_dp0", "",
            "IF EXIST \"%dp0%\\node.exe\" (", "  SET \"_prog=%dp0%\\node.exe\"", ") ELSE (", "  SET \"_prog=node\"",
            "  SET PATHEXT=%PATHEXT:;.JS;=;%", ")", "",
            "endLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & \"%_prog%\"  \"%dp0%\\node_modules\\cli.js\" %*", ""));
        return shim;
    }

    private static IReadOnlyList<string> OnOneLine(IReadOnlyList<string> sent) =>
        sent.Select(a => a.Replace("\r\n", " ").Replace('\n', ' ')).ToList();

    private void AssertArrives(string program, IReadOnlyList<string> sent, IReadOnlyList<string> expected)
    {
        var info = OutsideDoor.StartInfo(program, sent, _folder, keepOpen: false);
        var received = Run(info);
        if (OutsideDoor.IsBatch(program))
        {
            Assert.EndsWith("cli.js", received[0]);
            received = received.Skip(1).ToList();
        }
        Assert.Equal(expected, received);
    }

    /// <summary>
    /// Runs exactly what the door would start, without a window: the same
    /// program and the same command line, through CreateProcess.
    /// </summary>
    private List<string> Run(ProcessStartInfo door, bool allowNothing = false)
    {
        string output = Path.Combine(_scratch, Guid.NewGuid().ToString("N") + ".txt");
        var info = new ProcessStartInfo(door.FileName, door.Arguments)
        {
            WorkingDirectory = door.WorkingDirectory, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
        };
        info.Environment[StubProgramCollection.OutputVariable] = output;
        using (var process = Process.Start(info)!)
        {
            string said = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
            Assert.True(process.WaitForExit(30_000), "the stub did not finish");
            if (said.Length > 0) _output.WriteLine("printed: " + said);
        }
        if (!File.Exists(output))
        {
            Assert.True(allowNothing, $"nothing arrived; started: {door.FileName} {door.Arguments}");
            return new List<string>();
        }
        var lines = File.ReadAllLines(output, Encoding.UTF8);
        Assert.Equal(_folder, Encoding.UTF8.GetString(Convert.FromBase64String(lines[0])));
        return lines.Skip(1).Select(line => Encoding.UTF8.GetString(Convert.FromBase64String(line))).ToList();
    }
}

/// <summary>
/// The stub program both door tests start: compiled once per run with the
/// C# compiler every Windows 11 carries (.NET Framework 4.8's), so no project
/// is added to the solution for it. It writes its working folder and each
/// argument it was given, one per line in base64, to the file its
/// environment names, and exits.
/// </summary>
[CollectionDefinition(Name)]
public sealed class StubProgramCollection
{
    public const string Name = "the outside doors' stub program";
    public const string OutputVariable = "PLANTOIR_PROBE_OUTPUT";

    private static readonly Lazy<string> Probe = new(Compile);

    public static string ProbeExe => Probe.Value;

    private static string Compile()
    {
        string csc = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                                  "Microsoft.NET", "Framework64", "v4.0.30319", "csc.exe");
        if (!File.Exists(csc)) throw new InvalidOperationException($"No C# compiler at {csc}; .NET Framework 4.8 is part of Windows 11.");
        string folder = Directory.CreateTempSubdirectory("plantoir-probe").FullName;
        string source = Path.Combine(folder, "probe.cs"), exe = Path.Combine(folder, "probe.exe");
        File.WriteAllText(source, """
            using System; using System.IO; using System.Text;
            class Probe { static int Main(string[] args) {
                string output = Environment.GetEnvironmentVariable("PLANTOIR_PROBE_OUTPUT");
                var text = new StringBuilder();
                text.Append(Convert.ToBase64String(Encoding.UTF8.GetBytes(Environment.CurrentDirectory))).Append("\n");
                foreach (string argument in args) text.Append(Convert.ToBase64String(Encoding.UTF8.GetBytes(argument))).Append("\n");
                File.WriteAllText(output, text.ToString());
                return 0; } }
            """);
        var info = new ProcessStartInfo(csc, $"-nologo -out:\"{exe}\" \"{source}\"")
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true,
        };
        using var process = Process.Start(info)!;
        string said = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        if (!File.Exists(exe)) throw new InvalidOperationException("The stub did not compile: " + said);
        return exe;
    }
}

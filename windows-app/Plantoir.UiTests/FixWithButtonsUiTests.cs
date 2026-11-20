using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// Fix with Claude… and Fix with Codex… under a section's Problems table
/// (#736), driven through the real window, with the doors pointed at STUB
/// programs: a <c>claude.exe</c> and an npm-shaped <c>codex.cmd</c> first on
/// the driven app's PATH, which write down the argument vector they were
/// given and exit — so a press opens a console window for a moment and starts
/// no real assistant. What no unit test can see: that the buttons are under
/// the table, reachable by Tab, named, greyed with a reason Narrator can read
/// when nothing is ticked, absent on a course kept for reference — and that a
/// press hands a course with a hostile name to Windows' real start
/// (ShellExecute, a new console) and the message arrives as ONE argument,
/// exactly the message <see cref="FixWithAssistant"/> made. The rules are
/// pinned by <c>FixWithAssistantContractTests</c> and <c>OutsideDoorTests</c>.
/// </summary>
[Collection("drives the real app")]
public class FixWithButtonsUiTests
{
    private const string Code = "MPM2D", Reference = "MPM1D";

    /// <summary>A hostile course name: cmd's metacharacters, variables, delayed expansion, Windows Terminal's tab separator, a quote, text that is not ASCII.</summary>
    private const string HostileName = "Maths & <Co> | ^x %OS% !x! (a); \"q\" é 🎓";

    private static readonly UTF8Encoding Utf8 = new(false);

    [UiFact]
    public void TheButtonsFollowTheTicks_AndAPressHandsTheMessageOverWhole()
    {
        string stubs = Directory.CreateTempSubdirectory("plantoir-fix-stubs").FullName;
        string output = Path.Combine(stubs, "argv.txt");
        string probe = Probe(stubs);
        File.Copy(probe, Path.Combine(stubs, "claude.exe"));
        File.Copy(probe, Path.Combine(stubs, "node.exe"));
        File.WriteAllText(Path.Combine(stubs, "cli.js"), "");
        // npm's shape where it matters — %* parsed by cmd a second time — and
        // an exit, so the window the door's cmd /k opens closes again.
        File.WriteAllText(Path.Combine(stubs, "codex.cmd"), "@\"%~dp0node.exe\" \"%~dp0cli.js\" %*\r\n@exit\r\n");

        string? oldPath = Environment.GetEnvironmentVariable("PATH");
        string? oldOutput = Environment.GetEnvironmentVariable("PLANTOIR_PROBE_OUTPUT");
        // ShellExecute hands this process's environment to the app it starts.
        Environment.SetEnvironmentVariable("PATH", stubs + Path.PathSeparator + oldPath);
        Environment.SetEnvironmentVariable("PLANTOIR_PROBE_OUTPUT", output);
        string recordJson = "";
        try
        {
            using var app = new DrivenApp(courses =>
            {
                EndToEnd.WriteCourse(courses, Code, HostileName, new[] { "Concepts" });
                EndToEnd.WriteCourse(courses, Reference, "Last year", new[] { "Concepts" },
                                     config => { config["kept_for_reference"] = true; config["reference_school_year"] = 2025; });
            }, beforeLaunch: workspace =>
            {
                recordJson = SeededRecord(Code, "FIX-ONE");
                Seed(workspace, Code, recordJson);
                Seed(workspace, Reference, SeededRecord(Reference, "FIX-REF"));
                var kept = ProblemsAcknowledgements.Read(workspace);
                kept.RememberAnswered("FIX-ONE", Code, 1);
                kept.RememberAnswered("FIX-REF", Reference, 1);
                kept.Write(workspace);
            });

            // A course kept for reference: the tab, and no button at all.
            app.SelectSection(Reference, 1);
            OpenTheProblemsTab(app);
            Assert.NotNull(app.FindOrNull("problemsTable", TimeSpan.FromSeconds(10)));
            Thread.Sleep(1500);
            Assert.False(Showing(app, "fixWithClaudeButton"), "no Fix with Claude on a course kept for reference");
            Assert.False(Showing(app, "fixWithCodexButton"), "no Fix with Codex on a course kept for reference");

            app.SelectSection(Code, 1);
            OpenTheProblemsTab(app);
            var claude = Wait(app, "fixWithClaudeButton");
            var codex = Wait(app, "fixWithCodexButton");
            Assert.Equal(FixWithAssistant.ClaudeButtonTitle, claude.Name);
            Assert.Equal(FixWithAssistant.CodexButtonTitle, codex.Name);
            Assert.True(claude.IsEnabled && codex.IsEnabled, "every row starts ticked, so both can be pressed");
            Assert.True(claude.BoundingRectangle.Left < codex.BoundingRectangle.Left, "Claude's first");
            Assert.True(claude.BoundingRectangle.Top > app.Find("problemsTable", "the table").BoundingRectangle.Bottom - 1, "under the table");

            // Tab from the table reaches the buttons.
            app.ClickMiddleOf(app.Find("problemRow-pageSettingsUnreadable|Unit 1/Lesson 1", "the first row"));
            Keyboard.Type(VirtualKeyShort.SPACE);   // unticks it
            string? reached = null;
            for (int press = 0; press < 6 && reached is null; press++)
            {
                Keyboard.Type(VirtualKeyShort.TAB);
                Thread.Sleep(150);
                string focused = app.Window.Automation.FocusedElement()?.AutomationId ?? "";
                if (focused is "fixWithClaudeButton" or "fixWithCodexButton") reached = focused;
            }
            Assert.Equal("fixWithClaudeButton", reached);

            // Untick the other: nothing is handed over, both greyed, and say why.
            app.Find("problemTick-pageSettingsUnreadable|Unit 1/Lesson 2", "the second tick").AsCheckBox().Toggle();
            foreach (int lesson in new[] { 1, 2 })
            {
                var box = app.Find($"problemTick-pageSettingsUnreadable|Unit 1/Lesson {lesson}", "a tick").AsCheckBox();
                if (box.IsChecked == true) box.Toggle();
            }
            Assert.True(Retry.WhileFalse(() => !Wait(app, "fixWithClaudeButton").IsEnabled, TimeSpan.FromSeconds(5)).Result,
                        "with nothing ticked the buttons cannot be pressed; ticks: " + string.Join(", ", new[] { 1, 2 }.Select(lesson =>
                            app.Find($"problemTick-pageSettingsUnreadable|Unit 1/Lesson {lesson}", "a tick").AsCheckBox().IsChecked)));
            Assert.Equal(FixWithAssistant.NotEnabledHelp, Wait(app, "fixWithClaudeButton").HelpText);
            Assert.Equal(FixWithAssistant.NotEnabledHelp, Wait(app, "fixWithCodexButton").HelpText);
            Assert.True(Showing(app, "fixWithClaudeButton"), "greyed, never hidden, when nothing is ticked");

            // Tick both again and press each door.
            app.Find("problemTick-pageSettingsUnreadable|Unit 1/Lesson 1", "the first tick").AsCheckBox().Toggle();
            app.Find("problemTick-pageSettingsUnreadable|Unit 1/Lesson 2", "the second tick").AsCheckBox().Toggle();
            Assert.True(Retry.WhileFalse(() => Wait(app, "fixWithClaudeButton").IsEnabled, TimeSpan.FromSeconds(5)).Result);

            var record = SectionProblemsRecord.Parse(recordJson)!;
            string expected = FixWithAssistant.GreetingFor(record.Rows, Code, HostileName, 1, "preview")!.Text;

            Wait(app, "fixWithClaudeButton").AsButton().Invoke();
            var claudeArgv = Arrived(output);
            Assert.Equal(4, claudeArgv.Count);
            Assert.Equal("--mcp-config", claudeArgv[0]);
            Assert.Equal("--strict-mcp-config", claudeArgv[2]);
            Assert.Equal(expected, claudeArgv[3]);

            Wait(app, "fixWithCodexButton").AsButton().Invoke();
            var codexArgv = Arrived(output);
            Assert.EndsWith("cli.js", codexArgv[0]);
            Assert.Equal(12, codexArgv.Count);
            Assert.Equal(expected, codexArgv[^1]);

            string trail = File.ReadAllText(Path.Combine(app.StateDirectory, "Logs", "activity.txt"));
            Assert.Contains($"{Code}/1 · asked Claude to fix 2 problems (pageSettingsUnreadable); named in the message: 2; left out: 0 unticked, 0 fixed in the source", trail);
            Assert.Contains($"{Code}/1 · asked Codex to fix 2 problems", trail);
            Assert.DoesNotContain("Lesson 1", trail);
            Console.WriteLine($"MEASURED: a press of each door handed a {expected.Length}-unit message with the course named \"{HostileName}\" over whole.");
        }
        finally
        {
            Environment.SetEnvironmentVariable("PATH", oldPath);
            Environment.SetEnvironmentVariable("PLANTOIR_PROBE_OUTPUT", oldOutput);
            try { Directory.Delete(stubs, recursive: true); } catch { }
        }
    }

    // ---- Helpers ------------------------------------------------------------------

    private static void OpenTheProblemsTab(DrivenApp app)
    {
        Assert.True(Retry.WhileFalse(() => Showing(app, "sectionTabProblems"), TimeSpan.FromSeconds(15)).Result, "the tab bar shows");
        app.ClickMiddleOf(app.Find("sectionTabProblems", "the Problems tab"));
    }

    private static AutomationElement Wait(DrivenApp app, string id) =>
        app.FindOrNull(id, TimeSpan.FromSeconds(10)) ?? throw new Xunit.Sdk.XunitException($"{id} never appeared");

    private static bool Showing(DrivenApp app, string id)
    {
        try { return app.FindOrNull(id, TimeSpan.FromMilliseconds(300)) is { } found && !found.IsOffscreen; }
        catch { return false; }
    }

    /// <summary>What the stub wrote, once it has: its working folder first, then each argument.</summary>
    private static List<string> Arrived(string output)
    {
        Assert.True(Retry.WhileFalse(() => File.Exists(output), TimeSpan.FromSeconds(20)).Result, "the door started nothing");
        string[] lines = Array.Empty<string>();
        Retry.WhileFalse(() =>
        {
            try { lines = File.ReadAllLines(output); return lines.Length > 0; } catch { return false; }
        }, TimeSpan.FromSeconds(5));
        File.Delete(output);
        return lines.Skip(1).Select(line => Encoding.UTF8.GetString(Convert.FromBase64String(line))).ToList();
    }

    private static string SeededRecord(string course, string alertKey)
    {
        var now = DateTime.UtcNow;
        var rows = new JsonArray();
        for (int lesson = 1; lesson <= 2; lesson++)
        {
            string place = $"Unit 1/Lesson {lesson}";
            rows.Add(new JsonObject
            {
                ["id"] = $"pageSettingsUnreadable|{place}", ["kind"] = "pageSettingsUnreadable", ["page"] = place,
                ["reason"] = "", ["item"] = $"“{place}”",
                ["sentence"] = $"The settings at the top of “{place}” in {course} Section 1 could not be read.",
                ["detail"] = "Check the lines between the two --- lines.", ["fixable"] = false,
                ["prompt"] = $"The settings at the top of “{place}” could not be read: 100% & <done>.",
                ["from"] = "build",
                ["firstSeen"] = now.ToString("yyyy-MM-ddTHH:mm:ssZ"), ["lastSeen"] = now.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            });
        }
        return new JsonObject
        {
            ["version"] = 1, ["course"] = course, ["section"] = 1, ["buildId"] = alertKey,
            ["builtAt"] = now.ToString("yyyy-MM-ddTHH:mm:ssZ"), ["occasion"] = "preview",
            ["pagesShown"] = new JsonArray(), ["before"] = new JsonArray(), ["siteSaidComplete"] = true, ["alertKey"] = alertKey,
            ["changed"] = new JsonObject { ["new"] = new JsonArray(), ["gone"] = new JsonArray() },
            ["rows"] = rows,
        }.ToJsonString();
    }

    private static void Seed(string workspace, string course, string json)
    {
        string path = SectionProblemsRecord.PathFor(
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir", "builds",
                         FolderContainers.FolderIdentifier(workspace)), course, 1);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, json, Utf8);
    }

    /// <summary>The stub program: compiled with the C# compiler Windows carries; writes its folder and argv, in base64, to PLANTOIR_PROBE_OUTPUT.</summary>
    private static string Probe(string folder)
    {
        string csc = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                                  "Microsoft.NET", "Framework64", "v4.0.30319", "csc.exe");
        string source = Path.Combine(folder, "probe.cs"), exe = Path.Combine(folder, "probe.exe");
        File.WriteAllText(source, """
            using System; using System.IO; using System.Text;
            class Probe { static int Main(string[] args) {
                var text = new StringBuilder();
                text.Append(Convert.ToBase64String(Encoding.UTF8.GetBytes(Environment.CurrentDirectory))).Append("\n");
                foreach (string argument in args) text.Append(Convert.ToBase64String(Encoding.UTF8.GetBytes(argument))).Append("\n");
                File.WriteAllText(Environment.GetEnvironmentVariable("PLANTOIR_PROBE_OUTPUT"), text.ToString());
                return 0; } }
            """);
        using var process = Process.Start(new ProcessStartInfo(csc, $"-nologo -out:\"{exe}\" \"{source}\"")
                                          { UseShellExecute = false, CreateNoWindow = true })!;
        process.WaitForExit();
        Assert.True(File.Exists(exe), "the stub did not compile");
        return exe;
    }
}

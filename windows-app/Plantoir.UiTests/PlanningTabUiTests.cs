using System.Diagnostics;
using System.Text;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// The course page's Settings | Planning tabs (#801, #820), driven through the
/// real window with the outside doors pointed at STUB programs (a
/// <c>claude.exe</c> and an npm-shaped <c>codex.cmd</c> first on PATH, as
/// <see cref="FixWithButtonsUiTests"/> has them): what no unit test can see.
/// The tabs are there and named; switching to Planning while a settings box
/// has the keyboard leaves no setting reachable and loses nothing typed;
/// Course ▸ Save on Planning saves and says so beside the tabs; the plan is
/// SHOWN from the planning folder, the popup follows a link, a link out of the
/// planning folder is refused; Open in Browser hands the page to the default
/// browser (recorded in <c>browser-opened.txt</c> in this redirected run,
/// nothing started); Plan a Unit opens the door with the contract's message;
/// Revise With ▸ Claude… names the plans. Every word read is the contract's,
/// through Core's constants (pinned to the contract by the unit suite).
/// </summary>
[Collection("drives the real app")]
public class PlanningTabUiTests
{
    private const string Code = "SNC2D", Name = "Grade 10 Science", Empty = "SPH3U";

    [UiFact]
    public void ThePlanningTabShowsThePlanAndKeepsSettingsOutOfReach()
    {
        string stubs = Directory.CreateTempSubdirectory("plantoir-plan-stubs").FullName;
        string output = Path.Combine(stubs, "argv.txt");
        string probe = Probe(stubs);
        File.Copy(probe, Path.Combine(stubs, "claude.exe"));
        File.Copy(probe, Path.Combine(stubs, "node.exe"));
        File.WriteAllText(Path.Combine(stubs, "cli.js"), "");
        File.WriteAllText(Path.Combine(stubs, "codex.cmd"), "@\"%~dp0node.exe\" \"%~dp0cli.js\" %*\r\n@exit\r\n");

        string? oldPath = Environment.GetEnvironmentVariable("PATH");
        string? oldOutput = Environment.GetEnvironmentVariable("PLANTOIR_PROBE_OUTPUT");
        Environment.SetEnvironmentVariable("PATH", stubs + Path.PathSeparator + oldPath);
        Environment.SetEnvironmentVariable("PLANTOIR_PROBE_OUTPUT", output);
        string courseDirectory = "";
        try
        {
            using var app = new DrivenApp(courses =>
            {
                courseDirectory = EndToEnd.WriteCourse(courses, Code, Name, new[] { "Concepts" });
                EndToEnd.WriteCourse(courses, Empty, "Physics", new[] { "Concepts" });
                WritePlans(Path.Combine(courses, Code));
            });
            string planning = UnitPlans.PlanningFolder(Path.Combine(app.WorkspacePath, "courses", Code));
            var look = PlanningTab.LookIn(planning, Path.Combine(app.WorkspacePath, "courses", Code));
            Assert.Equal(3, look.Choices.Count);

            app.SelectCourse(Code);
            var planningTab = Wait(app, "courseTabPlanning", TimeSpan.FromSeconds(20));
            Assert.Equal(PlanningTabWording.TabPlanning, planningTab.Name);
            Assert.Equal(PlanningTabWording.TabSettings, Wait(app, "courseTabSettings").Name);

            // A setting has the keyboard and something typed; Planning is chosen
            // WITHOUT a click (a click would move the keyboard first: 790 plan
            // review M3), and nothing typed then can reach Settings.
            var nameField = Wait(app, "courseNameField").AsTextBox();
            nameField.Focus();
            nameField.Text = Name + " edited";
            Thread.Sleep(300);
            planningTab.Patterns.SelectionItem.Pattern.Select();
            Assert.True(Retry.WhileFalse(() => app.FindOrNull("planningUnitPopup", TimeSpan.FromMilliseconds(300)) is { IsOffscreen: false },
                                         TimeSpan.FromSeconds(20)).Result, "the plan's bar never showed");
            var settingsIds = new HashSet<string> { "courseNameField", "courseSettingsForm", "saveButton", "revertButton", "folderNotice" };
            for (int press = 0; press < 30; press++)
            {
                Keyboard.Type(VirtualKeyShort.TAB);
                Thread.Sleep(80);
                string focused = app.Window.Automation.FocusedElement()?.AutomationId ?? "";
                Assert.DoesNotContain(focused, settingsIds);
            }
            Assert.False(app.FindOrNull("courseSettingsForm", TimeSpan.FromMilliseconds(500)) is { IsOffscreen: false },
                         "the settings form is still drawn under Planning");
            // A key typed on Planning reaches no setting. (Undo in WinUI lives in
            // each box, and no box can have the keyboard here: nothing to undo.)
            Keyboard.Type("x");
            Thread.Sleep(300);

            // Course ▸ Save on Planning saves what was typed, and says so here.
            EndToEnd.PressMenuBarItem(app, "Course", "courseSaveSettings");
            string config = Path.Combine(app.WorkspacePath, "courses", Code, "course_config.json");
            string? saved = null;
            Assert.True(Retry.WhileFalse(() =>
            {
                try { saved = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(config))?["course_name"]?.ToString(); } catch { }
                return saved?.StartsWith(Name + " edited") == true;
            }, TimeSpan.FromSeconds(10)).Result, "Save on Planning wrote nothing");
            Assert.Equal(Name + " edited", saved);
            Assert.StartsWith("Saved", Wait(app, "planningSaveStatus").Name);
            Assert.True(app.FindOrNull("planningUnitPopup", TimeSpan.FromSeconds(2)) is { IsOffscreen: false }, "a plain save stays on Planning");

            // The bar's words, and the page: All Plans (no unit covers today).
            var popup = Wait(app, "planningUnitPopup");
            Assert.Equal(PlanningTabWording.UnitPopup, popup.Name);
            Assert.Equal(PlanningTabWording.AllPlans, popup.ItemStatus);
            Assert.Equal(PlanningTabWording.Back, Wait(app, "planningBack").Name);
            Assert.Equal(PlanningTabWording.Forward, Wait(app, "planningForward").Name);
            Assert.Equal(PlanningTabWording.Reload, Wait(app, "planningReload").Name);
            Assert.Equal(PlanningTabWording.OpenInBrowser, Wait(app, "planningOpenInBrowser").Name);
            WaitForPage(app, "planning/index.html");
            var web = Wait(app, "planningWebView");
            Assert.True(web.BoundingRectangle.Top >= planningTab.BoundingRectangle.Bottom, "the plan is under the tabs");
            Assert.True(web.BoundingRectangle.Bottom <= app.Window.BoundingRectangle.Bottom + 1, "a tall plan scrolls inside its view (#838)");

            // Open in Browser: the page on screen, handed to the https: browser.
            Assert.Equal(PlanningTabWording.OpenInBrowserHelp, Wait(app, "planningOpenInBrowser").HelpText);
            Wait(app, "planningOpenInBrowser").AsButton().Invoke();
            string opened = Path.Combine(app.StateDirectory, WindowsDefaultBrowser.OpenedFileName);
            Assert.True(Retry.WhileFalse(() => File.Exists(opened), TimeSpan.FromSeconds(10)).Result, "nothing was handed to the browser");
            Assert.EndsWith("| " + new Uri(Path.Combine(planning, "index.html")).AbsoluteUri, File.ReadAllLines(opened).Last());

            // A link to a unit: the popup follows the page.
            app.ClickMiddleOf(web);
            WaitForPage(app, "unit-1-cells/index.html");
            Assert.True(Retry.WhileFalse(() => Wait(app, "planningUnitPopup").ItemStatus
                                               == PlanningTab.TitleFor(PlanningTab.Choice.Unit("unit-1-cells"), look.Plans),
                                         TimeSpan.FromSeconds(5)).Result, "the popup did not follow the page");

            // A link out of the planning folder: refused, the page stays.
            app.ClickMiddleOf(Wait(app, "planningWebView"));
            Thread.Sleep(2000);
            WaitForPage(app, "unit-1-cells/index.html");

            // Back returns; the popup chooses another unit.
            Wait(app, "planningBack").AsButton().Invoke();
            WaitForPage(app, "planning/index.html");
            Wait(app, "planningUnitPopup").AsButton().Invoke();
            var second = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("planningUnit2")), TimeSpan.FromSeconds(5)).Result;
            Assert.NotNull(second);
            DrivenApp.PressMenuItem(second!);
            WaitForPage(app, "unit-2-forces/index.html");

            // Revise With ▸ Claude… on this course names its plans.
            EndToEnd.PressMenuBarItem(app, "Course", "courseReviseWith");
            var reviseClaude = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("courseReviseWithClaude")),
                                               TimeSpan.FromSeconds(5)).Result;
            Assert.NotNull(reviseClaude);
            DrivenApp.PressMenuItem(reviseClaude!);
            var revise = Arrived(output);
            Assert.EndsWith(UnitPlans.GreetingSentence(UnitPlans.Read(Path.Combine(app.WorkspacePath, "courses", Code)).Plans), revise[^1]);

            // A course with no plans: the offer, and Plan a Unit opens the door with the message.
            app.SelectCourse(Empty);
            Wait(app, "courseTabPlanning", TimeSpan.FromSeconds(20)).Patterns.SelectionItem.Pattern.Select();
            Assert.Equal(PlanningTabWording.EmptyTitle, Wait(app, "planningEmptyTitle", TimeSpan.FromSeconds(20)).Name);
            Assert.Equal(PlanningTabWording.EmptyDescription, Wait(app, "planningEmptyDescription").Name);
            var claude = Wait(app, "planAUnitWithClaude");
            var codex = Wait(app, "planAUnitWithCodex");
            Assert.Equal(PlanAUnit.ClaudeButtonTitle, claude.Name);
            Assert.Equal(PlanAUnit.CodexButtonTitle, codex.Name);
            Assert.True(claude.BoundingRectangle.Left < codex.BoundingRectangle.Left, "Claude's first");
            claude.AsButton().Invoke();
            var plan = Arrived(output);
            Assert.Equal(PlanAUnit.OpeningMessage(Empty, "Physics"), plan[^1]);

            string trail = File.ReadAllText(Path.Combine(app.StateDirectory, "Logs", "activity.txt"));
            Assert.Contains(PlanningTab.OpenedTrailText(Code, look.Choices), trail);
            Assert.Contains(PlanningTab.OpenedTrailText(Empty, Array.Empty<PlanningTab.Choice>()), trail);
            Assert.Contains(PlanInTheBrowser.TrailText(Code, PlanInTheBrowser.Kind.AllPlans), trail);
            Assert.Contains(PlanAUnit.TrailText(Empty, FixWithAssistant.Assistant.Claude), trail);
            Assert.Contains(" · reminded of 2 unit plans", trail);
            Assert.DoesNotContain("Cells", trail);
        }
        finally
        {
            Environment.SetEnvironmentVariable("PATH", oldPath);
            Environment.SetEnvironmentVariable("PLANTOIR_PROBE_OUTPUT", oldOutput);
            try { Directory.Delete(stubs, recursive: true); } catch { }
        }
    }

    // ---- Helpers ------------------------------------------------------------------

    /// <summary>Two dated units long past (so none covers today and the tab starts on All Plans), each page a link at full size.</summary>
    private static void WritePlans(string course)
    {
        string planning = UnitPlans.PlanningFolder(course);
        static string Link(string href, string text) =>
            "<!doctype html><title>" + text + "</title><body style='margin:0'>"
            + $"<a href='{href}' style='display:block;width:100vw;height:100vh;background:#ddd'>{text}</a></body>";
        void Write(string relative, string text)
        {
            string path = Path.Combine(planning, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, text, new UTF8Encoding(false));
        }
        Write("index.html", Link("unit-1-cells/index.html", "All of the plans"));
        Write(@"unit-1-cells\plan.json", "{\"unit\": \"Unit 1\", \"title\": \"Cells\", \"firstClass\": \"2001-02-05\", \"lastClass\": \"2001-02-16\"}");
        Write(@"unit-1-cells\index.html", Link("../../../course_config.json", "Unit 1"));
        Write(@"unit-2-forces\plan.json", "{\"unit\": \"Unit 2\", \"title\": \"Forces\", \"firstClass\": \"2001-03-05\", \"lastClass\": \"2001-03-16\"}");
        Write(@"unit-2-forces\index.html", Link("../index.html", "Unit 2"));
    }

    /// <summary>Waits for the view to be on a page whose address ends <paramref name="ending"/> (Reload's ItemStatus in a redirected run).</summary>
    private static void WaitForPage(DrivenApp app, string ending)
    {
        string seen = "";
        bool there = Retry.WhileFalse(() =>
        {
            seen = app.FindOrNull("planningReload", TimeSpan.FromMilliseconds(300))?.ItemStatus ?? "";
            return seen.EndsWith(ending, StringComparison.OrdinalIgnoreCase);
        }, TimeSpan.FromSeconds(20)).Result;
        Assert.True(there, $"the plan view never showed {ending}; it was on {seen}");
    }

    private static AutomationElement Wait(DrivenApp app, string id, TimeSpan? within = null) =>
        app.FindOrNull(id, within ?? TimeSpan.FromSeconds(10)) ?? throw new Xunit.Sdk.XunitException($"{id} never appeared");

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

    /// <summary>The stub program (FixWithButtonsUiTests' own): writes its folder and argv, in base64, to PLANTOIR_PROBE_OUTPUT.</summary>
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

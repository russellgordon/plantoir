using System.Text;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #641: a driven run writes nothing to this PC's REAL trail
/// (<c>%LOCALAPPDATA%\Plantoir\Logs\activity.txt</c>). Two writers used to
/// reach it although the app was started with <c>--state-dir</c>: the
/// harness's OWN process, whose in-process set-up of the working folder
/// writes "got the working folder ready", and the window's
/// <c>plantoir-mcp</c>, which was never handed the state folder. This drives
/// both: a fresh working folder (a copy that changes files, so the line is
/// written) and Section ▸ Publish Pages…, whose backup line is the server's.
///
/// <para><b>Judged by content, not by byte count alone.</b> This PC is
/// shared: Russell's own copy, another session's run or a scheduled publish
/// may append to the real trail while this runs, and that is not this
/// test's to fail. So it fails on an ADDED line naming this run's temporary
/// folder or this test's course code, both unique to the run, and prints
/// anything else added for information.</para>
///
/// <para>Not covered, deliberately: the launchers' own refusal lines
/// (<c>Write-TrailLine</c> in <c>preview.ps1</c>/<c>deploy.ps1</c>) still use
/// the real <c>%LOCALAPPDATA%</c>. That is a toolchain change on both
/// platforms and is #664; nothing here triggers a refusal.</para>
/// </summary>
[Collection("drives the real app")]
public class RealTrailUntouchedUiTests
{
    private readonly ITestOutputHelper _output;
    public RealTrailUntouchedUiTests(ITestOutputHelper output) => _output = output;

    private static long LengthOf(string path)
    {
        try { return new FileInfo(path).Exists ? new FileInfo(path).Length : 0; }
        catch { return 0; }
    }

    private static string AddedSince(string path, long offset)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length <= offset) return "";
            stream.Seek(offset, SeekOrigin.Begin);
            using var reader = new StreamReader(stream, Encoding.UTF8);
            return reader.ReadToEnd();
        }
        catch (FileNotFoundException) { return ""; }
        catch (DirectoryNotFoundException) { return ""; }
    }

    private static AutomationElement WaitFor(DrivenApp app, string automationId, string what) =>
        Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
                        TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result
        ?? throw new Xunit.Sdk.XunitException($"{what} never appeared ({automationId}).");

    private static void Press(DrivenApp app, string buttonId, string what)
    {
        var dialog = MenuBar.Dialog(app, what);
        var button = Retry.WhileNull(() => dialog.FindFirstDescendant(cf => cf.ByAutomationId(buttonId)),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result
                     ?? throw new Xunit.Sdk.XunitException($"{what} has no {buttonId}");
        Assert.True(Retry.WhileFalse(() => button.IsEnabled, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"{what}: {buttonId} never became available");
        button.AsButton().Invoke();
    }

    [UiFact]
    public void ADrivenRunWritesNothingToTheRealTrail()
    {
        string real = DrivenApp.RealTrailPath;
        long before = LengthOf(real);
        // Unique to this run, so a line carrying it can only be ours. Not
        // EndToEnd.Marker itself: a course code is at most twelve characters
        // (course-management.json -> courseCode.mostCharacters).
        string code = "UIT" + Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();
        string runFolder;

        using (var app = new DrivenApp(courses =>
        {
            EndToEnd.WriteCourse(courses, code, "Trail Course", new[] { "Concepts" });
            EndToEnd.WritePage(Path.Combine(courses, code, "section1", "All Classes", "Unit 1, Day 1.md"),
                               "title: Unit 1, Day 1\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400", "A class.");
        }))
        {
            runFolder = app.RunFolderName;

            // Writer 1, the harness's own copy: the line exists, in THIS run's trail.
            string own = MenuBar.Trail(app);
            Assert.Contains("got the working folder ready", own);
            Assert.Contains(runFolder, own);

            // Writer 2, the window's plantoir-mcp: Publish Pages… backs the
            // course up first, and the server writes that line.
            app.SelectSection(code, 1);
            EndToEnd.PressMenuBarItem(app, "Section", "sectionPublishPages");
            WaitFor(app, "sectionVerbPage0", "the checklist's first page").AsCheckBox().Toggle();
            Press(app, "PrimaryButton", "Publish Pages… (Continue)");
            WaitFor(app, "sectionVerbPlan", "the plan");
            Press(app, "PrimaryButton", "Publish Pages… (Publish)");
            _output.WriteLine("result: " + WaitFor(app, "sectionVerbResult", "what Publish did").Name);
            MenuBar.CloseDialog(app);
            Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Contains($"{code}/1 · the Section menu backed up the course"),
                                         TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result,
                        "the server's backup line never reached this run's own trail");
        }

        string added = AddedSince(real, before);
        var ours = new List<string>();
        var others = new List<string>();
        foreach (string line in added.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            if (line.Contains(runFolder, StringComparison.OrdinalIgnoreCase) || line.Contains(code, StringComparison.Ordinal))
                ours.Add(line.TrimEnd('\r'));
            else
                others.Add(line.TrimEnd('\r'));
        }
        foreach (string line in others)
            _output.WriteLine("added to the real trail by something else during the run (information only): " + line);
        Assert.True(ours.Count == 0,
                    $"This run wrote {ours.Count} line(s) to the REAL trail ({real}):\n" + string.Join("\n", ours));
    }
}

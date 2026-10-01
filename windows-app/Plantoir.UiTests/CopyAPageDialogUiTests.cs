using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>
/// Copy a Page's checklist fits on the screen (#384, mac #365): eleven rows and
/// seventy per-page sentences, at the smallest window height, scroll as ONE
/// region — the buttons stay on screen, and the region has neither grown past
/// its ceiling nor collapsed to nothing (a size test asserting only a maximum
/// passes when the region has collapsed to zero height).
/// </summary>
/// <remarks>
/// Nothing is copied: the test presses Cancel on the checklist, before the
/// backup or any write. The fixture is two ordinary courses in a
/// <c>--state-dir</c> working folder.
/// </remarks>
[Collection("drives the real app")]
public class CopyAPageDialogUiTests
{
    private const string Source = "CPS1";
    private const string Destination = "CPD1";

    private static void WriteCourses(string coursesDir)
    {
        var utf8 = new UTF8Encoding(false);
        foreach (string code in new[] { Source, Destination })
        {
            string dir = Path.Combine(coursesDir, code);
            Directory.CreateDirectory(Path.Combine(dir, "Concepts"));
            Directory.CreateDirectory(Path.Combine(dir, "section1"));
            var config = new JsonObject
            {
                ["course_code"] = code, ["course_name"] = code,
                ["shared_folders"] = new JsonArray("Concepts"), ["per_section_folders"] = new JsonArray("All Classes"),
                ["shared_files"] = new JsonArray(), ["per_section_files"] = new JsonArray(),
                ["num_sections"] = 1, ["section_numbers"] = new JsonArray(1),
            };
            File.WriteAllText(Path.Combine(dir, "course_config.json"), config.ToJsonString(), utf8);
            File.WriteAllText(Path.Combine(dir, "section1", "index.md"), $"# {code}\n", utf8);
        }
        string source = Path.Combine(coursesDir, Source);
        var body = new StringBuilder("# Big\n");
        for (int page = 1; page <= 10; page++)
        {
            File.WriteAllText(Path.Combine(source, "Concepts", $"Linked {page}.md"), "Body\n", utf8);
            body.Append($"[[Linked {page}]]\n");
        }
        // Seventy root pages: each one a "sits outside the course's folders" sentence.
        for (int page = 1; page <= 70; page++)
        {
            File.WriteAllText(Path.Combine(source, $"Root {page}.md"), "Body\n", utf8);
            body.Append($"[[Root {page}]]\n");
        }
        File.WriteAllText(Path.Combine(source, "Concepts", "Big.md"), body.ToString(), utf8);
    }

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);

    [UiFact]
    public void CheckListAndSentencesScrollAsOne()
    {
        using var app = new DrivenApp(WriteCourses);
        var window = app.Window;
        // The smallest height the window allows: asked for 100, given its minimum.
        window.Patterns.Transform.Pattern.Resize(1100, 100);
        double scale = GetDpiForWindow(window.Properties.NativeWindowHandle.Value) / 96.0;

        var row = app.Find("sidebar-" + Source, $"the sidebar entry for {Source}");
        row.RightClick();
        var item = Retry.WhileNull(() => app.Window.Automation.GetDesktop()
                .FindFirstDescendant(cf => cf.ByName("Copy a Page from This Course…")),
            TimeSpan.FromSeconds(8), TimeSpan.FromMilliseconds(200)).Result;
        Assert.True(item is not null, "the course row's menu offers Copy a Page");
        item!.Click();

        var picker = app.Find("copyPagePicker", "the page picker");
        picker.Click();
        Keyboard.Type("Big");
        Thread.Sleep(500);
        Keyboard.Press(VirtualKeyShort.DOWN);
        Keyboard.Press(VirtualKeyShort.ENTER);

        var copy = app.Find(CopyAPageDialogIds.Primary, "the Copy button").AsButton();
        Assert.True(Retry.WhileFalse(() => copy.IsEnabled, TimeSpan.FromSeconds(5)).Result, "Copy is offered once a page is chosen");
        copy.Invoke();

        Assert.True(app.FindOrNull("copyPageRow:Linked 10", TimeSpan.FromSeconds(10)) is not null, "the checklist lists the linked pages");
        var scroll = app.Find(CopyAPageDialogIds.Scroll, "the checklist's scroll region");
        var close = app.Find(CopyAPageDialogIds.Close, "Cancel");
        var windowBox = window.BoundingRectangle;

        foreach (var button in new[] { copy, close.AsButton() })
        {
            var box = button.BoundingRectangle;
            Assert.False(button.IsOffscreen, $"{button.Name} is off screen");
            Assert.True(box.Bottom <= windowBox.Bottom && box.Top >= windowBox.Top, $"{button.Name} at {box} is outside the window {windowBox}");
        }
        double height = scroll.BoundingRectangle.Height / scale;
        Assert.True(height >= 120, $"the scroll region collapsed to {height:0} epx");
        Assert.True(height <= 380 + 2, $"the scroll region grew to {height:0} epx, past its ceiling");
        var texts = DrivenApp.TextsUnder(scroll);
        Assert.True(texts.Count(t => t.Contains("sits outside the course", StringComparison.Ordinal)) >= 70,
            "the seventy sentences are inside the one scroll region");

        close.AsButton().Invoke();   // nothing copied, nothing backed up
        Assert.False(File.Exists(Path.Combine(app.WorkspacePath, "courses", Destination, "Concepts", "Big.md")));
    }
}

/// <summary>The dialog's automation ids, spelled once for the tests.</summary>
internal static class CopyAPageDialogIds
{
    public const string Primary = "copyPagePrimary";
    public const string Close = "copyPageClose";
    public const string Scroll = "copyPageScroll";
}

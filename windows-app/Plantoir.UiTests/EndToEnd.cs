using System.Net.Http;
using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;

namespace Plantoir.UiTests;

/// <summary>
/// What the end-to-end tests (bundle 11) share: the contract's sentences read
/// rather than retyped, courses written as a teacher would have them, the
/// served preview and the published folder READ BACK rather than trusted from
/// a label, and the system folder picker driven like any other window.
/// </summary>
internal static class EndToEnd
{
    // ---- The contract, deserialised (ruling U3) ---------------------------

    public static JsonNode Contract(string file = "shared-rules.json") =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "contracts", file)))!;

    /// <summary>A sentence from the contract with its {placeholders} filled.</summary>
    public static string Say(JsonNode template, params (string Key, string Value)[] fills)
    {
        string text = template.ToString();
        foreach (var (key, value) in fills) text = text.Replace("{" + key + "}", value);
        return text;
    }

    public static JsonNode CopyPageWording => Contract()["copyingAPageBetweenCourses"]!["wording"]!;
    public static JsonNode ReferenceWording => Contract()["referenceCourses"]!["wording"]!;
    public static JsonNode ImportWording => Contract()["referenceCourses"]!["importing"]!["wording"]!;

    // ---- Courses, written as a teacher would have them --------------------

    private static readonly UTF8Encoding Utf8 = new(false);

    /// <summary>A one-section course with the shared folders named, each made on disk.</summary>
    public static string WriteCourse(string coursesDir, string code, string name, string[] sharedFolders,
                                     Action<JsonObject>? more = null, string? frontPage = null)
    {
        string dir = Path.Combine(coursesDir, code);
        Directory.CreateDirectory(Path.Combine(dir, "section1", "All Classes"));
        Directory.CreateDirectory(Path.Combine(dir, "Media"));
        foreach (string folder in sharedFolders) Directory.CreateDirectory(Path.Combine(dir, folder));
        var config = new JsonObject
        {
            ["course_code"] = code,
            ["course_name"] = name,
            ["num_sections"] = 1,
            ["section_numbers"] = new JsonArray(1),
            ["shared_folders"] = new JsonArray(sharedFolders.Select(f => (JsonNode?)JsonValue.Create(f)).ToArray()),
            ["per_section_folders"] = new JsonArray("All Classes"),
            ["shared_files"] = new JsonArray(),
            ["per_section_files"] = new JsonArray(),
        };
        more?.Invoke(config);
        File.WriteAllText(Path.Combine(dir, "course_config.json"),
            config.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }), Utf8);
        File.WriteAllText(Path.Combine(dir, "section1", "index.md"),
            frontPage ?? $"---\ntitle: {code}\n---\n# {name}\n", Utf8);
        return dir;
    }

    /// <summary>Publish this course to a folder on this PC (the folder must exist, as one a teacher chose would).</summary>
    public static Action<JsonObject> PublishesTo(string folder) => config =>
    {
        config["deploy_target"] = "local_folder";
        config["deploy_folder_path"] = folder;
    };

    public static void WritePage(string path, string frontmatter, string body)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, $"---\n{frontmatter.TrimEnd()}\n---\n{body}\n", Utf8);
    }

    /// <summary>A word no page would contain by accident: what a test greps a built site for.</summary>
    public static string Marker(string what) => $"UIE2E{what}{Guid.NewGuid().ToString("N")[..8]}";

    // ---- Reading a site back ----------------------------------------------

    /// <summary>Every file under a folder whose text contains <paramref name="marker"/>.</summary>
    public static List<string> FilesContaining(string folder, string marker)
    {
        var found = new List<string>();
        if (!Directory.Exists(folder)) return found;
        foreach (string file in Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories))
        {
            string ext = Path.GetExtension(file).ToLowerInvariant();
            if (ext is not (".html" or ".json" or ".xml" or ".txt" or ".js" or ".md")) continue;
            try { if (File.ReadAllText(file).Contains(marker, StringComparison.Ordinal)) found.Add(file); } catch { }
        }
        return found;
    }

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(4) };

    /// <summary>The preview ports a launcher can pick (app-rules.json → previewPorts: from 8081, ten apart, forty blocks).</summary>
    public static IEnumerable<int> PreviewPorts => Enumerable.Range(0, 40).Select(k => 8081 + 10 * k);

    public static HashSet<int> Listening() =>
        IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners().Select(e => e.Port).ToHashSet();

    /// <summary>The address of a preview whose front page carries <paramref name="marker"/>, or null.</summary>
    public static string? ServedFrontPage(string marker)
    {
        var listening = Listening();
        foreach (int port in PreviewPorts.Where(listening.Contains))
        {
            foreach (string host in new[] { "127.0.0.1", "localhost" })
            {
                string url = $"http://{host}:{port}/";
                try
                {
                    string body = Http.GetStringAsync(url).GetAwaiter().GetResult();
                    if (body.Contains(marker, StringComparison.Ordinal)) return url;
                }
                catch { }
            }
        }
        return null;
    }

    public static bool Answers(string url)
    {
        try { using var r = Http.GetAsync(url).GetAwaiter().GetResult(); return true; }
        catch { return false; }
    }

    // ---- The section's own progress view ----------------------------------

    /// <summary>
    /// Press Deploy and wait for its ENDING, answering ordinary dialogs on the
    /// way; fail with the app's own words and the console's tail when the
    /// ending is not "Done".
    /// </summary>
    public static void DeployAndWait(DrivenApp app, TimeSpan within)
    {
        var deploy = app.Find("deployButton", "the Deploy button");
        deploy.AsButton().Invoke();
        // TaskProgressView's own endings; while a leg runs (or sits between
        // its build and its deploy halves) the label is a step, never these.
        string[] endings = { "Done", "Stopped", "Cancelled", "Some destinations failed", "Something went wrong" };
        string phase = "";
        bool ended = app.WaitAnsweringDialogs(() =>
        {
            phase = app.FindOrNull("taskPhaseLabel", TimeSpan.FromMilliseconds(300))?.Name ?? "";
            return endings.Contains(phase);
        }, within);
        if (ended && phase == "Done") return;
        throw new Xunit.Sdk.XunitException(
            (ended ? $"the deploy ended, but not well: the section said \"{phase}\"."
                   : $"the deploy never finished within {within.TotalMinutes} minutes; it last said \"{phase}\".")
            + NewCourseWizardUiTests.Explanation(app) + app.AnsweredSoFar + NewCourseWizardUiTests.ConsoleTail(app));
    }

    // ---- The system folder picker -----------------------------------------

    /// <summary>
    /// Choose <paramref name="folder"/> in the Windows folder picker the app
    /// just opened. It is the common item dialog (class #32770): its folder
    /// box is control 1152 and "Select Folder" is control 1. A full path typed
    /// into the box and Select Folder chooses that folder; on a system where
    /// the first press only navigates INTO it, the second press chooses it.
    /// </summary>
    public static void ChooseInFolderPicker(DrivenApp app, string folder)
    {
        int pid = app.Window.Properties.ProcessId.Value;
        AutomationElement? Picker() =>
            app.Window.FindFirstDescendant(cf => cf.ByClassName("#32770"))
            ?? app.Desktop.FindFirstChild(cf => cf.ByClassName("#32770").And(cf.ByProcessId(pid)));

        var picker = Retry.WhileNull(Picker, TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(300)).Result
                     ?? throw new Xunit.Sdk.XunitException("the folder picker never opened");
        var box = Retry.WhileNull(
            () => picker.FindFirstDescendant(cf => cf.ByAutomationId("1152").And(cf.ByControlType(ControlType.Edit)))
                  ?? picker.FindFirstDescendant(cf => cf.ByControlType(ControlType.Edit).And(cf.ByName("Folder:"))),
            TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result
            ?? throw new Xunit.Sdk.XunitException("the folder picker has no folder box");
        box.Patterns.Value.Pattern.SetValue(folder);

        for (int press = 1; press <= 3; press++)
        {
            var select = picker.FindFirstDescendant(cf => cf.ByAutomationId("1").And(cf.ByControlType(ControlType.Button)));
            if (select is null) break;
            try { select.AsButton().Invoke(); } catch { }
            if (Retry.WhileFalse(() => Picker() is null, TimeSpan.FromSeconds(4), TimeSpan.FromMilliseconds(250)).Result) return;
        }
        if (Picker() is not null) throw new Xunit.Sdk.XunitException($"the folder picker would not take {folder}");
    }

    /// <summary>Open a top-level menu of the window's menu bar and press one of its items.</summary>
    public static void PressMenuBarItem(DrivenApp app, string menu, string itemAutomationId)
    {
        for (int attempt = 1; attempt <= 3; attempt++)
        {
            var top = app.Window.FindFirstDescendant(cf => cf.ByName(menu).And(cf.ByControlType(ControlType.MenuItem)))
                      ?? throw new Xunit.Sdk.XunitException($"the menu bar has no {menu} menu");
            if (top.Patterns.ExpandCollapse.IsSupported) top.Patterns.ExpandCollapse.Pattern.Expand();
            else app.ClickMiddleOf(top);
            var item = Retry.WhileNull(
                () => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId(itemAutomationId)),
                TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
            if (item is null) continue;
            DrivenApp.PressMenuItem(item);
            return;
        }
        throw new Xunit.Sdk.XunitException($"the {menu} menu never offered {itemAutomationId}");
    }

    /// <summary>
    /// Press Copy a Page's own Cancel/Done — by its documented id
    /// <c>copyPageClose</c> and nothing else — and wait for the dialog to go.
    /// FAILS when no dialog is up or its button lacks the id (bundle 11, W1:
    /// the "whichever id" fallback hid an app race).
    /// </summary>
    public static void CloseCopyAPage(DrivenApp app)
    {
        var dialog = Retry.WhileNull(() => app.OpenDialog(), TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result
                     ?? throw new Xunit.Sdk.XunitException("there was no Copy a Page dialog to close");
        var close = Retry.WhileNull(() => dialog.FindFirstDescendant(cf => cf.ByAutomationId(CopyAPageDialogIds.Close)),
                                    TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result
                    ?? throw new Xunit.Sdk.XunitException($"the dialog \"{dialog.Name}\" has no button with the id {CopyAPageDialogIds.Close}");
        close.AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    "Copy a Page would not close");
    }

    /// <summary>Whether writing to a file is refused — the reference lock, measured on disk.</summary>
    public static bool WritingIsRefused(string file)
    {
        try
        {
            using var stream = new FileStream(file, FileMode.Open, FileAccess.Write, FileShare.ReadWrite);
            return false;
        }
        catch (UnauthorizedAccessException) { return true; }
    }
}

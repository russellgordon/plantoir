using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.ViewModels;
using Plantoir.Views;
using Windows.Graphics;

namespace Plantoir.Services;

/// <summary>
/// The pictures on plantoir.app, staged in REAL windows (#380, #370).
///
/// <para><c>Plantoir.exe --stage-scene &lt;scene&gt; --theme light|dark
/// --folder &lt;working folder&gt; --ready-file &lt;path&gt;</c> opens the
/// window a scene is about, drives it to the state its caption describes
/// through the app's own code, writes <c>staged</c> (or why not) to the ready
/// file, and holds the window open. <c>website/shots/app_scenes_windows.py</c>
/// then photographs that window whole with Windows.Graphics.Capture — its own
/// corners and alpha, nothing cropped or drawn — and ends the process.</para>
///
/// <para>This replaced <c>--capture-marketing-shots</c>, which rendered each
/// window's CONTENT with RenderTargetBitmap: no title bar, no window, square
/// corners, and bubbles and buttons typed by hand into the assistant. Russell's
/// rule (2026-09-27, again 2026-10-04) is that every picture is a whole window
/// capture, so a rendering of content cannot be one however it is trimmed.</para>
///
/// <para>Every scene is run with <c>--state-dir</c>, so the windows, settings
/// and trail lines a scene leaves behind are a temporary folder's, never a
/// teacher's. Nothing here is reachable without these arguments.</para>
/// </summary>
public static class MarketingShotCapturer
{
    public static void Log(string message)
    {
        try
        {
            File.AppendAllText(Path.Combine(Path.GetTempPath(), "marketing_capture.log"),
                               $"[{DateTime.UtcNow:HH:mm:ss.fff}] {message}\n");
        }
        catch { }
    }

    // ---- Staging -----------------------------------------------------------

    /// <summary>
    /// Stage one scene and leave its window open. The ready file says
    /// <c>staged</c> once the window shows what the caption says, or
    /// <c>refused: …</c> with the reason — never a picture of something else.
    /// </summary>
    public static async Task StageAsync(MarketingScene request)
    {
        string outcome;
        try
        {
            Log($"Staging {request.Scene} ({Theme(request)}) in {request.Folder}");
            outcome = request.Scene switch
            {
                "provision" => await Provision(request),
                "courses" => await Courses(request),
                "new-course" => await NewCourse(request, "TEJ3M", "1, 2", club: false),
                "club" => await NewCourse(request, "CODING", "1", club: true),
                "progress" => await Progress(request),
                "preview" => await Preview(request),
                "assistant" => await Assistant(request),
                "reference" => await Reference(request),
                "start-of-year" => await StartOfYear(request),
                "schedule-sheet" => await ScheduleSheet(request),
                "curriculum-settings" => await CurriculumSettings(request),
                "map-ontario" => await PreviewPage(request, "ICS3U", 1, "/Curriculum-Coverage", null),
                "map-college-board" => await PreviewPage(request, "ICS3U", 1, "/College-Board-Curriculum-Coverage", null),
                "both-curricula" => await PreviewPage(request, "ICS3U", 1, "/Explorations/The-Unplugged-Algorithm", "curriculum-connection"),
                "hero" => await Hero(request),
                _ => $"refused: no scene {request.Scene}",
            };
        }
        catch (FolderNotReady notReady)
        {
            outcome = $"refused: {notReady.Message}";
        }
        catch (Exception error)
        {
            outcome = $"refused: {error.GetType().Name}: {error.Message}";
        }
        Log($"{request.Scene}: {outcome}");
        if (request.ReadyFile is { } ready)
        {
            try { File.WriteAllText(ready, outcome); } catch (Exception error) { Log($"ready file: {error.Message}"); }
        }
    }

    private const string Staged = "staged";

    private static ElementTheme Theme(MarketingScene request) => request.Dark ? ElementTheme.Dark : ElementTheme.Light;

    // A main window is 1280 x 800 effective pixels, the mac's own size in
    // points, so a picture shows the same amount of the app on both.
    private const int MainWidth = 1280, MainHeight = 800;
    private const int AssistWidth = 560, AssistHeight = 760;

    private static async Task<MainWindow> OpenMain(MarketingScene request)
    {
        var window = App.OpenWindow(request.Folder, null);
        Dress(window, Theme(request), MainWidth, MainHeight);
        await Task.Delay(1500);
        await WaitUntilTheFolderIsReady(request.Folder);
        return window;
    }

    /// <summary>A scene refused because the folder could not be got ready (#473).</summary>
    private sealed class FolderNotReady(string sentence) : Exception(sentence);

    /// <summary>
    /// #473: the window's own launch copies the app's tools into the folder in
    /// the background, and Preview, Deploy and New Course are refused — with a
    /// dialog that would be in the picture — until it is done. So a scene
    /// waits for that copy (joining it, never starting a second) before it
    /// presses anything, and is refused with the sentence when it failed.
    /// </summary>
    private static async Task WaitUntilTheFolderIsReady(string folder)
    {
        await ToolchainReadiness.Ensure(folder, BundledToolchain.Root);
        if (ToolchainReadiness.Refusal(folder) is { } notReady) throw new FolderNotReady(notReady);
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    /// <summary>The scene's appearance on the window's content, and its size in effective pixels at this display's scale.</summary>
    private static void Dress(Window window, ElementTheme theme, int width, int height)
    {
        if (window.Content is FrameworkElement root) root.RequestedTheme = theme;
        WindowTheme.Sync(window);   // the caption too, before the window is shown or shot
        double scale = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(window)) / 96.0;
        if (scale <= 0) scale = 1;
        window.AppWindow.Resize(new SizeInt32((int)Math.Round(width * scale), (int)Math.Round(height * scale)));
        window.AppWindow.Move(new PointInt32(20, 20));
    }

    private static async Task<bool> Until(Func<bool> condition, TimeSpan patience)
    {
        var deadline = DateTime.UtcNow + patience;
        while (DateTime.UtcNow < deadline)
        {
            if (condition()) return true;
            await Task.Delay(400);
        }
        return condition();
    }

    private static Course? CourseNamed(MainWindow window, string code) =>
        window.Workspace.Courses.FirstOrDefault(c => !ReferenceCourse.IsKeptForReference(c)
                                                     && c.Code.Equals(code, StringComparison.OrdinalIgnoreCase));

    private static void ShowOver(MainWindow window, ContentDialog dialog)
    {
        dialog.XamlRoot = window.Content.XamlRoot;
        if (window.Content is FrameworkElement root) dialog.RequestedTheme = root.RequestedTheme;
        _ = dialog.ShowAsync();
    }

    // ---- The scenes ----------------------------------------------------------

    /// <summary>
    /// The folder made the way a teacher makes it: set up, each course through
    /// the New Course panel (its ready-made content taken), then the reference
    /// copy through Keep a Copy for Reference's own code. A course already
    /// there is left as it is, so running this twice changes nothing.
    /// </summary>
    private static async Task<string> Provision(MarketingScene request)
    {
        Directory.CreateDirectory(request.Folder);
        var window = App.OpenWindow(request.Folder, null);
        await Task.Delay(1500);
        if (window.Workspace.State != WorkspaceState.Ready)
        {
            await window.Workspace.InitializeWorkspaceAsync();
            window.ApplyState();
            await Task.Delay(1000);
        }
        if (window.Workspace.State != WorkspaceState.Ready)
            return $"refused: the folder could not be set up ({window.Workspace.WorkspaceProblem})";
        await WaitUntilTheFolderIsReady(request.Folder);   // #473: the New Course panel waits for it

        foreach (var (code, sections) in request.Courses)
        {
            if (CourseNamed(window, code) is not null) continue;
            var wizard = new NewCourseDialog(window) { XamlRoot = window.Content.XamlRoot };
            // Filled in as typed FIRST, so the course gets the name a teacher
            // typing the code is offered ("Intro to Comp Sci"), not the
            // panel's fallback: AutoCreate alone sets the code before the box
            // is live, no name is suggested, and the first folder made this
            // way was called "Course Website".
            wizard.Opened += (_, _) => wizard.StageForCapture(code, sections);
            wizard.AutoCreate(code, sections);
            var showing = wizard.ShowAsync();
            bool made = await Until(() => wizard.CreatedCourseCode is not null, TimeSpan.FromMinutes(6));
            wizard.Hide();
            await showing;
            window.Workspace.Reload();
            window.ApplyState();
            if (!made) return $"refused: {code} was not made by the New Course panel";
        }

        if (request.ReferenceCopy is { } copy
            && !window.Workspace.Courses.Any(c => ReferenceCourse.IsKeptForReference(c)
                                                  && c.Code.StartsWith(copy.Code, StringComparison.OrdinalIgnoreCase)))
        {
            if (CourseNamed(window, copy.Code) is not { } course) return $"refused: there is no {copy.Code} to keep a copy of";
            string coursesDirectory = window.Workspace.CoursesDirectory();
            await Task.Run(() => ReferenceCopier.KeepACopy(course, MarketingScene.ReferenceFolderName(copy.Code, copy.Year), copy.Year, coursesDirectory));
            window.Workspace.Reload();
            window.ApplyState();
        }
        return Staged;
    }

    /// <summary>The first course's settings, beside the others and last year's copy under Reference Courses.</summary>
    private static async Task<string> Courses(MarketingScene request)
    {
        var window = await OpenMain(request);
        if (CourseNamed(window, "ICS3U") is null) return "refused: no ICS3U in the folder";
        if (!window.Workspace.Courses.Any(ReferenceCourse.IsKeptForReference)) return "refused: no reference course in the folder";
        window.Workspace.Selection = new SidebarSelection.CourseItem("ICS3U");
        await Task.Delay(1500);
        return Staged;
    }

    /// <summary>The New Course or Club panel with a code entered, as typed, before Create is pressed.</summary>
    private static async Task<string> NewCourse(MarketingScene request, string code, string sections, bool club)
    {
        var window = await OpenMain(request);
        var wizard = new NewCourseDialog(window);
        bool opened = false;
        wizard.Opened += (_, _) => { wizard.StageForCapture(code, sections, club); opened = true; };
        ShowOver(window, wizard);
        if (!await Until(() => opened, TimeSpan.FromSeconds(20))) return "refused: the New Course panel did not open";
        await Task.Delay(1500);
        if (wizard.IsMakingAClub != club) return $"refused: the panel {(club ? "is not" : "is")} making a club";
        if (!club)
        {
            // The caption promises the suggested names beneath the code; the
            // panel is taller than the window, so they are brought into view.
            if (FindById(wizard, "newCourseSuggestions") is not FrameworkElement suggestions
                || suggestions.Visibility != Visibility.Visible)
                return $"refused: no names were suggested for {code}";
            suggestions.StartBringIntoView(new BringIntoViewOptions { VerticalAlignmentRatio = 0.6, AnimationDesired = false });
            await Task.Delay(1000);
        }
        return Staged;
    }

    /// <summary>A real preview being built, caught part-way: the words beside the bar are the build's own.</summary>
    private static async Task<string> Progress(MarketingScene request)
    {
        var window = await OpenMain(request);
        window.Workspace.Selection = new SidebarSelection.SectionItem("ENG2D", 2);
        await Task.Delay(800);
        if (window.DetailPresenter.Content is not SectionDetailView detail) return "refused: ENG2D section 2 did not open";
        detail.StartPreviewForAutomation();
        // Far enough in that the bar has moved, not so far that it is done.
        await Task.Delay(TimeSpan.FromSeconds(14));
        if (detail.HasPreview) return "refused: the preview finished before it could be photographed";
        return Staged;
    }

    /// <summary>A real preview of the section, built and shown in the window.</summary>
    private static async Task<string> Preview(MarketingScene request)
    {
        var window = await OpenMain(request);
        window.Workspace.Selection = new SidebarSelection.SectionItem("ENG2D", 1);
        await Task.Delay(800);
        if (window.DetailPresenter.Content is not SectionDetailView detail) return "refused: ENG2D section 1 did not open";
        detail.StartPreviewForAutomation();
        if (!await Until(() => detail.HasPreview, TimeSpan.FromMinutes(15))) return "refused: the preview never appeared";
        await Task.Delay(TimeSpan.FromSeconds(8));   // the page itself drawing in the window
        return Staged;
    }

    /// <summary>
    /// The assistant window with the promise card's "Unpublish Unit 2, Day 3"
    /// sent: the plan and its buttons are the app's own, from Plantoir's real
    /// tools (<see cref="AssistWindow.StageForCapture"/> says why no model is
    /// needed for it).
    /// </summary>
    private static async Task<string> Assistant(MarketingScene request)
    {
        var course = Workspace.DiscoverCourses(request.Folder)
            .FirstOrDefault(c => c.Code.Equals("ENG2D", StringComparison.OrdinalIgnoreCase));
        if (course is null) return "refused: no ENG2D in the folder";
        var window = new AssistWindow(request.Folder, course, 1);
        window.StageForCapture(new AnswersNothing(), "Unpublish Unit 2, Day 3");
        Dress(window, Theme(request), AssistWidth, AssistHeight);
        window.Activate();
        if (!await Until(() => window.IsWaitingForApproval, TimeSpan.FromSeconds(90)))
            return "refused: the assistant did not come back with a plan to approve";
        await Task.Delay(1500);
        return Staged;
    }

    /// <summary>Copy a Page from last year's ICS3U into ICS4U, the questions answered and Copy not pressed.</summary>
    private static async Task<string> Reference(MarketingScene request)
    {
        var window = await OpenMain(request);
        var source = window.Workspace.Courses.FirstOrDefault(c => ReferenceCourse.IsKeptForReference(c)
                                                                  && ReferenceCourse.ShownCode(c).StartsWith("ICS3U", StringComparison.OrdinalIgnoreCase));
        if (source is null) return "refused: no reference copy of ICS3U in the folder";
        var dialog = CopyAPageDialog.StagedForCapture(source, window.Workspace.Courses, request.Folder,
                                                      "The Unplugged Algorithm", "ICS4U");
        if (dialog is null) return "refused: the reference ICS3U has no page called The Unplugged Algorithm, or ICS4U is not offered";
        ShowOver(window, dialog);
        await Task.Delay(2000);
        return Staged;
    }

    /// <summary>Get ICS3U Section 2 Ready for the Start of the Year, its plan shown and nothing done.</summary>
    private static async Task<string> StartOfYear(MarketingScene request)
    {
        var window = await OpenMain(request);
        if (CourseNamed(window, "ICS3U") is not { } course) return "refused: no ICS3U in the folder";
        window.Workspace.Selection = new SidebarSelection.SectionItem("ICS3U", 2);
        await Task.Delay(800);
        ContentDialog? shown = null;
        _ = StartOfYearDialog.OfferAsync(request.Folder, course, 2, dialog =>
        {
            shown = dialog;
            ShowOver(window, dialog);
            // Never answered: the scene holds the sheet open until the process ends.
            return new TaskCompletionSource<ContentDialogResult?>().Task;
        }, () => true);
        if (!await Until(() => shown is not null, TimeSpan.FromSeconds(20)))
            return "refused: there was nothing to put into draft, so no plan was shown";
        await Task.Delay(1500);
        return Staged;
    }

    /// <summary>ICS3U's Course Settings, scrolled to its curriculum folders: Curriculum and College Board Curriculum ticked.</summary>
    private static async Task<string> CurriculumSettings(MarketingScene request)
    {
        var window = await OpenMain(request);
        if (CourseNamed(window, "ICS3U") is not { } course) return "refused: no ICS3U in the folder";
        if (!course.Configuration.CurriculumFolders.Contains("College Board Curriculum"))
            return "refused: ICS3U does not declare College Board Curriculum as a curriculum";
        window.Workspace.Selection = new SidebarSelection.CourseItem("ICS3U");
        await Task.Delay(1500);
        if (FindById(window.Content, "curriculumFoldersList") is not FrameworkElement list)
            return "refused: the settings show no curriculum folders list";
        list.StartBringIntoView(new BringIntoViewOptions { VerticalAlignmentRatio = 0.35, AnimationDesired = false });
        await Task.Delay(1500);
        return Staged;
    }

    private static DependencyObject? FindById(DependencyObject? root, string automationId)
    {
        if (root is null) return null;
        if (root is UIElement element
            && Microsoft.UI.Xaml.Automation.AutomationProperties.GetAutomationId(element) == automationId) return root;
        int count = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < count; i++)
            if (FindById(Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(root, i), automationId) is { } found) return found;
        return null;
    }

    /// <summary>
    /// One page of a REAL preview of the section, in the window: the two
    /// coverage maps, and a lesson whose curriculum connection quotes both
    /// curricula. Refused when the page does not load, or its heading does not
    /// land at the top.
    /// </summary>
    private static async Task<string> PreviewPage(MarketingScene request, string code, int section, string path, string? anchor)
    {
        var window = await OpenMain(request);
        window.Workspace.Selection = new SidebarSelection.SectionItem(code, section);
        await Task.Delay(800);
        if (window.DetailPresenter.Content is not SectionDetailView detail) return $"refused: {code} section {section} did not open";
        detail.StartPreviewForAutomation();
        if (!await Until(() => detail.HasPreview, TimeSpan.FromMinutes(15))) return "refused: the preview never appeared";
        await Task.Delay(TimeSpan.FromSeconds(4));
        if (await detail.ShowPreviewPageForCaptureAsync(path, anchor) is { } problem)
            return $"refused: {problem}";
        return Staged;
    }

    /// <summary>ICS3U Section 1's Schedule a Deploy sheet, as the section's menu opens it; Schedule never pressed.</summary>
    private static async Task<string> ScheduleSheet(MarketingScene request)
    {
        var window = await OpenMain(request);
        if (CourseNamed(window, "ICS3U") is not { } course) return "refused: no ICS3U in the folder";
        window.Workspace.Selection = new SidebarSelection.SectionItem("ICS3U", 1);
        await Task.Delay(800);
        window.SidebarPane.OpenScheduleSheetForCapture(course, 1);
        await Task.Delay(2500);
        return Staged;
    }

    /// <summary>
    /// The hero's middle card: the window staged mid-deploy. The ONE scene
    /// whose progress is staged rather than real, because a real deploy would
    /// put a site on the internet to take a photograph.
    /// </summary>
    private static async Task<string> Hero(MarketingScene request)
    {
        var window = await OpenMain(request);
        window.Workspace.Selection = new SidebarSelection.SectionItem("ENG2D", 1);
        await Task.Delay(500);
        var runner = new ScriptRunner(SynchronizationContext.Current);
        var progressView = new TaskProgressView { RequestedTheme = Theme(request) };
        progressView.Show(runner, "Deploying ENG2D-S1");
        window.DetailPresenter.Content = progressView;
        runner.StageAsRunningForCapture(TaskMilestones.Deploy, DeployTranscript);
        await Task.Delay(1000);
        return Staged;
    }

    /// <summary>
    /// Enough launcher output to walk the deploy milestones to "Connecting to
    /// Netlify…" — the step the hero shows. The strings are the MARKERS from
    /// <see cref="TaskMilestones.Deploy"/>; change one there and this stops
    /// advancing, which is the intended coupling.
    /// </summary>
    private const string DeployTranscript =
        "Host timezone offset: -0400\nDeploying ENG2D S1 from this PC ...\n"
        + "Deploying from local build\n";

    /// <summary>A model that is never asked anything in a staged scene, and says nothing if it is.</summary>
    private sealed class AnswersNothing : IChatModel
    {
        public Task<ModelReply?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation) =>
            Task.FromResult<ModelReply?>(null);
    }
}

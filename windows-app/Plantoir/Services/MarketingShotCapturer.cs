using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Tasks;
using Microsoft.UI.Text;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.ViewModels;
using Plantoir.Views;
using Windows.Graphics;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Plantoir.Services;

/// <summary>
/// Autonomous screenshot capture harness for Windows marketing shots.
/// Takes pixel-perfect captures for all 5 app-window marketing shots (courses,
/// new-course, progress, preview, assistant) in both Light and Dark appearance.
/// </summary>
public static class MarketingShotCapturer
{
    private static readonly string[] DemoCodes = { "ENG2D", "MCV4U", "SCH3U" };
    private static string LogPath => Path.Combine(Path.GetTempPath(), "marketing_capture.log");

    public static void Log(string message)
    {
        try
        {
            File.AppendAllText(LogPath, $"[{DateTime.UtcNow:HH:mm:ss.fff}] {message}\n");
        }
        catch { }
    }

    /// <summary>
    /// Photograph the app windows, optionally for one appearance only.
    ///
    /// One appearance per PROCESS, with the OS switched to it first, is the
    /// only way these come out right. Setting RequestedTheme on the window's
    /// content changes what the controls draw, but every brush fetched as
    /// Application.Current.Resources["..."] still resolves against the theme
    /// the APP launched in — so a dark capture came back with a white dialog
    /// card carrying white text, and assistant bubbles in light grey on a
    /// dark window. Chasing those brush by brush (tried first: hardcoding
    /// approximate literals in ThemedBrush) works but keeps drifting from the
    /// real design tokens and needs re-chasing for every new brush anyone
    /// adds; one process per appearance makes every themed resource resolve
    /// exactly the way a teacher's copy resolves it, because the situation is
    /// the same one. capture_windows.py switches Windows into each appearance
    /// before launching this with --theme, and puts the colour mode back in a
    /// finally.
    /// </summary>
    public static async Task RunAsync(string outputDir, string? onlyTheme = null)
    {
        try
        {
            outputDir = Path.GetFullPath(outputDir);
            Directory.CreateDirectory(outputDir);
            Log($"Starting marketing capture to {outputDir}");

            string workspacePath = @"C:\Users\russellgordon\Teaching";
            try
            {
                Directory.CreateDirectory(workspacePath);
                string testFile = Path.Combine(workspacePath, "write_test.tmp");
                File.WriteAllText(testFile, "test");
                File.Delete(testFile);
            }
            catch
            {
                workspacePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Teaching");
            }
            ProvisionDemoWorkspace(workspacePath);
            Log($"Workspace provisioned at {workspacePath}");

            ElementTheme[] wanted = onlyTheme is null
                ? new[] { ElementTheme.Light, ElementTheme.Dark }
                : new[] { onlyTheme.Equals("dark", StringComparison.OrdinalIgnoreCase)
                              ? ElementTheme.Dark : ElementTheme.Light };

            foreach (var theme in wanted)
            {
                string themeName = theme == ElementTheme.Dark ? "dark" : "light";
                Log($"--- Capturing theme: {themeName} ---");

                // ---- 1. Shot: courses ----
                string coursesPath = Path.Combine(outputDir, $"courses-windows-{themeName}.png");
                await CaptureCoursesWindow(workspacePath, theme, coursesPath);
                Log($"Saved {coursesPath}");

                // ---- 2. Shot: new-course ----
                string newCoursePath = Path.Combine(outputDir, $"new-course-windows-{themeName}.png");
                await CaptureNewCourseWindow(workspacePath, theme, newCoursePath);
                Log($"Saved {newCoursePath}");

                // ---- 3. Shot: progress ----
                string progressPath = Path.Combine(outputDir, $"progress-windows-{themeName}.png");
                await CaptureProgressWindow(workspacePath, theme, progressPath);
                Log($"Saved {progressPath}");

                // ---- 4. Shot: preview ----
                string previewPath = Path.Combine(outputDir, $"preview-windows-{themeName}.png");
                string siteImagePath = Path.Combine(outputDir, $"site-eng2d-windows-{themeName}.png");
                await CapturePreviewWindow(workspacePath, theme, previewPath, siteImagePath);
                Log($"Saved {previewPath}");

                // ---- 5. Shot: assistant ----
                string assistPath = Path.Combine(outputDir, $"assistant-windows-{themeName}.png");
                await CaptureAssistantWindow(workspacePath, theme, assistPath);
                Log($"Saved {assistPath}");
            }

            Log("Capture finished successfully.");
        }
        catch (Exception ex)
        {
            // Exiting 0 here made a mid-capture crash invisible: capture_windows.py's
            // subprocess.run(..., check=True) only raises on a NONZERO exit, so a
            // failure that struck the very first window still printed "Every
            // screenshot now has an authentic Windows twin" and left every
            // remaining image as a stale leftover from whatever run last touched
            // it -- discovered 2026-08-20 when a resource-lookup bug silently
            // aborted two capture attempts in a row and both were reviewed as if
            // they were fresh. The failure was always in the log
            // (%TEMP%\marketing_capture.log); it just never reached the exit code.
            Log($"Capture failed: {ex}");
            Environment.Exit(1);
        }
        Environment.Exit(0);
    }

    /// <summary>
    /// Open one Plantoir window, staged mid-deploy, and leave it on screen.
    ///
    /// This is the only capture that is NOT a RenderTargetBitmap: the hero
    /// composite sets Plantoir beside Obsidian and Edge, and a visual-tree
    /// render has no title bar, so it would be the one card in the cascade
    /// with no window chrome. The Python harness photographs this window off
    /// the screen instead, which is also how it takes the other two.
    ///
    /// Nothing here writes settings or joins App's window list -- the process
    /// is killed once the picture is taken, and a remembered-window list that
    /// grew a marketing window would reopen it on the teacher's next launch.
    /// </summary>
    public static async Task ShowHeroWindowAsync(string themeName)
    {
        var theme = themeName.Equals("dark", StringComparison.OrdinalIgnoreCase)
            ? ElementTheme.Dark : ElementTheme.Light;

        string workspacePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Teaching");
        ProvisionDemoWorkspace(workspacePath);

        var window = new MainWindow(workspacePath, null);
        if (window.Content is FrameworkElement root) root.RequestedTheme = theme;
        window.Activate();

        await Task.Delay(700);
        window.Workspace.Selection = new SidebarSelection.SectionItem("ENG2D", 1);
        await Task.Delay(500);

        var runner = new ScriptRunner(System.Threading.SynchronizationContext.Current);
        var progressView = new TaskProgressView();
        progressView.RequestedTheme = theme;
        progressView.Show(runner, "Deploying ENG2D-S1");
        window.DetailPresenter.Content = progressView;
        runner.StageAsRunningForCapture(TaskMilestones.Deploy, DeployTranscript);

        Log($"Hero window staged in {themeName}; waiting to be photographed.");
    }

    private static void ProvisionDemoWorkspace(string workspacePath)
    {
        if (Directory.Exists(workspacePath))
        {
            try { Directory.Delete(workspacePath, recursive: true); } catch { }
        }
        Directory.CreateDirectory(workspacePath);

        // Marker launchers required for WorkspaceState.Ready
        File.WriteAllText(Path.Combine(workspacePath, "preview.ps1"), "# Plantoir Launcher\n");
        File.WriteAllText(Path.Combine(workspacePath, "preview.sh"), "#!/usr/bin/env bash\n");
        File.WriteAllText(Path.Combine(workspacePath, "setup.ps1"), "# Plantoir Setup\n");
        File.WriteAllText(Path.Combine(workspacePath, "deploy.ps1"), "# Plantoir Deploy\n");

        string[] possibleRoots = new[]
        {
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "..")),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..")),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..")),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..")),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..")),
            Directory.GetCurrentDirectory(),
            @"C:\Users\lenov\Desktop\Developer\containerized-quartz-for-teachers",
            @"C:\Users\lenov\Desktop\Developer\plantoir"
        };
        string? foundRoot = possibleRoots.FirstOrDefault(r => Directory.Exists(Path.Combine(r, "support", "example_content")));
        string exampleContentDir = foundRoot != null ? Path.Combine(foundRoot, "support", "example_content") : "";

        string coursesDir = Path.Combine(workspacePath, "courses");
        Directory.CreateDirectory(coursesDir);

        var demoMeta = new (string Code, string Name, string Scheme, string HFont, string BFont)[]
        {
            ("ENG2D", "Grade 10 English", "default", "serif", "sans-serif"),
            ("MCV4U", "Grade 12 Calculus and Vectors", "forest", "sans-serif", "sans-serif"),
            ("SCH3U", "Grade 11 Chemistry", "ocean", "sans-serif", "sans-serif")
        };

        foreach (var (code, defaultName, defaultScheme, defaultHFont, defaultBFont) in demoMeta)
        {
            string courseTarget = Path.Combine(coursesDir, code);
            Directory.CreateDirectory(courseTarget);
            Directory.CreateDirectory(Path.Combine(courseTarget, "shared"));
            Directory.CreateDirectory(Path.Combine(courseTarget, "section1"));
            Directory.CreateDirectory(Path.Combine(courseTarget, "section2"));

            string sourceDir = !string.IsNullOrEmpty(exampleContentDir) ? Path.Combine(exampleContentDir, code) : "";
            string courseName = defaultName;
            string scheme = defaultScheme;
            string hFont = defaultHFont;
            string bFont = defaultBFont;

            if (Directory.Exists(sourceDir))
            {
                string manifestPath = Path.Combine(sourceDir, "manifest.json");
                if (File.Exists(manifestPath))
                {
                    try
                    {
                        var manifest = JObject.Parse(File.ReadAllText(manifestPath));
                        courseName = manifest["course_name"]?.ToString() ?? defaultName;
                        scheme = manifest["colour_scheme"]?.ToString() ?? defaultScheme;
                        hFont = manifest["header_font"]?.ToString() ?? defaultHFont;
                        bFont = manifest["body_font"]?.ToString() ?? defaultBFont;
                    }
                    catch { }
                }

                string sharedSrc = Path.Combine(sourceDir, "shared");
                if (Directory.Exists(sharedSrc))
                    CopyDirectory(sharedSrc, Path.Combine(courseTarget, "shared"));

                string sectionSrc = Path.Combine(sourceDir, "per_section");
                if (Directory.Exists(sectionSrc))
                {
                    CopyDirectory(sectionSrc, Path.Combine(courseTarget, "section1"));
                    CopyDirectory(sectionSrc, Path.Combine(courseTarget, "section2"));
                }
            }

            var configObj = new JObject
            {
                ["course_name"] = courseName,
                ["course_code"] = code,
                // NOT "section_count" -- no such key. The two apps and the
                // Python both read num_sections/section_numbers, so a course
                // written the other way silently came up with one section.
                ["num_sections"] = 2,
                ["section_numbers"] = new JArray(1, 2),
                ["colour_scheme"] = scheme,
                ["header_font"] = hFont,
                ["body_font"] = bFont,
                ["use_literal_grade_markers"] = false,
                ["use_lcs_terminology"] = false,
                ["deploy_target"] = "netlify"
            };
            var config = CourseConfiguration.FromDictionary(configObj);
            config.Write(Path.Combine(courseTarget, "course_config.json"));

            WriteNetlifyMarkers(courseTarget, code);
        }
    }

    /// <summary>
    /// Record which site each SECTION is published to, the way a real deploy
    /// does -- ".netlify_sites/section&lt;n&gt;.json", which is what
    /// build_site.py's resolve_section_domain and deploy.py's
    /// load_netlify_marker actually read.
    ///
    /// This replaces a "deploy_site_name" key these fixtures used to write.
    /// WINDOWS-HANDOFF.md asked this side to decide what that key should hold
    /// under the per-section naming adopted on 2026-08-19
    /// (<c>&lt;code&gt;-s&lt;n&gt;-2026-gordon</c>), on the grounds that the new
    /// scheme names a section while the key sits in course-level config. The
    /// answer is that the key was never real: it appears in no launcher, no
    /// contract (contracts/file-formats.json lists the keys course_config.json
    /// carries) and nowhere else in either app, so renaming it would have
    /// looked like settling the question while changing nothing. The per-section
    /// marker is where a section's address genuinely lives, so that is what
    /// gets written.
    /// </summary>
    private static void WriteNetlifyMarkers(string courseDir, string code)
    {
        string markerDir = Path.Combine(courseDir, ".netlify_sites");
        Directory.CreateDirectory(markerDir);
        foreach (int section in new[] { 1, 2 })
        {
            string name = $"{code.ToLowerInvariant()}-s{section}-2026-gordon";
            var marker = new JObject
            {
                ["name"] = name,
                ["url"] = $"http://{name}.netlify.app",
                ["ssl_url"] = $"https://{name}.netlify.app"
            };
            File.WriteAllText(Path.Combine(markerDir, $"section{section}.json"),
                              marker.ToString());
        }
    }

    private static void CopyDirectory(string source, string target)
    {
        Directory.CreateDirectory(target);
        foreach (string file in Directory.GetFiles(source))
        {
            string dest = Path.Combine(target, Path.GetFileName(file));
            string content = File.ReadAllText(file);
            content = content.Replace("__CREATED__", "2026-09-08T07:00:00Z");
            content = System.Text.RegularExpressions.Regex.Replace(content, @"__CREATED_CLASS_\d+__", "2026-10-14T07:00:00Z");
            File.WriteAllText(dest, content);
        }
        foreach (string dir in Directory.GetDirectories(source))
        {
            CopyDirectory(dir, Path.Combine(target, Path.GetFileName(dir)));
        }
    }

    private static async Task CaptureCoursesWindow(string workspacePath, ElementTheme theme, string outputPath)
    {
        var window = new MainWindow(workspacePath, null);
        ConfigureWindow(window, 1280, 800, theme);
        window.Activate();

        await Task.Delay(500);
        window.Workspace.Selection = new SidebarSelection.CourseItem("ENG2D");
        await Task.Delay(600);

        await SaveWindowContentToPngAsync(window, outputPath);
        window.Close();
    }

    private static async Task CaptureNewCourseWindow(string workspacePath, ElementTheme theme, string outputPath)
    {
        var window = new MainWindow(workspacePath, null);
        ConfigureWindow(window, 1280, 800, theme);
        window.Activate();

        await Task.Delay(600);
        window.Workspace.Selection = new SidebarSelection.CourseItem("ENG2D");
        await Task.Delay(400);

        var dialog = new NewCourseDialog(window);
        dialog.RequestedTheme = theme;
        dialog.StageForCapture("SBI3U", "1, 2");

        var isDark = theme == ElementTheme.Dark;
        var overlay = new Grid
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(isDark ? (byte)140 : (byte)90, 0, 0, 0)),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch
        };
        Grid.SetRow(overlay, 0);
        Grid.SetRowSpan(overlay, 3);

        var dialogCard = new Border
        {
            Width = 540,
            // 680 cut the Language / region row through the middle of its
            // control, with no scrollbar to explain why -- it read as a
            // rendering fault rather than as a panel that continues.
            MaxHeight = 720,
            Background = (Brush)Application.Current.Resources["SolidBackgroundFillColorBaseBrush"],
            BorderBrush = (Brush)Application.Current.Resources["SurfaceStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(24, 20, 24, 20),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };

        var dialogLayout = new Grid();
        dialogLayout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        dialogLayout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        dialogLayout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var titleBlock = new TextBlock
        {
            // The dialog's own title, not a second copy of it that can
            // drift: the real one says "New Course or Club".
            Text = dialog.Title?.ToString() ?? "New Course",
            FontSize = 20,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 16)
        };
        Grid.SetRow(titleBlock, 0);
        dialogLayout.Children.Add(titleBlock);

        if (dialog.Content is FrameworkElement formContent)
        {
            dialog.Content = null;
            Grid.SetRow(formContent, 1);
            dialogLayout.Children.Add(formContent);
            GiveTheFormRoomForCapture(formContent);
        }

        var buttonRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Spacing = 8,
            Margin = new Thickness(0, 16, 0, 0)
        };
        var createBtn = new Button
        {
            Content = "Create",
            Style = (Style)Application.Current.Resources["AccentButtonStyle"],
            MinWidth = 80
        };
        var cancelBtn = new Button
        {
            Content = "Cancel",
            MinWidth = 80
        };
        buttonRow.Children.Add(createBtn);
        buttonRow.Children.Add(cancelBtn);
        Grid.SetRow(buttonRow, 2);
        dialogLayout.Children.Add(buttonRow);

        dialogCard.Child = dialogLayout;
        overlay.Children.Add(dialogCard);

        if (window.Content is Grid rootGrid)
        {
            rootGrid.Children.Add(overlay);
        }

        await Task.Delay(800);
        await SaveWindowContentToPngAsync(window, outputPath);
        window.Close();
    }

    /// <summary>
    /// Enough launcher output to walk the preview milestones as far as
    /// "Building your site…", which is the step worth photographing: far
    /// enough in that the bar has moved, not so far that it reads as finished.
    /// The strings are the MARKERS from <see cref="TaskMilestones.Preview"/> --
    /// change one there and this stops advancing, which is the intended
    /// coupling.
    /// </summary>
    private const string PreviewTranscript =
        "Running the website builder on this PC\n"
        + "Copying shared folders\nUpdated pageTitle\nInstalling dependencies\n";

    /// <summary>
    /// The deploy equivalent, stopped at "Connecting to Netlify…" -- the step
    /// the hero composite shows, and the one that makes the picture say
    /// "publishing" rather than "building".
    /// </summary>
    private const string DeployTranscript =
        "Host timezone offset: -0400\nDeploying EXC2O S1 from this PC ...\n"
        + "Deploying from local build\n";

    /// <summary>
    /// Give the form enough room that the photograph cuts where the mac's
    /// twin cuts -- at a section boundary, not through a control.
    ///
    /// The form lives in a ScrollViewer capped at 520, which put the card's
    /// bottom edge straight through the "Language / region" row: a label with
    /// its dropdown sliced off reads as a rendering fault rather than as a
    /// panel that continues. Asking for the scrollbar instead was tried first
    /// and does nothing -- Windows' "automatically hide scroll bars" setting
    /// wins over VerticalScrollBarVisibility.Visible, so a still frame never
    /// shows one. 600 completes that row and brings the next heading into
    /// view, which is what the mac shot shows.
    /// </summary>
    private static void GiveTheFormRoomForCapture(FrameworkElement content)
    {
        if (content is ScrollViewer viewer)
        {
            viewer.MaxHeight = 600;
            return;
        }
        if (content is Panel panel)
            foreach (var child in panel.Children)
                if (child is FrameworkElement element)
                    GiveTheFormRoomForCapture(element);
    }

    private static async Task CaptureProgressWindow(string workspacePath, ElementTheme theme, string outputPath)
    {
        var window = new MainWindow(workspacePath, null);
        ConfigureWindow(window, 1280, 800, theme);
        window.Activate();

        await Task.Delay(500);
        window.Workspace.Selection = new SidebarSelection.SectionItem("ENG2D", 2);
        await Task.Delay(400);

        // Stage the progress view exactly as a real preview does. The runner
        // has to LOOK like it is running, or Render() takes neither branch and
        // the pane shows a bar with no words beside it -- which contradicts
        // this shot's own caption ("Progress is described in words").
        var runner = new ScriptRunner(System.Threading.SynchronizationContext.Current);
        var progressView = new TaskProgressView();
        progressView.RequestedTheme = theme;
        progressView.Show(runner, "Preparing the preview of ENG2D-S2");
        window.DetailPresenter.Content = progressView;

        runner.StageAsRunningForCapture(TaskMilestones.Preview, PreviewTranscript);

        await Task.Delay(600);
        await SaveWindowContentToPngAsync(window, outputPath);
        window.Close();
    }

    private static async Task CapturePreviewWindow(string workspacePath, ElementTheme theme, string outputPath, string? siteImagePath = null)
    {
        var window = new MainWindow(workspacePath, null);
        ConfigureWindow(window, 1280, 800, theme);
        window.Activate();

        await Task.Delay(500);
        window.Workspace.Selection = new SidebarSelection.SectionItem("ENG2D", 1);
        await Task.Delay(400);

        if (window.DetailPresenter.Content is SectionDetailView detail)
        {
            detail.StagePreviewForCapture(theme, siteImagePath);
        }

        await Task.Delay(1200);
        await SaveWindowContentToPngAsync(window, outputPath);
        window.Close();
    }

    private static async Task CaptureAssistantWindow(string workspacePath, ElementTheme theme, string outputPath)
    {
        var configObj = new JObject
        {
            ["course_name"] = "Grade 10 English",
            ["course_code"] = "ENG2D",
            ["num_sections"] = 1,
            ["section_numbers"] = new JArray(1),
            ["colour_scheme"] = "default",
            ["header_font"] = "serif",
            ["body_font"] = "sans-serif",
            ["use_literal_grade_markers"] = false,
            ["use_lcs_terminology"] = false,
            ["deploy_target"] = "netlify"
        };
        var config = CourseConfiguration.FromDictionary(configObj);
        var course = new Course("ENG2D", Path.Combine(workspacePath, "courses", "ENG2D"), config);

        var window = new AssistWindow(workspacePath, course, 1);
        ConfigureWindow(window, 560, 760, theme);
        window.Activate();

        await Task.Delay(500);

        window.ShowPromptShelfForCapture();

        // Stage teacher message bubble matching macOS assistant test
        var teacherMsg = new TextBlock
        {
            Text = "Unpublish Unit 2, Day 3",
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["BodyTextBlockStyle"]
        };
        window.AddStagedBubbleForCapture("You", true, teacherMsg);

        // Stage assistant response bubble
        var assistMsg = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["BodyTextBlockStyle"]
        };
        assistMsg.Inlines.Add(new Run { Text = "I will hide " });
        assistMsg.Inlines.Add(new Run { Text = "Unit 2, Day 3: Character Analysis", FontWeight = FontWeights.SemiBold });
        assistMsg.Inlines.Add(new Run { Text = " from the website (2026-10-14)." });
        window.AddStagedBubbleForCapture("Assistant", false, assistMsg);

        // Stage plan approval card
        var planPanel = new StackPanel { Spacing = 6 };
        var planHeader = new TextBlock
        {
            Text = "Shall I go ahead?",
            FontWeight = FontWeights.SemiBold,
            Style = (Style)Application.Current.Resources["BodyTextBlockStyle"]
        };
        var planBody = new TextBlock
        {
            Text = "This will make 1 page hidden from students:\n• Unit 2, Day 3: Character Analysis",
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["BodyTextBlockStyle"]
        };
        var btnRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 4, 0, 0) };
        var btnApprove = new Button { Content = "Approve", Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
        var btnCancel = new Button { Content = "Cancel" };
        btnRow.Children.Add(btnApprove);
        btnRow.Children.Add(btnCancel);

        planPanel.Children.Add(planHeader);
        planPanel.Children.Add(planBody);
        planPanel.Children.Add(btnRow);
        window.AddStagedBubbleForCapture("Assistant", false, planPanel);

        await Task.Delay(600);
        await SaveWindowContentToPngAsync(window, outputPath);
        window.Close();
    }

    private static void ConfigureWindow(Window window, int width, int height, ElementTheme theme)
    {
        window.AppWindow.Resize(new SizeInt32(width, height));
        if (window.Content is FrameworkElement root)
        {
            root.RequestedTheme = theme;
            var bgBrush = theme == ElementTheme.Light
                ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 243, 243, 243)) // #F3F3F3 Page Light
                : new SolidColorBrush(Windows.UI.Color.FromArgb(255, 32, 32, 32));   // #202020 Page Dark
            if (root is Panel panel)
            {
                panel.Background = bgBrush;
            }
            else if (root is Control control)
            {
                control.Background = bgBrush;
            }
            root.Width = width;
            root.Height = height;
        }
    }

    private static async Task SaveWindowContentToPngAsync(Window window, string outputPath)
    {
        if (window.Content is not UIElement element) return;

        var rtb = new RenderTargetBitmap();
        await rtb.RenderAsync(element);

        var buffer = await rtb.GetPixelsAsync();
        byte[] pixels = buffer.ToArray();

        using var fileStream = File.Create(outputPath);
        using var randomStream = fileStream.AsRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, randomStream);
        encoder.SetPixelData(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            (uint)rtb.PixelWidth,
            (uint)rtb.PixelHeight,
            96,
            96,
            pixels);
        await encoder.FlushAsync();
    }
}

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

    public static async Task RunAsync(string outputDir)
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

            foreach (var theme in new[] { ElementTheme.Light, ElementTheme.Dark })
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
            Log($"Capture failed: {ex}");
        }
        finally
        {
            Environment.Exit(0);
        }
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
                ["section_count"] = 2,
                ["colour_scheme"] = scheme,
                ["header_font"] = hFont,
                ["body_font"] = bFont,
                ["use_literal_grade_markers"] = false,
                ["use_lcs_terminology"] = false,
                ["deploy_target"] = "netlify",
                ["deploy_site_name"] = $"{code.ToLowerInvariant()}-gordon-2026-27"
            };
            var config = CourseConfiguration.FromDictionary(configObj);
            config.Write(Path.Combine(courseTarget, "course_config.json"));
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
            MaxHeight = 680,
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
            Text = "New Course",
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

    private static async Task CaptureProgressWindow(string workspacePath, ElementTheme theme, string outputPath)
    {
        var window = new MainWindow(workspacePath, null);
        ConfigureWindow(window, 1280, 800, theme);
        window.Activate();

        await Task.Delay(500);
        window.Workspace.Selection = new SidebarSelection.SectionItem("ENG2D", 2);
        await Task.Delay(400);

        // Stage progress view for preview build matching macOS progress shot
        var runner = new ScriptRunner(System.Threading.SynchronizationContext.Current);
        var progressView = new TaskProgressView();
        progressView.RequestedTheme = theme;
        progressView.Show(runner, "Preparing the preview of ENG2D-S2");
        window.DetailPresenter.Content = progressView;

        runner.Milestones = TaskMilestones.Preview;
        runner.ReceiveOutput("Setting up this PC\nBuilding your website builder\nEnsuring container is running\nStarting preview container\n");

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
            ["section_count"] = 1,
            ["colour_scheme"] = "default",
            ["header_font"] = "serif",
            ["body_font"] = "sans-serif",
            ["use_literal_grade_markers"] = false,
            ["use_lcs_terminology"] = false,
            ["deploy_target"] = "netlify",
            ["deploy_site_name"] = "eng2d-gordon-2026-27"
        };
        var config = CourseConfiguration.FromDictionary(configObj);
        var course = new Course("ENG2D", Path.Combine(workspacePath, "courses", "ENG2D"), config);

        var window = new AssistWindow(workspacePath, course, 1);
        ConfigureWindow(window, 560, 760, theme);
        window.Activate();

        await Task.Delay(500);

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

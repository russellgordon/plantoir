using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// The title bar follows dark and light mode (Windows v1.4.4, 2026-10-07):
/// <c>Services/WindowTheme.cs</c> sets <c>AppWindowTitleBar.PreferredTheme</c>
/// from the content's theme. The behaviour is visual and was checked by
/// screenshot (documentation/12-windows-app.md, "The title bar follows dark
/// and light mode"); this pins what a reviewer could lose without a window to
/// look at — that EVERY window calls the helper, that the mapping is
/// content-theme to caption-theme, that a live switch is followed, and that
/// the marketing capture re-syncs after setting a scene's theme. Source-read
/// because the test project cannot reference the WinUI app.
/// </summary>
public class WindowThemeSourceTests
{
    private static string AppFolder => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");

    private static string Helper() => File.ReadAllText(Path.Combine(AppFolder, "Services", "WindowTheme.cs"));

    [Fact]
    public void EveryWindowTheAppCreatesCallsTheHelper()
    {
        var windowClass = new Regex(@"\bclass\s+(\w+)\s*:\s*(Microsoft\.UI\.Xaml\.)?Window\b");
        var found = new List<string>();
        foreach (string file in Directory.EnumerateFiles(AppFolder, "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains(Path.DirectorySeparatorChar + "obj" + Path.DirectorySeparatorChar)
                || file.Contains(Path.DirectorySeparatorChar + "bin" + Path.DirectorySeparatorChar)) continue;
            string source = File.ReadAllText(file);
            foreach (Match match in windowClass.Matches(source))
            {
                found.Add(match.Groups[1].Value);
                Assert.True(source.Contains("WindowTheme.Apply(this);"),
                    $"{match.Groups[1].Value} ({Path.GetFileName(file)}) is a Window that never calls WindowTheme.Apply(this), " +
                    "so its title bar stays light in dark mode.");
            }
        }
        // The two known today; a third is fine as long as it calls the helper.
        Assert.Contains("MainWindow", found);
        Assert.Contains("AssistWindow", found);
    }

    [Fact]
    public void TheCaptionFollowsTheContentThemeAndFallsBackToTheApplication()
    {
        string source = Helper().Replace("\r\n", "\n");
        Assert.Contains("ElementTheme.Dark => TitleBarTheme.Dark,", source);
        Assert.Contains("ElementTheme.Light => TitleBarTheme.Light,", source);
        Assert.Contains("_ => application == ApplicationTheme.Dark ? TitleBarTheme.Dark : TitleBarTheme.Light,", source);
        Assert.Contains("window.AppWindow.TitleBar.PreferredTheme = CaptionFor(", source);
        // Not the system's mode: the marketing capture themes the content directly.
        Assert.DoesNotContain("TitleBarTheme.UseDefaultAppMode;", source);
    }

    [Fact]
    public void ALiveSwitchIsFollowedWithoutARestart()
    {
        string source = Helper();
        Assert.Contains("root.ActualThemeChanged += (_, _) => Sync(window);", source);
        Assert.Contains("settings.ColorValuesChanged += handler;", source);
        Assert.Contains("window.Closed += (_, _) => settings.ColorValuesChanged -= handler;", source);
    }

    [Fact]
    public void TheMarketingCaptureSyncsTheCaptionAfterSettingTheScenesTheme()
    {
        string source = File.ReadAllText(Path.Combine(AppFolder, "Services", "MarketingShotCapturer.cs")).Replace("\r\n", "\n");
        int theme = source.IndexOf("root.RequestedTheme = theme;", StringComparison.Ordinal);
        int sync = source.IndexOf("WindowTheme.Sync(window);", StringComparison.Ordinal);
        Assert.True(theme >= 0 && sync > theme, "Dress must set the content's theme and THEN sync the caption.");
    }
}

using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// #913, read off the source: the section preview's WebView2 is made on its
/// own environment with crash reporting to Microsoft turned off
/// (<c>IsCustomCrashReportingEnabled = true</c>) and with SmartScreen's
/// reputation check turned off on the view
/// (<c>IsReputationCheckingRequired = false</c>), and every place the pane's
/// browser is made goes through that. Neither setting changes a contact in a
/// run without a crash or an off-computer page, so this test, not a
/// measurement, is what holds them (windows-app/notes/806-win-webview.md).
/// </summary>
public class PreviewBrowserPrivacySourceTests
{
    private static string Read(string file) => File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
        "windows-app", "Plantoir", "Views", file));

    private static string WithoutComments(string code) =>
        Regex.Replace(Regex.Replace(code, @"/\*.*?\*/", "", RegexOptions.Singleline), @"//[^\n]*", "");

    private static string Body(string code, string header, string file)
    {
        int at = code.IndexOf(header, StringComparison.Ordinal);
        Assert.True(at >= 0, $"'{header}' is no longer in {file}");
        int open = code.IndexOf('{', at);
        int depth = 0;
        for (int i = open; i < code.Length; i++)
        {
            if (code[i] == '{') depth++;
            else if (code[i] == '}' && --depth == 0) return code[open..(i + 1)];
        }
        throw new InvalidOperationException("unbalanced braces");
    }

    [Fact]
    public void ThePreviewsEnvironmentKeepsCrashReportsOnTheComputer()
    {
        string code = WithoutComments(Read("PreviewBrowserEnvironment.cs"));
        string get = Body(code, "public static Task<CoreWebView2Environment> GetAsync(", "PreviewBrowserEnvironment.cs");
        Assert.Matches(@"new\s+CoreWebView2EnvironmentOptions\s*\{[^}]*\bIsCustomCrashReportingEnabled\s*=\s*true\b[^}]*\}", get);
        Assert.Matches(@"CoreWebView2Environment\.CreateWithOptionsAsync\([^;]*\boptions\b", get);
    }

    [Fact]
    public void ThePreviewsViewHasSmartScreenTurnedOff()
    {
        string code = WithoutComments(Read("PreviewBrowserEnvironment.cs"));
        string apply = Body(code, "public static void ApplyViewSettings(", "PreviewBrowserEnvironment.cs");
        Assert.Matches(@"\.Settings\.IsReputationCheckingRequired\s*=\s*false\s*;", apply);
    }

    [Fact]
    public void EveryPlaceThePanesBrowserIsMadeUsesBoth()
    {
        string code = WithoutComments(Read("SectionDetailView.xaml.cs"));
        string ensure = Body(code, "private async Task EnsurePreviewBrowserAsync(", "SectionDetailView.xaml.cs");
        Assert.Matches(@"Preview\.EnsureCoreWebView2Async\(\s*await\s+PreviewBrowserEnvironment\.GetAsync\(\)\s*\)", ensure);
        Assert.Matches(@"PreviewBrowserEnvironment\.ApplyViewSettings\(\s*Preview\.CoreWebView2\s*\)", ensure);
        // No other call makes the pane's browser on the default environment.
        Assert.Single(Regex.Matches(code, @"\.EnsureCoreWebView2Async\("));
        Assert.DoesNotMatch(@"\bPreview\.Source\s*=", code);
    }
}

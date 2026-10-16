using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// #514, read off the section window's source: every load the APP makes goes
/// through the two methods that mark it in the ledger, the root is the only
/// address kept in <c>_previewUrl</c>, and only the teacher's press asks for
/// the page last viewed. A load that slipped past the ledger would be
/// remembered as the teacher's, and the first rebuild would erase the page
/// being read — the mac's 504 plan review's blocker.
/// </summary>
public class PreviewNavigationSourceTests
{
    private static string Source => File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
        "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs"));

    private static string WithoutComments(string code) =>
        Regex.Replace(Regex.Replace(code, @"/\*.*?\*/", "", RegexOptions.Singleline), @"//[^\n]*", "");

    private static string Body(string code, string header)
    {
        int at = code.IndexOf(header, StringComparison.Ordinal);
        Assert.True(at >= 0, $"'{header}' is no longer in SectionDetailView.xaml.cs");
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
    public void EveryAppLoadGoesThroughTheLedger()
    {
        string code = WithoutComments(Source);
        Assert.DoesNotMatch(@"\bPreview\.Source\s*=", code);
        string navigate = Body(code, "private async Task NavigateAsAppAsync(");
        string reload = Body(code, "private async Task ReloadAsAppAsync(");
        string outside = code.Replace(navigate, "").Replace(reload, "");
        Assert.Matches(@"_ledger\.AppLoadRequested\(", navigate);
        Assert.Matches(@"_ledger\.AppLoadRequested\(", reload);
        Assert.DoesNotMatch(@"\.Navigate\(", outside);
        Assert.DoesNotMatch(@"\.Reload\(", outside);
    }

    [Fact]
    public void ThePreviewUrlHoldsTheRootOrNothing()
    {
        var assigned = Regex.Matches(WithoutComments(Source), @"\b_previewUrl\s*=\s*([^;]+);")
                            .Select(m => m.Groups[1].Value.Trim()).Distinct().OrderBy(v => v).ToList();
        Assert.Equal(new[] { "null", "root" }, assigned);
    }

    [Fact]
    public void OnlyTheTeachersPressAsksForThePageLastViewed()
    {
        string code = WithoutComments(Source);
        var asking = Regex.Matches(code, @"WaitForPreviewServer\(\s*new\b").Count;
        Assert.Equal(1, asking);
        Assert.Contains("await WaitForPreviewServer(new StartPageRequest(atLastViewed, frontPageWasJustChanged));",
                        Body(code, "private async Task PressPreviewAsync("));
        // The automated starts and the smoke hook: the front page.
        Assert.Contains("await WaitForPreviewServer();", Body(code, "private async void StartAutomatedPreview("));
        Assert.Contains("PressPreviewAsync(atLastViewed: false)", code);
    }

    [Fact]
    public void ARunThatEndedDuringTheAskOpensNothing()
    {
        // L-b of batch 6's review: the server can die while the page is being
        // asked about, with no cancel. The press must check the run itself,
        // after the ask and before any load, or it loads a dead port.
        string open = Body(WithoutComments(Source), "private async Task OpenTheSiteAsync(");
        int check = open.IndexOf("if (!_previewRunner.IsRunning || _previewRunner.WasStoppedByUser)", StringComparison.Ordinal);
        Assert.True(check >= 0, "OpenTheSiteAsync no longer checks that the run is still going after the ask");
        Assert.True(check > open.IndexOf("PreviewStartPage.AskAsync(", StringComparison.Ordinal));
        Assert.True(check < open.IndexOf("LoadIfNeeded(", StringComparison.Ordinal));
        Assert.True(check < open.IndexOf("ActivityTrail.Note(", StringComparison.Ordinal));
    }
}

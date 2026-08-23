using System;
using System.Collections.Generic;
using System.IO;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

public class OutputParserTests
{
    [Fact]
    public void PreviewAddressComesFromTheAnnouncementLastWins()
    {
        string text = "noise\nPreview will be available at: http://localhost:8081/\n" +
                      "more\nPreview will be available at: http://localhost:8092/\n";
        var url = OutputParsers.PreviewAddress(text)!;
        Assert.Equal("127.0.0.1", url.Host);
        Assert.Equal(8092, url.Port);
    }

    [Fact]
    public void PreviewAddressIgnoresUnrelatedLines() =>
        Assert.Null(OutputParsers.PreviewAddress("Launching Quartz preview on http://localhost:8081\n"));

    [Fact]
    public void PublishedUrlPrefersLabelledLinesAndSkipsAdmin()
    {
        string text = " Netlify site created.\n Live URL: https://ics3u-s1.netlify.app\n Admin: https://app.netlify.com/sites/x\n";
        Assert.Equal("https://ics3u-s1.netlify.app/", OutputParsers.PublishedSiteUrl(text)!.ToString());
    }

    [Fact]
    public void PublishedFolderComesFromItsMarkerLastWins()
    {
        string text = "Published.\n Folder: C:\\old\\section1\nPUBLISHED_FOLDER=C:\\old\\section1\n" +
                      "noise\nPUBLISHED_FOLDER=C:\\Users\\pat\\site\\section1\n";
        Assert.Equal(@"C:\Users\pat\site\section1", OutputParsers.PublishedFolder(text));
    }

    [Fact]
    public void ANetlifyPublishHasNoFolderMarker() =>
        Assert.Null(OutputParsers.PublishedFolder(" Live URL: https://x.netlify.app\n✅ Deploy complete.\n"));

    [Fact]
    public void RepeatPublishPlainHttpIsPromoted()
    {
        string text = " Using existing Netlify site for this section.\n Site: http://ics3u-s1.netlify.app\n";
        Assert.Equal("https://ics3u-s1.netlify.app/", OutputParsers.PublishedSiteUrl(text)!.ToString());
    }

    [Fact]
    public void CustomDomainSiteIsRecognizedFromItsLabel()
    {
        string text = " Site URL: https://ics3u.school.ca/welcome\n";
        Assert.Equal("https://ics3u.school.ca/welcome", OutputParsers.PublishedSiteUrl(text)!.ToString());
    }

    [Fact]
    public void EmojiGluedOntoTheUrlIsStripped()
    {
        // The pseudo console merged "✅ Deploy complete." onto the URL line.
        string text = " Site URL: https://exc2o-s1-2026-gordon.netlify.app✅ Deploy complete.\n";
        Assert.Equal("https://exc2o-s1-2026-gordon.netlify.app/", OutputParsers.PublishedSiteUrl(text)!.ToString());
    }

    [Fact]
    public void EmojiGluedWithNoSpaceIsStripped()
    {
        string text = " Site URL: https://exc2o-s1-2026-gordon.netlify.app✅Deploy\n";
        Assert.Equal("https://exc2o-s1-2026-gordon.netlify.app/", OutputParsers.PublishedSiteUrl(text)!.ToString());
    }

    [Fact]
    public void DashboardOnlyOutputYieldsNothing() =>
        Assert.Null(OutputParsers.PublishedSiteUrl(" Admin: https://app.netlify.com/sites/x\nsee https://docs.netlify.com/x\n"));

    [Fact]
    public void CustomDomainSwapsHostKeepsPathForcesHttps()
    {
        var swapped = OutputParsers.ApplyingCustomDomain("ics3u.school.ca",
            new Uri("http://ics3u-s1.netlify.app/notes/page"));
        Assert.Equal("https://ics3u.school.ca/notes/page", swapped.ToString());
    }

    [Fact]
    public void UploadCountsAreParsedLastWins()
    {
        Assert.Equal((125, 234), OutputParsers.UploadProgress(" …uploaded 100/234 required files\n …uploaded 125/234 required files\n"));
        Assert.Equal(234, OutputParsers.UploadTotal(" Netlify requires 234 file(s) for this deploy.\n"));
        Assert.Null(OutputParsers.UploadProgress("nothing uploaded here\n"));
    }

    [Fact]
    public void BuildStepsComeFromBuildKitLines()
    {
        Assert.Equal((7, 15), OutputParsers.BuildStepProgress("#12 [ 7/15] RUN apt-get update\n"));
        Assert.Null(OutputParsers.BuildStepProgress("[7/15] not a hash line\n"));
    }

    [Fact]
    public void ExampleCourseCodeIsReadBack()
    {
        Assert.Equal("XXX2O", OutputParsers.ExampleCourseCode("EXAMPLE_COURSE_CODE=EXC2O\nEXAMPLE_COURSE_CODE=XXX2O\n"));
        Assert.Null(OutputParsers.ExampleCourseCode("no code here"));
    }
}

public class QuestionParserTests
{
    [Fact]
    public void BracketedDefaultMovesIntoTheAnswerField()
    {
        var asked = QuestionParser.SeparateDefaultAnswer("Enter Netlify site name [ics3u-s3-2026-gordon]:");
        Assert.Equal("Enter Netlify site name:", asked.Question);
        Assert.Equal("ics3u-s3-2026-gordon", asked.SuggestedAnswer);
    }

    [Fact]
    public void DefaultPrefixIsUnderstood()
    {
        var asked = QuestionParser.SeparateDefaultAnswer("Enter the course code (e.g. ICS3U) [Default: ICS3U]:");
        Assert.Equal("ICS3U", asked.SuggestedAnswer);
    }

    [Theory]
    // The colour-scheme picker footer, however the pseudo console lays it out —
    // on its own line, or merged onto the tail of the last swatch line.
    [InlineData("Use ← / → (or 'p' / 'n') to browse, Enter to select. Press 'q' to keep previous choice.", true)]
    [InlineData("  textHighlight Use ← / → (or 'p' / 'n') to browse, Enter to select. Press 'q'.", true)]
    [InlineData("Enter the course code (e.g. ICS3U) [Default: ICS3U]:", true)]
    [InlineData("Select 1-27 or type a code [Default: en-US]:", true)]
    [InlineData(">", true)]
    [InlineData("Light Mode:", true)]     // still prompt-shaped; the settle wait keeps it from being answered mid-render
    [InlineData("  secondary", false)]    // a bare swatch line is not a prompt
    [InlineData("Copied per-section file: Private Notes.md", false)]
    public void CreatorPromptShapesAreRecognized(string line, bool expected) =>
        Assert.Equal(expected, Plantoir.Core.Scripting.NewCourseCreator.LooksLikePrompt(line));

    [Fact]
    public void ChoiceListsStayInTheWording()
    {
        var asked = QuestionParser.SeparateDefaultAnswer("Overwrite? [Y/n]:");
        Assert.Equal("", asked.SuggestedAnswer);
        Assert.Contains("[Y/n]", asked.Question);
    }

    [Fact]
    public void CancelKeystrokeAsideIsHiddenButCaptured()
    {
        string prompt = "Choose a different Netlify site name (or 'q' to cancel) [ics3u-s3-2026-gordon-01]:";
        var asked = QuestionParser.SeparateDefaultAnswer(prompt);
        Assert.Equal("Choose a different Netlify site name:", asked.Question);
        Assert.Equal("q", asked.CancelToken);
        Assert.Equal("ics3u-s3-2026-gordon-01", asked.SuggestedAnswer);
    }

    [Fact]
    public void InformativeAsidesAreKept() =>
        Assert.Equal("Install the Example Course now? (y/n)", QuestionParser.Asked("Install the Example Course now? (y/n)"));

    [Fact]
    public void UnclosedBracketIsNotAnAside() =>
        Assert.Equal("weird (unclosed", QuestionParser.Asked("weird (unclosed"));

    [Theory]
    [InlineData("Enter something:", true)]
    [InlineData("What is your last name?", true)]
    [InlineData(">", true)]
    [InlineData("Install? (y/n) proceeding", true)]
    [InlineData("Just some progress line", false)]
    public void PromptShapesAreRecognized(string line, bool expected) =>
        Assert.Equal(expected, QuestionParser.LooksLikeQuestion(line));
}

public class FailureExplainerTests
{
    [Fact]
    public void RateLimitReadsTheResetWindow()
    {
        string output = "Netlify API error 429: rate limited\nWindow resets at: 2026-08-11 01:00:00 EDT (in ~59s).";
        Assert.Equal("Netlify is limiting how often websites can be deployed right now. Try deploying again in about a minute.",
            FailureExplainer.Explanation(output));
        Assert.Contains("in about 3 minutes", FailureExplainer.WaitDescription("(in ~150s)"));
        Assert.Equal("in a few minutes", FailureExplainer.WaitDescription("no marker"));
    }

    [Fact]
    public void TokenProblemsAreExplained()
    {
        Assert.Contains("isn't connected yet", FailureExplainer.Explanation("❌ Netlify token missing."));
        Assert.Contains("didn't accept your access token", FailureExplainer.Explanation("Netlify API error 401: unauthorized"));
    }

    [Fact]
    public void ConnectionAndMissingBuildAreExplained()
    {
        Assert.Contains("couldn't reach the internet", FailureExplainer.Explanation("curl: Could not resolve host api.netlify.com"));
        Assert.Contains("hasn't been built yet", FailureExplainer.Explanation("Built site not found at: /x"));
    }

    [Fact]
    public void UnrecognizedFailuresStayQuiet() =>
        Assert.Null(FailureExplainer.Explanation("something exploded mysteriously"));

    [Fact]
    public void UnreadableFolderIsExplainedGently()
    {
        string output = "Get-FileHash : The file '...\\Plantoir.dll' ... [Write-Error], WriteErrorException\n" +
                        "+ FullyQualifiedErrorId : FileReadError,Get-FileHash";
        string? message = FailureExplainer.Explanation(output);
        Assert.NotNull(message);
        Assert.Contains("couldn't read every file", message);
        Assert.Contains("Try a folder you own", message);
    }

    [Fact]
    public void AccessDeniedIsExplainedGently() =>
        Assert.Contains("couldn't read every file",
            FailureExplainer.Explanation("icacls: Access is denied.")!);
}

public class TranscriptBuilderTests
{
    [Fact]
    public void CrLfIsANormalLineEnding()
    {
        var transcript = new TranscriptBuilder();
        transcript.Append("hello\r\nworld\r\n");
        Assert.Equal(new[] { "hello", "world" }, transcript.Lines);
    }

    [Fact]
    public void LoneCarriageReturnRestartsTheLine()
    {
        var transcript = new TranscriptBuilder();
        transcript.Append("spinner |\rspinner /\rspinner done\r\n");
        Assert.Equal(new[] { "spinner done" }, transcript.Lines);
    }

    [Fact]
    public void PendingCarriageReturnCarriesAcrossChunks()
    {
        var transcript = new TranscriptBuilder();
        transcript.Append("line\r");
        transcript.Append("\nnext");
        Assert.Equal(new[] { "line" }, transcript.Lines);
        Assert.Equal("next", transcript.CurrentLine);
    }

    [Fact]
    public void AnsiSequencesAreStripped()
    {
        var transcript = new TranscriptBuilder();
        transcript.Append("\x1b[32mgreen\x1b[0m and \x1b]0;title\x07plain\r\n");
        Assert.Equal(new[] { "green and plain" }, transcript.Lines);
    }

    [Fact]
    public void RetainedLinesAreCapped()
    {
        var transcript = new TranscriptBuilder();
        for (int i = 0; i < 4200; i++) transcript.Append($"line {i}\r\n");
        Assert.Equal(TranscriptBuilder.MaximumRetainedLines, transcript.Lines.Count);
        Assert.Equal("line 4199", transcript.Lines[^1]);
    }

    [Fact]
    public void RecentTextWalksBackwards()
    {
        var transcript = new TranscriptBuilder();
        transcript.Append("aaaa\r\nbbbb\r\ncccc");
        string recent = transcript.RecentText(10);
        Assert.Contains("cccc", recent);
        Assert.DoesNotContain("aaaa", recent);
    }
}

public class TaskMilestoneTests
{
    [Fact]
    public void EveryLabelEndsWithAnEllipsis()
    {
        foreach (var list in TaskMilestones.AllLists)
            foreach (var milestone in list)
                Assert.EndsWith("…", milestone.Label);
    }

    [Fact]
    public void NoLabelMentionsMachinery()
    {
        foreach (var list in TaskMilestones.AllLists)
            foreach (var milestone in list)
            {
                Assert.DoesNotContain("Docker", milestone.Label);
                Assert.DoesNotContain("WSL", milestone.Label);
                Assert.DoesNotContain("script", milestone.Label, StringComparison.OrdinalIgnoreCase);
            }
    }

    [Fact]
    public void FolderPublishingNeverMentionsNetlify()
    {
        // Row 102d: a folder publish saying "Connecting to Netlify…" was
        // wrong twice over. The folder lists must never say the word.
        foreach (var list in new[] { TaskMilestones.DeployToFolder, TaskMilestones.BuildAndDeployToFolder })
            foreach (var milestone in list)
                Assert.DoesNotContain("Netlify", milestone.Label, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void CloudflarePublishingNeverMentionsNetlify()
    {
        // Same rule as folder publishing: a Cloudflare publish that said
        // "Connecting to Netlify…" would be naming the wrong company.
        foreach (var list in new[] { TaskMilestones.DeployToCloudflare, TaskMilestones.BuildAndDeployToCloudflare })
            foreach (var milestone in list)
                Assert.DoesNotContain("Netlify", milestone.Label, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ACloudflareLiveUrlIsFoundByItsLabel()
    {
        // deploy.py prints "Live URL: https://<project>.pages.dev" — the same
        // label the Netlify path uses, which is why no parser change was
        // needed. wrangler's own chatter must not win over it.
        const string transcript = """
             Uploading the built site to Cloudflare…
            Deploying to https://abc123.mcv4u-s1-2026-gordon.pages.dev
             Live URL: https://mcv4u-s1-2026-gordon.pages.dev

            ✅ Deploy complete.
            """;
        Uri? found = OutputParsers.PublishedSiteUrl(transcript);
        Assert.NotNull(found);
        Assert.Equal("https://mcv4u-s1-2026-gordon.pages.dev", found!.ToString().TrimEnd('/'));
    }

    [Fact]
    public void ALaterMarkerImpliesEarlierSteps()
    {
        var runner = new ScriptRunner(uiContext: null) { Milestones = TaskMilestones.Preview };
        runner.ReceiveOutput("Quartz v4 building...\n");
        Assert.Equal(5, runner.MilestonesReached);
        Assert.Equal("Opening the preview…", runner.CurrentMilestoneLabel);
    }

    [Fact]
    public void AMarkerSplitAcrossChunksStillMatches()
    {
        var runner = new ScriptRunner(uiContext: null) { Milestones = TaskMilestones.Preview };
        runner.ReceiveOutput("Copying shared fol");
        runner.ReceiveOutput("ders into place\n");
        Assert.Equal(2, runner.MilestonesReached);
    }

    [Fact]
    public void UploadCountsBecomeStepDetailAndClearOnAdvance()
    {
        var runner = new ScriptRunner(uiContext: null) { Milestones = TaskMilestones.Deploy };
        runner.ReceiveOutput("Delta deploy created\n");
        runner.ReceiveOutput(" …uploaded 125/234 required files\n");
        Assert.Equal("125 of 234", runner.StepDetail);
        runner.ReceiveOutput("Deploy complete\n");
        Assert.Equal("", runner.StepDetail);
    }
}

/// <summary>
/// Every "launcher"-origin marker in <see cref="TaskMilestones"/> (per
/// contracts/app-rules.json → markerOrigins) is Windows' own text — printed
/// by setup.ps1/preview.ps1/deploy.ps1, never by the shared Python. Nothing
/// caught it when those four went stale on 2026-08-19: the native-toolchain
/// rewrite (setup.ps1's "Native toolchain (no container)" block) dropped
/// "Setting up this PC"/"Building your website builder"/"Ensuring container
/// is running"/"Starting container if needed" from every real launcher run,
/// but TaskMilestones.cs — last touched the day before — kept matching
/// against them, so those progress stages could never be reached: the bar
/// sat at 0% until a later, still-real marker jumped it forward several
/// steps at once (see WINDOWS-HANDOFF.md item 5). This reads the ACTUAL
/// .ps1 files rather than a hand-typed transcript, so a future launcher
/// rewrite that drops a line these markers depend on fails here instead of
/// silently stalling a teacher's progress bar again.
/// </summary>
public class TaskMilestoneLauncherMarkerTests
{
    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }

    /// <summary>Marker text → the launcher that must actually print it.</summary>
    private static readonly IReadOnlyDictionary<string, string> LauncherOnlyMarkers = new Dictionary<string, string>
    {
        ["Detected host timezone offset"] = "setup.ps1",
        ["Running the website builder on this PC"] = "preview.ps1",
        ["Host timezone offset"] = "deploy.ps1",
        ["from this PC"] = "deploy.ps1",
        ["to a folder"] = "deploy.ps1",
        ["PUBLISHED_FOLDER="] = "deploy.ps1",
    };

    [Fact]
    public void EveryLauncherOnlyMarkerAppearsInItsOwnScript()
    {
        foreach (var (marker, script) in LauncherOnlyMarkers)
        {
            string text = File.ReadAllText(Path.Combine(RepoRoot, script));
            Assert.True(text.Contains(marker, StringComparison.Ordinal),
                $"Expected \"{marker}\" to appear in {script}, but it does not — " +
                "TaskMilestones.cs is matching against text the launcher no longer prints.");
        }
    }

    /// <summary>
    /// The four mac-only strings this class exists to keep out of
    /// TaskMilestones.cs — a plain guard so a future edit that reaches for
    /// the mac's phrasing (the exact mistake that shipped 2026-08-18) fails
    /// immediately rather than waiting for a teacher's progress bar to stall.
    /// </summary>
    [Fact]
    public void NoMilestoneMatchesAMacOnlyLauncherString()
    {
        string[] macOnly =
        {
            "Setting up this Mac",
            "Setting up this PC",
            "Building your website builder",
            "Ensuring container is running",
            "Starting container if needed",
        };
        foreach (var list in TaskMilestones.AllLists)
            foreach (var milestone in list)
                foreach (var mac in macOnly)
                    Assert.DoesNotContain(mac, milestone.Marker, StringComparison.Ordinal);
    }
}

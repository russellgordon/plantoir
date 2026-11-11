using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The view's half of #728 (the mac's #706), which no model test can reach —
/// the window cannot be built in a unit test, so its shape is read from the
/// source, as <c>SectionDetailTeardownTests</c> reads the teardown. Each of
/// these is red on the code before #728, whose deploy runner was a field of
/// the view.
/// </summary>
public sealed class SectionDeployRunSourceTests
{
    private static string Source(params string[] parts) =>
        File.ReadAllText(Path.Combine(new[] { ContractLoader.RepositoryRoot, "windows-app", "Plantoir" }.Concat(parts).ToArray())).Replace("\r\n", "\n");

    private static string View => Source("Views", "SectionDetailView.xaml.cs");

    /// <summary>From <paramref name="signature"/> to the member's closing brace at four spaces.</summary>
    private static string Body(string source, string signature)
    {
        int start = source.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start > 0, $"no {signature}");
        int end = source.IndexOf("\n    }\n", start, StringComparison.Ordinal);
        Assert.True(end > start, $"no end to {signature}");
        return source[start..end];
    }

    /// <summary>The deploy state is the app's, found in <c>SectionRuns</c>, never the view's own.</summary>
    [Fact]
    public void TheViewBindsToTheSectionsRun()
    {
        string view = View;
        Assert.DoesNotContain("new MultiDestinationDeployRunner(", view);
        Assert.DoesNotContain("private bool _isPreparingDeploy", view);
        Assert.DoesNotContain("private bool _isAskingAboutLaterClasses", view);
        Assert.Contains("SectionRuns.Deploy(_folderThisSectionRegisteredIn, course.Code, sectionNumber)", view);
    }

    /// <summary>Nothing a view runs on appearing deploys: coming back starts nothing.</summary>
    [Fact]
    public void AppearingNeverDeploys()
    {
        string loaded = Body(View, "    private void OnLoaded(");
        foreach (string forbidden in new[] { "DeployAsync(", "Deploy_Click(", "RunAsync(", "PressDeploy(" })
            Assert.DoesNotContain(forbidden, loaded);
        Assert.Contains("EndingToHideOnAppearing()", loaded);
        Assert.True(loaded.IndexOf("EndingToHideOnAppearing()", StringComparison.Ordinal)
                    < loaded.IndexOf("TakeWhatTheDeployLeft()", StringComparison.Ordinal),
                    "an appearing view must decide what to hide BEFORE it takes the ending");
    }

    /// <summary>
    /// The deploy takes its run ONCE, from the folder it checked, and uses only
    /// that object — a window re-pointed at another folder mid-await must not
    /// split one deploy across two runs (the mac's plan review, H1).
    /// </summary>
    [Fact]
    public void TheDeployTakesItsRunOnce()
    {
        string deploy = Body(View, "    private async Task<string?> DeployAsync(");
        int taken = deploy.IndexOf("run = SectionRuns.Deploy(workspacePath, _course.Code, _sectionNumber);", StringComparison.Ordinal);
        Assert.True(taken > 0, "DeployAsync must take its run from the folder it checked");
        string after = deploy[taken..];
        Assert.DoesNotContain("_deployRun.", after);
        Assert.Contains("run.Folder = workspacePath;", after);
        Assert.Contains("run.Hold(", after);
        Assert.Contains("run.EndPublish()", after);
        // Between the deploy ending and its announcement, the publish ends:
        // the runner's IsRunning=false arrives first, so a view redrawing on
        // the announcement must already see the section free.
        int ended = after.IndexOf("await running;", StringComparison.Ordinal);
        int announced = after.IndexOf("run.NoteEnded(", StringComparison.Ordinal);
        Assert.True(ended > 0 && announced > ended, "the deploy must await its runner, then announce the ending");
        Assert.Contains("run.EndPublish();", after[ended..announced]);
        // The deploy's build claim belongs to the run: handed to the view's
        // preview build claim, Unloaded gave it back mid-deploy (#728).
        Assert.DoesNotContain("_buildWork = deployBuild", deploy);
        Assert.DoesNotContain("_publishWork = deployPublish", deploy);
        // ...while the PREVIOUS build claim is still let go (#728 plan review, 3).
        Assert.Contains("ReleaseBuildClaim();", after);
    }

    /// <summary>Cancel aims at the run's folder; the view lets go of the shared run when it leaves.</summary>
    [Fact]
    public void CancelAimsAtTheRunAndTheViewLetsGoOnUnloaded()
    {
        string view = View;
        string cancel = Body(view, "    private void CancelDeploy(");
        Assert.Contains("_deployRun.Folder", cancel);
        Assert.Contains("_deployRun.Runner.Cancel()", cancel);
        string unloaded = Body(view, "    private void OnUnloaded(");
        Assert.Contains("_deployRun.PropertyChanged -= OnDeployRunChanged", unloaded);
        Assert.Contains("_deployRun.Runner.PropertyChanged -= OnDeployRunnerChanged", unloaded);
    }

    /// <summary>A view that came back has no preview start of its own: the section's last one decides (the mac's L3).</summary>
    [Fact]
    public void TheLaterPreviewIsAskedOfTheSection()
    {
        string view = View;
        Assert.Contains("_deployRun.IsShown(_endingHiddenHere, _previewRunner.StartedAt)", view);
        Assert.Equal(2, CountOf(view, "_deployRun.NotePreviewStarted("));
    }

    /// <summary>The readers that used the view's own runner now ask the run (#728 plan review, finding 2).</summary>
    [Fact]
    public void EveryDeployReaderAsksTheRun()
    {
        string view = View;
        Assert.Contains("internal bool IsBusy => _previewRunner.IsRunning || DeployIsUnderWay;", view);
        Assert.Contains("internal bool IsDeploying => DeployIsUnderWay;", view);
        Assert.Contains("SectionDeployRun.UnderWay(_deployRun, _folderThisSectionRegisteredIn, _course.Code, _sectionNumber)", view);
        Assert.Contains("if (_previewRunner.IsRunning || DeployIsUnderWay) return;", Body(view, "    private void OfferTheLinksChecklistIfWaiting("));
        // The Endings handler redraws: the runner's IsRunning=false arrives before the publish ends.
        string handler = Body(view, "    private void OnDeployRunChanged(");
        Assert.Contains("RefreshChrome();", handler);
        Assert.Contains("TakeWhatTheDeployLeft();", handler);
    }

    /// <summary>The window's busy answer finds the section's run by the CALLER's folder, on screen or not (plan review, 5).</summary>
    [Fact]
    public void IsSectionBusyAsksTheRunsByTheCallersFolder()
    {
        string body = Body(Source("MainWindow.xaml.cs"), "    public bool IsSectionBusy(");
        Assert.Contains("SectionRuns.Find(folder, courseCode, section)", body);
        Assert.Contains("SectionDeployRun.UnderWay(", body);
        Assert.DoesNotContain("DetailHost.Content", body);
    }

    /// <summary>The progress panel lets go of shared runners, and one window asks a question, not two.</summary>
    [Fact]
    public void TheProgressPanelLetsGoAndAsksOnce()
    {
        string panel = Source("Views", "TaskProgressView.xaml.cs");
        Assert.Contains("runner.PropertyChanged -= handler", panel);
        Assert.Contains("s_asking", panel);
        Assert.Contains("if (runner.IsAwaitingInput) _ = AskQuestion(runner);", panel);
    }

    private static int CountOf(string text, string what)
    {
        int count = 0;
        for (int at = text.IndexOf(what, StringComparison.Ordinal); at >= 0; at = text.IndexOf(what, at + 1, StringComparison.Ordinal)) count++;
        return count;
    }
}

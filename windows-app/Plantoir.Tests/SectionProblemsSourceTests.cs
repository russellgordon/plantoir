using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The window's half of #734 (the mac's #717), which no model test can reach
/// — the WinUI views cannot be built here, so their shape is read from the
/// source, comment lines taken out so a comment that names a member cannot
/// satisfy a scan for the code. Each assertion is a statement about what the
/// code DOES, and each was seen to go red with the line it guards commented
/// out (the closing comment on #734 lists them).
/// </summary>
public sealed class SectionProblemsSourceTests
{
    private static string Source(params string[] parts) =>
        string.Join("\n", File.ReadAllText(Path.Combine(new[] { ContractLoader.RepositoryRoot, "windows-app", "Plantoir" }.Concat(parts).ToArray()))
            .Replace("\r\n", "\n").Split('\n')
            .Where(line => !line.TrimStart().StartsWith("//", StringComparison.Ordinal)));

    private static string View => Source("Views", "SectionDetailView.xaml.cs");

    /// <summary>From <paramref name="signature"/> to the member's closing brace at four spaces.</summary>
    private static string Body(string source, string signature)
    {
        int start = source.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start >= 0, $"no {signature}");
        int end = source.IndexOf("\n    }\n", start, StringComparison.Ordinal);
        Assert.True(end > start, $"no end to {signature}");
        return source[start..end];
    }

    /// <summary>ONE alert, raised from the record and the store — never from a run's findings — and held by one view of the section.</summary>
    [Fact]
    public void OneAlertIsRaisedFromTheRecord()
    {
        string raise = Body(View, "    private async Task RaiseTheProblemsAlertIfDueAsync(");
        Assert.Contains("SectionProblems.RecordWithAnAlertDue(folder, _course.Code, _sectionNumber)", raise);
        Assert.Contains("SectionProblems.ClaimTheAlert(folder, _course.Code, _sectionNumber, due.AlertKey)", raise);
        Assert.Contains("SectionProblems.ReleaseTheAlert(folder, _course.Code, _sectionNumber);", raise);
        Assert.Contains("if (_healthDialogIsUp || _todaysClassQuestionUp || _linksChecklistUp) return;", raise);
        Assert.Contains("SectionProblems.Answer(due, answer, folder, _course.Code, _sectionNumber);", raise);
        Assert.Contains("if (choice is { } answered && !_windowIsClosing)", raise);
        Assert.Contains("_windowIsClosing = true;", Body(View, "    internal void LetGoAsTheWindowCloses("));
        Assert.Contains("ShowTab(SectionProblems.Tab.Problems, focusTheTable: true);", raise);
    }

    /// <summary>The per-build dialog, its queue and the route that fed them are gone.</summary>
    [Fact]
    public void ThePerBuildDialogIsGone()
    {
        string view = View;
        Assert.DoesNotContain("FolderProblemsDialog.Findings(", view);
        Assert.DoesNotContain("FolderProblemQueue", view);
        Assert.DoesNotContain("NoteHealthFindings(", view);
        Assert.DoesNotContain("nameof(_previewRunner.HealthFindings)", view);
        Assert.DoesNotContain("public static ContentDialog Findings(", Source("Views", "FolderProblemsDialog.cs"));
        Assert.False(File.Exists(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Models", "FolderProblemQueue.cs")));
    }

    /// <summary>The alert carries no box (#731: the mac's suppression toggle was window-wide), and Show is its default.</summary>
    [Fact]
    public void TheAlertCarriesNoBox()
    {
        string alert = Body(Source("Views", "FolderProblemsDialog.cs"), "    public static ContentDialog NewProblems(");
        Assert.DoesNotContain("CheckBox", alert);
        Assert.Contains("PrimaryButtonText = SectionProblemsWording.Show,", alert);
        Assert.Contains("DefaultButton = ContentDialogButton.Primary,", alert);
        Assert.Contains("CloseButtonText = SiteHealthRepair.CloseTitle(besideAnotherButton: true, isARepair: false),", alert);
    }

    /// <summary>
    /// The tab never moves the web view: it is collapsed under the Problems
    /// tab, never removed from the tree and never re-sourced — and what is
    /// under the tab leaves the Tab order with it.
    /// </summary>
    [Fact]
    public void TheWebViewStaysMountedUnderTheTab()
    {
        string view = View;
        string chrome = Body(view, "    private void RefreshChrome(");
        Assert.Contains("Preview.Visibility = previewShown && !problemsShown ? Visibility.Visible : Visibility.Collapsed;", chrome);
        Assert.Contains("BaseLayer.Visibility = problemsShown ? Visibility.Collapsed : Visibility.Visible;", chrome);
        Assert.Contains("ContentArea.Children.Add(_problemsView);", view);
        foreach (string signature in new[] { "    private void ShowTheProblems(", "    private void SectionTabs_SelectionChanged(", "    private void ShowTab(" })
        {
            string body = Body(view, signature);
            foreach (string forbidden in new[] { "Preview.Source", "Children.Remove", "Children.Clear", "Preview.Close", "NavigateToString" })
                Assert.DoesNotContain(forbidden, body);
        }
        string xaml = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SectionDetailView.xaml"));
        Assert.DoesNotContain("<TabView", xaml);
        Assert.Contains("<SelectorBar x:Name=\"SectionTabs\"", xaml);
    }

    /// <summary>The Problems view asks no disk whether an assistant is installed while it draws (#736's rule, held from the start).</summary>
    [Fact]
    public void TheProblemsViewSearchesNothingWhileItDraws()
    {
        string table = Source("Views", "SectionProblemsView.cs");
        Assert.DoesNotContain("IsAvailable", table);
        Assert.DoesNotContain("File.", table);
        Assert.DoesNotContain("Directory.", table);
        Assert.DoesNotContain("SectionProblemsRecord.Read(", table);
        // The tick rules are TickTable's, called rather than copied.
        Assert.Contains("TickTable.TickWithSpace(args, _list, row.Item, row.Box);", table);
        Assert.Contains("TickTable.Status(item, box);", table);
    }

    /// <summary>The sidebar's marker is read from the store's memory, on every reconcile and when the store says something moved.</summary>
    [Fact]
    public void TheSidebarReadsTheMarkerFromMemory()
    {
        string sidebar = Source("Views", "SidebarPane.xaml.cs");
        string reconcile = Body(sidebar, "    private void ReconcileSections(");
        Assert.Contains("row.HasProblems = SectionProblems.HasMarker(Workspace.WorkspacePath, course.Code, number);", reconcile);
        Assert.Contains("row.HasProblems = SectionProblems.HasMarker(folder, row.CourseCode, row.SectionNumber);",
                        Body(sidebar, "    public void RefreshProblemMarkers("));
        Assert.DoesNotContain("SectionProblemsRecord.Read(", sidebar);
        Assert.DoesNotContain("SectionProblems.Reload", sidebar);
        int rowStart = sidebar.IndexOf("public sealed class SidebarRow", StringComparison.Ordinal);
        string row = sidebar[rowStart..sidebar.IndexOf("public sealed partial class SidebarPane", rowStart, StringComparison.Ordinal)];
        Assert.Contains("PublishStopped is not null || HasProblems ? Visibility.Visible : Visibility.Collapsed;", row);
        Assert.Contains("$\"problemsBadge-{CourseCode}-section{SectionNumber}\"", row);
        string xaml = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SidebarPane.xaml"));
        Assert.Contains("AutomationProperties.HelpText=\"{x:Bind WarningTooltip, Mode=OneWay}\"", xaml);
        Assert.Contains("AutomationProperties.AutomationId=\"{x:Bind WarningId, Mode=OneWay}\"", xaml);
        Assert.DoesNotContain("scheduledPublishWarning", xaml);
    }

    /// <summary>
    /// The moments a record is read: the view's own preview's marker, a
    /// deploy's ending, the view appearing, the window becoming active
    /// (throttled), the courses loading, a marker from any run in this app.
    /// </summary>
    [Fact]
    public void TheRecordIsReadAtTheMomentsItCanHaveChanged()
    {
        string view = View;
        Assert.Contains("if (args.PropertyName == nameof(_previewRunner.ProblemsMarker) && _previewRunner.ProblemsMarker is not null)", view);
        Assert.Contains("ReadTheProblems();", Body(view, "    private void TakeWhatTheDeployLeft("));
        string loaded = Body(view, "    private void OnLoaded(");
        Assert.Contains("SectionProblems.Changed += OnProblemsChanged;", loaded);
        Assert.Contains("ReadTheProblems();", loaded);
        Assert.Contains("SectionProblems.Changed -= OnProblemsChanged;", Body(view, "    private void OnUnloaded("));
        Assert.Contains("QueueTheProblemsAlert();", Body(view, "    private void OnWindowActivated("));
        Assert.Contains("ScheduledHealthFindings.Take(", Body(view, "    private void TakeAnythingTheScheduledDeployFound("));

        string window = Source("MainWindow.xaml.cs");
        Assert.Contains("if (throttled && now - _problemsReadAt < TimeSpan.FromSeconds(3)) return;", Body(window, "    private void ReadTheProblems("));
        Assert.Contains("ReadTheProblems(throttled: true);", window);
        Assert.Contains("SectionProblems.MarkerArrived += ProblemsMarkerArrived;", window);
        Assert.Contains("SectionProblems.MarkerArrived -= ProblemsMarkerArrived;", window);
        Assert.Contains("if (args.PropertyName is nameof(WorkspaceViewModel.Courses)) ReadTheProblems(throttled: false);", window);
        Assert.Contains("SectionProblems.NoteMarker(problems);",
            File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Scripting", "ScriptRunner.cs")));
    }

    /// <summary>The links checklist FOLLOWS the alert (#379 after #734), and waits for a record that is current.</summary>
    [Fact]
    public void TheLinksChecklistFollowsTheAlert()
    {
        string present = Body(View, "    private async Task PresentTheLinksChecklistAsync(");
        int read = present.IndexOf("await ReadTheProblemsNowAsync();", StringComparison.Ordinal);
        int wait = present.IndexOf("SectionProblemsRules.TheChecklistWaits(", StringComparison.Ordinal);
        int up = present.IndexOf("_linksChecklistUp = true;", StringComparison.Ordinal);
        int offer = present.IndexOf("LinksChecklistDialog.OfferAsync(", StringComparison.Ordinal);
        Assert.True(read > 0 && wait > read, "the checklist reads the record, then waits by the one rule");
        // The flag the alert waits behind is set only once the checklist is
        // going on screen — never while it waits for the alert (review finding 1).
        Assert.True(up > wait && offer > up, "_linksChecklistUp is set after the wait and just before the checklist shows");
        Assert.DoesNotContain("_linksChecklistUp = true;", present[..wait]);
        // With nothing due it is shown in the SAME turn: the at-once test comes
        // before the first await, and the wait is only on the other branch.
        int atOnce = present.IndexOf("SectionProblemsRules.TheChecklistGoesAtOnce(", StringComparison.Ordinal);
        int firstAwait = present.IndexOf("await ", StringComparison.Ordinal);
        Assert.True(atOnce > 0 && atOnce < firstAwait, "the checklist asks whether it can go at once before it awaits anything");
        Assert.Contains("if (!SectionProblemsRules.TheChecklistGoesAtOnce(", present);
        // A view rebuilt while it waited hands the offer on, and the next view takes it.
        Assert.Contains("ChecklistsWaiting[SectionKey.For(folder, _course.Code, _sectionNumber)] = (offer, occasion);", present);
        Assert.Contains("ChecklistsWaiting.Remove(", Body(View, "    private void OfferTheLinksChecklistIfWaiting("));
        Assert.Contains("if (_healthDialogIsUp || _todaysClassQuestionUp || _linksChecklistUp) return;",
                        Body(View, "    private async Task RaiseTheProblemsAlertIfDueAsync("));
    }

    /// <summary>A due alert that could not get on screen is asked for again when whatever held the slot goes.</summary>
    [Fact]
    public void ADueAlertIsAskedForAgain()
    {
        string view = View;
        Assert.Contains("QueueTheProblemsAlert();", Body(view, "    private async Task<ContentDialogResult?> ShowDialogSafelyAsync("));
        Assert.Contains("QueueTheProblemsAlert();", Body(view, "    private async Task PresentRepairOutcomeAsync("));
        Assert.Contains("QueueTheProblemsAlert();", Body(view, "    private async Task<bool> OfferTodaysClassAsync("));
        Assert.Contains("QueueTheProblemsAlert();", Body(view, "    private async Task PresentTheLinksChecklistAsync("));
        string raise = Body(view, "    private async Task RaiseTheProblemsAlertIfDueAsync(");
        int notShown = raise.IndexOf("if (choice is null)", StringComparison.Ordinal);
        Assert.True(notShown > 0 && raise.IndexOf("QueueTheProblemsAlert();", notShown, StringComparison.Ordinal) > notShown);
    }
}

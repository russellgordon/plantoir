using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// Copy a Page from This Course… (#247, #384; mac <c>CopyPageSheet</c>). Three
/// questions — which page, into which course, which folder — then, when the
/// page links to others, a checklist in the FUTURE tense whose numbers follow
/// the ticks, then the result. Every rule is <see cref="CoursePageCopy"/>'s and
/// every sentence <see cref="CopyPageWording"/>'s; this file is the drawing.
/// </summary>
/// <remarks>
/// <para><b>One scroll region (#384).</b> On the checklist and on the result,
/// the rows AND every sentence that grows with the page count (skips, links
/// leading nowhere, pictures lines) are in ONE <see cref="ScrollViewer"/> with
/// a <see cref="FrameworkElement.MaxHeight"/>; the heading, "Copies start
/// hidden…", the backup line and the buttons stay outside it. The mac capped
/// only the rows first, and ~70 sentences pushed its buttons off the screen.</para>
///
/// <para><b>The page picker does not open on focus</b> — it suggests only on
/// typing (<see cref="AutoSuggestionBoxTextChangeReason.UserInput"/>): a list
/// that opens the moment the dialog appears covers the questions under it.</para>
///
/// <para><b>The checklist's ROWS do not move</b>: they are the first plan's
/// candidates; ticking re-plans and repaints only the numbers and sentences
/// below them. One backup per dialog, however many times "Copy another" is
/// pressed (<see cref="CoursePageCopy.Session"/>).</para>
///
/// <para>AutomationIds: <c>copyPagePicker</c>, <c>copyPageDestination</c>,
/// <c>copyPageFolder</c>, <c>copyPageAlsoLinked</c>, <c>copyPageScroll</c>,
/// <c>copyPageRow:&lt;name&gt;</c>, <c>copyPagePrimary</c>, <c>copyPageClose</c>.</para>
/// </remarks>
public sealed class CopyAPageDialog
{
    public const string ScrollAutomationId = "copyPageScroll";
    public const string PrimaryAutomationId = "copyPagePrimary";
    public const string CloseAutomationId = "copyPageClose";

    /// <summary>The scroll region's ceiling on the checklist and on the result (the mac's 380 and 320 points).</summary>
    public const double ChecklistMaxHeight = 380, ResultMaxHeight = 320;

    private enum Stage { Ask, Checklist, Result }

    private readonly Course _source;
    private readonly List<Course> _destinations;
    private readonly List<string> _offered;
    private readonly string _workspacePath;
    private readonly CoursePageCopy.Session _session;
    private readonly ContentDialog _dialog;
    private Stage _stage = Stage.Ask;

    private readonly AutoSuggestBox _picker = new() { Header = Say("whichPage"), PlaceholderText = Say("pagePickerPrompt") };
    private readonly ComboBox _destination = new() { Header = Say("whichCourse"), HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly ComboBox _folder = new() { Header = Say("whichFolder"), HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly CheckBox _alsoLinked = new() { Content = Say("alsoCopyLinkedPages"), IsChecked = true };
    private readonly TextBlock _askNote = new() { TextWrapping = TextWrapping.Wrap };
    private string? _chosenPage;

    private CoursePageCopy.Request? _request;
    private CoursePageCopy.Plan? _firstPlan;
    private CoursePageCopy.Plan? _plan;
    private readonly HashSet<string> _unticked = new(StringComparer.Ordinal);
    private readonly Dictionary<string, CheckBox> _rowBoxes = new(StringComparer.Ordinal);
    private StackPanel _sentences = new();
    private StackPanel? _askPanel;
    private bool _painting;
    private TextBlock _header = new();

    private static string Say(string key, params (string, string)[] fills) => CopyPageWording.Say(key, fills);

    private CopyAPageDialog(Course source, IEnumerable<Course> courses, string workspacePath)
    {
        _source = source;
        _workspacePath = workspacePath;
        _destinations = CoursePageCopy.Destinations(source, courses);
        _offered = CoursePageCopy.Offered(source);
        _session = new CoursePageCopy.Session(destination =>
            CourseArchiver.BackUpCourse(destination, Workspace.CoursesDirectory(workspacePath)));
        _dialog = new ContentDialog
        {
            Title = Say("sheetTitle", ("course", ReferenceCourse.NameWithYear(source, DateOnly.FromDateTime(DateTime.Today)))),
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        _dialog.Opened += (_, _) => TagButtons();
        _dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            args.Cancel = true;            // every stage decides for itself whether the dialog goes
            try { await PrimaryPressed(); }
            finally { deferral.Complete(); }
        };

        AutomationProperties.SetAutomationId(_picker, "copyPagePicker");
        AutomationProperties.SetAutomationId(_destination, "copyPageDestination");
        AutomationProperties.SetAutomationId(_folder, "copyPageFolder");
        AutomationProperties.SetAutomationId(_alsoLinked, "copyPageAlsoLinked");
        _picker.TextChanged += (box, args) =>
        {
            // Suggest only on typing — never on focus (the list would cover the questions).
            if (args.Reason != AutoSuggestionBoxTextChangeReason.UserInput) return;
            string typed = box.Text.Trim();
            var matches = _offered.Where(p => typed.Length == 0 || p.Contains(typed, StringComparison.OrdinalIgnoreCase))
                .Select(Shown).ToList();
            box.ItemsSource = matches.Count > 0 ? matches : new List<string> { Say("noPagesMatch") };
            _chosenPage = _offered.FirstOrDefault(p => Shown(p).Equals(box.Text, StringComparison.Ordinal));
            RefreshAsk();
        };
        _picker.SuggestionChosen += (_, args) =>
        {
            _chosenPage = _offered.FirstOrDefault(p => Shown(p) == args.SelectedItem as string);
            PreferTheSourceFolder();
            RefreshAsk();
        };
        _destination.ItemsSource = _destinations.Select(c => ReferenceCourse.ShownCode(c)).ToList();
        _destination.SelectionChanged += (_, _) => { FillFolders(); RefreshAsk(); };
        _folder.SelectionChanged += (_, _) => RefreshAsk();
        if (_destinations.Count > 0) _destination.SelectedIndex = 0;
        ShowAsk();
    }

    /// <summary>A page as the picker lists it: grouped by folder, folder first.</summary>
    private static string Shown(string relative) => relative.Replace("/", " › ")[..^3];

    private Course? Destination => _destination.SelectedIndex >= 0 ? _destinations[_destination.SelectedIndex] : null;

    private void FillFolders()
    {
        _folder.ItemsSource = Destination is { } d ? CoursePageCopy.FoldersOffered(d) : new List<string>();
        PreferTheSourceFolder();
    }

    /// <summary>The folder question starts on the page's own folder when the destination has one of that name.</summary>
    private void PreferTheSourceFolder()
    {
        if (_folder.ItemsSource is not List<string> folders || folders.Count == 0) return;
        string own = _chosenPage?.Split('/')[0] ?? "";
        int at = folders.FindIndex(f => f.Equals(own, StringComparison.OrdinalIgnoreCase));
        _folder.SelectedIndex = at >= 0 ? at : Math.Max(0, _folder.SelectedIndex);
    }

    // ---- Stage 1: the three questions -------------------------------------

    private void ShowAsk()
    {
        _stage = Stage.Ask;
        _dialog.PrimaryButtonText = "Copy";
        _dialog.CloseButtonText = _session.BackupName is null ? "Cancel" : "Done";
        // Built once and shown again on "Copy another": a control can have only one parent.
        if (_askPanel is null)
        {
            _askPanel = new StackPanel { Spacing = 10, MinWidth = 440 };
            _askPanel.Children.Add(_picker);
            _askPanel.Children.Add(_destination);
            _askPanel.Children.Add(_folder);
            _askPanel.Children.Add(_alsoLinked);
            _askPanel.Children.Add(_askNote);
            foreach (string key in new[] { "copiesStartHidden", "datesAreKept", "nothingIsWrittenOver" })
                _askPanel.Children.Add(new TextBlock { Text = Say(key), TextWrapping = TextWrapping.Wrap, Opacity = 0.8 });
        }
        _dialog.Content = _askPanel;
        RefreshAsk();
    }

    private void RefreshAsk()
    {
        if (_stage != Stage.Ask) return;
        string course = ReferenceCourse.ShownCode(_source);
        string? problem =
            _offered.Count == 0 ? Say("thisCourseHasNoPagesToCopy", ("course", course))
            : _destinations.Count == 0 ? Say("thereIsNoCourseToCopyInto")
            : Destination is { } d && CoursePageCopy.FoldersOffered(d).Count == 0
                ? Say("thatCourseHasNowhereToPutIt", ("course", ReferenceCourse.ShownCode(d)))
                : null;
        _askNote.Text = problem ?? "";
        _askNote.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
        _dialog.IsPrimaryButtonEnabled = problem is null && _chosenPage is not null && _folder.SelectedItem is string;
    }

    // ---- Stage 2: the checklist, in the future tense ------------------------

    private void ShowChecklist()
    {
        _stage = Stage.Checklist;
        _dialog.PrimaryButtonText = "Copy";
        _dialog.CloseButtonText = "Cancel";
        _rowBoxes.Clear();
        var outer = new StackPanel { Spacing = 10, MinWidth = 440 };
        _header = new TextBlock { TextWrapping = TextWrapping.Wrap, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] };
        outer.Children.Add(_header);

        var inside = new StackPanel { Spacing = 6 };
        var chosen = _firstPlan!.Pages.FirstOrDefault(p => p.IsChosen);
        if (chosen is not null) inside.Children.Add(Row(chosen.Name + " — " + Say("thePageYouChose"), chosen.Name, enabled: false));
        foreach (string name in _firstPlan.LinkedPageRows) inside.Children.Add(Row(name, name, enabled: true));
        _sentences = new StackPanel { Spacing = 6, Margin = new Thickness(0, 8, 0, 0) };
        inside.Children.Add(_sentences);
        outer.Children.Add(Scroll(inside, ChecklistMaxHeight));

        outer.Children.Add(new TextBlock { Text = Say("copiesStartHidden"), TextWrapping = TextWrapping.Wrap, Opacity = 0.8 });
        _dialog.Content = outer;
        RepaintChecklist();
    }

    private CheckBox Row(string text, string name, bool enabled)
    {
        var box = new CheckBox { Content = text, IsChecked = true, IsEnabled = enabled };
        AutomationProperties.SetAutomationId(box, "copyPageRow:" + name);
        box.Checked += (_, _) => { if (_painting) return; _unticked.Remove(name); Replan(); };
        box.Unchecked += (_, _) => { if (_painting) return; _unticked.Add(name); Replan(); };
        _rowBoxes[name] = box;
        return box;
    }

    private static ScrollViewer Scroll(UIElement content, double maxHeight)
    {
        var scroll = new ScrollViewer
        {
            Content = content,
            MaxHeight = maxHeight,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        AutomationProperties.SetAutomationId(scroll, ScrollAutomationId);
        return scroll;
    }

    private void Replan()
    {
        _plan = CoursePageCopy.MakePlan(_request! with { Unticked = _unticked.ToHashSet() });
        RepaintChecklist();
    }

    /// <summary>Only the numbers and sentences move; the rows stay where the first plan put them.</summary>
    private void RepaintChecklist()
    {
        var plan = _plan!;
        var destination = _request!.Destination;
        string course = ReferenceCourse.ShownCode(destination);
        _header.Text = Say("willCopy", ("pages", plan.Pages.Count.ToString()), ("course", course), ("folder", _request.IntoFolder));
        var required = plan.Pages.Where(p => p.Required && !p.IsChosen).Select(p => p.Name).ToHashSet(StringComparer.Ordinal);
        string? chosen = plan.Pages.FirstOrDefault(p => p.IsChosen)?.Name;
        _painting = true;
        try
        {
            foreach (var (name, box) in _rowBoxes)
            {
                // Shown inside a page that comes: ticked and fixed while it does.
                if (required.Contains(name)) { box.IsChecked = true; box.IsEnabled = false; }
                else box.IsEnabled = name != chosen;
            }
        }
        finally { _painting = false; }
        _sentences.Children.Clear();
        if (required.Count > 0) Add(_sentences, Say("embeddedPagesAlwaysComeAlong"));
        int brought = plan.Brought.Count();
        if (brought > 0)
            Add(_sentences, Say("willBringPicturesAndFilesInAll", ("count", brought.ToString()), ("size", CoursePageCopy.SizeText(plan.BytesBrought))));
        int renamed = plan.Media.Count(m => m.Kind == CoursePageCopy.MediaKind.Renamed);
        if (renamed > 0) Add(_sentences, Say("picturesWillComeInUnderANewName", ("count", renamed.ToString())));
        foreach (var skip in plan.Skipped)
            Add(_sentences, Say(CoursePageCopy.FutureOf(skip.Reason), ("page", skip.Name)));
        if (plan.LinksLeadingNowhere.Count > 0) Add(_sentences, CopyPageWording.Names(plan.LinksLeadingNowhere));
        _dialog.IsPrimaryButtonEnabled = plan.Pages.Count > 0;
    }

    private static void Add(Panel panel, string text) =>
        panel.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap });

    // ---- Pressing Copy -------------------------------------------------------

    private async Task PrimaryPressed()
    {
        switch (_stage)
        {
            case Stage.Ask:
                if (Destination is not { } destination || _chosenPage is null || _folder.SelectedItem is not string folder) return;
                _unticked.Clear();
                _request = new CoursePageCopy.Request(_source, destination, _chosenPage, folder, _alsoLinked.IsChecked == true);
                _firstPlan = _plan = CoursePageCopy.MakePlan(_request);
                if (_request.AlsoCopiesLinkedPages && _firstPlan.LinkedPageRows.Count > 0) { ShowChecklist(); return; }
                await CopyNow();
                return;
            case Stage.Checklist:
                await CopyNow();
                return;
            case Stage.Result:
                _chosenPage = null;
                _picker.Text = "";
                ShowAsk();
                return;
        }
    }

    private async Task CopyNow()
    {
        var request = _request! with { Unticked = _unticked.ToHashSet() };
        var plan = _plan!;
        var destination = request.Destination;
        string course = ReferenceCourse.ShownCode(destination);
        _dialog.IsPrimaryButtonEnabled = false;
        if (_session.BackupName is null)
            _dialog.Content = new TextBlock { Text = Say("savingACopyFirst", ("course", course)), TextWrapping = TextWrapping.Wrap };

        // Asked immediately before the first write, and only the narrow
        // "is a deploy running" question: a preview only reads.
        bool IsDeploying() =>
            CourseActivity.IsPublishing(_workspacePath, destination.Code)
            || WorkLease.HeldBy(_workspacePath, destination.Code).Contains(WorkLease.Publishing);
        bool deploying = IsDeploying();
        var outcome = await Task.Run(() => CoursePageCopy.Copy(plan, request, _session, () => deploying));
        ShowResult(outcome, request);
    }

    // ---- Stage 3: the result, in the past tense -----------------------------

    private void ShowResult(CoursePageCopy.Outcome outcome, CoursePageCopy.Request request)
    {
        _stage = Stage.Result;
        string course = ReferenceCourse.ShownCode(request.Destination);
        var outer = new StackPanel { Spacing = 10, MinWidth = 440 };
        if (outcome.Refusal is { } refusal)
        {
            Add(outer, Say(refusal, ("course", course)));
            _dialog.Content = outer;
            _dialog.PrimaryButtonText = Say("copyAnother");
            _dialog.IsPrimaryButtonEnabled = true;
            _dialog.CloseButtonText = "Done";
            return;
        }
        outer.Children.Add(new TextBlock
        {
            Text = outcome.PagesCreated.Count > 0
                ? Say("copiedInto", ("pages", outcome.PagesCreated.Count.ToString()), ("course", course), ("folder", request.IntoFolder))
                : Say("nothingWasCopied"),
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
        });

        var inside = new StackPanel { Spacing = 6 };
        int brought = outcome.MediaCreated.Count;
        if (brought > 0)
            Add(inside, Say("willBringPicturesAndFiles", ("count", brought.ToString()), ("size", CoursePageCopy.SizeText(_plan!.BytesBrought))));
        if (outcome.MediaReused.Count > 0) Add(inside, Say("picturesAlreadyThere", ("count", outcome.MediaReused.Count.ToString())));
        if (outcome.MediaRenamed.Count > 0) Add(inside, Say("picturesBroughtInUnderANewName", ("count", outcome.MediaRenamed.Count.ToString())));
        foreach (var skip in outcome.Skipped)
        {
            string sentence = skip.Reason switch
            {
                "aPictureCouldNotBeCopied" => Say(skip.Reason, ("name", skip.Name)),
                "theCopyIsStillThereAndMustBeRemoved" => Say(skip.Reason, ("page", skip.Name),
                    ("path", outcome.MustBeRemoved.FirstOrDefault(p => p.Contains(skip.Name, StringComparison.Ordinal)) ?? "")),
                _ => Say(skip.Reason, ("page", skip.Name)),
            };
            Add(inside, sentence);
        }
        if (outcome.LinksLeadingNowhere.Count > 0) Add(inside, CopyPageWording.Names(outcome.LinksLeadingNowhere));
        if (inside.Children.Count > 0) outer.Children.Add(Scroll(inside, ResultMaxHeight));

        if (outcome.BackupName is { } named)
            outer.Children.Add(new TextBlock { Text = Say("theBackupTaken", ("course", course), ("named", named)), TextWrapping = TextWrapping.Wrap, Opacity = 0.8 });
        _dialog.Content = outer;
        _dialog.PrimaryButtonText = Say("copyAnother");
        _dialog.IsPrimaryButtonEnabled = true;
        _dialog.CloseButtonText = "Done";
    }

    // ---- Plumbing --------------------------------------------------------------

    private void TagButtons()
    {
        if (FindByName(_dialog, "PrimaryButton") is Button primary) AutomationProperties.SetAutomationId(primary, PrimaryAutomationId);
        if (FindByName(_dialog, "CloseButton") is Button close) AutomationProperties.SetAutomationId(close, CloseAutomationId);
    }

    private static DependencyObject? FindByName(DependencyObject root, string name)
    {
        int count = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < count; i++)
        {
            var child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(root, i);
            if (child is FrameworkElement { Name: var n } && n == name) return child;
            if (FindByName(child, name) is { } found) return found;
        }
        return null;
    }

    /// <summary>
    /// Shows the dialog for one source course. Its refusals answer before
    /// anything is touched and record nothing; a copy writes one trail line.
    /// </summary>
    public static async Task ShowAsync(Course source, IEnumerable<Course> courses, string workspacePath,
                                       Func<ContentDialog, Task<ContentDialogResult?>> show)
    {
        var ui = new CopyAPageDialog(source, courses, workspacePath);
        await show(ui._dialog);
    }
}

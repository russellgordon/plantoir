using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Item = Plantoir.Core.Models.SubjectMenuRules.Item;

namespace Plantoir.Views;

/// <summary>
/// The Section menu's ONE dialog (#489, the mac's <c>SectionVerbSheet</c>):
/// a single <see cref="ContentDialog"/> that moves through its stages —
/// Choose (the pages, the day, the class and how many) → Plan (the plan
/// twin's own card, with the verb's button) → Working → Result — rather than
/// a dialog per stage, because WinUI shows one ContentDialog at a time and a
/// second asked for while the first is closing is refused.
/// </summary>
/// <remarks>
/// <para>A stage changes by cancelling the button's own close
/// (<c>args.Cancel</c>) and doing the work under its deferral, so the dialog
/// stays up throughout. While a call runs, no button can be pressed and the
/// dialog cannot be closed: a change half-seen is worse than a wait.</para>
///
/// <para>A plan twin that REFUSES ends the dialog with its sentence and OK
/// alone — a refusal is an answer, never a proposal to approve. Cancel at the
/// plan writes "cancelled at the plan" on the trail; nothing ran.</para>
/// </remarks>
internal sealed class SectionVerbDialog
{
    private enum Stage { Choose, Plan, Working, Result }

    private readonly ContentDialog _dialog;
    private readonly SectionVerbs _verbs;
    private readonly Course _course;
    private readonly int _section;
    private readonly Item _item;
    private readonly bool _meeting;
    private Stage _stage = Stage.Choose;
    private Func<JsonObject>? _planCall;
    private JsonObject? _pendingCall;
    private string _verbButton = AssistWording.MenuContinueButton;
    private TextBlock? _workingWords;

    // Choose: Publish Pages… / Hide Pages…
    private readonly List<(AssistWorkspace.MenuPage Page, CheckBox Box)> _rows = new();
    // Choose: Publish Class for a Date…
    private CalendarDatePicker? _day;
    // Choose: Make Room for Classes…
    private ComboBox? _classes;
    private NumberBox? _howMany;
    private IReadOnlyList<AssistWorkspace.MenuClass> _classRows = Array.Empty<AssistWorkspace.MenuClass>();

    private SectionVerbDialog(XamlRoot root, SectionVerbs verbs, Course course, int section, Item item, string title)
    {
        _verbs = verbs;
        _course = course;
        _section = section;
        _item = item;
        _meeting = course.Configuration.ClassNoun == ClassNoun.Meeting;
        _dialog = new ContentDialog
        {
            Title = title,
            XamlRoot = root,
            DefaultButton = ContentDialogButton.Primary,
        };
        AutomationProperties.SetAutomationId(_dialog, "sectionVerbDialog");
        _dialog.PrimaryButtonClick += PrimaryPressed;
        _dialog.Closing += (_, args) =>
        {
            // While a call runs, nothing closes it — Escape included.
            if (_stage == Stage.Working)
            {
                args.Cancel = true;
                return;
            }
            // Closed at the plan, by Cancel or by Escape: nothing ran, and the trail says so.
            if (_stage == Stage.Plan)
                SectionVerbs.NoteCancelled(MenuPath(_item), _course.Code, _section, Counts());
        };
    }

    /// <summary>Where an item is in the menus, the way the trail says it.</summary>
    internal static string MenuPath(Item item) => item switch
    {
        Item.PublishPages => "Section ▸ Publish Pages…",
        Item.HidePages => "Section ▸ Hide Pages…",
        Item.PublishClassForADate => "Section ▸ Publish Class for a Date…",
        Item.RebuildPreview => "Section ▸ Rebuild Preview",
        Item.UndoLastChange => "Section ▸ Undo Last Change",
        Item.AddNextClass => "Section ▸ Add Next Class",
        Item.ReDateClasses => "Section ▸ Re-date Classes…",
        Item.MakeRoomForClasses => "Section ▸ Make Room for Classes…",
        Item.ClassDates => "Section ▸ Class Dates…",
        _ => item.ToString(),
    };

    // ---- Opening it, per item ---------------------------------------------------

    /// <summary>Publish Pages… or Hide Pages…: a searchable checklist, classes first.</summary>
    public static Task ChoosePages(XamlRoot root, SectionVerbs verbs, Course course, int section, bool publishing)
    {
        string sectionText = section.ToString();
        var item = publishing ? Item.PublishPages : Item.HidePages;
        var view = new SectionVerbDialog(root, verbs, course, section, item, publishing
            ? AssistWording.MenuPublishPagesTitle(course.Code, sectionText)
            : AssistWording.MenuHidePagesTitle(course.Code, sectionText));
        IReadOnlyList<AssistWorkspace.MenuPage> pages;
        try { pages = Reader(verbs.Folder).PagesToOffer(course.Code, section, publishing); }
        catch (Exception ex)
        {
            App.LogDiagnostic($"Section menu could not list the pages: {ex.Message}");
            pages = Array.Empty<AssistWorkspace.MenuPage>();
        }
        if (pages.Count == 0)
        {
            view.ShowResult(publishing ? AssistWording.MenuNoHiddenPages(course.Code, sectionText)
                                       : AssistWording.MenuNoVisiblePages(course.Code, sectionText));
            return view.Show();
        }
        view._verbButton = publishing ? AssistWording.MenuPublishButton : AssistWording.MenuHideButton;
        view._planCall = () =>
        {
            var names = view.Ticked();
            view._pendingCall = publishing
                ? SectionVerbs.PublishPages(course.Code, section, names, plan: false)
                : SectionVerbs.HidePages(course.Code, section, names, plan: false);
            return publishing
                ? SectionVerbs.PublishPages(course.Code, section, names, plan: true)
                : SectionVerbs.HidePages(course.Code, section, names, plan: true);
        };
        view.BuildChecklist(pages, publishing);
        return view.Show();
    }

    /// <summary>Publish Class for a Date…: a day, the section's next class day from its dates (tomorrow with none).</summary>
    public static Task ChooseADay(XamlRoot root, SectionVerbs verbs, Course course, int section)
    {
        string sectionText = section.ToString();
        bool meeting = course.Configuration.ClassNoun == ClassNoun.Meeting;
        var view = new SectionVerbDialog(root, verbs, course, section, Item.PublishClassForADate, meeting
            ? AssistWording.MenuPublishClassTitleForAMeeting(course.Code, sectionText)
            : AssistWording.MenuPublishClassTitle(course.Code, sectionText));
        view._verbButton = AssistWording.MenuPublishButton;
        var today = DateOnly.FromDateTime(DateTime.Now);
        var first = FirstDayOffered(verbs.Folder, course.Code, section, today);
        view._day = new CalendarDatePicker
        {
            Date = new DateTimeOffset(first.ToDateTime(new TimeOnly(12, 0))),
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        AutomationProperties.SetAutomationId(view._day, "sectionVerbDay");
        view._planCall = () =>
        {
            var chosen = DateOnly.FromDateTime((view._day.Date ?? DateTimeOffset.Now).Date);
            view._pendingCall = SectionVerbs.PublishClassOn(course.Code, section, chosen, plan: false);
            return SectionVerbs.PublishClassOn(course.Code, section, chosen, plan: true);
        };
        var panel = new StackPanel { Spacing = 12, MinWidth = 420 };
        panel.Children.Add(Words(meeting ? AssistWording.MenuPickClassDayForAMeeting : AssistWording.MenuPickClassDay));
        panel.Children.Add(view._day);
        view.ShowChoosing(panel);
        return view.Show();
    }

    /// <summary>The day Publish Class for a Date… offers first: the next class day after today, or tomorrow.</summary>
    internal static DateOnly FirstDayOffered(string folder, string courseCode, int section, DateOnly today)
    {
        var remembered = TimetableMemory.Read(folder, courseCode, section, today, recording: false);
        if (remembered?.Dates.Where(day => day > today).OrderBy(day => day).FirstOrDefault() is { } next && next != default)
            return next;
        return today.AddDays(1);
    }

    /// <summary>Make Room for Classes…: the class a new one goes in front of, and how many (1–10).</summary>
    public static Task ChooseWhereToMakeRoom(XamlRoot root, SectionVerbs verbs, Course course, int section)
    {
        string sectionText = section.ToString();
        bool meeting = course.Configuration.ClassNoun == ClassNoun.Meeting;
        var view = new SectionVerbDialog(root, verbs, course, section, Item.MakeRoomForClasses, meeting
            ? AssistWording.MenuMakeRoomTitleForAMeeting(course.Code, sectionText)
            : AssistWording.MenuMakeRoomTitle(course.Code, sectionText));
        view._verbButton = AssistWording.MenuMakeRoomButton;
        try { view._classRows = Reader(verbs.Folder).ClassesToMakeRoomBefore(course.Code, section); }
        catch (Exception ex) { App.LogDiagnostic($"Section menu could not list the classes: {ex.Message}"); }
        view._classes = new ComboBox { MinWidth = 260 };
        foreach (var row in view._classRows) view._classes.Items.Add(row.Title);
        if (view._classRows.Count > 0) view._classes.SelectedIndex = 0;
        AutomationProperties.SetAutomationId(view._classes, "sectionVerbClass");
        view._howMany = new NumberBox
        {
            Value = 1, Minimum = 1, Maximum = 10, SmallChange = 1,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        AutomationProperties.SetAutomationId(view._howMany, "sectionVerbHowMany");
        view._planCall = () =>
        {
            var chosen = view._classRows[Math.Max(0, view._classes.SelectedIndex)];
            int howMany = (int)Math.Clamp(double.IsNaN(view._howMany.Value) ? 1 : view._howMany.Value, 1, 10);
            view._pendingCall = SectionVerbs.MakeRoomForClasses(course.Code, section, chosen.Unit, chosen.Day, howMany, plan: false);
            return SectionVerbs.MakeRoomForClasses(course.Code, section, chosen.Unit, chosen.Day, howMany, plan: true);
        };
        var panel = new StackPanel { Spacing = 12, MinWidth = 420 };
        panel.Children.Add(Words(meeting ? AssistWording.MenuMakeRoomAtForAMeeting : AssistWording.MenuMakeRoomAt));
        panel.Children.Add(view._classes);
        panel.Children.Add(view._howMany);
        view.ShowChoosing(panel);
        view._dialog.IsPrimaryButtonEnabled = view._classRows.Count > 0;
        return view.Show();
    }

    /// <summary>Re-date Classes…: straight to the plan.</summary>
    public static Task PlanReDate(XamlRoot root, SectionVerbs verbs, Course course, int section)
    {
        string sectionText = section.ToString();
        bool meeting = course.Configuration.ClassNoun == ClassNoun.Meeting;
        var view = new SectionVerbDialog(root, verbs, course, section, Item.ReDateClasses, meeting
            ? AssistWording.MenuReDateTitleForAMeeting(course.Code, sectionText)
            : AssistWording.MenuReDateTitle(course.Code, sectionText));
        view._verbButton = AssistWording.MenuReDateButton;
        view._pendingCall = SectionVerbs.ReDateClasses(course.Code, section, plan: false);
        var planning = view.Show();
        _ = view.RunPlan(SectionVerbs.ReDateClasses(course.Code, section, plan: true));
        return planning;
    }

    /// <summary>Undo Last Change and Add Next Class: no plan; the dialog shows working, then what was done.</summary>
    public static Task RunAtOnce(XamlRoot root, SectionVerbs verbs, Course course, int section, Item item,
                                 JsonObject call, string title)
    {
        var view = new SectionVerbDialog(root, verbs, course, section, item, title);
        var showing = view.Show();
        _ = view.RunChange(call);
        return showing;
    }

    /// <summary>A sentence and OK, under the item's title — Rebuild Preview's refusal.</summary>
    public static Task ShowAnswer(XamlRoot root, SectionVerbs verbs, Course course, int section, Item item,
                                  string title, string sentence)
    {
        var view = new SectionVerbDialog(root, verbs, course, section, item, title);
        view.ShowResult(sentence);
        return view.Show();
    }

    /// <summary>The section's pages, read in-process; nothing here launches or writes.</summary>
    private static AssistWorkspace Reader(string folder) =>
        new(folder, new ReadsOnly()) { Surface = AssistSurface.Menu };

    private sealed class ReadsOnly : ILauncherRunner
    {
        public Task<LaunchOutcome> Run(string launcher, IReadOnlyList<string> arguments, string workingFolder,
                                       IProgress<string>? progress, System.Threading.CancellationToken cancellation) =>
            Task.FromResult(new LaunchOutcome(false, "Not from the Section menu's list."));
    }

    // ---- The stages ---------------------------------------------------------------

    /// <summary>
    /// Shown, waiting for a dialog that is still closing — the class dates
    /// dialog just before it, say: WinUI's ShowAsync completes as a dialog
    /// BEGINS to close, and a second asked for then is refused. Dropping the
    /// answer to a change the teacher just asked for is the one thing this
    /// must not do (the mac's implementation review, note 4).
    /// </summary>
    private async Task Show()
    {
        for (int attempt = 0; attempt < 10; attempt++)
        {
            try
            {
                await _dialog.ShowAsync();
                return;
            }
            catch (Exception ex)
            {
                if (attempt == 0) App.LogDiagnostic($"The Section menu's dialog waited for another to close: {ex.Message}");
                await Task.Delay(150);
            }
        }
    }

    private static TextBlock Words(string text) => new() { Text = text, TextWrapping = TextWrapping.Wrap, MaxWidth = 520 };

    private void ShowChoosing(UIElement content)
    {
        _stage = Stage.Choose;
        _dialog.Content = content;
        _dialog.PrimaryButtonText = AssistWording.MenuContinueButton;
        _dialog.CloseButtonText = AssistWording.MenuCancelButton;
        _dialog.DefaultButton = ContentDialogButton.Primary;
    }

    private void ShowWorking(string said)
    {
        _stage = Stage.Working;
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, MinWidth = 420 };
        panel.Children.Add(new ProgressRing { IsActive = true, Width = 20, Height = 20 });
        var words = Words(said);
        _workingWords = words;
        AutomationProperties.SetAutomationId(words, "sectionVerbWorking");
        panel.Children.Add(words);
        _dialog.Content = panel;
        _dialog.PrimaryButtonText = "";
        _dialog.CloseButtonText = "";
    }

    private void ShowPlan(string card)
    {
        _stage = Stage.Plan;
        var words = Words(card);
        words.IsTextSelectionEnabled = true;
        AutomationProperties.SetAutomationId(words, "sectionVerbPlan");
        _dialog.Content = new ScrollViewer { Content = words, MaxHeight = 420, MinWidth = 420 };
        _dialog.PrimaryButtonText = _verbButton;
        _dialog.IsPrimaryButtonEnabled = true;
        _dialog.CloseButtonText = AssistWording.MenuCancelButton;
        _dialog.DefaultButton = ContentDialogButton.Primary;
    }

    private void ShowResult(string said)
    {
        _stage = Stage.Result;
        var words = Words(said);
        words.IsTextSelectionEnabled = true;
        AutomationProperties.SetAutomationId(words, "sectionVerbResult");
        _dialog.Content = new ScrollViewer { Content = words, MaxHeight = 420, MinWidth = 420 };
        _dialog.PrimaryButtonText = "";
        _dialog.CloseButtonText = AssistWording.MenuDoneButton;
        _dialog.DefaultButton = ContentDialogButton.Close;
    }

    private async void PrimaryPressed(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        args.Cancel = true;
        var deferral = args.GetDeferral();
        try
        {
            if (_stage == Stage.Choose && _planCall is not null) await RunPlan(_planCall());
            else if (_stage == Stage.Plan && _pendingCall is not null) await RunChange(_pendingCall);
        }
        finally { deferral.Complete(); }
    }

    private async Task RunPlan(JsonObject planCall)
    {
        ShowWorking(AssistWording.MenuWorking);
        var answer = await _verbs.Perform(planCall, MenuPath(_item), _course.Code, _section, Counts());
        if (answer.IsPlan)
        {
            ShowPlan(answer.Summary);
            return;
        }
        // A plan twin that refused: its sentence and OK, nothing to approve.
        SectionVerbs.NoteRan(MenuPath(_item), "changed nothing", _course.Code, _section, Counts());
        ShowResult(answer.Summary);
    }

    /// <summary>
    /// A change: "Working…", and "Saving a copy of ICS3U first…" only while the
    /// server SAYS it is saving one (2B's implementation review, M2). It used
    /// to say so for every change from the first moment — Undo, which never
    /// saves a copy, and a change refused before its copy, included.
    /// </summary>
    private async Task RunChange(JsonObject call)
    {
        ShowWorking(AssistWording.MenuWorking);
        string savingACopy = AssistWording.MenuSavingACopy(_course.Code);
        var answer = await _verbs.Perform(call, MenuPath(_item), _course.Code, _section, Counts(),
            progress: note => _dialog.DispatcherQueue?.TryEnqueue(() =>
            {
                if (_stage == Stage.Working && _workingWords is not null)
                    _workingWords.Text = note == savingACopy ? savingACopy : AssistWording.MenuWorking;
            }));
        ShowResult(answer.Summary);
    }

    // ---- Publish Pages… / Hide Pages…: the checklist ----------------------------------

    private void BuildChecklist(IReadOnlyList<AssistWorkspace.MenuPage> pages, bool publishing)
    {
        var titleCounts = pages.GroupBy(page => page.Title, StringComparer.OrdinalIgnoreCase)
                               .ToDictionary(group => group.Key, group => group.Count(), StringComparer.OrdinalIgnoreCase);
        var list = new StackPanel { Spacing = 2 };
        int index = 0;
        foreach (var page in pages)
        {
            // Two pages of one title — every shipped course's _DUPLICATE ME
            // templates — are told apart by their folder.
            string shown = titleCounts[page.Title] > 1 ? $"{page.Title} — {page.Folder}" : page.Title;
            var box = new CheckBox { Content = shown };
            AutomationProperties.SetName(box, shown);
            AutomationProperties.SetAutomationId(box, $"sectionVerbPage{index++}");
            box.Checked += (_, _) => UpdateContinue();
            box.Unchecked += (_, _) => UpdateContinue();
            _rows.Add((page, box));
            list.Children.Add(box);
        }
        var find = new TextBox { PlaceholderText = AssistWording.MenuFindAPage };
        AutomationProperties.SetName(find, AssistWording.MenuFindAPage);
        AutomationProperties.SetAutomationId(find, "sectionVerbFind");
        find.TextChanged += (_, _) =>
        {
            string wanted = find.Text.Trim();
            foreach (var (page, box) in _rows)
                box.Visibility = wanted.Length == 0
                                 || page.Title.Contains(wanted, StringComparison.CurrentCultureIgnoreCase)
                                 || page.Folder.Contains(wanted, StringComparison.CurrentCultureIgnoreCase)
                    ? Visibility.Visible : Visibility.Collapsed;
        };
        var panel = new StackPanel { Spacing = 12, MinWidth = 460 };
        panel.Children.Add(Words(publishing ? AssistWording.MenuPickPagesToPublish : AssistWording.MenuPickPagesToHide));
        panel.Children.Add(find);
        panel.Children.Add(new ScrollViewer { Content = list, MaxHeight = 360 });
        ShowChoosing(panel);
        UpdateContinue();
    }

    private void UpdateContinue()
    {
        if (_stage == Stage.Choose && _rows.Count > 0) _dialog.IsPrimaryButtonEnabled = _rows.Any(row => row.Box.IsChecked == true);
    }

    private List<string> Ticked() => _rows.Where(row => row.Box.IsChecked == true).Select(row => row.Page.Name).ToList();

    /// <summary>The trail line's counts — never a title.</summary>
    private string? Counts() => _item switch
    {
        Item.PublishPages or Item.HidePages => Ticked().Count == 1 ? "1 page ticked" : $"{Ticked().Count} pages ticked",
        Item.MakeRoomForClasses when _howMany is not null => (int)_howMany.Value == 1 ? "room for 1" : $"room for {(int)_howMany.Value}",
        _ => null,
    };
}

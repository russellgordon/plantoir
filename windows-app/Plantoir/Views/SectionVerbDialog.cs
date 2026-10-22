using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Item = Plantoir.Core.Models.SubjectMenuRules.Item;

namespace Plantoir.Views;

/// <summary>
/// The Section menu's ONE dialog (#489, the mac's <c>SectionVerbSheet</c>):
/// a single <see cref="ContentDialog"/> that moves through its stages —
/// Choose (the pages, the day, the class and how many) → Plan (the plan
/// twin's own card, with the verb's button; for the three page items a TABLE
/// since #548) → Working → Result — rather than
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
    private enum Stage { Choose, LaterClasses, Plan, Working, Result }

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
    // Publish Pages…: the question about classes dated after the next class (#475)
    private readonly List<(ClassesDatedLater.Page Page, CheckBox Box)> _laterRows = new();

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
        _dialog.Content = _host;
        if (ShowsAPlanTable(item))
        {
            // Wide enough for the plan table's three columns, and the SAME
            // width at every stage: a dialog that widened at the plan would
            // jump (the mac rejected widening mid-flow for that, #524). Since
            // #634 (the mac's #621, the sheets resize) the width follows the
            // WINDOW — 680 at its 900-epx minimum, growing with it up to 300
            // more (PageTableLayout.DialogWidth), never wider than the window
            // less a margin — and a resized window resizes the dialog. The
            // template reads ContentDialogMin/MaxWidth once, so they are set
            // wide open here and the HOST carries the width, at every stage.
            _dialog.Resources["ContentDialogMaxWidth"] = 100000.0;
            // Every fit is #548's up to 756 epx; a taller window gives the
            // table its rows (PlanTableLayout.ExtraRows), so the dialog may be
            // taller than ContentDialog's own 756.
            _dialog.Resources["ContentDialogMaxHeight"] = 100000.0;
            SizeTheHost(root);
        }
        _dialog.PrimaryButtonClick += PrimaryPressed;
        // The resize handler is on the WINDOW's XamlRoot, which outlives this
        // dialog: attached while the dialog is up, and taken off when it closes
        // — at any stage, Cancel and Escape included.
        _dialog.Opened += (_, _) => StartFollowingTheWindow();
        _dialog.Closed += (_, _) => StopRefitting();
        _dialog.Closing += (_, args) =>
        {
            // While a call runs, nothing closes it — Escape included.
            if (_stage == Stage.Working)
            {
                args.Cancel = true;
                return;
            }
            // Closed at the plan, or at the question about classes dated
            // later, by Cancel or by Escape: nothing ran, and the trail says so.
            if (_stage is Stage.Plan or Stage.LaterClasses)
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
        DialogButtons.EnablePrimary(view._dialog, view._classRows.Count > 0);
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
        SetContent(content);
        _dialog.PrimaryButtonText = AssistWording.MenuContinueButton;
        _dialog.CloseButtonText = AssistWording.MenuCancelButton;
        // Live until a caller says otherwise (a pick with nothing ticked greys it).
        DialogButtons.EnablePrimary(_dialog, true);
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
        SetContent(panel);
        _dialog.PrimaryButtonText = "";
        _dialog.CloseButtonText = "";
    }

    private void ShowPlan(string card)
    {
        _stage = Stage.Plan;
        var words = Words(card);
        words.IsTextSelectionEnabled = true;
        AutomationProperties.SetAutomationId(words, "sectionVerbPlan");
        SetContent(new ScrollViewer { Content = words, MaxHeight = 420, MinWidth = 420 });
        _dialog.PrimaryButtonText = _verbButton;
        DialogButtons.EnablePrimary(_dialog, true);
        _dialog.CloseButtonText = AssistWording.MenuCancelButton;
    }

    // ---- The plan as a table (#548, the mac's #524) -----------------------------------

    /// <summary>The three items whose plan is a page plan, shown as a table.</summary>
    private static bool ShowsAPlanTable(Item item) =>
        item is Item.PublishPages or Item.HidePages or Item.PublishClassForADate;

    /// <summary>The ContentDialog's own padding at each side of its content.</summary>
    private const double DialogPadding = PageTableLayout.DialogPadding;

    /// <summary>
    /// What every stage is drawn in (#634): for the three page items it
    /// carries the dialog's width, so the dialog is one width at every stage
    /// and follows the window.
    /// </summary>
    private readonly Grid _host = new();

    /// <summary>The dialog's width (the three page items): <see cref="PageTableLayout.DialogWidth"/> at the window's width.</summary>
    private double _planWidth = PageTableLayout.PageSheetWidth;

    /// <summary>What the stage showing does when the window changes size: the table's rows, the plan's notes and columns.</summary>
    private Action? _relayout;

    /// <summary>The handler on the window's <c>XamlRoot.Changed</c>, while the dialog is up.</summary>
    private Windows.Foundation.TypedEventHandler<XamlRoot, XamlRootChangedEventArgs>? _refit;
    private XamlRoot? _refitRoot;

    private void SizeTheHost(XamlRoot? root)
    {
        if (!ShowsAPlanTable(_item)) return;
        if (root is { Size.Width: > 0 })
            _planWidth = PageTableLayout.DialogWidth(PageTableLayout.PageSheetWidth, root.Size.Width);
        _host.Width = _planWidth - 2 * DialogPadding;
    }

    private void StartFollowingTheWindow()
    {
        StopRefitting();
        if (_dialog.XamlRoot is not { } root) return;
        _refit = (_, _) =>
        {
            SizeTheHost(root);
            _relayout?.Invoke();
        };
        _refitRoot = root;
        root.Changed += _refit;
        // The size the window had when the dialog opened.
        SizeTheHost(root);
        _relayout?.Invoke();
    }

    private void StopRefitting()
    {
        if (_refit is not null && _refitRoot is not null) _refitRoot.Changed -= _refit;
        _refit = null;
        _refitRoot = null;
    }

    /// <summary>A stage's content, in the host; the last stage's relayout is dropped with it.</summary>
    private void SetContent(UIElement content, Action? relayout = null)
    {
        _host.Children.Clear();
        _host.Children.Add(content);
        _relayout = relayout;
    }

    /// <summary>The window's height, or ContentDialog's old maximum before it is known.</summary>
    private double WindowHeight => _dialog.XamlRoot is { Size.Height: > 0 } root ? root.Size.Height : PlanTableLayout.DialogMaxHeight;

    /// The plan stage of the three page items: the summary, a read-only table
    /// of the pages a teacher reads before Go (sortable by its headers), the
    /// pages already right folded under it (#634, the mac's #622), and the
    /// card's other sentences under that. Built from the rows the menu's
    /// server sent, never by parsing the card. Return still presses the verb's
    /// button and Escape Cancel while the table has focus (measured, doc 12).
    /// </summary>
    private void ShowPlanTable(PlanTable table)
    {
        _stage = Stage.Plan;
        var panel = new StackPanel { Spacing = 8 };

        var summary = Words(table.Summary);
        summary.MaxWidth = double.PositiveInfinity;
        summary.IsTextSelectionEnabled = true;
        AutomationProperties.SetAutomationId(summary, "sectionVerbPlan");
        panel.Children.Add(summary);

        // The columns' widths follow the dialog's (#634): at 680 exactly #548's
        // 170 / 150 / the rest; wider, Page takes what What changes (capped at
        // 320, the mac's) does not.
        var grids = new List<Grid>();
        Grid Columns()
        {
            var grid = new Grid { ColumnSpacing = PageTableLayout.ColumnSpacing };
            for (int i = 0; i < 3; i++) grid.ColumnDefinitions.Add(new ColumnDefinition());
            grids.Add(grid);
            return grid;
        }
        void SizeTheColumns()
        {
            var (page, folder, change) = PageTableLayout.PlanColumns(_planWidth);
            foreach (var grid in grids)
            {
                grid.ColumnDefinitions[0].Width = new GridLength(page);
                grid.ColumnDefinitions[1].Width = new GridLength(folder);
                grid.ColumnDefinitions[2].Width = new GridLength(change);
            }
        }

        StackPanel? notes = null;
        if (table.Notes.Count > 0)
        {
            notes = new StackPanel { Spacing = 6 };
            for (int i = 0; i < table.Notes.Count; i++)
            {
                var note = Words(table.Notes[i]);
                note.MaxWidth = double.PositiveInfinity;
                note.IsTextSelectionEnabled = true;
                AutomationProperties.SetAutomationId(note, $"sectionVerbPlanNote{i}");
                notes.Children.Add(note);
            }
        }

        var list = new ListView
        {
            SelectionMode = ListViewSelectionMode.None,
            IsItemClickEnabled = false,
            BorderThickness = new Thickness(PageTableLayout.TableBorder),
            CornerRadius = new CornerRadius(4),
            TabIndex = 1,
        };
        if (Application.Current.Resources.TryGetValue("CardStrokeColorDefaultBrush", out var stroke) && stroke is Brush brush)
            list.BorderBrush = brush;
        AutomationProperties.SetAutomationId(list, "sectionVerbPlanTable");
        AutomationProperties.SetName(list, table.Summary);

        var rowItems = new Dictionary<int, ListViewItem>();
        foreach (var row in table.Rows)
        {
            var grid = Columns();
            string[] cells = { row.Title, row.Folder, row.WhatChanges };
            for (int i = 0; i < cells.Length; i++)
            {
                var cell = new TextBlock
                {
                    Text = cells[i],
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    TextWrapping = TextWrapping.NoWrap,
                    VerticalAlignment = VerticalAlignment.Center,
                };
                // A cell's tooltip carries its whole text, as on the mac.
                ToolTipService.SetToolTip(cell, cells[i]);
                Grid.SetColumn(cell, i);
                grid.Children.Add(cell);
            }
            var item = new ListViewItem
            {
                Content = grid,
                MinHeight = PlanTableLayout.RowPitch,
                Padding = new Thickness(PageTableLayout.RowPadding, 0, PageTableLayout.RowPadding, 0),
            };
            AutomationProperties.SetAutomationId(item, $"sectionVerbPlanRow{row.Position}");
            AutomationProperties.SetName(item, $"{row.Title}, {row.Folder}, {row.WhatChanges}");
            rowItems[row.Position] = item;
        }

        // The pages already right are folded away, closed for every new plan
        // (#622); opening adds them to the SAME table, through the one sort.
        bool open = false;
        var order = PlanTableOrder.Opening;
        void Fill()
        {
            list.Items.Clear();
            foreach (var row in PlanTableOrder.Sorted(table.DrawnRows(open), order.Column, order.Ascending))
                list.Items.Add(rowItems[row.Position]);
            TickTable.Band(list);
        }

        // The headers sort. They stay in the Tab order, AFTER the table
        // (TabIndex 2), so Tab reaches the table first; Return on a focused
        // header sorts, as a button does (doc 12).
        var header = Columns();
        header.Margin = new Thickness(PageTableLayout.TableBorder + PageTableLayout.RowPadding, 0,
                                      PageTableLayout.TableBorder + PageTableLayout.RowPadding, 0);
        var sortButtons = new List<(Button Button, string Title, PlanTableOrder.Column Column)>();
        void TitleTheHeaders()
        {
            foreach (var (button, title, column) in sortButtons)
            {
                button.Content = PlanTableOrder.Header(title, column, order);
                // The arrow is drawn, so Narrator is TOLD it too.
                AutomationProperties.SetName(button, column != order.Column ? $"Sort by {title}"
                    : $"Sort by {title}, sorted {(order.Ascending ? "ascending" : "descending")}");
            }
        }
        foreach (var (title, column, slot, id) in new[]
                 {
                     (AssistWording.MenuPlanPageColumn, PlanTableOrder.Column.Page, 0, "sectionVerbPlanSortPage"),
                     (AssistWording.MenuPlanFolderColumn, PlanTableOrder.Column.Folder, 1, "sectionVerbPlanSortFolder"),
                     (AssistWording.MenuPlanChangeColumn, PlanTableOrder.Column.Change, 2, "sectionVerbPlanSortChange"),
                 })
        {
            var button = new Button
            {
                Padding = new Thickness(0),
                Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
                BorderThickness = new Thickness(0),
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                HorizontalAlignment = HorizontalAlignment.Left,
                TabIndex = 2,
            };
            AutomationProperties.SetAutomationId(button, id);
            button.Click += (_, _) =>
            {
                order = PlanTableOrder.AfterPressing(column, order);
                TitleTheHeaders();
                Fill();
            };
            Grid.SetColumn(button, slot);
            header.Children.Add(button);
            sortButtons.Add((button, title, column));
        }
        TitleTheHeaders();
        Fill();
        SizeTheColumns();
        panel.Children.Add(header);

        // The table and its disclosure as one part, 4 epx apart: the
        // disclosure reads as the table's (the mac's 6-pt reason).
        var tablePart = new StackPanel { Spacing = 4 };
        tablePart.Children.Add(list);
        if (table.FoldLabel is { } label)
            tablePart.Children.Add(Disclosure(label, isOpen =>
            {
                open = isOpen;
                Fill();
            }));
        panel.Children.Add(tablePart);

        ScrollViewer? scroller = null;
        if (notes is not null)
        {
            scroller = new ScrollViewer { Content = notes };
            AutomationProperties.SetAutomationId(scroller, "sectionVerbPlanNotes");
            panel.Children.Add(scroller);
        }

        // Rows and the notes' cap from the window's height (PlanTableLayout),
        // and again whenever the window changes size while the plan shows —
        // counted once, a window made shorter would clip what was counted. The
        // notes are measured at the dialog's LIVE width, which follows the window.
        // The table's height is FIXED — counted with the disclosure closed —
        // so opening it never grows the dialog (Russell's ruling on the mac):
        // a MaxHeight would let a short table shrink to its rows and grow when
        // the folded rows arrive, the mac's measured 316 → 484.
        PlanTableLayout.Fit? fitted = null;
        double fittedWidth = 0;
        void Fit()
        {
            SizeTheColumns();
            double notesNatural = 0;
            if (notes is not null)
            {
                notes.Measure(new Windows.Foundation.Size(_planWidth - 2 * DialogPadding, double.PositiveInfinity));
                notesNatural = notes.DesiredSize.Height;
            }
            double windowHeight = WindowHeight;
            var fit = PlanTableLayout.For(windowHeight, notesNatural, table.FoldsAlreadyRight);
            if (fit == fitted && fittedWidth == _planWidth) return;
            fitted = fit;
            fittedWidth = _planWidth;
            int rows = Math.Min(table.RowsWhenClosed, fit.Rows);
            list.Height = rows * PlanTableLayout.RowPitch + 2 * PageTableLayout.TableBorder;
            if (scroller is not null) scroller.MaxHeight = fit.NotesCap;
            App.LogDiagnostic($"Plan table: window {windowHeight:0} epx tall, dialog {_planWidth:0} wide, notes {notesNatural:0} epx " +
                              $"(shown at most {fit.NotesCap:0}), {rows} rows tall of {table.Rows.Count} " +
                              $"({table.RowsToRead.Count} to read{(table.FoldsAlreadyRight ? $", {table.RowsAlreadyRight.Count} folded" : "")})");
        }
        Fit();

        // Return is the verb's button while the table has focus, as it is
        // everywhere else in the dialog. MEASURED (doc 12): with the focus on
        // a row, the ListView took Return for itself and nothing happened, so
        // Return is caught on its way down, before the list sees it — as
        // CopyAPageDialog does for the AutoSuggestBox and Escape. Escape needed
        // nothing: it reached the dialog and cancelled. Handled here, the key
        // never reaches the dialog too, so the change cannot run twice.
        list.PreviewKeyDown += (_, args) =>
        {
            if (args.Key != Windows.System.VirtualKey.Enter || _stage != Stage.Plan) return;
            args.Handled = true;
            _ = Advance();
        };

        // The table takes the focus when it appears. Measured (doc 12): the
        // focus was on the stage just replaced, and with it gone Tab went to
        // the main window BEHIND the dialog, not into the table. Programmatic,
        // not Keyboard: Keyboard drew the focus ring on the first row however
        // Continue was pressed (measured, a picture each way); Programmatic
        // follows the last input, so a mouse user is not shown a ring.
        list.Loaded += (_, _) => list.Focus(FocusState.Programmatic);

        SetContent(panel, Fit);
        _dialog.PrimaryButtonText = _verbButton;
        DialogButtons.EnablePrimary(_dialog, true);
        _dialog.CloseButtonText = AssistWording.MenuCancelButton;
    }

    /// <summary>
    /// The plan's disclosure (#634, the mac's <c>DisclosureGroup</c>): a
    /// borderless toggle with a chevron and the words, closed to begin with.
    /// A <c>ToggleButton</c>, so Narrator hears its state through the Toggle
    /// pattern. REJECTED: <c>Expander</c>, whose header is 48 epx on a card
    /// background with an animation — a second panel, where the mac's is one
    /// line of the table's (the plan review).
    /// </summary>
    private static ToggleButton Disclosure(string label, Action<bool> toggled)
    {
        var chevron = new FontIcon { Glyph = "", FontSize = 10 };
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        content.Children.Add(chevron);
        content.Children.Add(new TextBlock { Text = label });
        var button = new ToggleButton
        {
            Content = content,
            Padding = new Thickness(2, 4, 6, 4),
            BorderThickness = new Thickness(0),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            HorizontalAlignment = HorizontalAlignment.Left,
            TabIndex = 3,
        };
        // A toggle that is on keeps the look of one that is off: the chevron
        // says the state, as a disclosure's does.
        var clear = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        foreach (string key in new[] { "ToggleButtonBackgroundChecked", "ToggleButtonBackgroundCheckedPointerOver",
                                       "ToggleButtonBackgroundCheckedPressed", "ToggleButtonBorderBrushChecked",
                                       "ToggleButtonBorderBrushCheckedPointerOver", "ToggleButtonBorderBrushCheckedPressed",
                                       "ToggleButtonBackground", "ToggleButtonBorderBrush" })
            button.Resources[key] = clear;
        if (Application.Current.Resources.TryGetValue("TextFillColorPrimaryBrush", out var primary) && primary is Brush text)
            foreach (string key in new[] { "ToggleButtonForegroundChecked", "ToggleButtonForegroundCheckedPointerOver",
                                           "ToggleButtonForegroundCheckedPressed" })
                button.Resources[key] = text;
        AutomationProperties.SetAutomationId(button, "sectionVerbPlanAlreadyRight");
        AutomationProperties.SetName(button, label);
        button.Checked += (_, _) => { chevron.Glyph = ""; toggled(true); };
        button.Unchecked += (_, _) => { chevron.Glyph = ""; toggled(false); };
        return button;
    }

    private void ShowResult(string said)
    {
        _stage = Stage.Result;
        var words = Words(said);
        words.IsTextSelectionEnabled = true;
        AutomationProperties.SetAutomationId(words, "sectionVerbResult");
        SetContent(new ScrollViewer { Content = words, MaxHeight = 420, MinWidth = 420 });
        _dialog.PrimaryButtonText = "";
        _dialog.CloseButtonText = AssistWording.MenuDoneButton;
        _dialog.DefaultButton = ContentDialogButton.Close;
    }

    private async void PrimaryPressed(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        args.Cancel = true;
        var deferral = args.GetDeferral();
        try { await Advance(); }
        finally { deferral.Complete(); }
    }

    /// <summary>
    /// What the verb's button does at the stage showing: the plan after the
    /// choice, the change after the plan. Also reached by Return on the plan
    /// table, which keeps that key for itself (<see cref="ShowPlanTable"/>).
    /// </summary>
    private async Task Advance()
    {
        if (_stage == Stage.Choose && _item == Item.PublishPages && AskAboutClassesDatedLater()) return;
        if (_stage == Stage.Choose && _planCall is not null) await RunPlan(_planCall());
        else if (_stage == Stage.LaterClasses) await AnswerAboutClassesDatedLater();
        else if (_stage == Stage.Plan && _pendingCall is not null) await RunChange(_pendingCall);
    }

    private async Task RunPlan(JsonObject planCall)
    {
        ShowWorking(AssistWording.MenuWorking);
        var answer = await _verbs.Perform(planCall, MenuPath(_item), _course.Code, _section, Counts());
        if (answer.IsPlan)
        {
            // The table when the menu's server sent one (#548); the text card
            // for any plan without — Re-date, Make Room, and a whole unit.
            if (answer.PlanTable is { } table && ShowsAPlanTable(_item)) ShowPlanTable(table);
            else ShowPlan(answer.Summary);
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

    // ---- Publish Pages…: classes dated after the next class (#475) ---------------------

    /// <summary>
    /// After the choice and before the plan (<c>shared-rules.json</c> →
    /// <c>classesDatedLater.askedFrom</c>): the ticked pages that would be
    /// classes dated after the next class once published, each ticked to be
    /// LEFT OUT. True when the question is now up.
    /// </summary>
    private bool AskAboutClassesDatedLater()
    {
        var today = DateOnly.FromDateTime(DateTime.Now);
        IReadOnlyList<ClassesDatedLater.Page> flagged;
        DateOnly? next;
        try
        {
            flagged = ClassesDatedLater.FlaggedIfPublishing(_course, _section, today, Ticked());
            next = ClassesDatedLater.NextClassDay(today, ClassesDatedLater.ClassPages(_course, _section));
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"Section menu could not read the classes dated later: {ex.Message}");
            return false;
        }
        if (flagged.Count == 0 || next is not { } nextDay) return false;

        _stage = Stage.LaterClasses;
        _laterRows.Clear();
        // A table, the picker's shape (#634, the mac's #608): Page with its
        // box, and Date. Return is the main button; Space ticks the row.
        var table = TickTable.ForLaterClasses(flagged, _meeting ? AssistWording.LaterClassesTitleForAMeeting : AssistWording.LaterClassesTitle);
        foreach (var row in table.Rows) _laterRows.Add((flagged[row.Index], row.Box));
        table.Changed += NameTheLaterClassesButton;
        table.Enter = () => { if (_stage == Stage.LaterClasses) _ = Advance(); };
        var panel = new StackPanel { Spacing = 12, MinWidth = 460 };
        panel.Children.Add(Words(_meeting ? AssistWording.LaterClassesAtPublishForAMeeting(nextDay)
                                          : AssistWording.LaterClassesAtPublish(nextDay)));
        panel.Children.Add(table.Panel);
        var note = Words(_meeting ? AssistWording.LaterClassesKeptNoteForAMeeting : AssistWording.LaterClassesKeptNote);
        note.Opacity = 0.8;
        panel.Children.Add(note);
        _dialog.Title = _meeting ? AssistWording.LaterClassesTitleForAMeeting : AssistWording.LaterClassesTitle;
        void Rows()
        {
            int rows = PageTableLayout.PickerRows(WindowHeight, flagged.Count);
            table.SetRows(rows);
            App.LogDiagnostic($"Later classes at Publish Pages: window {WindowHeight:0} epx tall, {rows} rows tall of {flagged.Count}");
        }
        Rows();
        SetContent(panel, Rows);
        _dialog.CloseButtonText = AssistWording.MenuCancelButton;
        DialogButtons.EnablePrimary(_dialog, true);
        NameTheLaterClassesButton();
        return true;
    }

    /// <summary>"Leave 2 Hidden and Continue", or "Publish Them All" with none ticked.</summary>
    private void NameTheLaterClassesButton()
    {
        int leftOut = _laterRows.Count(row => row.Box.IsChecked == true);
        _dialog.PrimaryButtonText = leftOut == 0
            ? AssistWording.PublishThemAllButton
            : AssistWording.LeaveOutAndContinueButton(leftOut);
    }

    /// <summary>
    /// The ticked are LEFT OUT and stay hidden; the unticked are published with
    /// the rest and remembered as kept at their dates. With nothing left, nothing
    /// is published and the dialog closes.
    /// </summary>
    private async Task AnswerAboutClassesDatedLater()
    {
        var leftOut = _laterRows.Where(row => row.Box.IsChecked == true).Select(row => row.Page).ToList();
        var kept = _laterRows.Where(row => row.Box.IsChecked != true).Select(row => row.Page).ToList();
        LaterClassesKept.Keep(_course.DirectoryPath, _section, kept);
        Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.LaterClassesAsked,
            ClassesDatedLater.AskedLine(MenuPath(_item), _laterRows.Count, leftOut.Count, kept.Count), _course.Code, _section);

        var leaving = leftOut.Select(page => page.Place).ToHashSet(StringComparer.Ordinal);
        foreach (var (page, box) in _rows)
            if (leaving.Contains(ClassesDatedLater.PlaceKey(page.Name))) box.IsChecked = false;

        _dialog.Title = AssistWording.MenuPublishPagesTitle(_course.Code, _section.ToString());
        if (Ticked().Count == 0)
        {
            SectionVerbs.NoteCancelled(MenuPath(_item), _course.Code, _section,
                                       "every page ticked was a class dated later, left hidden");
            _stage = Stage.Result;
            _dialog.Hide();
            return;
        }
        if (_planCall is not null) await RunPlan(_planCall());
    }

    // ---- Publish Pages… / Hide Pages…: the checklist ----------------------------------

    private void BuildChecklist(IReadOnlyList<AssistWorkspace.MenuPage> pages, bool publishing)
    {
        var titleCounts = pages.GroupBy(page => page.Title, StringComparer.OrdinalIgnoreCase)
                               .ToDictionary(group => group.Key, group => group.Count(), StringComparer.OrdinalIgnoreCase);
        // A table (#634, the mac's #608): Page — the box is the title — Folder
        // and Date, a class's day as the later-classes question says it.
        var offers = new List<TickTable.Offer>();
        for (int index = 0; index < pages.Count; index++)
        {
            var page = pages[index];
            // Two pages of one title — every shipped course's _DUPLICATE ME
            // templates — are told apart by their folder, in the Folder
            // column and in the box's name for Narrator.
            string name = titleCounts[page.Title] > 1 ? $"{page.Title} — {page.Folder}" : page.Title;
            string day = page.IsClass && page.Date is { } date ? AssistWording.LaterClassesDay(date) : "";
            offers.Add(new TickTable.Offer(page.Title, name, $"sectionVerbPage{index}", $"sectionVerbPageRow{index}",
                                           new[] { page.Folder, day }, Ticked: false));
        }
        var table = new TickTable("sectionVerbPickerTable",
                                  publishing ? AssistWording.MenuPickPagesToPublish : AssistWording.MenuPickPagesToHide,
                                  new[] { AssistWording.MenuPlanFolderColumn, AssistWording.MenuPickDateColumn },
                                  new[] { PageTableLayout.PickFolder, PageTableLayout.PickDate }, offers);
        for (int i = 0; i < pages.Count; i++) _rows.Add((pages[i], table.Rows[i].Box));
        table.Changed += UpdateContinue;
        // Return reaches Continue with a row selected — when Continue is live.
        table.Enter = () => { if (_stage == Stage.Choose && Ticked().Count > 0) _ = Advance(); };

        var find = new TextBox { PlaceholderText = AssistWording.MenuFindAPage };
        AutomationProperties.SetName(find, AssistWording.MenuFindAPage);
        AutomationProperties.SetAutomationId(find, "sectionVerbFind");
        find.TextChanged += (_, _) =>
        {
            string wanted = find.Text.Trim();
            table.ShowOnly(row => wanted.Length == 0
                                  || pages[row.Index].Title.Contains(wanted, StringComparison.CurrentCultureIgnoreCase)
                                  || pages[row.Index].Folder.Contains(wanted, StringComparison.CurrentCultureIgnoreCase));
        };
        var panel = new StackPanel { Spacing = 12, MinWidth = 460 };
        panel.Children.Add(Words(publishing ? AssistWording.MenuPickPagesToPublish : AssistWording.MenuPickPagesToHide));
        panel.Children.Add(find);
        panel.Children.Add(table.Panel);
        // The table's height is counted from EVERY page offered, never the
        // search's leftovers, so the dialog stays still while the teacher
        // types (the mac's #608); the window decides how many of them.
        void Rows()
        {
            int rows = PageTableLayout.PickerRows(WindowHeight, pages.Count);
            table.SetRows(rows);
            App.LogDiagnostic($"Pages to tick: window {WindowHeight:0} epx tall, dialog {_planWidth:0} wide, {rows} rows tall of {pages.Count}");
        }
        Rows();
        ShowChoosing(panel);
        _relayout = Rows;
        UpdateContinue();
    }

    private void UpdateContinue()
    {
        if (_stage == Stage.Choose && _rows.Count > 0) DialogButtons.EnablePrimary(_dialog, _rows.Any(row => row.Box.IsChecked == true));
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

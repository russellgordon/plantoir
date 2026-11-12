using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// A section's Problems tab (#734, the mac's <c>ProblemsTableView</c>, #717):
/// one row per problem its last build met, with a tick per row — ticked means
/// included, every row starts ticked, for the session — sortable by every
/// column but the tick and the Problem (the mac's), and the repair inline
/// where a problem has one, because the alert no longer comes with every
/// build.
/// </summary>
/// <remarks>
/// <para><b>Drawn OVER the section's site</b>, as the last child of the
/// section's content grid, with an opaque background; the
/// <c>WebView2</c> underneath is never removed from the tree and its source
/// is never reset (the mac rejected a <c>TabView</c> for exactly that: it
/// throws the live page away). <see cref="SectionDetailView"/> also collapses
/// what is underneath while this shows, so the covered page and console leave
/// the Tab order and the UI Automation tree — measured, documentation/
/// 12-windows-app.md → "A section's Problems tab".</para>
///
/// <para><b>The tick rules are <see cref="TickTable"/>'s</b> (Space on its way
/// down, a held Space's repeats swallowed, the row's <c>ItemStatus</c> ticked
/// / not ticked), called rather than copied. The builder is not: this table's
/// first column is a box with no title, its Problem cell carries a button, and
/// its headers sort.</para>
///
/// <para>Fix with Claude… and Fix with Codex… go UNDER the table (#736, a
/// later piece): <see cref="Footer"/> is where they go, and
/// <see cref="TickedRowIds"/> is what they hand over.</para>
/// </remarks>
internal sealed class SectionProblemsView : UserControl
{
    /// <summary>The columns that sort, and how (the mac's: every column but the tick and the Problem).</summary>
    internal enum SortColumn { Kind, Page, FirstFound, LastFound }

    private sealed class Row
    {
        public required SectionProblemRow Problem { get; init; }
        public required SectionProblemsRules.RowState State { get; init; }
        public required int Order { get; init; }
        public required string Kind { get; init; }
        public required string Page { get; init; }
        public required ListViewItem Item { get; init; }
        public required CheckBox Box { get; init; }
        public Button? Repair { get; init; }
    }

    // Column widths: the tick, Kind, Page, Problem (the rest), First found, Last found.
    private const double TickWidth = 64, KindWidth = 150, PageWidth = 180, DateWidth = 150;

    private readonly Course _course;
    private readonly int _sectionNumber;
    private readonly Func<string?> _folder;
    private readonly Action<SectionProblemRow> _repair;
    private readonly TextBlock _intro;
    private readonly Grid _header;
    private readonly ListView _list;
    private readonly Dictionary<SortColumn, Button> _sortButtons = new();
    private readonly List<Row> _rows = new();
    private SectionProblemsRecord? _shownRecord;
    private IReadOnlyList<SectionProblemsRecord> _shownOthers = Array.Empty<SectionProblemsRecord>();
    private SortColumn _sortedBy = SortColumn.Kind;
    private bool _ascending = true;

    /// <summary>Under the table: where #736's two buttons go.</summary>
    internal StackPanel Footer { get; }

    /// <summary>How long the last build of the rows took, and how many — for the measurement under <c>--state-dir</c>.</summary>
    internal (int Rows, double Milliseconds) LastBuild { get; private set; }

    internal SectionProblemsView(Course course, int sectionNumber, Func<string?> folder, Action<SectionProblemRow> repair)
    {
        _course = course;
        _sectionNumber = sectionNumber;
        _folder = folder;
        _repair = repair;
        AutomationProperties.SetAutomationId(this, "sectionProblems");
        if (Application.Current.Resources.TryGetValue("SolidBackgroundFillColorBaseBrush", out var fill) && fill is Brush brush)
            Background = brush;

        _intro = new TextBlock { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 4) };
        if (Quiet() is { } quiet) _intro.Foreground = quiet;
        AutomationProperties.SetAutomationId(_intro, "problemsIntro");

        _header = Columns();
        _header.Margin = new Thickness(PageTableLayout.TableBorder + PageTableLayout.RowPadding, 0,
                                       PageTableLayout.TableBorder + PageTableLayout.RowPadding, 0);
        AddHeader(Plain(SectionProblemsWording.ColumnIncluded), 0);
        AddHeader(SortButton(SortColumn.Kind, SectionProblemsWording.ColumnKind), 1);
        AddHeader(SortButton(SortColumn.Page, SectionProblemsWording.ColumnPage), 2);
        AddHeader(Plain(SectionProblemsWording.ColumnProblem), 3);
        AddHeader(SortButton(SortColumn.FirstFound, SectionProblemsWording.ColumnFirstFound), 4);
        AddHeader(SortButton(SortColumn.LastFound, SectionProblemsWording.ColumnLastFound), 5);

        _list = new ListView
        {
            SelectionMode = ListViewSelectionMode.Single,
            IsItemClickEnabled = false,
            BorderThickness = new Thickness(PageTableLayout.TableBorder),
            CornerRadius = new CornerRadius(4),
        };
        if (Application.Current.Resources.TryGetValue("CardStrokeColorDefaultBrush", out var stroke) && stroke is Brush strokeBrush)
            _list.BorderBrush = strokeBrush;
        AutomationProperties.SetAutomationId(_list, "problemsTable");
        AutomationProperties.SetName(_list, SectionProblemsWording.TabProblems);
        _list.PreviewKeyDown += (_, args) =>
        {
            if (TickTable.ItemWithTheFocus(_list) is not { } item) return;
            // Space inside the row's repair button presses the button, not the tick.
            if (args.OriginalSource is Button) return;
            if (_rows.FirstOrDefault(row => ReferenceEquals(row.Item, item)) is { } row)
                TickTable.TickWithSpace(args, _list, row.Item, row.Box);
        };

        Footer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };

        var layout = new Grid { Padding = new Thickness(16, 12, 16, 12), RowSpacing = 6 };
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(_intro, 0);
        Grid.SetRow(_header, 1);
        Grid.SetRow(_list, 2);
        Grid.SetRow(Footer, 3);
        layout.Children.Add(_intro);
        layout.Children.Add(_header);
        layout.Children.Add(_list);
        layout.Children.Add(Footer);
        Content = layout;
        ShowTheSort();
    }

    // ---- What the teacher has ticked (#736 hands these over) --------------

    /// <summary>The ids of the rows ticked now, in the order shown.</summary>
    internal IReadOnlyList<string> TickedRowIds =>
        _list.Items.OfType<ListViewItem>()
            .Select(item => _rows.First(row => ReferenceEquals(row.Item, item)))
            .Where(row => row.Box.IsChecked == true)
            .Select(row => row.Problem.Id)
            .ToList();

    /// <summary>A box was ticked or unticked.</summary>
    internal event Action? TicksChanged;

    // ---- Showing a record ------------------------------------------------

    /// <summary>
    /// Shows <paramref name="record"/>'s rows. Built again only when the record
    /// or another section's (which decides "fixed in the source") is a
    /// different read: the store hands back the same object for a file that
    /// has not moved, so the window coming to the front rebuilds nothing.
    /// </summary>
    internal void Show(SectionProblemsRecord record, IReadOnlyList<SectionProblemsRecord> others)
    {
        _intro.Text = SectionProblemsWording.IntroFor(ReferenceCourse.ShownCode(_course), _sectionNumber);
        if (ReferenceEquals(record, _shownRecord) && others.Count == _shownOthers.Count
            && others.Zip(_shownOthers).All(pair => ReferenceEquals(pair.First, pair.Second)))
            return;
        _shownRecord = record;
        _shownOthers = others;

        var clock = Stopwatch.StartNew();
        _rows.Clear();
        _list.Items.Clear();
        var duplicates = record.Rows
            .GroupBy(problem => (problem.Kind, SectionProblemsWording.PageColumn(problem)))
            .Where(group => group.Count() > 1)
            .Select(group => group.Key)
            .ToHashSet();
        bool repairsOffered = !ReferenceCourse.IsKeptForReference(_course);
        for (int order = 0; order < record.Rows.Count; order++)
        {
            var problem = record.Rows[order];
            var state = SectionProblemsRules.State(problem, record, others);
            string kind = SectionProblemsWording.LabelOfKind(problem.Kind);
            string page = SectionProblemsWording.PageColumn(problem);
            string said = SectionProblemsWording.ProblemColumn(problem, state);
            // Unique, and naming its row: kind and page, and the problem's own
            // words when another row has the same kind on the same page.
            string rowName = duplicates.Contains((problem.Kind, page))
                ? $"{kind}, {page}, {Shortened(said, 80)}"
                : $"{kind}, {page}";
            _rows.Add(MakeRow(problem, state, order, kind, page, said, rowName, repairsOffered));
        }
        Sort();
        LastBuild = (record.Rows.Count, clock.Elapsed.TotalMilliseconds);
        // For a test run ONLY (--state-dir): how many rows were built, and how
        // long that took — the 300-row measurement reads it (review change 4).
        // Never in a teacher's run: Narrator would read it.
        if (AppDataRoot.IsRedirected)
            AutomationProperties.SetItemStatus(_list, $"built {LastBuild.Rows} rows in {LastBuild.Milliseconds:0} ms");
    }

    private Row MakeRow(SectionProblemRow problem, SectionProblemsRules.RowState state, int order,
                        string kind, string page, string said, string rowName, bool repairsOffered)
    {
        var grid = Columns();
        var box = new CheckBox
        {
            IsChecked = SectionProblems.IsTicked(problem.Id, _folder(), _course.Code, _sectionNumber),
            MinWidth = 0,
            VerticalAlignment = VerticalAlignment.Center,
        };
        AutomationProperties.SetName(box, $"{SectionProblemsWording.ColumnIncluded}: {rowName}");
        AutomationProperties.SetAutomationId(box, "problemTick-" + problem.Id);
        grid.Children.Add(box);

        Cell(grid, kind, 1);
        Cell(grid, page, 2);

        var problemCell = new Grid { ColumnSpacing = 8 };
        problemCell.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        problemCell.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new TextBlock
        {
            Text = said,
            TextWrapping = TextWrapping.Wrap,
            MaxLines = 3,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (state == SectionProblemsRules.RowState.FixedInTheSource)
        {
            if (Quiet() is { } quiet) text.Foreground = quiet;
            AutomationProperties.SetAutomationId(text, "problemFixedInTheSource-" + problem.Id);
        }
        problemCell.Children.Add(text);
        Button? repair = null;
        if (repairsOffered && state == SectionProblemsRules.RowState.Current
            && SiteHealthRepair.ButtonTitle(new[] { problem.AsFinding(_course.Code, _sectionNumber) }) is { } title)
        {
            repair = new Button { Content = title, VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(8, 2, 8, 2) };
            // Its Name says which row it belongs to (review change 3).
            AutomationProperties.SetName(repair, $"{title}: {rowName}");
            AutomationProperties.SetAutomationId(repair, "problemRepair-" + problem.Id);
            repair.Click += (_, _) => _repair(problem);
            Grid.SetColumn(repair, 1);
            problemCell.Children.Add(repair);
        }
        Grid.SetColumn(problemCell, 3);
        grid.Children.Add(problemCell);

        Cell(grid, DateText(problem.FirstSeen), 4);
        Cell(grid, DateText(problem.LastSeen), 5);

        string help = SectionProblemsWording.Help(problem);
        var item = new ListViewItem
        {
            Content = grid,
            MinHeight = PlanTableLayout.RowPitch,
            Padding = new Thickness(PageTableLayout.RowPadding, 4, PageTableLayout.RowPadding, 4),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
        if (help.Length > 0) ToolTipService.SetToolTip(item, help);
        AutomationProperties.SetAutomationId(item, "problemRow-" + problem.Id);
        AutomationProperties.SetName(item, $"{kind}, {page}, {said}");
        // The whole of what the folder problem says, where Narrator reads it.
        AutomationProperties.SetHelpText(item, help);
        TickTable.Status(item, box);
        box.Checked += (_, _) => Ticked(problem.Id, item, box);
        box.Unchecked += (_, _) => Ticked(problem.Id, item, box);
        return new Row { Problem = problem, State = state, Order = order, Kind = kind, Page = page, Item = item, Box = box, Repair = repair };
    }

    private void Ticked(string rowId, ListViewItem item, CheckBox box)
    {
        SectionProblems.SetTicked(box.IsChecked == true, rowId, _folder(), _course.Code, _sectionNumber);
        TickTable.Status(item, box);
        TicksChanged?.Invoke();
    }

    // ---- Sorting ------------------------------------------------------------

    private Button SortButton(SortColumn column, string title)
    {
        var button = new Button
        {
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Left,
            HorizontalContentAlignment = HorizontalAlignment.Left,
        };
        AutomationProperties.SetName(button, title);
        AutomationProperties.SetAutomationId(button, "problemsSort-" + column);
        button.Click += (_, _) =>
        {
            _ascending = _sortedBy != column || !_ascending;
            _sortedBy = column;
            Sort();
            ShowTheSort();
        };
        _sortButtons[column] = button;
        return button;
    }

    /// <summary>
    /// Says the sort on the header: an arrow after the sorted column's title,
    /// and — the most UI Automation allows a plain button — its ItemStatus.
    /// A header button has no SortDirection to set: that belongs to a
    /// table's column header, and a ListView exposes none.
    /// </summary>
    private void ShowTheSort()
    {
        foreach (var (column, button) in _sortButtons)
        {
            string title = (string)AutomationProperties.GetName(button);
            bool sorted = column == _sortedBy;
            var face = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            face.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold });
            if (sorted)
                face.Children.Add(new FontIcon { Glyph = _ascending ? "" : "", FontSize = 10, VerticalAlignment = VerticalAlignment.Center });
            button.Content = face;
            AutomationProperties.SetItemStatus(button, sorted ? (_ascending ? "sorted ascending" : "sorted descending") : "");
        }
    }

    private void Sort()
    {
        // Ties keep the record's own order, in either direction.
        var list = (_ascending ? _rows.OrderBy(SortKey) : _rows.OrderByDescending(SortKey))
            .ThenBy(row => row.Order)
            .ToList();
        var focusedItem = TickTable.ItemWithTheFocus(_list);
        _list.Items.Clear();
        foreach (var row in list) _list.Items.Add(row.Item);
        TickTable.Band(_list);
        if (focusedItem is not null && _list.Items.Contains(focusedItem)) _list.SelectedItem = focusedItem;
    }

    private IComparable SortKey(Row row) => _sortedBy switch
    {
        SortColumn.Page => row.Page.ToLower(CultureInfo.CurrentCulture),
        SortColumn.FirstFound => row.Problem.FirstSeen ?? DateTimeOffset.MinValue,
        SortColumn.LastFound => row.Problem.LastSeen ?? DateTimeOffset.MinValue,
        _ => row.Kind.ToLower(CultureInfo.CurrentCulture),
    };

    // ---- Focus (review change 3) -------------------------------------------

    /// <summary>The first row, focused — after Show on the alert, so the keyboard lands on what Show opened, never on the covered page.</summary>
    internal void FocusTheTable()
    {
        if (_list.Items.FirstOrDefault() is ListViewItem first)
        {
            _list.SelectedItem = first;
            first.Focus(FocusState.Programmatic);
        }
        else _list.Focus(FocusState.Programmatic);
    }

    /// <summary>A row by its problem id, focused — after its repair's outcome closes. False when it is no longer shown.</summary>
    internal bool FocusRow(string rowId)
    {
        if (_rows.FirstOrDefault(row => row.Problem.Id == rowId) is not { } row || !_list.Items.Contains(row.Item)) return false;
        _list.SelectedItem = row.Item;
        return row.Item.Focus(FocusState.Programmatic);
    }

    /// <summary>Whether the keyboard focus is anywhere inside this view.</summary>
    internal bool ContainsFocus()
    {
        if (XamlRoot is not { } root || FocusManager.GetFocusedElement(root) is not DependencyObject focused) return false;
        for (var node = focused; node is not null; node = VisualTreeHelper.GetParent(node))
            if (ReferenceEquals(node, this)) return true;
        return false;
    }

    // ---- Layout helpers -----------------------------------------------------

    private static Grid Columns()
    {
        var grid = new Grid { ColumnSpacing = PageTableLayout.ColumnSpacing };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(TickWidth) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(KindWidth) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(PageWidth) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 160 });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(DateWidth) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(DateWidth) });
        return grid;
    }

    private void AddHeader(FrameworkElement cell, int column)
    {
        Grid.SetColumn(cell, column);
        _header.Children.Add(cell);
    }

    private static TextBlock Plain(string text) => new() { Text = text, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };

    private static void Cell(Grid grid, string text, int column)
    {
        var cell = new TextBlock
        {
            Text = text,
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextWrapping = TextWrapping.NoWrap,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (text.Length > 0) ToolTipService.SetToolTip(cell, text);
        Grid.SetColumn(cell, column);
        grid.Children.Add(cell);
    }

    private static Brush? Quiet() =>
        Application.Current.Resources.TryGetValue("TextFillColorSecondaryBrush", out var secondary) ? secondary as Brush : null;

    /// <summary>A local short date and time, as the mac's abbreviated date and shortened time; empty for none.</summary>
    internal static string DateText(DateTimeOffset? when) =>
        when is { } moment ? moment.ToLocalTime().ToString("d MMM yyyy, h:mm tt", CultureInfo.CurrentCulture) : "";

    private static string Shortened(string text, int most) =>
        text.Length <= most ? text : text[..(most - 1)] + "…";
}

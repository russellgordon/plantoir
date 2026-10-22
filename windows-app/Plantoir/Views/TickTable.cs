using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Assist;

namespace Plantoir.Views;

/// <summary>
/// A list of pages to tick, as a bordered table with banded rows (#634, the
/// mac's #608): Page â€” the checkbox IS the title â€” then the other columns
/// (Folder and Date for Publish Pagesâ€¦ and Hide Pagesâ€¦; Date for the question
/// about classes dated later, at Publish Pagesâ€¦ and at Deploy). ONE builder
/// for the three, so they cannot drift.
/// </summary>
/// <remarks>
/// <para><b>The tick rules</b> (the mac's, measured there on a real
/// <c>NSTableView</c>): a click on a box ticks it â€” and on its title, which is
/// the box's content; selecting a row ticks nothing; Space ticks the selected
/// row (or the row the focus is in); Return reaches the dialog's main button
/// with a row selected (a <c>ListView</c> keeps Return for itself â€” measured
/// for #548 â€” so it is caught on its way down). Space typed in Find a Page
/// never reaches the list: the field is its sibling.</para>
///
/// <para>Space is taken on its way DOWN and its way UP: a focused
/// <c>CheckBox</c> clicks on key-up, so a key-down taken here and a key-up let
/// through would flip a focused box twice (the plan review's amendment 2).</para>
///
/// <para>Each row tells Narrator whether it is ticked
/// (<c>AutomationProperties.ItemStatus</c>), updated on every change, so a
/// teacher moving through the ROWS hears the state the box shows.</para>
/// </remarks>
internal sealed class TickTable
{
    /// <summary>One page offered: its title, the box's own accessible name and id, the row's id, and the other cells.</summary>
    public sealed record Offer(string Title, string BoxName, string BoxId, string RowId, IReadOnlyList<string> Cells, bool Ticked);

    public sealed class Row
    {
        public required int Index { get; init; }
        public required Offer Offer { get; init; }
        public required CheckBox Box { get; init; }
        public required ListViewItem Item { get; init; }
        public required Grid Cells { get; init; }
    }

    /// <summary>Plain words for Narrator, beside the box's own state.</summary>
    internal const string TickedStatus = "ticked", NotTickedStatus = "not ticked";

    private readonly double[] _otherWidths;
    private readonly List<Grid> _grids = new();
    private readonly List<Row> _rows = new();

    public ListView List { get; }
    public Grid Header { get; }

    /// <summary>The header and the table, together.</summary>
    public StackPanel Panel { get; }

    public IReadOnlyList<Row> Rows => _rows;

    /// <summary>A box was ticked or unticked, by any means.</summary>
    public event Action? Changed;

    /// <summary>Return with the table focused: the dialog's main button.</summary>
    public Action? Enter { get; set; }

    public TickTable(string id, string name, IReadOnlyList<string> otherHeaders, IReadOnlyList<double> otherWidths,
                     IReadOnlyList<Offer> offers)
    {
        _otherWidths = otherWidths.ToArray();
        List = new ListView
        {
            SelectionMode = ListViewSelectionMode.Single,
            IsItemClickEnabled = false,
            BorderThickness = new Thickness(PageTableLayout.TableBorder),
            CornerRadius = new CornerRadius(4),
        };
        if (Application.Current.Resources.TryGetValue("CardStrokeColorDefaultBrush", out var stroke) && stroke is Brush brush)
            List.BorderBrush = brush;
        AutomationProperties.SetAutomationId(List, id);
        AutomationProperties.SetName(List, name);

        Header = Columns();
        Header.Margin = new Thickness(PageTableLayout.TableBorder + PageTableLayout.RowPadding, 0,
                                      PageTableLayout.TableBorder + PageTableLayout.RowPadding, 0);
        var headers = new[] { AssistWording.MenuPlanPageColumn }.Concat(otherHeaders).ToList();
        for (int i = 0; i < headers.Count; i++)
        {
            var cell = new TextBlock { Text = headers[i], FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };
            Grid.SetColumn(cell, i);
            Header.Children.Add(cell);
        }

        Brush? quiet = Application.Current.Resources.TryGetValue("TextFillColorSecondaryBrush", out var secondary) ? secondary as Brush : null;
        for (int index = 0; index < offers.Count; index++)
        {
            var offer = offers[index];
            var grid = Columns();
            var box = new CheckBox
            {
                Content = new TextBlock { Text = offer.Title, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap },
                IsChecked = offer.Ticked,
                MinWidth = 0,
                VerticalAlignment = VerticalAlignment.Center,
            };
            ToolTipService.SetToolTip(box, offer.Title);
            AutomationProperties.SetName(box, offer.BoxName);
            AutomationProperties.SetAutomationId(box, offer.BoxId);
            grid.Children.Add(box);
            for (int c = 0; c < offer.Cells.Count; c++)
            {
                var cell = new TextBlock
                {
                    Text = offer.Cells[c],
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    TextWrapping = TextWrapping.NoWrap,
                    VerticalAlignment = VerticalAlignment.Center,
                };
                if (quiet is not null) cell.Foreground = quiet;
                if (offer.Cells[c].Length > 0) ToolTipService.SetToolTip(cell, offer.Cells[c]);
                Grid.SetColumn(cell, c + 1);
                grid.Children.Add(cell);
            }
            var item = new ListViewItem
            {
                Content = grid,
                MinHeight = PlanTableLayout.RowPitch,
                Padding = new Thickness(PageTableLayout.RowPadding, 0, PageTableLayout.RowPadding, 0),
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
            };
            AutomationProperties.SetAutomationId(item, offer.RowId);
            AutomationProperties.SetName(item, string.Join(", ", new[] { offer.Title }.Concat(offer.Cells.Where(text => text.Length > 0))));
            var row = new Row { Index = index, Offer = offer, Box = box, Item = item, Cells = grid };
            Status(row);
            box.Checked += (_, _) => { Status(row); Changed?.Invoke(); };
            box.Unchecked += (_, _) => { Status(row); Changed?.Invoke(); };
            _rows.Add(row);
        }
        ShowOnly(_ => true);

        List.PreviewKeyDown += (_, args) =>
        {
            if (args.Key == Windows.System.VirtualKey.Enter)
            {
                if (Enter is null) return;
                args.Handled = true;
                Enter();
                return;
            }
            if (args.Key != Windows.System.VirtualKey.Space) return;
            if (RowWithTheFocus() is not { } row) return;
            args.Handled = true;
            row.Box.IsChecked = row.Box.IsChecked != true;
            List.SelectedItem = row.Item;
        };
        // The box's own click comes on key-up: taken too, so Space flips once.
        List.PreviewKeyUp += (_, args) =>
        {
            if (args.Key == Windows.System.VirtualKey.Space && RowWithTheFocus() is not null) args.Handled = true;
        };

        Panel = new StackPanel { Spacing = 4 };
        Panel.Children.Add(Header);
        Panel.Children.Add(List);
    }

    /// <summary>
    /// The question about classes dated after the next class (#475), at
    /// Publish Pagesâ€¦ and at Deploy: Page and Date, every class ticked. Each
    /// box is named by its title (it was "title â€” day" when the day was in the
    /// box's words), and its row "title, day".
    /// </summary>
    public static TickTable ForLaterClasses(IReadOnlyList<ClassesDatedLater.Page> flagged, string name)
    {
        var offers = new List<Offer>();
        for (int index = 0; index < flagged.Count; index++)
        {
            var page = flagged[index];
            string day = page.Date is { } date ? AssistWording.LaterClassesDay(date) : "";
            offers.Add(new Offer(page.Title, page.Title, $"laterClass{index}", $"laterClassRow{index}", new[] { day }, Ticked: true));
        }
        return new TickTable("laterClassesTable", name,
                             new[] { AssistWording.MenuPickDateColumn }, new[] { PageTableLayout.PickDate }, offers);
    }

    private static void Status(Row row) =>
        AutomationProperties.SetItemStatus(row.Item, row.Box.IsChecked == true ? TickedStatus : NotTickedStatus);

    private Grid Columns()
    {
        var grid = new Grid { ColumnSpacing = PageTableLayout.ColumnSpacing };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        foreach (double width in _otherWidths)
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(width) });
        _grids.Add(grid);
        return grid;
    }

    /// <summary>The row the keyboard focus is in, else the selected row â€” and only a row the table is showing.</summary>
    private Row? RowWithTheFocus()
    {
        var showing = List.Items.OfType<ListViewItem>().ToHashSet();
        if (List.XamlRoot is { } root && Microsoft.UI.Xaml.Input.FocusManager.GetFocusedElement(root) is DependencyObject focused)
        {
            for (var node = focused; node is not null; node = VisualTreeHelper.GetParent(node))
                if (node is ListViewItem item && showing.Contains(item))
                    return _rows.FirstOrDefault(row => ReferenceEquals(row.Item, item));
        }
        return List.SelectedItem is ListViewItem selected && showing.Contains(selected)
            ? _rows.FirstOrDefault(row => ReferenceEquals(row.Item, selected))
            : null;
    }

    /// <summary>Shows the rows <paramref name="shown"/> keeps, in their order, banded by their shown position. Ticks are kept.</summary>
    public void ShowOnly(Func<Row, bool> shown)
    {
        List.Items.Clear();
        foreach (var row in _rows.Where(shown)) List.Items.Add(row.Item);
        Band(List);
    }

    /// <summary>The table's height, counted from the rows it is told â€” the dialog counts every page offered, never a search's leftovers.</summary>
    public void SetRows(int rows) => List.Height = rows * PlanTableLayout.RowPitch + 2 * PageTableLayout.TableBorder;

    /// <summary>
    /// Alternate rows take a quiet fill, counted by the rows SHOWN, so a search
    /// or a sort never leaves two bands together (#634, the mac's banded
    /// <c>.bordered(alternatesRowBackgrounds: true)</c>). Used by the plan table
    /// and Start of Year too, so the steps of one flow look alike.
    /// </summary>
    public static void Band(ListView list)
    {
        Brush? band = Application.Current.Resources.TryGetValue("SubtleFillColorSecondaryBrush", out var fill) ? fill as Brush : null;
        var clear = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        int shown = 0;
        foreach (var item in list.Items.OfType<ListViewItem>())
            item.Background = shown++ % 2 == 1 && band is not null ? band : clear;
    }
}

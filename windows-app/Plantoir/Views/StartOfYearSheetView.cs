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
/// The Start of Year sheet before Go, drawn (#619, mac #589): what must be
/// read before Go in a capped area above — the warnings first, and never cut —
/// the two list headings as the summary, a read-only table sortable by its
/// headers (Page, Folder, Why) with a row for every page going into draft, and
/// the notes under it, the ones that must be read before Go first. Built on
/// #548's pieces: <see cref="PlanTable.Row"/> and <see cref="PlanTableOrder"/>.
/// How much of each part shows is <see cref="StartOfYearSheetLayout"/>'s,
/// from the window's height and each part measured at the sheet's width.
/// </summary>
internal static class StartOfYearSheetView
{
    /// <summary>
    /// The sheet's width at the window's 900-epx minimum, as the Section menu's
    /// plan table (#548); since #634 (the mac's #621, the sheets resize) it
    /// follows a wider window up to 300 more (<see cref="PageTableLayout.DialogWidth"/>),
    /// and the Page column takes the width (Why capped at 300, the mac's).
    /// </summary>
    private const double SheetWidth = PageTableLayout.PageSheetWidth;

    /// <summary>ContentDialog's padding at each side of its content.</summary>
    private const double DialogPadding = PageTableLayout.DialogPadding;

    private const double ColumnSpacing = PageTableLayout.ColumnSpacing, RowPadding = PageTableLayout.RowPadding;

    /// <summary>A row is at least this tall (<c>ListViewItem.MinHeight</c>, measured 32 epx for #548).</summary>
    private const double OneLineRow = PlanTableLayout.RowPitch;

    /// <summary>What a row adds round its Why text when that text is two lines tall.</summary>
    private const double RowTextMargin = 12;

    public static void Build(ContentDialog dialog, StartOfYearSheet sheet)
    {
        // The template reads these once, so they are opened wide and the
        // content carries the width, which follows the window (#634). Every
        // fit is #619's up to 756 epx; a taller window gives the table rows.
        dialog.Resources["ContentDialogMaxWidth"] = 100000.0;
        dialog.Resources["ContentDialogMaxHeight"] = 100000.0;

        // ---- Above the table: the warnings first, then the intro.
        var above = new StackPanel { Spacing = 8 };
        var warnings = new StackPanel { Spacing = 8 };
        Brush? caution = Application.Current.Resources.TryGetValue("SystemFillColorCautionBrush", out var c) ? c as Brush : null;
        for (int i = 0; i < sheet.Warnings.Count; i++)
        {
            var warning = Words(sheet.Warnings[i], $"startOfYearWarning{i}");
            if (caution is not null) warning.Foreground = caution;
            warnings.Children.Add(warning);
        }
        if (sheet.Warnings.Count > 0) above.Children.Add(warnings);
        above.Children.Add(Words(sheet.Intro, "startOfYearPlan"));
        var aboveScroller = new ScrollViewer { Content = above };
        AutomationProperties.SetAutomationId(aboveScroller, "startOfYearPlanIntro");

        // ---- The summary: the two list headings, unchanged words.
        var summary = new StackPanel { Spacing = 2 };
        for (int i = 0; i < sheet.Summary.Count; i++)
        {
            var line = Words(sheet.Summary[i], $"startOfYearPlanSummary{i}");
            line.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
            summary.Children.Add(line);
        }

        // ---- The table.
        var grids = new List<Grid>();
        Grid Columns()
        {
            var grid = new Grid { ColumnSpacing = ColumnSpacing };
            for (int i = 0; i < 3; i++) grid.ColumnDefinitions.Add(new ColumnDefinition());
            grids.Add(grid);
            return grid;
        }
        void SizeTheColumns(double sheetWidth)
        {
            var (page, folder, why) = PageTableLayout.StartOfYearColumns(sheetWidth);
            foreach (var grid in grids)
            {
                grid.ColumnDefinitions[0].Width = new GridLength(page);
                grid.ColumnDefinitions[1].Width = new GridLength(folder);
                grid.ColumnDefinitions[2].Width = new GridLength(why);
            }
        }
        var list = new ListView
        {
            SelectionMode = ListViewSelectionMode.None,
            IsItemClickEnabled = false,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            TabIndex = 1,
        };
        if (Application.Current.Resources.TryGetValue("CardStrokeColorDefaultBrush", out var stroke) && stroke is Brush brush)
            list.BorderBrush = brush;
        AutomationProperties.SetAutomationId(list, "startOfYearPlanTable");
        AutomationProperties.SetName(list, string.Join(" ", sheet.Summary));

        var rowItems = new Dictionary<int, ListViewItem>();
        var whyCells = new Dictionary<int, TextBlock>();
        foreach (var row in sheet.Rows)
        {
            var grid = Columns();
            string[] cells = { row.Title, row.Folder, row.WhatChanges };
            for (int i = 0; i < cells.Length; i++)
            {
                bool why = i == 2;
                var cell = new TextBlock
                {
                    Text = cells[i],
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    // Why takes the rest of the width and wraps to two lines:
                    // the longest reason, cut on one line, lost its useful half (mac #589).
                    TextWrapping = why ? TextWrapping.Wrap : TextWrapping.NoWrap,
                    MaxLines = why ? 2 : 1,
                    VerticalAlignment = VerticalAlignment.Center,
                };
                ToolTipService.SetToolTip(cell, cells[i]);
                Grid.SetColumn(cell, i);
                grid.Children.Add(cell);
                if (why) whyCells[row.Position] = cell;
            }
            var item = new ListViewItem { Content = grid, MinHeight = OneLineRow, Padding = new Thickness(RowPadding, 0, RowPadding, 0) };
            AutomationProperties.SetAutomationId(item, $"startOfYearPlanRow{row.Position}");
            AutomationProperties.SetName(item, $"{row.Title}, {row.Folder}, {row.WhatChanges}");
            rowItems[row.Position] = item;
        }

        var order = PlanTableOrder.Opening;
        void Fill()
        {
            list.Items.Clear();
            foreach (var row in PlanTableOrder.Sorted(sheet.Rows, order.Column, order.Ascending))
                list.Items.Add(rowItems[row.Position]);
            TickTable.Band(list);
        }
        var header = Columns();
        header.Margin = new Thickness(RowPadding + PageTableLayout.TableBorder, 0, RowPadding + PageTableLayout.TableBorder, 0);
        var sortButtons = new List<(Button Button, string Title, PlanTableOrder.Column Column)>();
        void TitleTheHeaders()
        {
            foreach (var (button, title, column) in sortButtons)
            {
                button.Content = PlanTableOrder.Header(title, column, order);
                AutomationProperties.SetName(button, column != order.Column ? $"Sort by {title}"
                    : $"Sort by {title}, sorted {(order.Ascending ? "ascending" : "descending")}");
            }
        }
        foreach (var (title, column, slot, id) in new[]
                 {
                     (AssistWording.MenuPlanPageColumn, PlanTableOrder.Column.Page, 0, "startOfYearPlanSortPage"),
                     (AssistWording.MenuPlanFolderColumn, PlanTableOrder.Column.Folder, 1, "startOfYearPlanSortFolder"),
                     (StartOfYearWording.ReasonColumn, PlanTableOrder.Column.Change, 2, "startOfYearPlanSortWhy"),
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

        // ---- Under the table: what must be read before Go first.
        var notes = new StackPanel { Spacing = 6 };
        var mustRead = new StackPanel { Spacing = 6 };
        for (int i = 0; i < sheet.MustReadNotes.Count; i++)
            mustRead.Children.Add(Words(sheet.MustReadNotes[i], $"startOfYearPlanNote{i}"));
        notes.Children.Add(mustRead);
        for (int i = 0; i < sheet.OtherNotes.Count; i++)
        {
            var note = Words(sheet.OtherNotes[i], $"startOfYearPlanNote{sheet.MustReadNotes.Count + i}");
            if (Application.Current.Resources.TryGetValue("TextFillColorSecondaryBrush", out var secondary) && secondary is Brush quiet)
                note.Foreground = quiet;
            notes.Children.Add(note);
        }
        var notesScroller = new ScrollViewer { Content = notes };
        AutomationProperties.SetAutomationId(notesScroller, "startOfYearPlanNotes");

        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(aboveScroller);
        if (sheet.Summary.Count > 0) panel.Children.Add(summary);
        panel.Children.Add(header);
        panel.Children.Add(list);
        panel.Children.Add(notesScroller);
        dialog.Content = panel;

        // ---- How much of each part shows, from the window's height; again
        // whenever the window changes size while the sheet is up.
        StartOfYearSheetLayout.Fit? fitted = null;
        double measuredChrome = StartOfYearSheetLayout.Chrome;
        double fittedWidth = 0;
        SizeTheColumns(SheetWidth);
        panel.Width = SheetWidth - 2 * DialogPadding;
        void Refit()
        {
            if (dialog.XamlRoot is not { } root) return;
            double windowHeight = root.Size.Height > 0 ? root.Size.Height : StartOfYearSheetLayout.DialogMaxHeight;
            double sheetWidth = root.Size.Width > 0 ? PageTableLayout.DialogWidth(SheetWidth, root.Size.Width) : SheetWidth;
            double contentWidth = sheetWidth - 2 * DialogPadding;
            panel.Width = contentWidth;
            SizeTheColumns(sheetWidth);
            double whyWidth = PageTableLayout.StartOfYearColumns(sheetWidth).Why;

            double Height(UIElement element)
            {
                element.Measure(new Windows.Foundation.Size(contentWidth, double.PositiveInfinity));
                return element.DesiredSize.Height;
            }
            double warningsHeight = sheet.Warnings.Count > 0 ? Height(warnings) : 0;
            double aboveHeight = Height(above);
            double mustReadHeight = Height(mustRead);
            double notesHeight = Height(notes);
            var rowHeights = new List<double>();
            foreach (var row in sheet.Rows)
            {
                var why = whyCells[row.Position];
                why.Measure(new Windows.Foundation.Size(Math.Max(1, whyWidth), double.PositiveInfinity));
                double height = Math.Max(OneLineRow, Math.Ceiling(why.DesiredSize.Height + RowTextMargin));
                rowItems[row.Position].MinHeight = height;
                rowHeights.Add(height);
            }

            var fit = StartOfYearSheetLayout.For(windowHeight, measuredChrome, warningsHeight, aboveHeight,
                                                 mustReadHeight, notesHeight, rowHeights);
            if (fit == fitted && fittedWidth == sheetWidth) return;
            fitted = fit;
            fittedWidth = sheetWidth;
            aboveScroller.MaxHeight = fit.AboveCap;
            list.MaxHeight = fit.TableHeight;
            notesScroller.MaxHeight = fit.NotesCap;
            App.LogDiagnostic(
                $"Start of Year sheet: window {windowHeight:0} epx tall, {sheetWidth:0} wide; chrome {measuredChrome:0}; " +
                $"warnings {warningsHeight:0}, above {aboveHeight:0} (shown {fit.AboveCap:0}); " +
                $"rows {rowHeights.Count} ({rowHeights.Count(h => h > OneLineRow)} two-line, heights {string.Join("/", rowHeights.Distinct().Select(h => h.ToString("0")))}), " +
                $"{fit.Rows} shown in {fit.TableHeight:0}; notes must-read {mustReadHeight:0}, all {notesHeight:0} (shown {fit.NotesCap:0}); " +
                $"sheet {fit.Height:0} epx{(fit.AllShown ? ", nothing scrolls" : "")}");
        }

        // The real dialog's height once laid out, for the chrome: what is
        // neither above, rows nor notes — the title, padding, summary, header
        // and buttons. Read on the first layout pass after the fit, logged,
        // and used for every later fit while the sheet is up.
        bool chromeRead = false;
        void ReadTheChrome(object? sender, object e)
        {
            if (chromeRead || fitted is not { } fit || BoxOf(dialog) is not { ActualHeight: > 0 } box) return;
            chromeRead = true;
            dialog.LayoutUpdated -= ReadTheChrome;
            double parts = aboveScroller.ActualHeight + list.ActualHeight + notesScroller.ActualHeight;
            double chrome = box.ActualHeight - parts;
            App.LogDiagnostic($"Start of Year sheet laid out: dialog {box.ActualHeight:0} epx; above {aboveScroller.ActualHeight:0}, " +
                              $"table {list.ActualHeight:0}, notes {notesScroller.ActualHeight:0}; chrome {chrome:0} " +
                              $"(the layout assumed {measuredChrome:0}); window {dialog.XamlRoot?.Size.Height:0}");
            if (Math.Abs(chrome - measuredChrome) > 1)
            {
                measuredChrome = Math.Ceiling(chrome);
                fitted = null;
                Refit();
            }
        }

        Windows.Foundation.TypedEventHandler<XamlRoot, XamlRootChangedEventArgs>? refit = null;
        dialog.Opened += (_, _) =>
        {
            Refit();
            dialog.LayoutUpdated += ReadTheChrome;
            if (dialog.XamlRoot is { } root)
            {
                refit = (_, _) => Refit();
                root.Changed += refit;
            }
            list.Focus(FocusState.Programmatic);
        };
        dialog.Closed += (_, _) =>
        {
            if (refit is not null && dialog.XamlRoot is { } root) root.Changed -= refit;
            dialog.LayoutUpdated -= ReadTheChrome;
        };
    }

    /// <summary>The dialog's visible box: its template's <c>BackgroundElement</c>.</summary>
    private static FrameworkElement? BoxOf(ContentDialog dialog)
    {
        var queue = new Queue<DependencyObject>();
        queue.Enqueue(dialog);
        while (queue.Count > 0)
        {
            var node = queue.Dequeue();
            if (node is FrameworkElement { Name: "BackgroundElement" } box) return box;
            int count = VisualTreeHelper.GetChildrenCount(node);
            for (int i = 0; i < count; i++) queue.Enqueue(VisualTreeHelper.GetChild(node, i));
        }
        return null;
    }

    private static TextBlock Words(string text, string id)
    {
        var block = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        AutomationProperties.SetAutomationId(block, id);
        return block;
    }
}

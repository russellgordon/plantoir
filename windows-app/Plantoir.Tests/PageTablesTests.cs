using Plantoir.Core.Assist;
using Change = Plantoir.Core.Assist.PlanTable.Change;

namespace Plantoir.Tests;

/// <summary>
/// #634 (the mac's #608, #621, #622): the rules under the page-table dialogs
/// that can be proven without a window — which plan rows fold, the
/// disclosure's words, the table's height with the disclosure closed, the
/// picker's rows, and the dialogs' widths and columns as the window grows.
/// The tick rules and the drawn heights are in <c>PageTablesUiTests</c>.
/// </summary>
public class PageTablesTests
{
    private static PlanTable.Row R(int position, Change change) =>
        new(position, $"Page {position}", "Concepts", change, change.ToString());

    /// <summary>A plan: <paramref name="changes"/> rows that change, then <paramref name="already"/> already right, in plan order.</summary>
    private static PlanTable Plan(int changes, int already, bool publishing = true, params Change[] alsoToRead)
    {
        var rows = new List<PlanTable.Row>();
        for (int i = 0; i < changes; i++) rows.Add(R(rows.Count, publishing ? Change.WillBecomeVisible : Change.WillBecomeHidden));
        foreach (var change in alsoToRead) rows.Add(R(rows.Count, change));
        for (int i = 0; i < already; i++) rows.Add(R(rows.Count, publishing ? Change.AlreadyVisible : Change.AlreadyHidden));
        return new PlanTable("summary", rows, Array.Empty<string>());
    }

    // ---- Which rows fold (#622) -----------------------------------------------

    [Fact]
    public void APublishPlanFoldsOnlyThePagesAlreadyVisible_AndOpeningDrawsThemInPlanOrder()
    {
        var plan = Plan(5, 16);
        Assert.True(plan.FoldsAlreadyRight);
        Assert.Equal(5, plan.DrawnRows(open: false).Count);
        Assert.All(plan.DrawnRows(open: false), row => Assert.False(PlanTable.IsAlreadyRight(row.Change)));
        var open = plan.DrawnRows(open: true);
        Assert.Equal(21, open.Count);
        Assert.Equal(plan.RowsToRead.Concat(plan.RowsAlreadyRight).Select(row => row.Position), open.Select(row => row.Position));
        Assert.Equal(Enumerable.Range(5, 16), open.Skip(5).Select(row => row.Position));
    }

    /// <summary>
    /// Every page that stays FOR A REASON is a row to read — only already
    /// visible and already hidden fold. Must-fail: count a kept, left-alone or
    /// no-room row as already right.
    /// </summary>
    [Fact]
    public void PagesKeptForAReasonAreRowsToRead()
    {
        var plan = Plan(1, 3, true, Change.StaysVisible, Change.StaysAsItIs, Change.StaysExactlyAsItIs);
        Assert.Equal(4, plan.RowsToRead.Count);
        Assert.Equal(new[] { Change.WillBecomeVisible, Change.StaysVisible, Change.StaysAsItIs, Change.StaysExactlyAsItIs },
                     plan.RowsToRead.Select(row => row.Change));
        Assert.Equal(3, plan.RowsAlreadyRight.Count);
    }

    [Fact]
    public void AHidePlanFoldsThePagesAlreadyHidden()
    {
        var plan = Plan(2, 2, publishing: false);
        Assert.True(plan.FoldsAlreadyRight);
        Assert.Equal(2, plan.DrawnRows(false).Count);
        Assert.Equal(4, plan.DrawnRows(true).Count);
        Assert.Equal(AssistWording.MenuPlanShowAlready(2, publishing: false), plan.FoldLabel);
    }

    /// <summary>A plan with nothing else to read shows every row and no disclosure (the mac's <c>foldsAlreadyRight</c>).</summary>
    [Fact]
    public void APlanWithNothingElseToReadShowsEveryRowAndNoDisclosure()
    {
        var onlyAlready = Plan(0, 4);
        Assert.False(onlyAlready.FoldsAlreadyRight);
        Assert.Null(onlyAlready.FoldLabel);
        Assert.Equal(4, onlyAlready.DrawnRows(open: false).Count);
        Assert.Equal(4, onlyAlready.RowsWhenClosed);

        var nothingAlready = Plan(3, 0);
        Assert.False(nothingAlready.FoldsAlreadyRight);
        Assert.Null(nothingAlready.FoldLabel);
        Assert.Equal(3, nothingAlready.DrawnRows(open: false).Count);
    }

    /// <summary>
    /// The disclosure's words say the pages' own state. Must-fail: reading
    /// "publishing" from the plan's FIRST row, which is a change, not a page
    /// already right.
    /// </summary>
    [Fact]
    public void TheDisclosureNamesTheCountAndTheState()
    {
        Assert.Equal(AssistWording.MenuPlanShowAlready(16, publishing: true), Plan(5, 16).FoldLabel);
        Assert.Equal(AssistWording.MenuPlanShowAlreadyOnePage, Plan(5, 1).FoldLabel);
        Assert.Equal(AssistWording.MenuPlanShowAlreadyOnePageHiding, Plan(5, 1, publishing: false).FoldLabel);
        var kept = new PlanTable("s", new[] { R(0, Change.StaysVisible), R(1, Change.AlreadyHidden) }, Array.Empty<string>());
        Assert.Equal(AssistWording.MenuPlanShowAlreadyOnePageHiding, kept.FoldLabel);
    }

    // ---- The table's height with the disclosure closed ------------------------

    /// <summary>
    /// The table is as tall as the rows to read, never fewer than five while
    /// pages are folded (or every row, when there are fewer), and the count is
    /// the SAME open and closed — opening never grows the dialog. Must-fail:
    /// counting the drawn rows (5 + 16 → 21).
    /// </summary>
    [Theory]
    [InlineData(5, 16, 5)]
    [InlineData(1, 16, 5)]
    [InlineData(1, 4, 5)]
    [InlineData(1, 2, 3)]
    [InlineData(14, 1, 14)]
    [InlineData(0, 9, 9)]
    public void TheTableIsCountedWithTheDisclosureClosed(int changes, int already, int rows)
    {
        var plan = Plan(changes, already);
        Assert.Equal(rows, plan.RowsWhenClosed);
    }

    // ---- The picker's rows (#608) ---------------------------------------------

    [Fact]
    public void ThePickerShowsTwelveRowsAtMostWithin756_FewerOnAShortWindow_AndOneForOnePage()
    {
        Assert.Equal(12, PageTableLayout.PickerRows(756, 40));
        Assert.Equal(3, PageTableLayout.PickerRows(756, 3));
        Assert.Equal(1, PageTableLayout.PickerRows(756, 1));
        Assert.Equal(1, PageTableLayout.PickerRows(330, 1));
        Assert.Equal(0, PageTableLayout.PickerRows(756, 0));
        Assert.Equal(PageTableLayout.FewestPickerRows, PageTableLayout.PickerRows(200, 40));
        // The 600-epx window minimum (a XAML root of about 563): what fits.
        int atMinimum = PageTableLayout.PickerRows(563, 40);
        Assert.InRange(atMinimum, PageTableLayout.FewestPickerRows, PageTableLayout.MostPickerRows);
        Assert.True(PageTableLayout.PickerChrome + atMinimum * PlanTableLayout.RowPitch + 2 <= 563);
        // A window taller than 756 gives the table its rows.
        Assert.Equal(12 + 7, PageTableLayout.PickerRows(1000, 40));
        Assert.Equal(40, PageTableLayout.PickerRows(4000, 40));
    }

    // ---- Widths: the window is the resize handle (#621) ------------------------

    /// <summary>
    /// Today's width at the 900-epx window minimum and under (a narrow work
    /// area still gets the window less 24 a side), growing one for one past it,
    /// up to 300 more (the director's Windows-only cap). Must-fail: pinning the
    /// base, or dropping the cap.
    /// </summary>
    [Fact]
    public void TheDialogIsItsOldWidthAtTheWindowMinimum_AndGrowsWithTheWindowUpTo300More()
    {
        Assert.Equal(680, PageTableLayout.DialogWidth(680, 900));
        Assert.Equal(680, PageTableLayout.DialogWidth(680, 886));        // a root about 14 epx inside a 900 window
        Assert.Equal(595 - 48, PageTableLayout.DialogWidth(680, 595));
        Assert.Equal(780, PageTableLayout.DialogWidth(680, 1000));
        Assert.Equal(980, PageTableLayout.DialogWidth(680, 1280));
        Assert.Equal(980, PageTableLayout.DialogWidth(680, 2560));
        Assert.Equal(548, PageTableLayout.DialogWidth(548, 900));
        Assert.Equal(848, PageTableLayout.DialogWidth(548, 1920));
        for (double window = 300; window <= 3000; window += 13)
        {
            double width = PageTableLayout.DialogWidth(680, window);
            Assert.True(width <= window - 2 * PageTableLayout.Margin, $"{width} at {window}");
            Assert.True(width >= Math.Min(680, window - 2 * PageTableLayout.Margin));
            Assert.True(width <= 980);
        }
    }

    /// <summary>
    /// At 680 the plan's columns are exactly #548's, and Start of Year's
    /// #619's; wider, the capped column stops (What changes 320, Why 300, the
    /// mac's caps) and Page takes the rest. Must-fail: giving the added width to
    /// What changes or Why.
    /// </summary>
    [Fact]
    public void ThePageColumnTakesTheAddedWidth()
    {
        var plan = PageTableLayout.PlanColumns(680);
        Assert.Equal((170.0, 150.0), (Math.Round(plan.Page, 6), plan.Folder));
        Assert.Equal(262, Math.Round(plan.Change, 6));
        var wide = PageTableLayout.PlanColumns(980);
        Assert.Equal(PageTableLayout.PlanChangeMost, wide.Change);
        Assert.Equal(PageTableLayout.CellsWidth(980) - 150 - 24 - 320, wide.Page, 6);
        Assert.True(wide.Page > 400);

        var year = PageTableLayout.StartOfYearColumns(680);
        Assert.Equal((170.0, 140.0, 272.0), (Math.Round(year.Page, 6), year.Folder, Math.Round(year.Why, 6)));
        var yearWide = PageTableLayout.StartOfYearColumns(980);
        Assert.Equal(PageTableLayout.YearWhyMost, yearWide.Why);
        Assert.Equal(PageTableLayout.CellsWidth(980) - 140 - 24 - 300, yearWide.Page, 6);

        // Narrower than 680 (a narrow work area): both share what is left in the old proportion.
        var narrow = PageTableLayout.PlanColumns(547);
        Assert.True(narrow.Page > 0 && narrow.Change > 0);
        Assert.Equal(170.0 / 262.0, narrow.Page / narrow.Change, 6);
    }
}

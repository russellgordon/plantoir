using System;

namespace Plantoir.Core.Assist;

/// <summary>
/// The page-table dialogs' sizes (#634, the mac's #608 and #621): how wide
/// the dialog is at a window's width, how that width is shared between the
/// columns, and how many rows the picker shows. Pure, so it is tested
/// without a window.
/// </summary>
/// <remarks>
/// <para><b>The window is the dialog's resize handle.</b> On the mac the
/// sheets became resizable: they open at their old size, which is their
/// minimum, and the table and the Page column take whatever the teacher adds.
/// A ContentDialog has no edge to drag, so here the teacher makes the WINDOW
/// bigger. At the 900-epx window minimum (#542) every dialog is the width it
/// was before; each epx of window past that is an epx of dialog, up to
/// <see cref="MostAdded"/> more — a Windows-only cap (the director's ruling
/// of 2026-10-22, pending Russell), so a maximised window does not make a
/// table 1,700 epx wide.</para>
/// </remarks>
public static class PageTableLayout
{
    /// <summary>
    /// The window width at which every page dialog is the width it always was:
    /// the window's 900-epx minimum (#542). The XAML root is about 14 epx
    /// narrower than the window's outer edge, so growth starts a little past
    /// the outer minimum.
    /// </summary>
    public const double WindowMinimumWidth = 900;

    /// <summary>What a dialog leaves of the window at each side when the window is narrow (#548).</summary>
    public const double Margin = 24;

    /// <summary>The Section menu's page dialogs and Start of Year: their width before #634.</summary>
    public const double PageSheetWidth = 680;

    /// <summary>The question about classes dated later at Deploy: its width before #634 (ContentDialog's own 548).</summary>
    public const double DeployQuestionWidth = 548;

    /// <summary>The most a wider window adds to a dialog's width (Windows-only; see the remarks).</summary>
    public const double MostAdded = 300;

    /// <summary>ContentDialog's padding at each side of its content.</summary>
    public const double DialogPadding = 24;

    /// <summary>
    /// The dialog's width at a window's (XAML root's) width:
    /// <paramref name="baseWidth"/> up to the window minimum, growing one for
    /// one past it up to <see cref="MostAdded"/> more, and never wider than the
    /// window less <see cref="Margin"/> at each side.
    /// </summary>
    public static double DialogWidth(double baseWidth, double windowWidth)
    {
        double grown = Math.Clamp(windowWidth - (WindowMinimumWidth - baseWidth), baseWidth, baseWidth + MostAdded);
        return Math.Min(grown, windowWidth - 2 * Margin);
    }

    /// <summary>
    /// Two flexible columns sharing <paramref name="room"/> (the width left once
    /// the fixed column and the spacing are taken) exactly as they did at the
    /// old width — <paramref name="pageAtBase"/> : <paramref name="otherAtBase"/> —
    /// until the other reaches <paramref name="otherMost"/>; past that, Page
    /// takes every epx (the mac's #621: the width added goes to the titles).
    /// </summary>
    public static (double Page, double Other) Share(double room, double pageAtBase, double otherAtBase, double otherMost)
    {
        room = Math.Max(0, room);
        double other = room * otherAtBase / (pageAtBase + otherAtBase);
        if (other > otherMost) other = otherMost;
        return (room - other, other);
    }

    /// <summary>Between columns; the rows' padding at each side; the table's border at each side.</summary>
    public const double ColumnSpacing = 12, RowPadding = 12, TableBorder = 1;

    /// <summary>The width a row's cells share: the content less the table's border and the rows' padding.</summary>
    public static double CellsWidth(double dialogWidth) => dialogWidth - 2 * DialogPadding - 2 * TableBorder - 2 * RowPadding;

    // ---- The plan table (#548): Page | Folder | What changes ----------------

    public const double PlanPageAtBase = 170, PlanFolder = 150, PlanChangeMost = 320;

    /// <summary>The plan table's three columns at a dialog width; at 680 exactly #548's 170 / 150 / the rest.</summary>
    public static (double Page, double Folder, double Change) PlanColumns(double dialogWidth)
    {
        double changeAtBase = CellsWidth(PageSheetWidth) - PlanPageAtBase - PlanFolder - 2 * ColumnSpacing;
        var (page, change) = Share(CellsWidth(dialogWidth) - PlanFolder - 2 * ColumnSpacing,
                                   PlanPageAtBase, changeAtBase, PlanChangeMost);
        return (page, PlanFolder, change);
    }

    // ---- Start of Year (#619): Page | Folder | Why ---------------------------

    public const double YearPageAtBase = 170, YearFolder = 140, YearWhyMost = 300;

    /// <summary>Start of Year's three columns; at 680 exactly #619's 170 / 140 / the rest.</summary>
    public static (double Page, double Folder, double Why) StartOfYearColumns(double dialogWidth)
    {
        double whyAtBase = CellsWidth(PageSheetWidth) - YearPageAtBase - YearFolder - 2 * ColumnSpacing;
        var (page, why) = Share(CellsWidth(dialogWidth) - YearFolder - 2 * ColumnSpacing,
                                YearPageAtBase, whyAtBase, YearWhyMost);
        return (page, YearFolder, why);
    }

    // ---- The picker and the later-classes list (#608): Page | Folder | Date -

    /// <summary>The picker's fixed columns; Page takes the rest.</summary>
    public const double PickFolder = 140, PickDate = 170;

    /// <summary>Rows the picker and the later-classes list show before scrolling, as the mac's <c>mostPickerRowsShown</c>.</summary>
    public const int MostPickerRows = 12;

    /// <summary>The fewest rows, when there are that many pages.</summary>
    public const int FewestPickerRows = 2;

    /// <summary>
    /// Everything on the picker stage that is not its rows or the table's
    /// border: the title, the dialog's padding, the sentence, Find a Page, the
    /// header, the panel's spacing and the buttons. The later-classes stage
    /// has no Find but a note under the table, about the same. Measured in the
    /// window (documentation/12-windows-app.md → #634); the dialog logs the
    /// rows it chose.
    /// </summary>
    public const double PickerChrome = 300;

    /// <summary>
    /// How many rows tall the picker (or the later-classes list) is: counted
    /// from EVERY page <paramref name="offered"/> — never the ones a search
    /// leaves — so the dialog stays still while the teacher types; up to
    /// <see cref="MostPickerRows"/> within <see cref="PlanTableLayout.DialogMaxHeight"/>,
    /// plus <see cref="PlanTableLayout.ExtraRows"/> for a taller window; never
    /// fewer than two (one, when one page is offered) and never more than offered.
    /// </summary>
    public static int PickerRows(double windowHeight, int offered, double chrome = PickerChrome)
    {
        if (offered <= 0) return 0;
        double room = Math.Min(windowHeight, PlanTableLayout.DialogMaxHeight) - chrome - PlanTableLayout.TableBorder;
        int rows = (int)Math.Clamp(Math.Floor(room / PlanTableLayout.RowPitch), FewestPickerRows, MostPickerRows)
                   + PlanTableLayout.ExtraRows(windowHeight);
        return Math.Min(rows, offered);
    }
}

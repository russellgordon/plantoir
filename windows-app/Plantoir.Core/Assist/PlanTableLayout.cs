using System;

namespace Plantoir.Core.Assist;

/// <summary>
/// How much of the Section menu's plan table (#548) is shown at a window's
/// height: how many rows before the table scrolls, and how tall the notes may
/// be before THEY scroll. Pure, so it is tested without a window.
/// </summary>
/// <remarks>
/// <para>ContentDialog's own content <c>ScrollViewer</c> does not scroll
/// vertically: whatever does not fit is clipped from outside, where no scroll
/// bar can reach it. So everything on the plan stage has to fit, and two parts
/// can give way. The NOTES give way first, down to <see cref="NotesFewest"/>,
/// so that <see cref="PreferredRows"/> rows still show; then the rows, down to
/// <see cref="FewestRows"/>. The notes' cap is the notes scroller's <c>MaxHeight</c>, so a
/// note cut short is scrolled into view, never cut off out of reach (the #548
/// implementation review, finding 1).</para>
///
/// <para>The mac opens at 12 rows and the teacher may drag the sheet taller
/// (#621); this follows the WINDOW instead, because a ContentDialog has no
/// edge to drag and a Windows window is often much shorter
/// (documentation/12-windows-app.md → "The plan as a table" and, since #634,
/// "The picker as a table, the plan folds, the dialogs follow the window").
/// When the plan folds the pages already right, the dialog fixes the table at
/// <see cref="PlanTable.RowsWhenClosed"/> within these rows.</para>
/// </remarks>
public static class PlanTableLayout
{
    public const int MostRows = 12;

    /// <summary>The rows the notes give way to: the notes' cap leaves room for this many.</summary>
    public const int PreferredRows = 4;

    /// <summary>The fewest rows shown, on a window too short for <see cref="PreferredRows"/> and two lines of notes.</summary>
    public const int FewestRows = 2;

    /// <summary>One row's height and pitch: <c>ListViewItem.MinHeight</c> (measured 32 epx).</summary>
    public const double RowPitch = 32;

    /// <summary>The table's border, top and bottom.</summary>
    public const double TableBorder = 2;

    /// <summary>
    /// Everything on the plan stage that is not a row, the table's border or
    /// the notes: the title, the dialog's padding, the summary, the header,
    /// the panel's spacing and the button row. Measured 220–222 epx; 230
    /// leaves a margin.
    /// </summary>
    public const double Chrome = 230;

    /// <summary>The panel's spacing above the notes.</summary>
    public const double NotesSpacing = 8;

    /// <summary>The notes' own cap, as the mac's 120 pt.</summary>
    public const double NotesMost = 120;

    /// <summary>The least the notes are given: about two lines, enough to see that there is more to scroll.</summary>
    public const double NotesFewest = 40;

    /// <summary>
    /// ContentDialog's own <c>ContentDialogMaxHeight</c>, which #548 laid out
    /// within. Since #634 the page dialogs raise that resource and give a
    /// taller window's height to the table (<see cref="ExtraRows"/>); this is
    /// still the height up to which every fit is #548's.
    /// </summary>
    public const double DialogMaxHeight = 756;

    /// <summary>Rows shown before the table scrolls, and the notes' cap (0 when there are none).</summary>
    public readonly record struct Fit(int Rows, double NotesCap)
    {
        public double TableHeight => Rows * RowPitch + TableBorder;
    }

    /// <summary>
    /// The checkbox under the table when the plan folds the pages already
    /// right (#655, the mac's #654; a disclosure since #634): the platform's
    /// 32-epx <c>CheckBox</c>, the 4-epx gap above it, and a 4-epx margin.
    /// 36 would have been an exact fit with no margin, and a fit that comes
    /// out short clips the dialog's buttons — which costs more than the one
    /// row this takes at about one window height in eight. The disclosure it
    /// replaced measured 27 + 4 against 36.
    /// </summary>
    public const double FoldHeight = 40;

    /// <param name="windowHeight">The XAML root's height, epx.</param>
    /// <param name="notesNatural">The notes' height laid out at the dialog's width, uncapped; 0 for none.</param>
    /// <param name="folds">Whether the checkbox shows under the table.</param>
    /// <remarks>
    /// Up to <see cref="DialogMaxHeight"/> this is the #548 fit, unchanged.
    /// A window taller than that gives every further <see cref="RowPitch"/>
    /// to the table (#634, the mac's #621: the sheet resizes, and the table
    /// takes the height added): on Windows the window is the dialog's resize
    /// handle, and 756 epx is the most the dialog ever used before.
    /// </remarks>
    public static Fit For(double windowHeight, double notesNatural, bool folds = false)
    {
        double room = Math.Min(windowHeight, DialogMaxHeight) - Chrome - TableBorder - (folds ? FoldHeight : 0);
        int added = ExtraRows(windowHeight);
        if (notesNatural <= 0)
            return new Fit(Rows(room) + added, 0);
        double cap = Math.Clamp(room - NotesSpacing - PreferredRows * RowPitch, NotesFewest, NotesMost);
        double notes = Math.Min(notesNatural, cap) + NotesSpacing;
        return new Fit(Rows(room - notes) + added, cap);
    }

    /// <summary>The rows a window taller than <see cref="DialogMaxHeight"/> adds to the table.</summary>
    public static int ExtraRows(double windowHeight) =>
        windowHeight > DialogMaxHeight ? (int)Math.Floor((windowHeight - DialogMaxHeight) / RowPitch) : 0;

    private static int Rows(double room) =>
        (int)Math.Clamp(Math.Floor(room / RowPitch), FewestRows, MostRows);
}

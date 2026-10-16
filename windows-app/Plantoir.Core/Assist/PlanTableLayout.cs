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
/// so that <see cref="FewestRows"/> rows still show; then the rows, down to
/// that floor. The notes' cap is the notes scroller's <c>MaxHeight</c>, so a
/// note cut short is scrolled into view, never cut off out of reach (the #548
/// implementation review, finding 1).</para>
///
/// <para>The mac shows a fixed 12 rows; this departs from it deliberately,
/// because a Windows window is often much shorter (documentation/12-windows-app.md
/// → "The plan as a table").</para>
/// </remarks>
public static class PlanTableLayout
{
    public const int MostRows = 12;
    public const int FewestRows = 4;

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

    /// <summary>ContentDialog's <c>ContentDialogMaxHeight</c>: it is never taller than this, whatever the window.</summary>
    public const double DialogMaxHeight = 756;

    /// <summary>Rows shown before the table scrolls, and the notes' cap (0 when there are none).</summary>
    public readonly record struct Fit(int Rows, double NotesCap)
    {
        public double TableHeight => Rows * RowPitch + TableBorder;
    }

    /// <param name="windowHeight">The XAML root's height, epx.</param>
    /// <param name="notesNatural">The notes' height laid out at the dialog's width, uncapped; 0 for none.</param>
    public static Fit For(double windowHeight, double notesNatural)
    {
        double room = Math.Min(windowHeight, DialogMaxHeight) - Chrome - TableBorder;
        if (notesNatural <= 0)
            return new Fit(Rows(room), 0);
        double cap = Math.Clamp(room - NotesSpacing - FewestRows * RowPitch, NotesFewest, NotesMost);
        double notes = Math.Min(notesNatural, cap) + NotesSpacing;
        return new Fit(Rows(room - notes), cap);
    }

    private static int Rows(double room) =>
        (int)Math.Clamp(Math.Floor(room / RowPitch), FewestRows, MostRows);
}

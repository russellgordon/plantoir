using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace Plantoir.Core.Assist;

/// <summary>
/// The order of the Section menu's plan table (#548; the mac's
/// <c>KeyPathComparator</c> on its <c>Table</c>, #524). It opens in PLAN order
/// — the contract's: changes, kept, left alone, no room, already right. A
/// newly pressed column sorts ascending, the same one again flips it, and ties
/// fall back to plan order so the order is total. Modelled on
/// <see cref="Models.AllBackupsOrder"/>.
/// </summary>
public static class PlanTableOrder
{
    public enum Column { Plan, Page, Folder, Change }

    /// <summary>What the dialog opens on: the plan's own order.</summary>
    public static readonly (Column Column, bool Ascending) Opening = (Column.Plan, true);

    /// <summary>The next order after a header is pressed: a new column ascending, the same one flipped.</summary>
    public static (Column Column, bool Ascending) AfterPressing(Column pressed, (Column Column, bool Ascending) now) =>
        pressed == now.Column ? (pressed, !now.Ascending) : (pressed, true);

    /// <summary>The rows in order, by the cells' text, numbers in it compared as numbers.</summary>
    public static IReadOnlyList<PlanTable.Row> Sorted(IReadOnlyList<PlanTable.Row> rows, Column column, bool ascending)
    {
        int Compare(PlanTable.Row a, PlanTable.Row b)
        {
            int byColumn = column switch
            {
                Column.Page => Natural(a.Title, b.Title),
                Column.Folder => Natural(a.Folder, b.Folder),
                Column.Change => Natural(a.WhatChanges, b.WhatChanges),
                _ => a.Position.CompareTo(b.Position),
            };
            if (!ascending) byColumn = -byColumn;
            return byColumn != 0 ? byColumn : a.Position.CompareTo(b.Position);
        }
        var sorted = rows.ToList();
        sorted.Sort(Compare);
        return sorted;
    }

    /// <summary>"▲" or "▼" after the header of the column the rows are sorted by; plan order marks none.</summary>
    public static string Header(string title, Column column, (Column Column, bool Ascending) now) =>
        column == now.Column ? $"{title} {(now.Ascending ? "▲" : "▼")}" : title;

    /// <summary>
    /// "Unit 1, Day 2" before "Unit 1, Day 10", as the mac's string comparator
    /// sorts them (.NET 9 has no numeric ordering of its own): runs of digits
    /// compare by value, everything else by the current culture, ignoring case.
    /// </summary>
    internal static int Natural(string a, string b)
    {
        int i = 0, j = 0;
        while (i < a.Length && j < b.Length)
        {
            if (char.IsAsciiDigit(a[i]) && char.IsAsciiDigit(b[j]))
            {
                int startA = i, startB = j;
                while (i < a.Length && char.IsAsciiDigit(a[i])) i++;
                while (j < b.Length && char.IsAsciiDigit(b[j])) j++;
                string runA = a[startA..i].TrimStart('0'), runB = b[startB..j].TrimStart('0');
                int byLength = runA.Length.CompareTo(runB.Length);
                if (byLength != 0) return byLength;
                int byDigits = string.CompareOrdinal(runA, runB);
                if (byDigits != 0) return byDigits;
                continue;
            }
            int startTextA = i, startTextB = j;
            while (i < a.Length && !char.IsAsciiDigit(a[i])) i++;
            while (j < b.Length && !char.IsAsciiDigit(b[j])) j++;
            int byText = string.Compare(a[startTextA..i], b[startTextB..j], CultureInfo.CurrentCulture,
                                        CompareOptions.IgnoreCase);
            if (byText != 0) return byText;
        }
        return (a.Length - i).CompareTo(b.Length - j);
    }
}

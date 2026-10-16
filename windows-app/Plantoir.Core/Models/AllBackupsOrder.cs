namespace Plantoir.Core.Models;

/// <summary>
/// The order of All Backups' rows (#491 item 7; the mac's <c>BackupRow</c>
/// sorting): by Course, Made or Size, newest first until a header is pressed.
/// A newly chosen column sorts ascending; pressing the same one again flips
/// it. Ties — the same course, the same size — fall back to newest first, so
/// the order never depends on how the folder happened to be read.
/// </summary>
public static class AllBackupsOrder
{
    public enum Column { Course, Made, Size }

    /// <summary>What the dialog opens on: newest first.</summary>
    public static readonly (Column Column, bool Ascending) Opening = (Column.Made, false);

    /// <summary>The next order after a header is pressed: a new column ascending, the same one flipped.</summary>
    public static (Column Column, bool Ascending) AfterPressing(Column pressed, (Column Column, bool Ascending) now) =>
        pressed == now.Column ? (pressed, !now.Ascending) : (pressed, true);

    /// <summary>
    /// The rows in order. A size that could not be measured sorts as -1, below
    /// every real size (the row says it could not be read).
    /// </summary>
    public static IReadOnlyList<(BackupItem Item, long? Bytes)> Sorted(
        IReadOnlyList<(BackupItem Item, long? Bytes)> rows, Column column, bool ascending)
    {
        int Compare((BackupItem Item, long? Bytes) a, (BackupItem Item, long? Bytes) b)
        {
            int byColumn = column switch
            {
                Column.Course => string.Compare(a.Item.CourseCode, b.Item.CourseCode, StringComparison.OrdinalIgnoreCase),
                Column.Size => (a.Bytes ?? -1).CompareTo(b.Bytes ?? -1),
                _ => a.Item.BackedUpAt.CompareTo(b.Item.BackedUpAt),
            };
            if (!ascending) byColumn = -byColumn;
            if (byColumn != 0) return byColumn;
            // Ties: newest first, then by file, so the order is total.
            int newest = b.Item.BackedUpAt.CompareTo(a.Item.BackedUpAt);
            return newest != 0 ? newest : string.Compare(a.Item.FilePath, b.Item.FilePath, StringComparison.OrdinalIgnoreCase);
        }
        var sorted = rows.ToList();
        sorted.Sort(Compare);
        return sorted;
    }

    /// <summary>"▲" or "▼" after the header of the column the rows are sorted by.</summary>
    public static string Header(string title, Column column, (Column Column, bool Ascending) now) =>
        column == now.Column ? $"{title} {(now.Ascending ? "▲" : "▼")}" : title;
}

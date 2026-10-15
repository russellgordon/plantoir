using Plantoir.Core.Models;
using Column = Plantoir.Core.Models.AllBackupsOrder.Column;

namespace Plantoir.Tests;

/// <summary>#491 item 7: All Backups sorts by Course, Made or Size, newest first until a header is pressed.</summary>
public class AllBackupsOrderTests
{
    private static (BackupItem, long?) Row(string code, int day, long? bytes) =>
        (new BackupItem(code, new DateTime(2026, 9, day, 12, 0, 0), $@"C:\b\{code}_backup_2026-09-{day:00}_120000.zip"), bytes);

    private static readonly IReadOnlyList<(BackupItem Item, long? Bytes)> Rows = new[]
    {
        Row("MFM2P", 1, 300), Row("ICS3U", 3, 100), Row("ICS3U", 2, null), Row("ENG1D", 4, 100),
    };

    private static string[] Order(Column column, bool ascending) =>
        AllBackupsOrder.Sorted(Rows, column, ascending).Select(r => $"{r.Item.CourseCode}/{r.Item.BackedUpAt.Day}").ToArray();

    [Fact]
    public void ItOpensNewestFirst()
    {
        Assert.Equal((Column.Made, false), AllBackupsOrder.Opening);
        Assert.Equal(new[] { "ENG1D/4", "ICS3U/3", "ICS3U/2", "MFM2P/1" }, Order(Column.Made, false));
    }

    [Fact]
    public void ByCourse_TiesNewestFirst()
    {
        Assert.Equal(new[] { "ENG1D/4", "ICS3U/3", "ICS3U/2", "MFM2P/1" }, Order(Column.Course, true));
        Assert.Equal(new[] { "MFM2P/1", "ICS3U/3", "ICS3U/2", "ENG1D/4" }, Order(Column.Course, false));
    }

    [Fact]
    public void BySize_AnUnmeasuredSizeIsTheSmallest_TiesNewestFirst()
    {
        Assert.Equal(new[] { "ICS3U/2", "ENG1D/4", "ICS3U/3", "MFM2P/1" }, Order(Column.Size, true));
        Assert.Equal(new[] { "MFM2P/1", "ENG1D/4", "ICS3U/3", "ICS3U/2" }, Order(Column.Size, false));
    }

    [Fact]
    public void ANewColumnSortsAscending_TheSameOneFlips()
    {
        Assert.Equal((Column.Size, true), AllBackupsOrder.AfterPressing(Column.Size, AllBackupsOrder.Opening));
        Assert.Equal((Column.Made, true), AllBackupsOrder.AfterPressing(Column.Made, AllBackupsOrder.Opening));
        Assert.Equal((Column.Size, false), AllBackupsOrder.AfterPressing(Column.Size, (Column.Size, true)));
    }

    [Fact]
    public void TheSortedHeaderCarriesItsArrow()
    {
        Assert.Equal("Made ▼", AllBackupsOrder.Header("Made", Column.Made, AllBackupsOrder.Opening));
        Assert.Equal("Size ▲", AllBackupsOrder.Header("Size", Column.Size, (Column.Size, true)));
        Assert.Equal("Course", AllBackupsOrder.Header("Course", Column.Course, AllBackupsOrder.Opening));
    }
}

using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The one line #144's reader writes: a remembered timetable naming a date
/// that cannot be a class date is set aside, and the trail says so, with
/// the date, so a problem report can explain an assistant that asked for a
/// timetable the disk still holds. In <c>SharedActivityState</c> because the
/// trail's path is process-wide.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class TimetableSetAsideTrailTests : IDisposable
{
    private readonly string _root;

    public TimetableSetAsideTrailTests()
    {
        _root = Directory.CreateTempSubdirectory("plantoir-144-trail").FullName;
        ActivityTrail.SetCustomLogPathForTesting(Path.Combine(_root, "trail.txt"));
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    [Fact]
    public void SettingATimetableAsideLeavesALineNamingTheDate()
    {
        string folder = Path.Combine(_root, "courses", "ICS3U", ".internal", "timetable");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "section1.json"),
            """{"section":1,"dates":["2569-09-08","2569-09-10"],"source":"typed in by hand","recorded":"2569-09-09"}""");

        Assert.Null(TimetableMemory.Read(_root, "ics3u", 1, today: new DateOnly(2026, 9, 9)));

        string trail = File.ReadAllText(Path.Combine(_root, "trail.txt"));
        Assert.Contains("ICS3U/1 · remembered timetable set aside: it names 2569-09-08", trail);
        Assert.Contains("the assistant will ask for the timetable again", trail);
    }

    [Fact]
    public void ABelievableTimetableLeavesNoSuchLine()
    {
        string folder = Path.Combine(_root, "courses", "ICS3U", ".internal", "timetable");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "section1.json"),
            """{"section":1,"dates":["2026-09-08","2026-09-10"],"source":"typed in by hand","recorded":"2026-09-09"}""");

        Assert.NotNull(TimetableMemory.Read(_root, "ICS3U", 1, today: new DateOnly(2026, 9, 9)));
        string trailPath = Path.Combine(_root, "trail.txt");
        Assert.True(!File.Exists(trailPath) || !File.ReadAllText(trailPath).Contains("set aside"));
    }
}

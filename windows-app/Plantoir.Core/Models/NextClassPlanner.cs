using System.Text.RegularExpressions;
using Plantoir.Core.Assist;

namespace Plantoir.Core.Models;

/// <summary>
/// The page for the next class: the one that comes after the last one a
/// section has, on the next day it meets.
///
/// <para>Every method takes the course's own word for a unit, defaulting to
/// "Unit" so a caller that has none keeps the answer it always had. Passing it
/// matters: in a course that says Module, parsing for "Unit" finds no numbered
/// classes at all, and this would then propose "Unit 1, Day 1" for a course
/// that already has thirty Module pages.</para>
/// </summary>
public static class NextClassPlanner
{
    public static UnitDay NextUnitAndDay(IEnumerable<string> pageTitles, string? term = null)
    {
        var unitDays = pageTitles
            .Select(t => UnitDay.Parse(t, term))
            .Where(u => u.HasValue)
            .Select(u => u!.Value)
            .ToList();

        if (unitDays.Count == 0)
            return new UnitDay(1, 1);

        int highestUnit = unitDays.Max(u => u.Unit);
        int highestDay = unitDays.Where(u => u.Unit == highestUnit).Max(u => u.Day);
        return new UnitDay(highestUnit, highestDay + 1);
    }

    public static UnitDay FirstDayOfANewUnit(IEnumerable<string> pageTitles, string? term = null)
    {
        var unitDays = pageTitles
            .Select(t => UnitDay.Parse(t, term))
            .Where(u => u.HasValue)
            .Select(u => u!.Value)
            .ToList();

        if (unitDays.Count == 0)
            return new UnitDay(1, 1);

        int highestUnit = unitDays.Max(u => u.Unit);
        return new UnitDay(highestUnit + 1, 1);
    }

    public static List<string> NumberedClasses(IEnumerable<string> pageTitles, string? term = null)
    {
        return pageTitles
            .Select(t => (Title: t, UnitDay: UnitDay.Parse(t, term)))
            .Where(x => x.UnitDay.HasValue)
            .OrderBy(x => x.UnitDay!.Value.Unit)
            .ThenBy(x => x.UnitDay!.Value.Day)
            .Select(x => x.Title)
            .ToList();
    }

    public static DateOnly Date(int position, IReadOnlyList<DateOnly> dates, string courseCode, int sectionNumber)
    {
        if (dates.Count == 0)
            throw new AssistRefusal($"I don’t know when {courseCode} Section {sectionNumber} meets, so I can’t date a new class. {AssistWording.MayIAskForYourDates}");

        if (position < dates.Count)
            return dates[position];

        return dates[^1];
    }
}

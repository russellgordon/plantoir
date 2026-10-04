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
    public static UnitDay NextUnitAndDay(IEnumerable<string> pageTitles, string? term = null) =>
        NextUnitAndDay(pageTitles, new ClassPageNaming(term, ClassPageScheme.UnitDay));

    /// <summary>The next position under a course's naming: in a numbered course, one past the HIGHEST number (a gap is never filled).</summary>
    public static UnitDay NextUnitAndDay(IEnumerable<string> pageTitles, ClassPageNaming naming)
    {
        var unitDays = pageTitles
            .Select(t => naming.Parse(t))
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

    public static List<string> NumberedClasses(IEnumerable<string> pageTitles, string? term = null) =>
        NumberedClasses(pageTitles, new ClassPageNaming(term, ClassPageScheme.UnitDay));

    public static List<string> NumberedClasses(IEnumerable<string> pageTitles, ClassPageNaming naming)
    {
        return pageTitles
            .Select(t => (Title: t, UnitDay: naming.Parse(t)))
            .Where(x => x.UnitDay.HasValue)
            .OrderBy(x => x.UnitDay!.Value.Unit)
            .ThenBy(x => x.UnitDay!.Value.Day)
            .Select(x => x.Title)
            .ToList();
    }

    /// <summary>
    /// A numbered course's next date (#274, mac <c>positionAfterTheLatestPage</c>):
    /// the first class day after the LATEST dated page, because a numbered
    /// course orders by date and may have gaps. Position counting gave CODING's
    /// next page a date five weeks before Week 8. Null when the timetable has no
    /// day after it (the caller then shares the last day, as the ordinary path does).
    /// </summary>
    public static DateOnly? DateAfterTheLatestPage(IEnumerable<DateOnly?> pageDates, IReadOnlyList<DateOnly> timetable)
    {
        var latest = pageDates.Where(d => d is not null).Select(d => d!.Value).DefaultIfEmpty(DateOnly.MinValue).Max();
        return timetable.Where(d => d > latest).OrderBy(d => d).Cast<DateOnly?>().FirstOrDefault();
    }

    /// <summary>
    /// The refusal for "start a new unit" or "add days to a unit" in a numbered
    /// course (<c>refusals</c> → <c>noUnitsInANumberedCourse</c>). Says "page", not
    /// "meeting": a refusal is one string for both audiences, and the model's
    /// words are not changed by #274. The mac's sentence, word for word.
    /// </summary>
    public static string NoUnitsInANumberedCourse(string courseCode, string word) =>
        $"{courseCode} numbers its pages one after another — “{word} 1”, “{word} 2” — and has " +
        "no units, so there is no unit to start or add days to. Ask for the next page " +
        "instead and it takes the next number.";

    public static DateOnly Date(int position, IReadOnlyList<DateOnly> dates, string courseCode, int sectionNumber)
    {
        if (dates.Count == 0)
            throw new AssistRefusal($"I don’t know when {courseCode} Section {sectionNumber} meets, so I can’t date a new class. {AssistWording.MayIAskForYourDates}");

        if (position < dates.Count)
            return dates[position];

        return dates[^1];
    }
}

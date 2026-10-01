using Newtonsoft.Json.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// The school years a reference course can be filed under
/// (<c>shared-rules.json → referenceCourses.schoolYearLabel / schoolYearsOffered /
/// schoolYearRead</c>, #241).
///
/// <para>A school year is named for the calendar year it STARTS in and stored
/// as that integer, so the dash never reaches the file format. A new year
/// appears on 1 August — the same rule as <c>Timetable.AcademicYearStarting</c>,
/// which the contract names as where it was inherited from. Every function
/// takes the DAY rather than reading the clock, so each contract case runs.</para>
/// </summary>
public static class SchoolYear
{
    /// <summary>The floor: 2022–23 is the oldest year ever offered (Russell's; it does not move).</summary>
    public const int EarliestStartingYear = 2022;

    /// <summary>The group a course with no usable year is filed under, always last.</summary>
    public const string OtherGroupName = "Other";

    /// <summary>The school year containing <paramref name="day"/>.</summary>
    public static int StartingYear(DateOnly day) => Plantoir.Core.Assist.Timetable.AcademicYearStarting(day);

    /// <summary>Newest first, from the year containing today down to the floor.</summary>
    public static IReadOnlyList<int> Offered(DateOnly day)
    {
        int newest = StartingYear(day);
        if (newest < EarliestStartingYear) return Array.Empty<int>();
        return Enumerable.Range(EarliestStartingYear, newest - EarliestStartingYear + 1).Reverse().ToList();
    }

    /// <summary>"2025–26": the starting year, an EN DASH, the last two digits of the next.</summary>
    public static string Label(int startingYear)
    {
        int endsIn = startingYear + 1;
        return $"{startingYear}–{((endsIn % 100) + 100) % 100:D2}";
    }

    /// <summary>"2025–26", or "no school year" — how a trail line and a sentence name a year.</summary>
    public static string Name(int? startingYear, string none = "no school year") =>
        startingYear is int year ? Label(year) : none;

    /// <summary>
    /// A stored <c>reference_school_year</c> as a year, or null ("Other"). A
    /// whole number within the years offered on <paramref name="day"/> and
    /// nothing else: a missing key, a null, a hand-edited 2019, a 2031 written
    /// with a wrong clock, a word and a <c>true</c> all land in Other, where a
    /// teacher can see it and change it.
    /// </summary>
    public static int? Read(JToken? stored, DateOnly day)
    {
        if (stored is not JValue { Type: JTokenType.Integer } value) return null;
        long year;
        try { year = (long)value; } catch { return null; }   // beyond a long: not a year
        return year >= EarliestStartingYear && year <= StartingYear(day) ? (int)year : null;
    }
}

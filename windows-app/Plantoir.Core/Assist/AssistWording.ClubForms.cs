using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// #1027 round 3: sentences a club's teacher reads that said class, each with
/// its <c>…ForAMeeting</c> twin, word for word the mac's
/// <c>AssistWording</c> functions of the same names. The model is always
/// given the class form (#267); only the teacher's copy takes the course's noun.
/// </summary>
public static partial class AssistWording
{
    private static string One(ClassNoun noun) => noun == ClassNoun.Meeting ? "meeting" : "class";

    private static string Many(ClassNoun noun) => noun == ClassNoun.Meeting ? "meetings" : "classes";

    public const string AddClassesNeedsAUnitForAMeeting =
        "No unit was named. Which unit should the meeting pages be added to? Give its number, for example 4.";

    public const string AddClassesNeedsACountForAMeeting = "No number of meeting pages was given. How many should be added?";

    public const string MenuPickPagesToPublishForAMeeting =
        "Tick the pages to publish. The pages they link to are published with them, as far as the next meeting.";

    /// <summary>The "ran from a menu" counts for Add Class… (Add Meeting… in a club): how, never the title.</summary>
    public static string AddClassCountsNext(ClassNoun noun = ClassNoun.Class) =>
        noun == ClassNoun.Meeting ? "the next meeting" : "the next class in this unit";
    public static string AddClassCountsNextForAMeeting() => AddClassCountsNext(ClassNoun.Meeting);

    public static string AddClassCountsAsACopy(ClassNoun noun = ClassNoun.Class) => $"as a copy of a {One(noun)}";
    public static string AddClassCountsAsACopyForAMeeting() => AddClassCountsAsACopy(ClassNoun.Meeting);

    /// <summary>The counts of the hide Deploy's question about later classes runs.</summary>
    public static string UntickedAtDeployCounts(int count, ClassNoun noun = ClassNoun.Class) =>
        (count == 1 ? $"1 {One(noun)}" : $"{count} {Many(noun)}") + " dated later, unticked at Deploy";
    public static string UntickedAtDeployCountsForAMeeting(int count) => UntickedAtDeployCounts(count, ClassNoun.Meeting);

    /// <summary>A make-room plan's problem: the remembered dates run out.</summary>
    public static string TimetableTooShortFrom(int needed, string from, int has, ClassNoun noun = ClassNoun.Class)
    {
        int missing = needed - has;
        return $"This needs {needed} {One(noun)} days from {from} onwards and the timetable only has {has}. " +
               $"Add {missing} more {One(noun)} date{(missing == 1 ? "" : "s")} and ask again.";
    }
    public static string TimetableTooShortFromForAMeeting(int needed, string from, int has) =>
        TimetableTooShortFrom(needed, from, has, ClassNoun.Meeting);

    public static string TimetableTooShortAfter(int count, string from, int has, ClassNoun noun = ClassNoun.Class)
    {
        int missing = count - has;
        return $"This needs {count} {One(noun)} day{(count == 1 ? "" : "s")} after {from} and the timetable only has " +
               $"{has}. Add {missing} more {One(noun)} date{(missing == 1 ? "" : "s")} and ask again.";
    }
    public static string TimetableTooShortAfterForAMeeting(int count, string from, int has) =>
        TimetableTooShortAfter(count, from, has, ClassNoun.Meeting);

    public static string NoDaysAfterTheLastPage(ClassNoun noun = ClassNoun.Class) =>
        $"There are not enough {One(noun)} days after the last page to move it onto. Add more {One(noun)} dates and ask again.";
    public static string NoDaysAfterTheLastPageForAMeeting() => NoDaysAfterTheLastPage(ClassNoun.Meeting);

    /// <summary>
    /// The mac's add-pages problem when unused dates run short. This app has no
    /// path that says it: its plan shares the last day instead (<c>sharingTheLastDay</c>).
    /// </summary>
    public static string UnusedDatesRunShort(int free, int undated, ClassNoun noun = ClassNoun.Class) =>
        $"Only {free} unused {One(noun)} date{(free == 1 ? "" : "s")} remain in the timetable, so the last {undated} " +
        $"can’t be dated. Add more {One(noun)} dates and ask again.";
    public static string UnusedDatesRunShortForAMeeting(int free, int undated) =>
        UnusedDatesRunShort(free, undated, ClassNoun.Meeting);

    /// <summary>A make-room plan's problem: pages not named the course's way, left where they are.</summary>
    public static string PagesNotNamedTheCoursesWay(int count, string shape, ClassNoun noun = ClassNoun.Class)
    {
        bool one = count == 1;
        return $"{count} {One(noun)} page{(one ? " is" : "s are")} not named “{shape}”, so " +
               $"{(one ? "it was" : "they were")} left where {(one ? "it is" : "they are")} — including " +
               $"{(one ? "its" : "their")} date.";
    }
    public static string PagesNotNamedTheCoursesWayForAMeeting(int count, string shape) =>
        PagesNotNamedTheCoursesWay(count, shape, ClassNoun.Meeting);

    /// <summary>The mac's one-line summaries of <c>plan_remember_timetable</c> and <c>remember_timetable</c>.</summary>
    public static string WorkedOutTheClassDates(ClassNoun noun = ClassNoun.Class) =>
        $"Worked out what recording those {One(noun)} dates would do.";
    public static string WorkedOutTheClassDatesForAMeeting() => WorkedOutTheClassDates(ClassNoun.Meeting);

    public static string RememberedTheClassDates(int count, string place, ClassNoun noun = ClassNoun.Class) =>
        $"Remembered {count} {One(noun)} {(count == 1 ? "date" : "dates")} for {place}.";
    public static string RememberedTheClassDatesForAMeeting(int count, string place) =>
        RememberedTheClassDates(count, place, ClassNoun.Meeting);
}

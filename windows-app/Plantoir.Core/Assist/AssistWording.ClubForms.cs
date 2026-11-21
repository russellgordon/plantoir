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

    // #1027 round 4: the planners' refusals, each with its club twin.

    private static string Ask(ClassNoun noun) => noun == ClassNoun.Meeting ? MayIAskForYourDatesForAMeeting : MayIAskForYourDates;

    public static string AskForAtLeastOneClass(ClassNoun noun = ClassNoun.Class) => $"Ask for at least one {One(noun)}.";
    public static string AskForAtLeastOneClassForAMeeting() => AskForAtLeastOneClass(ClassNoun.Meeting);

    public static string CannotMoveClassesWithoutDates(string code, int number, ClassNoun noun = ClassNoun.Class) =>
        $"I don’t know when {code} Section {number} meets, so I can’t move {Many(noun)} onto real " +
        $"days. Ask for the {One(noun)} dates, then record them first.";
    public static string CannotMoveClassesWithoutDatesForAMeeting(string code, int number) =>
        CannotMoveClassesWithoutDates(code, number, ClassNoun.Meeting);

    public static string CannotDateNewClassesWithoutDates(string code, int number, ClassNoun noun = ClassNoun.Class) =>
        $"I don’t know when {code} Section {number} meets, so I can’t date new {Many(noun)}. " +
        $"Ask for the {One(noun)} dates, then record them first.";
    public static string CannotDateNewClassesWithoutDatesForAMeeting(string code, int number) =>
        CannotDateNewClassesWithoutDates(code, number, ClassNoun.Meeting);

    public static string CannotDateANewClassWithoutDates(string code, int number, ClassNoun noun = ClassNoun.Class) =>
        $"I don’t know when {code} Section {number} meets, so I can’t date a new {One(noun)}. " + Ask(noun);
    public static string CannotDateANewClassWithoutDatesForAMeeting(string code, int number) =>
        CannotDateANewClassWithoutDates(code, number, ClassNoun.Meeting);

    public static string CannotReDateWithoutDates(string code, int number, ClassNoun noun = ClassNoun.Class) =>
        $"I don’t know when {code} Section {number} meets, so I can’t re-date it. " + Ask(noun);
    public static string CannotReDateWithoutDatesForAMeeting(string code, int number) =>
        CannotReDateWithoutDates(code, number, ClassNoun.Meeting);

    public static string NoNumberedClassPagesToReDate(string code, int number, ClassNoun noun = ClassNoun.Class) =>
        $"{code} Section {number} has no numbered {One(noun)} pages, so there is nothing to re-date.";
    public static string NoNumberedClassPagesToReDateForAMeeting(string code, int number) =>
        NoNumberedClassPagesToReDate(code, number, ClassNoun.Meeting);

    public static string NoClassOnThatDay(string weekday, string date, string code, int number, ClassNoun noun = ClassNoun.Class) =>
        $"I can't find a {One(noun)} on {weekday}, {date}, in {code} Section {number}. Ask me what dates you are " +
        $"teaching to see the ones I know about, or tell me the name of the {One(noun)} page you meant.";
    public static string NoClassOnThatDayForAMeeting(string weekday, string date, string code, int number) =>
        NoClassOnThatDay(weekday, date, code, number, ClassNoun.Meeting);

    public static string NoClassDateLeftForTheCopy(ClassNoun noun = ClassNoun.Class) =>
        $"There is no {One(noun)} date left for another {One(noun)}.";
    public static string NoClassDateLeftForTheCopyForAMeeting() => NoClassDateLeftForTheCopy(ClassNoun.Meeting);

    public static string WhichDayShouldTheNewClassTake(ClassNoun noun = ClassNoun.Class) => $"Which day should the new {One(noun)} take?";
    public static string WhichDayShouldTheNewClassTakeForAMeeting() => WhichDayShouldTheNewClassTake(ClassNoun.Meeting);
}

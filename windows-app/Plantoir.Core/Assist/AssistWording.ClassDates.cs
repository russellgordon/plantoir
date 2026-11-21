using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// #1027: the Class Dates dialog's own sentences (Meetings ▸ Meeting Dates… in
/// a club), each with its <c>…ForAMeeting</c> twin, word for word the mac's
/// <c>AssistWording.classDates…</c>. The dialog says them in the course's noun;
/// everything the model reads keeps the class form.
/// </summary>
public static partial class AssistWording
{
    private static string DatesNoun(ClassNoun noun) => noun == ClassNoun.Meeting ? "meeting" : "class";

    private static string DatesNouns(ClassNoun noun) => noun == ClassNoun.Meeting ? "meetings" : "classes";

    /// <summary>"a", "a and b", "a, b and c": the mac's <c>SectionTimetableStore.list</c>.</summary>
    internal static string ListedForTheDates(IReadOnlyList<string> items) => items.Count switch
    {
        0 => "nothing",
        1 => items[0],
        _ => string.Join(", ", items.Take(items.Count - 1)) + " and " + items[^1],
    };

    /// <summary>The line under the dialog's title: what giving the dates buys.</summary>
    public static string ClassDatesPurpose(ClassNoun noun = ClassNoun.Class) =>
        $"Give Plantoir the {DatesNoun(noun)} dates once, so it can date new {DatesNoun(noun)} pages for you. " +
        "They are kept inside the course folder, so they travel with it through backup, archive and restore.";
    public static string ClassDatesPurposeForAMeeting() => ClassDatesPurpose(ClassNoun.Meeting);

    /// <summary>Said in place of the sheet when its course is gone (the mac's sheet; no dialog here says it yet).</summary>
    public static string ClassDatesCourseMissing(string course, ClassNoun noun = ClassNoun.Class) =>
        $"{course} could not be found in this working folder, so there is nothing to record {DatesNoun(noun)} dates against.";
    public static string ClassDatesCourseMissingForAMeeting(string course) => ClassDatesCourseMissing(course, ClassNoun.Meeting);

    public static string ClassDatesNoneGiven(string course, string section, ClassNoun noun = ClassNoun.Class) =>
        $"No {DatesNoun(noun)} dates were given for {course} Section {section}, so there is nothing to remember.";
    public static string ClassDatesNoneGivenForAMeeting(string course, string section) =>
        ClassDatesNoneGiven(course, section, ClassNoun.Meeting);

    public static string ClassDatesNotWrittenAsDates(IReadOnlyList<string> offenders, string course, string section,
                                                     ClassNoun noun = ClassNoun.Class) =>
        $"{ListedForTheDates(offenders)} {(offenders.Count == 1 ? "isn’t a date" : "aren’t dates")} written as 2026-09-08, " +
        $"so nothing was remembered for {course} Section {section}. A half-remembered timetable would date the wrong " +
        $"{DatesNouns(noun)}, so the whole list is refused — send it again with those corrected.";
    public static string ClassDatesNotWrittenAsDatesForAMeeting(IReadOnlyList<string> offenders, string course, string section) =>
        ClassDatesNotWrittenAsDates(offenders, course, section, ClassNoun.Meeting);

    public static string ClassDatesOnFileUnreadable(IReadOnlyList<string> offenders, string course, string section,
                                                    ClassNoun noun = ClassNoun.Class) =>
        $"The remembered timetable for {course} Section {section} has {(offenders.Count == 1 ? "an entry" : "entries")} " +
        $"that cannot be read — {ListedForTheDates(offenders)}. It is being ignored rather than half-trusted. " +
        $"Record the {DatesNoun(noun)} dates again.";
    public static string ClassDatesOnFileUnreadableForAMeeting(IReadOnlyList<string> offenders, string course, string section) =>
        ClassDatesOnFileUnreadable(offenders, course, section, ClassNoun.Meeting);

    /// <summary>A list holding a date too far from today to be believed; the dialog's refusal before it writes.</summary>
    public static string ClassDatesTooFarFromToday(IReadOnlyList<string> offenders, string course, string section,
                                                   ClassNoun noun = ClassNoun.Class) =>
        $"{ListedForTheDates(offenders)} " +
        (offenders.Count == 1
            ? $"is too far from today to be a {DatesNoun(noun)} date"
            : $"are too far from today to be {DatesNoun(noun)} dates") +
        $", so nothing was remembered for {course} Section {section}. A half-remembered timetable would date the wrong " +
        $"{DatesNouns(noun)}, so the whole list is refused — send it again with " +
        $"{(offenders.Count == 1 ? "that date" : "those dates")} corrected.";
    public static string ClassDatesTooFarFromTodayForAMeeting(IReadOnlyList<string> offenders, string course, string section) =>
        ClassDatesTooFarFromToday(offenders, course, section, ClassNoun.Meeting);

    public static string ClassDatesCouldNotBeSaved(string course, string section, string reason, ClassNoun noun = ClassNoun.Class) =>
        $"The {DatesNoun(noun)} dates for {course} Section {section} could not be saved, so they are NOT remembered: {reason}";
    public static string ClassDatesCouldNotBeSavedForAMeeting(string course, string section, string reason) =>
        ClassDatesCouldNotBeSaved(course, section, reason, ClassNoun.Meeting);

    public static string ClassDatesAreRemembered(string course, string section, ClassNoun noun = ClassNoun.Class) =>
        $"The {DatesNoun(noun)} dates for {course} Section {section} are remembered.";
    public static string ClassDatesAreRememberedForAMeeting(string course, string section) =>
        ClassDatesAreRemembered(course, section, ClassNoun.Meeting);

    /// <summary>The trail line when a remembered timetable is set aside (<c>TimetableMemory.Read</c>).</summary>
    public static string ClassDatesSetAside(string date, ClassNoun noun = ClassNoun.Class) =>
        $"remembered {DatesNoun(noun)} dates set aside: they include {date}, which cannot be a {DatesNoun(noun)} date, " +
        "so they will be asked for again";
    public static string ClassDatesSetAsideForAMeeting(string date) => ClassDatesSetAside(date, ClassNoun.Meeting);

    public static string ClassDatesAlreadyRecorded(int count, string course, string section, ClassNoun noun = ClassNoun.Class) =>
        $"{course} Section {section} already has exactly these {count} {DatesNoun(noun)} dates recorded, so nothing would change.";
    public static string ClassDatesAlreadyRecordedForAMeeting(int count, string course, string section) =>
        ClassDatesAlreadyRecorded(count, course, section, ClassNoun.Meeting);

    /// <summary>The proposal's first line; the dialog's status once the dates are read.</summary>
    /// <param name="first">Written "2026-09-08 (Tuesday)".</param>
    public static string ClassDatesToRemember(int count, string course, string section, string first, string last,
                                              ClassNoun noun = ClassNoun.Class) =>
        $"Remember {count} {DatesNoun(noun)} {(count == 1 ? "date" : "dates")} for {course} Section {section}, from {first} to {last}.";
    public static string ClassDatesToRememberForAMeeting(int count, string course, string section, string first, string last) =>
        ClassDatesToRemember(count, course, section, first, last, ClassNoun.Meeting);

    /// <summary>A column read with something in it that is not a date (<c>SectionScheduleSource</c>).</summary>
    public static string ClassDatesHalfRead(IReadOnlyList<string> offenders, string source, ClassNoun noun = ClassNoun.Class) =>
        $"{ListedForTheDates(offenders)} {(offenders.Count == 1 ? "isn’t a date" : "aren’t dates")} Plantoir can read, " +
        $"so nothing was taken from {source}. A half-read timetable would date the wrong {DatesNouns(noun)}, so the whole " +
        "list is refused — fix those and try again. Dates written 2026-09-08 always work.";
    public static string ClassDatesHalfReadForAMeeting(IReadOnlyList<string> offenders, string source) =>
        ClassDatesHalfRead(offenders, source, ClassNoun.Meeting);
}

/// <summary>
/// What the Class Dates dialog (<c>SectionScheduleDialog</c>) says, chosen by
/// its course's noun (#1027), so the choice is tested without a window.
/// </summary>
public static class ClassDatesDialogWords
{
    /// <summary>The line under the title.</summary>
    public static string Purpose(Course course) => AssistWording.ClassDatesPurpose(course.Configuration.ClassNoun);

    /// <summary>Refused before writing: a date <c>TimetableMemory.Read</c> would not believe.</summary>
    public static string CannotBeADate(IReadOnlyList<DateOnly> impossible, Course course, int section) =>
        AssistWording.ClassDatesTooFarFromToday(impossible.Select(DateText.Iso).ToList(), course.Code, section.ToString(),
                                                course.Configuration.ClassNoun);

    /// <summary>The assistant's dates card, after the dialog or Not Now (#1027 review 2, low 3), in the course's noun.</summary>
    public static string CouldNotOpen(Course course) =>
        $"Could not open the {(course.Configuration.ClassNoun == ClassNoun.Meeting ? "meeting" : "class")} dates dialog.";

    public static string NoneRecorded(Course course) =>
        $"No {(course.Configuration.ClassNoun == ClassNoun.Meeting ? "meeting" : "class")} dates were recorded.";

    /// <summary>Not Now: the mac's <c>datesNotGivenYet</c>, in the course's noun.</summary>
    public static string NotGivenYet(Course course) =>
        course.Configuration.ClassNoun == ClassNoun.Meeting ? AssistWording.DatesNotGivenYetForAMeeting : AssistWording.DatesNotGivenYet;

    public static string Remembered(int count, Course course, int section) =>
        AssistWording.RememberedTheClassDates(count, $"{course.Code} Section {section}", course.Configuration.ClassNoun);

    /// <summary>The status once the dates are read: what Remember These Dates would remember.</summary>
    public static string Found(IReadOnlyList<DateOnly> dates, Course course, int section) =>
        AssistWording.ClassDatesToRemember(dates.Count, course.Code, section.ToString(),
                                           $"{DateText.Iso(dates[0])} ({dates[0].DayOfWeek})",
                                           $"{DateText.Iso(dates[^1])} ({dates[^1].DayOfWeek})",
                                           course.Configuration.ClassNoun);
}

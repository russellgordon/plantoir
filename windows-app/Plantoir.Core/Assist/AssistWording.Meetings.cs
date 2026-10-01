namespace Plantoir.Core.Assist;

/// <summary>
/// The class/meeting pairs of <c>assist-wording.json</c> (#274, mac #267).
/// </summary>
/// <remarks>
/// <para><b>The rule that matters more than the words.</b> The <c>…ForAMeeting</c>
/// form is for what a TEACHER reads in a club — a plan's card, a write's
/// one-line summary, the transcript line — and NEVER for the text the model
/// reads, nor for the text content <c>plantoir-mcp.exe</c> returns to Claude
/// Code. On this side the teacher's copy travels only in the result's
/// <c>_meta</c> (<see cref="AssistToolAnswer.TeacherSummaryKey"/>), which the
/// in-app window shows and never forwards to the model, and which Claude Code
/// does not read. Putting "meeting" into the model's copy would make a club's
/// routing unmeasured (CLAUDE.md, "The local assistant", trap 4). Pinned by
/// <c>ClubNounTests</c>: a plan rendered with the noun flipped must give a
/// byte-identical model copy.</para>
///
/// <para>Each sentence here is the contract's, word for word, with its numbers
/// handed in; <c>ContractTests.AssistWording_MatchesContract</c> renders each
/// with the generator's own example values. Refusals are NOT paired: one string
/// serves both audiences, so they keep the ordinary wording.</para>
/// </remarks>
public static partial class AssistWording
{
    private static string S(int n, string one, string many) => n == 1 ? one : many;

    /// <summary>
    /// The links-into-hidden-pages finding, said by the assistant when the
    /// checklist WILL be offered (#392, mac #379) — see
    /// <c>AssistWorkspace.AppendingFindings</c> for when.
    /// </summary>
    public static string LinksIntoHiddenPagesWillBeOffered(string course, string section) =>
        $"Some links on pages students can see lead to pages that are still hidden. Plantoir will offer to publish them when you next open {course} Section {section}.";

    public const string AddedTheNextPage = "Added the next class page.";
    public const string AddedTheNextPageForAMeeting = "Added the next meeting page.";

    public static string AllScheduledDatesHaveConcluded(int count, string course, string section, string dayName, string day) =>
        $"All {count} scheduled {S(count, "class", "classes")} for {course} Section {section} have concluded (last class was on {dayName}, {day}).";
    public static string AllScheduledDatesHaveConcludedForAMeeting(int count, string course, string section, string dayName, string day) =>
        $"All {count} scheduled {S(count, "meeting", "meetings")} for {course} Section {section} have concluded (last meeting was on {dayName}, {day}).";

    public const string DatesForTheNextPage = "Adding the next class page needs to know which days this section meets.";
    public const string DatesForTheNextPageForAMeeting = "Adding the next meeting page needs to know which days this section meets.";

    public const string DatesNotGivenYetForAMeeting =
        "Right you are. I will not be able to date new meetings until I have them — say “I have a revised list of meeting dates” whenever you would like to give them.";

    public const string DatesToDuplicate = "Duplicating a class needs to know which days this section meets, so the copy can be given a date.";
    public const string DatesToDuplicateForAMeeting = "Duplicating a meeting needs to know which days this section meets, so the copy can be given a date.";

    public const string DatesToFindADaysPage = "Finding the class taught on a given day needs to know which days this section meets.";
    public const string DatesToFindADaysPageForAMeeting = "Finding the meeting held on a given day needs to know which days this section meets.";

    public const string DatesToReDate = "Re-dating a section puts its classes onto the days it meets, so it needs those days first.";
    public const string DatesToReDateForAMeeting = "Re-dating a section puts its meetings onto the days it meets, so it needs those days first.";

    public static string DatesToReplace(string course, string section) =>
        $"Replacing the class dates on file for {course} Section {section}.";
    public static string DatesToReplaceForAMeeting(string course, string section) =>
        $"Replacing the meeting dates on file for {course} Section {section}.";

    public const string EveryDateIsSpokenForForAMeeting =
        "Every recorded date is spoken for, so another meeting cannot be dated until more dates are recorded.";

    public static string LinkedClassStaysVisibleForAMeeting(string page) =>
        $"“{page}” stays visible, because it is a meeting of its own.";

    public static string LinkedClassWasLeftAloneForAMeeting(IReadOnlyList<string> classes) =>
        $"{PublishPlan.Listing(classes)} is a meeting of its own, so it stays as it is — publish it when you get to that meeting.";

    public static string LinkedClassesWereLeftAloneForAMeeting(IReadOnlyList<string> classes) =>
        $"{PublishPlan.Listing(classes)} are meetings of their own, so they stay as they are — publish each one when you get to it.";

    /// <param name="position">The position named the way the course names a page (<c>InsertPlan.PositionTitle</c>).</param>
    public static string MadeRoom(int added, string position) =>
        $"Made room for {added} {S(added, "class", "classes")} at {position}.";
    public static string MadeRoomForAMeeting(int added, string position) =>
        $"Made room for {added} {S(added, "meeting", "meetings")} at {position}.";

    public const string MakingRoomCannotBeUndoneForAMeeting =
        "Because other meetings move, “Undo that” will not take this back afterwards — the copy made before any of it is in Plantoir's Backups list.";

    public const string MayIAskForYourDatesForAMeeting = "May I ask you for your meeting dates?";

    public static string MovedToLaterDaysForAMeeting(int moved) => $"Moved to later meeting days — {moved}:";

    public static string MovesAndBecomesADraftForAMeeting(string page, string day) =>
        $"“{page}” moves to {day} and becomes a draft because it has no meeting date.";

    public static string MovesToTheFirstDay(string page, string day) =>
        $"“{page}” moves to {day}, the first day of class, because Key Links points at it.";
    public static string MovesToTheFirstDayForAMeeting(string page, string day) =>
        $"“{page}” moves to {day}, the first meeting day, because Key Links points at it.";

    public static string PagesAcrossTheDates(string course, string section, int pages, int dates, int spare) =>
        $"{course} Section {section} has {pages} class {S(pages, "page", "pages")} across {dates} recorded dates ({spare} spare).";
    public static string PagesAcrossTheDatesForAMeeting(string course, string section, int pages, int dates, int spare) =>
        $"{course} Section {section} has {pages} meeting {S(pages, "page", "pages")} across {dates} recorded dates ({spare} spare).";

    public static string PagesRunFrom(int count, string from, string fromDay, string to, string toDay) =>
        $"{count} {S(count, "class", "classes")} run from {from} ({fromDay}) to {to} ({toDay}).";
    public static string PagesRunFromForAMeeting(int count, string from, string fromDay, string to, string toDay) =>
        $"{count} {S(count, "meeting", "meetings")} run from {from} ({fromDay}) to {to} ({toDay}).";

    public static string PagesWithNoDayOfTheirOwn(int count, string day) =>
        $"{count} {S(count, "class has", "classes have")} no day of {S(count, "its", "their")} own this year, so {S(count, "it goes", "they all go")} on {day} with the last one as {S(count, "a draft", "drafts")}. Move, publish or delete {S(count, "it", "them")} when you have decided what to do.";
    public static string PagesWithNoDayOfTheirOwnForAMeeting(int count, string day) =>
        $"{count} {S(count, "meeting has", "meetings have")} no day of {S(count, "its", "their")} own this year, so {S(count, "it goes", "they all go")} on {day} with the last one as {S(count, "a draft", "drafts")}. Move, publish or delete {S(count, "it", "them")} when you have decided what to do.";

    public static string PublishedTheClassOnForAMeeting(string day) => $"Published the meeting on {day}.";

    public static string ReDatedForAMeeting(int meetings, int pages) =>
        $"Re-dated {meetings} {S(meetings, "meeting", "meetings")} and {pages} {S(pages, "page", "pages")} they use.";

    public static string ReDatedOnlyPagesTheyUseForAMeeting(int pages) =>
        $"Every meeting was already on its day, so only the {pages} {S(pages, "page", "pages")} they use " +
        $"{S(pages, "was", "were")} re-dated.";

    public static string ReDatingOntoTheDatesOnFileForAMeeting(string course, string section) =>
        $"{course} Section {section}: re-dating onto the meeting dates on file.";

    public const string SharingTheLastDay =
        "This one has no class date left, so it shares the last day with the class already on it. Give it a day of your own when you know what they are.";
    public const string SharingTheLastDayForAMeeting =
        "This one has no meeting date left, so it shares the last day with the meeting already on it. Give it a day of your own when you know what they are.";

    /// <param name="source">Where the timetable was recorded from, or empty.</param>
    public static string SpareDatesAfterThese(int spare, string source) =>
        $"{spare} more class {S(spare, "date is", "dates are")} spare after these{(source.Length == 0 ? "" : ", out of the timetable recorded from " + source)}.";
    public static string SpareDatesAfterTheseForAMeeting(int spare, string source) =>
        $"{spare} more meeting {S(spare, "date is", "dates are")} spare after these{(source.Length == 0 ? "" : ", out of the timetable recorded from " + source)}.";

    public static string TheNextWouldFallOnForAMeeting(string day, string dayName) =>
        $"The next meeting would fall on {day} ({dayName}).";

    public static string TheSemesterBegins(string dayName, string day, int count) =>
        $"The semester begins on {dayName}, {day}. The first {count} {S(count, "class is", "classes are")}:";
    public static string TheSemesterBeginsForAMeeting(string dayName, string day, int count) =>
        $"The semester begins on {dayName}, {day}. The first {count} {S(count, "meeting is", "meetings are")}:";

    /// <param name="unitName">"Unit 4" — the course's own word.</param>
    public static string WouldAddPages(int count, string unitName, string course, string section) =>
        $"Add {count} class {S(count, "page", "pages")} to {unitName} of {course} Section {section}, on the {S(count, "day", "days")} this class actually meets:";
    /// <summary>No unit: a numbered course has none.</summary>
    public static string WouldAddPagesForAMeeting(int count, string course, string section) =>
        $"Add {count} meeting {S(count, "page", "pages")} to {course} Section {section}, on the {S(count, "day", "days")} this group actually meets:";

    public static string WouldMakeRoom(int count, string position, string course, string section) =>
        $"Make room for {(count == 1 ? "one new class" : $"{count} new classes")} at {position} in {course} Section {section}.";
    public static string WouldMakeRoomForAMeeting(int count, string position, string course, string section) =>
        $"Make room for {(count == 1 ? "one new meeting" : $"{count} new meetings")} at {position} in {course} Section {section}.";

    public static string YourNextUpcoming(int count, string course, string section) =>
        $"Your next {count} upcoming {S(count, "class", "classes")} for {course} Section {section}:";
    public static string YourNextUpcomingForAMeeting(int count, string course, string section) =>
        $"Your next {count} upcoming {S(count, "meeting", "meetings")} for {course} Section {section}:";
}

public static partial class ClassChangeWording
{
    public static string OtherClassesWouldMoveAndLinksFollowForAMeeting(int moving) =>
        $"{moving} later {(moving == 1 ? "meeting moves" : "meetings move")} one along to make room, and the links that point at them are rewritten to match.";

    public static string OtherClassesWouldMoveKeepingTheirNamesForAMeeting(int moving) =>
        $"{moving} later {(moving == 1 ? "meeting moves" : "meetings move")} onto a later meeting day to make room. {(moving == 1 ? "Its name does" : "Their names do")} not change.";

    /// <summary>The teacher's half of <see cref="OtherClassesWouldMove"/> in a club.</summary>
    public static string OtherClassesWouldMoveForAMeeting(int moving, int renaming) => renaming > 0
        ? OtherClassesWouldMoveAndLinksFollowForAMeeting(moving)
        : OtherClassesWouldMoveKeepingTheirNamesForAMeeting(moving);
}

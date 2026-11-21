using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Classes ▸ Add Class…'s sentences (#927, the mac's #897 piece A): the
/// dialog's title, its question, one line per way, the lines under the ways
/// that say why a way is greyed, and the copy's answers. The mac's
/// <c>AssistWording.menuAddClass…</c>, word for word; each key of
/// <c>contracts/assist-wording.json</c> has a member of its own name here
/// (<c>ContractTests.AssistWording_MatchesContract</c>), and the members
/// that take a noun or a word are what the dialog calls.
/// </summary>
public static partial class AssistWording
{

    // ---- The dialog's title and question -----------------------------------------

    public static string MenuAddClassTitle(string course, string section) => AddClassWords.Title(course, section, ClassNoun.Class);
    public static string MenuAddClassTitleForAMeeting(string course, string section) => AddClassWords.Title(course, section, ClassNoun.Meeting);

    public static string MenuHowToAddAClass => AddClassWords.HowToAdd(ClassNoun.Class);
    public static string MenuHowToAddAClassForAMeeting => AddClassWords.HowToAdd(ClassNoun.Meeting);

    // ---- One line per way ------------------------------------------------------

    /// <summary>
    /// The first way, what Add Next Class did, in the course's own word as a
    /// sentence says it ("module"); a numbered course (a club) has no units,
    /// and its line says only "the next".
    /// </summary>
    public static string MenuAddClassNextInThisUnit => AddClassWords.NextInThisUnit(ClassNoun.Class, "unit", false);
    public static string MenuAddClassNextInThisUnitForAMeeting => AddClassWords.NextInThisUnit(ClassNoun.Meeting, "unit", false);
    public static string MenuAddClassNextInThisUnitInAModuleCourse => AddClassWords.NextInThisUnit(ClassNoun.Class, "module", false);
    public static string MenuAddClassNextInANumberedCourse => AddClassWords.NextInThisUnit(ClassNoun.Class, "unit", true);
    public static string MenuAddClassNextInANumberedCourseForAMeeting => AddClassWords.NextInThisUnit(ClassNoun.Meeting, "unit", true);

    /// <summary>The second way: Unit 5, Day 1 after Unit 4, in the course's word.</summary>
    public static string MenuAddClassInANewUnit => AddClassWords.InANewUnit(ClassNoun.Class, "unit");
    public static string MenuAddClassInANewUnitForAMeeting => AddClassWords.InANewUnit(ClassNoun.Meeting, "unit");
    public static string MenuAddClassInANewUnitInAModuleCourse => AddClassWords.InANewUnit(ClassNoun.Class, "module");

    /// <summary>The third way: a copy of one of this section's classes.</summary>
    public static string MenuAddClassAsACopy => AddClassWords.AsACopy(ClassNoun.Class);
    public static string MenuAddClassAsACopyForAMeeting => AddClassWords.AsACopy(ClassNoun.Meeting);

    // ---- Why a way is greyed -----------------------------------------------------

    public static string MenuAddClassGreyedNoUnits => AddClassWords.GreyedNoUnits(ClassNoun.Class);
    public static string MenuAddClassGreyedNoUnitsForAMeeting => AddClassWords.GreyedNoUnits(ClassNoun.Meeting);

    public static string MenuAddClassGreyedNothingToCopy => AddClassWords.GreyedNothingToCopy(ClassNoun.Class);
    public static string MenuAddClassGreyedNothingToCopyForAMeeting => AddClassWords.GreyedNothingToCopy(ClassNoun.Meeting);

    /// <summary>
    /// The rename's line, naming only the ways the rename holds back. In a
    /// numbered course the word renamed is the pages' own name, and only a
    /// copy can be held back there.
    /// </summary>
    public static string MenuAddClassGreyedRenameUnfinished => AddClassWords.GreyedRenameUnfinished(ClassNoun.Class, "unit", true, true, false);
    public static string MenuAddClassGreyedRenameUnfinishedForAMeeting => AddClassWords.GreyedRenameUnfinished(ClassNoun.Meeting, "unit", true, true, false);
    public static string MenuAddClassGreyedRenameHoldsANewUnit => AddClassWords.GreyedRenameUnfinished(ClassNoun.Class, "unit", true, false, false);
    public static string MenuAddClassGreyedRenameHoldsACopyInANumberedCourse => AddClassWords.GreyedRenameUnfinished(ClassNoun.Class, "unit", false, true, true);
    public static string MenuAddClassGreyedRenameHoldsACopyInANumberedCourseForAMeeting => AddClassWords.GreyedRenameUnfinished(ClassNoun.Meeting, "unit", false, true, true);

    // ---- The copy ------------------------------------------------------------------

    public static string MenuPickClassToDuplicate => AddClassWords.PickClassToDuplicate(ClassNoun.Class);
    public static string MenuPickClassToDuplicateForAMeeting => AddClassWords.PickClassToDuplicate(ClassNoun.Meeting);

    /// <summary>The default button for a way that adds at once.</summary>
    public const string MenuAddButton = "Add";

    public const string MenuDuplicateButton = "Duplicate";

    /// <summary>
    /// A copy asked for after the section's class dates went missing. A club
    /// is pointed at the menu by the title its menu bar gives it (Meetings,
    /// #990), without Class Dates…'s own title, which says "class".
    /// </summary>
    public static string MenuNeedsClassDatesFirst => AddClassWords.NeedsClassDatesFirst(ClassNoun.Class);
    public static string MenuNeedsClassDatesFirstForAMeeting => AddClassWords.NeedsClassDatesFirst(ClassNoun.Meeting);

    /// <summary>The finished dialog: the copy's name, its date, and that it is hidden.</summary>
    public static string DuplicatedFromTheMenu(string page, string copy, string date) =>
        $"Duplicated “{page}” as “{copy}”, dated {date}. The copy is hidden: write it, then publish it when it is ready.";

    /// <summary>The copy could not be read back as hidden, so nothing was written.</summary>
    public static string TheCopyCouldNotBeMadeHiddenFromTheMenu(string page) =>
        $"“{page}” was not copied, and nothing was written: the copy could not be made certainly hidden, and a lesson " +
        $"students can already see must not turn up somewhere new where they can read it. The settings at the top of " +
        $"“{page}” are written in a way Plantoir cannot read for certain; open it in Obsidian to look.";

    /// <summary>The page the copy would become is already there; it is never written over.</summary>
    public static string MenuTheNextPageIsAlreadyThere(string page) =>
        $"A page called “{page}” is already where the copy would go, so nothing was copied. A page is never written over.";

    /// <summary>A unit-word rename stopped part way: a new unit and a copy wait for it, in every course.</summary>
    public static string MenuUnitWordRenameUnfinished => AddClassWords.UnitWordRenameUnfinished(ClassNoun.Class);
    public static string MenuUnitWordRenameUnfinishedForAMeeting => AddClassWords.UnitWordRenameUnfinished(ClassNoun.Meeting);
}

/// <summary>
/// Add Class…'s sentences with the course's noun and word filled in, as the
/// dialog and the server say them (<see cref="AssistWording"/> carries one
/// member per contract key, each one of these with the contract's example).
/// </summary>
public static class AddClassWords
{
    private static string Singular(ClassNoun noun) => noun == ClassNoun.Meeting ? "meeting" : "class";

    private static string Plural(ClassNoun noun) => noun == ClassNoun.Meeting ? "meetings" : "classes";

    public static string Title(string course, string section, ClassNoun noun) =>
        $"Add a {Singular(noun)} to {course} Section {section}";

    public static string HowToAdd(ClassNoun noun) =>
        $"How should the new {Singular(noun)} be added? It is dated for this section's next {Singular(noun)} day and starts hidden.";

    public static string NextInThisUnit(ClassNoun noun, string unit, bool numbered) => numbered
        ? $"As the next {Singular(noun)}"
        : $"As the next {Singular(noun)} in the {unit} under way";

    public static string InANewUnit(ClassNoun noun, string unit) => $"In a new {unit}, as its first {Singular(noun)}";

    public static string AsACopy(ClassNoun noun) => $"As a copy of a {Singular(noun)} in this section";

    public static string GreyedNoUnits(ClassNoun noun) =>
        $"This course numbers its {Plural(noun)} one after another, without units, so there is no new unit to start.";

    public static string GreyedNothingToCopy(ClassNoun noun) =>
        $"This section has no {Singular(noun)} pages yet, so there is nothing to copy.";

    public static string GreyedRenameUnfinished(ClassNoun noun, string unit, bool newUnit, bool copy, bool numbered)
    {
        string what = newUnit && copy ? $"a new {unit} or a copy" : newUnit ? $"a new {unit}" : "a copy";
        return numbered
            ? $"A rename of what this course calls its {Plural(noun)} stopped part way, so some are named the old way and some the new. Finish the rename in the course's settings to add {what}."
            : $"A rename of what this course calls a {unit} stopped part way, so some {Plural(noun)} are named the old way. Finish the rename in the course's settings to add {what}.";
    }

    public static string PickClassToDuplicate(ClassNoun noun) =>
        $"Choose the {Singular(noun)} to copy. The copy becomes the next {Singular(noun)}, dated for this section's next {Singular(noun)} day, and starts hidden. Nothing else moves.";

    /// <summary>
    /// The item named where the menu bar has it: Classes ▸ Class Dates…, or
    /// Meetings ▸ Meeting Dates… in a club (#1027), from the layout.
    /// </summary>
    public static string NeedsClassDatesFirst(ClassNoun noun)
    {
        var item = SubjectMenuRules.Item.ClassDates;
        string path = SubjectMenuLayout.Path(item, SubjectMenuLayout.TitleSayingTheNoun(item, noun)!, noun);
        return $"This section has no {Singular(noun)} dates on file, so nothing was copied. Add them with {path}, then try again.";
    }

    public static string UnitWordRenameUnfinished(ClassNoun noun) =>
        $"A rename of the names this course gives its {Plural(noun)} stopped part way, so some are named the old way and " +
        "some the new. Nothing was changed. Finish the rename in the course's settings, then choose this again.";

    /// <summary>The line a way is drawn with, the course's noun and word filled in.</summary>
    public static string Label(SubjectMenuRules.AddClassLabel label, ClassNoun noun, string unit) => label switch
    {
        SubjectMenuRules.AddClassLabel.NextInTheUnitUnderWay => NextInThisUnit(noun, unit, numbered: false),
        SubjectMenuRules.AddClassLabel.NextInANumberedCourse => NextInThisUnit(noun, unit, numbered: true),
        SubjectMenuRules.AddClassLabel.InANewUnitInTheCoursesWord => InANewUnit(noun, unit),
        SubjectMenuRules.AddClassLabel.InANewUnitPlainly => InANewUnit(noun, "unit"),
        _ => AsACopy(noun),
    };

    /// <summary>A line under the ways, the course's noun and word filled in.</summary>
    public static string Reason(SubjectMenuRules.AddClassReasonLine line, ClassNoun noun, string unit) => line switch
    {
        SubjectMenuRules.AddClassReasonLine.TheCourseHasNoUnits => GreyedNoUnits(noun),
        SubjectMenuRules.AddClassReasonLine.ThereIsNoClassToCopy => GreyedNothingToCopy(noun),
        SubjectMenuRules.AddClassReasonLine.ARenameHoldsBackANewUnitAndACopy => GreyedRenameUnfinished(noun, unit, newUnit: true, copy: true, numbered: false),
        SubjectMenuRules.AddClassReasonLine.ARenameHoldsBackANewUnit => GreyedRenameUnfinished(noun, unit, newUnit: true, copy: false, numbered: false),
        _ => GreyedRenameUnfinished(noun, unit, newUnit: false, copy: true, numbered: true),
    };

}

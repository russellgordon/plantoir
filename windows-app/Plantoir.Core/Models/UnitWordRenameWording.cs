namespace Plantoir.Core.Models;

/// <summary>
/// What the Rename… sheet for a course's word for a unit says — every
/// sentence from <c>shared-rules.json → specialNames.renameUnitWord</c>, word
/// for word (the mac's <c>UnitWordRenameWording</c>), except
/// <see cref="Explanation"/>, which says "on this PC" where the mac says "on
/// your Mac" (<c>specialNames.platformWording.keys</c>). Pinned by
/// <c>UnitWordRenameContractTests</c>.
/// </summary>
public static class UnitWordRenameWording
{
    public const string FieldLabel = "What do you call a unit?";
    public const string RenameButton = "Rename…";
    public static string SheetTitle(string word) => $"Rename “{word}”";
    public static string RowCaption(string word) => $"Class pages are named “{word} 1, Day 1”.";

    /// <summary>The row's caption in a NUMBERED course (#274): the one-number shape, never "Day".</summary>
    public static string RowCaptionNumbered(string word) => $"Class pages are named “{word} 1”, “{word} 2” and so on.";

    /// <summary>
    /// Under the DISABLED Rename… in a numbered course (#274): a club's word,
    /// folder, heading and noun are one choice made in the wizard.
    /// </summary>
    public const string RenameLockedNumbered =
        "This course numbers its pages one after another, so its word was chosen when the course was made and cannot be renamed here.";

    public const string Explanation =
        "This renames every class page on this PC, in every section, and points your pages’ links at the new names. " +
        "It happens straight away, so Cancel in Settings will not undo it. To change it back, rename it again; " +
        "a backup of the whole course is saved first, as a last resort.";

    public const string ProseIsLeftAlone =
        "Pages and sentences that mention a unit by number, other than the class pages themselves, are left as they are.";

    public const string LookingOver = "Looking over the course’s pages…";

    // ---- Refusals

    public const string ProblemEmpty = "Type the word this course uses for a unit.";
    public const string ProblemUnchanged = "That is already this course’s word.";

    public static string ProblemMustFinishFirst(string target) =>
        $"Plantoir is part way through renaming to “{target}”. Finish that first — press Rename with “{target}” — and then rename again.";

    public static string ProblemPageInTheWay(string code, int section, string name) =>
        $"{code} Section {section} already has a page called “{name}”, so the pages cannot be renamed. Move or rename that page first.";

    public static string ProblemPageUnreadable(string code, int section, string name) =>
        $"“{name}” in {code} Section {section} could not be read, so nothing was renamed. If the course is kept in iCloud Drive, wait for it to finish downloading and try again.";

    public static string ProblemRecordNotWritten(string reason) =>
        $"Plantoir could not write its note of the rename under way ({reason}), so nothing was renamed. Check that the working folder can be written to, then try again.";

    public static string ProblemBusy(string code) =>
        $"{code} is previewing or deploying right now. Stop that first, then rename.";

    // ---- The plan, shown before Rename

    public static string Pages(int pages, IReadOnlyList<int> sections, string code, string oldWord, string newWord) => pages switch
    {
        0 => $"No class page in {code} is named “{oldWord} N, Day N”, so only this course’s settings would change: new class pages will be named “{newWord} 1, Day 1” and so on.",
        1 => $"One class page, in {SectionsPhrase(sections)}, would be renamed — “{oldWord} 1, Day 1” becomes “{newWord} 1, Day 1”, and so on.",
        _ => $"{pages} class pages in {SectionsPhrase(sections)} would be renamed — “{oldWord} 1, Day 1” becomes “{newWord} 1, Day 1”, and so on.",
    };

    public static string Links(int count) => count switch
    {
        0 => "No links point at those names, so nothing else needs changing.",
        1 => "One link points at those names and would be updated to match.",
        _ => $"{count} links point at those names and would be updated to match.",
    };

    /// <summary>“Section 1”, “Sections 1 and 3”, “Sections 1, 2 and 4”.</summary>
    public static string SectionsPhrase(IReadOnlyList<int> sections) => sections.Count switch
    {
        0 => "no section",
        1 => $"Section {sections[0]}",
        _ => $"Sections {string.Join(", ", sections.Take(sections.Count - 1))} and {sections[^1]}",
    };

    // ---- Done

    public static string Done(string oldWord, string newWord, UnitWordRenameOutcome outcome)
    {
        var parts = new List<string> { $"“{oldWord}” is now “{newWord}”." };
        parts.Add(outcome.PagesRenamed switch
        {
            0 => "No class page needed renaming, so only this course’s settings changed.",
            1 => "One class page was renamed.",
            _ => $"{outcome.PagesRenamed} class pages were renamed.",
        });
        if (outcome.PagesRenamed > 0 || outcome.LinksRewritten > 0 || outcome.PagesNotWritten > 0)
        {
            parts.Add(outcome.LinksRewritten switch
            {
                0 => "No links needed updating.",
                1 => "One link was updated to match.",
                _ => $"{outcome.LinksRewritten} links were updated to match.",
            });
            if (outcome.PagesNotWritten == 1) parts.Add("One page could not be written, so its links still use the old names.");
            else if (outcome.PagesNotWritten > 1) parts.Add($"{outcome.PagesNotWritten} pages could not be written, so their links still use the old names.");
            parts.Add(DonePublish);
        }
        parts.Add(DoneBackup);
        return string.Join(" ", parts);
    }

    public const string DonePublish = "Deploy each section for its website to use the new names.";
    public const string DoneBackup = "A backup of the whole course was saved first, and is listed under Backups.";

    public static string InterruptedRename(string oldWord, string newWord) =>
        $"Plantoir started renaming “{oldWord}” to “{newWord}” and did not finish — some class pages have the new word, and this course’s settings still use the old one. Press Rename to finish.";

    public static string HalfDone(int renamed, int total, string name, string reason) =>
        $"Plantoir renamed {renamed} of {total} class pages and then could not rename “{name}”: {reason}. Press Rename to finish the rest.";

    public static string SettingsNotWritten(string newWord, string reason) =>
        $"Every class page now says “{newWord}”, but Plantoir could not write the change to this course’s settings: {reason}. Press Rename to finish.";
}

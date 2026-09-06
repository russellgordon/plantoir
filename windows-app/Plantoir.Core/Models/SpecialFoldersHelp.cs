using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// One row of the "Folders Plantoir uses" sheet.
/// </summary>
/// <param name="Name">What the folder or file is called in THIS course.</param>
/// <param name="What">What it is for, in four or five words.</param>
/// <param name="Why">What happens if it is renamed, moved or written over.</param>
public readonly record struct SpecialFolderEntry(string Name, string What, string Why);

/// <summary>
/// What Plantoir does with particular folders in THIS course — the answer to
/// "What else does Plantoir use my folders for?" in Course Settings.
///
/// <para><b>It names the folders this course actually has, never the rule that
/// finds them.</b> Saying "any folder whose name mentions the curriculum"
/// invites a teacher to get creative with it, and turns an implementation
/// detail into a promise the product then has to keep. Saying "your
/// expectations live in Ontario Curriculum" tells them the thing they can act
/// on. It is also why the sheet is per-COURSE rather than one static help
/// page: the answers genuinely differ. One course grades "Tasks", another
/// "Tests" and "Thinking Tasks"; one calls its class folder "All Classes",
/// another "Lessons".</para>
///
/// <para>The rules and the sentences are
/// <c>contracts/shared-rules.json</c> → <c>specialFoldersHelp</c>, run by
/// <c>SpecialFoldersHelpContractTests</c>. This type is deliberately pure and
/// lives in Core rather than beside the dialog: the wording is the part that
/// must match the mac, and a rule buried in a XAML code-behind cannot be
/// tested against the contract.</para>
///
/// <para><b>Every name comes from the course's own resolved rules</b>
/// (<see cref="ClassFolderRule"/>, <see cref="CourseConfiguration.ResolvedCurriculumFolder"/>,
/// <see cref="CourseConfiguration.MaterializedGradedFolders"/>) rather than
/// from the raw configuration keys. That matters most for the curriculum
/// folder: a course whose <c>curriculum_folder</c> key was never written still
/// HAS a curriculum folder as far as the build is concerned, and telling that
/// teacher to go and create one they already have is the one failure a sheet
/// about folder names cannot afford.</para>
/// </summary>
public static class SpecialFoldersHelp
{
    /// <summary>The sheet's title. Shared wording — see the contract.</summary>
    public const string Title = "Folders Plantoir uses";

    /// <summary>The sentence under the title.</summary>
    public const string Intro =
        "Renaming or deleting one of these changes what appears on your site. "
        + "Everything else in your course is yours to arrange however you like.";

    /// <summary>What the curriculum row says when the course has no curriculum
    /// folder at all — the single row allowed to describe rather than name,
    /// and only in that case.</summary>
    public const string NoCurriculumFolderYet = "Your curriculum folder";

    /// <summary>What a list of names reads as when there are none.</summary>
    public const string NoneChosen = "None chosen";

    /// <summary>
    /// One row per thing a teacher can break by renaming it in Obsidian, in
    /// the order the contract fixes. No row is ever omitted: the curriculum
    /// row falls back to <see cref="NoCurriculumFolderYet"/> rather than
    /// disappearing, because a course with no curriculum folder is exactly
    /// the course whose coverage map is missing.
    /// </summary>
    public static IReadOnlyList<SpecialFolderEntry> Entries(CourseConfiguration config)
    {
        ArgumentNullException.ThrowIfNull(config);

        var rows = new List<SpecialFolderEntry>
        {
            new(Listed(ClassFolderRule.Names(config.ClassFolder, config.PerSectionFolders)),
                "Your lessons",
                "Each day's class page lives here. Plantoir puts new classes in this "
                + "folder, keeps them in date order, and uses them to work out which "
                + "pages your course actually teaches."),

            new(config.ResolvedCurriculumFolder is { Length: > 0 } curriculum
                    ? curriculum
                    : NoCurriculumFolderYet,
                "Your curriculum expectations",
                "One page per expectation. The curriculum map is built from these — "
                + "without them there is nothing to measure your lessons against, and "
                + "the map is left out."),

            new(Listed(config.MaterializedGradedFolders()),
                "Work that counts for marks",
                "The curriculum map shows an expectation as evaluated when a page in "
                + "one of these addresses it. You choose these above."),

            new("Media",
                "Images and files you add to pages",
                "Plantoir looks after this one itself and keeps it out of your sidebar. "
                + "If it goes missing, pictures stop appearing on your site."),

            new("index.md",
                "The page a folder opens on",
                "Every section has one, and so does each folder. It is the way in, "
                + "not a lesson."),

            new("Key Links.md",
                "The shortcuts in your sidebar",
                "Plantoir adds the curriculum map to this list when it builds your "
                + "site. Your own copy is left exactly as you wrote it."),

            new("Curriculum Coverage",
                "Written for you, every time you build",
                "Do not write your own page with this name — it is replaced each time, "
                + "so anything you put there would be lost."),
        };

        return rows;
    }

    /// <summary>
    /// Several folder names, said the way a person would say them: "A",
    /// "A and B", "A, B and C". A bracketed comma-separated list is a data
    /// structure showing through, and these are read aloud in a teacher's
    /// head.
    /// </summary>
    public static string Listed(IEnumerable<string>? names)
    {
        var kept = (names ?? Enumerable.Empty<string>())
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .ToList();

        if (kept.Count == 0) return NoneChosen;
        if (kept.Count == 1) return kept[0];
        return string.Join(", ", kept.Take(kept.Count - 1)) + " and " + kept[^1];
    }
}

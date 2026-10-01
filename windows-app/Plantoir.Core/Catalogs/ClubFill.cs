using Plantoir.Core.Models;

namespace Plantoir.Core.Catalogs;

/// <summary>The words a club uses, or a course (#274, mac <c>ClubVocabulary</c>).</summary>
public sealed record ClubVocabulary(string ClassFolder, string UnitWord, string FrontPageHeading, ClassNoun Noun)
{
    /// <summary>A club's words — <c>shared-rules.json</c> → <c>wizard.clubToggle.club</c>.</summary>
    public static ClubVocabulary Club { get; } = new("All Meetings", "Week", "Most Recent Meeting", ClassNoun.Meeting);

    /// <summary>A course's words — what every course made before #267 says.</summary>
    public static ClubVocabulary Course { get; } = new("All Classes", ClassPageTerm.DefaultWord, "Most Recent Class", ClassNoun.Class);
}

/// <summary>What the wizard's fields hold, as far as the club choice touches them.</summary>
public sealed record ClubFillFields(
    IReadOnlyList<string> SharedFolders,
    IReadOnlyList<string> PerSectionFolders,
    string ClassFolder,
    string UnitWord,
    string FrontPageHeading,
    ClassNoun Noun);

/// <summary>
/// Turning "This is a club" on or off, as a pure function (#274, mac
/// <c>ClubFill.applying</c>; <c>wizard.clubToggle.fillRule</c> and its cases).
/// </summary>
/// <remarks>
/// <para><b>A field moves only while it still holds the value the OTHER choice
/// would have put there.</b> A teacher who typed "All Gatherings" and ticks the
/// box off and on keeps it; a field nobody touched follows the box. A switch
/// that quietly undid typing would be a switch nobody trusted.</para>
///
/// <para>A club has no curriculum (Russell, 2026-09-24), so ticking takes every
/// curriculum folder out of the shared folders and unticking puts the
/// terminology's factory one back at its factory place. The class folder keeps
/// its PLACE in the per-section list and the recorded name follows it.</para>
/// </remarks>
public static class ClubFill
{
    /// <summary>Every name a curriculum folder is given by the defaults and skeletons.</summary>
    public static readonly IReadOnlyList<string> CurriculumFolders = new[]
    {
        "Ontario Curriculum", "College Board Curriculum", "Curriculum",
    };

    public static ClubFillFields Applying(bool isClub, ClubFillFields fields, bool usesLcsTerminology)
    {
        var leaving = isClub ? ClubVocabulary.Course : ClubVocabulary.Club;
        var arriving = isClub ? ClubVocabulary.Club : ClubVocabulary.Course;

        var perSection = fields.PerSectionFolders.ToList();
        string classFolder = fields.ClassFolder;
        if (fields.ClassFolder == leaving.ClassFolder)
        {
            int at = perSection.IndexOf(leaving.ClassFolder);
            if (at >= 0) perSection[at] = arriving.ClassFolder;
            else if (!perSection.Contains(arriving.ClassFolder)) perSection.Insert(0, arriving.ClassFolder);
            classFolder = arriving.ClassFolder;
        }

        return new ClubFillFields(
            isClub
                ? fields.SharedFolders.Where(folder => !CurriculumFolders.Contains(folder)).ToList()
                : PuttingTheCurriculumFoldersBack(fields.SharedFolders, usesLcsTerminology),
            perSection,
            classFolder,
            fields.UnitWord == leaving.UnitWord ? arriving.UnitWord : fields.UnitWord,
            fields.FrontPageHeading == leaving.FrontPageHeading ? arriving.FrontPageHeading : fields.FrontPageHeading,
            fields.Noun == leaving.Noun ? arriving.Noun : fields.Noun);
    }

    private static List<string> PuttingTheCurriculumFoldersBack(IReadOnlyList<string> folders, bool usesLcsTerminology)
    {
        var factory = usesLcsTerminology ? WizardDefaults.LcsSharedFolders : WizardDefaults.SharedFolders;
        var result = folders.ToList();
        for (int index = 0; index < factory.Count; index++)
        {
            string name = factory[index];
            if (!CurriculumFolders.Contains(name) || result.Contains(name)) continue;
            result.Insert(Math.Min(index, result.Count), name);
        }
        return result;
    }

    /// <summary>
    /// The keys a CLUB writes into <c>course_config.json</c> beyond an ordinary
    /// course's — only for a club; every other course's file stays byte for
    /// byte what it was, which absence already describes.
    /// </summary>
    public static IReadOnlyDictionary<string, string> ClubKeys(string frontPageHeading, ClassNoun noun) =>
        new Dictionary<string, string>
        {
            ["class_page_scheme"] = ClassPageSchemes.NumberedValue,
            ["front_page_heading"] = frontPageHeading.Trim().Length == 0 ? ClubVocabulary.Club.FrontPageHeading : frontPageHeading.Trim(),
            ["class_noun"] = noun == ClassNoun.Meeting ? "meeting" : "class",
        };
}

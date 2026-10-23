using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

public static class CurriculumRules
{
    /// <summary>
    /// Three shapes since #345 (mac #128): <c>A1.1</c> (an Ontario or BC
    /// expectation, either case), <c>1.A</c> (a College Board skill: digits, a
    /// dot, ONE letter) and <c>CRD-1.A</c> (a learning objective: 2–4
    /// capitals, a hyphen, digits, a dot, one capital). Whole name. Rejected,
    /// so not re-proposed: <c>1.A.1</c> / <c>CRD-1.A.1</c>, never measured on a
    /// real course.
    /// </summary>
    private static readonly Regex ExpectationCodeRegex =
        new(@"^(?:[A-Za-z]\d+\.\d+|\d+\.[A-Za-z]|[A-Z]{2,4}-\d+\.[A-Z])$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    /// <summary>The shape every expectation had before #128: a letter, digits, a dot, digits.</summary>
    private static readonly Regex LetterFirstCodeRegex = new(@"^[A-Za-z]\d+\.\d+$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    /// <summary>A letter-first code (<c>A1.1</c>) — the shape the fallback scan prefers.</summary>
    public static bool IsLetterFirstCode(string code) =>
        !string.IsNullOrWhiteSpace(code) && LetterFirstCodeRegex.IsMatch(code.Trim());

    /// <summary>
    /// The coverage maps' titles, one per mapped folder in order
    /// (<c>curriculumRules.coveragePageTitles</c>): the PRIMARY folder's map is
    /// "Curriculum Coverage" — no existing site has its map renamed — and every
    /// other is "&lt;Folder&gt; Coverage"; a title that would repeat an earlier
    /// one, ignoring case, gets " (2)", " (3)"…
    /// </summary>
    public static List<string> CoveragePageTitles(IReadOnlyList<string> mapped, string? primary)
    {
        var titles = new List<string>();
        foreach (string folder in mapped)
        {
            string title = primary is not null && string.Equals(folder, primary, StringComparison.OrdinalIgnoreCase)
                ? "Curriculum Coverage"
                : folder + " Coverage";
            string candidate = title;
            for (int n = 2; titles.Contains(candidate, StringComparer.OrdinalIgnoreCase); n++)
                candidate = $"{title} ({n})";
            titles.Add(candidate);
        }
        return titles;
    }
    private static readonly Regex BlockAnchorRegex = new(@"\s+\^[A-Za-z0-9_-]+$", RegexOptions.Compiled);

    /// <summary>
    /// True when a page, given by its path RELATIVE TO THE COURSE, is in a
    /// curriculum folder (shared-rules.json → curriculumRules.isCurriculumPage).
    /// Splits the path and hands its folders to <see cref="IsCurriculum"/>;
    /// the file name is dropped. For a full path on disk use
    /// <see cref="PagePaths.IsCurriculum(string, string, IReadOnlyList{string})"/>,
    /// which makes it relative to the course first, so a working folder called
    /// "Curriculum Work" does not make every page curriculum.
    /// </summary>
    public static bool IsCurriculumPage(string relativePath, IReadOnlyList<string> declared)
    {
        if (string.IsNullOrWhiteSpace(relativePath)) return false;
        var segments = relativePath.Split(new[] { '/', '\\' }, StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length < 2) return false;                 // a page at the top has no folder
        return IsCurriculum(segments[..^1], declared);
    }

    /// <summary>
    /// The one curriculum rule (#614, the mac's
    /// <c>AssistCurriculumMentions.isCurriculum(folderSegments:declared:)</c>),
    /// without a disk: the page's FOLDER segments relative to the course, its
    /// file name already dropped, and the names the course declares
    /// (<see cref="CourseConfiguration.CurriculumFolders"/>: curriculum_folders,
    /// then the legacy curriculum_folder).
    ///
    /// <list type="number">
    /// <item>A leading section folder (<c>section2</c>) is set aside, and is
    /// never itself compared with a declared name.</item>
    /// <item>DECLARED: the first folder left equals a declared name, ignoring
    /// letter case. Top level only — that is the folder the build maps; a
    /// lesson subfolder sharing the name is not it.</item>
    /// <item>BY NAME, kept beside it: any folder contains "curriculum",
    /// ignoring letter case. A course made from scratch declares nothing, and
    /// a page wrongly kept up costs nothing students did not already see,
    /// while one wrongly hidden breaks every class that embeds it.</item>
    /// <item>The file name never counts (#615).</item>
    /// </list>
    ///
    /// Both sides are NFC-normalised before comparing: Swift's <c>==</c>
    /// treats the composed and decomposed forms of an accent as equal, and an
    /// ordinal comparison in C# does not, so a folder typed one way and
    /// declared the other would otherwise miss.
    /// </summary>
    public static bool IsCurriculum(IReadOnlyList<string> folderSegments, IReadOnlyList<string> declared)
    {
        var folders = folderSegments.Where(s => !string.IsNullOrEmpty(s)).ToList();
        if (folders.Count > 0 && HowITeachPage.IsASectionFolderName(folders[0])) folders.RemoveAt(0);
        if (folders.Count == 0) return false;

        string top = folders[0].Normalize();
        foreach (string name in declared)
            if (!string.IsNullOrEmpty(name) && string.Equals(name.Normalize(), top, StringComparison.OrdinalIgnoreCase))
                return true;

        return folders.Any(folder => folder.Contains("curriculum", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Checks whether a string is a leaf curriculum expectation code (e.g., "A1.1", "B2.11").
    /// </summary>
    public static bool IsExpectationCode(string code)
    {
        if (string.IsNullOrWhiteSpace(code)) return false;
        return ExpectationCodeRegex.IsMatch(code.Trim());
    }

    /// <summary>
    /// Returns the expectation wording from a markdown body:
    /// body after frontmatter, minus any trailing block anchor (e.g. ^b21).
    /// </summary>
    public static string ExpectationWording(string body)
    {
        if (string.IsNullOrWhiteSpace(body)) return "";

        string afterFrontmatter = StripFrontmatter(body).Trim();
        return BlockAnchorRegex.Replace(afterFrontmatter, "").Trim();
    }

    private static string StripFrontmatter(string text)
    {
        if (!text.StartsWith("---")) return text;
        int next = text.IndexOf("---", 3, StringComparison.Ordinal);
        if (next < 0) return text;
        return text[(next + 3)..];
    }
}

using System;
using System.IO;
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
    /// Checks whether a page path is inside a curriculum folder.
    /// Matches any folder segment containing "curriculum" (case-insensitive);
    /// the file name itself is ignored.
    /// </summary>
    public static bool IsCurriculumPage(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;

        string normalized = path.Replace('\\', '/');
        var segments = normalized.Split('/');
        for (int i = 0; i < segments.Length - 1; i++)
        {
            if (segments[i].Contains("curriculum", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
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

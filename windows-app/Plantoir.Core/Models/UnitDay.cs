using System;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// A unit and day number for a class page, e.g. Unit 3, Day 2.
/// </summary>
public readonly record struct UnitDay(int Unit, int Day) : IComparable<UnitDay>
{
    private static readonly Regex UnitDayRegex = new(@"^Unit\s+(\d+),\s*Day\s+(\d+)$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary>
    /// The title in the DEFAULT word. Use <see cref="TitleIn"/> for a course
    /// that calls a unit something else.
    /// </summary>
    public string Title => $"Unit {Unit}, Day {Day}";

    /// <summary>The title in this course's own word — "Module 2, Day 3".</summary>
    public string TitleIn(string? term) => $"{ClassPageTerm.Cleaned(term)} {Unit}, Day {Day}";

    public int CompareTo(UnitDay other)
    {
        int unitComp = Unit.CompareTo(other.Unit);
        return unitComp != 0 ? unitComp : Day.CompareTo(other.Day);
    }

    public static UnitDay? Parse(string? title) => Parse(title, null);

    /// <summary>
    /// Read a class page's numbers, in the word this COURSE uses.
    ///
    /// <para>The load-bearing case is the one that fails silently if it is got
    /// wrong: in a Module course, a page called "Unit 2, Day 3" is NOT a class
    /// page. Answering "yes" there would let one course's pages be renumbered
    /// under another course's vocabulary; answering "no" for a real Module page
    /// is worse still, because nothing reports it — the coverage map simply
    /// finds nothing to count and falls back to every published page.</para>
    ///
    /// <para>A null or empty term means the default word, exactly as an absent
    /// <c>unit_word</c> does, so every existing caller keeps its answer.</para>
    /// </summary>
    public static UnitDay? Parse(string? title, string? term)
    {
        if (string.IsNullOrWhiteSpace(title)) return null;
        string trimmed = title.Trim();

        string word = ClassPageTerm.Cleaned(term);
        var pattern = word.Equals(ClassPageTerm.DefaultWord, StringComparison.OrdinalIgnoreCase)
            ? UnitDayRegex
            : new Regex(ClassPageTerm.PagePattern(word), RegexOptions.IgnoreCase);

        var match = pattern.Match(trimmed);
        if (!match.Success) return null;
        return new UnitDay(int.Parse(match.Groups[1].Value), int.Parse(match.Groups[2].Value));
    }
}

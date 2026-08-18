using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// A unit and day number for a class page, e.g. Unit 3, Day 2.
/// </summary>
public readonly record struct UnitDay(int Unit, int Day) : IComparable<UnitDay>
{
    private static readonly Regex UnitDayRegex = new(@"^Unit\s+(\d+),\s*Day\s+(\d+)$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public string Title => $"Unit {Unit}, Day {Day}";

    public int CompareTo(UnitDay other)
    {
        int unitComp = Unit.CompareTo(other.Unit);
        return unitComp != 0 ? unitComp : Day.CompareTo(other.Day);
    }

    public static UnitDay? Parse(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return null;
        var match = UnitDayRegex.Match(title.Trim());
        if (!match.Success) return null;
        return new UnitDay(int.Parse(match.Groups[1].Value), int.Parse(match.Groups[2].Value));
    }
}

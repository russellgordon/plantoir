using System;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// What a course calls the first half of a class page's name — "Unit 2, Day 3",
/// or "Module 2, Day 3", or "Thread 2, Day 3".
///
/// <para>The C# mirror of <c>scripts/class_pages.py</c> and the mac's
/// <c>ClassPageTerm</c>. The rule itself is shared (the default, the pattern,
/// the refusals); this is the half the app needs in order to ask the question
/// before a build exists.</para>
///
/// <para><b>Why the parsing half matters more than the naming half.</b> Reading
/// only the literal "Unit" does not FAIL for a course that says Module — it
/// answers "this is not a class page", the coverage map finds nothing to count,
/// and falls back to counting every published page. A map that looks healthy
/// and is wrong is the silent-success failure this whole family of keys exists
/// to end, which is why "new courses only, with the parsing left hardcoded"
/// was rejected on the mac and is not an option here either.</para>
///
/// <para><b>"Day" is deliberately not configurable.</b> A teacher who says
/// "Thread" almost certainly still says "Day 3".</para>
/// </summary>
public static class ClassPageTerm
{
    /// <summary>
    /// What a course says when <c>unit_word</c> is absent — and what every
    /// course made before the key existed says.
    /// </summary>
    public const string DefaultWord = "Unit";

    /// <summary>
    /// A course's word, defaulting the way an absent key must.
    ///
    /// <para>An absent key and an empty string both mean "Unit". They are NOT
    /// distinguished the way <c>graded_folders</c> distinguishes absent from
    /// empty: there is no sensible reading of "the teacher cleared the word",
    /// and a course whose class pages had no name at all could not be
    /// built.</para>
    /// </summary>
    public static string Cleaned(string? word)
    {
        string trimmed = (word ?? string.Empty).Trim();
        return trimmed.Length == 0 ? DefaultWord : trimmed;
    }

    /// <summary>
    /// Why this word cannot be used, or null when it is fine. Empty is fine —
    /// it means the default, and a wizard should not refuse a field nobody has
    /// typed in yet.
    ///
    /// <para>These two sentences are NOT in any contract: they live only in
    /// each app's own code, and are worded here to match the mac's
    /// <c>ClassPageTerm.problem(with:)</c> so a teacher meets the same
    /// explanation on either platform.</para>
    /// </summary>
    public static string? Problem(string? raw)
    {
        string trimmed = (raw ?? string.Empty).Trim();
        if (trimmed.Length == 0) return null;
        foreach (char character in trimmed)
            if (char.IsDigit(character))
                return "A unit's name cannot contain a number — the number after it is the unit's own.";
        if (trimmed.Contains(','))
            return "A unit's name cannot contain a comma; the comma separates the unit from the day.";
        return null;
    }

    /// <summary>
    /// The pattern a class page's name must match for this word.
    ///
    /// <para><see cref="Regex.Escape"/> is not decoration: the word comes from
    /// a teacher's own configuration, and one containing "(" or "+" would
    /// otherwise quietly become a different pattern, or fail to compile in the
    /// middle of a build.</para>
    /// </summary>
    public static string PagePattern(string? word) =>
        "^" + Regex.Escape(Cleaned(word)) + @"\s+(\d+),\s*Day\s+(\d+)$";

    /// <summary>The pattern the FIRST class of the year matches.</summary>
    public static string FirstClassPattern(string? word) =>
        "^" + Regex.Escape(Cleaned(word)) + @"\s+0*1,\s*Day\s+0*1$";

    /// <summary>
    /// The caption a wizard shows under the field, so a teacher can see what
    /// their word will produce before they commit to it.
    /// </summary>
    public static string Caption(string? word) =>
        $"Class pages will be named '{Cleaned(word)} 1, Day 1'.";
}

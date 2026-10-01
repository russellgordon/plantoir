using System;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// The SHAPE a course's class-page names take (#274, mac #267). Stored as
/// <c>class_page_scheme</c>; absent, empty and unknown all read as
/// <see cref="UnitDay"/>, so a scheme a newer app wrote is today's shape here
/// rather than an error (<c>contracts/file-formats.json</c> → <c>class_page_scheme</c>).
/// </summary>
public enum ClassPageScheme
{
    /// <summary>"Unit 2, Day 3" — every course made before the scheme existed.</summary>
    UnitDay,

    /// <summary>"Week 3": ONE number counting meetings — how a club names its pages.</summary>
    Numbered,
}

/// <summary>
/// What the assistant calls one class page when it talks to the TEACHER. A
/// closed pair because the sentences carry articles and plurals. Stored as
/// <c>class_noun</c>; absent and unknown read as <see cref="Class"/>.
/// </summary>
/// <remarks>
/// <para><b>Never reaches the model.</b> The "meeting" form is for what a
/// teacher reads — a plan's card, a write's summary, the dates card, the
/// transcript — and never for the tool result the model reads nor for what
/// <c>plantoir-mcp.exe</c> returns. Putting it there would make a club's
/// routing unmeasured (CLAUDE.md, "The local assistant", trap 4); the mac pins
/// it with <c>ClubNounTests.testTheNounNeverReachesWhatTheModelReads</c>, this
/// side with <c>ClubNounTests.TheNounNeverReachesWhatTheModelReads</c>.</para>
/// </remarks>
public enum ClassNoun
{
    Class,
    Meeting,
}

/// <summary>Reading the two stored values.</summary>
public static class ClassPageSchemes
{
    /// <summary>The value written for a club.</summary>
    public const string NumberedValue = "numbered";

    /// <summary>The value an ordinary course would write (none ever does: absence says it).</summary>
    public const string UnitDayValue = "unit_day";

    /// <summary>The scheme a stored value means.</summary>
    public static ClassPageScheme Reading(string? raw) =>
        string.Equals((raw ?? "").Trim(), NumberedValue, StringComparison.OrdinalIgnoreCase)
            ? ClassPageScheme.Numbered
            : ClassPageScheme.UnitDay;

    /// <summary>Which of a class/meeting pair a course's TEACHER reads (never the model).</summary>
    public static string Say(ClassNoun noun, string forAClass, string forAMeeting) =>
        noun == ClassNoun.Meeting ? forAMeeting : forAClass;

    /// <summary>The noun a stored value means.</summary>
    public static ClassNoun NounReading(string? raw) =>
        string.Equals((raw ?? "").Trim(), "meeting", StringComparison.OrdinalIgnoreCase)
            ? ClassNoun.Meeting
            : ClassNoun.Class;
}

/// <summary>
/// How ONE course names its class pages: its word and its scheme, together.
/// </summary>
/// <remarks>
/// <para><b>No default on any path that writes a page.</b> Every place that
/// builds a class-page title has to say which course's naming it is using, so
/// none of them can quietly fall back to "Unit 1, Day 10" inside a course whose
/// pages are "Week 10". The mac's #267 plan review found that with a default a
/// missed site writes the wrong file and every test stays green, which is why
/// <see cref="Standard"/> is a named value a caller must ask for, never an
/// optional parameter.</para>
///
/// <para>Under <see cref="ClassPageScheme.Numbered"/> a page is held as unit 1
/// and the DAY is its number — every planner then counts one number with no
/// rewrite — but nothing may treat that unit as a real one: a numbered course
/// has no units, and "publish Week 1" read as "unit 1" publishes every meeting
/// (<c>class-planning.json</c> → <c>wholeUnit</c>).</para>
/// </remarks>
public sealed record ClassPageNaming
{
    public ClassPageNaming(string? word, ClassPageScheme scheme)
    {
        Word = ClassPageTerm.Cleaned(word);
        Scheme = scheme;
    }

    /// <summary>What the course calls a unit — or, numbered, the whole word: "Week".</summary>
    public string Word { get; }

    public ClassPageScheme Scheme { get; }

    /// <summary>What a course says when it has said nothing: "Unit 2, Day 3".</summary>
    public static ClassPageNaming Standard { get; } = new(ClassPageTerm.DefaultWord, ClassPageScheme.UnitDay);

    /// <summary>True when a page name carries one number and there are no units.</summary>
    public bool IsNumbered => Scheme == ClassPageScheme.Numbered;

    /// <summary>The pattern a class page's name must match, numbers captured.</summary>
    public string Pattern => IsNumbered
        ? "^" + Regex.Escape(Word) + @"\s+(\d+)$"
        : ClassPageTerm.PagePattern(Word);

    /// <summary>"Unit N, Day N" or "Week N" — for sentences about pages passed over.</summary>
    public string ShapeDescription => IsNumbered ? $"{Word} N" : $"{Word} N, Day N";

    /// <summary>
    /// The name a position makes: "Unit 2, Day 3", or "Week 3". Every sentence
    /// and every file name that names a position goes through here (#268).
    /// </summary>
    public string Title(int unit, int day) => IsNumbered ? $"{Word} {day}" : $"{Word} {unit}, Day {day}";

    /// <summary>The name a parsed position makes.</summary>
    public string Title(UnitDay position) => Title(position.Unit, position.Day);

    /// <summary>A unit, named — "Unit 4" — or null in a numbered course, which has none.</summary>
    public string? UnitName(int unit) => IsNumbered ? null : $"{Word} {unit}";

    /// <summary>Read a title under this naming; null when it is not a class page here.</summary>
    public UnitDay? Parse(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return null;
        var match = Regex.Match(title.Trim(), Pattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (!match.Success) return null;
        return IsNumbered
            ? new UnitDay(1, int.Parse(match.Groups[1].Value))
            : new UnitDay(int.Parse(match.Groups[1].Value), int.Parse(match.Groups[2].Value));
    }
}

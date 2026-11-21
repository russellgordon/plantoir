using System.Text;

namespace Plantoir.Core.Models;

/// <summary>
/// Text that must stay on one line and read as it is stored: control
/// characters become a space, and the bidirectional controls are removed
/// (#821, the mac's #780 and its <c>OneLineText</c>).
///
/// <para>The rule is <c>contracts/shared-rules.json</c> →
/// <c>courseNameCharacters</c>. It works on code points; every code point in
/// the set is in the Basic Multilingual Plane and is not a surrogate
/// (<c>onCodePoints</c>), so a <c>char</c>-by-<c>char</c> loop is exact and a
/// surrogate pair is never touched.</para>
/// <list type="bullet">
/// <item>C0 controls U+0000 to U+001F (tab, line feed and carriage return
/// included), DEL U+007F, the C1 controls U+0080 to U+009F, and the line and
/// paragraph separators U+2028 and U+2029 each become ONE space.</item>
/// <item>The bidirectional embeddings, overrides and isolates, U+202A to
/// U+202E and U+2066 to U+2069, are removed.</item>
/// <item>Everything else is kept, on purpose (<c>keptOnPurpose</c>).</item>
/// </list>
/// <para>Nothing is trimmed and nothing is collapsed (<c>noTrimming</c>): a
/// reader that wants the ends trimmed trims AFTER cleaning, as the New Course
/// window does.</para>
/// </summary>
public static class OneLineText
{
    // MARK: - Functions

    /// <summary>Whether <paramref name="unit"/> becomes one space.</summary>
    public static bool IsSpacedOut(char unit)
    {
        int value = unit;
        if (value <= 0x1F) return true;
        if (value == 0x7F) return true;
        if (value >= 0x80 && value <= 0x9F) return true;
        if (value == 0x2028 || value == 0x2029) return true;
        return false;
    }

    /// <summary>Whether <paramref name="unit"/> is taken out altogether.</summary>
    public static bool IsRemoved(char unit)
    {
        int value = unit;
        if (value >= 0x202A && value <= 0x202E) return true;
        if (value >= 0x2066 && value <= 0x2069) return true;
        return false;
    }

    /// <summary>
    /// <paramref name="text"/> with the rule applied.
    /// <paramref name="keepingLineBreaks"/> leaves U+000A alone and cleans
    /// everything else, a carriage return included: it is for the one trail
    /// record that is two lines on purpose (the assistant's question and the
    /// teacher's sentence behind <see cref="Scripting.ActivityTrail.PromptPrefix"/>).
    /// </summary>
    public static string Cleaned(string text, bool keepingLineBreaks = false)
    {
        var result = new StringBuilder(text.Length);
        foreach (char unit in text)
        {
            if (IsRemoved(unit))
            {
                continue;
            }
            if (keepingLineBreaks && unit == '\n')
            {
                result.Append(unit);
            }
            else if (IsSpacedOut(unit))
            {
                result.Append(' ');
            }
            else
            {
                result.Append(unit);
            }
        }
        return result.ToString();
    }

    /// <summary>
    /// A course's name as every reader of <c>course_config.json</c> →
    /// <c>course_name</c> shows it and every writer stores it (#821): one name
    /// at the places that read a course name, so a search finds them all.
    /// </summary>
    public static string CourseName(string name) => Cleaned(name);
}

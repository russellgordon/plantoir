using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// What settler S3 reads about a course before it judges a model's
/// add_next_class (#440). Built by <see cref="AssistWorkspace.NextClassReading"/>
/// in <c>plantoir-mcp</c> and carried back to the window in the answer's
/// <c>_meta</c> under <see cref="AssistToolAnswer.NextClassKey"/>.
/// </summary>
/// <param name="UnitWord">The course's word for a unit ("Unit", "Module") — or, in a numbered course, its page word ("Week").</param>
/// <param name="IsNumbered">True when the course names its pages with one number and has no units.</param>
/// <param name="Noun">What the course calls one of its pages: class or meeting.</param>
/// <param name="PlainNextUnit">The unit a plain "add the next class" would land in.</param>
/// <param name="PlainNextDay">The day it would carry.</param>
public sealed record AssistNextClassReading(string UnitWord, bool IsNumbered, ClassNoun Noun,
                                            int PlainNextUnit, int PlainNextDay)
{
    /// <summary>The reading as the <c>_meta</c> value <c>plantoir-mcp</c> sends.</summary>
    public JsonObject ToJson() => new()
    {
        ["unitWord"] = UnitWord,
        ["isNumbered"] = IsNumbered,
        ["noun"] = Noun == ClassNoun.Meeting ? "meeting" : "class",
        ["unit"] = PlainNextUnit,
        ["day"] = PlainNextDay,
    };

    /// <summary>The reading back out of a <c>_meta</c> value, or null when it is missing or not this shape.</summary>
    public static AssistNextClassReading? FromJson(JsonNode? node)
    {
        if (node is not JsonObject value) return null;
        try
        {
            if (value["unitWord"]?.GetValue<string>() is not { } word) return null;
            if (value["unit"] is null || value["day"] is null) return null;
            return new AssistNextClassReading(
                word,
                value["isNumbered"]?.GetValue<bool>() == true,
                ClassPageSchemes.NounReading(value["noun"]?.GetValue<string>()),
                value["unit"]!.GetValue<int>(),
                value["day"]!.GetValue<int>());
        }
        catch (Exception error) when (error is InvalidOperationException or FormatException)
        {
            return null;
        }
    }
}

/// <summary>
/// Settler S3 (#440): a teacher's sentence that the MODEL answered with a
/// plain add_next_class, read in code for the three things that tool cannot
/// carry on the local surface — a new unit, a unit or day other than the next
/// one, and more than one page. A literal port of the mac's
/// <c>AssistNextClassUnits</c> (AssistNextClassUnits.swift), pinned by the
/// same rows: <c>assist-cases.json</c> → <c>nextClassUnits</c>.
/// </summary>
/// <remarks>
/// <para><b>Why it exists.</b> Measured on the mac 2026-10-07 (M4 Pro,
/// b10435): ten sentences about units and counts reached add_next_class 50
/// times in 50 with only a course and a section, each adding ONE page in the
/// current unit and reporting success. Showing the tool <c>unit</c> and
/// <c>days</c> instead is what #411 measured and parked (both models read the
/// NEXT in "add the next class" as "start a new unit"), and Windows' own
/// router, shown them until #440, sent unit "next" on 50 of 50 plain calls.
/// So the model keeps two arguments, the phrasings that do these things are
/// answered in code (<see cref="AssistCardCommand"/>), and a sentence that
/// reaches the model anyway is stopped here and pointed at them.</para>
///
/// <para><b>It points; it never converts.</b> Turning "don't start a new unit
/// yet" into a new-unit call would be reading meaning out of words, which is
/// what the frames exist to avoid. Stopping costs a teacher one more sentence;
/// guessing wrong costs a page in the wrong unit, reported as done.</para>
///
/// <para><b>Two places a C# port differs from Swift by accident, closed on
/// purpose</b> (stack-2 plan review, L1): Swift's <c>Int</c> is 64-bit, so
/// numbers are read with <see cref="long.TryParse(string?, out long)"/> — or
/// "unit 3000000000" would be kind b on the mac and run here; and Swift walks
/// grapheme clusters, so a decomposed "é" is ONE non-letter there but "e" and
/// a separator here — the sentence is normalised to Form C first.
/// Two differences REMAIN, deliberately, since no contract row exercises them
/// and both need exotic input that only changes which non-words are seen: a
/// multi-character grapheme (an a-z letter with a combining mark that has no
/// precomposed form) is a letter in Swift's comparison and a separator here,
/// and 'İ' lower-cases to "i" here where Swift gives "i̇".</para>
/// </remarks>
public static class AssistNextClassUnits
{
    /// <summary>Which of the three things the sentence asked for. The contract names them a, b and c.</summary>
    public enum Kind
    {
        /// <summary>"new unit", "next unit", "another unit" — or the course's own word. Contract "a".</summary>
        NewUnit,
        /// <summary>"Unit 3", or "Unit 3, Day 7", that is not where the next page goes. Contract "b".</summary>
        AnotherUnitOrDay,
        /// <summary>A count above one right before the noun: "the next two classes". Contract "c".</summary>
        Several,
    }

    /// <summary>The letter the contract's <c>pointed[].kind</c> uses for a kind.</summary>
    public static string Letter(Kind kind) => kind switch
    {
        Kind.NewUnit => "a",
        Kind.AnotherUnitOrDay => "b",
        _ => "c",
    };

    /// <summary>The nouns a count may stand right before.</summary>
    private static readonly HashSet<string> PageNouns = new(StringComparer.Ordinal)
        { "classes", "days", "lessons", "meetings", "pages", "periods" };

    /// <summary>The words that may stand between a count and the noun.</summary>
    private static readonly HashSet<string> BeforeTheNoun = new(StringComparer.Ordinal) { "more", "extra", "new" };

    /// <summary>The verbs a count may follow (with "the", "next" or "another" between). "set up" is read separately.</summary>
    private static readonly HashSet<string> AddingVerbs = new(StringComparer.Ordinal) { "add", "create", "make", "plan" };

    /// <summary>The words that make the next word a NEW unit.</summary>
    private static readonly HashSet<string> NewUnitWords = new(StringComparer.Ordinal)
        { "new", "next", "another", "fresh", "different" };

    /// <summary>Counts written as words. One is not here: one page is what the tool does.</summary>
    private static readonly Dictionary<string, long> SpelledCounts = new(StringComparer.Ordinal)
    {
        ["two"] = 2, ["three"] = 3, ["four"] = 4, ["five"] = 5, ["six"] = 6, ["seven"] = 7, ["eight"] = 8,
        ["nine"] = 9, ["ten"] = 10, ["eleven"] = 11, ["twelve"] = 12, ["several"] = 2,
    };

    /// <summary>Unit numbers written as words.</summary>
    private static readonly Dictionary<string, long> SpelledNumbers = new(StringComparer.Ordinal)
    {
        ["one"] = 1, ["two"] = 2, ["three"] = 3, ["four"] = 4, ["five"] = 5, ["six"] = 6, ["seven"] = 7,
        ["eight"] = 8, ["nine"] = 9, ["ten"] = 10, ["eleven"] = 11, ["twelve"] = 12,
    };

    /// <summary>
    /// What the sentence asked for that a plain add_next_class would not do,
    /// or null when the plain call is the request — and null, too, when there
    /// is no reading (no remembered dates, or the course gone), so the call
    /// runs and the tool asks for the dates (ruling 7).
    /// </summary>
    public static Kind? KindOf(string? typed, AssistNextClassReading? reading)
    {
        if (reading is null) return null;
        var words = Words(typed);
        // In a numbered course the page word is not a unit ("Week 9" is a
        // page), so only the literal word "unit" is read there.
        var unitWords = new HashSet<string>(StringComparer.Ordinal) { "unit", "units" };
        if (!reading.IsNumbered)
        {
            string own = reading.UnitWord.ToLowerInvariant();
            unitWords.Add(own);
            unitWords.Add(own + "s");
        }

        // The mac's order, which the rows depend on: a, then c, then b.
        if (AsksForANewUnit(words, unitWords)) return Kind.NewUnit;
        if (AsksForSeveral(words)) return Kind.Several;
        if (UnitNamed(words, unitWords) is not { } named) return null;
        // A numbered course has no units, so any unit named is not this one.
        if (reading.IsNumbered) return Kind.AnotherUnitOrDay;
        if (named != reading.PlainNextUnit) return Kind.AnotherUnitOrDay;
        // The DAY, too (ruling 4): "Unit 3, Day 7" when the next page is
        // Unit 3, Day 5 would otherwise make Day 5 and report success.
        if (DayNamed(words) is { } day && day != reading.PlainNextDay) return Kind.AnotherUnitOrDay;
        return null;
    }

    /// <summary>
    /// The sentence as lower-case words: runs of ASCII letters, digits and
    /// apostrophes, so "Unit 3," is "unit", "3" and "tomorrow's" stays whole.
    /// Deliberately NOT <see cref="char.IsLetter(char)"/>: the mac keeps a-z only.
    /// </summary>
    public static List<string> Words(string? typed)
    {
        string folded = (typed ?? "").Normalize(NormalizationForm.FormC)
            .ToLowerInvariant().Replace('’', '\'');
        var words = new List<string>();
        var word = new StringBuilder();
        foreach (var element in EnumerateClusters(folded))
        {
            char only = element.Length == 1 ? element[0] : '\0';
            bool keep = (only >= 'a' && only <= 'z') || (only >= '0' && only <= '9') || only == '\'';
            if (keep)
            {
                word.Append(only);
                continue;
            }
            if (word.Length > 0) words.Add(word.ToString());
            word.Clear();
        }
        if (word.Length > 0) words.Add(word.ToString());
        return words;
    }

    /// <summary>The text one grapheme cluster at a time, as Swift's <c>for character in</c> walks it.</summary>
    private static IEnumerable<string> EnumerateClusters(string text)
    {
        var walker = StringInfo.GetTextElementEnumerator(text);
        while (walker.MoveNext()) yield return walker.GetTextElement();
    }

    /// <summary>"new unit", "next unit", "another module" — two words side by side.</summary>
    private static bool AsksForANewUnit(List<string> words, HashSet<string> unitWords)
    {
        for (int index = 0; index + 1 < words.Count; index++)
            if (NewUnitWords.Contains(words[index]) && unitWords.Contains(words[index + 1])) return true;
        return false;
    }

    /// <summary>
    /// A count above one IMMEDIATELY before a page noun (an optional "more",
    /// "extra" or "new" between them), where the count follows either an
    /// adding verb — "add", "create", "make", "plan", "set up", with "the",
    /// "next" or "another" allowed between — or the word "next". Strict on
    /// purpose (ruling 5): "Add tomorrow's class page, I teach two classes
    /// tomorrow" and "Add the next class for period 2" each ask for ONE page,
    /// and both are <c>runs</c> rows.
    /// </summary>
    private static bool AsksForSeveral(List<string> words)
    {
        for (int index = 0; index < words.Count; index++)
        {
            int? after = null;
            if (AddingVerbs.Contains(words[index])) after = index + 1;
            else if (words[index] == "set" && index + 1 < words.Count && words[index + 1] == "up") after = index + 2;

            if (after is { } start)
            {
                int position = start;
                // In this order, each at most once — the mac's `for optional in [...] where`.
                foreach (string optional in new[] { "the", "next", "another" })
                    if (position < words.Count && words[position] == optional) position++;
                if (CountThenNoun(words, position)) return true;
            }
            if (words[index] == "next" && CountThenNoun(words, index + 1)) return true;
        }
        return false;
    }

    /// <summary>A count above one at <paramref name="start"/>, then the noun.</summary>
    private static bool CountThenNoun(List<string> words, int start)
    {
        if (start >= words.Count) return false;
        int position = start;
        bool counted = false;
        if (Number(words[position]) is { } number && number >= 2)
        {
            counted = true;
            position++;
        }
        else if (SpelledCounts.ContainsKey(words[position]))
        {
            counted = true;
            position++;
        }
        else if (words[position] == "a" && position + 1 < words.Count)
        {
            // "a few", "a couple of".
            if (words[position + 1] == "few")
            {
                counted = true;
                position += 2;
            }
            else if (words[position + 1] == "couple")
            {
                counted = true;
                position += 2;
                if (position < words.Count && words[position] == "of") position++;
            }
        }
        if (!counted || position >= words.Count) return false;
        if (BeforeTheNoun.Contains(words[position])) position++;
        if (position >= words.Count) return false;
        if (PageNouns.Contains(words[position])) return true;
        // "two class pages", "three meeting pages".
        return words[position] is "class" or "meeting" or "lesson"
            && position + 1 < words.Count && words[position + 1] == "pages";
    }

    /// <summary>The number after the first unit word that has one: "Unit 3", "unit three", "Module 4".</summary>
    private static long? UnitNamed(List<string> words, HashSet<string> unitWords)
    {
        for (int index = 0; index + 1 < words.Count; index++)
        {
            if (!unitWords.Contains(words[index])) continue;
            if (Number(words[index + 1]) is { } number) return number;
            if (SpelledNumbers.TryGetValue(words[index + 1], out long spelled)) return spelled;
        }
        return null;
    }

    /// <summary>
    /// The number after the first "day" that has one — read only beside a
    /// unit, so a rotation's "it's a Day 2 tomorrow" alone never stops a call.
    /// </summary>
    private static long? DayNamed(List<string> words)
    {
        for (int index = 0; index + 1 < words.Count; index++)
        {
            if (words[index] != "day") continue;
            if (Number(words[index + 1]) is { } number) return number;
            if (SpelledNumbers.TryGetValue(words[index + 1], out long spelled)) return spelled;
        }
        return null;
    }

    /// <summary>Swift's <c>Int(word)</c> over a word of a-z, 0-9 and apostrophes: digits only, 64-bit.</summary>
    private static long? Number(string word) =>
        long.TryParse(word, NumberStyles.None, CultureInfo.InvariantCulture, out long value) ? value : null;

    /// <summary>
    /// The pointer settler S3 shows (<c>wording.nextClassNeedsItsOwnPhrasing*</c>):
    /// the numbered form, the Unit form, or the form for a course with its own
    /// unit word — the mac's one function, split here into three
    /// <see cref="AssistWording"/> members because the contract walk resolves
    /// each key to a member of its own name. The days sentence names the
    /// course's LATEST unit (the plain next page's), never a constant.
    /// </summary>
    public static string Pointer(AssistNextClassReading reading)
    {
        if (reading.IsNumbered) return AssistWording.NextClassNeedsItsOwnPhrasingInANumberedCourse(reading.Noun);
        if (reading.UnitWord.ToLowerInvariant() == "unit")
            return AssistWording.NextClassNeedsItsOwnPhrasing(reading.Noun, reading.PlainNextUnit);
        return AssistWording.NextClassNeedsItsOwnPhrasingInAModuleCourse(reading.UnitWord, reading.Noun,
                                                                         reading.PlainNextUnit);
    }
}

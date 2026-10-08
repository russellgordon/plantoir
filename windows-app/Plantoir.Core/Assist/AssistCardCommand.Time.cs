using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace Plantoir.Core.Assist;

/// <summary>A one-digit time with no am or pm, asked about rather than guessed (#281).</summary>
/// <param name="Clock">The time named back, always with a colon: <c>6:30</c>.</param>
/// <param name="SayMorning">The sentence to type for the morning, which the family accepts.</param>
/// <param name="SayEvening">The same for the evening.</param>
public sealed record AssistTimeQuestion(string Clock, string SayMorning, string SayEvening);

/// <summary>A time the family can read but does not SET, answered with the one spelling to use (#288).</summary>
/// <param name="Written">The teacher's own words for the time, in their capitals.</param>
/// <param name="Say">The sentence to type, in the canonical form.</param>
/// <param name="CommaIsTheOnlyDifference">Whether taking the commas out is all that stands in the way.</param>
public sealed record AssistTimeRespelling(string Written, string Say, bool CommaIsTheOnlyDifference);

/// <summary>
/// "deploy at &lt;time&gt;": matched in code and never sent to the model
/// (#193), asked about when it could be morning or evening (#281), and
/// answered with the spelling to use when it is written a way the family does
/// not set (#288). A port of the mac's <c>AssistCardCommand</c> — the same
/// frame, the same readings, the same refusals — because two platforms reading
/// a time differently is a deploy set for a different moment.
/// </summary>
/// <remarks>
/// <para><b>Why in code at all.</b> Measured on the mac (Qwen2.5-1.5B, ctx
/// 8192, Metal, M4 Pro, 2026-09-18): "Deploy at 6:30 AM" went to
/// <c>deploy_section</c> 10 trials of 10 — an IMMEDIATE deploy to students for
/// a teacher who asked for half six. The larger assistant gets it right; this
/// is a small-tier failure, and a time is a number, not a judgement.</para>
///
/// <para><b>Clock-free.</b> The matcher answers <c>when = "06:30"</c> or
/// <c>"tomorrow 06:30"</c>, never a date; the DAY is settled later, once, where
/// the call is made (<see cref="ScheduledMoment"/>).</para>
///
/// <para><b>The rule that carries the most weight:</b> a time with no am/pm
/// must be written with two digits of hour. <c>6:30</c> is morning or evening
/// and nobody can tell which — so it is ASKED, never guessed and never sent to
/// the model. Every spelling is a row in <c>assist-cases.json</c> →
/// <c>deployAtATime</c>.</para>
/// </remarks>
public sealed partial record AssistCardCommand
{
    /// <summary>The mac's tidier: whitespace off, then . and ! off the ends, lower-cased.</summary>
    private static string TidiedForTime(string message) =>
        message.Trim().Trim('.', '!').ToLowerInvariant();

    private static string[] Words(string text) => text.Split(' ', StringSplitOptions.RemoveEmptyEntries);

    /// <summary>
    /// <c>[please] deploy [it|this section] [today|tomorrow] at &lt;time&gt; [today|tomorrow] [please]</c>.
    /// The one frame behind the matcher, the question and the spelling, so the
    /// three cannot disagree.
    /// </summary>
    internal static (string? DayWord, List<string> TimeWords)? DeployFrame(string tidied)
    {
        // A question mark comes off HERE, not in the shared tidier: fixed
        // shapes are matched by equality and some of them carry one.
        string frame = tidied.TrimEnd('?');
        var words = Words(frame).ToList();
        // "Please" is courtesy at either end. "Can you deploy at 7 pm" is
        // deliberately not accepted: it asks about ability as much as it
        // instructs.
        if (words.Count > 0 && words[0] == "please") words.RemoveAt(0);
        if (words.Count > 0 && words[^1] == "please") words.RemoveAt(words.Count - 1);
        if (words.Count == 0 || words[0] != "deploy") return null;
        words.RemoveAt(0);
        if (words.Count > 0 && words[0] == "it") words.RemoveAt(0);
        else if (words.Count >= 2 && words[0] == "this" && words[1] == "section") words.RemoveRange(0, 2);

        string? dayWord = null;
        if (words.Count > 0 && words[0] is "today" or "tomorrow")
        {
            dayWord = words[0];
            words.RemoveAt(0);
        }
        if (words.Count == 0 || words[0] != "at") return null;
        words.RemoveAt(0);
        if (words.Count > 0 && words[^1] is "today" or "tomorrow")
        {
            // A day word on BOTH sides is a sentence disagreeing with itself.
            if (dayWord is not null) return null;
            dayWord = words[^1];
            words.RemoveAt(words.Count - 1);
        }
        return (dayWord, words);
    }

    // ---- "schedule a deploy …" and "cancel the scheduled deploy" (#424) -----

    /// <summary>
    /// <c>[please] schedule a|the deploy [today|tomorrow] at|for &lt;time&gt; …</c>
    /// read AS the deploy-at-a-time family — "schedule a deploy" for "deploy",
    /// and "for" for "at" in that one place — or null. Everything after the
    /// opening is then the family's own frame, so an accepted, asked and
    /// refused time is read exactly as "deploy at …" reads it.
    /// </summary>
    /// <remarks>
    /// <para><b>Why (#424).</b> Measured on this PC (bundle 10, Intel UHD 620,
    /// Qwen2.5-1.5B): with <c>includeLinked</c> gone from the local surface, a
    /// sentence asking for a LATER deploy reached <c>deploy_section</c> 10 of
    /// 10 — an immediate deploy behind the Deploy button. Read in code, the
    /// canonical phrasing never reaches the model.</para>
    /// <para><b>Tolerance is the hide frame's discipline, not more.</b> A
    /// question mark falls through (a teacher may be ASKING whether one is
    /// scheduled); so does a leading word other than "please" ("don't"), and
    /// any course, section or condition named — a card binds THIS window's
    /// course and section.</para>
    /// </remarks>
    internal static string? ScheduleAsDeploy(string tidied)
    {
        if (tidied.EndsWith('?')) return null;
        var words = Words(tidied).ToList();
        bool please = words.Count > 0 && words[0] == "please";
        if (please) words.RemoveAt(0);
        if (words.Count < 3 || words[0] != "schedule" || words[1] is not ("a" or "the") || words[2] != "deploy")
            return null;
        words.RemoveRange(0, 3);
        // The day first (bundle A fix round, ruling 1a): "for tomorrow at
        // 6:30 am" is "tomorrow at 6:30 am" — the more common order.
        if (words.Count >= 2 && words[0] == "for" && words[1] is "today" or "tomorrow") words.RemoveAt(0);
        int where = words.Count > 0 && words[0] is "today" or "tomorrow" ? 1 : 0;
        if (words.Count > where && words[where] == "for") words[where] = "at";
        var rebuilt = new List<string>();
        if (please) rebuilt.Add("please");
        rebuilt.Add("deploy");
        rebuilt.AddRange(words);
        return string.Join(' ', rebuilt);
    }

    /// <summary>
    /// "schedule a deploy" with no time the family can set (#424): never a deploy now, and
    /// never sent to the model, which measured 10 of 10 to an immediate deploy
    /// for this shape of sentence. The app asks for the time instead
    /// (<see cref="AssistWording.ScheduleADeployNeedsATime"/>), transcript only.
    /// </summary>
    /// <remarks>
    /// Widened in the bundle A fix round (ruling 1b): ANY sentence that opens
    /// "[please] schedule a|the deploy" and is not answered by the family —
    /// "schedule a deploy tomorrow morning", "… later today", "… for Monday",
    /// "… at 7" — is asked about, because the model it would otherwise reach
    /// sent exactly this shape to an immediate deploy 10 of 10. Three things
    /// still fall through to the model, as everywhere in these frames: a
    /// question mark, a negation, and another course or section named (a
    /// card, and this question, are about THIS window's section).
    /// </remarks>
    public static bool AsksWhenToSchedule(string message)
    {
        string tidied = TidiedForTime(message);
        if (tidied.EndsWith('?')) return false;
        var words = Words(tidied).ToList();
        if (words.Count > 0 && words[0] == "please") words.RemoveAt(0);
        if (words.Count < 3 || words[0] != "schedule" || words[1] is not ("a" or "the") || words[2] != "deploy")
            return false;
        foreach (string raw in words.Skip(3))
        {
            string word = raw.Trim(',', ';', ':');
            if (word is "don't" or "dont" or "don’t" or "not" or "never" or "no") return false;
            if (word.Contains("section", StringComparison.Ordinal) || word is "course" or "courses") return false;
            if (System.Text.RegularExpressions.Regex.IsMatch(word, "^[a-z]{3}[0-9][a-z0-9-]*$")) return false;
        }
        // Answered already — set, asked morning-or-evening, or respelled.
        if (Matching(message) is not null || MorningOrEvening(message) is not null || TimeToSayAs(message) is not null)
            return false;
        return true;
    }

    /// <summary>
    /// <c>[please] cancel the|that|my scheduled deploy [please]</c> →
    /// <c>cancel_scheduled_deploy</c> (#424), and — since #466 (the mac's
    /// #449) — the prompt shelf's own card, "Cancel scheduled deploy", with no
    /// determiner. Measured on this PC (bundle 10): "Don't send it in the
    /// morning after all" was declined 10 of 10, so a deploy the teacher
    /// wanted stopped still went out. The canonical sentence is answered in
    /// code; anything else — a question mark, "don't", a course or section
    /// named, or "cancel the deploy" (which may mean a deploy running now) —
    /// reaches the model as before. Cancelling is the SAFE direction: it stops
    /// a deploy and starts nothing.
    /// </summary>
    private static AssistCardCommand? CancelTheScheduledDeploy(string tidied)
    {
        var words = Words(tidied).ToList();
        if (words.Count > 0 && words[0] == "please") words.RemoveAt(0);
        if (words.Count > 0 && words[^1] == "please") words.RemoveAt(words.Count - 1);
        return string.Join(' ', words) is "cancel the scheduled deploy" or "cancel that scheduled deploy"
                                          or "cancel my scheduled deploy" or "cancel scheduled deploy"
            ? new AssistCardCommand("cancel_scheduled_deploy", new Dictionary<string, string>())
            : null;
    }

    private static AssistCardCommand? DeployAtATime(string tidied)
    {
        if (DeployFrame(tidied) is not { } frame) return null;
        if (TimeOfDay(frame.TimeWords) is not { } time) return null;
        string when = frame.DayWord is null ? time : $"{frame.DayWord} {time}";
        return new AssistCardCommand("schedule_deploy", new Dictionary<string, string> { ["when"] = when });
    }

    private static readonly string[] MeridiemEndings = { "a.m.", "p.m.", "a.m", "p.m", "am", "pm" };

    /// <summary>One or two words read as a clock, "HH:mm" on the 24-hour clock — or null.</summary>
    internal static string? TimeOfDay(IReadOnlyList<string> words)
    {
        if (words.Count is not (1 or 2)) return null;
        if (words.Count == 1)
        {
            if (words[0] == "noon") return "12:00";
            if (words[0] == "midnight") return "00:00";
        }

        string clock = words[0];
        string? meridiem = null;
        if (words.Count == 2)
        {
            if (Meridiem(words[1]) is not { } named) return null;
            meridiem = named;
        }
        else
        {
            // Longest spellings first, so "6:30a.m" does not lose only "m".
            foreach (string ending in MeridiemEndings)
            {
                if (meridiem is null && clock.EndsWith(ending, StringComparison.Ordinal))
                {
                    meridiem = Meridiem(ending);
                    clock = clock[..^ending.Length];
                }
            }
        }

        string hourText = clock;
        string minuteText = "00";
        int colon = clock.IndexOf(':');
        if (colon >= 0)
        {
            hourText = clock[..colon];
            minuteText = clock[(colon + 1)..];
        }
        else if (meridiem is null)
        {
            // "deploy at 7" — a bare number might have been a unit or a section.
            return null;
        }
        // One or two digits of hour, always: "007:30 am" is refused rather
        // than read as 07:30 (a refused row says so).
        if (!PlainDigits(hourText) || !PlainDigits(minuteText) || hourText.Length > 2 || minuteText.Length != 2)
            return null;
        int hour = int.Parse(hourText, CultureInfo.InvariantCulture);
        int minute = int.Parse(minuteText, CultureInfo.InvariantCulture);
        if (minute > 59) return null;

        if (meridiem is null)
        {
            if (hourText.Length != 2 || hour > 23) return null;
            return $"{hour:00}:{minuteText}";
        }
        if (hour is < 1 or > 12) return null;
        int onTheClock = hour;
        if (meridiem == "pm" && hour != 12) onTheClock = hour + 12;
        if (meridiem == "am" && hour == 12) onTheClock = 0;
        return string.Create(CultureInfo.InvariantCulture, $"{onTheClock:00}:{minuteText}");
    }

    private static string? Meridiem(string raw)
    {
        string folded = raw.Replace(".", "");
        return folded is "am" or "pm" ? folded : null;
    }

    /// <summary>ASCII digits only — <c>char.IsDigit</c> would accept Arabic-Indic and others.</summary>
    private static bool PlainDigits(string text) => text.Length > 0 && text.All(c => c is >= '0' and <= '9');

    // ---- Morning or evening? (#281) ------------------------------------------

    /// <summary>
    /// The question for "deploy at 6:30": morning or evening, with two sentences
    /// this family accepts — or null. Transcript only; nothing waits for the
    /// answer, because the teacher types one of the two sentences.
    /// </summary>
    public static AssistTimeQuestion? MorningOrEvening(string message)
    {
        string tidied = TidiedForTime(message);
        if (ScheduleAsDeploy(tidied) is { } asDeploy) tidied = asDeploy;   // #424
        if (DeployFrame(tidied) is { } frame && AskedOutright(frame.TimeWords, frame.DayWord) is { } question)
            return question;
        return RespellingReading(tidied, message) is { Question: { } asked } ? asked : null;
    }

    /// <summary>The one spelling to use for a time the family reads but does not set (#288), or null.</summary>
    public static AssistTimeRespelling? TimeToSayAs(string message)
    {
        string tidied = TidiedForTime(message);
        if (ScheduleAsDeploy(tidied) is { } asDeploy) tidied = asDeploy;   // #424
        return RespellingReading(tidied, message) is { Respelling: { } respelling } ? respelling : null;
    }

    /// <summary>
    /// One word, <c>H:MM</c> with a one-digit hour 1–9 (or a DOTTED hour 10–12),
    /// two digits of minutes, no meridiem; a full stop may stand for the colon
    /// and one trailing comma is dropped.
    /// </summary>
    private static AssistTimeQuestion? AskedOutright(IReadOnlyList<string> timeWords, string? dayWord)
    {
        if (timeWords.Count != 1) return null;
        string written = timeWords[0];
        if (written.EndsWith(',')) written = written[..^1];
        int separator = written.IndexOf(':');
        if (separator < 0) separator = written.IndexOf('.');
        if (separator < 0) return null;
        bool fullStop = written[separator] == '.';
        string hourText = written[..separator];
        string minuteText = written[(separator + 1)..];
        if (!PlainDigits(hourText) || !PlainDigits(minuteText) || minuteText.Length != 2) return null;
        int hour = int.Parse(hourText, CultureInfo.InvariantCulture);
        int minute = int.Parse(minuteText, CultureInfo.InvariantCulture);
        if (minute > 59) return null;
        bool oneDigit = hourText.Length == 1 && hour >= 1;
        bool dottedTenToTwelve = fullStop && hourText.Length == 2 && hour is >= 10 and <= 12;
        if (!oneDigit && !dottedTenToTwelve) return null;
        return Question(hourText + ":" + minuteText, dayWord);
    }

    private static AssistTimeQuestion Question(string clock, string? dayWord)
    {
        string opening = dayWord is null ? "deploy at " : $"deploy {dayWord} at ";
        return new AssistTimeQuestion(clock, opening + clock + " am", opening + clock + " pm");
    }

    /// <summary>A part of the day, and what it says about the hour.</summary>
    private sealed record DayPart(string[] Words, string? DayWord, string Kind)
    {
        public bool Holds(int onTheClock) => Kind switch
        {
            "morning" => onTheClock is >= 0 and <= 11,
            "afternoon" => onTheClock is >= 12 and <= 17,
            "evening" => onTheClock is >= 17 and <= 23,
            _ => onTheClock is >= 17 and <= 23 or 0,   // tonight
        };

        public int? Place(int hour) => Kind switch
        {
            "morning" => hour == 12 ? 0 : hour is >= 1 and <= 11 ? hour : null,
            "afternoon" => hour == 12 ? 12 : hour is >= 1 and <= 5 ? hour + 12 : null,
            "evening" => hour is >= 5 and <= 11 ? hour + 12 : null,
            _ => hour == 12 ? 0 : hour is >= 5 and <= 11 ? hour + 12 : null,   // tonight
        };
    }

    private static readonly DayPart[] DayParts =
    {
        new(new[] { "in", "the", "morning" }, null, "morning"),
        new(new[] { "in", "the", "afternoon" }, null, "afternoon"),
        new(new[] { "in", "the", "evening" }, null, "evening"),
        new(new[] { "this", "morning" }, "today", "morning"),
        new(new[] { "this", "afternoon" }, "today", "afternoon"),
        new(new[] { "this", "evening" }, "today", "evening"),
        new(new[] { "tonight" }, "today", "tonight"),
        new(new[] { "tomorrow", "morning" }, "tomorrow", "morning"),
        new(new[] { "tomorrow", "afternoon" }, "tomorrow", "afternoon"),
        new(new[] { "tomorrow", "evening" }, "tomorrow", "evening"),
    };

    private static bool EndsWithWords(List<string> words, string[] ending) =>
        words.Count >= ending.Length && words.Skip(words.Count - ending.Length).SequenceEqual(ending);

    /// <summary>Either the question or the spelling — one reading behind both, so a sentence is never both.</summary>
    private sealed record Reading(AssistTimeQuestion? Question, AssistTimeRespelling? Respelling);

    private static Reading? RespellingReading(string tidied, string original)
    {
        if (RespellingFrame(tidied) is not { } frame) return null;
        if (TimeOfDay(frame.TimeWords) is not null) return null;
        if (AskedOutright(frame.TimeWords, frame.DayWord) is not null) return null;

        var words = frame.TimeWords.ToList();
        bool tookOffAComma = false;

        // 1. One comma after the last word: what the frame leaves of "6:30 pm, please".
        if (words.Count > 0 && words[^1].EndsWith(','))
        {
            string without = words[^1][..^1];
            if (without.Length == 0) return null;
            words[^1] = without;
            tookOffAComma = true;
        }

        // 1b. A day word the comma kept away from the frame.
        string? frameDayWord = frame.DayWord;
        if (tookOffAComma && words.Count > 0 && words[^1] is "today" or "tomorrow")
        {
            if (frameDayWord is not null) return null;
            frameDayWord = words[^1];
            words.RemoveAt(words.Count - 1);
            if (AskedOutright(words, frameDayWord) is { } question) return new Reading(question, null);
        }

        // 2. A part of the day at the end — exact words only.
        DayPart? dayPart = null;
        foreach (var candidate in DayParts)
        {
            if (words.Count > candidate.Words.Length && EndsWithWords(words, candidate.Words))
            {
                dayPart = candidate;
                words.RemoveRange(words.Count - candidate.Words.Length, candidate.Words.Length);
                break;
            }
        }

        // 3. ...and one comma before it: "6:30 pm, tonight".
        if (dayPart is not null && words.Count > 0 && words[^1].EndsWith(','))
        {
            string without = words[^1][..^1];
            if (without.Length == 0) return null;
            words[^1] = without;
            tookOffAComma = true;
        }

        // "Today" and "tonight" agree, and "tonight" says more.
        if (dayPart?.Kind == "tonight" && frameDayWord == "today") frameDayWord = null;

        // 4. What is left is a clock, with or without am or pm.
        if (words.Count is not (1 or 2)) return null;
        string clock = words[0];
        string? meridiem = null;
        if (words.Count == 2)
        {
            if (Meridiem(words[1]) is not { } named) return null;
            meridiem = named;
        }
        else
        {
            foreach (string ending in MeridiemEndings)
            {
                if (meridiem is null && clock.EndsWith(ending, StringComparison.Ordinal))
                {
                    meridiem = Meridiem(ending);
                    clock = clock[..^ending.Length];
                }
            }
        }

        string hourText = clock;
        string minuteText = "00";
        bool writtenWithAFullStop = false;
        int separator = clock.IndexOf(':');
        if (separator < 0) separator = clock.IndexOf('.');
        if (separator >= 0)
        {
            writtenWithAFullStop = clock[separator] == '.';
            hourText = clock[..separator];
            minuteText = clock[(separator + 1)..];
        }
        else if (meridiem is null && dayPart is null)
        {
            return null;   // "deploy at 7," — nothing says it is a time
        }
        if (!PlainDigits(hourText) || !PlainDigits(minuteText) || hourText.Length > 2 || minuteText.Length != 2)
            return null;
        int hour = int.Parse(hourText, CultureInfo.InvariantCulture);
        int minute = int.Parse(minuteText, CultureInfo.InvariantCulture);
        if (minute > 59) return null;

        // 5. A REASON must be present, or the family's own refusal stands.
        if (!writtenWithAFullStop && !tookOffAComma && dayPart is null) return null;

        // 6. The day: a part of the day's day must agree with a day word said.
        string? dayWord = frameDayWord;
        if (dayPart?.DayWord is { } partDay)
        {
            if (dayWord is not null && dayWord != partDay) return null;
            dayWord = partDay;
        }

        // 7. The moment, on the 24-hour clock.
        int onTheClock = hour;
        if (meridiem is not null)
        {
            if (hour is < 1 or > 12) return null;
            if (meridiem == "pm" && hour != 12) onTheClock = hour + 12;
            if (meridiem == "am" && hour == 12) onTheClock = 0;
            if (dayPart is not null && !dayPart.Holds(onTheClock)) return null;
        }
        else if (dayPart is not null)
        {
            bool twentyFourHour = hourText.Length == 2 && (hourText.StartsWith('0') || hour >= 13);
            if (twentyFourHour)
            {
                if (hour > 23 || !dayPart.Holds(hour)) return null;
                onTheClock = hour;
            }
            else if (dayPart.Place(hour) is { } placed)
            {
                onTheClock = placed;
            }
            else
            {
                // Outside the window: a one-digit hour is the #194 question
                // after all — the day word kept only when said plainly.
                if (hourText.Length != 1 || hour < 1) return null;
                string? askingDay = dayPart.DayWord == "tomorrow" ? "tomorrow" : frameDayWord;
                return new Reading(Question(hourText + ":" + minuteText, askingDay), null);
            }
        }
        else
        {
            if (hourText.Length != 2 || hour > 23) return null;
            onTheClock = hour;
        }

        // 8. Midnight "tonight" is the start of TOMORROW: no day word for it.
        if (dayPart is not null && dayPart.Words.SequenceEqual(new[] { "tonight" }) && onTheClock < 12)
        {
            if (frameDayWord is not null) return null;
            dayWord = null;
        }

        // 9. The canonical sentence.
        int twelveHour = onTheClock % 12 == 0 ? 12 : onTheClock % 12;
        string half = onTheClock >= 12 ? "pm" : "am";
        string say = (dayWord is null ? "deploy at " : $"deploy {dayWord} at ") +
                     string.Create(CultureInfo.InvariantCulture, $"{twelveHour}:{minuteText} {half}");

        return new Reading(null, new AssistTimeRespelling(
            AsTheTeacherWroteIt(frame.WrittenWords, original), say, OnlyTheComma(tidied, say)));
    }

    private static (string? DayWord, List<string> TimeWords, List<string> WrittenWords)? RespellingFrame(string tidied)
    {
        if (DeployFrame(tidied) is { } frame) return (frame.DayWord, frame.TimeWords, frame.TimeWords);

        // A part of the day in FRONT of "at" — "deploy tonight at 6:30" — is
        // moved behind the time and read with the same frame. The frame
        // itself is not widened: the accepted rows would move.
        var words = Words(tidied.TrimEnd('?')).ToList();
        int at = words.IndexOf("at");
        if (at < 0) return null;
        var before = words.Take(at).ToList();
        var after = words.Skip(at + 1).ToList();
        foreach (var candidate in DayParts)
        {
            int length = candidate.Words.Length;
            if (before.Count <= length || !EndsWithWords(before, candidate.Words)) continue;
            bool closingPlease = after.Count > 0 && after[^1] == "please";
            if (closingPlease) after.RemoveAt(after.Count - 1);
            var rebuilt = before.Take(before.Count - length).ToList();
            rebuilt.Add("at");
            rebuilt.AddRange(after);
            rebuilt.AddRange(candidate.Words);
            if (closingPlease) rebuilt.Add("please");
            if (DeployFrame(string.Join(' ', rebuilt)) is not { } rebuiltFrame) return null;
            var written = candidate.Words.ToList();
            written.Add("at");
            written.AddRange(after);
            return (rebuiltFrame.DayWord, rebuiltFrame.TimeWords, written);
        }
        return null;
    }

    /// <summary>
    /// The teacher's own words for the time, found in the ORIGINAL message —
    /// their capitals, and "p.m." keeping the closing dot the tidier took.
    /// </summary>
    private static string AsTheTeacherWroteIt(List<string> writtenWords, string original)
    {
        string wanted = string.Join(' ', writtenWords);
        if (wanted.EndsWith(',')) wanted = wanted[..^1];
        int found = original.LastIndexOf(wanted, StringComparison.OrdinalIgnoreCase);
        if (found < 0) return wanted;
        int end = found + wanted.Length;
        if (wanted.EndsWith(".m", StringComparison.Ordinal) && end < original.Length && original[end] == '.') end++;
        return original[found..end];
    }

    /// <summary>
    /// Whether taking the commas out of the teacher's sentence sets the SAME
    /// MOMENT as the sentence handed back. Moments, never text: comparing
    /// text named "deploy it at 6:30 pm, please"'s time back as the problem.
    /// </summary>
    private static bool OnlyTheComma(string tidied, string say)
    {
        if (Matching(say) is not { ToolName: "schedule_deploy" } handedBack ||
            !handedBack.Arguments.TryGetValue("when", out string? moment)) return false;
        string withoutCommas = string.Join(' ', Words(tidied).Select(word => word.Replace(",", "")).Where(word => word.Length > 0));
        return Matching(withoutCommas) is { ToolName: "schedule_deploy" } command &&
               command.Arguments.TryGetValue("when", out string? same) && same == moment;
    }
}
